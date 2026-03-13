---
scope: mvp
status: draft
---

# UE Prototype — Blueprint Reference
Seasons & Ecology in Unreal Engine 5.7 using primitive shapes.

---

## Architecture Overview

```
BP_SeasonManager (persistent actor)
  └── EventDispatcher: OnSeasonChanged (Season name)
  └── EventDispatcher: OnWeekTick (WeekIndex int, Season name)

BP_Zone (one per zone, 7 total)
  └── StaticMeshComponent (Plane or flat Cube, scaled by area)
  └── F_ZoneState (runtime state struct)
  └── F_ZoneDef (constant def struct, set per instance)
  └── DynamicMaterialInstance (from M_Zone master material)

BPI_ZoneDef (interface, optional) — for querying state from other systems
```

---

## Struct: [[F_ZoneDef]]
Constants. Set these on each BP_Zone instance in the Details panel.

| Variable          | Type    | Description                           |
| ----------------- | ------- | ------------------------------------- |
| ZoneID            | Name    | e.g. `river_valleys`                  |
| ZoneName          | String  | Display name                          |
| Biome             | String  | e.g. `Riverland`                      |
| Elevation         | Integer | 0–5                                   |
| AreaKm2           | Float   | For scale reference                   |
| BiomassFloor      | Float   | Min survivable biomass                |
| BiomassCap        | Float   | Maximum biomass                       |
| SoilCap           | Float   | Maximum soil fertility                |
| GrowthMult        | Float   | Zone growth multiplier                |
| RainfallMult      | Float   | Modifies weekly rainfall input        |
| EvapMult          | Float   | Modifies weekly evaporation           |
| DrainThreshold    | Float   | Water above this drains to neighbours |
| WaterlogThreshold | Float   | Water above this suppresses growth    |

---

## Struct: F_ZoneState
Runtime values. Updated each week tick.

| Variable | Type | Initial value (see table below) |
|---|---|---|
| Biomass | Float | base_biomass |
| SoilFertility | Float | base_soil |
| WaterLevel | Float | base_water |
| DroughtWeeks | Integer | 0 |
| FloodFlag | Boolean | false |
| Season | Name | `Spring` |

---

## Zone Data Table
Copy these values into each BP_Zone instance's `ZoneDef` struct.

| Zone | Elev | Area | BiomassFloor | BiomassCap | SoilCap | GrowthMult | BaseBiomass | BaseSoil | BaseWater |
|---|---|---|---|---|---|---|---|---|---|
| central_peaks | 5 | 60 | 3 | 45 | 50 | 0.55 | 22 | 38 | 35 |
| highland_forest | 4 | 180 | 12 | 100 | 100 | 1.10 | 78 | 72 | 55 |
| interior_hills | 3 | 220 | 8 | 80 | 90 | 0.90 | 60 | 65 | 45 |
| river_valleys | 2 | 120 | 15 | 95 | 100 | 1.20 | 72 | 80 | 62 |
| coastal_plains | 2 | 160 | 5 | 75 | 85 | 0.95 | 55 | 60 | 40 |
| wetlands | 1 | 90 | 18 | 90 | 95 | 1.05 | 68 | 70 | 72 |
| coastal_margin | 0 | 110 | 3 | 50 | 55 | 0.65 | 30 | 40 | 35 |

---

## Zone Visual Identity
Use flat Planes. Z-height = Elevation × 80 units (so peaks stand out visually).

| Zone | Suggested base colour | Z offset |
|---|---|---|
| Central Peaks | Mid grey (rock) | +400 |
| Highland Forest | Dark forest green | +320 |
| Interior Hills | Olive / muted green | +240 |
| River Valleys | Blue-green | +160 |
| Coastal Plains | Warm yellow-green | +160 |
| Wetlands | Desaturated teal | +80 |
| Coastal Margin | Sandy beige | 0 |

Scale each plane's XY roughly proportional to area_km2.
Suggested: `ScaleXY = sqrt(area_km2) / 4` (gives rough visual sizing).

---

## BP_SeasonManager Logic

### Variables
- `WeekIndex` (Integer, 0–51)
- `CurrentSeason` (Name — `Spring` / `Summer` / `Autumn` / `Winter`)
- `SecondsPerWeek` (Float, default `2.0` — tune for demo pacing)

### BeginPlay
```
Set Timer by Function  →  function: WeekTick  →  time: SecondsPerWeek  →  looping: true
Set WeekIndex = 0
Set CurrentSeason = Spring
```

### WeekTick function
```
WeekIndex = (WeekIndex + 1) % 52

NewSeason = GetSeasonFromWeek(WeekIndex)

IF NewSeason != CurrentSeason:
    CurrentSeason = NewSeason
    Call EventDispatcher: OnSeasonChanged(NewSeason)

Call EventDispatcher: OnWeekTick(WeekIndex, CurrentSeason)
```

