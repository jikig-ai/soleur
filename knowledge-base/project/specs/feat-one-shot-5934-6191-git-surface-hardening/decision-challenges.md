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

## D2 — Keep the TS `atomicGitConfig` module, or collapse #6191 to comment-only? (Taste / User-Challenge)

**Context:** the operator's ARGUMENTS directed *"route workspace.ts:236/246 raw git config writes
through the stale-lock-safe atomic_git_config path (defense-in-depth),"* and ADR-099 §latent
prescribes exactly this. The plan default builds a rename-based TS `atomicGitConfig` module.

**Challenge (deepen-plan code-simplicity-reviewer):** DROP the module entirely. Native `git config`
is ALREADY atomic host-side (`config.lock`→rename) and the `workspace.ts` surface is unmasked,
single-writer, already `try/catch→log.warn` — so a hand-rolled writer buys near-zero marginal safety
(genuine residual value: immunity to a *stale/masked* `config.lock`, which is the crashed-provision
edge). Recommends treating workspace.ts exactly like the gate (D1): accept-the-caveat + a comment
citing ADR-099, collapsing #6191 to docs + two comments with zero new runtime surface.

**Counter-weight:** the scoped-advisor (fable) AND deepen-plan architecture-strategist both ACCEPTED
the module (architecture verdict: "ship-ready … executes an already-recorded ADR-099 decision"), with
only rationale-precision fixes (applied). So review is split 2-endorse / 1-drop.

**Plan default (operator's directed approach preserved):** KEEP the rename-based module — it honors the
explicit ARGUMENTS direction + the ADR-099 prescription + the 2 endorsing reviews, and the PR body
states the honest near-zero marginal value so no one over-reads the safety. The operator may elect the
comment-only collapse at /work or ship time; both close #6191.

**Operator decision needed?** Optional. Default proceeds with the module.

## Note — scoped-advisor mechanical corrections (already applied, not challenges)

The advisor's two correctness corrections were auto-applied to the plan (Mechanical class):
(1) `atomicGitConfig` uses cp-p→temp→`git config --file`→`rename` (lock-free), NOT a stale-lock sweep
(sweep reintroduces a TOCTOU / can delete a live lock; `cp -p` first prevents dropping other keys);
(2) if the gate active-fix is chosen, apply the bot-shape check to both scopes. No operator action.
