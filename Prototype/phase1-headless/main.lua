-- ============================================================
-- TheGame — Phase 1 Prototype: Headless Simulation
-- ============================================================
-- No player. No graphics. Just the world running.
-- Seasons tick. Resources deplete. Prices move. Villages react.
--
-- Run with: love . (Love2D) or lua main.lua (pure Lua, see note below)
--
-- NOTE: This file is written to run in EITHER Love2D OR pure Lua.
-- In Love2D: love.update drives the sim; love.draw renders the log.
-- In pure Lua: call run_headless() directly.
-- ============================================================
-- Set up debug mode if "debug" arg is passed (e.g. love . debug)
if arg[2] == "debug" then
    require("lldebugger").start()
end

-- Fix require path whether run from love or lua CLI
local function setup_path()
    -- Love2D uses love.filesystem; plain Lua uses package.path
    if love then
        -- Love2D handles require natively from the root
    else
        package.path = package.path .. ";./?.lua"
    end
end
setup_path()

-- Load systems
local EventBus            = require("systems.event_bus")
local SeasonSubsystem     = require("systems.season_subsystem")
local EcologySimulator    = require("systems.ecology_simulator")
local ResourceManager     = require("systems.resource_manager")
local EconomySubsystem    = require("systems.economy_subsystem")
local PopulationSimulator = require("systems.population_simulator")

-- ============================================================
-- World Configuration
-- Define settlements and their tiles/biomes here.
-- Phase 2 will load this from a world data file.
-- ============================================================

local SETTLEMENTS         = {
    -- Stocks represent post-last-autumn-harvest state entering Spring.
    -- Grain must last through Spring+Summer (8 wks) until next Autumn harvest.
    -- Base: 8 units/week/100 people. Ashford (pop 120) needs ~10/wk for 8 wks = ~80 minimum.
    -- Starting slightly above minimum to leave room for a bad year.
    -- Starting in Spring after last autumn's harvest + woodcutting.
    -- Fuel stocks reflect autumn woodcutting surge (2× production in autumn).
    -- Stonekeep is linked to Millhaven (upland pastoral ↔ forest timber trade).
    {
        id          = "Ashford",
        biome       = "Plains",
        population  = 120,
        init_stocks = { Grain = 100, Livestock = 50, Timber = 40, Fuel = 70, Salt = 25, Water = 80, Forage = 30 },
        neighbours  = { "Millhaven", "Brackenmere" },
    },
    {
        id          = "Millhaven",
        biome       = "Forest",
        population  = 80,
        init_stocks = { Grain = 75, Livestock = 30, Timber = 90, Fuel = 90, Salt = 18, Water = 70, Forage = 50 },
        neighbours  = { "Ashford", "Stonekeep" },
    },
    {
        id          = "Brackenmere",
        biome       = "Wetland",
        population  = 60,
        init_stocks = { Grain = 60, Livestock = 25, Timber = 20, Fuel = 80, Salt = 30, Water = 90, Forage = 20 },
        neighbours  = { "Ashford" },
    },
    {
        id          = "Stonekeep",
        biome       = "Upland",
        population  = 50,
        init_stocks = { Grain = 60, Livestock = 60, Timber = 10, Fuel = 75, Salt = 12, Water = 40, Forage = 60 },
        neighbours  = { "Millhaven" }, -- upland trade route through Millhaven forest
    },
}

-- ============================================================
-- Logging
-- ============================================================

local LOG                 = {} -- table of log lines
local MAX_LOG             = 500

local function log(msg)
    local s = SeasonSubsystem.get_state()
    local prefix = string.format("[Y%d W%02d %-6s] ", s.year, s.week, s.season)
    local line = prefix .. msg
    table.insert(LOG, line)
    if #LOG > MAX_LOG then table.remove(LOG, 1) end
    -- Also print to terminal
    print(line)
end

-- ============================================================
-- Wire up event logging — all world events go through here
-- ============================================================

local function setup_event_logging()
    EventBus.subscribe("SEASON_CHANGED", function(d)
        log(string.format("=== SEASON CHANGE: %s (Year %d) ===", d.season, d.year))
    end)

    EventBus.subscribe("WEATHER_EVENT", function(d)
        local sev_str = ({ "mild", "moderate", "severe" })[d.severity] or "?"
        log(string.format("WEATHER  %s (%s) — all tiles affected", d.event_type, sev_str))
    end)

    EventBus.subscribe("RESOURCE_DEPLETED", function(d)
        local reason = d.reason and (" [" .. d.reason .. "]") or ""
        log(string.format("DEPLETED %s in %s%s", d.resource, d.settlement_id, reason))
    end)

    EventBus.subscribe("FAMINE_STARTED", function(d)
        log(string.format("!! FAMINE in %s — pop %d, starvation > 4 weeks !!", d.settlement_id, d.population))
    end)

    EventBus.subscribe("REVOLT_STARTED", function(d)
        log(string.format("!! REVOLT in %s — morale %d, pop %d !!", d.settlement_id, d.morale, d.population))
    end)

    EventBus.subscribe("REVOLT_SPREAD", function(d)
        log(string.format("!! REVOLT SPREAD  %s → %s !!", d.from_id, d.to_id))
    end)
