# ADR-175: Shared bash primitives ship inside `plugins/soleur/` and resolve plugin-root-relative

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
`~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/`:

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

**This change arms the reaper.** Pre-fix, a marketplace user's missing library made
`is_lease_active` return "active" for everything, so `cleanup-merged` could never reap
anything. Post-fix the library resolves and an unrecoverable operation goes live for
that entire population **for the first time**. The refusal direction therefore carries
its own test in a cache layout, with a mutation arm proving the refusal is attributable
to the lease rather than to an inert reaper.

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
`git rev-parse --git-common-dir`, so they share one set of lease files. This is safe
**only** under byte-identity of the moved file — no lease-format change is permitted in
the move — and interoperation is asserted directly by running the pre-move library
(recovered from `origin/main`) against the post-move one. Byte-identity is verified on
the final tree by `diff`, never by `git show --stat -M`: rename detection is a
diff-renderer heuristic, not a stored property.

**No compat shim at the old path.** `_SOLEUR_SESSION_STATE_LOADED` makes a double-source
harmless, so a shim would be *safe* — but it would re-introduce the two-homes ambiguity
this decision exists to remove. The transient window fails **safe**: a missing library
makes `is_lease_active` return "active", so nothing is reaped.

**Delivery is not guaranteed by merging.** `plugin.json` carries the frozen sentinel
version `0.0.0-dev`, so the cache directory name never changes and there is no version
bump to trigger an update. Measured on the authoring machine: the install carries **64
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
