-- Phase 3: Island Ecology Simulation
-- A self-sustaining world with no humans.
-- Run headless:  lua main.lua
-- Run visual:    love .
--
-- SPACE        pause / resume
-- UP / DOWN    simulation speed
-- L            toggle log
-- Q            quit

local IS_LOVE = type(love) == "table"

local EventBus = require("systems/event_bus")
local Seasons  = require("systems/seasons")
local Ecology  = require("systems/ecology")
local Fauna    = require("systems/fauna")

-- ── Simulation config ─────────────────────────────────────────────────────────
local SIM_YEARS = 20

-- ── Initialise ────────────────────────────────────────────────────────────────
local function start_simulation()
    EventBus.reset()
    math.randomseed(os.time())
    Seasons.init()
    Ecology.init()
    Fauna.init()
end

-- ── Shared log ────────────────────────────────────────────────────────────────
local LOG = {}
local function push_log(msg)
    table.insert(LOG, msg)
    if #LOG > 500 then table.remove(LOG, 1) end
end

-- ── Colour helpers ────────────────────────────────────────────────────────────
-- Returns an RGB colour for a zone based on its health (0..1)
local function zone_color(zone_id)
    local h = Ecology.get_health(zone_id)
    local zone = Ecology.get_zone(zone_id)
    local def  = Ecology.get_def(zone_id)

    -- Base colour per biome
    local base = {
        Mountain  = { 0.65, 0.62, 0.58 },
        Forest    = { 0.22, 0.52, 0.22 },
        Hills     = { 0.52, 0.62, 0.30 },
        Riverland = { 0.30, 0.55, 0.65 },
        Plains    = { 0.72, 0.76, 0.38 },
        Wetland   = { 0.28, 0.52, 0.45 },
        Coastal   = { 0.80, 0.74, 0.55 },
    }
    local c = base[def.biome] or { 0.5, 0.5, 0.5 }

    -- Darken when unhealthy, brighten when thriving
    local factor = 0.5 + h * 0.8
    return { c[1]*factor, c[2]*factor, c[3]*factor }
end

local function health_bar_color(h)
    if h > 0.75 then return { 0.30, 0.75, 0.30 }
    elseif h > 0.45 then return { 0.80, 0.72, 0.20 }
    else return { 0.80, 0.25, 0.20 } end
end

-- ── Love2D layout ─────────────────────────────────────────────────────────────
-- Zone positions on a schematic island map (centre of each node)
local ZONE_POS = {
    central_peaks   = { x=390, y=100 },
    highland_forest = { x=200, y=210 },
    interior_hills  = { x=560, y=220 },
    river_valleys   = { x=220, y=360 },
    coastal_plains  = { x=560, y=370 },
    wetlands        = { x=280, y=490 },
    coastal_margin  = { x=490, y=510 },
}

local CONNECTIONS = {
    { "central_peaks",   "highland_forest" },
    { "central_peaks",   "interior_hills"  },
    { "highland_forest", "interior_hills"  },
    { "highland_forest", "river_valleys"   },
    { "interior_hills",  "river_valleys"   },
    { "interior_hills",  "coastal_plains"  },
    { "river_valleys",   "wetlands"        },
    { "coastal_plains",  "coastal_margin"  },
    { "wetlands",        "coastal_margin"  },
}

local NODE_R = 44  -- zone circle radius

-- ── Love2D mode ───────────────────────────────────────────────────────────────
if IS_LOVE then

local sim_time  = 0
local sim_speed = 1.0
local paused    = false
local show_log  = true
local log_scroll = 0

function love.load()
    love.window.setTitle("Phase 3 — Island Ecology")
    love.window.setMode(1100, 620, { resizable = false })
    start_simulation()

    -- Wire log events
    EventBus.subscribe("SEASON_CHANGED", function(d)
        push_log(string.format("--- %s  Year %d ---", d.season, d.year))
    end)
    EventBus.subscribe("WEATHER_EVENT", function(d)
        push_log(string.format("  [weather] %s  sev=%d", d.event_type, d.severity))
    end)
    EventBus.subscribe("FAUNA_MIGRATION", function(d)
        push_log(string.format("  [migrate] %s  %s → %s  (%.1f)",
            d.category, d.from, d.to, d.amount))
    end)
end

function love.update(dt)
    if paused then return end
    sim_time = sim_time + dt * sim_speed
    while sim_time >= 1.0 do
        sim_time = sim_time - 1.0
        Seasons.tick_day()
    end
end

local function draw_bar(x, y, w, h, frac, col)
    love.graphics.setColor(0.18, 0.18, 0.18, 0.6)
    love.graphics.rectangle("fill", x, y, w, h, 2)
    love.graphics.setColor(col[1], col[2], col[3], 0.9)
    love.graphics.rectangle("fill", x, y, math.max(0, w * math.min(1, frac)), h, 2)
end

