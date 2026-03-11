---
scope: mvp
status: defined
---

# Reputation & Propagation

Reputation is not a number attached to a character. It is a story that lives in other people's mouths — and whether it survives, spreads, or dies depends entirely on who is carrying it and what traits they have.

---

## Core Principle

Most stories break. A witnessed event generates a reputation event. That event is passed — or not passed — from person to person along the social network. Each hand it passes through applies a probability roll shaped by that person's traits. The default outcome for almost any event is silence. It takes an unlikely alignment of the right traits in the right sequence, connected to someone with enough [[Influence]] to matter, for a story to escape its origin.

This is not a limitation. It is the design. Rarity is what makes emergence meaningful.

---

## The Propagation Chain

When an event occurs that generates a reputation mark, the simulation begins a propagation attempt:

1. **Witness** — someone observes or is party to the event. They hold the story.
2. **First transmission** — the witness tells someone. Whether they do, and who they tell, depends on their traits.
3. **Each subsequent link** — the recipient may pass it on, drop it, or corrupt it before passing it on. The chain continues until it dies or reaches a stable anchor (a high-influence character or a public venue like a tavern or market).

Each link is a probability roll. Traits modify the roll. The story either passes to the next node or stops.

### Relevant Trait Examples

| Trait | Effect on Propagation |
|---|---|
| `gossip` | High pass rate; story moves quickly, context may degrade |
| `discretion` | Low pass rate; story is likely to stop here |
| `loudmouth` | Near-certain pass; strong context degradation |
| `loyal` | Pass rate depends on relationship to subject |
| `fearful` | Low pass rate if story involves powerful figures |
| `storyteller` | High pass rate; context preserved or embellished |

---

## Influence as Chain Amplifier

When a story involves or is carried by a high-influence character, chains break less often. People are more likely to pass on a story about someone they recognise, and more likely to listen to someone whose name carries weight.

This creates an asymmetry: events involving unremarkable people die in obscurity. The same event involving a named character escapes into the world. The same event witnessed by a named character escapes into the world. This is why crossing the wrong person can define a life.

---

## Context Degradation

Stories lose nuance as they travel. Each retelling strips away circumstance and leaves label.

The full account: *"Tom, a man from Village A — which lost half its grain to the early frost — stole a single loaf of bread from a food cart on the south road because his children had not eaten in three days."*

After two retellings through traits like `loudmouth` or `gossip`: *"There is a thief working the south road."*

What survives: the label. What is lost: the reason.

This means the simulation can produce genuine injustice. A man driven to theft by starvation becomes, in the collective record, simply a criminal. His circumstances were real. The world judges the label because the context did not survive the journey.

**Context preservation** is itself trait-dependent. A `storyteller` or `empathetic` character retains more nuance in their retelling. A `legalistic` character strips it deliberately — the act is the act regardless of motive.

---

## Information Travels at the Speed of People

Reputation events propagate through the same settlement graph used by trade and travel — and at the same seasonal speeds.

- Summer: fast propagation. Stories move with merchants, pilgrims, drovers.
- Winter: slow propagation. A crime committed in a blizzard may stay local for months.
- A scandal at a summer market can be known in every village within a week.
- A murder in a remote upland hamlet in February may not reach the lowland towns until spring thaw.

This means the timing of events matters. Being witnessed in summer is more dangerous than in winter. Bad news travels faster when the roads are open.

---

## Canonical Example: Tom and Bob

*This example anchors the design intent for the system.*

Village A is depleted by an early frost. Tom — gentle by nature, impulsive by trait — steals a loaf of bread from a food cart. Bob witnesses this. Bob is also gentle, but carries the `law & order` trait. He confronts Tom; Tom escapes.

Bob returns to his village and tells his spouse. She has the `gossip` trait — she passes it on. The chain reaches Jimmy, who is a drunkard and a `loudmouth`. Jimmy tells the tavern. The tavern knows Bob. Bob has influence. The story is now out of control.

Tom is now named — not because he did anything significant, but because the chain aligned and Bob's influence gave the story legs. Tom is `notorious thief`. The context — the frost, the starvation, Village A — may or may not survive depending on how many Jimmys were in the chain.

Most of the time, this chain breaks. Bob's wife tells someone with discretion and it stops there. Tom remains just a hungry boy who made a bad decision. The same action, wildly different outcomes, depending on who was in the chain and what traits they carried.

---

## Public Venues as Propagation Anchors

Taverns, markets, and churches act as propagation anchors — places where many chains converge and stories are broadcast to multiple listeners simultaneously. A story that reaches a market does not need to travel link by link from there; it disperses into many chains at once.

This gives geography a social dimension. Settlements with active markets or well-attended taverns are louder. Stories that reach them travel further and faster. Remote hamlets are quiet. Events that happen far from public venues are more likely to stay local.

---

## Interaction with Other Systems

- **[[Influence]]** — the prominence score that determines how far stories travel when they involve a character
- **[[Relations]]** — personal standing between named characters is shaped by what reputation events have reached them
- **[[Factions]]** — faction-level reputation is the aggregate of many propagated reputation events over time
- **[[Legacy System]]** — infamy or honour that reached wide propagation can leave marks the next generation inherits
- **[[Narrative Layer]]** — when a story reaches a public venue or named character, it is queued for LLM narrative generation; the hop count passed to the generator determines how much context survives

---

**Links:** [[Social Overview]] | [[Influence]] | [[Relations]] | [[Factions]] | [[Legacy System]] | [[NPCs]]
