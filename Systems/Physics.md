---
scope: v2
status: draft
---

# Physics

Light physics and environmental simulation as a living-world feature.

---

## Scope Note
Full light physics simulation is **V2**. MVP uses UE 5.7's Lumen for atmospheric lighting tied to time-of-day and seasons.

---

## Target Features (V2)
- Volumetric lighting driven by season, time of day, weather
- Light quality shifts with latitude and season (low winter sun, harsh summer noon)
- Atmospheric effects: fog, rain light scatter, snow diffusion

## UE 5.7 Foundation
- Lumen: fully dynamic global illumination — no baked lighting
- Nanite: high-fidelity environment without LOD management
- Volumetric clouds and fog: built-in, configurable per biome/season

## Integration
- Seasons → lighting angle and quality
- Weather → fog, rain, overcast diffusion
- Biome → base atmospheric look (e.g., forest canopy vs. open steppe)

## Open Questions
- [ ] What's the perf budget for light physics on target hardware?
- [ ] Are there gameplay mechanics tied to light (e.g., shadows for stealth)?

**Links:** [[UE5]] | [[Seasons & Cycles]] | [[Biomes Overview]] | [[Scope]]
