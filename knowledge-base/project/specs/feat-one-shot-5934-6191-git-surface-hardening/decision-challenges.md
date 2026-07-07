# Decision Challenges — feat-one-shot-5934-6191-git-surface-hardening

Persisted headless (one-shot pipeline, no TTY) per plan Step 4.5 + Plan Review routing.
`ship` renders these into the PR body and files an `action-required` issue for operator visibility.

## D1 — Gate authority-inversion: resolve vs. accept-the-caveat (Taste)

**Context:** `.claude/hooks/prod-write-defer-gate.sh:112` `resolve_operator_email` falls back to
`git config --global --get user.email`. On the non-bare Concierge surface `--global` = the sandbox
bot (authority inversion). The path feeds an **audit log, not a git op**, and is reached only when
BOTH `SOLEUR_OPERATOR_EMAIL` and `GITHUB_ACTOR` are unset. ADR-099 §latent and the ARGUMENTS both say
*"resolve OR accept the caveat."*

**Scoped-advisor (fable) position:** lean **accept-the-caveat** — the bot-shape substring match can
*mis*classify a legitimately-named human/service account and downgrade it to `unknown@local`, trading
a known-wrong value for a differently-wrong one on a marginal, audit-only, double-unset-guarded path.

**Plan default:** accept-the-caveat (comment-only, cannot regress, ADR-sanctioned). Active fix
(bot-shape discriminator applied uniformly to `--local` AND `--global`) is documented as the
alternative if a reviewer/operator prefers an active resolution.

**Operator decision needed?** Optional. Both are within the ARGUMENTS' "resolve/accept" latitude.
Default proceeds with accept-the-caveat unless the operator elects the active fix.

## Note — scoped-advisor mechanical corrections (already applied, not challenges)

The advisor's two correctness corrections were auto-applied to the plan (Mechanical class):
(1) `atomicGitConfig` uses cp-p→temp→`git config --file`→`rename` (lock-free), NOT a stale-lock sweep
(sweep reintroduces a TOCTOU / can delete a live lock; `cp -p` first prevents dropping other keys);
(2) if the gate active-fix is chosen, apply the bot-shape check to both scopes. No operator action.
