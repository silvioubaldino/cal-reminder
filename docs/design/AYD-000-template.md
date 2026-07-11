---
id: AYD-NNN
type: design
status: draft
updated: 2026-07-11
parents: [REQ-01]
children: []          # SPECs generated, e.g.: [SPEC-001]
related: [GLO]
---

# AYD-NNN: <feature>

> Analysis & Design of a feature. Decides the affected modules/components, the
> **internal interfaces/contracts** between them, the domain model, and the flow.
> It is the source of the design — the SPEC implements, it doesn't redefine. Be objective.

## Goal
_Which requirement (REQ) does this feature meet, and what's the expected outcome._

## Affected modules
| Module | Role in this feature | Generated SPEC |
|--------|----------------------|----------------|
| <module> | _does…_ | SPEC-NNN |

## Interfaces / contract (source of truth)
_Public types, function signatures, data shapes, errors. Names in English (use GLO terms)._
```
<type / signature / payload>
```

## Affected domain model
_Entities/fields (glossary terms)._

## Flow
```mermaid
sequenceDiagram
    participant A
    participant B
    A->>B: action
    B-->>A: result
```

## Out of scope / open questions
-
