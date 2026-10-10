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

## Enhancement Summary

**Deepened on:** 2026-10-10. **Sections enhanced:** Proposed Solution (D1 to D6), Implementation Phases 1 to 6, Guard Contract (3 guards, 13/18/8 rows), Observability, Acceptance Criteria. **Seats:** architecture-strategist, security-sentinel, spec-flow-analyzer, test-design-reviewer, observability-coverage-reviewer (after the plan-review panel of DHH, Kieran and simplicity seats and the CTO read). Mechanical gates re-run clean: User-Brand Impact, Observability, PAT scan, Guard Contract lint, Scope Check (one unfenced section, no BLOCKED marker).

### Key improvements
1. The isolation check now includes the namespace's own `/proc` (measured: a wrapper that drops `--mount-proc` keeps `$$` 1 and `$PPID` 0 but shows the host's process list), `unshare` is resolved once to an absolute path (an exported function must not decide the probe), `exec --` guards a leading-dash command, and every refusal arm prints the marker.
2. The seat-brief sentence works for plugin consumers (two branches), carries `timeout -k` (a PID-1 command ignores SIGTERM), defines the verdict `UNVERIFIED-NO-NAMESPACE` and the cleanup path, and separates signal helpers (namespace mandatory) from file-removing ones (sandbox mandatory).
3. The scan reads `git ls-files -z` under a `GIT_*`-free environment, accepts only regular files, decodes with surrogateescape and splits on `"\n"`, caps line and file size, turns any exception into rc 3, and prints a comma-free `ancestor-signal scan: CLEAN` literal for the discoverability probe.
4. The nonce walker fixture fails closed (nonce must be 32 hex, suite PID set and numeric, hop cap, signal only when the chain is complete) and is a data file, not scanned source.
5. Test design: stub rows observe the working directory, per-conjunct mutants, window-edge and bound-form fixtures, literal floors with `cases + skipped == planned`, an opt-in `SOLEUR_REQUIRE_REAL_NS`, and rc discrimination plus an instrument control for the mutation batteries.

### New considerations discovered
- The session manager (`systemctl --user kill`, `loginctl terminate-session`) and the D-Bus session bus are a second route to ending a desktop session that no PID namespace bounds; the doc names it.
- `components.test.ts` rejects a SKILL.md span opening with `scripts/` or `references/`, so the `review/SKILL.md` pointer must avoid that shape.
- The allocator suite's declared edge set reaches the new helper dependency only if the arms name the helper path literally.
- A mutant that deletes `.soleur-owned` leaves a copy neither `run-isolated` nor `rm` will touch (24 h reaper); documented, not worked around.

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
- Planned files: about 37 (29 created: 5 code files, about 20 fixture data files, the plan, tasks, decision-challenges, evidence; 8 edited) | Estimated changed lines: about 1100 (helper 60, its suite 250, scan 220, its suite 300, baseline 10, fixtures 80, allocator 30, allocator arms 60, docs 110, roadmap-reconcile 12)
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

- Exit codes: the command's own code on success; **125** when the helper refuses (the convention `timeout` and `env` use for "my own failure"), with a first stderr line `RUN_IN_PID_NAMESPACE_REFUSED reason=<missing-unshare|userns-unavailable|not-isolating> ...` followed by the cause, a per-reason remedy and the sentence "no unsandboxed fallback: run the mutant on a host that allows user namespaces, or do not run it". Every refusal path, including the one inside the namespace, prints the marker. The quoted `unshare` stderr line is stripped of control characters and newlines and cut to one line (it is influenced by whatever `unshare` resolves to). 2 for a usage error. A wrapped command that itself exits 125 without the marker is the command's; a seat distinguishes by the marker line (measured: `unshare` passes the child's code through unchanged, 7 -> 7 and 125 -> 125). Per-reason remedy: `missing-unshare` says Linux with util-linux is required (stock macOS has none; use a Linux host or VM); `userns-unavailable` names the sysctls `kernel.unprivileged_userns_clone`, `kernel.apparmor_restrict_unprivileged_userns`, `user.max_user_namespaces`, a container seccomp profile (Docker's default blocks `unshare`: `--security-opt seccomp=unconfined` or a Linux VM) and says that on a restricted CI runner every seat on a signalling helper refuses until the runner relaxes the sysctl (root); `not-isolating` says the `unshare` on `PATH` did not create a fresh PID namespace with its own `/proc`.
- Flow: (1) no command -> usage, rc 2. (2) Resolve `unshare` ONCE with `u=$(type -P unshare)` and require an absolute path (an exported shell function named `unshare` or a relative `PATH` element must not decide the probe), `unset -f unshare`, and use `"$u"` in both the probe and the exec so the two cannot resolve differently; absent -> refuse `missing-unshare`. (3) probe: `"$u" -Urpf --kill-child --mount-proc -- sh -c <check>` with stderr captured, where `<check>` is the isolation property: `$$` is 1 AND `/proc` is the namespace's own (`awk '/^NSpid:/{print NF-1}' /proc/self/status` prints 1; with the host's `/proc` mounted the line has two fields, measured: a wrapper that drops `--mount-proc` keeps `$$` 1 and `$PPID` 0 but shows the host's process list). Non-zero -> refuse (`userns-unavailable` when `unshare` itself failed, `not-isolating` when it ran and the check failed). The probe is what separates "unshare failed" from "the command exited 1". (4) `exec "$u" -Urpf --kill-child --mount-proc -- sh -c '<check> || { marker; exit 125; }; exec -- "$@"' sh "$@"`: the same check inside the run keeps the property true at the instant the command starts even if the probe and this run disagree, `exec --` keeps a command whose name begins with `-` from being read as an option, and `exec` leaves the command as PID 1 (no ancestor at all). No receipt line: the helper adds nothing to the wrapped command's stderr on the success path.
- The wrapped command has PID-1 semantics (measured: a signal it sends to itself, including `kill -9 $$`, is ignored and it exits 0; SIGTERM sent to the helper from outside does not stop a command with no handler). A caller that wants a bound uses `timeout -k <grace> <secs> <helper> ...`, never a plain `timeout`; SIGKILL of the helper does reap every descendant (`--kill-child`). The helper header and the doc say so in one sentence.
- stdin, stdout, stderr, cwd and environment pass through unchanged; `--kill-child` plus PID 1's exit tear down every descendant (measured: a backgrounded `sleep` is gone when the command exits), so a mutant that backgrounds a process leaves none behind.
- No test-only env seam: tests prepend a stub `unshare` to `PATH`.
- A mount namespace is created (`--mount-proc` needs it) but the filesystem is NOT confined: writes pass through, and so do network, IPC, abstract unix sockets, the D-Bus session bus, `$SSH_AUTH_SOCK` and the session manager (`systemctl --user kill`, `loginctl terminate-session` reach the host: a second way to end a desktop session that a PID namespace does not bound). The caller is mapped to uid 0 inside, so `id -u` and root-guard branches differ. The helper's header and the doc say so in one sentence each.

