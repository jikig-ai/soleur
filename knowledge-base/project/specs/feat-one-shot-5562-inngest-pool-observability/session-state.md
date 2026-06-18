# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-18-observability-inngest-pool-monitoring-emaxconnsession-plan.md
- Status: complete

### Errors
None blocking. Two transient gate interactions resolved in-session:
- deepen-plan Phase 4.8 (PAT-shaped var halt) matched `var.supabase_access_token` — verified false-positive (hr-github-app-auth-not-pat is scoped to GitHub write creds; this is a Supabase Management-API token).
- iac-plan-write-guard.sh PreToolUse hook blocked three Edits on out-of-band-PAT-mint framing — resolved via the auditable `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out.

### Decisions
- Task (c) → REVERT default_pool_size to 15, not codify-30. The client-side `--postgres-max-open-conns 10` cap is already merged (#5559, inngest-bootstrap.sh:354), making the live default_pool_size=30 drift redundant. Codified as an out-of-band comment in inngest.tf (no Supabase TF provider exists).
- GH secret via Terraform, not operator: `SUPABASE_ACCESS_TOKEN` via a new `github_actions_secret` resource sourced from a no-default `var.supabase_access_token` (hr-tf-variable-no-operator-mint-default). Auto-apply sequencing risk flagged — var must be in Doppler prd_terraform before merge.
- Three failure modes, two alert routes: `pool_pressure` (70% leading indicator) + `pool_exhausted` (EMAXCONNSESSION cliff) share `[ci/inngest-pool]`, both excluded from auto-restart; `pool_probe_unavailable` is a soft probe-health mode.
- Security hardening from review: scrub_pat() (sbp_… redaction) + head -c 400 truncation + hardcoded host (no env-override exfil seam).

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, security-sentinel, observability-coverage-reviewer, code-simplicity-reviewer, general-purpose verify pass
