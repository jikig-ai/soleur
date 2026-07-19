---
title: "fix: GitHub community-monitor collector data gaps (E2BIG + stderr poisoning + fabricated stats)"
date: 2026-07-19
type: fix
lane: cross-domain
issue: 6695
brand_survival_threshold: none
status: draft
revision: v2 (post plan-review — scope cut ~55%; see Review Reconciliation)
---

# fix: GitHub community-monitor collector data gaps

Ref #6695 (scheduled digest issue — reference, do not auto-close; its Discord/X/Bluesky/
LinkedIn/HN content is unrelated to this fix).

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No
> `knowledge-base/project/specs/feat-one-shot-6695-github-collector-data-gaps/` directory exists.

> **Citation convention:** this plan cites **content anchors**, not line numbers
> (`cq-cite-content-anchor-not-line-number`). v1 already carried two drifted line cites.

## Overview

Three reported failures, all reproduced live. The fix is small and mechanical:
**two `--argjson` call sites, one `2>&1`, and one prompt contradiction.**

### Root causes (reproduced at the *production* configuration)

The cron invokes every GitHub subcommand with **`days=1`** (`cron-community-monitor.ts`,
anchor `bash plugins/soleur/skills/community/scripts/community-router.sh github activity 1`),
daily at 08:00 UTC. All measurements below are at `days=1`.

| # | Defect | Mechanism | Evidence |
|---|---|---|---|
| RC1 | `activity` + `contributors` die with "Argument list too long" | jq `--argjson` places the whole payload in **one `execve` argument**. The binding limit is **`MAX_ARG_STRLEN` = 131,072 B *per argument*** (32 × 4096-B pages) — **not** `ARG_MAX` (2,097,152 B) | Bisected: 131,071 → OK, 131,072 → E2BIG. At `days=1`: commits = **142,236 B** in one arg (only **10 items**); issues = **448,247 B** (**56 items**) |
| RC2 | `repo-stats` "stargazer parse error" | `cmd_repo_stats` pipes `gh api … 2>&1` into `jq -s`, merging **stderr into the JSON stream**; any stderr byte poisons the parse | `( echo '[{"a":1}]'; echo noise >&2 ) 2>&1 \| jq -s 'add // []'` → `parse error`, exit **5** |
| RC3 | Digest printed stale stars/forks/watchers "(stale)" and claimed a 41-day period | **No code or prose authorizes either.** The script exits loudly; the LLM filled a *mandatory* table from a 6-week-old digest and invented a period | Prompt anchor `The ## GitHub Activity section must include` has no failure clause; LinkedIn's `To distinguish` anchor does. Anchor `If any command in a batch fails, log the error and continue.` grants the standing permission |

**RC1 is driven by per-object payload size, not item count** — 10 commits already breach the
128 KB per-argument ceiling. That is why the failure is deterministic and recurring
(16 digests mention a GitHub gap), and why item-count pagination is orthogonal to it.

## Review Reconciliation — v1 → v2

Plan review (advisor + simplicity + correctness panels) overturned v1's central scope
argument. Each finding below was **independently verified** before being accepted or rejected.