function love.draw()
    local W, H = 1100, 620
    local MAP_W = 720
    local LOG_X = MAP_W + 4

    -- Background
    love.graphics.setBackgroundColor(0.10, 0.13, 0.10)
    love.graphics.setColor(0.08, 0.12, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, MAP_W, H - 40)

    -- Season tint overlay on map
    local season = Seasons.get_season()
    local tints = {
        Spring = { 0.55, 0.80, 0.45, 0.08 },
        Summer = { 0.95, 0.90, 0.40, 0.07 },
        Autumn = { 0.85, 0.55, 0.20, 0.09 },
        Winter = { 0.70, 0.85, 1.00, 0.10 },
    }
    local t = tints[season] or { 1,1,1,0 }
    love.graphics.setColor(t[1], t[2], t[3], t[4])
    love.graphics.rectangle("fill", 0, 0, MAP_W, H - 40)

    -- Draw connections
    love.graphics.setColor(0.35, 0.42, 0.35, 0.5)
    love.graphics.setLineWidth(2)
    for _, conn in ipairs(CONNECTIONS) do
        local a = ZONE_POS[conn[1]]
        local b = ZONE_POS[conn[2]]
        love.graphics.line(a.x, a.y, b.x, b.y)
    end

    -- Draw zones
    for zone_id, pos in pairs(ZONE_POS) do
        local col = zone_color(zone_id)
        local h   = Ecology.get_health(zone_id)
        local zone = Ecology.get_zone(zone_id)
        local def  = Ecology.get_def(zone_id)
        local pop  = Fauna.get(zone_id)
        local cap  = { herbivore = 60, carnivore = 25 }  -- rough display cap

        -- Zone circle
        love.graphics.setColor(col[1], col[2], col[3], 1)
        love.graphics.circle("fill", pos.x, pos.y, NODE_R)
        love.graphics.setColor(0.60, 0.70, 0.55, 0.7)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", pos.x, pos.y, NODE_R)

        -- Zone name
        love.graphics.setColor(0.92, 0.92, 0.88, 1)
        local name = def.name
        love.graphics.print(name, pos.x - #name * 3.2, pos.y - NODE_R - 14, 0, 0.72)

        -- Biome label
        love.graphics.setColor(0.65, 0.80, 0.65, 0.85)
        love.graphics.print(def.biome, pos.x - #def.biome * 2.6, pos.y - 6, 0, 0.65)

        -- Mini stats inside circle
        love.graphics.setColor(0.90, 0.88, 0.75, 0.9)
        love.graphics.print(string.format("B:%.0f", zone.biomass), pos.x - 20, pos.y + 6, 0, 0.65)
        love.graphics.print(string.format("W:%.0f", zone.water_level), pos.x - 20, pos.y + 18, 0, 0.65)

        -- Health bar below node
        local bary = pos.y + NODE_R + 4
        draw_bar(pos.x - NODE_R, bary, NODE_R*2, 5, h, health_bar_color(h))

        -- Fauna dots above node
        if pop then
            local herb_frac = pop.herbivore / 70
            local carn_frac = pop.carnivore / 28
            love.graphics.setColor(0.40, 0.85, 0.40, 0.85)
            love.graphics.circle("fill", pos.x - 10, pos.y - NODE_R - 5, 3 + herb_frac * 5)
            love.graphics.setColor(0.85, 0.30, 0.30, 0.85)
            love.graphics.circle("fill", pos.x + 10, pos.y - NODE_R - 5, 2 + carn_frac * 4)
        end
    end

    -- Legend: fauna dots
    love.graphics.setColor(0.40, 0.85, 0.40, 0.85)
    love.graphics.circle("fill", 16, H - 30, 5)
    love.graphics.setColor(0.75, 0.85, 0.65, 0.85)
    love.graphics.print("herbivore", 24, H - 37, 0, 0.70)
    love.graphics.setColor(0.85, 0.30, 0.30, 0.85)
    love.graphics.circle("fill", 110, H - 30, 4)
    love.graphics.setColor(0.75, 0.85, 0.65, 0.85)
    love.graphics.print("carnivore", 118, H - 37, 0, 0.70)

    -- ── Right panel: log + zone stats ────────────────────────────────────────
    love.graphics.setColor(0.10, 0.14, 0.10, 0.94)
    love.graphics.rectangle("fill", LOG_X, 0, W - LOG_X, H - 40)
    love.graphics.setColor(0.30, 0.48, 0.28, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", LOG_X, 0, W - LOG_X, H - 40)

    love.graphics.setColor(0.55, 0.82, 0.45, 1)
    love.graphics.print("ZONE STATUS", LOG_X + 8, 8, 0, 0.80)

    local zy = 28
    local function zone_stat_row(zone_id)
        local zone = Ecology.get_zone(zone_id)
        local def  = Ecology.get_def(zone_id)
        local pop  = Fauna.get(zone_id)
        local h    = Ecology.get_health(zone_id)
        local hc   = health_bar_color(h)

        love.graphics.setColor(hc[1], hc[2], hc[3], 1)
        love.graphics.print(def.name, LOG_X + 8, zy, 0, 0.68)
        love.graphics.setColor(0.72, 0.80, 0.65, 0.85)
        local s = string.format("  B:%-4.0f W:%-4.0f H:%-3.0f C:%-3.0f",
            zone.biomass, zone.water_level,
            pop and pop.herbivore or 0,
            pop and pop.carnivore or 0)
        love.graphics.print(s, LOG_X + 8, zy + 11, 0, 0.62)
        zy = zy + 26
    end

    for _, id in ipairs(Ecology.all_zone_ids()) do
        zone_stat_row(id)
    end

    -- Divider
    zy = zy + 4
    love.graphics.setColor(0.30, 0.48, 0.28, 0.4)
    love.graphics.line(LOG_X + 4, zy, W - 4, zy)
    zy = zy + 6

    -- Event log
    love.graphics.setColor(0.50, 0.72, 0.42, 1)
    love.graphics.print("EVENT LOG", LOG_X + 8, zy, 0, 0.72)
    zy = zy + 14

    local line_h = 12
    local max_vis = math.floor((H - 40 - zy - 4) / line_h)
    local start_i = math.max(1, #LOG - max_vis - log_scroll + 1)
    local end_i   = math.min(#LOG, start_i + max_vis - 1)

    love.graphics.setScissor(LOG_X, zy, W - LOG_X, H - 40 - zy)
    for i = start_i, end_i do
        local line = LOG[i]
        local col = { 0.65, 0.78, 0.58, 1 }
        if line:find("^%-%-%-") then col = { 0.45, 0.75, 0.90, 1 }
        elseif line:find("weather") then col = { 0.90, 0.82, 0.35, 1 }
        elseif line:find("migrate") then col = { 0.72, 0.55, 0.88, 1 }
        end
        love.graphics.setColor(col[1], col[2], col[3], col[4])
        love.graphics.print(line, LOG_X + 6, zy + (i - start_i) * line_h, 0, 0.65)
    end
    love.graphics.setScissor()

    -- ── Status bar ────────────────────────────────────────────────────────────
    love.graphics.setColor(0.08, 0.12, 0.08, 0.95)
    love.graphics.rectangle("fill", 0, H - 40, W, 40)
    love.graphics.setColor(0.55, 0.80, 0.45, 1)
    local ss = Seasons.get_state()
    local bar = string.format(
        "  Year %-3d  Week %-2d  %-6s  |  speed: %.1fx  |  SPACE=pause  UP/DOWN=speed  L=log  Q=quit%s",
        ss.year, ss.week, ss.season, sim_speed,
        paused and "  [PAUSED]" or "")
    love.graphics.print(bar, 4, H - 28, 0, 0.78)
end

function love.keypressed(key)
    if key == "space" then paused = not paused end
    if key == "up"    then sim_speed = math.min(16.0, sim_speed * 1.5) end
    if key == "down"  then sim_speed = math.max(0.1,  sim_speed / 1.5) end
    if key == "l"     then show_log = not show_log end
    if key == "q" or key == "escape" then love.event.quit() end
end

function love.wheelmoved(x, y)
    log_scroll = math.max(0, log_scroll - y * 3)
end

end -- IS_LOVE

-- ── Headless mode ─────────────────────────────────────────────────────────────
if IS_LOVE then return end

start_simulation()

EventBus.subscribe("SEASON_CHANGED", function(d)
    print(string.format("\n--- %s  Year %d ---", d.season, d.year))
end)
EventBus.subscribe("WEATHER_EVENT", function(d)
    print(string.format("  [weather] %-14s sev=%d", d.event_type, d.severity))
end)
EventBus.subscribe("FAUNA_MIGRATION", function(d)
    print(string.format("  [migrate] %-10s %s → %s  (%.1f)", d.category, d.from, d.to, d.amount))
end)

for day = 1, SIM_YEARS * 56 do
    Seasons.tick_day()
end

-- Final report
print("\n" .. string.rep("=", 70))
print(string.format("Island ecology after %d years:", SIM_YEARS))
print(string.format("%-20s  %-9s  %5s  %5s  %5s  %6s  %6s",
    "Zone", "Biome", "Biom.", "Water", "Soil", "Herb.", "Carn."))
print(string.rep("-", 70))
for _, id in ipairs(Ecology.all_zone_ids()) do
    local z = Ecology.get_zone(id)
    local d = Ecology.get_def(id)
    local p = Fauna.get(id)
    print(string.format("%-20s  %-9s  %5.1f  %5.1f  %5.1f  %6.1f  %6.1f",
        d.name, d.biome,
        z.biomass, z.water_level, z.soil_fertility,
        p and p.herbivore or 0,
        p and p.carnivore or 0))
end
