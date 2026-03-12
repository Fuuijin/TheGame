-- Phase 2: Entity Simulation
-- Run headless:  lua main.lua
-- Run visual:    love .
--
-- MENU          +/- buttons to tune parameters, then START
-- SPACE         pause / resume
-- UP / DOWN     sim speed (0.1x .. 8x)
-- L             toggle log panel
-- M             toggle map labels
-- T             toggle tweak panel
-- Q             quit

local IS_LOVE = type(love) == "table"

-- ── Requires ──────────────────────────────────────────────────────────────────
local EventBus = require("systems/event_bus")
local SeasonSubsystem = require("systems/season_subsystem")
local EcologySimulator = require("systems/ecology_simulator")
local ResourceManager = require("systems/resource_manager")
local EconomySubsystem = require("systems/economy_subsystem")
local PopulationSimulator = require("systems/population_simulator")
local EntityManager = require("systems/entity_manager")
local SituationEngine = require("systems/situation_engine")
local ReputationSystem = require("systems/reputation_system")

-- ── Global CONFIG (read by systems at runtime) ────────────────────────────────
CONFIG = {
	scarcity_threshold = 2.5,
	surplus_threshold = 70,
	base_pass_chance = 0.28,
	prominence_decay = 0.5,
	predator_min_forage = 20,
}

-- ── Adjustable parameters with UI metadata ────────────────────────────────────
-- fmt_read: how to parse the display string back (not needed — we store numeric)
local PARAM_DEFS = {
	{ key = "sim_years", label = "Sim Years", min = 1, max = 30, step = 1, fmt = "%d" },
	{ key = "random_seed", label = "Random Seed", min = 1, max = 9999, step = 1, fmt = "%d" },
	{ key = "initial_speed", label = "Start Speed", min = 0.1, max = 8.0, step = 0.5, fmt = "%.1fx" },
	{ key = "scarcity_threshold", label = "Scarcity (wks)", min = 0.5, max = 6.0, step = 0.5, fmt = "%.1f" },
	{ key = "surplus_threshold", label = "Surplus (grain)", min = 30, max = 120, step = 5, fmt = "%d" },
	{ key = "base_pass_chance", label = "Gossip Chance", min = 0.05, max = 0.90, step = 0.05, fmt = "%.2f" },
	{ key = "prominence_decay", label = "Fame Decay/wk", min = 0.0, max = 3.0, step = 0.1, fmt = "%.1f" },
	{ key = "predator_min_forage", label = "Predator Trigger", min = 5, max = 50, step = 5, fmt = "%d" },
}

-- Tweak-panel subset (live during simulation)
local TWEAK_DEFS = {
	{ key = "scarcity_threshold", label = "Scarcity (wks)", min = 0.5, max = 6.0, step = 0.5, fmt = "%.1f" },
	{ key = "surplus_threshold", label = "Surplus (grain)", min = 30, max = 120, step = 5, fmt = "%d" },
	{ key = "base_pass_chance", label = "Gossip Chance", min = 0.05, max = 0.90, step = 0.05, fmt = "%.2f" },
	{ key = "prominence_decay", label = "Fame Decay/wk", min = 0.0, max = 3.0, step = 0.1, fmt = "%.1f" },
}

-- Starting values (menu editable)
local PARAMS = {
	sim_years = 8,
	random_seed = 42,
	initial_speed = 1.0,
	scarcity_threshold = 2.5,
	surplus_threshold = 70,
	base_pass_chance = 0.28,
	prominence_decay = 0.5,
	predator_min_forage = 20,
	settlements = {
		{ id = "Ashford", pop = 120, grain = 85 },
		{ id = "Millhaven", pop = 80, grain = 70 },
		{ id = "Brackenmere", pop = 60, grain = 60 },
		{ id = "Stonekeep", pop = 50, grain = 55 },
	},
}

-- ── Static world data ─────────────────────────────────────────────────────────
local NEIGHBOURS = {
	Ashford = { "Millhaven", "Brackenmere", "Stonekeep" },
	Millhaven = { "Ashford", "Stonekeep" },
	Brackenmere = { "Ashford" },
	Stonekeep = { "Ashford", "Millhaven" },
}

local SVIS = {
	Ashford = { x = 260, y = 250, w = 100, h = 58, biome = "Plains" },
	Millhaven = { x = 430, y = 90, w = 100, h = 58, biome = "Forest" },
	Brackenmere = { x = 75, y = 390, w = 100, h = 58, biome = "Wetland" },
	Stonekeep = { x = 380, y = 390, w = 100, h = 58, biome = "Upland" },
}

local ROADS = {
	{ "Ashford", "Millhaven" },
	{ "Ashford", "Brackenmere" },
	{ "Ashford", "Stonekeep" },
	{ "Millhaven", "Stonekeep" },
}

local SEASON_COLORS = {
	Spring = { 0.62, 0.82, 0.55, 0.18 },
	Summer = { 1.00, 0.95, 0.55, 0.15 },
	Autumn = { 0.88, 0.60, 0.25, 0.18 },
	Winter = { 0.75, 0.88, 1.00, 0.22 },
}

