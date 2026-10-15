---
title: "fix(infra): remove runnable Hetzner DELETE recipes from drift-workflow issue bodies (#9927 item 8c)"
date: 2026-10-15
slug: fix-drift-workflow-remove-delete-recipes
branch: feat-one-shot-9927-drift-delete-recipes
issue: 9927
lane: single-domain
type: fix
requires_cpo_signoff: false
---

# fix(infra): remove runnable Hetzner DELETE recipes from drift-workflow issue bodies (#9927 item 8c)

Ref #9927 (no closing keyword anywhere; #9927 stays open). Draft PR #10355 already exists on this branch.

## Enhancement Summary

**Deepened on:** 2026-10-15
**Sections enhanced:** Scope Check (rebuilt to the gate schema), Observability (added), Guard Contract (validated by simulation), Research Insights.
**Agents used:** none beyond the plan-phase CTO ruling and learnings researcher; the change is S-sized, so deepening was done as mechanical gate verification plus a simulation of the guard against the real workflow.

### Key Improvements
1. The guard design was simulated against the real workflow with python/yaml: 46 steps parsed, exactly 2 steps named "File an issue for orphaned rehearsal hosts", both flagged RED by the Hetzner write check and by the Doppler destroy check on the current file, and 0 flags after an in-memory removal of the 5 lines (no false positive elsewhere, including the read-only sweep steps that mention api.hetzner.cloud and HCLOUD_TOKEN).
2. The Scope Check was rebuilt to the schema deepen-plan section 4.12 verifies (Ask Mapping, Plan-Item Provenance, Split Assessment with a Recommendation line).
3. A five-field Observability block was added because section 4.7 applies to any plan whose Files to Edit are not all docs; its discoverability command is a one-line python count that prints 0 once the recipes are gone.

### New Considerations Discovered
- The old recipe lines begin with `echo`, so the suite's existing `strip_comments` (which drops only lines starting with `#`) does not hide them: no special handling is needed, and the comment-only must-PASS row is still required to prove comments are ignored.
- The sweep steps (lines near 1918 and 2329) read `HCLOUD_TOKEN` as `TOKEN="${HCLOUD_TOKEN:-}"  # loader-exported (#8209)`; that confirms the CTO's point that the fence's token source is a separate hardening.

## Overview

`.github/workflows/scheduled-terraform-drift.yml` auto-files two GitHub issues when a rehearsal host survives past its
teardown: "Orphaned rung-2 rehearsal resource(s) on Hetzner" (label `app=soleur-rung2-rehearsal`) and "Orphaned inngest
rehearsal resource(s) on Hetzner" (label `app=soleur-inngest-provision-rehearsal`). Each body hands a reader a bash
fence that fetches the read/write Hetzner token and ends in a pasteable `curl -sS -X DELETE ... /v1/<kind>/<id>`. ADR-282's
residual list names exactly this as a one-paste destroy vector. Both filers are label-scoped to rehearsal objects, not
the sole-copy volume, but a printed destroy recipe is the wrong affordance regardless of the scope it was written for.

This plan removes the DELETE recipe (and the Doppler `configs delete` / `environments delete` one-liners on the same
lines of prose, per CTO ruling), keeps the read-only list loop and the rest of each body, rewords the Remedy prose so it
stays true, corrects the two documents that quote the recipe (ADR-282 residual, one runbook line), and adds a
regression assertion that no issue-body printer in the drift workflow prints a Hetzner write or Doppler destroy call.

Workflow-text edit only: no dispatch of the workflow, no Hetzner, Doppler, SSH or production call. Never touches web-1
volume 106443278.

## Premise Validation

- #9927 is OPEN ("infra: Inngest LUKS key-loss residuals deferred from #9879 ..."); item 8c is one of its listed items.
  Draft PR #10355 is OPEN. Not stale.
- Cited lines hold on this branch (== origin/main at branch point): `-X DELETE` at lines 2084 and 2445; "the exact
  calls are" at 2073 (rung-2) and 2436 (inngest); `# then, per object (detach a volume ...)` at 2083 only. The brief's
  "reclaimed by the API directly" is the rung-2 wording at 2072; the inngest wording is "reclaim it by the API directly"
  (2436). Both are reworded.
