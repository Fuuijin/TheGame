-- EcologySimulator (L1)
-- Per-tile ecological state: biomass, soil fertility, water level, fauna.
-- Weekly batch tick. Responds to season changes and weather events.
-- Tiles represent the smallest simulation unit — roughly a village catchment area.

local EventBus       = require("systems/event_bus")
local SeasonSubsystem = require("systems/season_subsystem")

local EcologySimulator = {}

-- Biome definitions
-- winter_severity: multiplier applied to winter biomass loss (1.0 = standard)
-- disease_risk:    base weekly disease roll added to PopulationSimulator
local BIOMES = {
    Forest  = { winter_severity = 1.0, disease_risk = 0.02, base_biomass = 80 },
    Plains  = { winter_severity = 1.0, disease_risk = 0.02, base_biomass = 60 },
    Wetland = { winter_severity = 1.0, disease_risk = 0.08, base_biomass = 55 },
    Upland  = { winter_severity = 1.4, disease_risk = 0.02, base_biomass = 45 },
    Coastal = { winter_severity = 0.7, disease_risk = 0.04, base_biomass = 50 },
}

-- Tile state shape:
-- {
--   id              : string
--   biome           : string
--   biomass         : number   [0..100]
--   soil_fertility  : number   [0..100]  (100 = pristine)
--   water_level     : number   [0..100]  (50 = normal)
--   fauna_pop       : number   [0..100]
--   drought_weeks   : number   accumulated drought stress
--   flood_damage    : number   flood damage flag (cleared each season)
-- }

EcologySimulator.tiles = {}

-- Register a tile. Called during world setup in main.lua.
function EcologySimulator.register_tile(id, biome)
    local biome_data = BIOMES[biome] or BIOMES.Plains
    EcologySimulator.tiles[id] = {
        id             = id,
        biome          = biome,
        biomass        = biome_data.base_biomass,
        soil_fertility = 80,
        water_level    = 50,
        fauna_pop      = 60,
        drought_weeks  = 0,
        flood_damage   = false,
    }
end

function EcologySimulator.get_tile(id)
    return EcologySimulator.tiles[id]
end

-- Subscribe to events
function EcologySimulator.init()
    EventBus.subscribe("WEEKLY_TICK",    EcologySimulator._on_weekly_tick)
    EventBus.subscribe("WEATHER_EVENT",  EcologySimulator._on_weather_event)
    EventBus.subscribe("SEASON_CHANGED", EcologySimulator._on_season_changed)
end

-- Weekly tick — apply biomass delta and secondary ecology
function EcologySimulator._on_weekly_tick(data)
    local season = data.season
    local delta  = SeasonSubsystem.BIOMASS_WEEKLY_DELTA[season] or 0

    for id, tile in pairs(EcologySimulator.tiles) do
        local biome_data = BIOMES[tile.biome] or BIOMES.Plains

        -- Biome modifies winter loss
        local effective_delta = delta
        if season == "Winter" then
            effective_delta = delta * biome_data.winter_severity
        end

        -- Drought stress accumulates and further suppresses growth
        if tile.drought_weeks > 0 and effective_delta > 0 then
            effective_delta = effective_delta * (1 - math.min(tile.drought_weeks * 0.15, 0.8))
        end

        -- Flood damage suppresses growth for one week after event
        if tile.flood_damage then
            effective_delta = effective_delta - 5
            tile.flood_damage = false  -- clear after one tick
        end

        -- Logistic recovery: when biomass is very low, spring pushes it back harder.
        -- Root systems, seed banks, and dormant plants survive even a brutal winter.
        -- This prevents total ecological death from one bad season.
        if effective_delta > 0 and tile.biomass < 20 then
            -- Below 20% biomass, growth is boosted proportionally to the deficit
            effective_delta = effective_delta * (1 + (20 - tile.biomass) * 0.05)
        end

        -- Apply and clamp. Hard floor of 3 = seed bank / root systems always survive.
        local BIOMASS_FLOOR = 3
        tile.biomass = math.max(BIOMASS_FLOOR, math.min(100, tile.biomass + effective_delta))

        -- Soil fertility: recovers in summer and autumn (fallow fields, leaf litter)
        -- Depletes only under sustained drought. Hard floor at 40 — medieval fields
        -- managed with crop rotation and animal manuring don't fall to zero.
        if tile.drought_weeks == 0 then
            if season == "Summer" or season == "Autumn" then
                tile.soil_fertility = math.min(100, tile.soil_fertility + 1.0)
            end
        elseif tile.drought_weeks > 2 then
            tile.soil_fertility = math.max(40, tile.soil_fertility - 1)
        end

        -- Fauna population tracks biomass with lag
        local fauna_target = tile.biomass * 0.8
        tile.fauna_pop = tile.fauna_pop + (fauna_target - tile.fauna_pop) * 0.1

        -- Drain drought counter each week without drought
        if tile.drought_weeks > 0 and season ~= "Summer" then
            tile.drought_weeks = math.max(0, tile.drought_weeks - 1)
        end
    end
