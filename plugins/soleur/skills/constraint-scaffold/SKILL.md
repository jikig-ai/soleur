---
name: constraint-scaffold
description: "This skill should be used when generating the Layer 1 dependency-cruiser import-boundary gate (client modules importing server secrets) into a Next.js product codebase's CI."
---

<!-- Inspired by mattpocock/skills/skills/in-progress/setup-ts-deep-modules/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# constraint-scaffold

Generates **one** deterministic, no-LLM Layer-1 structural gate into a Next.js product
codebase: a [dependency-cruiser](https://github.com/sverweij/dependency-cruiser) **import-boundary
gate** that fails closed when a `"use client"` module takes a **value** (non-`type-only`) import on
the server-only tree (`server/**`) — i.e. a server secret leaking into the browser bundle. The gate
runs in CI and rejects the violation *before* the LLM-judged review layer (`soleur:review`). See
ADR-071 (mechanism = Option D) and `knowledge-base/project/plans/2026-06-30-feat-constraint-scaffold-l1-gate-generator-plan.md`.

This gate covers this one boundary only, CI-only, Next.js-only. It catches BOTH direct
client→server-secret value imports AND transitive ones (a `"use client"` module reaching a
server secret through a chain of value imports, e.g. a non-client `lib/` helper) — the transitive
`reachable` rule was added in the 2026-07-01 #5777 amendment (ADR-071 §Amendment). Naming /
contract / pre-commit / multi-stack coverage remain deferred (ADR-071 Consequences).

## Agent-owns-gates recovery model (load-bearing)

The gate is **fail-closed**, and the target user is a non-technical founder who can never hand-edit
a `.cjs` config, a baseline, or a workflow. So the agent — never the founder — owns gate
maintenance and recovery:

1. **The agent authors and maintains the gate.** The founder never touches `.dependency-cruiser.cjs`,
   `.dependency-cruiser-known-violations.json`, the shared runner, or the workflow.
2. **When the agent's own change trips the gate:**
   - real leak → the agent fixes the offending import;
   - legitimate new cross-boundary import → the agent runs
     `constraint-scaffold.sh --refresh-baseline` (clean-tree + `origin/main` merge-base capture, so a
     same-PR violation is never grandfathered); the baseline diff is PR-reviewable.
3. **In-code escape hatch (agent-owned, used sparingly):** dependency-cruiser's native
   `// dependency-cruiser-disable-next-line` comment on the importing line.
4. **Founder hotfix with no agent in the loop (the brand-survival deadlock).** A GitHub-web hotfix
   or a machine without the repo tooling can trip the gate with no agent present. Recovery is
   **automatic and zero-touch**: the two-stage auto-recovery dispatcher (`fix-constraints-stage-a`
   → `fix-constraints-stage-b`, **ADR-074**) fires on the PR, fixes the offending import, and opens
   a **draft follow-up PR** the founder can merge — no comment, no command, no agent-in-the-loop
   required. (A real leak the agent cannot fix is surfaced for a maintainer; auto-recovery is
   fix-only and never grows the suppression baseline.) The gate stays **informational /
   non-blocking** — it is NOT promoted to a required check (promotion is now blocked only on #5778;
   the #5791 dispatcher half is satisfied by ADR-074), so it cannot deadlock a founder hotfix.
   **No override label, no `.cjs` edit, no second human required.**
5. The founder is **never** required to read or unblock the gate.

## Usage

Generate the gate into `apps/web-platform` (default mode — detect Next.js, require `app/`,
`components/` and `server/` to exist under the target, emit config + shared runner + CI workflow,
capture the initial baseline, **prove the gate bites** (see Bite-proof below), then write the
boundary README and the agent-instructions pointer last). Non-destructive: refuses to overwrite an
existing `.cjs`, runner, or workflow (there is no `--force`); the baseline JSON is the only
re-writable artifact, and only via `--refresh-baseline`; the README block and the pointer line are
append-once (marker-keyed, never rewritten):

```bash
bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/constraint-scaffold/scripts/constraint-scaffold.sh
```

Refresh the baseline after a legitimate new cross-boundary import (agent-only; clean tree required;
captures against the `origin/main` merge-base). Refresh mode runs the bite-proof too — it catches
config/runner drift a baseline entry can never grandfather (a rule softened to `warn`, a mis-scoped
from-set, a runner that stopped failing on rc>0) — and it can exit **74** when HEAD carries a real
client→server-secret violation newer than the baseline; that is the gate being live, not a broken
gate, and the fix is the listed import, not a re-run. In refresh mode nothing is removed on failure
(the artifacts are committed); the rewritten baseline is reviewed with `git diff`:

```bash
bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/constraint-scaffold/scripts/constraint-scaffold.sh --refresh-baseline
```

## What it emits (into `apps/web-platform/`)

| Artifact | Role |
|---|---|
| `.dependency-cruiser.cjs` | Executable CommonJS config. Computes the `"use client"` from-set at require-time (recomputed every run, **never** committed static), regex-escaping route-group paths. `tsConfig.fileName` + `tsPreCompilationDeps` give `@/*` alias resolution and the type-only/value distinction. |
| `.dependency-cruiser-known-violations.json` | dependency-cruiser native baseline (`--output-type baseline` / `--ignore-known`). Grandfathers only pre-existing violations. |
| `apps/web-platform/scripts/constraint-gates.sh` | Shared runner — owns the single pinned `depcruise --ignore-known … --output-type err` invocation. Fails closed on any non-zero depcruise rc; CI (and future pre-commit) both exec this. |
| `.github/workflows/constraint-gates.yml` | Always-runs + internal path-check (reports a real conclusion on every PR; no pending-forever deadlock). On failure the two-stage auto-recovery dispatcher (`fix-constraints-stage-a/b`, ADR-074) auto-opens a follow-up PR when the gate is auto-fixable. Informational/non-blocking until promoted (now blocked only on #5778; the #5791 dispatcher half is satisfied by ADR-074). |
| `.github/workflows/fix-constraints-stage-a.yml` | Untrusted `pull_request` producer (ADR-074): `contents: read` only. Runs the gate, dispatches the fix-only agent, re-verifies green, uploads the fix as a full-post-image-contents artifact (per-file sha256 + meta.json). No write token, no commit/push. |
| `.github/workflows/fix-constraints-stage-b.yml` | Privileged `workflow_run` consumer (ADR-074): validates the attacker-controlled artifact (isCrossRepository==false gate, event-sourced identity, charset+traversal+symlink+size allowlist, sha256 byte-verify) and applies it via the Git Data API (blob→tree with mandatory base_tree→commit→ref) — never checks out the untrusted tree, never git-applies. Delivers a draft follow-up PR. |
| `server/README.md` | Boundary README next to the governed path: what the boundary is, the two rule names, `import type` as the permitted shape, how to run the gate, the three-dirs requirement, what the founder sees when it trips (a red check and, when auto-fixable, an ADR-074 draft PR), that install proved pass → fail → pass, how to re-prove, and the agent-owns-recovery rule. **Append-once** between `<!-- constraint-scaffold:readme:start -->` / `:end -->` markers (existing content untouched; a symlink is refused); **written last**, after the bite-proof, so the clean-tree guard inside baseline capture never sees it. Soleur-authored; no peer sentence, no attribution line in the emission. Default mode only. |
| repo-root `CLAUDE.md` (else `AGENTS.md`, created if absent) | One plain, informational pointer line naming `apps/web-platform/server/README.md`, ending in `<!-- constraint-scaffold:pointer -->`; append-once; never an `@path` import (that would load the README into every session) and never an imperative "read X before Y". The first scaffold write outside the target directory (ADR-071 amendment). Written last, with the README. Default mode only. |

**Before editing either stage workflow (or its template), read ADR-074 + [[2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps]].** The load-bearing invariants — trigger split (untrusted producer / privileged non-executing consumer), Stage B's `isCrossRepository==false` gate on the *fully attacker-controlled* artifact, event-sourced identity, mandatory `base_tree`, name-coupling (`workflow_run` matches Stage A's `name:`, not its filename), the give-up marker (no terminal state is silent), and `emit()` output-sanitization — are enforced by `test/emit-fix-constraints.test.sh` + `test/parity.test.sh` (which covers the repo-root dogfood copies, not just emitted fixtures). A change that greens those tests but breaks an invariant is the class the tests exist to catch.

## Bite-proof (every run)

A gate that cannot fail is not a gate. Both modes end by proving, on the committed tree, that the
emitted gate goes **pass → fail → pass**; the founder never sees a scaffold whose only evidence is
that it ran green once:

1. **Stage.** In a detached-HEAD worktree under `$TMPDIR` (a `TMPDIR` that resolves inside the
   repository is refused, exit 69, before anything is written, so the worktree and its logs can never
   land in the founder's tree as untracked files), copy the three artifacts that may be uncommitted —
   config, runner, baseline — into the target path and symlink the target's `node_modules`, exactly
   as baseline capture does. A symlinked `server/` or `components/` is refused (71): the probes are
   never written through a link.
   Every runner invocation is captured to a `bite-N.log` so a failure can show its evidence before
   the worktree is removed.
2. **Pass.** The runner must exit 0 on the clean tree. `error <rule>:` lines in the log → exit
   **74** (real violations on HEAD newer than the merge-base baseline — the gate is live; fix the
   listed imports); any other non-zero → exit **71** (config or toolchain error; log tail shown).
3. **Inject — each rule on the edge it exists for.** Under
   `components/__constraint_scaffold_bite_probe__/`: a `"use client"` module value-importing the
   probe server module directly, a non-client hop that imports it, and a `"use client"` module that
   imports the hop; plus `server/__constraint_scaffold_bite_probe__.ts` exporting one string that is
   visibly not a secret.
4. **Fail, naming both rules on their own edges.** The runner must exit non-zero **and** the log must
   carry `error no-client-to-server-secret: … direct.tsx` and
   `error no-client-to-server-secret-transitive: … via-hop.tsx` — anchored on depcruise's call-form,
   never a bare rule name. Otherwise exit **72**: the gate did NOT reject the injected import.
5. **Revert.** The four probe files are removed.
6. **Pass again.** The runner must exit 0, else exit **73** (non-deterministic gate).
7. The helper removes the worktree (also on INT/TERM — the handler exits 143 with the worktree gone).
   One verdict line on stdout: `constraint-scaffold: bite-proof pass -> fail(no-client-to-server-secret@direct, no-client-to-server-secret-transitive@via-hop) -> pass depcruise=<version>`.

**Exit codes 71–74 and what the agent does next.** Every bite failure prints
`constraint-scaffold: bite-proof FAILED (<code>): <msg>` and the last 40 lines of the relevant log
on stdout. In **default mode** the self-cleanup is armed before the first artifact is written and
disarmed only after the bite has passed, so this holds for every failure in between — 66..74, an
unusable `TMPDIR`, a `set -e` abort, an INT/TERM (143), a runner interrupted by a terminal Ctrl-C
(130): the script removes every artifact this run emitted (config, runner, the three workflows, the
baseline; empty `scripts/` and `.github/workflows/` directories are removed too) and says so — the
README and pointer have not been written yet — so the repo is as it was and the next run is a clean
first install, never a 66 on a half-installed gate. Every failure message is on stdout first
(`constraint-scaffold: FAILED (<code>): …`). Only a SIGKILL can leave residue (the six files plus a
stale `.git/worktrees` registration); the 66 message names that recovery (`git clean -n`, `git
worktree prune`, re-run). The base ref is `origin/main`, else the remote's default branch
(`origin/HEAD` — a founder repo on `master`); neither present exits 69 before anything is written.
In refresh mode nothing is removed. A failure while writing the README or the pointer **after** a
successful bite is a warning on stdout, not a fatal: the gate is installed and proven; the message
names the file and the missing doc. **Hosted-runner deviation:** `plugins/soleur/` is vendored into
the production image, so this script can run where no human reads stdout; there a 71–74 is
transcript-only by design — no `SOLEUR_*` marker is emitted (AC13, the marker-population caution)
— and the mirrored-not-paged `SOLEUR_CONSTRAINT_SCAFFOLD_HALT` is #8381 (`deferred-scope-out`).

**Precondition (exit 65).** Default mode requires `app/`, `components/` and `server/` to exist under
the target before anything is emitted — the emitted runner cruises all three and would fail its own
CI otherwise; the message names the missing one. The README names the requirement.

The script carries **no test seams** (no `CONSTRAINT_SCAFFOLD_TEST_*` variable is honoured); the
suite drives every failure arm through a fixture-owned stub `depcruise` reached via the fixture's
`node_modules` symlink. Decision record: ADR-071 §Amendment 2026-09-19 (#8288).

## Self-tests

`test/bite-proof.test.sh` (scripts shard) pins the contract above: pass → fail → pass on the real
dependency-cruiser; every 71/72/73/74 arm through the stub; both rule names asserted on their own
probe files; worktree removal on success, on failure and on TERM; default-mode self-cleanup leaving
the fixture tree as it was; and the `TMPDIR`-inside-repo refusal.

`test/boundary.test.sh` (scripts shard) proves the gate is not vacuous: a value import of `server/**`
via the `@/server/…` alias FAILS, an `import type` of the same PASSES, route-group/metacharacter
paths are matched (regex-escaping), an empty from-set while `"use client"` files exist is a hard
error, and a broken `.cjs` fails the runner closed.

- **Sharp edge (transitive rule):** the "reachable baseline stays empty" guard MUST key on the
  transitive rule NAME, never on `type:"reachability"` — dependency-cruiser softens the reachable
  rule per-origin on `from`+`rule.name` IGNORING entry `type`, so a `type:"module"` baseline entry
  naming the rule suppresses a real leak while a type-count reads 0 (a `--refresh-baseline` capture
  never emits that shape, so the regression fixture must inject it by hand). See
  `knowledge-base/project/learnings/security-issues/2026-07-01-depcruise-reachability-baseline-softens-per-rule-name-ignoring-type.md`.
