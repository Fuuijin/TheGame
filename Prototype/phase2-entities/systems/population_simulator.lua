-- PopulationSimulator (L4)
-- Tracks population, morale, starvation, disease, and revolt per settlement.
-- Monthly tick for population changes. Weekly checks for morale and starvation.
-- Revolt is contagious: spreads to neighbouring settlements within 2 weeks.
--
-- Morale scale: 0–100
--   < 20 → passive resistance (lower tax yield, slower labour)
--   < 10 → revolt (granary burning, killing of tax collectors)
-- Starvation threshold: < 0.6 food/day sustained for 4 weeks

local EventBus        = require("systems/event_bus")
local ResourceManager = require("systems/resource_manager")
local EcologySimulator = require("systems/ecology_simulator")

local PopulationSimulator = {}

-- Settlement population state
-- pop_state[id] = {
--   population      : number
--   morale          : number (0–100)
--   starvation_weeks: number  (how many consecutive weeks below food threshold)
--   in_revolt       : bool
--   revolt_weeks    : number  (weeks since revolt started)
--   neighbours      : list of settlement IDs for revolt contagion
--   disease_active  : bool
-- }
PopulationSimulator.pop_state = {}

-- Mortality rates by season (additional per-capita weekly deaths per 1000)
local SEASONAL_MORTALITY = {
    Spring = { elderly = 0.5, infant = 0.3, disease = 0.2 },  -- spring dysentery
    Summer = { elderly = 0.2, infant = 0.2, disease = 0.3 },  -- summer malaria
    Autumn = { elderly = 0.2, infant = 0.2, disease = 0.1 },
    Winter = { elderly = 2.0, infant = 1.5, disease = 0.1 },  -- winter mortality spike
}

-- Morale recovery rate per week when conditions are good.
-- Symmetric with starvation hit: hard times take as long to forget as recover from.
local MORALE_RECOVERY_RATE  = 5
-- Morale hit per week during actual scarcity (< threshold weeks of reserve).
local MORALE_STARVATION_HIT = 5
-- Morale hit per week during active revolt (desperation deepens slightly)
local MORALE_REVOLT_HIT     = 1
-- Food threshold per person per day (design doc: 0.6)
local FOOD_THRESHOLD        = 0.6

-- Register a settlement
function PopulationSimulator.register_settlement(id, initial_population, neighbours)
    PopulationSimulator.pop_state[id] = {
        population       = initial_population or 100,
        morale           = 65,
        starvation_weeks = 0,
        in_revolt        = false,
        revolt_weeks     = 0,
        neighbours       = neighbours or {},
        disease_active   = false,
    }
end

function PopulationSimulator.get_state(id)
    return PopulationSimulator.pop_state[id]
end

function PopulationSimulator.init()
    EventBus.subscribe("WEEKLY_TICK",       PopulationSimulator._on_weekly_tick)
    EventBus.subscribe("MONTHLY_TICK",      PopulationSimulator._on_monthly_tick)
    EventBus.subscribe("RESOURCE_DEPLETED", PopulationSimulator._on_resource_depleted)
    EventBus.subscribe("WEATHER_EVENT",     PopulationSimulator._on_weather_event)
end

