local script_data =
{
  transport_speed = {},
  transport_capacity = {},
}

-- For a finite technology in the chain ("...-1" to "...-4"), .level is just its own level and
-- .researched flips to true when it completes. For the infinite one, .researched never becomes
-- true and .level is the *next* researchable level - so right after completing (or reversing)
-- a level, the highest finished level is .level - 1.
local get_effective_level = function(technology)
  if technology.researched then
    return technology.level
  end
  return technology.level - 1
end

local technology_effects =
{
  [shared.transport_speed_technology] = function(technology)
    local force_index = technology.force.index
    script_data.transport_speed[force_index] = get_effective_level(technology) * 0.2
  end,
  [shared.transport_capacity_technology] = function(technology)
    local force_index = technology.force.index
    script_data.transport_capacity[force_index] = get_effective_level(technology)
  end,
}


local on_research_changed = function(event)
  local technology = event.research
  local name = technology.name

  for effect_name, effect in pairs (technology_effects) do
    if name:find(effect_name, 0, true) then
      effect(technology)
      break
    end
  end

end

local lib = {}

lib.get_transport_speed_bonus = function(force_index)
  return script_data.transport_speed[force_index] or 0
end

lib.get_transport_capacity_bonus = function(force_index)
  return script_data.transport_capacity[force_index] or 0
end

lib.on_load = function()
  script_data = storage.transport_technologies or script_data
end

lib.on_init = function()
  storage.transport_technologies = storage.transport_technologies or script_data
end

lib.events =
{
  [defines.events.on_research_finished] = on_research_changed,
  [defines.events.on_research_reversed] = on_research_changed
}

return lib