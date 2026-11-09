# Tasks — feat-one-shot-12478-merge-group-escape-evidence

Plan: `knowledge-base/project/plans/2026-11-09-fix-9323-probe-merge-queue-pending-plan.md`
Issue: #12478 (Closes) | Trackers: #9323 (Ref), #12360 (Ref)

## Phase 1 — Probe: merge_group fallback in `_pbg_w_esc`

- [ ] 1.1 Ruling re-verify: read `knowledge-base/project/specs/feat-one-shot-12478-merge-group-escape-evidence/decision-challenges.md` `## Decision Classes` row 1. `pending - assumed: Arm A` → proceed; if the parent's batched technical-ruling gate re-ruled Arm B, re-scope to the `queued`/`no-push-run` bucket (bucket row + counter + note, no classifier path).
- [ ] 1.2 In `scripts/followthroughs/pr-battery-gate-saving-9323.sh` `_pbg_w_esc` (:327-372): extract the red-run conclusion→bucket logic (:341-368) into ONE shared classification path parameterized on event name (`push`/`merge_group`) — no second `test-scripts` enumeration; the prefix stays the examine arm's :283 derivation.
- [ ] 1.3 In the catch-all arm (:370 `*)`), before emitting `pending`: issue `api "repos/$REPO/actions/workflows/ci.yml/runs?event=merge_group&head_sha=$sha" --jq '"\(.workflow_runs[0].id // "") \(.workflow_runs[0].conclusion // "")"'` through `api()` with `cut`/`fail` rows mirroring :337-338; feed rid/concl through the shared classifier; empty/inconclusive → `pending`.
- [ ] 1.4 Add `via_mg` counter: `ok` rows sourced from merge_group increment it; note line beside :598-600 (`note: N qualifying PR(s) verified via merge_group run(s) on their merge commit (queue merges carry no push run)`); `unrelated` note wording event-agnostic or parameterized.
- [ ] 1.5 `need_min` (:406): `3 * MAX_RUNS` → `4 * MAX_RUNS` + comment update (pull + push + mg + prefetch; mg jobs read rides the red-only rare carve-out).
- [ ] 1.6 Doc honesty: header arm-(b) :9-13, `_pbg_w_esc` doc comment :319-326, `need_min` comment :401-406, qualifying-PR-state comment :567-577, pending NOT YET line :602 — all name merge_group; sweep RETIREMENT block :82-84.

## Phase 2 — Fixture coverage (.test.sh)

- [ ] 2.1 Fake-gh route: `repos/*/actions/workflows/ci.yml/runs?event=merge_group*head_sha=*` → `mg-<sha>.json` (add to endpoint case; missing file = read failure like `push-`).
- [ ] 2.2 Cases (matrix rows): absent-push+green-mg → ok/PASS; absent-push+red-mg gated → ESCAPE/FAIL; absent-push+red-mg non-gated-only → unrelated (not escape); absent-push+absent-mg → pending/NOT YET; absent-push+red-mg+jobs-fail → pending; incomplete/cancelled mg → pending; two queue-merged PRs (first green, second red-gated) → escape on second.
- [ ] 2.3 `requests.log` assertions: conclusive push arm issues NO `event=merge_group` read; open PR issues neither push nor mg read; absent-push merged PR issues exactly one mg read; `via_mg` note count + wording.

## Phase 3 — Verify & ship

- [ ] 3.1 `bash -n` both files; `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` exits 0.
- [ ] 3.2 Optional (GH_TOKEN present): `PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh` — report the verdict verbatim, do not post to #9323.
- [ ] 3.3 Commit decision-challenges.md + tasks.md; PR body `Closes #12478`, `Ref #9323`, `Ref #12360` (no Closes/Fixes/Resolves on trackers).
