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
local road_network = require("script/road_network")
local transport_drone = require("script/transport_drone")

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
-- The read half of the blueprint tag round trip, which needs no player: ask a live depot for the
-- tags it would write into a blueprint, then feed those straight back through script_raised_built
-- (the same event/shape a construction robot reviving a tagged ghost produces) on a fresh depot
-- and check read_tags() turned drone_count back into an item-request-proxy.
local check_blueprint_tag_round_trip = function(surface, force, tagged_entity, position)
  local depot = depot_common.get_depot(tagged_entity)
  if not depot then error("no depot registered for the entity to be blueprint-tagged") end
  if not depot.save_to_blueprint_tags then error("depot has no save_to_blueprint_tags") end

  local tags = depot:save_to_blueprint_tags()
  if not (tags and tags.drone_count and tags.drone_count > 0) then
    error("save_to_blueprint_tags returned nothing useful: " .. serpent.line(tags))
  end

  surface.request_to_generate_chunks(position, 3)
  surface.force_generate_chunk_requests()

  local fresh = surface.create_entity{name = tagged_entity.name, position = position, direction = defines.direction.south, force = force, raise_built = false}
  if not (fresh and fresh.valid) then
    error("failed to build a fresh " .. tagged_entity.name .. " for the tag read-back check")
  end

  script.raise_event(defines.events.script_raised_built, {entity = fresh, tags = {transport_depot_tags = tags}, tick = game.tick})

  local proxies = surface.find_entities_filtered{name = "item-request-proxy", position = position, radius = 2}
  if #proxies == 0 then
    error("tag read-back produced no item-request-proxy - read_tags() didn't apply drone_count")
  end

  log("SELF_TEST: blueprint tag round trip ok (drone_count=" .. tags.drone_count .. ")")
