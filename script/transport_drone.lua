local shared = require("shared")
local transport_technologies = require("script/transport_technologies")

local fuel_amount_per_drone = shared.fuel_amount_per_drone
local fuel_consumption_per_meter = shared.fuel_consumption_per_meter
local drone_pollution_per_second = shared.drone_pollution_per_second

local script_data =
{
  drones = {},
  riding_players = {},
  reset_to_be_taken_again = true,
  reset_fuel_on_the_way = true
}

local fuel_fluid
local get_fuel_fluid = function()
  if fuel_fluid then
    return fuel_fluid
  end
  fuel_fluid = prototypes.recipe["fuel-depots"].products[1].name
  return fuel_fluid
end

local transport_drone = {}

transport_drone.metatable = {__index = transport_drone}

local add_drone = function(drone)
  script_data.drones[drone.index] = drone
end

local remove_drone = function(drone)
  script_data.drones[drone.index] = nil
end

local get_drone = function(index)

  local drone = script_data.drones[index]

  if not drone then
    return
  end

  if not drone.entity.valid then
    drone:clear_drone_data()
    return
  end

  return drone

end


local states =
{
  going_to_supply = 1,
  return_to_requester = 2,
  waiting_for_reorder = 3,
  delivering_fuel = 4
}

-- Base speed before any transport-drone-speed research. Lowered from the old 0.066 (~4 tiles/s) -
-- with the steering tightened up (see the drone prototype's `steering` field), a slower base speed
-- shows that off better and gives the speed tech line more room to feel like an upgrade.
local base_drone_speed = 0.035
local get_drone_speed = function(force_index)
  return (base_drone_speed * (1 + transport_technologies.get_transport_speed_bonus(force_index))) --+ (math.random() / 32)
end

-- There is exactly one drone entity prototype now. It used to be picked at random out of 50
-- otherwise-identical variations that differed only by a small render offset (plus a per-cargo
-- "special" family, e.g. transport-drone-fuel-truck-N, which no longer exists at all) - see the
-- comment in data/entities/transport_drone/transport_drone.lua for why that's gone. The name still
-- ends in "-1" because pollution/kill statistics are recorded against it by name, below.
local drone_entity_name = "transport-drone-1"


local player_leave_drone = function(player)

  local drone = script_data.riding_players[player.index]
  if not drone then return end

  script_data.riding_players[player.index] = nil
  drone.riding_player = nil
  drone:update_speed()

end

local player_enter_drone = function(player, drone)

  script_data.riding_players[player.index] = drone
  drone.riding_player = player.index
  drone:update_speed()

end


-- No longer takes the cargo name: it used to pick a matching "special" drone prototype for
-- certain cargoes (and a random variation otherwise), but there's only one drone prototype now.
transport_drone.new = function(request_depot)

  local corpse = request_depot.corpse
  if not (corpse and corpse.valid) then
    if request_depot.get_corpse then
      corpse = request_depot:get_corpse()
    end
  end
  if not (corpse and corpse.valid) then
    error("No corpse found")
  end

  local entity = request_depot.entity.surface.create_entity{name = drone_entity_name, position = corpse.position, force = request_depot.entity.force}
  if not (entity and entity.valid) then
    log("transport_drone.new: failed to create '"..drone_entity_name.."' at "..serpent.line(corpse.position))
    return
  end

  local drone =
  {
    entity = entity,
    request_depot = request_depot,
    index = tostring(entity.unit_number),
    state = 0,
    requested_count = 0,
    tick_created = game.tick
  }
  setmetatable(drone, transport_drone.metatable)
  add_drone(drone)

  --entity.ai_settings.path_resolution_modifier = 0

  return drone
end

function transport_drone:update_speed()
  local speed = get_drone_speed(self.entity.force.index)
  if self.riding_player then
    speed = speed * 1.5
  elseif self.fuel_amount then
    speed = speed * 0.6
  elseif self.held_item then
    speed = speed * 0.75
  end
  self.entity.speed = speed
end

function transport_drone:add_slow_sticker()
  self.entity.surface.create_entity{name = "drone-slowdown-sticker", position = self.entity.position, target = self.entity, force = "neutral"}
end

function transport_drone:pickup_from_supply(supply, quality, item, count)

  if not supply.entity.valid then
    self:return_to_requester()
    return
  end

  self.supply_depot = supply
  self.requested_count = count
  self.requested_item = item
  self.requested_quality = quality
  self.supply_depot:add_to_be_taken(quality, item, count)

  self:add_slow_sticker()
  self:update_speed()
  self.state = states.going_to_supply

  self:go_to_depot(self.supply_depot)

end

function transport_drone:deliver_fuel(depot, amount)

  if not depot.entity.valid then
    self:return_to_requester()
    return
  end

  self.target_depot = depot
  self.fuel_amount = amount
  self.state = states.delivering_fuel
  self.target_depot.fuel_on_the_way = (self.target_depot.fuel_on_the_way or 0) + amount

  self:add_slow_sticker()
  self:update_speed()
  self:update_sticker()

  self:go_to_depot(self.target_depot)

end

function transport_drone:retry_command()

  local distance = 1.5

  local surface = self.entity.surface
  if not surface.can_place_entity
  {
    name = self.entity.name,
    position = self.entity.position,
    build_check_type=defines.build_check_type.manual
  } then
    local position = self.entity.surface.find_non_colliding_position(self.entity.name, self.entity.position, 5, 0.25, false)
    if position then
      self.entity.teleport(position)
    end
  end

  if self.state == states.going_to_supply then
    if self.supply_depot.entity.valid then
      self:go_to_depot(self.supply_depot, distance)
    else
      self:return_to_requester()
    end
    return
  end

  if self.state == states.delivering_fuel then
    if self.target_depot.entity.valid then
      self:go_to_depot(self.target_depot, distance)
    else
      self:return_to_requester()
    end
    return
  end

  if self.state == states.waiting_for_reorder then
    self:say("Forgive me master")
    self:suicide()
    return
  end

  if self.state == states.return_to_requester then
    if self.request_depot.entity.valid then
      self:go_to_depot(self.request_depot, distance)
    else
      self:suicide()
    end
    return
  end

end

function transport_drone:process_failed_command()

  if (self.failed_command_count or 0) < 2 then
    self.failed_command_count = (self.failed_command_count or 0) + 1
    self:say("R")
    self:retry_command()
    return
  end

  self:say("F")

  if self.state == states.going_to_supply then
    self:return_to_requester()
    return
  end

  if self.state == states.delivering_fuel then
    self:return_to_requester()
    return
  end

  if self.state == states.waiting_for_reorder then
    self:say("Forgive me master")
    self:suicide()
    return
  end

  if self.state == states.return_to_requester then
    self:suicide()
    return
  end

end

local distance = util.distance
function transport_drone:distance(position)
  return distance(self.entity.position, position)
end

local min = math.min
function transport_drone:process_pickup()

  if not self.request_depot.item then
    self:return_to_requester()
    return
  end

  if self.requested_item ~= self.request_depot.item or self.requested_quality ~= self.request_depot.quality then
    self:return_to_requester()
    return
  end

  if not self.supply_depot.entity.valid then
    self:return_to_requester()
    return
  end

  local available_count = self.requested_count + self.supply_depot:get_available_item_count(self.request_depot.quality, self.request_depot.item)

  local to_take
  if not self.request_depot.circuit_limit then
    -- No circuit limit, pickup as much as we can
    to_take = min(available_count, self.request_depot:get_request_size())
  else
    -- We want to only take what we requested.
    to_take = self.requested_count
  end

  local sprite_switch = false

  if to_take > 0 then
    local temperature = self.supply_depot.get_temperature and self.supply_depot:get_temperature()
    local given_count = self.supply_depot:give_item(self.requested_quality, self.requested_item, to_take)

    if given_count > 0 then
      self.held_item = self.requested_item
      self.held_quality = self.requested_quality
      self.held_count = given_count
      self.held_temperature = temperature
      self:update_sticker()
      sprite_switch = true
    end

  end

  self:add_slow_sticker()
  self:update_speed()
  self:return_to_requester(sprite_switch)

end

function transport_drone:process_deliver_fuel()

  local delivered = false

  if self.target_depot.entity.valid then
    self.target_depot.entity.insert_fluid({name = get_fuel_fluid(), amount = self.fuel_amount})
    self:clear_reservations()
    self.fuel_amount = nil
    delivered = true
  end

  self:add_slow_sticker()
  self:update_speed()
  self:return_to_requester(delivered)

end

function transport_drone:clear_reservations()

  if self.state == states.going_to_supply then
    if self.supply_depot and self.supply_depot.entity.valid and self.requested_item then
      self.supply_depot:add_to_be_taken(self.requested_quality, self.requested_item, -self.requested_count)
      self.requested_item = nil
      self.requested_quality = nil
      self.requested_count = nil
    end
  end

  if self.state == states.delivering_fuel then
    if self.target_depot and self.target_depot.entity.valid and self.fuel_amount then
      self.target_depot.fuel_on_the_way = self.target_depot.fuel_on_the_way - self.fuel_amount
    end
  end

end

function transport_drone:return_to_requester(sprite_switch)

  self:clear_reservations()

  if not self.request_depot.entity.valid then
    self:suicide()
    return
  end

  self:update_sticker()

  self.state = states.return_to_requester


  self:go_to_depot(self.request_depot, nil, sprite_switch)

end

local valid_item_cache = {}
local is_valid_item = function(item_name)
  local bool = valid_item_cache[item_name]
  if bool ~= nil then
    return bool
  end
  valid_item_cache[item_name] = prototypes.item[item_name] ~= nil
  return valid_item_cache[item_name]
end

local valid_fluid_cache = {}
local is_valid_fluid = function(fluid_name)
  local bool = valid_fluid_cache[fluid_name]
  if bool ~= nil then
    return bool
  end
  valid_fluid_cache[fluid_name] = prototypes.fluid[fluid_name] ~= nil
  return valid_fluid_cache[fluid_name]
end

function transport_drone:update_sticker()


  if self.background_rendering then
    self.background_rendering.destroy()
    self.background_rendering = nil
  end

  if self.item_rendering then
    self.item_rendering.destroy()
    self.item_rendering = nil
  end

  if self.held_item then

    local sprite
    if is_valid_fluid(self.held_item) then
      sprite = "fluid/"..self.held_item
    elseif is_valid_item(self.held_item) then
      sprite = "item/"..self.held_item
    end

    local surface = self.entity.surface
    local offset = self.entity.prototype.sticker_box.left_top
    --local force = self.entity.force

    -- This pair (dark plate + item icon) is the big, highly legible read-at-a-glance indicator, so
    -- it stays alt-mode-only - showing it permanently is far too loud once there are a lot of
    -- drones on the road. The always-visible "what am I carrying" cue is meant to be a separate,
    -- subtler overlay sprite rendered onto the tank body instead (a tray/box render); that art
    -- doesn't exist yet, so right now a drone's cargo only reads in alt mode.
    self.background_rendering = rendering.draw_sprite
    {
      sprite = "utility/entity_info_dark_background",
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

    self.item_rendering = rendering.draw_sprite
    {
      sprite = sprite,
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {self.entity.force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

  end

  if self.fuel_amount then

    local surface = self.entity.surface
    local offset = self.entity.prototype.sticker_box.left_top

    -- Same as the held_item case above - alt-mode-only.
    self.background_rendering = rendering.draw_sprite
    {
      sprite = "utility/entity_info_dark_background",
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {self.entity.force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

    self.item_rendering = rendering.draw_sprite
    {
      sprite = "fluid/"..get_fuel_fluid(),
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {self.entity.force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

  end

end

function transport_drone:suicide()
  self:say("S")

  self:clear_drone_data()

  if self.request_depot.entity.valid then
    self.request_depot:remove_drone(self)
  end
  self.entity.force = "neutral"
  self.entity.die()
end

function transport_drone:process_return_to_requester()

  if not self.request_depot.entity.valid then
    self:suicide()
    return
  end

  if self.held_item then
    self.request_depot:take_item(self.held_quality, self.held_item, self.held_count, self.held_temperature)
    self.held_item = nil
    self.held_quality = nil
  end

  if self.fuel_amount then
    self.request_depot.entity.insert_fluid({name = get_fuel_fluid(), amount = self.fuel_amount})
    self.fuel_amount = nil
  end

  --self:update_sticker()
  self:refund_fuel()

  --if self.supply_depot then
  --  self:wait_for_reorder()
  --  return
  --end

  self:remove_from_depot()

end

local random = math.random
function transport_drone:wait_for_reorder()
  self.state = states.waiting_for_reorder
  self.entity.commandable.set_command
  {
    type = defines.command.stop,
    ticks_to_wait = random(20, 30),
    distraction = defines.distraction.none
  }
end

function transport_drone:refund_fuel()
  local age = game.tick - (self.tick_created or game.tick - 1)
  local consumption = age * self.entity.speed * fuel_consumption_per_meter

  local pollution = (age / 60) * drone_pollution_per_second
  game.get_pollution_statistics(self.entity.surface).on_flow("transport-drone-1", pollution)

  --self:say(consumption)
  self.entity.force.get_fluid_production_statistics(self.entity.surface).on_flow(get_fuel_fluid(), -consumption)
  local fuel_refund = fuel_amount_per_drone - consumption
  --self:say(fuel_refund)

  if fuel_refund > 0 then
    self.request_depot.entity.insert_fluid({name = get_fuel_fluid(), amount = fuel_refund})
  elseif fuel_refund < 0 then
    self.request_depot.entity.extract_fluid({name = get_fuel_fluid(), amount = -fuel_refund})
  end

end

function transport_drone:remove_from_depot()

  self.request_depot:remove_drone(self)
  self:clear_drone_data()
  self.entity.destroy()

end

local min = math.min
function transport_drone:update(event)
  if not self.entity.valid then return end

  if event.result ~= defines.behavior_result.success then
    self:process_failed_command()
    return
  end

  if self.failed_command_count then
    self.failed_command_count = nil
  end

  if self.state == states.going_to_supply then
    self:process_pickup()
    return
  end

  if self.state == states.delivering_fuel then
    self:process_deliver_fuel()
    return
  end

  if self.state == states.return_to_requester then
    self:process_return_to_requester()
    return
  end

end

function transport_drone:say(text)
  self.entity.surface.create_entity{name = "tutorial-flying-text", position = self.entity.position, text = text}
end

function transport_drone:go_to_position(position, radius)
  self.entity.commandable.set_command
  {
    type = defines.command.go_to_location,
    destination = position,
    radius = radius or 1,
    distraction = defines.distraction.none,
    pathfind_flags = {prefer_straight_paths = false, use_cache = false},
  }
end

function transport_drone:go_to_entity(entity, radius)
  self.entity.commandable.set_command
  {
    type = defines.command.go_to_location,
    destination_entity = entity,
    radius = radius or 1,
    distraction = defines.distraction.none,
    pathfind_flags = {prefer_straight_paths = false, use_cache = false}
  }
end

local random = math.random
local drone_path_flags = {prefer_straight_paths = true, use_cache = false, no_break = true}
local insert = table.insert

function transport_drone:go_to_depot(depot, radius, sprite_switch)
  local commands = {}
  local corpse = depot.corpse

  if not (corpse and corpse.valid) then
    if depot.get_corpse then
      corpse = depot:get_corpse()
    end
  end

  if not (corpse and corpse.valid) then
    --idk...
    self:suicide()
    return
  end
  --if sprite_switch then
  --  local proxy = self.entity.surface.create_entity
  --  {
  --    name = "sprite-switch-proxy",
  --    position = self.entity.position,
  --    force = "neutral"
  --  }
  --  insert(commands,
  --  {
  --    type = defines.command.attack,
  --    target = proxy,
  --    distraction = defines.distraction.none
  --  })
  --end

  -- This radius is what keeps drones from piling up on the exact same spot at a depot: they stop
  -- anywhere within it rather than all converging on the corpse. It replaces the old trick of
  -- drawing each drone at a small random offset (50 near-identical prototypes, see
  -- data/entities/transport_drone/transport_drone.lua) - roughly the same apparent spread as
  -- before (0.5 arrival + up to ~0.47 render offset), except the drones really are where they
  -- look like they are. Drones can only stand on road tiles, so on a narrow road this naturally
  -- becomes a queue along it rather than a blob around it.
  insert(commands,
  {
    type = defines.command.go_to_location,
    destination_entity = corpse,
    distraction = defines.distraction.none,
    radius = radius or 1,
    pathfind_flags = drone_path_flags
  })

  insert(commands,
  {
    type = defines.command.stop,
    distraction = defines.distraction.none,
    ticks_to_wait = 15
  })

  self.entity.commandable.set_command
  {
    type = defines.command.compound,
    distraction = defines.distraction.none,
    structure_type = defines.compound_command.return_last,
    commands = commands
  }

end

function transport_drone:clear_drone_data()

  self:clear_reservations()

  if self.riding_player then
    local player = game.get_player(self.riding_player)
    if player then player_leave_drone(player) end
  end

  remove_drone(self)
end

function transport_drone:handle_drone_deletion()
  if self.entity.valid then
    self:say("D")
  end

  self:clear_drone_data()

  if self.request_depot.entity.valid then
    self.request_depot:remove_drone(self, true)
  end

end

local on_ai_command_completed = function(event)
  local drone = get_drone(tostring(event.unit_number))
  if not drone then return end
  drone:update(event)
end

local on_entity_removed = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end

  local unit_number = entity.unit_number
  if not unit_number then return end

  local drone = get_drone(tostring(unit_number))
  if not drone then return end

  if event.force then
    entity.force.get_kill_count_statistics(entity.surface).on_flow("transport-drone-1", 1)
    event.force.get_kill_count_statistics(entity.surface).on_flow("transport-drone-1", -1)
  end

  drone:handle_drone_deletion()


end

local follow_drone_hotkey = function(event)
  local player = game.get_player(event.player_index)

  if script_data.riding_players[player.index] then
    player_leave_drone(player)
    return
  end

  if player.vehicle then
    --He is getting out of a vehicle.
    return
  end

  local radius = player.character and player.character.prototype.enter_vehicle_distance or 5

  if player.surface.count_entities_filtered{type = "car", force = player.force, position = player.position, radius = radius, limit = 1} > 0 then
    --There is a vehicle nearby, let him get into that.
    return
  end

  local nearby = player.surface.find_entities_filtered{type = "unit", force = player.force, position = player.position, radius = radius}

  -- get_closest takes a plain array, so the rideable ones have to be collected into a fresh
  -- densely-packed table - nil'ing entries out of `nearby` in place would leave holes in the
  -- middle of the array and silently truncate (or error on) the conversion.
  local units = {}
  local count = 0
  for k, unit in pairs (nearby) do
    local drone = get_drone(tostring(unit.unit_number))
    if drone and not drone.riding_player then
      count = count + 1
      units[count] = unit
    end
  end

  if count == 0 then return end

  local closest = player.surface.get_closest(player.position, units)
  if not closest then return end

  local drone = get_drone(tostring(closest.unit_number))
  if not drone then return end
  player_enter_drone(player, drone)

end

local floor = math.floor
local to_direction = function(orientation)
  local direction = floor(8 * (orientation + (1 / 16)))
  if direction >= 8 then direction = 0 end
  -- defines.direction has 16 values now (to support diagonal rails), so the 8 discrete
  -- compass directions are the even values: north = 0, northeast = 2, east = 4, ...
  return direction * 2
end


local get_orientation = function(source_position, target_position)

  -- Angle in rads
  local angle = util.angle(target_position, source_position)

  -- Convert to orientation
  local orientation =  (angle / (2 * math.pi)) - 0.25
  if orientation < 0 then orientation = orientation + 1 end

  return orientation

end

local smoothing = 0.20

local on_tick = function(event)
  if not next(script_data.riding_players) then return end
  local players = game.players
  for player_index, drone in pairs (script_data.riding_players) do
    local player = players[player_index]
    if not (player and player.valid) then
      -- Player no longer exists (removed from the game); drop the stale entry.
      script_data.riding_players[player_index] = nil
      drone.riding_player = nil
    elseif not (drone.entity and drone.entity.valid) or player.surface ~= drone.entity.surface then
      -- Drone died mid-ride, or the player got teleported to another surface - dismount rather
      -- than dragging them toward coordinates on the wrong surface.
      player_leave_drone(player)
    else
      local player_position = player.position
      local position = drone.entity.position
      local shift = drone.entity.prototype.sticker_box.left_top
      local target_position = {x = position.x + shift.x, y = position.y + shift.y}
      local dx, dy = (target_position.x - player_position.x) * smoothing, (target_position.y - player_position.y) * smoothing

      local final_position = {player_position.x + dx, player_position.y + dy}
      player.teleport(final_position)
      if player.character then
        --player.character.walking_state = {walking = false, direction = to_direction(drone.entity.orientation)}
        player.character.direction = to_direction(get_orientation(player_position, final_position))
      end
    end
  end
end

local on_pre_player_left_game = function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  player_leave_drone(player)
end

local on_player_removed = function(event)
  local drone = script_data.riding_players[event.player_index]
  if not drone then return end
  script_data.riding_players[event.player_index] = nil
  drone.riding_player = nil
end

-- Another mod cloning entities (e.g. Space Exploration's spaceship launches) can clone a drone
-- unit. The clone has no drone data and no command, so it would just sit on the road forever -
-- remove it. The source drone (if it gets destroyed by the cloning mod) is handled by the normal
-- on_entity_removed/on_object_destroyed paths.
local on_entity_cloned = function(event)
  local destination = event.destination
  if not (destination and destination.valid) then return end
  if destination.name ~= drone_entity_name then return end
  if get_drone(tostring(destination.unit_number)) then return end
  destination.destroy()
end

local set_map_settings = function()
  game.map_settings.path_finder.max_steps_worked_per_tick = 10000
  game.map_settings.path_finder.max_work_done_per_tick = 80000
  game.map_settings.path_finder.use_path_cache = false
end

transport_drone.events =
{
  --[defines.events.on_built_entity] = on_built_entity,
  --[defines.events.on_robot_built_entity] = on_built_entity,
  --[defines.events.script_raised_revive] = on_built_entity,
  --[defines.events.script_raised_built] = on_built_entity,

  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,

  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.script_raised_destroy] = on_entity_removed,

  [defines.events.on_ai_command_completed] = on_ai_command_completed,
  [defines.events.on_entity_cloned] = on_entity_cloned,

  [defines.events.on_pre_player_left_game] = on_pre_player_left_game,
  [defines.events.on_player_removed] = on_player_removed,

  ["follow-drone"] = follow_drone_hotkey,
  [defines.events.on_tick] = on_tick,
}

transport_drone.on_load = function()
  script_data = storage.transport_drone or script_data
  for unit_number, drone in pairs (script_data.drones) do
    setmetatable(drone, transport_drone.metatable)
  end
end

transport_drone.on_init = function()
  storage.transport_drone = storage.transport_drone or script_data
  set_map_settings()
end

transport_drone.on_configuration_changed = function()
  script_data.riding_players = script_data.riding_players or {}

  for k, drone in pairs (script_data.drones) do
    if drone.entity.valid then
      -- depot_common's on_configuration_changed wipes every depot's to_be_taken/fuel_on_the_way
      -- (they changed shape for quality support), so any reservation an in-flight drone is
      -- holding has to be re-registered here, or it's silently lost - and then subtracted again
      -- when the drone delivers, driving the depot's accounting negative.
      if drone.state == states.going_to_supply and drone.supply_depot then
        local count = drone.requested_count or 0
        local item = drone.requested_item or drone.request_depot.item
        local quality = drone.requested_quality or drone.request_depot.quality
        drone:pickup_from_supply(drone.supply_depot, quality, item, count)
      end
      if drone.state == states.delivering_fuel and drone.target_depot then
        drone.target_depot.fuel_on_the_way = (drone.target_depot.fuel_on_the_way or 0) + (drone.fuel_amount or 0)
      end
    else
      -- The entity is gone - which is the normal case for any drone that was in flight when a mod
      -- update removed its prototype (that happened wholesale when the 50 drone variations were
      -- collapsed into one, so every save upgraded across that point hits this for most of its
      -- drones).
      --
      -- Drop it from its depot's drone list as well, not just the global one. depot_common's
      -- handler has already wiped every depot's to_be_taken/fuel_on_the_way, and this drone's
      -- reservation was NOT re-registered above because its entity is invalid. If it were left in
      -- depot.drones, check_drone_validity would eventually find it and call clear_reservations,
      -- subtracting a reservation that no longer exists - leaving the supply depot with a negative
      -- to_be_taken, which then inflates get_available_item_count and has it advertise stock it
      -- hasn't got.
      local depot = drone.request_depot
      if depot and depot.drones then
        depot.drones[drone.index] = nil
      end
      script_data.drones[k] = nil
    end
  end

  set_map_settings()

end

transport_drone.get_drone = get_drone

transport_drone.get_drone_count = function()
  return table_size(script_data.drones)
end

return transport_drone
