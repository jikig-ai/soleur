---
title: "fix: S4 observation-window probe dies on a large pull request (argv limit) and cannot finish inside the sweeper job"
type: fix
date: 2026-10-27
slug: observation-window-probe-argv-limit
branch: feat-one-shot-observation-window-probe-argv
issue: 10865
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

<!-- lane: the branch has no spec.md, so the carry-forward is empty and the fail-closed default cross-domain applies (TR2). closes: is deliberately absent; the PR text uses "Ref #10865, Ref #10861" only, never a closing keyword. -->

## Overview

The follow-through probe `scripts/followthroughs/ratchet-observation-window-10865.sh` (tracker #10865, Ref #10861)
exits 3 with `CANNOT ESTABLISH: GitHub API read failed (pull 9051 files (parse))` and cannot certify the S4
observation window while a large pull request is among the listed runs. It also prints nothing while it works, so
the failure took ~15 to 30 minutes to see. This plan (1) fixes the confirmed cause, (2) makes the sweep finish
inside the nightly sweeper job (it cannot today, see Research Reconciliation), (3) adds progress markers and a real
error message, and (4) extends the existing probe rows in `plugins/soleur/test/ci-pr-affected-replay.test.sh`
test-first with a many-files, large-patch fixture.

This is a follow-through probe, not an oracle input and not a drain PR: no change to `scripts/lib/test-affected-paths.sh`,
`scripts/test-all.sh`, the baseline, the accept file or `scripts/ci-pr-affected-replay.py`; no `s4-drain` label; none of
the standing holds (`CI_PR_AFFECTED`, activation-lock removal, PR D, PR3b, evidence re-run, flip PR) is touched.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured 2026-10-27, `origin/main` 2e9874cdf6, read-only, GH_TOKEN from `gh auth token`) | Plan response |
|---|---|---|
| "HYPOTHESIS, UNVERIFIED: argv-size limit (E2BIG class)" | **Confirmed.** `pulls/9051/files?per_page=100` page 1 is 704,649 bytes (pages 2 and 3: 768,190 and 1,134,782; page 4: 41 entries, 341 files in all) because of `patch` bodies. `jq -c -n --argjson a "[]" --argjson b "$page1" '$a + $b'` fails with `/usr/bin/jq: Argument list too long`, rc 126: Linux `MAX_ARG_STRLEN` is 131,072 bytes per argv entry (`ARG_MAX` is 4,194,304, not the binding limit). The probe's `2>/dev/null` hides the message and `\|\| fail_api "... (parse)"` relabels it. | Fix the cause (Phase 2), not the symptom. |
| "PR 9051 is the problem" | Not only 9051: a 12-PR sample of recent PRs had first files pages of 54 to 117 KB (3 of 12 within 15% of the limit). Any PR with a first page over 128 KiB trips it; 9051 is hit first because the oldest 260 runs belong to ~7 PRs and 9051 is the first green PR unit. | The fixture is generic (many files, large patches), and a static row bans API data on any jq argv. |
| "a single sweep takes 30 min" | Measured on an instrumented copy: **listing 13 calls, 44.5 s (3.4 s each); reading 265 `jobs` calls (2.08 s avg, 550 s) + 264 job-log calls (1.14 s avg, 302 s) = 897 s; the run reached the PR-facts phase at t+953 s and died there.** 99% of the time is serial API latency; local jq/awk is negligible. The PR-facts phase (`draft_at`: 2 uncached calls per green PR unit until a draft is seen, up to ~199 PR units) is not yet measured because the run dies before it; the 30 minutes observed earlier is consistent with ~16 min of reads plus several minutes of repeated timeline/pull reads. | Phase 4: bounded-parallel reads, per-PR cache of timeline/pull reads, progress markers that make the PR-facts phase measurable. |
| (not in brief) | **`scheduled-followthrough-sweeper.yml` has `timeout-minutes: 15` for the whole job; probes run sequentially; `scripts/sweep-followthroughs.sh` has no per-probe timeout (grep for timeout/budget/deadline: no hit); a typical whole sweep was 3m51s.** The probe's `earliest=2026-10-31`: from then on a ~16 to 30 minute probe is killed by the job timeout every night and starves every tracker after it. The E2BIG fix alone only moves the failure. | CTO ruling D: speed work is in scope. Comment on existing #7923 (sweeper per-probe timeout) with the measured evidence; no new issue. |
| "`api()` ... fails (parse)" | `api() { gh api "$1" 2>/dev/null; }` and the jq calls in `pr_facts` all discard stderr, so the error text of any failure is invisible. | Ruling C: keep the first 160 printable bytes of jq's stderr in the message. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10865 OPEN (soak tracker, labels `follow-through`, directive `script=scripts/followthroughs/ratchet-observation-window-10865.sh earliest=2026-10-31T00:00:00Z secrets=GH_TOKEN`); #10861 OPEN ("S4 PR5, accept rows and non-code pairs, delete the baseline"); PR 9051 OPEN, draft, `changedFiles` 341 (the brief says 340). The probe file exists on `origin/main` (introduced by commit 45f0b096ff, PR3a #10851); its test rows exist at `plugins/soleur/test/ci-pr-affected-replay.test.sh` section "ratchet observation window (#10865)". Collision pre-check: no open PR names #10865; the 11 foreign `test-all.sh` processes belong to sibling worktrees unrelated to this probe. ADR corpus: no ADR names a probe-sweep mechanism; this plan makes no architectural decision. The brief's "~30 min" is higher than the 16 min measured here; API latency varies by time of day, so the plan budgets for the larger figure.

