local util = require("util")

local deregister_gui_internal
deregister_gui_internal = function(gui_element, data)
  data[gui_element.index] = nil
  for k, child in pairs (gui_element.children) do
    deregister_gui_internal(child, data)
  end
end

util.deregister_gui = function(gui_element, data)
  local player_data = data[gui_element.player_index]
  if not player_data then return end
  deregister_gui_internal(gui_element, player_data)
end

util.register_gui = function(data, gui_element, param)
  local player_data = data[gui_element.player_index]
  if not player_data then
    data[gui_element.player_index] = {}
    player_data = data[gui_element.player_index]
  end
  player_data[gui_element.index] = param
end

util.gui_action_handler = function(event, data, functions)
  error("don't actually use me")
  if not data then error("Gui action handler data is nil") end
  if not functions then error("Gui action handler functions is nil") end
  local element = event.element
  if not (element and element.valid) then return end
  local player_data = data[event.player_index]
  if not player_data then return end
  local action = player_data[element.index]
  if action then
    functions[action.type](event, action)
    return true
  end
end

util.center = function(area)
  return {x = (area.left_top.x + area.right_bottom.x) / 2, y = (area.left_top.y + area.right_bottom.y) / 2}
end

util.distance = function(p1, p2)
  return (((p1.x - p2.x) ^ 2) + ((p1.y - p2.y) ^ 2)) ^ 0.5
end

util.radius = function(area)
  return util.distance(area.right_bottom, area.left_top) / 2
end

util.clear_item = function(entity, item_name)
  if not (entity and entity.valid and item_name) then return end
  entity.remove_item{name = item_name, count = entity.get_item_count(item_name)}
end

util.copy = util.table.deepcopy

-- get/set_fluid_segment_fluid require the fluid storage to already have an established "fluid
-- segment" (a connected pipe network, or something previously flowed through it) and error
-- otherwise ("Fluid storage at the given index does not have a fluid segment."). This mod's
-- depots use fluid boxes as plain script-controlled storage that's often never pipe-connected,
-- so read/write them through add_fluid/remove_fluid/clear_fluid instead, which work regardless.
--
-- On top of that, a crafting machine's fluid box *indices* now depend on which fluid
-- ingredients/products the currently set recipe actually has - an index that's valid with one
-- recipe set can simply not exist with another (e.g. an item-only recipe may leave only 1 fluid
-- box addressable even though the prototype defines 2), and touching a nonexistent index throws
-- rather than returning nil/false. Every call here is pcall-guarded for that reason.
util.get_fluid_box_content = function(entity, index)
  local ok, capacity = pcall(entity.get_fluid_capacity, index)
  if not (ok and capacity and capacity > 0) then return end
  local ok2, fluid = pcall(entity.remove_fluid, index, capacity)
  if not (ok2 and fluid) then return end
  pcall(entity.add_fluid, index, fluid)
  return fluid
end

util.set_fluid_box_content = function(entity, index, fluid)
  pcall(entity.clear_fluid, index)
  if fluid and fluid.name then
    pcall(entity.add_fluid, index, fluid)
  end
end

-- Drones themselves are always normal quality (see the "transport-drone" item recipe's
-- allow_quality = false) - this is the one quality name every depot always has to know about
-- regardless of what it's tracking for its actual cargo.
util.normal_quality = "normal"

-- A recipe set on a depot does NOT necessarily have any products. Blueprint parameters
-- ("parameter-0" through "parameter-9") are real recipe prototypes carrying no results at all,
-- and the game lets the player set one on any crafting machine while parametrising a blueprint -
-- so a depot can genuinely be sitting there with a product-less recipe. Indexing products[1]
-- blindly crashes the whole save in that case. Returns nil for "this recipe doesn't name a
-- thing to move", which every caller treats as "no request set".
util.get_recipe_product = function(recipe)
  local products = recipe and recipe.products
  return products and products[1]
end

