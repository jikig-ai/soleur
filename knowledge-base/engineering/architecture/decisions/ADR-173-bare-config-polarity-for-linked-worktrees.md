# ADR-173 — a bare repo keeps `core.bare` shared and leaves per-worktree resolution off

- **Status:** accepted
- **Date:** 2026-08-10
- **Issue:** #7394
- **Amends:**
  [ADR-099 — git surface topology](ADR-099-git-surface-topology.md)
  (row 3's `.git` column, and the new statement that `[[ -d <root>/.git ]]` cannot
  discriminate row 2 from row 3's root)
- **Related:** #5934 (the round-6 mask guard this preserves), #6184 (the non-bare
  regression that motivated the guard), #5912 (the lockless writer every config
  mutation here routes through), #7307 (the run during which the defect surfaced)
- **Supersedes:** nothing. Ordinal `173` re-derived from the decisions directory on
  2026-08-10 (ADR-172 was highest), not carried over from the plan.

## Measurement scope

**Every behavioural claim below was measured on `git version 2.53.0`** against synthesized
fixtures (`plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh`). Git has
changed what `git worktree add` writes to a shared config more than once, so treat the
version as part of the claim rather than as incidental context.

## Context

`worktree-manager.sh` used to enforce this shape on a bare repo:

```
.git/config             core.bare REMOVED, extensions.worktreeConfig = true,
                        core.repositoryformatversion = 1
.git/config.worktree    core.bare = true      (for the bare root)
```

The stated theory was *"`core.bare` must ONLY exist in `.git/config.worktree`, never in
`.git/config`."* Both halves of that are inverted.

**`extensions.worktreeConfig` is the half that wedges.** With it enabled, git resolves
`core.bare` per-worktree. A linked worktree that does not set `bare = false` in its **own**
`config.worktree` therefore falls back to the shared value — `true` — and git treats a
perfectly valid worktree as bare. `git rev-parse --show-toplevel` fatals, and every
`require_working_tree`-gated subcommand refuses with *"Cannot run from bare repo root"*.
And `git worktree add` writes **no `config.worktree` at all** (measured with `[[ -e ]]`;
the file does not exist, it is not an empty one), so **every** worktree created while the
extension is on starts out in exactly that state.

**Removing shared `core.bare` is not a safe end state either — on ADR-099 row 3.** It makes
that layout's bare **root** report as a normal working tree. (Measured: on row 1, where the
gitdir IS the root, git infers bareness from layout and the unset is inert. The justification
stands because row 3 is the operator's layout, but the claim is not universal.) That is the workaround applied by hand on the operator's
clone while diagnosing #7394; it is retired here rather than codified.

The wedge needs a **conjunction** of three conditions, not the two the issue names:

1. `extensions.worktreeConfig = true` in the shared config,
2. `core.bare = true` in the shared config, and
3. the linked worktree's own `config.worktree` not setting `bare = false`.

Removing (1) alone fixes it. The issue as filed names (2) and (3) but not (1), which makes
its root cause correct-but-incomplete: on a clone where the extension is absent the bug is
**latent**, not absent. `worktree-manager.sh` was the only in-repo production setter of that
key, so the tool that fixes this is also the only thing that was causing it — and after
#7394 there is no production setter left anywhere.

## Decision

On a repo whose shared config carries `core.bare = true`, `ensure_bare_config` enforces:

| Key | Location | State | Why |
|---|---|---|---|
| `core.bare` | shared `.git/config` | **kept** as `true` | the bare root must keep reporting bare |
| `extensions.worktreeConfig` | shared `.git/config` | **removed** | it is what redirects `core.bare` per-worktree |
| `core.repositoryformatversion` | shared `.git/config` | **no longer written** | only ever set to satisfy the extension |
| `core.worktree` | shared `.git/config` | **removed if stale** | unchanged from prior behaviour |
| `core.bare = false` | each worktree's own `config.worktree` | **seeded at create (bare repos only); healed at detection** | defense in depth (see below) |

This is the state git itself produces, so an untouched clone is already compliant and the
normalization performs **zero writes** on it.

**Bare-ness is decided from `core.bare` read out of the shared config FILE**, never from
the gitdir's shape, and still **defaults to SKIP**. Reading the file is what preserves the
#5934 round-6 mask protection: under the char-device mask the read degrades to empty with
a non-zero rc, which is not the literal `true` required to fall through, so a masked repo
takes the same skip branch it always took. It is deliberately **not** gated on
`core.repositoryformatversion` — a bare repo predating the extension era carries version 0,
so requiring 1 would reintroduce a shape test that misses exactly the repos most likely to
be poisoned.

