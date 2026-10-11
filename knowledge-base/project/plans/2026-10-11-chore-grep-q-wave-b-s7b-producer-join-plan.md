---
title: "chore: grep -q pipe-guard series, slice S7b (producer-side join, Arm P)"
date: 2026-10-11
slug: grep-q-wave-b-s7b-producer-join
branch: feat-one-shot-grep-q-pipe-guard-s7b-producer-join
issue: 9217
type: chore
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-11. **Method:** a four-seat plan-review panel (simplicity, correctness, DHH-style, devex), then the deepen-plan mechanical halts (user-brand, observability, PAT, Guard Contract lint, Scope Check schema) and live verification of every cited commit, PR, label and rule id; the all-agent fan-out was not run because each mechanism had already been read against the real guard and suites by two seats.

- Reproduced the brief's "about 29 sites in 20 files" with a committed derivation (`j0-derive.py`), and showed the verb-free population is 60 pairs in 48 test files.
- The review measured that the first derivation could not see the cases that motivated the guard (a stub in a sourced harness, a variable-named `ssh` stand-in); the plan now has a one-hop sourced arm and named recall rows.
- Replaced the region extractor with a positional first-statement pin, replaced the wall-clock delay with a sentinel hand-off, fixed a snippet that redirected to `/dev/null.stdin`, made shell portability explicit, and moved wall-clock and load conditions out of the acceptance criteria.
- Dropped the pre-registered cut gate; the open design questions are recorded as decision-challenges items 1 to 8 (user-challenge items 1 and 5).

## Overview

Slice S7b of the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482). S1 to S6 and S7a are merged and deployed (S7a merge `abd08840a2`, deployed via `21331e94e3`), so every consumer-side pipe the guard can see is converted or owned by a file-exact row. What is left is the PRODUCER side: a test stub that never reads the stdin a non-test `printf ... | verb` feeds it, so the writer takes SIGPIPE (or EPIPE where SIGPIPE is ignored, as on CI) and `pipefail` folds that into a false failure. The guard header says so in one sentence: it is "invisible to any line search: it needs a join from each production pipe to the owning suite's stub".

