-- Setting names/descriptions come from the [mod-setting-name] section of the locale files.
-- Deliberately no localised_name here: a literal string counts as a LocalisedString and
-- would override that lookup, pinning every language to English (zh-CN has a full set).
local settings =
{
  {
    type = "int-setting",
    name = "transport-depot-update-interval",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 1,
    maximum_value = 80085
  },

  {
    type = "string-setting",
    name = "fuel-fluid",
    setting_type = "startup",
    default_value = "petroleum-gas"
  },

  {
    type = "double-setting",
    name = "fuel-amount-per-drone",
    setting_type = "startup",
    default_value = 50,
    minimum_value = 0,
    maximum_value = 10000
  },

  {
    type = "double-setting",
    name = "drone-fluid-capacity",
    setting_type = "startup",
    default_value = 500,
    minimum_value = 1,
    maximum_value = 10000
  },

  {
    type = "double-setting",
    name = "fuel-consumption-per-meter",
    setting_type = "startup",
    default_value = 0.025,
    minimum_value = 0
  },

  {
    type = "double-setting",
    name = "drone-pollution-per-second",
    setting_type = "startup",
    default_value = 0.005,
    minimum_value = 0
  }
}

data:extend(settings)
