local shared = require("shared")
local collision_mask_util = require("collision-mask-util")

local road_collision_layer = "transport_drone_road"
local tiles = data.raw.tile


local road_list = {}
local road_tile_list =
{
  type = "selection-tool",
  name = "road-tile-list",
  hidden = true,
  icon = "__Transport_Drones_Fixed__/data/tf_util/empty-sprite.png",
  icon_size = 1,
  stack_size = 1,
  select =
  {
    border_color = {},
    mode = {"any-tile"},
    cursor_box_type = "entity",
    tile_filters = road_list,
  },
  alt_select =
  {
    border_color = {},
    mode = {"any-tile"},
    cursor_box_type = "entity",
    tile_filters = road_list,
  }
}
data:extend{road_tile_list}

local place_as_tile_condition = {layers = {water_tile = true}}

if mods["space-exploration"] then
  if spaceship_collision_layer then place_as_tile_condition.layers[spaceship_collision_layer] = true end
  if empty_space_collision_layer then place_as_tile_condition.layers[empty_space_collision_layer] = true end
end

local process_road_item = function(item)

  local tile = tiles[item.place_as_tile.result]
  if not tile then return end
  local seen = {}
  while true do
    tile.collision_mask = {layers = {[road_collision_layer] = true}}
    table.insert(road_list, tile.name)
    seen[tile.name] = true
    tile = tiles[tile.next_direction or ""]
    if not tile then break end
    if seen[tile.name] then break end
  end
  item.place_as_tile.condition = place_as_tile_condition
end


local process_non_road_item = function(item)
  local condition = item.place_as_tile.condition
  condition.layers[road_collision_layer] = true
end

for k, item in pairs (data.raw.item) do
  if item.place_as_tile then
    if item.is_road_tile then
      process_road_item(item)
    else
      process_non_road_item(item)
    end
  end
end

local all_used_tile_collision_masks = {}
for k, tile in pairs (tiles) do
  tile.check_collision_with_entities = true
  for layer, bool in pairs ((tile.collision_mask and tile.collision_mask.layers) or {}) do
    all_used_tile_collision_masks[layer] = true
  end
end

all_used_tile_collision_masks[road_collision_layer] = nil

shared.drone_collision_mask =
{
  layers = all_used_tile_collision_masks,
  colliding_with_tiles_only = true,
  consider_tile_transitions = true,
}

for k, prototype in pairs (collision_mask_util.collect_prototypes_with_layer("player")) do
  if prototype.type ~= "gate" and prototype.type ~= "tile" then
    local mask = collision_mask_util.get_mask(prototype)
    if mask.layers["item"] then
      mask.layers[road_collision_layer] = true
    end
    prototype.collision_mask = mask
  end
end

if data.raw["assembling-machine"]["mining-depot"] then
  local mask = collision_mask_util.get_mask(data.raw["assembling-machine"]["mining-depot"])
  mask.layers[road_collision_layer] = true
  data.raw["assembling-machine"]["mining-depot"].collision_mask = mask
end

local util = require "__Transport_Drones_Fixed__/data/tf_util/tf_util"
require("data/entities/transport_drone/transport_drone")
require("data/make_request_recipes")