- ADR-282 line ~188 does name "the drift workflow's runnable DELETE recipes" (confirmed). ADR corpus check for the
  mechanism: ADR-282 is the only ADR naming it, as a recorded residual, not a rejected alternative. ADR-284
  (hosted-bash must-ask lane for destroy families) is adjacent policy, not contradicted.
- No open PR touches the workflow (re-verified via `gh pr list --state open` file filter: empty).
- Not a stale-premise case: nothing cited is already resolved.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Two `-X DELETE` echo blocks plus a `# then, per object` echo "in the first block" | Confirmed: rung-2 has all three lines (2083-2085), inngest has the two `curl`/URL lines (2445-2446). | Remove exactly those lines. |
| "keep the TOKEN fetch only if nothing left needs it" | The kept read-only `for k in servers volumes ...` loop uses `$TOKEN` (`Authorization: Bearer $TOKEN`). | Keep the `TOKEN=` line unchanged (CTO ruling: swapping to `HCLOUD_TOKEN_READONLY` is separate hardening). |
| Known test: `git-data-rung2-rehearsal.test.sh` strips comments at ~1395-1399 and asserts on code | Asserts only that the sweep job id and the `api.hetzner.cloud/v1/${_kind}` call exist; neither matches any removed line. | No edit; run it as a regression check. |
| Known test: `inngest-provision-rehearsal.test.sh` greps at ~229-247 | Greps `soleur-inngest-rehearsal-`, `soleur-inngest-provision-rehearsal`, `rehearsal_`, `soleur-inngest` in the drift workflow; all live in lines this change keeps. | No edit; run as regression check. |
| `terraform-target-parity.test.ts:2312` reads the file | It reads `scheduled-terraform-drift.yml` only to assert no `-target` on pin addresses. | No edit. |
| A destructive-verb census may scan workflows for `-X DELETE` | `workspaces-luks-cutover-workflow.test.sh` censuses only its own workflow; `operator-script.test.sh` / `operator-agent-runnable.test.sh` scan operator scripts, not this workflow. None scan `scheduled-terraform-drift.yml`. | No census edit; the new assertion is the first guard over this file's bodies. |
| Doppler one-liners are out of scope ("Hetzner DELETE recipes") | They sit at the end of the same two bodies and are the same pasted-destroy class (the rung-2 config holds a live `GIT_DATA_LUKS_KEY`). | CTO ruled: reword to non-runnable prose and include in the assertion (see Decision Challenges file). |
| Sweep of the repo by subject | Only the workflow, ADR-282 line ~188, and `inngest-provision-rehearsal.md` line ~167 quote or direct the recipe. Archived plans are history and stay untouched. `git-data-rung2-rehearsal.md` line ~406 says the rung-2 destroy reclaims volumes and the scratch config, which stays true. | Edit ADR-282 + runbook; leave the rest. |

## Property List and Cut List (Phase 0.6b)

**Properties the change must buy**

1. No auto-filed drift/orphan issue body contains a runnable Hetzner write call (DELETE/PUT/POST/PATCH or `hcloud ... delete`).
2. No such body contains a runnable Doppler destroy one-liner (`doppler configs|environments|projects delete`).
3. The Remedy prose stays true: it still routes to the `teardown_only` dispatch and still lets a reader enumerate the survivors with ids.
4. The read-only enumeration (label-selector GET loop) survives in both bodies.
5. Documents that told a reader to paste the recipe (ADR-282 residual, runbook line) no longer lie.
6. A future edit re-adding a write call to an issue body goes red in CI.

**Cut List** (mechanisms considered, not built)

