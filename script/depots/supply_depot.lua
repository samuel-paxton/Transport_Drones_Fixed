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

function supply_depot.new(entity, tags)
  local position = entity.position
  local force = entity.force
  local surface = entity.surface
  entity.destructible = false
  entity.minable_flag = false
  entity.rotatable = false
  entity.disabled_by_script = true
  local chest = surface.create_entity{name = "supply-depot-chest", position = position, force = force, player = entity.last_user}

  local depot =
  {
    entity = chest,
    assembler = entity,
    to_be_taken = {},
    index = tostring(chest.unit_number),
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

  local corpse_position = get_corpse_position(self.assembler)
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

end

--[[

had iron 10
now iron 5
]]

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

  if self.assembler.valid then
    self.assembler.destructible = true
    if event.name == defines.events.on_entity_died then
      self.assembler.die()
    else
      self.assembler.destroy()
    end
  end

  if self.entity.valid then
    self.entity.destroy()
  end
end

function supply_depot:on_config_changed()
  -- Reset unconditionally: contents/to_be_taken used to be flat [name] = count tables before
  -- quality support; they're now [quality][name] = count. Rebuilt from scratch on next update().
  self.to_be_taken = {}
  self.old_contents = {}
end

return supply_depot