Three real instances already cost CI cycles: the `cryptsetup` stubs (#9245, fixed in #9261), the `ssh` stub in the workspaces-luks-verify-workflow suite (#9525), and the function consumer in `cutover-inngest-workflow.test.sh` (Arm F, fixed in S6). Each surfaced as a red run first, and no check named the class beforehand.

This PR (S7b) delivers five things, each owned by one Guard Contract entry or one phase:

1. J0, the measurement, as the first phase and the first commit: a committed, re-runnable derivation (`j0-derive.py` in the spec dir) that counts the join population, a reach probe that separates suites which RUN a pipe from suites that only READ the file as text, and a hand reading of each running stub. No stub is edited before these numbers are recorded in `evidence.md`.
2. A `PRODUCER_JOIN` table in the existing guard (`.claude/hooks/grep-q-pipe-guard.test.sh`), one row per derived (test file, verb) pair, with set identity against the tree (Guard 1).
3. The stub edits the J0 shows are needed: in each suite that runs a pipe with a stub that does not read stdin, the stub drains as its FIRST statement, exactly when argv carries the consuming flag, and keeps the bytes for a wire assert (Guard 2, a positional pin).
4. A dynamic control inside the guard: a non-reading stub whose exit is awaited by a sentinel hand-off must reproduce the failure, and every accepted drain spelling must pass (Guard 3).
5. The guard header rewritten to the S7b state, with the follow-on slices listed and not planned here.

## Research Insights

**Sources read.** The S7a plan and spec dir (`2026-10-11-chore-grep-q-wave-b-s7-codemod-guard-cleanup-plan.md`, `specs/feat-one-shot-grep-q-wave-b-s7-codemod-guard-cleanup/evidence.md` and `decision-challenges.md`), the series plan's "Producer-side join (S7 design)" section (`2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md`), the tracker comments for S5, S6 and S7a, the guard header and its end (`.claude/hooks/grep-q-pipe-guard.test.sh`, 1160 lines at `31ada28352`), and two learnings: `test-failures/2026-09-30-stub-drain-fidelity-and-endpoint-keyed-sweeps.md` (drain on the flag, not the verb; capture to a side file; wire assert with the `${KNOB:-default}` form; keep `[ ! -t 0 ]`) and `test-failures/2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md` (size is not a bound; the producer-side form; a race row pinned only by timing is a timing-only test). The model stubs are `luks-monitor.test.sh` (the `cryptsetup` stub, the `$CALLS.escrow-stdin` wire assert) and `workspaces-luks-verify-workflow.test.sh` (the `FIXTURE_NO_DRAIN` control, a sentinel hand-off, `PROBE_STDIN`).

**Premise validation (Phase 0.6).** Checked against `origin/main` at `31ada28352`:

- #9217, #7376, #6601, #7797, #9482 are open; #9971, #9950, #9956, #9638 and #9639 are open; PR #9745 is open. Nothing cited is closed or merged, so no premise is stale.
- The brief's figure "about 29 non-test sites in 20 files" is reproduced by the hand-written verb registry measure under the series' first recipe (substring owner match, no sourced-file hop): 32 sites in 20 files, the first run of `j0-derive.py` at this head. With the corrected owner rule and the one-hop sourced-stub arm the same funnel reads 39 sites in 22 files (Funnel B below). It is NOT the population of the property: the verb-free join finds 60 (test file, verb) pairs in 48 test files. The brief's figure comes from the identifier set, which is the class the Guard Contract gate exists to catch. This is a User-Challenge (decision-challenges.md item 1).
- No ADR in `knowledge-base/engineering/architecture/decisions/` decides a stub-drain mechanism (a grep for `stub.{0,20}drain|producer-side|EPIPE` finds ADR-034, ADR-192, ADR-211, none of which is about test stubs). No shared stub-drain helper exists in the repo (a grep for `drain_stdin|stub_drain|drain-stdin|stdin_drain` returns nothing).
- #9956 (the `egress_gateway` deletion without `removed {}` claims, red on main) is open and unfixed, and S6's tracker comment records `cloud-init-inngest-bootstrap.test.sh` red on main under #9956. That suite is one of the owners below; Phase 0 treats it as BLOCKED, not edited (see Sharp Edges).
- PR #9745's `cursor-matcher-parity.test.sh` line 102 still carries a consumer-side pipe; it is a different PR's file and is not touched.

**J0 at plan time** (run at head `372f507a83`, a tree whose only difference from `31ada28352` is the branch-init commit; command and full output are in the spec dir: `j0-derive.py` and `j0-plan-time-output.txt`; the command is `ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7b-producer-join/j0-derive.py`):

| Funnel | Stage | Count |
| --- | --- | --- |
| A, verb-free (the property) | text-pipe lines over non-test files | 2881 lines in 483 files |
| A | pairs (test file, verb) under `pipefail` with observed status | 60 pairs, 58 non-test files behind them, 48 test files |
| A | by verb | jq 10, cryptsetup 10, curl 9, doppler 7, docker 4, nft 4, timeout 3, gh 3, grep 2, rc 2, and one each of bc_hmac_sha256_hex, tr, sha256sum, hmac_sha1_b64, openssl, parse_directive |
| B, hand-written registry (the series' earlier recipe) | F0 lines with a registry verb | 61 lines in 35 files |
| B | F1 `pipefail` in file scope; F2 status observed | 59 in 33 files; 59 in 33 files |
| B | F3 an owner suite stubs the verb | 39 sites in 22 files (32 in 20 under the first recipe, the brief's figure) |
| B | registry pairs | 38 pairs in 34 test files |

The registry (`gh curl doppler docker terraform nft ssh sudo systemctl logger cryptsetup openssl tar aws mount umount`) is the hand-written identifier set; the parent plan's own earlier registry (ten verbs) missed `cryptsetup` (23 lines) and `openssl`. Twelve of the 60 pairs are verbs the registry does not name (`jq`, `timeout`, `grep`, `tr`, `sha256sum`, `rc` and four shell functions): `jq` and `grep` stubs exist and a stub of either that exits without reading is the same hazard. Funnel A counts a test file as an owner when it holds the non-test file's basename as a whole token on a non-comment line, so it OVER-includes suites that only read the file as text (for example `cron-egress-firewall.test.sh` names `apply-web-platform-infra.yml` to pin its text and never runs it). The reach probe in Phase 0 is what separates running from reading; the textual funnel cannot.

**Recall, measured by the correctness seat of the plan review and re-checked.** A join over stubs defined in the suite file alone misses the cases that motivated it: `luks-monitor.test.sh` defines no `cryptsetup` stub (its stub arm lives in the sourced `workspaces-luks-harness.sh`), and `workspaces-luks-verify-workflow.test.sh` writes its `ssh` stand-in as `bin/sshstub`, reached through `WEB_HOST_SSH`, so the production site's verb word is a variable. The derivation therefore reads stubs one hop into the files a suite sources (matched by basename), which makes the `luks-monitor.test.sh` and `cryptsetup` pair derive; the variable-named verb stays a stated miss, listed as an `exempt` row. The J0 script runs in about 1.4 s wall (tracked-file reads plus token sets), which is the measured budget the guard's bash and awk version must stay near.

A crude textual look at the 69 stub definitions behind an earlier, looser join of the registry verbs (41 groups) finds about 30 with no stdin reader, 31 with one, and 8 defined through a helper the pattern cannot read. That is an upper bound on edits, not a count: the reader detector also matches `cat >> "$CALLS"` style lines that are not stdin readers, and a TEXT-only owner needs no edit at all. The real number is a Phase 0 output.

**Precedent diff (deepen-plan 4.4), the drain idiom.** Three precedents exist and the plan's form is a superset of each: #9261's `luks-monitor.test.sh` stub drains with `{ [ ! -t 0 ] && cat >"$CALLS.escrow-stdin"; }` keyed on the `--key-file -` argv; the luks-verify suite's `ssh` stub drains with `cat > "${PROBE_STDIN:-/dev/null}"` after creating a sentinel, behind a `FIXTURE_NO_DRAIN` control knob; `ci-deploy.test.sh`'s one-line `curl() { ...; timeout 2 cat >> "$FO_STDIN" || true; ... }` bounds the read. The plan's snippet adds what each lacks: the flag key (the third has none), the bounded read (the first two have none), and an unset-capture fallback. The novel part is the join itself; no precedent guard joins non-test pipes to owner stubs (a grep of the guard for the word `join` finds only the header sentence that names the missing join, and no hook suite carries `PRODUCER_JOIN`), so the Guard Contract is the only precedent the guard has.

**Property List (Phase 0.6b).**

- P1. A new non-test pipe from a text producer into a command a test suite stubs cannot appear without a recorded decision (a table row), whatever the command is called.
- P2. In every suite that RUNS such a pipe with the command stubbed, the stub reads stdin before it can exit, when argv carries the consuming flag.
- P3. A stub's drain cannot be removed, commented out, unkeyed from its flag or moved below another statement of the stub (so after an `exit` arm could run) without the guard going red.
- P4. The failure the property prevents is reproduced in the guard's own run, and the checker can tell a stub that reads from a stub that does not.

**Cut List (Phase 0.6b),** each cut names the property it would have bought and what covers it:

- A shared stub-drain helper sourced by every owning stub: cut. It edits the same stubs, adds a sourced path to heredoc stubs that run as `#!/bin/sh` files, drains on the verb rather than the flag (the 2026-09-30 learning says that masks a mutant that drops the flag), and its own suite would need a registration in `scripts/test-all.sh`, which this slice may not edit. The inline flag-keyed form is two to four lines and is already the idiom of #9261 and #9525.
- Converting the non-test pipes themselves to here-strings or files: cut. It edits user-data and bootstrap scripts (a host replace, per the 2026-10-06 learning on which files feed user data), and a secret in a here-string is a temp file on a shell older than bash 5.1. The non-test verbs read stdin to EOF; the defect is stub fidelity, not the sites.
- Running the owner suites from inside the guard, and a dynamic run of each real heredoc stub under a late writer (plan-review suggestion): cut for this slice. CI already runs the suites; the guard stays a text derivation plus a sub-second control. Recorded as decision-challenges item 6.
- The pre-registered Phase 0.5 cut gate (more than 20 suites, or more than 10 infra suites): cut at plan review. The thresholds had no cited source; the commit order (non-infra owners first, infra owners second) makes a split at ship time free, and the measured edit count is recorded in `evidence.md`.
- A region extractor with an end-of-definition locator and a first-`exit` locator: cut at plan review in favour of a positional pin (Guard 2): the Phase 2 edit puts the drain first, so the guard checks that the drain is the first statement after the definition's opener and never has to find the definition's end.
- A hand-written verb list as the population: cut (this is the User-Challenge). The population is derived from both sides; a verb needs no registration to be counted.
- A new sibling suite for the join: cut. A sibling in `.claude/hooks/` would be registered by the glob for free, but a new registered suite needs a declared affected-edge entry in `scripts/lib/test-affected-paths.sh`, which is fenced. The existing guard already has its declared entry.
- A permanent guard at all, versus fixing the running stubs and recording a learning (plan-review seat): not cut; the brief asks for the join with its own Guard Contract. Recorded as decision-challenges item 5, with the minimal alternative named.
- The Arm F remainder (103 lines in 24 files that pipe into a function defined in the same file): not in this slice; it needs a per-function early-return measure and is reported on the tracker, as the series plan says.

**Value-proposition measurement (Phase 0.6c).** The claim is flake prevention, not a cost saving, so there is no saving to quantify. The measured base rate: `git log origin/main --since=2026-07-01 -i -E --grep='stub.{0,30}(drain|read)|EPIPE|producer.side'` returns 33 commits, of which the producer-side stub instances are #9261 (cryptsetup, 2026-09-30), #9525 (ssh stub, 2026-10-05) and S6's `cutover-inngest-workflow` fix (2026-10-10): three in eleven days, each found only after a red run. What the slice buys is the end of that discovery path; whether it also reduces flake counts is not measurable until the next quarter's CI history, and is not claimed.

## Research Reconciliation: Spec vs. Codebase

| Claim | Reality | Plan response |
| --- | --- | --- |
| Brief: "about 29 non-test sites in 20 files" | The registry funnel measures 32 sites in 20 files under the first recipe and 39 in 22 under the corrected one (reproducible: `j0-derive.py`); the verb-free join measures 60 pairs in 48 test files | Report both. The guard derives verb-free; edits follow what RUNS (reach probe), so the edit count is likely close to the brief's. User-Challenge recorded |
| Series plan: a join over each suite's own stub definitions | Two of the three producer-side instances are invisible to it: the `cryptsetup` stub lives in a sourced harness file, and the `ssh` stand-in is a variable-named script | One-hop sourced-stub arm in the derivation; the variable-named verb is a stated miss with its own `exempt` row; Guard 1 carries recall rows naming the instances (Phase 3) |
| Series plan: owners are "the suites that name the production file on a code line and define a stub for the verb" | Naming is not running: `cron-egress-firewall.test.sh` names `apply-web-platform-infra.yml` only to pin text, and its `docker` stub serves other code | Phase 0 reach probe classifies each pair EXEC, TEXT or UNVERIFIED; only EXEC pairs get a drain; TEXT rows carry the probe evidence as their reason |
| Series plan: verbs are "gh curl doppler docker terraform nft ssh sudo systemctl logger" | `cryptsetup` (23 lines in 9 files) and `openssl` are absent from that list; `jq`, `grep`, `timeout` stubs exist | Population derived from the stub side and the pipe side; no verb list is part of the guard |
| Series plan: table rows are (site, verb, consuming flag, owners) | A site-keyed row would need a second row for every owner; `ci-deploy.test.sh` alone holds five `curl` stub definitions behind one non-test file | Rows are (test file, verb), with a pinned count of stub definitions; the flag is part of the row |
| S7a: the guard affected-edge entry is "already derived" | `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh` is a hand-declared list of the suites the guard names | The join names about 30 more suites; the declaration cannot be extended here (fenced file). Stated as a limit: `--affected` will not select the guard when only an owner suite changes; CI's full battery does. Follow-on, not a hole this slice can close |
| Brief: cite the spec dir's evidence file, and keep a barred vocabulary out of the PR body | This plan's path carries none of the barred tokens, but the PR body is its own surface | PR body cites `evidence.md` in the spec dir only (AC-11) |

## Implementation Phases

Phase 0 (J0, read-only, before any edit). Everything here is recorded in `evidence.md` and committed first.

- 0.1 Re-run the derivation in a clean checkout (`git status --porcelain` empty): `ulimit -v 6000000; python3 -I knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7b-producer-join/j0-derive.py`. Compare with `j0-plan-time-output.txt`; explain any difference (main moves). The derivation reads tracked files only (`git ls-files`), so an untracked scratch file cannot change the set; the sweep elsewhere in the guard reads the working tree, which is a different rule.
- 0.2 Classify each Funnel A pair: a stdin-reading command (an external CLI or a function/script that reads stdin) or not a command in that sense (`rc`, a `tr` pipeline inside a function body, a shell function name, a string such as `echo "a|b"`). The guard still derives these pairs; they become `exempt` rows. Every `exempt` reason is one word from a closed vocabulary, optionally followed by detail: `not-a-command`, `text-only`, `unverified`, `blocked-#N`, `helper-built-stub`, `variable-named-verb`. The vocabulary is what lets a later reader grep and audit the reasons.
- 0.3 Reach probe (scratch checkout under a sandbox allocated by `scripts/soleur-sandbox.sh new`, never committed). For each pair, insert one marker line at the top of each stub definition for the verb (`[ -p /dev/stdin ] && printf '%s\n' "$*" >> "$REACH_LOG"` or the dash-safe equivalent), run the owner suite once under `timeout 300` and `ulimit -v 6000000`, and read the log. EXEC = a piped call reached the stub, with its argv recorded; TEXT = the suite ran green and no piped call arrived; UNVERIFIED = a timeout, a suite red at its base commit, or a stub built by a helper the marker cannot enter. A suite that is red at `origin/main` before any edit (#9956) is listed BLOCKED, never edited.
- 0.4 Read each EXEC stub by hand (the textual reader detector over-matches) and record: drains in every arm before its first `exit`/`return`; drains only in some arms; never drains. The consuming flag per verb is read from the production site (`--password-stdin`, `--key-file -` and `--key-file=-`, `-K -`, `--config -`, `-H @-`, `--body-file -`, `-f -`; the secret-write verb of `doppler` when its value is piped; none for a command that reads stdin by default, recorded as `*`).
- 0.5 Record the count of suites that need an edit (EXEC and not draining in every arm) and how many of them are under `apps/web-platform/infra/`. There is no gate on the number: Phase 2 orders its commits non-infra first and infra second, so a cut at ship time is free if the count is large, and the call is recorded in `decision-challenges.md` when it is made.

Phase 1 (red first, `cq-write-failing-tests-before`). In the guard, before any stub edit, add the derivation, the empty-table comparison and the control rows. Run it once in a clean checkout under `ulimit -v 6000000`. Record that every derived pair reads FAIL as `unlisted pair` (count equal to Funnel A after Phase 0.2) and that each control row reads PASS or FAIL for its named reason. The rows are the tests; the edits turn them green.

Phase 2 (stub edits, by hand; the three kinds of edit are the only ones). For each suite Phase 0.4 marked for edit, in two commits ordered by blast radius: first the suites outside `apps/web-platform/infra/` (`.github/scripts/test`, `plugins/soleur/test`, `scripts`, `tests`), then the infra suites. In each stub definition: (a) as its FIRST statement, drain exactly when argv carries the consuming flag, keeping the not-a-terminal test, bounding the read, and capturing to a side file only when the suite names one (an unset capture variable must never turn into a redirect to a path under `/dev`):

```sh
case " $* " in *" --key-file - "*|*" --key-file=- "*) [ -t 0 ] || { if [ -n "${CALLS:-}" ]; then timeout 2 cat >"$CALLS.stdin"; else timeout 2 cat >/dev/null; fi; } ;; esac
```

The `timeout 2 cat` form is the canonical reader (the repo's existing stubs, for example the `curl` stub in `ci-deploy.test.sh`, use it): a bare `cat` blocks on an inherited open stdin, which the luks-verify suite documents. Stubs that run as `#!/bin/sh` use only `case`, `[ ]` and `cat`.

(b) one wire assert per drained pair that compares the captured bytes to the value the production site piped, with the `${KNOB:-default}` form so an exported-empty knob cannot compare `"" = ""`; (c) a `NO_DRAIN` knob only where the suite already has a race row that needs one (the luks suites do); no other suite gains a control. A suite whose existing wire assert already proves arrival needs only (a). No production file, workflow, `.tf` file or fenced file is edited.

Phase 3 (the guard). Add `PRODUCER_JOIN` (rows, below) and one derivation function used by three checks: the missing-row check, the stale-row check and the per-row stub check. The derivation is bash, `git ls-files`, `git grep` and `awk` (the guard has no python3 dependency today and gains none); owners are matched by whole token from a token set built once per test file, never by a per-pair substring scan, to stay near the measured 1.4 s of the Python J0. The bash derivation is AUTHORITATIVE; `j0-derive.py` is a point-in-time measurement artifact, compared with it once (AC-4), and the guard header says so. Row format, in the style of `SWEEP_DEFERRALS`:

```text
<test file> | <verb> | drains | <defs> | <flag token or *>
<test file> | <verb> | exempt | <closed-vocabulary reason> <detail>
```

Guard 2's rule is positional: for each of a `drains` row's `<defs>` definitions, the first non-comment statement after the definition's opener (a function's `{`, a heredoc's opening line, a one-line write) is the flag-keyed drain naming the row's token (or an unconditional reader when the token is `*`). The guard never has to find where a definition ends.

Recall rows (Guard 1): the guard names the known instances: `luks-monitor.test.sh` with `cryptsetup` must derive (through the sourced harness); `workspaces-luks-verify-workflow.test.sh` with `ssh` is the stated miss and must be an `exempt variable-named-verb` row; each is asserted by name so a narrowing of the derivation that loses a known instance is red.

An unlisted pair prints a ready-to-paste candidate row (suite, verb, the definition count and flag token the derivation found) and a one-line pointer to the drain form in the Phase 2 snippet, so the author of a new suite gets the row from the guard itself.

Findings of the repo (an unlisted pair, a stale row, a stub that does not drain) print `FAIL:` lines and set `FAIL=1` before the verdict gate; faults of the instrument (zero pairs derived, a `drains` row that finds zero definitions, a failed listing, rc above 1) print `UNRESOLVED:` and exit 3; probe-of-the-probe checks join `sweep_probe_fail` and are counted. The join prints its own `PASS: grep-q-producer-join` line on success and one `JOINED:` line per row, so the guard's existing `PASS: grep-q-sweep-probe-pass` line never claims a join result. Recompute `SWEEP_PROBE_CHECKS` from the file with the recipe in the guard header; do not subtract by hand. Place the new block before the "Return wiring" block, so its pins still count only what they pinned and the join is read by the same verdict gate. The wiring pins read the whole file's non-comment lines, so every fixture in the new block is indented or built with `printf`: no column-0 `FAIL=0`, `exit "$FAIL"`, `sweep_fold` or `|| sweep_probe_fail+=(` text inside a fixture or a message, and the recipe is re-run after drafting.

Phase 4 (the dynamic control, Guard 3). Inside the guard, one function runs a writer into a stub, and the writer does not write until the stub has exited: the stub's wrapper creates a sentinel file as it exits and the writer polls for it (a bounded poll, the hand-off the luks-verify suite already uses), so the late write is deterministic and no wall-clock delay decides the result. The pipeline is always run under bash with `pipefail` (dash has no such option), once with SIGPIPE ignored (`( trap '' PIPE; ... )`, the CI disposition) and once with the default. The stub's interpreter is the variable: the non-reading control stub and each accepted drain spelling run as `#!/bin/sh` and as bash stubs, and a spelling is tagged `posix` or `bash` and runs only where it parses (`read -d` is not POSIX and is not an accepted `sh` spelling). Expected: the non-reading stub fails the pipeline in both dispositions; each accepted spelling succeeds. One array of spellings, built from the forms the tree uses after Phase 2 plus the prescribed one, drives both this row and the detector in Guard 2, and a second array of NON-reading spellings (`cat /dev/null`, `true`) must fail the control, so the control can see a vacuous stub. No `kill`, no `rm` of anything outside a per-run `mktemp -d`.

Phase 5 (wording). Rewrite the header paragraph that says the producer side is "invisible to any line search" to say what is now pinned and what is not (the stated limits below), keep the series open (Items D, E, F, G, I, H and the Arm F remainder are listed, not planned), and do not write that the series is finished.

Phase 6 (evidence, battery, ship). Run the mutation rows M1 to M21 and the harness rows H1 to H6 below, one mutant at a time, under `ulimit -v 6000000`, in a scratch clone; a row whose mutation executes an owner suite runs through `bash scripts/soleur-sandbox.sh run-isolated "$SBX" -- <cmd>` (the owner suites remove files and some start background processes; the guard's own mutants only read). Pair run: each edited suite at its base commit and at head, same machine, same load, results compared. Then the lints in AC-9, `bash scripts/test-affected-kb-consumers.test.sh` once (about 95 s; the guard names about 30 more test paths literally, and a ratchet-lane SKIP does not mean CI will skip), `decision-challenges.md`, a learning if a non-obvious finding occurs, the PR body per AC-11, `soleur:ship`, then AC-12.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh` (derivation, `PRODUCER_JOIN`, three checks, the dynamic control, `SWEEP_PROBE_CHECKS`, header wording)
- Owner suites, only those Phase 0.4 marks for edit. Candidates are the test files in `j0-plan-time-output.txt`'s PAIRS list: 34 in registry pairs plus 14 whose pairs name a verb outside the registry (`jq`, `timeout`, `grep`, `tr`, `sha256sum`, `rc` and four shell functions), 48 in all. The non-registry 14 join the edit list only if the reach probe shows them EXEC and not draining; the final list is recorded in `evidence.md`. Registry candidates: `apps/web-platform/infra/{ci-deploy,cloud-init-web-zot-seed,cron-egress-firewall,cron-egress-ghcr-probe,cron-egress-nftables,cron-egress-self-heal,cutover-inngest-workflow,fresh-boot-ready,git-data-bootstrap-store-verify,git-data-luks-reopen,git-data-root-key,inngest-boot-emitter,inngest,luks-monitor,registry-luks-escrow,resend-inbound-bootstrap,web-ghcr-deny,workspaces-boot-unlock,workspaces-luks-freeze,workspaces-luks-rollback-refusal,workspaces-luks-staging,zot-disk-heartbeat-redaction}.test.sh`, `plugins/soleur/test/{flag-detach-shared,flag-org-scoping-pr2,operator-ack-guard,operator-digest-provision,operator-script,operator-stage-approval-hook}.test.sh`, `scripts/{rotate-supabase-db-credential,sweep-followthroughs,watch-registration-narrowing-9564,web2-rebirth-recovery-check}.test.sh`, `scripts/followthroughs/zot-*-6122.test.sh` (one file). Not edited even if EXEC: `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` while #9956 leaves it red at base. A stub that lives in a sourced helper (`apps/web-platform/infra/workspaces-luks-harness.sh`) is edited in the helper, which then joins the list.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-pipe-guard-s7b-producer-join/{tasks.md,evidence.md,decision-challenges.md}` (`j0-derive.py` and `j0-plan-time-output.txt` already exist there)
- `knowledge-base/project/learnings/test-failures/2026-10-11-<slug>.md` only if a non-obvious finding occurs

## Files to Delete

None.

Not touched, on purpose: `plugins/soleur/skills/work/SKILL.md`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` (see the reconciliation row on the declared affected-edge list), `scripts/lib/scratch-root.sh`, `plugins/soleur/test/skill-body-budget.json`, `plugins/soleur/skills/plan/SKILL.md`, `AGENTS*.md`, every file under `.github/workflows/`, every non-test script and cloud-init file that carries a pipe (the sites are correct; the stubs are not), `cursor-matcher-parity.test.sh` (PR #9745), and the main checkout's `.mcp.json` and untracked `apps/web-platform/1000:` and `500` files.

## Open Code-Review Overlap

None. A query of the 88 open `code-review` issues for the guard path and the candidate suite basenames returned no body that names any of them.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; a regression is a CI false-red (a suite that now fails on a drain it should not need) or a false-green on a test-hygiene gate, seen by contributors as a red `test` or `infra-validation` check.
**If this leaks, the user's data is exposed via:** no vector; the diff edits test stubs and one drift guard, handles no credential or user data, and the drained bytes are written to a per-run scratch file the suite already owns.
**Brand-survival threshold:** none
threshold: none, reason: the diff edits repo-internal test stubs and one drift guard; no runtime, data or credential surface is touched, and no non-test script is edited.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Guard Contract

The deliverable is a guard (the join) and a control over it. One entry per property; the matrix is written from the design before the guard, and each entry carries at least one row against the guard's own dispatch, one second-member row and, where the property is about order, a REORDER row. Review round 1 cut the region extractor (Guard 2 is now a positional pin) and the wall-clock delay (Guard 3 uses a sentinel hand-off); the rows below are the post-review set.

### Guard 1 — the join population is closed

**Property.** Every (test file, verb) pair where the test file names a non-test file that pipes text into that verb under `pipefail` with its status observed, and the test file (or a file it sources, one hop) stubs that verb, has exactly one row, and every row's pair still derives; an unlisted pair or a stale row turns the guard red whatever the verb is called, and the known instances are asserted by name.

**Assembly.** The derivation `join_pairs` and everything it quantifies over: the non-test file set (tracked `.sh .bash .yml .yaml`, minus test-shaped paths, fixtures, `knowledge-base/`), the test file set, the text-pipe pattern (`printf|echo|cat ... | [sudo [-flags]] WORD`, comment lines dropped), the `pipefail` rule (the file's non-comment text, or `shell: bash` in a workflow), the observed rule (a trailing `|| true` or `|| :` drops the site), the owner rule (the non-test file's basename as a whole token on a non-comment line of the test file), and the four stub arms (a function definition, a file written to `.../WORD`, a stub-helper call naming WORD, and any of those three in a file the suite sources, matched by basename). `PRODUCER_JOIN` is the other half. The chokepoint is `join_pairs`: the missing-row check, the stale-row check, the per-row stub check, the recall rows and the control all read its one output, so a narrowed arm shows up as a stale row in each. There is more than one injection path into the pair set (three producer verbs, four stub arms), so each arm has its own mutation row. The set identity is rows against derived pairs, not a count; the recall rows name the instances that motivated the guard so a narrowing that loses one is red even when rows and pairs shrink together.

**Mutation matrix.** Each row is run one at a time against a scratch copy of the edited guard under `ulimit -v 6000000`; expected result is RED on the named text. Mutations that add a file `git add` it, because the derivation reads tracked files only.

| # | Mutation | Expected RED |
| --- | --- | --- |
| M1 | Add a non-test script that pipes `printf` into `gh`, and a new suite that stubs `gh` and names it | `unlisted pair` naming the suite and `gh`, with a candidate row |
| M2 | Second member: add a second suite that stubs an already-listed verb and names an already-listed non-test file | `unlisted pair` naming the second suite (a check that stopped at the first owner would stay green) |
| M3 | Delete one row and leave its pair | `unlisted pair` |
| M4 | Keep a row whose stub was renamed in its suite | `stale join row` |
| M5 | Own dispatch: make the listing return nothing (a pathspec that matches no file) | `UNRESOLVED: derived zero pairs`, exit 3, never a pass |
| M6 | Narrow the stub detector: drop the stub-helper-call arm | `stale join row` for the 4 pairs that derive only through a helper call (measured by the review) |
| M7 | Narrow the stub detector: drop the function-definition arm | `stale join row` for the 3 pairs that derive only through a function definition (measured by the review) |
| M8 | Narrow the stub detector: drop the sourced-file hop | `stale join row` for the pairs that derive only through a sourced file, and the `luks-monitor.test.sh` and `cryptsetup` recall row |
| M9 | Narrow the text-pipe pattern: drop `echo` producers | `stale join row` for the pairs that derive only through `echo` (the review measured that all current pairs derive through `printf` or `echo`, none through `cat`, so `cat` is not the row) |
| M10 | Edit the one site behind a single-site pair so its status is dropped (`|| true`; name the site in `evidence.md`) | `stale join row` (proves the observed rule runs) |

**Harness rows.** H1 (suite edit that MUST read RED): delete the join check's `|| sweep_probe_fail+=` tail; `probe-count` reads RED. H2 (must-PASS, not the canonical): a new suite that names a listed non-test file only in a comment derives no pair and stays green; a row with extra whitespace around the separators parses; a suite that names `fci.yml` does not become an owner of `ci.yml`.

**Anchor.** The table and the guard sit in one file, and each row's stub sits in another, so one diff can edit a row and its stub together; that proves consistency, not integrity. What sits outside the commit: the evidence file's recorded J0 table (the reach probe per pair), Guard 3's dynamic control (which reads no row), the closed vocabulary that makes `exempt` reasons greppable, and the reviewer reading the two-place edit. Stated, not claimed as integrity.

### Guard 2 — a running stub reads stdin as its first act

**Property.** For every `drains` row, each of the row's N stub definitions in the test file has, as its first non-comment statement after the opener, a drain keyed on the row's flag token (or an unconditional reader when the token is `*`); a definition removed, commented out, unkeyed, moved below another statement or added beyond N turns the guard red.

**Assembly.** The three definition kinds the opener finder recognises (a function opener, a heredoc opening line, a one-line write), the pinned definition count N per row, the first-statement reader, comment stripping, and the accepted-spelling array shared with Guard 3. The chokepoint is `stub_openers`: the count check, the flag check and the first-statement check all consume its output. A positional pin is a deliberate narrowing of "reads before it can exit": it needs no end-of-definition search and no exit locator, at the price that a stub that drains second is red even when it still reads before exiting; the Phase 2 snippet makes first the only supported place. A stub built by a helper whose body the finder cannot read is not checked here; such a pair must be an `exempt helper-built-stub` row (stated limit, with the measured count in `evidence.md`).

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| M11 | Delete the drain statement from one compliant stub | `no stdin reader as the first statement` naming suite, verb and the definition's opening line |
| M12 | REORDER: move the drain below the stub's first other statement (the stub's first `exit` arm) in the same definition (a delete-only battery cannot see this) | `drain is not the first statement` |
| M13 | Second member: add a second definition of the verb with no drain after a compliant first | `definitions 2, pinned 1` |
| M14 | Leave the drain only in a comment | `no stdin reader as the first statement` |
| M15 | Remove the flag token and keep an unconditional `cat` (a verb-gated drain, which masks a mutant that drops the flag) | `flag token missing` |
| M16 | Own dispatch: rename the definition's opening line so the finder sees zero | `UNRESOLVED: a drains row found 0 definitions`, exit 3, never a pass |
| M17 | An `exempt` row with an empty reason, or a reason outside the closed vocabulary | `exempt row without a vocabulary reason` |

**Harness rows.** H3 (suite edit): make the opener finder accept only a function opener; the rows whose stubs are heredocs read RED. H4 (must-PASS, not the canonical): each accepted spelling in the array (the prescribed `case` form, the `timeout 2 cat >>` form of `ci-deploy.test.sh`, the `[ ! -t 0 ] && cat >` form of #9261) passes as a first statement, and the flag test spelled with `[[ "$*" == *--key-file* ]]` instead of `case` passes.

**Anchor.** The flag token in a row and the flag in the stub are edited by one diff. The dynamic control (Guard 3) is the reading that does not trust either, and the evidence file's reach table records which pairs actually ran. Stated.

### Guard 3 — the hazard is real and the checker can see a vacuous stub

**Property.** Measured in the guard's own run: a stub that exits without reading, with the writer held until the stub has exited, makes a `pipefail` pipeline fail with SIGPIPE ignored and with the default disposition; every accepted drain spelling makes the same pipeline succeed under the interpreter it is tagged for; and every non-reading spelling fails it.

**Assembly.** The control function, the sentinel hand-off (the stub's wrapper creates a file as it exits; the writer polls for it with a bound), the two SIGPIPE dispositions, the stub interpreters (`sh` and bash), the non-reading control stub, and the two spelling arrays (accepted, with a shell tag each; non-reading). The chokepoint is the one function that runs the pipeline; every row of the control calls it. This is the in-window observation Guard 2's positional pin cannot make: it observes the pipeline while the writer is held, not after the function returned.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| M18 | Make the control stub drain | `control did not reproduce the failure` (the guard would otherwise certify a hazard it cannot produce) |
| M19 | Remove the writer's wait on the sentinel | the same text, deterministically (the write races the stub's start) |
| M20 | Add a non-reading spelling (`cat /dev/null`) to the accepted array | that spelling's row fails the dynamic run |
| M21 | Own dispatch: empty the accepted array | `zero spellings ran`, never a pass |

**Harness rows.** H5 (suite edit): delete the control's `|| sweep_probe_fail+=` tail; `probe-count` reads RED. H6 (must-PASS, not the canonical): a spelling that differs from the canonical in a way the contract permits (`dd of=/dev/null 2>/dev/null` under bash) passes the dynamic run, and a bash-tagged spelling is not run under `sh`.

**Anchor.** The control stores no value, so nothing outside the commit needs to move for a weakening to pass: weakening it means editing the control, which M18 to M21 drive RED. The hand-off is a sentinel with a bounded poll, so no wall-clock constant decides the result; the poll bound is the only time-based value and a timeout reads as RED, never as a pass.

## Observability

```yaml
liveness_signal:
  what: the grep-q-pipe-guard suite runs in the CI test group on every PR and merge_group run and prints PASS lines, one DEFERRED line per sweep row and one JOINED line per join row
  cadence: per PR and per merge_group run; run directly before each push
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: scripts/test-all.sh SUITE_GLOBS entry '.claude/hooks/*.test.sh' (registration), .claude/hooks/grep-q-pipe-guard.test.sh (the passes)
error_reporting:
  destination: CI job log of the test check (repo-hygiene guard, no Sentry surface)
  fail_loud: a FAIL line naming the unlisted pair, the stale row, or the stub and the reason (no reader as the first statement, drain not first, flag token missing, definition count), exit 1; an empty derivation, a drains row that finds no definition, a failed listing or a control that did not reproduce prints UNRESOLVED or FAIL and exits non-zero
failure_modes:
  - mode: a new non-test pipe plus a suite that stubs its verb lands without a row
    detection: the derived pair set differs from PRODUCER_JOIN, so the guard prints "unlisted pair" naming the suite and the verb
    alert_route: required test check red on the PR
  - mode: a running stub loses its drain, or the drain is moved below the stub's first statement
    detection: the per-row stub check prints "no stdin reader as the first statement" or "drain is not the first statement"; the dynamic control is unaffected, so a reordered stub is caught by the positional pin and a non-reading spelling by the control
    alert_route: required test check red on the PR
  - mode: the derivation stops seeing a stub spelling or a pipe shape
    detection: rows whose pairs derived only through that arm print "stale join row"; a derivation of zero pairs prints UNRESOLVED and exits 3
    alert_route: required test check red on the PR
  - mode: an edited owner suite changes behaviour
    detection: the suite's own result in infra-validation deploy-script-tests or the test check on the PR head, and the recorded pair run; infra-validation is not a required check, so AC-6 reads it
    alert_route: the check on the PR (visible, not always blocking) and the review
logs:
  where: CI job logs of the test and infra-validation checks; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: grep-q-sweep-probe-pass
```

Detection note for preflight Check 10: one deterministic file set, no build or network. The guard took about 2.4 to 3.6 s in sandbox copies after S7a (evidence.md of S7a); the join adds one `git ls-files` listing, one token pass per test file (the Python J0 doing the same reads and token sets takes about 1.4 s wall at plan time) and the control rows, whose sentinel hand-off adds no fixed delay. AC-10 records after the edit, plain and in a Check 10-shaped read-only `bwrap`, with `uptime` beside each figure, because the margin to the 15 s cap is what a contended host erodes.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Keep the series plan's design as written: a site-keyed table over the registry verbs | The registry is the identifier set narrower than the property (Cut List); a site-keyed row multiplies by owner |
| Shared stub-drain helper | Cut List: same edits, a sourced dependency in `#!/bin/sh` stubs, drains on the verb, and an unregisterable suite |
| Convert the non-test pipes to here-strings | Cut List: edits user-data scripts and cloud-init, a host replace; the non-test verbs are correct |
| Sibling suite for the join | Cut List: a new registered suite needs a declared affected-edge entry in a fenced file |
| Dynamic whole-suite run per pair inside the guard | Cut List: CI already runs the suites; the guard would take minutes |
| Pin only a count of `drains` rows | A `>=` or equal count survives any substitution that keeps it; the row set is pinned by identity |

## Follow-on slices (listed, not planned here)

Items D, E, F, G, I and H of the series brief, the Wave A3 carriers where unblocked (the six carrier rows and the 23 later-wave sites are gated on a host replace), and the #9639 and #9638 triage are later slices tracked on #9217. Two are visible from this slice's evidence: Item F (a per-subtree count pin for the `# sigpipe-demo: intentional` marker; the baseline is 34 marked lines repo-wide, 9 in the guard file at S7a) and the Arm F remainder (103 lines in 24 files that pipe into a function defined in the same file). The declared affected-edge list for the guard (`scripts/lib/test-affected-paths.sh`) needs the join's owner suites added by a PR that may edit that file.

## Scope Check

Required on every plan (plan Phase 2.4; halted at deepen-plan 4.12). Asks are quoted from the run's brief (`[brief]`).

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Continue the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482)." [brief] | Overview, Phases 0 to 6 | mapped |
| 2 | "Next: S7b (producer-side join, Arm P): about 29 non-test sites in 20 files, J0 measure first; own plan and Guard Contract." [brief] | Phase 0, Guard Contract, Phases 2 to 4 | mapped |
| 3 | "J0 (measure the real site count first, with a reproducible command) must be a plan phase before any conversion." [brief] | Phase 0, `j0-derive.py`, AC-1 | mapped |
| 4 | "Start from the S7a evidence/spec dir under knowledge-base/project/specs/ ... to learn the Guard Contract shape, the J0 measure method and the Arm P definition; reuse them." [brief] | Research Insights, Guard Contract | mapped |
| 5 | "Then Items D, E, F, G, I, H, Wave A3 carriers only where unblocked, and the #9639/#9638 triage." [brief] | Follow-on slices | descoped — justification: the brief's scope line makes them later slices, to be listed in this plan and not planned in detail |
| 6 | "per PR an evidence comment on #9217, Ref not Closes, a plain NOT-fixed list, no [skip-deploy-fix-apply], nothing added to plugins/soleur/skills/work/SKILL.md." [brief] | AC-11, AC-12, NOT fixed here | mapped |
| 7 | "Keep the PR body free of ... vocabulary and of bullets starting with operator verbs. Cite the spec dir's evidence.md" [brief] | AC-11 | mapped |
| 8 | "Mutation batteries run under ulimit -v 6000000, one mutant at a time. Never run a mutant of a signal-sending or file-removing helper outside `scripts/soleur-sandbox.sh run-isolated`." [brief] | Phase 6, AC-7 | mapped |
| 9 | "Leave the main checkout's .mcp.json and the untracked apps/web-platform/1000: and 500 files alone." [brief] | Not touched list | mapped |
| 10 | "Do not edit work/SKILL.md, scripts/test-all.sh, scripts/lib/test-affected-paths.sh, scripts/lib/scratch-root.sh, skill-body-budget.json, plan/SKILL.md, any .github workflow or AGENTS*.md." [brief] | Not touched list, Cut List (sibling suite), Follow-on slices | mapped |
| 11 | "Before pushing a change that names test or script paths literally inside a suite, run `bash scripts/test-affected-kb-consumers.test.sh` once (about 95 s)" [brief] | Phase 6, AC-9 | mapped |
| 12 | "Open: #9971 (dissents ledger for S7a), #9950 (S6 dissents), #9956 (pre-existing main reds). Open PR #9745's cursor-matcher-parity test line 102 still has a pipe." [brief] | Premise validation, Phase 0.3 (BLOCKED rule), NOT fixed here | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
| --- | --- | --- |
| `j0-derive.py` and `j0-plan-time-output.txt` in the spec dir | "J0 (measure the real site count first, with a reproducible command)" (ask 3) | asked |
| Phase 0.3 reach probe | "J0 ... measure the real site count" (ask 3) | inferred — justification: the textual count over-includes suites that only read the file as text, so without a running/reading split the "real site count" the brief asks for cannot be stated |
| `.claude/hooks/grep-q-pipe-guard.test.sh` edits | "own plan and Guard Contract" (ask 2) | asked |
| `PRODUCER_JOIN` table and derivation | "S7b (producer-side join, Arm P)" (ask 2) | asked |
| Owner suite stub edits | "S7b (producer-side join, Arm P): about 29 non-test sites in 20 files" (ask 2) | asked |
| Dynamic control (Guard 3) | "own plan and Guard Contract" (ask 2) | inferred — justification: an order-based property needs a case that observes inside the window; without it the textual order check certifies a property it never exercised (the Guard Contract gate's REORDER rule) |
| Recall rows (Guard 1) and the one-hop sourced-stub arm | "own plan and Guard Contract" (ask 2) | inferred — justification: a join that cannot see the cases that motivated it (a stub in a sourced harness, a variable-named verb) certifies a population narrower than the property; the plan review measured both misses |
| `evidence.md`, `decision-challenges.md`, `tasks.md` | "a plain NOT-fixed list" and "an evidence comment on #9217" (ask 6) | inferred — justification: the tracker comment cites the spec dir's `evidence.md`, and the pipeline's decision-record contract needs `decision-challenges.md` |
| Follow-on list | "Then Items D, E, F, G, I, H ..." (ask 5) | asked |

### Split Assessment

- Subsystems touched: up to 6 — `.claude/hooks`, `apps/web-platform`, `plugins/soleur`, `scripts`, `tests`, `.github` (the test script under `.github/scripts/test`), plus the knowledge-base spec dir
- Planned files: 1 guard, up to 48 candidate owner suites, one per test file in a Funnel A pair (the EXEC and non-draining subset is a Phase 0 output), 3 spec artifacts | Estimated changed lines: about 250 added to the guard, about 5 to 12 per edited suite (up to about 500), about 600 in total
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root count and the candidate file count exceed the thresholds, but every edit is test-side and mechanical, and the number that decides (suites needing an edit) is not known until the reach probe runs; Phase 2's commit order (non-infra owners, then infra owners) makes a cut at the infra boundary free at ship time, and the call is recorded in `decision-challenges.md` if it is made

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1 `evidence.md` records, before any owner suite is edited (the first commit that touches `evidence.md` precedes the first commit that touches an owner suite, `git log --reverse` order): the re-run of `j0-derive.py` with its command and output, the reconciliation to the plan-time numbers, the Phase 0.2 classification, the reach table (EXEC, TEXT or UNVERIFIED per pair, with the argv seen), the drain-state table, and the Phase 0.5 count of suites needing an edit.
- [ ] AC-2 The red-first run (Phase 1) is recorded: with an empty table the guard reads FAIL `unlisted pair` once per derived pair, the count equal to Funnel A after Phase 0.2, and each control row's first result is recorded.
- [ ] AC-3 `bash .claude/hooks/grep-q-pipe-guard.test.sh`, run from inside the repo in a checkout with an empty `git status --porcelain` under `ulimit -v 6000000`, exits 0, still prints its twelve `DEFERRED:` lines, prints one `JOINED:` line per row (`... | grep -c '^JOINED:'` equals the derived pair count) and its own `PASS: grep-q-producer-join` line.
- [ ] AC-4 The guard's derived pair list, sorted, equals the pair list printed by `j0-derive.py` on the same tree (an empty `diff` of the two), run once and recorded.
- [ ] AC-5 Every pair classified EXEC is a `drains` row (its stubs verified by Guard 2) or an `exempt` row with a reason that cites the evidence; the count of EXEC pairs whose stub lacks a first-statement drain is zero; every TEXT, UNVERIFIED and BLOCKED pair is an `exempt` row whose reason is a word from the closed vocabulary (Phase 0.2).
- [ ] AC-6 Pair run: each edited suite is run at its base commit and at head on the same machine, results compared: pass, fail and assertion counts must be equal at base and head (a difference is a failure of this PR); wall time and `uptime` are recorded as context only and gate nothing; a suite red at base is listed and not edited; the infra-validation `deploy-script-tests` shard results on the PR head are read and any red that main also shows is recorded as pre-existing, not counted against this PR.
- [ ] AC-7 Mutation rows M1 to M21 and harness rows H1 to H6 are each graded against the committed guard, one at a time under `ulimit -v 6000000`, a row that executes an owner suite through `scripts/soleur-sandbox.sh run-isolated`, results in `evidence.md`; a row that cannot be run is listed UNVERIFIED with the reason, never counted as passed. M2 and M12 are the two rows that MUST read RED where a stopping-at-the-first-member or delete-only battery would read green.
- [ ] AC-8 The dynamic control (Guard 3) is recorded: the non-reading stub fails the pipeline under SIGPIPE ignored and under the default, as a `#!/bin/sh` stub and as a bash stub; each accepted spelling passes under the interpreter it is tagged for; each non-reading spelling fails; the writer waits on a sentinel with a bounded poll, so the row asserts reproduction and no wall-clock constant decides it.
- [ ] AC-9 Repo-global lints pass against the branch's base: `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `shellcheck -S warning` findings on the guard and every edited suite unchanged from base, `python3 scripts/lint-guard-contract.py` on this plan, `markdownlint --config .markdownlint.json` on changed `.md`, `bash scripts/pre-push-ratchet-lane.sh`, and `bash scripts/test-affected-kb-consumers.test.sh` once before the push (a baseline row may be added only for a reference the guard does not read).
- [ ] AC-10 `SWEEP_PROBE_CHECKS` equals `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -cE '(\|\||&&)[[:space:]]+sweep_probe_fail\+=\('`, the arithmetic (36 at S7a, checks added here) is recorded, and the guard's derivation reads files through one `git ls-files` and one token set per test file (read in the code, no per-pair scan of the test corpus); the guard's wall time before and after is recorded plain and under a Check 10-shaped read-only `bwrap` with `uptime` beside each figure as context for the 15 s preflight cap, not as a gate.
- [ ] AC-11 PR body: `Ref #9217` (never a closing keyword), a plain NOT-fixed list, a `Filed:` line and a gate-override justification if an issue is filed, Merge Danger (`Undo:` and `Blast Radius:`), Pipeline Tally, Changelog, Model Dissents; cites the spec dir's `evidence.md`, not this plan's path; says the sites are unchanged and only test stubs moved; avoids the barred vocabulary (write "non-test" for the series' older word) and bullets that start with an operator verb; labels per the S5 and S6 convention (`semver:patch`, and `app:web-platform` when an infra suite changed); no `[skip-deploy-fix-apply]`.

### Post-merge

- [ ] AC-12 `soleur:postmerge`: `deploy-arm.sh find --wait <full sha>`, then `served` reads CONTAINS (a tests-only diff may have no deploy for the merge SHA; record what the arm says); when an infra suite changed, read the `Apply web-platform infra` and `Infra Validation` runs for the merge SHA against #9956's known reds; then a tracker comment on #9217 with the J0 funnel numbers and their command, the before and after `JOINED:` table, the matrix results, the NOT-fixed list, and the next slice named (the tracker is the re-evaluation record; no new issue).

## NOT fixed here (carried into the PR body and the tracker comment)

- The Arm F remainder (103 lines in 24 files piping into a function defined in the same file) and the guard's consumer-side blind spots already listed in its header.
- Items D, E, F, G, I and H; the Wave A3 carriers (six carrier rows, 23 hits, gated on a host replace); the #9639 and #9638 triage; the dissent records #9971 and #9950.
- Pairs whose owner could not be run (UNVERIFIED) or is red at base (BLOCKED, including `cloud-init-inngest-bootstrap.test.sh` while #9956 is open): listed as `exempt` rows with their class, not fixed.
- A stub built through a helper whose body the definition finder cannot read, a stub in a file sourced two or more hops away, a stub spelled in a way none of the four arms detects, and a verb named through a variable (`WEB_HOST_SSH`): invisible to the join, listed as `exempt` rows where known and counted in `evidence.md`; the `ssh` stand-in in `workspaces-luks-verify-workflow.test.sh` is the named example.
- The positional pin is stricter than "reads before it can exit": a stub that drains second is red. Recorded, not relaxed.
- The dynamic check of each real heredoc stub under a late writer (plan-review suggestion, decision-challenges item 6) and the review's other taste cuts (decision-challenges items 5 to 8).
- A named follow-on slice, to be filed on the tracker when this lands: add the join's owner suites to the guard's declared affected-edge list in `scripts/lib/test-affected-paths.sh` (or derive the edge from the join), so `--affected` selects the guard when an owner suite changes.
- The declared affected-edge list for the guard cannot be extended here, so `--affected` runs do not select the guard when only an owner suite changes; CI's full battery does.
- PR #9745's `cursor-matcher-parity.test.sh` line 102 pipe (another PR's file).

## Test Scenarios

- Given the guard after Phase 3, when a new suite stubs `gh` and names a non-test script that pipes into `gh`, then the guard fails naming the suite and `gh` as an unlisted pair.
- Given a running stub whose drain is its first statement, when the drain is moved below the stub's `exit` arm, then the guard fails on the positional pin even though the text still contains a drain.
- Given the control, when its non-reading stub is replaced by a draining one, then the guard fails because the hazard no longer reproduces.
- Given a suite that names a listed non-test file only in a comment, then no pair derives and the guard stays green.
- Given the repository after Phase 2, when the owner suites run, then each edited suite's result equals its result at its base commit.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; this one carries `threshold: none` with a reason.
- The text-pipe regex must itself be pipe-guard clean when run in this repo: the J0 derivation and the guard's derivation read files with `git grep`, a here-string or a process substitution, never `... | grep -q`. A pipe-fed early-exit reader in the measuring tool would flake the measurement it reports (the scratch version of this plan's own J0 did exactly that on first draft).
- Funnel A counts a suite as an owner when it NAMES the file; naming is not running. Never edit a stub because the textual join listed it: the reach probe decides, and a TEXT pair is an `exempt` row whose reason cites the probe, not a skipped pair.
- The reach probe inserts a marker into scratch copies only. A probe left in a committed stub is a defect; AC-9's shellcheck and the pair run would not see it, so `git diff --stat` on each owner suite is read for added lines that are not the three kinds of edit.
- Guard 2 pins the drain as the FIRST statement of a stub definition. A stub with several definitions (`ci-deploy.test.sh` holds five `curl` stubs) needs the statement in each pinned definition or an exemption; the row's definition count is what stops a sixth from slipping in. A stub that reads stdin elsewhere in its body is red until it is rewritten, by design.
- A drain written as a bare `cat >` blocks when a harness leaves stdin open (the luks-verify suite measured `sleep 20 | timeout 8 bash <suite>` rc 124); the canonical form in Phase 2 bounds the read with `timeout 2`. An unset capture variable must not become a redirect to `/dev/null.stdin`.
- `#!/bin/sh` stubs run under dash: use `case`, `[ ]` and `cat`; no `[[ ]]`, no `<<<`.
- The suites under `apps/web-platform/infra/` edit at merge time what S6 documented: an infra-validation run, the web-platform release path and an apply plan of the whole root. Unrelated drift in that plan is applied at this merge; AC-12 reads the run for the merge SHA.
- Mutation rows that run an owner suite do so inside `scripts/soleur-sandbox.sh run-isolated`; the guard's own mutants only read files and need no sandbox beyond a scratch clone, and `/var/tmp` has been near full, so leave no clone behind.
- The sweep elsewhere in the guard reads the working tree (`--no-index`), so a stray untracked `.sh` or `.yml` changes ITS hit set; the join's derivation reads tracked files only (`git ls-files`), so a mutation that adds a file must `git add` it, and a scratch file left untracked cannot change the join. Run the guard, J0 and the matrix from a clean checkout either way.
- The guard's derivation and `j0-derive.py` are two implementations of one definition; the guard's is authoritative (stated in its header), `j0-derive.py` is a point-in-time measurement artifact, and AC-4 compares them once. AC-4 proves the two agree, not that either finds every instance: recall is what Guard 1's named recall rows are for.
