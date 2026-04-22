# Verify admin-ip-refresh no-drift detection and SSH-symptom hypothesis gate

**Issues:** Closes #2690, Closes #2691
**Source PR:** #2683 (merged 2026-04-19)
**Type:** chore (post-merge operator verification)
**Detail level:** MINIMAL

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
| Skill should report "No drift. Current IP X.X.X.X/32 is in ADMIN_IPS (list length N)." | `SKILL.md` step 3 says: "If `<current-egress>/32` is in the list, print 'No drift.' and exit 0" — exact quote format not prescribed in the skill. | Verification records whatever exact string the skill emits; any string containing "No drift" + exit 0 satisfies #2690's "no-drift detection". Do not fail the verification on minor wording. |
| Deepen-plan Phase 4.5 spawns "Network-Outage Deep-Dive subsection when re-deepening the same plan." | `deepen-plan/SKILL.md:299-309` confirms Phase 4.5 spawns a subagent that emits a "Network-Outage Deep-Dive" subsection. | Verification step 2b runs deepen-plan against the throwaway plan from step 2a and greps for the subsection heading. |
| Verification is "manual" with `sla_business_days: 5` | Per AGENTS.md `hr-never-label-any-step-as-manual-without`, every step must be attempted via automation first. `/soleur:admin-ip-refresh --dry-run` is non-interactive and produces machine-parseable output; `/soleur:plan` with a file-description argument is non-interactive in pipeline mode. | Both verifications are fully automated in this plan. "Manual" is only the original issue's classification, carried over from #2683's caution about prod-write skills. Dry-run is automatable. |

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

1. Run the skill: `/soleur:admin-ip-refresh --dry-run`. If the skill invocation cannot be captured verbatim (e.g., the skill runs interactively inside the conversation), invoke the procedure script directly: `bash -c "$(cat plugins/soleur/skills/admin-ip-refresh/references/admin-ip-refresh-procedure.md | <extract detection/read/diff steps>)"` — this is a fallback; prefer the skill invocation.
2. Capture stdout, stderr, exit code.
3. Verify one of two outcomes:
   - **No drift (expected):** stdout contains "No drift" (or semantically equivalent — the skill prescribes this message at SKILL.md:40), exit code is 0.
   - **Drift detected (unexpected):** stdout shows a diff between current list and proposed list. If this happens, HALT the verification, file a separate issue, and do NOT proceed to the write path — the operator must investigate whether the drift is real or the skill misidentified the egress IP.
4. If "No drift" path hits:
   - Transcribe stdout into the learning file under a `## #2690 Verification` section with date, command, exit code, and a redacted list length (e.g., "list length 3" — NEVER include the actual CIDRs in a committed file; `ADMIN_IPS` is PII-adjacent per SKILL.md:61).
   - Comment on #2690 with: the date, verification command, exit code, and "List length N (CIDRs redacted)" — then close the issue.

**Sharp edges:**

- **Doppler auth prerequisite.** `doppler configure get token --plain` must return a token before running the skill. If not authenticated, the skill exits with an install/auth hint (SKILL.md:32). Authenticate via `doppler login` first; do NOT commit tokens.
- **PII-redaction gate.** The learning file and issue comment must NOT include the actual egress IP or the ADMIN_IPS list contents. Record list length only. Per SKILL.md:61, ADMIN_IPS is PII-adjacent.
- **`--dry-run` only.** Never run the skill without `--dry-run` during this verification, even if the operator expects no drift. The point is to exercise the detection path; the write path is out of scope.

### Phase 2 — Verify #2691 (plan Phase 1.4 + deepen-plan Phase 4.5 trigger)

This verification produces a throwaway plan file by invoking `/soleur:plan` with a contrived input containing an SSH-outage trigger keyword (`plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` regex: `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` — case-insensitive). The resulting plan is inspected for the `## Hypotheses` L3 ordering and then deleted — it must NOT land under `knowledge-base/project/plans/`.

**Acceptance criteria (pre-merge):**

1. **Contrived input.** Use this exact feature description: `"fix: intermittent SSH connection reset when deploying to soleur-web-platform from GitHub Actions runner"`. This contains `SSH`, `connection reset`, and `timeout`-adjacent framing, guaranteeing Phase 1.4 fires.
2. **Invoke plan.** Run `skill: soleur:plan` with the contrived input. The skill will write a plan file under `knowledge-base/project/plans/YYYY-MM-DD-fix-<slug>-plan.md`. Capture the path.
3. **Relocate the artifact.** Immediately after plan completion, `mv` the file to `/tmp/2691-verification-plan.md`. Do NOT commit the throwaway plan to `knowledge-base/project/plans/`. This is a verification artifact, not a real plan — committing it would pollute the plans directory and trip any "feature X planned but never shipped" audits.
4. **Grep for L3 entries in `## Hypotheses`.** The throwaway plan's `## Hypotheses` section MUST:
   - Contain the heading `## Hypotheses`.
   - The first 1-4 bulleted/numbered items MUST be L3-layer entries (firewall allow-list AND DNS/routing) BEFORE any sshd, fail2ban, journalctl, or service-layer hypothesis. Check for keywords: the L3 items mention `hcloud firewall describe`, `ifconfig.me`, `dig`, `traceroute`, or `mtr`. Service-layer items mention `sshd`, `fail2ban`, `sshguard`, or `journalctl -u`.
   - A service-layer hypothesis appearing BEFORE any L3 entry is a verification FAILURE — file a new issue documenting the regression and do NOT close #2691.
