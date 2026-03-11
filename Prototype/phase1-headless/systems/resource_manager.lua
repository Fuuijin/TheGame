-- ResourceManager (L2)
-- Tracks resource stocks per settlement. Responds to weekly ecology tick
-- and season events. Resources: Grain, Livestock, Timber, Fuel, Salt, Water, Forage.
-- Conservation law: resources consumed from stock; not conjured from nothing.

local EventBus        = require("systems.event_bus")
local EcologySimulator = require("systems.ecology_simulator")

local ResourceManager = {}

-- Base weekly production rates per resource per settlement (normal conditions)
-- These are POTENTIAL yields; actual yield is modified by ecology state.
local BASE_WEEKLY_PRODUCTION = {
    Grain     = 0,    -- harvested once in Autumn only (planted Spring, harvested Autumn)
    Livestock = 3,    -- slow replenishment year-round
    Timber    = 4,    -- harvested from forest tiles
    Fuel      = 5,    -- wood/peat, cut year-round
    Salt      = 2,    -- coastal/trade acquisition
    Water     = 10,   -- drawn from river/well; near-unlimited in normal conditions
    Forage    = 0,    -- calculated from ecology tile biomass
}

-- Weekly consumption rates per settlement (per capita scaling applied in PopulationSimulator)
-- These are base rates for a settlement of ~100 people
local BASE_WEEKLY_CONSUMPTION = {
    Grain     = 8,
    Livestock = 2,    -- slaughter & milk draw
    Timber    = 1,
    Fuel      = 3,    -- normal season; winter is 4x
    Salt      = 1,
    Water     = 5,
    Forage    = 4,
}

-- Fuel demand multiplier by season
local FUEL_DEMAND_MULTIPLIER = {
    Spring = 1.0,
    Summer = 0.5,
    Autumn = 1.5,
    Winter = 4.0,   -- design doc: fuel demand 4x higher in winter
}

-- Grain calendar flags — tracks whether grain was planted this spring
-- If not planted → no harvest → famine risk next winter
local GRAIN_FLAGS = {}  -- settlement_id → { planted, harvest_ready }

-- Settlement resource stocks
-- stocks[settlement_id][resource] = number
ResourceManager.stocks = {}

-- Population per settlement, used for consumption scaling.
-- A settlement of 50 people consumes half what a settlement of 100 does.
-- Updated from main.lua at registration; Phase 2 updates dynamically each month.
ResourceManager.pop = {}  -- settlement_id → population

