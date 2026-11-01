local simulations = require("data/tips/simulations")

local tips =
{


  {
    type = "tips-and-tricks-item-category",
    name = "transport-drones",
    order = "t-[transport-drones]"
  },
  {
    type = "tips-and-tricks-item",
    name = "transport-drones",
    localised_name = {"transport_drones.title_transport_drones"},
    localised_description = {"transport_drones_pages.welcome-1"},
    order = "a",
    trigger =
    {
      type = "research",
      technology = "transport-system"
    },
    is_title = true,
    indent = 0,
    simulation = simulations.overview,
    category = "transport-drones",
  },
  {
    type = "tips-and-tricks-item",
    name = "road-network",
    localised_name = {"transport_drones.title_road_network"},
    localised_description = {"transport_drones_pages.road-network"},
    order = "b",
    dependencies = {"transport-drones"},
    indent = 1,
    simulation = simulations.road_network,
    category = "transport-drones",
    tag = "[item=road]"
  },
  {
    type = "tips-and-tricks-item",
    name = "drones",
    localised_name = {"transport_drones.title_drone"},
    localised_description = {"transport_drones_pages.drones-1"},
    order = "c",
    dependencies = {"transport-drones"},
    indent = 1,
    simulation = simulations.drones,
    category = "transport-drones",
    tag = "[item=transport-drone]"
  },

  {
    type = "tips-and-tricks-item",
    name = "depots",
    localised_name = {"transport_drones.title_depots"},
    localised_description = {"transport_drones_pages.transport-depots"},
    order = "d",
    dependencies = {"transport-drones"},
    category = "transport-drones",
    indent = 1,
    simulation = simulations.depots,
    tag = "[technology=transport-system]"
  },
  {
    type = "tips-and-tricks-item",
    name = "fuel-depots",
    localised_name = {"transport_drones.title_fuel_depots"},
    localised_description = {"transport_drones_pages.fuel-depot-1"},
    order = "e",
    dependencies = {"transport-drones"},
    category = "transport-drones",
    indent = 2,
    simulation = simulations.fuel_depots,
    tag = "[item=fuel-depot]"
  },
  {
    type = "tips-and-tricks-item",
    name = "request-depots",
    localised_name = {"transport_drones.title_request_depots"},
    localised_description = {"transport_drones_pages.request-depot-1"},
    order = "f",
    dependencies = {"transport-drones"},
    category = "transport-drones",
    indent = 2,
    simulation = simulations.request_depots,
    tag = "[item=request-depot]"
  },
  {
    type = "tips-and-tricks-item",
    name = "supply-depots",
    localised_name = {"transport_drones.title_supply_depots"},
    localised_description = {"transport_drones_pages.supply-depot"},
    order = "g",
    dependencies = {"transport-drones"},
    category = "transport-drones",
    indent = 2,
    simulation = simulations.supply_depots,
    tag = "[item=supply-depot]"
  },
  {
    type = "tips-and-tricks-item",
    name = "buffer-depots",
    localised_name = {"transport_drones.title_buffer_depots"},
    localised_description = {"transport_drones_pages.buffer-depot"},
    order = "h",
    dependencies = {"transport-drones"},
    category = "transport-drones",
    indent = 2,
    simulation = simulations.buffer_depots,
    tag = "[item=buffer-depot]"
  },
  {
    type = "tips-and-tricks-item",
    name = "network-reader",
    localised_name = {"transport_drones.title_network_reader"},
    localised_description = {"transport_drones_pages.network-reader"},
    order = "j",
    dependencies = {"transport-drones"},
    category = "transport-drones",
    indent = 1,
    simulation = simulations.network_reader,
    tag = "[item=road-network-reader]"
  },


}

data:extend(tips)