- New dedicated reclaim workflow / `reclaim_survivors` dispatch input: buys "owner can delete a survivor by a reviewed path", already covered by the owner-authorised agent-session route the ADR assumes, and out of scope for a S-sized item; also invents a path the prose would then have to name. Cut.
- Swap the fence to `HCLOUD_TOKEN_READONLY` so a pasted write 403s: real hardening, but the workflow's own sweep still reads the read/write token and the no-fallback loader is carried by #9927. Cut; optional follow-up noted under #9927.
- New standalone test file: the property is covered by extending `token-drift-workflow-causes.test.sh`, which already owns the filer assertions. Cut.
- Repo-wide destructive-verb census over all workflows: broader than the ask; other workflows legitimately issue writes. Cut; the new check is step-scoped to bodies that mention the Hetzner API or token.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` filtered per planned file (the workflow, ADR-282, the runbook, the test):
None. (Re-run at work time; the check is a snapshot.)


## User-Brand Impact

- **If this lands broken, the user experiences:** the next auto-filed orphan issue shows a garbled or misleading Remedy block (the operator, who is the only reader of these issues, loses the survivor list or follows a stale step); no end-user surface is touched.
- **If this leaks, the user's workflow is exposed via:** nothing new; the change removes a printed destroy recipe and prints no secret (the `TOKEN=` line fetches from Doppler at run time and is unchanged).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** this change only subtracts a destroy affordance from operator-facing issue text, so it cannot raise exposure; a higher tier would be for a change that adds a write path.
- `threshold: none, reason: the touched workflow neither handles end-user data nor adds a write path; it deletes printed destroy text from operator-facing issue bodies.`

## Guard Contract

### Guard 1 - drift-workflow issue bodies print no Hetzner write or Doppler destroy call

**Property.** No step in `scheduled-terraform-drift.yml` whose comment-stripped `run:` body mentions the Hetzner API or `HCLOUD_TOKEN` contains a Hetzner write verb, and no step's body anywhere contains a Doppler `configs|environments|projects delete`.

**Assembly.** The population is every step of every job in the parsed YAML (not the two filers by name or line: both filers share the step name "File an issue for orphaned rehearsal hosts", and a future third issue-body printer must be covered with no edit). Chokepoint: one python `yaml.safe_load` helper that yields (job, step name, `run` body) for ALL steps, then `strip_comments` per body, then step-scoped matching. The write-verb check is scoped per step body rather than per line because the filers split the verb and the URL across separate `echo` lines (a same-line `api.hetzner.cloud` match misses the old recipe); the Doppler check is whole-workflow because that destroy needs no URL co-occurrence. The workflow path is a parameter so the mutation rows point at a sandbox copy.

**Mutation matrix.**

| # | Mutation (on a sandbox copy of the workflow) | Must be |
|---|---|---|
| 1 | Re-insert the old `echo 'curl -sS -X DELETE -H "Authorization: Bearer $TOKEN" \'` and URL echo after the `done` echo of the rung-2 filer | RED |
| 2 | Same injection in the inngest filer only, after a compliant rung-2 filer (second member after a compliant first) | RED |
| 3 | Inject `echo 'doppler configs delete <name> -p soleur'` (and separately the `environments delete` form) in a body that never mentions the Hetzner API | RED |
| 4 | Spell the verb as `--request DELETE`, `-XDELETE` and `hcloud volume delete` in a Hetzner-mentioning body | RED (each) |
| 5 | Replace both filers' read-only `label_selector` loops with `echo noop` (guard's own dispatch/anti-vacuity: scan would pass over nothing) | RED via the positive row |
| 6 | Rename one filer step so the exactly-two count falls to one | RED via the positive row |
| 7 | Move a write call into a `#`-prefixed line only | GREEN (comment-stripped; harness must-PASS, see below) |

**Harness rows.** (a) Suite-edit that must go RED: change the helper to read an empty path or drop the yield loop so it examines zero steps; the "at least N steps examined" non-vacuity floor must fail. (b) Must-PASS inputs that are not the canonical: a sandbox copy with the Remedy prose reworded differently, with `gh api -X POST` in a step that never mentions Hetzner (the step-scoped check must not false-fail a legitimate GitHub write), and a comment-only mention of `-X DELETE`.

