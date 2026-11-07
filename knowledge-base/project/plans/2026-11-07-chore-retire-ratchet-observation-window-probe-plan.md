---
title: "chore: retire the #10865 observation-window soak probe (script, test rows, census re-pins, doc reconciliation)"
type: chore
date: 2026-11-07
slug: retire-ratchet-observation-window-probe
branch: feat-one-shot-retire-10865-window-probe
issue: 10865
domain: engineering
priority: p3-low
lane: cross-domain
brand_survival_threshold: none
---

# chore: retire the #10865 observation-window soak probe

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). There is no spec.md for this branch.

## Overview

Tracker #10865 ("ci: S4 PR3a observation window for the advisory affected-index-ratchet job") is CLOSED and its `soleur:followthrough` directive was removed: the observation window certified PASS on 2026-11-07. The probe's own `RETIREMENT:` clause (`scripts/followthroughs/ratchet-observation-window-10865.sh:77-79`) prescribes deleting the script and its test rows in `plugins/soleur/test/ci-pr-affected-replay.test.sh` (the "ratchet observation window" section). Per the followthrough convention (`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, "the header is a seed"), a live re-census of `ratchet-observation-window` / `10865` finds a larger footprint than the clause's three sites: suite census pins (`DECLARED_TOTAL`, `FLOOR_ASSERTIONS`, an `OW_SITES` floor), three registered `--rows` range splits, declared-edge arrays in `scripts/lib/test-affected-paths.sh`, accept rows in `scripts/ci-pr-affected-audit.accept.tsv`, a `pull-requests: read` permission comment in the sweeper workflow that says "Retire this line with the probe", and runbook references. Every live reference must be deleted, re-pinned, or dispositioned in the same commit so no dead-path ratchet trips.

## Problem Statement / Motivation

A retired probe that survives only as dead references is worse than a live one: the replay suite executes `$OW_SCRIPT` unconditionally (the section would fail at fixture setup), the suite's end-of-file census asserts `OW_SITES >= 126` and `SITES_MUTATE + OW_SITES == DECLARED_TOTAL`, the `--rows` range split tiles `1..DECLARED_TOTAL` across three registered arms in two files, the ratchet's stale-accept check exits 2 (`census-degraded`) on an accept row whose pair is no longer emitted, and `scripts/lib/test-affected-paths.sh` declares edges to a path that would no longer exist. Each of these reddens CI on its own. The deletion must land as one atomic change covering the script, the test rows, every census/pin the rows fed, and the doc references the retirement clause named.

## Proposed Solution

One PR, one commit-class change: delete the probe, excise its test section and OW-only helpers, re-pin the suite's three census values and the three `--rows` arm ranges in the same edit, prune the accept rows the ratchet reports stale, remove the declared-edge entries, re-attribute the sweeper workflow's `pull-requests: read` comment to the probes that still need the scope (the permission itself stays — see Decisions), and add a dated past-tense retirement note to the activation runbook. Verify locally with the suite, the shard-totality gate, the sweeper suite, `lint-followthrough-varq-ban.sh`, `lint-orphan-test-suites.sh`, the ratchet's own `--print-baseline`, and a residual-reference grep.

## Technical Considerations

### Live-code footprint (re-census, 2026-11-07 — authoritative)