-- ── Setup helpers ─────────────────────────────────────────────────────────────
local function setup_entities()
	EntityManager.register({
		name = "Lord Edmund",
		settlement_id = "Ashford",
		role = "lord",
		traits = { "law_order", "greedy" },
		prominence = 75,
	})
	EntityManager.register({
		name = "Miller Agnes",
		settlement_id = "Ashford",
		role = "miller",
		traits = { "gossip", "compassionate" },
		prominence = 45,
	})
	EntityManager.register({
		name = "Blacksmith Hugh",
		settlement_id = "Ashford",
		role = "blacksmith",
		traits = { "brave", "cautious" },
		prominence = 40,
	})
	EntityManager.register({
		name = "Father Cormac",
		settlement_id = "Ashford",
		role = "priest",
		traits = { "compassionate", "discretion" },
		prominence = 50,
	})
	EntityManager.register({
		name = "Merchant Ida",
		settlement_id = "Ashford",
		role = "merchant",
		traits = { "greedy", "loudmouth" },
		prominence = 35,
	})
	EntityManager.register({
		name = "Headman Tomas",
		settlement_id = "Millhaven",
		role = "headman",
		traits = { "law_order", "cautious" },
		prominence = 60,
	})
	EntityManager.register({
		name = "Forester Bran",
		settlement_id = "Millhaven",
		role = "forester",
		traits = { "brave", "gentle" },
		prominence = 35,
	})
	EntityManager.register({
		name = "Herbalist Wren",
		settlement_id = "Millhaven",
		role = "herbalist",
		traits = { "compassionate", "discretion" },
		prominence = 30,
	})
	EntityManager.register({
		name = "Elder Marta",
		settlement_id = "Brackenmere",
		role = "elder",
		traits = { "gossip", "gentle" },
		prominence = 55,
	})
	EntityManager.register({
		name = "Boatman Piers",
		settlement_id = "Brackenmere",
		role = "boatman",
		traits = { "impulsive", "brave" },
		prominence = 25,
	})
	EntityManager.register({
		name = "Trader Odo",
		settlement_id = "Brackenmere",
		role = "trader",
		traits = { "greedy", "loudmouth" },
		prominence = 30,
	})
	EntityManager.register({
		name = "Steward Aldric",
		settlement_id = "Stonekeep",
		role = "steward",
		traits = { "law_order", "cautious" },
		prominence = 55,
	})
	EntityManager.register({
		name = "Shepherd Nell",
		settlement_id = "Stonekeep",
		role = "shepherd",
		traits = { "gentle", "compassionate" },
		prominence = 20,
	})
	EntityManager.register({
		name = "Watchman Garrett",
		settlement_id = "Stonekeep",
		role = "watchman",
		traits = { "brave", "impulsive" },
		prominence = 25,
	})
end

local function setup_world(params)
	for _, s in ipairs(params.settlements) do
		EcologySimulator.register_tile(s.id, (SVIS[s.id] or {}).biome or "Plains")
		local stocks = { Livestock = 40, Timber = 50, Fuel = 70, Salt = 18, Water = 80, Forage = 35 }
		stocks.Grain = s.grain
		stocks._population = s.pop
		ResourceManager.register_settlement(s.id, stocks)
		EconomySubsystem.register_settlement(s.id)
		PopulationSimulator.register_settlement(s.id, s.pop, NEIGHBOURS[s.id] or {})
	end
end

local function setup_trade()
	EventBus.subscribe("WEEKLY_TICK", function(data)
		if data.season == "Winter" then
			return
		end
		for sid, neighbours in pairs(NEIGHBOURS) do
			local stocks = ResourceManager.stocks[sid]
			if stocks and stocks.Grain > 60 then
				for _, nsid in ipairs(neighbours) do
					-- Re-read donor grain each iteration so we can't over-donate
					local grain  = stocks.Grain
					if grain <= 60 then break end
					local ngrain = (ResourceManager.stocks[nsid] or {}).Grain or 0
					if ngrain < 15 then
						local share = math.min(8, grain - 60)
						stocks.Grain = grain - share
						ResourceManager.stocks[nsid].Grain = ngrain + share
					end
				end
			end
		end
	end)
end

local function setup_new_systems()
	local deps = {
		EntityManager = EntityManager,
		ReputationSystem = ReputationSystem,
		EventBus = EventBus,
		ResourceManager = ResourceManager,
		PopulationSimulator = PopulationSimulator,
		EcologySimulator = EcologySimulator,
		NEIGHBOURS = NEIGHBOURS,
	}
	SituationEngine.init(deps)
	ReputationSystem.init(deps)
	EventBus.subscribe("WEEKLY_TICK", function(data)
		SituationEngine.weekly_tick(data.week, data.year, data.season)
	end)
end

-- ── Shared log ────────────────────────────────────────────────────────────────
local ALL_LOG = {}
local function push_log(msg)
	table.insert(ALL_LOG, msg)
	if #ALL_LOG > 400 then
		table.remove(ALL_LOG, 1)
	end
end

-- ── Colour helpers ────────────────────────────────────────────────────────────
local function settlement_color(sid)
	local ps = PopulationSimulator.pop_state[sid]
	if not ps then
		return { 0.6, 0.6, 0.6 }
	end
	if ps.in_revolt then
		return { 0.76, 0.18, 0.18 }
	end
	if ps.famine_active then
		return { 0.80, 0.39, 0.10 }
	end
	local grain = (ResourceManager.stocks[sid] or {}).Grain or 0
	local wg = 99
	if ps.population > 0 then
		wg = grain / (8 * (ps.population / 100))
	end
	if wg < 1.5 then
		return { 0.78, 0.64, 0.12 }
	end
	if wg < 3.0 then
		return { 0.65, 0.72, 0.30 }
	end
	return { 0.40, 0.68, 0.38 }
end

local function entity_color(entity)
	if entity.last_event_time < 2.0 then
		return { 1.0, 0.88, 0.1, 1.0 }          -- flash yellow: recent event
	end
	if entity.infamy > 15 then
		return { 0.80, 0.22, 0.22 }              -- red: notorious
	end
	if entity.honour > 20 and entity.prominence > 55 then
		return { 0.85, 0.70, 0.15 }              -- gold: honoured and famous
	end
	if entity.prominence > 40 then
		return { 0.28, 0.52, 0.78 }              -- blue: named
	end
	if entity.prominence > 20 then
		return { 0.30, 0.42, 0.55 }              -- slate blue: emerging
	end
	return { 0.28, 0.22, 0.14 }                  -- dark brown: anonymous (visible on parchment)
end

local function entity_radius(entity)
	return math.max(4, math.min(10, 4 + math.floor(entity.prominence / 14)))
end

-- ── Love2D (all state and callbacks wrapped so headless Lua ignores them) ──────

