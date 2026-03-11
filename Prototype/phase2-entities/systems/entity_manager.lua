-- EntityManager
-- Named individuals crystallised from the aggregate population.
-- Each entity has traits that modify how they respond to world situations.
-- Prominence scores rise and fall; above a threshold they are "named" by the world.

local EntityManager = {}

EntityManager.entities        = {}   -- ordered list of all entities
EntityManager.by_settlement   = {}   -- settlement_id -> { entity, ... }
EntityManager.next_id         = 1

-- ── Trait definitions ────────────────────────────────────────────────────────
-- pass_mod:          multiplier on gossip propagation chance when this entity spreads news
-- context_preserve:  multiplier on how much context survives a retelling by this entity
EntityManager.TRAIT_DEFS = {
    impulsive     = { pass_mod=1.0, context_preserve=0.75, desc="Acts without thinking" },
    gentle        = { pass_mod=0.8, context_preserve=1.0,  desc="Avoids conflict by nature" },
    compassionate = { pass_mod=1.1, context_preserve=1.2,  desc="Moved by others suffering" },
    law_order     = { pass_mod=0.9, context_preserve=1.1,  desc="Values rules and justice" },
    gossip        = { pass_mod=2.0, context_preserve=0.85, desc="Cannot keep a secret" },
    loudmouth     = { pass_mod=1.8, context_preserve=0.45, desc="Talks freely, loses details" },
    discretion    = { pass_mod=0.15,context_preserve=1.0,  desc="Keeps things to themselves" },
    greedy        = { pass_mod=0.9, context_preserve=0.9,  desc="Wants more, shares less" },
    generous      = { pass_mod=1.2, context_preserve=1.0,  desc="Gives freely" },
    cautious      = { pass_mod=0.7, context_preserve=1.0,  desc="Thinks before acting" },
    brave         = { pass_mod=1.1, context_preserve=1.0,  desc="Faces danger" },
    cowardly      = { pass_mod=0.6, context_preserve=0.8,  desc="Avoids danger" },
}

-- ── Narrative traits ─────────────────────────────────────────────────────────
-- Gained from events. Each shifts prominence and tells the world something about the person.
EntityManager.NARRATIVE_TRAIT_DEFS = {
    local_hero    = { prominence_mod=12, tone="honour",  desc="Helped community in need" },
    petty_thief   = { prominence_mod=8,  tone="infamy",  desc="Known to have stolen" },
    oath_breaker  = { prominence_mod=10, tone="infamy",  desc="Broke their word publicly" },
    protector     = { prominence_mod=15, tone="honour",  desc="Put themselves at risk for another" },
    peacemaker    = { prominence_mod=8,  tone="honour",  desc="Resolved a public conflict" },
    hoarder       = { prominence_mod=6,  tone="infamy",  desc="Kept resources while others starved" },
    generous_soul = { prominence_mod=6,  tone="honour",  desc="Gave freely when they did not have to" },
    coward        = { prominence_mod=5,  tone="infamy",  desc="Fled when action was needed" },
    wolf_fighter  = { prominence_mod=18, tone="honour",  desc="Drove off predators threatening the village" },
}

-- Role-based prominence baselines (floor — prominence will not decay below this)
EntityManager.ROLE_BASELINE = {
    lord      = 65,
    steward   = 50,
    priest    = 45,
    headman   = 55,
    elder     = 48,
    merchant  = 35,
    miller    = 38,
    blacksmith= 35,
    herbalist = 28,
    forester  = 25,
    boatman   = 20,
    trader    = 28,
    shepherd  = 15,
    watchman  = 20,
    farmer    = 10,
    peasant   = 5,
}

-- ── API ───────────────────────────────────────────────────────────────────────

function EntityManager.register(data)
    local baseline = EntityManager.ROLE_BASELINE[data.role] or 10
    local entity = {
        id               = EntityManager.next_id,
        name             = data.name,
        settlement_id    = data.settlement_id,
        role             = data.role or "peasant",
        traits           = data.traits or {},
        prominence       = data.prominence or baseline,
        narrative_traits = {},
        age              = data.age or math.random(20, 50),
        infamy           = 0,
        honour           = 0,
        -- Visual state (used by renderer, updated by situation engine)
        last_event_time  = -999,   -- seconds since last event (for flash)
        last_event_tone  = "none", -- "honour"|"infamy"|"none"
    }
    EntityManager.next_id = EntityManager.next_id + 1
    table.insert(EntityManager.entities, entity)
    if not EntityManager.by_settlement[data.settlement_id] then
        EntityManager.by_settlement[data.settlement_id] = {}
    end
    table.insert(EntityManager.by_settlement[data.settlement_id], entity)
    return entity
end

function EntityManager.has_trait(entity, trait)
    for _, t in ipairs(entity.traits) do
        if t == trait then return true end
    end
    return false
end

function EntityManager.get_pass_mod(entity)
    local mod = 1.0
    for _, t in ipairs(entity.traits) do
        local def = EntityManager.TRAIT_DEFS[t]
        if def then mod = mod * def.pass_mod end
    end
    return mod
end

function EntityManager.get_context_preserve(entity)
    local preserve = 1.0
    for _, t in ipairs(entity.traits) do
        local def = EntityManager.TRAIT_DEFS[t]
        if def then preserve = preserve * def.context_preserve end
    end
    return math.min(1.0, math.max(0.1, preserve))
end

function EntityManager.add_narrative_trait(entity, trait_name, ctx, EventBus)
    -- No duplicates
    for _, nt in ipairs(entity.narrative_traits) do
        if nt.name == trait_name then return false end
    end
    local def = EntityManager.NARRATIVE_TRAIT_DEFS[trait_name]
    if not def then return false end

    local old_prom = entity.prominence
    table.insert(entity.narrative_traits, {
        name     = trait_name,
        week     = ctx and ctx.week or 0,
        year     = ctx and ctx.year or 0,
        location = ctx and ctx.location or "unknown",
    })
    entity.prominence = math.min(100, entity.prominence + def.prominence_mod)
    if def.tone == "infamy" then entity.infamy = entity.infamy + def.prominence_mod
    else                          entity.honour = entity.honour + def.prominence_mod end

    if EventBus then
        EventBus.fire("PROMINENCE_CHANGED", {
            entity_id = entity.id,
            old_val   = old_prom,
            new_val   = entity.prominence,
            reason    = trait_name,
        })
    end

    entity.last_event_time = 0
    entity.last_event_tone = def.tone

    return true
end

-- Weekly decay: prominence drifts back toward role baseline without events
function EntityManager.weekly_decay()
    for _, entity in ipairs(EntityManager.entities) do
        local baseline = EntityManager.ROLE_BASELINE[entity.role] or 5
        if entity.prominence > baseline then
            entity.prominence = math.max(baseline, entity.prominence - 1)
        end
        entity.last_event_time = entity.last_event_time + 1
    end
end

function EntityManager.get_by_id(id)
    for _, e in ipairs(EntityManager.entities) do
        if e.id == id then return e end
    end
    return nil
end

return EntityManager
