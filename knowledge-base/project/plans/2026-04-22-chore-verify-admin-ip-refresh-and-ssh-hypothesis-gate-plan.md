# Verify admin-ip-refresh no-drift detection and SSH-symptom hypothesis gate

**Issues:** Closes #2690, Closes #2691
**Source PR:** #2683 (merged 2026-04-19)
**Type:** chore (post-merge operator verification)
**Detail level:** MINIMAL

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Research Reconciliation, Phase 1, Phase 2, Sharp Edges
**Sources consulted:** `plugins/soleur/skills/admin-ip-refresh/SKILL.md`, `plugins/soleur/skills/admin-ip-refresh/references/admin-ip-refresh-procedure.md`, `plugins/soleur/skills/plan/SKILL.md:470-495`, `plugins/soleur/skills/deepen-plan/SKILL.md:299-309`, AGENTS.md hard rules, `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`.

### Key Improvements

1. **Reconciled the "No drift" message format claim.** The exact format `No drift. Current IP X.X.X.X/32 is in ADMIN_IPS (list length N).` IS prescribed — in `admin-ip-refresh-procedure.md:12` and `:75`, not in SKILL.md:40 which says only `print "No drift."`. Verification must accept either the full prescribed format or a substring match on "No drift"; the plan had this backwards (claimed not prescribed, now corrected).
2. **Concrete mitigation for the `plan` skill's auto-commit + auto-push of the throwaway plan.** The plan skill at `plan/SKILL.md:487-494` commits AND pushes the generated plan under `knowledge-base/project/plans/` AND overwrites `knowledge-base/project/specs/feat-<branch>/tasks.md` on any `feat-*` branch. This clobbers THIS plan's existing tasks.md and leaves the throwaway plan in remote history. Phase 2 now prescribes running the throwaway from a sibling worktree on a non-`feat-*` branch (e.g., `tmp/verify-ssh-gate`) so neither auto-commit fires.
3. **Phase 4.5 recursion hazard clarified.** Running `soleur:deepen-plan` from inside `/soleur:one-shot`'s work phase against a throwaway plan spawns another 10+ agents plus this plan's own deepen was already running. Acceptable in one-shot work-phase but NOT from within plan/deepen-plan themselves.
4. **Opt-out in `## Hypotheses` strengthened.** Added per-layer artifact references so the inline opt-out passes the plan-network-outage-checklist's own "one-line justification citing a verification artifact" gate.

### New Considerations Discovered

- The throwaway plan will itself trigger `plan/Phase 1.4` (intended), AND the plan-skill's "Save Tasks" step will overwrite the real tasks.md for this feature branch. This is a silent-data-loss hazard this plan must prevent.
- `doppler configure get token --plain` returns a token when any authentication path is active (user token, service token). The skill doesn't distinguish; the operator must manually confirm they're using a user token before running — service tokens typically don't have `prd_terraform` read.
- `/soleur:admin-ip-refresh --dry-run` is the only SKILL.md-documented flag that guarantees no Doppler mutation. `--verify` also avoids writes but depends on a prior apply. For #2690, `--dry-run` is authoritative.

## Overview

Two follow-through verifications from PR #2683 land in the same PR because they share a source, share a worktree, and can be evidenced in a single commit (a learning file + issue-comment transcripts). Both are operator-layer verifications of mechanisms that are not CI-testable end-to-end:

1. **#2690** — exercise `/soleur:admin-ip-refresh` in dry-run mode against prod Doppler + Hetzner firewall and confirm the skill reports "No drift" (exit 0) when the operator's current egress IP is already present in `ADMIN_IPS`.
2. **#2691** — exercise `/soleur:plan` with a contrived input containing an SSH-outage trigger keyword and confirm the resulting plan's `## Hypotheses` section lists unverified L3 layers (firewall allow-list, DNS/routing) before any sshd/fail2ban/service-layer hypothesis. Same for `/soleur:deepen-plan` Phase 4.5 "Network-Outage Deep-Dive" subsection.

