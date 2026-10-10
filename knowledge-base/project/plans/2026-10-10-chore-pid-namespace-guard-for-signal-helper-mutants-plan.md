---
title: "chore: run mutants of process-signalling helpers only inside a PID namespace (helper, allocator verb, seat briefs, inventory scan)"
type: chore
date: 2026-10-10
slug: pid-namespace-guard-for-signal-helper-mutants
branch: feat-one-shot-pid-namespace-guard-signal-helpers
issue: 9217
closes: none
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# chore: run mutants of process-signalling helpers only inside a PID namespace

## Overview

On 2026-10-09 an observer mutant of one converted line (`grep -c` to `grep -vc`) inside a helper in
`plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` ended the operator's desktop session four
times. The helper walks `$PPID` upwards and sends SIGTERM to the outermost ancestor whose argv matches; with
the match inverted every ancestor matches and the walk reaches the top of the session. S5 (PR 9841, merged as
`de6d0c447f`; tracker 9217, Ref only) bounded that one helper at the suite's own PID and recorded the incident
(`knowledge-base/project/learnings/test-failures/2026-10-09-an-inverted-match-mutant-of-an-ancestor-walking-helper-ended-the-desktop-session-four-times.md`),
and deferred the wider hardening to this change, at the operator's request ("update our workflow and skills to
avoid that issue in the future for us or soleur users").

This change makes the safe way the easy way and finds the next hazard before someone mutates it:

1. **A helper** `plugins/soleur/scripts/run-in-pid-namespace.sh` that runs a command inside
   `unshare -Urpf --kill-child --mount-proc` and refuses (rc 125, a named marker line, the command never
   started, no unsandboxed fallback) when unprivileged user namespaces are unavailable. It lives under
   `plugins/soleur/scripts/` so plugin users get it, and so its suite registers through the existing
   `plugins/soleur/scripts/*.test.sh` glob with no runner edit.
2. **Rule wiring**: a `run-isolated <sandbox> -- <cmd>` verb on `scripts/soleur-sandbox.sh`, a section in
   `work-scratch-sandboxes.md`, a pointer in the review skill's mutating-seat brief, a bullet in the review
   fix-round brief reference, a bullet in the test-design-reviewer agent, and one entry in the plan skill's
   sharp-edges catalogue (the incident began in a plan that prescribed "flip every converted line").
3. **An inventory scan** `plugins/soleur/scripts/scan-ancestor-signal-helpers.py` with a content-keyed,
   shrink-only baseline, run by its own suite in the full CI battery, listing shell test suites that contain an
   ancestor-walking signal helper (gated), a signal to the parent or an all-process signal (gated), and, as a listing only, targeted group and name-pattern signals.
4. **A second unbounded walker, found by the prototype scan**, in `plugins/soleur/test/roadmap-reconcile.test.sh`
   (the `term` branch of the fake `gh`): same shape, bounded only by its own match predicate. It gets the same
   bound S5 gave the first one, so the baseline never records an unbounded walker.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation: brief and trackers vs measured reality

