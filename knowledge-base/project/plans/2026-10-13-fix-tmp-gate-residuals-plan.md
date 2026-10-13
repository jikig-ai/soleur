---
title: "fix: tmp-gate residuals — #10167 block-mapping presence check, #6752 verified-clean close-out, #7004 measured-producer adoption"
type: fix
date: 2026-10-13
slug: fix-tmp-gate-residuals
branch: feat-one-shot-6752-7004-10167-tmp-gate-residuals
issue: 10167
closes: [6752, 10167]
refs: [7004, 8786, 6760, 10017, 10158]
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: tmp-gate residuals — #10167 block-mapping presence check, #6752 verified-clean close-out, #7004 measured-producer adoption

## Enhancement Summary

**Deepened on:** 2026-10-13
**Sections enhanced:** Proposed Solution (#7004 splice shape), Observability (4.7 proxy argued down), Research Insights (citations re-verified)
**Research agents used:** inline (no Task-spawn capability in this context — recorded in `decision-challenges.md`); all deepen-plan halts/gates ran mechanically

### Key Improvements

1. **Trap-splice shape corrected against the live chain.** `cloud-init-inngest-bootstrap.test.sh`'s EXIT trap is a *growing* four-arm chain (:164→:809→:1179→:1714); each assignment replaces the prior trap, so `_soleur_scratch_cleanup` must be appended to **every** arm, with the `test-all.sh:507-514` stub-fallback (`declare -F … || _soleur_scratch_cleanup() { :; }`) so the name always resolves. A mid-chain assert failure through an unspliced arm would leak the whole root — the dominant window.
2. **`harness-discovery-smoke.ts` adoption placement verified.** `bun <file>` (ci.yml:1819,1865) does not run bunfig `[test].preload`, so the script binds no root today; `ensureScratchSession()` goes as a top-level statement after imports, matching `git-tripwire.ts:108`.
3. **Every cited symbol/line re-verified against `origin/main`** in the deepen pass: `ensureScratchSession` :195, `writeScratchMarker` :122, `normalizeScratchBase` :73, `soleur_scratch_session_begin` :76, `_soleur_scratch_cleanup` :158, `add_leaf` :181, `parse-override.sh` grep at :74, all three parse-override call doors (pr-quality-guards.yml:786/822, postmerge:133, hook:23), ci.yml invocation lines.

### New Considerations Discovered

- `ensureScratchSession()`'s inherited-root arm (`SOLEUR_SCRATCH_SESSION_ROOT` already set → pins TMPDIR to it, returns it, never deletes a parent-owned root) makes the Guard 2 "must-PASS nested shape" row a real code path, not a hypothetical.
- The cloud-init test's own :1712 comment already documents the "extend, don't replace" convention the splice uses — the edit is in-file convention, not novel.
- `discoverability_test.command` trips the 4.7 suite-shape proxy (`/test/` path); argued down inline in the Observability block (the suite IS the probe, ~7-arm scratch-git smoke, well under 15s).

## Overview

Bundle three residual follow-ups in the tmp/scratch-gate neighborhood that
surfaced around the merged #6760 close-out (PR #10158):

- **#10167** (`fix(parse-override)`, p3) — a real, reproducible defect:
  `parse-override.sh:74` gates required frontmatter fields on
  `grep -qE "^${f}:[[:space:]]"`, which demands a non-empty value on the same
  line. The schema's `oneOf string|object` for `findings_json` permits the
  block-mapping spelling (`findings_json:` + indented keys), which the grep
  rejects as `missing fields` → `invalid_schema` → the PreToolUse hook denies
  and the CI gate reds.
- **#6752** (chore, p3) — **premise stale, verified on this tree.** The merged
  #10017 mktemp census (`specs/archive/20261013-062704-feat-one-shot-10017-mktemp-tmp-leak/mktemp-census.md`,
  "Mandatory rows") dispositioned all three named sites
  **already-clean (verified)**: `learning-retrieval-bench.sh`'s stray allocs are
  `rm -f`'d on all paths or live under `TMP_ROOT` (owning EXIT trap :1168);
  `weekly-analytics.sh`'s `response_file` is rm'd on all 5 paths and
  `_preflight_file` trapped then disarmed+rm'd; `constraint-scaffold.sh`'s
  `trap '_wt_cleanup' EXIT` (:230) is the single owner per ADR-129. The
  deliverable is re-verification + close-out with evidence, not new traps —
  the issue itself warns that speculative "fixes" here have real blast radius.
- **#7004** (p2, `deferred-scope-out` — reclamation scope now operator-authorized) —
  the ownership-keyed reclamation machinery **already shipped** in PR #8738
  (`soleur_scratch_session_begin`, `.soleur-owned` markers, Reaper 3,
  `tmp-classify.sh`, `soleur-tmp-purge.sh`, session-start sweep; ADR-250).
  What remains in a code PR is the bounded **producer-adoption residual**:
  two measured-but-still-unadopted producers (below). The issue's recorded
  close-condition is the operator-run drain evidence tracked in #8786, which
  this PR cannot produce — **Refs only, do not `Closes #7004`**.