-- item-request-proxy's (and blueprint entities') "modules" field used to be a plain
-- {[item_name] = count} dictionary. It's now an array of BlueprintInsertPlan, which needs an
-- explicit destination inventory + stack index per item rather than just a name and a count.
-- This mod only ever uses it to request "transport-drone" items into a depot's crafter_input
-- (the recipe's item ingredient slot), so that's the only shape this needs to build. Drones are
-- always normal quality, so the request is pinned to that explicitly.
util.drone_item_request_modules = function(count)
  return
  {
    {
      id = {name = "transport-drone", quality = util.normal_quality},
      items = {in_inventory = {{inventory = defines.inventory.crafter_input, stack = 0, count = count}}}
    }
  }
end

-- Everywhere this mod tracks item quantities by name, it now has to track them by (quality,
-- name) instead, since the same item name can show up in several different qualities at once.
-- Quality is indexed first - t[quality][name] - since the overwhelming majority of items in
-- play are normal quality, which keeps that common case a single cheap sub-table lookup rather
-- than something every single name-lookup has to unpack.
util.get_quality_item = function(t, quality, name)
  local by_name = t[quality]
  return by_name and by_name[name]
end

-- Sets network.item_supply[quality][name][depot_index] = count (or clears it, for count = nil),
-- creating the intermediate sub-tables as needed. This is the exact operation every depot type
-- does to publish (or retract) its contribution to the network's supply of an item/fluid.
util.set_network_supply = function(supply, quality, name, depot_index, count)
  local by_quality = supply[quality]
  if not by_quality then
    if count == nil then return end
    by_quality = {}
    supply[quality] = by_quality
  end
  local by_name = by_quality[name]
  if not by_name then
    if count == nil then return end
    by_name = {}
    by_quality[name] = by_name
  end
  by_name[depot_index] = count
end

util.set_quality_item = function(t, quality, name, value)
  local by_name = t[quality]
  if not by_name then
    if value == nil then return end
    by_name = {}
    t[quality] = by_name
  end
  by_name[name] = value
end

util.add_quality_item = function(t, quality, name, amount)
  local by_name = t[quality]
  if not by_name then
    by_name = {}
    t[quality] = by_name
  end
  by_name[name] = (by_name[name] or 0) + amount
end

-- Calls f(quality, name, count) for every entry of a t[quality][name] = count table.
util.for_each_quality_item = function(t, f)
  for quality, by_name in pairs (t) do
    for name, count in pairs (by_name) do
      f(quality, name, count)
    end
  end
end

-- Returns quality, name, count for an arbitrary (first found) entry of a t[quality][name] =
-- count table, or nil if it's empty.
util.first_quality_item = function(t)
  local quality, by_name = next(t)
  if not quality then return end
  local name, count = next(by_name)
  if not name then return end
  return quality, name, count
end

-- LuaInventory::get_contents() now returns an array of {name=, count=, quality=} rather than
-- a name -> count dictionary. Fold it into this mod's [quality][name] = count shape.
util.contents_to_dict = function(contents)
  local dict = {}
  for k, item in pairs (contents) do
    util.add_quality_item(dict, item.quality or util.normal_quality, item.name, item.count)
  end
  return dict
end

-- Constant combinators no longer expose get_signal/set_signal - signals now live in
-- "logistic sections" of slots. These helpers keep the old {signal = {type=,name=,quality=}, count=}
-- shape used throughout this mod so callers barely have to change.
util.get_combinator_signal = function(behavior, slot)
  local section = behavior.get_section(1)
  if not section then return {count = 0} end
  local filter = section.get_slot(slot)
  if not filter or not filter.value then return {count = 0} end
  return {signal = {type = filter.value.type, name = filter.value.name, quality = filter.value.quality}, count = filter.min or 0}
end

util.set_combinator_signal = function(behavior, slot, signal)
  local section = behavior.get_section(1) or behavior.add_section()
  if not (signal and signal.signal and signal.signal.name) then
    section.clear_slot(slot)
    return
  end
  section.set_slot(slot,
  {
    value =
    {
      type = signal.signal.type or "item",
      name = signal.signal.name,
      quality = signal.signal.quality or util.normal_quality
    },
    min = signal.count or 0
  })
end

util.first_key = function(map)
  local k, v = next(map)
  return k
end

util.first_value = function(map)
  local k, v = next(map)
  return v
end

util.angle = function(position_1, position_2)
  local d_x = (position_2[1] or position_2.x) - (position_1[1] or position_1.x)
  local d_y = (position_2[2] or position_2.y) - (position_1[2] or position_1.y)
  return math.atan2(d_y, d_x)
end

util.area = function(position, radius)
  return {{position.x - radius, position.y - radius},{position.x + radius, position.y + radius}}
end

local math = math
util.gaussian = function(mean, variance)
  return  math.sqrt(-2 * variance * math.log(math.random())) *
          math.cos(2 * math.pi * math.random()) + mean
end

local random = math.random
util.shuffle_table = function(table)
  for k1, v1 in pairs (table) do
    local k2 = random(#table)
    table[k1], table[k2] = table[k2], table[k1]
  end
end

-- Debug helper for the various depot/drone :say() methods. 1.1 used the
-- "tutorial-flying-text" entity, which no longer exists in 2.x, so this draws
-- the text via the rendering API instead - no prototype required.
util.say = function(entity, text)
  if not (entity and entity.valid) then return end
  rendering.draw_text
  {
    text = tostring(text),
    surface = entity.surface,
    target = entity.position,
    color = {r = 1, g = 1, b = 1},
    alignment = "center",
    time_to_live = 60,
  }
end

return util
