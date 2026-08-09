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

-- LuaInventory::get_contents() now returns an array of {name=, count=, quality=} rather than
-- a name -> count dictionary. This mod doesn't track quality (everything it makes/moves is
-- always normal quality - see the recipes' allow_quality = false), so just collapse by name.
util.contents_to_dict = function(contents)
  local dict = {}
  for k, item in pairs (contents) do
    dict[item.name] = (dict[item.name] or 0) + item.count
  end
  return dict
end

-- Constant combinators no longer expose get_signal/set_signal - signals now live in
-- "logistic sections" of slots. These helpers keep the old {signal = {type=, name=}, count=} shape
-- used throughout this mod so callers barely have to change.
util.get_combinator_signal = function(behavior, slot)
  local section = behavior.get_section(1)
  if not section then return {count = 0} end
  local filter = section.get_slot(slot)
  if not filter or not filter.value then return {count = 0} end
  return {signal = {type = filter.value.type, name = filter.value.name}, count = filter.min or 0}
end

util.set_combinator_signal = function(behavior, slot, signal)
  local section = behavior.get_section(1) or behavior.add_section()
  if not (signal and signal.signal and signal.signal.name) then
    section.clear_slot(slot)
    return
  end
  section.set_slot(slot, {value = {type = signal.signal.type or "item", name = signal.signal.name}, min = signal.count or 0})
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
  --local profiler = game.create_profiler()
  for k1, v1 in pairs (table) do
    local k2 = random(#table)
    table[k1], table[k2] = table[k2], table[k1]
  end
  --game.print({"", game.tick, " - ", profiler})
end


return util
