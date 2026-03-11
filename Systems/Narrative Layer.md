---
scope: v2
status: defined
---

# Narrative Layer

The Narrative Layer translates simulation events into human-readable prose. It does not decide what happens — the simulation does that entirely in data. The Narrative Layer is a renderer: it takes a structured event, the actors involved, their traits, the location, and the propagation context, and produces a few lines of text describing that moment from a specific character's point of view.

The simulation and the Narrative Layer run on completely separate clocks. They do not block each other.

---

## Core Principle

The LLM is not the engine. It is the voice.

Nothing about what happens in the world is determined by generation. Events, consequences, reputation changes, and propagation all resolve in the simulation first. The Narrative Layer only runs afterward, asynchronously, to give those events a human shape.

---

## Generation Queue

When a simulation event crosses the narrative threshold (see below), it is placed in a **generation queue** as a structured prompt payload. The queue is processed whenever the system has spare cycles — between ticks, during loading, or in a background thread. Generation does not block gameplay at any point.

Each payload contains:
- **Event type** — theft, rescue, confrontation, death, betrayal, etc.
- **Actors** — name, traits, current prominence score, relationship to each other
- **Location** — settlement name, biome, region
- **World context** — season, recent pressures on the location (famine, conflict, prosperity)
- **Propagation hop count** — how many hands this story has passed through (0 = original perspective; higher = degraded context)

The hop count is critical. A story told from the perspective of the person who was there receives full context. A story told three hops later, through a gossip and a loudmouth, receives stripped context. The LLM renders whatever it is handed. The distortion is mechanical, not invented.

### Narrative Threshold

Not every event generates a narrative. Generation fires when:
- A story reaches a **public venue** (tavern, market, church) — it has become social
- A **named character** is involved as actor or witness — it is already significant
- A propagation chain produces a **named entity crystallisation** — a character just crossed the prominence threshold

Everything below this threshold stays as silent simulation data.

---

## The Story Pool

Completed narratives are placed in a **story pool** — a categorised collection of generated text, waiting to be consumed.

### Categorisation Axes

| Axis | Purpose |
|---|---|
| **Geography** | Which settlement or road the event occurred near |
| **Recency** | Week and year generated; stories age and eventually expire |
| **Propagation reach** | How widely the story spread; determines how far from origin it can be known |
| **Subject** | Named characters involved; enables player lookup |
| **Tone** | Infamy, heroism, tragedy, mundane — used to select appropriate stories for context |

When a traveler is asked about the region, the system pulls from stories tagged to that geography whose propagation reach extends to the traveler's current location, filtered by recency. A traveler from the south road knows south road stories from the last few months. They do not know a decade-old tale from the northern highlands.

---

## Two Consumption Paths

### 1. Diegetic — In-World Discovery

The player encounters stories by engaging with the world.

- **Tavern**: asking the barkeep or patrons what they know about a region
- **Traveler encounter**: asking a traveler on the road what news they carry
- **Named NPC conversation**: a character with high influence may recount an event they witnessed

When a story is consumed this way it is **spent**. It was told. It lived in the world, someone heard it, and it does not appear in the codex. The player may or may not have been paying attention. There is no guarantee they caught it.

Stories told by characters who received a degraded version of the context will contain the degraded version. The player hears what the teller knows, which may be wrong.

### 2. Codex — The Archive of Untold Stories

Stories not consumed through in-world discovery accumulate in the **codex** — a record of events that happened but that nobody in the world ever told the player directly.

The codex is not a menu the player browses at leisure. It surfaces in three moments:

**Loading screen** — a story appears while the world loads. Brief, no commentary.

**Death screen** — when the player's character dies, a story from the world they inhabited plays out. Not the player's story. Someone else's. The world continued while the player was alive, and the world will continue now that they are not.

**Rebirth wait** — the pause between death and the next life. This is the most significant moment. The player is between characters, suspended in the world. The stories shown here are fragments of the history they are about to inherit — events that shaped the world they are being born into, told from the perspectives of people who will never know the player existed. Several may play in sequence.

The codex is the graveyard of untold stories. A story that no traveler ever happened to carry to the right tavern, that no named character ever recounted, ends up here — seen only by the player, only in the silences between lives.

---

## Implementation Notes

### LLM Choice
- **MVP**: Claude Haiku via API. Small prompt, cheap per call, consistent quality. The payload is structured and short; the output is 2–4 sentences. Cost is negligible at simulation event frequency.
- **V2 / Offline**: Small local model (e.g. Phi-4 mini, Llama 3.2 3B). Quality varies but acceptable for flavour text. Enables fully offline play.

### Prompt Structure (sketch)
```
You are a narrator for a 13th century world simulation.
Write 2-3 sentences from [CHARACTER]'s point of view describing this moment.
Be plain and grounded. No flowery language. This is how a peasant remembers things.

Character: [name], traits: [trait list]
Event: [event description]
Location: [settlement], [season], [world context — if hop count = 0]
[If hop count > 2: you only know the broad outline, not the details]
```

### What the LLM Must Not Do
- Invent facts not in the payload
- Resolve ambiguity in favour of drama (the simulation already decided what happened)
- Produce more than 3–4 sentences
- Reference the player character unless they are explicitly in the payload

---

## Example

**Payload (hop count 0 — Tom's perspective):**
Event: theft, item: bread, location: south road, season: winter week 3
Tom traits: impulsive, gentle. Hunger: critical. Village A grain: 8%.

**Generated:**
*"I told myself it was just the one loaf. The cart was sitting there on the frozen road and I had not eaten in two days. I do not know what the man thought of me — I did not stay to find out."*

---

**Payload (hop count 3 — tavern retelling, context degraded):**
Event: theft, item: unknown, location: south road region
Teller traits: loudmouth, drunkard.

**Generated:**
*"There is a thief working the roads south of here, bold as anything. Robbed a man in broad daylight, they say. Watch your carts."*

---

## Interaction with Other Systems

- **[[Reputation & Propagation]]** — determines which events reach the narrative threshold and what context survives to each hop
- **[[Influence]]** — named characters increase the chance that events involving them generate narratives and that those narratives are consumed in-world
- **[[Legacy System]]** — narratives from prior runs can surface in the rebirth wait screen, connecting the player to history they partly created
- **[[Seasons & Cycles]]** — season and world pressure are included in the payload as grounding context

---

**Links:** [[Social Overview]] | [[Reputation & Propagation]] | [[Influence]] | [[Legacy System]] | [[Seasons & Cycles]] | [[Tech/UE5]]
