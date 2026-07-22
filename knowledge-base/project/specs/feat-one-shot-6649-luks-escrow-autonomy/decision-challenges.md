# Decision Challenges — feat-one-shot-6649-luks-escrow-autonomy

Recorded at plan/deepen-plan time (headless one-shot). `ship` renders these into the PR body and files an `action-required` issue for the operator (ADR-084). Each is a Taste / User-Challenge where a reviewer's recommendation diverges from the task's stated direction; the task direction is kept as the default, dissent surfaced here.

## 1. Autonomy mechanism: conditional-environment vs split-job (Taste)
- **Task direction / plan default:** conditional `environment: ${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` (the task's first-listed option; minimal diff).
- **architecture-strategist (P2):** prefers SPLIT-JOB (static literal `environment:` on a separate freeze job) for static auditability at single-user-incident threshold — the C19/AC20b property is then verifiable by inspection, not by trusting empty-string-environment vendor behavior.
- **Resolution:** kept conditional-environment as primary because the freeze arm always evaluates to the literal `'workspaces-luks-cutover'` (never empty), so the SAFETY property does not depend on empty-string handling — only the autonomy property does. Split-job documented as the fallback if Phase 0 empty-string verification fails or the PR-time security reviewer prefers it. **Operator may prefer split-job for auditability — flag for decision.**

## 2. verify.yml in scope (Scope)
- **Task direction:** BLOCKER 3 explicitly names "BOTH .github/workflows/workspaces-luks-cutover.yml AND workspaces-luks-verify.yml."
- **code-simplicity-reviewer:** cut verify.yml — it runs an already-installed file (no BASH_SOURCE bug) and is not on #6649's dry-run-green critical path.
- **Resolution:** kept per the task direction AND because verify.yml has a genuine token-delivery bug (manual `sudo /usr/local/bin/luks-monitor` has no `EnvironmentFile`, so `doppler` fails). Scoped its change to the token delivery + run-from-shipped-copy. **Operator may defer verify.yml to a follow-up if desired.**

## 3. WORKSPACES_LUKS_DEV derivation: hcloud API vs tf-published variable (Taste)
- **Task direction:** "terraform output or hcloud API" — runtime derivation.
- **code-simplicity-reviewer:** since the PR already adds a tf-published `github_actions_secret`, publish the device path as a `github_actions_variable` in the same apply and read `${{ vars.WORKSPACES_LUKS_DEV }}` — deterministic-at-apply, removes the runtime curl + `HCLOUD_TOKEN` read + regex guard.
- **Resolution:** kept hcloud-API-runtime (task direction; no extra tf resource / parity burden; the API call runs on the runner with a bounded `--max-time` + regex guard). **tf-published variable is a reasonable alternative if the operator prefers zero runtime network calls in the cutover.**