-- Register a settlement with initial stocks
function ResourceManager.register_settlement(id, initial_stocks)
    ResourceManager.stocks[id] = {
        Grain     = initial_stocks.Grain     or 60,
        Livestock = initial_stocks.Livestock or 40,
        Timber    = initial_stocks.Timber    or 50,
        Fuel      = initial_stocks.Fuel      or 40,
        Salt      = initial_stocks.Salt      or 20,
        Water     = initial_stocks.Water     or 80,
        Forage    = initial_stocks.Forage    or 30,
    }
    -- Store population for consumption + harvest scaling
    local pop = initial_stocks._population or 100
    ResourceManager.pop[id] = pop
    -- Year 1 starts in Spring with crops already in the ground (last autumn's planting)
    GRAIN_FLAGS[id] = { planted = true, harvest_ready = false, _population = pop }
end

function ResourceManager.get_stock(settlement_id, resource)
    local s = ResourceManager.stocks[settlement_id]
    if not s then return 0 end
    return s[resource] or 0
end

function ResourceManager.init()
    EventBus.subscribe("WEEKLY_TICK",    ResourceManager._on_weekly_tick)
    EventBus.subscribe("SEASON_CHANGED", ResourceManager._on_season_changed)
    EventBus.subscribe("WEATHER_EVENT",  ResourceManager._on_weather_event)
end

-- Weekly tick: produce and consume resources
function ResourceManager._on_weekly_tick(data)
    local season = data.season

    for id, stocks in pairs(ResourceManager.stocks) do
        -- Population-scaled consumption: a village of 50 uses half the resources of 100.
        -- Base rates are calibrated for 100 people; pop_scale adjusts for actual size.
        local pop_scale = (ResourceManager.pop[id] or 100) / 100

        -- === PRODUCTION ===

        -- Forage: driven by ecology biomass. Conversion factor tuned so summer
        -- production (biomass ~80 × 0.5 × 0.12 = ~4.8) covers weekly consumption (4).
        -- Winter (biomass ~30 × 0.5 × 0.12 = ~1.8) draws down reserves — that's fine.
        local forage_yield = EcologySimulator.get_forage_yield(id)
        stocks.Forage = math.min(100, stocks.Forage + forage_yield * 0.12)

        -- Timber: only meaningful production in non-winter
        if season ~= "Winter" then
            stocks.Timber = math.min(200, stocks.Timber + BASE_WEEKLY_PRODUCTION.Timber)
        end

        -- Fuel: cut year-round. Peak in autumn (pre-winter stocking) and summer.
        -- Reduced in winter (frozen ground, short daylight). Net annual is positive
        -- so settlements build a small fuel reserve in good years.
        local fuel_cut = BASE_WEEKLY_PRODUCTION.Fuel  -- baseline 5/wk
        if season == "Autumn" then fuel_cut = fuel_cut * 2.0  -- autumn woodcutting surge
        elseif season == "Summer" then fuel_cut = fuel_cut * 1.5
        elseif season == "Winter" then fuel_cut = fuel_cut * 0.4  -- frozen ground
        end
        stocks.Fuel = math.min(200, stocks.Fuel + fuel_cut)

        -- Salt: slow accumulation through trade routes (simplified)
        stocks.Salt = math.min(100, stocks.Salt + BASE_WEEKLY_PRODUCTION.Salt)

        -- Water: replenishes naturally; drought reduces it
        stocks.Water = math.min(100, stocks.Water + BASE_WEEKLY_PRODUCTION.Water)

        -- Livestock: breeding in spring/summer (lambing, calving), slow in autumn, none in winter.
        -- Net production tuned so herd is self-sustaining at steady consumption.
        local livestock_gain = 0
        if season == "Spring" or season == "Summer" then
            livestock_gain = BASE_WEEKLY_PRODUCTION.Livestock * 1.5  -- peak breeding
        elseif season == "Autumn" then
            livestock_gain = BASE_WEEKLY_PRODUCTION.Livestock * 0.5  -- slowing down
        end
        -- Forage availability gates livestock growth
        if stocks.Forage > 10 then
            stocks.Livestock = math.min(150, stocks.Livestock + livestock_gain)
        end

        -- Grain is NOT produced weekly — it's a single autumn harvest event

        -- === CONSUMPTION ===

        -- Grain: steady daily draw
        stocks.Grain = math.max(0, stocks.Grain - BASE_WEEKLY_CONSUMPTION.Grain * pop_scale)

        -- Fuel: season-modulated
        local fuel_demand = BASE_WEEKLY_CONSUMPTION.Fuel * (FUEL_DEMAND_MULTIPLIER[season] or 1.0)
        stocks.Fuel = math.max(0, stocks.Fuel - fuel_demand * pop_scale)

        -- Livestock slaughter draw
        stocks.Livestock = math.max(0, stocks.Livestock - BASE_WEEKLY_CONSUMPTION.Livestock * pop_scale)

        -- Salt consumption (preserving food — critical pre-winter)
        stocks.Salt = math.max(0, stocks.Salt - BASE_WEEKLY_CONSUMPTION.Salt * pop_scale)

        -- Water consumption
        stocks.Water = math.max(0, stocks.Water - BASE_WEEKLY_CONSUMPTION.Water * pop_scale)

        -- Forage consumption (animal feed)
        stocks.Forage = math.max(0, stocks.Forage - BASE_WEEKLY_CONSUMPTION.Forage * pop_scale)

        -- Fire resource depletion events (only for critical resources to avoid spam)
        local CRITICAL = { Grain = true, Fuel = true, Livestock = true }
        for resource, qty in pairs(stocks) do
            if CRITICAL[resource] and qty <= 0 then
                -- Track first-depletion to avoid re-firing every week
                local key = id .. "_" .. resource .. "_depleted"
                if not ResourceManager._depleted_flags then ResourceManager._depleted_flags = {} end
                if not ResourceManager._depleted_flags[key] then
                    ResourceManager._depleted_flags[key] = true
                    EventBus.fire("RESOURCE_DEPLETED", {
                        resource      = resource,
                        settlement_id = id,
                        season        = season,
                    })
                end
            elseif qty > 5 then
                -- Clear flag once recovered
                if ResourceManager._depleted_flags then
                    ResourceManager._depleted_flags[id .. "_" .. resource .. "_depleted"] = nil
                end
            end
        end

        -- Check grain salt-preservation failure going into winter
        -- Salt scarcity in autumn → winter starvation (design doc)
        if season == "Autumn" and stocks.Salt < 5 then
            -- Livestock can't be preserved → effective food stock drops
            stocks.Grain = math.max(0, stocks.Grain - 10)
        end
    end
end

-- Season change: handle grain planting (Spring) and harvest (Autumn)
function ResourceManager._on_season_changed(data)
    local season = data.season

    for id, stocks in pairs(ResourceManager.stocks) do
        local flags = GRAIN_FLAGS[id]

        if season == "Spring" then
            -- Planting window opens. Automatic for now; Phase 2 lets player direct labour.
            -- Deduct seed grain
            if stocks.Grain >= 10 then
                stocks.Grain = stocks.Grain - 10
                flags.planted = true
            else
                flags.planted = false  -- not enough seed grain → no harvest
            end
            flags.harvest_ready = false

        elseif season == "Autumn" and flags.planted then
            -- Harvest: yield scales with population (a village farms for its size)
            -- and soil fertility. Formula: (pop/100) × 90 × (fertility/100)
            -- At pop=100, fertility=80: 90 × 0.8 = 72 units.
            -- Annual consumption for pop=100 at 8/wk × 8 weeks = 64 units.
            -- So a normal year produces a ~12% buffer — modest surplus as designed.
            local tile      = EcologySimulator.get_tile(id)
            local fertility = tile and tile.soil_fertility or 70
            local pop       = flags._population or 100  -- injected at registration
            local harvest_yield = math.floor((pop / 100) * 90 * (fertility / 100))
            stocks.Grain = math.min(250, stocks.Grain + harvest_yield)
            flags.planted       = false
            flags.harvest_ready = true

        elseif season == "Autumn" and not flags.planted then
            -- No crop was planted — famine incoming
            EventBus.fire("RESOURCE_DEPLETED", {
                resource      = "Grain",
                settlement_id = id,
                season        = "Autumn",
                reason        = "NoCropPlanted",
            })

        elseif season == "Winter" then
            -- Hoarding spikes: settlements hoard remaining stores (economic signal only)
            -- Actual price spike is handled in EconomySubsystem
        end
    end
end

-- Weather events directly reduce stocks
function ResourceManager._on_weather_event(data)
    local evt = data.event_type
    local sev = data.severity or 1

    for id, stocks in pairs(ResourceManager.stocks) do
        if evt == "Drought" then
            -- Drought reduces water and eventual grain yield
            stocks.Water  = math.max(0, stocks.Water  - sev * 8)
            -- Grain loss will be reflected at harvest via soil_fertility hit in EcologySimulator

        elseif evt == "Flood" then
            -- Flood damages stored grain (wet rot) and forage
            stocks.Grain  = math.max(0, stocks.Grain  - sev * 5)
            stocks.Forage = math.max(0, stocks.Forage - sev * 8)

        elseif evt == "CropBlight" then
            -- Blight hits standing grain directly; harvested less in Autumn
            GRAIN_FLAGS[id] = GRAIN_FLAGS[id] or { planted = false }
            if GRAIN_FLAGS[id].planted then
                -- Mark: blight will reduce harvest yield (tracked via soil_fertility)
                local tile = EcologySimulator.get_tile(id)
                if tile then tile.soil_fertility = math.max(0, tile.soil_fertility - sev * 15) end
            end

        elseif evt == "WetHarvest" then
            -- Wet harvest: yield reduced by 20-40% depending on severity
            if GRAIN_FLAGS[id] and GRAIN_FLAGS[id].planted then
                local tile = EcologySimulator.get_tile(id)
                if tile then tile.soil_fertility = math.max(0, tile.soil_fertility - sev * 5) end
            end

        elseif evt == "Blizzard" then
            -- Blizzard burns through fuel stocks and kills some livestock
            stocks.Fuel      = math.max(0, stocks.Fuel      - sev * 10)
            stocks.Livestock = math.max(0, stocks.Livestock - sev * 8)

        elseif evt == "EarlyFrost" or evt == "LateFrost" then
            -- Frost kills growing crops if still in ground
            if GRAIN_FLAGS[id] and GRAIN_FLAGS[id].planted then
                local tile = EcologySimulator.get_tile(id)
                if tile then tile.soil_fertility = math.max(0, tile.soil_fertility - sev * 8) end
            end
        end
    end
end

return ResourceManager
