-- EconomySubsystem (L3)
-- Price simulation using design formula:
--   BaseCost × (ExpectedDemand / CurrentStock) × SeasonPressure [0.5x–5.0x]
-- Rolling 4-week demand average. Trade capacity modulated by season.
-- Weekly tick.

local EventBus        = require("systems/event_bus")
local SeasonSubsystem = require("systems/season_subsystem")
local ResourceManager = require("systems/resource_manager")

local EconomySubsystem = {}

-- Base costs (abstract currency units — not gold yet, just relative value)
local BASE_COST = {
    Grain     = 10,
    Livestock = 25,
    Timber    = 8,
    Fuel      = 6,
    Salt      = 15,
    Water     = 2,
    Forage    = 4,
}

-- Base weekly expected demand (normal conditions, ~100-person settlement)
local BASE_DEMAND = {
    Grain     = 8,
    Livestock = 2,
    Timber    = 1,
    Fuel      = 3,
    Salt      = 1,
    Water     = 5,
    Forage    = 4,
}

-- Per-settlement economy state
-- economy_state[settlement_id] = {
--   prices     : { resource → current_price }
--   demand_history : { resource → [4 weeks of demand values] }
--   trade_volume   : number (relative units)
-- }
EconomySubsystem.economy_state = {}

-- Register a settlement for economy tracking
function EconomySubsystem.register_settlement(id)
    local prices   = {}
    local demand_h = {}
    for resource, base in pairs(BASE_COST) do
        prices[resource]   = base
        demand_h[resource] = { BASE_DEMAND[resource] or 1, BASE_DEMAND[resource] or 1,
                               BASE_DEMAND[resource] or 1, BASE_DEMAND[resource] or 1 }
    end
    EconomySubsystem.economy_state[id] = {
        prices         = prices,
        demand_history = demand_h,
        trade_volume   = 100,  -- index (100 = normal)
    }
end

function EconomySubsystem.get_price(settlement_id, resource)
    local state = EconomySubsystem.economy_state[settlement_id]
    if not state then return BASE_COST[resource] or 1 end
    return state.prices[resource] or BASE_COST[resource] or 1
end

function EconomySubsystem.init()
    EventBus.subscribe("WEEKLY_TICK",   EconomySubsystem._on_weekly_tick)
    EventBus.subscribe("SEASON_CHANGED", EconomySubsystem._on_season_changed)
end

-- Weekly tick: recalculate all prices
function EconomySubsystem._on_weekly_tick(data)
    local season          = data.season
    local season_pressure = SeasonSubsystem.SEASON_PRESSURE[season] or 1.0
    local travel_cap      = SeasonSubsystem.TRAVEL_CAPACITY[season] or 1.0

    for id, state in pairs(EconomySubsystem.economy_state) do
        -- Update trade volume based on travel capacity
        state.trade_volume = travel_cap * 100

        for resource, base_cost in pairs(BASE_COST) do
            -- Rolling demand: use last 4 weeks average
            local demand_hist = state.demand_history[resource]
            local actual_demand = BASE_DEMAND[resource] or 1

            -- Season modifies demand
            if resource == "Fuel" then
                actual_demand = actual_demand * (
                    season == "Winter" and 4.0 or
                    season == "Autumn" and 1.5 or 1.0
                )
            elseif resource == "Grain" and season == "Spring" then
                -- Post-winter scarcity: grain demand spikes
                actual_demand = actual_demand * 1.4
            end

            -- Update rolling 4-week history (shift left, add new value)
            table.remove(demand_hist, 1)
            table.insert(demand_hist, actual_demand)

            -- Expected demand = rolling 4-week average
            local expected_demand = 0
            for _, v in ipairs(demand_hist) do expected_demand = expected_demand + v end
            expected_demand = expected_demand / #demand_hist

            -- Current stock
            local current_stock = ResourceManager.get_stock(id, resource)
            if current_stock <= 0 then current_stock = 0.1 end  -- avoid division by zero

            -- Price formula: BaseCost × (ExpectedDemand / CurrentStock) × SeasonPressure
            local raw_price = base_cost * (expected_demand / current_stock) * season_pressure

            -- Clamp 0.5x – 5.0x relative to base
            local min_price = base_cost * 0.5
            local max_price = base_cost * 5.0
            state.prices[resource] = math.max(min_price, math.min(max_price, raw_price))
        end
    end
end

-- Season change: apply hoarding spike entering winter
function EconomySubsystem._on_season_changed(data)
    if data.season ~= "Winter" then return end

    -- Pre-winter hoarding: spike commodity prices for first week of winter
    for id, state in pairs(EconomySubsystem.economy_state) do
        for resource, price in pairs(state.prices) do
            if resource ~= "Water" then
                state.prices[resource] = math.min(BASE_COST[resource] * 5.0, price * 1.3)
            end
        end
    end
end

-- Query: return a formatted price snapshot for logging
function EconomySubsystem.get_price_snapshot(settlement_id)
    local state = EconomySubsystem.economy_state[settlement_id]
    if not state then return {} end
    local snap = {}
    for resource, price in pairs(state.prices) do
        snap[resource] = math.floor(price * 10) / 10  -- round to 1dp
    end
    snap._trade_volume = state.trade_volume
    return snap
end

return EconomySubsystem
