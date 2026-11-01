local mining_depot = {}
mining_depot.metatable = {__index = mining_depot}

mining_depot.corpse_offsets =
{
  [defines.direction.north] = {0, 4.5},
  [defines.direction.east] = {-4.5, 0},
  [defines.direction.south] = {0, -4.5},
  [defines.direction.west] = {4.5, 0},
}

local get_corpse_position = function(entity)

  local position = entity.position
  local direction = entity.direction
  local offset = mining_depot.corpse_offsets[direction]
  return {position.x + offset[1], position.y + offset[2]}

end

function mining_depot.new(entity)

  local force = entity.force
  local surface = entity.surface

  entity.disabled_by_script = true
  entity.rotatable = false


  local depot =
  {
    entity = entity,
    index = tostring(entity.unit_number),
    to_be_taken = {},
    old_contents = {}
  }
  setmetatable(depot, mining_depot.metatable)
  depot:get_corpse()

  return depot

end

function mining_depot:get_corpse()
  if self.corpse and self.corpse.valid then
    return self.corpse
  end

  local corpse_position = get_corpse_position(self.entity)
  local corpse = self.entity.surface.create_entity{name = "invisible-transport-caution-corpse", position = corpse_position}
  corpse.corpse_expires = false
  self.corpse = corpse
  self.node_position = {math.floor(corpse_position[1]), math.floor(corpse_position[2])}
  return corpse
end

function mining_depot:get_to_be_taken(quality, name)
  return util.get_quality_item(self.to_be_taken, quality, name) or 0
end

function mining_depot:update_contents()

  local supply = self.road_network.get_network_item_supply(self.network_id)
  if not supply then return end

  -- Provider-side depots (supply/mining/fluid) always offer their stock to the network - there's
  -- no circuit-disable for them any more (mirrors supply depot, which can't support it at all now
  -- it's a plain container - kept uniform across all three rather than mining/fluid being
  -- circuit-gateable just because their underlying entity happens to support it and supply
  -- doesn't). Only request/buffer depots are circuit-gateable now. Mining drills also don't
  -- support a native "read contents" equivalent (only circuit_read_resources, for the ore patch
  -- remaining underneath them), so there's nothing to replace the old reader signal with either -
  -- that's simply gone.
  local new_contents = util.contents_to_dict(self.entity.get_output_inventory().get_contents())

  util.for_each_quality_item(self.old_contents, function(quality, name, count)
    if not util.get_quality_item(new_contents, quality, name) then
      util.set_network_supply(supply, quality, name, self.index, nil)
    end
  end)

  util.for_each_quality_item(new_contents, function(quality, name, count)
    local new_count = count - self:get_to_be_taken(quality, name)
    util.set_network_supply(supply, quality, name, self.index, new_count > 0 and new_count or nil)
  end)

  self.old_contents = new_contents

end


function mining_depot:update()
  self:update_contents()
end

function mining_depot:say(string)
  util.say(self.entity, string)
end

function mining_depot:give_item(quality, requested_name, requested_count)
  local inventory = self.entity.get_output_inventory()
  local removed_count = inventory.remove({name = requested_name, count = requested_count, quality = quality})
  return removed_count
end

function mining_depot:add_to_be_taken(quality, name, count)
  util.add_quality_item(self.to_be_taken, quality, name, count)
end

function mining_depot:get_available_item_count(quality, name)
  return self.entity.get_output_inventory().get_item_count{name = name, quality = quality} - self:get_to_be_taken(quality, name)
end

function mining_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "mining")
  self:update_contents()
end

function mining_depot:remove_from_network()
  self.road_network.remove_depot(self, "mining")
  self.network_id = nil
end

function mining_depot:on_removed()
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
end

function mining_depot:on_config_changed()
  -- Reset unconditionally: contents/to_be_taken used to be flat [name] = count tables before
  -- quality support; they're now [quality][name] = count. Rebuilt from scratch on next update().
  self.to_be_taken = {}
  self.old_contents = {}
end

return mining_depot