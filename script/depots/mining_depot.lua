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

  local new_contents
  if (self.circuit_writer and self.circuit_writer.valid) then
    local behavior = self.circuit_writer.get_control_behavior()
    if behavior and behavior.disabled then
      new_contents = {}
    end
  end
  if not new_contents then
    new_contents = util.contents_to_dict(self.entity.get_output_inventory().get_contents())
  end

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

  if self.circuit_reader and self.circuit_reader.valid then
    local behavior = self.circuit_reader.get_or_create_control_behavior()
    local quality, name, count = util.first_quality_item(new_contents)
    if not name then
      quality, name, count = util.first_quality_item(util.contents_to_dict(self.entity.get_output_inventory().get_contents()))
    end
    local signal
    if name and count and count > 0 then
      signal = {signal = {type = "item", name = name, quality = quality}, count = count}
    end
    util.set_combinator_signal(behavior, 1, signal)
  end

end


function mining_depot:update()
  self:update_contents()
end

function mining_depot:say(string)
  self.entity.surface.create_entity{name = "tutorial-flying-text", position = self.entity.position, text = string}
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
  self.corpse.destroy()
end

function mining_depot:on_config_changed()
  -- Reset unconditionally: contents/to_be_taken used to be flat [name] = count tables before
  -- quality support; they're now [quality][name] = count. Rebuilt from scratch on next update().
  self.to_be_taken = {}
  self.old_contents = {}
end

return mining_depot