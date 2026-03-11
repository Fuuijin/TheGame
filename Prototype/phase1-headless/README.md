---
scope: mvp
status: draft
---

# Phase 1 Prototype — Headless Simulation

No player. No graphics. Just the world running.

This prototype proves the simulation cascade works: **seasons tick → ecology responds → resources deplete → prices move → villages react**.

## Running

### Love2D (visual log viewer)
```
love .
```
Runs in a coloured scrollable terminal window. Arrow keys / PgUp / PgDn to browse. ESC to quit.

### Plain Lua (terminal output)
```
lua main.lua
```
Or point to a specific Lua binary:
```
/path/to/lua5.4 main.lua
```

## What it simulates

**Tick structure** (matching the UE5 design):

| Tick | Frequency | Systems |
|---|---|---|
| Daily | Every sim day | SeasonSubsystem clock advance |
| Weekly | Every 7 days | EcologySimulator, ResourceManager, EconomySubsystem |
| Monthly | Every 14 days | PopulationSimulator (births/deaths/morale) |
| Weather | Weekly roll | Probability table per season |

**5-layer cascade** (L1→L5):

1. **L1 — EcologySimulator**: Biomass grows/shrinks by season (+8/wk spring, −12/wk winter). Weather events (flood, drought, frost, blizzard, blight) hit tile ecology. Biome modifiers apply (Upland winters are 1.4× severity).

2. **L2 — ResourceManager**: Grain (annual calendar: plant spring, harvest autumn), livestock, timber, fuel, salt, water, forage. Fuel demand 4× higher in winter. Salt scarcity in autumn reduces winter food preservation. No crop planted → famine incoming.

3. **L3 — EconomySubsystem**: Price formula: `BaseCost × (ExpectedDemand / Stock) × SeasonPressure [0.5x–5.0x]`. Rolling 4-week demand average. Travel capacity at 20% in winter (trade suppressed). Pre-winter hoarding spike.

4. **L4 — PopulationSimulator**: Morale (0–100). Starvation trigger at < 2 weeks of grain reserve, sustained 4 weeks → famine. **Revolt contagion**: revolts spread to low-morale neighbours within 2 weeks. Winter mortality spike (elderly, infant). Seasonal disease risk from ecology.

5. **L5 — World Events**: Emergent from simulation state. No scripted events. All logged to console.

## Architecture

All cross-system coupling routes through `SimulationEventBus`. Systems subscribe to event types and fire events; they never hold direct references to each other.

```
main.lua
└── systems/
    ├── event_bus.lua          -- SimulationEventBus (sole coupling point)
    ├── season_subsystem.lua   -- Global clock, weather rolls
    ├── ecology_simulator.lua  -- L1: biomass, soil, fauna per tile
    ├── resource_manager.lua   -- L2: resource stocks per settlement
    ├── economy_subsystem.lua  -- L3: prices, trade capacity
    └── population_simulator.lua -- L4: morale, starvation, revolt
```

## Observed behaviour (3-year run, seed 12345)

**Year 1** — stable. Harvest fires in Autumn. Morale rises through summer. Blizzard (severe) in Winter W8 kills livestock and drains fuel.

**Year 2** — cascade begins. Biomass crashes from ecology debt of bad winter. Without biomass → no forage → livestock starve. Brackenmere and Stonekeep run out of seed grain (< 10 units needed to plant). Revolt in Summer (Brackenmere), then Stonekeep, then Millhaven in Autumn.

**Year 3** — collapse. No harvest for 3 of 4 settlements. Universal famine. All settlements in revolt by Year 3.

The event chain (`Blizzard → livestock dead → forage zero → no seed grain → no harvest → famine → revolt`) matches the design doc's `drought → blight → famine → revolt` cascade structure.

**This is working as designed.** Recovery requires player intervention (Phase 2) — trade, labour redirection, faction aid, rationing decisions. Without those levers, a single severe weather event triggers a death spiral.

## Open questions revealed by this prototype

- [ ] Biomass recovery from 0 — should there be a minimum baseline (seeds in soil, root systems) that prevents complete ecological death? Currently once biomass = 0 there's no growth signal.
- [ ] Minimum viable seed grain mechanic — should a faction or event provide emergency grain to restart collapsed settlements?
- [ ] Difficulty tuning — is one severe blizzard triggering a 3-year collapse too punishing? Needs playtesting with Phase 2 player tools.
- [ ] Trade routes — even basic inter-settlement trade (Ashford shares grain with Stonekeep) would break the isolation that makes the cascade so total.

## What Phase 2 adds

The player character enters the world. They can:
- Direct labour (ensure crops are planted, fuel cut, grain stored)
- Make trade decisions (buy grain from other settlements at price)
- Influence faction relations (unlock aid, levy exemptions)
- Manage their own survival (food, shelter, cold damage)

The simulation runs whether or not the player acts — they experience the consequences of inaction as readily as action.
