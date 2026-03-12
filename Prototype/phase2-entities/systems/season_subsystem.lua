-- SeasonSubsystem
-- Global season state authority. Daily tick advances the clock.
-- Fires SEASON_CHANGED when season transitions, DAILY_TICK every day,
-- WEEKLY_TICK every 7 days, MONTHLY_TICK every ~28 days.

local EventBus = require("systems/event_bus")

local SeasonSubsystem = {}

-- Season definitions in order
local SEASONS = { "Spring", "Summer", "Autumn", "Winter" }
local DAYS_PER_SEASON = 14  -- 14 real days per season (56 days/year) per design recommendation
local DAYS_PER_YEAR   = DAYS_PER_SEASON * 4  -- 56

-- Biomass growth delta per week by season.
-- Annual balance over 4 equal 2-week seasons: +10+6-2-8 = +12 (net positive).
-- Slight annual surplus means the ecosystem recovers from bad years on its own.
-- Design note: original GDD values (8,4,-3,-12) assumed unequal season lengths.
-- With equal 14-day seasons, winter loss dominated. Rebalanced for stable world.
SeasonSubsystem.BIOMASS_WEEKLY_DELTA = {
    Spring = 10,   -- peak growth, snowmelt unlocks nutrients
    Summer = 6,    -- steady growth
    Autumn = -2,   -- slowing but still warm
    Winter = -8,   -- dormancy, not death
}

-- Travel capacity multiplier by season
SeasonSubsystem.TRAVEL_CAPACITY = {
    Spring = 0.7,   -- muddy roads post-snowmelt
    Summer = 1.0,   -- roads at 100%
    Autumn = 0.85,  -- harvest traffic, variable weather
    Winter = 0.2,   -- roads at 20% (mud, snow, ice)
}

-- Season pressure multiplier used by EconomySubsystem
-- Represents overall economic tension in the season
SeasonSubsystem.SEASON_PRESSURE = {
    Spring = 1.3,   -- post-winter scarcity
    Summer = 0.9,   -- peak growth, relatively easy
    Autumn = 0.8,   -- harvest glut
    Winter = 1.6,   -- scarcity, cold, reduced trade
}

-- Weather probability tables: { event_type, probability (0-1) }
SeasonSubsystem.WEATHER_TABLE = {
    Spring = {
        { event = "Flood",       prob = 0.15 },
        { event = "LateFrost",   prob = 0.20 },
    },
    Summer = {
        { event = "Drought",     prob = 0.18 },
        { event = "CropBlight",  prob = 0.08 },
    },
    Autumn = {
        { event = "EarlyFrost",  prob = 0.25 },
        { event = "WetHarvest",  prob = 0.30 },
    },
    Winter = {
        { event = "Blizzard",    prob = 0.35 },
    },
}

-- State
SeasonSubsystem.state = {
    year          = 1,
    day_of_year   = 1,   -- 1..56
    season_index  = 1,   -- 1=Spring, 2=Summer, 3=Autumn, 4=Winter
    season        = "Spring",
    week          = 1,
    month         = 1,
}

function SeasonSubsystem.init()
    SeasonSubsystem.state = {
        year        = 1,
        day_of_year = 1,
        season_index = 1,
        season      = "Spring",
        week        = 1,
        month       = 1,
    }
end

function SeasonSubsystem.get_season()
    return SeasonSubsystem.state.season
end

function SeasonSubsystem.get_state()
    return SeasonSubsystem.state
end

-- Advance one day. Called from the main simulation loop.
function SeasonSubsystem.tick_day()
    local s = SeasonSubsystem.state

    -- Fire daily tick first
    EventBus.fire("DAILY_TICK", {
        day    = s.day_of_year,
        season = s.season,
        year   = s.year,
    })

    -- Weekly tick every 7 days
    if s.day_of_year % 7 == 0 then
        EventBus.fire("WEEKLY_TICK", {
            week   = s.week,
            season = s.season,
            year   = s.year,
        })
        s.week = s.week + 1
        -- Roll weather events for this week
        SeasonSubsystem._roll_weather()
    end

    -- Monthly tick every 14 days (half-season cadence; a "month" = one season-half)
    if s.day_of_year % 14 == 0 then
        EventBus.fire("MONTHLY_TICK", {
            month  = s.month,
            year   = s.year,
            season = s.season,
        })
        s.month = s.month + 1
    end

    -- Advance day
    s.day_of_year = s.day_of_year + 1

    -- Check season transition
    local new_season_index = math.ceil(s.day_of_year / DAYS_PER_SEASON)
    if new_season_index > 4 then
        -- Year rollover
        s.day_of_year  = 1
        s.year         = s.year + 1
        new_season_index = 1
        s.week         = 1
        s.month        = 1
    end

    if new_season_index ~= s.season_index then
        s.season_index = new_season_index
        s.season       = SEASONS[new_season_index]
        EventBus.fire("SEASON_CHANGED", {
            season = s.season,
            year   = s.year,
            day    = s.day_of_year,
        })
    end
end

-- Weighted severity roll: 60% mild, 30% moderate, 10% severe.
-- The world muddles through most years; catastrophes are rare.
local function roll_severity()
    local r = math.random()
    if r < 0.60 then return 1  -- mild
    elseif r < 0.90 then return 2  -- moderate
    else return 3  -- severe
    end
end

-- Roll weather events for this week based on season probability table
function SeasonSubsystem._roll_weather()
    local s   = SeasonSubsystem.state
    local tbl = SeasonSubsystem.WEATHER_TABLE[s.season]
    if not tbl then return end

    for _, entry in ipairs(tbl) do
        if math.random() < entry.prob then
            EventBus.fire("WEATHER_EVENT", {
                event_type = entry.event,
                severity   = roll_severity(),
                season     = s.season,
                year       = s.year,
            })
        end
    end
end

return SeasonSubsystem
