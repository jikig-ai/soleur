---
title: Layer 1 deterministic constraint gates for product code
status: accepted
date: 2026-06-30
---

# ADR-071: Layer 1 deterministic constraint gates for product code

## Context

Soleur has rich deterministic Layer-1 enforcement for its **meta-workflow** (PreToolUse
hooks — `guardrails.sh`, `brand-hex-commit-gate.sh`, `git-commit-secret-scan.sh`, the
change-class classifier) but **no deterministic constraint on the shape of product code**
the agent writes for the founder's SaaS. Every structural check (import/layer boundaries)
is currently LLM-judged in `soleur:review` (`architecture-strategist`,
`pattern-recognition-specialist`) — i.e. ADR-011 tier 2/3, not tier 1. That is
probabilistic, token-costly, and the wrong tier for a mechanical invariant.

The target user is a non-technical founder who can never hand-author or unblock such a
gate, so Soleur must *generate* it. `dependency-cruiser` and any fitness-function
infrastructure are absent from the repo (#3132 / #3133 unbuilt). The brand-survival vector
(threshold: single-user incident) is a `"use client"` module taking a **value** import on a
server-secret module — shipping a server secret into the browser bundle.

## Decision

The `constraint-scaffold` skill generates a deterministic, no-LLM **import-boundary gate**
into the product codebase (`apps/web-platform` first). It runs in CI, fails closed, and
rejects the violation **before** the LLM-judged review layer — the product-code
instantiation of ADR-011 tier 1.

**The agent — never the founder — owns gate maintenance, baseline refresh, and recovery.**
Founder-hotfix recovery is **automatic and zero-touch** via the two-stage auto-recovery
dispatcher (`fix-constraints-stage-a` → `fix-constraints-stage-b`, **ADR-074**): a tripped
gate on a PR triggers a fix-only agent run that delivers the fix as a **draft follow-up PR**
— no comment, no command, no head-push. (The held `/soleur fix constraints` comment-dispatcher
that this superseded ran untrusted PR-head code in a privileged `issue_comment` trigger; ADR-074
replaced it with an untrusted producer / privileged non-executing consumer split.) Auto-recovery
is fix-only and never grows the suppression baseline; a real leak it cannot fix is surfaced for a
maintainer (who re-runs `constraint-scaffold` locally: fix the import, or `--refresh-baseline`).
The gate stays **informational / non-blocking** — it is NOT promoted to a required check.
Promotion to a REQUIRED check is now **blocked only on #5778** (monorepo/multi-stack follow-up);
the #5791 "no agent-free recovery for a tripped required gate" blocker is **satisfied by ADR-074**
(auto-recovery is agent-free from the founder's perspective). No override label, no `.cjs` edit,
no second human required.

**Mechanism (Option D).** `dependency-cruiser` is the engine — it robustly owns `@/*`
alias resolution (`tsConfig` + `tsPreCompilationDeps`), the type-only/value erasure, and the
native known-violations baseline (`--output-type baseline` / `--ignore-known`). But
dep-cruiser matches modules by **path** and cannot see the `"use client"` directive (it is a
graph tool, not a directive scanner), and this codebase has no `.client.tsx` convention.
Therefore the `.cjs` config is **executable CommonJS that computes the client-module
`from.path` set at config-require time**: it greps `app/**`+`components/**` for the leading
`"use client"` directive, maps each hit to dep-cruiser's cwd-relative posix module-source
format, and **regex-escapes** each path (route groups like `app/(dashboard)/` carry regex
metacharacters). The `forbidden` rule is then `from: { path: <computed escaped set> }`,
`to: { path: <secret-module set>, dependencyTypesNot: ['type-only'] }`, direct edges only.

The from-set is **recomputed on every run and never committed as a static list** — a stale
list would be blind to a newly-added client file (the exact leak the gate exists to catch).
An empty from-set while `"use client"` files exist is a hard error, not a silently-disabled
rule.

## Alternatives Considered

- **A — bespoke AST-lite checker** (custom script resolving imports itself). Rejected: it
  re-implements TS module resolution (`@/*` + tsconfig `paths` + barrels) and the
  type-only/value distinction — the exact correctness work dep-cruiser already solves, and
  the exact leak modes the brand-survival threshold names. Concentrates the highest-consequence
  correctness risk in untested code.
- **B — `server-only` npm package marker** (build throws if a client module imports a marked
  module). Rejected for v1: not baseline-grandfatherable (all-or-nothing → hard-breaks the
  webpack build on all 10 pre-existing violations at once = the "deploy stranded, no
  engineer-free recovery" outcome the threshold forbids), and a build error bypasses the
  discrete `constraint-gates` check + comment-summon recovery model. Retained as optional
  later defense-in-depth.
- **C — dep-cruiser native `from "use client"` match.** Impossible: dep-cruiser exposes no
  content/directive matcher.

## Consequences

Structural import-boundary violations get deterministic, fail-closed, token-free enforcement
at tier 1 instead of probabilistic LLM review. The agent-owns-gates contract keeps the
fail-closed gate from stranding a non-technical founder. v1 is Next.js-only, single gate
(client→server-secret); the naming gate, contract gate, pre-commit surface, and
multi-stack support are deferred (#5774–#5776, #5778). **Transitive-edge coverage (#5777/NG5)
is now CLOSED** — see §Amendment 2026-07-01. **The scaffold now proves the gate bites on every run
and emits a README plus an agent-instructions pointer (#8288)** — see §Amendment 2026-09-19. The
content-scan adds a small amount of executable logic to the `.cjs` config that must stay correct
(regex escaping, module-source format) — covered by self-tests. Cross-reference: ADR-011 (the three-tier model this instantiates at
tier 1 for product code).

## Amendment 2026-07-01 (#5777) — transitive client→helper→server-secret coverage

The v1 gate matched **direct** edges only, so a `"use client"` module that imports a non-client
helper (e.g. in `lib/`) which value-imports a `server/**` secret still shipped that secret into
the browser bundle undetected (NG5, deferred from #5765). This amendment adds a dependency-cruiser
`reachable` rule to catch `client → helper → … → server-secret` value chains. The original
Context / Decision / Alternatives above are preserved intact — this is an EXTENSION of the v1
decision, not a rewrite.

**Decision (added).** The gate now enforces **transitive** reachability via a second forbidden
rule (`no-client-to-server-secret-transitive`, `to.reachable: true`) alongside the direct rule.
Two load-bearing sub-decisions, both verified against the installed <dependency-cruiser@16.10.x>
source:

- **`options.tsPreCompilationDeps` flipped `true → false`.** dependency-cruiser v16 `reachable`
  rules are schema-locked to `{path, pathNot, reachable}` (`additionalProperties: false`) and
  CANNOT filter `dependencyTypesNot` per-rule, so the ONLY way to stop reachability from following
  a build-time-erased `import type` hop is to elide type-only edges from the graph GLOBALLY. With
  type-only edges gone, the direct rule no longer needs its `dependencyTypesNot:["type-only"]`
  filter — its violation set is **byte-identical** before and after the flip (proven empirically at
  build time). Because a flip regression could only *shrink* the value-edge set (value edges are
  never erased; only type-only edges are), a `boundary.test.sh` assertion floors the direct baseline
  at **≥10** (a legitimate new value-safe direct import may grow it). Both rules therefore ignore
  type-only imports.
- **The reachable baseline is kept EMPTY.** The zero-baseline invariant is enforced by keying on the
  transitive rule NAME, not on `type:"reachability"`: dependency-cruiser softens `reachability`
  violations **per-origin** (`soften-known-violations.mjs` matches on `from` + rule name only,
  ignoring `to`/`via` **and the entry `type`**), so a hand-authored `type:"module"` entry naming the
  transitive rule suppresses it identically to a `type:"reachability"` entry. The runner guard and
  `boundary.test.sh` both reject any baseline entry that is `type:"reachability"` OR names the
  transitive rule (any type), and fail closed on a non-array baseline. So baselining even one
  value-safe transitive path would blind that client to EVERY
  future transitive secret. Instead, the known value-safe server modules are excluded from the
  reachable **target** via `to.pathNot` (never from the `from` set — that would blind the client to
  all secrets), and any real transitive leak is FIXED, never grandfathered. A guard in the shared
  runner AND `boundary.test.sh` fails closed on any committed `type:"reachability"` baseline entry.

**Alternatives Considered (added).** (i) per-rule `dependencyTypesNot` on the reachable rule —
**impossible** (schema-forbidden in v16.10.x); (ii) baselining pre-existing transitive paths —
**rejected** (per-origin suppression = permanent blind spot); (iii) a separate reachable-only
second config with `tsPreCompilationDeps:false` isolated to it — retained as the fallback had the
flip changed the direct-rule set (it did not, so the single-config design shipped).

**Consequences (added).** The `to.pathNot` value-safe allowlist
(`domain-leaders`, `providers`, `team-names-validation`, `scope-grants/action-class-map` — the
4 modules any client reaches today, verified value-safe: no `process.env` value read, no secret
import) is a hand-maintained fail-open: if one later gains a real secret it ships green on both the
direct (baseline-suppressed) and transitive (`pathNot`-excluded) paths. Mitigated by a mandatory
D4 content-invariant drift guard in `boundary.test.sh` (each listed module must read no
`process.env` value / take no value import). The structural fix — relocating the 4 modules out of
`server/**` so the exclusion is enforced by LOCATION — is tracked in #5850 (`SOLEUR-DEBT` marker at
the `VALUE_SAFE_PATH` definition). The gate remains informational/non-blocking; the reachable rule
adds no new CI job (same shared runner, same version pin `^16.10.0`). NG5/#5777 moves from
deferred → closed.

## Amendment 2026-09-19 (#8288) — install-time bite-proof, README and agent-instructions pointer

Until this amendment the scaffold proved that its gate bites only inside Soleur's own hermetic
`test/boundary.test.sh` — never in the founder's repo, where the gate actually runs. A scaffold
run could emit a config whose `@/*` alias did not resolve, a runner that no longer failed on
`rc>0`, or a rule softened to `warn`, and still exit 0 with "gate installed". That is the class
the issue names: an asserted gate, not a proven one. The original Context / Decision /
Alternatives above and the 2026-07-01 amendment are preserved intact — this is an EXTENSION of
the scaffold's contract, not a change to the rule set or to any emitted sentinel.

**Decision (added).** `constraint-scaffold.sh` (`plugins/soleur/skills/constraint-scaffold/scripts/`)
gains a `prove_bite` step at the tail of **both** modes (default install and `--refresh-baseline`),
a README emitted next to the governed path, and one informational pointer line in the repo's
agent-instructions file. Six sub-decisions:

- **The bite is pass → fail → pass, on the committed tree, in a detached-HEAD worktree.**
  `with_detached_worktree <ref> <fn>` is the one helper that owns `mktemp -d`, the
  `worktree add --detach`, the `EXIT`/`INT`/`TERM` traps (the signal arm exits 143) and the
  removal; `capture_baseline_mergebase` and `prove_bite` are its two callers, so there is one trap
  owner and no ordering hazard between two copies. It refuses a `TMPDIR` that resolves inside the
  repository (exit 69, checked before the first write), so neither the worktree nor its logs can
  ever appear in the founder's tree as untracked files, and it refuses to write the probes through
  a symlinked `server/` or `components/` (71). Inside the worktree the three possibly-uncommitted artifacts (config, runner,
  baseline) are copied in and `node_modules` is symlinked, exactly as the baseline capture does.
- **Both rules are asserted on their own edges, by call-form.** The injected probe is four files
  under `components/__constraint_scaffold_bite_probe__/` and `server/`: `direct.tsx` (a
  `"use client"` module value-importing the probe server module), `hop.ts` (a non-client helper
  importing it), `via-hop.tsx` (a `"use client"` module importing `hop`), and the server module
  itself, exporting one constant that is visibly not a secret. The fail step requires a captured
  log line matching `error no-client-to-server-secret: .*direct\.tsx` **and** one matching
  `error no-client-to-server-secret-transitive: .*via-hop\.tsx` — depcruise's `error <rule>:`
  call-form, never a bare rule name, because the runner's zero-reachability prose carries the bare
  token and would satisfy a token grep on a neutered gate.
- **Four new exit codes, one verdict channel.** 71 — the gate did not pass on the clean tree
  before the probe (config or toolchain error); 72 — the gate did NOT reject the injected import,
  or did not name a rule on its edge; 73 — the gate did not return to green after the probes were
  removed (non-deterministic gate); 74 — real client→server-secret violations on HEAD newer than
  the merge-base baseline (the gate is live; the bite is unprovable until they are fixed — that is
  the not-grandfathered case, not a broken gate). `verdict_fail <code> <msg>` prints
  `constraint-scaffold: bite-proof FAILED (<code>): <msg>` and the last 40 lines of the captured
  runner log on **stdout**, then dies with the same message on stderr; success prints one stdout
  line, `constraint-scaffold: bite-proof pass -> fail(no-client-to-server-secret@direct,
  no-client-to-server-secret-transitive@via-hop) -> pass depcruise=<version>`. Stdout because agent
  runtimes surface stdout and swallow stderr.
- **Default mode cleans up after itself on any failure after the first write.** The one cleanup
  handler (`_wt_cleanup`) is armed before the first artifact is emitted and disarmed only after
  `prove_bite` returns, so a bite failure (71–74), a helper failure (68/69), an unusable `TMPDIR`,
  a `set -e` abort, an INT/TERM (143) and a runner interrupted by a terminal Ctrl-C (130 —
  propagated by the runner, never dispatched as a verdict) all remove every artifact the run
  emitted (config, runner, the three workflows, baseline), `rmdir` the directories it created when
  empty, and say so on stdout. The base ref (`origin/main`, else `origin/HEAD`) and the `TMPDIR`
  containment are resolved before the first write, so the two first-install failures a founder repo
  actually hits exit 69 with nothing to clean. A failed first install is therefore re-runnable and
  never leaves a half-installed gate whose next run would exit 66; only a SIGKILL can, and the 66
  message names that recovery. Every failure message is printed on stdout before stderr (`die` is
  the one failure path), and a tool failure carries the tool's own last lines (git, depcruise)
  plus a shallow-clone hint. One run per repository: a `mkdir` lock in the git common dir with the
  owner pid, released by the same handler; a live lock is 69, a stale one is taken over. POSIX
  tools only — the generator runs on founder hosts including stock macOS. Refresh mode removes nothing (the artifacts are committed) and says the
  baseline was rewritten and should be reviewed with `git diff`. *(Review of #8352 widened this from
  "on any bite failure": the merge-base 69 sat after the emits and before any trap, measured on a
  fixture without `origin/main` — five artifacts left, next run 66.)*
- **Precondition on the three directories.** Before anything is emitted, default mode requires
  `app/`, `components/` and `server/` to exist under the target (exit 65) — the emitted runner
  cruises all three and would fail its own CI otherwise. The README names the requirement.
- **README and pointer are prose, append-once, marker-keyed, and written last.** `append_once
  <file> <marker> <content>` refuses to write through a symlink (a `CLAUDE.md -> ~/.claude/CLAUDE.md`
  link is a common shape, and `>>` would land in the founder's global instructions), returns
  silently when the marker is already present, guarantees a trailing newline, then appends.
  `server/README.md` gets a block between `<!-- constraint-scaffold:readme:start -->` and
  `<!-- constraint-scaffold:readme:end -->`, rendered from
  `references/boundary-readme.template` with the template's first-line attribution comment
  stripped and `__TARGET_DIR__` substituted. The pointer goes to `$REPO_ROOT/CLAUDE.md` if
  present, else `$REPO_ROOT/AGENTS.md` (created if absent), as one plain informational sentence
  naming the README by repo-relative path with `<!-- constraint-scaffold:pointer -->` at its end
  — never the `@path` import form and never an imperative "read X before Y", which would promote
  a tracked, unpinned markdown file in a founder repo to de-facto agent instructions. Both are
  written **after** `prove_bite` succeeds, as the final writes before exit 0 in default mode, and
  not at all in refresh mode; a failure inside either emitter after a successful bite is a stdout
  warning, not a fatal — prose is not the gate.

The script honours no `CONSTRAINT_SCAFFOLD_TEST_*` variable: the bite-proof suite drives every
failure arm through a fixture-owned stub `depcruise` reached via the fixture's `node_modules`
symlink, so the code path a founder runs is the code path the suite runs.

**Alternatives Considered (added).**

- **In-place probe** (inject the four files into the working tree, run, delete). Rejected: it
  dirties the founder's tree during the run, a TERM between inject and delete leaves probe files
  for the next commit to pick up, and the clean-tree guard that precedes baseline capture would
  see them. The worktree is what makes "the founder's tree is as it was" a property rather than a
  promise.
- **CI-time bite** (a self-test job inside the generated `constraint-gates.yml`). Recognised as
  the stronger long-term home and deferred (Deferral 2 of the plan): ADR-074's Stage A has no
  write-free self-test slot today, and an install-time proof is what closes the issue's "asserted,
  never proven" gap for the run the founder is watching.
- **Refuse-if-exists README** (the executables' invariant applied to the prose). Rejected: a
  founder's repo may already carry `server/README.md` or `CLAUDE.md`, and refusing would make the
  scaffold un-runnable on exactly the repos that document things. The refuse-if-exists invariant
  protects gate **executables**, whose silent overwrite would change behaviour; prose gets
  append-once, whose worst case is a duplicate paragraph the marker check prevents.
- **Direct-rule-only assertion** (require only the `no-client-to-server-secret` line). Rejected: the
  transitive rule is the 2026-07-01 amendment's whole point, and a gate whose reachable rule was
  softened to `warn` would still pass a direct-only bite. Each rule is asserted on the edge it
  exists for.
- **An opt-out flag for the bite** (`--skip-bite-proof` or similar). Rejected: a gate you can skip
  proving is precisely the class the issue names, and the agent — the only caller — has no
  legitimate reason to install an unproven gate.

**Consequences (added).**

- **(a) The first scaffold write outside `$TARGET`.** Every artifact before this amendment lived
  under `apps/<app>/`; the pointer line goes to the repo-root `CLAUDE.md` (or `AGENTS.md`). In
  Soleur's own tree that file was exactly `@AGENTS.md`, so the dogfood pointer is the first
  product-specific line in it — one ~170-byte plain-prose line, not measured by
  `lint-agents-rule-budget.py`, deliberately not an `@` import.
- **(b) A new exception class to refuse-if-exists.** Prose artifacts (`server/README.md`, the
  pointer) are append-once and marker-keyed; executables (config, runner, workflows, baseline) stay
  refuse-only. The distinction is by consequence of an overwrite: a silently replaced executable
  changes what CI enforces, a duplicated paragraph does not — and a marker check makes even the
  duplicate impossible. Anyone adding a third emitted artifact must place it in one class and say
  why.
- **(c) Refresh mode can now exit non-zero (74) on a real HEAD violation newer than the
  baseline.** Before, `--refresh-baseline` always rewrote the baseline and exited 0; a same-branch
  leak was invisible until CI. Now the refresh run refuses to certify the gate while a live
  violation exists, lists the imports, and leaves the rewritten baseline for `git diff` review.
  Callers that treated refresh as infallible must handle 74 as "fix the listed imports, then
  re-run".
- **(d) What the bite proves.** It proves HEAD plus the copied artifacts, run under
  `CONSTRAINT_GATES_DIR=$WT/$TARGET_REL`, not the CI path's `dirname BASH_SOURCE/..` derivation of
  the gates directory. A regression confined to that derivation (a runner moved, a relative path
  broken) is caught by the emitted workflow on the next PR, not by the bite. Recorded so nobody
  reads "bite-proof pass" as "CI path exercised".
- **(e) Two sequential worktree adds per run, and the cost.** The baseline capture and the bite
  each take one `worktree add`/remove pair, and the bite adds three runner passes to both modes.
  Measured on `apps/web-platform` on 2026-09-19 (depcruise 16.10.4): one runner pass is 16–20 s
  wall-clock and a whole refresh run with the bite is ~49 s, so the bite adds ~45–60 s plus the
  worktree pair to every scaffold and refresh run, on an agent-only path. Each `worktree add` runs
  the founder repo's own `post-checkout` hook (same trust domain as `git checkout`; the pre-amendment
  script already ran one, this adds the second). The PR body carries the canonical Task 0.4 figure.
- **(f) Test-surface deltas.** The new operands in `constraint-scaffold.sh` may move its row count
  in `plugins/soleur/test/fixture-relative-assert.baseline.txt` (10 rows before this change); a
  regeneration is legal only in the same commit as the operand edits, diffed so that only rows for
  the edited files moved. `test/parity.test.sh` grows from 8 to 10 rows: row 7 pins the dogfood
  `apps/web-platform/server/README.md` non-empty and byte-equal to the emitter's transform of the
  template (and pins the strip expression itself by grep against the script); row 8 pins the
  root `CLAUDE.md` pointer present exactly once, naming the README path, with no `@apps/`. The
  suite gains an independent `cases` counter, a conservation check and a `MIN_ROWS=10` floor.
  Every pre-existing sentinel — the config template, the shared runner, the three workflow
  templates and their dogfood copies — is byte-unchanged by this amendment.
