---
title: "ci: repair affected-index-ratchet — 8 uncovered pairs on main (#11713 git-data + #11688 npm-oidc)"
type: fix
date: 2026-11-01
slug: ci-affected-index-ratchet-pairs-repair
branch: feat-one-shot-11796-ratchet-pairs
issue: 11796
closes: 11796
lane: cross-domain
---

# ci: repair affected-index-ratchet — 8 uncovered pairs on main (#11713 git-data + #11688 npm-oidc)

The advisory `affected-index-ratchet` CI job (`continue-on-error`, `.github/workflows/ci.yml`
job `affected-index-ratchet`) is red on every head. `python3 -I scripts/ci-pr-affected-replay.py
ratchet --report` on this branch reproduces `SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=new-pair
live=1518 baseline=1510` — **eight** uncovered pairs, not the five the issue measured at
`6d168231cf`: #11713's git-data machinery contributed five and #11688's npm-OIDC machinery
landed three more after the issue was filed. The ratchet reads any uncovered pair as `new-pair`,
so a partial repair cannot return the check to green — this plan covers all eight with the
ratchet's own two remedies (declared edge for a real read, anchor-keyed accept row for a
mention) per runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
("Ratchet red because main moved" + "The drain rubric"). No new machinery is added and no
baseline line is added.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user artifact — the check gates
  Soleur's own PR flow. Worst case: the advisory check stays red, or a declared edge selects
  one extra cheap suite on a rare lib/runbook edit.
- **If this leaks, the user's [data / workflow / money] is exposed via:** not applicable —
  no user data surface is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** CI-selection machinery and accept-row bookkeeping;
  the blast radius is reviewer-facing signal quality, not a user-facing surface.

*Scope-out override:* `threshold: none, reason: the diff touches only CI-selection
declarations and an accept-row table — no user-impacting path.`

## Observability

```yaml
liveness_signal:
  what:            affected-index-ratchet check conclusion on pull_request/merge_group runs
  cadence:         per-PR / per-queue-entry
  alert_target:    PR check list (advisory; the soak tracker #10865 watches the window)
  configured_in:   .github/workflows/ci.yml (affected-index-ratchet job)

error_reporting:
  destination:     GHA job log + step summary on the failing run
  fail_loud:       "SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=<kind> live=N baseline=M line"

failure_modes:
  - mode:          baseline/accept drift re-reddens every head
    detection:     the ratchet job's own exit marker on the next pull_request run
    alert_route:   the failing check on the PR itself; soak tracker #10865

logs:
  where:           GHA run log for job affected-index-ratchet; --report artifact on RUNNER_TEMP
  retention:       GitHub's run-log retention window

discoverability_test:
  command:         python3 -I scripts/ci-pr-affected-replay.py ratchet
  expected_output: SOLEUR_PR_AFFECTED_RATCHET exit=0
```

## Research Insights

**Premise Validation** (Phase 0.6): issue #11796 is OPEN with no merged or open linked PR.
Collision-precheck found only this run's own draft PR #11814 (same branch) plus two foreign
`test-all.sh` processes in sibling worktree `feat-one-shot-11648-fast-tier-demotion` — unrelated
scope, reported here per the gate. Every cited artifact exists on the tree and every cited
boundary line was verified by direct read: `scripts/lint-betterstack-emitter-read.sh:133`
(the `ALLOW` map row), `scripts/followthroughs/git-data-replication-signal.sh:75,:77` (runtime
`source` lines), `scripts/followthroughs/git-data-replication-signal.test.sh:131` (stub write).
One premise drift: the issue says 5 pairs at live=1515; a local `ratchet --report` now shows
**8 pairs at live=1518** — three npm-OIDC pairs from #11688 landed after the measurement.
Plan response: cover all eight (the ratchet cannot return `exit=0` while any pair is
uncovered); provenance per pair is recorded below and goes in the PR body.

**Property List** (Phase 0.6b): (1) the check returns to green on every head (`exit=0`);
(2) the repair uses only the ratchet's existing remedies — it must not weaken what the audit
measures (no baseline-row additions, no re-basing); (3) each pair gets the disposition the
drain rubric assigns to it, verified against the suite's real read surface.

