---
scope: mvp
status: draft
---

# UE 5.7

Unreal Engine 5.7 — engine notes, relevant features, constraints, and open questions.

---

## Why UE 5.7
- Nanite + Lumen suit a large, visually rich living world without baked-lighting overhead
- World Partition enables streaming a 40×40 km map
- Strong simulation tooling (Mass Entity, large-world coordinates)
- Team has existing UE experience

## Key Features in Use

| Feature | Purpose |
|---|---|
| **World Partition** | Streaming 40×40 km world without manual level management |
| **Nanite** | High-fidelity static meshes (forests, terrain) without LOD work |
| **Lumen** | Fully dynamic global illumination (no baked lighting) |
| **Mass Entity (ECS)** | High-count NPC/creature simulation (villagers, wildlife) |
| **PCG (Procedural Content Generation)** | Vegetation placement, world dressing |
| **Chaos Physics** | Physical simulation where needed |

## Version Control
- **Provider:** Diversion (diversion.dev) — Git-compatible, UE-native plugin
- **Project name:** TheStorySoFar (working name)
- Diversion plugin installed directly in UE — source control is active from within the editor

---

## Mass Entity (ECS) — Deep Notes

Mass is UE's data-oriented ECS framework, originally built for crowd and traffic simulations. Primary use here: villagers, wildlife, soldiers, merchants as high-count simulated agents.

### Core Concepts

| Term | What it is |
|---|---|
| **Fragment** | Atomic data struct (`FMassFragment`) — one piece of per-entity state (e.g. position, health, hunger) |
| **Shared Fragment** | Data shared across many entities (`FMassSharedFragment`) — must be CRC hashable |
| **Tag** | Empty struct (`FMassTag`) — no data, used to filter entities (e.g. `IsHungryTag`, `IsInCombatTag`) |
| **Trait** | Named collection of fragments + initial values — think "role" (e.g. Villager trait = Transform + Health + Faction + NeedsTag) |
| **Archetype** | A unique combination of traits/tags — entities with identical composition share an archetype |
| **Entity** | A runtime instance of an archetype — an integer ID pointing to fragment data |
| **Processor** | Stateless system that queries and operates on entities each tick |
| **Observer Processor** | Fires on add/remove operations rather than every tick |

### Memory Layout
Entities in an archetype are stored in **Chunks** — contiguous memory blocks optimized for cache (128-byte lines × 1024 lines). Processors receive whole chunks, not individual entities — this is why Mass is fast at scale.

### LOD System
Mass has a built-in LOD subsystem that outputs four tiers: **High / Medium / Low / Off**, with configurable distances and entity count caps per tier. Use this to:
- Run full AI only on nearby agents (High LOD)
- Run simplified tick-rate simulation on mid-range agents (Low LOD)
- Suspend per-entity simulation entirely at distance (Off) — fall back to aggregate regional modeling

This is critical for the living world: villagers far from the player can be aggregate stats, not individual agents.

### Plugin Stack
```
MassEntity         ← core ECS
MassGameplay       ← movement, LOD, spawning, replication
MassAI             ← navigation, behaviors, SmartObjects
MassCrowd          ← crowd/traffic (extends MassAI)
```

### StateTree Integration
Mass integrates with **StateTree** for NPC state management — cleaner than manual processor chains for complex behavior. Recommended for named NPCs and wildlife with distinct behavioral states.

### Spawning
- Use `AMassSpawner` with an `EntityConfig` Data Asset (specifies traits) and a **Spawn Data Generator** (defines placement — EQS, ZoneGraph, or custom)
- Custom generators extend `UMassEntitySpawnDataGeneratorBase`

### Key Gotchas
- **Entity mutations during processing must be deferred** via `Context.Defer()` — you cannot change an entity's composition mid-chunk without destabilizing it
- **Entity indices are volatile** — chunks reorganize; always use `FMassEntityHandle` for stable references, never raw indices
- **Shared fragments must be CRC hashable** — easy to miss, causes silent instantiation failures
- **Observer processors only fire during specific operations** — not on every state change; understand the trigger list before relying on them
- **Cache subsystem pointers in processors** — random lookups inside tight loops kill the performance benefit of ECS

