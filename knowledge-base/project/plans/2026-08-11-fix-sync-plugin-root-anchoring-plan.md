---
title: "fix(sync): make plugin-owned executables reachable from a customer repo"
date: 2026-08-11
slug: fix-sync-plugin-root-anchoring
branch: feat-one-shot-7442-sync-plugin-root-anchoring
issue: 7442
closes: 7442
type: bug
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-08-11
**Passes:** 2 research agents (repo conventions, learnings) · 4 plan-review agents
(architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, scoped
strong-model advisor) · 2 deepen-review agents (security-sentinel,
test-design-reviewer) · mechanical verification throughout.

### Key improvements over the first draft

1. **The proposed remedy was measured to be a no-op on the target surface.**
   `CLAUDE_PLUGIN_ROOT` is unset in a plain CLI session, so
   `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` expands to the bug. Root resolution is now
   a **blocking Phase 0** with a bound decision tree instead of an assumption.
2. **Scope corrected from 3 sites to 29.** The 50 findings decompose into 29 anchorable
   (payload-owned) and 21 un-anchorable (repo-root `scripts/`, = #6222). The first draft
   fixed 3 and grandfathered 26 — remediating the reporter, not the shape.
3. **The grandfathering subsystem was deleted.** Fixing all 29 removes the need for a
   baseline, a marker vocabulary, and a ~630-line Python linter family; the guard is now
   a ~50-line vitest file modelled on an existing sibling.
4. **Two measurement traps corrected** — indented fences (46 → 50) and inline code spans
   (which contain the single most dangerous site in the issue).
5. **The rule-prune claim was narrowed** from "structurally monorepo-only" to "no input
   source today", after two payload scripts were found consuming the same telemetry with
   graceful degradation. The halt became executable rather than prose.
6. **Second-writer defect avoided** — the degraded artifact moved from LLM-hand-authored
   markdown into `write-kb-coverage.ts --producer-unreachable`, preserving the single
   renderer, the documented `grep`, determinism, and the brand-wording gate.
7. **ADR decision reversed** — mint, don't amend: `check-adr-ordinals.sh` removes the
   collision rationale and ADR-093 is surface-bound to the platform.
8. **C4 finding reversed twice** — from "add an edge", to "no change", to the correct
   answer: the self-hosted CLI topology is genuinely unmodelled.

### New considerations discovered

- Two subagent claims were falsified by direct read (`rule-prune.sh:52` "move is safe";
  a non-existent `scheduled-rule-prune.yml`). Both are recorded in Reconciliation.
- A live citation check corrected the recurrence chain: **#4826 is the class's victim,
  not a member**.
- Axes 3 (library root) and 4 (toolchain root) were added; `worktree-manager.sh:48` is a
  live shipped instance where lease protection is silently off for customers.
- `/soleur:sync domain-model` standalone is dead on a fresh repo independently of this
  bug (`init` is wired only into `all`).
- Standalone areas write no durable artifact at all, exempting three areas from the
  layer-7 argument.

---

## Overview

`/soleur:sync` invokes its producer scripts with paths written relative to the
caller's working directory. Inside this monorepo that resolves correctly, because the
repo self-hosts the plugin. From a customer repo the same paths resolve into the
customer's own tree, so several sync areas cannot reach their producer — and one
producer is not in the plugin payload at all, so no marketplace update can deliver it.

**The fix the issue proposes does not work on the surface the issue is about.** That is
this plan's headline finding, and it is measured, not argued: `CLAUDE_PLUGIN_ROOT` is
**unset in a plain CLI session**, so `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…` expands
to `./plugins/soleur/…` relative to the customer's CWD — byte-identical to the bug. And
no `:-` fallback can work, because a marketplace install has no `plugins/soleur` in the
customer's repo at either anchor. Phase 0 therefore resolves the root-resolution
question **before** any edit lands; everything downstream is conditional on its outcome.

The defect is also wider than `/soleur:sync`: **29 invocations of payload-owned
executables are written bare-relative across 19 files**. The unit of remediation is the
shape, not the reporter.

## BLOCKING UNKNOWN — resolve before any edit

Everything in Phases 1–6 is conditional on this. It is cheap to measure and expensive
to assume, and the first two drafts of this plan assumed it wrongly in opposite
directions.

### What is measured and certain

| Fact | Evidence |
| --- | --- |
| `CLAUDE_PLUGIN_ROOT` is **unset** in a plain CLI bash session | Measured this session: `echo "[${CLAUDE_PLUGIN_ROOT:-<UNSET>}]"` → `[<UNSET>]` |
| The repo already knew this, twice | `plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md:369` — *"`CLAUDE_PLUGIN_ROOT` is unset in a plain session"*; `plans/2026-07-08-fix-residual-plugin-root-migration-agent-run-skills-plan.md:186` — *"CLI: var unset → git-root checkout regardless of CWD"* |
| The export invariant is **server-only** | ADR-093 §Amendment: *"fail-safe only under one invariant: the SDK exports a non-empty `CLAUDE_PLUGIN_ROOT` into the **Concierge** autonomous-bypass bash env"* — `buildAgentEnv`, `/app`-validated. Nothing equivalent exists on the CLI. |
| The harness **does** substitute it in `hooks.json` | `plugins/soleur/hooks/hooks.json:10,20,28` use bare `${CLAUDE_PLUGIN_ROOT}` with **no** fallback — that is a harness-substituted context, not a bash env read |
| Neither fallback form reaches a marketplace install | `./plugins/soleur` → customer's CWD; `$(git rev-parse --show-toplevel)/plugins/soleur` → customer's repo root. **A marketplace customer has `plugins/soleur` at neither.** |

**Consequence:** the existing convention (55 sites on `:-./plugins/soleur`, 38 on
`:-plugins/soleur`) is CLI-correct only because its CLI user has so far been the
dogfooding operator standing in this monorepo, where `git-root/plugins/soleur` exists.
That premise does not survive contact with a real customer — which is exactly what
#7442 reports.

### What must be measured in Phase 0

**Is `CLAUDE_PLUGIN_ROOT` exported into the bash tool environment when the agent is
executing instructions from a plugin-provided *command* (`commands/sync.md`) in a
marketplace-installed plugin — as opposed to the plain agent session measured above?**

Measure it directly; do not infer it from `hooks.json` (a different substitution
mechanism) or from the plain-session reading (a different context).

### Decision tree — bind the remedy to the measurement

| Outcome | Remedy |
| --- | --- |
| **(A) Set in plugin-command context** | Use **`${CLAUDE_PLUGIN_ROOT:?…}` — fail-closed, no `:-` fallback** — for every customer-facing producer. The fallback *is* the vector: it is what silently reaches the customer's tree. A hard failure naming the unresolved root is strictly better than executing an unknown file. |
| **(B) Unset** | Anchoring cannot fix this class at all, and #7442 is a **symptom of a missing capability**: a marketplace-installed plugin has no supported way to locate its own payload from a command's shell. Escalate — the remedy is a harness-level or packaging-level design question larger than this issue, and the honest interim shipment is Phase 5's fail-closed halts plus a clear "not available on this surface" message, not a cosmetic prefix. |
| **(C) Set only in some contexts** | Treat as (B) for customer-facing paths — fail closed — and use (A)'s form where the context is guaranteed. |

**Under every outcome, a `:-` fallback into a customer-writable path is rejected.**

### The test that decides it, written first

Per `cq-write-failing-tests-before`, add the missing matrix cell **before** any edit and
watch it go red:

> **customer CWD + `CLAUDE_PLUGIN_ROOT` unset + a decoy `plugins/soleur/scripts/write-kb-coverage.ts` planted in the fake customer repo.**

The prior draft's matrix had `customer CWD + var set` and `monorepo + var unset` — every
cell except the one that reproduces #7442. Worse, it planted a decoy only at
`scripts/rule-prune.sh`, never at `plugins/soleur/scripts/…`, so the vector the *fix
itself introduces* was untested. A suite that sets the variable it is supposed to be
testing the absence of is a manufactured pass.

## BLOCKING FINDINGS FROM DEEPEN REVIEW — read before Phase 0

Three findings from the security and test-design passes are plan-invalidating as
written. All are verified against files in this repo, not argued.

### BF-1 (P0) — The trust direction is NOT uniformly inverted, and a worse issue than #7442 exists

The plan claimed the CLI case inverts ADR-093's trust direction ("the customer's own
machine and own repo"). **That is true only for the marketplace-customer case.** For the
dominant CLI surface today it is **identical to ADR-093**:

- `plugins/soleur/skills/review/SKILL.md:63` — *"Make sure we are on the branch we are
  reviewing. Use `gh pr checkout` to switch to the branch."*
- `plugins/soleur/skills/review/SKILL.md:276` — then runs
  `bash scripts/domain-model-drift.sh drift --repo .` (bare CWD-relative), and
  `preflight/SKILL.md:1338` does the same.
- Measured: `git rev-parse --show-toplevel` returns the **worktree** root, not the
  operator's canonical checkout.

So reviewing an untrusted contributor's PR executes **that contributor's** script on the
operator's machine, with the operator's `gh` token, Doppler token and SSH keys. The repo
already models an untrusted `contributor` actor (ADR-074). The CLI-unset measurement
makes this unconditional.

**BF-1a — the 5 git-root redaction-gate sites are affected, and this is a separate, more
severe issue.** `incident/SKILL.md:222`, `legal-generate/SKILL.md:63`,
`linear-fetch/SKILL.md:79`, `compound/SKILL.md:326`, and the test that pins the form at
`incident/test/redact-sentinel.test.sh:593`. #7442's failure mode is *availability*;
these are a **security control whose exit code decides whether secrets are emitted** —
a substituted script that `exit 0`s silently disables redaction and the operator sees a
pass. The `[[ -r "$SENTINEL" ]]` guards do not help; ADR-093's own Amendment says so.

**ADR-093 §Amendment line 55 contains a now-falsified premise:** *"it is the correct,
trusted path for CLI/worktree/local-operator use (var legitimately unset, **git-root =
the operator's own checkout**)."* After `gh pr checkout`, git-root is the PR author's
tree; on a marketplace install it is the customer's repo. The entire justification for
retaining the fallback rests on that parenthetical.

**Action: file BF-1/BF-1a as a separate P0 security issue and fix the redaction gates
first — do not fold into #7442.** Correct the plan's trust-direction claim to:
*inverted for the marketplace-customer case; identical to ADR-093 for the
self-hosting/PR-review case.*

### BF-2 (P1) — The guard predicate as specified cannot go green, and would break two committed guards

If the `:-` fallback is the vector (BLOCKING UNKNOWN), then the ~100 already-anchored
literals are violations too — so the population is **~127, not 29**. Measured in the
guard's own declared scope: **100 `:-` literals across 35 files** in six forms,
including `${CLAUDE_PLUGIN_ROOT:-.}` and `${CLAUDE_PLUGIN_ROOT:-../../plugins/soleur}`.

Two committed artifacts **require** the `:-` form:

- `apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts:66-68` — its
  `LIST_EMISSION` regex is `\$\{CLAUDE_PLUGIN_ROOT:-[^}]+\}/skills/git-worktree/…`, with
  a `>= 1` vacuity floor. Converting the 22 git-worktree sites off `:-` reds it by
  vacuity.
- `apps/web-platform/server/safe-bash.ts:168` pins the exact literal
  `"bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh"`
  in an allowlist.

So the plan's Phase 4 ("constrain the fallback form"), AC2 ("zero anchorable violations
repo-wide") and Phase 1 ("29 one-line edits") are **mutually unsatisfiable**. Phase 0
must additionally fix **which verb/target set the predicate covers**, and an AC must
assert the guard is green against the pre-existing `:-` corpus (or scope its remediation
explicitly).

**BF-2a — `worktree-manager.sh:48` comes out of deferral 6.** It is a `source` (full
shell execution in the calling process, strictly worse than `bash <script>`) of
`$SCRIPT_DIR/../../../../../.claude/hooks/lib/session-state.sh` — five levels up from a
worktree is the **checked-out tree**, i.e. the untrusted-PR path from BF-1.

### BF-3 (P1) — The new test suite would never gate, and T0's assertion is near-vacuous

- **Silent orphan.** `scripts/test-all.sh:573-574` registers the two existing
  `tests/commands/` suites by **explicit `run_suite` lines — there is no glob**, and
  `scripts/lint-orphan-test-suites.sh:33` iterates only `"$REPO_ROOT"/scripts/*.test.sh`,
  so the tombstone that catches this class does not cover `tests/commands/`. The new
  suite must add a `run_suite` line, `scripts/test-all.sh` must join Files to Edit, and
  an AC must assert the registration **anchored on the call shape**, not the bare
  filename (`cq-assert-anchor-not-bare-token`).
- **T0 is negative-only.** "Neither decoy executed" is satisfied by *nothing executed* —
  and under decision-tree outcome (B) nothing does execute, by design. T0 needs a
  **positive control**: a pre-fix cell where the decoy sentinel **is** present, kept
  permanently in the suite and parameterized on the literal rather than on git state.
- **A bash test cannot assert what the agent would do.** The correct unit is one level
  down: extract the command literal from `sync.md`, `eval` it in a subshell with the fake
  CWD and the variable unset, and assert on what bash did. Substitute `<n>`-class
  placeholders first (`<n>` is a bash input redirect and fails before path resolution),
  seed the register fixture, and shim `bun` on `PATH` the way
  `tests/commands/test-sync-rule-prune.sh:24-79` already shims `gh`.
- **Do not pin the vacuity floor to a site count.** The repo litigated this and reached
  the opposite conclusion — `plugin-root-list-carveout-coupling.test.ts:41-44`: the floor
  *"is deliberately NOT pinned to today's exact count … so that legitimately removing a
  site does not false-fail the guard."* Bound it by **mechanism** instead: ≥1 site per
  detection mechanism (indented fence, column-0 fence, inline span), plus a
  synthetic-fixture self-test asserting exact counts on an in-test string.
- **`expected_output` pre-commits to outcome (A)** while H7 is declared UNKNOWN. Bind it
  to the measured branch at Phase 0.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verdict |
| --- | --- |
| `sync.md` invokes producers CWD-relative at 194/245/252/303/306/331/345/375 | **Holds** — 8 sites (the issue named 4) |
| The two named scripts are outside the payload | **Holds** |
| "35 files already anchor to `CLAUDE_PLUGIN_ROOT`" | **Understated** — 38 files, 103 literals, six fallback forms |
| ADR-093's reasoning applies verbatim | **Partly** — its *reasoning* transfers; its *guarantee* does not. ADR-093 is platform/Concierge-bound; #7442 is the self-hosted CLI, where the export invariant is absent and the trust direction is inverted |
| Un-superseded | **Holds** — overlaps open **#6222**, which ADR-093 §Consequences already opened for this class. `Ref #6222`, never `Closes` |

### The axes — four, not two

The monorepo collapses the first two into one directory, which is why the class is
invisible here. Axes 3 and 4 were added by review after the first draft claimed two.

1. **Executable root** — where the program lives. Must be the deployed payload.
2. **Data root** — which tree it reads/writes. Must be the customer's repo **top level**
   (`git rev-parse --show-toplevel`), never `$SCRIPT_DIR/..`, never a bare CWD.
3. **Library / dependency root** — where a shipped executable resolves what it *sources*.
   Independently rooted, and already inconsistent in the payload:
   `write-kb-coverage.ts:40` sources `../lib/kb-coverage` (inside the payload — fine);
   `gdpr-gate.sh:26-31` sources `$REPO_ROOT/.claude/hooks/lib/incidents.sh` and
   **degrades gracefully** (`emit_incident() { :; }`);
   `worktree-manager.sh:48` traverses *out* of the payload via
   `$SCRIPT_DIR/../../../../../.claude/hooks/lib/session-state.sh` — **a live shipped
   instance of this very class**, where lease protection is silently off for a customer.
4. **Toolchain root** — `generate-c4-from-components.ts:249-252` `spawnSync("npx", …)`
   resolving `likec4` by semver at run time; both TS producers are invoked as `bun …`.
   **Reachable ≠ runnable**, which is this plan's own stated distinction applied one
   level short of where it bites.

### The 50 findings decompose into two classes

The first draft missed this and consequently proposed grandfathering 26 live instances
of the bug it was fixing.

| Class | Count | Remedy |
| --- | --- | --- |
| Target is `plugins/…` — payload-owned, **anchorable** | **29** across 19 files | the Phase 0 form — **all fixed here** |
| Target is repo-root `scripts/…` — **un-anchorable** | **21** | out of scope — this *is* #6222 |

Because all 29 are fixed, the guard needs **no baseline, no grandfathering, no marker
vocabulary**. 26 extra one-line edits delete an entire grandfathering subsystem.

The 19 files: `commands/sync.md`, `agents/engineering/discovery/agent-finder.md`,
`agents/support/community-manager.md`, and the `cf-token-scope`,
`drain-labeled-backlog`, `drain-prs`, `flag-bootstrap`, `flag-create`, `flag-delete`,
`flag-list`, `flag-set-role`, `frontend-design`, `provision-cloudflare`,
`provision-doppler`, `provision-github`, `provision-hetzner`, `resolve-debt`, `ship`,
`user-set-role` skills.

### Two measurement traps, both hit and corrected

1. **Indented fences.** `/^```/` returned 46 and 3 sync.md sites; fences inside list
   items open with `   ```bash`. The indent-aware `/^[[:space:]]*```/` returns **50**,
   and 6 for sync.md.
2. **Inline code spans are not fenced.** `sync.md:306` is
   `` **Invoke** `bash scripts/rule-prune.sh --weeks=<n>` `` — invisible to any
   fence-based scanner, and **the most dangerous site in the issue**: the one whose name
   collision executes a customer's own file.

The guard must scan fenced blocks **and** inline spans, indent-aware. Both are
correctness requirements.

### Institutional learnings applied

| Learning | Applied as |
| --- | --- |
| `bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md` | "The command is deployed" ≠ "the scripts it shells out to are deployed" |
| `best-practices/2026-07-08-plugin-root-migration-ac-grep-scope-and-anchor-preservation.md` | Anchor preservation — but see the Blocking Unknown: that guidance is server-surface guidance |
| `best-practices/2026-07-08-adr093-anchored-literal-migration-needs-parity-test-and-grep-F.md` | **Every anchored-literal grep uses `grep -F`** — `$`, `{`, `}` are BRE metacharacters |
| `2026-07-29-a-per-producer-fix-left-seven-siblings-live-…md` | **The shape, not the reporter** — why 29 sites, not 3 |
| `workflow-patterns/2026-08-06-an-observability-plan-can-name-a-sink-the-code-cannot-reach.md` | A named sink is a claim to verify — applied in reverse to rule-prune |
| `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md` | Two subagent claims were falsified by direct read (Reconciliation rows 2, 6) |

### Reusable precedent

- **Guard template — `apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts`**
  (112 ln, ~40 ln logic): already a `${CLAUDE_PLUGIN_ROOT}` guard over
  `plugins/soleur/**/*.md`, with `walkMarkdown()` and a vacuity floor.
- **Not the template — `scripts/lint-credential-path-literals.py`** (288 ln) + `.test.sh`
  (267 ln). Same directory scope, but that is similarity on the wrong axis: its size
  comes from 15 regexes and three invocation modes.
- **`plugins/soleur/scripts/resolve-git-root.sh`** — sourceable, sets `GIT_ROOT` from
  `git rev-parse`. The axis-2 remedy for shell.
- **`scripts/check-adr-ordinals.sh`** — committed, fail-closed ordinal-collision guard.
  Its existence removes the process rationale for amending rather than minting an ADR.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
| --- | --- | --- |
| "4 of 8 areas unrunnable" | `rule-prune` is excluded from `all` (`sync.md:82`). `all` loses `c4`, `domain-model`, coverage — **3**. Five areas have no producer and were never broken. | Blast radius stated accurately |
| **Subagent:** `rule-prune.sh:52` is *"portable … move is safe"* | **FALSE.** `ROOT="${RULE_METRICS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"` → after a move, `plugins/soleur/`, whose `knowledge-base/` holds only `learnings/`. `exit 2` on every run, including here. | The canonical axis-2 inversion |
| Issue: *"move both scripts"* | Correct for `domain-model-drift.sh`; wrong for `rule-prune.sh` | Remedy split per script |
| Implicit: rule-prune is merely path-broken | Its chain starts at `emit_incident()`, defined **only** in `.claude/hooks/lib/incidents.sh`; payload hooks are `browser-cleanup`/`stop`/`welcome` and `hooks.json` has no incidents reference. **No input source on a customer repo today.** | Don't ship it — but see the narrowed claim below |
| **First draft's own claim:** rule-prune is *"structurally monorepo-only"* | **Over-reached.** `gdpr-gate.sh:26-31` and `compound/scripts/token-efficiency-report.sh:243-250` already ship as payload consumers of `emit_incident` **with graceful degradation**. Absence of the producer is not a structural bar. | Narrowed to: *no input source today, so shipping it would deliver a false-clean signal* — a product-scope call (deferral 4), not a law of the codebase |
| Issue enumerates four lines | A fifth repo-root script at `:303`; two further skills (`preflight:1338`, `review:276`); and 26 anchorable sites outside sync | All 29 fixed; `scripts/` class stays with #6222 |
| **Subagent:** `scheduled-rule-prune.yml` is a caller | **Does not exist** — migrated to `cron-rule-prune.ts` | Dropped |
| Implicit: the move is self-contained | `domain-model-lib.sh` has **one** code consumer — clean. But the script is cited at **13 living sites** incl. ADR-076, ADR-129, `domain-model.md` | Full reverse sweep, AC-enforced |
| Implicit: `/soleur:sync domain-model` works once relocated | **Standalone is still dead.** `domain-model-drift.sh:241-247` says so: `drift`/`write-row` `realpath -e` the register and die when absent; `init` is wired only into `all` (`sync.md:375`) | Phase 3 wires `init` into the standalone contract |
| Implicit: repointing `tests/commands/test-sync-domain-model.sh` is meaningful | **It is a no-op.** Its assertions `grep -qE 'scripts/domain-model-drift\.sh drift'` still match the anchored literal, so it neither breaks nor detects un-anchoring | Rewrite the assertion to anchor-aware, or drop the file from the sweep |

## Open Code-Review Overlap

**None.** All 64 open `code-review` issues queried; every planned path matched with
`jq --arg path … contains($path)`. Zero hits.

## Hypotheses

The Phase 1.4 gate fired on a substring match ("unreachable"). **It does not apply** —
its L3→L7 checklist is for *host connectivity*; here "unreachable" describes a
filesystem path that does not resolve. Fabricating four network-layer hypotheses would
be false diagnostics.

| # | Hypothesis | Method | Verdict |
| --- | --- | --- | --- |
| H1 | Invocations are CWD-relative | `grep -nE` over sync.md | **CONFIRMED** — 8 sites |
| H2 | Two scripts are outside the payload | `test -f` both locations | **CONFIRMED** |
| H3 | A bare `git mv` suffices | direct read of `rule-prune.sh:52` | **REFUTED** — inverts the data root |
| H4 | rule-prune is customer-runnable once pathed | traced chain to `emit_incident()`; checked payload hooks | **REFUTED** — no input source today |
| H5 | The issue's four sites are the whole set | repo-wide sweep | **REFUTED** — 29 anchorable across 19 files |
| H6 | `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` fixes the customer surface | **measured** `CLAUDE_PLUGIN_ROOT` in a CLI session; read ADR-093's amendment | **REFUTED** — unset on CLI, so it expands to the bug. See Blocking Unknown |
| H7 | `CLAUDE_PLUGIN_ROOT` is set in plugin-*command* context | — | **UNKNOWN — Phase 0 blocking measurement.** Not marked either way; the deciding datum has not been collected |

H7 is deliberately left UNKNOWN. A hypothesis table may not carry a verdict its
evidence cannot support, and every downstream phase is bound to H7's outcome by the
decision tree above.

## User-Brand Impact

**If this lands broken, the user experiences:** a first-run `/soleur:sync all` that
reports success while silently omitting the generated C4 diagram, the domain-model
register rows, and `kb-coverage.md` — the artifact whose purpose is to say what the
knowledge base contains. Adoption's first impression is a knowledge base quietly
two-thirds empty, with nothing in the repo saying so. Beyond sync, 26 further
invocations across `flag-*`, `provision-*` and `user-set-role` fail identically.

**If this leaks, the user's workflow is exposed via:** a name collision in their own
tree. A customer running `/soleur:sync rule-prune` with their own `scripts/rule-prune.sh`
gets **their** file executed under an agent that parses its stdout and files GitHub
issues from the sentinels. **The `:-` fallback keeps this vector open even after the
"fix"** — which is why the Blocking Unknown rejects fallbacks into customer-writable
paths outright, and why the decoy test must plant a decoy at `plugins/soleur/scripts/`
too, not only at `scripts/`.

**The sharper framing is BF-1, and it is not the customer's own code.** Executing a
customer's own file on the customer's own machine is an integrity failure. Executing an
**untrusted contributor's** file on the **operator's** machine — which
`review/SKILL.md:63`'s `gh pr checkout` plus `:276`'s bare-relative invocation does
today — is arbitrary code execution with the operator's credentials, triggered by the
act of reviewing a PR. The trust direction is therefore *inverted only for the
marketplace-customer case*; for the PR-review case it is identical to ADR-093. That
strand is more severe than #7442 and is filed separately (deferral 8).

**Brand-survival threshold:** `single-user incident`

One customer, one first run: silent, durable (committed to their history), and the
observability layer meant to surface it is knocked out by the same root cause. sync.md
specifies `SOLEUR_KB_SYNC_PRODUCERS` twice — stdout **and** inside `kb-coverage.md` —
because *"on a self-hosted CLI there is no Soleur-side sink and there must not be one
(ADR-171 §Observability boundary)"*. When the producer is unreachable both are lost.

`requires_cpo_signoff: true` per Phase 2.6 step 3; `user-impact-reviewer` runs at review
time.

## Architecture Decision (ADR/C4)

### ADR — mint a new one; do not amend ADR-093

The first draft proposed amending ADR-093 to dodge ordinal collisions. Review corrected
this on two grounds, both verified:

1. **The process rationale is already handled.** `scripts/check-adr-ordinals.sh` exists
   and is fail-closed. Avoiding a correct document boundary to dodge a hazard the repo
   already tools against is the wrong trade.
2. **The surfaces genuinely differ.** ADR-093's Decision is surface-bound — *"load the
   SDK plugin source from the platform-controlled deployed root (`getPluginPath()`)"* —
   and its entire machinery (`getPluginPath`, `/app/shared`, `assertTrustedPluginPath`,
   `buildAgentEnv`, bwrap, `safe-bash`) exists **only** on the platform. #7442 is the
   self-hosted CLI, where none of that exists, where the export invariant is absent
   (Blocking Unknown), and where the trust direction is inverted. Folding both into one
   ADR would make it span two surfaces, two threat models and two enforcement
   mechanisms.

**New ADR:** *the plugin payload boundary and root resolution on the self-hosted CLI* —
recording (a) executable reachability as a precondition distinct from anchoring, (b) the
four-axis rule, (c) that a `:-` fallback into a customer-writable path is not an
acceptable resolution strategy. Cross-reference ADR-093 §Consequences and #6222; add a
one-line pointer in ADR-093. Derive the ordinal with `scripts/check-adr-ordinals.sh`
across **every `origin/*` ref**, and **re-derive immediately before merge**. Also add an
`AP-0NN` row to `knowledge-base/engineering/architecture/principles-register.md` — the
register has no principle covering the payload boundary, and this class has recurred
across #6121 → #6154 → #6156 → #6222 → #7442 (all verified live: the first three
CLOSED, #6222 and #7442 OPEN).

**Citation correction.** ADR-093 cites #4826 as *"(delivery wedge; the infra bug behind
it)"*. Live-verified, **#4826 is "feat: nav-rail position resume"** — the issue whose
*delivery* the plugin-shadow bug blocked, not an instance of the class. It is therefore
the class's most visible **victim**, not a member of the recurrence chain, and must not
be listed as one. Do not propagate the looser reading into the new ADR.

### C4 — the self-hosted CLI topology is unmodelled

All three files read in full: `model.c4` (660 ln), `views.c4` (70 ln), `spec.c4` (54 ln).

- **External human actors:** `founder`, `emailSender`, `betaContact`, `contributor`.
- **External systems:** `connectedRepoPlugin` (`:324`), `connectedRepoKb` (`:339`) —
  both `#external`, with the trust edge `connectedRepoPlugin -> skillloader` present.
- **Containers:** `platform.plugin.{skills,agents,kb}`.

**The finding is not "no change".** `sync` is modelled as `platform.plugin.sync` — a
component *inside the platform system* — and `connectedRepoPlugin`/`connectedRepoKb` are
the connected repo as it appears in the **platform's** workspace volume. There is **no
element anywhere in `model.c4` representing a self-hosted CLI install**: a marketplace
plugin on a customer's own machine against their own repo. The first draft's claim that
*"the customer running `/soleur:sync` is `founder`, already modelled"* is **false** — on
the platform path the Concierge agent runs sync from `/app/shared/plugins/soleur` with
the variable set, which is the path that is **not** broken.

**The universal negative was tested, not assumed.** Enumerating every `person`/`system`
declaration in `model.c4` (24 top-level elements) and grepping for
`self.?host|marketplace|local install|customer.?machine|cli install|workstation` returns
only `zotRegistry` ("Self-hosted zot registry"), two Redis containers, and — tellingly —
the `contributor` description's mention of *"the operator's own workstation"* for the
ADR-175 preflight probe. So the model **acknowledges operator-workstation execution in
prose while modelling no element for it**. That is the gap, and it is exactly the shape
this bug lives in.

**In-scope C4 task:** add a `selfHostedCli` external element plus the producer-execution
edge, so the model represents the surface this bug lives on.

**View-include trap — check before adding the edge.** `connectedRepoPlugin` is in the
`containers` include list but **not** `components`; `sync` is in `components` but **not**
`containers`. An edge between them renders in **neither** view — the disconnected-box
artifact `views.c4`'s own comment warns about. Both endpoints must be added to whichever
view is meant to render the edge. Validate with `c4-code-syntax.test.ts` and
`c4-render.test.ts`, then `bash scripts/regenerate-c4-model.sh` and stage
`model.likec4.json` before committing or `c4-model-freshness.test.sh` reds.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Wider blast radius than the issue implies: 29 invocation sites across 19
files, a relocated script cited at 13 living sites including two ADRs, and a production
workflow. The governing risk is not any of those — it is that the proposed remedy is
unverified on its target surface (Blocking Unknown), which is why Phase 0 is a hard gate
and the decisive test is written first. No schema, migration, auth surface or new vendor.

### Product/UX Gate

Not applicable. Mechanical UI-surface override evaluated against Files to Create/Edit:
no `components/**/*.tsx`, `app/**/page.tsx` or `app/**/layout.tsx`; every file is
markdown, shell, TypeScript or a test. Tier **NONE**;
`wg-ui-feature-requires-pen-wireframe` does not fire.

**Lane note:** no `spec.md` existed at plan time; `lane:` defaulted to `cross-domain`
(TR2 fail-closed).

## Compliance Gates

**GDPR / Phase 2.7 — assessed, not skipped.** The canonical regex does not match. Of the
four expansion triggers only (d) *"new artifact distribution surface (plugin update)"*
arguably fires. The relocated script is deterministic shell reading the customer's own
repo locally, transmitting nothing; no new processing of personal data, no new
controller/processor relationship. **No gate invocation required.**

**Phase 2.8 IaC — skipped.** No new infrastructure. **Phase 2.11 Encryption — skipped.**
No persistent store, no new cross-component connection.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_KB_SYNC_PRODUCERS marker, emitted twice — stdout AND inside
         knowledge-base/project/kb-coverage.md (layer 7, cli-stdout-artifact;
         ADR-171 §Observability boundary)"
  cadence: "once per `/soleur:sync all` run, after every other area"
  alert_target: "none by design — self-hosted CLI. No Soleur-side sink and there must
                 not be one; the durable in-repo artifact IS the queryable surface."
  configured_in: "plugins/soleur/commands/sync.md (Coverage Summary);
                  producer plugins/soleur/scripts/write-kb-coverage.ts;
                  renderer plugins/soleur/lib/kb-coverage.ts"

error_reporting:
  destination: "SOLEUR_KB_SYNC_ERROR on stdout; degraded artifact written by
                write-kb-coverage.ts itself — never hand-authored."
  fail_loud: true

failure_modes:
  - mode: "Producer unreachable — the root does not resolve"
    detection: "tests/commands/test-sync-producer-reachability.sh makes this
                un-shippable at CI, INCLUDING the customer-CWD + var-unset + decoy cell.
                At runtime the emitted shell fails closed on an unresolved root."
    alert_route: "CI red pre-merge; at runtime a named halt on stdout"
  - mode: "Producer reachable but not RUNNABLE (bun absent, npx/network absent)"
    detection: "`command -v bun` probed in the precondition; `test -r` on the .ts file is
                NOT sufficient — a missing interpreter exits 127 while the readable check
                passes. generate-c4 additionally needs npx + network (:249-252)."
    alert_route: "NOT SHIPPED — `--producer-unreachable` was designed below but not built; write-kb-coverage.ts parses only `--degraded`. The durable-artifact half of this failure mode remains open, tracked in #7452. Do not read this row as a live route."
  - mode: "Anchor regression — a bare-relative or fallback-laundered payload path returns"
    detection: "apps/web-platform/test/plugin-root-anchoring.test.ts — constrains the
                FALLBACK, not merely token presence; fenced blocks + inline spans;
                indent-aware; vacuity floor"
    alert_route: "CI red on the introducing PR"
  - mode: "rule-prune invoked where its telemetry input cannot exist"
    detection: "the EMITTED SHELL fails closed on a monorepo sentinel — not a prose
                instruction the model may or may not honour"
    alert_route: "stdout halt naming the absent precondition"

logs:
  where: "knowledge-base/project/kb-coverage.md in the customer's own repository"
  retention: "permanent (git history); deterministic — no timestamp, stable ordering"

discoverability_test:
  command: "bash tests/commands/test-sync-producer-reachability.sh"
  expected_output: "0 failed"
```

First token `bash` is on Check 10's `PROBE_VERB_ALLOWLIST`; the target is repo-relative
and committed in this PR; no `ssh `; no credentials, so `credentials_required` is
correctly absent.

**The degraded artifact belongs in code, not prose.** The first draft had `sync.md`
hand-author a counts-free `kb-coverage.md`. That is a genuine second-writer defect:
`renderCoverageMarkdown` (`plugins/soleur/lib/kb-coverage.ts:196-251`) unconditionally
emits `formatProducersMarker(counts)` over fixed `MARKER_FIELDS`, so a counts-free file
is a **different schema by a different writer**; it breaks sync.md's own verification
command (`:289`), breaks the byte-identical determinism constraint (`:274-278`), bypasses
the brand-wording gate (`:267-273`) which is enforced only because the renderer owns the
text, and has none of the two-writer protections (`GENERATED` header refusal,
`O_CREAT|O_EXCL`, symlink refusal) that `sync.md:210-217` applies elsewhere.
**Remedy: give `write-kb-coverage.ts` a `--producer-unreachable <class>` mode** so the
same renderer emits the degraded file with a real marker line. Then the failure path is
testable from bash, and the second writer disappears.

**This is an extension of an existing shape, not a new mechanism.** Verified at
`write-kb-coverage.ts:96-110`: the catch block already calls
`renderCoverageMarkdown(entries, counts, ["coverage producer failed: ${reason}"])` —
the same renderer, real counts from `assessCoverage`, and the degraded reason passed as
the third argument. `--producer-unreachable <class>` reuses that argument exactly, so
the implementation is a new entry point onto a path that already exists and is already
correct. Its inner `catch {}` is deliberately best-effort with a comment explaining that
the stdout marker has already been emitted — preserve that.

**Standalone areas have no durable surface.** `sync.md:264-265` — standalone
`/soleur:sync c4|domain-model|rule-prune` never write `kb-coverage.md`, so their failures
are stdout-only, which this plan's own User-Brand Impact calls the defining defect.
Phase 5 either extends the durable surface to standalone runs or states in `sync.md`
that standalone is stdout-only by design and routes customers to `all`. Silently
exempting three areas from the layer-7 argument is not acceptable.

**Phase 2.9.1 soak — not required.** **Phase 2.9.2 blind surface — applies:** a
self-hosted CLI is uninspectable, hence CI gating over host-side probes, and named
reasons over booleans.

## Implementation Phases

### Phase 0 — BLOCKING: resolve root resolution, and write the failing test

1. **Measure H7** — is `CLAUDE_PLUGIN_ROOT` exported into bash when the agent executes a
   plugin-provided command in a marketplace install? Record the result verbatim.
2. **Bind the remedy** to the decision tree in the Blocking Unknown. Under every outcome,
   no `:-` fallback into a customer-writable path.
3. **Write the decisive test cell first and watch it go red** — customer CWD, var unset,
   decoy planted at **both** `scripts/rule-prune.sh` **and**
   `plugins/soleur/scripts/write-kb-coverage.ts`.
4. Three hard stops — re-derive the 29/21 decomposition; confirm `rule-prune.sh:52`'s
   `$SCRIPT_DIR/..`; confirm `emit_incident` absent from `plugins/soleur/hooks/`.

### Phase 1 — Fix all 29 anchorable sites in the Phase 0 form

One-line change each, no behaviour change, no per-site test. If Phase 0 lands on (B),
this phase reduces to the fail-closed form plus a clear unsupported-surface message.

### Phase 2 — The two shipped TS producers: root form, data root, and runnability

Apply the Phase 0 form. Then **axis 2**: both default their root to `process.cwd()`
(`write-kb-coverage.ts:85`; `generate-c4-from-components.ts:398`) and compose
`join(root, KB_DIR)` — so a subdirectory invocation `mkdirSync`s a *new*
`<subdir>/knowledge-base/` in the customer's repo. Default to the git top level,
preserving the `--root` and positional overrides. Then **axis 4**: probe `command -v bun`
in the precondition, and decide explicitly what `/soleur:sync c4` does when `npx`/network
are unavailable. Add the `--producer-unreachable <class>` mode. Do **not** regress
`write-kb-coverage.ts`'s existing catch-block degraded write.

### Phase 3 — Relocate `domain-model-drift.sh`, sweep citations, fix the standalone contract

1. `git mv` the script and `scripts/lib/domain-model-lib.sh` — **verified single code
   consumer**. If a second appeared, *that consumer moves too*; never source the lib from
   repo root, which would ship the same defect one level down.
2. Axis 2 needs no change (`--repo`, `realpath`, register under `$REPO/`).
3. **Sweep all 13 living citations** — see Files to Edit. Largest churn item.
4. **Wire `init` into the standalone `domain-model` contract** (`sync.md:359-362`).
   Today `init` is only in `all` (`:375`), so standalone dies at `realpath -e` on a fresh
   repo — path fixed, outcome still nothing.

**Blast-radius asymmetry:** `domain-model-lib.sh` has **one** consumer;
`rule-metrics-constants.sh` has **four**, including `.claude/hooks/lib/incidents.sh:48`
walking `../../../scripts/lib/`. The two "identical" moves are not the same size.

### Phase 4 — The guard

`apps/web-platform/test/plugin-root-anchoring.test.ts`, modelled on its 112-line sibling
— not a new ~630-line Python linter family for identical teeth.

- **Scope:** `plugins/soleur/**/*.md` minus `**/archive/**`, `**/test/**`. **State
  explicitly** that shipped `.sh`/`.ts` under `plugins/soleur/**/scripts/` are *not*
  scanned, so axis-3/4 defects (e.g. `worktree-manager.sh:48`) remain uncovered — file
  the remainder rather than implying closure.
- **Predicate: constrain the FALLBACK, not token presence.** `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}`
  *contains* the token and *expands to* the rejected form, so a token-presence regex
  lets every violation be laundered green by wrapping it in `:-`. Pass only a closed set
  of sanctioned forms fixed by Phase 0.
- **Detection:** fenced blocks (indent-aware) **and** inline code spans.
- **Vacuity floor:** assert a floor tied to the expected site count, not merely `> 0` —
  zero-only catches a broken glob, not a broken fence detector.
- **Mutation tests, both:** (a) delete an anchor → red; (b) **replace an anchor with a
  `:-`-wrapped bare path → red**. (b) is the one that proves the predicate.
- **Stated blind spots:** line-continuation forms, `cd plugins/soleur && bash …`, verbs
  outside the recognised set.

### Phase 5 — rule-prune: fail closed in the emitted shell, and de-advertise

1. **Executable halt, not prose.** The threat is a customer's same-named file executing
   under an agent that files issues from parsed sentinels; the control must not be an
   instruction the model may skip. Gate the emitted command on a monorepo sentinel so the
   halt runs regardless of whether the agent read the paragraph.
2. **Cover `:303` too, and first.** `bash scripts/rule-metrics-aggregate.sh` is instructed
   *before* `:306` and is the same collision class. Marking it for the linter is
   documentation, not prevention.
3. **De-advertise** the area in `argument-hint` and `**Valid areas:**` (`sync.md:4,20`)
   and in `/soleur:help`, or a customer is invited into a path that always halts.
4. Specify the halt message literal so it is AC-checkable.
5. Leave `scripts/rule-prune.sh`, `rule-metrics-constants.sh`, `retired-rule-ids.txt`
   and `cron-rule-prune.ts` **untouched** — a move breaks four sites in the production
   cron including the fail-loud sentinel at `cron-rule-prune.ts:117`.

### Phase 6 — New ADR + principles-register row + C4

Per the Architecture Decision section. Check both edge endpoints against the view
include lists before adding the edge.

## Files to Edit

**Anchoring (29 sites / 19 files)** — `plugins/soleur/commands/sync.md`;
`agents/engineering/discovery/agent-finder.md`; `agents/support/community-manager.md`;
and the `SKILL.md`/`SETUP.md` of `cf-token-scope`, `drain-labeled-backlog`, `drain-prs`,
`flag-bootstrap`, `flag-create`, `flag-delete`, `flag-list`, `flag-set-role`,
`frontend-design`, `provision-cloudflare`, `provision-doppler`, `provision-github`,
`provision-hetzner`, `resolve-debt`, `ship`, `user-set-role`.

**Producers** — `plugins/soleur/scripts/write-kb-coverage.ts` (root default ~:85;
`--producer-unreachable` mode); `plugins/soleur/scripts/generate-c4-from-components.ts`
(root default ~:398; toolchain precondition); `plugins/soleur/lib/kb-coverage.ts`
(degraded render path).

**`domain-model-drift.sh` citation sweep (13 living sites)** —
`plugins/soleur/skills/preflight/SKILL.md:1338`; `plugins/soleur/skills/review/SKILL.md:276`;
`.github/workflows/scheduled-domain-model-drift.yml:11,56`;
`plugins/soleur/test/domain-model-init.test.sh:26`;
`plugins/soleur/test/domain-model-headless-append.test.sh:26`;
`tests/commands/test-sync-domain-model.sh:9` (**and rewrite its anchor-blind assertion**);
`scripts/domain-model-drift.test.sh:11`;
`apps/web-platform/server/inngest/functions/cron-domain-model-drift.ts:9` (comment);
`ADR-076-…md:27,28,96`; `ADR-129-…md:22,68`;
`knowledge-base/engineering/architecture/domain-model.md:20`;
`scripts/audit-bot-codeql-coverage.sh:278`; `scripts/learning-retrieval-bench.sh:632`;
`scripts/skill-freshness-aggregate.sh:186`.

*Point-in-time records excluded* — `knowledge-base/project/{learnings,plans,specs,brainstorms}/`
and `**/archive/**` legitimately cite the old path.

**Other** — `sync.md` (rule-prune halt, de-advertisement, standalone `init`,
`bun` precondition); `tests/commands/test-sync-rule-prune.sh`;
`knowledge-base/engineering/architecture/principles-register.md`;
`knowledge-base/engineering/architecture/decisions/ADR-093-…md` (one-line pointer);
`views.c4`, `model.c4`, `model.likec4.json`.

## Files to Create

- `plugins/soleur/scripts/domain-model-drift.sh`, `plugins/soleur/scripts/lib/domain-model-lib.sh` — relocated (`git mv`)
- `apps/web-platform/test/plugin-root-anchoring.test.ts` — the guard
- `tests/commands/test-sync-producer-reachability.sh` — customer-repo simulation
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-…md` — new ADR

**Deliberately NOT touched:** `scripts/rule-prune.sh`, `scripts/lib/rule-metrics-constants.sh`,
`scripts/rule-metrics-aggregate.sh`, `scripts/retired-rule-ids.txt`, `cron-rule-prune.ts`.

## Acceptance Criteria

Every anchored-literal grep uses **`grep -F`** — `$`, `{`, `}` are BRE metacharacters and
a plain `grep -c` returns 0, a false negative in the direction that hides the bug.

### Pre-merge (PR)

1. **The decisive cell passes:** `bash tests/commands/test-sync-producer-reachability.sh`
   green, including customer-CWD + var-unset + decoys at **both**
   `scripts/rule-prune.sh` and `plugins/soleur/scripts/write-kb-coverage.ts`, asserting
   neither decoy executed.
2. **Zero anchorable violations repo-wide** — the Phase 0 inventory filtered to
   `plugins/…` targets returns **0**.
3. Phase 0's measured H7 outcome and the chosen root form are recorded in the PR body,
   and every customer-facing producer uses that form — verified by `grep -F` count per
   file (`sync.md`: c4 = 1, coverage = 2, domain-model = 3; `preflight/SKILL.md` = 1;
   `review/SKILL.md` = 1), asserted per file, never `head -1`.
4. `test -f plugins/soleur/scripts/domain-model-drift.sh && test -f plugins/soleur/scripts/lib/domain-model-lib.sh`; `test -e scripts/domain-model-drift.sh` fails.
5. **Reverse sweep clean:** `grep -rn 'scripts/domain-model-drift\.sh\|scripts/lib/domain-model-lib\.sh' knowledge-base/ .github/ scripts/ plugins/ apps/ tests/ .claude/ | grep -v '/archive/' | grep -vE 'knowledge-base/project/(learnings|plans|specs|brainstorms)/'` returns **0 lines**.
6. `grep -Fc 'plugins/soleur/scripts/domain-model-drift.sh' .github/workflows/scheduled-domain-model-drift.yml` returns ≥ 1 — the production workflow is repointed, not merely broken.
7. `git ls-files scripts/rule-prune.sh scripts/lib/rule-metrics-constants.sh scripts/retired-rule-ids.txt` lists all three; `git diff --stat origin/main -- apps/web-platform/server/inngest/functions/cron-rule-prune.ts` is empty.
8. The rule-prune halt is **executable**: the emitted shell contains the sentinel gate, and `grep -F '<halt message literal>' plugins/soleur/commands/sync.md` returns 1.
9. `rule-prune` no longer appears in `sync.md`'s `argument-hint` or `**Valid areas:**`.
10. Guard green: `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`. *(**Verified at plan time**: `apps/web-platform/vitest.config.ts` `projects[unit]` declares `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` with `environment: "node"`, so this path is collected; the sibling guard already lives in the same directory. Use the in-package `./node_modules/.bin/vitest` form — the repo root declares no `workspaces`, so `npm run -w` aborts.)*
11. **Both** guard mutation tests behave: deleting an anchor → red; replacing an anchor with a `:-`-wrapped bare path → red.
12. Subdirectory invocation: coverage artifact at `<repo-top>/knowledge-base/project/kb-coverage.md`; `test -d <subdir>/knowledge-base` **fails**.
13. `--root` and the positional override still target the given path.
14. `--producer-unreachable <class>` writes a degraded artifact **containing a real `SOLEUR_KB_SYNC_PRODUCERS` line**, so `sync.md:289`'s documented `grep` still succeeds — asserted from bash, not prose.
15. `/soleur:sync domain-model` standalone on a fresh repo produces a register rather than `exit 2`.
16. `bash scripts/domain-model-drift.test.sh` passes against the relocated script.
17. `bash scripts/test-all.sh` green — the authoritative exit gate, which finds orphan suites the touched-file loop never sees.
18. `bash scripts/check-adr-ordinals.sh` passes; the new ADR's ordinal is free across all `origin/*` refs, re-derived immediately before merge.
19. C4: both edge endpoints present in the rendering view's include list; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass; `model.likec4.json` regenerated and staged (`git diff --stat -- model.likec4.json` non-empty).

### Post-merge (operator)

None. Every step is automatable in-session or in CI.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **The remedy is a no-op on the target surface** | The governing risk. Phase 0 is a blocking measurement with a bound decision tree; the decisive test is written first and must go red before it goes green. |
| The guard certifies laundered fallbacks | Predicate constrains the fallback form; mutation test (b) proves it. |
| The `git mv` breaks a citation | AC5 is a reverse grep that must return zero; AC6 pins the production workflow specifically. |
| Fixing 26 unrelated sites widens the diff | Each is one line, no behaviour change, and each is a live customer-facing defect of the same class. The alternative is a 46-entry baseline parking them forever. |
| rule-prune claim over-reaches again | Narrowed to "no input source today" with the two graceful-degradation precedents cited; the product call lives in deferral 4. |
| Axis 3/4 defects remain | Explicitly stated as out of guard scope and filed, rather than implied closed. |

## Alternatives Considered

| Alternative | Rejected because |
| --- | --- |
| Ship `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` as the fix | **Measured no-op on the CLI** — expands to the bug, and keeps the name-collision vector open. This was the issue's proposal and the first two drafts'. |
| Use the git-root fallback instead | CWD-independent, so strictly less bad — but still resolves to `<customer-repo>/plugins/soleur`, which does not exist in a marketplace install. |
| Fix only the 3 sites the issue names | Remediates the reporter, not the shape, and forces a 46-entry baseline parking 26 live defects. |
| Move both scripts as the issue suggests | `rule-prune.sh` derives its data root from its own location; its telemetry input does not exist for customers; and it would break four sites in a production cron. |
| A Python linter + unit suite + shrink-only baseline | ~630 net-new lines vs ~50 for the vitest sibling; the baseline existed only because the draft declined to fix 26 one-line defects. |
| Hand-authored counts-free `kb-coverage.md` | A real second-writer defect — different schema, breaks the documented `grep`, breaks determinism, bypasses the brand-wording gate, no two-writer protections. Replaced by `--producer-unreachable` in the producer. |
| Amend ADR-093 | Different surface, threat model and enforcement machinery; and `check-adr-ordinals.sh` already removes the collision rationale. |
| Declare "no C4 change" | False — the self-hosted CLI topology is genuinely absent from the model. |

## Deferrals — tracking issues to file

1. **Phase 4 (Definition Sync) can never fire for a customer** — its gate requires `plugins/soleur/` in the target repo (`sync.md:587`).
2. **Phase 2 sequential review does not scale** — ~15 findings meant ~15 `AskUserQuestion` round-trips; sanction batching.
3. **`dependencies:` frontmatter needs an inbound-vs-outbound direction rule** — "web-server replays the manifest" is an *inbound* edge; emitted as `dependencies:` it inverts the arrow.
4. **Make `rule-prune` customer-capable** — ship rule-incident telemetry in the payload hook surface (the graceful-degradation precedents show it is possible), or formally scope the area as a monorepo maintenance tool.
5. **The 21 un-anchorable repo-root `scripts/…` sites** — comment on **#6222** with the inventory; note the 29 anchorable sites are now closed so its remaining scope is the `scripts/` class plus `taste-profile-update.sh` siblings.
6. **Axis-4 residual** — the `npx likec4` toolchain dependency; guard scope excluding shipped `.sh`/`.ts`. *(`worktree-manager.sh:48` was pulled OUT of this deferral by BF-2a — it is a `source` on the untrusted-PR path.)*
7. **Standalone areas have no durable failure surface** — if Phase 5 does not extend it, file it.
8. **[P0 — FILED as #7450] Untrusted-PR code execution via the git-root fallback** (BF-1/BF-1a). The 5 redaction-gate sites plus `worktree-manager.sh:48`, plus the falsified safety premise at ADR-093 §Amendment line 55. Higher severity than #7442: these are security controls whose exit code decides whether secrets are emitted, and the trigger is the act of reviewing a contributor PR. Fix before, not with, this plan. *Anchors re-verified against `main` @ `532a6b348` before filing; BF-1's `review/SKILL.md:276` citation is correct — the invocation is an **inline span** inside a numbered list item, which is why a line-start grep misses it. #7450 also records that **#6222's proposed remedy is falsified by this finding** (it would migrate the repo-root class onto the same unsafe git-root anchor), so #6222 is blocked on #7450, not merely adjacent to it.*
9. **Extend `lint-orphan-test-suites.sh`'s glob to `tests/commands/`** so a new suite there cannot silently fail to gate (BF-3). Three suites now depend on someone remembering a `run_suite` line.

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| **T0** | **customer CWD + var UNSET + decoys at `scripts/` and `plugins/soleur/scripts/`** | **The decisive cell.** Red before the fix; green after, with neither decoy executed |
| T1 | `/soleur:sync all` in the monorepo | Unchanged; `kb-coverage.md` byte-identical on an unchanged KB |
| T2 | customer CWD + var set | Producers resolve into the payload |
| T3 | customer CWD, subdirectory | Artifact at repo top level; no second `knowledge-base/` |
| T4 | `bun` absent | Named degraded row via `--producer-unreachable`; not a silent nothing |
| T5 | Guard on the fixed tree | Green, zero violations, no baseline |
| T6 | Guard: anchor deleted / anchor `:-`-laundered | Red in **both** cases |
| T7 | Guard: broken fence detector | Fails the vacuity floor |
| T8 | `/soleur:sync domain-model` standalone, fresh repo | Register produced, not `exit 2` |
| T9 | `/soleur:sync rule-prune` with a decoy present | Executable halt; decoy never runs |

## Sharp Edges

- **`CLAUDE_PLUGIN_ROOT` is unset in a plain CLI session — measure before relying on it.**
  The repo documented this twice and 103 anchored literals were nonetheless written as
  though the fallback were safe. It is safe only for the dogfooding operator standing in
  this monorepo. ADR-093's export invariant is **Concierge-only**.
- **A `:-` fallback launders a violation past a token-presence guard.** The string
  contains `CLAUDE_PLUGIN_ROOT` and expands to the bare path. Guard the fallback form or
  the guard certifies the defect.
- **A test that sets the variable whose absence is the bug is a manufactured pass.**
  Check the matrix for the missing cell before trusting a green suite.
- **The obvious remedy is wrong for one script, and wrong silently.** `rule-prune.sh`
  derives its data root as `$SCRIPT_DIR/..`. A subagent assessed this as *"critically
  portable … move is safe"*, reasoning that `$SCRIPT_DIR`-derivation is inherently
  portable — which inverts the requirement: it must find the **repo** root, not its own
  parent. Verify by direct read, never by delegation.
- **`grep -F` is mandatory for anchored literals.** `${`, `}`, `$` are BRE metacharacters.
- **Reachable ≠ runnable.** `test -r` on a `.ts` passes while a missing `bun` exits 127.
- **A fence scanner anchored at column 0 misses indented fences and all inline spans** —
  and the most dangerous site in this issue is an inline span.
- **Do not write `Closes #6222`.**
- **Check both edge endpoints against the view include lists** before adding a C4 edge,
  or it renders in neither view — the artifact `views.c4`'s own comment warns about.