-- ── State ─────────────────────────────────────────────────────────────────────
local GAME_STATE = "menu" -- "menu" | "running"
local sim_time = 0
local sim_speed = 1.0
local SIM_YEARS = 8
local paused = false
local show_labels = true
local show_log = true
local show_tweak = false
local log_scroll = 0

-- ── Simple UI hit-test ────────────────────────────────────────────────────────
local UI_HITS = {}
local mx, my = 0, 0

local function ui_clear()
	UI_HITS = {}
end

local function ui_btn(x, y, w, h, label, cb, accent)
	table.insert(UI_HITS, { x = x, y = y, w = w, h = h, cb = cb })
	local hover = mx >= x and mx <= x + w and my >= y and my <= y + h
	if accent then
		love.graphics.setColor(hover and 0.55 or 0.38, hover and 0.45 or 0.30, hover and 0.18 or 0.10, 1)
	else
		love.graphics.setColor(hover and 0.55 or 0.32, hover and 0.44 or 0.24, hover and 0.22 or 0.12, 1)
	end
	love.graphics.rectangle("fill", x, y, w, h, 3)
	love.graphics.setColor(0.72, 0.58, 0.30, 1)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, 3)
	love.graphics.setColor(0.96, 0.90, 0.72, 1)
	-- centre label manually
	local lw = #label * 6 * 0.78
	love.graphics.print(label, x + (w - lw) / 2, y + h / 2 - 6, 0, 0.78)
end

local function ui_hit_check(px, py)
	for _, hit in ipairs(UI_HITS) do
		if px >= hit.x and px <= hit.x + hit.w and py >= hit.y and py <= hit.y + hit.h then
			if hit.cb then
				hit.cb()
			end
			return true
		end
	end
	return false
end

-- ── Parameter row helper ──────────────────────────────────────────────────────
-- Draws  [Label]  [value]  [-]  [+]  at (x,y), reads/writes into tbl[key]
local function param_row(x, y, def, tbl)
	love.graphics.setColor(0.82, 0.74, 0.52, 1)
	love.graphics.print(def.label, x, y, 0, 0.80)
	local valstr = string.format(def.fmt, tbl[def.key])
	love.graphics.setColor(0.96, 0.90, 0.70, 1)
	love.graphics.print(valstr, x + 170, y, 0, 0.80)

	local bx = x + 218
	ui_btn(bx, y - 1, 20, 17, "-", function()
		tbl[def.key] = math.max(def.min, tbl[def.key] - def.step)
		-- snap float precision
		tbl[def.key] = math.floor(tbl[def.key] / def.step + 0.5) * def.step
	end)
	ui_btn(bx + 22, y - 1, 20, 17, "+", function()
		tbl[def.key] = math.min(def.max, tbl[def.key] + def.step)
		tbl[def.key] = math.floor(tbl[def.key] / def.step + 0.5) * def.step
	end)
end

-- ── Start simulation ──────────────────────────────────────────────────────────
local function start_simulation()
	-- Clear all event subscriptions so re-running doesn't double-fire every handler
	EventBus.reset()

	-- Apply params to CONFIG
	CONFIG.scarcity_threshold = PARAMS.scarcity_threshold
	CONFIG.surplus_threshold = PARAMS.surplus_threshold
	CONFIG.base_pass_chance = PARAMS.base_pass_chance
	CONFIG.prominence_decay = PARAMS.prominence_decay
	CONFIG.predator_min_forage = PARAMS.predator_min_forage

	SIM_YEARS = PARAMS.sim_years
	sim_speed = PARAMS.initial_speed
	math.randomseed(PARAMS.random_seed)

	SeasonSubsystem.init()
	EcologySimulator.init()
	ResourceManager.init()
	EconomySubsystem.init()
	PopulationSimulator.init()
	setup_world(PARAMS)
	setup_entities()
	setup_trade()
	setup_new_systems()

	-- Wire event log
	EventBus.subscribe("SITUATION_FIRED", function(d)
		push_log(string.format("[Y%d W%02d %s] %s in %s", d.year, d.week, d.season, d.situation_type, d.settlement_id))
	end)
	EventBus.subscribe("PROMINENCE_CHANGED", function(d)
		local e = EntityManager.get_by_id(d.entity_id)
		if e then
			push_log(string.format("  >> %s prominence %d→%d (%s)", e.name, d.old_val, d.new_val, d.reason))
		end
	end)
	EventBus.subscribe("FAMINE_STARTED", function(d)
		push_log("!! FAMINE in " .. d.settlement_id)
	end)
	EventBus.subscribe("REVOLT_STARTED", function(d)
		push_log("!! REVOLT in " .. d.settlement_id)
	end)
	EventBus.subscribe("WEATHER_EVENT", function(d)
		push_log(string.format("  weather: %s sev=%d", d.event_type, d.severity))
	end)
	EventBus.subscribe("SEASON_CHANGED", function(d)
		push_log(string.format("--- %s  Year %d ---", d.season, d.year))
	end)

	GAME_STATE = "running"
end