### Relevance for TheGame
- Villagers (aggregate by default, individual when player is nearby) → Mass LOD tiers
- Wildlife populations → Mass with ecology fragment (hunger, herd, season-state)
- Merchants / caravans → Mass with pathfinding + trade-state fragments
- Named NPCs → likely standard AActor with richer state; Mass for crowd-level agents only

---

## World Partition — Deep Notes

World Partition replaces manual level streaming. The world is divided into **spatial cells** that load/unload dynamically based on streaming sources (usually the player controller).

### How It Works
- Actors have an **Is Spatially Loaded** flag — if true, they load only when a streaming source is within range
- **Data Layers** add a second conditional gate — actors in a disabled data layer won't load regardless of proximity. Use for: seasonal content, faction-specific actors, quest-gated content
- **HLOD (Hierarchical LOD)** renders distant geometry as simplified proxies — essential for a 40×40 km map where the player can see far

### Data Layers — Use Cases for TheGame
| Data Layer | Use |
|---|---|
| Season_Winter / Season_Summer etc. | Swap vegetation, snow cover, frozen rivers |
| Faction_[Name] | Load faction-specific actors (camps, banners) |
| (Future) Quest-gated content | Load dungeon/event content on trigger |

### Key Points
- One File Per Actor (OFPA) is required for World Partition — each actor is its own asset file. Important for Diversion source control (fewer merge conflicts on actors)
- PCG components should be set to **Is Partitioned** when using World Partition — enables streaming of generated content
- Navigation mesh also supports World Partition streaming (`World Partitioned Navigation Mesh`)

### Constraints
- Cell size and grid configuration are set in **Runtime Grid Settings** per actor — default grid works for most cases, custom grids for special streaming needs
- Large worlds with many always-loaded actors can still cause issues — audit `Is Spatially Loaded = false` actors carefully

---

## PCG (Procedural Content Generation) — Deep Notes

PCG is a node-graph system for placing content procedurally — primarily vegetation, rocks, and world dressing. Not procedural world *generation* (the map is fixed) — procedural *population* of a fixed map.

### Core Concept
PCG graphs take **input data** (terrain height, biome mask, splines, volumes) and output **spawned meshes or actors** according to rules. Graphs are reusable and data-driven.

### Biome Core Plugin
UE ships a **PCG Biome Core plugin** — a data-driven biome creation tool:
- Unlimited user-defined biomes, spatially defined from volumes, splines, or textures
- Supports mesh spawning, PCG Data Assets, PCG Assemblies, and actor spawning
- Works with **Attribute Set Tables** (data tables driving biome variation), feedback loops, and recursive sub-graphs

### World Partition Integration
- Enable **Is Partitioned** on the BiomeCore PCG Component to stream generated content with World Partition
- Default partition chunk size: **256×256 meters** (configurable via PCG World Actor's Partition Grid Size)
- This means vegetation loads/unloads with the world, not all at once — essential for 40×40 km

### GPU Processing
PCG supports GPU-accelerated graph execution — useful for dense vegetation passes. Opt-in per node.

### Relevance for TheGame
- Biome Core plugin is the right tool for populating the set biomes with vegetation
- Each biome gets a Data Asset defining its tree/shrub/grass palette and density rules
- Seasonal variation: swap PCG Data Assets or use Data Layers to change vegetation by season
- Deforestation: remove PCG-spawned trees when player clears land (runtime generation)

---

## Constraints / Risks
- Simulation complexity (economy + ecology + social + Mass) needs early profiling — don't assume it scales
- Mass Entity architecture decisions made early are hard to refactor — plan fragment/trait structure before building
- OFPA (One File Per Actor) + Diversion: understand merge workflow for actor files
- Team of 2 — avoid deep engine customization that creates maintenance debt

## Open Questions
- [ ] Target hardware spec? (Drives Lumen quality, Mass LOD distances, PCG density)
- [ ] C++ vs Blueprints split? (Recommend: C++ for simulation systems — Mass, economy, ecology; BP for gameplay iteration)
- [ ] World authoring pipeline: Houdini for terrain? Landscape tool? Manual biome volumes?
- [ ] At what player distance do villagers drop from individual Mass agents to aggregate regional counters?

**Links:** [[World Overview]] | [[Physics]] | [[Scope]] | [[Ecology Overview]] | [[Biomes Overview]]