Neither verification mutates prod state. `admin-ip-refresh --dry-run` runs steps 1-4 only (detect, read, diff, warn) and does not write to Doppler or emit a Terraform command. The plan-skill verification produces a throwaway plan file under `/tmp` (never committed to `knowledge-base/project/plans/`) and is deleted after transcription.

## Problem statement

The institutional prevention of admin-IP drift landed in #2683 with three artifacts (skill, checklist reference, AGENTS.md Hard Rule). None of them have been exercised against real prod state or a real trigger input. `follow-through` issues exist precisely for this class — the mechanism passed CI (unit-test-level proof of structure) but has not been observed firing in the conditions it was built to catch. Until each fires once, the backstop is theoretical and silently broken mechanisms don't surface until the next incident.

## Research Reconciliation — Spec vs. Codebase

| Claim in issue body | Reality in codebase | Plan response |
|----|----|----|
| Skill should report "No drift. Current IP X.X.X.X/32 is in ADMIN_IPS (list length N)." | `SKILL.md:40` says only `print "No drift."`. The procedure reference `admin-ip-refresh-procedure.md:12` and `:75` prescribe the exact full-format string `No drift. Current IP ${candidate} is in ADMIN_IPS (list length N).` — so the full format IS authoritative, just documented in the reference file rather than SKILL.md. | Verification accepts either: (a) the full prescribed format, or (b) any output containing the substring `No drift` with exit code 0. Both satisfy #2690. If the skill emits a format that differs from the procedure reference, file a follow-up issue to align SKILL.md + procedure before closing. |
| Deepen-plan Phase 4.5 spawns "Network-Outage Deep-Dive subsection when re-deepening the same plan." | `deepen-plan/SKILL.md:299-309` confirms Phase 4.5 spawns a subagent on trigger-pattern match that emits a "Network-Outage Deep-Dive" subsection. | Verification step 2b runs deepen-plan against the throwaway plan from step 2a and greps for the subsection heading. |
| Verification is "manual" with `sla_business_days: 5` | Per AGENTS.md `hr-never-label-any-step-as-manual-without`, every step must be attempted via automation first. `admin-ip-refresh --dry-run` is non-interactive and produces deterministic output; `skill: soleur:plan` is non-interactive when invoked with a file-description argument in pipeline mode. | Both verifications are fully automated in this plan. "Manual" is the original issue's classification, carried over from #2683's caution about prod-write skills. Dry-run is automatable. |
| Phase 1.4 trigger regex list is authoritative | Both `plan/SKILL.md:123` and `deepen-plan/SKILL.md:301` list the identical regex: `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` (case-insensitive). The checklist file itself (`plan-network-outage-checklist.md:3-8`) is authoritative. | Phase 2's contrived input must match this regex; chosen input `"fix: intermittent SSH connection reset when deploying to soleur-web-platform from GitHub Actions runner"` matches `SSH` + `connection reset` + `timeout`-adjacent framing (via the word "intermittent" as a soft signal; the hard matches are `SSH` and `connection reset`). |
| Plan skill Save Tasks clobbers existing spec | `plan/SKILL.md:483-494` on any `feat-*` branch auto-writes `knowledge-base/project/specs/<branch>/tasks.md` AND runs `git add ... && git commit && git push`. | **Running plan for the throwaway input from this feature branch would overwrite this plan's own tasks.md and push the throwaway plan to remote.** Phase 2 mitigates by running from a sibling worktree on `tmp/verify-ssh-gate` (non-`feat-*`), where Save Tasks is a no-op per SKILL.md:499-501. |

## Files to edit

None. This PR only adds a learning file and updates AGENTS.md only if the verification surfaces a gap.

## Files to create

- `knowledge-base/project/learnings/2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md` — transcript of both verifications (command, stdout, exit code), what fired correctly, any gaps found, and the closing note for #2690 / #2691.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero matches against the planned file list.

## Implementation phases

### Phase 1 — Verify #2690 (admin-ip-refresh no-drift detection)

