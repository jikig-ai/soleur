# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-02-fix-git-data-rung2-harness-attribution-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope check: `git diff origin/main...HEAD --name-only` returned only plans/ + specs/ — no product code. PASS.
- Post-plan collision re-probe: plan `closes: [7570, 7534, 7544, 7481, 7460]` — identical to the set cleared at Step 0a.5. No new refs to probe.

### Errors
Three premises in the one-shot brief did NOT survive verification and were corrected in-plan:
1. #7460's "merge-blocking Doppler write" is ALREADY satisfied — the no-default variable exists and resolves via `--name-transformer tf-var`. #7460 is therefore not blocked and lands in this PR.
2. The `HOST_SQL` `detail` gap closed on main in `dfcf7bd26` — no work needed.
3. ADR-115 does NOT state the `user_data` ForceNew property it was cited for (verified independently: `grep -c ForceNew` = 0 in ADR-115; the property lives in ADR-149 and ADR-152). The property is real; the citation was wrong.

Four self-caught planning errors were recorded rather than quietly patched (ref-count from a tag-dominated ls-remote; 83 duplicated lines in a Phase 4 rewrite; an `= 6`/`>= 6` contradiction in AC 8; a shared-helper consumer count from too narrow a grep — 1 claimed, 12 actual).

Three security claims drafted during planning were stronger than the tree supports and were walked back: `sentry_dsn` is already baked in the same 0755 file; the git-data firewall has zero rules so open egress serves all of user_data from the metadata endpoint regardless of file mode; and 0600 does not stop an argv read via world-readable /proc/<pid>/cmdline.

MCP server `plugin:github:github` failed to connect; `gh` CLI used throughout, nothing blocked.

### Decisions
- All five issues covered, none sequenced out. #7460 lands NOW because the host has never been born (verified live: Hetzner holds no `soleur-git-data`) — editing the hash-bound template is free today and costs a destructive host replace ever after.
- #7534 is NOT a genuine design fork: canonical-shape assertion chosen over HCL parsing. Converts an unbounded fail-OPEN into a bounded fail-CLOSED with no new dependency; full parsing cannot resolve `file(local.p)` anyway. Residual stated: non-canonical forms become inadmissible, not hashable.
- #7481 re-architected from rebuild to REUSE — `fresh-host-boot-trail.sh` already implements four of five mechanisms in production against the events endpoint.
- #7544's refresh mechanism substituted: the follow-through sweeper closes a tracker on exit 0, so the planned probe would have self-terminated on its first clean run. Replaced with a case in the existing `rule-audit.yml` staleness step.
- Review found one merge blocker (D1: both R2 credentials reach the capture step via `$GITHUB_ENV` and are tee'd unredacted into a public 7-day artifact) and one purpose-defeating defect (D2: Phase 4 fixed WHO reads Sentry but not WHAT the reader prints — a post-fix dispatch would still have reported "git-data LUKS stage FAILED" with no cause). Both fixed in-plan.
- PR-split recommendation SURFACED, not applied: three reviewers advised splitting against the operator's stated one-PR direction. Persisted to decision-challenges.md as a User-Challenge for the operator to decide.

### Components Invoked
soleur:plan -> soleur:plan-review -> soleur:deepen-plan; research (repo-research-analyst, learnings-researcher); 7-agent review panel; 4-agent deepen fan-out (self-audit sweep, security-sentinel, observability-coverage-reviewer, test-design-reviewer); live evidence (Sentry issues API x14, docker buildx imagetools, Doppler, Hetzner API, gh, three test-suite baselines); gates lint-guard-contract / lint-infra-no-human-steps / lint-encryption-posture --repo-sweep and deepen halts 4.5-4.11 all pass.