**Anchor.** The check compares live YAML to a fixed shape, not a stored value; there is no hash or count to weaken in one diff. The only stored number is the suite's anti-vacuity floor (`-lt 61` raised to the realized count): a diff could lower it, so the floor line, its FATAL message and its comment are edited together and the number is stated as the realized `PASS+FAIL` (the file's own rule). The independent anchor is CI running the suite on the PR.

## Implementation Phases

Files named by phase; line numbers are as of branch point and are located by content anchor at work time.

### Phase 1 - RED first (cq-write-failing-tests-before)

Edit `plugins/soleur/test/token-drift-workflow-causes.test.sh` (before touching the workflow):

1. Add `all_run_bodies <wf>`: python + `yaml.safe_load`, iterating every job's steps, printing a record per step (job, step name, `run` body), parameterised on the workflow path (so mutation rows use a sandbox copy). Do NOT reuse `step_get name:` (it returns the first of the two same-named filers).
2. Add the new section after S4 (before the Results line):
   - Check 1 (Hetzner write, step-scoped): for each step body (comment-stripped) mentioning `api.hetzner.cloud` or `HCLOUD_TOKEN`, no match of `(-X|--request)[[:space:]=]*\\?["']?(DELETE|PUT|POST|PATCH)|-X(DELETE|PUT|POST|PATCH)|hcloud[[:space:]].*[[:space:]](delete|create|update)`.
   - Check 2 (Doppler destroy, whole workflow): zero matches of `doppler[[:space:]]+(configs|environments|projects)[[:space:]]+delete`.
   - Check 3 (positive/anti-vacuity): exactly 2 steps named "File an issue for orphaned rehearsal hosts"; each contains `for k in servers volumes ssh_keys firewalls` and a `label_selector=` curl without `-X`; one carries `app%3Dsoleur-rung2-rehearsal`, the other `app%3Dsoleur-inngest-provision-rehearsal`; total steps examined >= a stated floor.
   - Check 4 (mutation, one combined pass/fail): control GREEN on an unmutated sandbox copy; injected `-X DELETE` echo RED; injected `doppler configs delete` echo RED; must-PASS variants (comment-only `-X DELETE`, `gh api -X POST` in a non-Hetzner step) GREEN.
3. Raise the anti-vacuity floor: run the suite, read the realized `PASS+FAIL`, then set guard, FATAL message and the "Raised 61 -> N" comment to that same number (expected 65: four new `pass/fail` calls).
4. Run it against the unchanged workflow and confirm Checks 1, 2 RED (the 4 old lines) and the mutation control behaves; record the RED output in the PR body.

### Phase 2 - GREEN: the workflow edit

Edit `.github/workflows/scheduled-terraform-drift.yml` (both filers), following [ci-workflow-authoring.md](../../../plugins/soleur/skills/ship/references/ci-workflow-authoring.md): `{ echo ...; } > file` pattern is already used; no heredocs; every new `echo` line stays at the existing block indentation (a column-0 line ends the YAML block); mind quote nesting in `echo '...'` vs `echo "..."` and backslash escapes.

Rung-2 filer ("Orphaned rung-2 rehearsal resource(s) on Hetzner"), per CTO text:

