local fluid_depot = {}

fluid_depot.metatable = {__index = fluid_depot}
fluid_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

local get_corpse_position = function(entity)

  local position = entity.position
  local direction = entity.direction
  local offset = fluid_depot.corpse_offsets[direction]
  return {position.x + offset[1], position.y + offset[2]}

end

function fluid_depot.new(entity)

  local force = entity.force
  local surface = entity.surface

  --entity.active = false
  entity.rotatable = false

  local depot =
  {
    entity = entity,
    to_be_taken = {},
    index = tostring(entity.unit_number),
    old_contents = {}
  }
  setmetatable(depot, fluid_depot.metatable)
  depot:get_corpse()

  return depot

end

function fluid_depot:get_corpse()
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

-- Fluids don't have quality, so this always publishes/reads under the "normal" bucket of the
-- shared (otherwise quality-indexed) network.item_supply table - transport_drone.lua and the
-- request/buffer depots don't need to know or care that a given supply depot happens to be a
-- fluid one, they just always pass a quality through uniformly.
function fluid_depot:get_to_be_taken(name)
  return util.get_quality_item(self.to_be_taken, util.normal_quality, name) or 0
end

function fluid_depot:get_output_fluidbox()
  local ok, has_segment = pcall(self.entity.has_fluid_segment, 1)
  if not (ok and has_segment) then return end
  local ok2, fluid = pcall(self.entity.get_fluid_segment_fluid, 1)
  if not ok2 then return end
  return fluid
end

function fluid_depot:get_temperature()
  local box = self:get_output_fluidbox()
  return box and box.temperature
end

function fluid_depot:set_output_fluidbox(box)
  util.set_fluid_box_content(self.entity, 1, box)
end


function fluid_depot:update_contents()

  local supply = self.road_network.get_network_item_supply(self.network_id)

  local new_contents = {}


  local enabled = true
  if (self.circuit_writer and self.circuit_writer.valid) then
    local behavior = self.circuit_writer.get_control_behavior()
    if behavior and behavior.disabled then
      enabled = false
    end
  end

  if enabled then
    local box = self:get_output_fluidbox()
    if box then
      new_contents[box.name] = box.amount
    end
  end

  for name, count in pairs (self.old_contents) do
    if not new_contents[name] then
      util.set_network_supply(supply, util.normal_quality, name, self.index, nil)
    end
  end

  for name, count in pairs (new_contents) do
    local new_count = count - self:get_to_be_taken(name)
    util.set_network_supply(supply, util.normal_quality, name, self.index, new_count > 0 and new_count or nil)
  end

  self.old_contents = new_contents

  if self.circuit_reader and self.circuit_reader.valid then
    local behavior = self.circuit_reader.get_or_create_control_behavior()
    local name, count = next(new_contents)
    if not name then
      local box = self:get_output_fluidbox()
      if box then
        name = box.name
        count = box.amount
      end
    end
    local signal
    if name and count and count > 0 then
      signal = {signal = {type = "fluid", name = name, quality = util.normal_quality}, count = count}
    end
    util.set_combinator_signal(behavior, 1, signal)
  end

end

function fluid_depot:update()
  if not self.network_id then return end

  local box = self:get_output_fluidbox()
  if not box then
    if not self.entity.active then
      self.entity.disabled_by_script = false
      self.entity.crafting_progress = 0
    end
    return
  end

  if self.entity.active then
    self.entity.disabled_by_script = true
  end

  self:update_contents()
  --self:say("U")

end

function fluid_depot:say(string)
  self.entity.surface.create_entity{name = "tutorial-flying-text", position = self.entity.position, text = string}
end

-- quality is accepted-and-ignored on all three of these: transport_drone.lua and the
-- request/buffer depots call supply depots generically without knowing whether they're item or
-- fluid based, and fluids don't have quality (always effectively normal).
function fluid_depot:give_item(quality, requested_name, requested_count)
  return self.entity.extract_fluid{name = requested_name, amount = requested_count}
end

function fluid_depot:add_to_be_taken(quality, name, count)
  util.add_quality_item(self.to_be_taken, util.normal_quality, name, count)
end

function fluid_depot:get_available_item_count(quality, name)
  return self.entity.get_fluid_count(name) - self:get_to_be_taken(name)
end

function fluid_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "fluid")
  self:update_contents()
end

function fluid_depot:remove_from_network()
  self.road_network.remove_depot(self, "fluid")
  self.network_id = nil
end

function fluid_depot:on_removed()
  self.corpse.destroy()
end

function fluid_depot:on_config_changed()
  self.to_be_taken = {}
  self.old_contents = {}
end

return fluid_depot