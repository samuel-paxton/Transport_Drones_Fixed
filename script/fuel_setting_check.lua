-- The fuel fluid is a free-text startup setting, and data stage quietly falls back to another fluid
-- when it doesn't name a real fluid prototype (see make_request_recipes.lua) - a log line nobody
-- reads. Tell the player instead, or it just looks like the setting didn't stick.

local get_fallback_message = function()
  local setting = settings.startup["fuel-fluid"].value
  local fuel = prototypes.recipe["fuel-depots"].products[1].name
  if setting == fuel then return end
  return {"fuel-fluid-not-found", setting, fuel, prototypes.fluid[fuel].localised_name}
end

local warn_all = function()
  local message = get_fallback_message()
  if message then game.print(message) end
end

local lib = {}

lib.events =
{
  -- on_init runs before a new game's player exists, so a print there would go nowhere.
  [defines.events.on_player_created] = function(event)
    local message = get_fallback_message()
    if message then game.get_player(event.player_index).print(message) end
  end
}

-- Changing a startup setting always raises on_configuration_changed on the next load.
lib.on_configuration_changed = warn_all

return lib