-- ── Draw: menu ────────────────────────────────────────────────────────────────
local function draw_menu()
	local W, H = 1110, 620

	-- Background
	love.graphics.setBackgroundColor(0.16, 0.12, 0.07)
	love.graphics.setColor(0.88, 0.80, 0.60, 1)
	love.graphics.rectangle("fill", 30, 20, W - 60, H - 40, 8)
	love.graphics.setColor(0.60, 0.46, 0.22, 1)
	love.graphics.setLineWidth(2)
	love.graphics.rectangle("line", 30, 20, W - 60, H - 40, 8)

	-- Title
	love.graphics.setColor(0.24, 0.16, 0.06, 1)
	love.graphics.print("ENTITY SIMULATION — Phase 2", 50, 36, 0, 1.3)
	love.graphics.setColor(0.48, 0.36, 0.16, 1)
	love.graphics.print("Tune starting parameters, then press START", 52, 72, 0, 0.82)

	-- Divider
	love.graphics.setColor(0.58, 0.44, 0.20, 0.6)
	love.graphics.line(50, 92, W - 50, 92)

	-- ── Left panel: simulation params ─────────────────────────────────────────
	love.graphics.setColor(0.35, 0.26, 0.10, 0.25)
	love.graphics.rectangle("fill", 50, 100, 480, 260, 5)
	love.graphics.setColor(0.55, 0.42, 0.18, 0.6)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", 50, 100, 480, 260, 5)

	love.graphics.setColor(0.70, 0.54, 0.24, 1)
	love.graphics.print("SIMULATION PARAMETERS", 62, 108, 0, 0.82)

	for i, def in ipairs(PARAM_DEFS) do
		param_row(62, 128 + (i - 1) * 28, def, PARAMS)
	end

	-- ── Right panel: settlement starting stocks ────────────────────────────────
	love.graphics.setColor(0.35, 0.26, 0.10, 0.25)
	love.graphics.rectangle("fill", 570, 100, 490, 260, 5)
	love.graphics.setColor(0.55, 0.42, 0.18, 0.6)
	love.graphics.rectangle("line", 570, 100, 490, 260, 5)

	love.graphics.setColor(0.70, 0.54, 0.24, 1)
	love.graphics.print("STARTING CONDITIONS PER SETTLEMENT", 582, 108, 0, 0.82)

	-- Column headers
	love.graphics.setColor(0.55, 0.44, 0.26, 1)
	love.graphics.print("Settlement", 582, 128, 0, 0.75)
	love.graphics.print("Population", 720, 128, 0, 0.75)
	love.graphics.print("Grain", 860, 128, 0, 0.75)

	local pop_def = { key = "pop", min = 10, max = 300, step = 10, fmt = "%d" }
	local grain_def = { key = "grain", min = 10, max = 150, step = 5, fmt = "%d" }

	for i, s in ipairs(PARAMS.settlements) do
		local ry = 146 + (i - 1) * 46
		-- Settlement name badge
		love.graphics.setColor(0.38, 0.28, 0.12, 0.5)
		love.graphics.rectangle("fill", 582, ry - 2, 120, 34, 4)
		love.graphics.setColor(0.96, 0.88, 0.68, 1)
		love.graphics.print(s.id, 590, ry + 4, 0, 0.82)

		-- Pop control
		local valP = string.format("%d", s.pop)
		love.graphics.setColor(0.96, 0.90, 0.70, 1)
		love.graphics.print(valP, 728, ry + 4, 0, 0.80)
		ui_btn(760, ry + 2, 20, 18, "-", function()
			s.pop = math.max(pop_def.min, s.pop - pop_def.step)
		end)
		ui_btn(782, ry + 2, 20, 18, "+", function()
			s.pop = math.min(pop_def.max, s.pop + pop_def.step)
		end)

		-- Grain control
		local valG = string.format("%d", s.grain)
		love.graphics.print(valG, 862, ry + 4, 0, 0.80)
		ui_btn(898, ry + 2, 20, 18, "-", function()
			s.grain = math.max(grain_def.min, s.grain - grain_def.step)
		end)
		ui_btn(920, ry + 2, 20, 18, "+", function()
			s.grain = math.min(grain_def.max, s.grain + grain_def.step)
		end)
	end

	-- ── Seed hint ─────────────────────────────────────────────────────────────
	love.graphics.setColor(0.50, 0.40, 0.20, 0.85)
	love.graphics.print("Tip: change the random seed to see different emergent histories", 52, 374, 0, 0.76)

	-- ── Entity roster preview ─────────────────────────────────────────────────
	love.graphics.setColor(0.35, 0.26, 0.10, 0.20)
	love.graphics.rectangle("fill", 50, 395, 1010, 155, 5)
	love.graphics.setColor(0.55, 0.42, 0.18, 0.5)
	love.graphics.rectangle("line", 50, 395, 1010, 155, 5)

	love.graphics.setColor(0.70, 0.54, 0.24, 1)
	love.graphics.print("NAMED ENTITIES (fixed)", 62, 403, 0, 0.82)

	local roster = {
		{ "Lord Edmund", "Ashford", "lord", "law_order · greedy" },
		{ "Miller Agnes", "Ashford", "miller", "gossip · compassionate" },
		{ "Blacksmith Hugh", "Ashford", "blacksmith", "brave · cautious" },
		{ "Father Cormac", "Ashford", "priest", "compassionate · discretion" },
		{ "Merchant Ida", "Ashford", "merchant", "greedy · loudmouth" },
		{ "Headman Tomas", "Millhaven", "headman", "law_order · cautious" },
		{ "Forester Bran", "Millhaven", "forester", "brave · gentle" },
		{ "Herbalist Wren", "Millhaven", "herbalist", "compassionate · discretion" },
		{ "Elder Marta", "Brackenmere", "elder", "gossip · gentle" },
		{ "Boatman Piers", "Brackenmere", "boatman", "impulsive · brave" },
		{ "Trader Odo", "Brackenmere", "trader", "greedy · loudmouth" },
		{ "Steward Aldric", "Stonekeep", "steward", "law_order · cautious" },
		{ "Shepherd Nell", "Stonekeep", "shepherd", "gentle · compassionate" },
		{ "Watchman Garrett", "Stonekeep", "watchman", "brave · impulsive" },
	}
	local cols = 4
	for idx, r in ipairs(roster) do
		local col = (idx - 1) % cols
		local row = math.floor((idx - 1) / cols)
		local rx = 62 + col * 254
		local ry = 420 + row * 42
		love.graphics.setColor(0.32, 0.24, 0.10, 0.45)
		love.graphics.rectangle("fill", rx - 4, ry - 2, 248, 36, 3)
		love.graphics.setColor(0.90, 0.82, 0.60, 1)
		love.graphics.print(r[1], rx, ry, 0, 0.80)
		love.graphics.setColor(0.65, 0.55, 0.35, 1)
		love.graphics.print(r[2] .. " · " .. r[3], rx, ry + 14, 0, 0.68)
		love.graphics.setColor(0.55, 0.72, 0.88, 1)
		love.graphics.print(r[4], rx, ry + 26, 0, 0.62)
	end

	-- ── START button ──────────────────────────────────────────────────────────
	ui_btn(430, 563, 250, 42, "START SIMULATION", start_simulation, true)