Per AGENTS.md `hr-menu-option-ack-not-prod-write-auth` and `hr-all-infrastructure-provisioning-servers`, this verification must not write to Doppler or trigger `terraform apply`. The skill's `--dry-run` flag (SKILL.md:21) runs steps 1-4 only: detect egress IP, read `ADMIN_IPS` from Doppler, diff, emit warnings. No secrets are mutated.

**Acceptance criteria (pre-merge):**

1. Run the skill: `skill: soleur:admin-ip-refresh` with args `--dry-run`. If the skill invocation cannot be captured verbatim (e.g., it runs inside the conversation without a machine-readable exit code), exit-code capture via a direct-bash fallback is out of scope — record the observed stdout and proceed; the presence of "No drift" in output is authoritative for this verification.
2. Capture stdout, stderr, and exit code (or "exit code not observable via skill wrapper" if the skill runs in-conversation).
3. Verify one of two outcomes:
   - **No drift (expected):** stdout contains either the full prescribed format from `admin-ip-refresh-procedure.md:75` — `No drift. Current IP <ip>/32 is in ADMIN_IPS (list length N).` — OR the shorter form from `SKILL.md:40` — `No drift.`. Exit code (if captured) is 0. Both satisfy #2690.
   - **Drift detected (unexpected):** stdout shows a diff between current list and proposed list. HALT the verification, file a new priority/p1 issue describing the drift (with egress IP REDACTED as `<redacted>/32`), and do NOT proceed to the write path. The operator must separately decide whether to run the real (non-dry) refresh, which is out of scope for this verification.
4. If "No drift" path hits:
   - Transcribe the skill's full stdout into the learning file `## #2690 Verification` section, with the egress IP replaced by `<redacted>/32` and the list length preserved (e.g., `No drift. Current IP <redacted>/32 is in ADMIN_IPS (list length 3).`). NEVER include actual CIDRs or the egress IP in any committed file — per `admin-ip-refresh/SKILL.md:61`, `ADMIN_IPS` is PII-adjacent.
   - Include: date, exact command, exit code (or observability note), redacted stdout excerpt, list length.
   - Comment on #2690 with the same redacted summary, then close via PR auto-close (`Closes #2690` in PR body).
5. **SKILL.md vs. procedure reference format drift check.** If the skill emits a third format (neither the short `No drift.` nor the full prescribed format), the two docs have drifted — file a separate issue to align `SKILL.md:40` with `admin-ip-refresh-procedure.md:75` before closing #2690. Document the drift in the learning file.

**Sharp edges:**

- **Doppler auth prerequisite.** `doppler configure get token --plain` must return a token before running the skill. If not authenticated, the skill exits with an install/auth hint (SKILL.md:32). Authenticate via `doppler login` first; do NOT commit tokens.
- **PII-redaction gate.** The learning file and issue comment must NOT include the actual egress IP or the ADMIN_IPS list contents. Record list length only. Per SKILL.md:61, ADMIN_IPS is PII-adjacent.
- **`--dry-run` only.** Never run the skill without `--dry-run` during this verification, even if the operator expects no drift. The point is to exercise the detection path; the write path is out of scope.

### Phase 2 — Verify #2691 (plan Phase 1.4 + deepen-plan Phase 4.5 trigger)

This verification produces a throwaway plan file by invoking `skill: soleur:plan` with a contrived input containing an SSH-outage trigger keyword (`plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` regex: `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` — case-insensitive). The resulting plan is inspected for the `## Hypotheses` L3 ordering and then deleted — it must NOT land under `knowledge-base/project/plans/` on the main branch.

**Pre-requisite: isolation worktree.** Per Research Reconciliation row 5, running plan from the current `feat-*` worktree would clobber this plan's tasks.md and auto-push the throwaway plan. Create a sibling worktree on a non-`feat-*` branch name:

```bash
bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create tmp/verify-ssh-gate
cd ../tmp-verify-ssh-gate   # whatever path the worktree manager emits
git branch --show-current   # MUST print tmp/verify-ssh-gate (not feat-*)
```

