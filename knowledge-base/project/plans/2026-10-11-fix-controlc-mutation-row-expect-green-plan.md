---
title: "fix: provisioner-parity mutation battery — control-C to expect_green under _norm classification"
type: fix
date: 2026-10-11
slug: fix-controlc-mutation-row-expect-green
branch: feat-one-shot-9970-controlc-expect-green
issue: 9970
closes: 9970
lane: cross-domain
---

# fix: provisioner-parity mutation battery — control-C to `expect_green` under `_norm` classification

## Overview

The `control-C` row in `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` is
red on `main` (GitHub issue #9970). The guard-side fix already landed in squash `21331e94e3`:
`apps/web-platform/infra/web-host-provisioner-parity.test.sh` now normalizes Terraform resource
names via `_norm()` (`lower()` + `-` → `_`) at the classification boundary, so the mutation that
renames `cosign_trusted_root` → `Cosign-Trusted_Root` resolves to the same normalized identity and
is correctly transparent — still swept, still justified. The row still calls `expect_red` with the
anchor `uncovered=['Cosign-Trusted_Root@web-2']`, a diagnostic the normalized guard can no longer
emit; post-merge CI run `38105510433` (`deploy-script-tests (4/4)` leg, `.github/workflows/infra-validation.yml`)
reports `[FAIL] control-C …: guard still PASSED with the invariant broken`.

The change has three parts, all in the battery file only — the guard is already correct and is not
touched:

1. Flip `control-C` to `expect_green` (signature `expect_green <label> <file> <mutator>` — three
   args, the expected-anchor argument drops).
2. Rewrite the stale comment block above the row, which currently justifies `expect_red`, to
   describe post-normalization semantics and the two re-break modes it now pins.
3. Add a sibling `expect_red` row (`M4j`) renaming to a normalized-UNIQUE name so the battery keeps
   pinning that normalization did not swallow detection. (Rationale corrected post-review:
   `mutations_run` is also incremented at inline sites — M33b, `_g2_json_row`, G2-C2 — so the
   landed count is ~75 and the bare flip would NOT trip `FLOOR=57`. M4j stands on its primary
   reason alone: the detection-preservation pin.)

The unrelated `cloud-init-inngest-bootstrap` pin drift, also red in the same CI leg, is out of scope
(tracked separately).

## Research Insights

### Premise Validation

- `gh issue view 9970` → `OPEN`, `closedByPullRequestsReferences: []` — the issue is live.
- Squash `21331e94e3` (PR #9947) is in history; `_norm()` is present at
  `web-host-provisioner-parity.test.sh` `def _norm` with the `#9970` comment — the cited
  normalization landed exactly as described.
- Local reproduction of the battery confirms the stale row:
  `[FAIL] control-C (uppercase/hyphen rename is swept by the classification): guard still PASSED
  with the invariant broken -- it cannot detect this` — byte-identical in shape to the CI failure.
- Harness signatures verified at `expect_red()` / `expect_green()` definitions:
  `expect_red <label> <file> <expected-anchor> <mutator>` (4 args) and
  `expect_green <label> <file> <mutator>` (3 args).
- ADR corpus grep (`provisioner.parity|_norm|name-normaliz` over
  `knowledge-base/engineering/architecture/decisions/`): no ADR decides this mechanism; the rename
  is a test-expectation alignment, not an architectural decision (Phase 2.10 skips cleanly).

### Empirical Verification (harness-faithful sandbox, 2026-10-11)

A replication of the battery's own sandbox (scratch `TF_REPO` + `git_fixture_env` + the same
`git ls-files --cached --others --exclude-standard -- '*.tf' '*.tf.json'` enumeration, all five
`INPUTS` + 70+ `.tf` files) ran the real guard three times:

- Baseline (pristine tree): GREEN.
- `cosign_trusted_root` → `Cosign-Trusted_Root`: GREEN — the `expect_green` flip is correct.
- `cosign_trusted_root` → `cosign_trusted_root_v2`: RED, emitting verbatim
  `[FAIL] 1: fleet delivery classification broken: uncovered=['cosign_trusted_root_v2@web-2']
  (add a <name>_web<N> twin or an ONLY_JUSTIFIED '<name>@<host>' entry naming the class +
  introduction PR), stale entries=['cosign_trusted_root@web-2'] (resource or fleet host no longer
  exists), dialers on undeclared hosts=[]`. The M4j anchor `uncovered=['cosign_trusted_root_v2@web-2']`
  is byte-verified against this emit, not transcribed from memory.

### Property List (Phase 0.6b)

1. The battery's verdict on the case/hyphen rename matches post-normalization guard semantics
   (row expects GREEN).
2. The comment block describes what the row pins under normalization, not the retired
   `expect_red` rationale.
3. The battery pins that normalization did not swallow detection: a rename landing on a
   normalized-unique name still produces `uncovered` + `stale` RED.
4. The `mutations_run` anti-vacuity count stays at `FLOOR=57` — no floor weakening.

### Cut List

- **Lower `FLOOR=57` to 56 instead of adding M4j** → buys property 4 only by weakening it; rejected —
  the sibling row buys properties 3 and 4 together for one row.
- **Name the sibling `control-D`** → controls A/B/C are the must-stay-green family; a red arm
  belongs to the M-series. Cut in favor of `M4j` (the §1 sibling/dialer series ends at `M4i`).
- **Rewrite the anchor to match a shorter token** (e.g. bare `cosign_trusted_root_v2`) → the
  verbatim `uncovered=[…]` spelling was measured; a looser token buys nothing and weakens
  attribution (`2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md`).

### Relevant files

- `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` — `expect_red()`
  (anchor-match semantics), `expect_green()` (no `mutations_run` increment), `control-C` row +
  stale comment block (the `Terraform identifiers legally contain uppercase and hyphens` comment
  above it), `FLOOR=57` anti-vacuity floor near the file end, `mutation_scorer_failed_on` in
  `apps/web-platform/infra/lib/mutation-scorer.sh` (anchor must appear on a `[FAIL]` line).
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — `hcl_blocks` name capture
  `resource\s+"terraform_data"\s+"([^"]+)"` (width pin), `def _norm`, `ssh_resources` keyed on
  `_norm(name)`, `_all_tf_names` normalized, `ONLY_JUSTIFIED` (`cosign_trusted_root@web-2` key),
  `_uncovered`/`_stale_class` emit `1: fleet delivery classification broken: uncovered=… stale
  entries=…`. **Do not edit this file.**
- `.github/workflows/infra-validation.yml` — owns the `deploy-script-tests` leg that runs the battery.

### Institutional learnings

- `knowledge-base/project/learnings/2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md`
  — this exact class: the guard was fixed and the battery's expectation could not see the fix.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — this battery's own #7493 vacuity class; RED rows + must-PASS rows both required.
- `knowledge-base/project/learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
  — the `mutations_run`/`cases` conservation discipline the `FLOOR=57` implements.
- `knowledge-base/project/learnings/2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md`
  — the rewritten comment must not reintroduce the anchor text or a paraphrase a `[FAIL]` line
  could fake; anchor text lives only in the `expect_red` argument.
- `knowledge-base/project/learnings/2026-10-10-my-must-pass-arm-passed-wherever-its-mutation-landed-and-nothing-noticed-the-arms-could-be-deleted.md`
  — a green arm must land its mutation and be attributable; `expect_green` already asserts the
  edit landed (`cmp -s` check).
- `knowledge-base/project/learnings/2026-10-06-narrowing-a-guard-leaves-every-sentence-about-its-old-scope.md`
  — the stale comment block is exactly this class: the guard's matching semantics were narrowed
  (verbatim → normalized) and every sentence about the old scope (the `expect_red` justification)
  was left behind. The comment rewrite is the sweep, not an optional nicety.

### Research decisions

- External research: skipped — trivially mechanical change, fully verified empirically in-repo.
- Community discovery / functional overlap: the battery is the artifact itself; #9970 is the
  owning issue. No new capability surface.
- Subagent fan-out: this planning context has no agent-spawn tool; repo research, learnings
  review, spec-flow edge analysis, and domain assessment ran in-process with full file context.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch; the ask arrived as verified context in the invocation. Every
cited fact re-verified against the tree (harness signatures, row location, `_norm` presence, issue
state, diagnostic spellings). One context claim needed sharpening: "the row pins that deleting
`_norm` or narrowing the sweep regex re-breaks it via uncovered+stale" — verified that
`_norm`-deletion yields uncovered+stale, while a sweep-regex narrowing to `[a-z_0-9]+` yields
stale-only (the renamed resource never enters `ssh_resources`, so no `uncovered` entry forms).
The comment text must keep that distinction accurate.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the artifact is a CI
  mutation battery; the worst outcome is a misleading green/red on an internal guard suite.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the diff is a
  test-expectation change with no runtime, credential, or data path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal test-only edit; no user artifact exists on the
  changed surface, so no incident tier applies.
- `threshold: none, reason: the touched path (`apps/web-platform/infra/`) matches the preflight
  sensitive-path regex on directory class only — the edit is a test-expectation flip inside a
  sandboxed mutation battery that never applies infrastructure.`

## Observability

Required: the diff touches `apps/web-platform/infra/` (sensitive-path regex class). The observable
surface is the battery itself; its signal is already maximally loud (CI-leg red + `[FAIL]`/`[FATAL]`
lines on stderr).

```yaml
liveness_signal:
  what: "the battery's summary line '=== provisioner-parity mutation: N passed, 0 failed (K cases) ==='"
  cadence: "per-PR and per-main-merge via the deploy-script-tests leg"
  alert_target: "GitHub Actions check failure (required test aggregator)"
  configured_in: ".github/workflows/infra-validation.yml (deploy-script-tests leg)"

error_reporting:
  destination: "GitHub Actions job log for the deploy-script-tests leg"
  fail_loud: "per-row '[FAIL] <label>: <reason>' lines plus non-zero suite exit; floor trips emit '[FATAL] anti-vacuity floor'"

failure_modes:
  - mode: "row direction drift — guard semantics move under an expect_* verdict"
    detection: "'[FAIL] <label>: guard still PASSED with the invariant broken' or 'guard went RED on a legitimate edit'"
    alert_route: "CI red on the deploy-script-tests leg"
  - mode: "diagnostic spelling drift — the guard renames its emit"
    detection: "'[FAIL] <label>: guard went red but NOT via <anchor>'"
    alert_route: "CI red on the deploy-script-tests leg"
  - mode: "arm deletion — mutation rows silently dropped"
    detection: "'[FATAL] anti-vacuity floor (mutations): only N landed'"
    alert_route: "CI red on the deploy-script-tests leg"

logs:
  where: "GitHub Actions run log (repo Actions tab); suite stdout/stderr captured per run"
  retention: "GitHub default run-log retention"

discoverability_test:
  command: grep -c 'expect_green "control-C' apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh
  expected_output: "1"
```

**Suite-shape false hit, argued down (deepen-plan Phase 4.7):** the detection regex
`[^[:space:]]*[-.]test\.` matches the path `web-host-provisioner-parity-mutation.test.sh`, but the
command is a single `grep -c` that READS the battery file — it does not run the suite. Measured
runtime <1 s (executed at plan time 2026-10-11: prints `0` pre-change, `1` post-change). It is the
smallest command that prints the signal `liveness_signal.what` names; the full battery (~4 min) is
the test, not the discovery probe.

## Guard Contract

The deliverable modifies an anti-vacuity control (the mutation battery is the guard-of-the-guard
for `web-host-provisioner-parity.test.sh`), so the contract applies to the battery arm being
reshaped.

### Guard 1 — fleet-classification coverage of Terraform-identifier renames

**Property.** A `terraform_data` resource rename is classified by normalized identity: a
case/hyphen variant resolves to the same `_norm` identity and stays swept+justified (GREEN), while
a rename landing on a normalized-unique name loses its `ONLY_JUSTIFIED` key and goes RED via
`uncovered` + `stale`.

**Assembly.** Two chokepoints. (a) The guard's name pipeline in
`web-host-provisioner-parity.test.sh`: the `hcl_blocks` capture `([^"]+)` and `_all_tf_names`'s
`resource "terraform_data" "([^"]+)"` sweep (width), `_norm()` at `ssh_resources` key time
(identity), `ONLY_JUSTIFIED` keys, the `_uncovered`/`_stale_class` classifier and its single
`no(f"1: fleet delivery classification broken: …")` emit. (b) The battery harness in
`web-host-provisioner-parity-mutation.test.sh`: the `control-C`/`M4j` rows, `expect_red`'s
`mutation_scorer_failed_on` attribution, `expect_green`'s landed-mutation check, and the
`mutations_run`/`cases` counters under `FLOOR=57`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete `_norm()` normalization (verbatim `name` keys in `ssh_resources`/`_all_tf_names`) | RED — control-C arm fails: `Cosign-Trusted_Root@web-2` uncovered + `cosign_trusted_root@web-2` stale |
| 2 | Narrow the `hcl_blocks` name capture `([^"]+)` to `([a-z_0-9]+)` | RED — renamed resource never swept → `cosign_trusted_root@web-2` stale-only; control-C arm fails (the `_all_tf_names` capture feeds only the twin-base exemption — not this row; control-D pins it) |
| 3 | Over-normalize `_norm` (e.g. strip a `_v\d+$` suffix) so `cosign_trusted_root_v2` collapses onto `cosign_trusted_root` | RED — M4j arm fails `guard still PASSED` — the detection-swallowed hole the sibling exists to catch |
| 4 | Harness: misspell the M4j anchor (e.g. `cosign_trusted_root_v3`) | RED — `guard went red but NOT via '<anchor>'`; attribution cannot be faked |
| 5 | Must-PASS: `Cosign-Trusted_Root` rename under correct `_norm` (the control-C mutation itself) | GREEN — normalization-transparency arm; also fails if the mutator does not land |

**Anchor.** The `uncovered=['cosign_trusted_root_v2@web-2']` anchor is a stored expectation matched
each run against the guard's live `[FAIL]` emit — verified byte-identical against a sandboxed run
of the real guard on 2026-10-11. A weakening that changes the diagnostic spelling, the sort order,
or the `<name>@<host>` shape reds the row; the emit site (`no(f"1: fleet delivery classification
broken: …")`) is the single outside-the-battery authority.

## Implementation Phases

### Phase 1 — Battery edits (`apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` only)

1. Replace the comment block above the `control-C` row (the `Terraform identifiers legally contain
   uppercase and hyphens. … #9860.)` block) with post-normalization prose stating: `_norm()`
   normalizes at the classification boundary so `Cosign-Trusted_Root` and `cosign_trusted_root`
   resolve to one identity; the row pins swept+justified transparency; deleting `_norm` re-breaks
   via `uncovered` + `stale`, and narrowing the `([^"]+)` name capture to `[a-z_0-9]+` re-breaks
   via `stale` alone (the renamed resource never enters `ssh_resources`). Do not quote the retired
   anchor `Cosign-Trusted_Root@web-2` in the new comment — anchors live in `expect_red` arguments
   only.
2. Change the row to `expect_green "control-C (uppercase/hyphen rename is swept by the
   classification)" server.tf '<same mutator body>'` — drop the expected-anchor argument; keep the
   mutator verbatim (assert + single `s.replace`).
3. Insert immediately after it the sibling arm, same mutator keyed on the same header line but
   renaming to `cosign_trusted_root_v2`:

   ```bash
   expect_red "M4j (§1: a normalized-unique rename is uncovered+stale)" server.tf \
     "uncovered=['cosign_trusted_root_v2@web-2']" '
   old = "resource \"terraform_data\" \"cosign_trusted_root\" {"
   assert old in s
   s = s.replace(old, "resource \"terraform_data\" \"cosign_trusted_root_v2\" {", 1)
   '
   ```

   with a short comment: normalization must not swallow detection — a rename landing on a
   normalized-unique name stays swept (the `([^"]+)` capture is case/hyphen-tolerant) but loses
   its `ONLY_JUSTIFIED` key, so the classification must still RED it.
4. Append `; ±0 #9970: control-C moved to expect_green (-1) and M4j added (+1)` to the `FLOOR=57`
   derivation comment so the count's provenance stays honest (count unchanged: 57).

### Phase 2 — Verification

1. `bash -n` syntax check on the battery.
2. `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` — full suite green,
   `[ok] control-C` and `[ok] M4j` present, `0 failed`.
3. `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/web-host-provisioner-parity.test.sh`
   — guard untouched.

## Files to Edit

- `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` — control-C comment
  rewrite, `expect_red` → `expect_green` flip, new `M4j` row, `FLOOR=57` provenance comment.

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 issues) contains no reference to
either `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` or
`apps/web-platform/infra/web-host-provisioner-parity.test.sh`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "flip the control-C row to `expect_green` (harness signature near line 306 is `expect_green <label> <file> <mutator>` — three args, drop the expected-anchor)" | Phase 1 step 2 / AC-2 | mapped |
| 2 | "rewrite the stale comment block above the row (it currently justifies expect_red) to describe post-normalization semantics: the row pins that case/hyphen renames resolve to the same identity and stay swept+justified, and that deleting `_norm` or narrowing the sweep regex re-breaks it via uncovered+stale" | Phase 1 step 1 / AC-5 | mapped |
| 3 | "evaluate (cheap, decide yes/no with rationale) whether to add a sibling `expect_red` row renaming to a normalized-UNIQUE name … to pin that normalization did not swallow detection" | Evaluated YES — Phase 1 step 3 / AC-3, AC-4; rationale in Overview + Cut List | mapped |
| 4 | "Do NOT modify `web-host-provisioner-parity.test.sh` — the guard is already correct" | AC-7 | mapped |
| 5 | "Do NOT address the unrelated `cloud-init-inngest-bootstrap` pin drift also red in that leg (tracked separately)" | Overview scope-out | mapped |
| 6 | "`bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` runs green including control-C" | AC-1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| control-C `expect_green` flip | "flip the control-C row to `expect_green`" | asked |
| comment block rewrite | "rewrite the stale comment block above the row" | asked |
| `M4j` sibling `expect_red` row | "a sibling `expect_red` row renaming to a normalized-UNIQUE name … to pin that normalization did not swallow detection" | asked (evaluation resolved YES) |
| `FLOOR=57` provenance comment touch | — | inferred — justification: the floor comment says "Re-derive from the battery log when adding rows"; a silent +1/−1 swap leaves the derivation misleading |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 1 | Estimated changed lines: ~25
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` exits 0; the
  summary line reports `0 failed`; output contains `[ok] control-C` and `[ok] M4j`.
- [ ] `grep -c 'expect_green "control-C' apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  prints `1` and `grep -c 'expect_red "control-C' apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  prints `0`.
- [ ] `grep -c 'expect_red "M4j' apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  prints `1`.
- [ ] `grep -cF "uncovered=['cosign_trusted_root_v2@web-2']" apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  prints `1` — the M4j anchor byte-identical to the guard's verified emit.
- [ ] `grep -B12 'expect_green "control-C' apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh | grep -c '_norm'`
  prints at least `1`, and the same window contains `uncovered` and `stale` — the rewritten
  comment names the normalization function and both re-break modes.
- [ ] `grep -n '^FLOOR=' apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`
  still reads `FLOOR=57` (net-zero: control-C −1 mutation, M4j +1).
- [ ] `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/web-host-provisioner-parity.test.sh`
  exits 0 — the guard file is untouched by this change.
- [ ] `bash -n apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` exits 0.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Semantic pass over all 8
assessment questions: no marketing content, no architectural decision (the normalization decision
shipped in `21331e94e3`; this aligns a test verdict to it), no vendor/process/procurement, no UI
surface (mechanical override scan: Files-to-Edit is a `.sh` battery, no UI-surface glob match), no
legal document, no sales/finance/support surface. Engineering's question requires *significant*
architectural or infra change beyond normal implementation — a one-row expectation flip does not
qualify.

## Test Scenarios

- Given the pristine `server.tf`, when `resource "terraform_data" "cosign_trusted_root" {` is
  renamed to `Cosign-Trusted_Root`, then the guard stays GREEN — `integration` layer, control-C arm
  (verified empirically 2026-10-11 in a harness-faithful sandbox).
- Given the pristine `server.tf`, when the same header is renamed to `cosign_trusted_root_v2`,
  then the guard emits `[FAIL] 1: fleet delivery classification broken:
  uncovered=['cosign_trusted_root_v2@web-2'] … stale entries=['cosign_trusted_root@web-2']` —
  `integration` layer, M4j arm (verified verbatim 2026-10-11).
- Given `_norm()` deleted or the name capture narrowed to `[a-z_0-9]+`, when the control-C
  mutation runs, then the `expect_green` arm fails — derived from design; matches the
  pre-normalization failure shape recorded in #9970's body.
- Given the suite runs end-to-end, when all rows resolve, then `mutations_run` still satisfies
  `FLOOR=57` and `pass + fail == cases` — `integration` layer, conservation identity.

## Deepen-Plan Enhancements

**Deepened on:** 2026-10-11 | **Halt gates:** all pass | **Mode:** in-process (no agent-spawn tool
in this pipeline subagent context; every gate and check ran against the real files)

### Gate results

- Phase 4.4 precedent-diff: precedent exists in-file — `expect_red` rows `M4a`–`M4i` and
  `expect_green` controls `control-A`/`control-B` are the canonical shapes; the prescribed edit
  reuses them verbatim (assert + single `s.replace`, same signature order).
- Phase 4.5 network-outage: no trigger tokens in Overview; plan drives no `terraform apply` —
  skipped.
- Phase 4.55 downtime: no downtime-inducing operation — skipped.
- Phase 4.6 user-brand: PASS (`none` + non-empty scope-out on a sensitive-path diff).
- Phase 4.7 observability: PASS with one argued-down false hit (see note under the block).
- Phase 4.8 PAT shapes: clean. Phase 4.9 UI: no UI surface. Phase 4.10 encryption: nothing
  introduced. Phase 4.11 guard contract: `lint-guard-contract.py` green (1 entry); adequacy read —
  assembly names the two chokepoints (guard name pipeline, battery harness/counters), matrix is
  design-derived. Phase 4.12 scope check: 1 unfenced section, all rows mapped, `Recommendation:`
  present, no `status: BLOCKED`.
- Phase 4.45 verify-the-negative (in-process): `expect_green` body confirmed to not touch
  `mutations_run` (0 hits inside the function); the stale-only-under-sweep-narrowing claim
  confirmed against the classifier (`_uncovered` is built only from `_dialed_hosts`, which derives
  from `ssh_resources` — an unswept name can be stale but never uncovered).

### Quality checks

- `21331e94e3` verified: `git rev-parse` resolves and `git merge-base --is-ancestor 21331e94e3
  origin/main` holds — the normalization squash is on main as claimed.
- `#9970` OPEN (live issue); `#9860` exists (the canary issue whose session authored the original
  incompatible `expect_green` shape — kept as provenance in the rewritten comment).
- Literal consistency: `uncovered=['cosign_trusted_root_v2@web-2']` is spelled identically across
  Research Insights, Guard Contract, Implementation, and AC-4; it was measured from the guard's
  live emit, not transcribed.
- No new ADR, no new labels, no new `SOLEUR_*` markers, no workflow paths edits, no rule-id
  citations requiring registry checks (`hr-monitor-not-run-in-background-for-polling` in tasks.md
  is an active index id).

## Context

- Issue: #9970 (`Closes #9970` in the PR body, not the title).
- The guard-side normalization shipped in squash `21331e94e3` (PR #9947, which contained
  "WIP: feat-one-shot-9855-dormant-integration-ci").
- CI evidence: run `38105510433`, `deploy-script-tests (4/4)` leg.
- `web-probe-envwrite.sh` and the other four `INPUTS` are untouched; the mutation applies to
  `server.tf` inside the scratch `TF_REPO` only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6 — section is filled above.
- `expect_green` does not increment `mutations_run`: flipping any `expect_red` to `expect_green`
  silently drops the landed-mutation count; pair the flip with a red arm or a deliberate floor
  re-derivation or the `FLOOR` anti-vacuity trip fires at suite end.
- Anchor text belongs in `expect_red` arguments, not in comments: the scorer matches the anchor
  against `[FAIL]` lines and the comment's own prose about the anchor class has previously served
  as a false fixture (`2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md`).
- The comment must distinguish the two re-break modes accurately: `_norm`-deletion produces
  `uncovered` + `stale`; sweep-narrowing produces `stale` only (the resource never enters
  `ssh_resources`, so nothing can be `uncovered`).