## Research Insights

### Relevant file paths

- `plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh:71-79` —
  the defective presence loop (`grep -qE "^${f}:[[:space:]]"`).
- `plugins/soleur/skills/skill-security-scan/references/override-artifact-schema.json` —
  `findings_json` is `oneOf` string|object; all 9 fields are `required`.
- `plugins/soleur/skills/skill-security-scan/test/` — auto-discovered by
  test-all via glob `plugins/soleur/skills/*/test/*.test.sh` (test-all.sh:97-98);
  sibling suites `meta-dir-reap.test.sh`, `argv-ceiling.test.sh` set the
  pass/fail output convention (`=== name: N passed, N failed ===` / `OK: N/N`).
- `plugins/soleur/test/lib/scratch-session.ts` — exports `ensureScratchSession()`
  (:195), `writeScratchMarker()` (:122), `normalizeScratchBase()` (:73). Called by
  both bunfig preloads (`plugins/soleur/test/lib/git-tripwire.ts:108`) and the
  vitest `apps/web-platform/test/global-setup-git-tripwire.ts:25`, so **every
  `bun test`/`vitest` suite already allocates under an owned root**. The
  `kbcov-*`/`gdpr-gate-incidents-*`/`pirgate-*`/`cron-filing-fixture-*`/
  `harness-discovery-{fixture,empty,bare}-*` residue classes in the 2026-09-24
  measurement predate that wiring (#9117, merged ~2026-10-01).
- `scripts/lib/scratch-root.sh` — `soleur_scratch_session_begin` (:76),
  `_soleur_scratch_cleanup` (:158, splice into caller's existing trap per
  ADR-129 — never a second trap), `soleur_scratch_mark_owned` (:185).
- `scripts/test-all.sh:505-515` — the canonical `.sh` adoption pattern:
  opportunistic `source lib/scratch-root.sh`, then `soleur_scratch_session_begin`,
  then the `declare -F _soleur_scratch_cleanup` guard.
- `tests/scripts/test-scratch-residue.sh` — Guard 1 canary: registered leaves
  run twice (delta arm = zero residue after normal exit; counting arm = ≥1
  entry in a handed-in parent root, anti-vacuity). `add_leaf` registry at :181+;
  `sh` kind supported (PATH-shim mktemp counting).
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — 12 `mktemp`
  sites, all under a growing EXIT trap (:164→:809→:1179→:1714; the :1712 comment
  documents the same "extend, don't replace" convention the plan's splice uses).
  Producer of the measured `inngest-ci-*` (2,374) + `inngest-arm-*` (4,748)
  classes — kill-residue only today; registered suite (run-registered-suites
  "cloud-init" group) so the runner path is already owned, and the file is
  already trap-covered so it is NOT a `lint-trap-tempfile-ownership` census
  member. Direct-run is the gap.
- `plugins/soleur/scripts/harness-discovery-smoke.ts` — `scratchDir()` (:50)
  allocates `harness-discovery-{codex,devin}-*` homes; has a `SCRATCH[]` +
  `cleanupScratch()` exit path (:55) but no ownership marker — kill-residue
  leaks unattributably. Runs via `bun <file>` (ci.yml:1819,1865) — bunfig
  `[test].preload` does NOT apply outside `bun test`.
- `scripts/suite-durations.tsv` + `scripts/suite-shard-legs.tsv` — carry
  per-suite entries; check whether the suite registry expects a row for the new
  test file at work time.

### Institutional learnings applied

- `specs/archive/20261013-062704-feat-one-shot-10017-mktemp-tmp-leak/mktemp-census.md`
  — the disposition authority for #6752; all three sites verified clean.
  **Do not** "fix" `.claude/hooks/lib/session-state.sh` or
  `apps/web-platform/infra/workspaces-cutover.sh` — #6752 itself names them
  do-not-touch (fd-held locks; the EXIT trap IS the LUKS rollback path).
- ADR-129 — one trap owner per file; `_soleur_scratch_cleanup` is spliced into
  an existing trap list, never installed as a second trap.
- ADR-250 / `specs/archive/20260924-225942-feat-tmp-scratch-reclamation/spec.md`
  FR3/FR5/FR7 — the adoption contract: session roots for entry points,
  `.soleur-owned` markers for producers that cannot adopt, measured fixture
  writers get self-reap or markers.
- `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`
  — used two-stage `gh --json` + standalone `jq --arg` for the overlap query.
- Headless precedent: `specs/archive/20261012-231343-feat-one-shot-6760-security-scan-dir-leak/decision-challenges.md`
  — the prior Devin-CLI run recorded `pending - assumed` rulings in the same
  no-spawn context this run has.

### Premise Validation (Phase 0.6)

Checked every cited artifact: #6752 OPEN but all three sites verified clean by
the merged #10017 census (premise stale → close-out, not rework); #7004 OPEN,
machinery shipped in #8738 (premise "reclamation deferred" stale in the title —
the residual is producer adoption + the operator drain in #8786); #10167 OPEN
and **live** — `grep -qE "^${f}:[[:space:]]"` confirmed at parse-override.sh:74
on `origin/main`; #6760 CLOSED via merged PR #10158 (2026-10-12); cited files
`lint-trap-tempfile-ownership.{py,highwater}`, `scratch-root.sh`,
`tmpfs-guard.sh` all present on `origin/main`. Proposed mechanisms checked
against the ADR corpus: scratch-session adoption is the ADR-250 mechanism
itself (not a rejected alternative); no ADR governs frontmatter presence-check
shape — the two-arm design is free.

### Property List (Phase 0.6b)

1. A schema-permitted `findings_json` spelling (block mapping) validates; a
   truly-absent or declared-but-empty required field still fails. (#10167)
2. The three #6752 sites' no-leak property holds and is evidenced; no
   speculative trap edits reach the two do-not-touch files. (#6752)
3. Every measured producer class in the 2026-09-24 dry-run table whose
   producer can declare ownership does so — residue from a killed run is
   attributable and Reaper-3-reclaimable. (#7004)
4. The adoption is pinned by a failing-when-reverted guard, not by prose.
   (#7004 — the residue canary's delta/counting arms)

### Cut List (Phase 0.6b)

- New reaper / new classifier / new purge logic → property 3 — already shipped
  in #8738 (`tmp-classify.sh`, Reaper 3, `soleur-tmp-purge.sh`); CUT.
- Adding `trap … EXIT` to the three #6752 files → property 2 — already
  satisfied per census verification (stray allocs are `rm -f`'d on all paths or
  under an owning trap); the issue warns the blast radius makes speculative
  edits net-negative; CUT.
- Tier-3 `env -i` sweep (~91 files), absolute `/tmp` literal sweep, day-7 soak
  probe, adoption floor + AGENTS rule → property 3's *unmeasured* tail — the
  #7004 decision-challenge record already ruled ~25+ `env -i` judgement calls
  belong in their own review sitting; measured classes are what this PR
  adopts; CUT to a tracking issue (filed at work time).
- Wiring `tmpfs-guard` cron/systemd install → already shipped optional unit
  files + runbook; the host install + backlog drain is the operator step
  #8786; CUT (out of a code PR's reach by design).

### Value-Proposition note (Phase 0.6c)

Not cost/perf-justified work — the plan claims no saving to measure.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| #6752: "three remaining tempfile-ownership sites … allocates a tempfile whose ownership is not covered" | All three verified **already-clean** by merged census (stray allocs rm'd on all paths; owning traps present) | Verify once more on this tree; close with evidence; no edits |
| #7004: "reclamation deferred" | `reap_orphan_scratch_roots` + allocator + classifier + purge **all on main** (#8738) | Residual = adopt the 2 un-adopted measured producers; issue stays open for #8786 drain evidence |
| #7004 brief: "treat the deferred work as in-scope" | Tail = Tier-3 `env -i` (~91 files), absolute literals, soak probe — each a large judgement-call sweep | Bounded adoption only; tail deferred to a tracking issue (operator-scope row in decision-challenges) |
| #10167: presence grep rejects block mapping | Confirmed live at `parse-override.sh:74` | Two-arm presence check + dedicated fixture suite |

## Problem Statement / Motivation

Three small residuals in the same defect neighborhood, none big enough for its
own pipeline, each with a different honest disposition: one live bug
(#10167), one stale-premise chore (#6752), one authorized-but-mostly-shipped
reclamation residual (#7004).

## Proposed Solution

### #10167 — block-aware presence check

Replace the per-field `grep -qE "^${f}:[[:space:]]"` loop
(`parse-override.sh:73-77`) with a single `awk` pass over `$fm` that reports a
required field **present** iff its top-level `^f:` key line exists AND either
(a) a non-empty same-line value follows the colon (covers `f: {...}`, `f: |`,
`f: path`, `f: ""`), or (b) at least one subsequent line is indented before
the next top-level key (covers block mappings/sequences/scalars). A key line
with neither arm still reports `missing fields:` — the fix cannot degenerate
into key-line-presence, which would accept `findings_json:` with nothing under
it (YAML-null, schema-invalid anyway). `^`-anchored key matching keeps nested
same-named keys from false-presenting, and comment/blank lines are neutral.

Add `plugins/soleur/skills/skill-security-scan/test/parse-override.test.sh`:
scratch git repo fixture (`git init` → base commit → add override artifact →
run `parse-override.sh --base … --head …`), asserting: block-mapping
`findings_json` validates; flow-style validates; absent `findings_json` still
fails; declared-but-empty still fails; a second artifact missing `timestamp`
still fails; a `verdict: LOW-RISK` artifact still fails downstream checks.
`rule_pack_sha256` is seeded from the real manifest's `sha256sum` at runtime so
the freshness arm stays out of the assertion path. Scratch state lives only
under a `SUITE_TMP="$(mktemp -d)"` root removed by an owning
`trap 'rm -rf "$SUITE_TMP"' EXIT` placed BEFORE any `source` of test helpers —
lint rule (c) gates new files calling `mktemp` (`--changed` scope), so the
suite ships its own ownership; every negative arm pairs a positive control on
the same fixture so a broken check cannot pass vacuously. Never writes into
the repo — Check-10-sandbox-safe (repo read-only, HOME tmpfs, allowlisted
verbs only). Discovered automatically by the
`plugins/soleur/skills/*/test/*.test.sh` glob.

### #6752 — verify-and-close

Re-run the census verification on this tree (commands in Test Scenarios),
confirm all three sites still satisfy the no-leak property, and close the
issue with evidence cited in the PR body (`Closes #6752`). Zero code edits.

### #7004 — bounded producer adoption

Adopt the shipped ownership mechanism at the two measured-but-unadopted
producers:

1. `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — source
   `scripts/lib/scratch-root.sh` opportunistically and call
   `soleur_scratch_session_begin "$TMPDIR" || true` before the first `mktemp`
   (:163), mirroring the canonical sequence at `test-all.sh:507-514`:
   `declare -F` gate on `begin`, then
   `declare -F _soleur_scratch_cleanup || _soleur_scratch_cleanup() { :; }`
   so each trap arm can name the cleanup unconditionally. Then append
   `_soleur_scratch_cleanup || true` to **every arm of the growing
   EXIT-trap chain** (:164, :809, :1179, :1714) — each assignment replaces
   the previous trap, so a mid-chain assert failure exits through an arm
   that, unspliced, would leak the whole root. This is the dominant leak
   window; ADR-129's "single owner" is preserved because the file still has
   exactly one `trap` live at any time (the chain itself already documents
   this "extend, don't replace" convention at :1712). Covers `inngest-ci-*`,
   `inngest-arm-*`, `inngest-runcmd-*`, `guarda-*`, `nicg1-*`, `g4pull-*`
   residue on direct runs.
2. `plugins/soleur/scripts/harness-discovery-smoke.ts` — call
   `ensureScratchSession()` as a top-level statement immediately after
   imports (the same placement `git-tripwire.ts:108` uses; `main()` runs
   after and `scratchDir()` at :50 then allocates under the owned root) —
   import from `../test/lib/scratch-session`. The existing
   `SCRATCH[]`/`cleanupScratch()` exit path is unchanged (kill-residue is
   the gap it closes, not clean exits). Under a `bun <file>` invocation the
   bunfig `[test].preload` does not run, so the script currently binds no
   root at all — the import is the adoption, not a duplication.

Register `cloud-init-inngest-bootstrap.test.sh` as a `sh` leaf in
`tests/scripts/test-scratch-residue.sh` so the adoption is proven
non-vacuously (delta arm: zero residue; counting arm: ≥1 entry in handed-in
root). `harness-discovery-smoke.ts` is not leaf-registerable (needs real
codex/devin CLIs); its adoption is verified by inspection + the
marker-format parity pin the residue suite already carries.

## Implementation Phases

### Phase 1 — #10167 fix + fixture suite

- Replace the grep presence loop with the single awk pass in
  `parse-override.sh` (no behavior change for same-line spellings).
- Create `test/parse-override.test.sh` per the design above; RED-then-GREEN
  per `cq-write-failing-tests-before` (write the block-mapping arm first —
  it fails on main).
- Run the new suite + `scripts/skill-security-scan-step-body.test.sh` +
  `plugins/soleur/test/skill-security-scan.test.ts`.

### Phase 2 — #6752 verification + close-out

- Run the per-site verification commands (Test Scenarios) against the
  worktree; confirm the census's "already-clean" dispositions hold.
- `gh issue comment 6752` with the evidence trail (census rows + fresh
  verification); PR body carries `Closes #6752`.

### Phase 3 — #7004 bounded adoption

- `cloud-init-inngest-bootstrap.test.sh`: source + `begin` + cleanup
  spliced into all four growing-trap arms (see Proposed Solution).
- `harness-discovery-smoke.ts`: `ensureScratchSession()` at entry.
- `test-scratch-residue.sh`: register the sh leaf; run the residue suite.
- Verify suite passes standalone (`bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`).

### Phase 4 — bookkeeping + deferred-tail tracking

- File the deferred-tail issue: "tmpfs-guard: adoption tail — Tier-3 `env -i`
  sites, absolute `/tmp` literals, day-7 soak probe" (Refs #7004; cite the
  decision-challenge safety rationale) and link it from #7004 via comment.
- `gh issue edit 7004 --remove-label deferred-scope-out` (reclamation scope
  is now authorized).
- Confirm `suite-durations.tsv`/`suite-shard-legs.tsv` cover the new suite if
  the registry requires explicit rows.

## Files to Edit

- `plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh` —
  presence-check loop → single awk pass (~15 lines).
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — source
  scratch-root lib, `soleur_scratch_session_begin` at entry, splice
  `_soleur_scratch_cleanup` into the :1714 trap (~8 lines).
- `plugins/soleur/scripts/harness-discovery-smoke.ts` — import +
  `ensureScratchSession()` at entry (~3 lines).
- `tests/scripts/test-scratch-residue.sh` — `add_leaf` registration (~2 lines).
- `scripts/suite-durations.tsv` / `scripts/suite-shard-legs.tsv` — only if the
  suite registry requires explicit rows for the new test file.

## Files to Create

- `plugins/soleur/skills/skill-security-scan/test/parse-override.test.sh` —
  fixture suite (block-mapping accept + reject arms).
- `knowledge-base/project/specs/feat-one-shot-6752-7004-10167-tmp-gate-residuals/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-6752-7004-10167-tmp-gate-residuals/decision-challenges.md`

## User-Brand Impact

- **If this lands broken, the user experiences:** a legitimate skill-override
  artifact denied at the Write gate / red `pr-quality-guards` CI (block-mapping
  `findings_json` still rejected), or reclaimed residue the operator cannot
  attribute — both surface inside this repo's own tooling, not the product.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  user data path — all touched surfaces are repo-internal scripts and tests;
  the override artifacts are already public-repo files.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI/tooling change with no
  user-facing artifact and no data exposure path; one tier up would require a
  shipped-user surface, which nothing in the diff touches.

*Scope-out override (diff touches sensitive path `apps/web-platform/infra/` per preflight Check 6):* `threshold: none, reason: the only sensitive-path hit is a test file under apps/web-platform/infra/ — scratch-dir adoption in a test suite, no user-facing or credential surface`

## Observability

```yaml
liveness_signal:
  what:            # the two guards' own suite health — parse-override.test.sh
                   # and the new residue leaf are CI-enforced green
  cadence:         # per-PR (test-all / affected suites)
  alert_target:    # required-check failure on the PR
  configured_in:   # scripts/test-all.sh suite glob
                   # (plugins/soleur/skills/*/test/*.test.sh) + .github/workflows/

error_reporting:
  destination:     # CI check output + suite FAIL lines on stderr
  fail_loud:       # `=== parse-override: N passed, F failed ===` non-zero exit;
                   # residue leaf delta arm prints the leaked basenames

failure_modes:
  - mode:          # presence check degenerates to key-line presence (accepts
                   # `findings_json:` with no content)
    detection:     # fixture arm: `f:` declared-but-empty must report
                   # `missing fields: findings_json`
    alert_route:   # red parse-override.test.sh suite
  - mode:          # begin() silently degrades (lib missing/failed) so the
                   # adopted suite leaks un-owned again
    detection:     # residue counting arm requires ≥1 entry in the handed-in
                   # root — a no-op adoption creates nothing there → RED
    alert_route:   # red test-scratch-residue.sh
  - mode:          # a later contributor drops the leaf or the begin() call
    detection:     # delta arm sees residue / leaf-count floor moves → RED
    alert_route:   # red test-scratch-residue.sh

logs:
  where:           # suite stdout in CI job log; residue suite prints
                   # per-leaf delta/counting lines
  retention:       # GitHub Actions log retention (~90d)

discoverability_test:
  command:         bash plugins/soleur/skills/skill-security-scan/test/parse-override.test.sh
  expected_output: OK:
  # 4.7 suite-shape proxy argued down: this file is the probe — a ~7-arm
  # scratch-git fixture smoke (git init + 3 commits + one parse run per arm),
  # measured at work time well under Check 10's 15s cap; no smaller command
  # prints the `OK:` liveness signal, and the file itself is created in this PR.
```

## Architecture Decision (ADR/C4)

No new architectural decision: the plan extends the already-decided ADR-250
ownership mechanism to two more producers (an enumerated adoption, not a new
boundary) and amends one validation predicate inside an existing gate. A
competent engineer reading the ADR corpus + C4 after this ships is not misled:
the scratch-reclamation system is already modeled (ADR-250; `model.c4` plugin
container, incl. Amendment 2's quarantine drain).

**C4 completeness read (all three model files checked):** no new external
human actor (all actors — Founder/Operator, Contributor/PR Author, external
readers — unchanged); no new external system/vendor (no API, webhook, or
third-party store added); no new container/data-store (scratch roots are
host-local dirs already modeled via the plugin container's write surface); no
actor↔surface access-relationship change. `model.c4`, `views.c4`, `spec.c4`
require no edit.

## Guard Contract

### Guard 1 — parse-override required-field presence check (amended)

**Property.** A newly-added skill-override artifact's each required
frontmatter key reports present iff the top-level `^f:` key exists AND carries
content — a non-empty same-line value or an indented block before the next
top-level key/`---`; absent, nested-only, or declared-but-empty reports
missing.

**Assembly.** The single chokepoint `required_fields` loop in
`plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh`
(reached by `.claude/hooks/skill-security-scan-write.sh` PreToolUse,
`.github/workflows/pr-quality-guards.yml`, and
`skill-security-scan-postmerge.yml`), exercised by the new fixture suite
`test/parse-override.test.sh` — the only three doors an override artifact can
enter through all pass through this one loop.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Artifact spells `findings_json` as a block mapping (`findings_json:` + indented `code-execution: {…}`) | PASS — the defect being fixed; must-PASS non-canonical spelling |
| 2 | `findings_json` key line deleted from a compliant artifact | RED — `missing fields: findings_json` |
| 3 | `findings_json:` kept but emptied (no same-line value, next line is a top-level key) | RED — the check must not degrade to key-line presence |
| 4 | `findings_json` renamed `findings-json`, or indented under a different key | RED — absent/mis-nested both reject |
| 5 | Second artifact added alongside a compliant first, missing `timestamp` | RED — the check must not stop at the first member |
| 6 | Harness row: break the fixture's `git diff … --diff-filter=A` enumeration to emit nothing — a suite that checks zero artifacts and exits green is vacuous | RED — suite fails (assert on `matched` count / accounting floor) |
| 7 | `verdict: LOW-RISK` inside an otherwise-valid block-mapping artifact | RED — presence fix must not weaken downstream value checks |

### Guard 2 — scratch-residue leaf registration for cloud-init-inngest-bootstrap

**Property.** A directly-run `cloud-init-inngest-bootstrap.test.sh` leaves no
unowned top-level residue in its TMPDIR base: zero new entries after a normal
exit, and kill-residue is confined to an ownership-declared `soleur-run.<pid>.*`
root the reapers can attribute.

**Assembly.** The `add_leaf` registry in `tests/scripts/test-scratch-residue.sh`
(the one enumeration point every directly-runnable leaf passes through), the
suite's `soleur_scratch_session_begin` call-site (its own entry — the
adoption), and the counting/delta arm machinery that already executes per
registered leaf.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert `soleur_scratch_session_begin` in the suite | RED — delta arm sees top-level residue |
| 2 | Register a leaf whose command allocates nothing (e.g. a suite stubbed to `true`) | RED — counting arm requires ≥1 entry created in the handed-in root |
| 3 | Make `begin` a silent no-op (lib unresolvable path simulated) while leaf stays registered | RED — counting arm sees zero entries inside the parent root |
| 4 | must-PASS, non-canonical: run the leaf with a valid inherited `SOLEUR_SCRATCH_SESSION_ROOT` (nested runner shape) | PASS — parent's root governs, is populated, and is NOT deleted by the leaf |

## Alternative Approaches Considered

| Option | Rejected because |
|---|---|
| `^${f}:` presence-only (the issue's first suggestion) | accepts `findings_json:` declared-but-empty — degenerates presence into key-line existence; the two-arm check costs one awk pass and still rejects it |
| Parse frontmatter once into a map (the issue's second suggestion) | a YAML-subset parser is a bigger surface than the loop it replaces; the two-arm check is the minimal correct delta |
| Add `trap … EXIT` to the three #6752 files anyway | census verified them clean; the issue itself warns speculative edits there carry blast radius |
| Full #7004 "PR 2+" tail in this bundle (Tier-3 `env -i` ~91 files, absolute literals, soak probe, adoption floor) | the recorded safety rationale stands — judgement-call sweeps do not belong in the same review sitting; deferred to a tracking issue |
| Run the #8786 backlog purge from the pipeline | production-mutating on the operator host; explicitly an operator step per `wg-block-pr-ready-on-undeferred-operator-steps` |
| `Closes #7004` in the PR body | the issue's recorded close-condition is the #8786 drain evidence, which this PR cannot produce |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`scripts/learning-retrieval-bench.sh`" + "`scripts/weekly-analytics.sh`" + "`plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` … allocates a tempfile whose ownership is not covered by a single owning `trap … EXIT`" [issue #6752] | Phase 2 (verify + close) | mapped — disposition differs from a fix because the merged census already verified all three clean |
| 2 | "A count-shaped leak is reclaimed without any heuristic over a shared namespace — reclamation keys on ownership the producer declared" [issue #7004] | machinery already shipped (#8738); Phase 3 closes the producer-adoption residual | mapped |
| 3 | "the operator has now authorized the reclamation scope, so treat the deferred work as in-scope" [brief] | Phase 3 (two measured producers) + Phase 4 (deferred-tail tracking issue) | mapped — the in-scope residual is bounded to measured producers; the unmeasured tail is deferred, rationale in decision-challenges |
| 4 | "Make the presence check block-aware (e.g. `^${f}:` alone counts as present … or parse frontmatter once and check keys), and add a fixture covering the block-mapping form" [issue #10167] | Phase 1 (`parse-override.sh` awk pass + `test/parse-override.test.sh`) | mapped |
| 5 | "the pre-existing backlog is bounded by `tmpfiles.d` + reboot and is explicitly out of scope" [issue #7004 amended AC2] | — | descoped — justification: operator-approved amendment; backlog drain is the #8786 operator step |
| 6 | "A dry run against a real `/tmp` carrying the leak reclaims the leak and reports zero non-leak candidates" [issue #7004 AC2, as amended: "reclaims leaks of the declared shape"] | residue-leaf delta arm + Reaper 3 (already shipped) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `parse-override.sh` awk presence pass | "Make the presence check block-aware" | asked |
| `test/parse-override.test.sh` | "add a fixture covering the block-mapping form" | asked |
| `cloud-init-inngest-bootstrap.test.sh` `begin` + splice | "reclamation keys on ownership the producer declared" / "the operator has now authorized the reclamation scope" | asked |
| `harness-discovery-smoke.ts` `ensureScratchSession()` | same | asked |
| `test-scratch-residue.sh` leaf registration | — | inferred — justification: the adoption is invisible to CI without a residue leaf; the guard's registry is the designed assertion point (ADR-250 producer side) |
| Phase 4 tracking-issue + label edit | "A deferral without a tracking issue is invisible" (Step 6 checklist) | inferred — justification: deferred scope must be tracked or it silently re-lands |
| `gh issue comment` on #6752 / #7004 | — | inferred — justification: the close-out claims need evidence posted where the operator reads them |

### Split Assessment

- Subsystems touched: 5 — `plugins/soleur`, `apps/web-platform`, `tests`, `scripts`, `knowledge-base`
- Planned files: ~8 | Estimated changed lines: ~200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over the root-count threshold by construction of
  the bundle (three issues spanning disjoint roots is the stated intent:
  "single bundled PR"); each issue's own diff is <60 lines so the alternative
  is three micro-PRs, not a natural seam.

## Open Code-Review Overlap

None — queried 89 open `code-review`-labeled issues (two-stage
`gh --json` + standalone `jq --arg`) for every planned path; zero matches.

## Acceptance Criteria

- [ ] **AC1 — block-mapping accepted.** A skill-override artifact spelling
  `findings_json` as an indented block mapping validates through
  `parse-override.sh` (no `missing fields` in `invalid_schema`); same for
  flow-style and path-string spellings.
- [ ] **AC2 — rejection preserved.** An artifact with `findings_json` absent
  entirely, declared-but-empty (`findings_json:` + next top-level key), or
  nested under another key still fails with `missing fields: findings_json`.
- [ ] **AC3 — fixture suite exists and gates.** The new
  `test/parse-override.test.sh` carries arms AC1+AC2 plus a missing-`timestamp`
  second member and a `verdict: LOW-RISK` downstream arm; it is discovered by
  the `plugins/soleur/skills/*/test/*.test.sh` glob (proven by
  `bash scripts/test-all.sh --print-suite-globs` or equivalent enumeration).
- [ ] **AC4 — #6752 closed with evidence.** Re-verification on this tree
  reproduces the census's three already-clean dispositions; the PR body
  carries `Closes #6752` and the evidence trail;
  `git diff --quiet origin/main...HEAD -- scripts/learning-retrieval-bench.sh scripts/weekly-analytics.sh plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh .claude/hooks/lib/session-state.sh apps/web-platform/infra/workspaces-cutover.sh`
  is clean (merge-base diff — the moving-tip form reddens on sibling merges).
- [ ] **AC5 — suite scratch is owned.** Directly running
  `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` under a
  private TMPDIR leaves zero un-owned top-level entries on a clean exit, and
  a SIGKILL mid-run leaves only an attributable `soleur-run.<pid>.*` root —
  pinned by the new residue leaf (delta + counting arms green).
- [ ] **AC6 — smoke scratch is owned.** `harness-discovery-smoke.ts`
  `scratchDir` allocations land under an owned session root when the script
  runs directly (verify by inspection + `TMPDIR=<base> timeout -s KILL …`
  leaving only a marker-bearing root — executed at work time).
- [ ] **AC7 — no ownership regression.** `tests/scripts/test-scratch-residue.sh`
  stays green including the new leaf; `python3 scripts/lint-trap-tempfile-ownership.py --census`
  unchanged (the adopted file was already trap-covered, not a class-b member).
- [ ] **AC8 — bookkeeping landed.** Deferred-tail tracking issue filed and
  linked from #7004; `deferred-scope-out` label removed from #7004; PR body
  carries `Closes #6752`, `Closes #10167`, `Refs #7004`, `Refs #8786` — and
  does NOT carry `Closes #7004`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal engineering tooling
(shell/test machinery). The `security` token in `skill-security-scan`
triggered the conservative `cross-domain` lane, but the semantic sweep finds
no marketing, product, legal, sales, finance, support, or ops surface; the
mechanical UI-surface glob matches zero planned files. No domain leaders
spawned — this harness has no agent-spawn capability; recorded in
`decision-challenges.md`.

### Product/UX Gate

Tier: none — no UI-surface file in Files to Edit/Create; the plan implements
orchestration/test changes only.

## Test Scenarios

- Given a scratch git repo where a branch adds
  `knowledge-base/engineering/security/skill-overrides/2026-10-13-x.md` whose
  `findings_json:` is an indented block mapping, when
  `parse-override.sh --base <base> --head <head>` runs, then `invalid_schema`
  is empty and the artifact appears in `matched`. (`integration`)
- Given the same fixture with `findings_json` deleted, `findings_json:` emptied,
  or indented under `justification:`, when parse-override runs, then
  `invalid_schema` reports `missing fields: findings_json`. (`integration`)
- Given a second added artifact missing `timestamp` beside a compliant first,
  when parse-override runs, then `invalid_schema` names the second artifact.
  (`integration`)
- Given the worktree, when
  `python3 scripts/lint-trap-tempfile-ownership.py --census` +
  `grep -n 'trap\|rm -f' scripts/learning-retrieval-bench.sh` etc. run, then
  all three #6752 sites reproduce the census dispositions (rm'd on all paths
  or owning trap; single owner for constraint-scaffold). (`integration`)
- Given a private TMPDIR, when
  `TMPDIR=<priv> bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
  runs clean, then `<priv>` gains zero top-level entries; when the same run is
  `timeout -s KILL`-interrupted mid-suite, then only a marker-bearing
  `soleur-run.<pid>.*` root remains. (`integration` — the residue leaf's two arms)
- Given `test-scratch-residue.sh`, when run, then every registered leaf —
  including the new one — passes its delta and counting arms. (`integration`)

## Success Metrics

- The block-mapping `findings_json` spelling validates end-to-end (the
  operator's documented inline-override path unblocks).
- Zero un-owned top-level residue from the two adopted producers on direct runs.
- `#6752` closes; `#10167` closes; `#7004` carries the adoption evidence +
  tracking link and loses `deferred-scope-out`.

## Dependencies & Risks

- `cloud-init-inngest-bootstrap.test.sh` must pass standalone for the residue
  leaf to be meaningful — verify at Phase 3 before registering; if it requires
  the runner's env, adopt `begin` anyway (no-op under runner) but register the
  leaf only if it runs green standalone.
- Pre-existing suite failures are documented on this host (#7210 tmpfs-guard
  socket-held-tree cases; #8335 five pre-existing suite failures) — do not
  chase them; `wg-when-tests-fail-and-are-confirmed-pre` applies.
- `begin` degrade arm is by-design (opportunistic source, `|| true`) — the
  counting arm is what proves adoption actually happened, not merely invoked.
- `lint-guard-contract.py` validates the `## Guard Contract` section
  mechanically at deepen-plan Phase 4.11 — matrix rows are design-derived, not
  implementation-derived.

## References & Research

- Issues: #6752, #7004 (+ #8786 drain tracker), #10167, #6760, #6734, #6991,
  #10017, #9117
- PRs: #10158 (merged #6760 close-out), #8738 (reclamation machinery), #7019
  (alarm rebaseline), #10129 (census)
- Specs: `specs/archive/20260924-225942-feat-tmp-scratch-reclamation/`
  (spec.md FR3/FR5/FR7, measurements.md), `specs/archive/20261013-062704-feat-one-shot-10017-mktemp-tmp-leak/mktemp-census.md`,
  `specs/archive/20261013-041741-feat-one-shot-7004-tmpfs-reclaim-scratch-roots/`
- ADRs: ADR-129 (one trap owner), ADR-133 (tmpfs managed resource), ADR-250
  (ownership-keyed reclamation)
- `override-artifact-schema.json` (`findings_json` oneOf string|object);
  `override-mechanism.md` (documents the same-line constraint until #10167 lands)

## Sharp Edges

- Do NOT touch `.claude/hooks/lib/session-state.sh` or
  `apps/web-platform/infra/workspaces-cutover.sh` — the issue names them
  do-not-touch; the census re-verified both (fd-held locks; the EXIT trap IS
  the LUKS rollback path).
- ADR-129: `_soleur_scratch_cleanup` is spliced into the file's existing
  (growing) EXIT-trap chain — never a second `trap … EXIT`. The final
  assignment (:1714) is the terminal owner.
- The `awk` presence pass must keep `^` anchoring — a nested `findings_json:`
  inside another field's block must not false-present.
- `parse-override.sh` is executed by THREE doors (PreToolUse hook + two
  workflows); a crash there is fail-closed by construction — keep stderr quiet
  and the exit contract intact.
- The `## User-Brand Impact` scope-out bullet is load-bearing: the
  `apps/web-platform/infra/` file trips preflight Check 6's sensitive-path
  regex; without the `reason:` bullet the ship gate FAILs.
