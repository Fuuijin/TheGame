-- SituationEngine
-- World pressure generates situations. Traits determine how nearby entities respond.
-- This is where the Tom-and-Bob scenarios emerge — no scripting, only pressure + traits.
--
-- Situations currently modelled:
--   SCARCITY       grain reserves below 2.5 weeks
--   PREDATOR_NEAR  hungry wildlife near a settlement (low forage, high fauna_pop)
--   SURPLUS_OFFER  a settlement has significant excess and a generous entity notices

local SituationEngine = {}
SituationEngine._log = {}

-- External refs injected at init
local EM, RS, EventBus, ResourceManager, PopulationSimulator, EcologySimulator, NEIGHBOURS

function SituationEngine.init(deps)
    EM                 = deps.EntityManager
    RS                 = deps.ReputationSystem
    EventBus           = deps.EventBus
    ResourceManager    = deps.ResourceManager
    PopulationSimulator= deps.PopulationSimulator
    EcologySimulator   = deps.EcologySimulator
    NEIGHBOURS         = deps.NEIGHBOURS
end

local function log(msg)
    table.insert(SituationEngine._log, msg)
    if #SituationEngine._log > 300 then table.remove(SituationEngine._log, 1) end
end

function SituationEngine.get_log() return SituationEngine._log end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function weeks_of_grain(sid)
    local grain = (ResourceManager.stocks[sid] or {}).Grain or 0
    local ps    = PopulationSimulator.pop_state[sid]
    if not ps or ps.population == 0 then return 99 end
    local weekly_need = 8 * (ps.population / 100)
    return grain / weekly_need
end

local function get_tile_for_settlement(sid)
    -- EcologySimulator tiles are keyed by a tile_id that matches settlement_id in phase2
    return EcologySimulator.tiles[sid]
end

local function others_in(sid, exclude_id)
    local out = {}
    for _, e in ipairs(EM.by_settlement[sid] or {}) do
        if e.id ~= exclude_id then table.insert(out, e) end
    end
    return out
end

-- ── Scarcity resolution ───────────────────────────────────────────────────────

local SITUATION_COOLDOWN = 3  -- weeks before an entity may respond to another situation

