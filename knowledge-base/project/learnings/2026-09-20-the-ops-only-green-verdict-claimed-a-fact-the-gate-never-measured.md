---
title: "The op's only green verdict claimed a fact the gate never measured, and five of its refusals were never rendered"
date: 2026-09-20
category: test-failures
tags: [review, dark-gate, cutover-inngest, mutation-testing, anti-vacuity, runbook, ci-paths, observability]
issue: 8079
pr: 8426
related:
  - knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md
  - knowledge-base/project/learnings/2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md
  - knowledge-base/project/learnings/2026-08-20-every-guard-i-fixed-was-narrower-than-the-claim-it-carried.md
  - knowledge-base/project/learnings/2026-09-18-the-gate-that-caught-it-was-the-one-suite-i-had-no-reason-to-run.md
---

# The op's only green verdict claimed a fact the gate never measured, and five of its refusals were never rendered

## Problem

PR #8426 routed `op=registry-probe`'s non-200 branch through `inngest_execute_registry_gate`,
mirroring the op=execute 2.0 arm. It arrived at review with 726/726 on a suite carrying seven
range-scoped mutation rows, sixteen renders, a plumbing-parity guard and a consumer census, twelve
commits deep, plan + deepen-plan + a five-reviewer panel behind it. Ten review seats and a coverage
consult found 27 defects; all were fixed inline. Four of them were in the one place every prior
phase had looked hardest.

**The green verdict was the false one.** `dark` — the op's only exit-0 host-state outcome — said
"nothing can have registered against 10.0.1.40 since boot `<id>` — its inngest-server has not been
bound on this boot." The plan's own premise correction says `dark` is reachable post-cutover only
after `op=rollback`. `op=rollback` is `systemctl stop`: same `boot_id`, after ~70 functions had
registered on that boot, and those registrations persist in the durable backend. E9–E14 establish
"not serving as of the newest row, flag pre-arm on the heartbeat, no FSM transition since" — a
statement about an INTERVAL. The message made it a statement about a BOOT. The 2.0 twin's wording
("no registry can double-fire from a host that cannot start") is forward-looking and survives;
copying its epistemics into a backward-looking diagnostic did not. Two seats converged on it; the
plan had carried the sentence verbatim in D2.

**Five refusal tokens had no render, and the two floors standing in for them had one line of
slack.** `host_serving`, `wrong_host`, `stale_row`, `stale_schema`, `flag_unreadable` (both cells),
`unreadable`/`fsm_unreadable` at rc 0 and the heartbeat read-failure leg were pinned only by
`_probe_case_exits >= 10` (actual 15) and `no-SSH lines >= exit-1 lines` (16 vs 15). Measured:
`host_serving)` could drop its `exit 1` — a REFUSED that then exits 0 — at 726/726; the heartbeat
leg's `_bs_read_remedy` step operand could revert to `2.0`; the E11 `flag_unreadable` message could
quote the heartbeat's age for the hourly row (the exact wrong-sample class D8 had fixed for
`flag_armed`). Three of those five unrendered messages were also the untruthful ones (`host_serving`
blamed the webhook path inside the branch that had already proved the path answered; `wrong_host`
said "the host is not the problem" where a dead host absent > 24 h lands).

**AC9 pinned the 200 path against `git show origin/main`** — one screen below the suite's own AC7
comment explaining why that is `main == main` after merge. With HEAD standing in for main it
measured 725/726: the restructured arm's outer `fi` lands in one extraction and not the other. It
would have turned `main` red on the first post-merge CI run.

