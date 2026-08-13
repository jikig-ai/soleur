---
title: "Encode the cross-worktree-destructive pkill recipe as a proc.sh helper"
date: 2026-08-13
slug: feat-encode-pkill-recipe-as-proc-sh
branch: feat-one-shot-7525-proc-sh-kill-mine
issue: 7525
closes: 7525
lane: cross-domain
type: enhancement
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

# Encode the cross-worktree-destructive pkill recipe as a `proc.sh` helper

## Overview

A prose rule forbidding self-matching `pkill -f` exists in the work skill and did not
prevent the failure it describes: on 2026-08-13 an agent self-killed its invoking shell
twice in one session, and the second attempt was also unscoped across sibling worktrees
running `scripts/test-all.sh`. Prose does not execute.

This plan replaces the mechanism guidance with an executable: `proc.sh` exposing
`list_runs <pattern>` (enumerate matching processes, each resolved to the worktree that
owns it) and `kill_mine <pattern>` (signal only processes owned by the current worktree,
refuse and report everything else). A companion suite mutation-proves the exclusions
against a synthesized procfs, so no test ever signals a real process. One pointer is added
where the `pkill` prose already lives.

Spec lacks valid `lane:` — defaulted to `cross-domain` (fail-closed). No `spec.md` exists
for this branch.

## Research Insights

### Premise Validation (Phase 0.6)

Every artifact the issue cites was verified against the working tree. Five premises held;
**two were falsified**, and both changed the deliverable.

| # | Cited premise | Verdict | Evidence |
|---|---|---|---|
| 1 | Issue #7525 is open | **HOLDS** | `gh issue view 7525` → `OPEN`, `closedByPullRequestsReferences: []` |
| 2 | The `pkill` prose exists in `work/SKILL.md` | **HOLDS** | `plugins/soleur/skills/work/SKILL.md:1153`, trailing clause of the subshell Sharp Edge |
| 3 | A `*.sh` + `*.test.sh` convention exists | **HOLDS** | 9 pairs under `scripts/lib/`; the shipped analogue is `plugins/soleur/scripts/lib/session-state.sh` + `plugins/soleur/test/session-state.test.sh` |
| 4 | Rule budget is at WARN | **HOLDS** | `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` → `[WARN] B_ALWAYS=45319 >= 44000` against the 46000 ratchet |
| 5 | #7523 tracks the orphan linter's blind spot | **HOLDS** | `gh issue view 7523` → OPEN |
| 6 | "Registered in `scripts/test-all.sh` by hand — nothing auto-discovers it" | **FALSIFIED** | `scripts/test-all.sh:1196` globs both `plugins/soleur/test/*.test.sh` and `scripts/lib/*.test.sh`. `scripts/lint-orphan-test-suites.sh:5-6`: *"test-all.sh's glob covers `scripts/lib/*.test.sh` but NOT `scripts/*.test.sh`, which must be registered by hand."* |
| 7 | "bracket-safe (`[t]est-all`) so it never self-matches" | **FALSIFIED as the mechanism** | The bracket trick is a `pgrep`/`ps \| grep` idiom. `git-worktree/SKILL.md:371`: *"Neither `grep -v grep` nor a `[t]est` bracket trick excludes it, because the matching process is the `/bin/bash -c` wrapper, not `grep`."* |

### Mechanism Minimality — Property List (Phase 0.6b step 1)

| ID | Property (observable outcome) |
|---|---|
| **P1** | An agent can enumerate every process matching a pattern, each labelled with the worktree that owns it, and the enumeration never reports the process performing it. |
| **P2** | An agent can signal the matching processes owned by the current worktree, and no process outside it is ever signalled. |
| **P3** | The invoking shell and its whole ancestor chain survive. |
| **P4** | The correct form is reachable from a surface the agent already reads, **and resolves on an installed user's machine**. |

### Cut List (Phase 0.6b step 3)

| Mechanism | Property | Disposition |
|---|---|---|
| Hand-registration in `scripts/test-all.sh` | "the suite runs" | **CUT** — `test-all.sh:1196` already globs `plugins/soleur/test/*.test.sh`. An explicit `run_suite` line would make it run **twice**. Replaced by AC5, which proves auto-discovery. |
| Bracket-safety as the anti-self-match mechanism | P1 | **CUT as mechanism, kept as property.** A `/proc` walk has no pattern for a bracket to fool, and the invoker's own cmdline still contains the literal pattern. P1 is bought by self+ancestry+pgid exclusion. |
| `$$` / `$PPID` exclusion | P3 | **CUT as sufficient, widened** to the full ancestry walk — see R1. |
| A new always-loaded AGENTS rule | P4 | **CUT** — excluded by the issue and by premise 4. |
| `elapsed_s` column | none | **CUT.** Inherited from `test-contention.sh`, where a contention banner needs "running 340s". Nothing here branches on it; it would cost a `/proc/uptime` read, `CLK_TCK`, field-22 extraction, and a `starttime` in every fixture. |
| `unreadable` as a third classification | none | **CUT to two** (`signal` / `refuse`). `<unreadable>` is the refusal *reason* printed in the owner column, not a class any consumer switches on. |

