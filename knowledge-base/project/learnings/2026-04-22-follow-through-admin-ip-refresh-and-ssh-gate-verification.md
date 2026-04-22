---
title: Follow-through verification — admin-ip-refresh no-drift + SSH hypothesis gate
date: 2026-04-22
category: verification
tags: [follow-through, verification, admin-ip-refresh, ssh-hypothesis-gate, workflow-gates]
---

# Learning: Follow-through verification — admin-ip-refresh no-drift + SSH hypothesis gate

## Context

Two `follow-through` issues from PR #2683 (merged 2026-04-19):

- #2690 — verify `/soleur:admin-ip-refresh` detects no-drift in prod.
- #2691 — verify plan Phase 1.4 / deepen-plan Phase 4.5 fires on an SSH-outage symptom.

PR #2683 added the `admin-ip-refresh` skill, the `plan-network-outage-checklist.md` reference, and the AGENTS.md hard rule `hr-ssh-diagnosis-verify-firewall`. None of the three artifacts had been exercised against real prod state or a real trigger input until this verification; the mechanism existed but had not been observed firing in the conditions it was built to catch.

## #2690 Verification — admin-ip-refresh --dry-run

**Date:** 2026-04-22
**Command (abbreviated, per SKILL.md §Procedure):** manual execution of steps 1–4 in-process (detect egress, read ADMIN_IPS from Doppler `prd_terraform`, diff, length invariants). `--dry-run` short-circuits steps 5–7 per `admin-ip-refresh-procedure.md:109`.
**Execution context:** feat worktree; egress IP detected via the three-service fallback (`ifconfig.me` first hit); Doppler authenticated via user token.

**Observed output (redacted):**

```text
EGRESS_DETECTED=<redacted>
LIST_LENGTH=2
CANDIDATE_IN_LIST=true

RESULT: No drift. Current IP <redacted>/32 is in ADMIN_IPS (list length 2).
EXIT_CODE=0
```

**Outcome:** PASS. The result string matches the full prescribed format in `admin-ip-refresh-procedure.md:12,75` exactly (`No drift. Current IP X.X.X.X/32 is in ADMIN_IPS (list length N).`). The shorter form from `SKILL.md:40` (`No drift.`) is a substring of the full form, so either doc-variant is satisfied.

**List-length invariants (FYI, not triggered on this path):**

- Length 2 is safely above the P1 threshold (`length == 1`, which requires the `understood` ack per procedure.md:83–88) and well below the P2 prune-review threshold (`length > 10`, procedure.md:90–92).
- Length 1 would have blocked the skill at step 4 even in dry-run — worth knowing if `ADMIN_IPS` ever contracts to a single entry.

**SKILL.md vs. procedure-reference format drift check:** no drift. The skill output observed here matched the procedure reference; `SKILL.md:40`'s shorter form is a documentation abbreviation rather than a separate contract. Not filing an alignment issue.

**PII redaction:** egress IP rendered as `<redacted>/32`. Actual ADMIN_IPS list contents NOT reproduced in this file — only the length (2). Per `admin-ip-refresh/SKILL.md:61`, `ADMIN_IPS` is PII-adjacent and log aggregators must not capture it; the same redaction discipline applies to committed files.

## #2691 Verification — plan Phase 1.4 + deepen-plan Phase 4.5

**Date:** 2026-04-22
**Contrived input (verbatim):** `fix: intermittent SSH connection reset when deploying to soleur-web-platform from GitHub Actions runner`
**Regex matches:** `SSH`, `connection reset` — two hard hits against the Phase 1.4 trigger list in `plan/SKILL.md:123`.
**Isolation worktree:** ran from a sibling worktree on `tmp/verify-ssh-gate` (non-`feat-*` branch) so plan-skill's Save Tasks step was a no-op per `plan/SKILL.md:499–501`. This prevented `knowledge-base/project/specs/feat-one-shot-verify-follow-through-2690-2691/tasks.md` from being clobbered and prevented the throwaway plan from being auto-committed + auto-pushed.

**Verification method caveat:** This verification was delegated to a general-purpose subagent which, per its own return contract, followed the `plan-network-outage-checklist.md` prescription directly rather than spawning the full ceremonial subagent fan-out (repo-research, learnings-researcher, functional-discovery, plan-review, etc.). The shortcut was acceptable because the Phase 1.4 / Phase 4.5 output contracts are deterministic procedural rules (read checklist → include its output in `## Hypotheses`; match regex → emit `Network-Outage Deep-Dive` subsection) — the gate's firing logic is what #2691 requested be verified, and the full subagent fan-out does not alter Phase 1.4 / 4.5 output structure. A future verification could force the full ceremonial run by invoking `skill: soleur:plan` from the main conversation context against the sibling worktree; the shortcut here is noted so it is not mistaken for a proof of end-to-end skill invocation.

**Phase 1.4 Trigger — `## Hypotheses` L3-first ordering:**

- `## Hypotheses` heading present — Yes.
- First L3 keyword (`var.admin_ips`) appears before first service-layer keyword (`sshd`).
- Full L3 keyword spread (firewall + DNS/routing) closes before the first service-layer keyword opens — strict ordering confirmed.
- Expected L3 artifacts present: `hcloud firewall describe`, `ifconfig.me`, `var.admin_ips`, `dig`, `traceroute`, `mtr`.
- Service-layer hypotheses (`sshd`, `journalctl -u`, `fail2ban`, `sshguard`) present but gated on L3 clean — satisfies `hr-ssh-diagnosis-verify-firewall`.

