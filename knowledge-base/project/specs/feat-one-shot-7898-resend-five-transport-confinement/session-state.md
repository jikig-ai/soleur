# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-11-fix-resend-five-infra-scripts-transport-confinement-plan.md
- Status: complete
- Plan artifact: complete (selector=subagent-summary)

### Errors
- Two plan writes denied by PreToolUse hooks (`iac-plan-write-guard`) on descriptive prose; resolved with the sanctioned `iac-routing-ack` opt-out and rewording. No content lost.
- Three plan-review agents stalled ~25 min; nudged and all returned before consolidation.

### Decisions
- Re-derived counts: D baseline file on origin/main (8be1ba1a9, PR 8023 still open) = 67 lines -> 62 after this PR; A/B/C 103 -> 98. Linter summary counts firing files (66 D / 100 A/B/C today -> 61 / 95). ACs assert "main - 5", never a literal.
- resend-inbound-bootstrap.sh is NOT hashed into any triggers_replace/user_data (only a dns.tf comment) -> in scope; laptop one-shot under `doppler run -c prd`.
- The four monitors ARE hashed into terraform_data SSH provisioners + local.host_script_files: merge fires apply-web-platform-infra.yml and web-platform-release.yml; hcloud_server is not recreated (established IaC path, not a host-replacement window).
- Invocation contexts: disk-monitor + resource-monitor = 5-min systemd timers (key from ENV_FILE); container-restart-monitor = doppler-wrapped timer; cron-egress-alarm = OnFailure= unit (env from doppler); bootstrap = laptop. Monitors keep `exit 0`; refused/failed send emits one `emit_refusal()` (stdout SOLEUR_* marker + stderr + `logger -p user.crit` -> Vector Source 2).
- Rule D findings beyond the ask: Sentry SENTRY_INGEST_DOMAIN/PROJECT_ID/PUBLIC_KEY adjudicated in two files; bootstrap `$path` allowlist + key-shape check close a measured curl --config directive-injection vector. Classifier untouched; every prescribed shape passes it.
- Observability: monitor units not in Vector Source 4, but Source 2 ships PRIORITY 0-2 from any unit; one `logger` line per branch buys the off-box path. Better Stack alert rule on SOLEUR_*_SEND_FAILED is the one follow-up ship files.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Plan-phase agents: repo-research-analyst, learnings-researcher, functional-discovery, cto, cpo, general-purpose (advisor consult)
- Plan-review panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto
- Deepen-plan agents: security-sentinel, observability-coverage-reviewer, silent-failure-hunter, test-design-reviewer, git-history-analyzer, pattern-recognition-specialist, user-impact-reviewer, general-purpose (verify-the-negative sweep)