**The suite could not run on the PR shape every remedy edit takes.** `infra-validation.yml`'s path
filter listed `.github/workflows/cutover-inngest.yml` (the body's home before ADR-150) and none of
the three files the suite has read since. An arm-only PR skipped its own guard; this one ran it
only because it also touched the suite file. No seat found this — it came from the coverage
consult's "which class is ABSENT" question.

**The runbook's read recipe could not match a real run.** `grep -E '::notice::registry-probe'`
returns nothing from `gh run view --log`, which renders workflow commands as `##[notice]`; measured
0 lines on a run that printed both a notice and a warning. Five seats found it. Two pre-existing
sibling recipes had the same defect.

## Solution

- Every message says what E9–E14 establish. `dark` names its interval and carries the same-boot
  rollback caveat; a render row bans `since boot` / `has not been bound on this boot`.
- Every token has a render (fixture = H5 with one substitution; the stub at the `doppler` process
  boundary gained eight modes); the aggregates are one per-arm row over tokens + `*)` requiring
  `exit 1` AND the no-SSH sentence in each body.
- AC9 is a verbatim heredoc pin. The census counts occurrences (`grep -o | wc -l`), not lines.
  The echo-arg emptier refuses to empty a string carrying `$(` or a backtick. Both region markers
  are asserted exactly-once and the end marker must be the arm's last line before `;;`.
- The Guard Contract's mutation matrix went from 7 of 17 rows to all of them plus the three
  survivors and H2/H3. `mutate_file` fails its row on a sed parse error instead of killing the suite.
- `infra-validation.yml` lists `scripts/cutover-inngest.sh`, the gate lib and the read classifier.
- Runbook: `grep -F 'registry-probe'`; the group's in-flight read lists the group's own workflows;
  P1-6 gated pre-arm only (post-cutover `registry_empty=false` is the healthy state and the
  section's remedy replaces the production scheduler host).
- The plan's `discoverability_test` is a block scalar anchored on the assignment form (the inline
  form failed Check 10 both as parsed and as intended — the arm's own comment sat inside the awk range).

## Key Insight

**A verdict's MESSAGE is a claim about the system, and the green one is the least-read.** Every
gate in the pipeline aims at claims that license an ACTION; a `dark` notice at exit 0 licenses
nothing, so no instrument pointed at it — and it was the one sentence copied from a sibling whose
epistemics differed. Ask of each verdict message: *which predicates in the gate establish this
sentence, and over what interval?* If the answer is "none, it is inherited", it is prose.

**An aggregate floor over a heterogeneous case body pins the count, never the member.** `>= 10
exit 1` over 15 arms is five deletable exits. The per-arm form costs the same number of lines.

**A path filter is a claim about which files a suite reads, and it goes stale the moment the
suite's inputs move.** After an extraction (ADR-150 moved the body out of the workflow), grep the
suite for the files it opens and diff that list against the filter.

## Session Errors

1. **`bash $H` with `H` unset hung a Bash call for 120 s** — `bash` with no argument reads stdin.
   Recovery: TaskStop, re-run with the path inline. **Prevention:** never rely on a variable set in
   a previous Bash call; the shell does not persist.
2. **`grep -qE "$5"` inside `assert`'s eval read assert's own `$5`** — every per-token render row
   went red with `unbound variable`. Recovery: bind the ERE to a local (`_rr_re`) the eval reads by
   dynamic scoping. **Prevention:** an eval'd condition sees the CALLEE's positionals; pass helper
   arguments through named locals.
3. **`sed 'RANGE/pat/d'` without braces is a parse error** and, inside `mutate_file` under `set -e`,
   it killed the suite with no Results line and no floor verdict. Recovery: `RANGE{/pat/d}`, and
   `mutate_file` now FAILs the row on a bad expression. **Prevention:** a harness helper that
   executes an operator-supplied expression must convert the expression's own failure into a row
   verdict — a dead suite is indistinguishable from a passing one to a reader of the last line.
4. **A sed that APPENDS a line has zero `<` diff lines**, so `mutate_file`'s exactly-one-`<`
   guard refuses it; a rename that keeps the grepped substring (`…_gatex`) does not redden a
   substring census. Recovery: replace the arm's first comment line; rename inside the name.
   **Prevention:** read the landing guard's diff direction before writing the mutation.
5. **The M2.6 mutant survived one run in three** — the four headlines interpolate the row age, and
   two renders straddling a second boundary print `421s`/`422s`, making a collapsed 2x2 count as
   four distinct. Recovery: normalise `[0-9]+s old` before `sort -u`. **Prevention:** a
   distinct-count over text that carries a clock-derived value is a flake in the SURVIVE direction;
   strip the clock first.
6. **Three anchor misfires in new rows**: an entry-point grep for `_erg_` matched 2.0's `_erg_line`
   loop variable; an AC10 denylist entry `RPG_DIR` matched the `RPG_DIR=$(mktemp …)` assignment line
   (which carries the guard echo); a fixture assertion grepped `"host":"web-1"` in JSON-escaped raw.
   Recovery: name the call forms; require the `$` expansion; read the field through `jq`.
   **Prevention:** run every new negative anchor against the pristine tree before trusting its
   verdict — the first three all fired on the correct code.
7. **`lint-shell-capture-exit` rejected a new `n=$(… | wc -l)`** whose pipeline can legitimately
   exit non-zero. Recovery: `|| true` and a defaulted read. **Prevention:** already ruled — run the
   repo-global ratchets by hand after each guard-shaped commit; they reference no changed file.
8. **Forwarded from the pre-compaction half of the session** (#8369/#8386/#8079 work): the filing
   gate refused `gh issue create` twice (milestone, then label, then a body file outside the repo);
   the brief's claim that BETTERSTACK_QUERY_* were GitHub-only was false (Doppler prd_terraform);
   the brief's `"available: …"` ledger value was schema-invalid (bare `available`); an unfiltered
   Better Stack query mixed web-1 rows into a false P1; "It does not close #8386" still linked via
   `closingIssuesReferences`; a commit was silently rejected by markdown-lint and `push` said
   up-to-date; `COMMIT_RC` captured `tail`'s status; `printf | grep -q` / `git show | awk exit` /
   `| head -1 | grep -q` SIGPIPEd under pipefail three times; assertions matched their own
   comments; a `FAIL` filter excluding "expected" hid "expected exactly 1"; four stop-hook
   interventions for closing text that named an untaken action. **Prevention:** each is documented
   in its own learning; the recurring one is the last — end a pipeline turn with the next skill
   INVOKED, not named.
9. **The ship-time incident-PIR gate fired on this PR** (`INCIDENT-SIGNAL: yes`) because the plan
   and body say "production outage" while describing the event class the diagnostic serves; no
   event occurred. Recovery: declared it in the PR body as preventive and filed nothing — a PIR for a
   non-event is a fabricated record. **Prevention:** the #6813 false-positive class; a diagnostic
   whose subject is outages will always trip a vocabulary gate, so state "no live event took place"
   in the body up front rather than after the gate names it.

## Tags

category: test-failures
module: scripts/cutover-inngest.sh, apps/web-platform/infra/cutover-inngest-workflow.test.sh, .github/workflows/infra-validation.yml, knowledge-base/engineering/operations/runbooks/inngest-server.md
