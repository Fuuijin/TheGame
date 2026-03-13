-- Ecology
-- Seven island zones derived from heightmap.
-- Tracks per-zone: biomass, soil_fertility, water_level, moisture.
-- Water flows downhill each week. Vegetation grows/decays with season and moisture.
-- No human systems. Designed to run forever in stable equilibrium.

local EventBus = require("systems/event_bus")
local Seasons  = require("systems/seasons")

local Ecology = {}

-- ── Zone definitions ──────────────────────────────────────────────────────────
-- elevation:      0 (coast) → 5 (peak). Determines water flow direction.
-- area_km2:       relative size. Larger zones buffer changes better.
-- rainfall_mult:  orographic effect — peaks catch more rain.
-- evap_mult:      how fast water evaporates (peaks cold=low, coast hot=high).
-- biomass_floor:  minimum biomass (seed banks, roots always survive).
-- biomass_cap:    maximum possible biomass for this zone.
-- soil_cap:       maximum soil fertility.
-- growth_mult:    scales seasonal growth delta from Seasons.BIOMASS_DELTA.
-- base_*:         starting values.

-- Per-zone thresholds (all added during balance pass):
--   waterlog_threshold:    sustained water above this suppresses growth (anaerobic stress)
--   flood_threshold:       acute water spike above this triggers flood_flag + soil damage
--                          (higher than waterlog so normal wet seasons don't damage soil)
--   flood_biomass_delta:   biomass effect when flood_flag fires (negative = damage)
--                          floodplain / wetland biomes are adapted — 0 = no net damage

local ZONE_DEFS = {
    central_peaks = {
        name                = "Central Peaks",
        biome               = "Mountain",
        elevation           = 5,
        area_km2            = 60,
        rainfall_mult       = 1.5,   -- orographic lift
        evap_mult           = 0.5,   -- cold, slow evaporation
        biomass_floor       = 3,
        biomass_cap         = 45,
        soil_cap            = 50,
        growth_mult         = 0.55,
        base_biomass        = 22,
        base_soil           = 38,
        base_water          = 35,
        drains_to           = { "highland_forest", "interior_hills" },
        drain_rate          = 0.50,  -- rocky: water runs off fast
        drain_threshold     = 38,
        waterlog_threshold  = 88,
        flood_threshold     = 95,
        flood_biomass_delta = -4,
    },
    highland_forest = {
        name                = "Highland Forest",
        biome               = "Forest",
        elevation           = 4,
        area_km2            = 180,
        rainfall_mult       = 1.2,
        evap_mult           = 0.65,
        biomass_floor       = 12,
        biomass_cap         = 100,
        soil_cap            = 100,
        growth_mult         = 1.1,
        base_biomass        = 78,
        base_soil           = 72,
        base_water          = 55,
        drains_to           = { "river_valleys", "interior_hills" },
        drain_rate          = 0.45,
        drain_threshold     = 45,
        waterlog_threshold  = 88,
        flood_threshold     = 95,
        flood_biomass_delta = -4,
    },
    interior_hills = {
        name                = "Interior Hills",
        biome               = "Hills",
        elevation           = 3,
        area_km2            = 220,
        rainfall_mult       = 1.0,
        evap_mult           = 0.80,
        biomass_floor       = 8,
        biomass_cap         = 80,
        soil_cap            = 90,
        growth_mult         = 0.90,
        base_biomass        = 60,
        base_soil           = 65,
        base_water          = 45,
        drains_to           = { "river_valleys", "coastal_plains" },
        drain_rate          = 0.50,  -- was 0.38; hillside runoff faster
        drain_threshold     = 42,
        waterlog_threshold  = 88,
        flood_threshold     = 95,
        flood_biomass_delta = -4,
    },
    river_valleys = {
        name                = "River Valleys",
        biome               = "Riverland",
        elevation           = 2,
        area_km2            = 120,
        rainfall_mult       = 0.9,
        evap_mult           = 0.75,
        biomass_floor       = 15,
        biomass_cap         = 95,
        soil_cap            = 100,
        growth_mult         = 1.2,
        base_biomass        = 72,
        base_soil           = 80,
        base_water          = 62,
        drains_to           = { "wetlands" },
        drain_rate          = 0.50,  -- was 0.30; rivers drain efficiently
        drain_threshold     = 55,    -- rivers naturally hold more water
        waterlog_threshold  = 92,    -- floodplains tolerate higher water
        flood_threshold     = 96,
        flood_biomass_delta = 0,     -- riverland vegetation adapted to flooding
    },
    coastal_plains = {
        name                = "Coastal Plains",
        biome               = "Plains",
        elevation           = 2,
        area_km2            = 160,
        rainfall_mult       = 0.85,
        evap_mult           = 0.95,
        biomass_floor       = 5,
        biomass_cap         = 75,
        soil_cap            = 85,
        growth_mult         = 0.95,
        base_biomass        = 55,
        base_soil           = 60,
        base_water          = 40,
        drains_to           = { "coastal_margin" },
        drain_rate          = 0.45,  -- was 0.35
        drain_threshold     = 42,
        waterlog_threshold  = 88,
        flood_threshold     = 95,
        flood_biomass_delta = -2,    -- partially adapted
    },
    wetlands = {
        name                = "Wetlands",
        biome               = "Wetland",
        elevation           = 1,
        area_km2            = 90,
        rainfall_mult       = 0.9,
        evap_mult           = 0.60,
        biomass_floor       = 18,
        biomass_cap         = 90,
        soil_cap            = 95,
        growth_mult         = 1.05,
        base_biomass        = 68,
        base_soil           = 70,
        base_water          = 72,    -- naturally wet
        drains_to           = { "coastal_margin" },
        drain_rate          = 0.28,  -- was 0.15
        drain_threshold     = 65,    -- wetlands hold water — only drain true excess
        waterlog_threshold  = 96,    -- wetland plants thrive at high water
        flood_threshold     = 99,    -- almost never flood-damaged
        flood_biomass_delta = 0,     -- wetland vegetation loves floods
    },
    coastal_margin = {
        name                = "Coastal Margin",
        biome               = "Coastal",
        elevation           = 0,
        area_km2            = 110,
        rainfall_mult       = 0.80,
        evap_mult           = 1.20,
        biomass_floor       = 3,
        biomass_cap         = 50,
        soil_cap            = 55,
        growth_mult         = 0.65,
        base_biomass        = 30,
        base_soil           = 40,
        base_water          = 35,
        drains_to           = {},
        drain_rate          = 0,     -- uses sea_drain instead
        drain_threshold     = 40,
        waterlog_threshold  = 88,
        flood_threshold     = 92,
        flood_biomass_delta = -2,    -- partial coastal adaptation
        sea_drain_rate      = 0.60,  -- was 0.45; stronger tidal/tidal exchange
        sea_drain_target    = 38,    -- natural coastal water level
    },
}

-- Zone order for water flow (high → low elevation, processed in this order)
local FLOW_ORDER = {
    "central_peaks",
    "highland_forest",
    "interior_hills",
    "river_valleys",
    "coastal_plains",
    "wetlands",
    "coastal_margin",
}

-- ── Zone state ────────────────────────────────────────────────────────────────
Ecology.zones = {}

function Ecology.init()
    EventBus.subscribe("WEEKLY_TICK",  Ecology._on_weekly_tick)
    EventBus.subscribe("WEATHER_EVENT", Ecology._on_weather_event)
    EventBus.subscribe("SEASON_CHANGED", Ecology._on_season_changed)

    for id, def in pairs(ZONE_DEFS) do
        Ecology.zones[id] = {
            id             = id,
            def            = def,           -- reference to static definition
            biomass        = def.base_biomass,
            soil_fertility = def.base_soil,
            water_level    = def.base_water,
            drought_weeks  = 0,
            flood_flag     = false,
            -- running averages for display
            biomass_avg    = def.base_biomass,
        }
    end
end

function Ecology.get_zone(id)
    return Ecology.zones[id]
end

function Ecology.get_def(id)
    return ZONE_DEFS[id]
end

function Ecology.all_zone_ids()
    return FLOW_ORDER
end

-- ── Weekly tick ───────────────────────────────────────────────────────────────
function Ecology._on_weekly_tick(data)
    local season = data.season

    -- 1. Rainfall added to each zone
    local base_rain = Seasons.WEEKLY_RAINFALL[season] or 8
    for id, zone in pairs(Ecology.zones) do
        local rain = base_rain * zone.def.rainfall_mult
        zone.water_level = math.min(100, zone.water_level + rain)
    end

    -- 2. Water flows downhill (process high → low)
    for _, id in ipairs(FLOW_ORDER) do
        local zone = Ecology.zones[id]
        local def  = zone.def

        -- Each zone has its own drain threshold (rocky zones drain at low levels,
        -- wetlands only drain true excess above their natural high water level)
        local threshold = def.drain_threshold or 45
        local excess = math.max(0, zone.water_level - threshold)

        if excess > 0 and #def.drains_to > 0 and def.drain_rate > 0 then
            local outflow = excess * def.drain_rate
            zone.water_level = zone.water_level - outflow
            local share = outflow / #def.drains_to
            for _, downstream_id in ipairs(def.drains_to) do
                local dz = Ecology.zones[downstream_id]
                if dz then
                    dz.water_level = math.min(100, dz.water_level + share)
                end
            end
        end

        -- Coastal margin drains excess directly to the sea
        if def.sea_drain_rate then
            local target = def.sea_drain_target or 38
            if zone.water_level > target then
                zone.water_level = zone.water_level
                    - (zone.water_level - target) * def.sea_drain_rate
            end
        end
    end

    -- 3. Evaporation
    local base_evap = Seasons.WEEKLY_EVAPORATION[season] or 4
    for id, zone in pairs(Ecology.zones) do
        local evap = base_evap * zone.def.evap_mult
        zone.water_level = math.max(0, zone.water_level - evap)
    end

    -- 4. Vegetation growth/decay
    local base_delta = Seasons.BIOMASS_DELTA[season] or 0
    for id, zone in pairs(Ecology.zones) do
        local def = zone.def

        local delta = base_delta * def.growth_mult

        -- Moisture modifies growth: below 25 water = drought stress
        -- Waterlogging threshold is zone-specific: wetland plants tolerate higher water
        local moisture_factor = 1.0
        local waterlog_limit = def.waterlog_threshold or 88
        if zone.water_level < 25 then
            moisture_factor = zone.water_level / 25  -- linear penalty
            zone.drought_weeks = zone.drought_weeks + 1
        elseif zone.water_level > waterlog_limit then
            -- Waterlogged: slows growth (anaerobic stress)
            moisture_factor = 0.85
            zone.drought_weeks = 0
        else
            zone.drought_weeks = math.max(0, zone.drought_weeks - 1)
        end

        -- Drought stress suppresses positive growth
        if delta > 0 then
            delta = delta * moisture_factor
        else
            -- Drought accelerates die-off
            if zone.drought_weeks > 2 then
                delta = delta * (1 + zone.drought_weeks * 0.15)
            end
        end

        -- Flood suppression: zone-specific biomass impact when flood_flag is set.
        -- Floodplain / wetland biomes are adapted — their flood_biomass_delta is 0.
        if zone.flood_flag then
            delta = delta + (def.flood_biomass_delta or -4)
            zone.flood_flag = false
        end

        -- Logistic recovery when biomass very low
        if delta > 0 and zone.biomass < 20 then
            delta = delta * (1 + (20 - zone.biomass) * 0.04)
        end

        -- Soil fertility modifies growth (fertile = bonus, depleted = penalty).
        -- Baseline is 80% of the zone's soil_cap so zones with low soil_cap (e.g. mountain)
        -- aren't permanently capped at poor growth just because their ceiling is lower.
        -- Minimum factor 0.55 ensures depleted zones can still recover — they never hit zero.
        local soil_baseline = def.soil_cap * 0.8
        local soil_factor = zone.soil_fertility / soil_baseline
        if delta > 0 then delta = delta * math.max(0.55, math.min(1.4, soil_factor)) end

        zone.biomass = math.max(def.biomass_floor, math.min(def.biomass_cap, zone.biomass + delta))

        -- Soil fertility: builds during summer/autumn proportional to biomass cover.
        -- No hard minimum-biomass gate — even sparse vegetation builds organic matter.
        -- Rate scales with how much living biomass there is relative to half-capacity.
        if zone.drought_weeks == 0 then
            if season == "Summer" or season == "Autumn" then
                local biomass_frac = math.min(1.0, zone.biomass / (def.biomass_cap * 0.5))
                zone.soil_fertility = math.min(def.soil_cap, zone.soil_fertility + 0.8 * biomass_frac)
            end
        elseif zone.drought_weeks > 3 then
            zone.soil_fertility = math.max(20, zone.soil_fertility - 0.5)
        end

        -- Slow rolling average for display smoothing
        zone.biomass_avg = zone.biomass_avg * 0.85 + zone.biomass * 0.15
    end
end

-- ── Season changed ────────────────────────────────────────────────────────────
function Ecology._on_season_changed(data)
    for id, zone in pairs(Ecology.zones) do
        if data.season == "Spring" then
            -- Snowmelt: only true alpine peaks (elevation 5).
            -- Highland Forest (elevation 4) is below the snowline on this maritime island.
            if zone.def.elevation >= 5 then
                zone.water_level = math.min(100, zone.water_level + 15)
            end
        elseif data.season == "Summer" then
            -- Peaks dry faster; valleys stabilise
        end
    end
end

-- ── Weather events ────────────────────────────────────────────────────────────
function Ecology._on_weather_event(data)
    local evt = data.event_type
    local sev = data.severity or 1

    for id, zone in pairs(Ecology.zones) do
        local def = zone.def

        if evt == "HeavyRain" then
            -- All zones get extra water; lower zones accumulate more runoff
            local flood_bonus = (5 - def.elevation) * 3
            zone.water_level = math.min(100, zone.water_level + sev * (8 + flood_bonus))
            -- Flood damage only on genuine acute spikes (flood_threshold >> waterlog_threshold)
            -- so normal wet seasons don't erode soil. Soil floor raised to 28 (was 10).
            local flood_limit = def.flood_threshold or 95
            if zone.water_level > flood_limit then
                zone.flood_flag = true
                zone.soil_fertility = math.max(28, zone.soil_fertility - sev * 2)
            end

        elseif evt == "StormSurge" then
            -- Coastal zones hit hardest. Biomass damage reduced (vegetation adapted to surge).
            -- Soil floor higher than before to allow recovery between storm years.
            if def.elevation <= 1 then
                -- elevation 0 (coast) more exposed than elevation 1 (wetlands)
                local bio_damage = def.elevation == 0 and sev * 5 or sev * 3
                zone.biomass = math.max(def.biomass_floor, zone.biomass - bio_damage)
                local soil_floor = def.elevation == 0 and 28 or 30  -- raised 22→28; prevents soil falling below recovery threshold
                zone.soil_fertility = math.max(soil_floor, zone.soil_fertility - sev * 3)
                zone.water_level = math.min(100, zone.water_level + sev * 12)
            elseif def.elevation <= 2 then
                zone.biomass = math.max(def.biomass_floor, zone.biomass - sev * 3)
            end

        elseif evt == "Drought" then
            zone.drought_weeks = zone.drought_weeks + sev * 3
            zone.water_level   = math.max(0, zone.water_level - sev * 8)

        elseif evt == "HeatWave" then
            local heat_factor = math.max(0.2, 1.0 - def.elevation * 0.15)
            zone.water_level  = math.max(0, zone.water_level - sev * 6 * heat_factor)
            zone.biomass      = math.max(def.biomass_floor, zone.biomass - sev * 3 * heat_factor)

        elseif evt == "Wildfire" then
            if def.elevation >= 2 and def.elevation <= 3 and zone.water_level < 40 then
                zone.biomass = math.max(def.biomass_floor, zone.biomass - sev * 18)
                zone.soil_fertility = math.max(18, zone.soil_fertility - sev * 8)
            end

        elseif evt == "Blizzard" then
            -- Damage tiered by elevation: peaks devastated, highland forest sheltered,
            -- interior hills get only light damage. Below elevation 3: negligible.
            if def.elevation >= 5 then
                zone.biomass = math.max(def.biomass_floor, zone.biomass - sev * 10)
            elseif def.elevation == 4 then
                zone.biomass = math.max(def.biomass_floor, zone.biomass - sev * 5)  -- was 10
            elseif def.elevation == 3 then
                zone.biomass = math.max(def.biomass_floor, zone.biomass - sev * 2)  -- was 4
            end

        elseif evt == "EarlyFrost" or evt == "LateFrost" then
            -- Frost multiplier reduced 5→3: maritime island frosts are mild
            local frost_hit = sev * 3 * math.max(0, (def.elevation - 1) / 4)
            zone.biomass = math.max(def.biomass_floor, zone.biomass - frost_hit)
        end
    end
end

-- ── Queries ───────────────────────────────────────────────────────────────────

-- Forage potential for fauna in a zone (0..100)
function Ecology.get_forage(zone_id)
    local z = Ecology.zones[zone_id]
    if not z then return 0 end
    return z.biomass * 0.6  -- 60% of biomass is grazeable
end

-- Water availability (drinking/habitat quality)
function Ecology.get_water(zone_id)
    local z = Ecology.zones[zone_id]
    if not z then return 0 end
    return z.water_level
end

-- Health index 0..1 for display (composite of biomass and soil vs caps)
function Ecology.get_health(zone_id)
    local z = Ecology.zones[zone_id]
    if not z then return 0 end
    local def = z.def
    local b = z.biomass / def.biomass_cap
    local s = z.soil_fertility / def.soil_cap
    return (b * 0.6 + s * 0.4)
end

return Ecology
