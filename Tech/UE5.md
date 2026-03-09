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

## Constraints / Risks
- UE 5.7 is not yet released as of this writing — track release notes
- Mass Entity has a learning curve; architecture decisions early matter
- Simulation complexity (economy + ecology + social) needs careful profiling
- Team of 2 — avoid engine customization that creates maintenance debt

## Open Questions
- [ ] What's the target hardware spec? (Affects Lumen/Nanite settings)
- [ ] Are we using C++ or Blueprints as primary? (Recommend: C++ for simulation systems, BP for gameplay iteration)
- [ ] World authoring pipeline: Houdini for terrain? Manual biome placement?

**Links:** [[World Overview]] | [[Physics]] | [[Scope]] | [[Ecology Overview]]