end

-- ============================================================
-- Inter-settlement grain sharing (basic trade buffer)
-- Simulates the informal charity / lord's obligation / market that prevents
-- total local collapse. Settlements with surplus share with desperate neighbours.
-- Phase 2 replaces this with explicit player trade decisions and prices paid.
-- ============================================================

local function setup_trade()
    EventBus.subscribe("WEEKLY_TICK", function(data)
        local season = data.season

        -- Only non-winter (roads passable enough for cart trade)
        if season == "Winter" then return end

        for _, settlement in ipairs(SETTLEMENTS) do
            local id     = settlement.id
            local stocks = ResourceManager.stocks[id]
            if not stocks then goto continue end

            -- A settlement shares grain if it has > 60 units AND neighbours have < 15
            -- Share up to 8 units per week total (limited by cart capacity)
            if stocks.Grain > 60 then
                for _, neighbour_id in ipairs(settlement.neighbours) do
                    local ns = ResourceManager.stocks[neighbour_id]
                    if ns and ns.Grain < 15 then
                        local share = math.min(8, math.floor((stocks.Grain - 60) / 2))
                        if share > 0 then
                            stocks.Grain = stocks.Grain - share
                            ns.Grain     = ns.Grain + share
                        end
                    end
                end
            end

            -- Emergency seed grain loan: if a neighbour can't plant (< 12 grain),
            -- and donor has > 40, donate exactly 12 (the minimum planting cost + buffer)
            if stocks.Grain > 40 and season == "Spring" then
                for _, neighbour_id in ipairs(settlement.neighbours) do
                    local ns = ResourceManager.stocks[neighbour_id]
                    if ns and ns.Grain < 12 then
                        local loan = math.min(12, stocks.Grain - 30)
                        if loan > 0 then
                            stocks.Grain = stocks.Grain - loan
                            ns.Grain     = ns.Grain + loan
                        end
                    end
                end
            end

            ::continue::
        end
    end)
end

-- ============================================================
-- Weekly report
-- ============================================================

local function print_weekly_report()
    local s = SeasonSubsystem.get_state()
    log(string.format("--- Weekly Report (Week %d, %s Y%d) ---", s.week, s.season, s.year))

    for _, settlement in ipairs(SETTLEMENTS) do
        local id = settlement.id
        local ps = PopulationSimulator.get_state(id)
        if ps then
            local grain  = ResourceManager.get_stock(id, "Grain")
            local fuel   = ResourceManager.get_stock(id, "Fuel")
            local prices = EconomySubsystem.get_price_snapshot(id)

            local status = "OK"
            if ps.in_revolt then status = "REVOLT" end
            if ps.famine_active then status = "FAMINE" end

            log(string.format(
                "  %-12s | pop %3d | morale %3d | grain %4.0f | fuel %3.0f | grain_price %.1f | [%s]",
                id,
                math.floor(ps.population),
                math.floor(ps.morale),
                grain,
                fuel,
                prices.Grain or 0,
                status
            ))
        end
    end

    -- Show ecology tile biomass
    local tile_line = "  Biomass:"
    for _, settlement in ipairs(SETTLEMENTS) do
        local tile = EcologySimulator.get_tile(settlement.id)
        if tile then
            tile_line = tile_line .. string.format(" %s=%.0f", settlement.id, tile.biomass)
        end
    end
    log(tile_line)
end

-- ============================================================
-- Initialise all systems
-- ============================================================

local function init_world()
    math.randomseed(123456) -- deterministic seed for reproducibility

    -- Init systems
    SeasonSubsystem.init()
    EcologySimulator.init()
    ResourceManager.init()
    EconomySubsystem.init()
    PopulationSimulator.init()

    -- Register settlements
    for _, s in ipairs(SETTLEMENTS) do
        EcologySimulator.register_tile(s.id, s.biome)
        -- Pass population into init_stocks so harvest yield can scale correctly
        local stocks_with_pop = {}
        for k, v in pairs(s.init_stocks) do stocks_with_pop[k] = v end
        stocks_with_pop._population = s.population
        ResourceManager.register_settlement(s.id, stocks_with_pop)
        EconomySubsystem.register_settlement(s.id)
        PopulationSimulator.register_settlement(s.id, s.population, s.neighbours)
    end

    -- Wire up event logging
    setup_event_logging()
    -- Wire up basic inter-settlement trade
    setup_trade()

    -- Wire weekly report to weekly tick
    EventBus.subscribe("WEEKLY_TICK", function(data)
        print_weekly_report()
    end)

    log("World initialised. 4 settlements. Simulation starting in Spring.")
    log("Year cycle: 56 days (4 × 14-day seasons). Weekly ecology tick.")
