local affected_by_tiles = true

local util = require "__Transport_Drones__/data/tf_util/tf_util"

local fuel = settings.startup["fuel-fluid"].value
if not data.raw.fluid[fuel] then
  log("Bad name for fuel fluid. reverting to something else...")

  fuel = "petroleum-gas"
  if not data.raw.fluid[fuel] then
    fuel = nil
    for k, fluid in pairs (data.raw.fluid) do
      if fluid.fuel_value then
        fuel = fluid.name
        break
      end
    end
  end

  if not fuel then
    local index, fluid = next(data.raw.fluid)
    if fluid then
      fuel = fluid.name
    end
  end
end

local shared = require("shared")

local name = "transport-drone"


local transport_drone_flags = {"placeable-off-grid", "not-in-kill-statistics"}

-- Classic look: the drone body is just a scaled-down copy of the Tank's own animation (base
-- layer + runtime-tinted mask layer + shadow layer), instead of the old bespoke truck/ore/fluid
-- masked sprites. What the drone is actually carrying is now shown by a sticker drawn on top at
-- runtime (see transport_drone:update_sticker in script/transport_drone.lua) rather than baked
-- into a per-resource/per-fluid body texture, so we don't need a separate body prototype per
-- cargo type any more.
local sprite_base = util.copy(data.raw.car.tank)
util.recursive_hack_make_hr(sprite_base) -- no-op on modern (non hr_version) sprites, kept just in case
util.recursive_hack_scale(sprite_base, 0.5)

local make_body_animation = function(shift)
  local animation = util.copy(sprite_base.animation)
  util.recursive_hack_shift(animation, shift)
  return animation
end

-- Units default to steering tuned for biter-sized creatures (this used to be a single global
-- MapSetting shared by every unit in the game, so a mod had no way to override it - as of the
-- 2.0 prototype changes, steering moved onto UnitPrototype/SpiderUnitPrototype, so each unit type
-- can now be tuned individually). Our drones are tiny (collision_box is basically a point) and
-- only collide with tiles (see data-final-fixes.lua), so give them a tiny steering footprint
-- instead of inheriting a radius/force sized for a small biter - that mismatch was a source of
-- unnecessary "jostling" jitter when several drones were moving near each other around a depot.
local drone_steering =
{
  move = {radius = 0.1, separation_force = 0.01, separation_factor = 0.5},
  stay = {radius = 0.1, separation_force = 0.01, separation_factor = 0.5}
}

local make_unit = function(k)

  local shift = {(math.random() - 0.5) / 1.5, (math.random() - 0.5) / 1.5}

  local selection_box =
  {
    {
      -0.3 + shift[1],
      -0.3 + shift[2],
    },
    {
      0.3 + shift[1],
      0.3 + shift[2],
    }
  }

  local darkness = 0.3  + math.random() / 5

  local unit =
  {
    type = "unit",
    name = name.."-"..k,
    localised_name = {name},
    icon = util.path("data/entities/transport_drone/transport-drone-icon.png"),
    icon_size = 112,
    icon_mipmaps = 0,
    flags = transport_drone_flags,
    map_color = {b = 0.5, g = 1},
    enemy_map_color = {r = 1},
    max_health = 50,
    radar_range = 1,
    order="i-d",
    subgroup = "transport",
    resistances =
    {
      {
        type = "acid",
        decrease = 0,
        percent = 90
      }
    },
    healing_per_tick = 0.1,
    --minable = {result = name, mining_time = 2},
    collision_box = {{-0.01, -0.01}, {0.01, 0.01}},
    selection_box = selection_box,
    sticker_box = {shift, shift},
    collision_mask = shared.drone_collision_mask,
    max_pursue_distance = 64,
    min_persue_time = (60 * 15),
    --sticker_box = {{-0.2, -0.2}, {0.2, 0.2}},
    distraction_cooldown = (15),
    move_while_shooting = true,
    can_open_gates = true,
    ai_settings =
    {
      do_separation = true
    },
    steering = drone_steering,
    attack_parameters =
    {
      type = "projectile",
      ammo_category = "bullet",
      warmup = 0,
      cooldown = 2 ^ 30,
      range = 0.5,
      ammo_type =
      {
        category = util.ammo_category("transport-drone"),
        target_type = "entity",
        action =
        {
          type = "direct",
          action_delivery =
          {
            {
              type = "instant",
              target_effects =
              {
                {
                  type = "damage",
                  damage = {amount = 10 , type = util.damage_type("physical")}
                }
              }
            }
          }
        }
      },
      animation = make_body_animation(shift)
    },
    vision_distance = 40,
    has_belt_immunity = true,
    not_controllable = true,
    movement_speed = 0.15,
    distance_per_frame = 0.15,
    absorptions_to_join_attack = {pollution = 1000},
    rotation_speed = 1 / (60 * 1 + (math.random() / 20)),
    --corpse = name.." Corpse",
    dying_explosion = "explosion",
    light =
    {
      {
        minimum_darkness = darkness,
        intensity = 0.4,
        size = 10,
        color = {r=1.0, g=1.0, b=1.0},
        shift = shift
      },
      {
        type = "oriented",
        minimum_darkness = darkness,
        picture =
        {
          filename = "__core__/graphics/light-cone.png",
          priority = "extra-high",
          flags = { "light" },
          scale = 2,
          width = 200,
          height = 200
        },
        shift = {shift[1], shift[2] -3.5},
        size = 0.5,
        intensity = 0.6,
        color = {r=1.0, g=1.0, b=1.0}
      }
    },
    vehicle_impact_sound =  { filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
    working_sound =
    {
      sound = sprite_base.working_sound.main_sounds[1].sound,
      max_sounds_per_type = 5,
      audible_distance_modifier = 0.7
    },
    run_animation = make_body_animation(shift),
    affected_by_tiles = affected_by_tiles,
    emissions_per_second = {pollution = shared.drone_pollution_per_second}
  }
  data:extend{unit}
end

for k = 1, shared.variation_count do
  make_unit(k)
end

local slow_sticker =
{
  type = "sticker",
  name = "drone-slowdown-sticker",
  --icon = "__base__/graphics/icons/slowdown-sticker.png",
  flags = {},
  animation =
  {
    filename = "__base__/graphics/entity/slowdown-sticker/slowdown-sticker.png",
    priority = "extra-high",
    width = 1,
    height = 1,
    frame_count = 1,
    animation_speed = 1
  },
  duration_in_ticks = 1 * 60,
  target_movement_modifier = 1,
  target_movement_modifier_from = -0.1,
  target_movement_modifier_to = 1
}

data:extend
{
  slow_sticker
}

local sprite_switch_hack_proxy =
{
  type = "simple-entity",
  name = "sprite-switch-proxy",
  picture = util.empty_sprite(),
  flags = {"placeable-off-grid", "not-in-kill-statistics"},
  selectable_in_game = false,
  collision_mask = {layers = {}},
  max_health = 1
}

data:extend{sprite_switch_hack_proxy}