local function resolve_scarcity(entity, sid, weeks_left, ctx)
    if entity.situation_cooldown > 0 then return end
    local r = math.random()

    -- GREEDY + IMPULSIVE → hoard / steal from neighbour
    if EM.has_trait(entity, "greedy") and EM.has_trait(entity, "impulsive") then
        if r < 0.55 then
            local neighbours = NEIGHBOURS[sid] or {}
            local took = false
            for _, nsid in ipairs(neighbours) do
                local nstocks = ResourceManager.stocks[nsid]
                if nstocks and (nstocks.Grain or 0) > 25 then
                    nstocks.Grain = nstocks.Grain - 4
                    ResourceManager.stocks[sid].Grain = (ResourceManager.stocks[sid].Grain or 0) + 4
                    took = true
                    break
                end
            end
            if took then
                local witness = others_in(sid, entity.id)[1]
                RS.record_event({
                    type="hoarding_theft", actor=entity, witness=witness,
                    location=sid, ctx=ctx, infamy_delta=8,
                })
                EM.add_narrative_trait(entity, "hoarder", ctx, EventBus)
                entity.situation_cooldown = SITUATION_COOLDOWN
                log(string.format("[Y%d W%02d] %s (greedy+impulsive) seized grain during scarcity in %s",
                    ctx.year, ctx.week, entity.name, sid))
                EventBus.fire("SITUATION_FIRED", {situation_type="hoarding_theft", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
            end
        end

    -- COMPASSIONATE → share from personal stores
    elseif EM.has_trait(entity, "compassionate") then
        if r < 0.55 then
            ResourceManager.stocks[sid].Grain = (ResourceManager.stocks[sid].Grain or 0) + 5
            local witness = others_in(sid, entity.id)[1]
            RS.record_event({
                type="charitable_act", actor=entity, witness=witness,
                location=sid, ctx=ctx, honour_delta=6,
            })
            EM.add_narrative_trait(entity, "generous_soul", ctx, EventBus)
            entity.situation_cooldown = SITUATION_COOLDOWN
            log(string.format("[Y%d W%02d] %s (compassionate) shared stores during scarcity in %s",
                ctx.year, ctx.week, entity.name, sid))
            EventBus.fire("SITUATION_FIRED", {situation_type="charitable_act", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
        end

    -- IMPULSIVE alone → public confrontation with another entity
    elseif EM.has_trait(entity, "impulsive") then
        if r < 0.30 then
            local targets = others_in(sid, entity.id)
            if #targets > 0 then
                local target = targets[math.random(#targets)]
                RS.record_event({
                    type="public_confrontation", actor=entity, witness=target,
                    location=sid, ctx=ctx, infamy_delta=3,
                })
                entity.situation_cooldown = SITUATION_COOLDOWN
                log(string.format("[Y%d W%02d] %s (impulsive) caused a public confrontation in %s",
                    ctx.year, ctx.week, entity.name, sid))
                -- Law-and-order witness responds
                if EM.has_trait(target, "law_order") then
                    RS.record_event({
                        type="confrontation_reported", actor=target, witness=nil,
                        location=sid, ctx=ctx, honour_delta=4,
                    })
                    log(string.format("[Y%d W%02d]   -> %s (law_order) took note and reported it",
                        ctx.year, ctx.week, target.name))
                end
                EventBus.fire("SITUATION_FIRED", {situation_type="public_confrontation", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
            end
        end

    -- LAW_ORDER → inspect and report on anyone with infamy in the settlement
    elseif EM.has_trait(entity, "law_order") then
        for _, other in ipairs(others_in(sid, entity.id)) do
            if other.infamy > 5 and r < 0.35 then
                RS.record_event({
                    type="public_accusation", actor=entity, witness=other,
                    location=sid, ctx=ctx, honour_delta=5,
                })
                entity.situation_cooldown = SITUATION_COOLDOWN
                log(string.format("[Y%d W%02d] %s (law_order) publicly accused %s in %s",
                    ctx.year, ctx.week, entity.name, other.name, sid))
                break
            end
        end

    -- CAUTIOUS → organises quiet rationing; no drama, modest respect earned
    elseif EM.has_trait(entity, "cautious") then
        if r < 0.25 then
            RS.record_event({
                type="quiet_rationing", actor=entity, witness=others_in(sid, entity.id)[1],
                location=sid, ctx=ctx, honour_delta=3,
            })
            entity.situation_cooldown = SITUATION_COOLDOWN
            log(string.format("[Y%d W%02d] %s (cautious) organised quiet rationing in %s",
                ctx.year, ctx.week, entity.name, sid))
            EventBus.fire("SITUATION_FIRED", {situation_type="quiet_rationing", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
        end

    -- GENTLE → calms tensions quietly; prevents confrontations from escalating
    elseif EM.has_trait(entity, "gentle") then
        -- Check if anyone in the settlement recently caused trouble
        local troublemaker = nil
        for _, other in ipairs(others_in(sid, entity.id)) do
            if other.infamy > 3 then troublemaker = other; break end
        end
        if troublemaker and r < 0.30 then
            RS.record_event({
                type="tensions_calmed", actor=entity, witness=troublemaker,
                location=sid, ctx=ctx, honour_delta=4,
            })
            EM.add_narrative_trait(entity, "peacemaker", ctx, EventBus)
            entity.situation_cooldown = SITUATION_COOLDOWN
            log(string.format("[Y%d W%02d] %s (gentle) calmed tensions in %s",
                ctx.year, ctx.week, entity.name, sid))
            EventBus.fire("SITUATION_FIRED", {situation_type="tensions_calmed", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
        end
    end
end

-- ── Predator resolution ───────────────────────────────────────────────────────

local function resolve_predator(entity, sid, fauna_pop, ctx)
    if entity.situation_cooldown > 0 then return end
    local r = math.random()

    if EM.has_trait(entity, "brave") then
        if r < 0.45 then
            RS.record_event({
                type="predator_confronted", actor=entity, witness=nil,
                location=sid, ctx=ctx, honour_delta=12,
            })
            EM.add_narrative_trait(entity, "wolf_fighter", ctx, EventBus)
            entity.situation_cooldown = SITUATION_COOLDOWN
            log(string.format("[Y%d W%02d] %s (brave) drove off wildlife threatening %s",
                ctx.year, ctx.week, entity.name, sid))
            EventBus.fire("SITUATION_FIRED", {situation_type="predator_confronted", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
        end

    elseif EM.has_trait(entity, "compassionate") then
        if r < 0.35 then
            RS.record_event({
                type="protected_villager", actor=entity, witness=nil,
                location=sid, ctx=ctx, honour_delta=15,
            })
            EM.add_narrative_trait(entity, "protector", ctx, EventBus)
            entity.situation_cooldown = SITUATION_COOLDOWN
            log(string.format("[Y%d W%02d] %s (compassionate) intervened to protect villagers in %s",
                ctx.year, ctx.week, entity.name, sid))
            EventBus.fire("SITUATION_FIRED", {situation_type="protected_villager", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
        end

    elseif EM.has_trait(entity, "gentle") then
        -- Guides livestock to safety quietly; not heroic but earns quiet respect
        if r < 0.35 then
            RS.record_event({
                type="livestock_sheltered", actor=entity, witness=others_in(sid, entity.id)[1],
                location=sid, ctx=ctx, honour_delta=6,
            })
            entity.situation_cooldown = SITUATION_COOLDOWN
            log(string.format("[Y%d W%02d] %s (gentle) sheltered livestock from predators in %s",
                ctx.year, ctx.week, entity.name, sid))
            EventBus.fire("SITUATION_FIRED", {situation_type="livestock_sheltered", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
        end

    elseif EM.has_trait(entity, "cowardly") then
        if r < 0.55 then
            RS.record_event({
                type="fled_danger", actor=entity, witness=others_in(sid, entity.id)[1],
                location=sid, ctx=ctx, infamy_delta=5,
            })
            EM.add_narrative_trait(entity, "coward", ctx, EventBus)
            entity.situation_cooldown = SITUATION_COOLDOWN
            log(string.format("[Y%d W%02d] %s (cowardly) fled when wildlife threatened %s",
                ctx.year, ctx.week, entity.name, sid))
            EventBus.fire("SITUATION_FIRED", {situation_type="fled_danger", settlement_id=sid, week=ctx.week, year=ctx.year, season=ctx.season})
        end
    end
end

-- ── Surplus resolution ────────────────────────────────────────────────────────

local function check_surplus(sid, week, year, season)
    local grain = (ResourceManager.stocks[sid] or {}).Grain or 0
    local surplus_thresh = (CONFIG and CONFIG.surplus_threshold) or 70
    if grain < surplus_thresh then return end
    local entities = EM.by_settlement[sid] or {}
    for _, entity in ipairs(entities) do
        if EM.has_trait(entity, "generous") and math.random() < 0.30 then
            local ctx = {week=week, year=year, location=sid, season=season, grain=grain}
            RS.record_event({
                type="public_generosity", actor=entity, witness=nil,
                location=sid, ctx=ctx, honour_delta=5,
            })
            EM.add_narrative_trait(entity, "generous_soul", ctx, EventBus)
            log(string.format("[Y%d W%02d] %s (generous) announced surplus distribution in %s",
                year, week, entity.name, sid))
            break
        end
    end
end

-- ── Weekly tick ───────────────────────────────────────────────────────────────

function SituationEngine.weekly_tick(week, year, season)
    for sid, _ in pairs(ResourceManager.stocks) do
        local ctx = {week=week, year=year, season=season, location=sid}

        -- SCARCITY
        local scarcity_thresh = (CONFIG and CONFIG.scarcity_threshold) or 2.5
        local wg = weeks_of_grain(sid)
        if wg > 0.3 and wg < scarcity_thresh then
            for _, entity in ipairs(EM.by_settlement[sid] or {}) do
                ctx.grain_weeks = wg
                resolve_scarcity(entity, sid, wg, ctx)
            end
        end

        -- PREDATOR_NEAR (autumn/winter only when fauna hungry)
        local predator_forage = (CONFIG and CONFIG.predator_min_forage) or 20
        if season == "Autumn" or season == "Winter" then
            local tile = get_tile_for_settlement(sid)
            if tile and tile.fauna_pop > 2 and tile.biomass < predator_forage then
                for _, entity in ipairs(EM.by_settlement[sid] or {}) do
                    ctx.fauna_pop = tile.fauna_pop
                    resolve_predator(entity, sid, tile.fauna_pop, ctx)
                end
            end
        end

        -- SURPLUS
        check_surplus(sid, week, year, season)
    end

    EM.weekly_decay()
end

return SituationEngine