The `plan/SKILL.md:474` guard `If on a feat-* branch` evaluates false, so Save Tasks is skipped (per `:499-501`). The throwaway plan file is still written to `knowledge-base/project/plans/` in that worktree, but it is never `git add`'d or pushed. `rm` is sufficient cleanup.

**Acceptance criteria (pre-merge):**

1. **Contrived input.** Use this exact feature description: `"fix: intermittent SSH connection reset when deploying to soleur-web-platform from GitHub Actions runner"`. Hard matches against the regex: `SSH`, `connection reset`. Phase 1.4 WILL fire.
2. **Invoke plan in the sibling worktree.** From the `tmp/verify-ssh-gate` worktree, run `skill: soleur:plan` with the contrived input. The skill writes a plan file under `knowledge-base/project/plans/YYYY-MM-DD-fix-<slug>-plan.md` but skips Save Tasks (non-feat branch). Capture the path from the skill's announce output.
3. **Read the throwaway plan.** Open the plan file and verify:
   - Contains the heading `## Hypotheses`.
   - The hypotheses list leads with L3 entries. L3 keywords expected: `hcloud firewall describe`, `ifconfig.me`, `var.admin_ips`, `dig`, `traceroute`, or `mtr`. Service-layer keywords: `sshd`, `fail2ban`, `sshguard`, `journalctl -u`.
   - **Pass condition:** every L3-keyword hypothesis appears at an earlier list index than every service-layer hypothesis.
   - **Fail condition:** any service-layer hypothesis at an earlier index than any L3 hypothesis — verification FAILS, file a new priority/p1 issue documenting the regression, do NOT close #2691.
4. **Invoke deepen-plan on the same file.** Run `skill: soleur:deepen-plan` with the throwaway plan path. Per `deepen-plan/SKILL.md:299-309`, Phase 4.5 matches the plan's Overview/Problem-Statement/Hypotheses against the trigger regex and spawns the deep-dive agent. After completion, grep the deepened plan for the substring `Network-Outage Deep-Dive` (subsection heading). Presence confirms Phase 4.5 fired.
5. **Transcribe evidence.** Copy the throwaway plan's `## Hypotheses` section and the `Network-Outage Deep-Dive` subsection text (truncated to ~50 lines each) into the learning file `## #2691 Verification` section. The contrived input has no secrets; no redaction needed.
6. **Clean up the sibling worktree.** Return to the main worktree, then:

   ```bash
   cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-verify-follow-through-2690-2691
   bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged
   # If the tmp/ worktree's branch wasn't merged (it shouldn't be), remove manually:
   git worktree remove ../tmp-verify-ssh-gate --force
   git branch -D tmp/verify-ssh-gate
   ```

   Verify `git worktree list` no longer shows `tmp/verify-ssh-gate` and `git branch -a` no longer shows the branch.
7. **Comment and close.** Post a comment on #2691 with the verification date, contrived input (verbatim), Pass/Fail outcome, and links to the transcribed evidence in the learning file. Close via PR auto-close (`Closes #2691` in PR body).

**Sharp edges:**

- **Worktree isolation is non-negotiable.** Running plan from the current `feat-one-shot-verify-follow-through-2690-2691` branch would auto-write a new tasks.md over the existing one (silent data loss) AND auto-commit+push the throwaway plan to remote (polluting `knowledge-base/project/plans/` history). The sibling worktree on `tmp/verify-ssh-gate` is the mitigation — do not shortcut it.
- **Recursion hazard from inside deepen-plan.** Invoking `skill: soleur:plan` from inside THIS plan's deepen-plan phase (which is running right now as part of the one-shot pipeline) would nest three levels deep and confuse context. The contrived-plan invocation MUST happen in work-phase (after deepen finishes), not in plan/deepen-plan phases.
- **Deepen-plan consumes budget.** It spawns 10+ agents in parallel. Running it on a throwaway plan is the point of the verification — do not trim.
- **Phase 4.5 regex is duplicated in three files.** `plan/SKILL.md:123`, `deepen-plan/SKILL.md:301`, and `plan-network-outage-checklist.md:3-8`. If any of these three drifts out of sync, Phase 1.4 can fire while Phase 4.5 silently misses (or vice versa). The verification incidentally tests all three — if the throwaway plan shows the L3 hypotheses but the deepen-plan pass doesn't emit the subsection, that's a regex-drift regression worth filing.
- **Worktree manager script path.** `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` is the canonical entry point per AGENTS.md `wg-at-session-start-run-bash-plugins-soleur`. The `--yes` flag bypasses interactive confirmation (idempotent for tmp branches).

