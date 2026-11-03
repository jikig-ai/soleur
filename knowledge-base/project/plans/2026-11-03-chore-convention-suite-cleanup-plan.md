---
title: "chore: family-wide cleanup — convention-suite asymmetries + seam coverage gaps (post-#11720)"
type: chore
date: 2026-11-03
slug: chore-convention-suite-cleanup
branch: feat-one-shot-11899-convention-suite-cleanup
issue: 11899
closes: 11899
domain: engineering
priority: p3-low
brand_survival_threshold: none
---

# chore: family-wide cleanup — convention-suite asymmetries + seam coverage gaps (post-#11720)

## Enhancement Summary

**Deepened on:** 2026-11-03
**Sections enhanced:** Observability (added — donor-mirrored), Guard Contract (lint-verified, 6 entries), Technical Considerations, Plan Review record
**Agents used:** none — `Reviewed-Coverage: sequential-fallback` (depth-1 subagent, no spawn tool); every prescribed fan-out (learnings filter, per-section research, review panel, verify-the-negative, post-edit self-audit) ran inline sequentially.

### Key Improvements
1. `## Observability` block added (deepen-plan 4.7 requires it for non-docs plans — the donor batch-3 plan carries the same shape; the suites ARE the observability).
2. `IV_JOB` non-empty/run-line-inside assertion and job-boundary regex widened to `[a-zA-Z0-9_-]` (correctness catches from the inline panel pass).
3. Halt-gate sweep run mechanically: 4.6 pass, 4.7 pass (after Observability add), 4.8 zero PAT hits, 4.9/4.10/4.13 skip, 4.11 `lint-guard-contract.py` green (6 entries), 4.12 exactly-one Scope Check all rows mapped or justified-inferred.

### New Considerations Discovered
- All `$GITHUB_ENV` writes in infra-validation.yml live in the `plan:` job (:1662/:1674) — confirms the job-scoped ban is the correct scoping and `validate:` is clean today.
- The issue's "vestigial EXPECT_1" describes live whole-string compares — reconciled as rename-not-delete (Research Reconciliation; taste row in decision-challenges.md).

## Overview

#11899 is the deferred family-wide remainder from the #11720 batch-3 review (PR #11885): eight findings shared with already-merged batch-1/batch-2 convention files or pre-existing on main, deferred so batch-3 did not diverge the port set. This plan sweeps them across the whole alert-guard convention family — the fourteen `apps/web-platform/test/infra/*alert*.test.sh` suites plus `apps/web-platform/infra/betterstack-alert-structure.test.sh` that carry the `PRESENCE_ROWS`/`MUT_ROWS` floor-window + `MUT_SKIP`-battery idiom — plus the `PROMOTED_FILES` meta-guard at `scripts/guard-vacuity-floor.test.sh`, plus one finding the resume brief carries that the issue body does not number (the `MAIN_PLAN` awk slice overshoot, with its verified `rc=` terminator remedy).

## Operator Holds

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: none — no Production Envelope authored this session (all holds below stand regardless)

