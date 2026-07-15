---
id: SPEC-007
type: spec
status: done
parents: [AYD-004]
related: [GLO, CONV]
updated: 2026-07-16
---

# SPEC-007: CI & code-quality gate — what + how

> Adds an automated build/test/lint gate on every push and pull request. Closes RF/RNF-09.
> Implements AYD-004; doesn't redefine it. **Tooling only** — no app module changes.

## What (goal)
A GitHub Actions workflow on a macOS runner that, on every push and pull request,
regenerates the Xcode project from `project.yml`, lints the sources (gating), builds the app,
and runs the test suite. A red step blocks the merge. Ships the standardized `.swiftlint.yml`
CONV §B.1 refers to, tuned lenient so the current code starts green (ratcheted in follow-ups).

## Acceptance criteria
```gherkin
Scenario: Gate runs on push and PR
  Given the workflow is committed
  When a commit is pushed or a pull request is opened
  Then a macOS CI job runs generate → lint → build → test

Scenario: Lint failure blocks
  Given a source file violates an enabled SwiftLint rule
  When CI runs
  Then the lint step fails (swiftlint --strict) and the job is red

Scenario: Build or test failure blocks
  Given the app fails to compile or a test fails
  When CI runs
  Then the corresponding step fails and the job is red

Scenario: Current codebase is green
  Given the repository at this SPEC's merge
  When CI runs against it
  Then lint, build, and test all pass

Scenario: No signing needed
  Given CI has no Apple Team or provisioning
  When the build and test steps run
  Then they complete without code signing (CODE_SIGNING_ALLOWED=NO)
```

## How (approach)
One workflow (`.github/workflows/ci.yml`) on `macos-14`, triggered on `push` + `pull_request`,
with a single job: install `xcodegen`/`swiftlint` (Homebrew), `xcodegen generate`,
`swiftlint lint --strict`, then `xcodebuild build`/`test` on the generic macOS destination with
signing disabled. Regenerating the project each run keeps `project.yml` authoritative (AYD-004
decision), so the committed `.xcodeproj` can't silently drift. The `.swiftlint.yml` is scoped to
`cal-reminder/` + `cal-reminderTests/` and starts lenient: `force_try` disabled (test fixtures
use `try!`), generous `line_length`, and `id` allowed as an identifier — enough that the current
tree passes `--strict`, with the length/complexity knobs left as documented ratchet points.

## Steps
1. **`.swiftlint.yml`** (new, repo root): `included: [cal-reminder, cal-reminderTests]`; disable
   `force_try` (test JSON fixtures) and `todo`; `line_length` warning 250 / error 400;
   `identifier_name` excluded `[id]`, min_length warning 2; generous `type_body_length`,
   `file_length`, `function_body_length`, `cyclomatic_complexity` — tuned so the current code is
   green under `--strict`. Comment each relaxation as a ratchet point.
2. **`.github/workflows/ci.yml`** (new): `name: CI`; `on: [push, pull_request]`; concurrency group
   per ref (cancel in progress). Job `build-test-lint` on `macos-14`:
   - `actions/checkout@v4`
   - select a pinned Xcode (`sudo xcode-select -s /Applications/Xcode_15.4.app`)
   - `brew install xcodegen swiftlint`
   - `xcodegen generate`
   - `swiftlint lint --strict`
   - `xcodebuild build -scheme cal-reminder -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
   - `xcodebuild test -scheme cal-reminder -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
3. **Docs**: mark AYD-004 `children: [SPEC-007]`; add one changelog line; set this SPEC `done`
   once CI is green on the PR.

## Affected files
- `.swiftlint.yml` *(new)*
- `.github/workflows/ci.yml` *(new)*
- `docs/design/AYD-004-ci-quality-gate.md` (wire `children`)
- `docs/changelog.md`

No `cal-reminder/*.swift` changes: the config is tuned to the tree rather than the tree to the
config, per AYD-004's "start lenient, then ratchet" decision.

## Tests
- **Acceptance:** the workflow itself is the test — the four gherkin gate scenarios are observed
  as CI step outcomes on the opening PR (green lint/build/test; a deliberately broken rule/compile
  would go red). Verified on the PR run, not by a unit test.
- **Unit:** none — tooling only, no app logic. The existing `cal-reminderTests` suite is what the
  `test` step exercises.

## Checklist
- [x] Workflow triggers on push and PR (observed on PR #6)
- [x] `swiftlint --strict` passes on the current tree
- [x] `xcodebuild build` passes without signing
- [x] `xcodebuild test` passes (existing suite green)
- [ ] A red step blocks the merge (branch protection is a repo setting, noted for the owner)
