---
title: "chore(inngest): retire the suite-only inngest_host_dark_gate entry point (narrow retire, Ref #8316)"
date: 2026-10-14
slug: retire-inngest-host-dark-gate-entry-point
branch: feat-one-shot-8316-retire-inngest-host-dark-gate
issue: 8316
closes: []
type: chore
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(inngest): retire the suite-only `inngest_host_dark_gate` entry point (Ref #8316)

Spec lacks valid `lane:` (no spec.md for this one-shot branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`tests/scripts/lib/inngest-host-dark-gate.sh` carries two entry points over one set of shared probe-row helpers.
`inngest_execute_registry_gate` is live: `scripts/cutover-inngest.sh` calls it from `op=execute` step 2.0 and from the
`registry-probe` arm (the P0 cutover double-fire guard). `inngest_host_dark_gate` ("Guard 2" of the long-gone
`inngest-volume-recut` target) has had no production caller since #8285 PR A and is kept only by its own suite, "pending the
retire-or-keep decision" on #8316. The decision inputs have resolved: PR #8248 is MERGED, #8285 CLOSED (the plaintext backstop
volume answered 404 on 2026-10-09), #7777 CLOSED, #8078 CLOSED (G8 already carries the wide predicate), #7695 and #6894 CLOSED.

This PR is the **narrow retire**: delete the dead entry point and the one helper only it used, trim the suite sections that exercise
it (porting any shared-helper behaviour whose only test dies with it), reconcile the prose that still describes a recut path,
append a dated retirement note to ADR-199, regenerate the derived baselines, and prove with a differential mutation run that
every execute-gate row (E1..E13, plus E14) still bites. The live gate's code, the shared helpers and the suite name stay.
`Ref #8316` only: the issue stays open for the operator to close (see Scope Check, row 13).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #8316 body / operator brief) | Reality at base `b6d745fe78` | Plan response |
|---|---|---|
| Retire "the `inngest-volume-recut` enum option and `inngest_volume_recut` job ... the two gate libraries and their suites ... `scripts/test-all.sh` rows ... `terraform-target-parity` expectations" | `git grep` over `.github/workflows`, `scripts/test-all.sh` and `terraform-target-parity.test.ts` finds no `inngest-volume-recut`: #8285 PR A converted the job and PR B deleted it. `tests/scripts/lib/` holds no `inngest-volume-recut-gate.sh`. `inngest_expect_luks` / `INNGEST_REDIS_LUKS_KEY` are live ADR-142 apparatus. | Nothing to do beyond the entry point; recorded so #8316's remaining scope is legible. |
| "function at ~L725-1145" | `inngest_host_dark_gate()` is L725-1059 (335 lines). L1060-1145 are the execute gate's banner, E-table and `_erg_flag_class` doc, which must stay. | Delete L725-1060 only (function plus its trailing blank line). |
| "helpers used ONLY by it" | Of 14 helpers, only `_ihdg_finished_count` (L387-411) is dark-gate-only. `_ihdg_decoded_rows` is born for G10 but is called by shared `_ihdg_undecodable`; `_ihdg_refuse`, `_ihdg_verdict`, `_ihdg_selector_unavailable`, `_IHDG_EXPECTED_SCHEMA` and `_IHDG_PROBE_LIB_OK` each have an execute-gate use. | Delete `_ihdg_finished_count` and its comment block; keep the rest byte-identical. |
| "suite sections 6 and 7 unchanged" | Sections 6.4/6.5 run each shared-helper mutation against both entry points (`mutate_both`, `GATE_FN=inngest_host_dark_gate` rows), and section 7 has five recut-gate selector rows plus a recut-gate canary and default-path row. `gate()`, `mutate()` and the 0b/0c wrapper self-tests default to the dark gate. | Execute-gate assertion lines stay byte-identical; sibling halves and the defaults necessarily change (decision row P1). |
| "(a) ... `.github/workflows/cutover-inngest.yml` ~L204 'recuts /mnt/data today'" | Present: L201-206, a CORRECTED-2026-08-25 comment still saying no `apply_target` recuts and "the design for one is tracked in #7695". | Line-local rewrite of those lines (Phase 3). |
| "(a) `scripts/cutover-inngest.sh` ~L3437 'recovery from `aborted` is a /mnt/data recut'" | Present at L3437 in the `op=resume` KNOWN DEAD END comment. | Line-local rewrite (Phase 3). |
| "verify whether 'No apply_target recuts THIS volume yet' ... already fixed on main" | Fixed: `git grep -n 'recuts THIS volume\|THIS volume yet'` is empty repo-wide. **But the same G3.7 `latched` `::error::` (L2659) now asserts the opposite falsehood:** "`apply_target=inngest-volume-recut` DOES exist (it shipped in #7695)" and tells the reader to use it. No test pins that sentence. | Fix the one sentence in this PR (CTO F2). |
| "verify ... model.c4 inngestRedis description already fixed" | Fixed: the anchor "becomes crypto_LUKS only when the gated" is gone; the description now states LUKS live, sole copy, backstop destroyed 2026-10-09 (#8285). `model.c4` names only `inngest_execute_registry_gate`. | Leave `model.c4` and `model.likec4.json`. |
| "ADR-199 Consequences paragraph 'Until the host is replaced, every dispatch'" | Present at L131-132. The brief also says "amend ADR-199 ... (append, change nothing above)". ADR-199's own convention is "Appended; nothing above is changed". | One append-only addendum that supersedes the paragraph by name (CTO F1). |
| ADR-199's 2026-10-09 addendum: the invariant "is unchanged and still enforced by `inngest-host-dark-gate.sh` for `scripts/cutover-inngest.sh`" | Overclaim. The execute gate grades "positively dark host" (E1..E14); the measured-empty-store, mount-devid pin, live id pin, #7674 followthrough, flag allowlist and diagnostic-boot predicates (G8-G20) die with the entry point and have no executable form afterwards. | The addendum states this plainly (CTO F12). |
| "#8078 (G8 predicate) — re-graded p3, fixed only on Keep" | #8078 is CLOSED: ADR-100 section 7 "RESOLVED 2026-10-07" and the suite's G8w/G8u rows. Moot for a Retire. | Note only. |
| "(c) `scripts/suite-durations.tsv` and `suite-shard-legs.tsv`" | Suite label `tests/scripts/inngest-host-dark-gate` stays registered (`scripts/test-all.sh:5989`); the manifests list labels, not content. `regenerate-shard-manifest.py --incremental` is the add/remove path and pins retained rows verbatim. | Expect a zero diff; run dry (CTO F5). The stale-high weight (16167 ms) persists until the scheduled CI-measured rebalance. |
| "(c) `scripts/test-affected-kb-consumers.baseline.txt`" | Row 222 maps this suite to `inngest-server.md` via one hop through `scripts/cutover-inngest.sh` (named by the suite's Row 6a/6b). That hop survives the trim. Separately, `plugins/soleur/test/fixture-relative-assert.baseline.txt` rows 463 and 467 count relative operands in these two files and can fall. | Run both checkers; regenerate only on drift. |
| "(d) fix `cutover-inngest-workflow.test.sh` L2607-2611 and any other test that names the deleted function" | `git grep` finds `inngest_host_dark_gate` in exactly one other test file: that assertion (comment L2607-2609, row L2610-2611) and a stale comment at L2617-2618. Its trailing `grep -v 'inngest_execute_registry_gate'` drops WHOLE LINES, so a line holding the allowed name AND a forbidden helper escapes. | Rewrite, strengthen, mutation-prove (CTO F10). |
| "(e) grep the SUBJECT across runbooks" | `inngest-server.md` L1481-1483 ("the recut gate refuses as `stale_schema`") is a live claim; L2308 (remediation line) and the L2330-2375 callout chain describe the recut as the latch's remedy and the library as "kept" with fate "decided on #8316". `inngest-bootstrap.sh` L704/L992 also mention the gate but ship in the OCI image. | Fix L1481-1483 in place, append one Update, leave bootstrap.sh (CTO F9, F13). |
| Open draft PR #10257 edits the same three files | Its hunks: yml `@@ -62` and `@@ -221`; script `@@ -134,-1233,-1576,-2324,-3001,-3130`; test `@@ -7,-292,-387,-4333,-4755`; runbook near L1304. Ours: yml L201-206, script L2659 and L3437, test L2606-2619, runbook L1481 and the callout chain near L2375. No overlap. | Keep every edit line-local; re-check the hunk map before pushing (AC11). |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #8316 OPEN (closedByPullRequestsReferences empty); PR #10268 draft, `closingIssuesReferences` `[]`;
PR #8248 MERGED; #8285, #7777, #8078, #7695, #6894 CLOSED; PR #10257 and PR #10081 OPEN drafts (#10081 labelled `parked`, "do not merge
until an approved `apply_target=inngest-host-replace` window exists"). Cited symbols confirmed on base: `inngest_host_dark_gate`
(L725), `_ihdg_finished_count` (L387), `inngest_execute_registry_gate` (L1228), the Row 6a/6b wiring rows, and the workflow-test
rows at L2606-2619. Mechanism vs ADR corpus: ADR-199 (the retired entry point's decision), ADR-100 section 7 and ADR-142 describe
it; none rejects deleting a gate whose only purpose has been removed, and ADR-199's own 2026-10-09 addendum already records the
dispatch as gone. Stale: the issue's retire list is mostly done by #8285; the brief's "model.c4" and "No apply_target recuts THIS
volume yet" items are already fixed (but see L2659).

**Property List (Phase 0.6b).**
P-a. After the change, no code path in the repo can call a function that the library no longer defines, and the live execute gate
 still grades exactly as before (same source bytes for it and every helper it calls).
P-b. No shared-helper behaviour loses its only test: every assertion that died with the entry point is either dark-gate-only logic
 or has a surviving or ported execute-gate assertion that kills the same mutant.
P-c. No document, comment or `::error::` text in a live position claims the retired mechanism exists or is the remedy for something.
P-d. Derived baselines match what their own generators produce from the post-change tree.
P-e. #8316 is referenced, never closed, by this PR.

**Cut List (Phase 0.6b).**

| Mechanism proposed or tempting | Property it would buy | What already covers it / why cut |
|---|---|---|
| Rewrite the kept helpers' G-numbered comments | P-c | The helpers are byte-identical by instruction; the lib header carries the G-to-E mapping (CTO F6). |
| Add a permanent CI gate that greps for the retired names | P-c | A one-time classified sweep is proportionate; fuzzy terms ("recut gate", "Guard 2") need judgment (CTO F14). |
| Bump `probe_schema` / prune now-unconsumed emitter fields | P-a | Forces an image build and host replace; PR #10081 is parked (CTO F8). Follow-up issue instead. |
| Edit `inngest-bootstrap.sh` L704/L992 comments | P-c | Image-baked; any edit chains into a pin bump and user_data drift (CTO F9). |
| Edit ADR-100 / ADR-142 / ADR-225 mentions | P-c | Historical ADRs; the ADR-199 addendum states they are historical (CTO F1). |
| Rename the lib or suite | none | "Keep file/suite names"; a rename would also trip rename-guard and the shard manifest. |
| Full `regenerate-shard-manifest.py --runs 5 --write` | P-d | Not needed: no suite added or removed; would rebalance legs and touch every sibling PR (CTO F5). |

**Institutional learnings applied.**
- `2026-10-12-retiring-a-probe-by-file-list-left-a-derived-baseline-row-and-live-runbook-claims.md` — deleting code has three consumer
 kinds (registrations, derived artifacts, live claims); run the generators in check mode and grep the SUBJECT, not the filename.
 This plan's Phases 5 and 6 are that learning's prevention list.
- Plan sharp edge "Before a plan review deletes an assertion as redundant, name the mutation it kills" — the basis of the differential
 mutation run (Phase 7) and the port-before-delete rule.
- `2026-09-14-the-sweep-that-retired-false-sentences-wrote-new-ones-from-my-own-issue-comment.md` — the L2659 edit and the ADR addendum
 are checked against the tree, not copied from the issue body (the issue body itself lists the `::error::` anchor that is already gone).
- `2026-10-03-a-manifest-priced-from-staged-runs-misses-a-suite-that-landed-after-them.md` — never hand-merge the TSVs; regenerate or leave.
- `2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md` — regenerate baselines as the last commit before
 merge, after the final `origin/main` sync.
- Closing-keyword learnings (`auto-closes #N` in a commit body trips the parser) — scan commit bodies, not only the PR body.

**Baseline measurements (run on base, targeted suite only).** `bash tests/scripts/test-inngest-host-dark-gate.sh`: 309 passed, 0 failed
(exact `_FLOOR=309`), 37 distinct predicates (floor 35), token coverage 19/19 with `dark` asserted 43x, wall time 31 s.
Execute-gate token set = 11 (`unreadable silent wrong_host stale_row stale_schema host_serving flag_armed flag_unreadable
fsm_unreadable fsm_silent dark`); after the deletion the lib's token set equals it, so the workflow test's `LIB_TOKEN_N -ge 11` and
`ERG_TOKEN_N -eq 11` rows still hold.

**CTO rulings** (F1-F14) are persisted in `knowledge-base/project/specs/feat-one-shot-8316-retire-inngest-host-dark-gate/decision-challenges.md`.

## Open Code-Review Overlap

None. Queried 93 open `code-review` issues for every planned file path (lib, suite, workflow test, `cutover-inngest.yml`,
`cutover-inngest.sh`, ADR-199, the runbook, both baselines): zero matches.

## Proposed Solution — Implementation Phases

Order matters only where noted: Phase 0 first (it fixes the kill-set reference), Phases 1-2 together (the suite sources the lib), Phase 7
after 1-2, Phase 5 last before the final push (derived artifacts).

### Phase 0 — Baseline and kill-set reference (read-only)

0.1 Record base SHA `git merge-base origin/main HEAD` (planning-time: `b6d745fe78`). Everything below diffs against it.
0.2 Build the **mutant list mechanically** from the base lib: for every non-comment line of `_ihdg_graded_row` and its helpers
 (`_ihdg_field`, `_ihdg_rows`, `_ihdg_newest_dt`, `_ihdg_row_count`, `_ihdg_tied_newest`, `_ihdg_undecodable`,
 `_ihdg_epoch_from_dt`, `_ihdg_decoded_rows`, `_ihdg_refuse`, `_ihdg_verdict`, `_IHDG_*`) and of `inngest_execute_registry_gate` /
 `_erg_*` that matches the guard shapes (`|| { _ihdg_refuse|_ihdg_verdict ...}`, `[[ ... ]]` predicates, `select(...)`, `sort`,
 `unique`, `max`, `startswith`, jq filters), emit one mutant that neutralises that single line (`:` for a guard, `select(true)` for a
 select). Key each mutant by `(line content, occurrence index)`, never by line number (the deletion shifts lines). Census at planning
 time: ~120 candidate lines. Store the list in the scratch directory, not the repo.
0.3 Run the list against a scratch `git archive <base>` copy with the base suite (4-way parallel; each run is ~31 s, ~15 min wall).
 Output: kill-set K_main (mutants for which the suite exits non-zero) and survivor set S_main. Per-case attribution is not needed: ports are found by iteration (Phase 7.2 — any K_main mutant missing from K_branch gets a port or a written justification, repeat until K_branch is a superset). First filter: shared lines already paired by a `mutate_both` main half are proven killed by an execute-gate case and need no port. This is the reference, and
 `mutate()`'s own contract is NOT applied here — only "suite red or not". The mutant floor is the measured base count (recorded in the PR body), not a fixed number.

### Phase 1 — Library: delete the entry point, rewrite the header

1.1 Delete `inngest_host_dark_gate()` (L725-1059) and its trailing blank line (L1060).
1.2 Delete `_ihdg_finished_count` (L387-412: comment block L387-393, function L394-411, and one trailing blank so no double blank remains). Do **not** delete `_ihdg_decoded_rows` (shared via
 `_ihdg_undecodable`).
1.3 Rewrite the header (L1-178; the selector block from L180 is untouched) AND the execute-gate banner (L1062-1138), whose prose says "The SECOND entry point of this lib", "runs helper rows against BOTH entry points" and that "the recut gate inherits" the boot_id tightening; keep its E-table, property and Usage block (the execute gate's Usage block is INSIDE this banner at L1125-1137, not at the bottom). New header states, in this order: what the library is (one
 live entry point, `inngest_execute_registry_gate`, plus shared `_ihdg_*` probe-row helpers and `_erg_*` helpers used only by it);
 that `inngest_host_dark_gate` was retired on 2026-10-14 under #8316 with the recovery SHA; that G1-G7 are the historical names of
 E1-E7 and survive as names inside the kept helpers' comments, and G8-G20 are retired (full table and the five-point monotonicity
 argument live in ADR-199 and in `git show <base>:tests/scripts/lib/inngest-host-dark-gate.sh` L26-77 and L107-142); the positive-
 allowlist posture (only the literal `dark` passes); "why this is not `inngest-dedicated-host-classify.sh`" (kept verbatim: it applies
 to the surviving gate's `stale_schema` vs `unreadable` split); the execute gate's Usage block (already inside the execute-gate banner).
 It must **not** say the entry point is kept pending any decision. List, in the header's retirement note, every dangling mention left
 in kept helper comments (`grep -n 'inngest_host_dark_gate\|_ihdg_finished_count\|recut gate\|SECOND entry\|BOTH entry' tests/scripts/lib/inngest-host-dark-gate.sh`)
 so none is silent (CTO F6).
1.4 Guard against dropping a sentence the AC checks need: `dbsize` must still appear on **zero** lines of the lib (the B13 row is
 deleted, but the lib stays clean); `SOLEUR_INNGEST_SERVER_PROBE` stays on zero non-comment lines (`[#8846-once]`).
1.5 Invariant check (run, do not eyeball): `diff <(sed '1,178d;387,412d;725,1060d' <base lib>) <(sed '1,<N>d' <branch lib>)` where N is the new header's last line must show only the banner prose changes of 1.3 (function bodies and `_IHDG_*` assignments byte-identical; an awk extract of `_ihdg_*`/`_erg_*`/`inngest_execute_registry_gate` bodies, minus `_ihdg_finished_count`, must be empty-diff).

### Phase 2 — Suite: trim sections 1-5, rebind the harness, port, recompute floors

Disposition map (line numbers at base; the executor recomputes them):

| Base region | Disposition |
|---|---|
| L1-60 header | Rewrite: one entry point; drop "THREE BATTERIES" items 1-2; keep the guard-mutation harness description; drop "since #8054 section 6". |
| L62-178 instrument self-test, constants, `bs_line`, `hb_line`, `PROBE_FIELDS`, `PD`, `msg`, `mk_rows` | Keep. Drop only constants left unused (`OTHERID`, `OTHERDEVID`); `VOLID`, `DEV*` feed `PD`. |
| L180-191 `ROWS`, `FIN`, `rows-selftest.json` | Delete (dark-gate fixtures). |
| L193-236 `NOW`, `_gate_default_args`, `gate()` | Keep `NOW`; drop the `inngest_host_dark_gate` arm; `GATE_FN` defaults to `inngest_execute_registry_gate`. |
| L238-267 `expect`, `predicate` | Keep byte-identical. |
| L269-283 (0b) expect self-test | Delete: the existing `ERG SELF-TEST` in section 6 proves the same property through the execute gate. |
| L285-303 (0c) predicate self-test | Move into the section 6 preamble beside `ERG SELF-TEST`; rebind to `$TMP/erg-selftest.json` + `$HB`. |
| L305-308 dark BASELINE | Delete (section 6 has `[ERG] BASELINE`). |
| L310-497 (section 1, drop-one G1-G20) | Delete. Shared behaviours get ports (below). |
| L499-755 (sections 2, 2a, 2c, 2b) | Delete. Ports below. |
| L757-791 (section 3 H-rows, H2 always-dark copy) | Delete (`ERG-H2` exists). |
| L793-805 (B13) | Delete. |
| L807-864 (B12 emit/read contract) | Keep **trimmed**: the field-name list shrinks to the fields the execute gate consumes (`boot_id probe_schema host_role server_active http_code cutover_flag registry_fns`); drop the dark-gate `expect ... dark` line; keep `B12_ERG_MSG` construction and the emitter-schema/lib-constant cross-pin verbatim. |
| L866-881 (Rows 6a/6b/6c) | Keep 6a and 6b verbatim; re-word 6c to "the workflow does not source the lib" (drop the `if ! inngest_host_dark_gate` alternative: the strengthened census already forbids the retired name in the script). |
| L883-896 (Row 8 default clock) | Move to a new section 6.6 and rebind to the execute gate (heartbeat stamped relative to now). |
| L898-931 (Row 9 no-floating-clock scan) | Keep, regex narrowed to `inngest_execute_registry_gate `; the two deliberate real-clock arms become the new 6.6 Row 8 fixtures. |
| L933-1046 (section 4 harness definitions) | Keep `PRISTINE`, `mutate`, `_kills_*`, `_LIB_TOKENS`, `mutate_open`; drop the dark-gate arms of the `case` blocks; rebind the `mutate SELFTEST` "mutation that cannot land" check to `$EROWS`, placed in 6.4 beside H7. |
| L1048-1082 (B10 rows G4-G20) | Delete. |
| L1084-1102 (section 5 operands) | Delete (`ERG-operand` rows cover the shared operands; dark-only ones die with the gate). |
| L1104-1780 (sections 6, 6.1-6.5, 7) | Execute-gate assertion lines **byte-identical**. Removed: the `-sib` halves of `mutate_both` (rename to `mutate_shared`, 4-arg), their sibling fixture args, the `[G2] the sibling ...` line, the four `GATE_FN=inngest_host_dark_gate expect`/`mutate` rows in 6.5, the `GATE_FN=inngest_host_dark_gate; unset` pair, section 7's five recut-gate rows, the recut canary row and the recut default-path row. Comments that name "the sibling"/"recut gate" are reworded or listed as historical. |
| L1780-1872 floors | Recompute `_PRED_FLOOR`, the token floor (`_T_n -ge 11` holds: lib tokens = 11), and exact `_FLOOR` from a measured run; rewrite the itemised history comment to end at this change. |

**Ports (new section 6.6, execute gate, appended after 6.5).** Row 8 / 8b (the default-clock branch: a row stamped now clears, a 2 h-old row
is `stale_row`) is an unconditional REBIND of an existing test to the execute gate. The table below is conditional: each port lands only if
Phase 0's kill-set shows the shared line is killed solely by a deleted dark-gate case (CTO F3); it is the planning-time candidate set:

| Port | Shared behaviour | Dark-gate case it replaces |
|---|---|---|
| ERG-E5d | unparseable `dt` (`yesterday`) in the graded row refuses `unreadable` (integrated path through `_ihdg_epoch_from_dt`) | G3d |
| ERG-E3b / E3c | a row whose envelope `host` is wrong (or only `host_name` is wrong) is `wrong_host`, each field alone | G5 / G6 |
| ERG-M1 | rows in reverse file order are still sorted by `dt` | M1 |
| ERG-Row10 | an older dark row plus a newer serving row never join (`host_serving`) | Row 10 |
| ERG-torn | a malformed PROBE line does not swallow later valid rows | torn-line row |
| ERG-outer | outer-envelope `host_name` cannot launder a foreign row | outer-envelope row |
| ERG-E9d | `http_code=` present-but-empty refuses `unreadable` | M4d |
| ERG-M5 | a bare `*` in a message cannot supply an absent field from the CWD (`read -ra`, not word-splitting) | M5 |
| ERG-M7 | a single-encoded `raw` refuses `unreadable` (not `silent`) | M7 |
| ERG-I1 / I2 | duplicated-field injection and an embedded newline refuse `unreadable` | I1 / I2 |
| ERG-R2 | a non-probe line quoting the marker mid-string is not a probe row | R2 |

**Phase 2b — workflow-test fix** (same commit as the lib deletion — otherwise CI is red in between). In
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`, line-local at L2606-2619:
 - L2606-2609 comment: say the lib exports ONE entry point plus `_ihdg_*` / `_erg_*` helpers; the retired entry point is gone.
 - L2610-2611 assertion: the allowed token is stripped with a word-boundary `sed` before the forbidden-pattern grep, and the
 forbidden set becomes any other `inngest_[a-z_]*_gate`, `_ihdg_[a-z_]+`, `_erg_(emit|hb_newest|flag_class|[a-z_]*verdict)`; the
 `^#` comment filter stays. Strictly stronger than the base form (CTO F10).
 - L2617-2618 comment ("The recut gate's own tokens ... are not reachable from the execute gate"): reword; the lib now has only
 the execute gate's 11 tokens.
 - Mutation rows (on a scratch copy of `$BODY_SH`, via the file's existing `mutate_file` facility or an inline copy-and-sed): (1) a
 non-comment call to `inngest_host_dark_gate` appended; (2) a `_ihdg_field` call; (3) a same-line combo of the allowed name and a
 forbidden helper; (4) positive control — the allowed name alone passes. Rows 1-3 must redden the new assertion; the OLD assertion
 form must pass row 3 (proves the strengthening is real).

### Phase 3 — Stale prose (line-local)

3.1 `.github/workflows/cutover-inngest.yml` L201-206: rewrite the CORRECTED-2026-08-25 comment so it stops saying "No apply_target
 recuts /mnt/data today; the design for one is tracked in #7695". New text (verify each clause against the tree before writing): no
 `apply_target` exists that recuts `/mnt/data` (`inngest-volume-recut` was converted and then deleted by #8285 PR A/B; the plaintext
 volume is destroyed), a replace re-attaches the same volume so it does not clear the latch, and the in-repo latch remedies are the
 ones the script's own `latched` text names (`op=reflush`, #7777 — confirm it exists on base before citing it). Keep the sentence about
 narrowing `FLUSH_LATCH_SINCE` on a false premise.
3.2 `scripts/cutover-inngest.sh` L3437: "recovery from `aborted` is a /mnt/data recut via the inngest-host-replace window" becomes a
 statement true of the tree (no dispatch recuts; the latch is cleared only by the authorized-flush path `op=reflush`, or the store is
 re-created via the ADR-142 additive path). One comment line, line-local.
3.3 `scripts/cutover-inngest.sh` L2659 (CTO F2): replace the single sentence beginning "CORRECTED #6894: `apply_target=inngest-volume-recut`
 DOES exist (it shipped in #7695)..." and the earlier clause "or the inngest-volume-recut apply target when the whole volume goes"
 with text that says the target was retired by #8285; keep `op=reflush` and `op=luks-cutover` guidance and the `FLUSH_LATCH_SINCE`
 advice. No other byte of the file changes; `bash -n scripts/cutover-inngest.sh` must pass, and the cutover workflow test (which greps
 this script) must stay green.
3.4 `inngest-bootstrap.sh`, `cloud-init-inngest.yml`, `inngest-host.tf`, `vector.toml`, `inngest-cutover-flip.sh`,
 `inngest-server-flip-guard.sh`: **untouched** (CTO F9). Their dangling mentions are listed in the follow-up issue (Phase 8).

### Phase 4 — ADR-199 addendum (append-only)

Append `## Addendum — 2026-10-14 (#8316)` at the end of `ADR-199-...md`; no byte above changes (`git diff <base> -- <ADR-199> | grep -c '^-[^-]'`
is 0). Content, each statement checked against the tree:
- `inngest_host_dark_gate` and `_ihdg_finished_count` are deleted; `inngest_execute_registry_gate` and the shared helpers stay.
- Supersedes by name: the Status paragraph's claim that `apply_target=inngest-volume-recut` cannot reach `terraform plan` without
 `inngest_host_dark_gate` returning `dark`; commitment 1 ("Twenty predicates ... G1..G20"); the Consequences bullet "Until the host
 is replaced, every dispatch verdicts `stale_schema`" and the Consequences cost bullet "Twenty predicates plus two batteries" (L151); the former was written for the pre-cutover dark host; on a `done` host the common path was
 G19, and now there is no dispatch); and the 2026-10-09 sentence "the invariant ... is unchanged and still enforced by
 `inngest-host-dark-gate.sh` for `scripts/cutover-inngest.sh`" (overclaim — the execute gate grades "positively dark host" only).
- What is NOT reproduced by the survivor: store-empty (G11-G13), mount-devid pin (G14), live volume id pin (G17), #7674 followthrough
 (G18), cutover-flag allowlist at dispatch (G19), diagnostic-boot (G20). Any future destructive clearing target must reintroduce a
 measured-empty plus dark-host gate before it may plan a destroy.
- Historical, not edited: ADR-100 section 7 and its "Where the code is" paragraph; ADR-142 and ADR-225 path mentions.
- Recovery point: a main SHA containing the gate (the base SHA at the final rebase) and the line ranges in the header note.
- `status:` stays `accepted`; this addendum changes no front matter. #8316 stays open.

### Phase 5 — Derived baselines (last substantive commit, after the final `origin/main` sync)

5.1 `bash scripts/test-affected-kb-consumers.test.sh` (check mode). If red with "baseline differs", run `--write-baseline`, inspect that
 the diff is limited to this suite's rows, commit. Expected: row 222 persists (one hop via `cutover-inngest.sh`).
5.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh` (check mode). Rows 463 and 467 count relative operands in the two files;
 if they fall, `--write-baseline` and keep only those two row changes.
5.3 `python3 scripts/regenerate-shard-manifest.py --group light --incremental` **without `--write`**: expect no diff to
 `scripts/suite-durations.tsv` / `scripts/suite-shard-legs.tsv` (measured on base at planning time: `vs incumbent: 0 moved, 0 new, 0 no longer registered`, `durations delta: +0 floor row(s), -0 stale row(s)`). Any drift means the suite label or registration changed — stop and
 investigate. Never hand-edit; never touch `*.tsv.n`; no `--runs 5` rebalance.

### Phase 6 — Runbook edits and the residual sweep

6.1 `knowledge-base/engineering/operations/runbooks/inngest-server.md` L1481-1483: "the recut gate refuses as `stale_schema`" and "cannot answer the recut gate's question" become "the
 execute gate" (both clauses) (confirm E6 yields `stale_schema` on the execute step — `_ihdg_graded_row` does, suite
 `ERG-E6`). In place, minimal.
6.2 Same file: append one dated `Update (2026-10-14, #8316)` to the callout chain that ends near L2375: the dark-gate entry point is
 retired, the library stays for `scripts/cutover-inngest.sh`, recovery SHA, #8316 stays open. Leave older entries.
6.3 One-time sweep for the SUBJECT: `git grep -n -i -E 'inngest_host_dark_gate|_ihdg_finished_count|recut gate|Guard 2|dark[- ]gate'` over the repo, plus the G-number pattern `G(8|9|1[0-9]|20)\b`
 restricted to `knowledge-base/engineering/operations/runbooks/` (elsewhere it matches unrelated tokens), excluding ADRs other than the new addendum, `archive/`, `learnings/`, `legal/audits/`, `specs/archive` and this feature's own
 `plans/` + `specs/` files. Classify every hit `historical` or `live` in the PR body; fix every `live`. Known classified residuals:
 `inngest-bootstrap.sh` L704/L992 (comment-only, image-baked), ADR-100/142/225 (historical), the two legal audits (attestation-class).
6.4 Apply the "full class" rule from the retirement-cleanup sharp edge: also grep opaque identifiers the gate pinned — volume id
 `106261946` / `scsi-0HC_Volume_106261946` — across `scripts/`, fixtures and population files, and read hits (the suite's `VOLID`
 fixture is expected; nothing outside it should pin the deleted gate's inputs). Never touch volume `106443278`.

### Phase 7 — Differential mutation proof (the E1..E13 table)

7.1 Re-run the Phase 0 mutant list (keys by line content + occurrence index) against the branch lib with the branch suite. Output K_branch,
 S_branch.
7.2 Gate: every mutant in K_main whose line still exists on the branch must be in K_branch. Every mutant in S_branch that touches a
 shared line must have a ported test or a one-line written justification (also when it survived on main), recorded in the PR body.
7.3 Emit the **E1..E14 row-to-mutant table** (below) with the actual mutant id, control token and kill class for each row; the table
 goes in the PR body.

| Row | Predicate | Mutant (line neutralised) | Expected red case(s) |
|---|---|---|---|
| E1 | query rc numeric and 0 | `[[ "$query_rc" -eq 0 ]]` -> `:` | ERG-E1 rc 22 / 3 / 1 / 2 / 99 |
| E2 | undecodable bytes | `_ihdg_undecodable` guard -> false | ERG-E2 garbage file |
| E3 | silent / wrong_host | `_ihdg_refuse silent; return 1` -> `:` | ERG-E3 empty / blank-line / web-host rows |
| E4 | newest tie-free | tie check -> `if false` | ERG-E4 tie, reverse-order tie |
| E5 | row age bounded, not future | `-le "$max_row_age"` and `-ge 0` -> `:` | ERG-E5 3 h-old / future rows |
| E6 | schema exact | `==` -> `-ge`; delete the check | ERG-E6 schema 7 / 9 / absent |
| E7 | boot_id /proc UUID shape | regex line -> `:` | ERG-E7 unknown / hyphens / un-hyphenated |
| E8 | host_role dedicated | line -> `:` | ERG-E8 web / absent |
| E9 | http_code non-200 | line -> `:` | ERG-E9 200 / abc / absent |
| E10 | server_active != active (and != unknown) | line -> `:`; drop `!= "unknown"` | ERG-E10 active / unknown / empty / absent |
| E11 | probe-row cutover_flag allowlist | `*) printf 'unreadable'` -> `preflip`; drop `flushed` | ERG-E11 armed set / unknown / empty / absent |
| E12 | registry_fns coherence | line -> `:` | ERG-E12 numeric / 0 / absent |
| E13 | heartbeat fresh, same boot, pre-arm | `select($d._BOOT_ID == $b)` -> `select(true)`; drop `-le "$hb_max_age"` | ERG-E13 old boot / 2 h / future / web host / string / armed |
| E14 | probe row postdates the newest FSM transition | `-le "$row_epoch"` -> `:` | ERG-E14 transition after the row |

### Phase 8 — PR hygiene and handoff (no merge)

8.1 Commit trailer on every commit: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. No commit body may contain a closing
 keyword followed by an issue reference (scan with `git log <base>..HEAD --format=%B | grep -iE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[: ]+(#|GH-)[0-9]+'`
 and the `auto-closes` form; triage any match by hand).
8.2 PR #10268: title `chore(inngest): retire the suite-only inngest_host_dark_gate entry point (Ref #8316)`; body uses `Ref #8316` only,
 carries the E1..E14 table, the classified residual sweep, the follow-up issue number, the base/recovery SHA, and ends with the line
 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. After every body edit: `gh pr view 10268 --json closingIssuesReferences --jq '.closingIssuesReferences | length'` must print `0`.
8.3 File one follow-up issue (milestone from `knowledge-base/product/roadmap.md`): "prune probe fields consumed only by the retired
 dark gate (`data_mount_devid`, `data_mount_base`, `data_bytes`, `flush_latched`, `redis_keys`, `redis_key_patterns`, ...) and the
 two stale comments in `inngest-bootstrap.sh` L704/L992 on the next planned `probe_schema` bump". Re-evaluation trigger: the next
 planned host-replace window. Do not file it during planning (an external write); file it at work time and cite it in the PR.
8.4 No rename in the diff (`git diff -M --name-status <base>...HEAD` shows no `R`), so `secret-scan-allow-rename` is not needed. If rename-guard
 trips anyway, stop and ask.
8.5 CI: run only `TEST_GROUP=affected` / targeted suites locally; CI is authority. Report `plugins/soleur/scripts/ci-head-verdict.sh verdict 10268`
 (`never-ready` / `pending-full` means the `test` row is the draft run's), then **stop and ask** before marking ready or queuing
 auto-merge.
8.6 Final report includes the #10081 status: re-read `gh pr view 10081 --json state,isDraft,labels` (planning-time: OPEN, draft, label
 `parked`, last updated 2026-10-12) and state whether any `inngest-host-replace` dispatch ran since; this PR plants no `user_data`
 drift (no cloud-init, `inngest-host.tf` or image-baked file is touched), so it neither unparks nor contradicts #10081.

## Files to Edit

- `tests/scripts/lib/inngest-host-dark-gate.sh` — delete L725-1060 and L387-411; rewrite header L1-178.
- `tests/scripts/test-inngest-host-dark-gate.sh` — trim, rebind harness, port, recompute floors (Phase 2).
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — L2606-2619 only (comments, one strengthened assertion, mutation rows).
- `.github/workflows/cutover-inngest.yml` — L201-206 comment only.
- `scripts/cutover-inngest.sh` — L2659 (one sentence) and L3437 (one comment line).
- `knowledge-base/engineering/architecture/decisions/ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md` — append addendum.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — L1481-1483 reword; append one Update.
- `scripts/test-affected-kb-consumers.baseline.txt`, `plugins/soleur/test/fixture-relative-assert.baseline.txt` — only if their own checkers report drift.
- Pipeline artifacts: this plan, `specs/feat-one-shot-8316-retire-inngest-host-dark-gate/{tasks.md,decision-challenges.md}`, and any generated `knowledge-base/INDEX.md` / `session-state.md` the pipeline writes.

## Files to Create

None.

## Files NOT to Touch (diff-against-merge-base ACs)

`apps/web-platform/infra/inngest-bootstrap.sh`, `cloud-init-inngest.yml`, `inngest-host.tf`, `vector.toml`, `inngest-cutover-flip.sh`,
`inngest-server-flip-guard.sh`; `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md` and
`inngest-aof-destruction-record.md`; ADR-100, ADR-142, ADR-225; `knowledge-base/engineering/architecture/diagrams/*`;
`scripts/test-all.sh`; `.github/workflows/infra-validation.yml`; `scripts/lib/inngest-probe-row.test.sh`; every `*.tsv.n`.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-199** by appending a dated retirement addendum (Phase 4). No new ADR and no ordinal is claimed, so there is no collision
exposure. The decision recorded: the measured-empty-plus-dark-host gate for destructive clearance of the live store is retired with its
only dispatch; the surviving gate is the cutover execute gate's positive-darkness check; the invariant is restated as a requirement
on any future destructive clearing target, not as a currently enforced property.

### C4 views
No C4 change. Read in full: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Enumerated for this change:
(a) external human actors — none added or removed (the founder/operator actor is unchanged); (b) external systems — GitHub, Better Stack,
Doppler, Hetzner, `inngestReleases` already modeled, none gains or loses an edge from a test-library deletion; (c) containers/data
stores — `inngest`, `inngestRedis`, `inngestPostgres` unchanged; `model.c4` names only `inngest_execute_registry_gate` (the
`github -> betterstack` edge at L845 and the `inngest -> betterstack` edge at L740) and the `inngestRedis` description is already post-#8285;
(d) actor-to-surface access relationships — unchanged. Cardinalities embedded in edge prose are guarded by
`plugins/soleur/test/c4-count-parity.test.sh`, which must stay green (AC13).

### Sequencing
The addendum describes a state that is true on merge; nothing is deferred.

## Guard Contract

### Guard 1 — workflow census: the cutover script reaches the lib only through the one live entry point

**Property.** No non-comment line of `scripts/cutover-inngest.sh` calls any library function other than `inngest_execute_registry_gate`.

**Assembly.** The population is every non-comment line of `scripts/cutover-inngest.sh` (all arms, top-level functions and the `*)`
catch-all), quantified over the full name families `inngest_*_gate`, `_ihdg_*` and `_erg_*`; the chokepoint is the single assertion at
`cutover-inngest-workflow.test.sh` L2610 after the allowed token is stripped from each line. The sibling consumer-count assertions
(`_gate_census`, `_gate_total`) stay as they are and pin the allowed name's call count to 2.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append a non-comment `inngest_host_dark_gate --rows-file x` line to a scratch copy of the script | RED |
| 2 | Append a non-comment `_ihdg_field "$m" boot_id` line (a shared helper called directly) | RED |
| 3 | Add a SECOND member after a compliant first by APPENDING `&& _ihdg_graded_row ...` to an existing `inngest_execute_registry_gate` call line (call count stays 2, so `_gate_total` does not mask it) | RED on this assertion (the base form passes it: the trailing `grep -v` drops the whole line) |
| 4 | Own dispatch: a dedicated non-vacuity row asserts the scanned script has > 0 non-comment lines; mutate it by scanning an empty file | RED by that dedicated row (an empty scan alone would make the `! grep` pass) |

**Harness rows.** The same row-3 mutant must PASS the OLD `grep -v` form (proving the harness distinguishes the two forms) and RED the new one. Must-PASS non-canonical input: a script copy whose only
gate reference is a `#` comment naming `inngest_host_dark_gate`, and a copy with `inngest_execute_registry_gate` alone on a line.

**Anchor.** The census compares the script's text to a pattern, with no stored value; the anchor is the allowed name's call-count rows
(`_gate_census`, `_gate_total`), which a single diff cannot satisfy by editing only this assertion.

### Guard 2 — the suite's exact-count floors and token coverage

**Property.** The suite exits non-zero if any execute-gate assertion, predicate case or lib verdict token stops being exercised.

**Assembly.** The floors read from the suite's own counters (`passes + fails` for `_FLOOR`, `_seen_predicates` for `_PRED_FLOOR`,
`_seen_tokens` against the lib-derived token set `_T` for token coverage) and from the wrappers `expect`, `predicate`, `mutate`;
members are every `expect`/`predicate`/`mutate*` call in sections 6, 6.6 and 7. The chokepoints are the three wrappers.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one `ERG-E4` case (not a whole battery) | RED by exact `_FLOOR` (`-ne`, no slack) |
| 2 | Replace `predicate()` body with a bare `pass` (counters keep moving) | RED by the moved 0c self-test |
| 3 | Add a second `predicate ERG-E1 ...` call (dup id) | no change to the distinct-predicate set — floor not inflated (existing `ERG-DUPTEST`) |
| 4 | Drop the only assertion of `fsm_silent` | RED by token coverage (`_T_hit -ne _T_n`) |
| 5 | Own dispatch: make `gate()` call the wrong function name | RED by `ERG SELF-TEST` (a serving row stops failing a `dark` expectation) |

**Harness rows.** Suite edit that must go RED: lower `_FLOOR` by one — the run must report `STALE FLOOR`. Must-PASS non-canonical input:
the `H5`/`H5b`/`H5c` rows in 6.2 (non-canonical dark rows) — already present, unchanged.

**Anchor.** The floors are literals in the same file as the assertions; a weakening that edits both passes. The outside anchor is the
differential mutation run (Phase 7), whose kill-set reference is built from the base tree and compared in the PR body, plus CI.

The differential mutation check (Phase 7) is a verification procedure, not committed code, so it carries no Guard Contract entry; its
non-vacuity floor (mutant count >= 100, a lost port flips a mutant to a survivor, K_main computed from a separate base tree) is stated in
Phase 0 and Phase 7.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly on a user surface; the failure mode is a mis-graded cutover guard
 (`inngest_execute_registry_gate`) letting the P0 cutover proceed while a prod scheduler can double-fire user reminders, or a red CI that
 blocks unrelated merges. The gate's code is byte-identical by construction (Phase 1.5), which is the control.
- **If this leaks, the user's workflow is exposed via:** no data path is touched; no secret, credential, log row or user data is read or
 written by this change.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`, because the live gate's source bytes do not change and the
 deleted entry point has had no caller since #8285 PR A.

threshold: none, reason: the diff touches `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (a test file under a sensitive path) and no production behaviour — edits are assertion text, comments and deletions, and the only edit to a production script is two prose strings.

## Observability

Skipped by the Phase 2.9 skip clause: the plan is delete-only plus comment, test and documentation edits. It adds no code or
infrastructure surface, no emitted signal, and removes none (the probe emitter, heartbeat and Better Stack rows are untouched; the
execute gate's `::notice::`/`::error::` output is unchanged except one sentence of operator prose at `cutover-inngest.sh` L2659).

## Encryption Posture

Skipped: the change introduces no persistent store and no cross-component connection.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings F1-F14 (decision-challenges.md): append-only ADR addendum; fix the live false `::error::` claim in-PR; port-before-
delete with a measured differential mutation run; no emitter or image-baked edits; strengthen the census assertion; rename `mutate_both`;
runbook fix plus append; classified residual sweep. Legal audit records untouched. No UI surface (no Product/UX gate), no regulated
data surface (no GDPR gate), no new infrastructure (no IaC gate), no encryption surface.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "delete the suite-only `inngest_host_dark_gate` entry point (tests/scripts/lib/inngest-host-dark-gate.sh, function at ~L725-1145) plus helpers used ONLY by it" [brief] | Phase 1.1, 1.2 | mapped |
| 2 | "trim the matching suite sections 1-5 of tests/scripts/test-inngest-host-dark-gate.sh" [brief] | Phase 2 disposition map | mapped |
| 3 | "KEEP the shared `_ihdg_*` helpers, `_ihdg_graded_row`, `_erg_*` and `inngest_execute_registry_gate` ... and suite sections 6 and 7 unchanged and passing" [brief] | Phase 1.5 (byte-identical extracts), Phase 2 (line-diff rule), AC2-AC4 | mapped |
| 4 | "Keep file/suite names unless the header rewrite demands otherwise" [brief] | Cut List (no rename), Phase 8.4, AC10 | mapped |
| 5 | "rewrite the lib header so it no longer says the entry point is kept pending the retire-or-keep decision" [brief] | Phase 1.3 | mapped |
| 6 | "(a) reconcile stale prose: .github/workflows/cutover-inngest.yml ~L204 ..., scripts/cutover-inngest.sh ~L3437 ..., ADR-199 Consequences paragraph" [brief] | Phase 3.1, 3.2, Phase 4 | mapped |
| 7 | "verify whether the \"No apply_target recuts THIS volume yet\" error text and model.c4 inngestRedis description are already fixed on main ... and leave them if so" [brief] | Research Reconciliation rows 7-8; Phase 3.3 (the adjacent false claim at L2659, issue #8316 list item "the G3.7 `latched` refusal's `::error::` text") | mapped |
| 8 | "(b) amend ADR-199 with a dated retirement note (append, change nothing above)" [brief] | Phase 4 | mapped |
| 9 | "(c) update derived baselines: scripts/test-affected-kb-consumers.baseline.txt ..., scripts/suite-durations.tsv and suite-shard-legs.tsv (do not hand-edit stray *.tsv.n files" [brief] | Phase 5 | mapped |
| 10 | "(d) fix apps/web-platform/infra/cutover-inngest-workflow.test.sh L2607-2611 and any other test that names the deleted function so it still asserts what it meant to (do not weaken it)" [brief] | Phase 2b, Guard 1 | mapped |
| 11 | "(e) grep the SUBJECT (inngest_host_dark_gate, G8..G20, \"dark gate\") across runbooks for live claims about the retired mechanism" [brief] | Phase 6 | mapped |
| 12 | "Run a mutation check proving the execute gate's E1..E13 rows still bite after the deletion" [brief] | Phase 7 | mapped |
| 13 | "Leave knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md untouched (attestation-class, CTO ruling)" [brief] | Files NOT to Touch | mapped |
| 14 | "Ref #8316 only, NEVER a closing keyword in PR body, title or commits; assert closingIssuesReferences is [] after every body edit" [brief] | Phase 8.1, 8.2, AC9 | mapped |
| 15 | "Do NOT queue auto-merge or merge: stop with the PR ready and CI verdict reported, and ask me first" [brief] | Phase 8.5, decision row A1 | mapped |
| 16 | "Add the secret-scan-allow-rename label only if rename-guard trips and ask me first" [brief] | Phase 8.4, decision row A2 | mapped |
| 17 | "Report the #10081 park/no-replace status at the end" [brief] | Phase 8.6 | mapped |
| 18 | "keep our edits to those files minimal and line-local to limit conflicts" [brief] | Phase 3, Phase 2b, AC11 | mapped |
| 19 | "Locally run only TEST_GROUP=affected or targeted suites; CI is authority" [brief] | Phase 8.5, Phase 0.3, Phase 7 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Delete the entry point and `_ihdg_finished_count` | "delete the suite-only `inngest_host_dark_gate` entry point" (asks 1) | asked |
| Rewrite the lib header | "rewrite the lib header" (ask 5) | asked |
| Trim suite sections 1-5 | "trim the matching suite sections 1-5" (ask 2) | asked |
| Port new section 6.6 assertions | — | inferred — justification: asks 3 and 10 require the suite to keep asserting what it meant to, and a deleted assertion that was a shared helper's only test is a coverage loss (plan sharp edge "name the mutation it kills"; CTO F3) |
| Rename `mutate_both` to `mutate_shared`, rebind `GATE_FN` default | — | inferred — justification: removing the sibling entry point makes the default dispatch and the "both" name false; leaving them breaks every execute-gate row or keeps a misleading name (CTO F11) |
| Move the 0c predicate self-test, rebind the `mutate` self-test | — | inferred — justification: they exercise the harness through the deleted gate; dropping them would let a neutered wrapper keep the suite green (the base file's own section 0c records exactly that) |
| Strengthen the census assertion (word-boundary strip, widened name family) | "so it still asserts what it meant to (do not weaken it)" (ask 10) | asked |
| Fix `cutover-inngest.sh` L2659 | "the G3.7 `latched` refusal's `::error::` text" (issue #8316 stale-prose list) | asked |
| Fix runbook L1481-1483 and append one Update | "across runbooks for live claims about the retired mechanism" (ask 11) | asked |
| Regenerate `fixture-relative-assert.baseline.txt` if it drifts | "update derived baselines" (ask 9) | asked |
| Differential mutation run, E1..E14 table | "Run a mutation check proving the execute gate's E1..E13 rows still bite" (ask 12) | asked |
| Follow-up issue for unconsumed emitter fields and bootstrap comments | — | inferred — justification: the plan skill's deferral-tracking rule (a deferral without an issue is invisible) and CTO F8/F9; not filed during planning |
| Grep the gate's pinned opaque id (Phase 6.4) | — | inferred — justification: plan sharp edge "a retirement census grepped by NAME misses consumers that pin the thing by ID"; one grep, expected to hit only the suite's own `VOLID` fixture |
| Classified residual sweep in the PR body | "grep the SUBJECT" (ask 11) | asked |

### Split Assessment

- Subsystems touched: 6 — `tests`, `apps/web-platform`, `.github`, `scripts`, `knowledge-base`, `plugins`
- Planned files: 10 | Estimated changed lines: ~2200 (about 1800 deletions, about 400 additions)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the workflow-test assertion must change in the same commit as the deletion (otherwise CI is red between PRs),
 four of the six roots are one-sentence prose edits or regenerated baselines, and the line count is dominated by deletion. Decision row P2.

## Acceptance Criteria

Pre-merge (PR):

- [ ] AC1. `grep -c '^inngest_host_dark_gate()' tests/scripts/lib/inngest-host-dark-gate.sh` prints `0`; `grep -c '_ihdg_finished_count'` over the lib prints `0`; `bash -n` passes; sourcing the lib defines `inngest_execute_registry_gate` and does not define `inngest_host_dark_gate` (`declare -F`).
- [ ] AC2. Kept-code invariance: the awk extracts of `_ihdg_*` (all except `_ihdg_finished_count`), `_erg_*`, `inngest_execute_registry_gate`, `_IHDG_*` assignments are byte-identical between `git merge-base origin/main HEAD` and HEAD. Command: the Phase 1.5 script, exit 0.
- [ ] AC3. `bash tests/scripts/test-inngest-host-dark-gate.sh` exits 0 with `0 failed`; the printed anti-vacuity line says `exactly N assertions` with `_FLOOR` set to that measured N (not hand-derived); drop-one floor and token coverage print `ok` with token coverage `11/11` and `dark` asserted >= 2x.
- [ ] AC4. Sections 6/7 line-diff rule: diff the base and branch text of the base section-6/7 region; every removed or changed line is one of (a) a `-sib` / `GATE_FN=inngest_host_dark_gate` / recut-gate row, (b) a trailing sibling arg removed from a `mutate_shared` call, (d) the call renamed `mutate_both` -> `mutate_shared`, (c) a comment reworded for the sibling. Execute-gate fixtures and expected tokens show zero diff. `grep -c 'mutate_both' tests/scripts/test-inngest-host-dark-gate.sh` prints `0`; `grep -c 'inngest_host_dark_gate' tests/scripts/test-inngest-host-dark-gate.sh` counts only hits inside retirement-note comments (each listed in the PR body); zero code hits.
- [ ] AC5. Differential mutation run (Phase 7): every mutant in K_main whose line survives on the branch is in K_branch; every shared-line survivor has a port or a written justification; the E1..E14 table is in the PR body with real mutant ids and kill classes; mutant count >= the measured base mutant count recorded in Phase 0 (a generator that silently emits fewer fails the procedure).
- [ ] AC6. `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0; THIS assertion (not the whole file) reddens on mutation rows 1-3, the positive control (allowed name alone) passes, row 4 reddens the dedicated non-vacuity row, and the base form is shown to pass row 3.
- [ ] AC7. Stale prose: `grep -n 'recuts /mnt/data today' .github/workflows/cutover-inngest.yml` and `grep -n 'recovery from .aborted. is a /mnt/data recut' scripts/cutover-inngest.sh` are empty; `grep -c 'DOES exist (it shipped in #7695)' scripts/cutover-inngest.sh` and `grep -c 'inngest-volume-recut apply target when' scripts/cutover-inngest.sh` print `0`; every sentence the diff ADDS in these three places cites a tree fact checked in Phase 3 (listed in the PR body); `bash -n scripts/cutover-inngest.sh` passes.
- [ ] AC8. ADR-199 append-only: `git diff <base> -- knowledge-base/engineering/architecture/decisions/ADR-199-*.md | grep -c '^-[^-]'` prints `0`; the addendum names EACH superseded passage (Status claim, commitment 1, Consequences "every dispatch" bullet, Consequences "Twenty predicates plus two batteries" cost bullet at L151, the 2026-10-09 sentence) and the not-reproduced predicate list; front matter unchanged.
- [ ] AC9. PR hygiene: `gh pr view 10268 --json closingIssuesReferences --jq '.closingIssuesReferences | length'` prints `0` after every body edit; `git log <base>..HEAD --format=%B` has no closing-keyword-plus-reference and no `auto-closes`; every commit ends with the `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` trailer; the PR body ends with the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line and names #8316 only as `Ref #8316`.
- [ ] AC10. No rename: `git diff -M --name-status <base>...HEAD` has no `R` line; the lib and suite paths are unchanged; `secret-scan-allow-rename` not added.
- [ ] AC11. Diff scope and no-touch: `git diff --name-only <merge-base>...HEAD` is a subset of Files to Edit plus the pipeline-written files (`knowledge-base/INDEX.md`, `specs/<branch>/session-state.md`, this plan, tasks.md, decision-challenges.md); `git diff --quiet <merge-base> -- <each Files-NOT-to-Touch path>` exits 0 (merge-base, not moving tip); the hunk map vs PR #10257 still shows no overlapping hunks (re-read `gh pr diff 10257` hunk headers before the final push).
- [ ] AC12. Baselines: `bash scripts/test-affected-kb-consumers.test.sh` and `bash plugins/soleur/test/fixture-relative-assert.test.sh` exit 0; `python3 scripts/regenerate-shard-manifest.py --group light --incremental` (no `--write`) reports no change to the two TSVs; `git diff --stat` shows neither TSV nor any `*.tsv.n` changed.
- [ ] AC13. `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 (backs the "no C4 impact" conclusion); `python3 scripts/lint-guard-contract.py <this plan>` exits 0. Orphan-suite, shard-totality and infra-human-steps lints are left to CI.
- [ ] AC14. Residual sweep: the classified-hits list (Phase 6.3) is in the PR body; zero hits classified live remain; `grep -c 'recut gate' knowledge-base/engineering/operations/runbooks/inngest-server.md` shows no live-position hit; the follow-up issue is filed and cited.
- [ ] AC15. CI verdict reported from `plugins/soleur/scripts/ci-head-verdict.sh verdict 10268` (not from a draft-run `test` row); no merge and no auto-merge queued; the report asks for authorization.

Post-merge (operator): none. The merge is not authorized by this plan (decision row A1).

## Test Scenarios

- Given the base suite and the branch suite, when each mutant of a shared guard line is applied to each, then every base kill is a branch kill (unit; Phase 7).
- Given a probe row whose `dt` is `yesterday`, when `inngest_execute_registry_gate` grades it, then the verdict is `unreadable` (unit; ERG-E5d).
- Given a scratch `cutover-inngest.sh` with `inngest_execute_registry_gate ... && _ihdg_graded_row ...` on one line, when the census runs, then it is RED (unit; Guard 1 row 3).
- Given the lib with `inngest_host_dark_gate` removed, when `scripts/cutover-inngest.sh op=execute` step 2.0 sources it and calls the execute gate, then the call resolves and returns one of the 11 tokens (integration; the workflow test's wiring rows).
- Given the PR body edited three times, when `closingIssuesReferences` is read after each, then it is `[]` (integration; Phase 8.2).
- Given a comment-only mutation of the execute gate (H7), when `mutate_shared` runs, then it reports the verdict unchanged (unit; known negative, unchanged).

## Success Metrics

The lib exposes one entry point. The measurable outcome is AC3 + AC5: suite green with exact floors, and kill-set(branch) a superset of kill-set(main). No numeric size target is asserted.

## Dependencies & Risks

- **Coverage loss (highest risk).** Deleting ~1500 suite lines can silently drop a shared-helper test. Mitigation: Phase 0/7 differential run, ports, and AC5; the Phase 2 port table is a candidate list, not a ceiling.
- **Exact-count floors.** Any later added or removed assertion moves `_FLOOR`; the failure message dictates the number. Recompute last, after ports settle.
- **Conflict with PR #10257** in three shared files. Mitigation: line-local edits, hunk map in AC11; if #10257 merges first, rebase (no force).
- **Equivalent mutants** inflate S_branch. Mitigation: each shared-line survivor needs a one-line justification; comment-only and no-op edits are the control class.
- **`mutate()`'s lib-token check** (`_LIB_TOKENS`) shrinks to the 11 execute tokens; a mutant must still produce one of them. Verified by the H7 known-negative and the canary.
- **Attestation-class records** keep citing the lib path: still valid, the file exists.
- **Residual:** probe fields and two bootstrap comments are left, tracked in the follow-up issue (decision rows F8, F9).
- **#10081** (parked host-replace PR) is untouched; this PR plants no `user_data` drift.

## References & Research

- Issue #8316; PRs #8248 (merged), #8285 PR A/B, #10257 (open, overlapping files), #10081 (parked), #10268 (this PR).
- ADR-199, ADR-100 section 7, ADR-142 addenda, ADR-225; `knowledge-base/project/learnings/2026-10-12-retiring-a-probe-by-file-list-left-a-derived-baseline-row-and-live-runbook-claims.md`.
- Decision record: `knowledge-base/project/specs/feat-one-shot-8316-retire-inngest-host-dark-gate/decision-challenges.md`.
