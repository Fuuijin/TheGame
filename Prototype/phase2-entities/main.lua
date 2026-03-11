-- Phase 2: Entity Simulation
-- Run headless:  lua main.lua
-- Run visual:    love .
--
-- SPACE        pause / resume
-- UP / DOWN    sim speed  (0.1x .. 8x)
-- L            toggle log panel
-- M            toggle map labels
-- Q            quit (headless: runs to SIM_YEARS then exits)

-- ── Detect runtime ────────────────────────────────────────────────────────────
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

-- ── World config ──────────────────────────────────────────────────────────────
local SIM_YEARS = 8
math.randomseed(42)

-- Settlement neighbour graph (also used by trade in phase1)
local NEIGHBOURS = {
	Ashford = { "Millhaven", "Brackenmere", "Stonekeep" },
	Millhaven = { "Ashford", "Stonekeep" },
	Brackenmere = { "Ashford" },
	Stonekeep = { "Ashford", "Millhaven" },
}

-- ── Settlement visual positions (Love2D map canvas) ───────────────────────────
-- Map canvas: x=0..690, y=0..560
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

-- ── Named entities ────────────────────────────────────────────────────────────
local function setup_entities()
	-- Ashford (Plains, pop 120) — largest, most connected
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

	-- Millhaven (Forest, pop 80)
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

	-- Brackenmere (Wetland, pop 60)
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

	-- Stonekeep (Upland, pop 50)
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

-- ── Phase-1 systems setup (unchanged from phase1-headless) ────────────────────
-- Settlement definitions: same initial stocks as phase1 (balanced)
local SETTLEMENTS = {
	{
		id = "Ashford",
		pop = 120,
		biome = "Plains",
		stocks = { Grain = 85, Livestock = 55, Timber = 50, Fuel = 80, Salt = 22, Water = 90, Forage = 35 },
	},
	{
		id = "Millhaven",
		pop = 80,
		biome = "Forest",
		stocks = { Grain = 70, Livestock = 45, Timber = 90, Fuel = 85, Salt = 18, Water = 80, Forage = 40 },
	},
	{
		id = "Brackenmere",
		pop = 60,
		biome = "Wetland",
		stocks = { Grain = 60, Livestock = 35, Timber = 40, Fuel = 70, Salt = 35, Water = 95, Forage = 30 },
	},
	{
		id = "Stonekeep",
		pop = 50,
		biome = "Upland",
		stocks = { Grain = 55, Livestock = 50, Timber = 45, Fuel = 90, Salt = 15, Water = 70, Forage = 50 },
	},
}

local function setup_world()
	for _, s in ipairs(SETTLEMENTS) do
		EcologySimulator.register_tile(s.id, s.biome)
		local stocks = {}
		for k, v in pairs(s.stocks) do
			stocks[k] = v
		end
		stocks._population = s.pop
		ResourceManager.register_settlement(s.id, stocks)
		EconomySubsystem.register_settlement(s.id)
		PopulationSimulator.register_settlement(s.id, s.pop, NEIGHBOURS[s.id] or {})
	end
end

-- ── Phase-1 trade (unchanged) ─────────────────────────────────────────────────
local function setup_trade()
	EventBus.subscribe("WEEKLY_TICK", function(data)
		if data.season == "Winter" then
			return
		end
		for sid, neighbours in pairs(NEIGHBOURS) do
			local grain = (ResourceManager.stocks[sid] or {}).Grain or 0
			if grain > 60 then
				for _, nsid in ipairs(neighbours) do
					local ngrain = (ResourceManager.stocks[nsid] or {}).Grain or 0
					if ngrain < 15 then
						local share = math.min(8, grain - 60)
						ResourceManager.stocks[sid].Grain = grain - share
						ResourceManager.stocks[nsid].Grain = ngrain + share
					end
				end
			end
			if grain > 40 and data.season == "Spring" then
				for _, nsid in ipairs(neighbours) do
					local ngrain = (ResourceManager.stocks[nsid] or {}).Grain or 0
					if ngrain < 12 then
						local loan = math.min(10, grain - 40)
						ResourceManager.stocks[sid].Grain = grain - loan
						ResourceManager.stocks[nsid].Grain = ngrain + loan
					end
				end
			end
		end
	end)
