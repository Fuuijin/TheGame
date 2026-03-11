---
scope: mvp
status: draft
---

# Seasons & Cycles

The primary simulation clock. All living systems tick relative to the seasonal cycle. Season is a **global state** — server authority, daily tick.

---

## The Four Seasons

| Season | Key Pressures |
|---|---|
| **Spring** | Planting window, birth cycles, snowmelt, flooding risk, dysentery outbreak |
| **Summer** | Peak growth, long days, drought risk, road travel at 100%, military levies, summer fairs |
| **Autumn** | Harvest glut, animal migration/fattening, tithe collection, pre-winter hoarding |
| **Winter** | Food scarcity, cold danger, reduced travel (20% road capacity), faction conflict over resources, elderly/infant mortality spike |

---

## Simulation Layers

The season system drives five nested layers. Each layer depends on the one above it — ecology sets the conditions that resources respond to, resources drive economic pressure, economic pressure shapes population outcomes, and population stress produces world events.

### L1 — Ecology & World Growth

The ecological baseline. Drives all downstream layers.

- **Flora:** Biomass growth rates, crop viability windows, forest regrowth speed
- **Fauna:** Population cycles, migration patterns, predator/prey balance
- **Soil & Water:** Fertility levels, river flow, flood/drought state
- **Weather Events (rolls):** Flood, drought, late frost, blight, blizzard, river freeze

### L2 — Base Resources

What the world actually produces. Determined by L1 conditions.

**Core resource set:** Grain | Livestock | Timber | Iron | Fuel (wood/peat) | Salt | Water | Forage

**Key seasonal dynamics:**
- Grain planted in spring, harvested in autumn — no harvest = famine the following winter
- Salt scarcity in autumn translates directly to winter starvation (preservation failure)
- Fuel demand is 4× higher in winter

### L3 — Economy & Trade

Prices and trade flow respond to seasonal resource state.

**Price formula:** `BaseCost × (Demand / Stock) × SeasonPressure [0.5x – 5.0x]`

**Seasonal price examples:**
- Spring: grain 3–4× (post-winter scarcity)
- Autumn: grain 0.8× (harvest glut)
- Pre-winter: hoarding spikes October prices across most commodities

**Travel & trade capacity:**
- Summer: roads at 100%
- Winter: roads at 20% (mud, snow, ice)

**Social/economic events:**
- Summer fairs (trade volume boost, faction relations opportunity)
- Tithe collection in autumn (village→faction wealth transfer)
- Active guilds: farming / merchant / blacksmith

### L4 — Population

Population responds to accumulated economic and ecological pressure.

- **Morale:** 0–100 scale. Below 10 → revolt
- **Starvation threshold:** < 0.6 food/day sustained for 4 weeks
- **Seasonal mortality:** Winter spikes elderly and infant death; spring dysentery; summer malaria
- **Migration:** Population flees famine conditions, follows available food
- **Military levy:** 10–20% of able men levied in summer (faction-driven)

Population feeds back into L3 (wages/prices) and draws from it (labour pool).

### L5 — World Events & Player Experience

Emergent threats that trace back to simulation root causes — no scripted events, no monsters.

- **Famine** — L2 grain failure sustained across a region
- **Plague** — L4 population density + seasonal disease roll
- **Revolt** — L4 morale below threshold
- **War / Bandits** — faction pressure + resource competition (L3) + population desperation (L4)

> All threats trace to simulation root causes — no scripted events, no monsters.

---

## Cycle Structure

- One full year = [TBD] real-time — **recommendation from design session: 14 real days per season (56 days/year)**
- **Daily tick** — season state updates; weather rolls; minor ecology/resource deltas
- **Weekly tick** — ecology simulation step; resource manager update; economy update
- **Monthly tick** — population simulation step
- **Multi-year drift** — forest regrowth, soil recovery, long-term ecological shifts

## Secondary Cycles

- **Day/Night:** NPC schedules, player visibility, danger levels
- **Weather:** Regional, season-weighted (V2: full weather simulation)
- **Multi-year:** Long-term ecological drift (forest regrowth takes years, not days)

---

## UE5.7 Architecture

**Design principle:** Component ownership is explicit. All cross-system coupling routes through the `SimulationEventBus` — systems are independently testable and swappable.

| System | Type | Tick Rate | Role |
|---|---|---|---|
| `SeasonSubsystem` | `UWorldSubsystem` (C++) | Daily | Global season state authority |
| `SimulationEventBus` | `UGameInstanceSubsystem` | Event-driven | Only cross-system coupling point |
| `SeasonModifierTable` | `UDataTable` | Caches on season change | Designer-editable season multipliers |
| `EcologySimulator` | `UWorldSubsystem` | Weekly | L1 flora/fauna/soil state |
| `ResourceManager` | `UGameInstanceSubsystem` | Weekly | L2 resource stock tracking |
| `EconomySubsystem` | `UWorldSubsystem` | Weekly | L3 price simulation, trade routing |
| `PopulationSimulator` | `UWorldSubsystem` | Monthly | L4 births/deaths/morale/migration |
| `WorldTileComponent` | `UActorComponent` | Batch (per tile) | Per-tile state, receives batch updates |

**Data flow:** `SeasonSubsystem` fires season-change events → `SimulationEventBus` → all subsystems re-cache from `SeasonModifierTable` and update their state.

---

## Open Questions

- [ ] **Season cycle length** — Recommendation: 14 real days per season (56 days/year). Gives players time to invest in each season without the year feeling trivial. Needs playtesting. *(Pending decision)*
- [ ] **Biome variation near equator** — Does the 40×40 km map have enough latitude range to warrant meaningfully different seasonal intensity by region? Southern biomes milder winters, northern harsher? *(Pending decision)*
- [ ] **Year-number difficulty scaling** — Does the simulation get harder as legacy years accumulate? Options: harder starting conditions, more aggressive factions, ecological depletion carrying forward. *(Pending decision)*
- [ ] **Player housing & seasons** — How does the player's shelter situation interact with the season system? Sleeping rough in winter = cold/disease risk; owning a homestead = fuel dependency. Needs design. *(Pending decision)*
- [ ] Does the player experience a time-skip between sessions, or does simulation time only advance in real-time?
- [ ] What is the minimum viable commodity list for L2? (Scope discipline: keep it small)
- [ ] At what tile resolution does `WorldTileComponent` operate? (Per village? Per biome chunk?)
- [ ] How does the player *read* the simulation — direct UI data or inference from world state?

---

**Links:** [[Ecology Overview]] | [[Vegetation]] | [[Wildlife]] | [[Economy Overview]] | [[Villages]] | [[Factions]]