| v1 claim | Verification | v2 response |
|---|---|---|
| "A jq-only fix yields a silent 87 % undercount (100 vs 768 commits)" — used to justify adding pagination | **Wrong.** The 768/741 figures were measured at `days=41`; production is `days=1`, where the endpoints return **10 commits / 56 issues / 14 in-window PRs** — all far under the 100 cap. v1's own `days=1` measurement showed 10 and 56 and was not reconciled | **RC4 (full pagination) cut.** Replaced by a 3-line cap-detection guard (D2) that makes a *future* truncation loud instead of engineering around one that does not occur |
| "Raise `days` from 1" (RC5) | **Wrong and self-contradictory.** `days=1` is correct for a daily cron. The 41-day claim is RC3's fabrication class, not config drift. v1 named no target value because none is defensible | **RC5 cut.** Replaced by D4b: the digest must echo `period_days` from collector JSON instead of inventing a window |
| AC3: `grep -c '2>&1'` → **0** | **Unachievable and harmful.** True count is **9**; two are legitimate `>/dev/null 2>&1` discard idioms in `validate_gh`, and the `cmd_discussions` site is load-bearing for its graceful "Discussions not enabled" path | Rewritten as a form-anchored AC scoped to the actual defect shape (`gh api … 2>&1` feeding a pipe). **Only the `repo-stats` site changes** |
| "Sweep `2>&1` → `2>/dev/null` at 7 sites" | **Would destroy every error message.** Those sites use the captured stderr as the diagnostic (`$(echo "$issues" \| head -c 200)`), and it directly contradicts D3's `…_CAUSE=` requirement | **Separate-stderr-tempfile shape (D3)** adopted and stated explicitly. Note this means Precedent A is *not* lifted verbatim — it throws stderr away, a defect to fix while lifting |
| "Tests stub `gh` per `make_gh_stub`" | **Unusable.** `test-helpers.sh` `make_gh_stub` handles **only `gh run list`**; every `gh api`/`gh auth status` call hits its `exit 1`. v1's Phase 0 precondition was vacuous | New `make_gh_api_stub` is an explicit **deliverable** in Files to Edit |
| D1 `--slurpfile` is a drop-in swap | **Not a drop-in.** `--slurpfile x f` wraps file contents in an array, so `$x` is `[[…]]` and every `$issues[]` / `$commits[]` reference must become `$issues[0][]` | Unwrapping shape pinned explicitly (D1) |
| D5 layer 3 "wire `reportSilentFallback`" | **Vague; collector runs in the agent sandbox**, so its exit code never reaches the handler. But a signal path *does* exist that v1 missed | Rebuilt on the **existing** `resolveOutputAwareOk` verify-output step (D5) |
| AC2 expected output ("`$repo`, `$since`, `$days` scalars") | **Wrong** — `$repo`/`$since` use `--arg`, not `--argjson` | AC rewritten as a mechanical count |
| v1 line-number cites for the prompt (`:205-208`, `:214-216`) | **Already drifted** — actual anchors are at 202 and 212 | All cites converted to content anchors |
| AC2 regex won't match continuation lines | **Rejected — the regex is correct.** `grep -nE '^\s*--argjson'` matches all 7 sites (4-space indent). Portability note adopted: use `^[[:space:]]*` | Kept, with the POSIX class |
| Auto-glob claim, all seven `2>&1` line numbers, Precedent A, latent `rm -f` leak, D-shape assertion precedent, router passthrough | **All verified correct** | Retained |

## Verified design decisions

**D1 — `--slurpfile` over `--argjson`, with the unwrapping shape pinned.** Verified to 10 MB
(`jq-1.8.1`). Reads via a file descriptor, so no `execve` argument is involved and the 128 KB
ceiling does not apply. **`--slurpfile x f` wraps the file's contents in an array**, so the jq
program must dereference `$x[0]`, or the file must be written pre-merged. Choose one shape and
apply it consistently — every `$issues[]`, `$prs[]`, `$commits[]`, `$stargazers[]` reference in
the affected jq programs changes. Getting this wrong yields a silent `count: 1`.

**D2 — Cap detection, not pagination.** Full pagination is unjustified (see Review
Reconciliation). But the 100-item cap is a *latent* silent undercount if the repo grows or a
run covers a longer window. Cheapest honest treatment: after each fetch, if the response
returns **exactly `per_page` items**, emit a truncation warning on stderr rather than silently
reporting a capped number. ~3 lines; converts a latent silent undercount into a loud signal
without a paging loop, a sort-order invariant, or a magic backstop constant.

**D3 — Separate stderr capture (supersedes a blanket `2>&1` sweep).** The defect is *stderr
merged into a JSON pipe*, not stderr capture per se. Fix the shape, preserving diagnostics:

```bash
if ! gh api "…" >"$out" 2>"$err"; then
  echo "GITHUB_COLLECTOR_CAUSE=$(head -c 200 "$err" | tr '\n' ' ')" >&2
```

**Only the `repo-stats` stargazer site changes.** The `validate_gh` `>/dev/null 2>&1` idioms
and the `cmd_discussions` error-classification capture are correct and stay. Note Precedent A
(`cmd_fetch_interactions`) discards stderr and prints a contentless error — lifting it verbatim
would propagate a diagnosability defect, so it is lifted *with* this improvement.

**D4 — Fix RC3 at the prompt layer, where the defect actually lives.**
(a) Give the GitHub section a failure clause mirroring the LinkedIn one that demonstrably
works (anchor `To distinguish`): require `collection failed: <reason>` and **forbid
carry-forward from a prior digest**.
(b) Require `period_days` to be stated **from the collector JSON**, never inferred.
(c) **Amend the standing permission** (anchor `If any command in a batch fails, log the error
and continue.`). Appending a failure clause without amending this leaves two contradictory
instructions and the LLM will keep resolving toward the vaguer one — the single most likely
way this fix silently fails.