### Relevant code

- `plugins/soleur/scripts/lib/session-state.sh` — **the shipped-primitive precedent this
  design mirrors**: double-source guard (`:17`), self-contained (sources nothing external),
  dual-mode CLI dispatch at `:611` (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`).
- `plugins/soleur/test/session-state.test.sh:1-31` — the suite convention: `set -uo pipefail`,
  `SCRIPT_DIR`/`HELPER` resolution, `PASS`/`FAIL` counters, `ROOTS=()` + `trap cleanup EXIT`,
  `make_root()` on `mktemp -d`.
- `scripts/lib/test-contention.sh` — the proven `/proc`-walk primitives being mirrored:
  `_tc_stat_field` (`:123`, strips through the **last** `') '` because `comm` may contain
  spaces and close-parens), `_tc_ppid`/`_tc_pgrp` (`:136,138`), `_tc_self_and_ancestors`
  (`:151`, 64-step guarded walk), `_tc_is_run_proc` (`:189`, argv-position discipline),
  `_tc_scan_procs` (`:316`, the single walk with self/ancestry + pgid exclusion).
- `scripts/test-contention.test.sh:43,105` — the synthesized-procfs fixture pattern
  (`TC_PROC_ROOT` seam) that tests the whole scan without a real process.
- `scripts/test-all.sh:1196` — the auto-glob, inside `if want_scripts` (`:240`).
- `scripts/tmpfs-guard.sh:84,357` — a third in-repo `/proc` walk
  (`PROC_ROOT="${TMPFS_GUARD_PROC:-/proc}"`); source of the seam-name collision handled in D4.

### Applicable learnings

- `knowledge-base/project/learnings/2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times.md`
  — the originating error, **and** the test-design constraint: *"A regression test that
  re-declares the correct idiom inline is decoupled from the file it guards… Reverting the
  real header to the leaky form leaked 34 orphans while the test printed PASS."* Drives AC6.
- `knowledge-base/project/learnings/2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`
  — *"A mutation battery measures the mutations its author imagined."* Drives the positive control.
- `knowledge-base/project/learnings/2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md`
  — `set -m` does not make bash its own group leader; `kill -TERM 0` can reach the parent. Drives D5.
- `knowledge-base/project/learnings/2026-08-11-i-measured-the-issues-remedy-then-asserted-my-own-without-measuring.md`
  — `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` expands to the CWD-relative defect when unset. Drives D3.

### Governing ADRs

- **ADR-178** — a shared bash primitive consumed by shipped plugin code lives in
  `plugins/soleur/`. **Controlling**; §2 enumerates *"Agent-executed `SKILL.md`"* as a
  consumer class (`ADR-178:110`). See D1.
- **ADR-179** — bare `${CLAUDE_PLUGIN_ROOT}` for customer-facing executable paths; `:-` and
  `:?` rejected. **Controlling**; see D1/D3.
- **ADR-151** — the rule corpus is unconditionally loaded; the reason no rule is added.

### Related issues

- **#7523** (OPEN) — orphan-linter blind spot. Out of scope; neither target directory is in it.
- **#6222** (OPEN, `type/security`) — the repo-root `scripts/` CWD-shadow class. This plan
  **does not add to it** (see D1); draining it is that issue's job.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| **R1.** `kill_mine` "excludes `$$` and `$PPID`" | Measurably insufficient. `test-contention.sh:142-150`: *"this runner is normally launched through a wrapper (`bash -c '… bash scripts/test-all.sh …'`) and that wrapper's OWN cmdline contains the string. Excluding only `$$` therefore reports the caller's own invocation as a concurrent sibling on EVERY run… Observed live: a clean solo run reported 2 phantom siblings, both links in its own ancestor chain."* | Widen to **three** exclusions: full ancestry (64-step guarded walk), own process group, and the cwd scope filter. `$$`/`$PPID` is the 2-deep special case of the first. Pinned by M2. |
| **R2.** "bracket-safe (`[t]est-all`)" | With a `/proc` walk there is no pattern for the bracket to fool. | Keep the **property**, implement via exclusions 1+2. Documented in the header. |
| **R3.** "by hand — nothing auto-discovers it" | `test-all.sh:1196` globs `plugins/soleur/test/*.test.sh`. | **Do not hand-register.** AC5 proves auto-discovery instead. |
| **R4.** The prose recipe in `git-worktree/SKILL.md:371` is the known-good form | Its ppid extraction is `awk '{print $4}' /proc/$p/stat` — the naive whitespace split. `/proc/<pid>/stat` field 2 is `(comm)` and may contain spaces and close-parens, so it mis-indexes on any such process (`test-contention.sh:119-121`). | `proc.sh` uses the `') '` last-occurrence strip. Pinned by M5. The currently-recommended prose is latently buggy — a further argument for the executable. |
| **R5.** cwd is a sufficient ownership discriminator | `test-contention.sh:276-289` records three measured failures: suites `cd` into `mktemp -d` sandboxes (one worktree, two unequal cwd strings); `<unreadable>` collapses many processes into one pseudo-worktree; `timeout … bash <script>` puts a non-shell at argv[0]. | Accepted as a **stated boundary**, not silently: `kill_mine` signals only processes whose own cwd is the current worktree; everything else is refused **and printed**. See Non-Goals. |
| **R6.** `scripts/lib/` is the right home | `work/SKILL.md` **ships** (`marketplace.json` copies the `plugins/soleur/` subtree). ADR-178:110 names agent-executed `SKILL.md` a consumer class, and ADR-178's precipitating defect (#7409) was exactly this: shipped SKILL.md sites invoking a non-shipped path, exiting 127. | **Location changed** to `plugins/soleur/scripts/lib/proc.sh`. See D1. |

## User-Brand Impact

**If this lands broken, the user experiences:** an agent running `kill_mine` terminates a
`scripts/test-all.sh` run belonging to a *different* parallel session, losing that session's
in-flight suite results — the incident of 2026-08-13, now with a tool that makes it look
sanctioned.

**If this leaks, the user's data is exposed via:** no exposure vector. `proc.sh` reads
`/proc/<pid>/{stat,cmdline,cwd}` for the invoking user's own processes, writes no files, and
transmits nothing.

**Brand-survival threshold:** `none`.

- threshold: none, reason: no personal data is read, stored, or transmitted, and the worst
  failure destroys in-flight local test results rather than user data or money.

The destructive blast radius is nonetheless why the Guard Contract is the centre of this plan.

## Decisions

- **D1 — the helper ships: `plugins/soleur/scripts/lib/proc.sh`, tested at
  `plugins/soleur/test/proc.test.sh`.** An earlier draft placed it at repo-root
  `scripts/lib/`; plan-review reversed that on evidence:
  - ADR-178 §2 (`:110`) lists *"Agent-executed `SKILL.md`"* as a consumer class, and the
    pointer lands in a shipped file. Its precipitating defect (#7409) was seven shipped
    SKILL.md sites invoking a non-shipped path and exiting 127. A repo-root helper would be
    the eighth.
  - ADR-179 decision 4 (`rule-prune` kept at repo root) is **not** a precedent: its
    dispositive test is that the capability's *input cannot exist on a customer machine*.
    `proc.sh`'s inputs are `/proc` and `git rev-parse --show-toplevel`, which exist
    everywhere — and a plugin user running parallel worktrees needs this capability more,
    not less. Decision 4 is also a package (repo root **and** de-advertise **and** a
    monorepo sentinel); the draft took clause one and then advertised on the shipped surface.
  - The threat is not only absence but **shadowing**: on a customer repo, `scripts/` is the
    customer's own directory, so a generic name executes *their* file under an agent — and
    this file's advertised contract is *to send signals*.
  - Cost of the move is ~one line: the file is new with zero existing consumers, and
    `test-all.sh:1196` globs both candidate homes on the same line in the same shard.
  - **Consequence — no new ADR.** The move makes D1 plain compliance with ADR-178 §1 and
    ADR-179 §1 rather than a carve-out in two accepted ADRs.
- **D2 — the test lives at `plugins/soleur/test/proc.test.sh`, NOT beside the library.**
  Shell globs do not cross `/`, and `test-all.sh:1196` covers
  `plugins/soleur/scripts/*.test.sh` but **not** `plugins/soleur/scripts/lib/*.test.sh`
  (while it *does* cover `apps/web-platform/scripts/lib/*.test.sh` — the asymmetry is the
  trap). A suite beside the library would be an orphan gating nothing. This is exactly what
  ADR-178 §Consequences did with `session-state.test.sh`.
- **D3 — the pointer uses bare `${CLAUDE_PLUGIN_ROOT}`.** ADR-179 decision 1 rejects `:-`
  and `:?`; the #7442 learning showed `:-./plugins/soleur` expands to the CWD-relative
  defect. Unset, the bare form yields `/scripts/lib/proc.sh` and fails loudly — fail-closed.
- **D4 — mirror `test-contention.sh`'s primitives; do not source it.** Now **forced**, not
  preferred: a shipped plugin file cannot source repo-root `scripts/lib/test-contention.sh`
  without reintroducing the exact ADR-178 defect. `session-state.sh` sets the norm — a
  shipped primitive sources nothing external. ~4 helpers (`_stat_field`, `_ppid`, `_pgrp`,
  `_self_and_ancestors`, ≈24 lines) are copied with their rationale comments; AC7 pins them
  against drift. Seams are **namespace-prefixed** (`PROC_SH_ROOT`, `PROC_SH_SELF_PID`,
  `PROC_SH_WORKTREE`) because `scripts/tmpfs-guard.sh:84` already binds a bare `PROC_ROOT`
  and `proc.sh` is sourceable.
- **D5 — signal individual PIDs, never a process group.** `kill -TERM 0` can reach the
  parent (2026-05-12 learning). Default `TERM`; optional signal argument; no auto-escalation.
- **D6 — `killed=N refused=M skipped_same_pgroup=P scanned=K` on every `kill_mine` run.**
  The pgid exclusion is load-bearing (see Hidden Assumption below) but it can *legitimately*
  suppress a real target: under a non-interactive shell without job control, a `test-all.sh`
  launched with `&` from the same shell shares its pgid. A bare `killed=0` would then read
  as "nothing to kill" and send the operator back to `pkill` — the precise failure the
  counters exist to prevent, reappearing one level down. `P` is counted separately so that
  "excluded by my own guard" never prints the same as "nothing matched".

**Hidden assumption, stated because the design depends on it:** `proc.sh`'s own command line
matches `proc.sh`'s own predicate — `bash …/proc.sh kill_mine test-all.sh` carries
`test-all.sh` as a whitespace-free later token under a shell argv[0]. That is the entire
reason the pgid exclusion is required (proc.sh's command-substitution forks match, and are
not ancestors). It goes in the header above the exclusion, so a later simplifier does not
remove it on the grounds that ancestry already covers P3.

## Files to Create

- `plugins/soleur/scripts/lib/proc.sh` — the library. Dual-mode (sourceable + CLI dispatch),
  self-contained, double-source guarded.
- `plugins/soleur/test/proc.test.sh` — the suite. Synthesized procfs only; signals nothing real.

## Files to Edit

- `plugins/soleur/skills/work/SKILL.md` — one pointer at the `pkill` clause.

## Open Code-Review Overlap

`None`. Queried `gh issue list --label code-review --state open --limit 200` and matched each
planned path against every issue body via `jq --arg`: zero matches.

## Guard Contract

Every mutation below is applied to a **copy** of the real `proc.sh` in a sandbox, proven
landed with `diff -q` against a pristine backup, and run in the same harness that produced a
GREEN baseline. The anchor is asserted present before replacement, so an anchor that drifts
fails loudly rather than silently no-opping into a mutation that never landed and a mutant
that "survives".

Each guard carries its own matrix. That is not bookkeeping: carving the mutations per guard
is what surfaced that Guard 1 had only **two** rows under the original single shared table
(M1 and M4), while M5 — filed under "the parse" — actually buys Guard 2. M6 was added to
close that gap rather than to reach a floor.

### Guard 1 — `kill_mine` signals only processes this worktree owns

**Property.** No process whose resolved cwd lies outside the current worktree is ever
signalled, and no process that merely *mentions* the pattern is ever signalled.

**Assembly.** Every pid produced by the single `/proc` walk reaches exactly one of
`{signal, refuse}`, and only `signal` rows reach the **one and only `kill` call site in the
file**. The assembly is structural — a second `kill` site anywhere in `proc.sh` is a contract
violation, asserted over non-comment lines by AC8.

**Mutation matrix:**

| # | Mutation | Must drive RED because |
|---|---|---|
| M1 | Drop the `/` boundary from the prefix test (`"$cwd" == "$root"*`) | A sibling worktree at `<ROOT>-two` must not be selected when ROOT is `<ROOT>`. The highest-risk one-character defect in the file. |
| M4 | Remove the argv-position discipline (fall through to a bare token match) | A process merely *mentioning* the pattern (`grep -rn test-all.sh scripts/`) must not be selected — otherwise `kill_mine test-all.sh` kills the operator's own grep, from inside their own worktree, where the cwd test cannot save them. |
| M6 | Rewrite the `refuse` arm of the classification fork to emit `signal` | The fork itself must be load-bearing. Without this row, "every pid reaches exactly one of `{signal, refuse}`" is asserted by reading rather than by measurement, and a collapsed fork would leave M1 and M4 both green. |

### Guard 2 — neither verb ever self-matches

**Property.** Neither `list_runs` nor `kill_mine` reports or signals the invoking process,
any ancestor, or a fork sharing its process group — **even though the pattern appears
verbatim in the invoker's own command line**.

**Assembly.** The exclusion block at the top of the walk's loop body, before classification.
Every emitted row passes through it. Both exclusions depend on `/proc/<pid>/stat` parsing, so
the parse is part of this assembly rather than a separate concern — which is why M5 is filed
here.

**Mutation matrix:**

| # | Mutation | Must drive RED because |
|---|---|---|
| M2 | Narrow the ancestry exclusion to `$$` + `$PPID` (`guard < 2`) | A 3-deep invocation (`bash -c 'bash proc.sh kill_mine <pat>'`) must still exclude the wrapper. **Pins R1** — the issue's own prescribed exclusion set is what this row falsifies. |
| M3 | Delete the own-pgid exclusion | A same-cmdline fork of `proc.sh` sharing its pgid must not be selected. Command-substitution forks are not ancestors, so ancestry alone does not cover them. |
| M5 | Replace the `') '` last-occurrence strip with the naive whole-line index (`awk '{print $4}'`) | A process whose `comm` contains a space must still resolve its ppid. Both exclusions above read ppid/pgrp through this parser, so breaking it silently disables *both*. **Pins R4** — the bug in the `/proc` recipe currently recommended in `git-worktree/SKILL.md`. |

**Anti-vacuity.** T3 is a positive control that no mutation row can substitute for: it spawns
a real `setsid sleep` inside a fresh mktemp sandbox, proves `list_runs` finds it, proves
`kill_mine` reports `killed=1`, and proves the process actually terminated. Any mutation that
makes the walk emit nothing fails it, and it is the only arm that exercises the real signal
path rather than the dry-run seam.

## Implementation Phases

### Phase 0 — Baseline

**Baseline on `origin/main`, never local `main`.** Run `git fetch origin main` first.
Measured in this worktree on 2026-08-13: local `main` is `0d644396` while `origin/main` is
`63b80b78`, two commits ahead — one being `perf(test-all): relevance-gate the C4 producer
e2e suite…` (#7495), which **edits `scripts/test-all.sh`**. Diffing against local `main`
reports a spurious `+64/-1` on that file and false-fails AC5; `git diff --stat
origin/main...HEAD -- scripts/test-all.sh` is empty, which is the true baseline. Use the
three-dot form.

### Phase 1 — RED: `plugins/soleur/test/proc.test.sh`

Written **before** the library (`cq-write-failing-tests-before`), mirroring
`plugins/soleur/test/session-state.test.sh:1-31`: `set -uo pipefail`, `SCRIPT_DIR`/`HELPER`
resolution, `PASS`/`FAIL` counters, `ROOTS=()` + `trap cleanup EXIT`.

Builds a synthesized procfs (the `scripts/test-contention.test.sh:43` pattern) containing: a
run owned by **this** worktree; a run owned by a **sibling**; a sibling whose path is the
current root plus a suffix (the M1 boundary fixture); a process merely *mentioning* the
pattern; a process whose `comm` contains a space; an `<unreadable>` cwd; a process sharing
the invoker's pgid; and the synthetic self + ancestor chain.

Asserts the three issue-mandated proofs (self-match does not occur; a sibling-worktree PID is
refused; the invoking shell survives), the five mutation rows, and the positive control.

### Phase 2 — GREEN: `plugins/soleur/scripts/lib/proc.sh`

Header records why the file exists, the issue's three-part selection criterion, the
`test-contention.sh:151` origin, why bracket-safety is a category error here, and the hidden
assumption above the pgid exclusion.

- Double-source guard; dual-mode dispatch per `session-state.sh:611`.
- Seams: `PROC_SH_ROOT` (default `/proc`), `PROC_SH_SELF_PID` (default `$$`),
  `PROC_SH_WORKTREE` (default `git rev-parse --show-toplevel`; **fails loudly** otherwise).
- `_stat_field` with the `') '` strip; `_ppid`; `_pgrp`; `_self_and_ancestors` (64-step guard).
- **One** walk over `$PROC_SH_ROOT/[0-9]*`, shared by both verbs: exclude self+ancestry →
  exclude own pgid (counting `P`) → argv-position match → `readlink cwd` → classify
  `signal` / `refuse`.
- `list_runs` is that walk with the signal suppressed — same row shape, one formatter.
- `kill_mine` signals only `signal` rows, prints each refusal with its owning worktree, and
  always ends with the D6 counter line. The `/` boundary carries an inline comment.
- Canonicalize both sides of the cwd comparison before comparing.

### Phase 3 — The pointer

One edit in `plugins/soleur/skills/work/SKILL.md`. The hazard sentence is **preserved** and
only the mechanism is replaced, so guidance degrades to the prohibition rather than to
silence:

> Related: never `pkill -f <pattern>` where the pattern appears in the pkill command line
> itself — it matches and kills the invoking shell. Use
> `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lib/proc.sh" list_runs <pattern>` to see who owns each
> match, and `… kill_mine <pattern>` to signal only this worktree's; both resolve ownership
> through `/proc/<pid>/cwd` and exclude self, ancestry and own process group, which a bracket
> pattern cannot do.

### Phase 4 — Verify

Run the suite directly, then confirm auto-discovery through the runner.

## Acceptance Criteria

### Pre-merge (PR)

1. `plugins/soleur/scripts/lib/proc.sh` exists, defines `list_runs` and `kill_mine`, and
   sources cleanly: `bash -c 'source plugins/soleur/scripts/lib/proc.sh; declare -F list_runs kill_mine'`
   prints both names and executes nothing.
2. `list_runs <pattern>` invoked with a pattern that **appears in its own command line**
   reports zero rows attributable to itself, its ancestors, or its process group, and the
   invoking shell is alive afterwards (`[[ -d /proc/$$ ]]`).
3. `kill_mine` signals no pid whose resolved cwd is outside the current worktree, and prints
   `killed=N refused=M skipped_same_pgroup=P scanned=K` on **every** invocation.
4. `bash plugins/soleur/test/proc.test.sh` exits `0` and prints no `FAIL:` line.
5. **Auto-discovery, not hand-registration.** `git diff --stat origin/main...HEAD -- scripts/test-all.sh`
   is empty, **and** the runner registers the suite exactly once:

   ```bash
   TEST_GROUP=scripts bash scripts/test-all.sh 2>&1 \
     | grep -cx -- '--- plugins/soleur/test/proc.test.sh ---'   # must be 1
   ```

   **Anchor on the `--- <label> ---` header line, not on the bare path.** `run_suite`
   (`scripts/test-all.sh`, `echo "--- $label ---"` at the top of the body and
   `echo "[ok] $label (${elapsed_ms}ms)"` in its `ok` arm) emits the label **twice per
   registration**, so a bare `grep -c '<path>'` returns `2` for a correctly-registered suite and
   would fail this criterion against a correct implementation. The header line is emitted once
   per `run_suite` call, which is precisely the quantity being asserted. `-x` is load-bearing
   too: the suite's own stdout may echo its path, and only a full-line match excludes that.
   Exactly-one is the assertion because D2's glob asymmetry makes `0` a live failure mode and a
   stray hand-registration would make it `2`.
6. Mutation rows M1–M6 are each proven: baseline GREEN, mutant RED, mutation confirmed landed
   via `diff -q` against a pristine backup, in the same harness, against a sandbox copy of the
   **real** `proc.sh`.
6a. `python3 scripts/lint-guard-contract.py` passes on this plan — every guard entry above
   carries a non-placeholder property, a non-placeholder assembly, and its own mutation matrix
   of at least three rows.
7. The four mirrored primitives are pinned against drift from `scripts/lib/test-contention.sh`
   by code-anchored `grep -F` assertions (not bare tokens, per `cq-assert-anchor-not-bare-token`).
8. **Single chokepoint (Guard 1), asserted over code only.**

   ```bash
   grep -vE '^[[:space:]]*#' plugins/soleur/scripts/lib/proc.sh \
     | grep -cE '(^|[^_[:alnum:]])kill[[:space:]]+-'            # must be 1
   ```

   The comment strip is required, not cosmetic: the header deliberately discusses `pkill` and
   the kill semantics, so a bare `grep -c '\bkill '` over the whole file counts prose and makes
   the assertion fail on a correct implementation — the same defect as AC5. The
   `[^_[:alnum:]]` prefix keeps `kill_mine` (the function name) and `killed=` (the D6 counter)
   from matching; the trailing `-` matches the signal flag of a real invocation. If the
   implementation needs a second literal `kill` for a non-signalling purpose (e.g. `kill -l`
   to name a signal), that is a contract violation of Guard 1 as written — route it through a
   different mechanism rather than relaxing this count.
9. `plugins/soleur/skills/work/SKILL.md` contains exactly one occurrence of
   `scripts/lib/proc.sh`, uses the **bare** `${CLAUDE_PLUGIN_ROOT}` form (no `:-`, no `:?`),
   and **still contains** the hazard sentence `it matches and kills the invoking shell`.
10. No new AGENTS rule: `git diff origin/main...HEAD -- AGENTS.md AGENTS.rules.md` is empty.
11. `plugins/soleur/test/proc.test.sh` never signals a process it did not synthesize: no
    `kill ` call outside a `PROC_SH_ROOT`-seamed sandbox, and the run leaves the invoking
    shell alive.
12. PR body carries `Closes #7525`.

### Post-merge (operator)

None. Every criterion is executable in-session.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `list_runs` with the pattern present in its own argv | zero self rows; synthesized sibling still listed |
| T2 | Sibling worktree at `<ROOT>-two` | refused (M1 boundary) |
| T3 | Run owned by the current worktree | signalled; `killed=1` **(positive control / anti-vacuity)** |
| T4 | 3-deep wrapper invocation | wrapper excluded (M2) |
| T5 | Process merely mentioning the pattern | not selected (M4) |
| T6 | Process whose `comm` contains a space | ppid resolves (M5) |
| T7 | Target sharing the invoker's pgid | refused, and counted in `skipped_same_pgroup` — never silently absorbed into `killed=0` |
| T8 | `<unreadable>` cwd | refused and printed, never signalled |
| T9 | Outside a git repo with `PROC_SH_WORKTREE` unset | fails loudly, non-zero, signals nothing |

## Observability

The library writes no files and has no runtime. Its signal is the suite: auto-globbed into
`scripts/test-all.sh:1196` (`plugins/soleur/test/*.test.sh`, `test-scripts` shard, a required
check), exiting non-zero with `FAIL:` lines on failure.

```yaml
discoverability_test:
  command: bash plugins/soleur/test/proc.test.sh
  expected_output: exit 0, no line matching `^FAIL:`
```

## Gates evaluated and skipped

- **1.4 Network-outage** — no SSH/connectivity keywords.
- **2.7 GDPR** — no regulated-data surface; no schema, auth, API route, or `.sql` file.
- **2.8 IaC** — no server, service, secret, vendor, or persistent runtime process.
- **2.10 ADR/C4** — **no new ADR** (D1 conforms to ADR-178 §1 and ADR-179 §1 after the move)
  and **no C4 impact**, established by reading all three model files: the four external
  actors (`model.c4:8,14,22,35`) are unchanged; no external system is reached (`proc.sh`
  touches only the local kernel's procfs, which is not a modelled boundary); no container or
  data store changes; the edited file is the body of `work = component "work skill"`, already
  modelled, and adding prose to a modelled component changes no element or edge; no
  `views.c4` include needs adding.
- **2.11 Encryption posture** — no persistent store, no cross-component connection.
- **1.8 Skill-description budget** — no `description:` frontmatter is edited.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A destructive helper is more dangerous than the prose it replaces.** | Five mutation rows plus a positive control; `list_runs` is a dry-run; `kill_mine` refuses by default and reports every refusal. |
| **Prefix-boundary bug kills a sibling worktree** — the bug the issue is about. | M1 fixture uses `<ROOT>-two`; the `/` boundary carries an inline comment and is the suite's highest-value assertion. |
| **The suite lands beside the library and silently gates nothing.** | D2; AC5's `grep -c … == 1` fails on `0` as well as `2`. |
| **`skipped_same_pgroup` reads as "nothing to kill".** | D6 counter + T7 + a Non-Goals entry. |
| **Discovery** — the issue's own stated top risk. | One pointer on the surface the failing session had loaded; the hazard sentence is preserved so absence degrades safely. |
| **Drift from the mirrored primitives.** | AC7 code-anchored pins; header cites the origin. |
| **Symlinks make every comparison fail**, so `kill_mine` refuses everything and looks correct. | Canonicalize both sides (Phase 2); T3 is the positive control that fails if nothing is ever signalled. |

## Non-Goals

- **Signalling a target that shares the invoker's process group.** Refused by design (the
  pgid exclusion is what stops `proc.sh` killing its own forks), surfaced via
  `skipped_same_pgroup` and T7. The documented workaround is the one this repo already
  recommends for the gate: launch under `setsid nohup`, which creates a new pgid.
- **Reaping descendants that `cd`'d into a `mktemp -d` sandbox** (R5). Such processes are
  *reported* by `list_runs`, never silently skipped. Deferral issue filed at ship time per
  `wg-when-deferring-a-capability-create-a`.
- Escalating `TERM` to `KILL` (D5).
- Fixing the `scripts/followthroughs/*.test.sh` orphan blind spot — **#7523**.
- Draining the repo-root `scripts/` CWD-shadow class — **#6222**.
- Adding an always-loaded AGENTS rule (premise 4).
- Editing `git-worktree/SKILL.md:371`. The issue mandates *exactly one* pointer; that
  bullet's value is its evidence. Its naive `awk '{print $4}'` snippet (R4) is noted for
  follow-up rather than changed here.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Repo-adjacent developer tooling with a destructive capability, now shipping
inside the plugin payload. Concerns and dispositions: exclusion completeness (widened from
`$$`/`$PPID` to full ancestry + pgid, R1); scope-boundary correctness (M1); placement and
shadowing (D1, reversed on ADR-178/179 evidence); suite-orphan risk from the glob asymmetry
(D2); the pgid blind spot (D6/T7); drift from the mirrored primitives (D4/AC7). No product,
legal, finance, marketing, sales, support, or operations implication: no data is processed,
no vendor or recurring cost is introduced.

**Product/UX Gate:** not applicable — Tier **NONE**. The mechanical UI-surface override was
run against `## Files to Create` and `## Files to Edit`; no path matches `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface term.

## Plan Review

Panel: `kieran-rails-reviewer` (correctness), `code-simplicity-reviewer` (YAGNI),
`architecture-strategist` (placement). Applied:

- **Architecture (blocking, applied):** D1 reversed from repo-root to the plugin payload on
  ADR-178 §2 + ADR-179 decision-4 evidence; D2 added for the glob asymmetry; D3 switched to
  the bare anchor; the 2.10 skip claim corrected.
- **Simplicity (applied):** cut `elapsed_s`, cut the third classification, collapsed
  `list_runs`/`kill_mine` to one walk and one row shape, dropped the mutation battery from 8
  rows to 5 plus a positive control, dropped the `exit 64` contract, compressed the C4,
  Observability, and Domain Review blocks, and removed the Phase 0 re-verifications.
- **Simplicity (applied, addition):** the same-pgid blind spot — D6 counters, T7, Non-Goals.
- **Simplicity (rejected, with reason):** "source `test-contention.sh` instead of mirroring."
  Sound in isolation, but incompatible with the architecture finding — a shipped plugin file
  cannot source a repo-root library without reintroducing the ADR-178 defect. Mirroring is
  now forced; the drift cost is paid by AC7 (D4).
- **Correctness (applied on recovery, blocking ×2).** The correctness arm's findings were
  never applied by the planning subagent — it stalled on the harness stream watchdog while
  verifying them, and a re-spawn stalled identically, so the arm was completed inline against
  the runner source rather than re-spawned a third time. Two acceptance criteria were
  **self-defeating**: each would have failed against a *correct* implementation, which is the
  worst failure mode an AC has, because the fix looks like a bug.
  - **AC5** anchored on the bare suite path. `run_suite` emits its label twice per registration
    (`--- $label ---` at the head of the body; `[ok] $label (…)` in the `ok` arm), so the
    prescribed `grep -c` returns `2` for a correctly auto-globbed suite. Re-anchored on the
    `--- <label> ---` header with `grep -cx`, which is emitted exactly once per `run_suite`
    call — the quantity AC5 actually means.
  - **AC8** counted `\bkill ` across the whole file, including the header comments that
    deliberately discuss `pkill` and the kill semantics. Re-scoped to non-comment lines with a
    prefix class that excludes `kill_mine` and `killed=`.
  - **Verified, not accepted on assertion:** D2's glob asymmetry is real —
    `scripts/test-all.sh`'s glob line lists `plugins/soleur/test/*.test.sh` and
    `plugins/soleur/scripts/*.test.sh` but no `plugins/soleur/scripts/lib/` entry, and shell
    globs do not cross `/`. The premise-6 falsification (auto-discovery, not hand-registration)
    therefore stands, and AC5's `0` failure mode is live.
