-- ReputationSystem
-- Records events, runs propagation chains, and builds narrative payloads.
-- Propagation is trait-weighted: gossip spreads far, discretion kills chains,
-- loudmouth spreads wide but strips context.
-- Narrative payloads are written to narrative_payloads.txt — ready for LLM rendering.

local ReputationSystem = {}
ReputationSystem.events            = {}
ReputationSystem.narrative_payloads= {}

local EM, EventBus, NEIGHBOURS

function ReputationSystem.init(deps)
    EM        = deps.EntityManager
    EventBus  = deps.EventBus
    NEIGHBOURS= deps.NEIGHBOURS
end

-- ── Record an event ───────────────────────────────────────────────────────────

function ReputationSystem.record_event(data)
    local event = {
        id          = #ReputationSystem.events + 1,
        type        = data.type,
        actor       = data.actor,
        witness     = data.witness,
        location    = data.location,
        ctx         = data.ctx or {},
        infamy_delta= data.infamy_delta or 0,
        honour_delta= data.honour_delta or 0,
        known_by    = {},   -- entity ids that have heard this
    }

    -- Apply deltas to actor
    if data.actor then
        data.actor.infamy  = (data.actor.infamy  or 0) + event.infamy_delta
        data.actor.honour  = (data.actor.honour  or 0) + event.honour_delta
        data.actor.last_event_time = 0
        data.actor.last_event_tone = event.infamy_delta > 0 and "infamy" or "honour"
    end

    table.insert(ReputationSystem.events, event)
    ReputationSystem._queue_narrative(event, 0, nil)
    ReputationSystem._propagate(event, 0)

    EventBus.fire("REPUTATION_EVENT", {
        event_type  = event.type,
        actor_id    = data.actor and data.actor.id or nil,
        witness_id  = data.witness and data.witness.id or nil,
        location    = event.location,
        infamy_delta= event.infamy_delta,
        honour_delta= event.honour_delta,
    })

    return event
end

-- ── Propagation chain ─────────────────────────────────────────────────────────

function ReputationSystem._propagate(event, depth)
    local sid      = event.location
    local entities = EM.by_settlement[sid] or {}
    local spreader = event.witness or event.actor
    if not spreader then return end

    -- Each entity in the settlement may hear the story from the spreader
    for _, entity in ipairs(entities) do
        local is_actor   = entity.id == (event.actor   and event.actor.id   or -1)
        local is_witness = entity.id == (event.witness and event.witness.id or -1)
        if not is_actor and not is_witness then
            local base_chance = (CONFIG and CONFIG.base_pass_chance) or 0.28
            -- Amplified if spreader is prominent
            if spreader.prominence > 50 then base_chance = base_chance * 1.6
            elseif spreader.prominence > 25 then base_chance = base_chance * 1.2 end
            -- Spreader traits
            base_chance = base_chance * EM.get_pass_mod(spreader)

            if math.random() < math.min(0.92, base_chance) then
                table.insert(event.known_by, entity.id)
                local context_fidelity = EM.get_context_preserve(entity)

                -- Loudmouth entity tries to spread to a neighbouring settlement (max depth 2)
                if EM.has_trait(entity, "loudmouth") and depth < 2 then
                    ReputationSystem._spread_to_neighbours(event, sid, entity, context_fidelity * 0.5, depth)
                -- Gossip entity spreads within same settlement one more hop (max depth 3)
                elseif EM.has_trait(entity, "gossip") and depth < 3 then
                    ReputationSystem._queue_narrative(event, depth + 1, entity)
                end
            end
        end
    end
end

function ReputationSystem._spread_to_neighbours(event, origin_sid, carrier, fidelity, depth)
    local neighbours = NEIGHBOURS[origin_sid] or {}
    for _, nsid in ipairs(neighbours) do
        if math.random() < 0.35 then
            -- Story reached a neighbouring settlement; actor gains regional notoriety
            if event.actor then
                local old = event.actor.prominence
                event.actor.prominence = math.min(100, event.actor.prominence + 3)
                if event.actor.prominence ~= old then
                    EventBus.fire("PROMINENCE_CHANGED", {
                        entity_id = event.actor.id,
                        old_val   = old,
                        new_val   = event.actor.prominence,
                        reason    = "story_spread_to_"..nsid,
                    })
                end
            end
            ReputationSystem._queue_narrative(event, depth + 2, carrier)
        end
    end
end

-- ── Narrative payload ─────────────────────────────────────────────────────────
-- Builds the structured payload that a future LLM call would receive.
-- Context degrades as hop_count rises.

function ReputationSystem._queue_narrative(event, hop_count, reteller)
    if not event.actor then return end

    local payload = {
        event_type = event.type,
        actor = {
            name       = event.actor.name,
            traits     = event.actor.traits,
            prominence = event.actor.prominence,
            settlement = event.location,
        },
        witness = event.witness and {
            name   = event.witness.name,
            traits = event.witness.traits,
        } or nil,
        reteller = reteller and {
            name   = reteller.name,
            traits = reteller.traits,
        } or nil,
        location    = event.location,
        hop_count   = hop_count,
        -- Context degrades with hops
        context = hop_count <= 1 and event.ctx or {
            season   = event.ctx.season,
            week     = event.ctx.week,
            year     = event.ctx.year,
            -- grain_weeks, fauna_pop etc stripped after 1 hop
        },
    }

    table.insert(ReputationSystem.narrative_payloads, payload)
    EventBus.fire("NARRATIVE_QUEUED", { payload = payload })
end

-- ── Dump payloads to file ─────────────────────────────────────────────────────

function ReputationSystem.dump_payloads()
    local lines = { "=== NARRATIVE PAYLOADS ===",
                    "Each entry is a structured prompt for LLM narrative generation.",
                    "hop_count=0: original perspective. Higher = context degraded.", "" }

    for i, p in ipairs(ReputationSystem.narrative_payloads) do
        local traits = table.concat(p.actor.traits, ", ")
        table.insert(lines, string.format("[%d] EVENT: %s  |  hop=%d", i, p.event_type, p.hop_count))
        table.insert(lines, string.format("  ACTOR:    %s  [%s]  prom=%d  in %s",
            p.actor.name, traits, p.actor.prominence, p.location))
        if p.witness then
            table.insert(lines, string.format("  WITNESS:  %s  [%s]",
                p.witness.name, table.concat(p.witness.traits, ", ")))
        end
        if p.reteller then
            table.insert(lines, string.format("  RETELLER: %s  [%s]  (degraded context)",
                p.reteller.name, table.concat(p.reteller.traits, ", ")))
        end
        if p.context then
            local ctx_parts = {}
            if p.context.season     then table.insert(ctx_parts, "season="..p.context.season) end
            if p.context.week       then table.insert(ctx_parts, "week="..p.context.week) end
            if p.context.year       then table.insert(ctx_parts, "year="..p.context.year) end
            if p.context.grain_weeks then table.insert(ctx_parts, string.format("grain_weeks=%.1f", p.context.grain_weeks)) end
            if p.context.fauna_pop  then table.insert(ctx_parts, "fauna_pop="..p.context.fauna_pop) end
            table.insert(lines, "  CONTEXT:  "..table.concat(ctx_parts, ", "))
        end
        table.insert(lines, string.format("  PROMPT:   Write 2-3 sentences from %s's perspective.", p.actor.name))
        table.insert(lines, "")
    end

    local f = io.open("narrative_payloads.txt", "w")
    if f then f:write(table.concat(lines, "\n")); f:close() end
end

return ReputationSystem
