-- Added last in control.lua so that every other lib's on_init has already set up its storage.
local depot_common = require("script/depot_common")

local lib = {}

lib.on_init = function()
  depot_common.adopt_existing_depots()
end

return lib
