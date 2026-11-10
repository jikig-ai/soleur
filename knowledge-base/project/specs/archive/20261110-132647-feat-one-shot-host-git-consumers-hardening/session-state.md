# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-09-fix-host-side-git-consumers-hardening-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

None. Plan review cost two CTO re-rulings; findings folded into the plan.

### Decisions

- Shared helper in new leaf server/host-git.ts returns args and env; consumers keep their own auth vars.
- Scope adds the key-auth push and inflight-checkpoint; the isolated-GIT_DIR push path is untouched.
- Filter drivers and insteadOf rewriting stay open and are pinned as residual rows.
- Network arms land as separate revertable commits; auto-commit failures mirror to Sentry.

### Components Invoked

soleur:plan, soleur:plan-review, soleur:gdpr-gate, soleur:deepen-plan, soleur:engineering:cto (x3 rounds), review panel agents.

## Operator Constraints

- constraint: Epic stays open, do not close or edit it, use Ref only and never a closing keyword.
- constraint: No standing delegation, every step is authorized only as written, deliver exactly one PR.
- constraint: File no issue and post no comment on existing issues unless the CTO rules it and the operator says so.
- constraint: Do not touch the isolated-GIT_DIR push path, it is operator-held.
- constraint: Real-git falsifier first with git 2.38 or newer, then the fix, and state plainly what the control does not claim.
- constraint: Brand-survival threshold stays single-user incident.
- constraint: Never sync an armed or queued PR without an explicit operator OK.
- constraint: Operator-class actions are never done by the agent, flags, environments, prd writes, migrations, legal wording, public security claims ahead of measurement.
- constraint: Technical forks go to the CTO agent and not to the operator.