**The per-worktree `core.bare = false` pin is defense in depth, not the fix.** With the
extension absent nothing reads `config.worktree`, so the pin is inert on a healthy repo. It
exists so a worktree stays correct if some other tool re-enables the extension later, and it
is gated on the repo being bare — on the non-bare Concierge workspace it would create the
very per-worktree config machinery `worktree-config-seed.ts` exists to keep off that surface.

**The detection-time self-heal writes only to the affected worktree's own admin dir.** It
fires on a two-way conjunction (git reports bare here, AND this CWD's gitdir resolves under
`<git-common-dir>/worktrees/`) and never touches the shared config. It also refuses to write
through a symlinked `config.worktree`, and re-probes before claiming success — the writer
returns 0 on its no-write fast path, so the rc alone does not mean the worktree is usable — a shared-config write from a path that runs on *every* invocation of this script
would reshape every sibling worktree at once.

## Migration

A repo normalized by the RETIRED polarity carries `extensions.worktreeConfig = true` with
shared `core.bare` **absent** (the old code unset it), and keeps the bare root reporting bare
via the root's own `config.worktree`. Deciding solely on `core.bare == true` would skip that
repo forever — the fix would converge on new repos and never reach the population the
previous release created.

So the guard also falls through when the extension is present, and the normalization
**restores `core.bare` before removing the extension**: until the extension is gone, the
root's `config.worktree` is what stands in for shared `core.bare`, so dropping the extension
first would momentarily de-bare the root — the end state this polarity exists to avoid.

Both probes are FILE reads, so the #5934 mask protection is unchanged: a masked config
degrades to empty for both, and such a repo takes the same SKIP it always took. That
deliberately leaves genuine-bare-under-mask reported (`reason=masked-cannot-determine`)
rather than escalated: escalating requires trusting `git rev-parse --is-bare-repository`,
which under that same degradation reports `true` for any normal clone, re-opening #5934 D3
on the production surface.

## Consequences

- The operator's existing worktrees, all created while the extension was live, recover on
  first use rather than waiting for the next session-start `cleanup-merged`. That gate is
  an AGENTS.md rule rather than a hook, and the learnings corpus records it being skipped.
- **Cross-surface convergence (a positive, not a new divergence).**
  `apps/web-platform/server/worktree-config-seed.ts` already pre-seeds workspaces so git
  works natively with **zero shared-config surgery**. The previous polarity disagreed with
  that encoding; this reversal removes a latent disagreement between the two rather than
  creating one.
- A failed self-heal is a genuine wedge and pages via `SOLEUR_GIT_BARE_SELFHEAL
  branch=failed`. Every other outcome is mirrored, not paged.
- `ensure_bare_config` is now reachable on ADR-099 row 3 for the first time. It was dead
  code there for as long as the shape-based guard existed.

## Alternatives Considered

**Keep the extension on and seed `bare = false` into every worktree (the plan's
reproduction matrix, row 4).**
Rejected. It makes correctness depend on a write happening for *every* worktree, forever,
including worktrees created by bare `git worktree add` outside this script — and since git
writes no `config.worktree`, any worktree created by any other tool is born broken. It also
cannot repair the existing population without transiting the wedged state anyway: to get
from today's poisoned repo to that target you must either remove the extension first (this
ADR's end state, at which point the extension buys nothing) or write into every worktree
while they are all still wedged. The chosen polarity makes the healthy state the
**default** rather than something each worktree must opt into.

**Codify the hand workaround (`git config --unset core.bare` in the shared config).**
Rejected: measured, it makes the bare root report as a normal working tree, breaking the
`IS_BARE` detection every other subcommand depends on.

**Keep the shape-based guard and special-case the bare-repo-in-`.git` layout.** Rejected as
a second shape test layered on a shape test that was already wrong. Config content is the
authoritative fact; the gitdir's shape never was.

## Re-evaluation trigger

Revisit if **either**:

1. a git release restores shared-config writes on `git worktree add` (which would make the
   removal of `core.repositoryformatversion` / `extensions.worktreeConfig` insufficient), **or**
2. a re-audit finds a **new setter** of `extensions.worktreeConfig` anywhere in the
   toolchain — including herdr and the Concierge runtime, not only this repo. As of
   #7394 there is **no** production setter of this key anywhere in the toolchain —
   `worktree-manager.sh` and `worktree-config-seed.ts` both only ever REMOVE it. The decision
   rests on that remaining true; a new setter invalidates it and re-arms the wedge.