- Hold: Carrier batch (#8525 + #8013 + RestartSec=300 half of #8080 + advisory #10290) waits for the next vinngest-v* bake / host-replace window
- Hold: Operator-reserved: #8839 dead-letter backstop for agent spawns stuck on Working — Product/UX call
- Hold: Operator-reserved: #9943 machine-enforce the git-data liveness-heartbeat flip precondition — owner credential/action
- Hold: Operator-reserved: Close #11720 only if the operator accepts the registry-clientip-not-rfc1918 descope as final

## Problem Statement / Motivation

The convention suites guard the ops-fleet drift-alert chain (Better Stack `logtail_exploration*` resources, apply-time `-target=` pins, runbook + emitter provenance). The batch reviews hardened them to a shared convention, but the port left family-wide gaps that all degrade the same property — **a muted or drifted alert-guard battery reads green in CI**:

- **Seam greps cover literal text only.** Every suite greps `infra-validation.yml`'s comment-stripped text for the literal `MUT_SKIP` and `<PREFIX>_GUARD_` strings; a runtime-composed env name (`echo "MUT_""SKIP=1" >> "$GITHUB_ENV"`, a `*_GUARD_*` name assembled from quoted fragments, or a `BASH_ENV`/`SHELLOPTS`/`BASHOPTS` shell-injection env) reaches the battery with no literal ever present. `betterstack-alert-structure.test.sh` already bans `*_GUARD_*` envs, shell-injection envs, and `$GITHUB_ENV`/`$GITHUB_PATH` writes **inside the job** structurally — the per-suite seam checks never adopted that coverage.
- **Eight seam-bearing suites pin only the byte-exact run line.** `bwrap-probe-rollback`, `egress-gw`, `faithful-canary-sandbox`, `inngest-step-524`, `registry-store-not-luks`, `registry-zot-credential-shape`, `sandbox-alerts`, and `workspaces-luks-deadman-fired` do not pin the step shape — an `if:` or `continue-on-error:` added to the step, or a `continue-on-error:` on the job, makes the suite non-blocking while every existing row stays green. (`ghcr`, `web-nic`, `inngest-cutover`, `registry-clientip`, `betterstack-alert-structure` already carry the step-shape pins.)
- **`MAIN_PLAN` awk slice overshoots in six suites.** The extraction `awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=\$\?/{exit}'` terminates on a literal `rc=$?` line-start; `apply-web-platform-infra.yml`'s actual capture line is `rc=${PIPESTATUS[0]}` (:685), so every `MAIN_PLAN` currently runs to EOF. The `-target=` pins still pass because the needles remain in the oversized slice — the overshoot is silent and would mask `-target=` text moved or duplicated below the plan step. Verified remedy (carried in the resume brief): terminate on `^[ \t]*rc=` — the only `rc=` line-start between the `terraform plan` line (:466) and `rc=${PIPESTATUS[0]}` (:685) is :685 itself — and assert the terminator actually matched so a deleted rc line fails loud rather than re-opening the overshoot.
- **The verdict-class boundary is missing in most suites.** Only `egress-gw` (:366) and `inngest-step-524` (:355) short-circuit presence-section failures with `fail>0 → summary + exit 1` before the battery; the rest record via `no()` and continue into mutation rows, where a real presence failure can surface as an exit-2 instrument FATAL (verdict mislabeled) or burn the whole battery on an already-failed tree.
- **inngest-step-524 pre-existing defects:** `probe_ts` is read (:127) and never asserted; `name`/`alert_type`/`email`/`escalation` attrs and all four period fields are pinned for `claude_cost_daily_burn` only (and through a vestigial single-element `for _n in ("claude_cost_daily_burn",):` loop at :287); `inngest_step_524`'s periods are unpinned; `.ts` emitter checks are `re.search` presence-only so `//`-comment decoys satisfy them; header comments (:24 "the two daily alerts", :37 "TWO units") describe a pre-discovery shape the code no longer has (it floors at ≥2 discovered, post-#11653).
- **Donor-carried asymmetries:** dead `Q = chr(39)` in seven PRELUDEs; `SELF="${BASH_SOURCE[0]}"` relative form in five files vs the canonical `$DIR/$(basename …)`; census-accumulator vocabulary drift; `EXPECT_1` whole-string compares in ghcr/web-nic kept under vestigial numbered naming.
- **Per-file smalls:** ghcr `JQ_DIR` mktemp (:376) has no EXIT trap while `MUT_DIR` (:432) does; sandbox `s.count(old) >= 1` (:602) weakens the sibling `== 1` anchor convention; sandbox's `EMITTER` awk takes the first `export function mirrorBashSandboxFailure(` and relies on tsc to reject duplicates; web-nic's readability gate loops `TF/WF/EM` only (:92) while RB/LQ/IV degrade to `no` not FATAL.
- **Meta-guard:** `PROMOTED_FILES` has four assignment sites in `scripts/guard-vacuity-floor.test.sh` (:798/:811/:819 stale snapshots, :1104 live — last assignment wins). Each promotion round appended a fresh assignment instead of editing the existing one; the stale sites are the kind of trap the next promotion falls into.
- **Floor self-reference (bounded):** decrementing `PRESENCE_ROWS`/`MUT_ROWS` alongside a row deletion keeps suites green+FIRES — documented as the accepted residual in the batch-3 plan's Anchor row; CTO ruling bounds this to document-and-keep unless a cheap invariant exists (assessment below: none cheap enough — see Proposed Solution item 8).

## Research Insights

**Reviewed-Coverage: sequential-fallback.** This run is a depth-1 subagent on a harness with no spawn tool; every fan-out the skill prescribes (repo-research-analyst, learnings-researcher, domain leaders, spec-flow-analyzer, advisor, plan-review panel) ran as the same role executed inline and sequentially by this process. No independent review ran.

### Premise Validation

- #11899 is OPEN (meta/machinery, priority/p3-low, Post-MVP milestone). Verified 2026-11-03.
- Cited refs hold: #11720 CLOSED (operator-confirmed), #11695/#11849/#11885 all MERGED. The deferred-findings premise is accurate — the findings exist verbatim on `origin/main` today (each verified by grep during planning).
- Cited code anchors verified: `PROMOTED_FILES` four sites at scripts/guard-vacuity-floor.test.sh:798/:811/:819/:1104; `MAIN_PLAN` extraction byte-identical in six suites; `apply-web-platform-infra.yml` `rc=${PIPESTATUS[0]}` at :685 with no earlier `rc=` line-start after :466; all suite run lines live under the `validate:` job of infra-validation.yml (:905-:1001).
- Mechanism vs ADR corpus: grepped `knowledge-base/engineering/architecture/decisions/` for `MUT_SKIP|seam check|convention suite|PROMOTED_FILES|floor.window` — no ADR prescribes or rejects the seam-check or floor-window mechanism; ADR-252 (suite registration = file presence, deploy-script-tests matrix) is adjacent and consistent with the step-pin approach. No mechanism lands in a rejected-alternatives table.
- Collision precheck (`collision-precheck.sh 11899`, exit 10): the only PR hit is this pipeline's own draft #11957; foreign `test-all.sh` processes belong to sibling worktrees feat-one-shot-11939 / feat-one-shot-9603 and do not name #11899. No competing PR.

### Property List (Phase 0.6b)

1. No env channel can mute or redirect a convention suite's CI battery — literal, composed, or injected — for any suite registered in `infra-validation.yml`.
2. A convention suite's CI step can never silently become non-blocking.
3. `MAIN_PLAN` contains exactly the `terraform plan` step's output span — no more (overshoot) and the terminator must have matched (no silent run-to-EOF).
4. A presence-verdict failure exits 1 with the FAILED ledger before any mutation row runs — never exit-2 instrument mislabel, never battery-on-failed-tree.
5. Every discovered alert's paging-relevant attributes are pinned — not just the first-discovered or the convenient one.
6. Dead code, stale comments, and divergent forms do not survive inside the convention family — one vocabulary, one `SELF` form, one readability gate shape.
7. `PROMOTED_FILES` has exactly one live write site — promotion cannot edit a stale snapshot.
8. Floor self-reference stays an explicitly documented accepted residual (bounded per CTO ruling), unless an invariant cheaper than a per-suite external constant table exists.

### Cut List (Phase 0.6b)

- "Stale-site marker" for PROMOTED_FILES (issue item 7's first option) — CUT: superseded by consolidation + single-site count pin, which buys the same property (editors can't hit a stale site when none exists) at lower steady-state cost and additionally makes a future accidental second site mechanically red.
- Per-suite external constant table in the meta-guard (the candidate "cheap invariant" for item 8) — CUT: it is a second write site per suite per row-touching edit (~15 × ongoing edit tax), which fails the CTO's "cheap" bound; document-and-keep covers the residual.
- A whole-file `GITHUB_ENV`/`GITHUB_PATH` ban — CUT: fails on `apply-web-platform-infra.yml`-style legit writes already present in infra-validation.yml (:1662/:1674, terraform-plan job); narrowed to the enclosing job slice instead.

### Convention-family census (measured this session, worktree == merge state of #11885)

| Suite | IV seam | run-line pin | step pins (`if:`/`c-o-e`) | pre-battery `fail>0` | `MAIN_PLAN` awk | dead `Q` | `SELF` abs | item-specific |
|---|---|---|---|---|---|---|---|---|
| bwrap-probe-rollback-alert | yes | yes | MISSING | MISSING | overshoot :125 | dead | abs | |
| egress-gw-alert | yes | yes | MISSING | has :366 | — | dead | abs | donor |
| faithful-canary-sandbox-alert | yes | yes | MISSING | MISSING | overshoot :122 | dead | abs | |
| ghcr-blocked-alert | yes | yes | has :352 | MISSING | overshoot :137 | dead | relative :430 | JQ_DIR trap :376; EXPECT_1 :218 |
| inngest-cutover-flip-silent-alert | yes | yes | has :247 | MISSING | overshoot :92 | none | relative :258 | |
| inngest-step-524-alert | yes | yes | MISSING | has :355 | — | none | abs | probe_ts :127; attr pins; comments :24/:37; loop :287; re.search |
| inngest-luks-key-probe-alert | none (sibling-covered) | no | n/a | MISSING | — | used | relative :408 | |
| inngest-luks-wrong-volume-alert | none (sibling-covered :50) | no | n/a | MISSING | — | used | relative :488 | |
| registry-clientip-not-rfc1918-alert | yes | yes | has (strong :447) | MISSING | — | used | abs | |
| registry-store-not-luks-alert | yes | yes | MISSING | MISSING | — | used | abs | |
| registry-zot-credential-shape-alert | yes | yes | MISSING | MISSING | — | dead | abs | |
| sandbox-alerts | yes | yes | MISSING | MISSING | overshoot :126 | TBD at work | abs | s.count :602; EMITTER awk :128 |
| web-nic-guard-unpinned-url-alert | yes | yes | has :291 | MISSING | overshoot :125 | dead | relative :316 | readability :92; EXPECT_1 :166 |
| workspaces-luks-deadman-fired-alert | yes | yes | MISSING | MISSING | — | dead | abs | |
| betterstack-alert-structure | structural (superset) | yes | has | has :430 | — | none | — | precedent only — no edits |

### Relevant institutional learnings

- `2026-10-31-a-guard-floor-constant-is-two-write-sites-not-one.md` — `PRESENCE_ROWS`/`MUT_ROWS` are two-write-site constants; grep every occurrence after each bump.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — mutation matrices must include harness rows and non-canonical must-PASS rows (drives Guard Contract row design below).
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — guards need dispatch-vacuity rows (the MAIN_PLAN terminator-match assertion exists for exactly this reason).
- `2026-10-29-call-form-anchored-needles-and-the-empty-disjunct-fail-loud.md` — fragment args must byte-match `no "…"` messages; grep -F the fragment before shipping.
- `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md` — `PROMOTED_FILES` promotion only after `git add` (derivation reads the index).
- Landmines carried from the batch runs (encoded in Technical Considerations + Test Scenarios): phantom-heredoc evasions (`<<[-]`/`<<\x2d`/`<<-${Z:-}`, never literal `<<-` in scanned fixture text; `\x24\x24` not bare `$$` in unquoted `<<PY`), no `| grep -q` pipelines, no `env -u`, six-line pure-assignment floor-window (no `$(`, no `[ -n ] &&` rebind) + column-0 `fi` + `MUT_ROWS` grep-counted + `MUT_ROWS_RUN` ledger where carried, shellcheck `-S warning` on every touched file.

### External research decision (Phase 1.6)

Skipped — internal repo convention convergence; all patterns, donors, and precedents are local (`egress-gw`/`ghcr`/`registry-clientip` donors, `betterstack-alert-structure` structural coverage). Community/functional overlap checks: no uncovered stacks (bash + TS, both covered); the convention is repo-specific machinery with no community equivalent. No brainstorm exists for this feature (one-shot pipeline entry).

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Reality on this branch | Plan response |
|---|---|---|
| "MAIN_PLAN slice overshoot in all five sibling awk extractions" (brief) | SIX suites carry the byte-identical extraction: bwrap :125, fcsb :122, ghcr :137, inngest-cutover :92, sandbox :126, web-nic :125 | Fix all six |
| "`if:`/`continue-on-error:` step pins only in ghcr/web-nic — the other four convention suites" | Pins also exist in inngest-cutover, registry-clientip, betterstack-alert-structure; EIGHT seam-bearing suites lack them | Add pins to the eight, port the ghcr/web-nic block shape |
| "pre-battery `fail>0` gate absent in 5/6 batch-3 files" | Confirmed for the batch-3 five (bwrap, fcsb, ghcr, sandbox, web-nic); also absent in registry-store, registry-zot, workspaces-luks, registry-clientip, inngest-cutover, inngest-luks-key-probe, inngest-luks-wrong-volume | Issue is "family-wide" — add the gate to every suite carrying the `no()`/FAILED + battery idiom (12 files) |
| "`SELF` relative form in ghcr/web-nic" | Relative form in FIVE files: ghcr :430, inngest-cutover :258, key-probe :408, wrong-volume :488, web-nic :316 | Converge all five to `$DIR/$(basename …)` |
| "vestigial EXPECT_1 in ghcr/web-nic" | Both compares are LIVE (`if [ "$SQL_1" = "$EXPECT_1" ]`, ghcr :223, web-nic :168); "vestigial" describes the numbered naming, not the check | Keep the compare; rename `EXPECT_1` → `EXPECT_SQL` (taste — see decision-challenges) |
| "all convention suites (incl. inngest-luks-*) grep infra-validation.yml" | The inngest-luks pair carries no IV seam — wrong-volume documents relying on sibling seam checks (:50-51) | No seam block added to the pair; the widened fragment set covers `*_GUARD_*` prefixes uniformly, which extends sibling coverage to `KEYPROBE_GUARD_*`/`LUKS_GUARD_*` automatically |
| "tasks.md `<3`" (inngest-524 stale text) | The reference lives in the archived batch-3 spec dir — point-in-time artifact | Not edited; the suite's own comments get the rewrite |

## Proposed Solution

Per-suite edits below; file-level matrix in Files to Edit. Donor-of-record for the convention remains `egress-gw-alert.test.sh`; the step-pin block shape comes from `ghcr` :345-355 / `web-nic` :285-295; the job-scope ban design follows `betterstack-alert-structure.test.sh` :269-353.

### Item 1 — Seam-check strengthening (CTO-ruling decision, resolved concretely)

Every IV-seam suite extends its `seam_bad` accumulation in two ways:

1. **Fragment set over `IV_CODE` (whole-file, comment-stripped).** Replace/augment the literal `MUT_SKIP` + `<PREFIX>_GUARD_` greps with the fragment set `{MUT_, _SKIP, GUARD, BASH_ENV, SHELLOPTS, BASHOPTS}` — each asserted absent. Rationale per fragment: `MUT_` + `_SKIP` catch `MUT_SKIP` and split-at-either-boundary compositions (`"MUT_""SKIP"`, `"MUT""_SKIP"`); `GUARD` (bare, no underscore) catches any `*_GUARD_*` env name or fragment regardless of prefix — uniformly covering `EGW_GUARD_*`, `SPEND_GUARD_*`, `UNPINNED_GUARD_*`, `KEYPROBE_GUARD_*`, `LUKS_GUARD_*` and any future prefix in one check; `BASH_ENV`/`SHELLOPTS`/`BASHOPTS` bar the shell-injection env names a composer could use to smuggle a computed name without any literal fragment. Verified safe today: none of the six fragments appears in `IV_CODE` (`MUTATION` at infra-validation.yml:910 and `SKIPPED` at :1391 do not match `MUT_`/`_SKIP`; `GUARD` and `BASH_ENV` appear only in whole-comment lines the strip drops). Implementer re-verifies fragment absence on `origin/main` at Phase-7 sync — a legit landing addition of any fragment forces a narrower fragment for that suite rather than a whole-file false positive.
2. **Enclosing-job `GITHUB_(ENV|PATH)` + `defaults:` ban.** Slice `IV_CODE` to the job block containing the suite's pinned run line (awk: index the run line, walk back to the nearest `^  [a-zA-Z_][a-zA-Z0-9_-]*:` job header — job IDs allow hyphens and digits — forward to the next `^  [a-zA-Z_][a-zA-Z0-9_-]*:` or EOF), **assert the slice is non-empty and contains the pinned run line before applying the ban** (an empty/missliced `IV_JOB` would pass the absence check vacuously — the spec-flow catch), then assert `GITHUB_ENV`, `GITHUB_PATH`, and `defaults:` absent within the slice. This closes the only runtime-composition channel — YAML `env:` names are static (caught by fragments) and a `$GITHUB_ENV` write from an earlier step in the same job is the sole way a computed name reaches the suite's step. Today the `validate:` job contains zero such writes (the :1662/:1674 writes live in the terraform-plan job — a must-PASS control row proves the scoping isn't over-broad). Residual documented: char-level obfuscation (hex/`tr`/`rev`/`base64`) in a different job could still compose a name — bounded because cross-job env writes don't exist, `env:` is static, and `BASH_ENV`-class smugglers are barred file-wide.

New `mutate_red` rows per seam suite (each with a `no "…"` fragment byte-matched, `grep -F`-verified): a composed `"MUT_""SKIP=1"` write; a `GUARD` fragment insertion; a `BASH_ENV` line; a `$GITHUB_ENV` write inside the job slice; plus a **must-PASS** row adding a `$GITHUB_ENV` write to a different job (the over-breadth control). No `env -u` anywhere (landmine; also self-reds registry-clientip's pin).

### Item 2 — inngest-step-524 defect completion

- Assert `probe_ts` carries the burn emitter's contract literals (`SOLEUR_CLAUDE_COST`, `claude-cost`, `cost_usd`, `cron:` component source) — the read-needle-from-emitter pattern `sandbox` already uses (`EM_FEATURE`/`EM_OP`); a dead read becomes a provenance pin.
- Extend the attr pins to BOTH discovered alerts: iterate `for _n in ("inngest_step_524", "claude_cost_daily_burn"):` pinning `query_period`/`check_period`/`recovery_period`/`confirmation_period` per alert with values canon-derived from `betterstack-logs-alerts.tf`, and add `alert_attr` pins for `name`, `alert_type`, `email`/`callout_list` shape, and `escalation` for both — same exactly-once `alert_attr` helper (a duplicated attr line already yields `None`).
- Strip `//` full-line comments (and `/* … */` blocks) from each `.ts` emitter read before the `re.search` checks — `re.sub(r"(?m)^[ \t]*//.*$", "", src)` + `re.sub(r"/\*.*?\*/", "", src, re.S)` — so a `//`-comment decoy can no longer satisfy a presence check.
- Fold the vestigial single-element `for` loop into the two-alert iteration above.
- Rewrite stale header comments (:24, :37) to the discovered-shape wording: "≥2 explorations discovered from the #8611 section, including `inngest_step_524` and `claude_cost_daily_burn`; the unit/source census is discovery-driven, not a fixed two."

### Item 3 — convention-internal asymmetries

- **Pre-battery `fail>0` gate** into all 12 suites lacking it (census above): the donor block verbatim — `echo "=== <suite>: $pass passed, $fail failed ==="` + `if [ "$fail" -gt 0 ]; then printf 'FAILED: %s\n' "${FAILED[@]}" >&2; exit 1; fi` — placed immediately before the battery section marker, inserted OUTSIDE the six-line floor window (purity preserved).
- **Dead `Q = chr(39)`** deleted from the seven PRELUDEs where `Q` has no other reference (bwrap, egress-gw, fcsb, ghcr, registry-zot, web-nic, workspaces-luks; per-file re-verified with `grep -cw Q` == 1 before deleting).
- **`SELF` convergence** to `SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"` in the five relative-form files.
- **Census vocabulary** — normalize census-accumulator naming (e.g. sandbox's `_census_missing`) to the donor term in files already being touched; no standalone cosmetic churn.
- **`EXPECT_1` → `EXPECT_SQL`** rename in ghcr/web-nic (compare retained — see Research Reconciliation; taste-class decision recorded in decision-challenges.md).

### Item 4 — `if:`/`continue-on-error:` step pins for the eight

Port the ghcr :345-355 block into the eight listed suites: `IV_STEP` = step-block slice containing the run line (`      - name:` boundaries), `IV_HDR` = enclosing job header; assert no `if:`/`continue-on-error:` at step indent inside IV_STEP, job `if:` equals the one known literal exactly once (`    if: needs.detect-changes.outputs.pr_duplicate != 'true'`), no `continue-on-error:` in IV_HDR. One `mutate_red` row each for step-`if:`, step-`continue-on-error:`, and job-`continue-on-error:` — byte-matched fragments to each suite's `no "…"` text.

### Item 5 — web-nic readability gate

Extend web-nic :92's `for f in "$TF" "$WF" "$EM"` to all six path vars (`TF WF EM RB LQ IV`) — every other suite's readability loop already covers its full var set; web-nic's is the only narrow one.

### Item 6 — per-file smalls

- **ghcr `JQ_DIR`:** unify the scratch-dir cleanup into the single EXIT trap (`trap 'rm -rf "$JQ_DIR" "$MUT_DIR"' EXIT` — one trap covering both, installed where `JQ_DIR` is created; the later `MUT_DIR` trap install folds into it rather than clobbering).
- **sandbox `s.count(old) >= 1` (:602):** tighten to `== 1`, matching the five sibling `== 1` anchors.
- **sandbox `EMITTER`:** add an exactly-once pin before extraction — `grep -c '^export function mirrorBashSandboxFailure(' "$DISP"` == 1 — instead of relying on tsc to reject a duplicate (the suite runs without tsc).
- **inngest-524 `re.search` presence checks:** covered under item 2's comment-strip.
- **`claude-cost-marker.test.ts`:** no change — the issue notes it already covers behaviorally.

### Item 7 — PROMOTED_FILES consolidation + single-site pin

In `scripts/guard-vacuity-floor.test.sh`: delete the three stale `^PROMOTED_FILES='` assignments at :798/:811/:819, hoisting each site's grounds comment paragraph into the live block above :1104 (history preserved, dead writes removed); add a marker line at the live site ("the single canonical assignment — every promotion edits THIS line; the count pin below reds a second `^PROMOTED_FILES=` site") — kept inside a `# ` comment so it cannot self-match; add a self-pin `[ "$(grep -cE "^PROMOTED_FILES='" "${BASH_SOURCE[0]}")" -eq 1 ]` (line-start anchored, so mid-line references including the pin's own pattern text never count) so re-introducing a second assignment is mechanically red rather than last-wins.

### Item 8 — floor self-reference (bounded, CTO ruling)

**Document-and-keep.** No cheap invariant exists: the only anchor that breaks self-reference is a value stored outside the file, i.e. a per-suite constant table in the meta-guard — a second write site per suite per row-touching edit (~15× ongoing tax), which fails the "cheap" bound (recorded on the Cut List). What ships: (a) a two-line comment at each suite's floor window stating the self-reference and the two-write-site caveat explicitly (extending the batch-3 Anchor language family-wide), and (b) the residual documented here — the `PROMOTED_FILES` membership pin still covers floor *deletion*, and row-count drift-with-decrement is covered by review + the must-PASS row shapes. Row stays open in decision-challenges.md as `pending - assumed: document-and-keep` for the parent technical-ruling gate.

### Item 9 — `MAIN_PLAN` slice bound (brief-carried, verified remedy)

In the six carriers: broaden the terminator `f&&/^[[:space:]]*rc=\$\?/{exit}` → `f&&/^[[:space:]]*rc=/{exit}` and add a terminator-match assertion immediately after extraction (`tail -1` of `MAIN_PLAN` matches `rc=` — a deleted or moved rc line fails loud instead of silently re-opening the run-to-EOF slice). Mutation rows: `-target=` lines moved below the `rc=` line in a mutant WF → RED (the overshoot shape this fixes); `rc=` line deleted → RED (dispatch vacuity).

## Implementation Phases

### Phase 1 — Meta-guard + shared remedies groundwork

- `scripts/guard-vacuity-floor.test.sh`: PROMOTED_FILES consolidation + single-site pin (item 7). Do this FIRST so every subsequent commit rides on the consolidated site.
- Verify all fourteen suites still report `FIRES` after each leg (batch convention); no `MIN_FIRING_SUITES` change (no new floors added or removed — constants bump inside existing suites only).

### Phase 2 — Seam + step + gate sweep (items 1, 3-fail>0, 4)

Group A (seam-bearing, need all three): bwrap, fcsb, inngest-524, registry-store, registry-zot, sandbox, workspaces-luks.
Group B (seam-bearing, need seam+gate only): ghcr, web-nic, inngest-cutover, registry-clientip, egress-gw.
Group C (no IV seam, gate + SELF only): inngest-luks-key-probe, inngest-luks-wrong-volume.
Each file: fragment-set seam block + job-slice ban + mutation rows; step-pin block + rows (A only); pre-battery gate; `PRESENCE_ROWS`/`MUT_ROWS`/`MUT_ROWS_RUN` constant bumps at column-0 adjacent sites with `mutate_floor_red` sed-anchor sweep.

### Phase 3 — `MAIN_PLAN` bound + per-file smalls (items 2, 5, 6, 9)

The six `MAIN_PLAN` carriers; inngest-524 completion; web-nic readability; ghcr JQ_DIR; sandbox `s.count`/EMITTER.

### Phase 4 — Cosmetic convergence + documentation (items 3-Q/SELF/census/EXPECT_1, 8)

Dead-`Q` deletions; `SELF` convergence in the five; `EXPECT_1` rename; census vocabulary; floor-window self-reference comments.

Ordering rationale: structural guards (items 1/4/7) land before cosmetics so every CI cycle validates the strongest state; floor-window comments last so they describe the final constants.

## Technical Considerations

- **Floor-window purity (landmine):** every inserted block sits OUTSIDE the six-line pure-assignment window — `PRESENCE_ROWS`/`MUT_ROWS`/`_eff`/`_floor`/`_ran` remain pure assignments (no `$(`, no `[ -n ] &&` rebind), constants at column 0 adjacent to the window, standalone column-0 `fi`. Constant bumps are two-write-site (declaration + `mutate_floor_red` sed anchor `^PRESENCE_ROWS=[0-9]+$`) — grep every occurrence after each bump.
- **Phantom heredocs (landmine):** any literal `<<-` in scanned fixture text opens a span that hides the floor — use the `<<[-]`/`<<\x2d`/`<<-${Z:-}` evasions the donors use; zero bare `$$` inside unquoted `<<PY` heredocs (`\x24\x24`).
- **`grep -q` pipes (landmine):** count-compare (`$(grep -c …)` vs expected) or `<<<`/`< <(producer)` input redirection — never `| grep -q`.
- **`env -u` banned (landmine):** seam coverage is inside each suite (byte-exact run-line pin + `IV_CODE` absence checks), never an `env -u` run line.
- **Fragment byte-match (landmine):** `mutate_red`/`mutate_floor_red` fragment args byte-match the `no "…"` message; `grep -F` the fragment against the file before shipping.
- **Shared SUT baseline:** all fourteen pin `betterstack-logs-alerts.tf` + `apply-web-platform-infra.yml` + `infra-validation.yml` — an in-flight `.tf`/workflow PR can invalidate canon strings mid-work; re-probe the pinned literals at every Phase-7 sync.
- **Serial CI runtime:** batch-3 measured ~64s for the six; the fourteen-plus-meta-guard sweep adds seam/step/gate rows — estimate +60-90s total; `deploy-script-tests-fixed` runs under `timeout-minutes: 15` — measure the leg on-branch, bump only if approaching ~12 min.
- **`assert_fixture_dir` parity:** the P1b blocks stay byte-identical across siblings (the P1a suite pins that) — do not touch them.
- **Shellcheck:** `shellcheck -S warning` clean on every touched file pre-panel (SC2183 format-arg, SC2034 dead vars — deleting dead `Q`/EXPECT_1-adjacent vars must not leave dangling refs).
- **Observability (Phase 2.9 / deepen 4.7):** the suites ARE the observability — the donor batch-3 plan carries the block (`apps/*/test/` is non-docs under the 4.7 trigger); mirrored below.
- **Encryption posture / Task design / ADR gate / GDPR gate / IaC gate / network-outage checklist:** all skip — no persistent store or connection, no new autonomous-task surface, no architectural decision (mechanism consistent with ADR-252), no regulated-data surface, no infrastructure provisioning, no SSH/network keywords.

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user-facing artifact — the worst case is a convention suite reporting green while its alert-guard battery is muted or drifted, which delays detection of ops-fleet alert drift (Better Stack pages are an operator surface, not a customer surface).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — test machinery only; the suites assert CI wiring and `.tf` alert shapes, not user data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is a false-green CI signal on internal ops alerting — indirect, operator-facing, and self-announcing at the next alert drift; it cannot reach a user record, payment, or page.

*Scope-out override:* `threshold: none, reason: the diff touches test-suite and meta-guard files under apps/web-platform/test/infra/ and scripts/ only — CI-machinery, no user-facing or data path is modified`

## Observability

```yaml
liveness_signal:    # the fourteen convention suites + meta-guard run as named serial steps in deploy-script-tests-fixed on every infra-touching PR; cadence per-push; alert_target = the required "test" aggregator leg; configured_in .github/workflows/infra-validation.yml
error_reporting:    # suite [FAIL] lines + non-zero exit → red named step → fail-closed deploy-script-tests-done aggregator (infra-validation.yml:~1345-1414); fail_loud = yes
failure_modes:      # [{mode: vacuous edit (assertion count below floor), detection: per-suite _floor + ledger conservation + mutate_floor_red, alert_route: red step}, {mode: floor invisible to meta-guard (phantom heredoc span), detection: PROMOTED_FILES membership pin reports not-floor-bearing, alert_route: red meta-guard suite}, {mode: PROMOTED_FILES stale-site edit, detection: single-site count pin (new), alert_route: red meta-guard suite}, {mode: CI-level muting via literal/composed/injected env name, detection: per-suite fragment + job-slice seam rows (new), alert_route: red suite step}, {mode: non-blocking step drift, detection: per-suite if:/continue-on-error: step-shape pins (new), alert_route: red suite step}, {mode: MAIN_PLAN run-to-EOF overshoot, detection: terminator-match assertion (new), alert_route: red suite step}, {mode: serial-leg timeout, detection: aggregator cancelled-classifier names the timeout shape, alert_route: red leg}]
logs:               # stdout in the infra-validation job log on GitHub Actions; GH retention default
discoverability_test:
  command:          bash -c 'grep -cE "^PRESENCE_ROWS=[0-9]+" apps/web-platform/test/infra/egress-gw-alert.test.sh'
  expected_output:  "1"
```

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed (sequential-fallback — CTO leader role run inline, no spawn tool)
**Assessment:** Internal test-machinery convergence on an already-adopted convention (the batch-2/3 ports are merged precedent). No architectural decision; the seam-check widening stays inside each suite's existing `IV_CODE` block and the job-slice ban follows a sibling suite's proven design. Main technical risks are convention-purity regressions (floor-window purity, P1b parity, sed anchors) — all mechanically gated by the suites themselves.

### Operations

**Status:** reviewed (sequential-fallback — COO leader role run inline, no spawn tool)
**Assessment:** No vendor, cost, or provisioning change. Operational relevance is the surface the suites guard (Better Stack alert drift detection); the change improves the trustworthiness of that detection without touching it. No follow-through enrollment needed — CI is the verification.

No `## Domain Assessments` brainstorm section exists to carry forward (no brainstorm ran). No UI-surface files in Files to Edit — mechanical Product/UX override does not fire; tier is NONE by both paths.

## Guard Contract

### Guard 1 — widened workflow seam check (per IV-seam suite)

**Property.** No executable-text fragment capable of composing a `MUT_SKIP` or `*_GUARD_*` env name, no shell-injection env name, and no `$GITHUB_ENV`/`$GITHUB_PATH`/`defaults:` inside the enclosing job reaches `infra-validation.yml` — the CI battery cannot be muted or redirected through any env channel.

**Assembly.** Every line of `IV_CODE` (the comment-stripped executable view of the whole workflow file) for the fragment set, plus the job-block slice enclosing each suite's byte-exact-pinned run line for the job-scope ban. The single chokepoint is the `validate:` job's step list — all convention suites dispatch through it; `env:` keys in YAML are static (fragments cover them) and `$GITHUB_ENV`/`$GITHUB_PATH` writes are the only dynamic channel (job slice covers them).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Insert `echo "MUT_""SKIP=1" >> "$GITHUB_ENV"` inside the mutant workflow's validate job | RED — `MUT_`/`_SKIP` fragments + job-scope `GITHUB_ENV` ban |
| 2 | Add `env:` key `FOO_GUARD_X: /dev/null` on the suite's step | RED — `GUARD` fragment, prefix-agnostic (second member after a compliant first: a plain `FOO:` env stays PASS in the same mutant family) |
| 3 | Add `BASH_ENV: /tmp/x` to the job env in the mutant | RED — shell-injection env name |
| 4 | Delete the fragment loop / empty the fragment set in a mutant suite copy (harness row) | RED — guard's own dispatch: the seam row reports a violation on a mutant carrying `MUT_SKIP` |
| 5 | Add `>> "$GITHUB_ENV"` write in a DIFFERENT job of the mutant workflow | must-PASS — over-breadth control: legit writes outside the suite's job do not red |
| 6 | Re-add the literal `MUT_SKIP: "1"` env (regression on the pre-existing literal check) | RED |
| 7 | Remove the suite's run line so `IV_JOB` slices empty | RED — the non-empty/run-line-inside assertion fires; the job-scope ban can never pass vacuously |

**Anchor.** `IV` is each suite's canonical-path read of the checked-in workflow (overridable only by the suite's own `<PREFIX>_GUARD_IV` axis, itself barred from the workflow by the same check); a weakening that edits both the fragment set and the workflow in one diff is caught by the mutation rows + review — same-documented-residual class as item 8.

### Guard 2 — step-shape pins (eight suites)

**Property.** The CI step running each convention suite is unconditionally blocking: no `if:`/`continue-on-error:` at step indent on its step, the job's `if:` is the one known literal exactly once, and no `continue-on-error:` in the job header.

**Assembly.** The step block and job header enclosing each suite's byte-exact-pinned run line in `infra-validation.yml` — sliced per suite at check time, so the property binds each suite's own registration point, not a first-match anywhere in the file.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `continue-on-error: true` to the suite's step in the mutant | RED |
| 2 | Add `if: false`/`if: github.ref == 'x'` at step indent | RED |
| 3 | Add `continue-on-error:` to the job header | RED |
| 4 | Alter the job `if:` literal or add a second `if:` | RED |
| 5 | Delete the suite's run line while leaving a decoy step (dispatch row) | RED via the byte-exact once-pin — the slice is derived, never vacuous |
| 6 | Leave the step compliant but mutate a SECOND suite's step non-blocking | RED — each suite checks its own slice; first-member compliance does not mask the second |

**Anchor.** Same `IV` canonical read as Guard 1; the step-pin block shape is ported verbatim from ghcr :345-355 / web-nic :285-295, so the mutation-row shapes are proven.

### Guard 3 — pre-battery verdict gate (twelve suites)

**Property.** Any failure in the presence section exits 1 with the FAILED ledger printed before a single mutation row executes — a verdict failure is never mislabeled as an exit-2 instrument FATAL and never spends the battery on an already-failed tree.

**Assembly.** The boundary between each suite's presence section and its `MUT_SKIP` battery — the one point every `no()`-recorded failure must be discharged at; suites that FATAL mid-presence (exit-2 instrument failures) are unaffected by definition.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Force a presence `no()` on a pristine run (e.g. `P_GUARD_TF` pointed at a gutted copy) | exit 1 with `FAILED:` ledger — never reaches a battery line, never exits 2 |
| 2 | Delete the gate in a mutant suite copy (harness row) | RED — a battery-time instrument failure exits 2 while a presence failure was pending; the suite's own mutation row on the gate text reds |
| 3 | Reorder: move the gate below the first battery row | RED — the property is ordering/lifetime; a case observing inside the window (presence failure + battery still ran) fails |

**Anchor.** The exit-code contract is the donor block at egress-gw :366-370 verbatim; insertion sits outside the floor window so `_floor`/`_ran` accounting is unchanged.

### Guard 4 — `MAIN_PLAN` slice bound (six suites)

**Property.** `MAIN_PLAN` contains exactly the `terraform plan` step's output span — it terminates on the first `rc=` line-start and the terminator is verified present, so a deleted/moved rc line fails loud rather than silently re-opening a run-to-EOF slice.

**Assembly.** The span between the `^[ \t]*terraform plan -no-color` opener and the first `^[ \t]*rc=` line-start in `apply-web-platform-infra.yml`, per carrier suite — the same slice every `-target=` pin grades.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move the `-target=logtail_exploration.*` lines below `rc=${PIPESTATUS[0]}` in the mutant WF | RED — pins can no longer find them inside the bounded slice (the overshoot shape this fixes) |
| 2 | Delete the `rc=` capture line entirely | RED — terminator-match assertion fires; without it the suite would re-overshoot silently |
| 3 | Insert a SECOND `terraform plan` block with decoy `-target=` lines after the real step | must-PASS — second-member row: pins grade only the first bounded span |
| 4 | Rename the capture to `plan_rc=` (line-start no longer `rc=`) | RED — terminator misses → run-to-EOF → terminator-match assertion fires |

**Anchor.** The remedy terminator `^[ \t]*rc=` was verified against the live workflow: `rc=${PIPESTATUS[0]}` at :685 is the first `rc=` line-start after the :466 opener; the next is :984 — far past the step's end — so the broadened terminator lands on the intended boundary.

### Guard 5 — PROMOTED_FILES single-site pin (meta-guard)

**Property.** Exactly one live `^PROMOTED_FILES=` assignment exists in `scripts/guard-vacuity-floor.test.sh`; the membership pin reads a single canonical set — a stale-snapshot edit or a fresh second assignment is mechanically red, never last-wins.

**Assembly.** All `^PROMOTED_FILES='` sites in the meta-guard file (the chokepoint: the variable's only consumers are the `:1110-:1114` covered/deferred/unclassified derivation and the `:1425+` per-member pin), plus the count pin's own text.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add a second `PROMOTED_FILES='…'` assignment anywhere in the file | RED — count pin fires |
| 2 | Delete the single live assignment | RED — count pin + downstream empty-set failures |
| 3 | Add a promoted entry via a comment-only edit mimicking a stale site | must-PASS — comments are not assignments; the pin counts `^PROMOTED_FILES='` only |
| 4 | Remove a promoted file's floor while leaving its PROMOTED_FILES entry | RED — pre-existing per-member pin (second-member semantics: membership pin, not count pin, catches this) |

**Anchor.** The meta-guard is the independently-checked registry here — the diff edits it and the suites together, and the meta-guard's own suite certifies consistency (ADR-193 shape).

### Guard 6 — inngest-524 attribute-pin completion

**Property.** Every paging-relevant attribute of every alert discovered from the #8611 section is pinned — `operator`/`value`, all four periods, `name`/`alert_type`/`email`-shape/`escalation` — not only the first-discovered or the convenient subset.

**Assembly.** The `names` discovery list (floor ≥2, `inngest_step_524` and `claude_cost_daily_burn` each `count == 1`) × the `logtail_exploration_alert` block per name — `alert_attr`'s exactly-once extraction is the per-member chokepoint (a duplicated attr line yields `None` → fails, never first-match).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `query_period` (or any period) on `inngest_step_524` only | RED — the second-member row: today only the burn alert's periods are pinned |
| 2 | Change `alert_type`/`name`/`escalation` on either alert | RED |
| 3 | Insert a `//`-comment decoy carrying an emitter needle into a `.ts` source in a mutant | RED — comment-stripped `re.search` view |
| 4 | Delete the `probe_ts` read or empty it (harness/dispatch row) | RED — the new provenance asserts require its literals |
| 5 | Discover a third alert in the section (mutant adds one) | RED via the existing `count == 1` shape + extended per-name pins covering the new member |

**Anchor.** Attribute values are canon-derived from the same `betterstack-logs-alerts.tf` the alerts live in — a weakening that edits both canon and pins in one diff is the item-8 class residual (documented, review-covered).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Seam greps cover literal text only. All convention suites (incl. merged donors egress-gw/registry-*/inngest-luks-*) grep infra-validation.yml for `MUT_SKIP`/`*_GUARD_*` literals; runtime-constructed env names (`echo \"MUT_\"\"SKIP=1\" >> $GITHUB_ENV`, composed prefixes) evade every seam row." | Item 1 (fragment set + job-scope ban) | mapped |
| 2 | "inngest-step-524 pre-existing defects: EMIT_PROBE/probe_ts parsed never asserted; name/alert_type/email/escalation + check/query/recovery/confirmation periods unpinned for both discovered alerts; stale comments (\"TWO units\", \"the two daily alerts\", tasks.md \"<3\" — code correctly refuses <2 post-#11653)." | Item 2 | mapped |
| 3 | "Convention-internal asymmetries carried from donors: pre-battery `fail>0 → summary+exit 1` gate absent in 5/6 batch-3 files …; `Q = chr(39)` dead in most PRELUDEs; vestigial EXPECT_1 in ghcr/web-nic; `SELF=\"${BASH_SOURCE[0]}\"` relative form in ghcr/web-nic; census vocabulary drift; single-element `for` loop in inngest:282." | Item 3 (+ item 2's loop fold) | mapped |
| 4 | "`if:`/`continue-on-error:` step pins only in ghcr/web-nic — the other four convention suites pin only the byte-exact run line; a non-blocking step survives." | Item 4 (eight suites per census) | mapped |
| 5 | "web-nic readability gate covers TF/WF/EM only — RB/LQ/IV unreadable grades `no` not FATAL (fail-closed, cosmetic)." | Item 5 | mapped |
| 6 | "ghcr JQ_DIR mktemp lacks EXIT trap; sandbox-alerts `assert s.count(old) >= 1` weakens the `== 1` anchor convention; sandbox EMITTER awk takes first `export function mirrorBashSandboxFailure(` (relies on tsc rejecting dupes); inngest-524 .ts emitter checks are `re.search` presence-only (`//`-comment decoys satisfy; claude-cost-marker.test.ts covers behaviorally)." | Item 6 (+ item 2's comment-strip) | mapped |
| 7 | "Meta-guard: PROMOTED_FILES has 4 assignment sites (last-wins :798/:811/:819 stale, :1104 live) — suggest a stale-site marker or consolidation." | Item 7 (consolidation + count pin chosen over marker) | mapped |
| 8 | "Floor self-reference: decrementing PRESENCE_ROWS/MUT_ROWS alongside row deletions keeps suites green+FIRES (documented accepted in batch-3 plan Anchor row — re-evaluate if a cheap invariant exists)." | Item 8 (document-and-keep) | mapped |
| 9 | "MAIN_PLAN slice overshoot in all five sibling awk extractions — terminator `^[ \t]*rc=` verified remedy" [brief] | Item 9 (six carriers per census) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Item 1 seam strengthening | asks 1 + "may need a coverage-design decision at plan time — decide the seam-check strengthening approach concretely" [brief CTO ruling] | asked |
| Item 2 inngest-524 completion | ask 2 | asked |
| Item 3 fail>0 gate ×12 (beyond the named 5) | ask 3 names 5/6 batch-3; extension to all `no()`+battery suites is inferred — justification: the issue is explicitly "family-wide … items shared with already-merged batch-1/batch-2 convention files"; fixing 5 of 12 identical-shape holes recreates the asymmetry the issue exists to remove | inferred — justification: family-wide convergence is the ask's stated frame |
| Item 3 dead-Q / SELF / census / EXPECT_1 | ask 3 (each named); SELF extended from 2 named files to all 5 relative-form sites — same family-wide justification | asked + inferred (same justification) |
| Item 4 step pins ×8 (beyond the named 4) | ask 4 names "the other four"; extension to the other four seam-bearing suites lacking pins | inferred — justification: identical hole, identical remedy, family-wide frame |
| Item 5 readability | ask 5 | asked |
| Item 6 per-file smalls | ask 6 | asked |
| Item 7 PROMOTED_FILES consolidation | ask 7 ("stale-site marker or consolidation" — consolidation chosen) | asked |
| Item 8 document-and-keep | ask 8 + CTO bound "resolve as document-and-keep if no cheap invariant exists" [brief] | asked |
| Item 9 MAIN_PLAN bound | ask 9 [brief] | asked |
| Step-pin mutation rows, job-slice must-PASS row, terminator-match assertion | — | inferred — justification: the guard-contract mutation matrix requires dispatch + must-PASS rows or the new checks are vacuous by construction |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (test/infra suites), `scripts` (meta-guard)
- Planned files: 15 | Estimated changed lines: ~550
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one mechanical convention sweep, uniform per-file shape, one CI leg validates all of it; splitting by item would serially re-touch the same files.

## Acceptance Criteria

<!-- founder-stated check: not captured — headless pipeline run (plan-founder-check.md §When it runs) -->

- [ ] AC1: In every IV-seam suite, a mutant `infra-validation.yml` carrying a composed `MUT_`/`_SKIP`/`GUARD`/`BASH_ENV`/`SHELLOPTS`/`BASHOPTS` fragment, or a `$GITHUB_ENV`/`$GITHUB_PATH`/`defaults:` write inside the enclosing job, drives the seam row RED; the same `$GITHUB_ENV` write in a different job stays PASS.
- [ ] AC2: The eight listed suites red on step-level `if:` or `continue-on-error:` and job-level `continue-on-error:` mutants; their step-pin block shape is the ghcr/web-nic port.
- [ ] AC3: All six `MAIN_PLAN` carriers bound the slice at the first `rc=` line-start, assert the terminator matched, and red on moved-below-rc `-target=` mutants.
- [ ] AC4: Every convention suite carrying `no()`/FAILED + a `MUT_SKIP` battery exits 1 with the FAILED ledger before the battery when a presence row fails — verified by forced-presence-failure runs; instrument FATALs still exit 2.
- [ ] AC5: inngest-step-524 asserts `probe_ts` emitter literals, pins the full attribute set for BOTH discovered alerts, strips `//`+`/* */` comments from `.ts` reads, and carries no vestigial single-element loop or stale two-unit/two-alert comments.
- [ ] AC6: web-nic's readability gate loops all six path vars; ghcr's JQ_DIR sits under the EXIT trap; sandbox's `s.count` is `== 1` and its EMITTER extraction is exactly-once-pinned.
- [ ] AC7: `scripts/guard-vacuity-floor.test.sh` has exactly one `^PROMOTED_FILES=` assignment; a self-pin reds a second site; grounds history is preserved above the live site.
- [ ] AC8: Dead `Q = chr(39)` is gone from the seven listed PRELUDEs; all five relative-form `SELF` sites use `$DIR/$(basename …)`; `EXPECT_1` renamed `EXPECT_SQL` in ghcr/web-nic.
- [ ] AC9: Each touched suite's floor window stays six pure assignments with column-0 constants and `fi`; `PRESENCE_ROWS`/`MUT_ROWS`/`MUT_ROWS_RUN` constants bumped at both write sites for every added row; every suite still scores FIRES; `MIN_FIRING_SUITES` unchanged at 71.
- [ ] AC10: A one- or two-line self-reference comment sits at each touched suite's floor window documenting the accepted residual (item 8, document-and-keep).
- [ ] AC11: `shellcheck -S warning` is clean on every touched file; no `| grep -q` pipeline, no `env -u`, no literal `<<-` in scanned fixture text, no bare `$$` in unquoted `<<PY`.
- [ ] AC12: All fourteen convention suites + the meta-guard pass locally (`bash <suite>` per file), and the `deploy-script-tests` CI leg is green with measured runtime reported in the PR body.

## Test Scenarios

All scenarios are `integration`-layer bash assertions inside the suites themselves — the suites are self-mutating guard batteries; new rows follow the `mutate_red`/`mutate_green`/`mutate_floor_red` convention with byte-matched `no "…"` fragments (`grep -F` verified pre-ship).

- Given a mutant `infra-validation.yml` with `echo "MUT_""SKIP=1" >> "$GITHUB_ENV"` inside the `validate:` job, when each seam suite runs its IV axis, then the seam row reports the composed-name violation and the suite exits 1 (`integration`).
- Given the same `$GITHUB_ENV` write moved to the terraform-plan job, when the seam check runs, then it stays PASS — the job-slice scoping does not over-reach (`integration`).
- Given a mutant with `continue-on-error: true` added to a suite's step, when each of the eight step-pin suites runs, then the step-shape row is RED (`integration`).
- Given a presence `no()` forced via a `*_GUARD_*`-pointed gutted copy, when a gated suite runs, then it prints `FAILED:` and exits 1 with zero battery lines in its log (`integration`).
- Given `-target=` lines moved below `rc=${PIPESTATUS[0]}` in a mutant `apply-web-platform-infra.yml`, when a `MAIN_PLAN` carrier runs, then the target pins are RED; given the `rc=` line deleted, then the terminator-match assertion is RED (`integration`).
- Given a `//`-comment decoy carrying an emitter needle in a mutant `.ts`, when inngest-step-524 runs, then its emitter checks are RED; given a period change on `inngest_step_524` only, then the attr pins are RED (`integration`).
- Given a second `PROMOTED_FILES='` assignment added to the meta-guard, when it runs, then the single-site pin is RED (`integration`).
- Given a `PRESENCE_ROWS` bump without a row (via `mutate_floor_red` on `^PRESENCE_ROWS=[0-9]+$`), when each touched suite runs, then the floor row is RED — the derived-floor convention is preserved (`integration`).

## Files to Edit

- `apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh` — items 1, 3 (fail>0, dead-Q), 4, 9
- `apps/web-platform/test/infra/egress-gw-alert.test.sh` — items 1, 3 (dead-Q), 4
- `apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh` — items 1, 3 (fail>0, dead-Q), 4, 9
- `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh` — items 1, 3 (fail>0, dead-Q, SELF, EXPECT_1 rename), 6 (JQ_DIR trap), 9
- `apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh` — items 1, 3 (fail>0, SELF), 9
- `apps/web-platform/test/infra/inngest-step-524-alert.test.sh` — items 1, 2, 4, 6 (comment-strip folded into 2)
- `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` — item 3 (fail>0, SELF)
- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — item 3 (fail>0, SELF)
- `apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh` — items 1, 3 (fail>0)
- `apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh` — items 1, 3 (fail>0), 4
- `apps/web-platform/test/infra/registry-zot-credential-shape-alert.test.sh` — items 1, 3 (fail>0, dead-Q), 4
- `apps/web-platform/test/infra/sandbox-alerts.test.sh` — items 1, 3 (fail>0), 4, 6 (s.count, EMITTER), 9
- `apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh` — items 1, 3 (fail>0, dead-Q, SELF, EXPECT_1 rename), 5, 9
- `apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh` — items 1, 3 (fail>0, dead-Q), 4
- `scripts/guard-vacuity-floor.test.sh` — item 7 (PROMOTED_FILES consolidation + single-site pin)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11899-convention-suite-cleanup/tasks.md` (this pipeline's task breakdown — planning artifact)

No product/test-source files are created; all edits are to existing tracked suite files.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for every file in Files to Edit; zero matches.

## Success Metrics

- All fourteen convention suites + meta-guard pass locally and on the `deploy-script-tests` leg.
- The seam checks red on every composed/injected env-name mutant in the Guard 1 matrix (previously all survived).
- Zero `grep -c '^PROMOTED_FILES='` count > 1; zero `rc=$\?`-only terminators remaining (`grep -c 'rc=\\$\\?/{exit}'` over the six files == 0).
- Serial runtime of the leg measured and reported; no timeout-margin regression past ~12 of 15 min.

## Dependencies & Risks

- **Shared-SUT drift:** `betterstack-logs-alerts.tf` / `apply-web-platform-infra.yml` / `infra-validation.yml` are pinned canon in fourteen files; an in-flight infra PR can invalidate needles mid-work — re-probe at every Phase-7 sync (precedent #11653).
- **`validate:` job scope:** the job-slice ban presumes all suite run lines live in `validate:` (verified :905-:1001); a future job split would move the slice with the run line by construction (the slice is derived from the pinned run line, not the job name).
- **Fragment false-positive risk:** a legit future `GUARD`/`MUT_`/`_SKIP`-bearing string in executable workflow text reds every seam suite at once — mitigated by the per-suite override axis (`<PREFIX>_GUARD_IV`) and the fail-loud message naming the fragment.
- **Merge-queue timing (landmine):** `enqueuePullRequest` waits for the required `test` check-run on the current head (~10-20 min post-push); push everything before enqueue, then freeze — rebase only before first enqueue.

## Plan Review

**Reviewed-Coverage: sequential-fallback** — panel seats run inline by the planner (no spawn tool); findings below are role-lens analyses, not independent reviews.

**Eng panel (always):** DHH / Kieran / code-simplicity. **Named panel:** `soleur:engineering:cto` devex lens activated (code/infra Files-to-Edit); CPO/CMO/UX-lead inactive (no UI-surface or product/market content); no `single-user incident` escalation (threshold `none`).

- **Mechanical (auto-applied):** (a) job-boundary regex widened to `^  [a-zA-Z_][a-zA-Z0-9_-]*:` — job IDs allow hyphens/digits (Kieran); (b) `IV_JOB` non-empty/run-line-inside assertion added — empty slice would pass the absence ban vacuously (spec-flow catch); (c) PROMOTED_FILES count pin specified as line-start-anchored `${BASH_SOURCE[0]}` self-read so the pin's own pattern text can never self-match (Kieran); (d) verified `defaults:`/`GITHUB_ENV`/`GITHUB_PATH` appear nowhere in `validate:` today (Kieran).
- **Agreements:** fragment-set + job-slice layering is the minimal coverage for the composed/injected channel (DHH concurred whole-file ban would false-positive on the `plan:` job's legit :1662/:1674 writes); code-simplicity confirmed every mechanism maps to a Property-List item with no simpler existing mechanism — the Cut List already records the two rejected heavier alternatives.
- **Taste (persisted, not auto-applied):** `EXPECT_1`→`EXPECT_SQL` rename and census-vocabulary convergence — already in `decision-challenges.md` as taste/pending-assumed; no new taste findings.
- **Standing check (cq-ac-must-not-depend-on-concurrent-sessions):** PASS — no AC asserts an ambient condition; AC12 reports a measured runtime, not a bound.

## References & Research

- Issue: #11899 (work target); parent #11720 (closed); batch PRs #11695/#11849/#11885 (merged); epic #10390.
- Donor plan: `knowledge-base/project/plans/archive/20261102-183000-2026-11-02-chore-mut-skip-guard-batch3-plan.md` (Anchor row = item-8 precedent).
- Donor suites: `apps/web-platform/test/infra/egress-gw-alert.test.sh` (convention), `ghcr-blocked-alert.test.sh`/`web-nic-guard-unpinned-url-alert.test.sh` (step-pin shape), `apps/web-platform/infra/betterstack-alert-structure.test.sh` (structural env/GITHUB_ENV coverage precedent).
- ADR-252 (suite registration by file presence); learnings listed in Research Insights.