**D2. The verb.** `bash scripts/soleur-sandbox.sh run-isolated <sandbox-path> -- <cmd> [args...]`: (1) trim trailing slashes, then refuse (rc **2**, a message that does NOT carry the helper's marker, so a seat cannot confuse "bad sandbox" with "namespace unavailable") unless the path is absolute, `cd -P -- "$path"` succeeds, `pwd -P` equals the trimmed path (no symlink in any component), the basename matches `soleur-sbx.?*`, `.soleur-owned` is a regular non-symlink file tested relative to the new cwd, and the directory is owned by the caller's uid; (2) the helper is resolved from `$HERE` (the live tree, never from the sandbox copy) and must be a regular executable file, else rc 2 and the command is NOT run; (3) `exec` the helper. The verb deletes nothing, so it does not repeat `rm`'s remaining conjuncts; `scripts/lib/scratch-root.sh` (the delete path) is not touched (a shared predicate extracted from it is the alternative, put to the reviewers in `decision-challenges.md`). Together: the namespace bounds signals, the copy bounds file removal. A mutant that deletes `.soleur-owned` makes later `run-isolated` and `rm` calls refuse; the copy is then left to the 24 h reaper and the doc says so; the refusal stands and the copy waits for the reaper.

**D3. The scan.** `plugins/soleur/scripts/scan-ancestor-signal-helpers.py [--root DIR] [--baseline FILE] [--list] [--write-baseline FILE] [PATH ...]`.

- Population: `git -C ROOT ls-files -z '*.test.sh' ':(glob)**/test-*.sh'` (one call, the single chokepoint; `-z` so quoted or non-ASCII paths are not silently dropped), run with every `GIT_*` variable removed from the child environment (a hook or CI wrapper may export `GIT_DIR`, `GIT_INDEX_FILE` and friends that would redirect the listing to another repository), or the explicit PATHs. Each member is `lstat`ed and read only if it is a regular file: a symlink, gitlink or special file is a counted `skipped` entry in the summary, and a member listed but missing from the worktree is rc 3. An empty population, a failed `git`, an unreadable baseline, or any uncaught exception (the entry point wraps `main`, so a traceback can never read as rc 1 "findings") is rc 3 `UNRESOLVED`, never a clean report.
- Reading model: files are decoded with `errors="surrogateescape"` and split on `"\n"` only (never `str.splitlines()`, which splits on separators bash does not and would skew the line windows), `\r` stripped explicitly. A line over 4 KB gets no regex work (counted `overlong` in the summary; a plain substring pre-filter still reports a gated verb on it), and a file over 2 MB is `skipped`. No nested quantifiers.
- Classes. A finding is one source line, content-keyed.
  - **W** (gated) ancestor walk with a signal: a self-referential cursor assignment (`v=$(... /proc/$v/stat ...)`, `v=$(ps -o ppid= -p $v)`, `v=$(... $v ... PPid ...)`) with `kill`, `pkill` or `killall` within 40 lines either side. 40 lines because the known helper's cursor and its `kill` sit 12 lines apart and heredoc helpers are short; raw text, so heredoc and string-embedded helpers count. Reported `bounded=yes` only when a NON-COMMENT line from 15 lines above to 3 lines below the cursor line (the S5 helper's guard and loop condition sit 6 and 7 lines above its cursor) mentions `SOLEUR_TEST_SUITE_PID` in a comparison or an exit (`!=`, `==`, `-ne`, `-eq`, `-n`, `-z`, with `exit`, `break` or `return` on that line or in the loop condition); a token that appears only in a comment or an `echo` reads `bounded=no`, and a bounded neighbour more than 15 lines away does not lend its bound. `bounded=yes` is a LEXICAL check (it cannot see that an unset variable means "signal nothing" or that a trailing `|| true` defeats the comparison); the baseline header and the docs say so, and the rehearsal in Phase 5.2 is the behavioural proof.
  - **P** (gated) a signal to the parent: `kill` and `$PPID` on one line, or a variable assigned from `$PPID` / `ps -o ppid=` then killed within 20 lines (the distance of the one derived case in the tree, `run-registered-suites.test.sh`).
  - **G** (gated) an all-process or own-group signal at command position: `kill [-SIG] 0`, `kill [-SIG] -1` (both reach the caller's ancestors in the group). No site exists today, so G has no baseline row and is proved by a fixture.
  - **L** (listed, never gated, no baseline) targeted group signals (`kill -- -<pgid>`, `pkill -g`, `-s`, `-P`) and name-pattern signals (`pkill`, `killall`). They are not signals to ancestors, so they do not fail a suite; `--list` shows them so a mutation seat sees the whole signalling surface (14 sites today).
  - Command position for P, G and L means: line start, or after `;`, `&&`, `||`, `|`, `(`, `{`, `` ` ``, `$(`, `!`, `then`, `do`, `else`, optionally behind `sudo`, `exec`, `command`, `builtin`, `nohup`, `env`, `timeout <n>` or a backslash. Heredoc bodies are counted like any other line (a signal verb in fixture text inside a heredoc is a finding; that is deliberate, such text is often a real helper).
  - Quoted spans are masked before a verb is located at command position (a `'pkill -f x'` test input or a message is not a finding); `kill -0`, `kill -l`, comment lines and blank lines are never findings.
- Baseline row: `<path>TAB<class>TAB<normalised line>` (whitespace collapsed), the shape of `scripts/lint-shell-capture-exit.baseline.txt`, matched as a multiset. A finding of a gated class not in the baseline is **new** (red); a baseline row with no live finding is **stale** (red: the baseline may only shrink, and a stale row is also how a dead detector is noticed); a baselined **W** row whose finding is `bounded=no` is red (admissibility: an unbounded walker cannot be baselined). Without `--baseline` the scan is list-only (rc 0, summary `no baseline: listing only`), so a plugin consumer running it on their own repo does not see every site as new.
- Output: `--list` prints `class TAB bounded TAB path TAB text` for every finding of every class (`--list <suite-path>` scopes it to one file, which is how a seat checks the file it is about to mutate); the summary line is `ancestor-signal scan: <files> files, <n> findings, <b> baselined, <k> new, <s> stale, <u> unbounded, <x> skipped`, and a clean gated result additionally prints the comma-free literal line `ancestor-signal scan: CLEAN` (the discoverability probe matches this, not the bare `0 new`, which also matches `10 new`). Exit 0 clean, 1 findings, 3 unresolved. Every red verdict ends with a remedy footer: new W (bound the walk with a non-comment `[ "$p" = "$SOLEUR_TEST_SUITE_PID" ]`-style test plus exit, break or return, then add one baseline row; `$$` comparisons read `bounded=no`), new P or G (rewrite to a nonce-scoped target, or baseline it with a reviewer's read), stale (delete or swap the row), unbounded (bounding is mandatory, baselining is refused), and for all: `--write-baseline` overwrites the whole file so review the diff, untracked files are not scanned (the producer is `git ls-files`, run `git add` first), and the doc section name.
- Measured prototype (scratchpad, not committed): W 2, P 5, G 0, L 14. Baseline at introduction: 7 rows (2 W, 5 P). After Phase 5 both W rows are `bounded=yes`. `python3` is a requirement of the scan only: the doc says that a missing `python3` skips the scan with a message and does not fail the helper.
- The scan suite's fixtures are tracked data files under `plugins/soleur/test/fixtures/ancestor-signal/` (the repo's fixture convention) with a `.txt` extension, which the population patterns do not match, so no scanned source line carries a walker the scan would find in itself and no spelling trick is needed. The suite passes them to the scan as explicit PATHs, and builds a throwaway git repository (the repo's git-fixture env helper) for the producer rows.
- Documented blind spots in the docstring: multi-line quoted strings and backslash-newline continuations (`kill \` then `-1`); a walk written in another language (`os.getppid`); a two-step cursor (`parent=$(...); cur=$parent`); a kill more than 40 lines from the cursor or reached through a function; `kill $(...)` and `xargs kill`; helpers sourced from a non-suite file; suites not matching the two name shapes; fixtures stored under another extension.
- The baseline file's header states the maintenance rule: an in-place replacement of an existing row (same path and class, e.g. after an unrelated edit of that line) is allowed, a net addition needs a reviewer's read, the file may only shrink otherwise, and `bounded=yes` is lexical, not proof of containment. An unrelated edit of a baselined line therefore costs one row swap (the failure footer prints the exact row to swap), not a regeneration.

**D4. The suites avoid the corpus-walk idiom on purpose and honestly.** `lint-orphan-test-suites.sh` has a repo-wide-idiom arm: a suite whose own source contains an unscoped `git ls-files`, `find .` or a recursive `grep` must be ALWAYS_ON or carry a declared edge set. The scan's suite delegates the whole-tree walk to the scanner (the subject under test), so the arm does not fire (its regex is textual over the whole file, comments included, so neither suite's source or comments may contain `git ls-files`, `find .` or a recursive `grep`; Phase 6.1 runs the lint to prove it) and its affected-set classification stays derived (stem equality `scan-ancestor-signal-helpers.test.sh` to `.py`). The cost is stated: under the *local* `--affected` gate a diff that adds a walker in an unrelated suite does not select this suite; CI's required `test` check runs the whole battery and catches it. Promoting it to ALWAYS_ON is an edit to `scripts/lib/test-affected-paths.sh` that `scripts/test-all.sh` itself guards (an index edit must pair an added label, line 2139 onward), so it is more than a one-line change; it is put to the operator as a challenge in `decision-challenges.md` rather than pre-decided. The allocator suite `tests/scripts/test-soleur-sandbox.sh` has a declared edge set (`AFFECTED_TESTS_SCRIPTS_SOLEUR_SANDBOX_PATHS`); the new arms name the helper path `plugins/soleur/scripts/run-in-pid-namespace.sh` literally (stub and missing-helper rows do), so derivation reaches the new dependency and the declared set is not edited.

**D5. The seat-brief sentence** (copy-pasteable, one place, referenced from the others). Two branches, because the allocator exists only in this repo:

> If a mutation touches a line inside a helper that sends signals (`kill`, `pkill`, a `$PPID` walk), run every mutant ONLY inside a PID namespace: in this repo `timeout -k 5 <secs> bash "$ROOT/scripts/soleur-sandbox.sh" run-isolated "$SBX" -- <command>`; in a repo without the allocator `(cd "$SBX" && timeout -k 5 <secs> bash "$PLUGIN/scripts/run-in-pid-namespace.sh" -- <command>)`, where `$PLUGIN` is the plugin root resolved as the other references do. Exit 125 with `RUN_IN_PID_NAMESPACE_REFUSED` means no namespace is available: do not run the mutant, report the row as `UNVERIFIED-NO-NAMESPACE` with the marker's first line quoted (the lead reads it as neither green nor a survivor), still remove your sandbox, and never retry on the host. If neither path can be resolved, do not run the mutant. For a helper that only removes files (`rm -r`, `unlink`) the sandbox copy is the bound: run it in the sandbox, with the namespace as extra containment when available. The namespace bounds signals, not writes, network or the session manager.

On `UNVERIFIED-NO-NAMESPACE` the lead's options are to accept the row as unproven or to run that mutant on a Linux host that allows user namespaces; on stock macOS there is no capable host and the row stays unproven.

**D6. How the namespace is proven to contain, without ever running a lethal walker for real.** The helper's suite copies a fixture walker (a tracked data file `plugins/soleur/test/fixtures/ancestor-signal/walker-nonce.txt`, so it is inert text on disk and not a scanned source line) whose match predicate is a per-run **nonce**, not a catch-all. Fail-closed preconditions, each a suite row: the nonce must match `^[0-9a-f]{32}$` (an empty nonce is a catch-all, the incident shape; `set -u` does not catch an empty value) and `SOLEUR_TEST_SUITE_PID` must be set and numeric, else it exits 0 without signalling; the chain is collected first (with a hop cap) and a signal is sent only if every hop below the target carried the nonce; if the climb reaches pid 1 without meeting the suite PID after a reparent, it signals nothing. The chain on the host is `victim` (a bash whose argv carries the nonce, outside the namespace) -> the helper -> `top.sh` (PID 1 in the namespace, argv carries the nonce) -> `mid` (argv carries the nonce) -> `walker`. The walker climbs while the ancestor's cmdline carries the nonce and its pid is above 1, and signals the topmost such ancestor (measured: a SIGTERM sent to PID 1 from inside its own namespace is ignored, rc 0, so the positive control must be a non-init process such as `mid`). Contained: `mid` dies (positive control: the walker really signals) and `victim` is alive afterwards. If the helper regressed to run unsandboxed, the same walker would climb into `victim`, a test process with no value, never into the user's session, because nothing above it carries the nonce and the climb stops at the suite's own PID. A rehearsal row replaces `kill` by `echo` with the nonce emptied and expects no target. This is also the pattern the doc recommends for any containment test ("scope the predicate to a nonce you control; never a catch-all").

## Technical Approach

### Implementation Phases

#### Phase 0: Setup and baselines (no edits)

0.1 `git merge origin/main` once (two commits, no planned file touched). Re-run the premise checks (9217 open, no open grep-q slice PR touching `plugins/soleur/test/roadmap-reconcile.test.sh`, state of #8626 vs `review/SKILL.md` bytes).
0.2 Record baselines before editing: `wc -c plugins/soleur/skills/review/SKILL.md` (476678), `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` summary, shellcheck finding counts of the files to be edited (base side of the delta), `bash scripts/lint-orphan-test-suites.sh` summary. Serial, one at a time (load 25 to 41).
0.3 Re-measure the namespace facts the helper relies on (already measured once): `$$ == 1`, `$PPID == 0`, rc propagation (0, 3, 7, 125), nested use, `--` accepted by `unshare`, a backgrounded child reaped at PID 1's exit.

#### Phase 1: the helper (RED first: `cq-write-failing-tests-before`)

1.1 Write `plugins/soleur/scripts/run-in-pid-namespace.test.sh` first, watch it fail (helper absent), then write the helper.
1.2 Suite shape (house style: `set -uo pipefail`; `export TMPDIR="${TMPDIR:-/var/tmp}"`; fixture dir under a `mktemp -d` owned by the suite's one EXIT trap with `assert_fixture_dir` before every `mkdir`/`rm -rf`; no `producer | grep -q`; `cases` and `skipped` incremented at the call site; floors in the repo's conditional-opener form with LITERAL thresholds, an unconditional floor on the always-run counter and a separate literal floor inside the real-namespace branch, never a computed threshold; no `git ls-files`, `find .` or recursive grep in its source or comments).
   - Always-run rows (stub `unshare` on a private `PATH`, a witness file written by the wrapped command at its FIRST instruction): R1 `unshare` absent -> rc 125, marker `reason=missing-unshare`, witness absent; R2 stub exits 1 with an EPERM message -> rc 125, `reason=userns-unavailable`, the stub's first line quoted on ONE line, witness absent; R3 stub exits 0 but runs the command in place (a dishonest `unshare`) -> rc 125 `reason=not-isolating`, witness absent; R4 stub records its argv -> over the parsed flag set (combined `-Urpf` and split spellings equivalent) `-U -r -p -f --kill-child --mount-proc` each present once before `--`, then the command and its arguments verbatim (spaces, an empty argument, a leading `-n`); R5 usage error rc 2; R6 witness control: run the witness-writing command directly and assert the witness appears (so "witness absent" in R1 to R3 means "never started", not "could not write"); R7 a stub whose probe call is isolated and whose run call is not -> rc 125 with the marker, witness absent, and the stub's call log proves the probe took the isolated branch and the run the in-place branch; R9 an exported shell function named `unshare` that returns 0, with no real `unshare` on `PATH`, must not decide the probe (refusal `missing-unshare`, with the marker).
   - Probe-driven rows: one real probe at the start decides `REAL_NS=yes|no`. When `no`, print `SKIP real-namespace rows (N): <unshare's first stderr line>`, count them in `skipped`, and run row R8: the REAL helper refuses with rc 125 + marker (so the unavailable branch is exercised for real on CI shapes where userns is restricted, and on macOS where `unshare` is absent). `SOLEUR_REQUIRE_REAL_NS=1` turns `no` into a FAIL instead of a SKIP (honoured by the suite; no workflow is edited here to set it). When `yes`: N1 the command is PID 1, `$PPID` 0, and `/proc/self/status` shows one `NSpid` field; N2 exit codes 0, 3 and 125-without-marker pass through (a signal death of PID 1 cannot be produced from inside the namespace, so no signal-death row is claimed; the observed behaviour is recorded in `evidence.md`); N3 stdin/stdout/stderr and cwd pass through, stderr carries nothing the command did not write, and a command path beginning with `-` runs; N4 the nonce-walker chain of D6 (positive control `mid` dead, `victim` alive) plus the fail-closed preconditions (empty nonce, unset or non-numeric suite PID, reparented chain: each signals nothing, via a `kill`-to-`echo` rehearsal); N5 a backgrounded `sleep` started by the command is gone after the helper returns, and again after the helper is SIGKILLed from outside (N5b: `--kill-child` reaps the tree; bounded polls, no fixed sleeps); N6 a nested helper call works; N7 a wrapper `unshare` that drops `--mount-proc` (it execs the real `unshare` without the flag) is refused with `not-isolating`. Accounting: `cases + skipped == planned_total` so a deleted row is distinguishable from a skipped one; floors: always-run >= 8 (literal), real-namespace branch >= 7 (literal).
1.3 The helper (about 60 lines, shellcheck-clean, `set -u`, every exit path explicit; the refusal text is built without backticks inside double quotes, and the rows that trip each refusal are run after any text edit).

#### Phase 2: the scan

2.1 Write the scan's suite first. Fixtures are tracked data files under `plugins/soleur/test/fixtures/ancestor-signal/` (`walker-bounded`, `walker-unbounded`, `walker-comment-bound` (the token only in a comment: must read `bounded=no`), `walker-echo-bound`, one bound-comparator fixture per form, window-edge fixtures at 15/16, 40/41 and 20/21 lines, `parent-direct`, `parent-derived`, `group-all`, `listed-targeted-and-pattern`, one must-PASS file per mention form (comment, quoted, `kill -0`, `kill -l`), `walker-nonce` (used by the helper suite)); the scan is invoked with explicit PATHs; the producer rows use a throwaway git repository built with the repo's git-fixture env helper (`plugins/soleur/test/lib/git-fixture-env.sh`), so no real repo state is touched and the git tripwire is respected.
2.2 Rows: see Guard 2 (18 rows). Floors are literal and `cases` is incremented at the call site; `cases + skipped == planned_total`.
2.3 Live row: run the scan over the repo with the committed baseline; require rc 0, `0 new, 0 stale, 0 unbounded`, the literal `ancestor-signal scan: CLEAN`, a population floor (>= 600 files; the measured count is recorded in `evidence.md`), a top-level root set that is a superset of `.claude apps plugins scripts tests`, and the two known walkers present as `W bounded=yes` (the positive control that the detector still finds what it exists for). Time the live run and record it (target under 5 s; the discoverability probe runs under a 15 s cap, and a timeout there reads as a FAILED probe, not a skip).
2.4 Write the scan (about 260 lines, stdlib only, no import from the scanned tree, entry point wrapped so an exception is rc 3), seed the baseline from the scan's own `--write-baseline`, and review every row by eye against the prototype (7 rows). Also run the exact discoverability command under Check 10's shape (`env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=<tmp>` with the repo read-only, under `timeout 15`) and record its output.

#### Phase 3: the allocator verb

3.1 Arms first in `tests/scripts/test-soleur-sandbox.sh` (already a registered suite; the new arms name `plugins/soleur/scripts/run-in-pid-namespace.sh` literally so its declared edge set reaches the new dependency): `run-isolated` with a valid allocated sandbox runs the command with `pwd` equal to the sandbox (a recording stub `unshare` writes its own cwd, so this is observable where no namespace exists), inside the namespace when `REAL_NS=yes` (pid 1) and refusing 125 + marker when it is not; refuses with rc 2 and WITHOUT the helper's marker for each of: relative path, missing, a symlinked component, wrong basename, no marker, a marker that is a directory or symlink; missing `--` -> rc 2; missing or non-executable helper -> rc 2 and the command NOT run (witness absent); a trailing slash is accepted; usage text lists the verb; one row asserts every doc surface that carries the rule (`work-scratch-sandboxes.md`, `risk-tier-and-fix-rounds.md`, `test-design-reviewer.md`) names both `run-isolated` and `RUN_IN_PID_NAMESPACE_REFUSED`, so the wording cannot drift apart.
3.2 Implement the arm (about 30 lines) in `scripts/soleur-sandbox.sh`, update the header comment and `usage`.

#### Phase 4: wiring the rule where seats are briefed

4.1 `work-scratch-sandboxes.md` (open the new section with the "plugin root in this file" preamble the sibling references carry, because a bare `${CLAUDE_PLUGIN_ROOT}` is not substituted in a Read file): new section "## Mutating a signalling or file-removing helper" after "Allocate, use, remove": how to recognise the class (grep the block and the helper for `kill|pkill|killall|PPID|rm -r|unlink|-delete`; the question "what does the predicate bound?"), the D5 sentence in both branches (verb, and the helper with `(cd "$SBX" && ...)` for the bare-`mktemp` fallback sandbox of a repo without the allocator; no hand-written `unshare` line, which would be the unguarded spelling), the `UNVERIFIED-NO-NAMESPACE` verdict and the lead's options (accept the row as unproven, or a Linux host; stock macOS has none), cleanup of the sandbox on the refusal path too, a deleted marker leaving the copy to the 24 h reaper (no `rm -rf` around the refusal), the rc-125 rule, "signals vs writes (and not network or IPC)", the PID-1 caveat and `timeout -k` (never a plain `timeout`), the environment differences inside the namespace (the caller is uid 0 and `/proc` shows only the namespace, so a suite with a not-root guard, an EACCES row or a host `pgrep` expectation behaves differently: run the UNMUTATED control inside the namespace first, and treat a red control there as an environment difference, not a kill), the nonce technique of D6, and the scan (`python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --list <suite-path>` to scope it to the file about to be mutated; `${CLAUDE_PLUGIN_ROOT}/scripts/...` for a consumer, where it is list-only without a baseline and a missing `python3` skips it with a message; a signal verb in a sourced or non-suite helper is a blind spot: assume the lethal class and use the verb). The paragraph that says "no script in the repo: use the fallback" keeps its existing fallback for the copy; the new section does not duplicate it.
4.2 `review/SKILL.md` line-217 paragraph: append one sentence of at most 220 bytes pointing at the verb and rc 125. The span must not open with `scripts/` or `references/` (`components.test.ts` fails a SKILL.md body that does; line 217 opens its span with `bash "$ROOT/...`), so use a markdown link or no path; measure AFTER that constraint, drop if it does not fit the 322-byte headroom, never edit `skill-body-budget.json`.
4.3 `review/references/risk-tier-and-fix-rounds.md` "Briefing fix agents and seats": one bullet: any brief that asks a seat (or the lead's own battery) to flip a line in such a helper carries the D5 sentence; a report-only seat is instead told to reason about the line and report, not to run it; the lead mutation-tests named gaps through the verb. Check `review-tier-parity.test.ts`, `fix-round-seats.sh` and `emit-review-trailer.sh`, which read this file, for anchors the bullet could disturb.
4.4 `agents/engineering/review/test-design-reviewer.md` "Auditing a Mutation Battery": one bullet: a battery or plan row that mutates a line inside a signalling or file-removing helper without running through the isolated verb is a finding against the INSTRUMENT (unsafe, severity high), and a suite helper that walks ancestors must be bounded at the suite PID and, where the repo ships a scan baseline, be listed by the scan. `plugins/soleur/.claude-plugin/agents.manifest.json` carries only the description (unchanged).
4.5 `plan/references/plan-sharp-edges.md`: one entry (about 700 characters) naming the trigger (a plan prescribes "flip every converted line", "invert the matcher" or an observer over a block containing `kill`/`pkill`/`$PPID`/`rm -r`), the requirement (name the namespace in the AC and the observer paragraph, run the scan `--list` for known sites) and the Why with the learning path.

4.6 If ADR-250's text enumerates the allocator's verbs, append a one-line amendment for `run-isolated` through `soleur:architecture`; if it does not, no ADR change is made (the rule is workflow guidance, not an architecture decision).

#### Phase 5: bound the second walker

5.1 In `plugins/soleur/test/roadmap-reconcile.test.sh`: `export SOLEUR_TEST_SUITE_PID=$$` once near the top (above the fake `gh` heredoc, which is quoted so the variable is read at run time from the environment), and in the `term` branch: a fail-closed guard when the variable is unset (the exact form is chosen in work against the row's expectations), the loop gaining `&& [[ "$p" != "$SOLEUR_TEST_SUITE_PID" ]] && [[ "$p" -gt 1 ]]`, and a comment stating the hazard and the namespace rule at the match line (the S5 wording). Unset means the helper signals nothing, so TS15e fails red rather than anything being killed; a mutant that removes the unset guard is a Guard-2-adjacent row run through the helper (the walk must still stop at the suite because pid 1 and the suite PID coincide inside the namespace, asserted in the no-kill rehearsal run through the helper too). The walk itself stays: the target is the module's process, an ancestor of the fake `gh` across a command-substitution subshell, and the fake cannot be told its PID (the module is launched by `run_main` and is not modified). Replacing the walk by a pidfile would change `run_main`'s launch shape and is a larger diff for the same containment.
5.2 Add one committed row to `plugins/soleur/test/roadmap-reconcile.test.sh`: anchored static assertions that the `term` branch carries, on non-comment lines, the unset guard, the suite-PID comparison and the `-gt 1` bound (a later edit that keeps the token on a dead line then reds the row and the scan's `bounded` rule); the behavioural proof is the rehearsal below, recorded in `evidence.md` because running the walker needs the namespace. Rehearse before relying: no-kill rehearsal (catch-all match, `kill` replaced by `echo`) printing the resolved target, which must be the module's PID and nothing above it; then the unmodified suite green (the whole file), then the catch-all mutant red (rc 1 on TS15e) with the session unaffected, run through the helper.
5.3 If an open grep-q slice PR touches the file, add its `hand-edits.txt` entry (Phase 0.1 decided).

#### Phase 6: verification (serial, load-aware)

6.1 Cheap repo-global lints from the brief, each alone: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (0 new), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` (the two new suites covered via the glob, none orphaned or unclassified, the repo-wide-idiom arm silent), shellcheck delta over every created or edited shell file (count at base vs head; new notes only of kinds the files already carry), `python3 scripts/lint-guard-contract.py` over this plan, `bun test plugins/soleur/test/components.test.ts` when bun is installed (the executable-surface and backtick-reference lints now cover the new files and the SKILL.md pointer; otherwise the CI leg), `bash .claude/hooks/grep-q-pipe-guard.test.sh` (the new files add no early-exit pipe under the swept `plugins/soleur/` root), `bash scripts/pre-push-ratchet-lane.sh` once at the end (fixture and trap ratchets that a targeted run cannot see: `fixture-relative-assert`, `lint-trap-tempfile-ownership`).
6.2 Targeted suites by name: the two new suites, `bash tests/scripts/test-soleur-sandbox.sh`, `bash plugins/soleur/test/roadmap-reconcile.test.sh`, `bash plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` (unchanged; its baseline row is read by the scan), `bash scripts/lint-skill-body-budget.test.sh`, `bash plugins/soleur/test/scripts-shard-manifest.test.sh` and `bash plugins/soleur/test/scripts-shard-totality.test.sh` (shown, not asserted: the new suites are covered by the glob and untabled labels hash-fall-back), the bun/vitest `review-tier-parity` test if the runner is installed (otherwise the CI leg). No `test-all.sh --affected`, no `--print-selection`.
6.3 Userland check, when docker is available and the load allows: `docker run --rm -v "$PWD":/w -w /w ubuntu:24.04` (install `git jq python3 curl openssl`, log under `/var/tmp`), the new suites with the same always-run row count as the host; in the container the real-namespace branch is expected to SKIP (the default seccomp profile blocks `unshare`), so this run proves only the refusal branch (R8) and the userland of the stub, scan and lint rows, not containment. The only real-namespace signal in CI is the scripts leg's best-effort sysctl relaxation (`ci.yml`); the plan records that the `REAL_NS=yes` rows may never run in CI. If docker or the time is not available, record that CI's ubuntu-24.04 scripts leg is the userland check.
6.4 Mutation protocol for Guards 1 to 3: a sandbox from the allocator (git-init'd inside it for the scan's live row), one mutant at a time under `ulimit -v 6000000`, pristine copy restored by `cp` from a backup (never from git), a landing check per mutant (`cmp` plus a content assertion in the region), an unmutated control first (credit nothing from a red baseline; the control runs inside a working namespace, probed first, and a known-negative proves the instrument can say RED), rc discrimination (only rc 1 plus a FAIL line naming the expected row is a kill; rc 2, 125, 127 and a `ulimit -v` abort are "instrument, not evidence", so a host without namespaces cannot read 14 of 14 caught), a `timeout -k` bound on every mutant (a plain `timeout` does not stop a PID-1 command), and **the whole battery driver run as `bash plugins/soleur/scripts/run-in-pid-namespace.sh bash <driver>`** (the helper protects its own mutation battery; the mutants of the walker fixtures and of the helper are never on the host). Record in `evidence.md` (written from the final state, corrections appended not edited in place).

## Files to Create

- `plugins/soleur/scripts/run-in-pid-namespace.sh`
- `plugins/soleur/scripts/run-in-pid-namespace.test.sh`
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`
- `plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt`
- `plugins/soleur/test/fixtures/ancestor-signal/` (about 20 small `.txt` data files: the scan suite's fixtures and the helper suite's nonce walker; the `.txt` extension keeps the scan's population patterns from matching them)
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

Derived, not assumed: every `.github/workflows/*.yml` with a `push`, `pull_request`, `merge_group` or `pull_request_target` trigger (88 workflows in the directory; 38 carry one of those triggers) was parsed and GitHub filter semantics applied (`*` stays within a segment, `**` crosses `/`, `!` negates, later patterns override) to the 37 planned paths (final list, about 20 of them fixture files). Result:

- Path-filtered push workflows that match: `version-bump-and-release.yml` (`plugins/soleur/**`) 31 of 37 (a plugin patch release), `web-platform-release.yml` (`apps/web-platform/**` and `plugins/soleur/**`, minus `plugins/soleur/docs/**` and `plugins/soleur/test/**`) 10 of 37 (a web image release and, as in S5, a deploy of it), `deploy-docs.yml` 5 of 37 (a docs-site deploy).
- No other path-filtered push or pull_request workflow matches (0 of 37 for each).
- Unfiltered, as on every merge: `ci.yml` (the required `test` check, full battery), `codeql-main-alert-gate`, `secret-scan`, `skill-security-scan-corpus`, `skill-security-scan-postmerge`, `tenant-integration`, `vendor-pin-verify`, plus the PR-time unfiltered set (`pr-quality-guards`, `claude-code-review`, `cla`, ...).
- `scripts/soleur-sandbox.sh` and `tests/scripts/test-soleur-sandbox.sh` match no filter; `plugins/soleur/test/roadmap-reconcile.test.sh` matches only the plugin-release filter (the web release excludes `plugins/soleur/test/`).
- Sanity probe for the matcher: adding `apps/web-platform/infra/server.tf`, `plugins/soleur/docs/x.md` and `scripts/test-all.sh` to the list lights further filtered workflows, so the matcher is not vacuous (re-run in Phase 6 on the final diff).
- The PR body states the first three as its **first line**. No `[skip-deploy-fix-apply]`, no `app:web-platform` label (nothing under `apps/web-platform/` changes; `plugins/soleur/skills/ship/SKILL.md` applies it only for that path), `semver:patch`, `type/chore`, `domain/engineering`.

## Guard Contract

### Guard 1 — run-in-pid-namespace.sh fails closed

**Property.** The wrapped command never starts unless it is PID 1 of a fresh PID namespace with that namespace's own `/proc`; every other outcome is rc 125 with the marker line and the command not started.

**Assembly.** The chokepoint is the single `exec "$u" ... sh -c '<check> || { marker; exit 125; }; exec -- "$@"'` line: every successful path flows through it and nothing else execs the command. Four refusal arms feed rc 125 (missing `unshare`, failed probe, non-isolating probe, the in-namespace re-check), each with its own test row and each printing the marker. `unshare` is resolved once to an absolute path and the probe and the exec share it. The allocator verb (Guard 3) calls the helper rather than spelling the flags, and the docs name only the helper's path, so there is one spelling of the flag set. The order property (refusal before the command starts) is observed by a witness written by the command at its FIRST instruction and read after the helper returns, so a late kill would still show the witness.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the `exec "$u" ...` line with `exec -- "$@"` (no namespace) | RED: R4 (the argv stub never sees the flags), N1 (not PID 1) where real. A stub proves the flags were passed, not that they isolate; `-p`, `--mount-proc` and `--kill-child` are proven only by N1, N4, N5 and N7, which skip where namespaces are unavailable (stated limit) |
| 2 | Dispatch: make the probe always succeed (`true`) | RED: R3 (a dishonest in-place `unshare` now reaches the in-namespace re-check, which refuses with `reason=not-isolating`; the witness stays absent, so the kill is the marker assertion, not the witness) |
| 3 | Refusal arm prints the marker but exits 0 | RED: R1, R2, R3 (rc must be 125) |
| 4 | Refusal arm prints the marker and then falls through to `exec -- "$@"` | RED: witness present in R1, R2, R3 |
| 5 | Remove only the missing-`unshare` arm, leave the other three (a second member after a compliant first) | RED: R1 alone |
| 6 | Remove only the not-isolating arm | RED: R3 alone |
| 7 | Drop one flag at a time: `-p`, `--kill-child`, `--mount-proc`, `-U` (four mutants; `-r` and `-f` are asserted by the same R4 loop and are not run separately) | RED: R4 for each (over the parsed flag set, combined `-Urpf` and split spellings equivalent); N1 for `-p`; N7 for `--mount-proc` (the host `/proc` check); N5 for `--kill-child` |
| 8 | Delete the in-namespace check | RED: R7 (positive control inside R7: the stub's log must show the probe call took the isolated branch and the run call the in-place branch, so a change of the probe text cannot silently re-route R7) |
| 9 | Resolve `unshare` by bare name again (drop `type -P` and the shared `"$u"`) | RED: R9 (an exported function `unshare` that returns 0 must not decide the probe) |
| 10 | Harness row: edit the suite so the witness path is never written (the command writes elsewhere) | RED: the witness control R6 |
| 11 | Must-PASS non-canonical input: arguments with spaces, an empty argument, a leading `-n`; a command path beginning with `-` | PASS: R4 (argv verbatim) and N3 (`exec --`) |
| 12 | Where real namespaces are unavailable the real helper must still refuse (the branch that actually runs on restricted CI and on macOS) | PASS (refusal); RED if the helper ran the command: R8 |
| 13 | Drop the `/proc` half of the check (keep only `$$` is 1) | RED: N7 (a wrapper that drops `--mount-proc` must be refused; on a stub-only host the NSpid arm is covered by R7's stub variant that reports two NSpid fields) |

**Anchor.** No stored value is compared. The independent witnesses are behavioural: N1, N4, N5 and N7 in a real namespace, and the stub-argv row R4 where none is available. The suite counts `cases + skipped == planned` so a deleted row is distinguishable from a skipped one, and an opt-in `SOLEUR_REQUIRE_REAL_NS=1` turns a missing namespace into a FAIL (the suite honours it; no workflow is edited here to set it).

### Guard 2 — the signal-helper inventory ratchet

**Property.** Every ancestor-walk, parent-signal and all-process-signal line in a tracked shell test suite is either a row of the committed baseline or fails the suite, a baseline row with no live line fails the suite, and no baselined ancestor walk is unbounded.

**Assembly.** The population flows through one `git ls-files -z` call with two pathspecs (`*.test.sh`, `:(glob)**/test-*.sh`) under a `GIT_*`-free child environment; three gated detector classes (W, P, G) plus the listed-only class L share one line normaliser and one multiset matcher against the baseline; the suite's live row is the only CI caller. Members drift (suites are added anywhere), so the assertion is structural: the population floor, the root-set superset (`.claude apps plugins scripts tests`), and the known-member control (both walkers present as `W bounded=yes`) pin that the walk still reaches what it exists for.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture corpus gains a new walker line not in the baseline | RED, naming file and class W |
| 2 | Dispatch: the producer returns zero files (pathspec emptied) | RED: rc 3 UNRESOLVED in the scan, and the suite's population floor |
| 3 | Dispatch: the producer is narrowed to `*.test.sh` only (drops `test-*.sh`) | RED: the producer row (a walker in `test-x.sh` of the throwaway repo must be found) and the root-set row (`tests` missing) |
| 4 | Fixture file has two sites, the first baselined, the second not (a check that stops at the first) | RED naming the second |
| 5 | Neuter class W's cursor regex | RED: the known-member control (both walkers must be found) and the stale-row check (the W baseline rows have no live finding) |
| 6 | Neuter class P, then class G (two mutants); a derived-variable P fixture is separate from the direct one | RED: stale baseline rows for P; the fixture rows for P-derived and G (no baseline row exists for G, so only the fixture can see it) |
| 7 | Delete the baseline row of a live site | RED (new) |
| 8 | Add a baseline row for a line that does not exist | RED (stale) |
| 9 | Remove the multiset count (treat duplicates as one) | RED: the duplicate fixture row (two identical lines against one baseline row read new; three rows against two lines read stale) |
| 10 | Bound-token forms: a comment-only mention, an `echo` mention, the token removed, and each comparator form (`!=`, `-ne`, `-z`) present | RED (unbounded) for the first three; PASS (bounded) for each comparator fixture |
| 11 | Window edges: the bound token 15 and 16 lines above the cursor; the kill 40 and 41 lines from the cursor; a derived P 20 and 21 lines out; each constant shifted by one in a mutant | RED for the shifted constants, one fixture per edge |
| 12 | Treat class L as gated | RED: the L fixture row (listed, rc 0) |
| 13 | Must-PASS: the same baselined line shifted by inserted blank lines; the same line re-indented and whitespace-collapsed; the same content under a different path (must read new: path-keyed AND content-keyed) | PASS for the first two, RED (new) for the third |
| 14 | Must-PASS, one fixture each so one mutant cannot hide behind another: a comment mention, a quoted mention, `kill -0 "$p"`, `kill -l` | PASS, no finding, one row per input |
| 15 | Harness row: neuter the suite's `fail()` | RED: `guard-vacuity-floor.test.sh` and the suite's own conservation and floor checks |
| 16 | Empty population and unreadable baseline passed as success | RED: the rc-3 rows |
| 17 | Environment: run the scan with a bogus `GIT_DIR` and `GIT_INDEX_FILE` exported; a symlink and a non-UTF-8 path in the throwaway repo; a pathological 100 KB single line | PASS (population unchanged), counted `skipped` for the symlink, no hang (timing bound), no traceback (rc 3 on an induced exception) |
| 18 | After-remediation: the original `roadmap-reconcile.test.sh` walker must read `bounded=no`, the Phase 5 edit `bounded=yes` (run on both) | RED on the original, PASS on the fixed file |

**Anchor.** A baseline row can be added in the same diff that adds the walker, so the suite certifies consistency between code and baseline, not integrity. What outside the commit moves for a weakening to pass: a reviewer reading a baseline addition (one content line, like `lint-shell-capture-exit.baseline.txt`), plus the admissibility rule, which removes the one weakening that matters (an unbounded walker cannot be baselined at all, so adding a row does not make a lethal walker pass); `bounded=yes` is lexical and the header says so. A merge-base shrink-only check is cut (Cut List) because the test legs do not guarantee a fetched base.

### Guard 3 — `run-isolated` starts nothing outside a sandbox

**Property.** `soleur-sandbox.sh run-isolated` runs the command only with an allocated sandbox as the working directory and only through the helper; every other input is rc 2 (no helper marker) with the command not started.

**Assembly.** One verb arm (the chokepoint), one sandbox-shape check (absolute, `cd -P` and `pwd -P` agree, `soleur-sbx.?*` basename, regular non-symlink marker tested from inside, owned by the caller), one helper-path resolution from `$HERE`. The stub-`unshare` rows record the stub's own `pwd` so the working-directory property is observable even where no real namespace exists.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the sandbox-shape check | RED: the bad-shape rows (command ran, witness present) |
| 2 | Dispatch: the verb arm dispatches to `rm` or to `usage` | RED: the valid-sandbox row |
| 3 | Drop one conjunct at a time: absolute path, `pwd -P` agreement, basename, marker present, marker regular and non-symlink, owner (six mutants) | RED: one bad-shape row per conjunct (relative path, a symlinked component, wrong basename, no marker, a marker that is a directory or symlink) |
| 4 | Accept a symlink to a sandbox | RED: the symlink row |
| 5 | Missing or non-executable helper falls back to running the command directly | RED: the missing-helper row (witness absent, rc 2) |
| 6 | Run the helper before `cd` (cwd stays the live tree) | RED: the recording stub's `pwd` must equal the sandbox |
| 7 | Print the helper's marker on a shape refusal | RED: the shape rows assert rc 2 and the marker's absence |
| 8 | Must-PASS non-canonical: sandbox path with a trailing slash | PASS |

**Anchor.** Not applicable (no stored value); the independent witness is the recording stub's `pwd`, and `pwd` printed from inside the namespace where one exists.

## User-Brand Impact

- **If this lands broken, the user experiences:** a mutation seat told to "run it isolated" that either refuses a healthy host (a seat stops and reports instead of proving its line) or, worse, runs the mutant unsandboxed because a wrapper regressed, which is the incident again: a desktop session ended with no warning. A broken scan fails the full-battery check red on an unrelated PR.
- **If this leaks, the user's workflow is exposed via:** no data or credential is read or written; the exposure vector is a false sense of safety, a seat or a plugin user trusting a wrapper that does not isolate (Guard 1 rows 1, 2, 4 and 8 and the dishonest-`unshare` stub exist for exactly that) or a baseline that certifies an unbounded walker (Guard 2's admissibility rule).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident`: the change adds containment to an internal test workflow, touches no user data, no deploy path and no credential, and a failure of the helper is rc 125 and a stopped seat, not a user-visible effect; not `none` because the same mistake already cost an operator four desktop sessions and plugin users run the same briefs, so a regression repeats across seats; the diff touches no sensitive path, so no `threshold: none` scope-out is needed.

## Observability

```yaml
liveness_signal:
  what: "the scan prints the literal line \"ancestor-signal scan: CLEAN\" (exit 0) when the committed baseline matches the tree; its suite runs in the CI scripts group on every PR and merge_group run"
  cadence: per PR and per merge_group run through CI's full battery only (the local affected gate does not select the suite for an unrelated diff, see D4), and on demand
  alert_target: the required test check turns red on the PR, which blocks merge
  configured_in: the pre-existing glob plugins/soleur/scripts/*.test.sh in scripts/test-all.sh SUITE_GLOBS (not edited here), plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh (the live row)
error_reporting:
  destination: "CI job log of the test check (workflow run log, ::error:: annotations); repo-hygiene tooling, no Sentry surface. The helper's refusal reaches a seat or a plugin consumer without ssh - the marker line is on the stderr of the tool result of the helper call, and row R8 runs it for real on restricted runners"
  fail_loud: a FAIL line naming the file, class and normalised line of each new, stale or unbounded finding plus a remedy footer, exit 1; an empty population, a failed git call, an unreadable baseline or an uncaught exception prints UNRESOLVED and exits 3; the helper prints RUN_IN_PID_NAMESPACE_REFUSED reason=... as the first stderr line (stderr only, so a wrapped command's stdout capture stays clean) and exits 125
failure_modes:
  - mode: a new ancestor-walking or signal-to-ancestors helper lands in a shell test suite
    detection: "the scan reports it as new in the suite's live row (workflow run log, ::error:: lines in the test job)"
    alert_route: required test check red on the PR (workflow run log)
  - mode: the producer stops reaching a root or a detector class stops matching
    detection: population floor, root-set superset, the two known walkers as W bounded=yes and stale baseline rows, in the suite's live row (workflow run log)
    alert_route: required test check red on the PR (workflow run log)
  - mode: user namespaces are unavailable where a seat expects isolation (layer 7, a plugin consumer's own host)
    detection: the helper's rc 125 and first stderr marker line, read from the tool-result stdout/stderr of the helper call (cli-stdout-artifact); the durable pairing is the seat report line UNVERIFIED-NO-NAMESPACE with the marker quoted, committed with the lead's evidence record. Hosted-agent coverage is not claimed - the marker is not SOLEUR_-prefixed, so the hosted Bash marker extractor does not mirror it, and the hosted sandbox is not a mutation-seat host
    alert_route: the seat stops and reports; CI shows the SKIP count line for the real-namespace rows (workflow run log)
  - mode: the wrapper regressed to run the command in place
    detection: suite rows R3, R4, R7, N1, N4, N7 in the helper's suite (workflow run log); on a runner where real rows skip, R3, R4 and R7 still run
    alert_route: required test check red on the PR (workflow run log)
logs:
  where: CI job log of the scripts test group; stderr of the helper in the seat's tool result
  retention: the CI log retention of the repository
discoverability_test:
  command: python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --baseline plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt
  expected_output: "ancestor-signal scan: CLEAN"
```

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO assessed the plan headless. Agreed: a PID namespace is the right containment for the signal class, never falling back is correct, the nonce-scoped real-namespace arm is the regression test for the incident, and the roadmap-reconcile bound is the root-cause fix with the namespace as a second layer. Applied: rc passthrough is asserted for 0, 1, 3 and a signal death with the observed mapping recorded (`--kill-child` with `-f` may flatten it); non-Linux and missing-`unshare` hosts refuse cleanly and the glob-registered suite SKIPs visibly (row R10); the doc states the namespace does not bound files, network, IPC or signals from outside. Challenged and kept at the operator's stated direction (persisted as user-challenges in `decision-challenges.md`): cut the scan to ancestor walks only or into a grep inside an existing suite; drop the review `SKILL.md` and plan-sharp-edges edits; place the helper in `scripts/lib/` with only its test in the plugin. Plan-review's engineering panel is the second read. No architecture decision is made: a containment wrapper and a lint do not move a tenancy boundary, add a substrate or change a trust boundary, so the ADR/C4 gate (plan Phase 2.10) does not fire and no `.c4` file changes; `plugins/soleur/test/c4-count-parity.test.sh` is unaffected (no workflow, monitor or heartbeat is added).

Product/UX Gate: none (no UI surface; the mechanical UI-surface override matched no planned path). GDPR gate: no regulated-data surface and none of the (a)-(d) expansion triggers. IaC gate, encryption-posture gate: no infrastructure, store or connection is introduced.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md (interactive only; headless run, no block written) -->

- [ ] AC-1. `bash plugins/soleur/scripts/run-in-pid-namespace.sh sh -c 'echo $$ $PPID'` prints `1 0` where user namespaces are available; where they are not it exits 125 with a first stderr line starting `RUN_IN_PID_NAMESPACE_REFUSED` and the command did not run. Both branches are asserted by `bash plugins/soleur/scripts/run-in-pid-namespace.test.sh` (rc 0, always-run rows >= 8 and real-namespace rows >= 7 when available, `cases + skipped == planned_total`, the SKIP count line printed when real rows are skipped).
- [ ] AC-2. The helper never falls back: the dishonest-`unshare` stub, the failing stub, the missing-`unshare` PATH and the re-check stub each end rc 125 with the witness absent (rows R1 to R3, R7).
- [ ] AC-3. `bash tests/scripts/test-soleur-sandbox.sh` passes with the `run-isolated` arms: a valid sandbox runs in the namespace (or refuses 125 where unavailable), each bad shape refuses with the command not started, a missing helper is rc 2.
- [ ] AC-4. `python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --baseline plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt` exits 0 and prints `ancestor-signal scan: CLEAN` (summary `0 new, 0 stale, 0 unbounded`); its `--list` shows both ancestor walkers as `W bounded=yes` and the listed-only class L; the baseline is the scan's own `--write-baseline` output reviewed row by row (7 rows: 2 W, 5 P, unless Phase 0 re-measures a different count, then recorded in `evidence.md`).
- [ ] AC-5. `bash plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh` passes with every row of Guard 2 and its absolute floor, including: a comment-only bound token reads `bounded=no`, an unbounded W cannot be baselined.
- [ ] AC-6. `plugins/soleur/test/roadmap-reconcile.test.sh` passes (all rows), its `term` walker stops at `SOLEUR_TEST_SUITE_PID` and signals nothing when it is unset, a no-kill rehearsal printed the module PID and nothing above it, and the catch-all mutant ran only through the helper.
- [ ] AC-7. The D5 sentence appears in `work-scratch-sandboxes.md`; a pointer or bullet appears in `risk-tier-and-fix-rounds.md` and `test-design-reviewer.md` (and in `review/SKILL.md` when it fits); `plan-sharp-edges.md` carries the one entry; no surface contains a hand-written `unshare` line other than the helper.
- [ ] AC-8. `plugins/soleur/skills/review/SKILL.md` is at most 477000 bytes (`wc -c`) and `plugins/soleur/test/skill-body-budget.json` is not in the diff.
- [ ] AC-9. Repo-global lints green on the final tree, each run by its own invocation: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (0 new), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` (the new suites covered, none orphaned or unclassified), `python3 scripts/lint-guard-contract.py` over this plan, `bun test plugins/soleur/test/components.test.ts` when bun is installed (the executable-surface and backtick-reference lints now cover the new files and the SKILL.md pointer; otherwise the CI leg), `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash scripts/lint-skill-body-budget.test.sh`, shellcheck delta (head not worse than base except notes of kinds the files already carry), `bash scripts/pre-push-ratchet-lane.sh` verdict PASS.
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
| Put the helper in `scripts/lib/` (glob-registered via `scripts/lib/*.test.sh`) | Repo-only: plugin users would not get it, which the brief's "for us or soleur users" rules out; registration is not the reason (the `scripts/lib/` glob exists) |
| Put the scan, baseline and fixtures repo-only (`scripts/lib/`) and keep only the helper in the plugin | The scan is generic and useful to plugin users (`--list` without a baseline); the baseline lists this repo's suite paths and the fixtures carry walker text, so they ship too, accepted: the plugin release is unavoidable anyway because the skill and agent edits already match `plugins/soleur/**`; recorded in `decision-challenges.md` |
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
