# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-08-chore-arm64-vector-shipper-inngest-host-plan.md
- Status: complete

### Errors
None. Two IaC-routing PreToolUse hooks fired on literal-string matches (`doppler secrets set` in prose/grep patterns, not manual-provisioning steps) — resolved by adding the sanctioned `iac-routing-ack: plan-phase-2-8-reviewed` comment and rewording. The plan provisions via a `doppler_secret` Terraform resource, not any manual CLI write.

### Decisions
- Mirror the existing Inngest-CLI arm64 pattern for Vector: new `VECTOR_CLI_ARCH` (default `amd64` preserves the web host) + arch→triple map fixing both the hardcoded download URL AND the extract path; pin a live-verified arm64 SHA (`365bab73…8e6`) in `vector.tf`.
- IaC provisioning flipped Approach A→B (both review agents, decisive): a `data.doppler_secrets` mirror would leak the entire ~116-secret `soleur/prd` map into shared tfstate. Chose `var.betterstack_logs_token` from `prd_terraform` — only the one token enters state.
- Boot isolation self-check must be widened (`cloud-init-inngest.yml:156-157`, floor 4→5, top-level-alternation regex) — load-bearing edit the issue body omits; getting it wrong bricks the host boot.
- Apply-path correction: the dedicated-inngest resources are dispatch-applied (not push-auto-applied); the additive-only destroy-guard blocks cloud-init force-replace, so the plan adds a new `inngest-host-replace` dispatch (web-2-recreate pattern, preserving the Redis AOF volume).
- Guard-suite sweep + ADR-100 amendment: the new `doppler_secret` must land in `OPERATOR_APPLIED_EXCLUSIONS` + the dispatch `-target` list; ADR-100's deferred Vector caveat resolved, stale "Sentry" prose reconciled to Better Stack Logs sink.

### Components Invoked
- Skill soleur:plan (#6197)
- Skill soleur:deepen-plan
- Agent Explore (Inngest host IaC + Doppler research)
- Agent architecture-strategist (apply-path/guard/parity review)
- Agent security-sentinel (isolation-boundary review)
- Deepen-plan gates 4.4/4.6/4.7/4.8/4.9 (all passed); plan Phase 1.7.5 code-review overlap check (none)
