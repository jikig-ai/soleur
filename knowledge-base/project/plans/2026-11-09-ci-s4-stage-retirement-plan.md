---
title: "ci: retire the S4 PR-affected-only stage — ratchet context, pr-selection lever, evidence layer"
date: 2026-11-09
slug: ci-s4-stage-retirement
branch: feat-one-shot-9729-s4-retire
issue: 9729
type: chore
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
refs: [9729, 10414, 10415, 10949]
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened on:** 2026-11-09
**Sections enhanced:** 4 (Scope Check → canonical schema; Observability probe → matchable literal; Phase 4.5 O-DOCPARITY → verified correction; Encryption Posture → non-boilerplate wording)
**Research agents used:** none — Task/agent fan-out unavailable in this harness; per-section research and review fan-outs executed inline (live `git grep` census, `gh` verification of every cited issue/PR/comment, archived-plan extraction for the #12329 addition mirror and the #12089 removal-ordering precedent). Every halt gate in deepen-plan §§4.5–4.13 was run mechanically: 4.5 skip (no SSH/network symptom; the apply drives `github_repository_ruleset` with zero provisioners — verified), 4.55 skip (config-replace apply only — no reboot/DDL/deploy class), 4.6 pass (`none` threshold + scope-out bullet; no sensitive-path-regex hit), 4.7 pass (5-field block, `bash` probe, literal `ABSENT`), 4.8 pass (zero PAT shapes), 4.9 skip (no UI files), 4.10 pass (`.tf` trigger, full ledger, no exception block), 4.11 pass (`lint-guard-contract.py` rc=0, 1 entry ≥3 matrix rows incl. suite + must-PASS rows), 4.12 pass (canonical 3-subsection Scope Check, 11 mapped asks, no unjustified inferred rows), 4.13 skip (no new autonomous task surface — a data file is not a registered check).

### Key improvements from the deepen pass

1. **O-DOCPARITY correction:** `scripts/lib/test-affected-paths.sh` does NOT carry an `is_doc_path` function (its earlier `git grep -l` hit was comment-only) — there is no surviving second copy to re-anchor onto, so Phase 4.5 now prescribes a literal byte-pin inside `ci-oracle-lane.sh` instead of a cross-file parity pin.
2. **Observability probe made ship-runnable:** the original `expected_output` was prose (unmatchable under Check 10's substring semantics and absent-=`""` semantics); the probe now prints `ABSENT`/`PRESENT` via `git grep -q` and expects `ABSENT`.
3. **Scope Check canonicalized:** the ask↔item table was a single-column-paraphrase form — now the three-subsection schema (Ask Mapping 11 rows verbatim-quoted from the brief, Plan-Item Provenance with three justified `inferred` rows, Split Assessment → `Recommendation: single PR` on atomicity grounds).
4. **Verified counts:** `yaml.safe_load(ci.yml)['jobs']` is currently 22 (ledger's last entry), so post-removal literal is 20; no `needs:` dependent names `affected-index-ratchet` (verified by grep — the job deletes cleanly).

### New considerations discovered

- `plugins/soleur/scripts/lint-ratchet.py` is shared machinery (ADR-290; lefthook, `ruff.toml`, `tests/scripts/test_lint_ratchet.py`, `apps/web-platform/eslint.test-dirs.config.mjs`, C4 `model.c4:198`) — it sits in `RATCHET_ORACLE` but is NOT S4-scoped; the plan keeps it in both the re-scoped oracle surface and the lane exclusion list.
- Two census-found issues the brief did not name are also retirement-scope: #12155 (ratchet-verdict drift gate) and #12456 (replay collect patch) — dispositioned `pending - assumed: not planned` in `decision-challenges.md` for ship-phase confirmation.
- `scripts/ci-pr-affected-audit.baseline.tsv` and `scripts/followthroughs/ratchet-observation-window-10865.sh` are already gone (PR5z and an earlier retirement) — the deletion list and #10949 disposition reflect reality, not the brief's snapshot.

## Overview

Retire the S4 PR-affected-only CI stage per the binding CTO ruling of 2026-11-09 on #9729 (issue comment 6751457876, verified verbatim) and the operator's authorization in the same comment thread. The stage never activated: the repository variable `CI_PR_AFFECTED` is unset and `PR_AFFECTED_LOCKED=1` is intact, so every PR and every merge_group entry already pays the full battery. Four fresh evidence windows failed go/no-go criterion (a) on coverage — not escapes (`attributable=0` on all four) — and criterion (c) caps any further funded round at UNDECIDED.

The teardown removes three things and re-scopes one:

1. **Required context `affected-index-ratchet`** — the job in `.github/workflows/ci.yml` plus every registry that pins the required set (`scripts/required-checks.txt`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`, `infra/github/ruleset-ci-required.tf`, count pins, admin-merge-ready fixtures, `tests/scripts/test-audit-ruleset-bypass.sh`, `scripts/pr-fanout-ledger.txt`, `scripts/probe-merge-group-coverage.sh`, the bot-synthetic unreachability assertion). PR #12329 added the context; this plan mirrors its file list in reverse.
2. **The dark `pr-selection` lever** — the `pr-selection` job (`ci.yml` ~:398), `scripts/ci-pr-selection.sh`, `scripts/ci-pr-selection.test.sh`, and every wiring site (`needs:` edges, `if:` skip-term clauses on the three gated heavy jobs, the `test` aggregator's PR-AFFECTED-SKIP tolerance, and the test pins that enshrine them).
3. **The evidence layer** — `scripts/ci-pr-affected-replay.py` (~2,977 lines), `scripts/ci-pr-affected-preactivation.sh`, `scripts/ci-pr-affected-audit.accept.tsv` (~865 KB), the suite files `plugins/soleur/test/ci-pr-affected-replay.test.sh` and `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`, and the runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`.

**Ordering constraint (load-bearing, ruled in the same comment):** `scripts/ci-oracle-review.sh` — the `oracle-review-required` sentinel — extracts its classification list at run time by importing `RATCHET_ORACLE` from the BASE commit's copy of `scripts/ci-pr-affected-replay.py` (`ci-oracle-review.sh:59`, `:158-178`). Deleting the replay script first fails the sentinel closed on every subsequent PR (`git show` errors → `finish fail api`). The re-scope lands **in the same commit as the deletion**: the oracle list moves to a new committed, base-sourced list file, and the sentinel gains a fallback chain so this PR's own check keeps working while the base still lacks the new file.

**Kept (explicitly out of scope for deletion):** `scripts/lib/test-affected-paths.sh` and `test-all.sh --affected` (the LOCAL affected-test gate — local default and a member of the live oracle lane), the entire oracle lane (`oracle-selection`, `oracle-index-check`, `ci-oracle-lane.sh`, its manifests and sentinel), and `plugins/soleur/scripts/lint-ratchet.py` — a *shared* shrink-only lint tool (ADR-290; lefthook, ruff.toml, `tests/scripts/test_lint_ratchet.py`, C4 model) that merely happens to sit in `RATCHET_ORACLE`.

## Research Reconciliation — Spec vs. Codebase

| Spec/ask claim | Reality on this branch | Plan response |
|---|---|---|
| "`oracle-review-required` imports `RATCHET_ORACLE` from `scripts/ci-pr-affected-replay.py` ~:2106-2108" | Verified: `RATCHET_ORACLE` defined at `scripts/ci-pr-affected-replay.py:2106`; imported at run time by `scripts/ci-oracle-review.sh:158-178` via `git show $base:…` + `importlib` | Re-scope designed around the import mechanism, not just the constant |
| "`scripts/ci-pr-affected-audit.baseline.tsv` is part of the evidence layer" | The baseline was deleted by PR5z (#10861 strict zero); only `.accept.tsv` (865,324 bytes) exists | Delete accept.tsv only; the lane's `is_oracle_data_path` becomes memberless and the `baseline-reintroduced` alarm comment needs an update pointing at retirement |
| "PR #12329 added the context — mirror its file list" | Verified via `gh pr view 12329 --json files` (39 files) | Mirror used as the enumeration seed; live `git grep` census is the authority and found sites #12329 did not touch (e.g. `suite-shard-legs.tsv`, `test-affected-kb-consumers.baseline.txt`, `ci-oracle-lane-legs.tsv`, `code-quality-followups-watch.yml`) |
| "test-all.sh --affected is a member of the live oracle lane" | Verified: `scripts/ci-oracle-lane.sh` exclusion list keeps `scripts/test-all.sh` as a full-battery trigger; `test-all.sh` registers the `--affected` machinery | Keep; only its S4 suite registrations and comments change |
| "apply path for the required context" | `apply-github-infra.yml` fires on `push` to `main` filtered on `infra/github/*.tf` (+ `workflow_dispatch` for re-runs); it checks out `main` — it CANNOT apply the branch's removal pre-merge | Ordering settled by the #12089 precedent: atomic diff + `gh pr merge --admin` + post-merge auto-apply + queue inspection + merge_group canary (see §Post-merge ordering) |
| Follow-through probe `scripts/followthroughs/ratchet-observation-window-10865.sh` (from #10949) | Does not exist on this branch (already retired) | #10949 is OBE on two counts (probe gone + machinery retired) |

## Research Insights

**Research agents used:** none — the Task/agent fan-out is unavailable in this harness; local research ran inline (live `git grep` census of every removed name, `gh` verification of every cited issue/PR/comment, archived-plan extraction for the #12329 and #12089 precedents). External research skipped: this is an internal teardown on machinery this repo authored; the codebase is the authority.

**Premise validation (Phase 0.6):** The CTO ruling comment (issue-comment 6751457876) was fetched and matches the brief verbatim, including the ordered teardown scope and the KEEP list. All cited issues are OPEN: #9729, #10414, #10415, #10949, #12151, #12263, #12013, #10447, #11066, #11166, #12154, #9307, #11679, #12328. PR #12329 is MERGED (2026-11-08). Cited paths verified on the branch: the `affected-index-ratchet` job (`ci.yml:528`), the `pr-selection` job (`ci.yml:398`), the aggregator tolerance (`ci.yml:2433-2438, 2525, 2564-2568`), `RATCHET_ORACLE` (`replay.py:2106`), the sentinel import (`ci-oracle-review.sh:158-178`), and every registry listed in §Files to Edit. Collision pre-check: no open PR names #9729 as closing it; the only in-flight adjacencies are the keep-list issues below.

**Property list (Phase 0.6b).** The properties this change must deliver: (1) no CI job, context, lever, or registry entry names `affected-index-ratchet` or `pr-selection` after merge; (2) `oracle-review-required` still evaluates the live oracle lane's files fail-closed, before AND after the deletion commit; (3) `test-all.sh --affected` still works locally; (4) no live doc/runbook instructs a reader toward retired machinery; (5) the merge is not blocked by the stranded required context (merge mechanics explicit).

**Cut list:** nothing proposed was cut — the brief names mechanisms, and every named mechanism maps to a property above (re-scope → property 2; deletions → property 1; doc edits → property 4; ordering section → property 5). No new machinery is proposed: the re-scoped oracle list is a *data file + fallback*, not a new tool — the alternative "leave the sentinel importing a stub replay.py" was cut as strictly worse (it keeps a dead 2,977-line module alive solely as an enum carrier and keeps `test-all.sh` registering suites for it).

**Key file paths (verified):**
- `.github/workflows/ci.yml` — ratchet job `:528-575`, pr-selection job `:398-437`, header comments `:22`, `:367-374`, `:440-450`, `:518-519`, `:2232`; `needs:` edges `:1651`, `:1757`, `:2034`, `:2396`; aggregator env + tolerance `:2433-2438`, `:2525`, `:2564-2568`
- `scripts/ci-oracle-review.sh` — `ORACLE_REPLAY` const `:59`, base-import block `:158-178`
- `scripts/ci-oracle-lane.sh` — surface/exclusion comments `:60-75`, `is_oracle_data_path` `:167-173`, `is_excluded_path` `:177-191`
- `scripts/ci-oracle-lane-suites.txt` `:31-34,50-54`, `scripts/ci-oracle-lane-legs.tsv` `:13,20,26-27,31`
- `scripts/required-checks.txt` `:240` (comment), `:251` (context); `scripts/ci-required-ruleset-canonical-required-status-checks.json` `:43`; `infra/github/ruleset-ci-required.tf` `:200-206`
- `scripts/pr-fanout-ledger.txt` `:57` (job-count ledger row; current count 22 → 20)
- `tests/scripts/test-audit-ruleset-bypass.sh` T-rsc-7 literal 12→11 `:718-724`, history comment `:701`
- `scripts/probe-merge-group-coverage.sh` `MIN_CONTEXTS_DEFAULT = 14` → 13 + comment `:69`
- `plugins/soleur/test/required-checks-canonical-parity.test.sh:180` `-ge 12` floors → `-ge 11`
- `plugins/soleur/test/fixtures/admin-merge-ready/` — `rules-branches-main.json:53`, `check-runs.json:931-944`, `README.md:13`; `plugins/soleur/scripts/admin-merge-ready.test.sh:72` floor `>= 13` → `>= 12`, `:337` `required=15` → `required=14`
- `scripts/ci-push-dedupe.test.sh` `:90-144,315-322` (PR-term grammar, `PRSEL_VAR` pin, `UNGATED_PINNED`, job key-set pin)
- `scripts/ci-draft-light.test.sh` `:85-110,159-192,353,978-1102` (`LIGHT_PINNED`, needs-set pins)
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` `:585-637,727,852,1045-1100` (G1-8 arms, W5/W7 pins)
- `apps/web-platform/test/c4-likec4-version-pin.test.ts:259` (`PR_AFFECTED_WEBPLAT_IF` expectation)
- `plugins/soleur/test/bot-synthetic-unreachability.test.sh` `:8-11,33,81-82` (oracle import + synthetic-set assertion)
- `scripts/ci-oracle-review.test.sh` `:98-105,169-187` (stub `RATCHET_ORACLE`, stub `git show` dispatch)
- `scripts/ci-oracle-lane.test.sh` `:17-57,243-263,438-454,1108,1181-1230,1403-1458,1637-1649` (exclusion pins, O-DOCPARITY byte-equality, manifest/legs fixtures)
- `scripts/test-all.sh` `:5651-5653` (replay arm registrations), `:7152` (`scripts/ci-pr-selection` registration), `:7554-7558` (replay start-first special-case), `:2840,:3576` (mirror comments)
- `scripts/suite-durations.tsv` `:195-198,:398`; `scripts/suite-shard-legs.tsv` `:197-200,:400`; `scripts/test-affected-kb-consumers.baseline.txt` `:165-171`
- `scripts/lib/test-affected-paths.sh` `:530-531,:1125,:2060-2129,:4128,:4293-4294,:4958-4983` (edges + comments naming retired files)
- `scripts/lib/test-suite-lanes.sh:135`; `scripts/lib/affected-glob.sh:31` (comments)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` `:396,:462` (regen)
- `plugins/soleur/test/scripts-shard-totality.test.sh:158`; `plugins/soleur/test/terraform-target-parity.test.ts:10563` (comment); `plugins/soleur/test/ci-head-verdict.test.sh:1216` (comment — verify no behavioral pin)
- `.claude/hooks/grep-q-pipe-guard.test.sh:2170` (fixture row names the preactivation suite)
- `.github/workflows/code-quality-followups-watch.yml:81` (comment)
- `scripts/ci-e2e-classify.sh:23`, `scripts/ci-shard-totality-classify.sh:27` (comments citing `ci-pr-selection.sh`'s allowlist)
- Runbooks: `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` `:17,:74,:181`; `ci-test-scripts-sharding.md` `:31,:350-354,:518`
- ADRs naming the machinery: ADR-276 (S4 owner — amend), ADR-270, ADR-242, ADR-262, ADR-290, ADR-282, ADR-293 (historical mentions — leave, see §Historical record)

**Institutional learnings applied:** `2026-04-03-github-ruleset-put-replaces-entire-payload.md` (pre/post `bypass_actors`+`conditions` read is the apply receipt); `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md` (producer-existence gate — the probe stays green because removal is symmetric); `2026-10-29-retiring-a-gate-arm-the-interlock-parser-and-the-ci-ratchets-it-trips.md` (gate-arm retirement trips sibling ratchets — every pinned set below is enumerated, not assumed); `2026-05-11-five-agent-plan-review-panel…` (paper-resolution lint — every FR/AC cites a file:line); `2026-11-05-deleting-a-literal-referenced-file-reds-followthrough-varq-ban.md` (deleted-file reference sweep — the census above is that sweep); `2026-11-06-a-cleanup-brief-with-three-items-had-two-already-resolved-on-main.md` (verify before listing — baseline.tsv and the followthrough probe were both already gone).

**Relevant prior PRs:** #12329 (the addition to mirror — 39 files), #12089 (the removal/ordering precedent — atomic context swap + `gh pr merge --admin` + apply watch + queue inspection + merge_group canary), #10861 PR5z (deleted `baseline.tsv` — precedent for evidence-file deletion), #12156 (oracle lane addition — the lane this plan keeps).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — the blast radius is the repo's own merge gate. The concrete bad outcome is `oracle-review-required` failing closed on every PR (a wedged pipeline), or a stranded `affected-index-ratchet` required context wedging the merge queue until the ruleset apply lands.

**If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — teardown removes a never-activated advisory layer; the full battery still runs on every `pull_request` and `merge_group`, so CI correctness coverage is unchanged (the ruling's point 5: "all dispositions leave the full battery on PRs … CI correctness is identical").

**Brand-survival threshold:** `none` — mirrors the PR3b plan's ruling for the same machinery: the harm class is a wedged internal merge gate with a committed break-glass (`gh pr merge --admin`, used by #12089), not a user-facing incident.

- `threshold: none, reason: the diff touches .github/workflows/ci.yml (a sensitive path) but only removes never-activated machinery; the merge-gate's protective coverage is unchanged and the failure mode is internal CI toil, not a user incident`

## Implementation Phases

Ordering inside the diff is semantic (one commit), but the *edit order* below is the safe authoring order — the re-scope is verified before the deletion is staged.

### Phase 1 — Re-scope the oracle sentinel off `replay.py` (blocks everything)

1. Create `scripts/ci-oracle-surface.txt` — one path per line, the new canonical oracle-surface list. Membership (pending-assumed ruling, see `decision-challenges.md`): `RATCHET_ORACLE` minus retired files, plus the lane's own machinery files already treated as oracle-grade — concretely:
   ```
   .github/workflows/ci.yml
   plugins/soleur/scripts/lint-ratchet.py
   scripts/lib/test-affected-paths.sh
   scripts/test-all.sh
   scripts/ci-oracle-lane.sh
   scripts/ci-oracle-lane.test.sh
   scripts/ci-oracle-lane-suites.txt
   scripts/ci-oracle-lane-legs.tsv
   scripts/ci-oracle-review.sh
   scripts/ci-oracle-review.test.sh
   scripts/ci-oracle-surface.txt            # self-member: editing the list requires owner review
   ```
   Rationale: identical coverage of every kept file the sentinel already guards; adds `ci-oracle-lane-legs.tsv` (a lane member a hostile diff could otherwise edit unreviewed — it was in `is_excluded_path` but NOT in `RATCHET_ORACLE`, a pre-existing gap this re-scope closes) and the list file itself.
2. `scripts/ci-oracle-review.sh` — replace the `ORACLE_REPLAY`/importlib extraction (`:59`, `:158-178`) with a base-sourced read chain: `git show "$base:scripts/ci-oracle-surface.txt"` → if absent (transition bases, including THIS PR's base), fall back to the legacy `git show "$base:scripts/ci-pr-affected-replay.py"` importlib arm verbatim → if both absent, the HEAD copy of the surface file is the last resort, mirroring the existing "pre-PR3b base runs the HEAD copy" convention. Update the header contract (`:4-13`) to name the new list. Output grammar unchanged.
3. `scripts/ci-oracle-review.test.sh` — repoint the stub surface (`:98-105`) at the new file; extend the stub `git show` dispatch (`:187`) to answer `*:scripts/ci-oracle-surface.txt`; add an arm asserting the legacy-fallback fires on a base lacking the new file.
4. `plugins/soleur/test/bot-synthetic-unreachability.test.sh` — re-source the oracle list from `scripts/ci-oracle-surface.txt` (`:33`); update the required-set assertions (`:81-82`) for the post-removal context set.
5. Verify: `bash scripts/ci-oracle-review.test.sh` and `bash plugins/soleur/test/bot-synthetic-unreachability.test.sh` green BEFORE any deletion is staged.

### Phase 2 — Remove the `affected-index-ratchet` required context (mirror of #12329, reversed)

1. `.github/workflows/ci.yml` — delete the `affected-index-ratchet` job (`:528-575`) and its header comments (`:22`, `:518-519`); it has no `needs:` dependents (verify: `grep -n 'needs.*affected-index-ratchet' .github/workflows/ci.yml` returns nothing).
2. `scripts/required-checks.txt` — remove the `affected-index-ratchet` row (`:251`) and its disposition comment (`:240`).
3. `scripts/ci-required-ruleset-canonical-required-status-checks.json` — remove the `{"context": "affected-index-ratchet", "integration_id": 15368}` row (`:43`); array goes 12 → 11.
4. `infra/github/ruleset-ci-required.tf` — remove the `required_check` block (`:200-206`) including its dated comment.
5. `tests/scripts/test-audit-ruleset-bypass.sh` — T-rsc-7 literal 12 → 11 (`:718-724`) + dated history line at `:701`.
6. `scripts/probe-merge-group-coverage.sh` — `MIN_CONTEXTS_DEFAULT` 14 → 13 + comment (`:69`).
7. `plugins/soleur/test/required-checks-canonical-parity.test.sh:180` — `-ge 12` → `-ge 11` (both floors).
8. `plugins/soleur/test/fixtures/admin-merge-ready/` — remove the context from `rules-branches-main.json:53`, the synthetic check-run from `check-runs.json:931-944`, update `README.md:13` with a dated removal note; update `plugins/soleur/scripts/admin-merge-ready.test.sh` floor `>= 13` → `>= 12` (`:72`) and the `required=15` literal (`:337`) → `required=14`.
9. `scripts/pr-fanout-ledger.txt:57` — append a `-2` entry to the ci.yml row: `-2 2026-11-09 for the S4 retirement (#9729 ruling 2026-11-09): affected-index-ratchet (required context removed) and pr-selection (dark lever removed). yaml.safe_load(ci.yml)['jobs'] is 20.` (verify the literal against `python3 -c 'import yaml;print(len(yaml.safe_load(open(".github/workflows/ci.yml"))["jobs"]))'` after the edits).
10. `.github/actions/bot-pr-with-synthetic-checks/action.yml` — verify it derives its synthetic set from `required-checks.txt` at run time (no hardcoded context list; comments at `:186-220` suggest it does). If it does, no edit; if not, remove the name.

### Phase 3 — Remove the dark `pr-selection` lever

1. `.github/workflows/ci.yml` — delete the `pr-selection` job (`:398-437`) and its header comments (`:367-374`, `:440-450` where it names pr-selection); remove `pr-selection` from the `needs:` lists at `:1651`, `:1757`, `:2034`, `:2396`; remove the PR-skip `if:` clauses `!(github.event_name == 'pull_request' && needs.pr-selection.outputs.active …)` on `test-webplat` (`:1652`), `test-bun` (`:1758`), `test-scripts-heavy` (`:2035`); in the `test` aggregator delete the env pins `SKIP_LEGS`/`ACTIVE`/`HEAD_SHA_OK` (`:2433-2438`) and the PR-AFFECTED-SKIP tolerance arms (`:2525`, `:2564-2568`) — keep the oracle-selection tolerance arms untouched; sweep stale comment mentions (`:22`, `:2232`).
2. `scripts/ci-pr-selection.sh`, `scripts/ci-pr-selection.test.sh` — delete.
3. `scripts/ci-push-dedupe.test.sh` — drop `pr-selection` from `UNGATED_PINNED` (`:144`), the PR-term grammar pins (`:90-105,225-230`), the job key-set pin (`:315-322`), and needs-set fixtures — update, not weaken: the same pins re-assert the post-removal set.
4. `scripts/ci-draft-light.test.sh` — same shape (`:85-110,159-192,353,978-1102`): `LIGHT_PINNED`, PR-term grammar, needs-set fixtures.
5. `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` — remove `pr-selection` from the allowed non-leg needs set (`:1049,1072-1073`), the W7 tolerance-input pin (`:1092-1100`), the G1-8 empty-input and PR-AFFECTED-SKIP arms (`:585-637,727,852`); keep the oracle arms.
6. `apps/web-platform/test/c4-likec4-version-pin.test.ts:259` — update `PR_AFFECTED_WEBPLAT_IF` to drop the pr-selection clause (keep the oracle-selection clause).
7. `scripts/ci-e2e-classify.sh:23`, `scripts/ci-shard-totality-classify.sh:27` — re-anchor the "driver's allowlist" comments to the surviving copies (`scripts/ci-oracle-lane.sh` `is_doc_path` / `scripts/lib/test-affected-paths.sh`).

### Phase 4 — Retire the evidence layer

1. Delete `scripts/ci-pr-affected-replay.py`, `scripts/ci-pr-affected-preactivation.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`, `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`.
2. `scripts/test-all.sh` — remove the three replay-arm `run_suite` registrations (`:5651-5653`), the `scripts/ci-pr-selection` registration (`:7152`), the replay start-first special-case (`:7554-7558`); update the "Python mirrors pinned by" comments (`:2840,:3576`) to name the surviving pin sites or delete the stale half of the sentence.
3. `scripts/ci-oracle-lane.sh` — drop `scripts/ci-pr-affected-replay.py` from `is_excluded_path` (`:181`); keep `plugins/soleur/scripts/lint-ratchet.py`, `scripts/test-all.sh`, `scripts/lib/*`, `ci.yml`, and the lane's own files — all still live code machinery; collapse `is_oracle_data_path` to zero members with a comment that the surface is now extent-edits + docs only (post-retirement); update the surface/exclusion header comments (`:60-75`).
4. `scripts/ci-oracle-lane-suites.txt` — remove the four retired members (`:50-54`) and stale comments (`:31-34`); `scripts/ci-oracle-lane-legs.tsv` — remove the four rows (`:20,26-27,31`) and REBALANCE the remaining members across the 5 legs (the file's own header records the balance method).
5. `scripts/ci-oracle-lane.test.sh` — update every pin naming a retired file: exclusion-list fixtures (`:263,1108,1637-1649`), the O-DOCPARITY byte-equality anchor (`:1181-1185` — verified at deepen time: `scripts/lib/test-affected-paths.sh` does NOT carry an `is_doc_path` function (mention is comment-only), so there is no surviving second copy to re-anchor onto; convert O-DOCPARITY into a literal byte-pin of the `is_doc_path` body inside `ci-oracle-lane.sh` and update its comment to record that the parity source retired with S4), manifest/legs mutation fixtures (`:1228-1230,1403-1458`), lock-neutralization comments (`:54-57,243-251`).
6. `scripts/suite-durations.tsv` `:195-198,:398` and `scripts/suite-shard-legs.tsv` `:197-200,:400` — remove the retired suite rows; `scripts/test-affected-kb-consumers.baseline.txt:165-171` — remove the `scripts/ci-pr-selection` rows.
7. `scripts/lib/test-affected-paths.sh` — remove the AFFECTED_ edge arrays and entries whose SUBJECT suite is deleted (`ci-pr-selection` block `:2060-2106`, `ci-pr-affected-preactivation.test.sh` `:530-531`, replay arms `:4958-4983`), dead edges TO deleted files (`:2129` replay.py, `:4128` accept.tsv glob), and stale comments (`:1125,:4293-4294`); leave every kept suite's edges alone — this file is oracle-surface, so keep the diff minimal and auditable.
8. `scripts/lib/test-suite-lanes.sh:135`, `scripts/lib/affected-glob.sh:31` — comment updates only.
9. `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerate (entries `:396,:462` name deleted files).
10. `plugins/soleur/test/scripts-shard-totality.test.sh:158` — drop the replay-split subtraction; `plugins/soleur/test/terraform-target-parity.test.ts:10563` — comment re-anchor; `plugins/soleur/test/ci-head-verdict.test.sh:1216` — comment only, verify no behavioral pin.
11. `.claude/hooks/grep-q-pipe-guard.test.sh:2170` — the fixture row names `ci-pr-affected-preactivation.test.sh`; substitute a live suite with the same shape (an `| sed |` fixture row on a kept file) or drop the row per the test's own fixture contract.
12. `.github/workflows/code-quality-followups-watch.yml:81` — update the comment (no behavior).
13. Runbooks: `ci-oracle-lane.md` — rewrite the accept.tsv-driven examples (`:17,:74`) and the `ci-pr-selection.sh` parallel-plumbing comment (`:181`); `ci-test-scripts-sharding.md` — remove replay-arm rows and the `ci-pr-selection.sh` `GATED` comment (`:31,:350-354,:518`).
14. ADR-276 — add the retirement amendment: new dated `### Stage status` line recording S4 retired at NO-GO per the 2026-11-09 ruling (criteria (a) failed on coverage, (c) caps at UNDECIDED, attributable=0 on all windows), the teardown's PR, and the standing dissent conditions ((i) enumerable queue-entry→run linkage AND (ii) a fresh criterion-(c) `pass` window — either alone insufficient). See §Architecture Decision.

### Phase 5 — Verification (pre-merge)

- `bash scripts/ci-oracle-review.test.sh`, `bash plugins/soleur/test/bot-synthetic-unreachability.test.sh`, `bash scripts/ci-oracle-lane.test.sh`, `bash tests/scripts/test-audit-ruleset-bypass.sh`, `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`, `bash plugins/soleur/test/required-checks-merge-group-coverage.test.sh`, `bash plugins/soleur/scripts/admin-merge-ready.test.sh`, `bash scripts/ci-push-dedupe.test.sh`, `bash scripts/ci-draft-light.test.sh`, `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `bash scripts/probe-merge-group-coverage.sh`, `bash plugins/soleur/test/scripts-shard-totality.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bun test apps/web-platform/test/c4-likec4-version-pin.test.ts`, `bun test plugins/soleur/test/terraform-target-parity.test.ts` — all green.
- `bash scripts/test-all.sh --affected --print-selection --paths=README.md` (or the suite's own probe form) exits 0 locally.
- Residual-zero census: `git grep -n 'affected-index-ratchet\|ci-pr-selection\|ci-pr-affected' -- ':!**/archive/**' ':!knowledge-base/project/learnings/**' ':!knowledge-base/project/plans/**' ':!knowledge-base/project/specs/**' ':!knowledge-base/engineering/architecture/decisions/**' ':!knowledge-base/project/brainstorms/**'` returns zero hits outside the historical-record set enumerated in §Historical record; `git grep -n 'affected-index-ratchet' scripts/ infra/ .github/ plugins/ tests/ .claude/ apps/` returns zero.
- `python3 -c 'import yaml;print(len(yaml.safe_load(open(".github/workflows/ci.yml"))["jobs"]))'` prints `20` and matches the updated ledger line.

### Post-merge ordering (the ordering question, answered)

**The apply path:** `apply-github-infra.yml` auto-fires on `push` to `main` when `infra/github/*.tf` changed (path filter, `:38-52`), performs a whole-payload replace of the live ruleset, and its own verify step is the receipt. It checks out `main` — it CANNOT apply the branch's removal pre-merge, and `workflow_dispatch` re-runs the same main checkout. A pre-merge apply is therefore impossible through the sanctioned path.

**The precedent:** #12329 (addition) needed no ordering work — the PR produced its own new contexts. #12089 (the umbrella consolidation — the only precedent for *removing* required contexts while their producers die in the same diff) did: atomic swap of every registry in one diff, then `gh pr merge --admin`, then watch `apply-github-infra.yml`, inspect the queue, run a merge_group canary, post-merge census delta.

**This plan follows #12089:**

1. This PR strands its own `affected-index-ratchet` required context (the job is deleted; the live ruleset still requires it until the post-merge apply) → merge via `gh pr merge --admin`, recorded in the merge record. `oracle-review-required` still applies to this PR normally — and because this diff touches oracle-surface files (`ci.yml`, `test-all.sh`, `test-affected-paths.sh`, the lane files, the sentinel itself), it needs author==deruelle or a bound deruelle APPROVED review on the head SHA — the ship phase must plan on that.
2. On merge, `apply-github-infra.yml` auto-fires (the `infra/github/*.tf` path filter). Do NOT put `[skip-github-apply]` in the merge message.
3. Post-merge verification (mirroring #12089 tasks 3.3-3.5):
   - `gh run list --workflow apply-github-infra.yml --limit 1` → watch to completion; its verify step must show live `required_status_checks` = the 11 CI names (no `affected-index-ratchet`); `bypass_actors` and `conditions` read unchanged before and after the apply (whole-payload replace receipt — record as a PR comment).
   - Queue inspection: any `merge_group` entry created between the merge and the apply's completion wedges on the missing context (merged ci.yml produces nothing under that name while the ruleset still demands it) — merge when the queue is shallow; a wedged entry is cleared by the apply completing, then re-queued.
   - merge_group canary: one trivial PR through the queue after the apply verifies — confirms no required context lacks a producer.
   - Post-merge census delta: `gh api repos/{owner}/{repo}/rules/branches/main` required-context count 12 → 11.
4. Ship phase closes `#9729`, `#10414`, `#10415`, `#10949` (and `#12151`, `#12154`, `#12155`, `#12456` per §Issue dispositions) as **not planned** — the PR body uses `Ref #N`, never `Closes`/`Fixes`.

## Files to Create

- `scripts/ci-oracle-surface.txt` — the base-sourced oracle-surface list (Phase 1.1)

## Files to Edit

- `.github/workflows/ci.yml` — delete two jobs, prune four `needs:` lists, remove three PR-skip `if:` clauses, remove aggregator env + tolerance arms, sweep stale comments (`:22,:367-374,:398-437,:440-450,:518-519,:528-575,:1651-1652,:1757-1758,:2034-2035,:2232,:2396,:2433-2438,:2525,:2564-2568`)
- `.github/workflows/code-quality-followups-watch.yml` — comment (`:81`)
- `infra/github/ruleset-ci-required.tf` — remove `required_check` block (`:200-206`)
- `scripts/required-checks.txt` — remove context + comment (`:240,:251`)
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — remove row (`:43`)
- `scripts/pr-fanout-ledger.txt` — append `-2` ledger entry (`:57`)
- `scripts/probe-merge-group-coverage.sh` — floor 14→13 (`:69`)
- `scripts/ci-oracle-review.sh` — re-scope list source (`:4-13,:59,:158-178`)
- `scripts/ci-oracle-review.test.sh` — stub list + fallback arm (`:98-105,:169-187`)
- `scripts/ci-oracle-lane.sh` — exclusion list + memberless data-path + comments (`:60-75,:167-191`)
- `scripts/ci-oracle-lane.test.sh` — pin updates (`:17-57,:243-263,:438-454,:1108,:1181-1230,:1403-1458,:1637-1649`)
- `scripts/ci-oracle-lane-suites.txt` — remove 4 members + comments (`:31-34,:50-54`)
- `scripts/ci-oracle-lane-legs.tsv` — remove 4 rows, rebalance (`:13,:20,:26-27,:31`)
- `scripts/test-all.sh` — remove registrations + special-case + comments (`:2840,:3576,:5651-5653,:7152,:7554-7558`)
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` — remove retired suite rows
- `scripts/test-affected-kb-consumers.baseline.txt` — remove `scripts/ci-pr-selection` rows (`:165-171`)
- `scripts/lib/test-affected-paths.sh` — remove dead-suite edge arrays/entries + stale comments (`:530-531,:1125,:2060-2129,:4128,:4293-4294,:4958-4983`)
- `scripts/lib/test-suite-lanes.sh:135`, `scripts/lib/affected-glob.sh:31` — comments
- `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh` — pin set updates
- `scripts/ci-e2e-classify.sh:23`, `scripts/ci-shard-totality-classify.sh:27` — comment re-anchors
- `tests/scripts/test-audit-ruleset-bypass.sh` — T-rsc-7 literal + history (`:701,:718-724`)
- `plugins/soleur/test/required-checks-canonical-parity.test.sh:180` — floors `-ge 12`→`-ge 11`
- `plugins/soleur/test/fixtures/admin-merge-ready/{rules-branches-main.json,check-runs.json,README.md}` — context removal
- `plugins/soleur/scripts/admin-merge-ready.test.sh` — floor + literal (`:72,:337`)
- `plugins/soleur/test/bot-synthetic-unreachability.test.sh` — oracle source + assertions (`:8-11,:33,:81-82`)
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` — pr-selection arms (`:585-637,:727,:852,:1045-1100`)
- `plugins/soleur/test/scripts-shard-totality.test.sh:158` — replay-split subtraction
- `plugins/soleur/test/terraform-target-parity.test.ts:10563`, `plugins/soleur/test/ci-head-verdict.test.sh:1216` — comments
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerate
- `apps/web-platform/test/c4-likec4-version-pin.test.ts:259` — `PR_AFFECTED_WEBPLAT_IF`
- `.claude/hooks/grep-q-pipe-guard.test.sh:2170` — fixture row
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` (`:17,:74,:181`), `ci-test-scripts-sharding.md` (`:31,:350-354,:518`)
- `knowledge-base/engineering/architecture/decisions/ADR-276-…md` — retirement amendment (§Architecture Decision)
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — verify-only; edit only if it hardcodes the name

## Files to Delete

- `scripts/ci-pr-affected-replay.py` (~2,977 lines)
- `scripts/ci-pr-affected-preactivation.sh`
- `scripts/ci-pr-affected-audit.accept.tsv` (~865 KB)
- `scripts/ci-pr-selection.sh`
- `scripts/ci-pr-selection.test.sh`
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (~4,742 lines)
- `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`

## Historical record (stays untouched)

ADRs ADR-270, ADR-242, ADR-262, ADR-290, ADR-282, ADR-293; all `knowledge-base/project/learnings/**`; all `knowledge-base/project/plans/archive/**` and `specs/archive/**`; `knowledge-base/project/brainstorms/**`; `plugins/soleur/skills/plan/references/plan-sharp-edges.md:331` (a past-failure catalogue entry whose lesson — verify the canary fixture before claiming a run-level result — survives the machinery it cites); `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh:160` (`AFFECTED_FALLBACK reason=index-missing` is the LOCAL gate's vocabulary — kept machinery, no edit). These cite the check name as it was; none asserts it is required today. ADR-276 is the exception — it is the live stage-status record and gets the amendment in Phase 4.14, not a rewrite of history.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Required context `affected-index-ratchet` — every site: .github/workflows/ci.yml job + scripts/required-checks.txt + the canonical required-checks JSON + infra/github ruleset Terraform + count pins + admin-merge-ready fixtures + test-audit-ruleset-bypass.sh + pr-fanout-ledger.txt" | Phase 2; §Files to Edit registry census | mapped |
| 2 | "The dark `pr-selection` lever — ci.yml (~line 398) + scripts/ci-pr-selection.sh + any wiring." | Phase 3 | mapped |
| 3 | "The evidence layer — scripts/ci-pr-affected-replay.py + scripts/ci-pr-affected-preactivation.sh + scripts/ci-pr-affected-audit.accept.tsv + their tests … + the runbook … Sweep for other references" | Phase 4; §Files to Delete | mapped |
| 4 | "the `oracle-review-required` sentinel imports `RATCHET_ORACLE` from scripts/ci-pr-affected-replay.py … Re-scope its oracle list OFF the replay script BEFORE removing the replay script — the oracle list must still cover the live oracle lane's files" | Phase 1; `scripts/ci-oracle-surface.txt` | mapped |
| 5 | "KEEP: scripts/lib/test-affected-paths.sh and `test-all.sh --affected` … The `oracle-review-required` check itself stays — only its import source moves." | Non-goal guard; AC 3, AC 4 | mapped |
| 6 | "the PR body must use `Ref #N`" / "close them `not planned`, NOT via `Closes` keywords" | §Post-merge ordering item 4; AC 11 | mapped |
| 7 | "evaluate #10949 (S4 residual — likely obsoleted by retirement …) and discriminate the other open affected-* issues" | §Issue dispositions | mapped |
| 8 | "does the ruleset Terraform get applied pre-merge, post-merge, or is there an apply workflow? Mirror however #12329 handled the ratchet ADDITION (its apply path) and state the apply step in the plan's post-merge section." | §Post-merge ordering | mapped |
| 9 | "(a) enumerate every consumer/import site of each removed file (cross-consumer grep — the corpus rules require it)" | §Research Insights census; residual-zero AC 1-2 | mapped |
| 10 | "(b) the affected-index/ratchet may be referenced by docs, AGENTS.rules.md, ADRs, learnings — list which need edits vs which stay as historical record" | §Historical record; Phase 4.12-14 | mapped |
| 11 | "(c) acceptance criteria must include: no remaining reference to `affected-index-ratchet` as a required context, `oracle-review-required` still evaluates the live lane, `test-all.sh --affected` still works locally, CI green on the PR itself" | §Acceptance Criteria 1-5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `scripts/ci-oracle-surface.txt` (create) + sentinel fallback chain | "Re-scope its oracle list OFF the replay script BEFORE removing the replay script — the oracle list must still cover the live oracle lane's files" | asked |
| Phase 2 registry removals | "remove required context `affected-index-ratchet` (ci.yml + scripts/required-checks.txt + infra/github ruleset)" | asked |
| Phase 3 lever removal | "remove the dark `pr-selection` lever (ci.yml + scripts/ci-pr-selection.sh)" | asked |
| Phase 4 deletions + runbook/doc edits | "retire the evidence layer (scripts/ci-pr-affected-replay.py + ci-pr-affected-preactivation.sh + ci-pr-affected-audit.accept.tsv + tests + this runbook)" | asked |
| `ci-oracle-lane-legs.tsv` oracle-surface membership | — | inferred — justification: legs.tsv sits in the lane's `is_excluded_path` (full-battery machinery) but was absent from `RATCHET_ORACLE`; a re-scoped list that omits it leaves a live lane file editable without owner review — the gap the sentinel exists to close |
| List-resolution fallback chain (base-txt → base-replay.py → HEAD-txt) | — | inferred — justification: `ci-oracle-surface.txt` does not exist on this PR's base; without the legacy arm the PR's own `oracle-review-required` fails closed the moment it is reviewed — mirrors the driver's existing HEAD-copy fallback convention |
| `gh pr merge --admin` + queue inspection + merge_group canary | "Wrong order strands PRs blocked on a context nothing produces." | inferred — justification: the PR deletes the job the live ruleset still requires, so no check-run can satisfy it; #12089 is the only precedent for removing required contexts whose producers die in the same diff and it used exactly this merge path |
| ADR-276 retirement amendment | — | inferred — justification: the retirement reverses a stage of ADR-276, and plan Phase 2.10 makes the decision record an in-scope deliverable rather than a deferred issue |
| Post-merge apply watch + `bypass_actors`/`conditions` pre/post read | "state the apply step in the plan's post-merge section" | asked |

### Split Assessment

- Subsystems touched: 8 — `.github`, `infra`, `scripts`, `plugins`, `tests`, `.claude`, `apps`, `knowledge-base`
- Planned files: ~44 (1 create, ~35 edits, 8 deletes) | Estimated changed lines: ~9,000 (dominated by two deletions: replay.py ~2,977 + its ~4,742-line test + the ~865 KB accept.tsv)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — all three exceeded
- Recommendation: single PR — the ordering constraint forbids a seam: the sentinel re-scope, the replay deletion, and the registry removal must land in one commit (any split strands either the sentinel's import source or a required context its producer no longer emits). The size is mostly deletion mass, not review surface; the #12089 atomic-swap precedent held its 11-context fold to one PR for the same reason.

## Domain Review

**Domains relevant:** Engineering only — internal CI machinery teardown; no user-facing, legal, marketing, sales, finance, support, or operations-dashboard surface. (Domain-leader fan-out unavailable in this harness — inline assessment against the brainstorm-domain-config checklist.)

### Product/UX Gate

**Tier:** none — `## Files to Create`/`## Files to Edit` contain no UI-surface paths (mechanical override scan: zero matches against `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, ui-surface terms). A plan that implements orchestration/docs changes only is exempt.

## Acceptance Criteria

- [ ] `git grep -n 'affected-index-ratchet' -- .github/ infra/ scripts/ plugins/ tests/ .claude/ apps/` returns zero hits; the name appears nowhere as a required context (historical-record directories per §Historical record excepted).
- [ ] `git grep -ln 'ci-pr-selection\|ci-pr-affected\|CI_PR_AFFECTED\|PR_AFFECTED_LOCKED' -- .github/ infra/ scripts/ plugins/ tests/ .claude/ apps/ knowledge-base/engineering/operations/ knowledge-base/engineering/architecture/diagrams/` returns zero hits outside §Historical record.
- [ ] `oracle-review-required` still evaluates the live oracle lane: `bash scripts/ci-oracle-review.test.sh` green, and a fixture diff touching `scripts/ci-oracle-lane.sh` (or any member of `scripts/ci-oracle-surface.txt`) still produces `oracle_diff=1`/`verdict=fail reason=review-required` while a docs-only diff produces `not-oracle`.
- [ ] `bash scripts/test-all.sh --affected --print-selection` (or its documented probe form) exits 0 on a scratch diff locally; `scripts/lib/test-affected-paths.sh` byte-survives except the removed dead-suite/dead-file edges.
- [ ] CI is green on the PR itself for every context the PR still produces; `oracle-review-required` is satisfied on this PR via the author/bound-approval arm (this diff touches oracle surface by construction).
- [ ] `python3 -c 'import yaml;print(len(yaml.safe_load(open(".github/workflows/ci.yml"))["jobs"]))'` == 20 and `scripts/pr-fanout-ledger.txt`'s new entry carries the same number.
- [ ] Canonical/canonical↔TF parity holds: `jq 'length' scripts/ci-required-ruleset-canonical-required-status-checks.json` == 11; `bash tests/scripts/test-audit-ruleset-bypass.sh` T-rsc-7/T-rsc-9 green; `bash scripts/probe-merge-group-coverage.sh` green with `contexts=13 producers=11`.
- [ ] Every pinned-set test updated rather than deleted: `ci-push-dedupe.test.sh`, `ci-draft-light.test.sh`, `ci-test-aggregator-diagnosis.test.sh`, `required-checks-canonical-parity.test.sh`, `admin-merge-ready.test.sh`, `bot-synthetic-unreachability.test.sh`, `ci-oracle-lane.test.sh`, `c4-likec4-version-pin.test.ts`, `scripts-shard-totality.test.sh`, `grep-q-pipe-guard.test.sh`, `fixture-relative-assert.baseline.txt`, `suite-durations.tsv`, `suite-shard-legs.tsv`, `test-affected-kb-consumers.baseline.txt` all green.
- [ ] `apply-github-infra.yml` post-merge run verifies live `required_status_checks` = 11 CI names with `affected-index-ratchet` absent; `bypass_actors`/`conditions` unchanged pre/post apply (receipt recorded as PR comment).
- [ ] ADR-276 carries the dated retirement amendment; `git grep -n 'S4' knowledge-base/engineering/architecture/decisions/ADR-276*.md` shows the retirement line.
- [ ] PR body uses `Ref #9729`, `Ref #10414`, `Ref #10415` (and the additional not-planned refs); no `Closes`/`Fixes` keyword names them.

## Open Code-Review Overlap

Checked 2026-11-09 against `gh issue list --label code-review --state open` (200 issues, body search over every Files-to-Edit path):

- **#8881** (shard-legs rebalance review evidence) — **acknowledge**: this plan also edits `suite-shard-legs.tsv`/`suite-durations.tsv`/`ci-oracle-lane-legs.tsv`, but to remove dead members, not rebalance weights; the leg-rebalance requirement for `ci-oracle-lane-legs.tsv` is called out in Phase 4.4.
- **#7942** (mutation batteries ungated) — **acknowledge**: mentions `test-all.sh` as context only; unrelated scope.
- Sibling open issues touching the same files (not code-review-labeled): **#12328** wants new edge declarations inside `scripts/lib/test-affected-paths.sh` (kept file, same file different section) — **acknowledge**, do not fold: oracle-surface diffs must stay minimal and that change needs its own owner review. **#12013/#12263/#10447/#11066/#11325/#9564/#9307/#11679** all track the KEPT local gate — stay open, no fold (Phase 4.7's edge removals are deletions of dead subjects only, not the improvements those issues track).

## Issue dispositions (ship phase: close as *not planned*, PR body `Ref #N` only)

| Issue | Disposition | Why |
|---|---|---|
| #9729 (epic) | not planned | the ruling's own instruction |
| #10414 (S4 PR D) | not planned | the ruling's own instruction — S4 follow-up work |
| #10415 (SOLEUR_FULL_BATTERY_ESCAPE heartbeat) | not planned | the ruling's own instruction — the escape metric it routed belongs to the retired stage |
| #10949 (drain-window restart probe) | not planned | subject is doubly dead: the probe file is already gone AND the machinery it observed is retired |
| #12151 (replay-arms selection edge) | not planned | the three replay arms it narrows are deleted in Phase 4; its parent #12013 stays open |
| #12154 (accept-row → edge sweep) | not planned | its subject file `accept.tsv` is deleted; the durable disposition it promoted (declare edges) survives in the kept gate |
| #12155 (PR3b-lite ratchet-verdict drift gate) | not planned | arms the verdicts of the retired ratchet — discovered in census, flagged for the ship phase to confirm |
| #12456 (replay collect window tip) | not planned | patches `ci-pr-affected-replay.py`, deleted in Phase 4 — discovered in census, flagged for the ship phase to confirm |
| #12013, #12263, #10447, #11066, #11166, #9307, #11679, #12328, #11325, #9564 | stay open | all track the KEPT local affected gate / lane machinery |

## Observability

```yaml
liveness_signal:    # the merge gate itself: required contexts green on pull_request + merge_group; alert_target = the `test` aggregator verdict and `oracle-review-required` check lines; configured_in = .github/workflows/ci.yml (existing)
error_reporting:    # job-level ::error lines on the GHA run page + PR check list (existing mechanism — no new sink)
failure_modes:
  - mode: sentinel fails closed on every PR (re-scope regression)
    detection: oracle-review-required check-run red with `reason=api` on a docs-only PR
    alert_route: PR check list — blocks merge by design; break-glass = admin merge + revert
  - mode: stranded required context wedges merge queue between merge and apply
    detection: merge_group entry reports `affected-index-ratchet` Expected/pending
    alert_route: apply-github-infra.yml run completion clears it; queue inspection is a post-merge task
  - mode: removed suite still referenced (residual reference)
    detection: residual-zero census grep in Phase 5 + lint-orphan-test-suites.sh + fixture-relative-assert baseline
    alert_route: CI `test` context
logs:               # GHA run logs, 90-day GitHub retention (existing)
discoverability_test:
  command:          bash -c 'git grep -q "affected-index-ratchet" scripts/required-checks.txt infra/github/ruleset-ci-required.tf scripts/ci-required-ruleset-canonical-required-status-checks.json .github/workflows/ci.yml && echo PRESENT || echo ABSENT'
  expected_output:  ABSENT
```

## Infrastructure (IaC)

Phase 2.8 reviewed: the only infrastructure this plan touches is an **edit to an existing Terraform root** — removing one `required_check` block from `infra/github/ruleset-ci-required.tf`. No new resource, host, secret, or service is created; no manual provisioning step exists anywhere in the plan.

### Terraform changes

- `infra/github/ruleset-ci-required.tf` — remove the `required_check` block at `:200-206` (context `affected-index-ratchet`, `integration_id = 15368`) including its dated history comment. No provider or variable changes; no sensitive variables touched.

### Apply path

- **Existing automated path, unchanged:** `apply-github-infra.yml` auto-applies `infra/github/*.tf` on push to `main` (path-filtered trigger) with a by-value pre-apply gate and a post-apply verify step. The merge is the authorization (`hr-menu-option-ack-not-prod-write-auth`); the plan adds no `[skip-github-apply]` marker. Expected blast radius: whole-payload replace of the CI Required ruleset — bounded by the canonical↔TF parity gates (T-rsc-9, canonical-parity test) and the pre/post `bypass_actors`+`conditions` read recorded as a PR comment.

### Host fan-out

- None — no `terraform_data` SSH provisioners are touched.

### Distinctness / drift safeguards

- Single ruleset on a single repo — no dev/prd distinctness axis. Drift is detected by `scheduled-terraform-drift.yml` and the daily live↔canonical audit (existing).

### Vendor-tier reality check

- N/A — GitHub rulesets have no tier gate.

## Encryption Posture

```yaml
at_rest:
  - store: GitHub repository ruleset (live, API-held configuration object — not a repo-hosted data store)
    mechanism: GitHub SaaS-managed storage; integrity (not confidentiality) is the property in scope — the change removes one required_status_checks member
    evidence: infra/github/ruleset-ci-required.tf + canonical JSON parity gates
    defends_against: unauthorized context-set drift (integrity, not confidentiality — no secret material)
    does_not_defend: the ruleset's required-context list integrity — carried by canonical-JSON parity tests, T-rsc-9, and apply-github-infra.yml's by-value pre-apply gate
    disclosed_as: n/a — config, not data
    live_verification: terraform plan diff reviewed by apply-github-infra.yml's pre-apply gate before apply; post-merge `gh api` census delta in §Post-merge ordering
in_transit:
  - connection: apply-github-infra.yml → GitHub API (ruleset PUT, whole-payload replace)
    tls: yes (api.github.com)
    cert_verification: on
    does_not_defend: payload correctness — carried by the by-value gate + canonical parity
    disclosed_as: existing workflow, unchanged
# no exception block — no plaintext-exception, no cert_verification off
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-276** (`knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`) — it owns the S4 stage and its `### Stage status` convention; the retirement is a partial reversal of the stage, not a new decision. The amendment records: retired at NO-GO on 2026-11-09 (ruling comment 6751457876), the four-window evidence outcome (criterion (a) failed on coverage; (c) caps further rounds at UNDECIDED; `attributable=0` on all windows), the machinery list removed/kept, and the standing dissent pair. No new ADR — the decision record lives where the stage's history lives. C4 completeness check performed: enumerated external actors (none new — the change touches no external actor), external systems/vendors (none new), containers/data-stores (none — the ruleset is API-held config, already not modeled), actor↔surface relationships (unchanged). `model.c4`/`views.c4`/`spec.c4` contain no `affected-index`/`pr-selection`/oracle-lane elements (verified by grep of all three files); `lint-ratchet` IS modeled (`model.c4:198`) and stays — no element falsified → **no C4 edit**, with the enumeration recorded here as required.

### Sequencing

The ADR amendment lands in the same commit as the teardown — the post-merge state (no S4 stage, no `affected-index-ratchet` context) is true the moment the diff lands; no `adopting` lag.

## Guard Contract

### Guard 1 — `oracle-review-required` still fails closed without a list source

**Property.** After the re-scope AND after the replay.py deletion, every pull_request/merge_group run resolves a non-empty oracle list or fails (`reason=api`/`shape`) — never a vacuous `not-oracle` pass.

**Assembly.** The sentinel's list-resolution chain (`scripts/ci-oracle-review.sh`): base `ci-oracle-surface.txt` → base `ci-pr-affected-replay.py` legacy import → HEAD `ci-oracle-surface.txt`; plus the list file itself and `scripts/ci-oracle-review.test.sh` pinning the chain in both directions.

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Delete `scripts/ci-oracle-surface.txt` AND `scripts/ci-pr-affected-replay.py`, drop the HEAD fallback arm | RED — every base resolves nothing → fail `api`/`shape`, never pass |
| Empty the surface file on base and head | RED — empty list must not yield `not-oracle` (the test's empty-list arm) |
| Remove `scripts/ci-oracle-lane-legs.tsv` from the surface file while a diff edits it | RED — the file is a list member; its edit must classify `oracle_diff=1` |
| Suite mutation: make the test accept `verdict=pass` on an oracle-touching fixture | RED — the harness's own expected-verdict literal |
| must-PASS variant: a `knowledge-base/**` docs-only diff | PASS `not-oracle` — proves the guard does not reject everything |
| must-PASS variant: base lacks the new file but carries replay.py (THIS PR's own base shape) | PASS — legacy fallback classifies; this PR's check works |

**Anchor.** The list is base-sourced — a PR cannot shrink the list that judges it; weakening both list and sentinel in one diff still trips canonical↔TF parity + the oracle-lane `is_excluded_path` full-battery trigger on the lane's own files.

## Test Scenarios

- Sentinel re-scope: fixture diffs — oracle-member path (`scripts/ci-oracle-lane.sh`), docs-only path, legacy-fallback base shape, missing-both-sources fail-closed — asserted in `ci-oracle-review.test.sh`.
- Registry removal: T-rsc-7 count literal, T-rsc-9 canonical↔TF, canonical-parity `-ge 11` floors, probe `contexts=13 producers=11`, admin-merge-ready fixture counts.
- ci.yml surgery: `ci-push-dedupe.test.sh` + `ci-draft-light.test.sh` pinned sets, `ci-test-aggregator-diagnosis.test.sh` tolerance arms, `c4-likec4-version-pin.test.ts` `if:` strings — all re-pin the POST-removal grammar (update, never weaken).
- Suite hygiene: `lint-orphan-test-suites.sh`, `fixture-relative-assert` baseline regen, `suite-shard-legs.tsv`/`suite-durations.tsv` row removals keep shard arithmetic consistent (`scripts-shard-totality.test.sh` green).
- Local gate: `test-all.sh --affected` selection probe on a docs diff (kept machinery, regression only).

## Alternative Approaches Considered

| Option | Rejected because |
|---|---|
| Two-PR sequence (remove required context first, machinery second) | The #12089 precedent already solved the wedge with atomic + admin-merge; two PRs doubles the cycle and leaves a green-but-meaningless ratchet running in the interim (~4,400 billed min/week the ruling cites as waste) |
| Pre-merge apply through `apply-github-infra.yml`'s `workflow_dispatch` | The workflow checks out `main` only — it cannot apply the branch's removal; any out-of-band apply of the branch TF bypasses the canonical↔live audit ordering |
| Keep `replay.py` as a stub enum carrier for the sentinel | Keeps a dead ~3k-line module as the list's hostage; the sentinel's own driver-fallback convention makes a plain committed list strictly better |
| Rewrite `RATCHET_ORACLE` references into ADR-270/242/262 etc. | ADRs are point-in-time decision records; only ADR-276 is the live stage-status owner — the rest stay as history |

## Decision Challenges (carried to `knowledge-base/project/specs/feat-one-shot-9729-s4-retire/decision-challenges.md`)

| Item | Class | Ruling |
|---|---|---|
| New oracle-list home: committed `scripts/ci-oracle-surface.txt` vs embedding the list in `ci-oracle-review.sh` | technical | pending - assumed: dedicated committed list file — base-sourced, greppable, self-membered, and it frees the sentinel's extractor from importlib-on-.py |
| Oracle-list membership: union(old RATCHET_ORACLE − retired) + `ci-oracle-lane-legs.tsv` + the list file itself | technical | pending - assumed: the set above — covers every live lane file; the legs.tsv addition closes a pre-existing gap (in `is_excluded_path` but not `RATCHET_ORACLE`) |
| List-resolution fallback chain during transition (base-txt → base-replay.py → HEAD-txt) | technical | pending - assumed: the chain above — mirrors the driver's existing HEAD-copy fallback for pre-PR3b bases and is the only ordering that keeps THIS PR's own check green |
| Atomic diff + `gh pr merge --admin` vs two-PR sequence | technical | pending - assumed: atomic + admin merge, mirroring the #12089 removal precedent exactly |
| #12155 / #12456 not-planned dispositions | operator (scope) | pending - assumed: not planned — both patch retired machinery; surfaced for ship-phase confirmation rather than closed unilaterally |

## Sharp edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan Phase 4.6 — filled above.
- `ci-oracle-lane.test.sh` O-DOCPARITY asserts `is_doc_path` byte-equality against `ci-pr-selection.sh` (`:1181-1185`) — deleting the reference copy reds the pin even though the lane copy survives; Phase 4.5 re-anchors it.
- Every pinned-set test names the members it tolerates (`UNGATED_PINNED`, `LIGHT_PINNED`, non-leg needs set, W7 inputs, job key-set) — a removal that forgets one reads as a diff the pin was written to catch; Phase 3 enumerates them all.
- The `admin-merge-ready` fixtures simulate the LIVE ruleset — editing `rules-branches-main.json` without `check-runs.json` (or the count floors) produces fixture-internal contradiction, not a test failure a reader can localize.
- `ci-oracle-lane-legs.tsv` is load-bearing balance data, not a list — dropping four members without rebalancing leaves a leg carrying the deleted ~17-minute replay-a weight in the header's accounting.
- The merge_group wedge window between merge and apply is real but short; merging when the queue is shallow and watching the apply run are the mitigations (#12089 did the same).
