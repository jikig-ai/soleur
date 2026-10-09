---
title: "docs: add bwrap canary-signature diagnosis rows + ci-deploy.sh delivery check to deploy-status-debugging reason table"
type: docs
date: 2026-10-09
slug: docs-deploy-status-bwrap-diagnosis
branch: feat-one-shot-deploy-status-bwrap-diagnosis
issue: none
lane: cross-domain
---

# docs: add bwrap canary-signature diagnosis rows + ci-deploy.sh delivery check to deploy-status-debugging reason table

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch; one-shot pipeline entry.)

## Enhancement Summary

**Deepened on:** 2026-10-09
**Sections enhanced:** Research Insights (learnings cross-check), Observability-gate disposition, Network-Outage Deep-Dive
**Research agents used:** none — docs-only scope, deepen-pass run inline in the planning subagent (no Task-spawn available); every claim verified by direct command instead

### Key Improvements

1. Verified the brief's "release/deploy skip by path filter" claim FALSE — `plugins/soleur/skills/**` is inside `web-platform-release.yml`'s push filter and `reusable-release.yml`'s `check_changed` pathspec; merge triggers a release+deploy arm (recorded in Research Reconciliation; tasks.md Phase 3 carries the correction).
2. Verified both canary stderr signatures byte-for-byte against this branch (`bwrap-shim/bwrap` is exactly 424 lines; line 424 is the `exec` of `/usr/bin/bwrap`) and the `ci_deploy_sha256` field against its producer (`cat-deploy-state.sh`, #9151) — plus the canned equivalent `scripts/check-deploy-script-parity.sh`.
3. Fixed a stale learnings path (`bug-fixes/` segment) and hardened AC-4 to the merge-base diff form with a planning-artifacts carve-out (sharp-edges pass).

### New Considerations Discovered

- The docs change is NOT deploy-skipping: the vendored plugin bundle carries `skills/**` reference docs, so post-merge the release arm runs — expected, and it is what delivers the corrected runbook to the host mount.

## Overview

Incident #9871 established that a deploy-blocking change to `apps/web-platform/infra/ci-deploy.sh` does not take effect at merge time: the host runs the installed copy until `apply-deploy-pipeline-fix.yml` (push-triggered on that path) delivers it. The same incident produced two distinct `canary_sandbox_failed` stderr signatures with one root cause (a file-cap'd `/usr/bin/bwrap`), and the signature a run shows depends on whether the container still carries the stale `--cap-add SYS_ADMIN` grant. This plan adds those two signature diagnosis rows — and the no-SSH delivery-verification read (`ci_deploy_sha256` vs the sha256 of `origin/main`'s `ci-deploy.sh`) — to the Reason Taxonomy table in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`.

## Research Insights

**Premise Validation (Phase 0.6).** Every cited artifact verified live on 2026-10-09:

- Issue #9871 `CLOSED` — "Deploys blocked: file-cap'd /usr/bin/bwrap refuses all invocations in-container (v0.333.1 canary_sandbox_failed)". Its comment thread carries the two-layer explanation verbatim: "capped image + cap-add container → 'Unexpected capabilities but not setuid' (ambient/bounding grant); capped image + clean container → execve EPERM rc126 (file caps outside bounding set)", plus "The host's installed ci-deploy.sh still carried --cap-add SYS_ADMIN until apply-deploy-pipeline-fix delivered the reverted script (push-triggered runs for the merge were cancelled; manual workflow_dispatch 37976212395 applied it)".
- PR #9887 `OPEN`, `isDraft: true`, `headRefName: feat-one-shot-deploy-status-bwrap-diagnosis` — the ship target; no second PR.
- Run 37976212395: `Apply deploy-pipeline-fix`, `workflow_dispatch`, `success`. Run 37980286319: `Web Platform Release`, `workflow_run`, `success` — the green deploy.
- `.github/workflows/apply-deploy-pipeline-fix.yml` `on.push.paths` contains exactly `apps/web-platform/infra/ci-deploy.sh` (plus `workflow_dispatch` escape hatch) — the "push-triggered on that path" claim holds.
- `ci_deploy_sha256` is a real emitted field: `apps/web-platform/infra/cat-deploy-state.sh` computes `sha256sum` of `/usr/local/bin/ci-deploy.sh` per request into the `/hooks/deploy-status` body (added for #9151 as "the parity anchor for scripts/check-deploy-script-parity.sh"; absent = old script, empty = read failure).
- Signature 1 verbatim: `bwrap: Unexpected capabilities but not setuid, old file caps config?` — bwrap's own guard; Dockerfile line ~146 and `apps/web-platform/server/agent-outer-wrap.ts` both state released bwrap (0.8–0.12) dies on `real_uid != 0 && has_caps()` and that upstream has no file-cap support.
- Signature 2 verbatim: `/usr/local/bin/bwrap: line 424: /usr/bin/bwrap: Operation not permitted` — `apps/web-platform/infra/bwrap-shim/bwrap` is exactly 424 lines; line 424 is `exec "$REAL" --add-seccomp-fd "$bpf_fd" "${argv[@]}"` with `REAL=${SOLEUR_BWRAP_REAL:-/usr/bin/bwrap}`; installed at `/usr/local/bin/bwrap` by Dockerfile `COPY --from=builder --chmod=0755 /app/infra/bwrap-shim/bwrap /usr/local/bin/bwrap`. execve EPERM on a file-cap'd binary outside the container bounding set → rc 126.
- Parity command verified: `git show origin/main:apps/web-platform/infra/ci-deploy.sh | sha256sum` → `4cbeee68…` matches the worktree checkout. The canned no-SSH equivalent is `scripts/check-deploy-script-parity.sh` (repo-sha vs `.ci_deploy_sha256` vs newest Better Stack `DEPLOY_SCRIPT_SHA` row).

**Property List (Phase 0.6b).**

1. A future `canary_sandbox_failed` diagnosis maps the observed stderr signature to the file-cap root cause without re-deriving it from an incident thread.
2. The doc encodes "merged ≠ delivered" for `ci-deploy.sh` and names the no-SSH verification read.

**Cut List (Phase 0.6b).** None — the ask's only mechanism is table rows in an existing runbook; no repo mechanism already carries these signatures (grep over `plugins/soleur/skills/` + `knowledge-base/engineering/operations/runbooks/` finds `Unexpected capabilities` only in Dockerfile/`agent-outer-wrap.ts` comments; `canary-probe-set.md` covers probe self-report verdicts, a different surface).

**Relevant files.**

- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — Reason Taxonomy table (`| reason | exit_code | Meaning | Remediation |`); `canary_sandbox_failed` row already points at `canary-probe-set.md#blocking-bwrap-sandbox-probe--reading-its-self-report-8016-pr-8026`.
- Consumers: `plugins/soleur/skills/postmerge/SKILL.md` (~line 533) and `plugins/soleur/skills/ship/SKILL.md` (~line 1157) link this runbook — no pointer updates needed.
- `apps/web-platform/infra/ci-deploy.sh` (host-installed copy is the drift surface), `apps/web-platform/infra/cat-deploy-state.sh`, `scripts/check-deploy-script-parity.sh` — cited, not edited.

**Learnings applied.**

- `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` — the runbook already splits proxy-layer vs provisioner-layer verification; the new rows' remediation belongs to the diagnosis layer (`.ci_deploy_sha256` read), and the doc's existing "When NOT to use this probe" section stays untouched.
- `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` — the workflow's own header cites this drift cycle; the rows encode its incident instance.
- `knowledge-base/project/learnings/2026-07-18-backlog-issue-with-merged-code-closes-on-deploy-gate-not-merge.md` — same lesson shape as the one being encoded: merged ≠ delivered, and the close/verify gate is the delivered artifact, not the merge event.

**Related issues/PRs/runs.** #9871 (incident, closed), #9874 / commit `d7dfd05aac` (file-cap revert), #9767 / `5e75548373` (introduced `--cap-add SYS_ADMIN`), #9151 (`ci_deploy_sha256` + parity script), run 37976212395 (manual apply), run 37980286319 (green deploy), PR #9887 (ship target).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| "Ship as docs-only PR (release/deploy skip by path filter)" | `web-platform-release.yml` `on.push.paths` includes `plugins/soleur/**` excluding only `plugins/soleur/docs/**` and `plugins/soleur/test/**`; `reusable-release.yml` `check_changed` `path_filter` is `apps/web-platform/ plugins/soleur/ :(exclude)plugins/soleur/docs/ :(exclude)plugins/soleur/test/`. The target file is under `plugins/soleur/skills/` — merge WILL trigger a release+deploy arm (runtime plugin content is vendored into the image). | Plan ships the docs diff anyway (vendoring the corrected runbook onto the host mount is desirable); drop the "deploy-skip" assumption — the PR body must not promise a skipped deploy, and post-merge the release arm is expected, not anomalous. |
| "`bwrap: Unexpected capabilities but not setuid, old file caps config?` = file-cap'd binary OR ambient/bounding caps … released bwrap 0.8–0.12 dies on `real_uid!=0 && has_caps()`" | Verbatim in Dockerfile comment and `agent-outer-wrap.ts`; matches #9871 comment layer 1. | Row written as stated. |
| "`/usr/local/bin/bwrap: line 424: /usr/bin/bwrap: Operation not permitted` rc=126 = execve EPERM — file caps not covered by container bounding set" | Shim is 424 lines; line 424 is the `exec "$REAL"` of `/usr/bin/bwrap`; #9871 comment layer 2 matches (clean container). | Row written as stated. |
| "Verify delivery by comparing `ci_deploy_sha256` … against `git show origin/main:apps/web-platform/infra/ci-deploy.sh \| sha256sum`" | Field emitted per-request by `cat-deploy-state.sh`; command verified; `scripts/check-deploy-script-parity.sh` is the canned multi-host equivalent. | Remediation cells cite both forms. |

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 most recent) scanned for `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`: zero bodies name the file.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the artifact is an operator-facing debugging runbook; a wrong row wastes a future incident responder's triage time (misdiagnosis cost, internal).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector — the file is already vendored into the deployed plugin bundle and reveals only internal runbook detail already present in the repo.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** docs-only edit to an internal ops runbook; no user data, no behavioral surface, no new distribution channel beyond the existing plugin vendoring.

## Files to Edit

- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — Reason Taxonomy table: add two `canary_sandbox_failed` diagnosis rows keyed by stderr signature (draft text in Proposed Rows below), each Remediation carrying the "merged ≠ delivered" parity check.

## Files to Create

- None.

## Proposed Rows

Columns are the table's existing `| reason | exit_code | Meaning | Remediation |`. The webhook `reason` stays `canary_sandbox_failed` (exit_code `1` — the state-file code, not the inner `rc=126`); the stderr signature discriminates inside `Meaning`. Exact wording is the implementer's, but must carry the quoted anchors below.

1. **Signature:** stderr `bwrap: Unexpected capabilities but not setuid, old file caps config?` — a file-cap'd `/usr/bin/bwrap` OR ambient/bounding capabilities reaching a non-root exec (e.g. a stale installed `ci-deploy.sh` still passing `--cap-add SYS_ADMIN`); released bwrap 0.8–0.12 aborts on `real_uid != 0 && has_caps()` (upstream has no file-cap support).
   **Remediation:** check whether the merged `ci-deploy.sh` reached the host — compare `.ci_deploy_sha256` in the `/hooks/deploy-status` body against `git show origin/main:apps/web-platform/infra/ci-deploy.sh | sha256sum` (or run `scripts/check-deploy-script-parity.sh`); a merge is NOT delivery — `apply-deploy-pipeline-fix.yml` (push-triggered on that path, or a `workflow_dispatch` re-run when the push arm is cancelled) is. If drifted, dispatch the apply; if the host script is current, the image itself still carries the `setcap` — confirm the deployed tag postdates the #9874 revert build.
2. **Signature:** stderr `/usr/local/bin/bwrap: line 424: /usr/bin/bwrap: Operation not permitted` (the shim's final `exec`, inner rc 126) — execve EPERM: file caps on the real binary not covered by the container bounding set (capped image + clean container, no `--cap-add`).
   **Remediation:** the running image carries `setcap cap_sys_admin,cap_setuid,cap_setgid+ep` on `/usr/bin/bwrap` — deploy the cap-free tag (post-#9874 build; in #9871 the fix landed as `v0.334.1` after a `ci_not_green`-skipped arm was rerun). Same `ci_deploy_sha256` parity check applies if `--cap-add` symptoms persist after the image is clean.
3. **Resolution trail** (carried in the rows' prose or a trailing note): incident #9871 (two-layer explanation in its comment thread), apply run 37976212395, green deploy run 37980286319.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add diagnosis rows to plugins/soleur/skills/postmerge/references/deploy-status-debugging.md's reason table" | Files to Edit entry + Proposed Rows 1–2 | mapped |
| 2 | "a deploy-blocking change to apps/web-platform/infra/ci-deploy.sh does NOT take effect on merge — the host runs the INSTALLED copy until apply-deploy-pipeline-fix (push-triggered on that path) delivers it. Verify delivery by comparing ci_deploy_sha256 …" | Proposed Rows remediation cells (both rows carry the parity check + merged≠delivered lesson) | mapped |
| 3 | "Two canary signatures, same root cause — candidate table rows: `bwrap: Unexpected capabilities…` … `/usr/local/bin/bwrap: line 424…` rc=126" | Proposed Rows 1–2 | mapped |
| 4 | "Resolution trail: incident issue 9871 …; apply workflow run 37976212395; green deploy run 37980286319" | Proposed Rows item 3 | mapped |
| 5 | "Ship as docs-only PR (release/deploy skip by path filter). Draft PR 9887 already exists … do NOT open a second PR" | AC-4/AC-5 (docs-only diff; reuse PR #9887). The "skip by path filter" clause is corrected by Research Reconciliation — merge triggers the release arm; recorded, not silently obeyed. | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `deploy-status-debugging.md` reason table | "add diagnosis rows to plugins/soleur/skills/postmerge/references/deploy-status-debugging.md's reason table" | asked |
| `ci_deploy_sha256` parity remediation text | "Verify delivery by comparing ci_deploy_sha256 in the deploy-state JSON against `git show origin/main:apps/web-platform/infra/ci-deploy.sh \| sha256sum`" | asked |
| `scripts/check-deploy-script-parity.sh` citation | — | inferred — justification: it is the canned multi-host form of the exact check the ask prescribes (its own header: "the no-SSH parity read"); omitting it would prescribe raw curl where a maintained script exists |
| Resolution-trail citations | "Resolution trail: incident issue 9871 …; apply workflow run 37976212395; green deploy run 37980286319" | asked |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 1 | Estimated changed lines: ~15
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal ops-runbook documentation change.

## Acceptance Criteria

- [ ] AC-1: The Reason Taxonomy table in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` contains a `canary_sandbox_failed` diagnosis row whose Meaning carries the literal signature `bwrap: Unexpected capabilities but not setuid, old file caps config?` and attributes it to a file-cap'd `/usr/bin/bwrap` or ambient/bounding caps reaching a non-root exec (released bwrap 0.8–0.12, `real_uid != 0 && has_caps()`).
- [ ] AC-2: The table contains a second `canary_sandbox_failed` row whose Meaning carries the literal signature `/usr/local/bin/bwrap: line 424: /usr/bin/bwrap: Operation not permitted` and attributes it to execve EPERM — file caps on the real binary outside the container bounding set (capped image + clean container).
- [ ] AC-3: Both rows' Remediation cells state that merging a `ci-deploy.sh` change does not deliver it (host runs the installed copy until `apply-deploy-pipeline-fix.yml` runs) and prescribe the no-SSH parity check: `.ci_deploy_sha256` from `/hooks/deploy-status` vs `git show origin/main:apps/web-platform/infra/ci-deploy.sh | sha256sum` or `scripts/check-deploy-script-parity.sh`.
- [ ] AC-4: `git diff --name-only origin/main...HEAD` (merge-base form, not the moving tip) lists only `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` plus this feature's own planning artifacts under `knowledge-base/project/{plans,specs}/`; the work lands on the existing draft PR #9887 branch — no second PR is opened.
- [ ] AC-5: The rows or an adjacent note cite #9871, run 37976212395, and run 37980286319 as the resolution trail.
- [ ] AC-6: `markdownlint` passes on the edited file (table rows keep `|`-escaping conventions; no MD034 bare URLs in prose).

## Test Scenarios

- **unit** — Given the edited file, when `grep -c 'Unexpected capabilities but not setuid'` runs, then count >= 1; likewise `grep -c 'line 424'` >= 1 and `grep -c 'ci_deploy_sha256'` >= 1.
- **unit** — Given the edited file, when markdownlint runs on it, then zero findings.
- **integration** — Given the merged PR, when `web-platform-release.yml` fires on the merge SHA, then the release arm running is EXPECTED (path filter includes `plugins/soleur/skills/`); a skipped release would indicate the vendored runbook did not reach the host mount.

## Deepen-Pass Gate Dispositions

### Network-Outage Deep-Dive (Phase 4.5 — fired)

The `SSH` trigger substring matched (`no-SSH` in the Overview's verification guidance). The checklist's L3→L7 layers are each opted out with artifact: this plan documents an already-resolved incident (#9871 CLOSED; green deploy run 37980286319) and edits a runbook — it proposes no network-layer remediation and diagnoses no connectivity symptom. Layers: L3 firewall (opt-out — no connectivity claim in scope), L3 DNS/routing (opt-out — same), L7 TLS/proxy (opt-out — same), L7 application (opt-out — same). Telemetry emitted (`SOLEUR_RULE_APPLIED rule=hr-ssh-diagnosis-verify-firewall`).

### Observability gate (Phase 4.7 — detection analyzed, does not apply)

Step 1's path list does not classify `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` as pure-docs (it sits inside `plugins/*/skills/`, outside the `\.md$` exemption). The gate's own scoping parenthetical — "production code/infra (per plan Phase 2.9 trigger set)" — is authoritative on applicability, and the Phase 2.9 trigger set is `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, or a new infrastructure surface. A skill *reference document* (loaded by agents on demand, never executed) matches none of those — the path heuristic under-covers this shape. Recorded here rather than silently skipped, per the "argue down a false hit" convention; if `soleur:ship`/preflight disagrees, the remedy is a minimal `## Observability` block, and the affected edit is confined to this plan file.

### Remaining conditional gates

4.8 PAT sweep: clean (ran verbatim, no hits). 4.9 UI-wireframe: no UI-surface files. 4.10 Encryption Posture: no store/connection. 4.11 Guard Contract: no guard deliverable. 4.12 Scope Check: exactly one unfenced section, all asks `mapped`, one `inferred` row with non-empty justification, `Recommendation: single PR` present, no `status: BLOCKED`. 4.6 User-Brand: section present, `none` + decision sentence, file does not match `SENSITIVE_PATH_RE` (count 0). 4.55 Downtime: no downtime-inducing operation. 4.4 Precedent-diff: the row shape follows the existing Reason Taxonomy convention — precedent is the table itself; not novel. Scheduled-work check: no new cron — N/A.

### Agent fan-out note

The Task-spawn fan-out (Phases 2/3/4/5's skill, learnings, research and review agents) could not execute — this planning subagent has no agent-spawn tool. Substitution: every load-bearing claim was verified by direct command (`gh issue/pr/run view`, `git show`/`merge-base`, `grep` over source files, `wc -l`/`sed -n` on the shim). Commands and outputs are recorded in Research Insights and Research Reconciliation above. If the pipeline wants panel coverage, run `soleur:plan-review` on this file as a follow-up; nothing in the plan requires re-dispatch to be correct — the claims cite their evidence inline.

## Context

- This is a planning artifact for a docs-only change; implementation is a later phase on the same branch.
- Sharp edge: the plan's verification command (`git show origin/main:… | sha256sum`) was executed during planning and produced `4cbeee68fdae1f59e36a9c99f79e85103cdb7359fe58a50ecbf4513c8ba91d84` — matching the worktree copy, since this branch does not modify `ci-deploy.sh`.
- Sharp edge: a plan whose `## User-Brand Impact` section omits the threshold fails deepen-plan — the section above carries `none` with its decision sentence. No sensitive-path scope-out line is required: the target file does not match the canonical `SENSITIVE_PATH_RE` (it lives under `plugins/soleur/`, not `apps/*/infra/` or a credential workflow).
- Deferred agents note: no Task/subagent spawn was available in this planning context — repo research, learnings sweep, functional-overlap, scope check, and premise verification were performed inline (each cited above with its command-level evidence).

## References

- Incident: #9871 — "Deploys blocked: file-cap'd /usr/bin/bwrap refuses all invocations in-container" (closed; two-layer explanation in comments)
- Fix PR: #9874 / commit `d7dfd05aac` — file-cap revert; origin of the `--cap-add`: #9767 / `5e75548373`
- Delivery machinery: `.github/workflows/apply-deploy-pipeline-fix.yml` (`on.push.paths: apps/web-platform/infra/ci-deploy.sh`), `apps/web-platform/infra/cat-deploy-state.sh` (`ci_deploy_sha256`), `scripts/check-deploy-script-parity.sh` (#9151)
- Runs: 37976212395 (apply, dispatch), 37980286319 (Web Platform Release, green)
- Ship target: draft PR #9887