end

-- ============================================================
-- Simulation loop
-- ============================================================

-- How many in-game years to simulate in headless mode
local SIM_YEARS   = 5
local TOTAL_DAYS  = 56 * SIM_YEARS
local current_day = 0
local sim_done    = false

-- Headless: run all days instantly (no Love2D frame budget required)
local function run_headless()
    init_world()
    log(string.format("Running %d-year headless simulation (%d days)...", SIM_YEARS, TOTAL_DAYS))

    for day = 1, TOTAL_DAYS do
        SeasonSubsystem.tick_day()
        current_day = day
    end

    log("=== Simulation complete ===")

    -- Final state summary
    log(string.format("Final state after %d years:", SIM_YEARS))
    for _, settlement in ipairs(SETTLEMENTS) do
        local id = settlement.id
        local ps = PopulationSimulator.get_state(id)
        if ps then
            log(string.format(
                "  %s: pop=%d morale=%d famine=%s revolt=%s",
                id,
                math.floor(ps.population),
                math.floor(ps.morale),
                tostring(ps.famine_active or false),
                tostring(ps.in_revolt or false)
            ))
        end
    end
end

-- ============================================================
-- Love2D entry points (ignored if running in plain Lua)
-- ============================================================

if love then
    -- Love2D mode: visual log viewer + stepped simulation

    local FONT_SIZE     = 13
    local font
    local scroll_offset = 0
    local step_mode     = false -- false = run full year on load; true = step by week
    local weeks_run     = 0

    function love.load()
        love.window.setTitle("TheGame — Phase 1 Headless Sim")
        love.window.setMode(1200, 800, { resizable = true })
        font = love.graphics.newFont(FONT_SIZE)
        love.graphics.setFont(font)

        init_world()

        if not step_mode then
            -- Run full simulation up-front; browse log afterwards
            log(string.format("Running %d-year simulation (%d days)...", SIM_YEARS, TOTAL_DAYS))
            for day = 1, TOTAL_DAYS do
                SeasonSubsystem.tick_day()
            end
            log("=== Simulation complete. Use ↑↓ or scroll to browse log. ===")
            sim_done = true
        end
    end

    function love.update(dt)
        if step_mode and not sim_done then
            -- Advance one week per frame in step mode (press SPACE to step)
        end
    end

    function love.keypressed(key)
        local _, wh = love.window.getMode()
        local line_h = FONT_SIZE + 2

        if key == "up" then scroll_offset = math.max(0, scroll_offset - 3) end
        if key == "down" then scroll_offset = scroll_offset + 3 end
        if key == "pageup" then scroll_offset = math.max(0, scroll_offset - 30) end
        if key == "pagedown" then scroll_offset = scroll_offset + 30 end
        if key == "end" then scroll_offset = math.max(0, #LOG - math.floor(wh / line_h)) end
        if key == "home" then scroll_offset = 0 end
        if key == "escape" then love.event.quit() end
    end

    function love.wheelmoved(x, y)
        scroll_offset = math.max(0, scroll_offset - y * 3)
    end

    function love.draw()
        local ww, wh = love.window.getMode()
        love.graphics.setBackgroundColor(0.08, 0.08, 0.10)
        love.graphics.setColor(0.85, 0.90, 0.80)

        local line_h  = FONT_SIZE + 2
        local max_vis = math.floor(wh / line_h)
        local start   = math.min(scroll_offset + 1, math.max(1, #LOG - max_vis + 1))

        for i = 0, max_vis - 1 do
            local idx  = start + i
            local line = LOG[idx]
            if not line then break end

            -- Colour-code by event type
            if line:find("REVOLT") then
                love.graphics.setColor(1.0, 0.3, 0.3)
            elseif line:find("FAMINE") then
                love.graphics.setColor(1.0, 0.6, 0.2)
            elseif line:find("SEASON CHANGE") then
                love.graphics.setColor(0.5, 0.9, 1.0)
            elseif line:find("WEATHER") then
                love.graphics.setColor(0.8, 0.8, 0.5)
            elseif line:find("DEPLETED") then
                love.graphics.setColor(1.0, 0.7, 0.4)
            elseif line:find("Weekly Report") then
                love.graphics.setColor(0.7, 1.0, 0.7)
            else
                love.graphics.setColor(0.85, 0.90, 0.80)
            end

            love.graphics.print(line, 8, i * line_h + 4)
        end

        -- Scroll position indicator
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.print(
            string.format("Lines %d/%d  |  ↑↓ PgUp PgDn Home End | ESC quit",
                start, #LOG),
            8, wh - 20
        )
    end
else
    -- Plain Lua mode: just run
    run_headless()
end

-- Setup error handler to raise errors in debugger if attached, otherwise use Love2D's default
local love_errorhandler = love.errorhandler

function love.errorhandler(msg)
    if lldebugger then
        error(msg, 2)
    else
        return love_errorhandler(msg)
    end
end
