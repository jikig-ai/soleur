---
title: "fix: fixture git env adoption, incident-ledger test containment, and the ancestry-walk disagreement"
date: 2026-09-07
slug: fix-fixture-env-ledger-ancestry
branch: feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry
issue: 7853
closes: [7849, 7853, 7854]
lane: cross-domain
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Overview

Three defects sit in the same neighbourhood — test fixtures and git hooks — and ship together in one
worktree and one PR. They share a single root shape: **a boundary that is a property of the runner's
environment was enforced per-file, or a fact was derived twice and the two derivations were allowed
to disagree.**

**#7849** — a fixture git-environment helper exists in TS and Python, and runtime tripwires stand
behind it, but a named set of fixture-creating suites still build their own environment. The tripwire
only stops git being *pointed* elsewhere; it does not stop git *walking up* into an enclosing
repository, does not neutralise the developer's own git config, and does not supply an identity.
Those three properties are open for every suite in the named set, and there is no shell sibling of
the helper at all.

**#7853** — three test suites invoke real emitters without pointing the incident-telemetry writer at
a sandbox, so synthetic deny events land in the operator's live incident ledger. Downstream consumers
read that ledger as a record of what actually happened, and one rolls it into a committed metrics
artifact. The same chain carries a second defect: the aggregator refuses to complete because it
treats every emitted identifier as a claim to be an AGENTS.md rule, when most emitters are hooks
whose rule bodies are tier-gated out of that corpus.

**#7854** — a hook decides whether it can find a Claude process by walking process ancestry; its test
suite gates an end-to-end arm on its own independent walk. Because the hook is spawned as a child of
the suite, its walk starts exactly one process deeper, so under the deeper process tree the
pre-commit runner creates the two walks reach different answers. The suite asserts an outcome that
correctly never happened, and fails the commit gate.

This is the **post-review** revision. A seven-reviewer panel (CTO devex, DHH, Kieran,
code-simplicity, architecture-strategist, spec-flow, and a scoped strong-model consult) cut five
mechanisms from the first draft and found nine defects in what remained. Every cut and every applied
finding is recorded in the Cut List and the Domain Review.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

---

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| #7849, #7853, #7854 all open | `gh issue view <n>` ×3 | **Holds** |
| #7833 process-boundary fix merged | `git log e23eb5bc0` | **Holds** — PR #7840, 2026-09-06 |
| `gdpr-gate-self-test.test.sh` invokes the real gate with no sandbox | read in full | **Holds** |
| `memory-backstop.test.sh` re-derives ancestry independently | read the `E2E=no` block | **Holds** — hand-rolled 8-hop loop, `MAX_WALK_HOPS` not referenced |
| the hook reports `claude_pid_not_found` | read the `discover_claude_pid` call site | **Holds** — `MAX_WALK_HOPS=8` |
| **"8 rows per run, 47 accumulated"** | measured 2026-09-07 | **STALE** — the ledger rotated; 0 `gdpr-gate-*` rows and 0 `lib/auth/foo.ts` survive the merged corpus |
| **"orphan rule_id(s) … : skill-security-scan"** | `bash scripts/rule-metrics-aggregate.sh --dry-run` at the real root | **STALE / 22× understated** — rc=5 with **23** orphan ids, **22 with a live wired emitter** |
| `tests/commands/*.sh` create git fixtures | `git grep '\bgit\b' tests/commands/` | **FALSE** — zero hits |
| `.github/scripts/test/test-*.sh` (11) create fixtures | grep each | **2 of 11** |
| six waived `workspace*` suites | read the #7833 waiver table | **Imprecise** — five, plus `mu1-integration.test.ts` |
| the vitest tripwire is a `setupFiles` entry | read `apps/web-platform/vitest.config.ts` | **FALSE** — it is the `globalSetup:` key |

### Property List (Phase 0.6b)

- **P1** A fixture's `git init` initialises the fixture and its commits land in the fixture — not the
  developer's live repository — **regardless of which runner started the suite**.
- **P2** Git cannot discover an enclosing repository by walking up from a fixture directory.
- **P3** A fixture's bytes and commit identity are unaffected by the developer's own git
  configuration and attributes.
- **P4** A test run cannot append a row to **either resolved** incident-ledger root, including
  through a spawn no call-site grep can see, **and including under direct invocation of a single
  suite** — which is the spelling all three measured leaks occur under.
- **P5** `scripts/rule-metrics-aggregate.sh` completes, so `rule-metrics.json` refreshes and
  `summary.rules_unused_over_8w` is available.
- **P6** A newly wired hook that emits telemetry cannot silently dark the aggregate.
- **P7** `bash .claude/hooks/memory-backstop.test.sh` reports the same verdict about the hook's
  outcome that the hook itself reports, at every process depth.

### Cut List (Phase 0.6b, extended by the review panel)

