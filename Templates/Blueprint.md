---
scope: <% await tp.system.suggester(["mvp", "v2", "dream"], ["mvp", "v2", "dream"], true, "Scope?") %>
status: draft
type: blueprint
parent_class: <% await tp.system.prompt("Parent class", "AActor") %>
system: <% await tp.system.prompt("Owning system (e.g. Ecology, Seasons, Fauna)", "") %>
---

# <% tp.file.title %>

> [!NOTE] Purpose
> _What does this Blueprint do in one sentence?_

## Parent & Components

- **Parent class:** `<% await tp.system.prompt("Parent class (repeat for note body)", "AActor") %>`
- **Key components:**

## Variables

| Name | Type | Default | Access | Notes |
| ---- | ---- | ------- | ------ | ----- |
|      |      |         |        |       |

## Functions

| Name | Inputs | Outputs | Notes |
| ---- | ------ | ------- | ----- |
|      |        |         |       |

## Event Dispatchers

| Name | Payload | Fired when |
| ---- | ------- | ---------- |
|      |         |            |

## Event Bindings

_Binds to dispatchers on other actors. List here so dependencies are visible in the graph._

| Dispatcher | Owner | Bound in |
| ---------- | ----- | -------- |
|            |       |          |

## BeginPlay Flow

```
→
→
```

## Links

- System: [[]]
- Related BPs: [[]]
- Related structs: [[]]

## Notes & Open Questions

-
