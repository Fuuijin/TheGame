-- Fauna
-- Abstract animal populations per zone. No named species yet — just categories.
-- Herbivores eat vegetation. Carnivores eat herbivores. Both migrate when stressed.
-- Designed to reach natural equilibrium without human interference.
--
-- Population units are abstract (think: "relative density index", not head count).
-- 100 = zone at carrying capacity for that category.

local EventBus = require("systems/event_bus")
local Ecology  = require("systems/ecology")

local Fauna = {}

-- ── Biome carrying capacities ─────────────────────────────────────────────────
-- Max herbivore and carnivore density sustainable in each biome.
local BIOME_CAPACITY = {
    Mountain  = { herbivore = 20, carnivore = 8  },
    Forest    = { herbivore = 70, carnivore = 30 },
    Hills     = { herbivore = 60, carnivore = 22 },
    Riverland = { herbivore = 65, carnivore = 20 },
    Plains    = { herbivore = 75, carnivore = 18 },
    Wetland   = { herbivore = 50, carnivore = 15 },
    Coastal   = { herbivore = 25, carnivore = 8  },
}

-- ── Migration adjacency ───────────────────────────────────────────────────────
-- Animals move to adjacent zones when food is scarce or population is over capacity.
-- Reflects physical connectivity on the island.
local MIGRATION_LINKS = {
    central_peaks   = { "highland_forest", "interior_hills" },
    highland_forest = { "central_peaks", "interior_hills", "river_valleys" },
    interior_hills  = { "central_peaks", "highland_forest", "river_valleys", "coastal_plains" },
    river_valleys   = { "highland_forest", "interior_hills", "wetlands" },
    coastal_plains  = { "interior_hills", "coastal_margin" },
    wetlands        = { "river_valleys", "coastal_margin" },
    coastal_margin  = { "coastal_plains", "wetlands" },
}

-- ── Population state ──────────────────────────────────────────────────────────
Fauna.populations = {}  -- zone_id → { herbivore, carnivore }

-- Starting populations as fraction of zone capacity.
-- Kept low so initial grazing pressure doesn't crash vegetation before equilibrium forms.
local START_HERB_FRAC = 0.25  -- was 0.45
local START_CARN_FRAC = 0.15  -- was 0.30

function Fauna.init()
    EventBus.subscribe("MONTHLY_TICK",  Fauna._on_monthly_tick)
    EventBus.subscribe("WEATHER_EVENT", Fauna._on_weather_event)
    EventBus.subscribe("SEASON_CHANGED", Fauna._on_season_changed)

    Fauna.populations = {}
    for _, zone_id in ipairs(Ecology.all_zone_ids()) do
        local zone = Ecology.get_zone(zone_id)
        local def  = Ecology.get_def(zone_id)
        local cap  = BIOME_CAPACITY[def.biome] or BIOME_CAPACITY.Plains
        Fauna.populations[zone_id] = {
            herbivore = cap.herbivore * START_HERB_FRAC,
            carnivore = cap.carnivore * START_CARN_FRAC,
        }
    end
end

function Fauna.get(zone_id)
    return Fauna.populations[zone_id]
end

