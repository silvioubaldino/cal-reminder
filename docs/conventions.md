---
id: CONV
type: conventions
title: Docs and code conventions
status: approved
updated: 2026-09-16
---

# Conventions

The "contract" that keeps docs and code consistent and readable by humans and AIs.
`cal-reminder` is the native macOS app **and** the product's **context repo**: it owns the shared
layer — requirements, glossary, architecture, cross-repo design (AYD) — that the sibling repo
`cal-reminder-service` mirrors read-only. Each repo keeps its own SPECs, technical decisions,
code conventions and changelog. Two sections: **A) documentation** and **B) code**.

---

## A. Documentation

### A.1 Document types, IDs, and where they live
ID = `PREFIX-NNN`, **stable** (never changes, even if the file is renamed). The numbering is one
sequence across the **whole product**: a number is never reused, so a given `SPEC-NNN` exists
in exactly one repo, never both.

| Prefix | Type | Where |
|---------|------|------|
| REQ  | Requirements | `docs/requirements.md` |
| GLO  | Glossary (ubiquitous language) | `docs/requirements.md` (section) |
| AYD  | Feature Analysis & Design | `docs/design/` |
| ARCH | Living architecture (C4) | `docs/architecture.md` |
| CONV | These conventions | `docs/conventions.md` |
| SPEC | Specification + plan (what + how) | `docs/specs/` — **in the repo it describes** |
| TDR  | Technical Decision Record | `docs/technical_decisions/` — **in the repo it applies to** |

### A.2 Referencing
IDs are **global** across the product. Reference another doc by its plain ID
(`AYD-003`, `SPEC-012`, `REQ-01`). A reference that **crosses repos** carries the repo:
`SPEC-NNN@service` from here, `AYD-NNN@cal-reminder` from there. Within a repo, the plain ID
is enough. **Before assigning a new ID, check both repos** — the sequence has no central
allocator, so two branches can pick the same free number; the one that lands on `main` second
renumbers.

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

**AYD and TDR** (append-only, A.6) also carry supersession fields: `supersedes: [AYD-old]` on
the newer doc and `superseded_by: <ID>` (default `null`) plus `status: superseded` on the one
it replaces.

### A.4 Status lifecycle
`draft → review → approved` (and `done` for a SPEC already implemented; `approved →
superseded` for an AYD replaced by a newer one; `proposed → accepted → superseded` for TDR).
**approved/accepted** = current source of truth.

### A.5 Linking (the graph's "glue")
- Refinement declared on both sides **at creation**: `children` on the parent, `parents` on the
  child. Across repos this is best-effort in one direction — an AYD here lists a SPEC that lives
  in the service repo, and that SPEC points back with `@cal-reminder`.
- A SPEC always declares its `AYD` in `parents`; every `AYD` declares its `REQ`. But a **past
  AYD is frozen** (A.6) — a SPEC written after an AYD was approved just points to it in
  `parents`; do **not** retro-edit that AYD's `children`. If the SPEC actually **changes** the
  design, write a new AYD instead (A.6).
- **1 AYD → N SPECs** (one per coherent slice of work). The AYD is the source of the design.
- A new AYD that **supersedes/overrides** an earlier one declares `supersedes: [AYD-old]`; the
  earlier AYD is not rewritten (only its `status`/`superseded_by` may flip — A.6).
- Domain terms live only in the **glossary**; other docs just reference them.

### A.6 Lifecycle
| Type | Behavior |
|------|------|
| REQ / GLO / ARCH / CONV | **Living** — edit in place, update `updated`. |
| AYD | **Append-only** — a past AYD's content is **never rewritten**. When a feature's design changes, write a **new AYD that supersedes/overrides** the old one (`supersedes` / `superseded_by`); the old AYD stays frozen as the historical design. The only edit allowed to a superseded AYD is flipping its `status` to `superseded` and setting `superseded_by` (exactly like a TDR). |
| SPEC | **Ephemeral** — working document; becomes historical once implemented (`done`). |
| TDR | **Append-only** — never rewritten. A new decision replaces the old one via `superseded_by`. |

Audit trail lives in **git + changelog**.

### A.7 Change propagation
When changing a **living** doc (REQ / GLO / ARCH / CONV): (1) edit it and update `updated`;
(2) log it in `docs/changelog.md`; (3) mark affected `children` as `status: review` and review
them; (4) if the change alters the topology (new module/integration), update
`docs/architecture.md` in the **same edit**.

An **AYD is not a living doc** (A.6): don't edit a past AYD to reflect a design change — write a
**new AYD that supersedes/overrides** it (`supersedes: [AYD-old]`), flip the old one's `status`
to `superseded` and set its `superseded_by`, and point new SPECs at the new AYD.

### A.8 Language
All docs are written in **English**, including entities, fields, enums, and events
(these carry through to the code). The glossary defines the canonical term for each concept.

### A.9 Only what was decided
A doc states the decision, not the road to it. Keep what someone needs to build or use the thing:
contracts, behavior, acceptance criteria, constraints, and the reason a decision is non-obvious —
one or two lines, where it prevents the next person undoing it by accident. Cut the rest: the
history of the discussion, options weighed and dropped, and features the project decided against.

Two exceptions. A **TDR** exists to record a choice, so its `Alternatives & trade-offs` stays —
one line per alternative. And anything a reader might reasonably expect to find belongs under a
short **Out of scope** list, so its absence reads as a decision rather than an oversight.

### A.10 Diagrams
**Mermaid embedded in the `.md`** (version-controlled, renders on GitHub) — never a PNG
as the canonical source. Current topology → `architecture.md`; a feature's flow → its
`AYD`. If the diagram diverges from the text, **the text wins**.

---

## B. Code

### B.1 Style
- **Naming:** use the glossary's terms — always in **English** (variables, functions,
  types, entities). Comments may be in English.
- **Linter/formatter:** keep configuration and command standardized across the project.
- The **Project Service** is a separate repo (`cal-reminder-service`) with its own code
  conventions; these apply to the macOS app.

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