5. **Invoke deepen-plan on the same file.** Run `skill: soleur:deepen-plan` with the `/tmp/2691-verification-plan.md` path. Per `deepen-plan/SKILL.md:299-309`, Phase 4.5 must spawn the "Network-Outage Deep-Dive" subagent. After deepen-plan completes, grep the plan for the subsection heading `Network-Outage Deep-Dive` or `## Network-Outage Deep-Dive`. Presence confirms Phase 4.5 fired.
6. **Clean up.** `rm /tmp/2691-verification-plan.md`. If `skill: soleur:plan` also auto-created `knowledge-base/project/specs/feat-<branch>/tasks.md` as part of its Save Tasks phase, also delete that file — the throwaway plan must not leave git-tracked debris.
7. **Transcribe.** Under a `## #2691 Verification` section of the learning file, record: the contrived input, the plan file's `## Hypotheses` section (redacted of nothing — the contrived input has no secrets), the deepen-plan subsection confirmation, and any gaps.
8. **Comment and close.** Comment on #2691 with the verification date, contrived input, transcript summary, then close.

**Sharp edges:**

- **Pipeline-mode recursion risk.** Running `skill: soleur:plan` from inside a work-skill phase of THIS plan could produce confusing output if the Skill tool re-enters this plan's context. Mitigation: the verification runs in a fresh session spawned from `/soleur:work` phase 2, not nested inside plan-skill execution. If recursion is detected (the inner plan receives this verification plan's content as its own feature description), abort and restart in a clean `/clear` session.
- **Skill's Save Tasks writes under `knowledge-base/`.** Per `plan/SKILL.md`, the Save Tasks step commits plan + tasks.md together when on a `feat-*` branch. The current branch IS `feat-one-shot-verify-follow-through-2690-2691`. This means the throwaway plan will be auto-committed. Mitigation: after step 3 above, run `git reset HEAD <path>` and `git checkout -- <path>` and delete the file BEFORE any subsequent commit runs. Alternative: invoke plan in a fresh sibling worktree whose branch name doesn't match `feat-*`.
- **Trigger-keyword stability.** The contrived input must match the regex in `plan-network-outage-checklist.md:1-8` exactly. If that regex changes in a future PR, this verification must be re-run. The learning file records the verified regex substring at verification time to anchor future re-verifications.
- **Deepen-plan runs many agents.** `deepen-plan/SKILL.md` spawns 10+ agents in parallel. Running it on a throwaway plan consumes budget; accept the cost. Do not trim the invocation — the point is to verify Phase 4.5 fires alongside the normal deepen agents, not in isolation.

### Phase 3 — Commit and close

1. Write the learning file `knowledge-base/project/learnings/2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md` with both `## #2690 Verification` and `## #2691 Verification` sections.
2. If the verification surfaced a gap (skill did not emit "No drift", plan did not emit L3-first hypotheses, deepen-plan did not emit subsection), the plan's final state is: learning file + a new GitHub issue describing the regression. #2690 / #2691 remain OPEN. Do NOT close them on failure.
3. If both verifications passed, comment on each issue with the transcript summary and close.
4. Run `/soleur:compound` to capture the verification methodology as a reusable pattern (e.g., "how to exercise a post-merge follow-through without polluting plans/").
5. Ship via `/ship`. PR body contains `Closes #2690` and `Closes #2691` on separate lines.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 1 executed: `admin-ip-refresh --dry-run` output captured, verification outcome recorded.
- [ ] Phase 2 executed: throwaway plan inspected for L3-first `## Hypotheses`, deepen-plan run inspected for Network-Outage Deep-Dive subsection, throwaway artifacts deleted.
- [ ] Learning file exists at `knowledge-base/project/learnings/2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md` with both `## #2690 Verification` and `## #2691 Verification` sections.
- [ ] Learning file redacts egress IP and ADMIN_IPS CIDRs (records list length only).
- [ ] `npx markdownlint-cli2 --fix knowledge-base/project/learnings/2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md knowledge-base/project/plans/2026-04-22-chore-verify-admin-ip-refresh-and-ssh-hypothesis-gate-plan.md` — zero new errors.
- [ ] `bash scripts/test-all.sh` passes (no regressions from committing the learning file).
- [ ] PR body includes `Closes #2690` and `Closes #2691`.

### Post-merge (operator)

- [ ] Comment on #2690 with verification date, `admin-ip-refresh --dry-run` exit code, and list length (CIDRs redacted). Close the issue.
- [ ] Comment on #2691 with verification date, contrived input, and links to the two trigger artifacts (L3 hypothesis list + Network-Outage Deep-Dive subsection from the throwaway plan). Close the issue.
- [ ] If either verification surfaced a regression: file a new priority/p1 issue tagged `domain/engineering` with the gap, DO NOT close #2690 / #2691, and reference the regression from the source issues.

## Hypotheses

This plan contains the words "SSH", "firewall", "timeout", and "connection reset" in its Problem Statement and Phase 2 — Phase 1.4's regex WILL trigger. However, the current plan's subject IS the SSH-hypothesis-gate verification itself, not an SSH-outage diagnosis. Running the network-outage checklist literally against this plan produces zero useful content.

Opt-out per checklist §"Opt-out": This plan is a verification of the SSH-outage hypothesis gate, not a diagnosis of an SSH outage. No L3-to-L7 layer verification applies because there is no outage to diagnose — the contrived input in Phase 2 acceptance criterion 1 is the verification subject, not a real incident. Artifact: this opt-out itself, recorded inline, per checklist §Opt-out ("one-line justification citing a verification artifact").

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
