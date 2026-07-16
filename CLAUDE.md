# cal-reminder — AI guide

Native **macOS** app that connects to Google Calendar and flies a little airplane pulling a
banner across the screen — over all windows — at each event's reminder time. It is built to
be **distributed** (Mac App Store) and **sold** — a commercial product, held to a
distributable bar on security and privacy. Single-part project (one app). Documentation is
**spec-driven** and lean.

## Start here
- @docs/requirements.md — requirements **and glossary** (ALWAYS use these terms)
- @docs/conventions.md — docs **and** code conventions (IDs, frontmatter, style, git, tests)
- @docs/architecture.md — living architecture (C4) of the app

## Where things live
- **REQ + Glossary** → `docs/requirements.md`
- **AYD** (feature analysis & design: modules, interfaces, model, flow) → `docs/design/`
- **Living architecture (C4)** → `docs/architecture.md`
- **SPEC** (what + how of a feature) → `docs/specs/`
- **TDR** (local technical decision) → `docs/technical_decisions/`
- **Changelog** → `docs/changelog.md`

## Feature workflow
1. Read the relevant **REQ** in `docs/requirements.md` (and confirm the terms in the glossary).
2. Capture the design in an **AYD** (`docs/design/AYD-NNN.md`): affected modules, the internal
   **interfaces/contracts**, the domain model, and the flow. The AYD is the source of the design.
   **Never edit a past AYD** — if the design changes, write a **new AYD that supersedes/overrides**
   the old one (`supersedes: [AYD-old]`); the old one stays frozen (see conventions §A.6).
3. Write the **SPEC** (`docs/specs/SPEC-NNN.md`, `parents: [AYD-NNN]`): **direct and
   objective** — what to do and how (acceptance criteria + steps + tests).
4. Implement. Non-trivial technical decision that doesn't change a feature's design →
   **TDR** (`docs/technical_decisions/`); if it changes the design, write a **new AYD that
   supersedes** the old one (don't edit the past AYD).
5. Log **1 line** in `docs/changelog.md` and, if the topology changed (new module/
   integration), update `docs/architecture.md` in the same PR.

## Golden rules
- The **glossary** (in `requirements.md`) defines the canonical term in **English** —
  code and docs use that term. Add the term there **before** using it.
- A feature's design lives in the **AYD**; the SPEC implements, it doesn't redefine.
- **AYDs are append-only**: never rewrite a past AYD — supersede/override it with a new one
  (`supersedes` / `superseded_by`). Only its `status`/`superseded_by` may change (like a TDR).
- References use the plain ID (`SPEC-012`, `AYD-003`) — single-part, no `@part` suffix.
- All docs are written in **English**.
- Changed a **living** doc (REQ/GLO/ARCH/CONV)? Update `updated` and mark affected `children`
  as `status: review`. (AYDs aren't living — supersede them instead, see above.)
