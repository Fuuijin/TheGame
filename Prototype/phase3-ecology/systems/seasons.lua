-- Seasons
-- Island climate: mild maritime. No extremes.
-- 4 seasons × 14 days = 56-day year. Weekly and monthly ticks.
-- Fires: DAILY_TICK, WEEKLY_TICK, MONTHLY_TICK, SEASON_CHANGED, WEATHER_EVENT

local EventBus = require("systems/event_bus")

local Seasons = {}

local SEASON_NAMES = { "Spring", "Summer", "Autumn", "Winter" }
local DAYS_PER_SEASON = 14
local DAYS_PER_YEAR   = 56

-- Weekly rainfall added to each zone (modified by zone.rainfall_mult)
-- Island is maritime so even summer has some rain; winter is wettest.
Seasons.WEEKLY_RAINFALL = {
    Spring = 7,    -- maritime island: moderate spring rains
    Summer = 3,    -- driest season
    Autumn = 9,    -- wetter autumn
    Winter = 12,   -- wettest season but not extreme
}

-- Weekly evaporation modifier by season (applied to zone water_level)
Seasons.WEEKLY_EVAPORATION = {
    Spring = 4,
    Summer = 11,   -- strong summer drying
    Autumn = 5,
    Winter = 2,
}

-- Vegetation growth delta per week by season (base, modified by zone)
-- Winter is mild on a maritime island — vegetation goes dormant, not dead.
Seasons.BIOMASS_DELTA = {
    Spring = 9,
    Summer = 5,
    Autumn = -2,
    Winter = -4,  -- was -7; maritime islands have mild winters, no hard frost at low elevation
}

-- Weather probability tables per season
-- Island climate: floods in spring/autumn, drought rare, frost only on peaks
Seasons.WEATHER_TABLE = {
    Spring = {
        { event = "HeavyRain",  prob = 0.25 },
        { event = "LateFrost",  prob = 0.15 },
        { event = "StormSurge", prob = 0.08 },
    },
    Summer = {
        { event = "Drought",    prob = 0.12 },
        { event = "HeatWave",   prob = 0.10 },
        { event = "Wildfire",   prob = 0.06 },
    },
    Autumn = {
        { event = "HeavyRain",  prob = 0.30 },
        { event = "StormSurge", prob = 0.12 },
        { event = "EarlyFrost", prob = 0.20 },
    },
    Winter = {
        { event = "Blizzard",   prob = 0.25 },  -- peaks only
        { event = "HeavyRain",  prob = 0.35 },
        { event = "StormSurge", prob = 0.18 },
    },
}

-- State
Seasons.state = {
    year         = 1,
    day_of_year  = 1,
    season_index = 1,
    season       = "Spring",
    week         = 1,
    month        = 1,
}

function Seasons.init()
    Seasons.state = {
        year         = 1,
        day_of_year  = 1,
        season_index = 1,
        season       = "Spring",
        week         = 1,
        month        = 1,
    }
end

function Seasons.get_season() return Seasons.state.season end
function Seasons.get_state()  return Seasons.state end

local function roll_severity()
    local r = math.random()
    if r < 0.55 then return 1   -- mild
    elseif r < 0.85 then return 2  -- moderate
    else return 3                   -- severe
    end
end

function Seasons._roll_weather()
    local s   = Seasons.state
    local tbl = Seasons.WEATHER_TABLE[s.season]
    if not tbl then return end
    for _, entry in ipairs(tbl) do
        if math.random() < entry.prob then
            EventBus.fire("WEATHER_EVENT", {
                event_type = entry.event,
                severity   = roll_severity(),
                season     = s.season,
                year       = s.year,
                week       = s.week,
            })
        end
    end
end

function Seasons.tick_day()
    local s = Seasons.state

    EventBus.fire("DAILY_TICK", { day = s.day_of_year, season = s.season, year = s.year })

    if s.day_of_year % 7 == 0 then
        EventBus.fire("WEEKLY_TICK", { week = s.week, season = s.season, year = s.year })
        s.week = s.week + 1
        Seasons._roll_weather()
    end

    if s.day_of_year % 14 == 0 then
        EventBus.fire("MONTHLY_TICK", { month = s.month, season = s.season, year = s.year })
        s.month = s.month + 1
    end

    s.day_of_year = s.day_of_year + 1

    local new_idx = math.ceil(s.day_of_year / DAYS_PER_SEASON)
    if new_idx > 4 then
        s.day_of_year  = 1
        s.year         = s.year + 1
        s.week         = 1
        s.month        = 1
        new_idx        = 1
    end

    if new_idx ~= s.season_index then
        s.season_index = new_idx
        s.season       = SEASON_NAMES[new_idx]
        EventBus.fire("SEASON_CHANGED", { season = s.season, year = s.year })
    end
end

return Seasons