| Mechanism | Property | Already covered by | Disposition |
|---|---|---|---|
| Tag `skill-security-scan` in AGENTS.md (#7853, option 1) | P5 | — | **CUT.** 1 of 22; blocked by `cq-agents-md-tier-gate` and `B_ALWAYS` at `[WARN]` |
| Raise `MAX_WALK_HOPS` (#7854) | P7 | — | **CUT.** Would make the e2e arm *run* under lefthook, adopting the live session's tree into a memory-capped transient scope mid-commit |
| Match the hook's traversal limit exactly (#7854, option 2) | P7 | — | **CUT — measured not to work.** The hook is a child of the suite; matching the *limit* leaves the *origin* one process apart |
| A tenth prefix-exemption stanza | P5 | nine existing | **CUT.** Each was added after a hook broke a run |
| A `SOLEUR_IN_TEST_RUN` marker exported by the **entry points** | P4 | — | **CUT.** All three leaks occur under direct suite invocation, where no entry point runs |
| **The same marker exported by the *chokepoints*, plus a refusal branch in `emit_incident`** | P4 | **the same chokepoints exporting `INCIDENTS_REPO_ROOT` directly** | **CUT (DHH P0-2, code-simplicity #6, strong-model consult — independent convergence).** If the chokepoint is the right place for the marker, the marker was never needed. Identical failure mode (a scrubbed env loses either), so it buys no coverage the redirect does not, and it puts test-awareness inside production hook code whose failure mode is silently darkened real telemetry. **Also falsified on its own terms** (spec-flow P0-1): its justification claimed the coverage guard "requires every shell suite to source `test-helpers.sh`" — measured, the guard greps for `test-incident-sandbox.sh`, and only 6 of 46 `.claude/hooks/*.test.sh`, 2 of 84 `tests/**`, and 0 of 13 `.github/scripts/test/` suites source `test-helpers.sh` at all |
| **A hand-maintained `hook-telemetry-rule-ids.txt` registry** | P5, P6 | **the AGENTS.md section-prefix invariant**, already stated in the aggregator's own `te-` comment | **CUT (DHH P0-1, code-simplicity #8).** Measured: **all 105** `[id: …]` tags carry one of `hr\|wg\|cq\|rf\|pdr\|cm`, zero exceptions — one predicate replaces nine stanzas *and* the registry. Independently killed by Kieran P0-5: several emitters build ids at runtime (`hook-input-${reason_key}`, `"$MATCHED_RULE"`, `"$_bypass_rid"`, `net-issue-flow-mandated-filing--<n>`), so an exact-id registry enumerates an open set — the shape this plan rejects the tenth stanza for |
| **An emitter↔registry drift lint** | P6 | — | **CUT.** Dies with the registry; under the predicate P6 holds **by construction**. Also unbuildable as drafted (Kieran P0-4): **8 hooks** emit through a bare-token `emit <id>` wrapper alias, so an `emit_incident "<literal>"` grep would red on its own registry the day it landed |
| **A committed quarantine script plus its own suite** | **none** | — | **CUT (DHH P1-2, code-simplicity #7).** Satisfies no property; the data is gitignored, operator-local and self-expiring (measured: the rows #7853 filed against rotated to zero unaided) |
| **A new declared `test-entry-points.txt`** | P1 at `run-all.sh` | **the parity test's existing scrub loop** | **CUT (code-simplicity #2).** A `.txt` rots identically — neither detects a *newly added* entry point. The existing loop already carries a floor |
| The `git_fixture` shell wrapper | — | the builder's own `GIT_CONFIG_NOSYSTEM` + `GIT_CONFIG_GLOBAL=/dev/null` | **CUT.** Its only job was `-c commit.gpgsign=false`, defending a config the line above made unreachable |
| A fourth parity derivation | P2, P3 | the existing parity test | **CUT.** One array read by both consumers keeps the shell side a single derivation. *(Kieran P1-6: the parity test already has **four** extractors and **three** comparisons — the cut is right, the draft's arithmetic was not.)* |
| A new shell fixture-env builder itself | P2, P3 in shell | **nothing** — `test-helpers.sh` is a tripwire, not a builder | **KEPT** |

### Consolidated findings

**The helper's real value proposition.** `gitFixtureEnv()` sets a discovery ceiling,
`GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_ATTR_NOSYSTEM`, an `XDG_CONFIG_HOME`
redirect and a synthesized identity. The tripwire sets none of those. **P2 and P3 are currently
open** for the named set, not merely defended in depth.

**Runtime chokepoints (measured), five — and none is universal.** Root `bunfig.toml` `preload`,
`plugins/soleur/bunfig.toml` `preload`, `apps/web-platform/vitest.config.ts`'s `globalSetup:` key
(**not** `setupFiles`), `test-helpers.sh`'s prelude, and `tests/conftest.py`. Their measured reach:
bun resolves `bunfig.toml` from the **invocation cwd**, so `bun test` from a third directory gets no
preload; `tests/conftest.py` is not loaded by `python3 -m unittest` and reaches suites only via a
`_git_fixture_env` import, which `tests/scripts/test_rule_id_regex_parity.py` does not make; and only
6 of 46 `.claude/hooks/*.test.sh` source `test-helpers.sh`. **The chokepoint set is a real
containment layer for the suites that pass through it and is not a universal one** — this plan states
the residual rather than claiming coverage it does not have, and Guard 3 counts and prints the
outside set.

**The entry-point set is enumerated twice, both hardcoded.** `hook-git-env-coverage.test.sh` parses
`lefthook.yml` `run:` commands plus one hardcoded `scripts/test-all.sh` block;
`git-env-list-parity.test.sh` iterates a hardcoded loop over `lefthook.yml`, `scripts/test-all.sh`
and `scripts/hooks/pre-push`. **`.github/scripts/test/run-all.sh` is in neither and carries no
scrub** — and neither are `.github/workflows/skill-security-scan-corpus.yml`'s `bun test` step nor
`tenant-integration.yml`'s `npm run test:ci` step (spec-flow P1-5).

**The ledger's three live leaks, and why the guard missed them.**
`.claude/hooks/incident-sandbox-coverage.test.sh` is well built — positive control, a population
floor, an explicit "zero, not a baseline" stance, a documented rejection of the
mentions-the-variable proxy. Its defect is purely **assembly**: `for t in "$HERE"/*.test.sh`. All its
members are clean; all three leaks (`test/pre-merge-rebase.test.ts` via `pre-merge-rebase.sh`,
`plugins/soleur/test/gdpr-gate.test.ts` and `gdpr-gate-self-test.test.sh` via `gdpr-gate.sh`) are
outside that directory.

**There are TWO ledger sinks** (Kieran P0-1, verified). `_incidents_repo_root()` resolves off
`BASH_SOURCE`; `gdpr-gate.sh` resolves its lib root off `CLAUDE_PROJECT_DIR` with a five-level walk
as fallback. From a worktree the two leaks land in **different files**. A containment AC naming one
root would have read a zero delta for the 143-row source *for the wrong reason*.

**And in a worktree the `BASH_SOURCE` sink does not exist yet** (spec-flow P0-2). This worktree has
no `.claude/.rule-incidents.jsonl`, so `wc -l < <that path>` errors and leaves the "before" value
empty — the AC arithmetic is undefined and a total regression passes. **The failure signature in a
worktree is a file appearing where none existed**, so containment must assert existence, not only
line count, and must derive the path the way `emit_incident` does.

**An empty `INCIDENTS_REPO_ROOT` reads as unset** (spec-flow P0-3). `_incidents_repo_root()` gates on
`[[ -n … ]]`, and `.github/scripts/test/run-all.sh` carries **no `set` line at all** — so a failing
`mktemp -d` yields `""`, indistinguishable from unset, and the whole battery writes the operator's
real ledger with no signal. The redirect must be asserted non-empty and absolute, and must abort the
entry point on failure — the same fail-loud posture `fixtureCeiling()` already takes.

**The 143 fabricated rows** are all `test/pre-merge-rebase.test.ts` driving `pre-merge-rebase.sh`'s
`rf-never-skip-qa-review-before-merging` and `hr-when-a-command-exits-non-zero-or-prints` deny paths
with `$CMD` verbatim.

**The orphan gate rejects hook telemetry as a class, and one predicate fixes it.** 23 orphan ids, 22
with a live wired emitter. The gate carries nine exemption stanzas — eight `startswith()` globs and
one exact-literal pair — every one added after a hook broke a run. But the file already states the
invariant that makes them unnecessary, in the `te-` stanza's own comment: *"AGENTS.md section
prefixes are hr|wg|cq|rf|pdr|cm."* **Measured: all 105 `[id: …]` tags carry one, zero exceptions.**
So the gate can ask "does this id *claim* to be a corpus rule?" instead of "is it on a list of things
that aren't". A renamed or removed corpus rule keeps its prefix and is still caught; hook telemetry
is structurally out of scope. That is *more* teeth than nine globs, which exempt every future id
under a prefix unreviewed.

**Five ids need handling** — hook telemetry mis-prefixed `cq-`: `cq-docs-cli-verification`,
`cq-never-skip-hooks`, `cq-when-lefthook-hangs-in-a-worktree-60s`,
`cq-before-calling-mcp-pencil-open-document`, `cq-pencil-collapse-auto-recover`.

**A sixth copy of the prefix set exists, pinned by an assertion that greps the aggregator** (Kieran
P0-3, verified). `rule-incident-marker-capture.sh`'s `_valid_rule()` mirrors the exemptions in a
`case` list, and its suite pins the mirror with `grep -qF 'startswith("<p>")'` against the aggregator
source. Deleting the stanzas reddens it deterministically. Under the new predicate both *simplify*:
`_valid_rule()` becomes "a real AGENTS id, or an id carrying no section prefix", and the companion
assertion becomes a shared-regex check — **one invariant in two places instead of six mirrored
prefixes in two places.**

**The redirect mechanism is proven.** Measured this session: the real `gdpr-gate.sh` under
`INCIDENTS_REPO_ROOT="$SB"` wrote 2 rows into `$SB` and left the real ledger unchanged.

**The one-hop delta is measured.** A script walking from its own `$$` sees `1=bash 2=bash 3=claude`;
a child sees `1=bash 2=bash 3=bash 4=claude`. Both walks cap at 8, so where claude sits at suite-hop
8 the hook needs hop 9. The issue's tree omits the `.git/hooks/pre-commit` level, which is why it
appears to fit.

**The hook has eleven decline reasons, not one** (architecture-strategist P1-8, verified):
`disabled`, `no_busctl`, `no_jq`, `no_bus` ×2, `cap_out_of_range`, `claude_pid_not_found`,
`no_terminal_scope`, `concurrent_apply`, plus `pid_reuse_disambiguated` and `adoption_unverified`.
Gating the e2e skip on one reason string still fails the commit gate for the documented opt-out
(`SOLEUR_DISABLE_MEMORY_BACKSTOP=1`) and for `concurrent_apply`, which is a race. **Gate on
`outcome != "applied"` and print the reason verbatim** — strictly closer to the plan's own property.

**Invoking the hook unconditionally is safe for cgroup state but widens one adoption surface**
(architecture-strategist). All six mutating call sites sit below the identity gate, and CI has no
user bus so the live arm skips entirely. But `discover_claude_pid`'s second predicate reads the
inherited `CLAUDE_CODE_EXECPATH`, which under an npm-global install resolves to a generic interpreter
— on such a box *any* `node` ancestor within 8 hops matches, and the hook would scope it and up to
256 descendants. The suite must invoke with `CLAUDE_CODE_EXECPATH` unset and `CLAUDE_PROJECT_DIR`
pointed at scratch (which also stops `_maybe_never_worked` writing its nag stamp into the real
checkout), and the fixture must pin a negative case for that predicate.

**`kind` is dead schema.** `emit_incident` writes it on every row; the aggregator's comments say
three times it "never reads `.kind`"; every live *and archived* row is `rule_event`. It cannot
classify history even if emitters started setting it. The discriminator is the prefix.

**`memory-backstop-mutation-battery.sh` exists and is registered in no runner.** The `MAX_WALK_HOPS`
mutation row belongs there rather than as a `/work`-time artifact with no durable owner.

### Applicable institutional learnings

| File | Rule it carries |
|---|---|
| `knowledge-base/engineering/operations/post-mortems/fixture-git-env-live-repo-write-postmortem.md` | The write boundary is the **environment**, not the operand |
| `knowledge-base/project/learnings/2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md` | **Two guards from one PR can make each other vacuous.** Sweep by shape, never a name list |
| `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` | The cheapest edit that breaks the property the guard NAMES while leaving it green. Floors absolute, ratchet upward |
| `knowledge-base/project/learnings/2026-09-04-a-learning-two-working-copies-and-it-still-got-re-derived-wrong.md` | A helper re-derived per file will be re-derived wrongly. **Only an import or a lint holds** |
| `knowledge-base/project/learnings/2026-09-04-three-review-rounds-each-found-defects-in-the-last-rounds-fixes.md` | **Delete, do not patch** — applied to nine stanzas, one walk, and five of this plan's own mechanisms |
| `knowledge-base/project/learnings/2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md` | An aggregator's gate can check structure while missing the property |
| `knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md` | Process-tree adoption into a memory-capped scope must not fire from inside a commit |

### Skill-description budget (Phase 1.8)

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate or finalized. **Skipped.**

---

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured 2026-09-07) | Plan response |
|---|---|---|
| #7853: "8 rows/run, 47 accumulated" | 0 `gdpr-gate-*` survive; **143** `gh pr merge 123` rows do, from a different suite | Fix all three leaks; quantify against 143 |
| #7853: blocked by `skill-security-scan` | 23 orphans, 22 with live emitters | One predicate |
| #7849: "four `tests/**` shell suites" | `tests/commands/*.sh` spawn no git; the four are under `tests/hooks/` and `tests/scripts/` | Corrected set |
| #7849: `.github/scripts/test/test-*.sh` | 2 of 11 create a fixture | Convert those two |
| #7849: vitest `setupFiles` | the `globalSetup:` key | Cite the key |
| Draft: `pre-merge-rebase.test.ts` covers "3 of 9 location vars" | **Wrong** (Kieran P2) — its `GIT_ENV` sets the *config* family plus a ceiling, none of which is in the 9-var location family | Correct the characterisation |
| Draft: one ledger sink | **Two**, and in a worktree the `BASH_SOURCE` one does not exist yet | Derive the path; assert existence and both roots |
| Draft: "nine prefix globs" | Eight globs plus one exact-literal pair | State accurately |
| Draft Sharp Edge: register with the literal `run_suite` (with its trailing space) token | **Inverted** (Kieran P1-8) — the linter requires `run_suite "<label>" bash <path>`, path last | Correct it |
| Draft: gate the e2e skip on `claude_pid_not_found` | **11 decline reasons**; the documented opt-out and `concurrent_apply` would still fail the commit gate | Gate on `outcome != "applied"` |
| Draft: the chokepoints cover every shell suite | 6 of 46 `.claude/hooks/*.test.sh` source `test-helpers.sh`; 0 of 13 `.github/scripts/test/` do | State the residual; count and print the outside set |

---

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --limit 200` (63 open), matched per planned
path with a standalone `jq --arg`.

- **#7208** — *memory backstop (#7166): post-merge hardening* — names both memory-backstop files.
  **Disposition: acknowledge.** #7208 is a cgroup-behaviour backlog; #7854 is a test-harness
  derivation defect. This plan changes only the suite. #7208 stays open, with a comment recording the
  rewrite so its next picker does not re-derive it.

No other overlap.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a pre-commit gate that either fails on an environment
fact (unchanged #7854 symptom) or silently skips the memory-backstop end-to-end arm on every run — so
a regression in session memory-capping ships unnoticed and the box is exposed to the
resource-exhaustion class again. On the #7849 arm, a wrong scrub means a test run rewrites the
operator's live branch tip. **A specific new exposure this plan introduces and bounds:** Phase 5
makes the suite invoke the real hook unconditionally, and on a box where `CLAUDE_CODE_EXECPATH`
resolves to a generic interpreter the hook could scope a `node` ancestor and its descendants — hence
the mandatory `CLAUDE_CODE_EXECPATH`-unset invocation and its negative fixture case.

**If this leaks, the user's workflow is exposed via:** the incident ledger carries `command_snippet`
— raw operator commands, capped at 1024 chars. This plan adds **no** new persistence location for
that data (the committed quarantine file was cut); it adds one temp-directory sink per test run.
Nothing is committed, transmitted, or widened in audience.

**Brand-survival threshold:** `none`.
*Reason (sensitive-path scope-out bullet):* the diff touches no schema, migration, auth flow, API
route or `.sql` file; every changed surface is a test harness, a git hook, or a local telemetry sink
whose blast radius is the operator's own workstation.

---

## Implementation Phases

### Phase 0 — Preconditions (measure before changing)

0.1 Re-run the aggregator read-only at the real root; then **re-derive the orphan set under the
proposed predicate** over the raw merged corpus. The panel's independent derivation gave 30 orphans
before any filter and 5 after; this plan's gave 23 before. The two are taken at different pipeline
points against a ledger that grows during a session. **Reconcile before acting; proceed on neither
number alone.**

0.2 Record fabricated-row counts by the two fixture markers. Baseline: **143** / **0**.

0.3 Confirm the one-hop depth delta (`measurements.md` M-4).

0.4 Confirm the five chokepoint registrations at their **content anchors**, and measure each one's
reach: how many `.claude/hooks/*.test.sh`, `tests/**`, and `.github/scripts/test/*.sh` suites pass
through one. Planning-time reads: 6/46, 2/84, 0/13. These numbers become Guard 3's printed
outside-set floor.

0.5 **Probe whether an env export in vitest `globalSetup` reaches worker children**, under both
`pool: "forks"` (default) and `WEBPLAT_TEST_USE_THREADS=1`. `globalSetup` was chosen as an
*assertion* point; using it as an *export* point is a different property. Fallback is `test.env` in
`vitest.config.ts` — **not** `setupFiles`, which the config's own comment measured at 1114
executions.

0.6 Read `git-env-list-parity.test.sh` in full: four extractors, three `cmp_set` comparisons, and a
hardcoded scrub loop over three files.

0.7 Establish `cq-rule-ids-are-immutable`'s scope: does it bind hook-telemetry *emitter literals*, or
only `[id: …]` tags in AGENTS.md? This decides whether Phase 4.5 renames five ids or exempts them.

0.8 Enumerate every `.github/workflows/**` `run:` step matching `hook-git-env-coverage.test.sh`'s
`RUNNER_RE`. Known: `skill-security-scan-corpus.yml`'s `bun test` and `tenant-integration.yml`'s
`npm run test:ci`, neither in any assembly.

### Phase 1 — The shell fixture chokepoint (contract change; precedes Phase 2)

1.1 **Create `plugins/soleur/test/lib/git-fixture-env.sh`.** One sourceable file, no assertion
framework, no `set -euo pipefail` imposed on the caller. It declares **one** `GIT_LOCATION_VARS`
array read by both consumers: the Guard-3 tripwire loop moved verbatim from `test-helpers.sh`
(including the `SOLEUR_GIT_TRIPWIRE_ALLOW=1` escape and its announcement, byte-for-byte), and
`git_fixture_env <fixture_dir>`, which *exports* the set `gitFixtureEnv()` constructs —
`GIT_CEILING_DIRECTORIES` (the fixture's realpath'd **parent**, refusing `/`, non-absolute, and any
path containing `:`), `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_ATTR_NOSYSTEM=1`,
`XDG_CONFIG_HOME=<fixture>/.soleur-fixture-xdg`, `GIT_TERMINAL_PROMPT=0`, and the synthesized
identity.

  **One array, not two.** **No `git_fixture` wrapper** — `GIT_CONFIG_NOSYSTEM` +
  `GIT_CONFIG_GLOBAL=/dev/null` already make `commit.gpgsign` unreachable; suites keep calling plain
  `git -C "$dir"`, one calling convention.

  **The failure path must not silently degrade.** Because the helper must not impose `set -e` on its
  caller, a bare `return 1` at a call site that does not check it leaves the suite running `git` with
  a partial or absent env — the exact silent degradation 1.1 exists to prevent. Two rules, both
  asserted: **the helper exports nothing until the ceiling validates** (no partial export), and
  **every call site is `git_fixture_env "$d" || { …; exit 1; }`**.

1.1b **Create `plugins/soleur/test/git-fixture-env-shell.test.sh`** — the helper's own suite, and the
producer for AC2 and Guard 1 rows M3/M4. Register it in `scripts/test-all.sh`.

1.2 **`test-helpers.sh` sources the new file** instead of inlining the tripwire.

1.3 **Repoint the parity test's `shell_list()`** at `lib/git-fixture-env.sh`, matching the **array
literal** instead of the `for` loop. Three comparisons, unchanged. *(Fail-loud: an un-repointed
extractor returns empty and trips the existing per-derivation floor.)*

1.4 **Add the missing entry points to the parity test's existing scrub loop** —
`.github/scripts/test/run-all.sh` plus every workflow step Phase 0.8 found — and add an **entry-point
count floor** so shortening the list reddens. `hook-git-env-coverage.test.sh`'s N2 block stays as-is;
the draft's "ratchet `RUN_LINES`" instruction was incoherent (that counter measures *lefthook* `run:`
commands, which this change does not alter) and is dropped.

1.5 The five `git-worktree/test/*.test.sh` inline copies stay inline; re-pointing is unblocked by 1.1
but deferred for review size.

### Phase 2 — Adopt the helpers at the named suites (#7849)

2.1 **`test/pre-merge-rebase.test.ts`** — replace the hand-rolled `GIT_ENV` with `gitFixtureEnv()`.
Its current env sets the *config* family plus a ceiling and destructures three location vars out of
`process.env`; the other six location vars, the attributes/XDG hardening and the identity are absent.
Also a Phase 3 target — one commit.

2.2 **The zero-env vitest population under `apps/web-platform/test/**`,** scoped as a property:
*every vitest suite that spawns `git` passes an env built by `gitFixtureEnv()`*. Members:
`cc-reprovision-git-discriminator.test.ts`, `worktree-config-seed.test.ts`,
`git-config-atomic.test.ts`, `server/inngest/rule-body-gate-recursion-invariant.test.ts` (its `git()`
helper **and** its transitive `python3` spawn), `helpers/context-queries-fixture.ts` **and** the
sibling inline site in `context-queries-hook.test.ts`, and `server/inngest/cron-safe-commit.test.ts`
(its `tgit()` sets identity/date pins only; its two bare `git init` calls carry no options object).

  **`apps/web-platform/server/worktree-config-seed.ts` is production code** — scope-out with a
  tracking issue.

2.3 **The four `tests/**` shell suites** source the helper and call `git_fixture_env` (with the `||`
guard) before their first `git`: `tests/hooks/test_hook_emissions.sh` (**delete** its partial 3-var
unset), `tests/hooks/test_openhands_guardrails.sh`, `tests/scripts/test-weakness-miner.sh`
(**delete** its 9-var scrub — a scrub, not the fail-loud prelude, and no ceiling/config/identity),
`tests/scripts/test-lint-supabase-deprecated-endpoints.sh`.

  **Every conversion is paired with a ledger check in the same commit** (spec-flow P1-1). Sourcing
  the helper brings a suite inside a chokepoint, so its emitter invocations are redirected;
  `tests/hooks/test_hook_emissions.sh` references `emit_incident` and sets `INCIDENTS_REPO_ROOT`
  zero times, so its assertions about emitted rows must be re-pointed at the sandbox rather than
  silently changing sink. For each converted suite: grep for emitter invocation and reconcile.

2.4 **The two `.github/scripts/test/` fixture suites** — `test-check-settings-integrity.sh` and
`test-infra-suite-registration-mutations.sh`.

2.5 **`apps/web-platform/infra/workspaces-luks-loopback.test.sh`** — route `mk_repo()` through
`git_fixture_env`. It runs with elevated privileges: resolve the helper from a repo root computed
once at the top and assert it absolute and non-degenerate before sourcing.

2.6 **`.github/scripts/test/run-all.sh`** gets the 9-variable `unset` in the same shell before the
suite loop, **as the first line-start-anchored `unset GIT_` in the file** — both `scrub_list`
(`head -1`) and the N2 regex take the first such line.

2.7 **Create a static adoption guard** (spec-flow P0-6). Phase 2 otherwise has no AC and no guard:
AC3 and the typecheck both stay green if Phase 2 is skipped entirely, and Guard 1's M6 row cites a
coverage assertion nothing builds — the same unratcheted-scrub class this plan names for
`run-all.sh`, applied to ~13 files. Two derivations, each with a non-empty floor: (a) files spawning
git (`execFileSync`/`spawnSync`/`Bun.spawn`/a bare `git` invocation) under `apps/web-platform/test/**`,
`tests/**` and `.github/scripts/test/**`; (b) files calling `gitFixtureEnv`/`git_fixture_env`. Assert
the difference set is empty **and printed**.

### Phase 3 — Ledger containment, one mechanism (#7853, write-boundary half)

3.1 **Fix the three leaks**, exporting the sandbox rather than setting it per call, per
`test-incident-sandbox.sh`'s contract: `gdpr-gate-self-test.test.sh` (create a `mktemp -d`, export
before Case A), `gdpr-gate.test.ts` (a `beforeAll` **and** the `spawnSync` env),
`test/pre-merge-rebase.test.ts` (the shared `Bun.spawn` env object, not per case).

3.2 **The five chokepoints export the sandbox root,** fail-loud:

```bash
sb="${INCIDENTS_REPO_ROOT:-$(mktemp -d)}"
case "$sb" in /?*) ;; *) <abort with a named message> ;; esac
export INCIDENTS_REPO_ROOT="$sb"
```

  Non-empty and absolute are both asserted, and failure **aborts the entry point** — `run-all.sh`
  carries no `set` line at all, so an unguarded `mktemp` failure yields `""`, which
  `_incidents_repo_root()` reads as unset and silently restores the real sink. `emit_incident`
  already `mkdir -p`s the `.claude/` parent, so the root needs no pre-seeding.

  **This is the whole containment mechanism.** It reaches a directly-invoked suite — the spelling all
  three leaks occur under — needs no branch in production hook code, and so carries no risk of
  darkening real telemetry. `scripts/test-all.sh` and `.github/scripts/test/run-all.sh` keep the same
  export as belt.

  **State the residual honestly.** The chokepoints do not cover every suite: `bun test` from a third
  cwd loads no preload, `python3 -m unittest` reaches `conftest.py` only through a
  `_git_fixture_env` import that one python suite does not make, and only 6 of 46
  `.claude/hooks/*.test.sh` source `test-helpers.sh`. Guard 3 counts and prints the outside set with
  a ratcheted floor; that set is what Phase 2's conversions and the deferral issues shrink.

  **Verify the redirect survives the fixture env builders.** A hermetic env builder is precisely what
  strips a containment variable, and fixture repos are where hooks are exercised. `gitCleanEnv()`
  sweeps by `GIT_` prefix and carries every other variable through — assert that explicitly rather
  than relying on the reading.

  **Do not break the aggregator's own suites**: `tests/scripts/test-rule-metrics-aggregate.sh` and
  `scripts/rule-metrics-aggregate.test.sh` set the root per call and override the default; check
  `tests/hooks/test_incidents.sh` too, whose isolation is by lib-copy.

3.3 **Widen `incident-sandbox-coverage.test.sh`'s ASSEMBLY.** Keep every existing case, its positive
control and its floor. Derive structurally:

1. **Emitter set** = every file sourcing `.claude/hooks/lib/incidents.sh` **or** defining
   `emit_incident` (this reaches the Python sibling a filename-paired enumeration already missed).
2. **Suite set** = every test file that **invokes** an emitter — `bash …<emitter>`,
   `spawn*([… "<emitter>"`, `execFile*` — **not** every file that *mentions* one. A name-mention
   derivation reintroduces the exact proxy this guard's own header rejects, and self-includes the
   guard, `tests/hooks/test_incidents.sh` and `memory-backstop.test.sh` (spec-flow P1-9).
3. Assert each member sources `test-incident-sandbox.sh`, **or** reaches a chokepoint, **or** sets
   `INCIDENTS_REPO_ROOT` at every invocation. `.claude/hooks/` members keep the stronger requirement.
4. **Print the outside set** — suites reaching an emitter through neither — with a ratcheted floor.

  **A non-empty floor on EACH derivation.** Once 3.2 lands a runtime leak stops being observable, so
  a silently-empty derivation has nothing else to reveal it and this static guard is the only
  remaining signal. Precedent: the parity test's per-derivation check and the `RUN_LINES` floor.

  **State hop 2's known false negative in the header:** a suite reaching an emitter through a
  variable, a settings path or `lefthook.yml` is not in the population. The floor bounds it; the
  comment stops the next such case reading as a guard bug.

3.4 **Add the python arm** (spec-flow P1-4): assert every `tests/**/*.py` test file imports
`_git_fixture_env`, with a floor. `conftest.py` is not loaded by `python3 -m unittest`, so the import
*is* the chokepoint.

3.5 **Clean up the already-written rows, reversibly and in-session.** No committed script: copy the
active ledger to `.claude/.rule-incidents-synthetic-quarantine.jsonl`, `grep -v` the two fixture
markers from the active file, and record before/after counts in the PR body. **Re-measure
immediately before and after the removal in the same command** — a concurrent hook can append
between a dry run and an apply, so a count recorded earlier will not reconcile. **Archives are left
untouched.** Deleting outright is rejected: a fix for a write-boundary defect must not itself be an
unannounced destructive write to operator telemetry. This **is** an operator-state write executed
in-session — say so in the PR body with the counts rather than letting `Post-merge: None` imply
nothing was touched.

### Phase 4 — The orphan gate's discriminator (#7853, telemetry-taxonomy half)

4.1 Reconcile Phase 0.1's two derivations and pin the surviving set.

4.2 **Replace all nine exemption stanzas with one predicate** — keep only ids that *claim* to be
corpus rules:

```jq
map(select(test("^(hr|wg|cq|rf|pdr|cm)-")))
```

Preserve the behaviours the file's comments call load-bearing: `select(.rule_id != null)` stays
*before* the reduce; the jq program is single-quoted, so **no apostrophes** in any comment added
inside it; and the `hook_input_fault_count` **LOAD-BEARING PAIR** — that exclusion's replacement
surface is `summary.hook_input_fault_count`, which must not be removed independently.

4.3 **Anything still orphan rejects with rc=5, unchanged.**

4.4 **Update the sixth copy and its companion assertion.** `_valid_rule()` becomes "a real AGENTS id,
or an id carrying no section prefix"; the companion assertion becomes a shared-regex check.

4.5 **Handle the five mis-prefixed hook ids** per Phase 0.7: rename the emitter literals where the
immutability rule permits — making the invariant *true* rather than carving around it — and
exact-exempt only those it genuinely binds. Record which path was taken and why.

4.6 Regenerate `rule-metrics.json` **as its own commit**, with the `--dry-run` output diffed against
the committed file in the PR body.

  **P6 is now structural:** a new hook emitting a non-section-prefixed id cannot dark the aggregate.

### Phase 5 — The ancestry-walk disagreement (#7854)

5.1 **Delete the independent 8-hop walk** and the `E2E` variable.

5.2 **Rewrite the rationale comment — do not merely drop it.** It argues the independence is a
feature; removed silently, the next reader restores the walk. Replace with the measured reason: *the
hook runs as a child of this suite, so an independent walk starts one process shallower and the two
can always disagree by one hop; the property under test is agreement with the hook's own verdict at
the hook's real depth, not independent reachability.*

5.3 **Restructure so the hook runs unconditionally and only the ADOPTION assertions are gated.**
Snapshot → invoke → snapshot → read the log line. Assert **unconditionally** that the hook exits 0
and leaks no busctl job object path (both legitimate on the skip path — a **coverage gain**). Then:

- **Gate on `outcome != "applied"`, not on one reason string.** The hook has eleven decline reasons;
  gating on `claude_pid_not_found` alone still fails the commit gate for the documented opt-out
  `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` and for `concurrent_apply`, a race rather than a defect. Print
  the reason verbatim in the skip message plus the remedy: *"run the suite standalone to exercise
  this arm; the hook runs one process deeper than this suite, so at lefthook depth claude sits
  outside its 8-hop limit."*
- **Invoke with `CLAUDE_PROJECT_DIR` pointed at scratch and `CLAUDE_CODE_EXECPATH` unset.** The
  scratch project dir stops `_maybe_never_worked` writing its one-shot nag stamp into the real
  checkout; unsetting the execpath removes the one predicate that, under an npm-global install
  resolving to a generic interpreter, would let the hook scope a `node` ancestor and up to 256
  descendants on a box with a shallower tree than the author's.

  **This is Option 1; Option 2 is rejected on measurement.** The comment defends independence so the
  gate "cannot be satisfied by the same code it is gating" — sound for a *correctness* gate. This is
  an *environment precondition*, and the operative fact is "will the hook, run from where this suite
  runs it, apply?" — which only the hook can answer, because it depends on the hook's own starting
  depth. Matching the traversal limit leaves the walks one process apart.

5.4 **Add the fixture cases** to the synthetic `/proc` builder: a 10-process chain returning non-zero
with claude at hop 9 and zero at hop 8 (pinning `MAX_WALK_HOPS=8` as intentional), **plus a negative
case** pinning that a generic-interpreter `CLAUDE_CODE_EXECPATH` is not sufficient for adoption — the
predicate no fixture currently covers.

5.5 **Do not raise `MAX_WALK_HOPS`.**

5.6 **Register `MAX_WALK_HOPS` in `memory-backstop-mutation-battery.sh`** — it exists, is registered
in no runner, and is the durable owner for AC14's row. A mutation recorded once in a PR body and
never re-run is the shape this plan's cited learnings reject.

5.7 Add a one-line note to issue #7208.

### Phase 6 — Documentation, ADR, C4 and deferrals

6.1 Write `ADR-204` (ordinal **provisional**), one decision.
6.2 Add the one-clause C4 amendment to the Hook Engine container description; run
`c4-code-syntax.test.ts` and `c4-render.test.ts`.
6.3 Correct the false comment in `tests/hooks/test_incidents.sh`.
6.4 File the deferral issues.

---

## Files to Edit

`plugins/soleur/test/test-helpers.sh` · `plugins/soleur/test/git-env-list-parity.test.sh` ·
`test/pre-merge-rebase.test.ts` · `apps/web-platform/test/cc-reprovision-git-discriminator.test.ts` ·
`apps/web-platform/test/worktree-config-seed.test.ts` ·
`apps/web-platform/test/git-config-atomic.test.ts` ·
`apps/web-platform/test/server/inngest/rule-body-gate-recursion-invariant.test.ts` ·
`apps/web-platform/test/server/inngest/cron-safe-commit.test.ts` ·
`apps/web-platform/test/helpers/context-queries-fixture.ts` ·
`apps/web-platform/test/context-queries-hook.test.ts` · `tests/hooks/test_hook_emissions.sh` ·
`tests/hooks/test_openhands_guardrails.sh` · `tests/scripts/test-weakness-miner.sh` ·
`tests/scripts/test-lint-supabase-deprecated-endpoints.sh` ·
`.github/scripts/test/test-check-settings-integrity.sh` ·
`.github/scripts/test/test-infra-suite-registration-mutations.sh` ·
`apps/web-platform/infra/workspaces-luks-loopback.test.sh` · `.github/scripts/test/run-all.sh` ·
`scripts/test-all.sh` (belt export + two suite registrations) ·
`plugins/soleur/test/gdpr-gate-self-test.test.sh` · `plugins/soleur/test/gdpr-gate.test.ts` ·
the five chokepoint files (`bunfig.toml` and `plugins/soleur/bunfig.toml` preload targets,
`apps/web-platform`'s `globalSetup:` target or `test.env` per Phase 0.5,
`plugins/soleur/test/lib/git-fixture-env.sh`, `tests/conftest.py`) ·
`.claude/hooks/incident-sandbox-coverage.test.sh` · `scripts/rule-metrics-aggregate.sh` ·
`.claude/hooks/rule-incident-marker-capture.sh` · `.claude/hooks/rule-incident-marker-capture.test.sh` ·
the five mis-prefixed emitters (Phase 4.5) · `knowledge-base/project/rule-metrics.json` ·
`.claude/hooks/memory-backstop.test.sh` · `.claude/hooks/memory-backstop-mutation-battery.sh` ·
`knowledge-base/engineering/architecture/diagrams/model.c4` · `tests/hooks/test_incidents.sh`

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/test/lib/git-fixture-env.sh` | the shell chokepoint: one array, the tripwire, `git_fixture_env` |
| `plugins/soleur/test/git-fixture-env-shell.test.sh` | its suite — the producer for AC2 and Guard 1 M3/M4 |
| `plugins/soleur/test/fixture-env-adoption.test.sh` | the Phase 2.7 static adoption guard |
| `knowledge-base/engineering/architecture/decisions/ADR-204-*.md` | the telemetry-id namespace contract |
| `knowledge-base/project/specs/<branch>/measurements.md` | Phase 0 baselines *(written)* |
| `knowledge-base/project/specs/<branch>/decision-challenges.md` | the panel's scope challenge and its resolution *(written)* |

Six new files, down from nine in the first draft — and two of the six exist because review found
acceptance criteria and guard rows with no producer.

---

## Acceptance Criteria

Every containment AC runs against a **derived, controlled** root, never a live count: the operator's
ledger grew 270 rows during this planning session with no test run involved, so an
`after - before == 0` assertion over the live file measures the machine
(`cq-ac-must-not-depend-on-concurrent-sessions`). Every ledger path is obtained the way
`emit_incident` obtains it —
`bash -c 'source .claude/hooks/lib/incidents.sh; _incidents_repo_root'` with the variable unset —
never written as a literal, because in a worktree the file does not exist and a `wc -l` over it
leaves the comparison undefined.

**AC1** `bash plugins/soleur/test/git-env-list-parity.test.sh` passes; its `shell` comparison label
names `lib/git-fixture-env.sh`; its assertion count is ≥ the pre-change count. *(Keyed on what the
suite prints — it emits `%d passed, %d failed, %d assertions` and per-comparison labels, and reports
no "derivations compared" figure.)*

**AC2** `bash plugins/soleur/test/git-fixture-env-shell.test.sh` passes, covering: the ceiling
refuses `/`, a non-absolute path, and a path containing `:`; **nothing is exported on the refusal
path** (assert the env is unchanged, not merely that the return code is 1).

**AC3** `bash plugins/soleur/test/fixture-env-adoption.test.sh` passes: both derivations non-empty,
the difference set empty and printed. **Removing `gitFixtureEnv()` from any one converted suite
reddens it** — this is the AC that makes Phase 2 verifiable at all.

**AC4** `bash scripts/test-all.sh` completes with 0 `[FAIL]` and 0 `[TRIPWIRE]` lines. Because the
`run-all.sh` arm is **relevance-gated** (declined on 56% of recent commits, and
`SOLEUR_ALLOW_FULL_GATE=1` overrides the refusal producers, *not* relevance), the run must touch a
`GITHUB_SCRIPTS_SUITE_PATHS` member or set `TEST_GROUP=scripts` so that arm actually executes.

**AC5** Reverting the `unset` in `.github/scripts/test/run-all.sh` reddens the parity test's scrub
loop, and that loop's entry-point count floor is ≥ the Phase 0.8 count.

**AC6 — containment, both roots, derived, existence-and-count.** For a full battery and for each of
the three previously-leaking suites run **standalone**: with `INCIDENTS_REPO_ROOT` unset and
`CLAUDE_PROJECT_DIR` at a `mktemp -d`, assert that at **both** sinks — the `BASH_SOURCE`-resolved
root and the `CLAUDE_PROJECT_DIR`-resolved root — the ledger file **either still does not exist, or
has the same row count as before**. The standalone arm is load-bearing: it is the spelling all three
leaks occur under, and the entry-point belt does not run there.

**AC7** The redirect is fail-loud: with `mktemp` forced to fail, each chokepoint and each entry point
**aborts with a named message** rather than proceeding with an empty `INCIDENTS_REPO_ROOT` (which
`_incidents_repo_root()` reads as unset).

**AC8** `bash .claude/hooks/incident-sandbox-coverage.test.sh` passes; population greater than the
count it prints today; at least one member outside `.claude/hooks/`; a non-empty count printed for
**each** derivation; and the **outside set printed** with its floor.

**AC9** `INCIDENTS_REPO_ROOT` survives the fixture env builders — a test asserts `gitFixtureEnv()`'s
output carries it and `git_fixture_env` does not unset it.

**AC10** Against a **frozen snapshot** of the merged corpus in a `mktemp -d` root,
`bash scripts/rule-metrics-aggregate.sh --dry-run` exits **0** with `summary.orphan_rule_ids == []`.

**AC11 — the gate still has teeth.** Into the same frozen snapshot, inject one synthetic
section-prefixed id with no AGENTS tag; the aggregator must exit **rc=5** and name it. *(AC10 alone
is satisfied by a gate that always passes.)*

**AC12** `git grep -c 'startswith(' scripts/rule-metrics-aggregate.sh` equals **3**, and those three
are the unrelated analytics selectors (`hook_input_faults`, `grep_rewrite_faults`,
`net-issue-flow-mandated-filing--`), named in the AC.

**AC13** `bash .claude/hooks/rule-incident-marker-capture.test.sh` passes: its companion assertion
pins the shared section-prefix regex, and no case greps the aggregator for a `startswith("<prefix>")`
literal.

**AC14** `knowledge-base/project/rule-metrics.json` is regenerated with a `generated_at` inside this
PR's date and a non-empty `summary.rules_unused_over_8w`.

**AC15** `bash .claude/hooks/memory-backstop.test.sh` passes in **both** shapes, each keyed on the
suite's own result token rather than an absolute pass floor: with no user bus (the CI shape) it
reports the live-arm skip; on the operator's box it reports `[live: yes]` and the e2e arm's own
verdict. Neither shape asserts a hardcoded count — the suite's live label is the discriminator.

**AC16** The e2e gate keys on `outcome != "applied"`, not on a single reason string: with
`SOLEUR_DISABLE_MEMORY_BACKSTOP=1` set, the suite **skips** the adoption tests and does not fail.

**AC17** The hook is invoked with `CLAUDE_PROJECT_DIR` at scratch and `CLAUDE_CODE_EXECPATH` unset —
asserted by grepping the invocation — and no `.memory-backstop.stamp.nagged` appears in the real
checkout after a suite run.

**AC18** The depth boundary is asserted **synthetically**: the Phase 5.4 fixture returns non-zero
with claude at hop 9, zero at hop 8, and non-zero for a generic-interpreter `CLAUDE_CODE_EXECPATH`.
*(An AC keyed on the suite's real ancestry depth is not reproducible.)*

**AC19** `MAX_WALK_HOPS` 8 → 9 flips the hop-9 case, exercised by
`.claude/hooks/memory-backstop-mutation-battery.sh` rather than by a one-off `/work` run.

**AC20** `git grep -n 'for _hop in' .claude/hooks/memory-backstop.test.sh` returns nothing, **and**
the rationale comment has been rewritten — asserted by grepping for the new measured-reason wording,
not for the old block's absence.

**AC21** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean. *(Not `npm run -w` —
the repo root declares no `workspaces` field.)* The C4 suites `c4-code-syntax.test.ts` and
`c4-render.test.ts` pass.

**AC22** `ADR-204-*.md` exists; its ordinal is re-verified free across every `origin/*` ref
immediately before merge; no artifact under `specs/<branch>/` or this plan retains a superseded
ordinal.

**AC23** The five deferral issues exist (`gh issue list` by title), the #7208 note is posted, and
`tests/hooks/test_incidents.sh`'s false comment is corrected.

**AC24** PR body carries `Closes #7849`, `Closes #7853`, `Closes #7854`, and records the Phase 3.5
before/after ledger counts as an in-session write to operator state.

### Post-merge (operator)

None. Phase 3.5's cleanup runs during `/work` against the operator's local ledger — disclosed in the
PR body per AC24 rather than described as untouched.

---

## Observability

```yaml
liveness_signal:
  what: "scripts/rule-metrics-aggregate.sh completing (rc=0) and knowledge-base/project/rule-metrics.json
         carrying a generated_at within the last 7 days"
  cadence: "on demand + every /soleur:compound Phase 1.5 run"
  alert_target: "the committed rule-metrics.json diff — a stale generated_at is visible in review"
  configured_in: "scripts/rule-metrics-aggregate.sh, knowledge-base/project/rule-metrics.json"
error_reporting:
  destination: "stderr of the invoking runner + the [FAIL]/[KILLED]/[TRIPWIRE] classification in scripts/test-all.sh"
  fail_loud: true
failure_modes:
  - mode: "a new hook emits an id that darks the aggregate"
    detection: "structurally prevented — a non-section-prefixed id is out of scope; a section-prefixed
                one is a real corpus-rule claim and SHOULD orphan (AC11 proves the teeth remain)"
    alert_route: "rc=5 from the aggregator naming the id"
  - mode: "a test run appends to either resolved ledger root"
    detection: "incident-sandbox-coverage.test.sh — static, repo-wide, per-derivation floors, and it
                PRINTS the set of emitter-reaching suites that pass through no chokepoint"
    alert_route: "[FAIL] line naming the unsandboxed suite"
  - mode: "the sandbox mktemp fails and the redirect silently restores the real sink"
    detection: "AC7 — the empty value is rejected and the entry point aborts with a named message"
    alert_route: "abort on stderr, not a silent continue"
  - mode: "the chokepoint redirect is stripped by a fixture env builder"
    detection: "AC9's pass-through assertion, run on every battery"
    alert_route: "[FAIL] line in the fixture-env suite"
  - mode: "a converted fixture suite is reverted to a hand-rolled env"
    detection: "the Phase 2.7 adoption guard's printed difference set (AC3)"
    alert_route: "[FAIL] line naming the suite"
  - mode: "a test entry point gains a runner with no git-location scrub"
    detection: "the parity test's scrub loop plus its entry-point count floor (AC5)"
    alert_route: "[FAIL] line carrying the exact unset to apply"
  - mode: "memory-backstop's e2e arm skips on every run, so an adoption regression ships"
    detection: "AC15's two-shape assertion keyed on the suite's own live label; the skip message names
                the hook's own outcome and reason verbatim plus the standalone remedy"
    alert_route: "suite stdout; the skip is loud and distinguishable from a pass"
  - mode: "the unconditionally-invoked hook adopts a non-Claude ancestor on a shallower tree"
    detection: "AC17 (invocation asserted with CLAUDE_CODE_EXECPATH unset) + AC18's negative fixture case"
    alert_route: "[FAIL] line in the memory-backstop suite"
logs:
  where: ".claude/.memory-backstop.jsonl (per-run hook outcome+reason); the incident ledger at BOTH
          resolved roots (operator-local, gitignored); scripts/test-all.sh stdout/stderr"
  retention: "the incident ledger rotates monthly to .claude/.rule-incidents-YYYY-MM.jsonl.gz; the
              memory-backstop log is append-only and operator-local"
discoverability_test:
  command: "bash scripts/rule-metrics-aggregate.sh --dry-run"
  expected_output: "exit 0, and the emitted JSON carries \"orphan_rule_ids\": []"
```

*Observability-layer citation:* **layer 7** — code under `plugins/` executing on a customer's
self-hosted CLI (`git-fixture-env.sh`, `test-helpers.sh`) — plus the repo-local `.claude/` hook
surface. Neither has a Sentry path; the operator-reachable signal is the runner's own exit
classification, routed to distinct `[FAIL]` / `[KILLED]` / `[TRIPWIRE]` lines. No step requires SSH.

*Soak follow-through (2.9.1):* no time-gated acceptance criterion. **Not applicable.**

*Affected-surface observability (2.9.2):* the memory-backstop hook is a blind surface — a detached
child of a test suite whose only output is a JSONL line. Phase 5.3 makes that line the suite's gate,
so the surface's own structured record (`outcome`, `reason`, `pid`, `scope`) discriminates the
competing hypotheses — detached runner, depth-exceeded, opt-out, concurrent apply, real defect — in
one event, rather than a host-side re-derivation that cannot see the hook's starting depth.

---

## Architecture Decision (ADR/C4)

**ADR-204 (provisional ordinal), one decision** — *"A telemetry rule id declares its namespace by
prefix, and test telemetry is redirected at the runtime chokepoint."*

The first draft carried two decisions; two reviewers argued for none. Scoped to one, which is where
the disagreement resolves: the surviving invariant is genuinely cross-cutting and non-obvious, and
today exists only as a comment inside a jq program.

**Decision.** The incident ledger carries two id namespaces. An id matching
`^(hr|wg|cq|rf|pdr|cm)-` is a claim to be an AGENTS.md corpus rule and the orphan gate holds it to
that claim; every other id is hook-operational telemetry whose rule body is tier-gated out of the
corpus (`cq-agents-md-tier-gate`) and is structurally out of scope. A hook author declares the
namespace in the emission itself. Correspondingly, a test run must never write to the operator's
ledger, and the redirect is applied at the per-runtime chokepoint every suite passes through — not at
the call site (applied twice, missed a sibling both times) and not at the entry point (inert against
direct suite invocation). **The chokepoint set is not universal**, and the residual is measured,
printed and ratcheted rather than assumed away.

**Alternatives considered.** Tagging each hook id in AGENTS.md (rejected — `cq-agents-md-tier-gate`,
`B_ALWAYS` at `[WARN]`). A tenth prefix glob (rejected — a glob exempts every future id under its
prefix unreviewed). A hand-maintained exact-id registry with a drift lint (rejected — several
emitters build ids at runtime, so it enumerates an open set; and 8 hooks emit through a bare-token
wrapper alias the lint's grep shape could not see). Discriminating on the existing `kind` field
(rejected — every live *and archived* row is `rule_event`, so it cannot classify history, and it
needs ~30 emitter edits plus a timestamp cutover to do what one predicate does). A marker-and-refuse
branch inside `emit_incident` (rejected — the chokepoint that would set the marker can set the
redirect instead, with no test-awareness in production hook code and no risk of darkening real
telemetry).

**Note for the next maintainer:** the discriminator is the **prefix**, not `kind`. `kind` is written
on every row and read by nothing.

### C4 views

**Enumeration against all three model files** (`model.c4` 691 lines, `views.c4` 74, `spec.c4` 54) —
not a keyword grep:

- **External human actors:** `founder`, `emailSender`, `betaContact`, `contributor` (last three
  `#external`). **No new actor**; no actor's access changes.
- **External systems / vendors:** `anthropic`, `github`, `soleurMarketplace`, `cloudflare`, `doppler`,
  `discord`, `stripe`, `systemdUser`, `plausible`, `resend`, `pushService`, `ghcr`, `projectZot`,
  `zotRegistry`, `letsencrypt`, Better Stack. **No new vendor**, no new edge.
- **Containers / data stores touched:** `hooks = container "Hook Engine"` — touched. The incident
  ledger is operator-local telemetry, not modelled as its own element; no element is added.
- **Access relationships that change:** none.

**Verdict: no element addition, one description amendment.** The Hook Engine's description already
carries `lib/incidents.sh` detail. Add one clause recording the two id namespaces and the chokepoint
redirect. No `views.c4` `include` changes. AC21 runs the C4 suites.

### Sequencing

True on merge. No `status: adopting` staging.

---

## Guard Contract

Five guards. The marker-refusal and registry-drift guards were cut with their mechanisms; the
adoption guard was added because review found Phase 2 unverified.

### Guard 1 — the shell fixture-env chokepoint (`plugins/soleur/test/lib/git-fixture-env.sh`)

**Property.** Every shell suite that creates a git fixture runs `git` under an environment that is
neither pointed at, nor able to walk up into, nor configured by, the developer's own repository —
**and never runs `git` under a partial one.**

**Assembly.** The **chokepoint** is the single `GIT_LOCATION_VARS` array and the single
`git_fixture_env` definition. The property quantifies over every shell suite that sources the file;
membership is pinned by the parity test (three language spellings) and by Guard 5 (adoption).
**More than one place can still supply the environment, stated not hidden:** the sourced helper,
`test-helpers.sh` (which sources it), and the five inline copies under `git-worktree/test/` — a
second chokepoint pinned only by the parity test, folded in by a deferral issue.

**Mutation matrix**

| # | Mutation | Must red |
|---|---|---|
| M1 | Delete one variable from the array | the parity test's shell comparison |
| M2 | Give the builder its own copy of the list, minus one entry | must red — otherwise the "one array" invariant is unenforced |
| M3 | Change the ceiling from the fixture's **parent** to the fixture itself | the helper's suite |
| M4 | Export some variables, then fail the ceiling | the "nothing exported on the refusal path" case — a partial env is the silent degradation the helper exists to prevent |
| M5 | Drop the `\|\|` guard at one call site | Guard 5's adoption assertion |
| M6 | **Guard's own dispatch:** make `shell_list()`'s extractor match nothing | the parity test's per-derivation floor |

**Harness rows**

| # | Mutation | Expected |
|---|---|---|
| H1 | Delete the parity test's comparison loop body, leaving the counters | must RED via the assertion floor, not read green on 0 comparisons |
| H2 | **Must-PASS non-canonical:** a fixture directory two levels below `/` whose name contains a space (only `:` is refused) | must PASS |

### Guard 2 — entry-point scrub coverage (the parity test's scrub loop)

**Property.** Every entry point that starts a test runner removes the git-location family in the same
shell before starting it. *(The ledger half is Guard 3's — deliberately not claimed here, because
`lefthook.yml`'s inline `unset … && bun test plugins/soleur/test/` command gets the git half and not
the ledger half, and a property this guard cannot assert must not appear in its name.)*

**Assembly.** The loop's file list plus its count floor. Before this plan the set was enumerated
twice in two hardcoded three-item lists, which is why `run-all.sh` and two workflow steps were
invisible to both.

**Mutation matrix**

| # | Mutation | Must red |
|---|---|---|
| M1 | Revert `run-all.sh`'s `unset` | the scrub loop (AC5) |
| M2 | Remove an entry from the loop | the count floor |
| M3 | Move `run-all.sh`'s unset below another line-anchored `unset GIT_` | must red — `scrub_list` takes the **first** such line |
| M4 | Add a workflow `run:` step matching `RUNNER_RE` that is neither in the list nor delegating to `test-all.sh` | the Phase 0.8 derivation |
| M5 | **Guard's own dispatch:** empty the loop's list | the count floor |
| M6 | Scrub the first member, leave the second | must still red |

**Harness rows**

| # | Mutation | Expected |
|---|---|---|
| H1 | Replace the check with `grep -q unset` on the file | must RED — `( unset … ); runner` and `runner && unset …` both mention it and both leave the runner hostile |
| H2 | **Must-PASS non-canonical:** an entry point delegating to `scripts/test-all.sh` rather than scrubbing itself | must PASS |

### Guard 3 — repo-wide ledger sandbox coverage (`incident-sandbox-coverage.test.sh`)

**Property.** No test in this repository can append a row to **either** resolved incident-ledger
root, including through a spawn no call-site grep can see and under direct invocation of a single
suite — **and the set of emitter-reaching suites protected by no chokepoint is counted, printed and
ratcheted downward.**

**Assembly.** Two emitter chokepoints, both enumerated (`emit_incident` in `incidents.sh` and its
Python mirror — a filename-paired enumeration already missed the `.py` once). Population derived in
two structural hops from **invocation shapes, not name mentions**, each with its own non-empty floor.

**Mutation matrix**

| # | Mutation | Must red |
|---|---|---|
| M1 | Remove the sandbox from `test/pre-merge-rebase.test.ts` | the widened assembly — the file the one-directory assembly could not see |
| M2 | Add a new unsandboxed suite under `tests/scripts/` that execs `gdpr-gate.sh` | the derived population |
| M3 | Delete the Python mirror from the emitter set | the emitter-set floor |
| M4 | Remove the chokepoint export from one of the five files | the chokepoint-count assertion |
| M5 | Make the sandbox `mktemp` fail | AC7 — the entry point must abort, not proceed on `""` |
| M6 | Switch hop 2 back to a name-mention derivation | the self-inclusion assertion (the guard would then include itself) |
| M7 | **Guard's own dispatch:** make either derivation return empty | that derivation's floor (AC8) |
| M8 | Sandbox the first member, leave the second | must still red |

**Harness rows**

| # | Mutation | Expected |
|---|---|---|
| H1 | Delete the `verdict` call inside the loop | must RED via the assertion-count floor, not read `0 failed` |
| H2 | **Must-PASS non-canonical:** a `.test.ts` setting the root inline at every emitter invocation rather than sourcing the bash helper (it cannot source bash) | must PASS |

### Guard 4 — the ancestry derivation (`memory-backstop.test.sh`)

**Property.** `discover_claude_pid`'s traversal limit is exactly `MAX_WALK_HOPS`; adoption requires
an unambiguous Claude identity; and the suite's e2e gate reports the hook's own verdict.

**Assembly.** The single `discover_claude_pid` definition, its three positive predicates, and the
single log-line read in the e2e arm. There is now **one** walk in the repository.

**Mutation matrix**

| # | Mutation | Must red |
|---|---|---|
| M1 | `MAX_WALK_HOPS` 8 → 9 | the hop-9 fixture case (AC19, in the mutation battery) |
| M2 | `MAX_WALK_HOPS` 8 → 7 | the hop-8 fixture case |
| M3 | Re-introduce a second independent walk | AC20's grep |
| M4 | Gate the skip on `reason == "claude_pid_not_found"` instead of `outcome != "applied"` | AC16 — the documented opt-out must skip, not fail |
| M5 | Drop `CLAUDE_CODE_EXECPATH`-unset from the invocation | AC17's invocation assertion, and AC18's negative fixture case |
| M6 | **Order/lifetime row:** move the log-line read to *before* the hook invocation | must red — the gate would read the previous run's outcome, the class a delete-only battery cannot see |
| M7 | **Guard's own dispatch:** make the synthetic `/proc` builder emit a chain shorter than 10 | the fixture-depth floor |

**Harness rows**

| # | Mutation | Expected |
|---|---|---|
| H1 | Change the skip helper so a skipped test increments the pass counter | must RED via the skip-count assertion |
| H2 | **Must-PASS non-canonical:** the hook reporting `outcome=applied` with `reason` absent entirely | must PASS (the gate keys on `outcome`, not on `reason` being present) |

### Guard 5 — fixture-env adoption (`plugins/soleur/test/fixture-env-adoption.test.sh`)

**Property.** Every test file that spawns `git` under `apps/web-platform/test/**`, `tests/**` or
`.github/scripts/test/**` obtains its environment from a helper, and checks the helper's return.

**Assembly.** Two independent derivations — git-spawn sites (by invocation shape, covering
`execFileSync`, `spawnSync`, `Bun.spawn`, `subprocess.run` and shell `git`) and helper-call sites —
each with a non-empty floor, differenced and printed. This guard exists because review found Phase 2
otherwise unverified: the battery and the typecheck both stay green if the conversions are skipped.

**Mutation matrix**

| # | Mutation | Must red |
|---|---|---|
| M1 | Revert one converted vitest suite to a bare `execFileSync("git", …)` | the difference set |
| M2 | Revert one converted shell suite | the difference set |
| M3 | Drop the `\|\| { …; exit 1; }` guard at one shell call site | the return-check assertion |
| M4 | Add a new suite that spawns git with no helper | the difference set must grow |
| M5 | **Guard's own dispatch:** make the git-spawn derivation match nothing | its floor |
| M6 | Convert the first member, leave the second | must still red |

**Harness rows**

| # | Mutation | Expected |
|---|---|---|
| H1 | Replace the difference check with a count comparison of the two sets | must RED — equal cardinality does not imply the same set |
| H2 | **Must-PASS non-canonical:** the six waived `workspace*`/`mu1-integration` suites and `agent-ready-git-worktree.test.ts`, which are correct for their runtime by `process.env` mutation | must PASS, via an explicit declared waiver list that the guard prints |

---

## Domain Review

**Domains relevant:** Engineering. Sweep over all 8: no customer-facing surface, no pricing, no
contract, no vendor spend, no support workflow.

### Engineering

**Status:** reviewed
**Agents invoked:** cto (devex), dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, plus a scoped strong-model
consult on the riskiest phase.

**Findings that changed the plan:**

1. **Cut the marker-and-refuse layer** (DHH P0-2, code-simplicity #6, strong-model consult —
   independent convergence). If the chokepoint is the right place for the marker, the marker was
   never needed. Its stated justification was also false (spec-flow P0-1): the coverage guard greps
   for `test-incident-sandbox.sh`, and only 6 of 46 hook suites source `test-helpers.sh`.
2. **Cut the registry and its drift lint** (DHH P0-1, code-simplicity #8/#9, Kieran P0-4/P0-5). One
   predicate over an invariant that holds for all 105 AGENTS ids replaces both.
3. **Cut the committed quarantine script and its suite** (DHH P1-2, code-simplicity #7).
4. **Cut the new entry-point file** (code-simplicity #2) — the parity loop is the list.
5. **Two ledger sinks** (Kieran P0-1), and **in a worktree the primary sink does not exist**
   (spec-flow P0-2). The draft's headline AC would have passed over the headline defect twice over.
6. **An empty `INCIDENTS_REPO_ROOT` reads as unset**, and `run-all.sh` carries no `set` line
   (spec-flow P0-3) — the redirect must be fail-loud (AC7).
7. **Containment ACs were flippable by concurrent sessions** (Kieran P0-2; measured 270 rows during
   planning). Rewritten against derived, controlled roots asserting existence and count.
8. **A sixth copy of the prefix set with an assertion that greps the aggregator** (Kieran P0-3) —
   `rule-incident-marker-capture.{sh,test.sh}` added to scope; both simplify under the predicate.
9. **The `run_suite` Sharp Edge was inverted** (Kieran P1-8) — the linter requires the path last.
10. **AC2 had no producer and Phase 2 had no guard** (spec-flow P0-5, P0-6) — two new suites, and
    Guard 1's M6 row now has something to assert against.
11. **The e2e gate must key on `outcome != "applied"`** (architecture-strategist P1-8) — the hook has
    eleven decline reasons, and the documented opt-out would otherwise fail the commit gate.
12. **Unconditional invocation widens an adoption surface via `CLAUDE_CODE_EXECPATH`**
    (architecture-strategist P1-9) and writes a nag stamp into the real checkout (P1-6) — scratch
    project dir, execpath unset, negative fixture case.
13. **`run-all.sh`'s arm is relevance-gated and `SOLEUR_ALLOW_FULL_GATE=1` does not override it**
    (spec-flow P1-2) — AC4 must force it.
14. **The chokepoint set is not universal** (spec-flow P1-3, P1-4) — bun's cwd-relative bunfig
    resolution and unittest's conftest bypass. Stated, counted, printed, ratcheted.
15. **Guard 3's hop 2 was a mentions-the-name proxy that self-includes** (spec-flow P1-9) — derive
    from invocation shapes.
16. **No AC proved the gate still rejects a real orphan** (spec-flow P1-8) — AC11 added; AC10 alone
    is satisfied by an always-pass gate.
17. **Deliverables without ACs** (spec-flow P1-10) — C4 suites, deferral issues, #7208 note, the
    comment correction now covered by AC21/AC23.
18. **The mutation battery exists and is registered nowhere** (architecture-strategist P2) — AC19's
    row gets a durable owner.
19. Minor corrections: `globalSetup:` cited by content anchor (the line number was off by four); the
    `[TRIPWIRE]` echo likewise; the coverage guard's printed population; `pre-merge-rebase.test.ts`'s
    env characterisation; "nine prefix globs" restated as eight globs plus an exact-literal pair;
    the parity test's four extractors and three comparisons.

### Product/UX Gate

**Mechanical UI-surface override:** ran against every planned path. Zero matches. Product is
**NONE**; no gate subsection.

---

## Decision Challenges

Persisted to `specs/<branch>/decision-challenges.md`. **DC-1 (the aggregator split) is resolved
rather than deferred:** the split was argued on blast radius proportional to the registry's size, and
the registry is cut — the arm is now one jq predicate, one `_valid_rule` simplification and a
regenerated artifact. Per `hr-technical-fork-is-not-an-operator-question`, a revert-unit boundary is
an engineering fork, not an operator question; resolved as **one PR**, with the reasoning recorded.

---

## GDPR / Compliance Gate (Phase 2.7)

Invoked inline and **sandboxed** — a dogfood of this plan's own fix. No regulated-data finding for
the plan's paths. The gate reported its own pre-existing `POSTURE_FAIL: gdpr-gate rules >90 days
stale`, a standing condition tracked by the content-vendoring posture chain.

**Two rows landed in the sandbox; the real ledger was unchanged.** Empirical proof of Phase 3's
mechanism, taken before any code was written.

Triggers (a)–(d) re-checked: no LLM/external-API processing of session-derived data; threshold not
`single-user incident`; no new cron reading `learnings/` or `specs/`; and with the quarantine script
cut, no new persistence location for `command_snippet` data.

---

## Infrastructure (IaC) — Phase 2.8

**Skipped; Phase 2.8 reviewed** (ack in `## Overview`). The scan found no remote-shell invocation, no
service-unit lifecycle change, no secret write, no Terraform import, no vendor-console wording, no
new scheduled job, no new vendor account. No `.tf` changes.
`apps/web-platform/infra/workspaces-luks-loopback.test.sh` is a **test suite** under `infra/`.

## Encryption Posture — Phase 2.11

**Skipped.** No persistent store, no new cross-component connection. The per-run sandbox is a
`mktemp -d`; the quarantine copy is a sibling of an existing gitignored file on the same filesystem.

---

## Risks & Mitigations

**R1 — the redirect makes the static guard's failure invisible.** Mitigation: non-empty floors on
each of Guard 3's derivations (AC8), following the parity test's and `RUN_LINES`' precedent. Guard 3
is static, so the redirect cannot satisfy it — only an empty assembly can.

**R2 — a fixture env builder strips the redirect.** The cross-phase interaction most likely to
produce a fourth leak after "containment shipped". Mitigation: AC9 asserts the pass-through
explicitly rather than relying on `gitCleanEnv()`'s prefix sweep being read correctly.

**R3 — the chokepoint set is not universal.** `bun test` from a third cwd, `python3 -m unittest` on a
suite that does not import `_git_fixture_env`, and 40 of 46 hook suites that do not source
`test-helpers.sh` all sit outside it. Mitigation: stated in the ADR and the plan rather than claimed
away; Guard 3 prints the outside set with a ratcheted floor, and Phase 2's conversions plus the
deferral issues are what shrink it.

**R4 — the section-prefix predicate silently exempts a mis-prefixed hook id.** Mitigation: Phase 4.5
**renames** the five known cases where the immutability rule permits, making the invariant true
rather than carving around it, and records the exceptions.

**R5 — the vitest chokepoint may not reach worker children.** Mitigation: Phase 0.5 probes it under
both pools before the design depends on it; `test.env` is the named fallback.

**R6 — converting a suite silently changes its ledger sink.** `tests/hooks/test_hook_emissions.sh`
asserts on emitted rows and sets no root; sourcing the helper redirects them. Mitigation: Phase 2.3
pairs every conversion with an emitter grep and a sandbox reconciliation in the same commit.

**R7 — the unconditional hook invocation adopts a non-Claude ancestor.** Mitigation: scratch
`CLAUDE_PROJECT_DIR`, `CLAUDE_CODE_EXECPATH` unset, AC17's invocation assertion and AC18's negative
fixture case. Named in `## User-Brand Impact` rather than left implicit.

**R8 — `workspaces-luks-loopback.test.sh` runs with elevated privileges.** Mitigation: resolve the
helper from a repo root computed once; assert absolute and non-degenerate before sourcing.

**R9 — converting vitest suites changes the env from inherited-plus-overrides to constructed.**
Mitigation: `agent-ready-git-worktree.test.ts` is the known instance of the pattern that breaks, is
explicitly waived, and appears in Guard 5's printed waiver list. Run each converted suite
individually before the battery.

**R10 — Phase 3.5 writes to the operator's live ledger during `/work`.** Mitigation: reversible by
construction (copy first, `grep -v` second, archives untouched), measured in one command so a
concurrent append cannot desynchronise the recorded counts, and disclosed in the PR body (AC24).

**R11 — regenerating `rule-metrics.json` produces a large diff.** Mitigation: its own commit, with
the `--dry-run` diff in the PR body.

**R12 — ADR ordinal collision.** Mitigation: AC22 re-derives across every `origin/*` ref immediately
before merge and mandates a same-edit sweep of this branch's planning artifacts on renumber.

**R13 — scope.** Six phases, three issues, five guards, ~32 edited files, six new files. The panel's
cuts removed ~530 lines of proposed new code, five mechanisms and two guards; the additions are two
suites that make previously-unverified phases verifiable. Mitigation: phases are dependency-ordered
and independently landable; Phase 4 lifts out at a measured-independent seam if review still prefers
it separate.

---

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| **#7854 Option 2** — keep the independent walk, match the hook's limit exactly | **Measured not to work.** The hook is a child of the suite, so the walks start one process apart regardless of matching limits. Option 2's fixture half is kept |
| **#7854** — raise `MAX_WALK_HOPS` | Would make the e2e arm *run* under lefthook, adopting the live session's tree into a memory-capped transient scope inside a `git commit` |
| **#7854** — call `discover_claude_pid` from the suite | Still starts at the suite's depth |
| **#7854** — gate the skip on `reason == "claude_pid_not_found"` | The hook has eleven decline reasons; the documented opt-out and a benign `concurrent_apply` race would still fail the commit gate |
| **#7853** — a marker plus a refusal branch in `emit_incident` | The chokepoint that sets the marker can set the redirect instead — no test-awareness in production hook code, no risk of darkening real telemetry |
| **#7853** — export the marker from the entry points | Inert against all three measured leaks |
| **#7853** — an exact-id registry plus a drift lint | Several emitters build ids at runtime, so it enumerates an open set; and 8 hooks emit through a bare-token wrapper alias the lint could not see |
| **#7853** — discriminate on the existing `kind` field | Every live and archived row is `rule_event`; it cannot classify history |
| **#7853** — tag `skill-security-scan` in AGENTS.md | 1 of 22; blocked by the tier gate and the budget |
| **#7853** — a tenth prefix glob | A glob exempts every future id under its prefix unreviewed |
| **#7853** — delete the fabricated rows outright | A write-boundary fix must not itself be an unannounced destructive write to operator telemetry |
| **#7853** — a committed quarantine script with its own suite | Permanent machinery for a one-time cleanup of a gitignored, self-expiring file |
| **#7849** — a new declared entry-point list file | A `.txt` rots identically; the parity loop already carries a floor |
| **#7849** — a fourth parity derivation | One array read by both consumers keeps the shell side a single derivation |
| **#7849** — a `git_fixture` wrapper for `-c commit.gpgsign=false` | The builder's config globals already make that setting unreachable |
| **#7849** — convert all ~60 shell + ~19 TS fixture sites | The ~50-file mechanical diff #7849 deliberately deferred |
| **#7849** — put the shell builder in `test-helpers.sh` | The `tests/**` and `.github/scripts/test/**` suites cannot take its assertion framework |
| Split into three PRs | The three issues share one file and one architectural shape |
| Split Phase 4 out | Argued on blast radius proportional to the registry; the registry is cut. Resolved as an engineering fork |

---

## Test Scenarios

Every scenario is `mutation → guard reddens`, except the two deliberate must-PASS rows — a battery
with only RED rows cannot detect a gate that rejects everything.

| # | Mutation | Guard that must redden |
|---|---|---|
| T1 | Drop a variable from the shell array | the parity test's shell comparison |
| T2 | Give the builder its own copy of the list | the "one array" assertion |
| T3 | Point the ceiling at the fixture instead of its parent | the helper's ceiling case |
| T4 | Export some variables, then fail the ceiling | the "nothing exported on refusal" case |
| T5 | Drop the `\|\|` guard at one shell call site | Guard 5's return-check assertion |
| T6 | Revert `run-all.sh`'s `unset` | the parity scrub loop (AC5) |
| T7 | Remove an entry from the scrub loop | the entry-point count floor |
| T8 | Place `run-all.sh`'s unset below another line-anchored `unset GIT_` | the scrub check (it reads the first) |
| T9 | Add a workflow `run:` step with a runner and no scrub | the Phase 0.8 derivation |
| T10 | Revert one converted vitest suite | Guard 5's difference set |
| T11 | Remove the sandbox from `test/pre-merge-rebase.test.ts` | the widened coverage guard; AC6 at both roots |
| T12 | Add a new unsandboxed suite that execs `gdpr-gate.sh` | the derived population |
| T13 | Force `mktemp -d` to fail | AC7 — the entry point must abort, not proceed on `""` |
| T14 | Switch Guard 3's hop 2 to a name-mention derivation | the self-inclusion assertion |
| T15 | Make `gitFixtureEnv()` drop non-`GIT_` variables | AC9's pass-through assertion |
| T16 | Emit a new `hr-`-prefixed id from a hook with no AGENTS tag | the orphan gate, rc=5 (AC11) |
| T17 | Emit a new non-prefixed id from a hook | must **PASS** — structurally out of scope; P6 by construction |
| T18 | Restore one `startswith()` exemption stanza | AC12's exact count of 3 |
| T19 | Revert `_valid_rule()` to its mirrored `case` list | the companion assertion |
| T20 | `MAX_WALK_HOPS` 8 → 9, then 8 → 7 | the hop-9 and hop-8 fixture cases, via the mutation battery |
| T21 | Gate the e2e skip on one reason string | AC16 — `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` must skip |
| T22 | Drop `CLAUDE_CODE_EXECPATH`-unset from the invocation | AC17 and AC18's negative case |
| T23 | Re-introduce an independent ancestry walk | AC20 |
| T24 | Move the log-line read before the hook invocation | the e2e gate's order assertion |
| T25 | Empty each guard's population derivation, one at a time | each guard's own floor (five anti-vacuity rows) |
| T26 | Fix the first offending member, leave the second, for Guards 1–3 and 5 | each must still redden |
| T27 | Run a waived suite (`workspace*`, `mu1-integration`, `agent-ready-git-worktree`) | must **PASS** via Guard 5's printed waiver list |

---

## Deferral Tracking

Each gets a GitHub issue at Phase 6.4, milestone `Post-MVP / Later`, labels `deferred-scope-out`,
`domain/engineering`, `type/chore`. **Verify each label exists** before filing.

1. **`apps/web-platform/server/worktree-config-seed.ts`** — a production module whose `git config`
   spawns pass `{ cwd }` and no `env`. *Trigger:* the next change to that module, or a report of
   worktree config seeding misbehaving under a git hook.
2. **The five `git-worktree/test/*.test.sh` inline tripwire copies** — re-point at
   `lib/git-fixture-env.sh`, which carries no assertion framework. *Trigger:* unblocked by Phase 1.
3. **`welcome-hook.test.ts`, `gdpr-gate-repo-scan.test.ts`,
   `web-platform-runtime-plugin-trigger.test.ts`** — the #7833 plan intended these on `gitFixture()`;
   they use the weaker `gitCleanEnv()` (no ceiling, no config hermeticity, no identity).
4. **The residual ~60 shell + remaining TS fixture sites**, with this plan's full enumeration
   attached — the enumeration is the expensive part and is done. *Trigger:* #7849's own triggers.
5. **Shrink Guard 3's printed outside set** — the suites that reach an emitter through no chokepoint
   (bun from a third cwd, `test_rule_id_regex_parity.py`, the 40 hook suites that do not source
   `test-helpers.sh`). *Trigger:* the floor is ratcheted, so it is a standing target rather than a
   one-off.
6. **`prod-write-defer-doppler-prd-secrets` has no live emitter** — confirm the rename and retire it.

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This one is filled.

- **There are TWO incident-ledger sinks, and in a worktree the primary one does not exist yet.**
  `incidents.sh` resolves off `BASH_SOURCE`; `gdpr-gate.sh` off `CLAUDE_PROJECT_DIR`. Derive the path
  the way `emit_incident` does and assert **existence**, not only line count — in a worktree the
  failure signature is a file appearing where none was, and `wc -l` over a missing file leaves the
  comparison undefined.

- **An empty `INCIDENTS_REPO_ROOT` is indistinguishable from unset** (`[[ -n … ]]`), and
  `.github/scripts/test/run-all.sh` carries **no `set` line at all**. An unguarded `mktemp -d`
  failure silently restores the real sink for the whole battery.

- **The chokepoint set is not universal.** bun resolves `bunfig.toml` from the invocation cwd;
  `python3 -m unittest` does not load `conftest.py`; 40 of 46 hook suites do not source
  `test-helpers.sh`. Claiming otherwise is what made the first draft's Layer 3 unreachable.

- **The vitest tripwire is at the `globalSetup:` key, not `setupFiles`** — and `globalSetup` was
  chosen as an *assertion* point, so using it as an *export* point needs a propagation probe under
  both pools. `test.env` is the fallback; `setupFiles` is not (1114 executions measured).

- **Register a new suite as `run_suite "<label>" bash <path>` — path last, after `bash`.**
  `lint-orphan-test-suites.sh` deliberately rejects a path-anywhere pattern, because `run_suite`'s
  first argument is a free-form label and a label-only match let a renamed runner read as registered.

- **`run-all.sh`'s arm in `test-all.sh` is relevance-gated (declined on 56% of recent commits), and
  `SOLEUR_ALLOW_FULL_GATE=1` overrides the refusal producers, not relevance.** An AC quantifying over
  that arm must force it.

- **The hook has eleven decline reasons.** Gating anything on one of them fails the commit gate for
  the documented opt-out and for a benign concurrency race.

- **`discover_claude_pid`'s `CLAUDE_CODE_EXECPATH` predicate matches a generic interpreter** under an
  npm-global install — invoke the hook with it unset, or a shallower tree adopts a `node` ancestor
  and up to 256 descendants.

- **The jq program in `rule-metrics-aggregate.sh` is single-quoted — no apostrophes in any comment
  added inside it.** One apostrophe ends the program and bash parses the remainder as shell.

- **The `hook_input_fault_count` exclusion is a LOAD-BEARING PAIR.** Removing it deletes the only
  surface a counts-only rule_id has; `summary.hook_input_fault_count` is its replacement.

- **A sixth copy of the exemption set lives in `rule-incident-marker-capture.sh`, pinned by an
  assertion that greps the aggregator's source.** Deleting the stanzas reddens it deterministically.

- **`scrub_list` and the N2 regex take the FIRST line-start-anchored `unset GIT_` in a file.**

- **A ceiling of `/` is silently ignored by git**, as is any non-absolute entry or one containing
  `:`. Fail loudly — and export nothing before the ceiling validates, or a suite runs under a partial
  env that reads as protection.

- **Every AC that claims a gate is green must run that gate's own invocation.**

- **`tests/hooks/test_incidents.sh`'s comment claiming its helper exports `INCIDENTS_REPO_ROOT` is
  false** — isolation is by lib-copy.

- **Typecheck with `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.** The repo root
  declares no `workspaces` field.

- **A skip that increments the pass counter is a green suite over an unexercised arm.** The suite
  already distinguishes `[live: yes]` from `[live: yes, e2e SKIPPED]` — key the AC on that token
  rather than a raw pass count, which would red every CI run.

- **Deleting a rationale comment is how a deleted mechanism comes back.** Phase 5 removes the
  independent walk *and* rewrites the comment that argued for it; AC20 greps for the new wording.

- **`kind` is dead schema.** Every row carries it; nothing reads it; every archived row says
  `rule_event`. The discriminator is the prefix.

- **A mutation recorded once in a PR body has no durable owner.**
  `memory-backstop-mutation-battery.sh` exists and is registered in no runner — put the row there.