-- ── Monthly tick: births, deaths, predation, migration ───────────────────────
function Fauna._on_monthly_tick(data)
    local season = data.season

    -- First pass: births and deaths per zone (no migration yet)
    local migration_queue = {}  -- { zone_id, category, amount }

    for zone_id, pop in pairs(Fauna.populations) do
        local zone = Ecology.get_zone(zone_id)
        local def  = Ecology.get_def(zone_id)
        local cap  = BIOME_CAPACITY[def.biome] or BIOME_CAPACITY.Plains

        local forage = Ecology.get_forage(zone_id)  -- 0..60 roughly
        local water  = Ecology.get_water(zone_id)

        -- ── Herbivores ────────────────────────────────────────────────────────
        -- Food availability: forage relative to what zone can sustain
        local herb_food = math.min(1.0, forage / (cap.herbivore * 0.8))
        local herb_water = math.min(1.0, water / 40)
        local herb_resource = herb_food * 0.7 + herb_water * 0.3

        -- Base birth rate: 8% per month in good conditions
        -- Winter halves reproduction
        local herb_birth_rate = 0.08 * herb_resource
        if season == "Winter" then herb_birth_rate = herb_birth_rate * 0.3
        elseif season == "Autumn" then herb_birth_rate = herb_birth_rate * 0.6
        end

        -- Density-dependent death: crowding increases mortality
        local herb_density = pop.herbivore / math.max(1, cap.herbivore)
        local herb_death_rate = 0.03
            + (1 - herb_resource) * 0.06   -- starvation
            + math.max(0, herb_density - 0.8) * 0.08  -- crowding

        -- Predation: carnivores consume herbivores
        local predation_rate = (pop.carnivore / math.max(1, cap.carnivore)) * 0.12

        local herb_delta = pop.herbivore * (herb_birth_rate - herb_death_rate - predation_rate)
        pop.herbivore = math.max(0, math.min(cap.herbivore, pop.herbivore + herb_delta))

        -- Herbivore grazing reduces biomass
        local graze_pressure = pop.herbivore * 0.04  -- units of biomass consumed per month
        zone.biomass = math.max(zone.def.biomass_floor, zone.biomass - graze_pressure)

        -- ── Carnivores ────────────────────────────────────────────────────────
        -- Carnivores depend on herbivore prey density
        local prey_density = pop.herbivore / math.max(1, cap.herbivore)

        local carn_birth_rate = 0.05 * math.min(1.0, prey_density * 1.5)
        if season == "Winter" then carn_birth_rate = carn_birth_rate * 0.2
        elseif season == "Autumn" then carn_birth_rate = carn_birth_rate * 0.7
        end

        local carn_density = pop.carnivore / math.max(1, cap.carnivore)
        local carn_death_rate = 0.04
            + math.max(0, 1 - prey_density) * 0.06  -- starvation when prey scarce
            + math.max(0, carn_density - 0.9) * 0.10

        local carn_delta = pop.carnivore * (carn_birth_rate - carn_death_rate)
        pop.carnivore = math.max(0, math.min(cap.carnivore, pop.carnivore + carn_delta))

        -- Minimum viable population: prevent local extinction from rounding
        pop.herbivore = math.max(0.5, pop.herbivore)
        pop.carnivore = math.max(0.2, pop.carnivore)

        -- ── Migration trigger ─────────────────────────────────────────────────
        -- Migrate if: food critically low OR population significantly over capacity
        local herb_migrate = 0
        local carn_migrate = 0

        if herb_resource < 0.35 or herb_density > 1.1 then
            -- 15-25% of population seeks better ground
            herb_migrate = pop.herbivore * (herb_resource < 0.35 and 0.22 or 0.12)
            pop.herbivore = pop.herbivore - herb_migrate
        end

        if prey_density < 0.25 or carn_density > 1.1 then
            carn_migrate = pop.carnivore * (prey_density < 0.25 and 0.20 or 0.12)
            pop.carnivore = pop.carnivore - carn_migrate
        end

        if herb_migrate > 0 then
            table.insert(migration_queue, { from=zone_id, cat="herbivore", amount=herb_migrate })
        end
        if carn_migrate > 0 then
            table.insert(migration_queue, { from=zone_id, cat="carnivore", amount=carn_migrate })
        end
    end

    -- Second pass: distribute migrants to adjacent zones
    for _, mig in ipairs(migration_queue) do
        local links = MIGRATION_LINKS[mig.from] or {}
        if #links > 0 then
            -- Find the best adjacent zone (highest forage for herbivores, highest prey for carnivores)
            local best_id, best_score = nil, -1
            for _, nid in ipairs(links) do
                local npop = Fauna.populations[nid]
                local nzone = Ecology.get_zone(nid)
                local ndef  = Ecology.get_def(nid)
                local ncap  = BIOME_CAPACITY[ndef.biome] or BIOME_CAPACITY.Plains
                local score
                if mig.cat == "herbivore" then
                    local density = (npop and npop.herbivore or 0) / math.max(1, ncap.herbivore)
                    score = Ecology.get_forage(nid) / 60 - density * 0.5
                else
                    local prey_d = (npop and npop.herbivore or 0) / math.max(1, ncap.herbivore)
                    local carn_d = (npop and npop.carnivore or 0) / math.max(1, ncap.carnivore)
                    score = prey_d - carn_d * 0.5
                end
                if score > best_score then
                    best_score = score
                    best_id    = nid
                end
            end

            if best_id then
                local dest = Fauna.populations[best_id]
                local def  = Ecology.get_def(best_id)
                local cap  = BIOME_CAPACITY[def.biome] or BIOME_CAPACITY.Plains
                if mig.cat == "herbivore" then
                    dest.herbivore = math.min(cap.herbivore, dest.herbivore + mig.amount)
                else
                    dest.carnivore = math.min(cap.carnivore, dest.carnivore + mig.amount)
                end

                EventBus.fire("FAUNA_MIGRATION", {
                    from     = mig.from,
                    to       = best_id,
                    category = mig.cat,
                    amount   = mig.amount,
                    season   = data.season,
                    year     = data.year,
                })
            end
        end
    end
end

-- ── Season changed ────────────────────────────────────────────────────────────
function Fauna._on_season_changed(data)
    -- Winter: some animals in exposed zones face extra mortality
    if data.season == "Winter" then
        for zone_id, pop in pairs(Fauna.populations) do
            local def = Ecology.get_def(zone_id)
            if def.elevation >= 5 then
                -- Alpine peaks: harsh winter kill
                pop.herbivore = pop.herbivore * 0.88
                pop.carnivore = pop.carnivore * 0.92
            elseif def.elevation >= 4 then
                -- Highland forest: mild maritime winter, modest kill
                pop.herbivore = pop.herbivore * 0.95
                pop.carnivore = pop.carnivore * 0.97
            end
        end
    end
end

-- ── Weather events ────────────────────────────────────────────────────────────
function Fauna._on_weather_event(data)
    local evt = data.event_type
    local sev = data.severity or 1

    for zone_id, pop in pairs(Fauna.populations) do
        local def = Ecology.get_def(zone_id)

        if evt == "Blizzard" and def.elevation >= 3 then
            pop.herbivore = math.max(0, pop.herbivore * (1 - sev * 0.07))
            pop.carnivore = math.max(0, pop.carnivore * (1 - sev * 0.05))

        elseif evt == "StormSurge" and def.elevation <= 1 then
            -- Coastal fauna disrupted
            pop.herbivore = math.max(0, pop.herbivore * (1 - sev * 0.12))
            pop.carnivore = math.max(0, pop.carnivore * (1 - sev * 0.08))

        elseif evt == "Wildfire" and def.elevation >= 2 and def.elevation <= 3 then
            -- Fire drives animals out (they migrate next month) and kills some
            pop.herbivore = math.max(0, pop.herbivore * (1 - sev * 0.15))
            pop.carnivore = math.max(0, pop.carnivore * (1 - sev * 0.10))

        elseif evt == "Drought" then
            -- All zones: slow background stress
            pop.herbivore = math.max(0, pop.herbivore * (1 - sev * 0.03))
        end
    end
end

return Fauna