end

-- ── Wire new systems ──────────────────────────────────────────────────────────
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

	-- Hook situation engine into the weekly tick
	EventBus.subscribe("WEEKLY_TICK", function(data)
		SituationEngine.weekly_tick(data.week, data.year, data.season)
	end)
end

-- ── Shared log (all systems feed into this for the panel) ─────────────────────
local ALL_LOG = {}
local function push_log(msg)
	table.insert(ALL_LOG, msg)
	if #ALL_LOG > 400 then
		table.remove(ALL_LOG, 1)
	end
end

local function capture_logs()
	-- Mirror entity / situation logs into ALL_LOG each frame
	local el = EntityManager._log or {}
	local sl = SituationEngine._log or {}
	-- Only push lines we haven't seen (track last seen index)
	-- Simpler: just read the two tables and merge on each draw
end

-- ── Colour helpers ────────────────────────────────────────────────────────────
local function settlement_color(sid)
	local ps = PopulationSimulator.pop_state[sid]
	if not ps then
		return { 0.6, 0.6, 0.6 }
	end
	if ps.revolt then
		return { 0.76, 0.18, 0.18 }
	end -- red
	if ps.famine then
		return { 0.80, 0.39, 0.10 }
	end -- orange
	local wg = 99
	local grain = (ResourceManager.stocks[sid] or {}).Grain or 0
	if ps.population > 0 then
		wg = grain / (8 * (ps.population / 100))
	end
	if wg < 1.5 then
		return { 0.78, 0.64, 0.12 }
	end -- amber
	if wg < 3.0 then
		return { 0.65, 0.72, 0.30 }
	end -- yellow-green
	return { 0.40, 0.68, 0.38 } -- healthy green
end

local function entity_color(entity, now)
	-- Flash yellow for 2 seconds after an event
	if entity.last_event_time and entity.last_event_time < 2.0 then
		return { 1.0, 0.88, 0.1, 1.0 }
	end
	if entity.infamy > 15 then
		return { 0.80, 0.22, 0.22 }
	end -- red: criminal
	if entity.honour > 20 and entity.prominence > 55 then
		return { 0.85, 0.70, 0.15 } -- gold: honoured and famous
	end
	if entity.prominence > 40 then
		return { 0.30, 0.56, 0.80 }
	end -- blue: named
	if entity.prominence > 20 then
		return { 0.70, 0.78, 0.88 }
	end -- light blue: emerging
	return { 0.75, 0.75, 0.75 } -- grey: aggregate
end

local function entity_radius(entity)
	return math.max(4, math.min(10, 4 + math.floor(entity.prominence / 14)))
end

-- ── Love2D ────────────────────────────────────────────────────────────────────
local sim_time = 0
local sim_speed = 1.0 -- weeks per second
local paused = false
local show_labels = true
local show_log = true
local weeks_per_tick = 1
local log_scroll = 0

local SEASON_COLORS = {
	Spring = { 0.62, 0.82, 0.55, 0.18 },
	Summer = { 1.00, 0.95, 0.55, 0.15 },
	Autumn = { 0.88, 0.60, 0.25, 0.18 },
	Winter = { 0.75, 0.88, 1.00, 0.22 },
}