### Phase 3 — Commit and close

1. Write the learning file `knowledge-base/project/learnings/2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md` with:
   - `## #2690 Verification` — date, exact command, exit code (or observability note), redacted stdout excerpt, list length, SKILL.md-vs-procedure format drift note (if any).
   - `## #2691 Verification` — contrived input, excerpt of throwaway plan's `## Hypotheses` section, excerpt of deepen-plan's `Network-Outage Deep-Dive` subsection, Pass/Fail outcome.
   - `## Methodology` — brief narrative of the sibling-worktree isolation pattern for future follow-through verifications against plan-generating skills.
2. If either verification surfaced a gap (skill did not emit "No drift", plan did not emit L3-first hypotheses, deepen-plan did not emit subsection, or SKILL.md/procedure format drift), file a new priority/p1 issue tagged `domain/engineering` describing the regression. #2690 / #2691 remain OPEN — do NOT close on failure. PR body uses `Ref #2690 #2691` instead of `Closes #N` so auto-close does not fire.
3. If both verifications passed, PR body contains `Closes #2690` and `Closes #2691` on separate lines — auto-close handles the rest.
4. Run `skill: soleur:compound` to capture the verification methodology as a reusable pattern (e.g., "how to exercise a post-merge follow-through verification for plan-generating skills without polluting plans/ or clobbering sibling specs/"). The sibling-worktree isolation pattern is the core insight.
5. Ship via `skill: soleur:ship`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] Phase 1 executed: `admin-ip-refresh --dry-run` output captured, verification outcome recorded.
- [x] Phase 2 pre-req: sibling worktree created on non-`feat-*` branch (`tmp/verify-ssh-gate`) via `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create tmp/verify-ssh-gate`.
- [x] Phase 2 executed: throwaway plan inspected for L3-first `## Hypotheses`, deepen-plan run inspected for `Network-Outage Deep-Dive` subsection.
- [x] Phase 2 cleanup: sibling worktree removed, branch deleted, no throwaway plan in remote `main` or in this feature branch's `knowledge-base/project/plans/`.
- [x] THIS plan's `knowledge-base/project/specs/feat-one-shot-verify-follow-through-2690-2691/tasks.md` is unchanged by the Phase 2 exercise (verify via `git diff` before commit).
- [x] Learning file exists at `knowledge-base/project/learnings/2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md` with `## #2690 Verification`, `## #2691 Verification`, and `## Methodology` sections.
- [x] Learning file redacts egress IP and ADMIN_IPS CIDRs (records list length only; egress rendered as `<redacted>/32`).
- [x] `npx markdownlint-cli2 --fix` run on the learning file and plan file with specific paths (not globs, per `cq-markdownlint-fix-target-specific-paths`) — zero new errors.
- [x] `bash scripts/test-all.sh` passes (no regressions from committing the learning file; reference-link integrity checks still pass).
- [x] PR body includes `Closes #2690` and `Closes #2691` (pass outcome) OR `Ref #2690 #2691` + linked regression issue(s) (fail outcome).

### Post-merge (operator)