**Property List (Phase 0.6b).** P1: a pull request whose files page is larger than 128 KiB (or whose file list is long) is read without error. P2: the probe finishes inside the sweeper job's 15 minutes with room for other trackers. P3: an operator watching the probe sees which phase it is in, and the sweeper's stdout first token is unchanged. P4: a failed read names its cause. P5: existing verdict semantics (oldest-first prefix, defects, incidents, oracle exclusion) are unchanged.

**Cut List.** (a) Moving to the GraphQL API to get filenames only: buys P1 which projecting each REST page already buys, and adds a second API surface; cut. (b) `gh api --jq` projection inside gh: buys P1 but breaks the stub-gh test seam (the stub keys on the last argument) and learning 2026-03-04 says `gh --jq` cannot take `--arg`; cut in favour of piping to jq. (c) A new `scripts/followthroughs/*.test.sh`: would need a `run_suite` line in `scripts/test-all.sh`, which is out of scope; rows stay in the replay suite as today. (d) A per-probe timeout in the sweeper: the right long-term guard, already tracked as #7923; not this PR.

**Value-proposition measurement (Phase 0.6c).** The saving claimed (reads drop from ~15 min to ~2.5 min) is derived from the measured series above: 529 serial reads at ~1.6 s each (stated command: the instrumented copy of the probe, per-call durations appended to a TSV, summarised with awk); divided by P=6 it is ~140 s. The parallel latency itself is **unmeasured** (GitHub's secondary rate limit may push calls slower); the work phase measures it with the new progress markers on the post-merge live run and the CTO's flip condition (403s: lower P to 4) applies.

**Institutional learnings applied** (learnings-researcher, 8 hits): `2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md` (E2BIG is `MAX_ARG_STRLEN` per entry; fix pattern is `printf '%s' "$x" > file` then `jq --slurpfile`, and a multi-page fixture is needed so `add // []` is distinguishable from `.[0]`); `test-failures/2026-08-19-my-stub-could-not-express-the-failure-so-the-fix-reverted-green.md` (a 90-byte fixture let the `--argjson` revert stay green: assert a fixture-size precondition `> 131072` before running the SUT); `2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md` (pass large fixtures by file, assert the failure MESSAGE not only rc != 0); `2026-03-04-gh-jq-does-not-support-arg-flag.md`; `2026-09-25-gh-stub-must-mirror-real-cli-flags.md`; `integration-issues/2026-06-02-followthrough-gh-probe-needs-secrets-gh-token-env-i-strips-it.md` (the directive already carries `secrets=GH_TOKEN`); `2026-10-22-a-verdict-function-inside-command-substitution-cannot-exit-...md` (fail paths must not live inside `$( )`: relevant to the worker design); `2026-10-06-total-count-is-a-snapshot-not-a-truncation-proof.md`. Gaps: no learning covers stderr progress markers or sweeper rate limits.

**Functional overlap (Phase 1.5b).** Three registry queries (claude-plugins.dev, claudepluginhub.com, Anthropic marketplace.json): no skill or agent covers bounded-parallel Actions sweeps or probe progress conventions. Repo research was done directly (single script, single suite); no `repo-research-analyst` fan-out was needed.

**Open Code-Review Overlap.** None. Queried open `code-review` issues for the three planned file paths: no match.

## Technical rulings (CTO, recorded in `decision-challenges.md`)

Ruled by CTO agent, 2026-10-27 (spawned with "do NOT use AskUserQuestion"):

- **A. Speed:** bounded-parallel reads, P=6 (`SOAK_PARALLEL` seam), plus a wall-clock budget `SOAK_BUDGET_S` default 300 s measured from probe start and checked before each dispatch. At the deadline stop launching, drain in-flight workers. Output is merged sorted by `created_at`, so it is order-independent. Any worker failure stops further launches and exits 3 naming the lowest failing run id. The newest 10 `merge_group` units are dispatched FIRST ("newest queue state" must never be what the budget cuts). A budget hit may still PASS with `truncated=1` only if the newest-queue units were fully read and every coverage predicate holds on the contiguous prefix; otherwise exit 2 `NOT YET`; never exit 3 merely because the budget ran out. Flip condition: secondary-rate-limit 403s in a live run -> P=4.
- **B. Progress:** (B1) about four coarse phase lines always on stderr (counts and phase names only, no run ids, titles or logins; < 500 bytes), plus a per-25-units heartbeat only when `SOAK_PROGRESS=1` or stderr is a TTY. The sweeper folds stderr into the public comment tail (`tail -c 4000`), hence the cap. The line format must not reuse the status line's token order.
- **C. Error text:** keep jq's stderr (`tr -cd '[:print:]'`, 160 bytes) in the `(parse)` message of the `pr_facts` jq calls.
- **D. Scope:** the speed work stays in this PR; edits are limited to the probe, the replay suite and the runbook's probe paragraph.

Lead dispositions (applied after the plan-review panel; challengeable): the "discard completed units beyond a gap" rule is satisfied structurally, because dispatch is in oldest-first order and the drain waits for every in-flight worker, so no defensive contiguity check, test hook or row is added (three reviewers: it is unreachable by design, and a skipped job legitimately writes no row). The newest-queue extras (at most 10) are exempt from the deadline, which resolves the rule-versus-check contradiction a reviewer found. `draft_at` reads the timeline once per PR and takes the draft flag from the pull JSON `pr_facts` already holds. Payloads travel by here-string or pipe (stdin), not temp files; `$SECONDS` replaces `EPOCHREALTIME`, so the bash >= 5 prerequisite and its row are cut. The status line on stdout is unchanged; elapsed time is on stderr only. Progress keys avoid the tokens the existing rows grep (`runs_listed`, `units=`, `units_read`, `truncated`, `restarted`, `paused`, `NOT YET`, `PASS:`) so no old row is satisfied by progress text. One reviewer challenge (DHH) is recorded, not adopted: make a budget hit always exit 2 and never PASS (the CTO ruled that a truncated PASS is allowed when the newest queue was read; see `decision-challenges.md` row H).

## Implementation Phases

### Phase 0 — Reproduce (re-run before touching code; evidence is in this plan)

```bash
# page 1 of the real files list, then the probe's own accumulator step
gh api "repos/jikig-ai/soleur/pulls/9051/files?per_page=100&page=1" > "$S/page1.json"; wc -c < "$S/page1.json"   # 704649
files="[]"; page_files="$(cat "$S/page1.json")"
jq -c -n --argjson a "$files" --argjson b "$page_files" '$a + $b' > /dev/null; echo "rc=$?"                    # rc=126, "Argument list too long"
```

`$S` is the session scratchpad. Expected: rc 126. If rc is 0, the hypothesis is wrong for this jq/kernel and the real cause must be found before any edit.

### Phase 1 — Tests first (RED on the unfixed probe)

All edits in `plugins/soleur/test/ci-pr-affected-replay.test.sh`, section "ratchet observation window (#10865)":

1. Fixture builders: `ow_big_files <n> <prefix> <patch_bytes> [patch_text]` (n entries `{"filename":"<prefix><i>.ts","patch":"<patch_bytes of x>"}`), a size precondition helper `ow_assert_bytes_over 131072 <fixture>` run by every big-fixture row (a trimmed fixture must fail the row, not silently become a duplicate of the small one), `ow_probe_split` (stdout and stderr captured to separate files; the existing `ow_probe` merges them with `2>&1`), and a stub-gh branch `SLOW_<key>` that sleeps `${SLOW_S:-1}` and then serves the REAL fixture (the existing `HANG_<key>` branch sleeps and then answers an empty run list, which makes the delayed unit vanish, so it cannot test ordering or the budget).
2. Rows. The E2BIG rows assert the failure MESSAGE on the unfixed probe, not only rc != 0:
   - `row_ow_big_patch`: PR 16 as the third distinct PR (`ow_u_few16`); pages of 100, 100 and 50 entries with 4 KB patches (page 1 about 410 KB; a full third page would append the 300-file sentinel and exclude the PR); one patch body contains the text `scripts/test-all.sh` (a must-PASS, non-canonical input: only filenames decide). Expect `green_pr_units_distinct_prs=3`, no `CANNOT ESTABLISH`. Unfixed: `pull 16 files (parse)`.
   - `row_ow_big_long`: three FULL big pages (the PR 9051 shape: the `(more than 300 files)` sentinel path): PR excluded, `distinct=2`, rc 2, no `CANNOT ESTABLISH`.
   - `row_ow_long_names`: pages of 100, 100 and 50 entries with 600-character names and no patches (each page and each accumulator operand is under 131072 bytes, the exclusion program's `files` operand is over it: ~150 KB). Expect `distinct=3`. Unfixed: `pull 16 (parse)` (the SECOND argv site), a different message from the rows above; the row asserts its own precondition (accumulated size > 131072, every page < 131072).
   - `row_ow_pr_facts_cached`: PR 11 (timeline `[]`, not a draft) given a second green unit earlier than 5003 (`5007 pull_request shaG feat/a 2031-02-02T01:30:00Z 1 11 0 150`); anchored greps assert exactly one `issues_11_timeline_per_page_100` request and exactly one `repos_..._pulls_11` request (unanchored `pulls_11` also matches `pulls_11_files`). Unfixed: 2 timeline and 3 pull requests. (PR 13 cannot test the cache: its timeline makes unit 5003 a draft and `draft_seen` latches.)
   - `row_ow_static` extended (one added regex, no new row): every `--argjson` operand in the probe is `$ORACLE_JSON` or `$curdraft` (and at least one was found, so a scan that matches nothing is RED); the projection `{filename}` is present.
   - `row_ow_progress`: via `ow_probe_split`: stdout begins with the verdict token and has no line starting `soak-progress:`; stderr carries `soak-progress: phase=listed`, `phase=read-done`, `phase=facts-done` in that order, under 500 bytes in all; no progress line contains `runs_listed`, `units_read`, `units=` or `truncated`.
   - `row_ow_heartbeat`: `SOAK_PARALLEL=1 SOAK_PROGRESS=1` with 30 units: a `heartbeat read=25/` line appears; without the flag (stderr is a file) none.
   - `row_ow_parallel_same`: `SOAK_PARALLEL=1` and `SOAK_PARALLEL=6` give byte-identical stdout, with `SLOW_` on the OLDEST unit's jobs path so completion order differs from dispatch order.
   - `row_ow_worker_fail`: one run's jobs read fails (`fx_err`) among many -> rc 3, message names that run id and is the first failing worker in dispatch order; a second failing run later in dispatch order is not the one named.
   - `row_ow_budget`: `SOAK_BUDGET_S=1 SOAK_PARALLEL=1`, `SLOW_S=2` on every PR unit's jobs path (the base fixture holds exactly 3 `merge_group` units): `truncated=1`, rc 2, no `CANNOT ESTABLISH`; the first jobs request in the stub log is a `merge_group` run (extras first); `units_read=4` (3 extras plus the first oldest-first unit, which is dispatched unconditionally; later dispatches see `SECONDS` >= 1 after the 2 s read).
   - `row_ow_jq_error_text`: a files page that is not an array (`{"message":"x"}`) -> message contains jq's own error text, at most 160 printable bytes, no control characters.
3. Mutants (`ow_mutate`, GREEN-row-on-real, RED-on-mutant): `args-accumulator` (feed a page through `--argjson`), `oracle-argv` (`--argjson files` back), `progress-to-stdout`, `parallel-rc-ignored`, `budget-ignored`, `extras-last`, `draft-cache-dropped`, `jq-error-dropped`, `merge-in-completion-order`. Existing mutant anchors (`long-file-list-read-forever`, `oracle-list-ignored`, `fork-head-repo-ignored`, `one-page-only`, `merged-at-spliced`) were checked against the planned edit: the `old` strings stay unique if the `[ "$page" -lt 3 ] || {` line, the exclusion `elif` lines and the listing filter are kept verbatim.
4. Floors: bump `FLOOR_ASSERTIONS` and `FLOOR_MUTANTS` by the measured additions (additive, with the comment style already used there).
5. Run the section against the UNFIXED probe and record which new rows are RED (E2BIG rows RED with the messages above; feature rows RED because the feature is absent). Existing rows stay GREEN.

### Phase 2 — The E2BIG fix (`pr_facts`)

In `scripts/followthroughs/ratchet-observation-window-10865.sh`, with no temp files for payloads (a here-string or pipe is not argv):

- Per page: `out="$(jq -c 'if type == "array" then [.[] | {filename}] else error("files page is not an array") end' 2>&1 <<<"$page_files")" || fail_api "pull $n files (parse): $(jq_detail "$out")"`; accumulate the projected page into `files` with a stdin-fed `jq -s -c 'add'`; the count `cnt` comes from the projected page; keep the page loop, the 3-page cap and the sentinel, now appended as one more projected element (`files="$(jq -c '. + [{"filename":"(more than 300 files)"}]' <<<"$files")"` already reads stdin and stays).
- The exclusion program takes the pull and the list on stdin: `{ printf '%s\n' "$p"; printf '%s\n' "$files"; } | jq -s -r --argjson oracle "$ORACLE_JSON" '.[0] as $p | .[1] as $files | ...'` with the program body unchanged (`$p` replaces `.`, `$files` is the same array). `printf` is a builtin, so there is no `execve` and no argv. `PR_DOCS` and `PR_SCRIPTS` already read `<<<"$files"`.
- `jq_detail` is `printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-160`.

### Phase 3 — Cache `draft_at`

`draft_at` re-reads the issue timeline and `pulls/<n>` for EVERY green PR unit until a draft is seen (2 calls per unit; it is called once per unit, not once per PR). In `pr_facts`, store `PR_CURDRAFT[$n]` from the `$p` it already holds (this removes the second `pulls/<n>` read entirely), and `draft_at` reads the timeline once per PR into an associative array `PR_TL[$n]` like `PR_DOCS`. Known pre-existing limitation, unchanged and recorded: the timeline read is the first 100 events only.

### Phase 4 — Parallel reads, budget and progress markers

- Seams (inert under the sweeper's `env -i`): `SOAK_PARALLEL` (default 6), `SOAK_BUDGET_S` (default 300), `SOAK_PROGRESS` (`1` forces the heartbeat on); validated as positive integers like `SOAK_MAX_PAGES` (exit 3 otherwise). The deadline uses `$SECONDS` (one-second granularity is irrelevant at 300 s and it has no locale radix: `EPOCHREALTIME` and a bash >= 5 prerequisite were cut). The probe already needs bash >= 4 (`declare -A`); `wait -n` needs 4.3 and the sweeper runs 5.2.
- Replace the `while read ... done < read.tsv` loop body with a function `read_unit` (prints the unit row, or the `CANNOT ESTABLISH` line and exits; the two `continue` statements become `return 0`, because a `continue` inside a function is evaluated against the CALLER's loop depth). Launch each as `{ ( read_unit ... ) > "$WORK/u/$seq.out" 2> "$WORK/u/$seq.err"; echo $? > "$WORK/u/$seq.rc"; } &` with a zero-padded `$seq` (`printf '%06d'`). A counter keeps at most P in flight (`wait -n`, guarded so a desynced counter cannot loop); the drain loop `while (( inflight > 0 )); do wait -n; inflight=$((inflight - 1)); done` counts completions for the heartbeat. `read_job`'s globals stay inside the worker subshell. `fail_api`'s `exit` ends only the worker; after the drain the main shell prints the `.out` of the first failing worker IN DISPATCH ORDER and exits 3. The EXIT trap also waits for in-flight workers before removing `$WORK`.
- Dispatch order: the newest-`merge_group` extras (at most 10, exempt from the deadline) first, then the oldest-first list; the deadline (`SECONDS - T0 >= SOAK_BUDGET_S`) is checked before each oldest-first dispatch except the first. `units_read` is the number of completed workers; `TRUNC=1` when it is below the readable count. Merge the rows in seq order, then the existing `sort -t$'\t' -k5,5 -s` with a `-k1,1n` tiebreak, so output is order-independent. When the budget cut the sweep, add `NOT YET: read budget ended after N of M runs (SOAK_BUDGET_S=...)` only if a coverage predicate is unmet (a PASS with `truncated=1` keeps today's prefix semantics, per ruling A).
- Progress (stderr only; three coarse lines, counts and phase names only): `soak-progress: phase=listed seen=<n> readable=<n> to_read=<n> parallel=<P> budget_s=<B> elapsed_s=<s>`, `soak-progress: phase=read-done done=<n> partial=<0|1> elapsed_s=<s>`, `soak-progress: phase=facts-done prs=<n> elapsed_s=<s>`; plus `soak-progress: heartbeat read=<d>/<n> elapsed_s=<s>` every 25 completions when `SOAK_PROGRESS=1` or stderr is a TTY. The status line on stdout is UNCHANGED (a wall-clock field there would make every nightly comment differ and break the byte-identity row; elapsed time lives on stderr).
- Update the header: the "WHAT A PASS CERTIFIES" paragraph (budget, newest-queue-first, the budget bounds the READ phase only; the facts phase is serial and unbudgeted, which is acceptable at ~35 calls for ~7 PRs), the seam list, and a measured-timings line.

### Phase 5 — Runbook, floors, local gates

- Update the bullet "Reads are bounded and oldest-first." in `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (budget, parallelism, progress markers).
- Run the replay suite (the CI-required `test` context's member); shellcheck the probe; the local affected-tests gate may fall back to the full battery if a runner file is touched, and CI's required `test` context is the merge gate.

### Phase 6 — Ship and post-merge verification

- PR text: `Ref #10865`, `Ref #10861` only; no closing keyword; no `s4-drain` label; `## Changelog` section; `semver:patch`.
- `prepush-secret-scan.sh` before every push; no `--no-verify`; CI and merge state polled with Monitor.
- Comment on #7923 with the measured 15-minute-job evidence (no new issue).
- After the merge, run the probe once, read-only: `GH_TOKEN="$(gh auth token)" bash scripts/followthroughs/ratchet-observation-window-10865.sh` with stderr to a file so the progress lines are kept; report its verdict, `elapsed_s` and the phase timings to the operator; **post nothing** to #10865 without the operator's go.

## Files to Edit

- `scripts/followthroughs/ratchet-observation-window-10865.sh` — pr_facts, draft_at, read phase, progress, seams, header.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — rows, mutants, floors (section "ratchet observation window (#10865)").
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — the probe's "Reads are bounded" bullet.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-observation-window-probe-argv/tasks.md` and `decision-challenges.md` (plan artifacts).

## Architecture Decision (ADR/C4)

None. A bug fix and a speed change inside one read-only probe; no ownership boundary, substrate, trust boundary or ADR is changed or reversed (ADR-276's PR3a amendment names the probe's behaviour at the level of "bounded reads, oldest-first", which this plan keeps). The probe's CTO row 6 in the PR4 decision log ("do NOT edit the probe") concerned drain PRs inside the window; this PR is not a drain PR and the probe's oracle-exclusion logic is unchanged.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** the CTO agent ruled the four forks above (parallel reads with a budget, tiered progress markers, jq error text, scope) with the evidence in this plan; no other domain (product, legal, finance, marketing, sales, support, operations) has an implication: an internal read-only probe, no user-facing surface, no regulated data, no spend change (about 570 REST reads per nightly sweep, 11% of one hour's 5,000-call token budget).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; the operator sees the nightly follow-through sweeper's tracker comment read `CANNOT ESTABLISH` or the sweeper job hit its 15-minute timeout and skip later trackers (internal tooling).
- **If this leaks, the user's data is exposed via:** no user data is read; the probe holds only `GH_TOKEN` and still refuses to run under xtrace; progress lines carry counts and phase names only, and the 160-byte jq error text is public GitHub metadata.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal read-only probe on public repository metadata; the worst case is a delayed or noisy operator signal.
- threshold: none, reason: the touched files are an internal follow-through probe, its test suite and a runbook paragraph; no user-impacting or credential-bearing path other than the already-declared GH_TOKEN secret.

## Observability

```yaml
liveness_signal:
  what: "the probe's own stderr phase lines (soak-progress: phase=listed / read-done / facts-done, each with elapsed_s)"
  cadence: "per sweep (nightly from 2026-10-31 via the follow-through sweeper)"
  alert_target: "the sweeper's tracker comment on #10865 (last 4 KB of output, verdict word from the exit code: NOT YET / CANNOT ESTABLISH)"
  configured_in: "scripts/followthroughs/ratchet-observation-window-10865.sh"
error_reporting:
  destination: "stdout first token and exit code, rendered by scripts/sweep-followthroughs.sh into the tracker comment"
  fail_loud: "CANNOT ESTABLISH: GitHub API read failed (<what> (parse): <first 160 printable bytes of jq's error>) and exit 3"
failure_modes:
  - mode: "a files page or any API payload crosses the argv limit"
    detection: "the static row bans API data on any jq argv (only the two small --argjson operands are allowed); the jq error text now appears in the message"
    alert_route: "exit 3 comment on #10865"
  - mode: "the sweep outgrows the sweeper job again"
    detection: "elapsed_s on the stderr phase lines; the SOAK_BUDGET_S deadline reports truncated=1 and NOT YET instead of a job timeout"
    alert_route: "the tracker comment; #7923 tracks the sweeper-side per-probe timeout"
  - mode: "GitHub secondary rate limit under parallel reads"
    detection: "a worker failure exits 3 naming the lowest failing run id"
    alert_route: "exit 3 comment; lower SOAK_PARALLEL to 4 (CTO flip condition)"
logs:
  where: "the sweeper job log and the tracker comment (last 4 KB)"
  retention: "GitHub Actions log retention; the comment is permanent"
discoverability_test:
  command: grep -o 'soak-progress: phase=listed' scripts/followthroughs/ratchet-observation-window-10865.sh
  expected_output: soak-progress: phase=listed
```

## Guard Contract

The behavioural rows are specified in Phase 1; this section states the properties and the mutations that must drive them RED.

### Guard 1 — no API data on a jq argv

**Property.** No jq invocation in the probe receives GitHub API payload data (a files page, the accumulated file list, a pull, a timeline) as an argv element, so no payload size can raise E2BIG.

**Assembly.** Every `jq` call in `scripts/followthroughs/ratchet-observation-window-10865.sh` that carries `--arg` or `--argjson` (the listing filter `--arg m/--arg ev`, `read_job` `--arg n/--arg s`, the exclusion program `--argjson oracle`, the docs program `--arg kb`, `draft_at` `--arg t/--argjson cur`, and the old accumulator `--argjson a/--argjson b`); payloads reach jq only by here-string or pipe. The chokepoint is the extended `row_ow_static` regex: any `--argjson` operand other than `$ORACLE_JSON` or `$curdraft` fails, so a NEW call site is covered without being named; the behavioural rows cover the sites a static regex cannot see.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | feed a files page back through `--argjson b "$page_files"` (the original defect) | RED (`row_ow_big_patch`, `row_ow_static`) |
| 2 | make the operand scan match nothing (the guard's own dispatch: "0 operands examined") | RED (the static row requires at least one `--argjson` operand found) |
| 3 | after a compliant first call, put the accumulated list on `--argjson files` in the exclusion program | RED (`row_ow_long_names`, `row_ow_static`) |

Harness rows: the fixture-size preconditions (`> 131072` bytes; every page `< 131072` for the long-names row) are asserted by the rows themselves, so a trimmed fixture reds the row; the must-PASS inputs differ from the canonical (a patch body that mentions an oracle path; long names with no patch) and `row_ow_pass` keeps the healthy window passing. Anchor: the 128 KiB figure and the allow-list live in the suite, outside the probe, so a probe edit cannot move both.

### Guard 2 — stdout contract survives progress output

**Property.** Progress output is on stderr only; stdout begins with exactly one of `PASS:`, `NOT YET:`, `CANNOT ESTABLISH:` (or the status line) and its token order is unchanged.

**Assembly.** The `note()` helper and the heartbeat (the only emitters of `soak-progress:`) and every `printf`/`echo` in the probe; the sweeper's `2>&1` fold is the consumer (it derives the verdict word from the exit code, not from the first token); the chokepoint is `note()`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove `>&2` from `note()` | RED (`row_ow_progress`) |
| 2 | emit zero progress lines (the helper's dispatch removed) | RED (the row asserts the three ordered phase lines) |
| 3 | after a compliant stderr line, add a second emitter that prints a `soak-progress:` line to stdout | RED (no stdout line may start with `soak-progress:`) |
| 4 | put `runs_listed=` in a progress line | RED (collision check in the same row) |

### Guard 3 — parallel reads keep order-independence, failure and the budget

**Property.** However reads are interleaved or cut by the deadline, the output is independent of completion order, a failed read exits 3 and is never counted, the newest-queue extras are read first, and a budget hit never becomes CANNOT ESTABLISH.

**Assembly.** The dispatch loop (the only place a read is launched, with its single deadline check), the drain, the merge of the worker rows, and the failure collection; the chokepoint is the dispatch loop.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | ignore the deadline | RED (`row_ow_budget`) |
| 2 | dispatch the newest-queue extras last | RED (`row_ow_budget`: first jobs request must be a `merge_group` run) |
| 3 | merge rows in completion order instead of sorting by `created_at` (a `SLOW_` fixture on the oldest unit) | RED (`row_ow_parallel_same`) |
| 4 | ignore a worker's non-zero rc | RED (`row_ow_worker_fail`) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Reproduce first (call the same jq steps against that PR's real pages, or a synthetic 340-file fixture with large patch fields) and confirm the cause before changing anything" | Phase 0; Research Reconciliation row 1 | mapped |
| 2 | "stream via stdin or --slurpfile / `jq -s` on temp files, and project each page to the fields the probe actually uses (filename only) before accumulating" | Phase 2 | mapped |
| 3 | "check whether it should emit a progress marker per sweep phase (runs_listed / units_read) on stderr" | Phase 4 progress; CTO ruling B | mapped |
| 4 | "why the sweep is that slow (measure; do not guess)" | Research Reconciliation row 3 (measured series); Phase 3 and 4 | mapped |
| 5 | "extend it with a many-files, large-patch fixture that fails before the fix and passes after, keeping existing rows green" | Phase 1 | mapped |
| 6 | "do not touch scripts/lib/test-affected-paths.sh, scripts/test-all.sh, the baseline, the accept file, or scripts/ci-pr-affected-replay.py; no `s4-drain` label" | Files to Edit (three files only) | mapped |
| 7 | "After the fix merges, re-run the probe read-only once (GH_TOKEN from `gh auth token`) and report its verdict; do not post it anywhere without the operator's go" | Phase 6 | mapped |
| 8 | "Ref only, never a closing keyword in PR text" | Phase 6 PR text; frontmatter note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| files projection, stdin pipes | "project each page to the fields the probe actually uses (filename only) before accumulating" | asked |
| progress markers (three phase lines) | "emit a progress marker per sweep phase" | asked |
| bounded-parallel reads, budget, newest-queue-first | "why the sweep is that slow (measure; do not guess)" | inferred — justification: the measurement showed the sweep cannot fit the sweeper job's 15-minute timeout; CTO ruled it in scope (rulings A and D) |
| seams SOAK_PARALLEL, SOAK_BUDGET_S, SOAK_PROGRESS | "why the sweep is that slow (measure; do not guess)" | inferred — justification: the test suite must drive the budget and ordering deterministically; seams are inert under the sweeper's `env -i` like the existing SOAK_* ones |
| heartbeat and TTY detection | "the probe printed nothing for 14 minutes under `| tail`" | inferred — justification: CTO ruling B1 (opt-in, keeps the public comment tail clean) |
| per-PR timeline cache, draft flag from the pull JSON | "why the sweep is that slow (measure; do not guess)" | inferred — justification: removes up to ~2 uncached calls per green PR unit (called once per unit); mechanical |
| jq error text in the message | "the probe printed nothing for 14 minutes" | inferred — justification: the real error was hidden by `2>/dev/null`, which is what made diagnosis slow; CTO ruling C |
| "measured timings" header line, runbook paragraph | "keeping existing rows green" | inferred — justification: the header and the runbook state the probe's read bounds and would be stale |
| comment on #7923 | "A technical fork goes to soleur:engineering:cto" | inferred — justification: the sweeper-side per-probe timeout is an existing tracked issue; the evidence belongs there instead of a duplicate issue (an external write at ship time) |
| the three Guards | "extend it with a many-files, large-patch fixture that fails before the fix and passes after" | inferred — justification: plan gate 2.12 requires a Guard Contract for any guard deliverable; they restate Phase 1 rows |

### Split Assessment

- Subsystems touched: 3 — `scripts/followthroughs/`, `plugins/soleur/test/`, `knowledge-base/engineering/operations/runbooks/`
- Planned files: 3 edited (+2 plan artifacts) | Estimated changed lines: ~350 (probe ~100, suite ~230, runbook ~6)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] Phase 0 reproduction re-run before the first edit shows rc 126 for the accumulator step on PR 9051 page 1 (or the plan is revisited).
- [ ] Every new E2BIG row is RED on the unfixed probe with its stated message (`pull 16 files (parse)` for the big-patch row, `pull 16 (parse)` for the long-names row) and GREEN after Phase 2; all pre-existing rows stay GREEN.
- [ ] `row_ow_static` finds no `--argjson` operand other than `$ORACLE_JSON` and `$curdraft`, and at least one such operand.
- [ ] The stdout status line and verdict first tokens are unchanged (no new field).
- [ ] Progress lines: stderr only, three coarse lines under 500 bytes in all, no run ids, titles or logins, no `runs_listed`/`units=`/`units_read`/`truncated` tokens; heartbeat only with `SOAK_PROGRESS=1` or a TTY.
- [ ] `SOAK_PARALLEL=1` and `=6` produce byte-identical stdout with an out-of-order completion fixture; a worker failure exits 3 naming the first failing worker in dispatch order; a budget hit exits 2 (a PASS with `truncated=1` only when the newest-queue units were read), never 3.
- [ ] The timeline and `pulls/<n>` are each requested at most once per PR regardless of how many green units the PR has.
- [ ] `FLOOR_ASSERTIONS` and `FLOOR_MUTANTS` raised by the measured additions; replay suite green; shellcheck clean; `git diff --name-only origin/main` lists only the Files to Edit and the plan artifacts (none of `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`, the baseline, the accept file, `scripts/ci-pr-affected-replay.py`).
- [ ] PR body: `Ref #10865`, `Ref #10861`, no closing keyword; no `s4-drain` label; comment posted on #7923 with the measured evidence.
- [ ] Post-merge: one read-only live run reported to the operator (verdict, phase timings from stderr), nothing posted to #10865.

## Test Scenarios

- Given a PR whose files pages are 100, 100 and 50 entries with 4 KB patches (first page ~410 KB), when the probe reads it, then the PR counts and no `CANNOT ESTABLISH` is printed (unit).
- Given three full big pages (the PR 9051 shape), when read, then the PR is excluded as oracle-touching (`more than 300 files`) and the window verdict is unchanged (unit).
- Given 250 files with 600-character names (pages of 100, 100, 50), when read, then the exclusion program works from stdin and the PR counts (unit).
- Given two green units of PR 11 (not a draft), when the probe runs, then exactly one timeline and one pull request were issued for it (unit).
- Given the stub gh, when stdout and stderr are captured separately, then stdout begins with the verdict token and stderr has the ordered phase lines (unit).
- Given `SOAK_BUDGET_S=1 SOAK_PARALLEL=1` and 2 s PR-unit jobs reads, when the probe runs, then `truncated=1`, `units_read=4`, the first jobs request is for a `merge_group` run and the exit is 2 (unit).
- Given one failing jobs read among many, when the probe runs, then exit 3 names the lowest failing run id (unit).
- Regression (post-merge live): the probe completes, prints the phase lines, and reports a verdict for the real window; elapsed time is recorded.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- Do not write the literal directory name of the knowledge base inside the probe's code: the dropped-consumer census (`scripts/test-affected-kb-consumers.test.sh`) would read the probe as a consumer. The existing code assembles it (`"knowledge-""base"`); keep that, and keep new prose comments free of the literal path.
- The suite's `OWOUT` merges stderr into stdout (`2>&1`); several existing rows grep it, which is why progress keys avoid their tokens. New stdout/stderr rows must use `ow_probe_split`.
- `SECONDS` has one-second granularity, which is why the first oldest-first dispatch is unconditional and the budget row uses 2 s reads against a 1 s budget (deterministic even on a loaded host); `EPOCHREALTIME` was cut because its radix follows the locale.
- The stub's existing `HANG_<key>` branch answers an EMPTY run list after sleeping: a delayed unit vanishes. Use the new `SLOW_<key>` branch for ordering and budget rows.
- A `continue` inside the new `read_unit` function would be evaluated against the caller's loop; use `return 0`. `$?` after a plain `&` is the launch status: capture the worker's rc inside the backgrounded group.
- The stub gh appends to `GH_LOG` from several background workers: single-line `printf` appends are atomic, so the log stays line-intact; do not add multi-line writes.
- Never run the probe under `bash -x`: it refuses (exit 78) because `GH_TOKEN` would print.
- Standing holds are untouched: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D, no PR3b, no evidence re-run, no flip PR.

## References

- Tracker #10865 (Ref), #10861 (Ref), PR3a #10851 (introduced the probe), existing sweeper per-probe-timeout issue #7923.
- `scripts/followthroughs/ratchet-observation-window-10865.sh`, `plugins/soleur/test/ci-pr-affected-replay.test.sh` (section "ratchet observation window (#10865)"), `scripts/sweep-followthroughs.sh` (output fold at the `exec python3 -I -c "$FT_LAUNCHER"` call, `tail -c 4000`), `.github/workflows/scheduled-followthrough-sweeper.yml` (`timeout-minutes: 15`).
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` ("Reads are bounded and oldest-first"); followthrough convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
- Instrumented measurement copy and call-duration TSV: session scratchpad only (not committed); the figures are recorded above.
