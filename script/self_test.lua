-- Dev-only smoke test: builds a small but complete road network (fuel depot, supply/request
-- item pair, supply/request fluid pair, buffer depot, circuit reader/writer) with real
-- resources and drone items in it, then checks over time that nothing errors and that goods
-- actually get delivered end to end.
--
-- Not wired into the mod by default - it builds entities on a running save, so it must only run
-- against a disposable test map. To use it: uncomment the `require` for this file in control.lua,
-- then run e.g. `factorio.exe --create test.zip` followed by
-- `factorio.exe --benchmark test.zip --benchmark-ticks 6000` and check the log for
-- "SELF_TEST_RESULT". Re-comment it out again afterwards.
local self_test = {}

local fuel_fluid = "petroleum-gas"
local test_fluid = "water"

local build = function(surface, force, name, position, direction)
  local ent = surface.create_entity{name = name, position = position, direction = direction, force = force, raise_built = true}
  if not ent or not ent.valid then error("failed to build " .. name) end
  return ent
end

local find_near = function(surface, name, position)
  local list = surface.find_entities_filtered{name = name, position = position, radius = 4}
  return list[1]
end

-- A depot's dispatch capacity is driven by how many "transport-drone" items are sitting in its
-- crafter_input inventory (normally placed there by hand, or via blueprint tags).
local give_drones = function(entity, count)
  entity.get_inventory(defines.inventory.crafter_input).insert{name = "transport-drone", count = count}
end

local setup = function()
  local surface = game.surfaces["nauvis"]
  surface.request_to_generate_chunks({0, 0}, 3)
  surface.force_generate_chunk_requests()

  local force = game.forces.player
  force.research_all_technologies()

  -- Long road strip connecting everything, plus perpendicular stubs so every depot's
  -- corpse-hidden-tile actually lands on a road node.
  local tiles = {}
  for x = -20, 20 do
    table.insert(tiles, {name = "transport-drone-road", position = {x, 0}})
  end
  for _, x in pairs({-16, -8, 0, 8, 16}) do
    for y = -3, 3 do
      table.insert(tiles, {name = "transport-drone-road", position = {x, y}})
    end
  end
  surface.set_tiles(tiles, true, "abort_on_collision", false, true)

  -- Fuel depot: the network's fuel source. Everything else needs this to ever dispatch a drone.
  -- It dispatches its own "fuel truck" drones (push model), so it needs drone items too.
  local fuel_depot = build(surface, force, "fuel-depot", {-16, -6}, defines.direction.south)
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 100000}
  give_drones(fuel_depot, 10)

  -- Item supply <-> request pair.
  local supply = build(surface, force, "supply-depot", {-8, -3}, defines.direction.south)
  local supply_chest = find_near(surface, "supply-depot-chest", supply.position)
  if not supply_chest then error("supply-depot-chest not found near supply depot") end
  supply_chest.insert{name = "iron-plate", count = 4000}

  local request = build(surface, force, "request-depot", {-8, 3}, defines.direction.north)
  request.set_recipe("request-iron-plate")
  give_drones(request, 10)

  -- Fluid supply <-> request pair.
  local fluid_supply = build(surface, force, "fluid-depot", {0, -3}, defines.direction.south)
  fluid_supply.insert_fluid{name = test_fluid, amount = 100000}

  local fluid_request = build(surface, force, "request-depot", {0, 3}, defines.direction.north)
  fluid_request.set_recipe("request-" .. test_fluid)
  give_drones(fluid_request, 10)

  -- Buffer depot requesting the same item, to exercise that code path too.
  local buffer = build(surface, force, "buffer-depot", {8, -3}, defines.direction.south)
  buffer.set_recipe("request-iron-plate")
  give_drones(buffer, 10)

  -- Circuit reader/writer + road network reader, just to make sure they build and update without error.
  build(surface, force, "road-network-reader", {16, 0}, defines.direction.north)
  build(surface, force, "transport-depot-writer", {16, 2}, defines.direction.north)
  build(surface, force, "transport-depot-reader", {16, 4}, defines.direction.north)

  log("SELF_TEST: setup complete")

  return {
    request = request,
    fluid_request = fluid_request,
    buffer = buffer,
  }
end

local refs
local setup_ok = false

local snapshot = function()
  return {
    item = refs.request.get_output_inventory().get_item_count("iron-plate"),
    fluid = refs.fluid_request.get_fluid_count(test_fluid),
    buffer = refs.buffer.get_output_inventory().get_item_count("iron-plate"),
  }
end

local report_progress = function()
  if not (refs and refs.request and refs.request.valid) then return end
  local s = snapshot()
  log(string.format("SELF_TEST_PROGRESS tick=%d item_delivered=%d fluid_delivered=%.1f buffer_delivered=%d",
    game.tick, s.item, s.fluid, s.buffer))
end

local tick_handler = function(event)
  local tick = event.tick

  if tick == 60 then
    local ok, err = pcall(setup)
    setup_ok = ok
    if ok then
      refs = err
    else
      log("SELF_TEST_RESULT: SETUP_FAIL - " .. tostring(err))
      game.print("SELF_TEST_RESULT: SETUP_FAIL - " .. tostring(err))
    end
    return
  end

  if not setup_ok then return end

  if tick % 1200 == 0 then
    local ok, err = pcall(report_progress)
    if not ok then
      log("SELF_TEST_RESULT: PROGRESS_CHECK_FAIL - " .. tostring(err))
      game.print("SELF_TEST_RESULT: PROGRESS_CHECK_FAIL - " .. tostring(err))
    end
  end

  if tick == 6000 then
    local s = snapshot()
    local msg = string.format("item=%d fluid=%.1f buffer=%d", s.item, s.fluid, s.buffer)
    if s.item > 0 and s.fluid > 0 and s.buffer > 0 then
      log("SELF_TEST_RESULT: PASS - " .. msg)
      game.print("SELF_TEST_RESULT: PASS - " .. msg)
    else
      log("SELF_TEST_RESULT: FAIL - nothing was delivered - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - nothing was delivered - " .. msg)
    end
  end
end

self_test.events =
{
  [defines.events.on_tick] = tick_handler
}

return self_test
