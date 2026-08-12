local transport_drone = require("script/transport_drone")

-- The informatron integration that used to live here is gone (script/informatron was removed
-- along with the in-game manual pages; the tips-and-tricks entries replaced it).
local interface =
{
  get_drone_count = function()
    return transport_drone.get_drone_count()
  end
}

if not remote.interfaces["transport_drones"] then
  remote.add_interface("transport_drones", interface)
end
