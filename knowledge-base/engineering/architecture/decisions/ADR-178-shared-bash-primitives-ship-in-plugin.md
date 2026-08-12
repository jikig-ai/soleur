# ADR-178: Shared bash primitives ship inside `plugins/soleur/` and resolve plugin-root-relative

- **Status:** Accepted
- **Date:** 2026-08-10
- **Issue:** #7409
- **Relationship to [ADR-093](./ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md):** **extends** it to a new member of a class it named. ADR-093 §Consequences leaves open the residual that some paths *cannot* be `${CLAUDE_PLUGIN_ROOT}`-anchored because they live outside `plugins/soleur/`, tracking two enumerated vectors under #6222 (the repo-root `scripts/` CWD-shadow set, and the `taste-profile-update.sh` siblings). `.claude/hooks/lib/session-state.sh` is **not** one of those two — it is a third instance of the same shape, and this ADR resolves it by the move #6222's members cannot use: **relocating the file so it becomes anchorable**, rather than adding an anchor that cannot reach it.
- **Relationship to [ADR-156](./ADR-156-hook-stdin-is-model-controlled-and-untrusted.md):** **constrained by** it. The relocated file carries the one allow-listed `eval` in the hook scan set, so the move had to preserve that scan set rather than silently narrow it (see Consequences).

## Context

`session-state.sh` implements Soleur's cross-session concurrency layer —
`acquire_lock` / `with_lock` / `acquire_lease` / `release_lease` / `is_lease_active` /
`sweep_orphan_leases` / `headless_or_stderr`. It is the only thing that distinguishes a
live session from an abandoned one before `worktree-manager.sh cleanup-merged` performs
an **unrecoverable** operation: delete the worktree, delete the local branch, delete the
remote branch, and close the PR.

It lived at `.claude/hooks/lib/session-state.sh` — inside Soleur's own repo-development
harness, which **the marketplace does not ship**. `marketplace.json` declares
`"source": "./plugins/soleur"`, a whole-subtree copy; nothing outside that directory
reaches an installed user.

`worktree-manager.sh` resolved the library with a fixed five-level walk:

```bash
_SS_LIB="$SCRIPT_DIR/../../../../../.claude/hooks/lib/session-state.sh"
```

From `<repo>/plugins/soleur/skills/git-worktree/scripts/` that lands on the repo root and
works. From the installed layout —
`~/.claude/plugins/cache/<marketplace>/soleur/<version>/skills/git-worktree/scripts/` —
it lands on `~/.claude/plugins/cache/<marketplace>/.claude/hooks/lib/session-state.sh`,
which does not exist and never has.

### Measured, not inferred

On the authoring machine, against the real install at
`~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/` *(the path shape as it stood on
2026-08-10; the third segment is no longer `0.0.0-dev` and the first is no longer
`soleur` for a new install — see the [2026-08-12 amendment](#amendment--2026-08-12-7471-the-cache-path-segments-and-the-delivery-comparator).
The reading below is unaffected: the library was absent at any depth)*:

```
$ find ~/.claude/plugins/cache/soleur -name 'session-state.sh'     # → empty
$ find ~/.claude/plugins/cache/soleur -name '.claude' -type d      # → empty
```

The install contains `skills/ scripts/ hooks/ agents/ commands/ docs/ test/` and nests
12 path-components deep. There is no `.claude/` at any depth, and the library is absent
entirely.

The consequences for every marketplace-installed user:

1. `worktree-manager.sh` loads its no-op stubs and prints
   `SOLEUR_WORKTREE_LEASE_LIB_MISSING`. `create` never acquires a lease.
2. `is_lease_active` is a **fail-closed** stub returning `0` ("active"), so
   `cleanup-merged` refuses to reap anything, ever. Users get neither the protection nor
   the cleanup.
3. The seven `SKILL.md` sites invoking `bash .claude/hooks/lib/session-state.sh …`
   exit **127**. On `ship` / `merge-pr` / `product-roadmap` / `schedule` the wrapped
   command is `gh pr merge --squash --auto`, so **the merge is simply never queued** —
   a hard functional failure, not a degraded one.

The coupling was **file-resolution only, never semantic**: `_session_state_root()`
anchors to `git rev-parse --git-common-dir` of the target repo and `WORKTREE_DIR` to
`$GIT_ROOT/.worktrees`. Everything stateful was already target-repo-derived and portable.
The library is stateless code that simply could not be found.

## Decision

### 1. Location

A shared bash primitive consumed by shipped plugin code lives **inside
`plugins/soleur/`**, never in `.claude/hooks/lib/`. Destination:
**`plugins/soleur/scripts/lib/session-state.sh`**.

Grounds, each verified against the tree rather than recalled:

- `plugins/soleur/scripts/` is the plugin's established home for sourceable shell
  helpers — `resolve-git-root.sh` lives there and `plugins/soleur/hooks/stop-hook.sh:14`
  already sources it `$SCRIPT_DIR`-relative. The pattern is not new.
- The `lib/` segment keeps ADR-156's A1 carve-out (`*/lib/session-state.sh`, suffix
  matched) matching with **zero edit** to the carve-out itself.
