---
title: "A red merge-commit push run is an escape only when a gated job failed; an adopted collect verifies per-idx, not per-key"
date: 2026-11-08
category: workflow-patterns
tags: [ci, followthroughs, soak-probe, escape-classification, ci-pr-affected-replay, fake-gh, fix-round]
related: [scripts/followthroughs/pr-battery-gate-saving-9323.sh, scripts/ci-pr-affected-replay.py, knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md, knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/adoption-note.md]
---

## Problem

Three traps surfaced driving the #9323/#9729 R3 re-ruling pipeline
(`feat-one-shot-9323-escape-r3-rerule`, PR #12439):

1. **Flake-vs-escape.** The #9323 soak probe (`pr-battery-gate-saving-9323.sh`)
   treated ANY red merge-commit ci.yml `push` run on a qualifying PR as an
   ADR-262 R1 escape. R1's escape is *a battery breaking on an undeclared
   path* — a run red solely on non-gated jobs (curl-56 flakes in
   `lint-bot-statuses`/`tenant-integration`) is not that, and counting it
   made the measured ~295 suite-min/run saving unreachable forever.
2. **Resume-dead-sibling collect.** The R3 ruling needs a 300-commit replay
   collect. A dead sibling session left orphaned collect processes still
   writing `/var/tmp/s4-r3-20261108/`; a predecessor session believed the
   sibling fully dead and launched a second 4-chunk restart against the same
   `--out` — the plan-forbidden two-writers configuration — while
   `origin/main` had moved `4fba0d512e` → `404e4c626f` between the two
   rev-lists, shifting the restart's commit window by one.
3. **`--paginate` arg-order.** The fix-round added `--paginate` to the
   probe's jobs read. The suite's fake `gh` reads the endpoint positionally
   (`ep="$2"` right after `api`); a flag placed before the endpoint silently
   becomes the endpoint, every case arm misses, and the probe reports
   `fail`/CANNOT ESTABLISH — an API-failure signature for what is a fixture
   contract break.

## Solution

1. **Classify escapes by failed-job family** (`_pbg_w_esc`, the sole escape
   producer): on red push-run conclusions, read the run's jobs (the third
   read — red-runs only, so `need_min` keeps 2); `escape` iff >=1 failed job
   matches `test-scripts*` (the same prefix the qual arm derives, not a
   second enumeration that can drift); all-failed-outside-gated → `unrelated`
   bucket (echoed on the note line, never counted); unreadable, empty, or
   inconclusive jobs reads → `pending` (NOT YET), never `ok`. The inconclusive
   arm now also covers `conclusion: null` — dropping the `!= null` filter
   surfaces in-flight gated jobs into `pending` instead of vanishing them.
   Detail rides inside the row (`pending <reason>` / `unrelated <detail>`) so
   the note line carries why. The 72-assertion suite pins every arm,
   including cancelled AND null-conclusion gated jobs → NOT YET (added by the
   fix round — the `gated_inc` arm had shipped with no fixture).
2. **Adopt the orphaned collect, verify per-idx.** Proved the two worktrees'
   selector inputs byte-identical (`ci-pr-affected-replay.py`, `test-all.sh`,
   `suite-durations{,-heavy}.tsv`, `suite-shard-legs.tsv`,
   `lib/test-relevance-paths.sh`) so either writer's units are equivalent;
   killed the duplicate restart PGID; kept the original orphaned processes as
   sole writers. Then found the contamination the first key-level scan missed:
   the restart's shifted window appended two `runner-changed` units (idx 3 and
   7 with DIFFERENT shas) — `(kind, sha)` dedupe cannot collide across
   windows and `check_complete` tests idx contiguity, not sha-vs-window, so
   only a per-idx `sha == rev_list(<window-tip>)[idx]` verification catches
   them. Both stale lines removed; full re-verification holds.
3. **Endpoint first, flags after:** `api "repos/.../jobs?per_page=100"
   --paginate --jq ...` — valid real-`gh` syntax AND the only order the
   positional fake tolerates.