- Keep the `Dispatch ... teardown_only=true` paragraph as is.
- Replace from `echo "If that arm reports survivors, ..."` through the Doppler paragraph with:
  - prose: "If that arm reports survivors, they are unreachable through Terraform. The block below is **read-only**: it lists every object still carrying the rehearsal label, with its id. It prints no delete call on purpose. Reclaiming a survivor is a Hetzner write, so it is an owner-authorised action (the owner tells an agent session to reclaim the listed ids), not a command to paste from an issue body." (as `echo` lines);
  - the fence: keep the `TOKEN=` line, add `# READ-ONLY: list every stranded rehearsal object with its id` (replaces the old `# list every ...` echo), keep the `for k in ... done` loop; delete the `# then, per object (detach a volume ...)` echo, the `curl -sS -X DELETE ... \` echo and the `"https://api.hetzner.cloud/v1/<kind>/<id>"` echo;
  - Doppler paragraph: "The scratch Doppler config, if listed above, is destroyed with the box by that arm when state still owns it. If it survives, removing it is the same owner-authorised reclaim, not a command printed here. It holds a live GIT_DATA_LUKS_KEY and the production Better Stack ingest token, so it matters more than the box does." The new prose spells no `doppler ... delete` command.
- Keep the trailing `_Auto-created by the [terraform-drift workflow]..._` line.

Inngest filer ("Orphaned inngest rehearsal resource(s) on Hetzner"), per CTO text:

- Replace the second Remedy paragraph with: "That arm exists for exactly this case. If state has forgotten the resource, Terraform cannot reach it. The block below is **read-only**: it lists every object still carrying the rehearsal label, with its id. It prints no delete call on purpose. Reclaiming a survivor is a Hetzner write, so it is an owner-authorised action (the owner tells an agent session to reclaim the listed ids), not a command to paste from an issue body." Keep the dispatch sentence before it. No claim about what the teardown arm verifies.
- Fence: keep `TOKEN=`, insert the `# READ-ONLY:` comment after it, keep the loop, drop the two DELETE echoes.
- Doppler paragraph: "A stranded scratch Doppler environment (slug `rehearsal_*` in project `soleur-inngest`) is reclaimed the same way, as an owner-authorised action. It holds only throwaway values (the worst it leaks is the write-only ingest tokens), but it is not free to leave."

After the edit: extract each filer's `run:` body and `bash -n` it; confirm both bodies still `echo "" ` between sections; confirm no `-X` remains in the file.

### Phase 3 - sweep hits

- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` line ~187-188: replace the parenthetical with "...a wrong id, a pasted recipe; the drift workflow's issue bodies printed runnable DELETE recipes until #9927 item 8c removed them), not against a leaked read/write token." Status stays `accepted`; re-wrap to file width; no new ADR (factual erratum, not a decision change).
- `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md` line ~167: replace "or reclaim by API — the filed issue prints the exact calls." with "If the arm cannot remove a survivor (state forgot it), the filed issue lists the stranded objects read-only, with their ids. Reclaiming them is an owner-authorised action: ask an agent session to delete those ids. The issue no longer prints a delete call."
- Left untouched (decided): archived plans/specs quoting the recipe (history); `git-data-rung2-rehearsal.md` ~406 (still true); `workspaces-luks-cutover-workflow.test.sh` and the operator-script censuses (they scan other files).

### Phase 4 - verify (targeted only; CI is the authority)

Run: `bash plugins/soleur/test/token-drift-workflow-causes.test.sh`; `bash plugins/soleur/test/terraform-drift-step-order.test.sh`; `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`; `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh`; `bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh`; `bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`; `bun test plugins/soleur/test/terraform-target-parity.test.ts`; `python3 scripts/lint-guard-contract.py` on this plan. Check the first-attempt Edit on the workflow may error on the security-reminder hook (learning 2026-03-18) and succeeds on retry. Do not dispatch the workflow. No git stash; sync with main via merge commit.

### Phase 5 - ship notes

- PR title and body use "Ref #9927" only (no closing keyword in body, title or commits); #9927 stays open. Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- The diff touches `.github/workflows/`: ship announces `UNTRUSTED-CI` at mark-ready. The PR still merges through normal queued auto-merge; there is no agent `--admin` fallback, so if a BEHIND livelock occurs the operator merges it by hand.
- Optional follow-up to file under #9927 (not this PR): make the fence fetch `HCLOUD_TOKEN_READONLY` with no fallback so a pasted write 403s by construction, after confirming the secret is minted in `prd_terraform`.

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml`
- `plugins/soleur/test/token-drift-workflow-causes.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`
- `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9927-drift-delete-recipes/decision-challenges.md` (created at plan time)
- `knowledge-base/project/specs/feat-one-shot-9927-drift-delete-recipes/tasks.md`