- `<x>/scripts/lib/` is an established repo pattern (`scripts/lib/`,
  `apps/web-platform/scripts/lib/`).
- Nested directories demonstrably ship — the live install nests 12 deep.

**Rejected `plugins/soleur/hooks/lib/`.** That directory is Claude Code's
hook-*registration* surface (the install carries `hooks.json` beside three `*-hook.sh`),
and this library is consumed by skills and repo-side scripts as well as hooks — so
`hooks/` is a cohesion misnomer. Its one advantage, keeping the A1 suffix carve-out
matching, is satisfied equally by `scripts/lib/`.

**Rejected `plugins/soleur/lib/`.** TypeScript-only by convention (created 2026-07-11,
`766199eda`); dropping a 590-line bash primitive there forks a settled convention.

### 2. Resolution order, by consumer class

- **In-plugin shell (`worktree-manager.sh`): `$SCRIPT_DIR`-relative, first and only** —
  `$SCRIPT_DIR/../../../scripts/lib/session-state.sh`. Identical arithmetic in the repo
  and in a cache install. **No environment variable.**

  This is load-bearing and deliberately *inverts* the resolution order the issue
  proposed (`CLAUDE_PLUGIN_ROOT` → plugin-relative → repo-relative). An env-dependent
  primary would make the destructive path's protection contingent on an invariant that
  is not guaranteed on the CLI — precisely the class of assumption ADR-093's amendment
  had to pin at `buildAgentEnv`. A path that is correct by construction needs no such
  pin.

- **Agent-executed `SKILL.md`:** `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/scripts/lib/session-state.sh`
  — the same anchor form every Soleur skill invocation already uses (ADR-093 Slices
  B/C/D), preserving each site's existing default arm. No bespoke resolver chain: after
  the move the library sits behind the *identical* anchor as the scripts beside it, and
  if that anchor does not resolve the user cannot run any Soleur skill at all — a far
  wider defect than this one.

- **Repo-only consumers** (`.claude/hooks/**`, `scripts/lib/`): reach into
  `plugins/soleur/scripts/lib/` relative to their own location.

### 3. Single source of truth — MOVE, not duplicate

No mirror, no drift gate. `plugins/soleur/AGENTS.md` permits duplication only for a pure
importable `lib/*.mjs` under a logic-parity guard; a 590-line `flock`/file-descriptor
primitive is the worst possible candidate, because drift in it is silent and fails
**open** on a destructive operation.

### 4. The canonical snippet

The `$SS_LIB` assignment **is** the defect, so it is standardised here in full rather
than shown as an `if` wrapped around an elided path:

```bash
SS_LIB="${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/scripts/lib/session-state.sh"
if [[ -r "$SS_LIB" ]]; then
  bash "$SS_LIB" with_lock merge-main 600 -- <CMD>
else
  echo "SOLEUR_SESSION_STATE_LIB_MISSING path=$SS_LIB reason=running-unlocked"
  <CMD>
fi
```

The `600` contention timeout is replicated across the four `with_lock` sites
(`merge-pr`, `product-roadmap`, `schedule`, `ship`); it is a per-site literal, not a
shared constant.

### 5. Terminal-arm disposition follows the destructiveness gradient

Not a blanket fail-closed rule. **What the call guards decides how its absence
degrades:**

| Call | Guards | Absent-library disposition |
|---|---|---|
| `with_lock … -- gh pr merge` (4 sites) | Advisory serialisation of concurrent auto-merge queueing | **Degrade open, loudly.** Fail-closed here leaves the user's PR unqueued — the original bug with a better error message. |
| `release_lease` (2 sites) | Nothing; leases expire on their own window | **Degrade open** (`\|\| true`). Inert either way. |
| `acquire_lease` (1 site) | **The acquisition of the protection itself** | **Degrade open, never silently.** Emits `reason=worktree-UNLEASED-and-reapable`. |
| `is_lease_active` (reap path) | An **unrecoverable** delete | **Fail closed** — unchanged. |

The `acquire_lease` row is the one that inverts naive intuition. It sits beside
`release_lease` in the code and looks like the same advisory class, but a silent
degrade there manufactures exactly the exposure the lease exists to prevent: a worktree
running unleased that a sibling `cleanup-merged` — now that this change **arms the
reaper** — is free to destroy.

