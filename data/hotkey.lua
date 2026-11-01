-- Names come from the [controls] section of the locale files, keyed by prototype name. There used
-- to be "localised_named" keys here - a typo for localised_name, so they never did anything - and
-- the values they pointed at ({"follow-drone"}) weren't valid locale keys either. Dropped rather
-- than corrected, since the automatic [controls] lookup is what should be used anyway.
local hotkeys =
{
  {
    type = "custom-input",
    name = "follow-drone",
    linked_game_control = "toggle-driving",
    key_sequence = "RETURN",
    enabled_while_in_cutscene = true
  },
  {
    type = "custom-input",
    name = "toggle-road-network-gui",
    key_sequence = "CONTROL + T",
    enabled_while_in_cutscene = true
  },
}

data:extend(hotkeys)