-- Tips and tricks simulations, one per tip. These replace the static screenshots the tips used to
-- show: each one builds a small but real road network on the simulation surface and then just lets
-- the mod's own control.lua run it, so what the player watches is the actual mod doing the actual
-- thing rather than a picture of it.
--
-- Everything shares the `prelude` below. The geometry rule the layouts are written against: depots
-- are odd-sized, so `build(name, x, y, direction)` centres one on tile (x, y), and the caution
-- plate that hooks it into the road network then lands a fixed distance away in the direction it
-- faces - 2 tiles for the 3x3 depots and the network reader, 3 for the 5x5 fuel depot. So a
-- south-facing depot built on tile (x, y) needs a road tile at (x, y + 2), and its own 3x3
-- footprint must stay clear of road tiles: data-final-fixes puts the road collision layer on every
-- player entity, so a depot overlapping a road refuses to build at all.
--
-- The visible area is 1408x704 pixels at 32 pixels per tile, divided by the camera zoom - so 22x11
-- tiles at the default zoom of 2, 29x15 at 1.5, 31x16 at 1.4. The engine only lays checkerboard
-- from (-20, -15) to (20, 15), which is why nothing here zooms out past about 1.4.

local prelude =
[[
local surface = game.surfaces[1]
local force = game.forces.player
local north, east, south, west = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local fuel_fluid = prototypes.recipe["fuel-depots"].products[1].name

-- An unresearched drone crawls at about 2 tiles a second, which over the few seconds a tip is on
-- screen reads as "nothing is happening". Four levels of the speed line is an ordinary mid-game
-- state and nearly doubles that, which is enough for a whole delivery to play out while watching.
for level = 1, 4 do
  local technology = force.technologies["transport-drone-speed-" .. level]
  if technology then technology.researched = true end
end

local road = function(x1, y1, x2, y2, tile_name)
  local tiles = {}
  for x = x1, x2 do
    for y = y1, y2 do
      tiles[#tiles + 1] = {name = tile_name or "transport-drone-road", position = {x, y}}
    end
  end
  -- The trailing true raises script_raised_set_tiles, which is what makes road_network.lua
  -- register these tiles as network nodes rather than leaving them as decoration.
  surface.set_tiles(tiles, true, "abort_on_collision", false, true)
end

-- Centres a depot on tile (x, y). raise_built is what registers it with depot_common.
local build = function(name, x, y, direction)
  local entity = surface.create_entity
  {
    name = name,
    position = {x + 0.5, y + 0.5},
    direction = direction,
    force = force,
    raise_built = true,
    create_build_effect_smoke = false
  }
  if not entity then error("Transport drones tip simulation could not build a " .. name) end
  return entity
end

-- How many drones a depot may have out at once is simply how many drone items are sitting in its
-- input inventory, exactly as if a player had put them there by hand.
local add_drones = function(entity, count)
  entity.get_inventory(defines.inventory.crafter_input).insert{name = "transport-drone", count = count}
end

-- Fluid box 1 of a request or buffer depot is its fuel tank. A depot normally fills that by asking
-- a fuel depot for a delivery, which costs a drone round trip; priming it means the simulation is
-- already moving cargo on the first frame instead of spending its opening seconds fetching fuel.
-- Every layout still builds a real fuel depot, so once this initial charge is burnt through the
-- network keeps itself running the honest way.
local prime_fuel = function(entity)
  entity.add_fluid(1, {name = fuel_fluid, amount = 400})
end

local restock = function(entity, item, target)
  local missing = target - entity.get_item_count(item)
  if missing > 0 then entity.insert{name = item, count = missing} end
end

-- A request depot stops dispatching the moment it is full, so without something eating what it
-- receives every one of these layouts goes quiet a few seconds after it opens. Taking a drone load
-- back out every second is what a factory consuming the goods would do, and it keeps drones on the
-- road for as long as the tip is on screen.
local consume = function(entity, item, count)
  entity.get_output_inventory().remove{name = item, count = count}
end

local consume_fluid = function(entity, amount)
  entity.remove_fluid(2, amount)
end
]]

local simulations = {}

local make = function(body, options)
  local simulation = options or {}
  simulation.init = prelude .. body
  -- Not optional. A simulation runs with NO mod runtime scripts loaded unless it names them here
  -- (LuaContext skips every mod whose name is missing from this list), and every layout below is
  -- nothing but a pile of inert entities without this mod's control.lua to register the depots and
  -- drive the drones. The base game's own simulations never need this because they only ever use
  -- entities the engine already knows how to run.
  simulation.mods = {"Transport_Drones_Fixed"}
  return simulation
end

-- The whole system at a glance: fuel in at one end, a stocked supply depot, and two request depots
-- pulling different items out of the same road.
simulations.overview = make(
[[
game.simulation.camera_position = {0, -0.5}
game.simulation.camera_zoom = 1.5
game.simulation.camera_alt_info = true

road(-18, -1, 18, 1)

local fuel_depot = build("fuel-depot", -11, -4, south)
add_drones(fuel_depot, 6)

local supply = build("supply-depot", -3, -3, south)

local iron = build("request-depot", 4, 3, north)
iron.set_recipe("request-iron-plate")
add_drones(iron, 4)
prime_fuel(iron)

local copper = build("request-depot", 11, 3, north)
copper.set_recipe("request-copper-plate")
add_drones(copper, 4)
prime_fuel(copper)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  restock(supply, "iron-plate", 2000)
  restock(supply, "copper-plate", 2000)
  consume(iron, "iron-plate", 100)
  consume(copper, "copper-plate", 100)
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 300})

-- The road itself is the subject here, so the layout is a shape rather than a line: one main road
-- with a branch off it, every depot on it part of the same network no matter which arm it sits on.
simulations.road_network = make(
[[
game.simulation.camera_position = {0, 1}
game.simulation.camera_zoom = 1.4
game.simulation.camera_alt_info = true

road(-20, -1, 20, 1)
road(4, 1, 6, 5)

local fuel_depot = build("fuel-depot", -12, -4, south)
add_drones(fuel_depot, 6)

local supply = build("supply-depot", -5, -3, south)

local far = build("request-depot", 12, 3, north)
far.set_recipe("request-iron-plate")
add_drones(far, 4)
prime_fuel(far)

-- Down the branch: a different arm of the same road, so it draws from the same supply depot.
local branch = build("request-depot", 5, 7, north)
branch.set_recipe("request-copper-plate")
add_drones(branch, 4)
prime_fuel(branch)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  restock(supply, "iron-plate", 2000)
  restock(supply, "copper-plate", 2000)
  consume(far, "iron-plate", 100)
  consume(branch, "copper-plate", 100)
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 300})

-- Close up on the drones themselves. The fuel depot is deliberately off the left edge at this zoom:
-- it has to exist for the network to work, but it isn't what this tip is about.
simulations.drones = make(
[[
game.simulation.camera_position = {0, 0}
game.simulation.camera_zoom = 2

road(-18, -1, 18, 1)

local fuel_depot = build("fuel-depot", -14, -4, south)
add_drones(fuel_depot, 6)

local supply = build("supply-depot", -6, -3, south)

local request = build("request-depot", 6, 3, north)
request.set_recipe("request-iron-plate")
add_drones(request, 6)
prime_fuel(request)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  restock(supply, "iron-plate", 2000)
  consume(request, "iron-plate", 150)
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 300})

-- One of each kind of depot on a single road, so the caution plates the tip talks about all line up
-- in a row along it. Alt info is on because half of what distinguishes these entities is what they
-- are holding or asking for.
simulations.depots = make(
[[
game.simulation.camera_position = {0, -0.5}
game.simulation.camera_zoom = 1.5
game.simulation.camera_alt_info = true

road(-18, -1, 18, 1)

local fuel_depot = build("fuel-depot", -12, -4, south)
add_drones(fuel_depot, 6)

local supply = build("supply-depot", -6, -3, south)
local fluid = build("fluid-depot", -1, -3, south)

local request = build("request-depot", 5, 3, north)
request.set_recipe("request-water")
add_drones(request, 4)
prime_fuel(request)

local buffer = build("buffer-depot", 11, 3, north)
buffer.set_recipe("request-iron-plate")
add_drones(buffer, 4)
prime_fuel(buffer)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  fluid.insert_fluid{name = "water", amount = 2000}
  restock(supply, "iron-plate", 2000)
  consume_fluid(request, 500)
  consume(buffer, "iron-plate", 100)
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 300})

-- Fuel is the one thing that has to be piped in by hand, so this layout gives the fuel depot a pipe
-- run heading off the top of the frame, and keeps two request depots hungry enough that fuel drones
-- are always out on the road.
simulations.fuel_depots = make(
[[
game.simulation.camera_position = {0, -2.5}
game.simulation.camera_zoom = 1.6
game.simulation.camera_alt_info = true

road(-18, -1, 18, 1)

local fuel_depot = build("fuel-depot", 0, -4, south)
add_drones(fuel_depot, 8)

-- The depot's intake connection ends up on its far side from the caution plate, so the supply runs
-- away from the road and off the top of the view - the player's refinery is somewhere up there.
local pipes = {}
for y = -7, -10, -1 do
  pipes[#pipes + 1] = surface.create_entity{name = "pipe", position = {0.5, y + 0.5}, force = force, create_build_effect_smoke = false}
end

local supply = build("supply-depot", 0, 3, north)

local left = build("request-depot", -8, 3, north)
left.set_recipe("request-iron-plate")
add_drones(left, 4)

local right = build("request-depot", 8, 3, north)
right.set_recipe("request-copper-plate")
add_drones(right, 4)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  for _, pipe in pairs (pipes) do
    pipe.insert_fluid{name = fuel_fluid, amount = 100}
  end
  restock(supply, "iron-plate", 2000)
  restock(supply, "copper-plate", 2000)
  consume(left, "iron-plate", 100)
  consume(right, "copper-plate", 100)
  -- Burn off the request depots' fuel faster than their own deliveries would, so they are always
  -- asking for more and the fuel drones this tip is about are always out on the road.
  left.extract_fluid{name = fuel_fluid, amount = 60}
  right.extract_fluid{name = fuel_fluid, amount = 60}
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 600})

-- Two request depots asking for different things, with visibly different numbers of drones in them,
-- since drone count is what sets how much a request depot asks for.
simulations.request_depots = make(
[[
game.simulation.camera_position = {0, -0.5}
game.simulation.camera_zoom = 1.6
game.simulation.camera_alt_info = true

road(-18, -1, 18, 1)

local fuel_depot = build("fuel-depot", -12, -4, south)
add_drones(fuel_depot, 6)

local supply = build("supply-depot", -5, -3, south)

local busy = build("request-depot", 3, 3, north)
busy.set_recipe("request-iron-plate")
add_drones(busy, 6)
prime_fuel(busy)

local quiet = build("request-depot", 10, 3, north)
quiet.set_recipe("request-copper-plate")
add_drones(quiet, 2)
prime_fuel(quiet)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  restock(supply, "iron-plate", 2000)
  restock(supply, "copper-plate", 2000)
  consume(busy, "iron-plate", 150)
  consume(quiet, "copper-plate", 50)
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 300})

-- Supply depots are passive, so the thing worth showing is that they never dispatch anything: every
-- drone on this road belongs to one of the request depots opposite. The fluid depot is here because
-- it plays exactly the same passive role for fluids.
simulations.supply_depots = make(
[[
game.simulation.camera_position = {-1, -0.5}
game.simulation.camera_zoom = 1.6
game.simulation.camera_alt_info = true

road(-18, -1, 18, 1)

local fuel_depot = build("fuel-depot", -12, -4, south)
add_drones(fuel_depot, 6)

local supply = build("supply-depot", -5, -3, south)
local fluid = build("fluid-depot", 2, -3, south)

local iron = build("request-depot", -5, 3, north)
iron.set_recipe("request-iron-plate")
add_drones(iron, 4)
prime_fuel(iron)

local water = build("request-depot", 2, 3, north)
water.set_recipe("request-water")
add_drones(water, 4)
prime_fuel(water)

local copper = build("request-depot", 9, 3, north)
copper.set_recipe("request-copper-plate")
add_drones(copper, 4)
prime_fuel(copper)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  fluid.insert_fluid{name = "water", amount = 2000}
  restock(supply, "iron-plate", 2000)
  restock(supply, "copper-plate", 2000)
  consume(iron, "iron-plate", 100)
  consume(copper, "copper-plate", 100)
  consume_fluid(water, 500)
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 300})

-- The outpost case from the tip text: ore comes in from a supply depot right at the edge of the
-- view over a long haul, and three request depots with two drones each take short hops off the
-- buffer instead of making that trip themselves.
simulations.buffer_depots = make(
[[
game.simulation.camera_position = {-1, -0.5}
game.simulation.camera_zoom = 1.4
game.simulation.camera_alt_info = true

road(-20, -1, 20, 1)

local supply = build("supply-depot", -15, -3, south)

local fuel_depot = build("fuel-depot", -8, -4, south)
add_drones(fuel_depot, 8)

local buffer = build("buffer-depot", 2, -3, south)
buffer.set_recipe("request-iron-ore")
add_drones(buffer, 10)
prime_fuel(buffer)

local requesters = {}
for _, x in pairs {-3, 5, 10} do
  local requester = build("request-depot", x, 3, north)
  requester.set_recipe("request-iron-ore")
  add_drones(requester, 2)
  prime_fuel(requester)
  requesters[#requesters + 1] = requester
end

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  restock(supply, "iron-ore", 4000)
  for _, requester in pairs (requesters) do
    consume(requester, "iron-ore", 50)
  end
end
cycle()
script.on_nth_tick(60, cycle)
]],
{init_update_count = 600})

-- The reader only means anything if its number moves, so the supply depot's stock is walked up and
-- down a fixed ladder and alt info is left on to show the signal it is putting out.
simulations.network_reader = make(
[[
game.simulation.camera_position = {0, -0.5}
game.simulation.camera_zoom = 1.8
game.simulation.camera_alt_info = true

road(-18, -1, 18, 1)

local fuel_depot = build("fuel-depot", -10, -4, south)
add_drones(fuel_depot, 6)

local supply = build("supply-depot", -3, -3, south)

local reader = build("road-network-reader", 3, -2, north)
local behavior = reader.get_or_create_control_behavior()
local section = behavior.get_section(1) or behavior.add_section()
section.set_slot(1, {value = {type = "item", name = "iron-plate", quality = "normal"}, min = 0})

local request = build("request-depot", 8, 3, north)
request.set_recipe("request-iron-plate")
add_drones(request, 4)
prime_fuel(request)

local cycle = function()
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 2000}
  consume(request, "iron-plate", 100)
end
cycle()
script.on_nth_tick(60, cycle)

-- Walk the network's stock up and back down a fixed ladder, slowly enough to read, so the count the
-- reader is putting out visibly moves instead of settling wherever the requests happen to leave it.
local ladder = {800, 1600, 2400, 3200, 2400, 1600}
local step = 0
local restock_supply = function()
  step = (step % #ladder) + 1
  supply.clear_items_inside()
  supply.insert{name = "iron-plate", count = ladder[step]}
end
restock_supply()
script.on_nth_tick(240, restock_supply)
]],
{init_update_count = 300})

return simulations