Path-glob check: no globs prescribed; all four edited paths verified to exist via `git ls-files`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "remove the runnable Hetzner DELETE recipes that .github/workflows/scheduled-terraform-drift.yml prints into drift-issue bodies" [brief] | Phase 2; Files to Edit: scheduled-terraform-drift.yml | mapped |
| 2 | "Drop the DELETE recipe (and the TOKEN fetch only if nothing left needs it — keep the list loop, which is read-only), keep the rest of the issue body intact" [brief] | Phase 2 (TOKEN line kept because the list loop needs it) | mapped |
| 3 | "the Remedy prose that says \"reclaim it by the API directly — the exact calls are\" must be reworded so it stays true once the DELETE call is gone" [brief] | Phase 2 (both Remedy paragraphs, CTO text) | mapped |
| 4 | "Repo-wide sweep by SUBJECT before editing: ... and decide each hit" [brief] | Research Reconciliation table; Phase 3 | mapped |
| 5 | "add a regression assertion (test-first per cq-write-failing-tests-before) that the drift workflow prints no `-X DELETE` / Hetzner write call in its issue bodies, placed in the most fitting existing test file" [brief] | Phase 1; Guard Contract; Files to Edit: token-drift-workflow-causes.test.sh | mapped |
| 6 | "also check any lint that scans workflows for Hetzner write verbs or `-X DELETE` ... so the edit passes them" [brief] | Research Reconciliation (census row); Phase 4 | mapped |
| 7 | "Locally run only targeted or TEST_GROUP=affected suites (CI is the authority)" [brief] | Phase 4 | mapped |
| 8 | "record every decision as a row `| Item | Class | Ruling |` in knowledge-base/project/specs/feat-one-shot-9927-drift-delete-recipes/decision-challenges.md" [brief] | Files to Create: decision-challenges.md | mapped |
| 9 | "\"Ref #9927\" only: no closing keyword in body, title or commits; #9927 stays open" and "note any ship UNTRUSTED-CI / no-agent --admin note for workflow diffs" [brief] | Phase 5; AC10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit: .github/workflows/scheduled-terraform-drift.yml | asks 1-3 | asked |
| Files to Edit: plugins/soleur/test/token-drift-workflow-causes.test.sh | ask 5 | asked |
| Files to Edit: ADR-282 residual bullet | ask 4 ("any runbook/ADR/test/learning that quotes the recipe") | asked |
| Files to Edit: inngest-provision-rehearsal.md line | ask 4 ("tells an operator to paste it") | asked |
| Files to Create: decision-challenges.md | ask 8 | asked |
| Files to Create: tasks.md | — | inferred — justification: the plan skill derives tasks.md as the contract soleur:work executes against; without it the work phase has no task list |
| Rewording the Doppler `configs delete` / `environments delete` one-liners | — | inferred — justification: they are the same pasted-destroy class on the same lines (the rung-2 config holds a live GIT_DATA_LUKS_KEY); leaving them while removing the Hetzner recipe defeats the intent of ask 1; CTO-ratified |
| Mechanism: sandbox mutation row and anti-vacuity floor in the new guard | ask 5 ("test-first") | asked |
| Mechanism: positive anti-vacuity row (exactly two filers keep the read-only loop) | — | inferred — justification: a scan over the wrong population passes trivially, so the guard must prove it examined both filers (Guard Contract harness rule) |
| Phase 5 follow-up note (HCLOUD_TOKEN_READONLY) | — | inferred — justification: the ask keeps the read/write token fetch for the list loop; recording the hardening under #9927 stops it being lost |

### Split Assessment

