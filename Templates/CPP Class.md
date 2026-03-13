---
scope: <% await tp.system.suggester(["mvp", "v2", "dream"], ["mvp", "v2", "dream"], true, "Scope?") %>
status: draft
type: cpp-class
parent_class: <% await tp.system.prompt("Parent class", "AActor") %>
module: <% await tp.system.suggester(["TheStorySoFar", "TheStorySoFarEditor"], ["TheStorySoFar", "TheStorySoFarEditor"], true, "Module?") %>
blueprint_exposable: <% await tp.system.suggester(["Yes", "No"], ["true", "false"], true, "Expose to Blueprint?") %>
---

# <% tp.file.title %>

> [!NOTE] Purpose
> _What does this class do in one sentence?_

## Header sketch

```cpp
// <% tp.file.title %>.h

UCLASS(<% tp.frontmatter["blueprint_exposable"] === "true" ? "Blueprintable, BlueprintType" : "" %>)
class <% tp.frontmatter["module"].toUpperCase() %>_API A<% tp.file.title %> : public <% tp.frontmatter["parent_class"] %>
{
    GENERATED_BODY()

public:
    A<% tp.file.title %>();

protected:
    virtual void BeginPlay() override;
};
```

## Properties

| Name | Type | Specifier | Category | Notes |
| ---- | ---- | --------- | -------- | ----- |
|      |      |           |          |       |

**Specifier quick ref:** `VisibleAnywhere` · `EditAnywhere` · `EditDefaultsOnly` · `BlueprintReadOnly` · `BlueprintReadWrite`

## Methods / UFunctions

| Signature | Specifier | Notes |
| --------- | --------- | ----- |
|           |           |       |

**Specifier quick ref:** `BlueprintCallable` · `BlueprintPure` · `BlueprintImplementableEvent` · `BlueprintNativeEvent`

## Dependencies

| Depends on | Type | Why |
| ---------- | ---- | --- |
|            |      |     |

## Links

- System: [[]]
- Related classes: [[]]
- Related structs: [[]]
- Blueprint wrapper: [[]]

## Notes & Open Questions

-
