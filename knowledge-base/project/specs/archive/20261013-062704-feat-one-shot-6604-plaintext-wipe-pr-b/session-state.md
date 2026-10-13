# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-01-feat-workspaces-plaintext-wipe-pr-b-convergence-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Draft PR: #9348

### Errors
- `iac-plan-write-guard.sh` blocked the first plan write (the phrase "out-of-band"); reworded, no opt-out used.
- The first repo-research and learnings reports were shallow (they missed the Guard-5 rows in the wipe suite and suggested published-doc edits); re-verified directly against the code.

### Decisions
- D1: protect the sole-copy LUKS volume with Terraform `prevent_destroy` + `delete_protection` on `hcloud_volume.workspaces_luks` in PR B (CTO BF-1; provider 1.63.0 verified). Recorded as UC-2 in decision-challenges.md.
- D2/D3: `CONFIRM_WIPE` becomes a refusal stub; `git mv` the wipe suite to `workspaces-luks-rollback-refusal.test.sh`, keeping the Guard-5 rows and loopback LW-P2/P3/P4. Test-gate Q4 needs no edit.
- D4: evidence uses `PENDING-EVIDENCE(<field>)` markers in the destruction record and the ADR-119 addendum only. The CLO audit `2026-10-counsel-review-6604.md` is BLOCKED until resume. `docs/legal/**` is untouched.
- D5: final PR body uses `Ref #6604` (follow-through label; the sweeper closes it) + `Closes #6588`. Recorded as UC-1.
- D6: PR B is merge-ready before D; after the forget, the pause ends only by merging PR B (48 h max); a read-only drift plan gates the post-merge `manual-rerun`.

### Components Invoked
- Skills: soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan.
- Agents: repo-research-analyst, learnings-researcher, functional-discovery, cto, clo, cpo, spec-flow-analyzer, ADR-083 advisor consult, dhh/kieran/simplicity reviewers, architecture-strategist, verify-the-negative sweep, terraform-architect, security-sentinel, user-impact-reviewer, test-design-reviewer, observability-coverage-reviewer.

### Operator constraints
- No SSH, no dashboard, no prod writes, no dispatches. The destructive dispatch D, the forget, and the post-merge apply each need a per-command operator go-ahead.
- Operator hold (plan `## Operator Holds`): PR B stays a draft until D concludes with delete_issued=true, the forget has run, the evidence is filled, CLO re-attests, and `infra-validation` is re-run green.

## Review + Compound Phase
- Review: 11/11 seats, 0 P1; fixes in 9cfcd1d486, trailer e333a4c3ec (`Reviewed-Coverage: full 11/11`).
- Compound: learning `knowledge-base/project/learnings/2026-10-01-the-guards-i-wrote-to-protect-the-sole-copy-scanned-a-shape-the-attack-did-not-take.md`; routed one bullet to plan-sharp-edges.md.
- Archival of this plan/spec is DEFERRED to the post-hold resume session (the resume reads them; archive-kb would orphan the PR body's resume pointer).
- Local gate skipped by operator direction ("rely on CI"); lefthook absent from PATH (#8271).

## Operator gate log (append-only)

- 2026-10-01 (UTC 21:30Z): step 1 DONE by explicit per-command go-ahead. `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` went `active` -> `disabled_manually` (verified via the Actions workflows API). BOTH MUST BE RE-ENABLED after #9348 merges (step 6), then dispatch manual-rerun (own go-ahead).
- 2026-10-01: #9381 merged (probe on main); tracker #9380 `earliest` re-baselined to 2026-10-01; plan note committed in abca1c78b1. Preconditions re-read before step 2: wipe/forget workflow files unchanged vs 59abf6a76c on main; `workspaces-luks-cutover` environment has required reviewer deruelle (non-empty).
- 2026-10-01 (UTC 21:38Z): DECISION: hold step 2 (the wipe dispatch) until #9372 (web-2 LUKS rebirth, parallel session) has finished its destructive workflow and its ledger/state edits have merged; then rebase #9348 onto them. Reasons: #9372 and #9348 edit the same `for_each` volume, ledger row and `workspaces_volume_id` line; the two apply workflows are paused (disabled_manually) and #9372 may need them; no deadline pressure (abandon 2026-10-15, ledger exception expires 2026-10-22). Re-enabling the two apply workflows while waiting needs its own per-command go-ahead (not yet given).
- 2026-10-08 (UTC 15:32Z): step 1 DONE by explicit per-command go-ahead. `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` went `active` -> `disabled_manually` (verified via the Actions API; nothing queued or running on either). PR #9348 at a308d9b071: CI 93 pass, only the expected `plan (apps/web-platform/infra)` hold red; 0 behind main. #9372 idle since 2026-10-07 20:12Z (web-2 replaced, id 169271252). BOTH WORKFLOWS MUST BE RE-ENABLED after #9348 merges (step 6), then dispatch manual-rerun (own go-ahead). Step 2 (wipe dispatch) NOT yet run; needs its own go-ahead naming the exact command.
- 2026-10-08 (UTC 15:42Z): step 2+3 DONE by explicit per-command go-ahead and owner approval. Run 37801674740 (workspaces-luks-cutover.yml) concluded success: wipe result=wiped arm=first_wipe volume_id=105149570 bytes=21474836480 readback=zero (15:41:41Z), DETACH_ACTION=660248143891602, DELETE_ISSUED=true, POST_RESULT=ok, PLAINTEXT_ONLY=0, preconditions "both apply workflows paused+idle, workspace_count=9>=8". Read-only Hetzner check (HCLOUD_TOKEN_READONLY): GET /volumes/105149570 = 404 not_found (web-1 server 123931471 answered 200, so the 404 is a real absence), LUKS volume 106443278 attached to web-1 and web-1 running, protection.delete=false (delivered by the post-merge SSH apply). Step 4 (forget workflow) NOT yet run; needs its own go-ahead. The 48 h merge bound starts at the forget run updated_at.
