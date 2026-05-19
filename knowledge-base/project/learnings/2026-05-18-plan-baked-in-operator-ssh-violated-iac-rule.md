# Plan baked in operator-SSH + Doppler-CLI; existing IaC rule was never consulted at plan time

**Captured:** 2026-05-18
**Source PRs:** #3940 (PR-F Inngest trigger layer), #3960 (post-merge follow-through issue)
**Source plan:** `knowledge-base/project/plans/archive/20260517-203729-2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md`
**Defect class:** rule-discoverability-gap — hard rule existed; no plan-time gate consulted it
**Severity:** P2 (no production impact; recoverable as a follow-up PR — but the failure mode is systemic and likely to recur)

## Problem

The PR-F plan included a `### Post-merge (operator)` section with four steps:

> - Install `inngest-cli` (pinned release tag) on Hetzner host AND configure systemd unit `inngest-server.service` running `inngest start --host 127.0.0.1 ...` with `Restart=always`. Verify `ss -tlnp | grep -E '8288|8289'` shows `127.0.0.1` only.
> - Set `SOLEUR_FR5_ENABLED=true` in Doppler `prd` and restart Node app.
> - Send synthesized Stripe `invoice.payment_failed` from operator's own Stripe TEST mode.
> - Wire Better Stack Incidents on-call (free tier) to alert on Inngest server outage AND `runtime_paused_at` flip events.

All four steps violate `hr-all-infrastructure-provisioning-servers`: "All infra provisioning (servers, volumes, firewalls, DNS) goes through Terraform — never vendor APIs or manual SSH."

The rule was added months earlier in response to a prior incident. The plan author (LLM, opus-4-7) did not consult it because no skill phase forced the consultation. The brainstorm, plan, deepen-plan, /work, /review, and /ship phases all ran without surfacing the violation. The first time the contradiction was noticed was when the user asked, post-merge, **"why isn't this done through Terraform?"**

The cost was small (the PR shipped fine, and a follow-up IaC PR can absorb the operator steps), but the pattern — "rule exists, no gate enforces it, plan ships violating it" — is the exact failure mode `hr-all-infrastructure-provisioning-servers` was created to prevent.

## Root cause

Three independent conditions had to all hold for the violation to ship:

1. **No plan-time gate consulted the rule.** The plan skill has gates for GDPR (Phase 2.7), user-brand impact (Phase 2.6), domain review (Phase 2.5), code-review overlap (Phase 1.7.5), and several others — but no gate scanned plan content for "operator-driven", "ssh root@", "systemctl enable", "doppler secrets set", or vendor-dashboard click-path language. The rule was a passive entry in `AGENTS.core.md`, loaded into every session's system prompt, but never invoked as a check against draft plan output.
2. **The rule lacked a `[skill-enforced: ...]` marker.** Several sibling rules carry markers like `[skill-enforced: brainstorm Phase 0.5]` or `[skill-enforced: ship Phase 5.5]`, which signal that a downstream skill phase actively consults the rule. `hr-all-infrastructure-provisioning-servers` had no such marker — so even if a plan-time scan had looked for "which rules are gated where?", this one wouldn't appear.
3. **The PR-F brainstorm's operations domain review (COO) reviewed the substrate decision (self-hosted vs. Inngest Cloud) but not the *implementation* of the infrastructure.** COO's "carry-forward" assessment landed in the plan as `Status: reviewed (carry-forward)` without anyone re-checking whether the substrate decision had been converted into Terraform-ready phase outputs vs. manual operator steps. The handoff from brainstorm → plan dropped the IaC framing.

The compounding failure mode: each individual layer (brainstorm domain assessment, plan draft, deepen-plan, /work, /review, /ship) was internally consistent. None of them owned the question "does this plan respect the IaC rule?"

## Solution

PR introduces defense-in-depth at three points:

1. **`plugins/soleur/skills/plan/SKILL.md` Phase 2.8 — Infrastructure-as-Code Routing Gate.** Scans the plan draft for manual-infra patterns (operator-SSH, `systemctl`, `doppler secrets set`, vendor-dashboard click-paths, manual `crontab -e`, `out-of-band` framings). If detected, auto-invokes `terraform-architect` to reshape the affected phases. Requires a `## Infrastructure (IaC)` section in the plan with four subsections: Terraform changes, Apply path, Distinctness/drift safeguards, Vendor-tier reality check.
2. **`AGENTS.core.md` rule extension.** Existing `hr-all-infrastructure-provisioning-servers` rule is extended with `[skill-enforced: plan Phase 2.8 + iac-plan-write-guard.sh]` marker and a `**Why:**` line referencing this incident. This keeps the byte-budget lean (one rule, not two) while making the gate discoverable.
3. **`.claude/hooks/iac-plan-write-guard.sh` PreToolUse hook.** Mechanically denies `Write`/`Edit` calls on `knowledge-base/project/plans/*.md`, `specs/*/spec.md`, `specs/*/tasks.md` when the content matches the same pattern set. Provides a one-line escape hatch (`<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`) for the genuinely-rare case where a manual step cannot be automated (e.g., one-time vendor token mint). 19/19 fixture tests pass.

## Prevention

The hook is the strongest enforcement (mechanical, cannot be bypassed by an LLM that hasn't read the skill). The plan-phase is the second net (advisory routing through `terraform-architect`). The AGENTS rule marker is the third net (discoverability for future rule audits).

**Mechanical detection (PreToolUse hook, fires on every Write/Edit to plan/spec markdown):**

```bash
# Pattern set (case-insensitive, scanned in tool_input.content / new_string):
#   - ssh (root|deploy|ubuntu|admin)@...
#   - manually install(s|ing) | operator (runs|installs|...) | operator-driven | out-of-band
#   - systemctl (enable|start|...) | /etc/systemd/system/<unit>.service
#   - doppler secrets set
#   - "go to|open|... the (cloudflare|hetzner|...) (dashboard|console|ui)"
#   - crontab -e | sudo crontab | edit the crontab
```

If any pattern matches, the hook returns `permissionDecision: deny` with a structured reason pointing at plan Phase 2.8.

**Discoverability litmus:** every hard rule in `AGENTS.core.md` that names a process discipline (not a code pattern) should carry a `[skill-enforced: <skill-or-hook>]` marker. Audit: `grep '\[id: hr-' AGENTS.core.md | grep -v 'skill-enforced'` — every line returned is a rule without an active enforcement surface.

## Session Errors

None this session were caused by missing rules; the session error WAS the original violation, captured above.

## Related learnings

- `knowledge-base/project/learnings/2026-05-17-mocked-tests-miss-shared-table-schema-gaps.md` — same failure shape (rule existed, no plan-time consultation, multi-agent review caught it)
- `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — precedent for plan-time gate addition (GDPR Phase 2.7)

## Tags

category: workflow-gate-gaps
module: plugins/soleur/skills/plan + .claude/hooks
defect-class: rule-exists-no-gate-enforces-it
captured-by: user-question-after-merge ("why isn't this done through terraform?")
gate-added: plan-phase-2-8 + iac-plan-write-guard.sh + AGENTS.core.md marker