- [ ] Comment on #2690 with verification date, `admin-ip-refresh --dry-run` exit code, and list length (CIDRs redacted). Close the issue.
- [ ] Comment on #2691 with verification date, contrived input, and links to the two trigger artifacts (L3 hypothesis list + Network-Outage Deep-Dive subsection from the throwaway plan). Close the issue.
- [ ] If either verification surfaced a regression: file a new priority/p1 issue tagged `domain/engineering` with the gap, DO NOT close #2690 / #2691, and reference the regression from the source issues.

## Hypotheses

This plan contains the words "SSH", "firewall", "timeout", and "connection reset" in its Overview, Problem Statement, and Phase 2 — Phase 1.4's regex WILL trigger (and did trigger on this deepen pass, producing this subsection). However, the plan's subject IS the SSH-hypothesis-gate verification itself, not an SSH-outage diagnosis. Running the full L3-to-L7 checklist literally would produce zero useful content.

**Per-layer opt-out with artifacts** (per checklist §"Opt-out"):

- **L3 firewall allow-list — opt out.** Artifact: there is no current SSH outage. This plan runs `/soleur:admin-ip-refresh --dry-run` in Phase 1 specifically to verify the firewall allow-list state; that IS the L3 verification step, inverted.
- **L3 DNS / routing — opt out.** Artifact: no host is unreachable in this plan's scope; the contrived input in Phase 2 acceptance criterion 1 is a string, not a target.
- **L7 TLS / proxy — opt out.** Artifact: no HTTPS endpoint is addressed; this is internal-tooling verification only.
- **L7 application — opt out.** Artifact: no service is suspected; `journalctl -u ssh` on prod is not in scope for this plan (it would be in scope for an actual outage, which this plan is preventing the mis-diagnosis of).

### Network-Outage Deep-Dive

(Added by Phase 4.5 during the deepen pass on this plan.)

All four layer checks opt out per the above artifacts. The deepen pass's per-layer checklist gate is satisfied by the inline opt-out artifacts — no L3 firewall-drift hypothesis is required because this plan is itself the firewall-drift-prevention verification. Future readers: if this plan is repurposed as a template for an actual SSH outage diagnosis, the opt-outs above must be REMOVED and replaced with concrete L3-to-L7 verifications.

## Domain Review

**Domains relevant:** none

No cross-domain implications — this is a post-merge operator verification of internal tooling (skill + checklist + AGENTS.md rule). No user-facing surface, no brand voice, no marketing angle, no product flow, no finance, no legal exposure. The COO/ops angle (prod-write skill hygiene) is already encoded in the source skill's sharp edges; no new policy.

## Test Scenarios

- **Happy path #2690:** operator egress IP is in `ADMIN_IPS`; skill exits 0 with "No drift"; verification closes #2690.
- **Happy path #2691:** contrived input triggers Phase 1.4; plan's `## Hypotheses` lists L3 firewall allow-list + DNS/routing before sshd entries; deepen-plan emits "Network-Outage Deep-Dive" subsection; verification closes #2691.
- **Drift-detected edge case:** operator egress IP is NOT in `ADMIN_IPS` (legitimate drift — e.g., operator's IP rotated since last refresh). Skill output shows diff; verification HALTS, files a remediation issue, runs the real refresh flow outside this verification, then re-runs the verification after prod is reconciled.
- **Regression #2691:** plan's `## Hypotheses` starts with `fail2ban` or `sshd` before any L3 entry. This indicates Phase 1.4 didn't fire OR fired but didn't shape the plan output. Verification FAILS; file a new issue; do not close #2691.

## References

- Source PR: #2683 (merged 2026-04-19)
- Skill: `plugins/soleur/skills/admin-ip-refresh/SKILL.md`
- Checklist: `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`
- Plan skill Phase 1.4: `plugins/soleur/skills/plan/SKILL.md` §"1.4. Network-Outage Hypothesis Check"
- Deepen-plan Phase 4.5: `plugins/soleur/skills/deepen-plan/SKILL.md:299-309`
- AGENTS.md rules: `hr-ssh-diagnosis-verify-firewall`, `hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers`, `hr-never-label-any-step-as-manual-without`
- Learnings: `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`, `knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`