**Cut List** (Phase 0.6b): baseline regeneration via `--print-baseline` is prune-only — it
cannot add rows, so it is not a remedy for new pairs, only for dead ones (run at the end to
confirm zero drift). No new scripts, gates, or waivers.

**Live audit reproduction** (this branch, `ratchet --report` — every boundary line quoted
below is from the tool's own `ref` lines):

| # | Pair | Boundary evidence | Kind (rubric §7) | Disposition |
|---|------|-------------------|------------------|-------------|
| 1 | `scripts/git-data-replication-signal-11704 → scripts/lib/betterstack-sources.sh` | SUT `git-data-replication-signal.sh:75` `source "${ROOT}/scripts/lib/betterstack-sources.sh"` (`1cc8cd95e8cf/1`) | (a) executes/sources; test `cp`s the real lib into the fixture tree (:123-125) and `-f`-asserts it (:33-35) | **declare edge** |
| 2 | `scripts/git-data-replication-signal-11704 → scripts/lib/betterstack-read-classify.sh` | SUT `git-data-replication-signal.sh:77` `source` (`e68a20b3166c/1`); same test `cp`/`-f` arms | (a) executes/sources | **declare edge** |
| 3 | `scripts/git-data-replication-signal-11704 → scripts/betterstack-query.sh` | test `:131` `cat > "$TREE/scripts/betterstack-query.sh" <<'STUB'` (`9b15ae82a00e/1`), test `:149` `chmod +x` on the stub (`3db9a5675390/1`), SUT `:72` `BSQ="${ROOT}/scripts/betterstack-query.sh"` (`7feaf06e5ad1/1`) | mention — the suite writes a stub into the scratch tree and the copied SUT resolves `BSQ` to `$TREE` (`ROOT=dirname…/../..`), so the real script is never opened | **accept row ×3** (one per boundary line) |
| 4 | `scripts/betterstack-emitter-read → knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` | `lint-betterstack-emitter-read.sh:133` (`f35b5c5e8a3d/1`) — the ADR path sits inside the `ALLOW` map's reason *value* | mention — `data row not fed to a read loop` | **accept row** |
| 5 | `scripts/betterstack-emitter-read → scripts/followthroughs/git-data-replication-signal.sh` | `lint-betterstack-emitter-read.sh:133` (`f35b5c5e8a3d/1`) — the path is the `ALLOW` map *key* | mention — `data row not fed to a read loop`; the probe IS a live-walk candidate, so the reason must cite the FLOOR/LIVE real-tree arms + the always-on twin, not "never reads" | **accept row** |
| 6 | `plugins/soleur/test/npm-publish-oidc.test.sh → packages/opencode-plugin/package.json` | test `:1103` `_pkg_json="$(jq -r .name "$REPO_ROOT/packages/opencode-plugin/package.json" …)"` (`243d3a657939/1`), `:1105` parity assert (`e6f0ead4b98e/1`) | (b) opens content — `jq` reads the real file | **declare edge** (existing `AFFECTED_PLUGINS_SOLEUR_TEST_NPM_PUBLISH_OIDC_TEST_SH_PATHS` array) |
| 7 | `plugins/soleur/test/npm-publish-oidc.test.sh → knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md` | test `:850` `grep -qF` output check (`fa587a9183a9/1`), SUT `.github/scripts/npm-oidc-diagnose.sh:54` `RUNBOOK=` (`e9fef2131543/1`) — and test `:1107` `[[ -f "$REPO_ROOT/$_rb" ]]` asserts the printed path **exists** | (c) asserts existence where the verdict depends on it — a runbook rename/delete must select this suite | **declare edge** (same existing array) — also prunes kb-consumers baseline row |
| 8 | `plugins/soleur/test/npm-publish-oidc.test.sh → package.json` (repo root) | same `:1103`/`:1105` lines — `package.json` appears only as the basename inside `packages/opencode-plugin/package.json` and inside the `:1105` fail text | mention — root `package.json` is never opened | **accept row ×2** |

Totals: **4 declared edges** (2 new array entries for the replication suite, 2 additions to the
existing npm-oidc array) + **7 accept rows** + **1 conditional kb-consumers baseline prune** +
the prune-only `--print-baseline` verification.

**Boundary-line verification notes** (the issue's "verify each boundary line's kind" ask):

- Pair 3 has exactly the three refs above per the report; `audit --all-refs` at work time
  re-enumerates before rows are written (the report caps at 3 `ref` lines per pair — the
  2026-11-01 learning shows the deciding line can hide beyond the cap).
- Pairs 1–2 may carry additional test-file refs (:33-35 `-f` asserts, :123-125 `cp`) that the
  capped report did not print — irrelevant to disposition (a declared edge covers every
  boundary line of the pair) but visible under `--all-refs`.
- Pair 7's deciding line (`:1107` `[[ -f "$REPO_ROOT/$_rb" ]]`) is NOT a `ref` line — it
  references `$_rb`, not the literal path — exactly the "SUT source, not the test file" class
  the 2026-11-01 learning warns about. Accepting this pair would write a false "mention"
  claim on a verdict-coupled existence assert — the rubric-(c) real dependency.
- Pair 4: the ADR contains zero `betterstack-query` hits (`grep -c` = 0); whether the live
  census walk reads it as an eligible file, the reason cites the real-tree arms + always-on
  twin per `learnings/test-failures/2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms.md`
  — no "never reads" claims.

**Edge cost check** (drain rubric "one suite run per ~20 PRs" bound): `git log --since=90.days
origin/main -- <path>` = 1 commit for each of `scripts/lib/betterstack-sources.sh`,
`scripts/lib/betterstack-read-classify.sh`, `scripts/followthroughs/git-data-replication-signal.sh`,
`scripts/betterstack-query.sh`, `packages/opencode-plugin/package.json`,
`npm-publish-trusted-publisher.md`; 2 for the ADR. All ~zero — no hold-back trigger (none is
a >8-commits/90d hot file either).

**Precedent and learnings:**

- PR #11781 (merged 2026-11-01, this repair's same-day sibling for #11771) — identical recipe:
  stale-row correction + `AFFECTED_*_PATHS` declaration + anchor-keyed accept row + prune-only
  baseline check. Its `decision-challenges.md` records the CTO ruling that a SUT runtime read
  makes the whole pair a declared edge (applied to pairs 1–2 and 7 here).
- PR #11734 (#11694) — same repair shape; produced
  `learnings/test-failures/2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms.md`:
  accept reasons must enumerate the suite's real-tree arms (`lint-betterstack-emitter-read.test.sh`
  FLOOR `:335` + LIVE `:347`) and cite the always-on `scripts/betterstack-emitter-read-live`
  twin — binding for pairs 4–5.
- `learnings/test-failures/2026-11-01-ratchet-repair-pair-disposition-moved-echoes-and-sut-source-boundary.md`
  — run `audit --all-refs` before choosing dispositions; `--print-baseline` is prune-only and
  adopted only when it differs.
- Existing accept rows `scripts/ci-pr-affected-audit.accept.tsv:160-162` are the verbatim
  precedent for the `betterstack-emitter-read` ALLOW-table disposition (kind `data row not
  fed to a read loop`).
- The `AFFECTED_SCRIPTS_GIT_DATA_REHEARSAL_EVIDENCE_8211_PATHS` array
  (`scripts/lib/test-affected-paths.sh:3299`) already declares the same two betterstack libs
  for a sibling git-data suite — the new array mirrors it.

**Related issues:** #11796 (this fix), #11713 (introducer of pairs 1–5, squash `78de558634`),
#11688 (introducer of pairs 6–8, squash `30fd787978`), #11771/PR #11781 (same-day precedent),
#10865 (soak tracker observing the advisory window), #8800 (overlap, acknowledged below).

**External research:** skipped — repo-internal machinery with an authoritative runbook, a
same-day merged precedent, and live tool output; external material would add nothing.

## Implementation

### Step 1 — Declare the four real-read edges in `scripts/lib/test-affected-paths.sh`

**Consumer (sharp-edge `AFFECTED_*_PATHS` rule — the list is live, not inert):** the
selector in `scripts/test-all.sh` resolves each registration label to its array by
name — `_arr="AFFECTED_${_u}_PATHS"` (`:3962`), `_u` computed by the label
normalisation at `:3958-3960` (`tr 'a-z' 'A-Z'`, non-alnum→`_`, leading `_` stripped),
then `declare -p "$_arr"` → `_affected_resolve_edges` → `_AC_CLASS="edge:declared"`
(`:3963-3967`). Label `scripts/git-data-replication-signal-11704` therefore maps to
`AFFECTED_SCRIPTS_GIT_DATA_REPLICATION_SIGNAL_11704_PATHS` and the arrays ARE the
mechanism that selects the suite — verified at Step 4's `--print-selection` check.

1a. Extend the existing `AFFECTED_PLUGINS_SOLEUR_TEST_NPM_PUBLISH_OIDC_TEST_SH_PATHS` array
(~line 3359), keeping sorted order:

```bash
AFFECTED_PLUGINS_SOLEUR_TEST_NPM_PUBLISH_OIDC_TEST_SH_PATHS=(
  ".github/workflows/npm-publish.yml"
  "knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md"  # test :1107 asserts [[ -f ]] — rename/delete must select
  "packages/opencode-plugin/package.json"                                            # test :1103 jq -r .name — real content read
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
```

1b. Add a new array for the replication suite, in label-sorted position immediately after
`AFFECTED_SCRIPTS_GIT_DATA_REHEARSAL_EVIDENCE_8211_PATHS` (REBOOT < REHEARSAL < REPLICATION):

```bash
# scripts/git-data-replication-signal-11704 — the suite copies both real libs into the
# fixture tree (git-data-replication-signal.test.sh:123-125, -f-asserted at :33-35) and the
# SUT sources them at runtime (git-data-replication-signal.sh:75,:77). betterstack-query.sh
# is deliberately NOT here: the suite writes a stub into $TREE (:131) and the copied SUT
# resolves BSQ inside $TREE (:72); the real script is never opened — accept rows cover it.
AFFECTED_SCRIPTS_GIT_DATA_REPLICATION_SIGNAL_11704_PATHS=(
  "scripts/lib/betterstack-read-classify.sh"
  "scripts/lib/betterstack-sources.sh"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
```

### Step 2 — Write the seven accept rows in `scripts/ci-pr-affected-audit.accept.tsv`

One row per boundary line, anchors/ordinals taken from `audit --all-refs` at work time (the
`--report` run already printed them; re-verify because line edits can shift anchors). Each row
is the canonical `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>` shape:

- `scripts/betterstack-emitter-read` → `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`, anchor `f35b5c5e8a3d` ord `1`. Reason: `data row not fed to a read loop: scripts/lint-betterstack-emitter-read.sh:133` — the ADR path is a doc citation inside the `ALLOW` map's reason *value*; the suite's real-tree reads are the FLOOR and LIVE no-arg guard runs (`lint-betterstack-emitter-read.test.sh:335,:347`), both duplicated by the always-on `scripts/betterstack-emitter-read-live` suite.
- `scripts/betterstack-emitter-read` → `scripts/followthroughs/git-data-replication-signal.sh`, anchor `f35b5c5e8a3d` ord `1`. Reason: `data row not fed to a read loop: scripts/lint-betterstack-emitter-read.sh:133` — the `ALLOW`-table map key names the probe as data; the suite drives the guard over git-init fixture trees; its real-tree reads of the probe are the FLOOR/LIVE arms cited above, duplicated by the always-on `-live` suite.
- `scripts/git-data-replication-signal-11704` → `scripts/betterstack-query.sh`, anchor `9b15ae82a00e` ord `1`. Reason: fixture stub write — `git-data-replication-signal.test.sh:131` `cat > "$TREE/scripts/betterstack-query.sh"`; the real script is never opened.
- `scripts/git-data-replication-signal-11704` → `scripts/betterstack-query.sh`, anchor `3db9a5675390` ord `1`. Reason: fixture stub chmod — `git-data-replication-signal.test.sh:149` `chmod +x` applies to the stub inside `$TREE`; the real script is never opened.
- `scripts/git-data-replication-signal-11704` → `scripts/betterstack-query.sh`, anchor `7feaf06e5ad1` ord `1`. Reason: path assignment shadowed by the fixture — `git-data-replication-signal.sh:72` `BSQ="${ROOT}/scripts/betterstack-query.sh"` resolves against `ROOT`, which under the suite is `$TREE` (the SUT copy), so the exec target is the stub; the real script is never opened.
- `plugins/soleur/test/npm-publish-oidc.test.sh` → `package.json` (repo root), anchor `243d3a657939` ord `1`. Reason: basename token — `:1103` opens `packages/opencode-plugin/package.json` (declared edge); root `package.json` is never read.
- `plugins/soleur/test/npm-publish-oidc.test.sh` → `package.json` (repo root), anchor `e6f0ead4b98e` ord `1`. Reason: basename token — `:1105` fail text mentions `package.json name`; root `package.json` is never read.

Reasons are draft shapes — each must be checked off against the line's kind at write time
(per the real-tree-arms learning and the closed kind grammar `message`, `JSDoc/comment`,
`data row not fed to a read loop`, `code line in a file read only as text`, …); rows are
inserted in TSV sorted position, never appended.

### Step 3 — Prune the kb-consumers baseline row the runbook edge vacates

`scripts/test-affected-kb-consumers.baseline.txt:100` carries
`plugins/soleur/test/npm-publish-oidc.test.sh → knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md`.
Declaring that edge (Step 1a) removes the pair from the kb-consumers live set — the same move
#11781 made for the home-census CLO row. Remove the line and run
`bash scripts/test-affected-kb-consumers.test.sh` to confirm the suite agrees (if the live
set still reports the pair, restore the line — the tool's verdict governs, not this plan's
prediction).

### Step 4 — Verify green + prune-only baseline

- `python3 -I scripts/ci-pr-affected-replay.py ratchet` → expect
  `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass`.
- `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > /tmp/pb.tsv &&
  diff -q /tmp/pb.tsv scripts/ci-pr-affected-audit.baseline.tsv` — adopt the pruned file
  only if they differ (prune-only; never hand-edit, never add a row).
- `bash scripts/lint-orphan-test-suites.sh` → clean on the new/changed `AFFECTED_*_PATHS`
  arrays (census linter).
- Selector behavioral check: `bash scripts/test-all.sh --print-selection
  --paths=scripts/lib/betterstack-sources.sh` → the replication suite selected via
  `edge:declared`; `--paths=knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md`
  → the npm-oidc suite selected via `edge:declared`.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — two path entries added to the existing npm-oidc
  array; one new `AFFECTED_SCRIPTS_GIT_DATA_REPLICATION_SIGNAL_11704_PATHS` array
- `scripts/ci-pr-affected-audit.accept.tsv` — seven anchor-keyed accept rows (sorted inserts)
- `scripts/test-affected-kb-consumers.baseline.txt` — one row pruned (the npm runbook pair
  the declared edge vacates; restore if the suite disagrees)
- `scripts/ci-pr-affected-audit.baseline.tsv` — conditional: only if `--print-baseline`
  output differs (prune-only regeneration)

## Files to Create

- none

## Open Code-Review Overlap

One probe hit: #8800 (census-sandbox write-through hazard in
`scripts/test-all-affected.test.sh`) — matched only because its body names
`scripts/lib/test-affected-paths.sh`. **Acknowledge:** different concern (fixture builder
semantics, not the declaration tables this plan edits); it keeps its own issue and
re-eval date. Not folded in.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "two declared edges in scripts/lib/test-affected-paths.sh (git-data-replication-signal-11704 → scripts/lib/betterstack-read-classify.sh and → scripts/lib/betterstack-sources.sh, both real runtime `source` reads)" [issue #11796 brief] | Step 1b | mapped |
| 2 | "anchor-keyed accept rows in scripts/ci-pr-affected-audit.accept.tsv for the two betterstack-emitter-read refs and the betterstack-query.sh fixture-class mention — after verifying each boundary line's kind against the suite" [issue #11796 brief] | Step 2 | mapped |
| 3 | "Finish with `--print-baseline` prune-only verification" [issue #11796 brief] | Step 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New `AFFECTED_SCRIPTS_GIT_DATA_REPLICATION_SIGNAL_11704_PATHS` array (Step 1b) | ask 1 | asked |
| Seven accept rows (Step 2) | ask 2 | asked — count is 7 not "≤3" because `--report` shows 3 refs for the stub pair plus 3 pairs landed after the issue's measurement |
| npm-oidc array additions — `packages/opencode-plugin/package.json`, `npm-publish-trusted-publisher.md` (Step 1a) | "ci: affected-index-ratchet red again" [issue title] | inferred — justification: the ratchet reads any uncovered pair as `new-pair`; `exit=0` requires zero uncovered pairs, so the 3 pairs #11688 landed after the issue's measurement must be covered in the same repair PR or the check stays red |
| kb-consumers baseline prune (Step 3) | — | inferred — justification: the declared runbook edge vacates `baseline.txt:100`; leaving it re-breaks `scripts/test-affected-kb-consumers` (the #11781 precedent removed the same class of row) |
| `--print-baseline` prune-only check (Step 4) | ask 3 | asked |

### Split Assessment

- Subsystems touched: 1 — `scripts/` CI-selection machinery
- Planned files: 4 (1 conditional) | Estimated changed lines: ~20
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

### Engineering

The only relevant domain: CI-selection machinery owned by the engineering tooling
surface. No product, marketing, legal, finance, sales, support, or operations impact —
the change alters which test suites a diff selects and adds audit accept rows. The
npm-oidc edge references a runbook path and the betterstack pair an ADR path, but no
runbook/ADR content changes.

## Acceptance Criteria

- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` prints
  `SOLEUR_PR_AFFECTED_RATCHET exit=0` on this branch (covers all 8 live uncovered pairs,
  not only the 5 the issue measured).
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline` output equals
  `scripts/ci-pr-affected-audit.baseline.tsv` (or the file is replaced by the pruned
  output — never hand-edited, never grown).
- [ ] No accept row is stale (`anchor-not-live`): `ratchet` reports zero `stale-accept`
  rows; every accept-row reason names the verified line kind and survives the suite's
  real-tree arms check (FLOOR `:335`, LIVE `:347`, always-on twin cited where applicable).
- [ ] `bash scripts/test-affected-kb-consumers.test.sh` passes after the runbook edge is
  declared (baseline row pruned iff the live set no longer reports it).
- [ ] `bash scripts/lint-orphan-test-suites.sh` clean on the changed/new `AFFECTED_*_PATHS`
  arrays.
- [ ] `bash scripts/test-all.sh --print-selection --paths=<edge path>` shows the affected
  suite selected via `edge:declared` for at least one path per declared edge.
- [ ] `Closes #11796` on the PR body, with per-pair provenance (#11713 vs #11688) recorded.

## Enhancement Summary

Gate dispositions verified at plan time: User-Brand section present (threshold `none`,
scope-out bullet included); Observability block carries a locally-runnable
`discoverability_test` (`python3 -I scripts/ci-pr-affected-replay.py ratchet`, first token
`python3` on the Check-10 allowlist); no UI surface (Phase 2.5 mechanical override: no
`.tsx`/`page.tsx`/`layout.tsx` in Files lists — NONE); no regulated-data surface and no
(a)-(d) GDPR trigger; no new infrastructure (Phase 2.8 skip); no new persistent store or
connection (Phase 2.11 skip); no architectural decision — extending declared edges of an
existing mechanism per its own runbook (Phase 2.10 skip); deliverable introduces no new
guard/gate — it edits the declaration data of the existing ratchet (Phase 2.12 not
triggered, mirroring the #11781 disposition); no new autonomous-task surface (Phase 2.9.3
skip); `## Scope Check` present with all three asks mapped and two justified `inferred`
rows (npm-pair coverage, kb-consumers prune).
