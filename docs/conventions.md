---
id: CONV
type: conventions
title: Docs and code conventions
status: approved
updated: 2026-07-11
---

# Conventions

The "contract" that keeps docs and code consistent and readable by humans and AIs.
`cal-reminder` is a **single-part** project (one native macOS app), so there is no
cross-part split — IDs are global and carry **no `@part` suffix**. Two sections:
**A) documentation** and **B) code**.

---

## A. Documentation

### A.1 Document types, IDs, and where they live
ID = `PREFIX-NNN`, **stable** (never changes, even if the file is renamed).

| Prefix | Type | Where |
|---------|------|------|
| REQ  | Requirements | `docs/requirements.md` |
| GLO  | Glossary (ubiquitous language) | `docs/requirements.md` (section) |
| AYD  | Feature Analysis & Design | `docs/design/` |
| ARCH | Living architecture (C4) | `docs/architecture.md` |
| CONV | These conventions | `docs/conventions.md` |
| SPEC | Specification + plan (what + how) | `docs/specs/` |
| TDR  | Technical Decision Record | `docs/technical_decisions/` |

### A.2 Referencing
IDs are **global** across the project. Reference another doc by its plain ID
(`AYD-003`, `SPEC-012`, `REQ-01`). No `@part` suffix (single-part project).

### A.3 Frontmatter (required in every doc)
```yaml
---
id: AYD-001
type: design          # requirements | design | spec | architecture | conventions | tdr
status: draft         # draft | review | approved | done
updated: 2026-07-11
parents: [REQ-01]       # what this doc refines (layer above)
children: [SPEC-001]    # what refines this doc
related: [GLO]           # cross-cutting context
---
```

### A.4 Status lifecycle
`draft → review → approved` (and `done` for a SPEC already implemented; `proposed →
accepted → superseded` for TDR).
**approved/accepted** = current source of truth.

### A.5 Linking (the graph's "glue")
- Refinement declared on both sides: `children` on the parent, `parents` on the child.
- Every `SPEC` has an `AYD` in `parents`. Every `AYD` has a `REQ`.
- **1 AYD → N SPECs** (one per coherent slice of work). The AYD is the source of the design.
- Domain terms live only in the **glossary**; other docs just reference them.

### A.6 Lifecycle
| Type | Behavior |
|------|------|
| REQ / GLO / AYD / ARCH / CONV | **Living** — edit in place, update `updated`. |
| SPEC | **Ephemeral** — working document; becomes historical once implemented (`done`). |
| TDR | **Append-only** — never rewritten. A new decision replaces the old one via `superseded_by`. |

Audit trail lives in **git + changelog**.

### A.7 Change propagation
When changing a living doc: (1) edit it and update `updated`; (2) log it in
`docs/changelog.md`; (3) mark affected `children` as `status: review` and review them;
(4) if the change alters the topology (new module/integration), update
`docs/architecture.md` in the **same edit**.

### A.8 Language
All docs are written in **English**, including entities, fields, enums, and events
(these carry through to the code). The glossary defines the canonical term for each concept.

### A.9 Diagrams
**Mermaid embedded in the `.md`** (version-controlled, renders on GitHub) — never a PNG
as the canonical source. Current topology → `architecture.md`; a feature's flow → its
`AYD`. If the diagram diverges from the text, **the text wins**.

---

## B. Code

### B.1 Style
- **Naming:** use the glossary's terms — always in **English** (variables, functions,
  types, entities). Comments may be in English.
- **Linter/formatter:** keep configuration and command standardized across the project.

### B.2 Tests
- **Structure:** AAA (Arrange, Act, Assert).
- **Coverage:** every acceptance criterion of a SPEC has a corresponding test.
- **Mocks:** only at the boundary (network, keychain, clock); don't mock the unit under test.

### B.3 Git
- **Branches:** `feature/<spec-id>-description` (e.g., `feature/SPEC-001-overlay`).
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org); reference the
  ID (SPEC/AYD/TDR) when applicable.
- **PRs:** link to the SPEC; one line in `docs/changelog.md` per PR.
- **Changelog lines:** state **what** shipped, not **how** — no stack/library names,
  file paths, or implementation detail (that lives in the SPEC/TDR/PR). Keep it to one
  short, general sentence.