- Subsystems touched: 3 - .github/workflows, plugins/soleur/test, knowledge-base (ADR, runbook, specs)
- Planned files: 6 | Estimated changed lines: ~170
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `grep -nE -- '-X[[:space:]]*(DELETE|PUT|POST|PATCH)|--request' .github/workflows/scheduled-terraform-drift.yml` returns no line that is inside an issue-body `echo` (the whole-file count of `-X DELETE` is 0).
- [x] AC2: `grep -nE 'doppler[[:space:]]+(configs|environments|projects)[[:space:]]+delete' .github/workflows/scheduled-terraform-drift.yml` returns 0 lines.
- [x] AC3: each of the two filers' rendered bodies still contains the label_selector `for k in servers volumes ssh_keys firewalls` loop with `app%3Dsoleur-rung2-rehearsal` / `app%3Dsoleur-inngest-provision-rehearsal` respectively, a `# READ-ONLY:` comment, the `teardown_only=true` dispatch sentence, the Better Stack/LUKS-key warning (rung-2) and the "Auto-created by" footer.
- [x] AC4: neither body contains "the exact calls are", "reclaimed by the API directly" or "reclaim it by the API directly" (`git grep` over the workflow returns 0).
- [x] AC5: `bash -n` passes on both filers' extracted `run:` bodies; `python3 -c 'import yaml;yaml.safe_load(open(".github/workflows/scheduled-terraform-drift.yml"))'` exits 0.
- [x] AC6 (superseded by the review round, see Implementation Outcome): the new guard section in `token-drift-workflow-causes.test.sh` is RED on the pre-edit workflow (Phase 1 evidence pasted in the PR body) and GREEN after Phase 2; its mutation row proves RED on injected `-X DELETE` and `doppler configs delete`, and GREEN on the comment-only and non-Hetzner `gh api -X POST` inputs.
- [x] AC7: the suite's anti-vacuity floor, its FATAL message and its comment name the same number, equal to the realized `PASS+FAIL` printed by the run.
- [x] AC8: ADR-282 residual bullet no longer claims the drift workflow prints runnable DELETE recipes in the present tense and cites #9927 item 8c; ADR status unchanged; runbook line no longer says "the filed issue prints the exact calls".
- [x] AC9: the targeted suites in Phase 4 all pass; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [x] AC10: PR body/title/commits contain "Ref #9927" and no closing keyword (`Closes|Fixes|Resolves`) for #9927.

### Post-merge

- [ ] None required (no apply, no dispatch). The next scheduled drift run that finds an orphan renders the new body; no operator step.

## Test Scenarios

- Unchanged workflow: new Checks 1 and 2 RED, naming the 4 lines (RED-first evidence).
- Edited workflow: Checks 1-4 GREEN.
- Sandbox mutants per the Guard Contract matrix.
- Regression suites listed in Phase 4 stay green (they never asserted the removed strings).

## Observability

```yaml
liveness_signal:
  what: the twice-daily orphan sweeps in the drift workflow and the infra-drift issue each files when it finds a survivor
  cadence: twice daily (scheduled run) plus per-PR CI for the guard
  alert_target: the infra-drift labelled GitHub issue and the existing drift ops email; the new guard reddens the PR check
  configured_in: .github/workflows/scheduled-terraform-drift.yml
error_reporting:
  destination: GitHub Actions run annotations and the filed infra-drift issue; no Sentry change (no application code touched)
  fail_loud: the guard section in token-drift-workflow-causes.test.sh exits non-zero and names the offending step, so the PR check goes red
failure_modes:
  - mode: a later edit re-adds a Hetzner write call or a Doppler destroy one-liner to an issue-body printer
    detection: the new step-scoped Hetzner write check and the whole-workflow Doppler destroy check, run by CI on every PR touching the workflow
    alert_route: red PR check on the author's PR
  - mode: an echo quoting slip leaves the filer body unparseable or truncated
    detection: YAML parse of the workflow plus bash -n of each extracted filer body in the same suite and in Phase 4
    alert_route: red PR check
  - mode: the guard scans the wrong population and passes over nothing
    detection: the positive row requires exactly two filers, each keeping the read-only label_selector loop, and a steps-examined floor
    alert_route: red PR check
logs:
  where: GitHub Actions run logs for the drift workflow and the test CI job
  retention: the repository's Actions log retention window
discoverability_test:
  command: python3 -c "import re;print(len(re.findall(r'-X +DELETE',open('.github/workflows/scheduled-terraform-drift.yml').read())))"
  expected_output: "0"
```

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO agent ruled all five forks (Remedy wording, Doppler one-liners, ADR-282 erratum, runbook line, assertion shape and home). Rulings are recorded as rows in `decision-challenges.md`. No architectural decision is made (ADR-282 gets a factual erratum only), so no `## Architecture Decision (ADR/C4)` section; no C4 impact: no actor, external system, container or access relationship changes (this edits issue text the existing GitHub Actions to GitHub Issues edge already produces).