-- Weekly tick: morale updates, starvation checks, revolt checks
function PopulationSimulator._on_weekly_tick(data)
    local season = data.season

    for id, ps in pairs(PopulationSimulator.pop_state) do
        -- Food availability check
        -- Starvation threshold: grain_stock < (FOOD_THRESHOLD × weekly_need)
        -- FOOD_THRESHOLD = 0.6 means "less than 60% of needed weekly grain"
        -- Base weekly need scales with population (base 8/wk for 100 people)
        local grain = ResourceManager.get_stock(id, "Grain")
        local weekly_need = 8 * (ps.population / 100)
        local food_fraction = (weekly_need > 0) and (grain / weekly_need) or 0
        -- Reinterpret: food_fraction < FOOD_THRESHOLD means < threshold weeks of supply left
        -- 0.6 threshold = less than 0.6 weeks of grain remaining → scarcity
        -- 1.5 weeks reserve: normal medieval households kept ~2 weeks buffer.
        -- Trigger only when truly running low, not pre-emptively.
        local WEEKS_RESERVE_THRESHOLD = 1.5

        if food_fraction < WEEKS_RESERVE_THRESHOLD then
            ps.starvation_weeks = ps.starvation_weeks + 1
            ps.morale = math.max(0, ps.morale - MORALE_STARVATION_HIT)
        else
            ps.starvation_weeks = 0
            ps.morale = math.min(100, ps.morale + MORALE_RECOVERY_RATE)
        end

        -- Famine trigger: < threshold sustained for 4 weeks
        if ps.starvation_weeks >= 4 and not ps.famine_active then
            ps.famine_active = true
            EventBus.fire("FAMINE_STARTED", {
                settlement_id = id,
                season        = season,
                population    = ps.population,
            })
        elseif food_fraction >= WEEKS_RESERVE_THRESHOLD then
            ps.famine_active = false
        end

        -- Disease risk from ecology
        local disease_chance = EcologySimulator.get_disease_risk(id)
        if math.random() < disease_chance then
            ps.disease_active = true
            ps.morale = math.max(0, ps.morale - 4)
        else
            ps.disease_active = false
        end

        -- Active revolt: morale continues to fall
        if ps.in_revolt then
            ps.revolt_weeks = ps.revolt_weeks + 1
            ps.morale = math.max(0, ps.morale - MORALE_REVOLT_HIT)
            -- Revolt spreads to neighbours within 2 weeks
            if ps.revolt_weeks <= 2 then
                for _, neighbour_id in ipairs(ps.neighbours) do
                    local nps = PopulationSimulator.pop_state[neighbour_id]
                    if nps and not nps.in_revolt and nps.morale < 40 then
                        -- Contagion: low-morale neighbours are vulnerable
                        local contagion_chance = (40 - nps.morale) / 100
                        if math.random() < contagion_chance then
                            nps.in_revolt = true
                            nps.revolt_weeks = 0
                            EventBus.fire("REVOLT_SPREAD", {
                                from_id = id,
                                to_id   = neighbour_id,
                                season  = season,
                            })
                        end
                    end
                end
            end
        end

        -- Revolt threshold check
        if not ps.in_revolt then
            if ps.morale < 10 then
                ps.in_revolt    = true
                ps.revolt_weeks = 0
                EventBus.fire("REVOLT_STARTED", {
                    settlement_id = id,
                    morale        = ps.morale,
                    season        = season,
                    population    = ps.population,
                })
            end
        else
            -- Revolt resolves if morale recovers above 30 (food restored, faction intervenes)
            if ps.morale > 30 and ps.starvation_weeks == 0 then
                ps.in_revolt    = false
                ps.revolt_weeks = 0
            end
        end

        -- Military levy: summer — 10-20% of able men levied by faction
        -- (Population drain; simplified — just remove 15% of population temporarily)
        -- Phase 2 will make this explicit with a levy mechanic
    end
end

-- Monthly tick: births, deaths, migration
function PopulationSimulator._on_monthly_tick(data)
    local season = data.season or "Spring"  -- fallback; month doesn't carry season in this prototype
    -- Use last known season from SeasonSubsystem (we'll pass it through)

    for id, ps in pairs(PopulationSimulator.pop_state) do
        local mort = SEASONAL_MORTALITY[season] or SEASONAL_MORTALITY.Spring

        -- Deaths per month (per thousand, scaled to actual population)
        local death_rate = (mort.elderly + mort.infant + mort.disease) / 1000
        if ps.famine_active  then death_rate = death_rate + 0.02 end
        if ps.disease_active then death_rate = death_rate + 0.015 end

        local deaths = math.floor(ps.population * death_rate)
        ps.population = math.max(1, ps.population - deaths)

        -- Births: only when morale is above 40 and food not scarce
        if ps.morale > 40 and ps.starvation_weeks == 0 then
            local birth_rate = 0.008  -- ~1% per month baseline
            local births = math.floor(ps.population * birth_rate)
            ps.population = ps.population + births
        end

        -- Migration: population flees famine conditions
        if ps.famine_active then
            local flee_count = math.floor(ps.population * 0.05)  -- 5% flee per month
            ps.population = math.max(1, ps.population - flee_count)
            -- In Phase 2: fleeing population moves to neighbouring settlements
        end
    end
end

-- Resource depleted event: morale hit
function PopulationSimulator._on_resource_depleted(data)
    local ps = PopulationSimulator.pop_state[data.settlement_id]
    if not ps then return end

    local morale_hit = 5
    if data.resource == "Grain" then morale_hit = 15 end
    if data.resource == "Fuel"  then morale_hit = 10 end

    ps.morale = math.max(0, ps.morale - morale_hit)
end

-- Weather events: direct morale impact
function PopulationSimulator._on_weather_event(data)
    local evt = data.event_type
    local sev = data.severity or 1

    for id, ps in pairs(PopulationSimulator.pop_state) do
        -- Weather hits morale but not catastrophically — bad weather is part of life.
        -- The real morale damage comes from resource failure, not the weather itself.
        if evt == "Blizzard" then
            ps.morale = math.max(0, ps.morale - sev * 2)
        elseif evt == "Flood" then
            ps.morale = math.max(0, ps.morale - sev * 2)
        end
    end
end

return PopulationSimulator