if IS_LOVE then
	function love.load()
		love.window.setTitle("Phase 2 — Entity Simulation")
		love.window.setMode(1110, 620, { resizable = false })
		SeasonSubsystem.init()
		EcologySimulator.init()
		ResourceManager.init()
		EconomySubsystem.init()
		PopulationSimulator.init()
		setup_world()
		setup_entities()
		setup_trade()
		setup_new_systems()

		-- Capture logs via EventBus
		EventBus.subscribe("SITUATION_FIRED", function(d)
			push_log(
				string.format(
					"[Y%d W%02d %s] event: %s in %s",
					d.year,
					d.week,
					d.season,
					d.situation_type,
					d.settlement_id
				)
			)
		end)
		EventBus.subscribe("PROMINENCE_CHANGED", function(d)
			local e = EntityManager.get_by_id(d.entity_id)
			if e then
				push_log(string.format("  >> %s prominence %d -> %d (%s)", e.name, d.old_val, d.new_val, d.reason))
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
	end

	function love.update(dt)
		if paused then
			return
		end
		-- Update entity flash timers
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
				love.event.quit()
			end
		end
	end

	function love.draw()
		local MAP_W = 700
		local LOG_X = MAP_W + 5
		local LOG_W = 400
		local H = 575
		local BAR_Y = H + 5

		-- Parchment background
		love.graphics.setBackgroundColor(0.90, 0.84, 0.68)

		-- Season tint over map
		local sc = SEASON_COLORS[SeasonSubsystem.get_state().season] or { 1, 1, 1, 0 }
		love.graphics.setColor(sc[1], sc[2], sc[3], sc[4])
		love.graphics.rectangle("fill", 0, 0, MAP_W, H)

		-- ── Roads ──
		love.graphics.setColor(0.45, 0.32, 0.18, 0.55)
		love.graphics.setLineWidth(2)
		for _, road in ipairs(ROADS) do
			local a, b = SVIS[road[1]], SVIS[road[2]]
			love.graphics.line(a.x + a.w / 2, a.y + a.h / 2, b.x + b.w / 2, b.y + b.h / 2)
		end

		-- ── Settlements ──
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

		-- ── Entity dots ──
		for i, entity in ipairs(EntityManager.entities) do
			local pos = SVIS[entity.settlement_id]
			if pos then
				-- Deterministic angle from entity index, stable across frames
				local angle = (i * 2.399) % (2 * math.pi)
				local radius = 52 + (i % 4) * 10
				local ex = pos.x + pos.w / 2 + math.cos(angle) * radius
				local ey = pos.y + pos.h / 2 + math.sin(angle) * radius
				local r = entity_radius(entity)
				local c = entity_color(entity, 0)

				-- Halo for prominent entities
				if entity.prominence > 40 then
					love.graphics.setColor(c[1], c[2], c[3] or 1, 0.25)
					love.graphics.circle("fill", ex, ey, r + 5)
				end

				love.graphics.setColor(c[1], c[2], c[3] or 1, c[4] or 1)
				love.graphics.circle("fill", ex, ey, r)
				love.graphics.setColor(0.1, 0.1, 0.1, 0.7)
				love.graphics.setLineWidth(1)
				love.graphics.circle("line", ex, ey, r)

				-- Name label for named entities
				if show_labels and entity.prominence > 25 then
					love.graphics.setColor(0.08, 0.05, 0.02, 0.9)
					love.graphics.print(entity.name, ex + r + 2, ey - 7, 0, 0.62)
				end
			end
		end

		-- ── Log panel ──
		if show_log then
			love.graphics.setColor(0.22, 0.18, 0.11, 0.88)
			love.graphics.rectangle("fill", LOG_X, 0, LOG_W, H, 4)
			love.graphics.setColor(0.45, 0.35, 0.18, 1)
			love.graphics.setLineWidth(1)
			love.graphics.rectangle("line", LOG_X, 0, LOG_W, H, 4)

			-- Entity roster (top third)
			love.graphics.setColor(0.85, 0.75, 0.50, 1)
			love.graphics.print("ENTITIES", LOG_X + 8, 6, 0, 0.85)
			local ey_off = 22
			for _, entity in ipairs(EntityManager.entities) do
				if ey_off > 195 then
					break
				end
				local col = entity_color(entity, 0)
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

			-- Divider
			love.graphics.setColor(0.55, 0.42, 0.22, 0.6)
			love.graphics.line(LOG_X + 4, ey_off + 4, LOG_X + LOG_W - 4, ey_off + 4)
			ey_off = ey_off + 10

			-- Event log (bottom portion, scrollable)
			love.graphics.setColor(0.72, 0.65, 0.45, 1)
			love.graphics.print("EVENT LOG  (scroll: mouse wheel)", LOG_X + 8, ey_off, 0, 0.75)
			ey_off = ey_off + 14

			local log_lines = ALL_LOG
			local max_visible = math.floor((H - ey_off - 4) / 13)
			local start_idx = math.max(1, #log_lines - max_visible - log_scroll + 1)
			local end_idx = math.min(#log_lines, start_idx + max_visible - 1)

			love.graphics.setScissor(LOG_X, ey_off, LOG_W, H - ey_off)
			for i = start_idx, end_idx do
				local line = log_lines[i]
				local col = { 0.78, 0.72, 0.56, 1 }
				if line:find("FAMINE") or line:find("REVOLT") then
					col = { 1.0, 0.45, 0.35, 1 }
				elseif line:find("seized") or line:find("fled") then
					col = { 0.90, 0.55, 0.30, 1 }
				elseif
					line:find("drove off")
					or line:find("intervened")
					or line:find("shared")
					or line:find("protected")
				then
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

		-- ── Status bar ──
		love.graphics.setColor(0.16, 0.12, 0.07, 0.92)
		love.graphics.rectangle("fill", 0, BAR_Y, 1110, 40)
		love.graphics.setColor(0.82, 0.74, 0.50, 1)
		local ss = SeasonSubsystem.get_state()
		local status = string.format(
			"  Year %-3d  Week %-2d  %-6s  |  speed: %.1fx  |  SPACE=pause  UP/DOWN=speed  L=log  M=labels  |  entities: %d  |  events: %d",
			ss.year,
			ss.week,
			ss.season,
			sim_speed,
			#EntityManager.entities,
			#ReputationSystem.events
		)
		if paused then
			status = "  [PAUSED]  " .. status
		end
		love.graphics.print(status, 4, BAR_Y + 10, 0, 0.82)

		-- Legend dots
		local lx = 800
		love.graphics.setColor(0.75, 0.75, 0.75)
		love.graphics.circle("fill", lx, BAR_Y + 20, 5)
		love.graphics.setColor(0.30, 0.56, 0.80)
		love.graphics.circle("fill", lx + 28, BAR_Y + 20, 5)
		love.graphics.setColor(0.85, 0.70, 0.15)
		love.graphics.circle("fill", lx + 56, BAR_Y + 20, 5)
		love.graphics.setColor(0.80, 0.22, 0.22)
		love.graphics.circle("fill", lx + 84, BAR_Y + 20, 5)
		love.graphics.setColor(0.70, 0.64, 0.42, 1)
		love.graphics.print("anon  named  famed  infamy", lx + 15, BAR_Y + 12, 0, 0.68)
	end

	function love.keypressed(key)
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
		if key == "q" then
			ReputationSystem.dump_payloads()
			love.event.quit()
		end
	end

	function love.wheelmoved(x, y)
		log_scroll = math.max(0, log_scroll - y * 3)
	end

-- ── Headless mode ─────────────────────────────────────────────────────────────
else
	SeasonSubsystem.init()
	EcologySimulator.init()
	ResourceManager.init()
	EconomySubsystem.init()
	PopulationSimulator.init()
	setup_world()
	setup_entities()
	setup_trade()
	setup_new_systems()

	-- Print header
	print(string.format("\n%-60s  %-6s  %-6s  %-5s  %-5s", "Event", "Prom", "Infamy", "Famine", "Revolt"))
	print(string.rep("-", 90))

	-- Subscribe to loggable events
	EventBus.subscribe("SEASON_CHANGED", function(d)
		print(string.format("\n--- %s  Year %d ---", d.season, d.year))
	end)
	EventBus.subscribe("SITUATION_FIRED", function(d)
		-- already printed by situation engine
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

	-- Flush situation log after each week
	local last_sl = 0
	EventBus.subscribe("WEEKLY_TICK", function()
		for i = last_sl + 1, #SituationEngine._log do
			print(SituationEngine._log[i])
		end
		last_sl = #SituationEngine._log
	end)

	-- Run (56 days per year)
	local max_days = SIM_YEARS * 56
	for d = 1, max_days do
		SeasonSubsystem.tick_day()
	end

	-- Final state
	print("\n" .. string.rep("=", 60))
	print(string.format("Final state after %d years:", SIM_YEARS))
	for sid, ps in pairs(PopulationSimulator.pop_state) do
		print(
			string.format(
				"  %-12s  pop=%-4d  morale=%-3d  famine=%-5s  revolt=%-5s",
				sid,
				ps.population,
				math.floor(ps.morale),
				tostring(ps.famine),
				tostring(ps.revolt)
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
end
