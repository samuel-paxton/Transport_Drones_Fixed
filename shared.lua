--Shared data interface between data and script, notably prototype names.

local data = {}

data.drone_collision_mask = {layers = {}} -- overwritten in data-final-fixes.lua
--data.drone_collision_mask = {layers = {ground_tile = true, water_tile = true}, not_colliding_with_itself = true, colliding_with_tiles_only = true}
--data.drone_collision_mask = {layers = {ground_tile = true, water_tile = true}}
-- variation_count/special_variation_count used to live here: the drone came in 50 near-identical
-- variations (plus per-cargo "special" families). There's one drone prototype now - see
-- data/entities/transport_drone/transport_drone.lua.
data.transport_speed_technology = "transport-drone-speed"
data.transport_capacity_technology = "transport-drone-capacity"
data.transport_system_technology = "transport-system"

data.fuel_amount_per_drone = settings.startup["fuel-amount-per-drone"].value
data.fuel_consumption_per_meter = settings.startup["fuel-consumption-per-meter"].value
data.drone_fluid_capacity = settings.startup["drone-fluid-capacity"].value
data.drone_pollution_per_second = settings.startup["drone-pollution-per-second"].value

return data
