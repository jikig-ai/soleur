# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-01-fix-7103-recovery-residuals-r1-r5-plan.md`
- Status: complete
- Draft PR: #7146
- Scope check: PASSED — `git diff origin/main...HEAD --name-only` returned only
  `knowledge-base/project/plans/` + `knowledge-base/project/specs/`. No product code,
  workflow YAML, infra script, or CHANGELOG was touched by the planning subagent, so its
  "Decisions" are prescriptions rather than applied changes.

### Errors
- First plan write blocked by the IaC-routing PreToolUse hook (`systemctl` in plan prose).
  Resolved by adding the required `## Infrastructure (IaC)` section + `iac-routing-ack`
  marker — not by weakening the routing.
- A second write failed "file modified since read" after a linter touched the file;
  resolved by remove-and-recreate rather than reading a ~900-line file back into context.
- Verification sweep found one self-contradiction and corrected it in the plan:
  `run-registered-suites.sh --list | wc -l` returns 88 because the runner prints a
  `Derived N registered infra suite(s)…` header; Phase 0.2 now uses
  `| grep -c '\.test\.sh$'` expecting 87.

### Coordinator verification of plan claims (independent, post-return)
Three load-bearing claims were spot-checked before accepting the plan — the Session
Summary narrative was not trusted on its own:
1. **Repo is PUBLIC** — `gh repo view --json visibility` = `PUBLIC`. Confirms the
   `::add-mask::` requirement for R4 is real, not defensive.
2. **Suite count 87** — `run-registered-suites.sh --list | grep -c '\.test\.sh$'` = 87.
   Plan's prescribed command and expected value agree with measurement.
3. **`vector.service` runs `User=deploy`** — CONFIRMED. The unit is a heredoc inside
   `apps/web-platform/infra/soleur-host-bootstrap.sh`, not a standalone `.service` file
   (first grep missed it). `User=deploy` / `Group=deploy` verified verbatim. Its
   `ExecStart` also wraps vector in `doppler run --project soleur --config prd`, which
   independently corroborates R3: vector's own process dies with the credential whose
   failure it is supposed to report.

### Decisions
*(what the plan PRESCRIBES — nothing was applied during planning)*

- **R1 split into two halves; half (a) re-filed rather than implied.** Second invoker
  named as `apply-deploy-pipeline-fix.yml` › *Redeploy to load applied profile*. But the
  residual's remedy "give it `ZOT_REGISTRY_URL`" has no invoker-side site — both hooks
  pass identical environments and the URL resolves inside `ci-deploy.sh` from Doppler.
  Plan prescribes half (b) (loud failure on the credential-absent gate arm, the only arm
  lacking a degraded event) plus a 4-field `SOLEUR_DEPLOY_INVOCATION` marker as the
  discriminator, holding both hypotheses at UNKNOWN until it has been read. The residual's
  short-form log string does not exist at HEAD — the outage-fix PR replaced it — leaving
  "stale script" a live hypothesis the plan refuses to grade from source.
- **R2 picks option (b), gated on a security precondition absent from the residual's
  option set.** `infra-config-install.sh` validates drop-in content only for
  `/etc/default/*`; the three `*.service.d/*.conf` dests get none. With
  `vector.service` running `User=deploy`, a drop-in may set `User=root` + `ExecStart=` —
  inert today only because nothing root-restarts the unit. A drop-in shape gate therefore
  ships BEFORE the restart grant, for all four options.
- **R3 fixes the consumer, not the emitter, and repairs two defects in the existing
  control.** The canary already exists but runs inside `doppler run`; and
  `betterstack-query.sh` has no `--host` flag while `--grep` terms OR-combine, so a
  foreign host's canary could certify this host. Prescribes hoisting the emit out of the
  credential wrapper, a host-scoped raw-SQL read, and a four-outcome helper where
  `unknown` and `unshipping` can never return 0.
- **R4 accepts required-check gating deliberately.** The harness needs no tooling the
  required `test` job doesn't already run; the advisory alternative would put a regression
  guard in a runner nobody is blocked by — reproducing, in the same PR, the exact defect
  R5 exists to fix. Adds `::add-mask::` because the repo is public and the digest step
  `nonsensitive()`s a base64 of the live prd Doppler token.
- **R5(b) was already done** by the credential-channel PR (it re-anchored the liveness
  gate's assertions). Plan prescribes the missing half — a committed 7-arm mutation
  battery proving deletion goes red — not a second learning file.
- **Phase order follows the risk ranking** (R1 → R5(a) → R2 → R3 → R4 → R5(b)), with
  R2→R3 a hard dependent pair. One consequence recorded: R1's tests live inside the runner
  Phase 2 folds in, so Phase 1 is re-verified at the exit gate.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Research: `Explore` ×4 (infra/vector, CI test globbing, R5 suite gap, prior plans/ADRs)
- Review panel (escalated by the `single-user incident` threshold):
  `architecture-strategist`, `code-simplicity-reviewer`, `spec-flow-analyzer`,
  `security-sentinel`, `observability-coverage-reviewer`, `user-impact-reviewer`, plus an
  `Explore` verify-the-negative / attribution / count sweep
- `gh` (issue/PR/ruleset/repo-visibility reads), `git fetch origin main` + ADR-ordinal
  derivation, `git log -S`, `git commit`/`push`
