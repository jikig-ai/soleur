# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-18-fix-web-probe-unit-start-doppler-auth-plan.md
- Status: complete

### Errors
- Two PreToolUse `hr-all-infrastructure-provisioning-servers` blocks fired on the literal `systemctl` token in plan prose. Resolved: the `systemctl` calls live inside `terraform_data` remote-exec provisioners (established IaC pattern); added `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out. Not a real IaC violation.
- No other errors.

### Decisions
- Root cause (diagnosis-first, self-pulled Better Stack telemetry CONFIRMED): units fail with `exit-code` and ZERO probe-tagged stderr reaches Better Stack (59 systemd lines, 0 probe lines). Unit-diff vs working siblings CONFIRMED: the 3 root-run probe units lack `Environment=HOME=/root` and any `DOPPLER_TOKEN` source.
- Fix shape (revised by deepen-plan review): add `Environment=HOME=/root`; fold `DOPPLER_TOKEN=` into each unit's existing `/etc/default/web-<probe>` write via the existing `*_install` provisioners; token = Terraform-minted read-scoped `doppler_service_token.web_probes`; deliver `vector.toml` via `journald_persistent` to make Source 4 live on unrebuildable web-1.
- Observability: added a positive-control canary (luks-#6604 pattern) since probes are silent-on-success.
- Phase model corrected: "measure still-broken units before fixing" is structurally unreachable in one auto-applied PR — demoted to best-effort; two-PR split persisted as a User-Challenge in decision-challenges.md; single-PR retained as default per ARGUMENTS.
- Issue handling: `Ref #6438 #6548` (never `Closes`); soak-gated auto-close via `l3-probe-armed-6438.sh` left untouched.

### Components Invoked
- Skill: soleur:plan, Skill: soleur:deepen-plan
- 2 Explore agents; scripts/betterstack-query.sh (x2); 1 fable advisor
- deepen-plan reviewers: architecture-strategist, spec-flow-analyzer, observability-coverage-reviewer, code-simplicity-reviewer, sonnet verify-the-negative
