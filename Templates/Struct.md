---
scope: <% await tp.system.suggester(["mvp", "v2", "dream"], ["mvp", "v2", "dream"], true, "Scope?") %>
status: draft
type: struct
datatable_row: <% await tp.system.suggester(["Yes — inherits FTableRowBase", "No — runtime only"], ["true", "false"], true, "Is this a DataTable row?") %>
---

# <% tp.file.title %>

> [!NOTE] Purpose
> _What data does this struct hold and why does it exist as a struct?_

## Fields

| Name | Type | UPROPERTY | Default | Notes |
| ---- | ---- | --------- | ------- | ----- |
|      |      |           |         |       |

**Key distinction:**
- `VisibleAnywhere` + `BlueprintReadOnly` → key / identity field (read only)
- `EditAnywhere` + `BlueprintReadWrite` → tunable value (editable in Details / DataTable)

## C++ Definition

```cpp
USTRUCT(BlueprintType)
struct F<% tp.file.title %><% tp.frontmatter["datatable_row"] === "true" ? " : public FTableRowBase" : "" %>
{
    GENERATED_BODY()

    // Fields go here
};
```

<% tp.frontmatter["datatable_row"] === "true" ? `## DataTable Notes

- Row Name = primary key (ZoneID, ItemID, etc.) — set once, not part of struct
- Import/export via CSV: column headers must match field names exactly
- Query in C++: \`Table->FindRow<F${tp.file.title}>(FName("row_name"), "")\`` : "" %>

## Used In

| Class / BP | Role |
| ---------- | ---- |
|            |      |

## Links

- Related structs: [[]]
- Related classes: [[]]

## Notes & Open Questions

-