end

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

  -- The read half (feeding a tag back in through script_raised_built) is covered by
  -- check_blueprint_tag_round_trip, which needs no player and so always runs.
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
  -- supply-depot is a single container entity now (no separate supply-depot-chest).
  local supply = build(surface, force, "supply-depot", {-8, -3}, defines.direction.south)
  supply.insert{name = "iron-plate", count = 4000, quality = "normal"}
  supply.insert{name = "iron-plate", count = 2000, quality = "uncommon"}
  supply.insert{name = "steel-plate", count = 4000, quality = "normal"}

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

  -- Road network reader, just to make sure it still builds and updates without error.
  build(surface, force, "road-network-reader", {16, 0}, defines.direction.north)

  -- Depots are wired directly now (no separate writer/reader entity). Exercise both circuit
  -- paths: the plain enable/disable gate, and the special "signal = requested item" request-size
  -- override - both read straight off the depot's own control behavior.

  -- Override test: wire a combinator outputting "iron-plate = 50" to the plain request depot and
  -- set its condition to match its own requested item - this should cap its request size at 50
  -- instead of the full drone-capacity default (which would be much higher).
  local override_signal = build(surface, force, "constant-combinator", {-8, 8})
  local override_cb = override_signal.get_or_create_control_behavior()
  local override_section = override_cb.add_section()
  override_section.set_slot(1, {value = {type = "item", name = "iron-plate", quality = "normal"}, min = 50})
  -- constant-combinator has no separate input/output sides (unlike arithmetic/decider
  -- combinators), so it uses the plain circuit_red/circuit_green connector like any other entity.
  -- connect_to must be called with dot syntax, not colon - LuaWireConnector methods accessed via
  -- ":" double up the self argument and misalign the rest (confirmed by testing).
  local source_connector = override_signal.get_wire_connector(defines.wire_connector_id.circuit_red, true)
  local target_connector = request.get_wire_connector(defines.wire_connector_id.circuit_red, true)
  source_connector.connect_to(target_connector)
  local request_behavior = request.get_or_create_control_behavior()
  -- The override only takes effect while circuit_enable_disable is actually on (see
  -- update_circuit_writer) - a condition sitting in a depot that never toggled circuit control on
  -- must stay inert, which is exactly what the "unarmed" depot below checks.
  request_behavior.circuit_enable_disable = true
  -- CircuitConditionDefinition is a flat table, not nested under its own "condition" key.
  request_behavior.circuit_condition =
  {
    comparator = "=",
    first_signal = {type = "item", name = "iron-plate", quality = "normal"},
    second_signal = {type = "item", name = "iron-plate", quality = "normal"}
  }

  -- Disable test: a dedicated request depot (different item, so it doesn't interfere with the
  -- override test above) with circuit_enable_disable on and a condition that's never true - it
  -- should never dispatch a single drone for the whole test.
  supply.insert{name = "copper-plate", count = 4000, quality = "normal"}
  local disabled_request = build(surface, force, "request-depot", {-16, 3}, defines.direction.north)
  disabled_request.set_recipe("request-copper-plate")
  give_drones(disabled_request, 10)
  local disabled_behavior = disabled_request.get_or_create_control_behavior()
  disabled_behavior.circuit_enable_disable = true
  disabled_behavior.circuit_condition =
  {
    comparator = "=",
    first_signal = {type = "virtual", name = "signal-A"},
    constant = 1
  }
  -- Needs a real wire connection for the condition to actually be evaluated against a network at
  -- all (an unwired circuit_enable_disable=true doesn't disable anything - nothing to read).
  -- Wire it to the override combinator above, which never outputs signal-A, so the condition
  -- still never holds.
  local disabled_connector = disabled_request.get_wire_connector(defines.wire_connector_id.circuit_red, true)
  disabled_connector.connect_to(source_connector)

  -- Regression check: a configured circuit_condition should be inert while its own
  -- circuit_enable_disable/connect_to_logistic_network toggle is off (e.g. a player set a
  -- condition, then unchecked the toggle) - it must not be silently read as a request-size
  -- override anyway. This depot has a self-match condition set but never armed, and isn't even
  -- wired to anything, so it should request and receive its full uncapped amount just like an
  -- ordinary request depot.
  local unarmed_request = build(surface, force, "request-depot", {-16, 6}, defines.direction.north)
  unarmed_request.set_recipe("request-steel-plate")
  give_drones(unarmed_request, 10)
  local unarmed_behavior = unarmed_request.get_or_create_control_behavior()
  unarmed_behavior.circuit_condition =
  {
    comparator = "=",
    first_signal = {type = "item", name = "steel-plate", quality = "normal"},
    constant = 50
  }
  -- Deliberately NOT setting circuit_enable_disable or connect_to_logistic_network, and NOT wiring
  -- it to anything - this is testing whether an inert/unarmed condition still gets read.

  -- A spare depot built off on its own, used later to check that tearing a depot down cleans up
  -- properly (registry entry dropped, corpse destroyed, no double-teardown). It asks for stone,
  -- which nothing in the network stocks, so it never actually competes for the goods the
  -- delivery assertions below measure.
  local doomed = build(surface, force, "request-depot", {8, 6}, defines.direction.north)
  doomed.set_recipe("request-stone")
  give_drones(doomed, 5)

  -- Dedicated depots for the blueprint-parameter recipe check below - one of each kind that reads
  -- a recipe. They ask for stone, which nothing in the network stocks, for two reasons: they never
  -- compete for the goods the delivery assertions measure, and set_recipe() voids a machine's
  -- output inventory, so swapping their recipe can't destroy anything being counted.
  local parameter_request = build(surface, force, "request-depot", {16, 4}, defines.direction.north)
  parameter_request.set_recipe("request-stone")
  give_drones(parameter_request, 5)

  local parameter_buffer = build(surface, force, "buffer-depot", {16, -3}, defines.direction.south)
  parameter_buffer.set_recipe("request-stone")
  give_drones(parameter_buffer, 5)

  -- Blueprint tag round trip. The read half needs no player, so it always runs.
  check_blueprint_tag_round_trip(surface, force, fuel_depot, {0, 40})

  -- The write half goes through on_player_setup_blueprint, so it needs a player with a cursor.
  -- A headless --create'd map has none; a client-created save does.
  local player = game.players[1]
  if player and player.valid then
    gui.open_gui(player)
    log("SELF_TEST: opened road network GUI for player 1")
    gui.close_gui(player)
    log("SELF_TEST: closed road network GUI for player 1")

    check_blueprint_tags(player, surface, force)
    log("SELF_TEST: blueprint capture tagging ok")
  else
    log("SELF_TEST: no player available, skipping GUI/blueprint-capture checks")
  end

  log("SELF_TEST: setup complete")

  return {
    surface = surface,
    force = force,
    fuel_depot = fuel_depot,
    supply = supply,
    fluid_supply = fluid_supply,
    request = request,
    quality_request = quality_request,
    fluid_request = fluid_request,
    buffer = buffer,
    disabled_request = disabled_request,
    unarmed_request = unarmed_request,
    doomed = doomed,
    parameter_request = parameter_request,
    parameter_buffer = parameter_buffer,
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
    -- Circuit disable test: should stay at 0 the whole run, since its condition never holds.
    -- (The circuit override test reuses "item" above - it's the same request depot, wired to cap
    -- its request size at 50 instead of the full drone-capacity default.)
    circuit_disabled_item = refs.disabled_request.get_output_inventory().get_item_count{name = "copper-plate", quality = "normal"},
    -- Unarmed-condition test: should climb well past the 50 its leftover condition would cap it
    -- at if that condition were wrongly being read despite its toggle being off.
    unarmed_item = refs.unarmed_request.get_output_inventory().get_item_count{name = "steel-plate", quality = "normal"},
  }
end

local report_progress = function()
  if not (refs and refs.request and refs.request.valid) then return end
  local s = snapshot()
  log(string.format(
    "SELF_TEST_PROGRESS tick=%d item_delivered=%d quality_item_delivered=%d (wrong-quality leakage: %d/%d) fluid_delivered=%.1f buffer_delivered=%d circuit_disabled_item=%d",
    game.tick, s.item, s.quality_item, s.item_wrong_quality, s.quality_item_wrong_quality, s.fluid, s.buffer, s.circuit_disabled_item))
end

-- Every depot the test built and still tracks, as depot objects rather than entities.
local tracked_depots = function()
  local list = {}
  for _, key in pairs({"fuel_depot", "supply", "request", "quality_request", "fluid_request",
                       "buffer", "disabled_request", "unarmed_request"}) do
    local entity = refs[key]
    if entity and entity.valid then
      local depot = depot_common.get_depot(entity)
      if depot then list[key] = depot end
    end
  end
  return list
end

-- Tearing a depot down has to drop it from the registry and destroy its corpse - and must not
-- double-teardown (on_entity_died plus the registered on_object_destroyed both fire here).
local check_depot_removal = function()
  local doomed = refs.doomed
  if not (doomed and doomed.valid) then error("the depot earmarked for removal is already gone") end

  local depot = depot_common.get_depot(doomed)
  if not depot then error("no depot registered for the entity earmarked for removal") end
  local corpse = depot.corpse
  local index = depot.index

  doomed.destroy({raise_destroy = true})

  if depot_common.get_depot_by_index(index) then
    error("depot still registered after its entity was destroyed")
  end
  if corpse and corpse.valid then
    error("depot corpse survived the depot being destroyed")
  end
  log("SELF_TEST: depot removal cleaned up registry entry and corpse")
end

-- Cut the road strip in two and put it back, exercising the network split/merge bookkeeping
-- (set_node_ids / clear_network) and the depot re-registration it triggers. Goes through
-- set_tiles' raise_event so the mod's own script_raised_set_tiles handler does the work.
local check_road_network_split = function()
  local surface = refs.surface
  local cut = {4, 0}

  local before = table_size(road_network.get_networks())
  surface.set_tiles({{name = "grass-1", position = cut}}, true, false, false, true)
  local after_cut = table_size(road_network.get_networks())

  if after_cut <= before then
    error(string.format("cutting the road didn't split the network (%d networks before, %d after)", before, after_cut))
  end

  surface.set_tiles({{name = "transport-drone-road", position = cut}}, true, false, false, true)
  local after_repair = table_size(road_network.get_networks())

  if after_repair >= after_cut then
    error(string.format("repairing the road didn't merge the networks back (%d after cut, %d after repair)", after_cut, after_repair))
  end

  log(string.format("SELF_TEST: road split/merge ok (%d -> %d -> %d networks)", before, after_cut, after_repair))
end

-- The riskiest path in a 1.1 -> 2.1 upgrade: run the on_configuration_changed handlers in the
-- same order control.lua registers them, exactly as a version change would. Everything has to
-- keep working afterwards, which the refill check at the end of the run verifies.
--
-- It also has to migrate *in-flight* state, so this deliberately puts a fuel drone on the road
-- first. depot_common's handler zeroes every depot's reservation counters (they changed shape for
-- quality support) and relies on transport_drone's handler to re-register whatever in-flight
-- drones are still carrying; if that misses a case the reservation is silently lost here, and
-- then subtracted again when the drone delivers, leaving the counter negative forever.
local run_migration = function()
  local target = depot_common.get_depot(refs.unarmed_request)
  local fuel = depot_common.get_depot(refs.fuel_depot)
  if not (target and fuel) then error("missing depot objects for the in-flight fuel check") end

  -- Top the fuel depot back up first: it only holds a couple of thousand units at a time (its
  -- fluid boxes are small) and the other depots draw it down, so without this whether it can
  -- dispatch at all depends on how many depots the test happens to be running.
  refs.fuel_depot.insert_fluid{name = fuel_fluid, amount = 100000}
  give_drones(refs.fuel_depot, 10)

  -- Empty the target and dispatch by hand rather than waiting for the depot update cycle, so the
  -- drone is reliably still en route (and not already delivered) when the handlers run below.
  target:remove_fuel(target:get_fuel_amount())
  fuel:handle_fuel_request(target)

  -- Also orphan an in-flight cargo drone holding a supply reservation. By this tick the request
  -- depots have long since filled up and gone idle, so put one on the road by hand: restock the
  -- provider, publish that to the network, empty the requester, and dispatch.
  local requester = depot_common.get_depot(refs.quality_request)
  local supply = depot_common.get_depot(refs.supply)
  if not (requester and supply) then error("missing depot objects for the orphaned-drone check") end

  refs.supply.insert{name = "iron-plate", count = 2000, quality = "uncommon"}
  supply:update_contents()
  refs.quality_request.get_output_inventory().clear()
  requester:make_request()

  -- Destroying the entity with no event raised leaves the drone object behind holding a
  -- reservation it can never hand back - exactly the state every in-flight drone ends up in when a
  -- mod update removes its prototype (which is what happened when the 50 drone variations were
  -- collapsed into one). The handlers below can't re-register that reservation, so the drone must
  -- not be left anywhere that later tries to *unreserve* it against an already-wiped counter.
  -- check_reservation_accounting is what catches that going wrong.
  local orphaned = 0
  for _, drone in pairs (requester.drones) do
    if drone.entity.valid and drone.requested_item then
      drone.entity.destroy()
      orphaned = orphaned + 1
      break
    end
  end
  if orphaned == 0 then
    error("no in-flight cargo drone to orphan, so the prototype-removal path isn't being covered")
  end

  local before = target.fuel_on_the_way or 0
  if before <= 0 then
    error("couldn't put a fuel delivery in flight to migrate (fuel_on_the_way = " .. tostring(before) .. ")")
  end

  road_network.on_configuration_changed()
  depot_common.on_configuration_changed()
  transport_drone.on_configuration_changed()

  local after = depot_common.get_depot(refs.unarmed_request)
  after = (after and after.fuel_on_the_way) or 0
  if after <= 0 then
    error(string.format("migration lost the in-flight fuel reservation (%s before -> %s after)",
      tostring(before), tostring(after)))
  end

  log(string.format("SELF_TEST: ran on_configuration_changed handlers, in-flight fuel reservation survived (%s -> %s)",
    tostring(before), tostring(after)))
end

-- Reservation counters must never go negative. fuel_on_the_way in particular is decremented when
-- a fuel drone delivers, so if the migration above failed to re-register an in-flight drone's
-- reservation it goes negative and the depot then over-orders fuel forever.
local check_reservation_accounting = function()
  for key, depot in pairs (tracked_depots()) do
    local on_the_way = depot.fuel_on_the_way
    if on_the_way and on_the_way < 0 then
      error(string.format("%s has negative fuel_on_the_way (%s)", key, tostring(on_the_way)))
    end
    if depot.to_be_taken then
      for quality, by_name in pairs (depot.to_be_taken) do
        for name, count in pairs (by_name) do
          if count < 0 then
            error(string.format("%s has negative to_be_taken for %s/%s (%d)", key, quality, name, count))
          end
        end
      end
    end
  end
end

-- Blueprint parameter recipes ("parameter-0" .. "parameter-9") are real recipe prototypes with no
-- results at all, and the game lets a player set one on any crafting machine while parametrising a
-- blueprint. A depot sitting on one used to crash the whole save on the next update, because
-- get_requested_item/set_request_mode indexed recipe.products[1] unconditionally.
--
-- Set one on both a request and a buffer depot, let them update, and check they just go quiet
-- (no item requested) instead of throwing - then put a real recipe back and check they recover.
local parameter_depots = {}
local check_parameter_recipe = function()
  parameter_depots = {}

  for _, key in pairs({"parameter_request", "parameter_buffer"}) do
    local entity = refs[key]
    if not (entity and entity.valid) then error("missing entity for the parameter recipe check: " .. key) end

    local previous = entity.get_recipe()
    entity.set_recipe("parameter-0")
    if not entity.get_recipe() then
      error(key .. ": the game refused to accept a parameter recipe, so this check proves nothing")
    end

    parameter_depots[key] = previous and previous.name
  end

  log("SELF_TEST: set parameter-0 on a request and a buffer depot")
end

-- Runs a couple of update intervals after the recipes were swapped, so every affected depot has
-- certainly ticked at least once while holding the product-less recipe.
local check_parameter_recipe_recovery = function()
  for key, previous_name in pairs (parameter_depots) do
    local entity = refs[key]
    local depot = depot_common.get_depot(entity)
    if not depot then error(key .. ": depot vanished while holding a parameter recipe") end
    if depot.item then
      error(string.format("%s still reports a requested item (%s) while set to a parameter recipe",
        key, tostring(depot.item)))
    end

    -- get_request_size() is what the GUI calls every 60 ticks; it must not be reachable in a
    -- state where it can't size the request.
    if depot.mode then
      error(key .. ": a product-less recipe left a request mode set")
    end

    if previous_name then
      entity.set_recipe(previous_name)
    end
  end

  log("SELF_TEST: depots survived a parameter recipe and had their real recipe restored")
end

-- Empty out two request depots so the final check proves the network is still actively
-- delivering after the migration, rather than just still holding what it had before it.
local drain_depots = function()
  refs.quality_request.get_output_inventory().clear()

  local fluid_depot = depot_common.get_depot(refs.fluid_request)
  if not fluid_depot then error("no depot registered for the fluid request depot") end
  fluid_depot:set_output_fluidbox(nil)

  -- Restock the providers too. Draining a request depot destroys goods that came out of the
  -- supply side, so without this the refill target would be capped by whatever happened to be
  -- left rather than by whether delivery actually still works.
  refs.supply.insert{name = "iron-plate", count = 2000, quality = "uncommon"}
  refs.fluid_supply.insert_fluid{name = test_fluid, amount = 100000}

  local s = snapshot()
  if s.quality_item ~= 0 then error("draining the quality request depot didn't empty it") end
  if s.fluid ~= 0 then error("draining the fluid request depot didn't empty it") end
  log("SELF_TEST: drained the quality item and fluid request depots, restocked the providers")
end

-- Staged checks, run once each at the given tick. Anything that throws is recorded and reported
-- as a FAIL at the end of the run rather than taking the game down.
local phases =
{
  [1500] = {name = "depot_removal", run = check_depot_removal},
  [1800] = {name = "road_split", run = check_road_network_split},
  [2100] = {name = "migration", run = run_migration},
  [2400] = {name = "drain", run = drain_depots},
  -- The two parameter phases are deliberately several update intervals apart, so the depots
  -- certainly tick at least once while holding the product-less recipe.
  [3000] = {name = "parameter_recipe", run = check_parameter_recipe},
  [3300] = {name = "parameter_recovery", run = check_parameter_recipe_recovery},
  [5900] = {name = "reservation_accounting", run = check_reservation_accounting},
}

local phase_failures = {}

local tick_handler = function(event)
  local tick = event.tick

  if tick == 60 then
    local ok, err = xpcall(setup, debug.traceback)
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

  local phase = phases[tick]
  if phase then
    local ok, err = xpcall(phase.run, debug.traceback)
    if not ok then
      phase_failures[#phase_failures + 1] = phase.name
      log("SELF_TEST: PHASE_FAIL " .. phase.name .. " - " .. tostring(err))
      game.print("SELF_TEST: PHASE_FAIL " .. phase.name .. " - " .. tostring(err))
    end
  end

  if tick % 1200 == 0 then
    local ok, err = pcall(report_progress)
    if not ok then
      log("SELF_TEST_RESULT: PROGRESS_CHECK_FAIL - " .. tostring(err))
      game.print("SELF_TEST_RESULT: PROGRESS_CHECK_FAIL - " .. tostring(err))
    end
  end

  if tick == 6000 then
    local s = snapshot()
    local msg = string.format("item=%d quality_item=%d wrong_quality_leakage=%d/%d fluid=%.1f buffer=%d circuit_disabled_item=%d unarmed_item=%d",
      s.item, s.quality_item, s.item_wrong_quality, s.quality_item_wrong_quality, s.fluid, s.buffer, s.circuit_disabled_item, s.unarmed_item)

    -- quality_item and fluid were emptied out (and their providers restocked) after the
    -- migration, so these climbing back to a substantial level is what proves the network still
    -- actively delivers post-migration, not merely that it delivered once before it.
    local delivered = s.item > 0 and s.quality_item >= 500 and s.fluid >= 5000 and s.buffer > 0
    local no_leakage = s.item_wrong_quality == 0 and s.quality_item_wrong_quality == 0
    -- The circuit override condition caps the plain request depot's request size at 50 - it
    -- should have converged there (not kept climbing toward the much higher drone-capacity
    -- default), with a little slack for in-flight rounding.
    local circuit_override_ok = s.item >= 45 and s.item <= 55
    -- The circuit disable condition never holds, so this depot should never have dispatched a
    -- single drone.
    local circuit_disabled_ok = s.circuit_disabled_item == 0
    -- The unarmed depot's condition is never toggled on, so it must behave like it has no
    -- condition at all - well past the 50 a wrongly-applied override would cap it at.
    local unarmed_ok = s.unarmed_item >= 500
    local phases_ok = #phase_failures == 0

    if delivered and no_leakage and circuit_override_ok and circuit_disabled_ok and unarmed_ok and phases_ok then
      log("SELF_TEST_RESULT: PASS - " .. msg)
      game.print("SELF_TEST_RESULT: PASS - " .. msg)
    elseif not phases_ok then
      local failed = table.concat(phase_failures, ", ")
      log("SELF_TEST_RESULT: FAIL - staged checks failed (" .. failed .. ") - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - staged checks failed (" .. failed .. ") - " .. msg)
    elseif not delivered then
      log("SELF_TEST_RESULT: FAIL - nothing was delivered - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - nothing was delivered - " .. msg)
    elseif not no_leakage then
      log("SELF_TEST_RESULT: FAIL - quality leaked across requests - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - quality leaked across requests - " .. msg)
    elseif not circuit_override_ok then
      log("SELF_TEST_RESULT: FAIL - circuit request-size override didn't hold (expected ~50) - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - circuit request-size override didn't hold (expected ~50) - " .. msg)
    elseif not circuit_disabled_ok then
      log("SELF_TEST_RESULT: FAIL - circuit-disabled depot dispatched a drone anyway - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - circuit-disabled depot dispatched a drone anyway - " .. msg)
    else
      log("SELF_TEST_RESULT: FAIL - unarmed circuit condition was applied anyway - " .. msg)
      game.print("SELF_TEST_RESULT: FAIL - unarmed circuit condition was applied anyway - " .. msg)
    end
  end
end

self_test.events =
{
  [defines.events.on_tick] = tick_handler
}

return self_test