## Key Insight

- **A red run is a claim, not an escape.** Classification of a gate-verdict
  input must be relative to the gated family the verdict is about;
  inconclusive evidence degrades to `pending` (fail-safe), never silently to
  `ok` — and never silently to a report-only bucket either: an unreadable
  jobs read pends rather than landing in `unrelated`.
- **"Alive → adopt" of a shared append-only outdir needs two proofs, not
  one:** writer equivalence (byte-identical selector inputs) AND population
  verification against the window the units were computed on. A restart on a
  moved ref produces units with different shas that dodge both `(kind, sha)`
  dedupe and idx-contiguity completeness checks — the valid check is
  per-idx `sha == rev_list(window_tip)[idx]`.
- **Fake-CLIs make the endpoint a positional contract.** Flags placed before
  the endpoint break the fixture silently; the failure signature reads as an
  upstream outage, not a test-harness bug.

## Session Errors

- **Planning subagent bare-root CWD slip** — Recovery: recovered and re-ran
  against the worktree. Prevention: the existing worktree/bare-repo guards
  held; one-off, no new rule.
- **Collision-precheck self-hit on own draft PR #12439** — Recovery:
  identified the flag as this branch's auto-created draft, not a foreign
  change. Prevention: none needed — the precheck's output was correct; the
  interpretation belongs in the reading, not the tool.
- **Plan path mistyped twice** — Recovery: re-read the plan frontmatter for
  the canonical path. Prevention: copy paths from `git status`/`ls` output,
  never retype.
- **technical-ruling-gate initial FAIL on a `pending - assumed:` placeholder
  row** — Recovery: executed the CTO ruling inline (sequential-fallback) and
  recorded it in `decision-challenges.md`; gate then PASSed with 3 rows.
  Prevention: the mechanism worked as designed — a pending row is a stop
  line, not a skip.
- **Duplicate R3 collect restart on the same `--out` (~22:08 UTC,
  predecessor session)** — Recovery: Phase-0 inventory found both writer sets
  alive; killed the restart PGID before it collided. Prevention: run the
  adopt-or-restart INVENTORY before believing "the sibling is dead" —
  orphaned-to-systemd processes keep writing after the session dies.
- **Stale-window units survived the first (key-level) dedupe scan** —
  Recovery: deeper per-idx verification found idx 3 and 7 duplicated with
  different shas; both removed; re-verified all four files. Prevention:
  verify adopted/replayed populations per-idx against the computed window —
  `sha == rev_list(<window-tip>)[idx]` — never by key-dedupe or idx
  contiguity alone.
- **`gated_inc` (inconclusive-gated → pending) arm shipped with no fixture** —
  Recovery: fix-round added cancelled- and null-conclusion gated-job rows
  (e4b0f15858, suite 69→72). Prevention: when a classifier arm's reachable
  inputs change (here, dropping `!= null` made null-conclusion jobs newly
  reachable into the arm), pin the arm — a verdict bucket with no fixture is
  a comment.
- **`edit` old_string byte-mismatch on the test file** — Recovery: re-read
  the exact bytes with `cat -A` (the printf's literal `\n` was omitted from
  the match string). Prevention: for edits into `printf`-heavy fixture code,
  match on a shorter unique substring.
- **`--affected` gate capacity-contended by a sibling worktree run** —
  Recovery: read `test-all.sh --capacity` first per the #9505 learning and
  relied on the targeted suite rather than queueing behind the sibling's
  lock. Prevention: covered — `--capacity` verdict exists precisely for this;
  read it before any `--affected` run when siblings are live.

## Prevention (standing)

- Two writers on one shared `--out` collect dir is the forbidden
  configuration; a session that "believes the sibling dead" has not inventoried.
- A verdict bucket with no fixture row is a comment, not a contract — pin
  every classifier arm, especially the fail-safe ones (`pending`), which a
  green suite structurally cannot exercise.
