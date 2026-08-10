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
local gui = require("script/gui")
local depot_common = require("script/depot_common")

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

-- Copies everything built so far into a blueprint and writes transport_depot_tags onto it the
-- same way on_player_setup_blueprint would (the write side), then checks a captured tag reads
-- back correctly into a freshly-built depot as an item-request-proxy (the read side, via
-- depot_lib:read_tags()). The read side is driven by raising script_raised_built directly with
-- a synthetic tags payload - the same event/shape a construction robot reviving a tagged ghost
-- would produce - rather than via LuaItemStack::build_blueprint, since that places real entities
-- straight away (not ghosts) and it's unclear whether/how blueprint entity tags carry over on
-- that particular path; script_raised_built is the actual, documented, script-facing hook this
-- mod's own on_built_entity/on_robot_built_entity/script_raised_built/script_raised_revive
-- handler already treats identically.
local check_blueprint_tags = function(player, surface, force)
  local cursor = player.cursor_stack
  cursor.set_stack{name = "blueprint", count = 1}

  local capture_area = {{-20, -8}, {20, 8}}
  cursor.create_blueprint{surface = surface, force = force, area = capture_area, always_include_tiles = false}

  local entities = cursor.get_blueprint_entities()
  if not (entities and next(entities)) then
    error("blueprint capture got no entities")
  end

  -- on_player_setup_blueprint only ever reads event.player_index, and can't be raised through
  -- script.raise_event, so call the handler directly.
  depot_common.on_player_setup_blueprint({player_index = player.index})

  local tagged_count = 0
  local fuel_depot_tag
  for index, blueprint_entity in pairs(entities) do
    local tag = cursor.get_blueprint_entity_tag(index, "transport_depot_tags")
    if tag then
      tagged_count = tagged_count + 1
      log("SELF_TEST: blueprint tag on " .. blueprint_entity.name .. " = " .. serpent.line(tag))
      if blueprint_entity.name == "fuel-depot" then
        fuel_depot_tag = tag
      end
    end
  end

  if tagged_count == 0 then
    error("no depot got a transport_depot_tags blueprint tag")
  end
  if not fuel_depot_tag then
    error("fuel-depot didn't get a transport_depot_tags blueprint tag")
  end
  cursor.clear()

  -- Read side: build a fresh fuel depot (not network-connected - that's not what's being tested
  -- here) and raise script_raised_built with the captured tag, exactly as a robot reviving a
  -- tagged ghost would. read_tags() should turn drone_count into an item-request-proxy.
  local paste_position = {0, 40}
  surface.request_to_generate_chunks(paste_position, 3)
  surface.force_generate_chunk_requests()

  local fresh = surface.create_entity{name = "fuel-depot", position = paste_position, direction = defines.direction.south, force = force, raise_built = false}
  if not (fresh and fresh.valid) then
    error("failed to build fresh fuel-depot for the tag read-back check")
  end

  script.raise_event(defines.events.script_raised_built, {entity = fresh, tags = {transport_depot_tags = fuel_depot_tag}, tick = game.tick})

  local proxies = surface.find_entities_filtered{name = "item-request-proxy", position = paste_position, radius = 2}
  log("SELF_TEST: tag read-back produced " .. #proxies .. " item-request-proxy(es) requesting " ..
    tostring(fuel_depot_tag.drone_count) .. " drones")

  if #proxies == 0 then
    error("tag read-back produced no item-request-proxy - read_tags() didn't apply drone_count")
  end
end