end

-- ── Draw: summary ────────────────────────────────────────────────────────────
local function draw_summary()
    local W, H = 1110, 620
    love.graphics.setBackgroundColor(0.10, 0.08, 0.05)
    love.graphics.setColor(0.86, 0.78, 0.58, 1)
    love.graphics.rectangle("fill", 30, 18, W-60, H-36, 8)
    love.graphics.setColor(0.55, 0.42, 0.18, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 30, 18, W-60, H-36, 8)

    -- Title
    love.graphics.setColor(0.22, 0.15, 0.05, 1)
    love.graphics.print(string.format("END OF YEAR %d  —  WORLD SUMMARY", SIM_YEARS), 50, 30, 0, 1.15)
    love.graphics.setColor(0.50, 0.38, 0.16, 0.8)
    love.graphics.line(50, 58, W-50, 58)

    -- ── Left: settlements ─────────────────────────────────────────────────────
    love.graphics.setColor(0.35, 0.26, 0.10, 0.22)
    love.graphics.rectangle("fill", 48, 65, 310, 490, 5)
    love.graphics.setColor(0.55, 0.42, 0.18, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", 48, 65, 310, 490, 5)
    love.graphics.setColor(0.68, 0.52, 0.22, 1)
    love.graphics.print("SETTLEMENTS", 60, 73, 0, 0.82)

    local sy = 94
    for _, s in ipairs(PARAMS.settlements) do
        local sid = s.id
        local ps  = PopulationSimulator.pop_state[sid]
        local col = settlement_color(sid)
        -- colour badge
        love.graphics.setColor(col[1], col[2], col[3], 0.85)
        love.graphics.rectangle("fill", 60, sy, 286, 88, 5)
        love.graphics.setColor(0.18, 0.12, 0.05, 0.6)
        love.graphics.rectangle("line", 60, sy, 286, 88, 5)

        love.graphics.setColor(0.10, 0.06, 0.02, 1)
        love.graphics.print(sid, 70, sy+6, 0, 0.90)
        if ps then
            local grain = (ResourceManager.stocks[sid] or {}).Grain or 0
            local status = ps.in_revolt and "REVOLT" or ps.famine_active and "FAMINE" or "stable"
            love.graphics.setColor(0.14, 0.09, 0.03, 0.9)
            love.graphics.print(string.format("Population : %d", ps.population),   70, sy+24, 0, 0.78)
            love.graphics.print(string.format("Morale     : %d", math.floor(ps.morale)), 70, sy+38, 0, 0.78)
            love.graphics.print(string.format("Grain      : %.0f", grain),          70, sy+52, 0, 0.78)
            love.graphics.print(string.format("Status     : %s", status),           70, sy+66, 0, 0.78)
        end
        sy = sy + 104
    end

    -- ── Middle: entity roll of honour ─────────────────────────────────────────
    love.graphics.setColor(0.35, 0.26, 0.10, 0.22)
    love.graphics.rectangle("fill", 370, 65, 380, 490, 5)
    love.graphics.setColor(0.55, 0.42, 0.18, 0.5)
    love.graphics.rectangle("line", 370, 65, 380, 490, 5)
    love.graphics.setColor(0.68, 0.52, 0.22, 1)
    love.graphics.print("NAMED ENTITIES", 382, 73, 0, 0.82)

    -- Sort: by prominence desc
    local sorted = {}
    for _, e in ipairs(EntityManager.entities) do table.insert(sorted, e) end
    table.sort(sorted, function(a, b) return a.prominence > b.prominence end)

    local ey = 94
    for _, e in ipairs(sorted) do
        if ey > 530 then break end
        local c = entity_color(e)
        love.graphics.setColor(c[1], c[2], c[3] or 1, 0.22)
        love.graphics.rectangle("fill", 378, ey-1, 364, 28, 3)
        love.graphics.setColor(c[1], c[2], c[3] or 1, 1)
        love.graphics.circle("fill", 390, ey+10, 5)
        love.graphics.setColor(0.12, 0.08, 0.02, 1)
        -- name + settlement
        love.graphics.print(string.format("%-18s %s", e.name, e.settlement_id), 400, ey+2, 0, 0.75)
        -- stats line
        local nt = e.narrative_traits[#e.narrative_traits]
        local nt_str = nt and ("["..nt.name.."]") or ""
        love.graphics.setColor(0.28, 0.20, 0.08, 0.9)
        love.graphics.print(string.format("p=%-3d hon=%-3d inf=%-3d  %s", e.prominence, e.honour, e.infamy, nt_str),
            400, ey+14, 0, 0.68)
        ey = ey + 32
    end

    -- ── Right: simulation stats + story highlights ────────────────────────────
    love.graphics.setColor(0.35, 0.26, 0.10, 0.22)
    love.graphics.rectangle("fill", 762, 65, 316, 490, 5)
    love.graphics.setColor(0.55, 0.42, 0.18, 0.5)
    love.graphics.rectangle("line", 762, 65, 316, 490, 5)
    love.graphics.setColor(0.68, 0.52, 0.22, 1)
    love.graphics.print("SIMULATION STATS", 774, 73, 0, 0.82)

    local sx = 774
    local ssy = 96
    local function stat(label, val)
        love.graphics.setColor(0.60, 0.48, 0.28, 1)
        love.graphics.print(label, sx, ssy, 0, 0.78)
        love.graphics.setColor(0.18, 0.12, 0.04, 1)
        love.graphics.print(tostring(val), sx+190, ssy, 0, 0.78)
        ssy = ssy + 22
    end

    stat("Years simulated",    SIM_YEARS)
    stat("Reputation events",  #ReputationSystem.events)
    stat("Narrative payloads", #ReputationSystem.narrative_payloads)
    stat("Random seed",        PARAMS.random_seed)
    ssy = ssy + 8
    love.graphics.setColor(0.50, 0.38, 0.18, 0.5)
    love.graphics.line(sx, ssy, sx+300, ssy)
    ssy = ssy + 12

    -- Standout characters
    love.graphics.setColor(0.68, 0.52, 0.22, 1)
    love.graphics.print("STANDOUTS", sx, ssy, 0, 0.82)
    ssy = ssy + 18

    local most_hon  = sorted[1]  -- already sorted by prominence, find by honour too
    local most_inf, most_prom = nil, sorted[1]
    for _, e in ipairs(EntityManager.entities) do
        if not most_inf or e.infamy > most_inf.infamy then most_inf = e end
        if not most_hon or e.honour > most_hon.honour then most_hon = e end
    end

    local function standout(label, entity, field)
        if not entity or entity[field] == 0 then return end
        love.graphics.setColor(0.55, 0.44, 0.24, 1)
        love.graphics.print(label, sx, ssy, 0, 0.74)
        ssy = ssy + 14
        local c = entity_color(entity)
        love.graphics.setColor(c[1], c[2], c[3] or 1, 1)
        love.graphics.circle("fill", sx+8, ssy+6, 4)
        love.graphics.setColor(0.15, 0.10, 0.03, 1)
        love.graphics.print(string.format("%s  (%s=%d)", entity.name, field, entity[field]),
            sx+16, ssy, 0, 0.76)
        ssy = ssy + 20
    end

    standout("Most prominent:",  most_prom,  "prominence")
    standout("Most honourable:", most_hon,   "honour")
    standout("Most infamous:",   most_inf,   "infamy")

    ssy = ssy + 10
    love.graphics.setColor(0.50, 0.38, 0.18, 0.5)
    love.graphics.line(sx, ssy, sx+300, ssy)
    ssy = ssy + 12
    love.graphics.setColor(0.50, 0.40, 0.22, 0.85)
    love.graphics.print("Narrative payloads saved to:", sx, ssy, 0, 0.72)
    ssy = ssy + 14
    love.graphics.setColor(0.35, 0.55, 0.35, 1)
    love.graphics.print("narrative_payloads.txt", sx, ssy, 0, 0.72)

    -- Quit button
    ui_btn(430, 565, 250, 38, "QUIT  (Q)", function() love.event.quit() end, true)
end

-- ── Draw: simulation ──────────────────────────────────────────────────────────
local function draw_sim()
	local MAP_W = 700
	local LOG_X = MAP_W + 5
	local LOG_W = 400
	local H = 575
	local BAR_Y = H + 5

	love.graphics.setBackgroundColor(0.90, 0.84, 0.68)

	-- Season tint
	local sc = SEASON_COLORS[SeasonSubsystem.get_state().season] or { 1, 1, 1, 0 }
	love.graphics.setColor(sc[1], sc[2], sc[3], sc[4])
	love.graphics.rectangle("fill", 0, 0, MAP_W, H)

	-- Roads
	love.graphics.setColor(0.45, 0.32, 0.18, 0.55)
	love.graphics.setLineWidth(2)
	for _, road in ipairs(ROADS) do
		local a, b = SVIS[road[1]], SVIS[road[2]]
		love.graphics.line(a.x + a.w / 2, a.y + a.h / 2, b.x + b.w / 2, b.y + b.h / 2)
	end

	-- Settlements
	for sid, pos in pairs(SVIS) do
		local col = settlement_color(sid)
		love.graphics.setColor(col[1], col[2], col[3], 1)
		love.graphics.rectangle("fill", pos.x, pos.y, pos.w, pos.h, 6)
		love.graphics.setColor(0.20, 0.14, 0.08, 0.9)
		love.graphics.setLineWidth(2)
		love.graphics.rectangle("line", pos.x, pos.y, pos.w, pos.h, 6)
		if show_labels then
			love.graphics.setColor(0.08, 0.05, 0.02, 1)
			love.graphics.print(sid, pos.x + 6, pos.y + 5, 0, 0.85)
			local ps = PopulationSimulator.pop_state[sid]
			if ps then
				love.graphics.setColor(0.15, 0.10, 0.04, 0.9)
				love.graphics.print(
					string.format("pop %d  mor %d", ps.population, math.floor(ps.morale)),
					pos.x + 6,
					pos.y + 20,
					0,
					0.72
				)
				local grain = (ResourceManager.stocks[sid] or {}).Grain or 0
				love.graphics.print(string.format("grain %.0f", grain), pos.x + 6, pos.y + 34, 0, 0.72)
			end
			love.graphics.setColor(0.25, 0.18, 0.08, 0.7)
			love.graphics.print(pos.biome, pos.x + 6, pos.y + 46, 0, 0.65)
		end
	end

	-- Entity dots
	for i, entity in ipairs(EntityManager.entities) do
		local pos = SVIS[entity.settlement_id]
		if pos then
			local angle = (i * 2.399) % (2 * math.pi)
			local radius = 52 + (i % 4) * 10
			local ex = pos.x + pos.w / 2 + math.cos(angle) * radius
			local ey = pos.y + pos.h / 2 + math.sin(angle) * radius
			local r = entity_radius(entity)
			local c = entity_color(entity)
			if entity.prominence > 40 then
				love.graphics.setColor(c[1], c[2], c[3] or 1, 0.25)
				love.graphics.circle("fill", ex, ey, r + 5)
			end
			love.graphics.setColor(c[1], c[2], c[3] or 1, c[4] or 1)
			love.graphics.circle("fill", ex, ey, r)
			love.graphics.setColor(0.1, 0.1, 0.1, 0.7)
			love.graphics.setLineWidth(1)
			love.graphics.circle("line", ex, ey, r)
			if show_labels and entity.prominence > 25 then
				love.graphics.setColor(0.08, 0.05, 0.02, 0.9)
				love.graphics.print(entity.name, ex + r + 2, ey - 7, 0, 0.62)
			end
		end
	end

	-- Log panel
	if show_log then
		love.graphics.setColor(0.22, 0.18, 0.11, 0.88)
		love.graphics.rectangle("fill", LOG_X, 0, LOG_W, H, 4)
		love.graphics.setColor(0.45, 0.35, 0.18, 1)
		love.graphics.setLineWidth(1)
		love.graphics.rectangle("line", LOG_X, 0, LOG_W, H, 4)

		love.graphics.setColor(0.85, 0.75, 0.50, 1)
		love.graphics.print("ENTITIES", LOG_X + 8, 6, 0, 0.85)
		local ey_off = 22
		for _, entity in ipairs(EntityManager.entities) do
			if ey_off > 195 then
				break
			end
			local col = entity_color(entity)
			love.graphics.setColor(col[1], col[2], col[3] or 1, 1)
			love.graphics.circle("fill", LOG_X + 10, ey_off + 4, 4)
			love.graphics.setColor(0.88, 0.82, 0.65, 1)
			local nt_str = ""
			if #entity.narrative_traits > 0 then
				nt_str = " [" .. entity.narrative_traits[#entity.narrative_traits].name .. "]"
			end
			love.graphics.print(
				string.format("%-16s p=%2d inf=%2d%s", entity.name, entity.prominence, entity.infamy, nt_str),
				LOG_X + 18,
				ey_off,
				0,
				0.70
			)
			ey_off = ey_off + 14
		end

		love.graphics.setColor(0.55, 0.42, 0.22, 0.6)
		love.graphics.line(LOG_X + 4, ey_off + 4, LOG_X + LOG_W - 4, ey_off + 4)
		ey_off = ey_off + 10

		love.graphics.setColor(0.72, 0.65, 0.45, 1)
		love.graphics.print("EVENT LOG  (scroll: mouse wheel)", LOG_X + 8, ey_off, 0, 0.75)
		ey_off = ey_off + 14

		local max_visible = math.floor((H - ey_off - 4) / 13)
		local start_idx = math.max(1, #ALL_LOG - max_visible - log_scroll + 1)
		local end_idx = math.min(#ALL_LOG, start_idx + max_visible - 1)

		love.graphics.setScissor(LOG_X, ey_off, LOG_W, H - ey_off)
		for i = start_idx, end_idx do
			local line = ALL_LOG[i]
			local col = { 0.78, 0.72, 0.56, 1 }
			if line:find("FAMINE") or line:find("REVOLT") then
				col = { 1.0, 0.45, 0.35, 1 }
			elseif line:find("seized") or line:find("fled") then
				col = { 0.90, 0.55, 0.30, 1 }
			elseif line:find("drove") or line:find("protected") or line:find("shared") then
				col = { 0.55, 0.90, 0.55, 1 }
			elseif line:find("^%-%-%-") then
				col = { 0.55, 0.82, 0.96, 1 }
			elseif line:find("weather") then
				col = { 0.95, 0.88, 0.40, 1 }
			elseif line:find("prominence") then
				col = { 0.75, 0.60, 0.95, 1 }
			end
			love.graphics.setColor(col[1], col[2], col[3], col[4])
			love.graphics.print(line, LOG_X + 6, ey_off + (i - start_idx) * 13, 0, 0.70)
		end
		love.graphics.setScissor()
	end

	-- Tweak panel (T)
	if show_tweak then
		local TX, TY, TW = 10, 10, 300
		local TH = 30 + #TWEAK_DEFS * 28 + 12
		love.graphics.setColor(0.12, 0.09, 0.05, 0.92)
		love.graphics.rectangle("fill", TX, TY, TW, TH, 5)
		love.graphics.setColor(0.65, 0.50, 0.22, 1)
		love.graphics.setLineWidth(1.5)
		love.graphics.rectangle("line", TX, TY, TW, TH, 5)
		love.graphics.setColor(0.82, 0.68, 0.38, 1)
		love.graphics.print("LIVE TWEAKS  (T to close)", TX + 10, TY + 8, 0, 0.80)
		for i, def in ipairs(TWEAK_DEFS) do
			local ry = TY + 28 + (i - 1) * 28
			-- draw row using CONFIG directly
			love.graphics.setColor(0.78, 0.70, 0.50, 1)
			love.graphics.print(def.label, TX + 10, ry, 0, 0.78)
			local valstr = string.format(def.fmt, CONFIG[def.key])
			love.graphics.setColor(0.96, 0.90, 0.70, 1)
			love.graphics.print(valstr, TX + 168, ry, 0, 0.78)
			ui_btn(TX + 210, ry - 1, 20, 17, "-", function()
				CONFIG[def.key] = math.max(def.min, CONFIG[def.key] - def.step)
				CONFIG[def.key] = math.floor(CONFIG[def.key] / def.step + 0.5) * def.step
			end)
			ui_btn(TX + 232, ry - 1, 20, 17, "+", function()
				CONFIG[def.key] = math.min(def.max, CONFIG[def.key] + def.step)
				CONFIG[def.key] = math.floor(CONFIG[def.key] / def.step + 0.5) * def.step
			end)
		end
	end

	-- Status bar
	love.graphics.setColor(0.16, 0.12, 0.07, 0.92)
	love.graphics.rectangle("fill", 0, BAR_Y, 1110, 40)
	love.graphics.setColor(0.82, 0.74, 0.50, 1)
	local ss = SeasonSubsystem.get_state()
	local txt = string.format(
		"  Year %-3d  Week %-2d  %-6s  |  speed: %.1fx  |  SPACE=pause  UP/DOWN=speed  L=log  M=labels  T=tweak  |  entities: %d  events: %d",
		ss.year,
		ss.week,
		ss.season,
		sim_speed,
		#EntityManager.entities,
		#ReputationSystem.events
	)
	if paused then
		txt = "  [PAUSED]  " .. txt
	end
	love.graphics.print(txt, 4, BAR_Y + 10, 0, 0.80)

	local lx = 820
	love.graphics.setColor(0.28, 0.22, 0.14)
	love.graphics.circle("fill", lx,    BAR_Y + 20, 5)
	love.graphics.setColor(0.28, 0.52, 0.78)
	love.graphics.circle("fill", lx+28, BAR_Y + 20, 5)
	love.graphics.setColor(0.85, 0.70, 0.15)
	love.graphics.circle("fill", lx+56, BAR_Y + 20, 5)
	love.graphics.setColor(0.80, 0.22, 0.22)
	love.graphics.circle("fill", lx+84, BAR_Y + 20, 5)
	love.graphics.setColor(0.70, 0.64, 0.42, 1)
	love.graphics.print("anon  named  famed  infamy", lx + 15, BAR_Y + 12, 0, 0.68)
end

-- All Love2D callbacks are inside this block so headless Lua skips them
if IS_LOVE then
	-- ── Love2D callbacks ──────────────────────────────────────────────────────────
	function love.load()
		love.window.setTitle("Phase 2 — Entity Simulation")
		love.window.setMode(1110, 620, { resizable = false })
	end

	function love.update(dt)
		mx, my = love.mouse.getPosition()
		if GAME_STATE ~= "running" or paused then
			return
		end
		for _, e in ipairs(EntityManager.entities) do
			if e.last_event_time < 999 then
				e.last_event_time = e.last_event_time + dt
			end
		end
		sim_time = sim_time + dt * sim_speed
		while sim_time >= 1.0 do
			sim_time = sim_time - 1.0
			SeasonSubsystem.tick_day()
			if SeasonSubsystem.get_state().year > SIM_YEARS then
				ReputationSystem.dump_payloads()
				GAME_STATE = "summary"
			end
		end
	end

	function love.draw()
		ui_clear()
		if GAME_STATE == "menu" then
			draw_menu()
		elseif GAME_STATE == "summary" then
			draw_summary()
		else
			draw_sim()
		end
	end

	function love.mousepressed(x, y, button)
		if button == 1 then
			ui_hit_check(x, y)
		end
	end

	function love.keypressed(key)
		if GAME_STATE == "menu" then
			if key == "return" or key == "kpenter" then start_simulation() end
			return
		end
		if GAME_STATE == "summary" then
			if key == "q" or key == "escape" then love.event.quit() end
			return
		end
		if key == "space" then
			paused = not paused
		end
		if key == "up" then
			sim_speed = math.min(8.0, sim_speed * 1.5)
		end
		if key == "down" then
			sim_speed = math.max(0.1, sim_speed / 1.5)
		end
		if key == "l" then
			show_log = not show_log
		end
		if key == "m" then
			show_labels = not show_labels
		end
		if key == "t" then
			show_tweak = not show_tweak
		end
		if key == "q" then
			ReputationSystem.dump_payloads()
			love.event.quit()
		end
	end

	function love.wheelmoved(x, y)
		log_scroll = math.max(0, log_scroll - y * 3)
	end
end -- if IS_LOVE

-- ── Headless mode ─────────────────────────────────────────────────────────────
if IS_LOVE then
	return
end

-- SIM_YEARS is already declared at the top of this file; no redeclaration needed
math.randomseed(423)

SeasonSubsystem.init()
EcologySimulator.init()
ResourceManager.init()
EconomySubsystem.init()
PopulationSimulator.init()
setup_world(PARAMS)
setup_entities()
setup_trade()
setup_new_systems()

print(string.format("\n%-60s  %-6s  %-6s", "Event", "Prom", "Infamy"))
print(string.rep("-", 80))

EventBus.subscribe("SEASON_CHANGED", function(d)
	print(string.format("\n--- %s  Year %d ---", d.season, d.year))
end)
EventBus.subscribe("PROMINENCE_CHANGED", function(d)
	local e = EntityManager.get_by_id(d.entity_id)
	if e then
		io.write(string.format("  >> %-20s prominence %d -> %d  (%s)\n", e.name, d.old_val, d.new_val, d.reason))
	end
end)
EventBus.subscribe("FAMINE_STARTED", function(d)
	print("!! FAMINE  " .. d.settlement_id)
end)
EventBus.subscribe("REVOLT_STARTED", function(d)
	print("!! REVOLT  " .. d.settlement_id)
end)
EventBus.subscribe("WEATHER_EVENT", function(d)
	print(string.format("  weather: %-16s sev=%d", d.event_type, d.severity))
end)

local last_sl = 0
EventBus.subscribe("WEEKLY_TICK", function()
	for i = last_sl + 1, #SituationEngine._log do
		print(SituationEngine._log[i])
	end
	last_sl = #SituationEngine._log
end)

for d = 1, SIM_YEARS * 56 do
	SeasonSubsystem.tick_day()
end

print("\n" .. string.rep("=", 60))
print(string.format("Final state after %d years:", SIM_YEARS))
for sid, ps in pairs(PopulationSimulator.pop_state) do
	print(
		string.format(
			"  %-12s  pop=%-4d  morale=%-3d  famine=%-5s  revolt=%-5s",
			sid,
			ps.population,
			math.floor(ps.morale),
			tostring(ps.famine_active),
			tostring(ps.in_revolt)
		)
	)
end
print("\nNamed entities:")
for _, e in ipairs(EntityManager.entities) do
	local nt = {}
	for _, t in ipairs(e.narrative_traits) do
		table.insert(nt, t.name)
	end
	print(
		string.format(
			"  %-22s  prom=%-3d  inf=%-3d  hon=%-3d  [%s]",
			e.name,
			e.prominence,
			e.infamy,
			e.honour,
			table.concat(nt, ", ")
		)
	)
end
print(string.format("\nTotal reputation events: %d", #ReputationSystem.events))
print(string.format("Narrative payloads queued: %d", #ReputationSystem.narrative_payloads))
ReputationSystem.dump_payloads()
print("\nNarrative payloads written to: narrative_payloads.txt")