| # | Site | Disposition |
|---|------|-------------|
| 1 | `scripts/followthroughs/ratchet-observation-window-10865.sh` | DELETE the file (`git rm`) |
| 2 | `plugins/soleur/test/ci-pr-affected-replay.test.sh` lines ~3020–3947 — the `# ---- the observation-window probe of #10865` section including the `# ---- the E2BIG fix` (3297) and `# ---- the merged-PR resolution` (3536) sub-sections: every `ow_*` helper, `OW_*` var, `ow_mutate` driver + its 129 call sites, `row_ow_*` definitions and their `chk` calls | DELETE the contiguous block (ends at the `# == glob-rate` banner ~3948; `chk` calls for `row_ow_parity` at 3946-3947 are the last OW lines) |
| 3 | Same file, `row_ow_parity()` definition ~line 2810 (defined in the earlier "advisory job" section, called only from the OW section — orphaned by #2) | DELETE the function |
| 4 | Same file, `nosleep` stub creation + comment ~lines 202–204 (`$BIN/nosleep`, used only by `ow_probe*` at 3172/3176) | DELETE |
| 5 | Same file, line 77 `DECLARED_TOTAL=602` | Re-pin to the post-deletion `grep -c '^mutate '` count (expected 473); update the comment |
| 6 | Same file, line ~5242 `FLOOR_ASSERTIONS=1313` | Re-measure as the new full-run pass count; rewrite the comment dropping the OW terms ("57 observation-window fix", "merged-PR resolution rounds", "+ 6 observation-window deadline-model", "+ 6 observation-window review-round rows", "+ 6 wall-discharge rows") |
| 7 | Same file, epilogue ~5241–5260: `OW_SITES=`, `MUT_RUN + OW_MUT_RUN != EXECUTED`, `SITES_MUTATE + OW_SITES != DECLARED_TOTAL`, `OW_SITES < 126 \|\| OW_MUT_KILLED != OW_MUT_RUN` | Remove the OW terms: `OW_SITES` line deleted; reconciliation becomes `MUT_RUN != EXECUTED` and `SITES_MUTATE != DECLARED_TOTAL`; the `OW_SITES < 126` floor block deleted |
| 8 | `scripts/test-all.sh:5627–5629` — `run_suite` arms `--rows 1-193`, `--rows 194-386`, `--rows 387-602` | Re-split to tile `1..<new DECLARED_TOTAL>` in the SAME commit (the in-file contract: "A DECLARED_TOTAL bump and the registered-range re-split land in the same commit"); keep three arms, roughly equal site counts |
| 9 | `scripts/ci-oracle-lane-suites.txt:45–47` — same three `--rows` ranges | Re-split identically to #8 (must agree with test-all.sh — `scripts-shard-totality.test.sh` asserts the union tiles `1..DECLARED_TOTAL`) |
| 10 | `scripts/lib/test-affected-paths.sh:4882,4891,4900` — `"scripts/followthroughs/ratchet-observation-window-10865.sh"` in `AFFECTED_PLUGINS_SOLEUR_TEST_CI_PR_AFFECTED_REPLAY_{A,B,C}_PATHS`, plus the comment at ~4872–4875 saying the suite "EXECUTEs the observation-window probe under a stub gh" | Remove the three entries; rewrite the comment |
| 11 | `scripts/ci-pr-affected-audit.accept.tsv` — 12 rows citing the probe's ORACLE array (`ratchet-observation-window-10865.sh:91`) at lines ~969–1116 (4 oracle paths × 3 replay arms) | Prune every row the ratchet reports stale after the section deletion — the 12 named rows at minimum; a stale accept row is `census-degraded` (exit 2). Re-derive by running the audit, not by counting rows by hand |
| 12 | `.github/workflows/scheduled-followthrough-sweeper.yml:55–58` — `pull-requests: read` with comment `(#10865) the observation-window probe reads the s4-drain label list… Retire this line with the probe.` | KEEP the permission — other live probes need it (`ci-push-dedupe-soak-9512.sh` reads the same mixed `issues?labels=follow-through` endpoint; `ci-draft-light-soak-9728.sh`, `pr-battery-gate-saving-9323.sh`, `git-data-boot-poll-8178.sh`, `cron-machinery-soak-9272.sh`, `inngest-cli-apply-window-7463.sh`, `resolve-pr-for-sha-extract-8279.sh` read `/pulls`). Rewrite the comment to attribute the surviving consumers and drop the retire note |
| 13 | `scripts/sweep-followthroughs.test.sh:1735` — comment `The probe's restart floor needs the scope (#10865).` on `wf_pr_read` (PERM-1 pin) | KEEP the PERM-1 pin (the permission stays); update the comment to name a surviving consumer |

### Doc references (historical-record disposition)

| # | Site | Disposition |
|---|------|-------------|
| 14 | `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:253` — "The window that PR3b waits for is enforced by the follow-through probe `scripts/followthroughs/ratchet-observation-window-10865.sh` (tracker #10865). Its rules:" | KEEP a historical mention, past-tense and dated: convert the sentence to "was enforced by … retired <date> (this PR); the rules below are the record of what the window certified." The rules text stays — PR3b's entry conditions (ADR-276 amendment item 9) cite the window's record. Line 230's "the probe enforces that itself (#10949)" falls under the same note |
| 15 | ADR-276 (`knowledge-base/engineering/architecture/decisions/ADR-276-…md`) — the PR3a amendment and 2026-11-02/03 ceiling amendments reference #10865 by issue number only; the literal script path does NOT appear (verified: `grep -n 'ratchet-observation\|followthroughs/'` — no hit) | NO EDIT. The amendments are dated historical narrative in an append-only record; the rollback recipe that names "the follow-through probe and its rows" stays accurate |
| 16 | `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md:9,119,137` — names #10865 as the evidence-attachment tracker | LEAVE. A closed tracker still accepts comments and remains the window's record; the reference is to the issue, not the script. (Recorded as a decision row.) |
| 17 | `knowledge-base/project/learnings/*`, `plugins/soleur/skills/*/references/*.md`, `knowledge-base/project/{plans,specs}/archive/**`, issue #10865's own body | LEAVE — point-in-time records |
| 18 | `scripts/pr-fanout-ledger.txt` + `plugins/soleur/test/pr-fanout-ledger.test.sh` | Unaffected — the ledger bounds PR-push WORKFLOW counts; a script deletion is out of scope (verified: no probe row, no script census) |

### Verification commands (local, before push)

- `grep -c '^ow_mutate ' plugins/soleur/test/ci-pr-affected-replay.test.sh` → 0; `grep -c '^mutate '` → new DECLARED_TOTAL
- `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (full run — prints the new FLOOR_ASSERTIONS count; or run all three new `--rows` arms)
- `bash plugins/soleur/test/scripts-shard-totality.test.sh` — the `--rows` union tiles `1..DECLARED_TOTAL`
- `bash scripts/sweep-followthroughs.test.sh` — PERM-1 still green (permission kept)
- `bash scripts/lint-followthrough-varq-ban.sh` — repo-relative literals in `scripts/followthroughs/*.sh` still resolve (learning 2026-11-05)
- `bash scripts/lint-orphan-test-suites.sh` — no orphan/double-coverage created
- `python3 -I scripts/ci-pr-affected-replay.py --print-baseline` — exits 0 after accept-row pruning (a stale row exits 2 `census-degraded`)
- `rg -n 'ratchet-observation-window-10865' scripts/ plugins/soleur/test/ .claude/hooks/ .github/workflows/` → zero hits

### Gates evaluated

- **Observability (2.9):** skipped — deletion-only change; no Files-to-Edit under `apps/*/server|src|infra` or `plugins/*/scripts`, no new runtime surface.
- **IaC (2.8), Encryption (2.11), Task Design (2.9.3), GDPR (2.7):** skipped — no new infrastructure, store, autonomous-task surface, or regulated-data surface.
- **Architecture (2.10):** skipped — the retirement is the machinery's own prescribed lifecycle step, not an architectural decision; ADR-276 is append-only and untouched.
- **Guard Contract (2.12):** skipped — the deliverable contains no new guard; the census re-pins are bookkeeping inside an existing suite, not a control.
- **Soak enrollment (2.9.1):** skipped — no new time-gated close criterion is created.
- **Scoped advisor consult (4.5) and plan-review panel:** skipped — no Task/Agent tool in this pipeline subagent context; deepen-plan follows.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a red `test-scripts` shard on the next PR if a census pin or accept row is missed.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure — the probe is read-only GH Actions metadata; the sweeper keeps `pull-requests: read`, a scope the other live probes already require.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff deletes internal CI machinery and edits comments/docs; no user-facing artifact changes.
- `threshold: none, reason:` the diff touches `.github/workflows/scheduled-followthrough-sweeper.yml` (secrets-bearing workflow) but only re-words a permission comment — no permission, job, or secret wiring changes.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Open Code-Review Overlap

1 open scope-out touches a planned file: **#7942** ("Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate") names `scripts/test-all.sh`. **Disposition: acknowledge** — this plan edits `run_suite` `--rows` arguments, not mutation-battery naming/registration; #7942 concerns a different surface (unregistered `*.mutation.sh` batteries). It remains open.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "delete the script file, and delete its rows in `plugins/soleur/test/ci-pr-affected-replay.test.sh` (the section named 'ratchet observation window')" | Footprint rows 1–7 | mapped |
| 2 | "Reconcile any stale references so no dead-path ratchet trips: `ci-pr-affected-activation.md` and ADR-276's PR3a amendment" | Footprint rows 14–15 | mapped |
| 3 | "check for any lint/census that pins followthrough script filenames or requires a `.test.sh` per script" | Footprint rows 5–13 (the census pins found); verification commands (lint-orphan, varq-ban) | mapped |
| 4 | "check `scripts/pr-fanout-ledger.txt` and `plugins/soleur/test/pr-fanout-ledger.test.sh`" | Footprint row 18 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Keep `pull-requests: read`, re-attribute comment | "check whether they should keep a historical mention … or lose the reference" / "no dead-path ratchet trips" | inferred — the workflow comment says retire the LINE with the probe, but surviving probes need the scope; removing it would break live probes (the dead-path trip the ask warns against) |
| Runbook keeps a dated past-tense mention | "check whether they should keep a historical mention (past-tense, dated, naming the commit)" | asked (option offered, chosen) |
| ADR-276 unedited | same | inferred — the clause claimed a script-path reference that does not exist; amendment text is historical and append-only |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `plugins/soleur/test/`, `knowledge-base/` docs (+ 1 workflow comment)
- Planned files: 9 | Estimated changed lines: ~1,000 (almost all deletion)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the change is one atomic retirement; the line count is dominated by one deleted test section.

## Research Insights

**Premise Validation (Phase 0.6):** #10865 verified CLOSED via `gh issue view` (title: "ci: S4 PR3a observation window for the advisory affected-index-ratchet job (soak tracker for #10859)"); its body retains one prose mention of the script path but the `soleur:followthrough` directive is gone, and no other open `follow-through`-labeled issue names the probe. The probe file exists with the `RETIREMENT:` clause at lines 77–79. The clause's claim that ADR-276's PR3a amendment references the script path is **stale** — no literal path appears there (role/issue-number references only). All other cited files exist. Collision precheck: the only PR naming #10865 is this branch's own draft #12296; no live duplicate. A `test-all.sh` run owned by another worktree (`feat-one-shot-12231-star-suites-last`) is unrelated.

**Property List (Phase 0.6b):** (a) `scripts/followthroughs/` contains no retired probe; (b) every census, floor, range-split, declared-edge and accept row that counted the probe's presence is re-pinned in the same commit; (c) the sweeper workflow's permissions still cover every live probe's API reads; (d) historical docs keep a dated record of what the window certified; (e) CI green on the edited suites. **Cut List:** none — the ask proposes no new mechanism; every disposition reuses an existing mechanism (the suite's own census, the ratchet's stale-accept check, the shard-totality tiling assertion).

**Relevant file paths:** all footprint rows above are verified against the live tree (line numbers as of 2026-11-07; they shift during the edit — anchor on section markers `OW_SCRIPT`, `ow_mutate`, `DECLARED_TOTAL`, `FLOOR_ASSERTIONS`, `--rows`, `pull-requests:`).

**Institutional learnings applied:**
- `2026-11-05-deleting-a-literal-referenced-file-reds-followthrough-varq-ban.md` — run `bash scripts/lint-followthrough-varq-ban.sh` locally before pushing a file deletion.
- `followthrough-convention.md` retirement convention — the RETIREMENT header is a seed; re-census by stem over live-code dirs (done; footprint is ~9 live sites vs the clause's 3).
- `2026-10-27-a-section-only-runner-cannot-see-a-cleanup-glob-deleting-another-sections-fixture.md` — run the WHOLE replay file, not a `--rows` slice, before committing (OW fixtures share the suite's stub `gh`; a partial run can hide breakage).

**Related issues/PRs:** #10865 (closed tracker), #10851 (PR3a merge), #10859 (PR3b — stays held; the probe's closing authorized nothing), #10448 (S4 tracker), #11226 (drain sentinel), #12129 (wall-discharge), #11562 (the `--rows` split this change re-pins), #7942 (acknowledged scope-out). ADR-276 + amendments. PR #12296 (this branch's draft).

**CLAUDE.md conventions:** deletion must not leave a dead path under lint/census coverage; plans on feat-* branches carry tasks.md under `knowledge-base/project/specs/<branch>/`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|-----------|---------|---------------|
| RETIREMENT clause: "delete this file and its rows … and the directive on #10865. References: … in `ci-pr-affected-activation.md` and in ADR-276's PR3a amendment." | Directive already removed; ADR-276 carries no literal script path (issue-number references in dated amendments only); the true footprint is ~9 live sites (census pins, `--rows` splits, declared edges, accept rows, sweeper permission comment, sweeper-test comment, runbook) | Treat the clause as a seed per convention; delete + re-pin + disposition per the footprint table |
| Brief: "delete its rows … (the section named 'ratchet observation window')" | The OW content spans lines ~3020–3947 (three sub-headers) plus OW-only code outside it (`row_ow_parity` ~2810, `nosleep` ~202–204) and OW terms in the epilogue census ~5241–5260 | Enumerate all of it; the "section" boundary is the `# == glob-rate` banner at ~3948 |
| Sweeper comment: "Retire this line with the probe." (re `pull-requests: read`) | 7+ other live probes read `/pulls` or the mixed `issues` endpoint that silently filters PRs without the scope | Keep the permission; re-attribute the comment (decision row) |

## Implementation Phases

**Phase 1 — deletion and census re-pins (one commit):**
1. `git rm scripts/followthroughs/ratchet-observation-window-10865.sh`.
2. In `plugins/soleur/test/ci-pr-affected-replay.test.sh`: delete the OW section (~3020–3947, ending before the `# == glob-rate` banner), `row_ow_parity` (~2810), `nosleep` (~202–204), and the OW terms in the epilogue; set `DECLARED_TOTAL` to the new `grep -c '^mutate '` count; re-measure `FLOOR_ASSERTIONS` from a full run and rewrite both comments.
3. Re-split `--rows` ranges in `scripts/test-all.sh` and `scripts/ci-oracle-lane-suites.txt` to tile `1..DECLARED_TOTAL` (same values in both files).
4. Remove the probe path from the three `AFFECTED_…CI_PR_AFFECTED_REPLAY_*_PATHS` arrays in `scripts/lib/test-affected-paths.sh`; update their comment.
5. Run `python3 -I scripts/ci-pr-affected-replay.py --print-baseline`; delete every accept row it reports stale (the 12 citing the probe's ORACLE array at minimum).
6. Re-attribute the `pull-requests: read` comment in `.github/workflows/scheduled-followthrough-sweeper.yml`; update the PERM-1 helper comment in `scripts/sweep-followthroughs.test.sh`.
7. Run the verification commands list; fix any residual reference the grep finds.

**Phase 2 — doc reconciliation (same PR):**
8. Add the dated past-tense retirement note at the window subsection of `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (naming this PR); convert the present-tense "is enforced by" sentence.
9. Re-grep `ratchet-observation-window|10865` over live-code dirs; confirm the only remaining hits are historical (archives, learnings, issue-number references in ADR/runbooks).

## Acceptance Criteria

- [ ] `scripts/followthroughs/ratchet-observation-window-10865.sh` is deleted and `rg -n 'ratchet-observation-window-10865' scripts/ plugins/soleur/test/ .claude/hooks/ .github/workflows/` returns zero hits.
- [ ] `plugins/soleur/test/ci-pr-affected-replay.test.sh` contains no `ow_`/`OW_` symbols, `DECLARED_TOTAL` equals `grep -c '^mutate '` on the file, `FLOOR_ASSERTIONS` equals the measured full-run pass count, and the epilogue carries no `OW_SITES`/observation-window floor.
- [ ] The three `--rows` ranges in `scripts/test-all.sh` and `scripts/ci-oracle-lane-suites.txt` are identical and tile `1..DECLARED_TOTAL` contiguously.
- [ ] `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (full run) passes; `bash plugins/soleur/test/scripts-shard-totality.test.sh` passes.
- [ ] `bash scripts/sweep-followthroughs.test.sh` passes (PERM-1 pin intact; `pull-requests: read` still present in `scheduled-followthrough-sweeper.yml` with a comment naming surviving consumers).
- [ ] `bash scripts/lint-followthrough-varq-ban.sh` and `bash scripts/lint-orphan-test-suites.sh` pass.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py --print-baseline` exits 0 (no stale accept rows; none of the remaining rows cites `ratchet-observation-window-10865.sh`).
- [ ] `scripts/lib/test-affected-paths.sh` contains no reference to the deleted path.
- [ ] `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` carries a dated, past-tense retirement note naming this PR; ADR-276 is unedited.
- [ ] No new files created; `scripts/pr-fanout-ledger.txt` unchanged.

## Test Scenarios

- **unit:** Given the probe file deleted, when `grep -c '^ow_mutate '` runs on the edited suite, then it prints 0 and `DECLARED_TOTAL` equals `grep -c '^mutate '`.
- **integration:** Given the three re-split `--rows` arms, when `scripts-shard-totality.test.sh` runs, then the union tiles `1..DECLARED_TOTAL` and the suite passes.
- **integration:** Given the deleted test section, when `python3 -I scripts/ci-pr-affected-replay.py --print-baseline` runs on the edited tree, then it exits 0 (no `census-degraded` stale-accept failure).
- **integration:** Given the kept `pull-requests: read` line, when `sweep-followthroughs.test.sh` runs, then PERM-1 and its negative arms all pass.

## Success Metrics

- CI `test-scripts` shard green on the PR; the `ci-pr-affected-replay-{a,b,c}` arms run the new ranges with no `[FATAL]` census/range-gate output.
- The nightly followthrough sweeper's next run shows no TRANSIENT/FAIL caused by a missing probe file or lost permission.
- Zero live-code references to the retired path (archives/learnings excepted).

## Dependencies & Risks

- **Risk:** `FLOOR_ASSERTIONS` arithmetic comment becomes misleading if re-measurement is skipped — mitigation: the AC requires the measured full-run count and a rewritten comment.
- **Risk:** an accept row missed by hand-counted pruning — mitigation: the AC requires `--print-baseline` exit 0, the ratchet's own stale-accept oracle.
- **Risk:** removing `pull-requests: read` would 403 surviving probes (the `#7432`/`#8450` explicit-permissions rule and the mixed-endpoint filtering) — mitigation: the permission stays; only the comment is re-attributed (decision row).
- **Risk:** the `nosleep`/`GHFIX` stub scaffolding is shared — mitigation: only the `nosleep` creation lines are OW-scoped; the `fx`/`GH_FIX` stub is used by ~77 earlier sites and stays.
- **Dependency:** none — the tracker is closed and the directive removed; the sweeper never invokes the file again.

## References & Research

- Probe + RETIREMENT clause: `scripts/followthroughs/ratchet-observation-window-10865.sh:77-79`
- Retirement convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` ("the header is a seed; re-census by stem")
- Tracker: #10865 (closed); the window's record: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §observation window
- Varq-ban precedent: `knowledge-base/project/learnings/workflow-patterns/2026-11-05-deleting-a-literal-referenced-file-reds-followthrough-varq-ban.md`
- Section-runner hazard: `knowledge-base/project/learnings/2026-10-27-a-section-only-runner-cannot-see-a-cleanup-glob-deleting-another-sections-fixture.md`
- `--rows` split contract: `plugins/soleur/test/ci-pr-affected-replay.test.sh:60-90`, `scripts/test-all.sh:5620-5629`
- ADR-276 PR3a amendment (item 8/9; append-only; references by issue number)

## Sharp Edges

- The `--rows` boundary lives in the flag argument, never the label; a `B > DECLARED_TOTAL` arm refuses. Re-split and `DECLARED_TOTAL` land in the same commit.
- `ow_mutate` sites are gated call sites: deleting them shifts `_site_seq` for every later `mutate` site — that is exactly why DECLARED_TOTAL and both range files must move together.
- Do NOT delete the shared stub `gh` scaffolding (`fx`, `GH_FIX`, `GH_LOG`, SLOW_/HANG_ handlers ~lines 184–197): earlier sections use it. Only `$BIN/nosleep` (OW-only) goes.
- `row_ow_parity` (defined ~2810 outside the deleted range, called only from it) must be deleted too, or it is dead code reading a missing file.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
