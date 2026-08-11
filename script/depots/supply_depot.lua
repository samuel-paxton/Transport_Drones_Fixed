local supply_depot = {}

supply_depot.metatable = {__index = supply_depot}

supply_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

local get_corpse_position = function(entity)

  local position = entity.position
  local direction = entity.direction
  local offset = supply_depot.corpse_offsets[direction]
  return {position.x + offset[1], position.y + offset[2]}

end

-- Supply depot used to be two overlapping entities (an inert assembling-machine placeholder for
-- visuals/circuit, plus a "supply-depot-chest" container underneath doing the actual storage) -
-- containers now support custom pictures/circuit connectors directly, so it's just the one real
-- entity. That also means it can no longer be circuit-disabled - plain containers don't support
-- circuit_condition/enable-disable at all, only reading contents - so a supply depot always
-- offers its stock to the network; only request/buffer depots are circuit-gateable now.
function supply_depot.new(entity, tags)

  entity.rotatable = false

  local depot =
  {
    entity = entity,
    to_be_taken = {},
    index = tostring(entity.unit_number),
    old_contents = {}
  }
  setmetatable(depot, supply_depot.metatable)

  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

function supply_depot:get_corpse()
  if self.corpse and self.corpse.valid then
    return self.corpse
  end

  local corpse_position = get_corpse_position(self.entity)
  local corpse = self.entity.surface.create_entity{name = "transport-caution-corpse", position = corpse_position}
  corpse.corpse_expires = false
  self.corpse = corpse
  self.node_position = {math.floor(corpse_position[1]), math.floor(corpse_position[2])}
  return corpse
end

function supply_depot:read_tags(tags)
  if tags then
    if tags.transport_depot_tags then
      local bar = tags.transport_depot_tags.bar
      if bar then
        self.entity.get_output_inventory().set_bar(bar)
      end
    end
  end
end

function supply_depot:save_to_blueprint_tags()
  return
  {
    bar = self.entity.get_output_inventory().get_bar()
  }
end

function supply_depot:get_to_be_taken(quality, name)
  return util.get_quality_item(self.to_be_taken, quality, name) or 0
end

function supply_depot:update_contents()
  local supply = self.road_network.get_network_item_supply(self.network_id)

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

function supply_depot:update()
  self:update_contents()

end

function supply_depot:say(string)
  self.entity.surface.create_entity{name = "tutorial-flying-text", position = self.entity.position, text = string}
end

function supply_depot:give_item(quality, requested_name, requested_count)
  local inventory = self.entity.get_output_inventory()
  local removed_count = inventory.remove({name = requested_name, count = requested_count, quality = quality})
  return removed_count
end

function supply_depot:add_to_be_taken(quality, name, count)
  util.add_quality_item(self.to_be_taken, quality, name, count)
end

function supply_depot:get_available_item_count(quality, name)
  return self.entity.get_output_inventory().get_item_count{name = name, quality = quality} - self:get_to_be_taken(quality, name)
end

function supply_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "supply")
  self:update_contents()
end

function supply_depot:remove_from_network()
  self.road_network.remove_depot(self, "supply")
  self.network_id = nil
end

function supply_depot:on_removed(event)
  self.corpse.destroy()
end

function supply_depot:on_config_changed()
  -- Reset unconditionally: contents/to_be_taken used to be flat [name] = count tables before
  -- quality support; they're now [quality][name] = count. Rebuilt from scratch on next update().
  self.to_be_taken = {}
  self.old_contents = {}
end

return supply_depot