### GetSeasonFromWeek (Pure function)
```
Week 0–12  → Spring
Week 13–25 → Summer
Week 26–38 → Autumn
Week 39–51 → Winter
```

---

## BP_Zone: OnWeekTick Logic

Wire this to the SeasonManager's `OnWeekTick` dispatcher in `BeginPlay`.

### Step 1 — Soil Factor
```
SoilBaseline = ZoneDef.SoilCap × 0.8
RawSF = ZoneState.SoilFertility / SoilBaseline
SoilFactor = Clamp(RawSF, 0.55, 1.0)
```

### Step 2 — Season Biomass Delta
```
SeasonDelta map:
  Spring → +9
  Summer → +5
  Autumn → -2
  Winter → -4

Delta = SeasonDelta[Season] × SoilFactor × ZoneDef.GrowthMult
ZoneState.Biomass = Clamp(Biomass + Delta, ZoneDef.BiomassFloor, ZoneDef.BiomassCap)
```

### Step 3 — Soil Recovery (Summer and Autumn only)
```
IF Season == Summer OR Season == Autumn:
    BiomassFrac = Min(1.0, ZoneState.Biomass / (ZoneDef.BiomassCap × 0.5))
    ZoneState.SoilFertility = Min(ZoneDef.SoilCap, SoilFertility + 0.8 × BiomassFrac)
```

### Step 4 — Water (simplified for prototype)
```
Weekly rainfall = 3.5 × ZoneDef.RainfallMult         (base ~3.5 units/week)
Weekly evap     = 2.0 × ZoneDef.EvapMult × SeasonEvapMult

SeasonEvapMult:
  Spring → 0.8
  Summer → 1.4
  Autumn → 0.9
  Winter → 0.5

WaterLevel = Clamp(WaterLevel + rainfall - evap, 0, 100)

IF WaterLevel > ZoneDef.DrainThreshold:
    WaterLevel = WaterLevel - (WaterLevel - DrainThreshold) × 0.5
```

### Step 5 — Waterlogging suppression (optional for prototype)
```
IF WaterLevel > ZoneDef.WaterlogThreshold:
    ZoneState.Biomass = Max(ZoneDef.BiomassFloor, Biomass - 1.0)
```

### Step 6 — Update Material
```
BiomassNorm  = (Biomass - BiomassFloor) / (BiomassCap - BiomassFloor)
SoilNorm     = SoilFertility / SoilCap
WaterNorm    = WaterLevel / 100.0

DynMat.SetScalarParam("Biomass", BiomassNorm)
DynMat.SetScalarParam("Soil",    SoilNorm)
DynMat.SetScalarParam("Water",   WaterNorm)
```

---

## M_Zone Master Material

Create one Material with three scalar params: `Biomass`, `Soil`, `Water` (all 0–1).

### Suggested colour logic (in the material graph)
```
HealthColour  = Lerp(BrownDead, DeepGreen, Biomass)     ← main signal
DrySoilShift  = Lerp(HealthColour, Tan, 1 - Soil)       ← low soil → pale/tan
WaterShift    = Lerp(DrySoilShift, SlateBlue, Water × 0.3)  ← high water → slight blue

Emissive hint (optional):
  Multiply HealthColour × 0.15 → drives subtle glow in dark season
```

Suggested colours:
- `BrownDead`  = (0.25, 0.15, 0.05)
- `DeepGreen`  = (0.05, 0.35, 0.05)
- `Tan`        = (0.65, 0.55, 0.35)
- `SlateBlue`  = (0.25, 0.35, 0.55)

---

## On-Screen Debug HUD (optional)

Add a `BP_EcologyHUD` widget with a vertical list. Each row:
```
[ZoneName]  B: 74%  S: 62%  W: 76  [Season colour badge]
```
Each BP_Zone registers itself with the HUD on BeginPlay.
HUD refreshes on `OnWeekTick`.

---

## Build Order

1. **BP_SeasonManager** → confirm seasons cycle in output log
2. **M_Zone material** → test with hard-coded scalar values
3. **One BP_Zone** (use `river_valleys` — most stable) → wire season delta, confirm colour changes
4. **Replicate to all 7 zones** → place on map, set ZoneDef values per instance
5. **HUD widget** → add debug readout
6. **Weather stubs** → random chance per week, log to screen, no visuals yet
7. **Weather visuals** → Niagara burst + material flash when event fires

---

## Season Colour Palette (for UI / sky tinting)

| Season | Suggested sky tint | Ground fog tint |
|---|---|---|
| Spring | Soft cyan-white | Pale green |
| Summer | Warm gold | Clear |
| Autumn | Amber-orange | Rust |
| Winter | Cool grey-blue | Near white |
