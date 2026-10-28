# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11445-web2-ci-ssh-preauth/knowledge-base/project/plans/2026-10-28-infra-web2-ssh-preauth-after-rebirth-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Initial plan write blocked by `.claude/hooks/iac-plan-write-guard.sh` (`ssh root@`/`operator runs` framing); resolved by routing all mutating arms through committed instruments (`scripts/capture-web-2-host-key.sh`, conditional `terraform_data` twin).
- deepen-plan agent fan-outs could not run (no agent-spawning tool in this harness); hard gates ran orchestrator-side, technical forks persisted as `pending - assumed:` rows.
- `collision-precheck.sh` flagged PR #11448 — verified as this pipeline's own draft PR.

### Decisions
- Root cause corrected by evidence: run 40744937376 log shows `Host key verification failed.` — stale `web-2-ssh-host-key.pub` pin after the 10-28 rebirth; the issue's "auth rejection" framing was wrong. Recorded as AC6.
- Evidence-ordered repair arms: Phase A re-capture pin (unconditional) → Phase B read-only on-host diagnostic via admin-IP → Phase C conditional `terraform_data.root_authorized_keys_web2` twin (only if pubkey proven absent) → re-replace fallback (workflow's `stock_preflight_gate` covers cx33 stock).
- Conditional arm kept conditional (mechanism minimality); IaC twin ships only on proven key absence.
- One merge self-verifies both consumers: pin file is in `apply-deploy-pipeline-fix.yml` push paths and under `apply-web-platform-infra.yml`'s `apps/web-platform/infra/**` glob; `deploy_pipeline_fix_web2` `triggers_replace` includes the pin file.
- Lane `cross-domain` (fail-closed default); threshold `none` with sensitive-path scope-out.

### Components Invoked
- Skill soleur:plan (inline), soleur:deepen-plan (inline)
- Scripts: cloud-detect.sh, collision-precheck.sh, lint-guard-contract.py; gh for issue/run/PR reads
- No agents spawned; CTO rulings pending in decision-challenges.md
cto_spawns=1
