---
title: "Durable agent-surface git-strand heal — add a host rev-parse confirm for dir-valid worktrees + an agent-context observability backstop, via one shared gate helper across all three dispatch gates"
type: fix
date: 2026-06-30
issue: 5733
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain  # no spec.md on the one-shot path → defaulted to cross-domain (fail-closed)
---

# Durable agent-surface git-strand heal (#5733)

## Enhancement Summary

**Deepened on:** 2026-06-30. **Review lenses:** 8 — CTO + spec-flow-analyzer (plan phase), then architecture-strategist, data-integrity-guardian, security-sentinel, performance-oracle, code-simplicity-reviewer, and a verify-the-negative grep pass (deepen phase). All 6 of the plan's factual premises were independently CONFIRMED against the code; zero P0 on the destroy boundary.

### Key revisions folded from review
1. **The "union" collapses to a single new arm.** `isReadyGitWorkTree` already heals escaping pointers on main (`git-worktree-validity.ts:183`), so behind the lstat pre-filter the `isStrandingFilePointer` arm is dead — the net-new mechanism is **just a host `git rev-parse` confirm for `dir-valid` shapes** (the one slice lstat cannot adjudicate). Reframed throughout.
2. **`rev-parse --is-inside-work-tree` does NOT validate object integrity** (perf P1) — it confirms gitdir *discoverability*. So this fix catches the corrupt-/unresolvable-`dir-valid` slice, NOT object-store corruption (HEAD→missing objects), which stays the documented out-of-scope residual.
3. **754ee124's shape is unconfirmed and may not be union-catchable** (arch/data P1). Shape confirmation moves to **Phase 0** (read-only live probe); the plan is made robust to the unconfirmed shape by an **agent-context observability backstop** (deliverable C2) that fires on the agent's *actual* in-sandbox Step 0.0 rev-parse failure regardless of on-disk shape.
4. **Fail-OPEN on an inconclusive probe** (arch P0 / data+perf P1) — a transient timeout/spawn-error must NOT honest-block a healthy `dir-valid` repo (that manufactures the exact #5733 strand). Disambiguate genuine `not-a-worktree` (heal/block + self-stop) from `probe-error` (re-probe once → spawn + low-signal breadcrumb).
5. **One shared `evaluateAgentReadinessAndEmit` helper** across cold/warm/reconcile (arch/data/simplicity P1) — the cold-only emit + warm/reconcile drift IS the 26×-dark incident; structural sharing > the type-widening grep.
6. **Reconcile `:368` `recovered` re-probe must also swap to `agentReady`** (data P1) — else populated-corrupt takes the recovered branch and the event never fires.
7. **Drop warm memoization** (perf/data/simplicity P1) — staleness masks sub-lstat corruption.
8. **Security hardening** (5×P1): `execFileAsync("git",[…])` array form, hardened git env (`GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL=/dev/null`/`GIT_TERMINAL_PROMPT=0`), no installation token, **no subprocess stderr/path in the Sentry `extra`** (git errors embed the raw path = raw userId for solo), tight ~2s timeout + `maxBuffer` + `killSignal`.

### New considerations discovered
- The escaping-pointer strand is already healed on main at all 3 gates; the subprocess earns its ADR-044 perf reversal ONLY for the corrupt-`dir-valid` slice — attributed honestly in the ADR Alternatives.
- `ensure-workspace-repo.ts` has **three** `rm(` calls (`:174`, `:236`, `:354` tmp-clean) — AC6's write-boundary assertion must scope to `.git`-targeting rm.
- `GIT_CEILING_DIRECTORIES` must be the absolute, symlink-resolved parent (AC2 adds a symlinked-`/workspaces` fixture).

## Overview

Concierge workspace `754ee124…` (the operator's own) still strands `/soleur:go` on
*"not a git repository"* **after** the prior fix (commit `190ab58a5`, merged
2026-06-30 14:32 UTC, deployed ~15:00 UTC). That commit shipped lstat-based
structural scaffolding (`probeGitWorktreeShape`, `isReadyGitWorkTree`,
`isStrandingFilePointer` in `git-worktree-validity.ts`) plus the
`reportAgentReadinessSelfStop` Sentry mirror, wired at all three dispatch gates.
**Those are on main — this PR does NOT re-ship them.** This PR closes the gap they
left:

1. All three readiness gates decide heal/spawn on a **cheap lstat structural
   proxy** (`isReadyGitWorkTree` = `dir-valid` OR non-escaping `file-pointer`).
   ADR-044's 2026-06-19 amendment chose that proxy *explicitly* as "deliberately
   WEAKER than `git rev-parse --is-inside-work-tree` but cheap enough to keep the
   AC7 zero-await hot path." For 754ee124 the proxy returns **ready**, so the heal
   is skipped, the agent spawns, and its in-bwrap `git rev-parse` strands. This is
   the textbook proxy-vs-invariant divergence (`2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`).
2. Because the gate is the lstat proxy, the `agent_readiness_self_stop` mirror is
   also silent (its firing condition is `!gitReady`, the same proxy) — zero
   `agent_readiness_self_stop` events exist in EU Sentry despite the confirmed
   strand. The observability is **blind precisely on the shape it was built to see.**
3. The mirror is wired at the **cold** path only. The two other gates (warm
   reprovision, Inngest reconcile-on-push) are observability-dark — and the
   reconcile path is the surface a prior session proved actually fires (26× on the
   affected workspace, zero actionable events; `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`).

**The durable fix (two complementary deliverables, one shared gate helper across all
three gates):** (A) for the one shape the on-main lstat verdict greenlights but the
agent still strands on — a `dir-valid` `.git` that `git rev-parse` itself cannot
resolve — add an authoritative host `rev-parse` confirm, fail-OPEN on an inconclusive
probe, emit-and-honest-block on a confirmed corruption (never destroy a populated
`.git`); and (C2) an **agent-context observability backstop** that fires on the
agent's *actual* in-sandbox Step 0.0 rev-parse failure, so the strand surfaces for
*any* on-disk shape — including the object-store residual the host confirm is blind
to. The escaping-pointer and dir-invalid realizations are already healed on main.

PR body uses **Ref #5733** (not Closes) — operator-surface reproduction on 754ee124
is post-merge verification.

## Problem Statement / Motivation

`/soleur:go` Step 0.0 runs `git rev-parse --is-inside-work-tree` inside the agent's
Bash bwrap sandbox, which sets `denyRead:["/workspaces","/proc"]`
(`agent-runner-sandbox-config.ts:94`) and is jailed to `workspacePath`. A `.git`
whose `gitdir:` target resolves under the `/workspaces` **parent** is host-readable
but `denyRead` in-sandbox → `rev-parse` fails → the agent reasons over the prompt and
self-stops, emitting **no server-side event** (the self-stop is prompt-driven). The
server-side readiness gates approximate that signal with `lstat` only; the
approximation disagrees with the agent's real signal on 754ee124's shape, so the
strand both (a) survives the heal and (b) leaves no queryable trace.

The exact on-disk `.git` shape at `/workspaces/754ee124…` is **the one thing not
remotely observable** (because the observability is blind). Therefore the fix MUST
be robust to every realization and MUST un-blind the observability on all three
paths so the next strand surfaces the shape.

## Research Reconciliation — brief framing vs. codebase reality

| Brief / issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Gate the dispatch self-heal on git rev-parse — NOT lstat `isValidGitWorkTree`" | All 3 gates already use the lstat verdict `isReadyGitWorkTree`, which on main ALREADY heals escaping pointers + dir-invalid (`:183`); only a corrupt `dir-valid` slips through. `probeGitWorktreeShape`/`isStrandingFilePointer`/`reportAgentReadinessSelfStop` already exist on main. | Delta is narrow: add a host `rev-parse` confirm for `dir-valid` shapes only (the one slice lstat can't adjudicate) + the C2 agent-context backstop. |
| "the merged self-stop mirror does NOT fire on the real strand (host-side git rev-parse runs outside bwrap)" | The merged mirror runs NO rev-parse; it fires on `!isReadyGitWorkTree` (lstat), which returns **ready** for 754ee124 → mirror silent. Host-side rev-parse is itself blind to the escaping-pointer strand (host isn't sandboxed). | Two-pronged: host confirm fires the mirror on a confirmed `dir-valid` corruption; the **C2 backstop** fires it from the agent's real in-sandbox context for any shape the host confirm can't see. |
| "clone a SELF-CONTAINED .git into workspacePath before query() constructs; assert ordering structurally" | Cold factory already `await ensureWorkspaceRepoCloned` (`cc-dispatcher.ts:1963`) before `sdkQuery()` (`:2326`); `ensureWorkspaceRepoCloned` unlinks an escaping pointer (`:174`) + clones self-contained (`git clone --depth 1` → `rename(tmp/.git, ws/.git)` sentinel, `:352`). | Part B is largely satisfied. New work: a structural **await-before-query ordering test**; route the rev-parse-invalid case into the heal; preserve the destroy boundary (see CTO trap below). |
| (B) implies "rev-parse failure → reclone fixes it" | For a populated `dir-valid` that fails rev-parse, `ensureWorkspaceRepoCloned` **early-returns `"ok"` at `ensure-workspace-repo.ts:207`** (`isValidGitWorkTree` passes) → it NO-OPS, does not heal. | Make populated-corrupt an explicit **"unhealed-by-design, observed-and-honest-blocked"** row: emit the self-stop + surface `RepoNotReadyError` (no destroy, no spawn). Strand is prevented by NOT spawning, not by destroying un-pushed work. |
| "robust to all H2 realizations (file-pointer, escaping gitdir, invalid HEAD/objects)" | Escaping pointer is ALREADY healed on main (lstat verdict `:183`). A corrupt `dir-valid` passes `isReadyGitWorkTree` as ready (SpecFlow P0-1). `rev-parse --is-inside-work-tree` does NOT validate object integrity (perf P1). | Split by mechanism: on-main lstat heals escaping/dir-invalid; deliverable A's `dir-valid` host confirm catches config/gitdir-indirection corruption; object-store corruption is the out-of-scope residual. **Deliverable C2 (agent-context backstop) guarantees observability for ALL realizations** regardless of which mechanism heals — that is what makes the fix robust to the unconfirmed shape. |

## Proposed Solution — Technical Approach

### Architecture — a host `rev-parse` confirm for `dir-valid` shapes (deliverable A) + an agent-context observability backstop (deliverable C2)

**Deliverable A — the heal gate.** Keep the existing cheap, sync lstat verdict
(`isReadyGitWorkTree`, which on main already routes escaping pointers + dir-invalid
to the heal at all three gates — `git-worktree-validity.ts:183`). For the ONE shape
the lstat verdict greenlights but the agent can still strand on — a **`dir-valid`**
`.git` (HEAD+objects present) that `git` itself cannot resolve as a work tree
(broken `config`/`commondir`/gitdir-indirection) — add an authoritative async
confirm:

```
hostGitRevParseOutcome(workspacePath): "worktree" | "not-a-worktree" | "inconclusive"
  runs: execFileAsync("git", ["-C", workspacePath, "rev-parse", "--is-inside-work-tree"])
  env:  GIT_CEILING_DIRECTORIES=<abs, symlink-resolved parent of workspacePath>,
        GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=/dev/null, GIT_TERMINAL_PROMPT=0
        (NO GIT_INSTALLATION_TOKEN — read-only, no network)
  ~2s timeout + maxBuffer cap + killSignal; stdout "true" → "worktree";
  clean "not a git repository"/exit-128 → "not-a-worktree"; spawn-error/timeout/EACCES → "inconclusive"
```

The net-new readiness rule, applied **only** to `dir-valid` shapes within the
lstat-ready + connected (`repoUrl`) + DB-ready (`repoReadiness.ok`) population:

```
dir-valid + "worktree"        → ready (fast path; common case)
dir-valid + "not-a-worktree"  → NOT ready → emit self-stop + honest-block (no spawn, no destroy)
dir-valid + "inconclusive"    → re-probe ONCE; still inconclusive → FAIL-OPEN: spawn + low-signal breadcrumb
```

- **Why this, not the "union" (arch P2 / perf cheaper-eq #2):** behind the lstat
  pre-filter, `isStrandingFilePointer` is always false (the pre-filter already
  excluded escaping pointers), so the union reduces to `!hostGitRevParse` on
  `dir-valid` shapes. Stating it as a `dir-valid`-only confirm removes a dead arm and
  two overlapping authorities for the pointer shape.
- **Why NOT bwrap-reproduction (CTO Q3):** the only host/in-sandbox divergence is the
  escaping pointer — already handled structurally on main. Host `rev-parse` cannot
  reproduce the sandbox `denyRead` (perf/arch P2), so it is honestly **blind to the
  escaping-pointer strand**; its net-new coverage is exactly the corrupt-`dir-valid`
  slice. Reproducing the bwrap mount adds cost + a silent-drift coupling to
  `agent-runner-sandbox-config.ts` for zero extra coverage.
- **`rev-parse` does NOT validate object integrity (perf P1):** a `dir-valid` whose
  `objects` are pruned / `HEAD` dangles still returns `"worktree"`. That object-store
  corruption is the documented out-of-scope residual — NOT a rev-parse strand. This
  fix does not claim to catch it; **deliverable C2 is what surfaces it.**
- **Fail-OPEN on inconclusive (arch P0):** a transient probe failure must never
  honest-block a healthy `dir-valid` repo — that manufactures the exact #5733 strand.
  Inconclusive → spawn; the agent's own Step 0.0 + C2 catch a genuine strand.

**Deliverable C2 — the agent-context observability backstop (the brief's literal
"read in the agent's OWN bwrap context").** Because host `rev-parse` is blind to the
escaping pointer AND to object-store corruption, the host-side pre-heal emit alone
can leave a strand dark for shapes it can't see (arch/perf P1). The guaranteed signal
is the agent's **own** in-sandbox `/soleur:go` Step 0.0 `git rev-parse
--is-inside-work-tree` outcome. Hook the existing agent-Bash tool-use mirror path
(the one that already emits "Unknown Bash verb" — `tool-labels.ts:198`, fired live at
15:18 UTC per the issue) so that when the agent's in-sandbox rev-parse reports
not-a-work-tree, a `reportAgentReadinessSelfStop` fires from the agent's real context,
carrying `gitKind` from a host-side `probeGitWorktreeShape` for enrichment. This fires
on the real strand regardless of on-disk shape — it is the backstop that lets us ship
without pre-confirming 754ee124's (unobservable) shape. Phase 0 locates the exact
onToolUse/Bash-result emit site.

### Shared gate helper (deliverables A + C, arch/data/simplicity P1)

Extract one helper so the emit + heal-route + re-probe + honest-block decision is
**structural, not re-specified per gate** (the cold-only emit + warm/reconcile drift
is the 26×-dark incident):

```
evaluateAgentReadiness(workspacePath, ctx): "ready" | "block"
  // ctx: { connected, dbReady } — caller already holds these
  // owns: the dir-valid host rev-parse confirm, the inconclusive re-probe + fail-open,
  //       the reportAgentReadinessSelfStop emit on "not-a-worktree", and returning
  //       "block" so the caller surfaces RepoNotReadyError instead of spawning.
```

Each of the three gates calls it after its existing lstat-gated heal; the
async `dir-valid` confirm CANNOT replace the **sync** `gitDirValid` seam
(`cc-dispatcher.ts:1886`) in place (data P2) — it is an additional re-probe of
`agentReady` AFTER `resolveRepoReadinessWithSelfHeal` returns `healed.ok=true`,
throwing `RepoNotReadyError` despite `healed.ok` for a confirmed-corrupt `dir-valid`.

### Heal / observe decision matrix (applied at ALL THREE gates via the shared helper)

Escaping pointers + dir-invalid + empty-corrupt are **already** routed to the heal by
the on-main lstat verdict (`isReadyGitWorkTree`) — unchanged. The rows below are the
net-new behavior for the lstat-ready + connected + DB-ready population:

| Shape / probe outcome | Heal action | Self-stop emit | Spawn? |
|---|---|---|---|
| `dir-valid` + `"worktree"` | none (fast path; common case) | no | yes |
| **`dir-valid` + `"not-a-worktree"`** (config/gitdir-indirection corruption) | **NONE — `ensureWorkspaceRepoCloned` no-ops at `:207`** | **YES** (`gitRevParseValid=false`, `gitKind=dir-valid`) | **NO — honest-block `RepoNotReadyError`, never destroy** |
| `dir-valid` + `"inconclusive"` (×2: re-probe still inconclusive) | none | low-signal `probe-inconclusive` breadcrumb (NOT the self-stop) | **YES — FAIL-OPEN** (don't block a healthy repo on a blip) |
| escaping/dir-invalid/empty-corrupt (on-main path) | existing `ensureWorkspaceRepoCloned` (`:174`/`:236`) | (cold pre-heal emit, unchanged) | iff re-clone succeeds |
| **agent's in-sandbox Step 0.0 rev-parse fails (C2 backstop, ANY shape)** | n/a (already spawned) | **YES** (`gitKind` enrichment) | already spawned — surfaces the strand |

The destroy authorizations stay exactly the two `.git`-targeting `rm`s that exist
today (`ensure-workspace-repo.ts:174` pointer FILE, `:236` empty-corrupt) — **this PR
adds no third** (`hr-write-boundary-sentinel-sweep-all-write-sites`). A populated
`dir-valid` satisfies *neither* destroy fingerprint, so it can only hit the `:207`
no-op or the `:215` honest-block — never an `rm` (data-integrity P0 verdict: invariant
structurally preserved). Note `:354` is a tmp-clone cleanup, not a `.git` site.

### Un-blinding the two dark gates (SpecFlow P0-2, P0-3; via the shared helper)

- **WARM** (`cc-reprovision.ts reprovisionWorkspaceOnDispatch`): currently returns
  `"ok"` on a benign `ensureWorkspaceRepoCloned` skip without healing, then the
  caller spawns regardless. Change: call `evaluateAgentReadiness`; a confirmed
  `"not-a-worktree"` returns a `"failed"`-class outcome (honest reclaim message, no
  spawn) and fires the self-stop. **No memoization** (perf/data/simplicity P1): a
  positive memo invalidated only on lstat-shape-change would serve a stale `ready`
  after a concurrent reconcile/pull corrupts a `dir-valid` below lstat granularity,
  re-darkening the warm path. The probe is a single ~2s-timeout, `dir-valid`-gated
  call per warm turn on a connected workspace — acceptable (the turn does an agent
  round-trip regardless). Warm intentionally bypasses the DB `claim_repo_clone_lock`
  (pre-existing; convergent via the unique-tmp + `isValidGitWorkTree` sentinel) — the
  new re-probe may observe a cold clone mid-flight and fail-OPEN spawn; acceptable.
- **RECONCILE** (`workspace-reconcile-on-push.ts`): two edits, BOTH load-bearing —
  (1) the benign-skip branch (`:384-398`) writes only a `kb_sync_history` row, no
  Sentry mirror (the exact dark surface of the 26×-fire incident); (2) **`:368`
  `recovered = outcome === "ok" && isReadyGitWorkTree(...)` must also swap to
  `agentReady`** (data P1) — else a populated-corrupt `dir-valid` reads `recovered=true`,
  takes the recovered branch (`:404`), and the self-stop never fires on reconcile.

Because the emit + heal-route lives in the **one shared helper**, "consistent across
all three gates" is structural, not hand-reviewed — directly answering the wrong-layer
learning.

### Observability event change (#5733 deliverable C)

`reportAgentReadinessSelfStop` (`repo-resolver-divergence.ts:128`) already
pseudonymizes (userId→`userIdHash` at the boundary, `activeWorkspaceIdHash`
pre-hashed, **no `installationId`/`repoUrl`/raw `gitdirTarget`**) — the privacy bar
is already met. Changes:

- **Add `gitRevParseValid: boolean`** (the host-confirm verdict) to the args +
  `extra`. Keep `gitValid` (lstat) — when the two diverge (`gitValid=true,
  gitRevParseValid=false`), the event itself shows the proxy-vs-invariant trap shape.
- **SECURITY (security P1, sharpest): never put the probe's `stderr` /
  `error.message` into `extra` or any `reportSilentFallback`.** git's failure text
  embeds the raw absolute path (`fatal: not a git repository: /workspaces/<id>/.git`);
  for a solo workspace `id == raw userId`, so leaking it defeats the deliberate
  boundary-rename pseudonymization (`repo-resolver-divergence.ts:121`). Only the
  structured booleans + `gitKind` are emitted.
- Type-widening of the args object → cross-consumer grep
  (`hr-type-widening-cross-consumer-grep`): consumers are `cc-dispatcher.ts:1823`
  (cold emit) + `test/server/repo-resolver-divergence.test.ts`; new emit sites are the
  shared helper (reached from warm + reconcile) and the C2 agent-context hook.
- Fingerprint stays `(op,userId,activeWorkspaceId,gitKind)` — acceptable (the emit
  fires only on a confirmed `"not-a-worktree"` or the C2 in-sandbox failure, so a
  `dir-valid` in the fingerprint always means "dir-valid that rev-parse-failed").
- **C2 backstop emit** reuses the same `reportAgentReadinessSelfStop` (a distinct
  `gitKind`/source tag distinguishes the in-sandbox backstop from the host pre-heal
  emit), so a strand of ANY shape — including the object-store residual the host
  confirm is blind to — produces a queryable event.

## Implementation Phases (failing tests FIRST — `cq-write-failing-tests-before`)

### Phase 0 — GATING shape confirmation + preconditions (no code)
- **Confirm 754ee124's actual on-disk `.git` shape FIRST (arch/data P1 — gates the
  whole design).** Read-only probe the live workspace path (`probeGitWorktreeShape`
  + a host `rev-parse`) if reachable from the work environment. Branch:
  - corrupt-`dir-valid` (`"not-a-worktree"`) → deliverable A's host confirm is the
    right heal gate; proceed.
  - object-store residual (rev-parse passes both sides) → A cannot heal it; the
    durable value is C2 (observability) + a follow-up for the residual; do NOT bill
    the ADR-044 perf reversal as fixing this shape.
  - escaping pointer (would contradict on-main already-heals) → fix escape detection.
  - **If the live workspace is NOT reachable** from the work env: proceed building
    A + C2 — C2 makes the plan robust to all shapes (it fires on the agent's real
    strand regardless), and AC11 confirms the shape post-merge.
- Verify `git rev-parse --is-inside-work-tree` exit semantics + that
  `GIT_CEILING_DIRECTORIES=<abs symlink-resolved parent>` prevents ascension, with
  throwaway fixtures incl. a **symlinked** `/workspaces` path component (arch P2). Pin
  output in Research Insights.
- Read the hardened git-spawn precedent (`git-auth.ts:283-309`) to mirror its
  `execFileAsync` + env block. Read the agent-Bash tool-use mirror site that emits
  "Unknown Bash verb" (`tool-labels.ts:198` + its onToolUse emit) to locate the C2
  hook. Read the existing sync `gitDirValid` seam (`cc-dispatcher.ts:1886`).
- Grep `rm(` in `ensure-workspace-repo.ts`: confirm exactly two `.git`-targeting
  destroy sites (`:174`, `:236`); `:354` is tmp-clone cleanup (exclude).

### Phase 1 — Probe + shared helper + failing tests (RED)
- Add `hostGitRevParseOutcome(workspacePath): Promise<"worktree"|"not-a-worktree"|"inconclusive">`
  to `git-worktree-validity.ts` — `execFileAsync("git",[array])`, hardened env (NO
  install token), `~2s` timeout + `maxBuffer` + `killSignal`. Standalone-testable
  (security/simplicity).
- Add `evaluateAgentReadiness(workspacePath, ctx): Promise<"ready"|"block">` — owns
  the `dir-valid` confirm, the inconclusive re-probe + fail-OPEN, and the
  `reportAgentReadinessSelfStop` emit on `"not-a-worktree"`.
- RED tests in `test/server/` (`test/**/*.test.ts`): dir-valid+worktree → ready;
  dir-valid+not-a-worktree → block + emit; dir-valid+inconclusive(×2) → ready
  (fail-open) + breadcrumb (no self-stop); ceiling no-ascension incl. symlinked
  parent; env asserts no install token; no stderr/path in `extra`.

### Phase 2 — Cold gate (cc-dispatcher) GREEN
- Call `evaluateAgentReadiness` after the existing lstat-gated self-heal; on `"block"`
  surface `RepoNotReadyError` (re-probe AFTER `resolveRepoReadinessWithSelfHeal`
  returns `healed.ok=true`; do NOT replace the sync `gitDirValid` seam in place).
- Update the now-stale load-bearing comment at `:1802-1806` ("adds no subprocess")
  (arch P1).

### Phase 3 — Warm gate (cc-reprovision) GREEN
- Call `evaluateAgentReadiness`; `"block"` → `"failed"` outcome (no spawn). **No memo.**

### Phase 4 — Reconcile gate (workspace-reconcile-on-push) GREEN
- Swap `:357` gate AND `:368` `recovered` re-probe to the helper's verdict; emit on
  the unrecovered/benign-skip branch. Assert **one `rev-parse` spawn per event** (the
  handler evaluates a single workspace) (perf P2).

### Phase 5 — C2 agent-context backstop + event widening + ADR-044
- Wire the C2 emit at the agent-Bash mirror site (Phase 0-located) on an in-sandbox
  `rev-parse` not-a-worktree result.
- Widen `reportAgentReadinessSelfStop` with `gitRevParseValid`; update all emit sites
  + tests (no stderr/path leak).
- Amend ADR-044 (see Architecture Decision section) — **supersede** AC7's zero-await
  guarantee for the connected cold path; do not claim "retained."

### Phase 6 — Typecheck + full runner
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run` (the package's real runner;
  do NOT use `npm run -w` — the repo root declares no `workspaces`).

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| **Predicate-swap only** (`isReadyGitWorkTree` → richer lstat) without a real rev-parse | SpecFlow P0-1: still shape-specific; misses corrupt `dir-valid`. If 754ee124 is corrupt-dir not escaping-pointer, the fix lands and still strands. |
| **bwrap-reproducing probe** (run rev-parse under a hand-rolled `denyRead` mount) | CTO Q3: the only divergence (escaping pointer) is already caught by `isStrandingFilePointer`; reproduction adds the expensive namespace setup + a silent-drift coupling to `agent-runner-sandbox-config.ts` for zero extra coverage. |
| **Widen destroy to "rev-parse-invalid + has origin → reclone"** | CTO Q1: origin is canonical for the *base*, not the working tree; a populated `.git` may hold the only copy of un-pushed prior-turn work. Loses the brand-survival invariant. |
| **Unconditional rev-parse on every dispatch** | Scoped to `dir-valid` shapes in the lstat-ready + connected + DB-ready population — repo-less / lstat-not-ready / pointer / cloning paths keep the cheap sync routing. (Warm memoization was considered and DROPPED — perf/data P1: a stale positive memo masks sub-lstat corruption and re-darkens the warm path.) |

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's own Concierge
  (`/soleur:go` on workspace 754ee124…) keeps dead-ending on *"No Git Repository in
  Workspace" / "not a git repository"* with no recovery and no queryable signal — the
  product's primary surface is unusable for the affected user.
- **If this leaks, the user's workflow/data is exposed via:** the new self-stop event
  carries only `userIdHash` + `activeWorkspaceIdHash` + booleans/`gitKind` — **no**
  `installationId`/`repoUrl`/raw path/`gitdirTarget`. A regression that emitted raw
  identifiers would expose workspace↔repo linkage in Sentry. The destroy boundary is
  the other exposure vector: a false-heal that `rm`s a populated `.git` would destroy
  un-pushed work.
- **Brand-survival threshold:** `single-user incident` (one operator's primary surface
  is already down). → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at
  review-time (enumerate the un-pushed-work-loss mode + the raw-identifier-leak mode).

## Observability

```yaml
liveness_signal:
  what:            "Sentry event `agent_readiness_self_stop` (own issue group), emitted by all 3 dispatch gates when agentReady=false on a connected+ready workspace"
  cadence:         per-dispatch (deduped per (op,userId,workspace,gitKind) per process)
  alert_target:    "Sentry issue (query-only / discoverability — no page, by design; auto-heals or honest-blocks same dispatch)"
  configured_in:   "apps/web-platform/server/repo-resolver-divergence.ts:128 (emit); cc-dispatcher.ts (cold), cc-reprovision.ts (warm), inngest/functions/workspace-reconcile-on-push.ts (reconcile)"
error_reporting:
  destination:     "Sentry web-platform (EU) via reportSilentFallback → captureException; SENTRY_DSN"
  fail_loud:       "agent_readiness_self_stop event with gitRevParseValid=false + gitKind names the strand shape; honest-block surfaces RepoNotReadyError to the user"
failure_modes:
  - mode:          "agent dispatched into a rev-parse-invalid worktree (the strand)"
    detection:     "agent_readiness_self_stop event count > 0 for the workspace (Sentry query, all 3 gates)"
    alert_route:   "operator Sentry triage (query-only; not paged — self-heals/honest-blocks)"
  - mode:          "false-heal destroys a populated .git"
    detection:     "no third rm authorization (asserted by write-boundary test); isEmptyCorruptGitDir/isStrandingFilePointer remain the only two"
    alert_route:   "CI test failure on the destroy-boundary assertion"
  - mode:          "probe subprocess error/timeout (inconclusive)"
    detection:     "re-probe once → FAIL-OPEN spawn + low-signal probe-inconclusive breadcrumb; the C2 in-sandbox backstop still fires if the open spawn really strands"
    alert_route:   "Sentry probe-inconclusive breadcrumb + agent_readiness_self_stop (C2 backstop)"
  - mode:          "object-store residual (rev-parse passes both sides, agent strands on object access)"
    detection:     "C2 agent-context backstop fires from the agent's in-sandbox failure (host confirm is blind to this shape)"
    alert_route:   "Sentry agent_readiness_self_stop (C2 source tag)"
logs:
  where:           "Sentry (events) + pino logger.error line via reportSilentFallback; Docker container stdout"
  retention:       "Sentry project retention (90d)"
discoverability_test:
  command:         "curl -s -H \"Authorization: Bearer $SENTRY_TOKEN\" \"https://sentry.io/api/0/projects/<org>/web-platform/events/?query=message:agent_readiness_self_stop\" | jq 'length'"
  expected_output: "0 in steady state; >0 after a strand on ANY of the 3 gates — the signal that was previously dark"
  tag_queries:     "`source` and `gitKind` are emitted as SEARCHABLE Sentry tags (promoted via reportSilentFallback `tags`, not just `extra`), so `source:in-sandbox-backstop` and `gitKind:dir-valid` narrow the query directly; `gitRevParseValid` is a stringified-boolean tag too (extra is NOT searchable)"
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-044** (`knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`,
status `accepted`) with a new **Amendment 2026-06-30 — dispatch readiness adds a host
`rev-parse` confirm for `dir-valid` worktrees, superseding the lstat-proxy trade-off
for the connected case.** This is an in-scope plan deliverable
(`wg-architecture-decision-is-a-plan-deliverable`) — it reverses the 2026-06-19
amendment's explicit "deliberately WEAKER than `git rev-parse` … cheap enough to keep
the AC7 zero-await hot path" decision. The amendment must record: it **supersedes**
the 2026-06-19 zero-await guarantee for the connected cold path (arch P1 — do NOT
claim the fast path is "retained"; an async `dir-valid` confirm now runs on the common
healthy connected cold dispatch); the confirm fires **only** for `dir-valid` shapes in
the lstat-ready + connected + DB-ready population; the subprocess's net-new coverage is
honestly the corrupt-`dir-valid` slice ONLY (blind to the escaping pointer, which the
lstat verdict already heals, and to object-store corruption, the residual); destroy
authorizations **unchanged**; and add the `dir-valid`-only confirm to
`## Alternatives Considered` against the rejected bwrap-reproduction.
Author via the `architecture` skill / Edit (Concierge and the plugin terminal are
equally-trusted agent contexts that edit ADR files on the filesystem and commit).

### C4 views
**No C4 impact.** Read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`).
Enumerated against this change: external human actors — none added (the operator is
the existing `founder` actor, multi-Owner per ADR-038); external systems/vendors —
none added (no new webhook/API/store); containers/data-stores — none (logic stays in
the existing `api` and `claude` containers); access relationships — unchanged. The
fix tightens the **pre-condition on the existing `api -> claude "Spawns agent
sessions"` edge** (`model.c4:249`), not the topology — consistent with ADR-044's own
prior no-C4-impact amendments (2026-06-17b, 2026-06-18). No `.c4` edit; no element
description is falsified.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Verified against the code. (Q1 destroy-boundary — HIGH: do NOT widen
`rm`; heal only provably-safe shapes, emit-and-honest-block the populated-corrupt dir;
flagged the `ensure-workspace-repo.ts:207` no-op trap that makes (B) observability,
not auto-heal, for that shape.) (Q2 hot-path — MEDIUM: acceptable when scoped to
`dir-valid` shapes; **deepen-review DROPPED the warm memoization** the CTO floated —
perf/data P1 staleness risk.) (Q3 mechanism — MEDIUM: `GIT_CEILING_DIRECTORIES`; drop
bwrap-reproduction. **Deepen-review further collapsed the "union" to a `dir-valid`-only
host confirm** — behind the lstat pre-filter the `isStrandingFilePointer` arm is dead,
arch P2.) Flags folded into the plan: ADR-044 amendment is a
deliverable; write-boundary sweep asserts no third `rm`; probe must be an injected
seam (unit-testable); `user-impact-reviewer` + `observability-coverage-reviewer` apply
at review-time. Known residual (out of scope for #5733): a `dir-valid` `.git` with
`objects/info/alternates` pointing under `/workspaces` passes rev-parse both sides but
strands later on object access — not a rev-parse strand.

### Product/UX Gate
Not relevant — no UI surface. All edits under `apps/web-platform/server/`; no
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`. The mechanical UI-surface
override did not fire. Tier: NONE.

### GDPR / Compliance (Phase 2.7)
Considered. No regulated-data surface (no schema/migration/auth/API-route/`.sql`).
Trigger (b) fires (single-user-incident threshold), but the change is
privacy-**preserving**: the self-stop event already pseudonymizes and the new field
(`gitRevParseValid`) is a non-PII boolean; **no `installationId`/`repoUrl`/raw path**
is emitted. Constraint carried into ACs: the new field must NOT defeat the
boundary-rename (no raw identifiers). Full `/soleur:gdpr-gate` invocation not required
(no new PII surface).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** `hostGitRevParseOutcome` returns `"worktree"` for a healthy clone,
      `"not-a-worktree"` for a `dir-valid` whose `.git` git cannot resolve,
      `"inconclusive"` on spawn-error/timeout — RED tests first. Uses
      `execFileAsync("git",[array])` (no shell string), `~2s` timeout + `maxBuffer` +
      `killSignal`, and env `GIT_CONFIG_NOSYSTEM=1` / `GIT_CONFIG_GLOBAL=/dev/null` /
      `GIT_TERMINAL_PROMPT=0` with **no installation token** (assert the env).
- [ ] **AC2** `GIT_CEILING_DIRECTORIES=<abs, symlink-resolved parent>`; tests prove no
      false-pass via parent-`.git` ascension AND via a **symlinked** `/workspaces` path
      component.
- [ ] **AC3** The `dir-valid` host confirm runs only in the lstat-ready + connected
      (`repoUrl`) + DB-ready population; a `"not-a-worktree"` routes to honest-block, an
      `"inconclusive"` (after one re-probe) FAILS-OPEN to spawn (a healthy repo is
      never blocked by a probe blip).
- [ ] **AC4** A single shared `evaluateAgentReadiness` helper owns the emit + heal-route
      + re-probe for all three gates (no per-gate duplication); a test asserts cold,
      warm, and reconcile all reach it.
- [ ] **AC5** `reportAgentReadinessSelfStop` fires on a confirmed `"not-a-worktree"`
      from all three gates (incl. reconcile after the `:368` `recovered` swap) AND from
      the C2 in-sandbox backstop, carrying `gitRevParseValid` + `gitValid` + `gitKind`
      + `activeWorkspaceIdHash` — and **no** `installationId`/`repoUrl`/raw path/
      `gitdirTarget`/**subprocess stderr** (assert the `extra` keys + that no git error
      string is captured).
- [ ] **AC6** Populated `dir-valid` + `"not-a-worktree"` → emit + `RepoNotReadyError`
      honest-block; **no destroy**. Write-boundary test asserts exactly two
      `.git`-targeting `rm` sites remain (`ensure-workspace-repo.ts:174`, `:236`); the
      assertion is scoped to `.git` paths so the `:354` tmp-clone `rm` is excluded; no
      third `.git` authorization added.
- [ ] **AC7** C2 backstop: an in-sandbox Step 0.0 `rev-parse` not-a-worktree result
      emits the self-stop (distinct source tag) regardless of on-disk shape — so the
      object-store residual the host confirm is blind to is still queryable.
- [ ] **AC8** Reconcile asserts **one** `rev-parse` spawn per event (single workspace
      per invocation).
- [ ] **AC9** ADR-044 Amendment 2026-06-30 written — **supersedes** AC7's zero-await
      guarantee for the connected cold path (does NOT claim "retained"); destroy
      authorizations unchanged; the `dir-valid`-only confirm + the rejected
      bwrap-reproduction in Alternatives; the stale `:1802-1806` comment updated.
- [ ] **AC10** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes;
      `./node_modules/.bin/vitest run` green (the real runner — not `npm run -w`).

### Post-merge (operator / automatable)
- [ ] **AC11** Confirm 754ee124's **actual on-disk `.git` shape** on the live prod
      surface (the Phase-0 attempt may have been unreachable from the work env) —
      corrupt-`dir-valid` vs. object-store residual vs. pointer — so a green dispatch
      isn't a false-green and so the ADR-044 perf reversal is attributed to a real
      shape (SpecFlow P0-4 / arch P1). Read-only shape probe.
- [ ] **AC12** Exercise the path the live strand actually traverses — per the prior
      incident, **RECONCILE / WARM**, not only a fresh COLD `/soleur:go` — and confirm
      no strand + an `agent_readiness_self_stop` event is queryable (host pre-heal emit
      OR the C2 backstop), or absent because healed. Ref #5733; `gh issue close 5733`
      after the operator-surface repro, not at merge.

## Test Scenarios

- Given an escaping gitdir `file-pointer` at the workspace root, when any of the 3
  gates evaluates readiness, then `agentReady=false` → heal (unlink+reclone) →
  self-stop emitted → re-probe ready → agent spawns into a healthy repo.
- Given a populated `dir-valid` `.git` that fails host `rev-parse`, when the cold gate
  evaluates, then self-stop emitted with `gitValid=true,gitRevParseValid=false` (the
  divergence) → honest-block `RepoNotReadyError` → **no spawn, no destroy**.
- Given a WARM dispatch whose `ensureWorkspaceRepoCloned` benign-skips without healing,
  when reprovision returns, then it re-probes, returns the honest "failed" outcome, and
  does not spawn (regression for SpecFlow P0-2).
- Given a RECONCILE benign-skip (repoUrl fails the allowlist) that did not heal, when
  the handler returns, then `agent_readiness_self_stop` is queryable (regression for
  P0-3 / the 26×-dark-fire incident).
- Given a healthy `dir-valid` clone, when a gate evaluates, then one bounded ~2s
  `rev-parse` returns `"worktree"` and the agent spawns (no memo; the agent round-trip
  dominates the probe cost). Given a probe timeout/spawn-error on that healthy repo,
  then it re-probes once and FAILS-OPEN to spawn (never honest-blocks a healthy repo).
- Given a repo-less Start-Fresh workspace (`git init`, no `repoUrl`, no origin), when
  the cold gate evaluates an absent or `dir-valid` `.git`, then it benign-skips / fast-
  paths and never destroys un-pushed init state (P2 edge).

## Open Code-Review Overlap

3 open code-review issues touch the edited files:
- **#3243** (`arch: decompose cc-dispatcher.ts into focused modules`) — **Acknowledge**:
  a structural refactor, different concern; this PR makes minimal in-place edits to the
  three gate blocks, not a decomposition. Remains open.
- **#3739** (`extract reportSilentFallbackWithUser helper — collapse 11-site duplication`)
  — **Acknowledge**: the new emit sites should follow the *existing*
  `reportAgentReadinessSelfStop` wrapper (which already routes through
  `reportSilentFallback`), so they do not add raw `withIsolationScope+setUser`
  duplication. Remains open.
- **#3242** (`tool_use WS event lacks raw name field`) — unrelated; no action.

**Merge-ordering note (#5783 docstring drift):** sibling open PR #5783 adds a +7-line
op-inventory docstring to `observability.ts` (multi-owner reconcile ops) and carries
`2026-06-30-sentry-op-inventory-docstring-drifts-when-sibling-op-added.md`. This PR's
self-stop emit lives in `repo-resolver-divergence.ts` (NOT `observability.ts`) and the
`agent-readiness-self-stop` op slug already exists — so this PR **should not edit
`observability.ts`'s inventory**, avoiding the drift. If review insists on inventorying
the op there, rebase after #5783 merges.

## Risks & Sharp Edges

- **Fail-OPEN on inconclusive, NOT fail-closed (arch P0 / data+perf P1):** a transient
  probe timeout/spawn-error on a healthy `dir-valid` repo must spawn (after one
  re-probe), never honest-block — fail-closed-to-heal manufactures the exact #5733
  strand on a working repo. Only a deterministic `"not-a-worktree"` blocks. Encoded in
  AC3.
- **Host `rev-parse` is blind to the original (sandbox-only) strand (arch/perf P2):**
  an escaping pointer is host-readable, so host `rev-parse` returns `"worktree"` for
  it — the escaping-pointer case is healed by the on-main lstat verdict + structural
  `isStrandingFilePointer`, NOT by this subprocess. The subprocess's only net-new
  coverage is the corrupt-`dir-valid` slice. Stated honestly in the ADR.
- **`rev-parse --is-inside-work-tree` does NOT validate object integrity (perf P1):**
  object-store corruption (HEAD→missing objects, broken alternates) passes it. That is
  the out-of-scope residual; **C2 (agent-context backstop) is the only thing that
  surfaces it** — which is why C2 is in-scope, not deferred.
- **754ee124's shape is unconfirmed and may be the residual (arch/data P1):** if the
  live workspace is corrupt-`dir-valid`, deliverable A heals it; if it is the
  object-store residual, A does NOT, and only C2 + AC11/AC12 close it. The plan ships
  robust to both because C2 fires on the agent's real strand regardless of shape.
- **The stderr-path leak (security P1, sharpest):** the new probe-error path must not
  copy git's stderr into the Sentry `extra` — it embeds the raw absolute path (= raw
  userId for a solo workspace), defeating the deliberate pseudonymization. Encoded in
  AC5.
- **AC6 write-boundary grep miscounts if unscoped (data P2):** `ensure-workspace-repo.ts`
  has THREE `rm(` calls — `:174` + `:236` (.git) + `:354` (tmp clean). Scope the
  assertion to `.git`-targeting paths.
- **Honest-block is a NEW branch, not a verdict swap (data P2):** the async confirm
  re-probes AFTER `resolveRepoReadinessWithSelfHeal` returns `healed.ok=true` and
  throws `RepoNotReadyError` despite it — the sync `gitDirValid` seam (`:1886`) stays
  unchanged.
- **The `ensure-workspace-repo.ts:207` no-op trap (CTO):** routing a populated-corrupt
  `dir-valid` into `ensureWorkspaceRepoCloned` does NOT heal it (early-returns `"ok"`).
  Anyone reading deliverable B as "rev-parse failure → reclone fixes it" is wrong for
  this shape — its value is observability + honest-block, not auto-heal. Encoded in AC6.
- **`GIT_CEILING_DIRECTORIES` is load-bearing:** without it host `git` ascends to a
  parent `.git` and false-passes, leaving the strand dark. Encoded in AC2.
- **Wrong-layer trap:** prior fixes landed at a gate the affected surface never
  traversed (zero `cc-dispatcher` events; reconcile fired 26×). This PR fires the
  self-stop from all three gates *and* AC11 exercises the live-traversed path — do not
  declare close on a COLD-only repro.
- **Type-widening sweep:** adding `gitRevParseValid` must update every consumer
  (`hr-type-widening-cross-consumer-grep`).
- **Known residual (out of scope):** `objects/info/alternates` under `/workspaces`
  passes rev-parse both sides but strands on object access — note it so #5733 isn't
  assumed to close it.
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan`
  Phase 4.6 — this one is filled (threshold `single-user incident`).

## Files to Edit

- `apps/web-platform/server/git-worktree-validity.ts` — add `hostGitRevParseOutcome`
  (execFile array, ceiling, hardened env, ~2s timeout, no token) + the shared
  `evaluateAgentReadiness(workspacePath, ctx)` helper.
- `apps/web-platform/server/cc-dispatcher.ts` — cold gate: call `evaluateAgentReadiness`
  after the existing self-heal (`:1807-1838`); honest-block `RepoNotReadyError` on a
  confirmed `dir-valid` corruption; update the stale `:1802-1806` comment. C2 hook at
  the agent-Bash onToolUse mirror (Phase-0-located near `tool-labels.ts:198`).
- `apps/web-platform/server/cc-reprovision.ts` — warm gate (`:123`): call the helper;
  honest "failed" on block; **no memoization**.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` —
  reconcile gate `:357` **AND** the `:368` `recovered` re-probe → helper verdict;
  self-stop on unrecovered/benign-skip (`:384-398`).
- `apps/web-platform/server/repo-resolver-divergence.ts` — widen
  `reportAgentReadinessSelfStop` with `gitRevParseValid` (`:128-162`); ensure no
  subprocess stderr/path can enter `extra`.
- `apps/web-platform/server/tool-labels.ts` (or its onToolUse emit site) — C2 backstop
  emit on in-sandbox Step 0.0 rev-parse failure (exact site Phase-0-located).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`
  — Amendment 2026-06-30 (supersede AC7 zero-await for connected cold).

## Files to Create (tests)

- `apps/web-platform/test/server/agent-ready-git-worktree.test.ts` — `hostGitRevParseOutcome`
  + `evaluateAgentReadiness` unit tests (dir-valid worktree/not-a-worktree/inconclusive,
  ceiling incl. symlinked parent, hardened env / no token, fail-OPEN, no stderr leak).
- Extend `apps/web-platform/test/cc-dispatcher-self-heal-observability.test.ts` +
  `apps/web-platform/test/helpers/cc-dispatcher-harness.ts` — three-gate emit/heal/honest-block
  + await-before-query ordering, via the injected seam.

## References

- Issue: Ref #5733. Prior fix commit: `190ab58a5` (#5734). Sibling: #5783.
- ADR-044 (`:715` 2026-06-19 amendment — the lstat-proxy trade-off this reverses).
- Sandbox SoT: `apps/web-platform/server/agent-runner-sandbox-config.ts:94`.
- Learnings: `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`,
  `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`,
  `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`.
- Review-time agents (single-user threshold): `user-impact-reviewer`,
  `observability-coverage-reviewer`.