### 6. Security posture

Post-move a marketplace user loads the library from `~/.claude/plugins/cache/`, i.e.
**outside** the untrusted connected workspace. This is a posture *improvement*
consistent with ADR-093's direction, not a weakening: previously the resolved path (had
it existed) would have been inside the user's own repo.

## Consequences

**This change arms the reaper, and arming it is a distinct event from running it.**
Pre-fix, a marketplace user's missing library made `is_lease_active` return "active" for
everything, so `cleanup-merged` could never reap anything. Post-fix the library resolves
and an unrecoverable operation goes live for that entire population **for the first
time**. The refusal direction carries its own test in a cache layout, with a mutation arm
proving the refusal is attributable to the lease rather than to an inert reaper.

That covers the steady state. The *transition* needed its own handling: every worktree
already on such a machine was created by a `create` that could not acquire a lease, so
none of them can hold one, and `cleanup-merged` runs at session start — so the first
post-upgrade session would have swept the entire accumulated backlog in one pass. Each
of those reaps might be individually correct; the objection is that the user's first
notice of the capability would have been its aftermath, including gitignored files
(`git status --porcelain` does not list ignored paths, and the reap's `--force` retry
removes them anyway). `cleanup_merged_worktrees` therefore takes a **one-time dry pass**
the first time it can reap on a given store: it reports what it would delete, emits
`SOLEUR_WORKTREE_REAPER_ARMED`, deletes nothing, and stamps the store. The stamp is what
makes it self-clearing — a condition-based hold ("hold while zero leases exist") would
never clear on a machine whose sessions only run cleanup, leaving the reaper permanently
inert, which is a worse failure than the one being prevented. Both directions are
mutation-tested.

**The ADR-156 eval scan set had to be preserved explicitly.** A1's roots are walked with
`find … 2>/dev/null`, so removing or outrunning a root makes the gate report `ok` while
scanning strictly less — a silently-narrowed green gate, the #5454 shape. Extending the
roots is a one-time patch; the durable half is a **membership assertion** that fails if
the enumerated set contains no `*/lib/session-state.sh`, plus a success message that
names the set actually scanned rather than a narrower one.

**The library's own test suite had never gated CI.** `test-all.sh` globs
`.claude/hooks/*.test.sh` **flat**, so `.claude/hooks/lib/session-state.test.sh` (34 KB)
was an orphan — which is how the #5454 vacuous-green class survived in it. Relocating
the suite to `plugins/soleur/test/` puts it inside an existing glob and de-orphans it.
Note that shell globs do not cross `/` while Python's `fnmatch` does: checking this with
`fnmatch` reports the file as covered and would have falsified the finding.

**Mid-rollout, two library homes coexist on disk.** A worktree created before this change
sources the old path; a new one sources the plugin. Both anchor their lease store to
`git rev-parse --git-common-dir`, so they share one set of lease files. This is safe only if the two copies agree on the lease FORMAT. The moved file is
identical to its predecessor **apart from comments** — it is not byte-identical, and
saying so would be false on inspection (`diff` reports four comment-only hunks). The
property the rollout actually depends on is behavioural, and it is asserted directly
rather than inferred from the diff: a scenario runs the pre-move library — recovered
from its immutable blob, not from a moving ref — against the post-move one and checks
that a lease written by either is honoured by the other. Do not substitute
`git show --stat -M` for that: rename detection is a diff-renderer heuristic, not a
stored property, and it says nothing about interop.

**No compat shim at the old path.** `_SOLEUR_SESSION_STATE_LOADED` makes a double-source
harmless, so a shim would be *safe* — but it would re-introduce the two-homes ambiguity
this decision exists to remove. The transient window fails **safe**: a missing library
makes `is_lease_active` return "active", so nothing is reaped.

