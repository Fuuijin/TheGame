---
scope: mvp
status: draft
---

# World Overview

The physical container of the game. A hand-crafted 40×40 km medieval world.

---

## Specs
| Property | Value |
|---|---|
| Size | 40 × 40 km |
| Layout | Fixed (not procedurally generated) |
| Biomes | Set — see [[Biomes Overview]] |
| Era | 13th century Europe-adjacent |
| Engine | UE 5.7 |

## Design Approach
The world is **fixed geography** — mountains, rivers, coastlines, and biome placement are authored, not generated. This:
- Allows deliberate design of trade routes, chokepoints, and faction territories
- Makes the graph of connections between places legible and authorable
- Keeps scope manageable for a two-person team

Procedural generation is deferred to [[Scope|Dream tier]].

## World Structure
- Terrain anchors biome placement
- Rivers define trade and village siting
- Elevation affects climate, ecology, and travel difficulty
- Coastlines provide maritime trade potential

## Starting State
The world begins with:
- [TBD] pre-placed villages / towns across the 40×40 km
- [TBD] factions with starting territories
- [TBD] ecological baseline per biome

## Open Questions
- [ ] Is there a single continent, or islands/coast?
- [ ] What's the player's starting region? Fixed or chosen?
- [ ] What tools will be used for world authoring in UE 5.7? (World Partition, Houdini, manual)

**Links:** [[Biomes Overview]] | [[Social Overview]] | [[Ecology Overview]] | [[UE5]]