local setup = function()
  local surface = game.surfaces["nauvis"]
  surface.request_to_generate_chunks({0, 0}, 3)
  surface.force_generate_chunk_requests()

  local force = game.forces.player
  force.research_all_technologies()

  -- A save created via headless --create has never had a client actually join and spawn, so
  -- the local player starts in remote view (no character, no cursor_stack) rather than as a
  -- character. Give it one so cursor/inventory-dependent checks (the blueprint test) can run.
  local player = game.players[1]
  if player and player.valid and player.controller_type ~= defines.controllers.character then
    local character = surface.create_entity{name = "character", position = {0, 0}, force = force}
    player.set_controller{type = defines.controllers.character, character = character}
  end

  -- Long road strip connecting everything, plus perpendicular stubs so every depot's
  -- corpse-hidden-tile actually lands on a road node.
  local tiles = {}
  for x = -20, 20 do
    table.insert(tiles, {name = "transport-drone-road", position = {x, 0}})
  end
  for _, x in pairs({-16, -8, 0, 8, 16}) do
    for y = -3, 7 do
      table.insert(tiles, {name = "transport-drone-road", position = {x, y}})
    end
  end
  surface.set_tiles(tiles, true, "abort_on_collision", false, true)

  -- Fuel depot: the network's fuel source. Everything else needs this to ever dispatch a drone.
  -- It dispatches its own "fuel truck" drones (push model), so it needs drone items too.
  local fuel_depot = build(surface, force, "fuel-depot", {-16, -6}, defines.direction.south)
  fuel_depot.insert_fluid{name = fuel_fluid, amount = 100000}
  give_drones(fuel_depot, 10)

  -- Item supply <-> request pair. Stock both normal and uncommon iron-plate, so the quality
  -- test below can check that requests only ever match supply of the same quality.
  local supply = build(surface, force, "supply-depot", {-8, -3}, defines.direction.south)
  local supply_chest = find_near(surface, "supply-depot-chest", supply.position)
  if not supply_chest then error("supply-depot-chest not found near supply depot") end
  supply_chest.insert{name = "iron-plate", count = 4000, quality = "normal"}
  supply_chest.insert{name = "iron-plate", count = 2000, quality = "uncommon"}

  local request = build(surface, force, "request-depot", {-8, 3}, defines.direction.north)
  request.set_recipe("request-iron-plate")
  give_drones(request, 10)

  -- A second request depot asking for the SAME item but at "uncommon" quality, on a spur off
  -- the same road so it shares the network. Should only ever draw from the uncommon stock above.
  local quality_request = build(surface, force, "request-depot", {-8, 6}, defines.direction.north)
  quality_request.set_recipe("request-iron-plate", "uncommon")
  give_drones(quality_request, 10)

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

  -- Also exercise the road network GUI, if there's a player to open it for (there is one even
  -- in a headless --create'd map; there won't be one on a dedicated server with nobody connected).
  local player = game.players[1]
  if player and player.valid then
    gui.open_gui(player)
    log("SELF_TEST: opened road network GUI for player 1")
    gui.close_gui(player)
    log("SELF_TEST: closed road network GUI for player 1")

    check_blueprint_tags(player, surface, force)
    log("SELF_TEST: blueprint tag round-trip ok")
  else
    log("SELF_TEST: no player available, skipping GUI/blueprint checks")
  end

  log("SELF_TEST: setup complete")

  return {
    request = request,
    quality_request = quality_request,
    fluid_request = fluid_request,
    buffer = buffer,
  }
end

local refs
local setup_ok = false

local snapshot = function()
  return {
    item = refs.request.get_output_inventory().get_item_count{name = "iron-plate", quality = "normal"},
    quality_item = refs.quality_request.get_output_inventory().get_item_count{name = "iron-plate", quality = "uncommon"},
    -- Cross-contamination check: the normal-quality request depot's output should never contain
    -- any uncommon iron-plate, and vice versa for the quality one.
    item_wrong_quality = refs.request.get_output_inventory().get_item_count{name = "iron-plate", quality = "uncommon"},
    quality_item_wrong_quality = refs.quality_request.get_output_inventory().get_item_count{name = "iron-plate", quality = "normal"},
    fluid = refs.fluid_request.get_fluid_count(test_fluid),
    buffer = refs.buffer.get_output_inventory().get_item_count("iron-plate"),
  }
end

local report_progress = function()
  if not (refs and refs.request and refs.request.valid) then return end
  local s = snapshot()
  log(string.format(
    "SELF_TEST_PROGRESS tick=%d item_delivered=%d quality_item_delivered=%d (wrong-quality leakage: %d/%d) fluid_delivered=%.1f buffer_delivered=%d",
    game.tick, s.item, s.quality_item, s.item_wrong_quality, s.quality_item_wrong_quality, s.fluid, s.buffer))
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
    local msg = string.format("item=%d quality_item=%d wrong_quality_leakage=%d/%d fluid=%.1f buffer=%d",
      s.item, s.quality_item, s.item_wrong_quality, s.quality_item_wrong_quality, s.fluid, s.buffer)

    local delivered = s.item > 0 and s.quality_item > 0 and s.fluid > 0 and s.buffer > 0
    local no_leakage = s.item_wrong_quality == 0 and s.quality_item_wrong_quality == 0

    if delivered and no_leakage then
      log("SELF_TEST_RESULT: PASS - " .. msg)
      game.print("SELF_TEST_RESULT: PASS - " .. msg)
    elseif not delivered then
      log("SELF_TEST_RESULT: FAIL - nothing was delivered - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - nothing was delivered - " .. msg)
    else
      log("SELF_TEST_RESULT: FAIL - quality leaked across requests - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - quality leaked across requests - " .. msg)
    end
  end
end

self_test.events =
{
  [defines.events.on_tick] = tick_handler
}

return self_test