Product/UX Gate: not relevant (no UI surface). GDPR gate: no regulated-data surface touched. Observability section: not required (no code under `apps/*/server`, `apps/*/src`, `apps/*/infra`, `plugins/*/scripts`; no new infrastructure surface); the operator-visible signal of success is the orphan issue body itself. Encryption posture: no store or connection introduced.

## Research Insights

- Learnings applied: build multi-line issue bodies with `echo` + `--body-file`, never a heredoc inside `run: |`, and keep every continuation line at block indentation (2026-03-21 and 2026-04-02 learnings); a check that cannot report is indistinguishable from a pass, so the guard is mutation-tested (2026-07-27); a forbiddance guard must match by shape, not the exact deleted string (2026-07-18), hence the verb regex over `DELETE|PUT|POST|PATCH` plus `hcloud ... delete`; `cq-assert-anchor-not-bare-token` and this suite's rule 3 (nothing grepped from the raw workflow; `run:` bodies comment-stripped). No existing learning covers a workflow echoing destroy commands into auto-filed issue bodies; this PR is the first instance (capture at ship via compound).
- Premise Validation, Property List and Cut List above are carried forward from Phases 0.6 and 0.6b.
- Edit-hook note: the first Edit/Write on a workflow file may fail on the security-reminder hook; retry succeeds.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above (`none`, with the scope-out bullet).
- The two filers share the step name "File an issue for orphaned rehearsal hosts"; `step_get name:` returns only the first. The new helper iterates all steps.
- New prose must not spell the destroy command it replaces, or the guard fires on the prose (`doppler ... delete`, `-X DELETE`). The CTO text avoids it; keep it that way when rewording.
- `echo "..."` lines containing backticks or `$` need the same escaping the neighbouring lines use; `bash -n` on the extracted bodies is the check, and a column-0 line breaks the YAML block.
- The anti-vacuity floor in the test file is edited in three places (guard, FATAL message, comment) and must name the realized number.

## Implementation Outcome (added at QA, 2026-10-15)

The shipped guard differs from the Guard Contract above; the contract text is kept as history.

- **Final design (R1-R5, `token-drift-workflow-causes.test.sh`).** The scan reads every string leaf of every step, job-level key and workflow-level key, in a joined and a flattened form, ungated by a same-step Hetzner mention for method flags, `hcloud` write verbs and Doppler delete/destroy/revoke (body flags stay scoped to a Hetzner/Doppler API step). A filer must assemble its body inline. The mutation table (53 per-spelling rows, plus a verdict-rule control) runs in-process off the same code; floor 61 to 163.
- **Superseded plan rows.** Comment-only input is now flagged (RED), not GREEN: comment stripping was dropped because a match in a comment can only false-RED and a `#` line in a heredoc is printed content (security, structural and simplicity seats). A non-Hetzner `gh api -X POST` is flagged only when it carries a non-GET explicit method on this workflow, which has none today; the unscoped method check replaced the per-step Hetzner gate. AC6's "GREEN on the comment-only input" no longer holds by design.
- **Docs beyond the plan.** The reclaim procedure for state-forgotten survivors now lives in `inngest-provision-rehearsal.md` ("Reclaiming survivors that state forgot"), bounded by name for Doppler objects, with a per-item live-state read, HTTP 200 on the listing, per-command owner go-ahead. ADR-282 got a dated Addendum and a dateless bullet edit; two runbook statements that turned false were corrected (`inngest-luks-cutover-6894.md`, `infra-credential-tiers-8209.md`).
- **Verified by running.** AC1, AC2, AC4: 0 hits. AC3/AC5: both filers keep the READ-ONLY comment, the dispatch sentence, the `label_selector` loop and the footer; `bash -n` clean. AC7: guard, FATAL text and comment all say 163 = realized 163/163. The guard is RED against the pre-fix workflow (origin/main) and mutants of the guard itself are each caught.