end

-- Season change: clear flood records, reset drought if wet season arrived
function EcologySimulator._on_season_changed(data)
    for id, tile in pairs(EcologySimulator.tiles) do
        if data.season == "Spring" then
            -- Snowmelt: water level spikes
            tile.water_level = math.min(100, tile.water_level + 20)
        elseif data.season == "Summer" then
            tile.water_level = math.max(10, tile.water_level - 10)
        elseif data.season == "Autumn" then
            -- Autumn rains partially restore water
            tile.water_level = math.min(100, tile.water_level + 10)
        end
    end
end

-- Weather events directly modify tile state
function EcologySimulator._on_weather_event(data)
    local evt = data.event_type
    local sev = data.severity or 1  -- 1..3

    for id, tile in pairs(EcologySimulator.tiles) do
        if evt == "Flood" then
            tile.water_level  = math.min(100, tile.water_level + sev * 15)
            tile.flood_damage = true
            tile.soil_fertility = math.max(0, tile.soil_fertility - sev * 3)

        elseif evt == "Drought" then
            tile.drought_weeks = tile.drought_weeks + sev * 2
            tile.water_level   = math.max(0, tile.water_level - sev * 10)

        elseif evt == "LateFrost" or evt == "EarlyFrost" then
            -- Direct biomass hit
            tile.biomass = math.max(0, tile.biomass - sev * 6)

        elseif evt == "Blizzard" then
            tile.biomass  = math.max(0, tile.biomass - sev * 4)
            tile.fauna_pop = math.max(0, tile.fauna_pop - sev * 5)

        elseif evt == "CropBlight" then
            -- Blight hits soil fertility hard; handled in ResourceManager for grain
            tile.soil_fertility = math.max(0, tile.soil_fertility - sev * 10)

        elseif evt == "WetHarvest" then
            -- Reduces effective harvest but doesn't damage tile ecology
            -- ResourceManager listens separately for this
        end
    end
end

-- Query: forage yield for a tile this week (used by ResourceManager)
-- 30% of biomass is grazeable; conversion factor tuned so summer sustains livestock.
function EcologySimulator.get_forage_yield(tile_id)
    local tile = EcologySimulator.tiles[tile_id]
    if not tile then return 0 end
    return tile.biomass * 0.5  -- 50% of biomass available as forage potential
end

-- Query: disease risk for a tile this week (used by PopulationSimulator)
function EcologySimulator.get_disease_risk(tile_id)
    local tile = EcologySimulator.tiles[tile_id]
    if not tile then return 0 end
    local biome_data = BIOMES[tile.biome] or BIOMES.Plains
    -- High water level raises disease risk
    local water_bonus = math.max(0, (tile.water_level - 60) * 0.002)
    return biome_data.disease_risk + water_bonus
end

return EcologySimulator
