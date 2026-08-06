# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-06-fix-inngest-redis-crash-loop-dark-error-channel-plan.md
- Status: complete

### Errors
None blocking. Two notes:
- The first `Write` was blocked by the IaC-routing hook because the plan quotes `ssh root@` runbook lines it intends to **delete**. Resolved with the documented `iac-routing-ack` opt-out plus an explicit header disclaimer.
- No `spec.md` exists for this branch (one-shot path skipped brainstorm/spec), so `lane:` fail-closed defaults to `cross-domain`, as recorded in the plan.

### Decisions
<!-- lint-infra-ignore start — #7286: the lines below QUOTE the `ssh root@` runbook instructions this PR DELETES, and the acceptance command that counts them. They are citations of a defect being removed, not prescribed steps. Without this region the no-SSH linter (correctly, now that #7286 taught it to see fenced/user@host forms) flags the AC that proves the deletion happened. -->

- Root cause measured, not inferred, but only one layer deep: `inngest-server` crash-loops on `dial tcp 127.0.0.1:6379: connection refused` because `inngest-redis.service` exits non-zero every ~5s since 2026-08-05 06:34:07 UTC. Postgres, disk, LUKS cutover, reboot, kernel OOM, and the 06:40 RLS apply are all refuted by timestamped evidence. Pulled from Better Stack + `/hooks/deploy-status` — no operator action.
- Why redis exits is UNKNOWN and unknowable remotely — that is the finding. All 7 hypotheses stay UNKNOWN. Phase 1 therefore ships a diagnostic instrument first, carrying one inert-if-unneeded fix.
- A CTO consult overturned the "dead token is REFUTED" verdict: `inngest-redis.service` is the only Doppler consumer with no token drop-in, so it and `inngest-server` read the same `EnvironmentFile` to different effect (leading hypothesis H7).
- A runtime SQLite fallback was rejected mid-plan — it would have masked this for 15h while silently dropping armed reminders. Replaced with detect-and-fail-loud plus a class-closing invariant test.
- Three review panels overturned four further claims: delivery IS a scoped `terraform apply`; the drop-in needs 7 registration surfaces, not 2; two instruments were false greens; and `lint-infra-no-human-steps.py` cannot match `ssh root@`, so the no-SSH gate exited 0 with all 7 violations present.

<!-- lint-infra-ignore end -->

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`, Explore x3 (infra/redis, observability, watchdog), `soleur:engineering:cto`, `observability-coverage-reviewer`, `spec-flow-analyzer`, `security-sentinel`, `learnings-researcher`, `gh`, `doppler` + `scripts/betterstack-query.sh`, `curl` to `/hooks/deploy-status` and `/hooks/inngest-liveness`, deepen gates 4.5-4.10 + 4.55

### Open Stop-Condition (flagged by planning subagent)
Phase 0.7 is a genuine stop-condition: if `terraform apply -target=terraform_data.deploy_pipeline_fix` is blocked, this plan has no delivery path and needs a different spine. That probe must run before implementation begins.
