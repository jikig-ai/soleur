# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10045-kdeny-least-priv/knowledge-base/project/plans/2026-10-11-chore-kdeny-kernel-stream-read-grant-plan.md
- Status: complete

### Errors
- No fatal errors. Two tool-level hiccups, both recovered: (1) a `get_output` call was rejected for an invalid `command` field during the research phase (retried with correct `shell_id`/`timeout` fields); (2) one `edit` call during plan-review application used a duplicated path and failed (retried with the correct absolute path). No production mutation, SSH, or implementation was attempted; all execution stayed inside the feature worktree.

### Decisions
- **Mechanism: fixed-argv sudoers grant, not `systemd-journal` group.** `Cmnd_Alias KDENY_KERNEL_STREAM = /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat` + `deploy ALL=(root) NOPASSWD:` in `deploy-inngest-bootstrap.sudoers` — strictly narrower than group membership (kernel transport only, bounded window, transient, per-read sudo audit record). Blast-radius read for group membership documented: `deploy` is already root-equivalent by documented decision, so the differentiator is ambient reach — group membership would give every deploy-uid process silent whole-journal read with no per-read audit.
- **Delivery reuses existing channels only**: the sudoers file already rides cloud-init (fresh hosts) and the two running-host terraform_data bridges (`infra_config_handler_bootstrap` web-1, `deploy_pipeline_fix_web2` web-2, auto-applied by `apply-deploy-pipeline-fix.yml`). No new provisioner; webhook FILE_MAP stays excluded. Apply gate = alias grep + `runuser -u deploy -- sudo -n <argv>` execute probe.
- **Reader change keeps degrade semantics**: `_canary_kdeny_read` tries `timeout -k 1 3 sudo -n /usr/bin/journalctl …` first, falls back to the unprivileged read on a sudo-denial signature, so mid-rollout or stale-birth hosts emit today's `noaccess`, not a new failure class.
- **Deepen-plan catch**: sudoers(5) requires `=` escaped in command args, but the in-file precedent (live + probed) resolves unescaped on the fleet's sudo-rs; plan standardizes on unescaped for byte-literal lockstep, escaped spelling recorded as fallback. Alias-body extraction must split on the first `=` only.
- **Boundary kept clean**: #9860 untouched; `kdeny` row retained (SOLEUR-DEBT note re-scoped, not deleted); ADR-075 Deferred paragraph amended; no new ADR; no C4 impact; all 12 cited issues/PRs and 4 rule IDs verified live.

### Components Invoked
- `soleur:plan` — SKILL.md read and run inline to completion: cloud-detect, premise validation, minimality/value gates, skeleton checkpoint, sequential research, gates (user-brand/GDPR/IaC/observability/ADR/encryption/guard-contract), SpecFlow, sharp-edges read, inline plan-review (`Reviewed-Coverage: sequential-fallback`), tasks.md + decision-challenges.md saved, commit + push (`8d96eef506`).
- `soleur:deepen-plan` — SKILL.md read and run inline: all halt gates (4.6–4.12, 4.45 verify-the-negative, 4.55), Phase 4.5 network deep-dive + telemetry; committed and pushed (`3094f935a5`).

---

## Review record (2026-10-11, resumed 2026-10-12)

**Panel (9 spawned, 8 agent + shellcheck deterministic):** classified `code`, tier `none` (plan's
sensitive-path scope-out honored), design-risk no. PANEL_SHA `9005da4048` (post-rebase onto
`cddc15da8d`; conflict in `server.tf` resolved keeping both sides, force-pushed).

Dedup ledger (~20 raw → 16 unique + 4 skips):

| defect | seats | severity | disposition |
|---|---|---|---|
| `^sudo:`-only denial signature misses GNU `Sorry,` shape (dead fallback → j=error) | test-design, code-quality (P1); git-history, pattern (P2) | P1 | FIXED: `^(sudo:\|Sorry,)` class + phrase requirement + mock pins both recorded bodies (rs/gnu) |
| Guard-1 census covers only `Cmnd_Alias` form | struct-enum (P1); security, test-design (P3) | P1 | FIXED: journalctl-mention totality==1 + anchored grant lines + no-include assert |
| accepted-run `sudo:` stderr pollutes counted stream | security (P3) | P3 | FIXED: post-check `^sudo:` strip + MOCK_SUDO_WARN fixtures (k6/k7) |
| d10g same-line smuggle / suffix-drift / kern boundary blind spots | struct-enum (P2/P3), architecture (P3) | P2 | FIXED: strip-first + widened boundary + suffix residual rule + SMUGGLE/SUFFIX/HELPERF fixtures |
| mock pins wrong denial subclass | pattern, test-design, code-quality | P2 | FIXED: rs=recorded fleet emission, gnu=sibling fixture shape; unknown value fails loud |
| test tightness (SJ anchor, KD==1, dead disjuncts, comment-strip, spacing) | test-design, code-quality | P3 | FIXED |
| plan/doc precision (paths: claim, eleven aliases, dmesg_restrict, FILE_MAP comment, "has LANDED", runbook wording) | git-history, pattern, architecture, struct-enum | P3 | FIXED |

**Fix round 1** (fix-range review over `9005da4048..1366a35ecf`, 8 seats resumed): all prior findings
CLOSED; two new P2s — un-ratcheted `CI_DEPLOY_ASSERT_FLOOR` (609 → 618 measured) and the `^sudo:`
strip shipping without fixtures (added MOCK_SUDO_WARN + D10k6/k7); plus micro-hardening
(include-whitespace, suffix boundary, rule-2b-only fixture, phrase requirement against the
warning-masquerade edge, stale `MOCK_SUDO_DENY=1` doc strings).

**Verified:** ci-deploy.test.sh 616/616 (round 1), cloud-init 250/250 (floor 173), handler 59/59,
terraform validate OK, visudo -cf OK, shellcheck clean.

Remaining: round-2 suite re-verify → review summary/trailer → qa → compound → ship.