**D5 — Monitored signal via the *existing* output-aware heartbeat.** The collector runs inside
the agent sandbox, so its exit code cannot reach the handler directly. The reachable path is
the already-wired `verify-output` step, which calls `resolveOutputAwareOk({ spawnOk, stdoutTail,
stderrTail, exitCode, … })` under `SENTRY_MONITOR_SLUG = "scheduled-community-monitor"`.
Treat a digest containing `collection failed:` as a non-ok output condition so it mirrors to
Sentry through the existing `reportSilentFallback` import. **Phase 0 must confirm the exact
extension point** before this is implemented — this is the one design decision resting on a
mechanism not yet read end-to-end.

**D6 — Shape assertion before emit.** Adopt the `linkedin-community.sh` precedent (anchor
`Shape validation BEFORE any`): assert `(.stargazers_count | type) == "number"` on `$repo_data`
so an error body can never render as a plausible number. ~6 lines.

**D7 — `trap`-based tempfile cleanup.** During planning `/tmp` hit 100 % (4 GB) and broke tool
output: **9,470 leaked `mktemp` files (1.9 GB)** from `workspaces-luks-freeze.test.sh` —
unrelated to #6695, but a first-hand demonstration. `cmd_fetch_interactions` has the same
latent flaw (`rm -f` on success paths only, no trap; under `set -e` a jq failure skips
cleanup). Every tempfile uses `trap 'rm -f …' EXIT`; the existing site is fixed while in the file.

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/skills/community/scripts/github-community.sh` | RC1: tempfile + `--slurpfile` at the **5 unbounded bindings** — `issues`+`prs` (`cmd_activity`), `commits`+`issues` (`cmd_contributors`), `stargazers` (`cmd_repo_stats`) (D1). RC2: separate-stderr shape at the **stargazer fetch only** (D3). D2 cap detection, D6 shape assertion, D7 traps (incl. the existing `cmd_fetch_interactions` leak). `repo_data` + `days` stay `--argjson` (bounded) |
| `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` | D4a/b/c prompt edits at the three content anchors; D5 output-aware failure signal |
| `plugins/soleur/test/test-helpers.sh` | **New `make_gh_api_stub`** — dispatches on `$1 == "api"` by URL substring, handles `auth status` → exit 0, supports a stderr-emitting mode. Shared by ~21 suites, so additive only |

## Files to Create

| File | Purpose |
|---|---|
| `plugins/soleur/skills/community/test/github-community.test.sh` | Regression suite. Auto-globbed by `scripts/test-all.sh` (`plugins/soleur/skills/*/test/*.test.sh` in the `want_scripts` loop) — **verified, no manual registration** |

## Implementation Phases

Ordered by dependency: the script contract lands before its consumers.

### Phase 0 — Preconditions (verify, do not assume)

- Confirm `jq --version` ≥ 1.6 supports `--slurpfile` (verified `jq-1.8.1` locally).
- **Confirm the D5 extension point** by reading `resolveOutputAwareOk` end-to-end. If it cannot
  express "digest contains a failure marker", fall back to an explicit `reportSilentFallback`
  call in the persistence step and record the deviation. *This is the plan's one unread mechanism.*
- Re-run the RC1 and RC2 repros to establish a RED baseline before changing anything.

### Phase 1 — RED: regression tests first (`cq-write-failing-tests-before`)

Build `make_gh_api_stub`, then write three cases (fixtures **synthesized**, never captured —
`cq-test-fixtures-synthesized-only`). Set `TMPDIR` to a **private per-test directory** so the
cleanup assertions cannot false-fail on a shared `/tmp` (the D7 anecdote is exactly this hazard).

1. **Large payload (RC1)** — stub a single JSON argument exceeding **131,072 B**. Assert exit 0
   and a correct item count. *Fails today with "Argument list too long."*
   Trailing `assert_file_not_exists` on the private `TMPDIR` covers D7 cleanup.
2. **stderr noise on the stargazer path (RC2)** — stub valid JSON on stdout **and** noise on
   stderr. Assert `repo-stats` parses, and that the diagnostic still carries the cause (D3).
   *Fails today with `parse error`.* Trailing cleanup assertion here too.
3. **No fabricated stat (RC3/D6)** — stub an error body. Assert non-zero exit and that **no
   numeric `stargazers_count` is emitted**.

Per `cq-assert-anchor-not-bare-token`, anchor on call-form/`^[[:space:]]*` and mutation-test
each assertion. **Mutation-testing happens at the end of Phase 2**, once there is a fix to break.

### Phase 2 — GREEN: script fixes

Apply D1, D2, D3, D6, D7 to `github-community.sh`. Then mutation-test the Phase 1 assertions.

### Phase 3 — Consumer wiring (after the contract exists)

`cron-community-monitor.ts`: D4a/b/c prompt edits (all three anchors — the amendment to the
standing permission is not optional), then the D5 signal.

### Phase 4 — Verify

Run all five subcommands against `jikig-ai/soleur` at `days=1` and confirm each returns real
data. Confirm `bash scripts/test-all.sh` (`TEST_GROUP=scripts`) is green.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `github activity 1`, `contributors 1`, `repo-stats 1` each exit 0 against the live
  repo and emit non-empty JSON. *(All three fail today.)*
- **AC2** No `--argjson` receives an unbounded payload. The five unbounded bindings
  (`issues` ×2, `prs`, `commits`, `stargazers`) must use `--slurpfile`; the two **bounded**
  ones may remain `--argjson` (`days`, a scalar; `repo_data`, a single repo object measured at
  **7,013 B** against the 131,072 B ceiling). Verify:

  ```bash
  S=plugins/soleur/skills/community/scripts/github-community.sh
  grep -cE '^[[:space:]]*--argjson (issues|prs|commits|stargazers)' "$S"   # 5 today -> 0
  grep -c -- '--slurpfile' "$S"                                            # 0 today -> 5
  ```

  *Executed at plan time: **5** and **0** respectively.* Do **not** assert a bare
  `grep -c -- '--argjson'` total — `repo_data` and `days` are legitimately bounded, so a
  fixed total would false-fail a correct implementation. (`$repo`/`$since` use `--arg` and are
  unaffected either way.)
- **AC3** No `gh api` call merges stderr into a pipe feeding `jq`. The defect **spans three
  lines**, so a line-oriented grep cannot see it — the check must be multiline-aware. Verify:

  ```bash
  grep -Pzoc '(?s)gh api[^)]*?2>&1[^)]*?\| *jq' \
    plugins/soleur/skills/community/scripts/github-community.sh   # 1 today -> 0 after fix
  ```

  *Executed at plan time: returns **1**, matching only the stargazer site.* (Requires GNU
  `grep -P`; the portable fallback is
  `awk '/stargazers=\$\(gh api/,/jq -s/' "$S" | grep -c '2>&1'`, also verified → **1**.)

  **Counter-assertions — these must NOT change** (a naive `grep -c '2>&1' → 0` sweep would
  break all of them; v1 prescribed exactly that):
  - `grep -c '>/dev/null 2>&1' …` → **2** (the `validate_gh` discard idioms, lines 21/27).
  - `cmd_discussions`' `2>&1` error-classification capture still present (see AC4).
  - The five `gh api … 2>&1` variable captures at the `issues`/`prs`/`commits`/`repo_data`
    sites still present — they are the error *diagnostic*, not the defect.
- **AC4** `cmd_discussions` still returns its graceful `{"discussions": []}` payload (exit 0)
  for a repo without Discussions — proves the sweep did not regress it.
- **AC5** On a stubbed fetch failure, the script exits non-zero **and** the diagnostic carries a
  non-empty cause (not `Error: … ()`) — proves D3 preserved diagnosability.
- **AC6** No fabricated stat: on a stubbed error body, output contains no numeric
  `stargazers_count`.
- **AC7 (D2)** When a fetch returns exactly `per_page` items, a truncation warning is emitted on
  stderr.
- **AC8 (D4)** The prompt contains a GitHub collection-failure clause **and** the standing
  permission is amended. Verify by grepping for the **guardrail's presence** at the content
  anchors — not for the absence of the old text (an absence-grep false-fails on a file that
  legitimately quotes the phrase).
- **AC9** `bash scripts/test-all.sh` runs `github-community.test.sh` and it passes; each case
  verified to fail against pre-fix code.
- **AC10** No tempfile residue in the private per-test `TMPDIR`, including on failure paths.
- **AC11** PR body uses `Ref #6695`, **not** `Closes` — #6695 is a scheduled digest whose other
  content is unrelated (`wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

None. All verification is automatable in-session (live `gh` calls + the shell suite).

## Observability

```yaml
liveness_signal:
  what: scheduled-community-monitor Sentry check-in via the existing resolveOutputAwareOk verify-output step
  cadence: daily 08:00 UTC
  alert_target: Sentry Crons — existing monitor (SENTRY_MONITOR_SLUG)
  configured_in: apps/web-platform/server/inngest/functions/cron-community-monitor.ts
error_reporting:
  destination: Sentry via the existing reportSilentFallback import, reached through the output-aware heartbeat (D5)
  fail_loud: true — script exits non-zero with a cause; prompt forbids substituting or carrying forward a value
failure_modes:
  - mode: GitHub fetch fails (rate limit, auth, 5xx)
    detection: non-zero exit + GITHUB_COLLECTOR_CAUSE= on stderr
    alert_route: digest records "collection failed" -> output-aware heartbeat -> Sentry
  - mode: Digest states a stat the collector did not produce (the RC3 class)
    detection: prompt requires "collection failed: <reason>" and forbids carry-forward; period_days echoed from collector JSON
    alert_route: same output-aware heartbeat — no longer only a human-read digest footnote
  - mode: A fetch is silently capped at per_page (latent, not present-tense)
    detection: D2 cap-detection warning when a response returns exactly per_page items
    alert_route: stderr -> digest -> heartbeat; regression test AC7
logs:
  where: Inngest run logs + Sentry breadcrumbs
  retention: per existing Sentry/Inngest retention
discoverability_test:
  command: "bash plugins/soleur/skills/community/scripts/community-router.sh github repo-stats 1; echo exit=$?"
  expected_output: "exit=0 with a numeric stargazers_count, OR non-zero with GITHUB_COLLECTOR_CAUSE= on stderr — never a number without a successful fetch"
```

No SSH is required for any verification step (`hr-no-ssh-fallback-in-runbooks`).

## User-Brand Impact

**If this lands broken, the user experiences:** a community digest stating confident, wrong
growth numbers — stars carried forward from a six-week-old digest and presented as current,
under a period the digest invented. The operator makes positioning and prioritization calls on
fabricated traction data.

**If this leaks, the user's data is exposed via:** no new exposure. The collector reads only
public repository metadata through already-granted `gh` auth. No new data category, destination,
or retention is introduced.

**Brand-survival threshold:** `none` — internal operator reporting, no external surface, no
customer data. No sensitive path is touched, so no scope-out bullet is required.

## Domain Review

**Domains relevant:** Engineering, Support

### Engineering

**Status:** reviewed
**Assessment:** Bug fix on an existing, already-provisioned surface. No new infrastructure,
dependency, or schema. The chief risk identified at v1 was *over*-fixing: a `2>&1` sweep and a
pagination loop that would have regressed `cmd_discussions` and added a sort-order invariant for
a defect that does not occur at the production window. v2 cuts both. The remaining diff is two
`--argjson` sites, one `2>&1`, three prompt anchors, and a test helper.

### Support

**Status:** reviewed
**Assessment:** Directly improves the community-monitor digest (CCO surface). The behavioral
change operators will notice: the digest will sometimes say "collection failed" instead of
showing a number. That is the intended outcome — an honest gap is more useful than a confident
fabrication, and it is what makes the next failure self-report.

### Product/UX Gate

Not applicable — no UI surface in Files to Edit/Create; the mechanical UI-surface override did
not fire (shell + server-side TS only).

## Architecture Decision (ADR/C4)

**Not required.** A bug fix on an existing surface: no ownership/tenancy boundary move, no new
substrate or integration pattern, no resolver/dispatch/trust boundary change, no divergence from
an existing ADR.

**C4 completeness check.** All three model files (`model.c4`, `views.c4`, `spec.c4`) were
considered against this change's external actors and systems. It introduces no new external
human actor, no new external system or vendor (GitHub is already the data source being read), no
new container or data store, and no changed actor↔surface access relationship. No `.c4` edit is
in scope.

## GDPR / Compliance

Considered and **not triggered**. The canonical regulated-surface regex does not match (no
schema, migration, auth flow, API route, or `.sql` file). None of the four expansion triggers
fire: no new LLM/external-API processing of operator-session data (the digest LLM already reads
this), threshold is `none`, no new cron reads `learnings/`/`specs/`, no new distribution surface.
v2 *reduces* data volume versus v1 by cutting pagination.

## Open Code-Review Overlap

**None.** Queried 61 open `code-review` issues; none reference `github-community.sh`,
`cron-community-monitor.ts`, or `community-router.sh`.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `--slurpfile` array-wrapping silently yields `count: 1` | D1 pins the unwrapping shape; AC1 asserts non-empty JSON with correct counts; RED test 1 asserts an exact item count |
| The `2>&1` fix regresses `cmd_discussions` or `validate_gh` | Only the stargazer site changes; AC3 asserts both survivors are still present; AC4 asserts the graceful path still works |
| D5's extension point is not yet read end-to-end | Phase 0 gates on reading it, with a named fallback (explicit `reportSilentFallback` in the persistence step) and a recorded deviation |
| The prompt's standing permission keeps overriding the new clause | D4c amends it directly; AC8 asserts the guardrail's presence |
| More "collection failed" lines in digests | Intended. An honest gap beats a confident fabrication — this is the fix, not a regression |
| Tempfiles leak on failure paths | `trap … EXIT` everywhere; AC10 asserts zero residue in a private `TMPDIR`, including forced-failure runs |

## Out of Scope (tracked separately)

- **`/tmp` leak in `apps/web-platform/infra/workspaces-luks-freeze.test.sh`** — 9,470 leaked
  `mktemp` files (1.9 GB) filled the 4 GB tmpfs during this planning session. Unrelated to #6695
  (introduced around `ca85c30bc`). **File a separate issue** labelled `bug`,
  `domain/engineering`, `priority/p2-medium` (all verified to exist). Reclaimed in-session by
  deleting entries untouched for >60 min; the missing-`trap` defect remains.
- **Why the cron produced no committed digest for 41 days** (newest committed digest is
  `2026-06-08`). The 41-day gap is an *availability* question, not a collector bug — `days=1` is
  correct for a daily cadence. Worth its own issue; D4b at least makes the resulting window honest.
- `github discussions` — not reported as failing, and its `2>&1` is load-bearing. Untouched.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **The binding limit is `MAX_ARG_STRLEN` (131,072 B *per argument*), not `ARG_MAX`
  (2,097,152 B).** A fixture sized against `ARG_MAX` would be 16× larger than needed and would
  obscure which limit is under test. RC1 fires on **10 commits** — it is driven by per-object
  payload size, not item count.
- **`--slurpfile` is not a drop-in for `--argjson`.** It wraps file contents in an array, so
  `$x` becomes `[[…]]` and every `$issues[]`-style reference must be rewritten. Get this wrong
  and the jq program silently emits `count: 1` — green exit, wrong data.
- **Do not sweep `2>&1` globally.** Of 9 occurrences, exactly **one** is the defect. Two are
  `>/dev/null 2>&1` discard idioms in `validate_gh`; the `cmd_discussions` capture is
  load-bearing for its graceful "Discussions not enabled" path (discarding it converts graceful
  degradation into a hard `exit 1`); and five others *are* the error diagnostic — discarding
  them yields `Error: Failed to fetch issues ()` and contradicts the `…_CAUSE=` requirement.
- **`make_gh_stub` handles only `gh run list`.** Every `gh api` / `gh auth status` call hits its
  `exit 1` branch. A precondition that merely checks the helper *exists* is vacuous — the
  `gh api` stub is a deliverable, not a reuse.
- **Measure at the configuration that actually runs.** v1's headline "-87 % undercount" was
  measured at `days=41` while production runs `days=1`; at `days=1` the endpoints return 10/56/14
  items and no truncation occurs. The error survived into a whole scope decision (pagination +
  a `days` change) because the `days=1` numbers were collected but never reconciled against the
  claim they contradicted.
- **A prompt fix must amend the contradicting instruction, not just append to it.** The standing
  `If any command in a batch fails, log the error and continue.` is what the LLM uses to omit the
  GitHub section; adding a failure clause elsewhere leaves two contradictory instructions and the
  vaguer one tends to win.
- `jq -s 'add // []'` on stderr-poisoned input exits **5** (not 0) and `set -o pipefail` *does*
  catch it — so `cmd_repo_stats` already fails loudly. Any claim that the script silently
  degrades to `[]` is wrong; the stale numbers come from the LLM, which is why the RC3 fix lives
  at the prompt layer, not in the script.
