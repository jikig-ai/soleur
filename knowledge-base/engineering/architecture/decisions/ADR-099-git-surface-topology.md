# ADR-099: Canonical git-surface topology — three layouts and the code paths they gate

**Status:** accepted
**Date:** 2026-07-07
**Deciders:** Engineering (CTO carry-forward from the #6184 non-bare worktree-identity-wedge fix)
**Related:** #6184 (the fix that surfaced the need for this canonical record), ADR-081 (chardevice `config.lock` substrate), ADR-068 (multi-host shared git-data), ADR-075 (agent-sandbox tenant read isolation), `knowledge-base/engineering/operations/post-mortems/concierge-worktree-creation-stale-lock-wedge-postmortem.md`

## Context

Six consecutive rounds of worktree-creation-wedge fixes (#5880 → #5907 → #5932 → #5934 → #6041 → #6071/#6108) kept mis-targeting the failing code path. The **root reason they recurred** was never a single bug — it was that Soleur runs git across **three structurally different repository layouts**, and this distinction was **tribal knowledge**: recorded only as an inline comment in `worktree-manager.sh` and re-derivable only by reading server provisioning code. Every round silently assumed one layout's polarity and hardened a path that does not execute on the layout that actually fails in production.

This ADR makes the three-surface model a **canonical, first-class fact** so future git-touching changes reason about *which* layout their code runs on before choosing an idiom.

## Decision

Soleur operates git over exactly three surfaces. Treat this table as authoritative:

| Surface | Layout | `.git` | Where it lives | Provisioned by |
|---|---|---|---|---|
| **Server-side git-data** | **BARE** (`git init --bare`) | git dir IS the repo root | `/mnt/git-data/repositories/<id>.git` | `apps/web-platform/infra/git-data-provision.sh` |
| **Agent workspace** (where `worktree-manager.sh` runs in production) | **NON-BARE** (`git clone --depth 1`, `core.bare=false`) | a `.git` **directory** | `/workspaces/<id>` | `apps/web-platform/server/ensure-workspace-repo.ts` |
| **Local CLI dev** | **BARE** root + linked worktrees | a `.git` **file** in each worktree | operator's checkout | operator's own clone |

**The load-bearing consequence.** `worktree-manager.sh`'s `ensure_bare_config` carries a **NON-BARE GUARD** (`worktree-manager.sh:478`, `#6184`): on a non-bare repo it runs the lock sweep and then `return 0`s **before** reaching `atomic_git_config`/`_config_lock_wedged`. So on the production Concierge agent workspace — which is **non-bare** — `ensure_bare_config`'s `atomic_git_config` machinery **never executes**. That is precisely the surface every prior wedge round hardened, which is why the wedge survived them: the actual production failure (#6184) was in `ensure_worktree_identity`, a *different* code path that runs on *both* layouts and whose identity-authority polarity is inverted between them (see ADR-081 §Decision). (Exception: `ensure_worktree_identity`'s own set-when-absent fallback DOES call `atomic_git_config` and IS reachable on the non-bare workspace — but only in the degraded host-seed-missing case, and it refuses to write a bot-shaped `--global` rather than misattribute.)

**Idiom rules that follow from the topology:**

- Do **not** assume `.git` is a directory. In a linked worktree it is a **file**; on a bare root it IS the git dir. Resolve the shared config with `git rev-parse --path-format=absolute --git-common-dir`, never `$GIT_ROOT/.git/config`.
- `git rev-parse --is-bare-repository` returns **false inside a worktree of a bare repo** — check the common-dir, not the worktree, to detect bareness.
- `git rev-parse --show-toplevel` is empty/fails on a bare root; prefer `--git-common-dir` for layout-agnostic path resolution.
- `git pull` / `git checkout` / `git stash` fail on a bare root; bare-only idioms (fetch-with-refspec, `update-ref`) are wrong on a non-bare clone. Gate on the actual detected layout, not an assumed one.
- Identity authority is inverted: on the non-bare Concierge workspace the **local** identity is the host-seeded owner (authoritative); on the bare CLI dev repo the operator's **global** is the human. Never blanket-force one over the other (the #6184 bug).
- A script that provably runs on **one** known layout (e.g. `git-data-provision.sh`, server-side on the bare data repo) may safely use that layout's idioms — but the single-layout assumption must be explicit, not accidental.

## Alternatives Considered

- **(i) Leave the topology as an inline comment in `worktree-manager.sh`** — rejected: that is exactly the state that let six rounds mis-target the wedge. A canonical ADR + always-loaded AGENTS pointer is the durable fix.
- **(ii) Collapse the layouts by making the agent workspace bare too** — rejected: the non-bare `git clone --depth 1` is the correct shallow-checkout shape for the agent sandbox; changing it to satisfy a script assumption inverts the dependency (fix the scripts, not the substrate).

## C4 impact

**None.** All three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) were checked. The surfaces are already-modeled containers (server git-data volume per ADR-068, the `/workspaces` agent compute per ADR-075); this ADR documents their git layouts, adding no element, edge, or actor.

## Known latent surfaces (audited #6184, tracked follow-up)

A full audit of every git-touching script (#6184) against this table found **zero** bugs that break on a layout they actually run on — the identity-inversion (#6184) was the only load-bearing instance. Two **low-severity latent** items carried the same smell but cannot strand a user; both were tracked for defense-in-depth and are now **RESOLVED (2026-07-08, #6191)**:

- ~~`apps/web-platform/server/workspace.ts:236/246`~~ — **RESOLVED (2026-07-08, #6191).** The host-side raw `git config` write that seeds the OWNER as the local identity now routes through the lock-free TS `atomicGitConfig` (`apps/web-platform/server/git-config-atomic.ts`): `cp -p` current config → same-dir temp → `git config --file <tmp>` → atomic `renameSync`, never touching `.git/config.lock`. Runs host-side (no mask), single-writer, still wrapped in try/catch → `log.warn` (never a strand). A non-regular (masked) config target fires a captured `reportSilentFallback` event and aborts without renaming.
- ~~`.claude/hooks/prod-write-defer-gate.sh`~~ — **RESOLVED (2026-07-08, #6191): accepted-the-caveat.** `resolve_operator_email` still prefers `--global`, whose trust model is inverted on the non-bare Concierge surface (there `--global` = the bot). The path is reached only when both `SOLEUR_OPERATOR_EMAIL` and `GITHUB_ACTOR` are unset and feeds an audit log, not a git operation, so the inversion was **documented, not code-changed** (the resolver comment now states plainly that under a double-unset the bot may be recorded as the operator). An active bot-shape discriminator was the alternative; see decision-challenges.md D1 for why accept-the-caveat was the lower-risk close.

## Consequences

- Positive: git-touching changes now have a single citable source for which layout runs where; the recurring wedge class has a documented root cause; the #6184 script audit graded ~20 files against this table and confirmed no other load-bearing instance.
- Negative / watch: the table must be kept current if a future ADR-068 shared-git-data topology or a nested-workspace layout changes any surface's shape.
