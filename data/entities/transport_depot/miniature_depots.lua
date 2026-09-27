-- Miniature depots: 1x1 request and supply depots (the supply one with a much smaller inventory).
-- Both reuse the full-size depots' script logic - only the footprint, the road node offset (see the
-- make_variant calls in script/depot_common.lua) and the graphics differ.

-- The full-size depot sprites are drawn at 0.45 for a 3x3 footprint; a third of that fits a tile.
local mini_scale = 0.45 / 3

local depot_sprite = function(name, shift)
  return
  {
    filename = util.path("data/entities/transport_depot/"..name.."-depot-base.png"),
    width = 474,
    height = 335,
    frame_count = 1,
    scale = mini_scale,
    shift = shift
  }
end

local mini_request = util.copy(data.raw["assembling-machine"]["request-depot"])
mini_request.name = "mini-request-depot"
mini_request.localised_name = {"mini-request-depot"}
mini_request.localised_description = {"mini-request-depot-description"}
mini_request.collision_box = {{-0.35, -0.35}, {0.35, 0.35}}
mini_request.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
mini_request.max_health = 100
mini_request.minable = {result = "mini-request-depot", mining_time = 0.5}
mini_request.placeable_by = {item = "mini-request-depot", count = 1}
mini_request.radius_visualisation_specification.offset = {0, -1}
-- Items only: there's no output fluidbox, which also means the engine won't let a fluid request
-- recipe be picked here. The fuel box has no pipe connections because fuel only ever arrives by
-- drone (insert_fluid), never by pipe.
mini_request.fluid_boxes =
{
  {
    production_type = "input",
    volume = 5000,
    pipe_connections = {},
  },
}
mini_request.circuit_connector = circuit_connector_definitions.create_vector
(
  universal_connector_template,
  {
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
  }
)
mini_request.circuit_wire_max_distance = 10
mini_request.graphics_set =
{
  animation =
  {
    north = {layers = {depot_sprite("request", {0, 0.4 / 3})}},
    east = {layers = {depot_sprite("request", {0, 0.4 / 3})}},
    south = {layers = {depot_sprite("request", {0, 0.4 / 3})}},
    west = {layers = {depot_sprite("request", {0, 0.4 / 3})}},
  }
}

local mini_supply = util.copy(data.raw.container["supply-depot"])
mini_supply.name = "mini-supply-depot"
mini_supply.localised_name = {"mini-supply-depot"}
mini_supply.localised_description = {"mini-supply-depot-description"}
mini_supply.collision_box = {{-0.35, -0.35}, {0.35, 0.35}}
mini_supply.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
mini_supply.max_health = 100
mini_supply.inventory_size = 10
mini_supply.minable = {result = "mini-supply-depot", mining_time = 0.5}
mini_supply.placeable_by = {item = "mini-supply-depot", count = 1}
mini_supply.picture = {layers = {depot_sprite("supply", {0, 0.4 / 3})}}
mini_supply.circuit_connector = circuit_connector_definitions.create_vector
(
  universal_connector_template,
  {
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
    { variation = 26, main_offset = util.by_pixel(3, 5.5), shadow_offset = util.by_pixel(7.5, 7.5), show_shadow = true },
  }
)
mini_supply.radius_visualisation_specification.offset = {0, -1}

local items =
{
  {
    type = "item",
    name = "mini-request-depot",
    localised_name = {"mini-request-depot"},
    localised_description = {"mini-request-depot-description"},
    icon = mini_request.icon,
    icon_size = mini_request.icon_size,
    subgroup = "transport-drones",
    order = "e-b-b",
    stack_size = 20,
    place_result = "mini-request-depot"
  },
  {
    type = "recipe",
    name = "mini-request-depot",
    localised_name = {"mini-request-depot"},
    icon = mini_request.icon,
    icon_size = mini_request.icon_size,
    enabled = false,
    allow_quality = false,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 5},
      {type = "item", name = "iron-gear-wheel", amount = 5},
      {type = "item", name = "advanced-circuit", amount = 2},
    },
    energy_required = 5,
    results = {{type = "item", name = "mini-request-depot", amount = 1}}
  },
  {
    type = "item",
    name = "mini-supply-depot",
    localised_name = {"mini-supply-depot"},
    localised_description = {"mini-supply-depot-description"},
    icon = mini_supply.icon,
    icon_size = mini_supply.icon_size,
    subgroup = "transport-drones",
    order = "e-b-a",
    stack_size = 20,
    place_result = "mini-supply-depot"
  },
  {
    type = "recipe",
    name = "mini-supply-depot",
    localised_name = {"mini-supply-depot"},
    icon = mini_supply.icon,
    icon_size = mini_supply.icon_size,
    enabled = false,
    allow_quality = false,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 5},
      {type = "item", name = "iron-plate", amount = 5},
      {type = "item", name = "advanced-circuit", amount = 1},
    },
    energy_required = 5,
    results = {{type = "item", name = "mini-supply-depot", amount = 1}}
  }
}

data:extend{mini_request, mini_supply}
data:extend(items)