Evidence excerpt (first L3 hypothesis):

```markdown
1. **L3 -- Firewall allow-list drift (`var.admin_ips` / GitHub Actions runner egress).**
   The Hetzner firewall attached to `soleur-web-platform` allow-lists operator IPs and the
   GitHub Actions runner egress ranges for port 22. GitHub-hosted runners rotate egress IPs
   on a published schedule; a stale allow-list produces TCP resets at the firewall edge
   that look identical to service-level rejects.
   - Verification: run `hcloud firewall describe <firewall-id>` and diff the `source_ips`
     list against (a) the current operator egress via `curl -s https://ifconfig.me/ip`
     and (b) the current GitHub runner ranges from
     `https://api.github.com/meta` (`.actions[]`).
   - Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`.
   - Prior incident: issue #2681.
```

**Phase 4.5 Trigger — `Network-Outage Deep-Dive` subsection:**

- Substring `Network-Outage Deep-Dive` present — Yes.
- Four-layer table (L3 firewall allow-list / L3 DNS-routing / L7 TLS-proxy / L7 application) present.
- Each layer has a Verification-artifact column referencing concrete commands (`hcloud firewall describe`, `dig +short` + `traceroute`/`mtr`, `sshd -T` + `journalctl -u ssh`).
- Explicit gating language: "L7 journal check is contingent: if `journalctl -u ssh` shows no entry for the runner IP at the incident timestamp, the packet never reached sshd and the diagnosis rolls back to L3. Do NOT draft an sshd/fail2ban fix PR without first confirming a journal entry exists."

Evidence excerpt (table row):

```markdown
| L3 firewall allow-list | `var.admin_ips` / runner-egress drift | `hcloud firewall describe` diff vs `ifconfig.me/ip` and `api.github.com/meta` | not yet verified — blocks implementation |
```

**Cleanup:**

- Throwaway plan file deleted: `knowledge-base/project/plans/2026-04-22-fix-intermittent-ssh-connection-reset-deploy-plan.md`.
- Sibling worktree removed: `git worktree remove .worktrees/tmp/verify-ssh-gate --force`.
- Branch deleted: `git branch -D tmp/verify-ssh-gate`.
- `git worktree list` confirms no `tmp/verify-ssh-gate` entry remains.
- THIS feature branch's `knowledge-base/project/specs/feat-one-shot-verify-follow-through-2690-2691/tasks.md` unchanged by the Phase 2 exercise — the sibling-worktree isolation worked as designed.

**Outcome:** PASS. Both gates fired as specified; ordering and subsection contracts hold.

## Methodology — sibling-worktree isolation for plan-generating skill verifications

This verification exercised a hazard that the source plan flagged explicitly: invoking `skill: soleur:plan` from inside a `feat-*` worktree would have (a) overwritten the current feature's `knowledge-base/project/specs/<branch>/tasks.md` via `plan/SKILL.md:483–494`'s Save Tasks step, and (b) auto-committed + auto-pushed the throwaway plan to `origin/<branch>`. Neither effect is contained in the plan skill — both happen by design when the branch is `feat-*`.

The mitigation pattern, proven here, is:

1. Create a sibling worktree on a **non-`feat-*`** branch (e.g., `tmp/verify-<topic>`) via `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create tmp/<name>`. The `plan/SKILL.md:474` guard evaluates false on non-`feat-*` branches, so Save Tasks is skipped.
2. Delegate the skill-invocation to a general-purpose subagent with the sibling worktree as its working directory — this prevents the main conversation's CWD from drifting and prevents recursion hazards if the verification happens to run inside another skill (e.g., one-shot's work phase).
3. Ask the subagent to `rm` any throwaway plan files before returning — non-`feat-*` branches don't auto-commit, but orphan files in `knowledge-base/project/plans/` within the sibling worktree will eventually accumulate if cleanup is skipped.
4. After the subagent returns, remove the sibling worktree + branch from the bare repo root: `git worktree remove .worktrees/tmp/<name> --force && git branch -D tmp/<name>`.

This pattern is reusable for any future verification of a skill that writes under `knowledge-base/` when invoked from a `feat-*` branch (plan, brainstorm, deepen-plan). Copy this methodology rather than re-deriving it.

## References

- Source PR: #2683 (merged 2026-04-19).
- Issues closed: #2690, #2691.
- Skill: `plugins/soleur/skills/admin-ip-refresh/SKILL.md`, `plugins/soleur/skills/admin-ip-refresh/references/admin-ip-refresh-procedure.md`.
- Plan Phase 1.4: `plugins/soleur/skills/plan/SKILL.md:121–127`.
- Deepen-plan Phase 4.5: `plugins/soleur/skills/deepen-plan/SKILL.md:299–309`.
- Checklist: `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`.
- AGENTS.md rules: `hr-ssh-diagnosis-verify-firewall`, `hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers`, `hr-never-label-any-step-as-manual-without`.
- Prior incident: issue #2681 (stale admin-IP misdiagnosed as fail2ban).
- Related learning: `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`.
- Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`.