| Brief or tracker claim | Reality (command or file) | Plan response |
| --- | --- | --- |
| "S5 already bounded that one helper (`SOLEUR_TEST_SUITE_PID`)" | True: `resolve-regenerable-conflicts.test.sh` lines 548-569 export `SOLEUR_TEST_SUITE_PID=$$` and the heredoc helper exits 0 when it is unset and stops the walk at that PID | Kept as is; the scan must classify it `bounded` |
| "a helper ... that walks `$PPID` upwards" (singular) | A prototype scan over tracked `*.test.sh` and `test-*.sh` (1 `git ls-files` call) finds **two** ancestor-walkers: that helper and `plugins/soleur/test/roadmap-reconcile.test.sh` lines 271-277 (`p=$PPID; top=""; while [[ -r /proc/$p/cmdline ]] && ... grep -c 'roadmap-reconcile.sh'; do top=$p; p=$(awk '{print $4}' /proc/$p/stat); done; kill -TERM "$top"`). Its only bound is its own predicate; it has no `-gt 1` and no suite-PID bound. `grep -vc` over its one-line `tr` output happens to stop at the first ancestor, a catch-all pattern does not | Bound it in this change (Phase 5); the scan's rule "a baselined walk must be bounded" then holds for both |
| "an inventory scan ... lists shell test suites containing an ancestor-walking signal helper or other signal-to-ancestors patterns" | Prototype (scratchpad, not committed) over 700+ tracked suites: ancestor-walk 2, signal to `$PPID` 5 (`arm-heartbeats`, `git-data-luks-reopen`, `workspaces-boot-unlock`, `workspaces-luks-provision` x2), all-process signal (`kill 0`, `kill -1`) 0, targeted group signal (`kill -- -$pgid`, `pkill -g`) 8 and name-pattern signal (`pkill` by name) 6 | Gated classes W, P, G (baseline 7 rows at introduction); targeted group and name-pattern signals are class L, listed by `--list`, not gated |
| "new suites must be registered the way this repo registers suites" | `scripts/test-all.sh` `SUITE_GLOBS` carries `plugins/soleur/scripts/*.test.sh`; `scripts/lint-orphan-test-suites.sh` treats a glob-matched suite as covered (surface 2, patterns asked of the runner). `tests/scripts/test-soleur-sandbox.sh` is already an explicit `run_suite` line (`scripts/test-all.sh` line 5107). A suite absent from `scripts/suite-shard-legs.tsv` hash-falls-back into a shard leg by design (`.github/workflows/ci.yml` comment "Untabled labels (added since the last regen) hash-fallback at runtime"); `pipeline-tally.test.sh` got its row (line 93) from a later regen, not from the PR that added it, and `plugins/soleur/test/scripts-shard-manifest.test.sh` only rejects phantom rows, not missing ones. A regen (`python3 scripts/regenerate-shard-manifest.py --incremental --write`) is optional and left out so the diff does not touch the table | Both new suites go under `plugins/soleur/scripts/` and need no registration edit. No edit to `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` or the shard tsv |
| "`unshare -Urpf --kill-child --mount-proc`" is available | Locally: util-linux 2.42.3, rc and `$$ == 1`, `$PPID == 0` observed, rc propagates, nested use works (an inner `unshare -Urpf` inside the outer one printed `pid=1 ppid=0`). On CI: ubuntu-24.04 restricts unprivileged user namespaces through AppArmor; `.github/workflows/ci.yml` relaxes `kernel.apparmor_restrict_unprivileged_userns` best-effort on the scripts leg, and `apps/web-platform/infra/inngest-cutover-latch.test.sh` records `unshare -rm` failing with "write failed /proc/self/uid_map: Operation not permitted" | The suite must be green both ways: refusal rows run for real where the namespace is unavailable, containment rows run where it is, each branch counted, neither silently skipped |
| "do NOT edit `plugins/soleur/skills/work/SKILL.md`" | `work/SKILL.md` already points at `work-scratch-sandboxes.md` (lines 903 and 919), and the allocator is briefed from three places only: `work/SKILL.md`, `review/SKILL.md` line 217 and `test-design-reviewer.md` (`git grep -l "soleur-sandbox\|work-scratch-sandboxes"` over `plugins .claude scripts`) | The rule goes in the pointed-to reference, so the work skill carries it without an edit |
| `review/SKILL.md` can take a note | `plugins/soleur/test/skill-body-budget.json` pins `review` at 477000 bytes; the file is 476678 (322 bytes of headroom). `lint-skill-body-budget.py` reads the ceiling from the merge base, so it cannot be raised in the same diff | One pointer of at most 220 bytes in the existing line-217 paragraph; the substance goes in `risk-tier-and-fix-rounds.md` and the allocator reference. If the byte count does not fit, the SKILL.md pointer is dropped and the other four surfaces carry the rule. `plan/SKILL.md` is at 119972 of 120000, so it is not touched |
| "the PR body must say what a merge fires" | Derived below (Workflows fired) with a matcher run over the final file list | Stated as the first line of the PR body |
| `origin/main` state | Two commits ahead of the branch base (`5c533f38f8` #9889, `8eafe0741d` #9899, an infra pin and a canary vitest config); neither touches a planned file. Open PR #8626 edits `plugins/soleur/skills/review/SKILL.md` | Phase 0 merges `origin/main` once. If #8626 lands first the byte headroom is re-measured before the pointer is written |
| Codemod hand-edits ledger | `roadmap-reconcile.test.sh` was converted by S2 (#9765). `scripts/grep-q-drain-codemod.py verify --base REF --hand-edits FILE` is per-slice, run only inside a slice; this change is not a slice and carries no ledger | Phase 0 greps open PRs for a grep-q slice touching `roadmap-reconcile.test.sh`; if one exists its ledger gains an entry there. Nothing else |

## Research Insights

### Premise Validation

Checked 2026-10-10. Issue #9217 is OPEN (cited as `Ref` only; no closing keyword anywhere in this change). PR 9841 is MERGED
(`de6d0c447f`, 2026-10-09T23:38Z). PR 8631 is MERGED. The cited learning and the S5 spec files
(`evidence.md` incident note, `decision-challenges.md` items 28 and 29) exist and were read. The mechanism
(a PID namespace around a mutant) is in no rejected-alternatives table of the ADR corpus: the only `unshare`
uses in the repo are the bwrap-userns seccomp family under `apps/web-platform/` (sandbox canary, a different
subject) and `scripts/audit-suite-reads.sh` (a network namespace for a read recorder); neither is a reusable
isolation helper. `git grep -n "unshare -"` over non-knowledge-base paths returns the S5 comments, the canary
probes and the audit script. The functional-overlap check found no community artifact with a namespace
helper or a signal-helper lint (three generic "mutation-testing" skills with no isolation; one microVM
sandbox skill rejected by the trust filter). The learnings search found no prior learning on ancestor walks
(the gap this change fills); nearest: `2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md`
(`kill -TERM 0` inherits the parent's group and can kill the operator's session),
`2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md` (key a baseline by identity),
`2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint.md` (the baseline shape),
`2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` (positive controls),
`2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md` (AppArmor userns drift).

### Property List and Cut List

Properties (each observable):

- P1. A command started through the helper is PID 1 of a fresh PID namespace with its own `/proc`, so an ancestor walk inside it ends at itself; if that cannot be arranged the command does not start, the exit code is 125 and stderr carries a one-line marker.
- P2. A seat or lead that is told to mutate a line inside a signalling or file-removing helper is told, at the point of the instruction, to run it through the helper and what rc 125 means; the surfaces that brief seats carry it.
- P3. A shell test suite that contains a signal-to-ancestors helper (or a group or pattern signal) is listed before anyone mutates it, and a new one fails the full battery until it is bounded and baselined.
- P4. No baselined ancestor walk is unbounded.
- P5. The merge fires only what is predicted below.

Mechanisms the ask names and what each buys: the helper (P1), the allocator verb (P2: a copy-pasteable
command inside the existing allocation recipe), the reference-doc section and the seat/agent bullets (P2), the
scan with baseline (P3, P4), the roadmap-reconcile bound (P4).

**Cut List** (mechanism, property, what already covers it):

| Cut | Property it would buy | What already covers it |
| --- | --- | --- |
| Gating targeted group and name-pattern signals (14 more baseline rows) | "signal-to-ancestors" coverage | They are not signals to ancestors; `--list` shows them (class L) |
| A receipt line, a hand-written `unshare` fallback line in the doc, an `unsupported-os` reason and its row | auditability, a no-script path, macOS coverage | The marker line, the helper's path and rows R1 and R8 already buy them |
| An `AGENTS.rules.md` hard rule for "mutants of signal helpers run in a PID namespace" | P2 | `cq-agents-md-tier-gate`: the violation can only occur inside mutation-seat briefs, which the reference doc and the two briefing surfaces already reach; an always-loaded rule costs every session (ADR-151) |
| A `--probe` mode and an `--assert-inside` mode on the helper | "a driver refuses to run a mutant outside" | Starting the mutant through the helper is the enforcement; an opt-in assertion inside an ad hoc driver is as optional as the helper call it would guard |
| Write confinement (bwrap `--ro-bind`, a read-only remount) for file-removing mutants | blast radius of `rm -r` mutants | The allocated sandbox is a copy with no `.git`; the PID namespace does NOT confine writes, and the doc says so in one sentence. bwrap is not available everywhere; recorded as a taste item in `decision-challenges.md`, not deferred to an issue |
| Editing `scripts/lib/test-affected-paths.sh` to classify the scan's suite ALWAYS_ON | local `--affected` selects the ratchet when a new walker lands anywhere | Not needed to pass any gate (the suite's own source carries no corpus-walk idiom: its live row delegates the walk to the scanner). CI's required `test` check runs the whole battery. Recorded in `decision-challenges.md` as the trade-off, not hidden |
| A merge-base "baseline may only shrink" check | anchor outside the commit | Needs a fetched `origin/main` the test legs do not guarantee (the body-budget lint needed a dedicated `fetch-depth: 0` job for the same reason); a check that skips at depth 1 is an inert mechanism. Stated honestly as consistency, not integrity, in Guard 2's Anchor |
| Scanning non-suite scripts, python or TypeScript tests | wider recall | The brief asks for shell test suites. `--paths` lets any file be scanned; the blind spots are listed in the scan's docstring |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
| --- | --- | --- | --- |
| 1 | "a small reusable helper script that runs a command inside `unshare -Urpf --kill-child --mount-proc` and fails closed (non-zero, named message, never an unsandboxed fallback) when unprivileged user namespaces are unavailable, with a test" [brief (1)] | `plugins/soleur/scripts/run-in-pid-namespace.sh` + `.test.sh` (Phase 1), Guard 1 | mapped |
| 2 | "wire the rule into the mutation-seat/observer guidance: plugins/soleur/skills/work/references/work-scratch-sandboxes.md and the sandbox allocator scripts/soleur-sandbox.sh (a note or a `run-isolated` verb)" [brief (2)] | Phase 3 (verb, Guard 3) and Phase 4 (reference section) | mapped |
| 3 | "the review skill's fix-round/mutation-seat brief text under plugins/soleur/skills/review/ and the test-design-reviewer agent guidance where it prescribes flipping/mutating lines" [brief (2)] | Phase 4: `review/SKILL.md` pointer, `references/risk-tier-and-fix-rounds.md` bullet, `test-design-reviewer.md` bullet | mapped |
| 4 | "so a brief that asks a seat to mutate a line inside a process-signalling or file-removing helper names the PID/mount-namespace requirement" [brief (2)] | The seat-brief sentence in the reference doc (copy-paste text) and the three briefing surfaces | mapped |
| 5 | "an inventory scan (a script plus test, ideally a lint or ratchet with a baseline) that lists shell test suites containing an ancestor-walking signal helper (PPID walk plus kill) or other signal-to-ancestors patterns" [brief (3)] | Phase 2: scan, test, baseline, Guard 2 | mapped |
| 6 | "do NOT edit plugins/soleur/skills/work/SKILL.md ... do not edit scripts/grep-q-drain-codemod.py, scripts/test-all.sh or scripts/lib/test-affected-paths.sh unless the plan proves it necessary and records why" [brief (4)] | None of the four is edited; the "necessary?" question for `test-affected-paths.sh` is answered in the Cut List | mapped |
| 7 | "new suites must be registered the way this repo registers suites (read scripts/lint-orphan-test-suites.sh and how S5's pair-run found suites)" [brief (4)] | New suites under `plugins/soleur/scripts/` (glob-registered); `lint-orphan-test-suites.sh` run in Phase 6 | mapped |
| 8 | "tracker 9217 is Ref-only if cited at all ... no [skip-deploy-fix-apply] ... the PR body must avoid the words soak, outage, production and Pro and bullets starting with operator verbs, and must not cite a plan path containing the word soak" [brief, standing constraints] | PR-body checklist (AC-14); this plan's path has none of the words | mapped |
| 9 | "do not run local test-all --affected or --print-selection, but do run the cheap repo-global lints (python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt, bash scripts/guard-vacuity-floor.test.sh, bash scripts/lint-orphan-test-suites.sh, shellcheck delta)" [brief] | Phase 6 gate list | mapped |
| 10 | "any mutation battery runs under ulimit -v 6000000, one mutant at a time, and a mutant of a signal-sending helper NEVER runs outside a PID namespace" [brief] | Mutation protocol (Phase 6): every battery runs inside the new helper itself; fixtures are nonce-scoped | mapped |
| 11 | "leave the main checkout's uncommitted .mcp.json and untracked apps/web-platform/1000: and 500 files alone and do not run the session-start .mcp.json restore" [brief] | No task touches the main checkout; all work is in this worktree | mapped |
| 12 | "review-fix commits to codemod-verified files need hand-edits entries" [brief] | Reconciliation row (ledger is per slice); Phase 0 check; entry added only if a slice PR is open | mapped |
| 13 | "State in the plan which workflows a merge of the planned diff fires ... the PR body must say so first" [brief] | `## Workflows fired by a merge` and AC-13 | mapped |
| 14 | "The machine is often contended (load 25 to 33): no heavy local gates in parallel" [brief] | Phase 6 runs gates serially, targeted suites only | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
| --- | --- | --- |
| `run-in-pid-namespace.sh` and its suite | "a small reusable helper script that runs a command inside `unshare -Urpf --kill-child --mount-proc`" | asked |
| Placement under `plugins/soleur/scripts/` | "for us or soleur users" (the request quoted in the brief) | asked |
| `run-isolated` verb on `scripts/soleur-sandbox.sh` and its arms in `tests/scripts/test-soleur-sandbox.sh` | "a note or a `run-isolated` verb" | asked |
| `work-scratch-sandboxes.md` section | "work-scratch-sandboxes.md" | asked |
| `review/SKILL.md` pointer, `risk-tier-and-fix-rounds.md` bullet | "the review skill's fix-round/mutation-seat brief text under plugins/soleur/skills/review/" | asked |
| `test-design-reviewer.md` bullet | "the test-design-reviewer agent guidance where it prescribes flipping/mutating lines" | asked |
| Scan, its suite and baseline | "an inventory scan (a script plus test, ideally a lint or ratchet with a baseline)" | asked |
| Rule "a baselined walk must be bounded" | "so the next one is found before someone mutates it" | asked (the scan exists to find them; a baseline row for an unbounded one would certify the hazard) |
| `plan/references/plan-sharp-edges.md` entry | none in the brief | inferred: the learning's Prevention item 1 says "a plan's 'flip every converted line' step names the helper-class exception", the incident began in a plan, and the brief says to read the learning first; without it the plan skill keeps producing the lethal instruction |
| Bound the walker in `plugins/soleur/test/roadmap-reconcile.test.sh` | none in the brief | inferred: the scan this change ships finds it; leaving a known unbounded ancestor-walking SIGTERM helper in a baseline built to prevent that incident would make the ratchet certify the hazard; the edit is about 8 lines and mirrors S5's bound. Surfaced as a challengeable item in `decision-challenges.md` |
| Nonce-scoped fixture walker in the helper's suite | "a mutant of a signal-sending helper NEVER runs outside a PID namespace" | asked (the suite itself contains a walker; if the helper regresses to run unsandboxed, the fixture must still be inert on the host) |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `scripts`, `tests`, `knowledge-base`
- Planned files: about 26 (18 created: 5 code files, about 9 fixture data files, the plan, tasks, decision-challenges, evidence; 8 edited) | Estimated changed lines: about 1100 (helper 60, its suite 250, scan 220, its suite 300, baseline 10, fixtures 80, allocator 30, allocator arms 60, docs 110, roadmap-reconcile 12)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, over two thresholds on purpose. The brief scopes this as one change with one plan, one test pass and one review; the pieces reference each other (the reference doc names the helper, the verb and the scan; the scan's "bounded" rule needs the roadmap-reconcile bound in the same tree); a split would put a doc that names a missing script in the first PR. If the review panel prefers two PRs the seam is: PR-A = helper + verb + wiring (Phases 1, 3, 4), PR-B = scan + baseline + roadmap-reconcile bound (Phases 2, 5). Recorded in `decision-challenges.md`.

## Problem Statement / Motivation

A mutation seat is told to prove a converted line is observed by flipping it and checking the suite goes red. For
a line inside a helper whose job is to signal processes, flipping the matcher removes the only thing that bounded
the helper. The seat, the brief and the plan each did exactly what they were told; nothing in the workflow named
the helper class as an exception. The existing rules for mutating seats (allocated sandbox, one copy, restore per
row, instrument controls) all concern the *copy of the tree*; none concerns what a mutant can reach *outside* it
(the process tree of the user's session).

## Proposed Solution

### Design decisions (measured or read, not assumed)

**D1. The helper.** `plugins/soleur/scripts/run-in-pid-namespace.sh [--] <command> [args...]`.

- Exit codes: the command's own code on success; **125** when the helper refuses (the convention `timeout` and `env` use for "my own failure"), with a first stderr line `RUN_IN_PID_NAMESPACE_REFUSED reason=<missing-unshare|userns-unavailable|not-isolating> ...` followed by the cause, the remedy hint (the sysctls `kernel.unprivileged_userns_clone`, `kernel.apparmor_restrict_unprivileged_userns`, `user.max_user_namespaces`, a container seccomp profile) and the sentence "no unsandboxed fallback: run the mutant on a host that allows user namespaces, or do not run it". 2 for a usage error. A wrapped command that itself exits 125 without the marker is the command's; a seat distinguishes by the marker line (measured: `unshare` passes the child's code through unchanged, 7 -> 7 and 125 -> 125).
- Flow: (1) no command -> usage, rc 2. (2) `command -v unshare` absent (stock macOS, minimal containers) -> refuse `missing-unshare`. (3) probe: `unshare -Urpf --kill-child --mount-proc -- sh -c 'test "$$" -eq 1'`, stderr captured; non-zero -> refuse with the first line of unshare's stderr. The probe asserts the *property* (the child is PID 1), not merely that `unshare` returned 0, so a wrapper that drops the flags or a stub that runs the command in place is refused as `not-isolating`. The probe is what separates "unshare failed" from "the command exited 1". (4) `exec unshare -Urpf --kill-child --mount-proc -- sh -c '[ "$$" -eq 1 ] || exit 125; exec "$@"' sh "$@"`: one in-namespace re-check keeps the property true at the instant the command starts even if the first probe and this run disagree, and `exec` leaves the command as PID 1 (no ancestor at all). No receipt line: the helper adds nothing to the wrapped command's stderr on the success path.
- The wrapped command has PID-1 semantics (measured: a signal it sends to itself, including `kill -9 $$`, is ignored and it exits 0; SIGTERM sent to the helper from outside does not stop a command with no handler). A caller that wants a bound uses `timeout -k <grace> <secs> <helper> ...`, never a plain `timeout`; SIGKILL of the helper does reap every descendant (`--kill-child`). The helper header and the doc say so in one sentence.
- stdin, stdout, stderr, cwd and environment pass through unchanged; `--kill-child` plus PID 1's exit tear down every descendant (measured: a backgrounded `sleep` is gone when the command exits), so a mutant that backgrounds a process leaves none behind.
- No test-only env seam: tests prepend a stub `unshare` to `PATH`.
- A mount namespace is created (`--mount-proc` needs it) but the filesystem is NOT confined: writes pass through, and so do network and IPC. The helper's header and the doc section say so in one sentence.

**D2. The verb.** `bash scripts/soleur-sandbox.sh run-isolated <sandbox-path> -- <cmd> [args...]`: (1) refuse unless the path is absolute, a real directory (not a symlink), named `soleur-sbx.?*` and holds a regular `.soleur-owned` marker (the verb deletes nothing, so it does not repeat `rm`'s full set of conjuncts; the point is "cwd is an allocated copy, not the live tree"); (2) `cd` into it; (3) `exec` the helper (`$HERE/../plugins/soleur/scripts/run-in-pid-namespace.sh`); a missing helper is rc 2, never a direct run of the command. `scripts/lib/scratch-root.sh` (the delete path) is not touched. Together: the namespace bounds signals, the copy bounds file removal.

**D3. The scan.** `plugins/soleur/scripts/scan-ancestor-signal-helpers.py [--root DIR] [--baseline FILE] [--list] [--write-baseline FILE] [PATH ...]`.

- Population: `git -C ROOT ls-files '*.test.sh' ':(glob)**/test-*.sh'` (one call, the single chokepoint), or the explicit PATHs. An empty population, a failed `git`, or an unreadable baseline is rc 3 `UNRESOLVED`, never a clean report.
- Classes. A finding is one source line, content-keyed.
  - **W** (gated) ancestor walk with a signal: a self-referential cursor assignment (`v=$(... /proc/$v/stat ...)`, `v=$(ps -o ppid= -p $v)`, `v=$(... $v ... PPid ...)`) with `kill`, `pkill` or `killall` within 40 lines either side. 40 lines because the known helper's cursor and its `kill` sit 12 lines apart and heredoc helpers are short; raw text, so heredoc and string-embedded helpers count. Reported `bounded=yes` only when a NON-COMMENT line from 15 lines above to 3 lines below the cursor line (the S5 helper's guard and loop condition sit 6 and 7 lines above its cursor) mentions `SOLEUR_TEST_SUITE_PID` in a comparison or an exit (`!=`, `==`, `-ne`, `-eq`, `-n`, `-z`, with `exit`, `break` or `return` on that line or in the loop condition); a token that appears only in a comment or an `echo` reads `bounded=no`, and a bounded neighbour more than 15 lines away does not lend its bound.
  - **P** (gated) a signal to the parent: `kill` and `$PPID` on one line, or a variable assigned from `$PPID` / `ps -o ppid=` then killed within 20 lines (the distance of the one derived case in the tree, `run-registered-suites.test.sh`).
  - **G** (gated) an all-process or own-group signal at command position: `kill [-SIG] 0`, `kill [-SIG] -1` (both reach the caller's ancestors in the group). No site exists today, so G has no baseline row and is proved by a fixture.
  - **L** (listed, never gated, no baseline) targeted group signals (`kill -- -<pgid>`, `pkill -g`, `-s`, `-P`) and name-pattern signals (`pkill`, `killall`). They are not signals to ancestors, so they do not fail a suite; `--list` shows them so a mutation seat sees the whole signalling surface (14 sites today).
  - Command position for P, G and L means: line start, or after `;`, `&&`, `||`, `|`, `(`, `{`, `` ` ``, `$(`, `!`, `then`, `do`, `else`, optionally behind `sudo`, `exec`, `command`, `builtin`, `nohup`, `env`, `timeout <n>` or a backslash. Heredoc bodies are counted like any other line (a signal verb in fixture text inside a heredoc is a finding; that is deliberate, such text is often a real helper).
  - Quoted spans are masked before a verb is located at command position (a `'pkill -f x'` test input or a message is not a finding); `kill -0`, `kill -l`, comment lines and blank lines are never findings.
- Baseline row: `<path>TAB<class>TAB<normalised line>` (whitespace collapsed), the shape of `scripts/lint-shell-capture-exit.baseline.txt`, matched as a multiset. A finding of a gated class not in the baseline is **new** (red); a baseline row with no live finding is **stale** (red: the baseline may only shrink, and a stale row is also how a dead detector is noticed); a baselined **W** row whose finding is `bounded=no` is red (admissibility: an unbounded walker cannot be baselined).
- Output: `--list` prints `class TAB bounded TAB path TAB text` for every finding of every class; the summary line is `ancestor-signal scan: <files> files, <n> findings, <b> baselined, <k> new, <s> stale, <u> unbounded`. Exit 0 clean, 1 findings, 3 unresolved.
- Measured prototype (scratchpad, not committed): W 2, P 5, G 0, L 14. Baseline at introduction: 7 rows (2 W, 5 P). After Phase 5 both W rows are `bounded=yes`.
- The scan suite's fixtures are tracked data files under `plugins/soleur/scripts/fixtures/ancestor-signal/` with a `.txt` extension, which the population patterns do not match, so no scanned source line carries a walker the scan would find in itself and no spelling trick is needed. The suite passes them to the scan as explicit PATHs, and builds a throwaway git repository (the repo's git-fixture env helper) for the producer rows.
- Documented blind spots in the docstring: multi-line quoted strings; a walk written in another language (`os.getppid`); a two-step cursor (`parent=$(...); cur=$parent`); a kill more than 40 lines from the cursor or reached through a function; `kill $(...)` and `xargs kill`; helpers sourced from a non-suite file; suites not matching the two name shapes; fixtures stored under another extension.
- The baseline file's header states the maintenance rule: an in-place replacement of an existing row (same path and class, e.g. after an unrelated edit of that line) is allowed, a net addition needs a reviewer's read, and the file may only shrink otherwise. An unrelated edit of a baselined line therefore costs one row swap, not a regeneration.

**D4. The suites avoid the corpus-walk idiom on purpose and honestly.** `lint-orphan-test-suites.sh` has a repo-wide-idiom arm: a suite whose own source contains an unscoped `git ls-files`, `find .` or a recursive `grep` must be ALWAYS_ON or carry a declared edge set. The scan's suite delegates the whole-tree walk to the scanner (the subject under test), so the arm does not fire (its regex is textual over the whole file, comments included, so neither suite's source or comments may contain `git ls-files`, `find .` or a recursive `grep`; Phase 6.1 runs the lint to prove it) and its affected-set classification stays derived (stem equality `scan-ancestor-signal-helpers.test.sh` to `.py`). The cost is stated: under the *local* `--affected` gate a diff that adds a walker in an unrelated suite does not select this suite; CI's required `test` check runs the whole battery and catches it. Promoting it to ALWAYS_ON is an edit to `scripts/lib/test-affected-paths.sh` that `scripts/test-all.sh` itself guards (an index edit must pair an added label, line 2139 onward), so it is more than a one-line change; it is put to the operator as a challenge in `decision-challenges.md` rather than pre-decided.

**D5. The seat-brief sentence** (copy-pasteable, one place, referenced from the others):

> If a mutation touches a line inside a helper that sends signals or removes files (`kill`, `pkill`, a `$PPID` walk, `rm -r`), run every mutant ONLY as `bash "$ROOT/scripts/soleur-sandbox.sh" run-isolated "$SBX" -- <command>`. Exit 125 with `RUN_IN_PID_NAMESPACE_REFUSED` means the namespace is unavailable: stop and report it. Never run that mutant on the host, never retry without the wrapper. The namespace bounds signals, not writes; the sandbox copy bounds writes.

**D6. How the namespace is proven to contain, without ever running a lethal walker for real.** The helper's suite copies a fixture walker (a tracked data file, so it is inert text on disk and not a scanned source line) whose match predicate is a per-run **nonce**, not a catch-all, and whose climb also stops at `SOLEUR_TEST_SUITE_PID` and at pid 1. The chain on the host is `victim` (a bash whose argv carries the nonce, outside the namespace) -> the helper -> `top.sh` (PID 1 in the namespace, argv carries the nonce) -> `mid` (argv carries the nonce) -> `walker`. The walker climbs while the ancestor's cmdline carries the nonce and its pid is above 1, and signals the topmost such ancestor (measured: a SIGTERM sent to PID 1 from inside its own namespace is ignored, rc 0, so the positive control must be a non-init process such as `mid`). Contained: `mid` dies (positive control: the walker really signals) and `victim` is alive afterwards. If the helper regressed to run unsandboxed, the same walker would climb into `victim`, a test process with no value, never into the user's session, because nothing above it carries the nonce and the climb stops at the suite's own PID. This is also the pattern the doc recommends for any containment test ("scope the predicate to a nonce you control; never a catch-all").

## Technical Approach

### Implementation Phases

#### Phase 0: Setup and baselines (no edits)

0.1 `git merge origin/main` once (two commits, no planned file touched). Re-run the premise checks (9217 open, no open grep-q slice PR touching `plugins/soleur/test/roadmap-reconcile.test.sh`, state of #8626 vs `review/SKILL.md` bytes).
0.2 Record baselines before editing: `wc -c plugins/soleur/skills/review/SKILL.md` (476678), `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` summary, shellcheck finding counts of the files to be edited (base side of the delta), `bash scripts/lint-orphan-test-suites.sh` summary. Serial, one at a time (load 25 to 41).
0.3 Re-measure the namespace facts the helper relies on (already measured once): `$$ == 1`, `$PPID == 0`, rc propagation (0, 3, 7, 125), nested use, `--` accepted by `unshare`, a backgrounded child reaped at PID 1's exit.

#### Phase 1: the helper (RED first: `cq-write-failing-tests-before`)

1.1 Write `plugins/soleur/scripts/run-in-pid-namespace.test.sh` first, watch it fail (helper absent), then write the helper.
1.2 Suite shape (house style: `set -uo pipefail`; `export TMPDIR="${TMPDIR:-/var/tmp}"`; fixture dir under a `mktemp -d` owned by the suite's one EXIT trap with `assert_fixture_dir` before every `mkdir`/`rm -rf`; no `producer | grep -q`; `cases` incremented at the call site; an absolute assertion floor in the repo's conditional-opener form; no `git ls-files`, `find .` or recursive grep in its source).
   - Always-run rows (stub `unshare` on a private `PATH`, a witness file written by the wrapped command at its FIRST instruction): R1 `unshare` absent -> rc 125, marker `reason=missing-unshare`, witness absent; R2 stub exits 1 with an EPERM message -> rc 125, `reason=userns-unavailable`, the stub's first line quoted, witness absent; R3 stub exits 0 but runs the command in place (a dishonest `unshare`) -> rc 125 `reason=not-isolating`, witness absent; R4 stub records its argv -> one loop asserts the flags `-U -r -p -f --kill-child --mount-proc` each present once before `--`, then the command and its arguments verbatim (spaces, an empty argument, a leading `-n`); R5 usage error rc 2; R6 witness control: run the witness-writing command directly and assert the witness appears (so "witness absent" in R1 to R3 means "never started", not "could not write"); R7 a stub whose probe call is isolated and whose run call is not (keyed on the probe's `test "$$"` argument) reaches the in-namespace re-check: rc 125, witness absent.
   - Probe-driven rows: one real probe at the start decides `REAL_NS=yes|no`. When `no`, print `SKIP real-namespace rows (N): <unshare's first stderr line>` and count them as skipped, and run row R8: the REAL helper refuses with rc 125 + marker (so the unavailable branch is exercised for real on CI shapes where userns is restricted, and on macOS where `unshare` is absent). When `yes`: N1 the command is PID 1, `$PPID` 0; N2 exit codes 0, 3 and 125-without-marker pass through (a signal death of PID 1 cannot be produced from inside the namespace, so no signal-death row is claimed; the observed behaviour is recorded in `evidence.md`); N3 stdin/stdout/stderr and cwd pass through, and stderr carries nothing the command did not write; N4 the nonce-walker chain of D6 (positive control `mid` dead, `victim` alive); N5 a backgrounded `sleep` started by the command is gone after the helper returns, and again after the helper is SIGKILLed from outside (N5b: `--kill-child` reaps the tree); N6 a nested helper call works. Floor: always-run rows >= 8, and `REAL_NS=yes` adds >= 6.
1.3 The helper (about 60 lines, shellcheck-clean, `set -u`, every exit path explicit; the refusal text is built without backticks inside double quotes, and the rows that trip each refusal are run after any text edit).

#### Phase 2: the scan

2.1 Write the scan's suite first. Fixtures are the tracked data files (`walker-bounded`, `walker-unbounded`, `walker-comment-bound` (the token only in a comment: must read `bounded=no`), `parent-direct`, `parent-derived`, `group-all`, `listed-targeted-and-pattern`, `must-pass-mentions` (a comment, a quoted string, `kill -0`, `kill -l`), `walker-nonce` (used by the helper suite)); the scan is invoked with explicit PATHs; the producer rows use a throwaway git repository built with the repo's git-fixture env helper (`plugins/soleur/test/lib/git-fixture-env.sh`), so no real repo state is touched and the git tripwire is respected.
2.2 Rows (see Guard 2): one per gated class, a listed-only row for L (reported by `--list`, never red), must-PASS inputs (mentions, a blank-line shift of a baselined line, duplicates within baseline multiplicity), a new site, a stale row, an unbounded baselined W, a comment-only bound, empty population (rc 3), unreadable baseline (rc 3), `--write-baseline` round trip, the producer rows (a `test-x.sh` walker in the throwaway repo must be found; narrowing the pathspec must red).
2.3 Live row: run the scan over the repo with the committed baseline; require rc 0 with `0 new, 0 stale, 0 unbounded`, a population floor (>= 600 files; the measured count is recorded in `evidence.md`), a top-level root set that is a superset of `.claude apps plugins scripts tests`, and the two known walkers present as `W bounded=yes` (the positive control that the detector still finds what it exists for).
2.4 Write the scan (about 220 lines, stdlib only, no import from the scanned tree), seed the baseline from the scan's own `--write-baseline`, and review every row by eye against the prototype (7 rows).

#### Phase 3: the allocator verb

3.1 Arms first in `tests/scripts/test-soleur-sandbox.sh` (already a registered suite): `run-isolated` with a valid allocated sandbox runs the command with `pwd` equal to the sandbox, inside the namespace when `REAL_NS=yes` (pid 1) and refusing 125 + marker when it is not (stub `unshare` on `PATH`); refuses without calling the helper for each of: relative path, missing, symlink, wrong basename, no marker; missing `--` -> rc 2; missing helper -> rc 2 and the command NOT run (witness absent); a trailing slash is accepted; usage text lists the verb.
3.2 Implement the arm (about 30 lines) in `scripts/soleur-sandbox.sh`, update the header comment and `usage`.

#### Phase 4: wiring the rule where seats are briefed

4.1 `work-scratch-sandboxes.md`: new section "## Mutating a signalling or file-removing helper" after "Allocate, use, remove": how to recognise the class (grep the block and the helper for `kill|pkill|killall|PPID|rm -r|unlink|-delete`; the question "what does the predicate bound?"), the D5 sentence, the verb, the helper path for a repo without the allocator (`${CLAUDE_PLUGIN_ROOT}/scripts/run-in-pid-namespace.sh`; no hand-written `unshare` line, which would be the unguarded spelling), the rc-125 rule, "signals vs writes (and not network or IPC)", the PID-1 caveat and `timeout -k` (never a plain `timeout`), the environment differences inside the namespace (the caller is uid 0 and `/proc` shows only the namespace, so a suite with a not-root guard, an EACCES row or a host `pgrep` expectation behaves differently: run the UNMUTATED control inside the namespace first, and treat a red control there as an environment difference, not a kill), the nonce technique of D6, and the scan (`python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --list`). The paragraph that says "no script in the repo: use the fallback" keeps its existing fallback for the copy; the new section does not duplicate it.
4.2 `review/SKILL.md` line-217 paragraph: append one sentence of at most 220 bytes pointing at the verb and rc 125 (measure; drop if it does not fit the 322-byte headroom; never edit `skill-body-budget.json`).
4.3 `review/references/risk-tier-and-fix-rounds.md` "Briefing fix agents and seats": one bullet: any brief that asks a seat (or the lead's own battery) to flip a line in such a helper carries the D5 sentence; a report-only seat is instead told to reason about the line and report, not to run it; the lead mutation-tests named gaps through the verb. Check `review-tier-parity.test.ts`, `fix-round-seats.sh` and `emit-review-trailer.sh`, which read this file, for anchors the bullet could disturb.
4.4 `agents/engineering/review/test-design-reviewer.md` "Auditing a Mutation Battery": one bullet: a battery or plan row that mutates a line inside a signalling or file-removing helper without running through the isolated verb is a finding against the INSTRUMENT (unsafe, severity high), and a suite helper that walks ancestors must be bounded at the suite PID and appear in the scan baseline. `plugins/soleur/.claude-plugin/agents.manifest.json` carries only the description (unchanged).
4.5 `plan/references/plan-sharp-edges.md`: one entry (about 700 characters) naming the trigger (a plan prescribes "flip every converted line", "invert the matcher" or an observer over a block containing `kill`/`pkill`/`$PPID`/`rm -r`), the requirement (name the namespace in the AC and the observer paragraph, run the scan `--list` for known sites) and the Why with the learning path.

#### Phase 5: bound the second walker

5.1 In `plugins/soleur/test/roadmap-reconcile.test.sh`: `export SOLEUR_TEST_SUITE_PID=$$` once near the top (above the fake `gh` heredoc, which is quoted so the variable is read at run time from the environment), and in the `term` branch: a fail-closed guard when the variable is unset (the exact form is chosen in work against the row's expectations), the loop gaining `&& [[ "$p" != "$SOLEUR_TEST_SUITE_PID" ]] && [[ "$p" -gt 1 ]]`, and a comment stating the hazard and the namespace rule at the match line (the S5 wording). Unset means the helper signals nothing, so TS15e fails red rather than anything being killed; a mutant that removes the unset guard is a Guard-2-adjacent row run through the helper (the walk must still stop at the suite because pid 1 and the suite PID coincide inside the namespace, asserted in the no-kill rehearsal run through the helper too). The walk itself stays: the target is the module's process, an ancestor of the fake `gh` across a command-substitution subshell, and the fake cannot be told its PID (the module is launched by `run_main` and is not modified). Replacing the walk by a pidfile would change `run_main`'s launch shape and is a larger diff for the same containment.
5.2 Rehearse before relying: no-kill rehearsal (catch-all match, `kill` replaced by `echo`) printing the resolved target, which must be the module's PID and nothing above it; then the unmodified suite green (the whole file), then the catch-all mutant red (rc 1 on TS15e) with the session unaffected, run through the helper.
5.3 If an open grep-q slice PR touches the file, add its `hand-edits.txt` entry (Phase 0.1 decided).

#### Phase 6: verification (serial, load-aware)

6.1 Cheap repo-global lints from the brief, each alone: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (0 new), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` (the two new suites covered via the glob, none orphaned or unclassified, the repo-wide-idiom arm silent), shellcheck delta over every created or edited shell file (count at base vs head; new notes only of kinds the files already carry), `python3 scripts/lint-guard-contract.py` over this plan, `bash .claude/hooks/grep-q-pipe-guard.test.sh` (the new files add no early-exit pipe under the swept `plugins/soleur/` root), `bash scripts/pre-push-ratchet-lane.sh` once at the end (fixture and trap ratchets that a targeted run cannot see: `fixture-relative-assert`, `lint-trap-tempfile-ownership`).
6.2 Targeted suites by name: the two new suites, `bash tests/scripts/test-soleur-sandbox.sh`, `bash plugins/soleur/test/roadmap-reconcile.test.sh`, `bash plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` (unchanged; its baseline row is read by the scan), `bash scripts/lint-skill-body-budget.test.sh`, `bash plugins/soleur/test/scripts-shard-manifest.test.sh` and `bash plugins/soleur/test/scripts-shard-totality.test.sh` (shown, not asserted: the new suites are covered by the glob and untabled labels hash-fall-back), the bun/vitest `review-tier-parity` test if the runner is installed (otherwise the CI leg). No `test-all.sh --affected`, no `--print-selection`.
6.3 Userland check, when docker is available and the load allows: `docker run --rm -v "$PWD":/w -w /w ubuntu:24.04` (install `git jq python3 curl openssl`, log under `/var/tmp`), the new suites with the same always-run row count as the host; in the container the real-namespace branch is expected to SKIP (the default seccomp profile blocks `unshare`), so this run proves only the refusal branch (R8) and the userland of the stub, scan and lint rows, not containment. The only real-namespace signal in CI is the scripts leg's best-effort sysctl relaxation (`ci.yml`); the plan records that the `REAL_NS=yes` rows may never run in CI. If docker or the time is not available, record that CI's ubuntu-24.04 scripts leg is the userland check.
6.4 Mutation protocol for Guards 1 to 3: a sandbox from the allocator (git-init'd inside it for the scan's live row), one mutant at a time under `ulimit -v 6000000`, pristine copy restored by `cp` from a backup (never from git), a landing check per mutant (`cmp` plus a content assertion in the region), an unmutated control first (credit nothing from a red baseline), and **the whole battery driver run as `bash plugins/soleur/scripts/run-in-pid-namespace.sh bash <driver>`** (the helper protects its own mutation battery; the mutants of the walker fixtures and of the helper are never on the host). Record in `evidence.md` (written from the final state, corrections appended not edited in place).

## Files to Create

- `plugins/soleur/scripts/run-in-pid-namespace.sh`
- `plugins/soleur/scripts/run-in-pid-namespace.test.sh`
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`
- `plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt`
- `plugins/soleur/scripts/fixtures/ancestor-signal/` (about 9 small `.txt` data files: the scan suite's fixtures and the helper suite's nonce walker; extension chosen so the scan's population patterns never match them)
- `knowledge-base/project/specs/feat-one-shot-pid-namespace-guard-signal-helpers/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-pid-namespace-guard-signal-helpers/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-pid-namespace-guard-signal-helpers/evidence.md` (created in work)

## Files to Edit

- `scripts/soleur-sandbox.sh` (verb `run-isolated`, header, usage)
- `tests/scripts/test-soleur-sandbox.sh` (arms)
- `plugins/soleur/skills/work/references/work-scratch-sandboxes.md` (new section)
- `plugins/soleur/skills/review/SKILL.md` (one pointer, <= 220 bytes, inside the existing line-217 paragraph; ceiling file untouched)
- `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` (one bullet)
- `plugins/soleur/agents/engineering/review/test-design-reviewer.md` (one bullet)
- `plugins/soleur/skills/plan/references/plan-sharp-edges.md` (one entry)
- `plugins/soleur/test/roadmap-reconcile.test.sh` (bound the `term` walker)

Not edited, by decision: `plugins/soleur/skills/work/SKILL.md`, `scripts/grep-q-drain-codemod.py`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/scratch-root.sh`, `plugins/soleur/test/skill-body-budget.json`, `plugins/soleur/skills/plan/SKILL.md` (28 bytes of headroom), `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, any `.github/workflows/*.yml`, `AGENTS.md`/`AGENTS.rules.md`.

## Open Code-Review Overlap

One open code-review issue names a file in this plan: #8659 ("33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct runs") mentions `roadmap-reconcile.test.sh`. Disposition: **acknowledge**. It is a different concern (EXIT-trap composition across 33 suites); the roadmap-reconcile edit here does not touch its trap, and this change's two new suites use one EXIT trap each so they do not add to the class. The issue stays open. No other planned file appears in an open code-review issue (queried per path with `jq --arg`, 200 issues).

## Workflows fired by a merge

Derived, not assumed: every `.github/workflows/*.yml` with a `push`, `pull_request`, `merge_group` or `pull_request_target` trigger (88 workflows in the directory; 38 carry one of those triggers) was parsed and GitHub filter semantics applied (`*` stays within a segment, `**` crosses `/`, `!` negates, later patterns override) to the 17 planned paths. Result:

- Path-filtered push workflows that match: `version-bump-and-release.yml` (`plugins/soleur/**`) 11 of 17 (a plugin patch release), `web-platform-release.yml` (`apps/web-platform/**` and `plugins/soleur/**`, minus `plugins/soleur/docs/**` and `plugins/soleur/test/**`) 10 of 17 (a web image release and, as in S5, a deploy of it), `deploy-docs.yml` 5 of 17 (a docs-site deploy).
- No other path-filtered push or pull_request workflow matches (0 of 17 for each).
- Unfiltered, as on every merge: `ci.yml` (the required `test` check, full battery), `codeql-main-alert-gate`, `secret-scan`, `skill-security-scan-corpus`, `skill-security-scan-postmerge`, `tenant-integration`, `vendor-pin-verify`, plus the PR-time unfiltered set (`pr-quality-guards`, `claude-code-review`, `cla`, ...).
- `scripts/soleur-sandbox.sh` and `tests/scripts/test-soleur-sandbox.sh` match no filter; `plugins/soleur/test/roadmap-reconcile.test.sh` matches only the plugin-release filter (the web release excludes `plugins/soleur/test/`).
- Sanity probe for the matcher: adding `apps/web-platform/infra/server.tf`, `plugins/soleur/docs/x.md` and `scripts/test-all.sh` to the list lights further filtered workflows, so the matcher is not vacuous (re-run in Phase 6 on the final diff).
- The PR body states the first three as its **first line**. No `[skip-deploy-fix-apply]`, no `app:web-platform` label (nothing under `apps/web-platform/` changes; `plugins/soleur/skills/ship/SKILL.md` applies it only for that path), `semver:patch`, `type/chore`, `domain/engineering`.

## Guard Contract

### Guard 1 — run-in-pid-namespace.sh fails closed

**Property.** The wrapped command never starts unless it is PID 1 of a fresh PID namespace with its own `/proc`; every other outcome is rc 125 with the marker line and the command not started.

**Assembly.** The chokepoint is the single `exec unshare ... sh -c '[ "$$" -eq 1 ] ... exec "$@"'` line: every successful path flows through it and nothing else execs the command. Three refusal arms feed rc 125 (missing `unshare`, failed probe, non-isolating probe) plus the in-namespace re-check, each with its own test row. The allocator verb (Guard 3) calls the helper rather than spelling the flags, and the docs name only the helper's path, so there is one spelling of the flag set. The order property (refusal before the command starts) is observed by a witness written by the command at its FIRST instruction and read after the helper returns, so a late kill would still show the witness.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the `exec unshare ...` line with `exec "$@"` (no namespace) | RED: R4 (the argv stub never sees the flags), N1 (not PID 1) where real |
| 2 | Dispatch: make the probe always succeed (`true`) | RED: R3 (a dishonest `unshare` that runs in place reaches the command, witness present) |
| 3 | Refusal arm prints the marker but exits 0 | RED: R1, R2, R3 (rc must be 125) |
| 4 | Refusal arm prints the marker and then falls through to `exec "$@"` | RED: witness present in R1, R2, R3 |
| 5 | Remove only the missing-`unshare` arm, leave the other two (a second member after a compliant first) | RED: R1 alone |
| 6 | Remove only the not-isolating arm | RED: R3 alone |
| 7 | Drop one flag at a time: `-p`, `--kill-child`, `--mount-proc`, `-U` (four mutants; `-r` and `-f` share R4's kill mechanism with `-U`) | RED: R4 for each; N1 for `-p` and `--mount-proc`; N5 for `--kill-child` |
| 8 | Delete the in-namespace `$$` re-check | RED: R7 |
| 9 | Harness row: edit the suite so the witness path is never written (the command writes elsewhere) | RED: the witness control R6 |
| 10 | Must-PASS non-canonical input: arguments with spaces, an empty argument, a leading `-n` | PASS: R4 (argv verbatim) and N3 |
| 11 | Where real namespaces are unavailable the real helper must still refuse (the branch that actually runs on restricted CI and on macOS) | PASS (refusal); RED if the helper ran the command: R8 |

**Anchor.** No stored value is compared. The independent witnesses are behavioural: N1, N4 and N5 in a real namespace, and the stub-argv row R4 where none is available.

### Guard 2 — the signal-helper inventory ratchet

**Property.** Every ancestor-walk, parent-signal and all-process-signal line in a tracked shell test suite is either a row of the committed baseline or fails the suite, a baseline row with no live line fails the suite, and no baselined ancestor walk is unbounded.

**Assembly.** The population flows through one `git ls-files` call with two pathspecs (`*.test.sh`, `:(glob)**/test-*.sh`); three gated detector classes (W, P, G) plus the listed-only class L share one line normaliser and one multiset matcher against the baseline; the suite's live row is the only CI caller. Members drift (suites are added anywhere), so the assertion is structural: the population floor, the root-set superset (`.claude apps plugins scripts tests`), and the known-member control (both walkers present as `W bounded=yes`) pin that the walk still reaches what it exists for.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture corpus gains a new walker line not in the baseline | RED, naming file and class W |
| 2 | Dispatch: the producer returns zero files (pathspec emptied) | RED: rc 3 UNRESOLVED in the scan, and the suite's population floor |
| 3 | Dispatch: the producer is narrowed to `*.test.sh` only (drops `test-*.sh`) | RED: the producer row (a walker in `test-x.sh` of the throwaway repo must be found) and the root-set row (`tests` missing) |
| 4 | Fixture file has two sites, the first baselined, the second not (a check that stops at the first) | RED naming the second |
| 5 | Neuter class W's cursor regex | RED: the known-member control (both walkers must be found) and the stale-row check (the W baseline rows have no live finding) |
| 6 | Neuter class P, then class G (two mutants) | RED: stale baseline rows for P; the fixture row for G (no baseline row exists for G, so only the fixture can see it) |
| 7 | Delete the baseline row of a live site | RED (new) |
| 8 | Add a baseline row for a line that does not exist | RED (stale) |
| 9 | Remove the multiset count (treat duplicates as one) | RED: the duplicate fixture row (two identical lines against one baseline row must read new, three rows against two lines must read stale) |
| 10 | Admissibility: a baselined W row whose bound token is only in a comment, and one whose bound is removed | RED (unbounded) for both |
| 11 | Treat class L as gated | RED: the L fixture row (listed, rc 0) |
| 12 | Must-PASS: the same baselined line shifted by inserted blank lines | PASS (content-keyed) |
| 13 | Must-PASS: a comment mention, a quoted mention, `kill -0 "$p"`, `kill -l` | PASS, no finding |
| 14 | Harness row: neuter the suite's `fail()` | RED: `guard-vacuity-floor.test.sh` and the suite's absolute floor |
| 15 | Empty population and unreadable baseline passed as success | RED: the rc-3 rows |
| 16 | After-remediation: the original `roadmap-reconcile.test.sh` walker must read `bounded=no`, the Phase 5 edit `bounded=yes` (run on both) | RED on the original, PASS on the fixed file |

**Anchor.** A baseline row can be added in the same diff that adds the walker, so the suite certifies consistency between code and baseline, not integrity. What outside the commit moves for a weakening to pass: a reviewer reading a baseline addition (one content line, like `lint-shell-capture-exit.baseline.txt`), plus the admissibility rule, which removes the one weakening that matters (an unbounded walker cannot be baselined at all, so adding a row does not make a lethal walker pass). A merge-base shrink-only check is cut (Cut List) because the test legs do not guarantee a fetched base.

### Guard 3 — `run-isolated` starts nothing outside a sandbox

**Property.** `soleur-sandbox.sh run-isolated` runs the command only with an allocated sandbox as the working directory and only through the helper; every other input is a non-zero refusal with the command not started.

**Assembly.** One verb arm (the chokepoint), one sandbox-shape check (absolute, real directory, `soleur-sbx.?*` basename, regular marker), one helper-path resolution.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the sandbox-shape check | RED: the bad-shape rows (command ran, witness present) |
| 2 | Dispatch: the verb arm dispatches to `rm` or to `usage` | RED: the valid-sandbox row |
| 3 | Check only the basename, not the marker (a second conjunct after a compliant first) | RED: the no-marker row |
| 4 | Accept a symlink to a sandbox | RED: the symlink row |
| 5 | Missing helper falls back to running the command directly | RED: the missing-helper row (witness absent, rc 2) |
| 6 | Run the helper before `cd` (cwd stays the live tree) | RED: `pwd` equals the sandbox |
| 7 | Must-PASS non-canonical: sandbox path with a trailing slash | PASS |

**Anchor.** Not applicable (no stored value); the independent witness is `pwd` printed from inside the namespace.

## User-Brand Impact

- **If this lands broken, the user experiences:** a mutation seat told to "run it isolated" that either refuses a healthy host (a seat stops and reports instead of proving its line) or, worse, runs the mutant unsandboxed because a wrapper regressed, which is the incident again: a desktop session ended with no warning. A broken scan fails the full-battery check red on an unrelated PR.
- **If this leaks, the user's workflow is exposed via:** no data or credential is read or written; the exposure vector is a false sense of safety, a seat or a plugin user trusting a wrapper that does not isolate (Guard 1 rows 1, 2, 4 and 8 and the dishonest-`unshare` stub exist for exactly that) or a baseline that certifies an unbounded walker (Guard 2's admissibility rule).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident`: the change adds containment to an internal test workflow, touches no user data, no deploy path and no credential, and a failure of the helper is rc 125 and a stopped seat, not a user-visible effect; not `none` because the same mistake already cost an operator four desktop sessions and plugin users run the same briefs, so a regression repeats across seats; the diff touches no sensitive path, so no `threshold: none` scope-out is needed.

## Observability

```yaml
liveness_signal:
  what: the scan prints one summary line and exits 0 when the committed baseline matches the tree; its suite runs in the CI scripts group on every PR and merge_group run
  cadence: per PR and per merge_group run, and on demand
  alert_target: the required test check turns red on the PR, which blocks merge
  configured_in: scripts/test-all.sh SUITE_GLOBS entry plugins/soleur/scripts/*.test.sh (registration), plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh (the live row)
error_reporting:
  destination: CI job log of the test check (repo-hygiene tooling, no Sentry surface)
  fail_loud: a FAIL line naming the file, class and normalised line of each new, stale or unbounded finding, exit 1; an empty population, a failed git call or an unreadable baseline prints UNRESOLVED and exits 3; the helper prints RUN_IN_PID_NAMESPACE_REFUSED with the reason and exits 125
failure_modes:
  - mode: a new ancestor-walking or signal-to-ancestors helper lands in a shell test suite
    detection: the scan reports it as new in the suite's live row
    alert_route: required test check red on the PR
  - mode: the producer stops reaching a root or detector class stops matching
    detection: population floor, root-set superset, the two known walkers as W bounded=yes, stale baseline rows
    alert_route: required test check red on the PR
  - mode: user namespaces are unavailable where a seat expects isolation
    detection: the helper's rc 125 and marker line, quoted in the seat report; the suite's real refusal row on restricted runners
    alert_route: the seat stops and reports; CI shows the SKIP count line for the real-namespace rows
logs:
  where: CI job log of the scripts test group; stderr of the helper in the seat's report
  retention: the CI log retention of the repository
discoverability_test:
  command: python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --baseline plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt
  expected_output: 0 new
```

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO assessed the plan headless. Agreed: a PID namespace is the right containment for the signal class, never falling back is correct, the nonce-scoped real-namespace arm is the regression test for the incident, and the roadmap-reconcile bound is the root-cause fix with the namespace as a second layer. Applied: rc passthrough is asserted for 0, 1, 3 and a signal death with the observed mapping recorded (`--kill-child` with `-f` may flatten it); non-Linux and missing-`unshare` hosts refuse cleanly and the glob-registered suite SKIPs visibly (row R10); the doc states the namespace does not bound files, network, IPC or signals from outside. Challenged and kept at the operator's stated direction (persisted as user-challenges in `decision-challenges.md`): cut the scan to ancestor walks only or into a grep inside an existing suite; drop the review `SKILL.md` and plan-sharp-edges edits; place the helper in `scripts/lib/` with only its test in the plugin. Plan-review's engineering panel is the second read. No architecture decision is made: a containment wrapper and a lint do not move a tenancy boundary, add a substrate or change a trust boundary, so the ADR/C4 gate (plan Phase 2.10) does not fire and no `.c4` file changes; `plugins/soleur/test/c4-count-parity.test.sh` is unaffected (no workflow, monitor or heartbeat is added).

Product/UX Gate: none (no UI surface; the mechanical UI-surface override matched no planned path). GDPR gate: no regulated-data surface and none of the (a)-(d) expansion triggers. IaC gate, encryption-posture gate: no infrastructure, store or connection is introduced.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md (interactive only; headless run, no block written) -->

- [ ] AC-1. `bash plugins/soleur/scripts/run-in-pid-namespace.sh sh -c 'echo $$ $PPID'` prints `1 0` where user namespaces are available; where they are not it exits 125 with a first stderr line starting `RUN_IN_PID_NAMESPACE_REFUSED` and the command did not run. Both branches are asserted by `bash plugins/soleur/scripts/run-in-pid-namespace.test.sh` (rc 0, always-run rows >= 8, the SKIP count line printed when real rows are skipped).
- [ ] AC-2. The helper never falls back: the dishonest-`unshare` stub, the failing stub, the missing-`unshare` PATH and the re-check stub each end rc 125 with the witness absent (rows R1 to R3, R7).
- [ ] AC-3. `bash tests/scripts/test-soleur-sandbox.sh` passes with the `run-isolated` arms: a valid sandbox runs in the namespace (or refuses 125 where unavailable), each bad shape refuses with the command not started, a missing helper is rc 2.
- [ ] AC-4. `python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --baseline plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt` exits 0 and prints `0 new, 0 stale, 0 unbounded`; its `--list` shows both ancestor walkers as `W bounded=yes` and the listed-only class L; the baseline is the scan's own `--write-baseline` output reviewed row by row (7 rows: 2 W, 5 P, unless Phase 0 re-measures a different count, then recorded in `evidence.md`).
- [ ] AC-5. `bash plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh` passes with every row of Guard 2 and its absolute floor, including: a comment-only bound token reads `bounded=no`, an unbounded W cannot be baselined.
- [ ] AC-6. `plugins/soleur/test/roadmap-reconcile.test.sh` passes (all rows), its `term` walker stops at `SOLEUR_TEST_SUITE_PID` and signals nothing when it is unset, a no-kill rehearsal printed the module PID and nothing above it, and the catch-all mutant ran only through the helper.
- [ ] AC-7. The D5 sentence appears in `work-scratch-sandboxes.md`; a pointer or bullet appears in `risk-tier-and-fix-rounds.md` and `test-design-reviewer.md` (and in `review/SKILL.md` when it fits); `plan-sharp-edges.md` carries the one entry; no surface contains a hand-written `unshare` line other than the helper.
- [ ] AC-8. `plugins/soleur/skills/review/SKILL.md` is at most 477000 bytes (`wc -c`) and `plugins/soleur/test/skill-body-budget.json` is not in the diff.
- [ ] AC-9. Repo-global lints green on the final tree, each run by its own invocation: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (0 new), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` (the new suites covered, none orphaned or unclassified), `python3 scripts/lint-guard-contract.py` over this plan, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash scripts/lint-skill-body-budget.test.sh`, shellcheck delta (head not worse than base except notes of kinds the files already carry), `bash scripts/pre-push-ratchet-lane.sh` verdict PASS.
- [ ] AC-10. The mutation batteries for Guards 1 to 3 ran one mutant at a time under `ulimit -v 6000000`, each with an unmutated control, a landing check and a restore from a pristine copy, with the driver run through the helper; results (killed, predicted-green, unexpected) are in `evidence.md`. Unexpected survivors are fixed or recorded as accepted with the enumeration that proves equivalence.

### Ship checklist (constraints carried from the brief; verified at ship, not product properties)

- [ ] The diff touches none of `plugins/soleur/skills/work/SKILL.md`, `scripts/grep-q-drain-codemod.py`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/scratch-root.sh`, any workflow file (`git diff origin/main --stat`).
- [ ] The PR body's FIRST line states that merging fires a plugin patch release, a web image release and deploy, and a docs-site deploy, and names the unfiltered checks; it cites tracker 9217 as `Ref #9217` only.
- [ ] The PR body avoids the four words the brief lists, has no bullet starting with an operator verb, cites no plan path containing the word soak; commit messages carry no `[skip-deploy-fix-apply]`.
- [ ] The main checkout's `.mcp.json` and the untracked `apps/web-platform/1000:` and `500` files are untouched and the session-start restore was not run.
- [ ] A userland run in `ubuntu:24.04` was done or CI's scripts leg is recorded as the userland check (Phase 6.3).

## Test Scenarios

(pyramid layer in brackets; all are bash suites, no e2e)

- [unit] Given `unshare` is absent from `PATH`, when the helper runs a command, then rc 125, the marker names `missing-unshare`, and the witness file does not exist.
- [unit] Given a stub `unshare` that exits 1 with "Operation not permitted", when the helper runs, then rc 125, `reason=userns-unavailable`, the stub's first line is quoted, and the witness is absent.
- [unit] Given a stub `unshare` that exits 0 and runs the command in place, when the helper runs, then rc 125 `reason=not-isolating`, witness absent (never an unsandboxed fallback).
- [unit] Given a stub that records argv, then the flags `-U -r -p -f --kill-child --mount-proc` precede `--`, each present once, and the command's arguments arrive verbatim including an empty argument and `-n`.
- [integration] Given real user namespaces, the command is PID 1 with `$PPID` 0, its exit codes and signals pass through, and a backgrounded child is gone after the helper returns.
- [integration] Given real user namespaces and a nonce-scoped walker under a nonce-carrying victim ancestor outside the namespace, the in-namespace middle process dies (control) and the victim survives.
- [integration] Given restricted user namespaces or no `unshare` (macOS), the real helper refuses with rc 125 and the suite prints the SKIP count line.
- [unit] Given the fixture files, the scan reports each gated class once, lists class L without failing, ignores comment, quoted, `kill -0` and `-l` mentions, survives a blank-line shift of a baselined line, treats duplicates as a multiset, reads a comment-only bound token as `bounded=no`, and rejects a new, a stale and an unbounded-W baseline row.
- [integration] Given the repo, the scan with the committed baseline prints `0 new, 0 stale, 0 unbounded`, the population is above its floor and spans the expected roots, and both known walkers are `W bounded=yes`.
- [integration] Given a sandbox from the allocator, `run-isolated "$SBX" -- pwd` prints the sandbox path from inside the namespace; each bad shape refuses with the command not started; the helper removed makes it rc 2.
- [regression] Given the roadmap-reconcile suite with the catch-all matcher mutant run through the helper, TS15e goes red and the session is unaffected; unmutated it is green in and out of the namespace.

## Dependencies & Risks

- **User namespaces unavailable on CI.** ubuntu-24.04 restricts them through AppArmor (`ci.yml` relaxes the sysctl best-effort). Mitigation: both branches are real and counted (rows R8 and N1 to N6); the SKIP line states the count and the reason. Risk accepted: on a runner where the sysctl stays restricted the containment rows run only on developer hosts; the refusal rows still run there and the stub rows cover the logic.
- **rc 125 ambiguity.** A wrapped command may itself exit 125; the marker line, not the code alone, identifies a refusal. Stated in the helper header and the doc.
- **A namespace does not confine writes.** Said once in the helper, once in the doc; the sandbox copy is the write bound. A file-removing mutant that uses an absolute path can still reach the host; the doc says to assert fixture dirs (`assert_fixture_dir`) in suites that remove files.
- **Scan recall.** A text heuristic over shell lines: multi-line quoted strings and helpers outside suites are blind spots, listed in the docstring; the scan is a finding aid plus a ratchet on the lines it can see, not a proof of absence.
- **`review/SKILL.md` byte headroom (322) and open PR #8626.** If the pointer does not fit or #8626 consumes the headroom first, the SKILL.md pointer is dropped; four other surfaces carry the rule.
- **Local affected gate blind spot** (D4) is stated, not hidden; CI full battery is the gate.
- **Load.** The host runs at load 25 to 41; gates run serially, targeted, with the heavy shared-runner suites left to CI.
- **A mutant of the helper must not escape its own battery.** The whole battery driver runs through the helper; the suite's walker is nonce-scoped, so even a helper that regressed to run in place cannot signal anything outside the fixture's own chain.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Only prose in the briefs (no helper) | The incident happened in the presence of careful prose in a plan; an executable wrapper with a refusal is the only form a seat cannot misread |
| bwrap instead of `unshare` | Not installed everywhere; the brief and the incident evidence name `unshare -Urpf --kill-child --mount-proc` (it was measured to contain the mutant); bwrap remains the answer for write confinement (taste item) |
| Put the helper in `scripts/` | Repo-only: plugin users would not get it, and a new suite there needs an explicit `run_suite` line in a file the brief says not to edit |
| Put the scan in `scripts/` and register it | Same registration problem; also not shipped to plugin users who want to scan their own suites |
| A pre-run hook that blocks `grep -vc` style edits | Matches the mutation text, not the hazard; the hazard is in what the line bounds |
| Make the scan ALWAYS_ON now | One-line edit to a file the brief fences off, not needed to pass any gate; the trade-off is recorded for the panel |
| Gate every signal class, including targeted group signals and `pkill` by name (the first draft: 21 baseline rows) | Not signals to ancestors, so outside the brief's wording; the only remedy when one went red was to add a baseline row (a tax, not a guard) and every harmless edit to a baselined line would churn it. Kept as class L in `--list` so a seat still sees them |
| A hand-written `unshare` fallback line in the doc, pinned to the helper by a parity row | A second spelling of the flags, unguarded (no probe, no marker); the doc points at the helper's path only |
| A receipt line on the helper's stderr | Adds output to every wrapped command; the property needs none |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills all three lines.
- The helper's tests must never run a catch-all walker for real. If a future edit to the fixture replaces the nonce predicate with a catch-all, the suite becomes the incident; the fixture's header comment says so and the walker is a tracked data file (inert text, not a scanned source line).
- A script a planning pass drops into a spec directory is repo code to the ratchets (S5 session error 5): this plan creates no script in `knowledge-base/`.
- Text built only on failure is never executed by a green suite (S5 session error 2): after writing the refusal messages, run the rows that trip them; no backtick pair inside a double-quoted message.
- Mutation drivers locate sites by content, never by line number (S5 session error 3).
- `assert_fixture_dir` before `mkdir`/redirects and again before `rm -rf`; one EXIT trap per suite (#8659 class); `export TMPDIR="${TMPDIR:-/var/tmp}"`.
- After renaming or adding text a gate keys on, assert the entry count moved, not only that the gate exits 0 (Guard 2's population floor and known-member control do this).
- The `guard-vacuity-floor` sweep classifies suites by the shape of their floor; use the repo's conditional-opener form (`if [[ "$cases" -lt N ]]; then fail ...`) so the new suites enter the population rather than being absent from it.
- A scan over test suites finds its own fixtures. Keep walker-shaped text in `.txt` data files passed as explicit PATHs, never as heredocs inside a scanned `.test.sh`; the scan's one bound token is `SOLEUR_TEST_SUITE_PID`, on a non-comment comparison or exit line (a comment mention reads `bounded=no`).
- Exit-code facts are measured, not assumed: `unshare` passes the child's rc through (7 -> 7, 125 -> 125), a backgrounded child is reaped when PID 1 exits, and a SIGTERM to PID 1 from inside is ignored; a positive control that targets PID 1 would pass vacuously red.
- A directory-prefix claim in the scan docstring ("walks every suite") is a universal; the docstring lists the two pathspecs and the blind spots instead.
