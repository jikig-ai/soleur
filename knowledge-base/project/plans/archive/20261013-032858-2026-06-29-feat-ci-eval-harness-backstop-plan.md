---
feature: ci-eval-harness-backstop
type: feat
issue: 5703
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
date: 2026-06-29
branch: feat-ci-eval-harness-backstop
pr: 5721
brainstorm: knowledge-base/project/brainstorms/2026-06-29-ci-eval-harness-backstop-brainstorm.md
spec: knowledge-base/project/specs/feat-ci-eval-harness-backstop/spec.md
---

# Plan: CI backstop for gated classifier-skill edits (#5703)

## Overview

Harden the eval-harness gated-skill **registry invariant** so a new/renamed gated
classifier cannot be added without wiring its projection check. Two deliverables, both
**deterministic / no-API**, both discovered for free by the existing `scripts` test
shard (`scripts/test-all.sh:186` globs `plugins/soleur/skills/*/test/*.test.sh`, run by
`ci.yml:375` on every PR):

1. **New** `plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh` —
   asserts bidirectional parity between `eval-gate:block` markers in source files and
   `block_id` entries in `gated-skills.json`. Pure bash + node one-liners, mirroring
   `test/eval-gate.test.sh`.
2. **Refactor** `test/extract-block.test.sh` — derive its round-trip target loop from
   `gated-skills.json` instead of the hardcoded `for target in go-routing ticket-triage`
   + the inline `go-skill.txt`/`triage-skill.txt` ternary.

No new workflow, no API spend in CI, no branch-protection change.

## Research Reconciliation — Spec vs. Codebase

All premises verified live this session (brainstorm + plan). No drift.

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| Deterministic round-trip already runs per-PR | `ci.yml:375` runs `bash scripts/test-all.sh scripts`; `test-all.sh:186` globs `plugins/soleur/skills/*/test/*.test.sh` ✓ | New + refactored tests land in same shard; no `ci.yml` edit (FR3). |
| `extract-block.test.sh` target loop is hardcoded | Confirmed: `extract-block.test.sh:21` `for target in go-routing ticket-triage` + `:22` ternary | Refactor to registry-driven loop (Phase 3). |
| `gated-skills.json` is the registry; markers in source | Confirmed: 2 entries (`go-routing`, `ticket-triage`); markers in `commands/go.md` + `agents/support/ticket-triage.md` | Read registry via node one-liner; scan markers via `git grep`. |
| Marker scan must exclude eval-harness prose | Confirmed load-bearing: `eval-harness/{SKILL.md, gated-skills.json, test/extract-block.test.sh}` all contain the literal marker strings | `git grep ... -- 'plugins/soleur/' ':(exclude)plugins/soleur/skills/eval-harness/'` — verified to yield exactly `{go-routing, ticket-triage}`. |
| (refinement) completeness needs a new `.cjs` script | `eval-gate.test.sh` is pure bash + node one-liners + `git grep`; that is the convention | **Pure-bash test, NO new `.cjs`** (simpler; YAGNI). Negative cases via tmp-fixture bash functions. |
| (refinement) reuse `eval-gate.cjs --check <file>` for source→registry | `--check` matches by `source_file` path → cannot catch a *second* unregistered block inside an already-registered file | Source→registry works at **block-id level** (extract ids from markers, set-membership against registry `block_id`s), not file-level `--check`. |

## User-Brand Impact

**If this lands broken, the user experiences:** a silently-unchecked classifier
regression — a gated block edited, or a new classifier added, without its
projection/eval coverage wired — so `soleur:go` mis-routes their request or
`ticket-triage` mis-prioritizes their ticket, with no CI signal.

**If this leaks, the user's workflow is exposed via:** N/A — no data, credentials,
auth, schema, or network surface; the diff is deterministic test infrastructure only.