**Delivery is not guaranteed by merging.** *(Reasoning superseded 2026-08-12 — see the
[amendment](#amendment--2026-08-12-7471-the-cache-path-segments-and-the-delivery-comparator).
The measured staleness below stands; the explanation for it has changed.)* `plugin.json`
carried the frozen sentinel version `0.0.0-dev`, so the cache directory name never
changed and there was no version bump to trigger an update. Measured on the authoring
machine: the install carries **64
skills against 96 in the repo**, with mtime **2026-05-10** — three months and 32 skills
stale — while its `.in_use` marker is stamped today. It has been actively used and has
received nothing. Users who never run `claude plugin marketplace update soleur &&
claude plugin update soleur` do not receive this fix, and no acceptance criterion can
cover that. This is a real limit on the change, stated rather than assumed away.

## Alternatives considered

| Option | Verdict |
|---|---|
| **A. MOVE to `plugins/soleur/scripts/lib/`** | **Chosen.** Sourceable-helper home, keeps the A1 suffix carve-out matching, established `<x>/scripts/lib/` pattern, honest cohesion. |
| B. MOVE to `plugins/soleur/hooks/lib/` | Rejected — `hooks/` is the hook-registration directory; cohesion misnomer (§1). |
| C. MOVE to `plugins/soleur/lib/` | Rejected — TypeScript-only by convention (§1). |
| D. DUPLICATE + drift gate | Rejected — silent, fail-open drift in a `flock` primitive (§3). |
| E. Keep in `.claude/hooks/lib/`, add a fallback chain | **Not a fix.** The file genuinely does not exist in the cache tree; a chain over nonexistent paths still ends in stubs. |
| F. Bespoke 4-arm resolver + extracted `resolve-session-state.sh` | Rejected as circular: sourcing the resolver requires resolving `plugins/soleur/` — the identical problem, plus a file. |
| G. Class-level `plugin-self-containment` CI gate | Rejected on measurement: **65 files / 338 hits** of `.claude/` under `plugins/soleur/**`; restricted to non-test `.sh`, **8 files / ~25 hits, of which exactly one is the defect** — a 96% seed-allowlist rate. The signature is also wrong: `$PROJECT_ROOT/.claude/` is *correct* (it addresses the user's repo, not ours). A cache-install test catches escapes behaviourally instead. |

## Amendment — 2026-08-12 (#7471): the cache-path segments and the delivery comparator

This ADR's `## Context` and `## Consequences` each named the installed cache path
`~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/`, and `## Consequences` reasoned from it
that "the cache directory name never changes and there is no version bump to trigger an
update." Both statements were true when written. Neither is true now, and they stopped
being true in **two independent ways** — which is why this is one amendment rather than a
line edit.

**What changed.** #7471 removed the `0.0.0-dev` version key from both in-repo manifests
(`plugins/soleur/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`'s
`plugins[0]`), and published an **additive** second marketplace source at
`jikig-ai/soleur-marketplace` — a `git-subdir` entry pointing back at `plugins/soleur` in
this repository. `jikig-ai/soleur` remains a valid marketplace; existing installs keep
working and do not auto-migrate.

**The path, by segment.** The cache path is
`cache/<marketplace manifest name>/<plugin name>/<version>`. All three segments were read
off a real install, not inferred — the `installPath` shape is recorded in
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/measurements.md`
§1.0, which is also where the byte and timing readings live. Cite that file by anchor
rather than restating its numbers.

| Segment | This ADR asserted | After the sentinel removal (existing install) | After the new marketplace (new install) |
|---|---|---|---|
| Marketplace | `soleur` | `soleur` (unchanged) | the `name` declared by `jikig-ai/soleur-marketplace`'s `.claude-plugin/marketplace.json` — the manifest's `name` field, **not** the repo name |
| Plugin | `soleur` | `soleur` (unchanged) | `soleur` (unchanged) |
| Version | `0.0.0-dev`, "never changes" | `unknown`, refreshed in place | `unknown`, refreshed in place |

Two cautions on that table. The §1.0 gate run resolved a version segment of `0.0.0-dev`
because it cloned pre-fix `main` — the manifest it materialised still carried the key; the
`unknown` value is the keyless resolution measured against the official control-group
plugins, not a guess. And the marketplace segment comes from the published manifest's
`name`, so it is read off that file rather than derived from the repo slug.

**The comparator, not the directory name.** The replacement reasoning is the one that
matters for delivery. `claude plugin update` short-circuits when it can compare two
identical version strings — that is the mechanism behind the staleness measured above. A
**keyless** manifest suppresses no `gitCommitSha`: the CLI records the source commit and
compares *that*, so new content is delivered by the source commit advancing rather than by
a version bump. The distribution manifest deliberately carries no pinned `ref`/`sha` and
tracks `main` for the same reason: a constant pin would be the frozen sentinel wearing
different clothes.

**What this does not change.** ADR-178's decision stands untouched. The library still
ships inside `plugins/soleur/` and still resolves `${CLAUDE_PLUGIN_ROOT}`-anchored, which
is precisely why the segment values above are *not* load-bearing — an anchored resolver is
indifferent to what the three segments happen to be, and the five-level walk this ADR
removed was the thing that was not. §6's security posture claim is likewise unaffected: it
names `~/.claude/plugins/cache/` without segments.

**The residual limit stands, for a different reason.** A user who never refreshes still
receives nothing. What changed is the cost of refreshing: the migration and install path
through `jikig-ai/soleur-marketplace` does not clone the monorepo, so the operation that
used to time out is no longer on the route.