**Brand-survival threshold:** single-user incident (carried forward from brainstorm
Phase 0.1, per #5175). `requires_cpo_signoff: true` — CPO framing carried from the
brainstorm record (no user-data/credential/infra surface; plan-time sign-off satisfied
by the brainstorm framing). `user-impact-reviewer` runs at review time.

> **Plan-review reconciliation (3-agent panel).** DHH + code-simplicity both flagged the
> original three-invariant design as overbuilt; reconciled below. **INV1 (registry→source
> integrity) is dropped** — the Phase 3 registry-driven round-trip already catches every
> INV1 case: `gen-skill-prompt.cjs:generateFromDisk()` does `readFileSync(source_file)`
> (throws if missing/renamed) → `extractBlock(... registry markers)` (throws if markers
> absent) → returns `projected_prompt_path` (round-trip `diff` fails if missing/stale).
> The completeness test reduces to **one set-equality assertion** (which also catches
> marker↔id inconsistency: a registry `block_id` disagreeing with the source marker
> surfaces as a scanned-id ≠ registry-id mismatch). The injectable-parameter +
> synthetic-registry "verify-the-verifier" machinery is dropped (it was testing that
> `diff` works). INV3 (no-dup) dropped — nothing keys uniqueness on `block_id`. Added:
> a charset guard (Simplicity's catch) so a non-lowercase-hyphen id can't confuse the
> scan. Phase 3 kept verbatim (all three endorsed).

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

Already verified this session (cite, re-run if stale):

- `git grep -hoE 'eval-gate:block:[a-z][a-z0-9-]*:start' -- 'plugins/soleur/' ':(exclude)plugins/soleur/skills/eval-harness/' | sed -E 's/eval-gate:block:(.*):start/\1/' | sort -u`
  → `go-routing\nticket-triage` (matches registry `block_id`s). ✓
- `node "$GEN" <target> --stdout` regenerates a projection to stdout (`gen-skill-prompt.cjs:17,116`). ✓
- Registry fields per entry: `source_file, block_id, block_start_marker, block_end_marker, target, projected_prompt_path` (`block_id == target` for both current entries). ✓

### Phase 1+2 — Create `test/registry-completeness.test.sh` (pure bash, one thesis)

Mirror `test/eval-gate.test.sh` scaffolding (`HERE`/`SKILL_DIR`/`REPO_ROOT`, `pass`/`fail`
counters, `cd "$REPO_ROOT"`, node one-liners for JSON — no `jq` dependency). The test
asserts a single thesis with three short checks:

- **DEDUP guard (Kieran P2).** BEFORE `sort -u`, assert each scanned id appears exactly
  once across source markers (count start-markers per id == 1). The registry maps a
  `block_id` to a single `source_file`; the *same* id appearing twice (two files, or
  twice in one file) is silently never projected for the second occurrence, and `sort -u`
  would hide it. Fail message: `gated block '<id>' appears N>1 times in source — each
  block_id maps to one registry source_file`.
- **PARITY (the feature) — set-equality, block-id level.** Build two sorted id sets:
  (a) source-scanned ids = `git grep -hoE 'eval-gate:block:[a-z][a-z0-9-]*:start'` over
  `'plugins/soleur/' ':(exclude)plugins/soleur/skills/eval-harness/'` → `sed` the id →
  `sort -u`; (b) registry ids = node one-liner over `gated-skills.json` `block_id`s →
  `sort -u`. Assert the sets are equal (`comm -3 <(a) <(b)` empty, or `diff`). A diff in
  the **source-only** column = an unregistered marker (add a registry entry +
  enums/tasks/promptfooconfig + `node scripts/gen-skill-prompt.cjs <id>`; see README
  additive recipe); a diff in the **registry-only** column = an orphan/renamed entry.
  Block-id level (not file-level `eval-gate.cjs --check`) so a *second* unregistered
  block inside an already-registered file is caught. This single assertion also catches
  marker↔id inconsistency (see reconciliation note). Also pin the live scan output to
  exactly `{go-routing, ticket-triage}` so the production command is *characterized*, not
  just exit-0'd (Kieran).
- **CHARSET guard.** Assert every registry `block_id` matches `^[a-z][a-z0-9-]*$` — the
  scanner regex only recognizes lowercase-hyphen ids, so a non-conforming id must fail
  loudly with a clear message rather than surface as a confusing "registry-only" diff.
- **NEGATIVE sanity (one inline check, `cq-write-failing-tests-before`).** Append a
  synthetic id to an **in-memory copy** of the scanned set and assert the parity
  comparison flags it. Deliberately in-memory, NOT a file/registry fixture: `git grep` is
  tracked-only and cannot see an untracked `/tmp` fixture (Kieran verified), so a
  file-based negative would test a different backend than production and false-pass.

Accumulate violations into a `fails` counter with `pass()`/`fail()` and a single
terminal `if [[ "$fails" -gt 0 ]]; then exit 1` — matching `eval-gate.test.sh` /
`extract-block.test.sh` (surfaces all drift in one run, not exit-on-first). End with the
canonical `echo "registry-completeness: all assertions passed"`.

### Phase 3 — Refactor `test/extract-block.test.sh` round-trip loop

Replace lines 21–29 (`for target in go-routing ticket-triage` + the
`go-skill.txt`/`triage-skill.txt` ternary) with a loop over registry entries: read
`target` (for `node "$GEN" "$target" --stdout`) and `projected_prompt_path` (committed
file = `"$REPO_ROOT/$projected_prompt_path"`) via a node one-liner. Keep the existing
`diff -u` round-trip assertion and the three extractBlock unit assertions unchanged.
Coverage MUST remain ≥ current (both targets still tested, now registry-derived).

### Phase 4 — Green + discovery proof

Run `bash plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh`,
`bash plugins/soleur/skills/eval-harness/test/extract-block.test.sh`, then
`bash scripts/test-all.sh scripts` (proves both files are discovered + green in the
shard `ci.yml` runs). Update the `## Tests` list in `eval-harness/SKILL.md` and the test
list in `eval-harness/README.md` to include `registry-completeness.test.sh`.

## Files to Create

- `plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh` — DEDUP + PARITY (set-equality, block-id level) + CHARSET guard + one in-memory negative sanity. Pure bash + node one-liners, accumulate-then-exit (mirrors `eval-gate.test.sh`).

## Files to Edit

- `plugins/soleur/skills/eval-harness/test/extract-block.test.sh` — registry-driven round-trip loop (Phase 3).
- `plugins/soleur/skills/eval-harness/SKILL.md` — add the new test to the `## Tests` list (prose only; no `description:` edit → no skill-budget impact).
- `plugins/soleur/skills/eval-harness/README.md` — add the new test to the Tests list.
- `knowledge-base/engineering/architecture/decisions/ADR-069-validation-gated-classifier-skill-edits.md` — **optional** one-line Consequences note that the registry completeness invariant is now CI-asserted. Skip if it bloats the ADR.

## Acceptance Criteria (Pre-merge)

- **AC1:** `bash plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh` exits 0 against the current repo, AND its output characterizes the live scan as exactly `{go-routing, ticket-triage}` (not just exit-0).
- **AC2:** The test prints `ok` lines for its in-memory negative sanity checks: (a) an injected unregistered id is flagged by PARITY; (b) an injected duplicate id is flagged by the DEDUP guard.
- **AC3:** `bash plugins/soleur/skills/eval-harness/test/extract-block.test.sh` exits 0 AND its output contains `ok` lines for both `round-trip go-routing` and `round-trip ticket-triage` (coverage preserved, now registry-derived — guards against an empty registry-driven loop silently exiting 0).
- **AC4:** `bash scripts/test-all.sh scripts` exits 0 (both files discovered + green in the shard `ci.yml:375` runs).
- **AC5:** `registry-completeness.test.sh` appears in the `## Tests` list of `eval-harness/SKILL.md` AND in `eval-harness/README.md`'s test list (test inventory stays accurate).

**Refactor checklist (not a merge gate):** confirm `extract-block.test.sh` no longer hardcodes the target list (the `for target in go-routing ticket-triage` literal is gone — read the diff; do not rely on `grep -c`, which exits 1 on a zero count). AC3 is the real anti-regression guard.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` searched against the two
edited/created file paths — no open scope-outs touch `eval-harness/test/`.)

## Domain Review

**Domains relevant:** Engineering (carried forward from brainstorm `## Domain Assessments`).

### Engineering

**Status:** reviewed (brainstorm carry-forward + plan-time grounding).
**Assessment:** Deterministic registry-parity invariant + registry-driven round-trip;
pure bash, no new script surface, no API, runs free in the existing `scripts` shard.
Fail-closed. No new infra, no UI, no data surface.

### Product/UX Gate

NONE — no UI-surface file in Files to Create/Edit (test + prose docs only).

## Observability

CI-test feature — no runtime component, so the 5-field server schema is degenerate:

- **liveness_signal:** the `scripts` shard run on every PR (`ci.yml:375`); cadence = per-PR; alert_target = the PR's required CI check; configured_in = `ci.yml` + `scripts/test-all.sh:186` (no new wiring).
- **failure_mode:** registry↔marker drift → `registry-completeness.test.sh` exits 1 → CI red → merge blocked. Detection = CI; alert_route = PR status check.
- **discoverability_test:** `bash scripts/test-all.sh scripts` (no ssh). expected = exit 0.

## Architecture Decision (ADR/C4)

**No architectural decision.** ADR-069 (`validation-gated-classifier-skill-edits`)
governs the gate; this plan *hardens the registry invariant ADR-069's gate already
relies on* — it does not change, reverse, or extend the decision. No
ownership/tenancy/substrate/resolver-boundary change. C4: no external actor, system,
container, or access-relationship changes (checked `model.c4`/`views.c4`/`spec.c4`
conceptually — the eval-harness is internal CI tooling, not modeled). Optional one-line
ADR-069 Consequences note listed in Files to Edit.

## Test Scenarios

| Scenario | Caught by | Expected |
|---|---|---|
| Registry + markers in sync (today) | — | all checks pass; exit 0 |
| New `eval-gate:block:foo:start` added to a source, no registry entry | PARITY (source-only) | exit 1 |
| Registry entry deleted, source marker remains | PARITY (source-only) | exit 1 |
| Orphan/renamed registry entry (id not in any source marker) | PARITY (registry-only) | exit 1 |
| `block_start_marker` disagrees with `block_id` | PARITY (scanned id ≠ registry id) | exit 1 |
| Second *different* gated block inside already-registered `go.md`, unregistered | PARITY (block-id level) | exit 1 |
| *Same* `block_id` duplicated across/within source files | DEDUP guard | exit 1 |
| Registry `block_id` with uppercase/underscore | CHARSET guard | exit 1 (clear message) |
| Registry entry's `source_file` / markers / `projected_prompt_path` missing | **Phase 3 round-trip** (`extract-block.test.sh`) — `generateFromDisk` throws / `diff` fails | exit 1 |

## Sharp Edges

- **Marker-scan scope is `plugins/soleur/` minus `eval-harness/`.** Verified the only
  marker hits there are the two real sources + the (excluded) eval-harness dir. Residual
  limitation: a *future* skill that documents the concrete marker syntax in prose under
  `plugins/soleur/` would false-positive INV2 → add it to the exclude pathspec. Scanning
  the whole repo is wrong: `knowledge-base/` (this plan included) mentions concrete
  marker strings in prose.
- **Source→registry must be block-id level, not file-level `--check`** — else a second
  unregistered block inside an already-registered file slips through.
- **`git grep` is tracked-only** (Kieran verified): in CI the PR's files are tracked so
  the scan is complete, but a developer running the test locally with a brand-new
  *unstaged* source file carrying a new gated block would see a false-negative. Acceptable
  — the feature's contract is the per-PR CI gate over committed content; documented here.
- **DEDUP guard is source-side; PARITY's `sort -u` would otherwise hide a same-id dup.**
- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — this one is filled (single-user incident).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| New `scripts/check-registry-completeness.cjs` + thin test | Rejected — `eval-gate.test.sh` precedent is pure bash + node one-liners; a new committed `.cjs` is unneeded surface (YAGNI). Negative cases are servable by tmp-fixture bash functions. |
| Dedicated path-scoped workflow `eval-harness-gate.yml` | Rejected in brainstorm — duplicates the `scripts` shard which already runs on every PR; cosmetic. |
| API corpus-regression eval in CI | Rejected in brainstorm — operator chose deterministic-only (flake-free, fork-safe, no secret). Stays manual/opt-in. |
| Fold completeness into `extract-block.test.sh` (one file) | Rejected — separate concerns (parity vs projection-freshness); separate files give clearer failure messages and match one-script-one-test convention. |
