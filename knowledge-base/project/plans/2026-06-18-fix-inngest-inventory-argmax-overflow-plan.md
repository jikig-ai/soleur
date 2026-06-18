---
title: "fix(inngest): op=inventory eventsV2 accumulation overflows ARG_MAX (jq --argjson)"
date: 2026-06-18
type: fix
issue: 5523
branch: feat-one-shot-5523-inngest-inventory-argmax
lane: procedural
brand_survival_threshold: none
status: planned
---

# 🐛 fix(inngest): op=inventory eventsV2 accumulation overflows ARG_MAX (jq --argjson)

## Overview

`op=inventory` (`.github/workflows/cutover-inngest.yml` → GET `/hooks/inngest-inventory`)
fails on the live host with HTTP 500:

```
/usr/local/bin/inngest-inventory.sh: line 154: /usr/bin/jq: Argument list too long
```

**Root cause (confirmed at `apps/web-platform/infra/inngest-inventory.sh:154`):** the
eventsV2 pagination loop accumulates pages with

```bash
all_edges=$(jq -nc --argjson a "$all_edges" --argjson b "$page_edges" '$a + $b')
```

`--argjson a "$all_edges"` passes the *entire accumulated edge set* as a single
command-line **argument** to `jq` on every page. The kernel bounds the size of any
single argv element by `MAX_ARG_STRLEN` (128 KB on Linux — `getconf ARG_MAX`, 2 MB
here, is the *total* envp+argv ceiling and is a red herring; the real wall is the
per-string limit). Once the accumulated JSON crosses ~128 KB the `execve(2)` of `jq`
fails with `E2BIG` → "Argument list too long". On the live host's real event volume
the accumulator crosses that bound after a few pages.

**Verified at plan time (this branch):** a single 8 000-edge accumulator (~870 KB)
already trips `jq -nc --argjson a "$big" '...'` with the exact error string; the
`tempfile + jq -s 'add'` fix reads identical input via file I/O and succeeds.

This surfaced live **immediately after PR #5518** (the functions-projection fix:
GET `/v1/functions` 404 → `/v0/gql functions` query) merged — before #5518 the
script aborted at the functions guard and never reached the eventsV2 loop, so the
pre-existing accumulation defect was dormant. #5518 did not introduce this defect;
it removed the guard that was masking it.

**Fix:** replace per-page argv accumulation with stdin/tempfile accumulation. Append
each page's `edges` array as one JSON value to a temp file inside the loop, then
collapse with a single `jq -s 'add // []' "$tmpfile"` after the loop. `jq` reading a
**file argument** uses file I/O, not argv expansion — no size limit applies. This is
the exact pattern already documented in the institutional learning
`knowledge-base/project/learnings/integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md`.

The downstream `event_names` / `armed_reminders` projections already pipe via stdin
(`echo "$all_edges" | jq ...`) and have the *same* latent overflow if `$all_edges`
crosses `MAX_ARG_STRLEN` — but stdin/`echo` is not argv, so those are safe **as long
as the accumulator itself is built without argv**. After the fix, `$all_edges` is
still a shell variable; the projections keep reading it via `echo | jq` (stdin),
which is correct. No change needed there. (See Sharp Edges for why we do *not* also
need to spool the projections to file.)

## Research Reconciliation — Spec vs. Codebase

| Claim in feature description | Codebase reality | Plan response |
| --- | --- | --- |
| Bug is at `inngest-inventory.sh:154` | Confirmed verbatim at line 154 | Fix line 154 + the loop around it |
| "op=enumerate … unaffected" | **FALSE.** `apps/web-platform/infra/inngest-enumerate-reminders.sh:126` has the byte-identical `all_edges=$(jq -nc --argjson a "$all_edges" --argjson b "$page_edges" '$a + $b')`, paginates the **same** eventsV2 edge set, and is a live cutover hook (`cutover-inngest.yml:69`, GET `/hooks/inngest-enumerate-reminders`). It will overflow on the same host. | **Fold the identical fix into enumerate in the same PR** (see Phase 2). The re-arm safety path depends on enumerate succeeding during cutover; shipping the inventory fix alone leaves a known HTTP 500 on the sibling op. |
| "downstream event_names/armed projections use stdin and are fine" | Correct — `echo "$all_edges" \| jq` is stdin, not argv. | No change to the projections. |
| ARG_MAX is the limit | Imprecise. The accumulator fails at the per-arg `MAX_ARG_STRLEN` (~128 KB), well below `getconf ARG_MAX` (2 MB). | Plan/test target the per-arg ceiling, not 2 MB. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `op=inventory`
and `op=enumerate` are operator-only cutover-diagnostics hooks invoked from a manually
dispatched GitHub Actions workflow. No end-user request path touches these scripts.
The *operator* experiences a blocked durable-backend cutover: the before/after
inventory diff (the proof that no reminders/events were dropped moving off the
volume-based SQLite store) cannot be captured, and the re-arm enumeration fails.

**If this leaks, the user's data is exposed via:** N/A — the fix is purely a change in
*how* JSON is accumulated (argv → file). It does not change what is read, emitted, or
logged. The #5503 combined-stream-purity invariant (stdout carries only the final
object; summary goes to journald via `logger`; no event bodies on either stream) is
preserved and re-asserted by the existing tests + the new test.

**Brand-survival threshold:** none — operator-only diagnostic surface, no end-user
blast radius, no regulated-data surface. (The diff touches only
`apps/web-platform/infra/*.sh`; no sensitive path per preflight Check 6.1.)

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [ ] `git grep -n 'argjson a "\$all_edges"' apps/web-platform/infra/` returns exactly
      two hits: `inngest-inventory.sh:154` and `inngest-enumerate-reminders.sh:126`
      (proves the fix scope; if a third appears, extend scope).
- [ ] Confirm both scripts run `set -euo pipefail` (they do) so a failed `mktemp` or
      write aborts loudly rather than silently producing a partial accumulator.
- [ ] Re-confirm the fix locally: `tmp=$(mktemp); echo '[{"a":1}]' >>"$tmp"; echo '[{"a":2}]' >>"$tmp"; jq -s 'add' "$tmp"` → `[{"a":1},{"a":2}]`. (verified: 2026-06-18)

### Phase 1 — RED test (`inngest-inventory.test.sh`)

Add a test that **fails on the current argv-accumulation code** and **passes after the
fix**. Two complementary assertions (either alone is acceptable; ship both for
defense in depth):

1. **Behavioral overflow probe (primary RED):** synthesize a fixture large enough to
   cross `MAX_ARG_STRLEN` when accumulated via argv, spread across multiple pages so
   the accumulator grows past the ceiling mid-loop. Mechanically:
   - Add a helper `make_big_page` (or extend `make_page`) that emits a page whose
     `edges` array contains ~N edges of realistic size. Sizing: the loop accumulates
     across pages, so the failure fires when the *running* `$all_edges` (not a single
     page) exceeds ~128 KB. Use e.g. 6 pages × ~4 000 edges, or tune until the
     pre-fix script reproduces `Argument list too long`. **Calibrate at authoring
     time** by running the test against the unpatched script and confirming it FAILs
     with the kernel error (the test is only valid if it reproduces RED first).
   - Assert the patched script exits 0 and emits a well-formed
     `{functions,event_names,armed_reminders}` object whose `event_names`/
     `armed_reminders` correctly reflect the large edge set (so the fix is proven to
     accumulate *all* pages, not just truncate).
   - Keep the fixture **synthesized**, not captured (cq-test-fixtures-synthesized-only)
     — generate edges programmatically via the existing `make_edge` / `jq` builders,
     no real event data.
2. **Structural regression guard (cheap, fast):** assert the accumulation loop never
   passes the running accumulator via `--argjson`. A source-grep test in the same
   harness:
   `grep -qE 'argjson a "\$all_edges"' "$TARGET"` MUST be **false** (i.e. the test
   FAILs if the argv form is reintroduced). Pair with a positive assertion that the
   accumulation reads from a file (`grep -qE 'jq -s|--slurpfile|jq .* "\$[A-Za-z_]+_(file|tmp)"' "$TARGET"`).
   - **Sharp edge:** the existing Test 7 (`test_jq_n_body`) greps for `jq -nc` to prove
     injection-safe body construction. The fix keeps `jq -nc` in `build_request_body`/
     `fetch_functions`, so Test 7 still passes — but make sure the new structural guard
     greps for the *specific* argv-accumulation line, not a bare `--argjson` (the
     `build_request_body` helper legitimately uses `--argjson first`/`--argjson after`).
     Anchor on `argjson a "$all_edges"` exactly.

Register the test in the harness's call list (the block at lines 200–210) and ensure
`=== Results: N passed, 0 failed ===` gates the run (exit 213).

### Phase 2 — GREEN fix (both scripts)

**`apps/web-platform/infra/inngest-inventory.sh`** — replace the loop's accumulation:

```bash
# Before (line 138 + 154):
local all_edges="[]" after="" page=1 resp page_edges has_next end_cursor
while :; do
  ...
  page_edges=$(echo "$resp" | jq -c '.data.eventsV2.edges // []')
  all_edges=$(jq -nc --argjson a "$all_edges" --argjson b "$page_edges" '$a + $b')   # ← overflows
  ...
done

# After:
local edges_file after="" page=1 resp has_next end_cursor all_edges
edges_file=$(mktemp)
# shellcheck disable=SC2064  # expand $edges_file now (trap fires at function return)
trap "rm -f '$edges_file'" RETURN
while :; do
  ...
  # append this page's edges array as ONE JSON value (one line) to the spool file;
  # file I/O has no argv size limit. `// []` keeps a missing/empty edges set well-formed.
  echo "$resp" | jq -c '.data.eventsV2.edges // []' >> "$edges_file"
  ...
done
# Collapse all spooled page-arrays into one flat edge array via stdin-free file input.
all_edges=$(jq -s 'add // []' "$edges_file")
```

Notes:
- `trap ... RETURN` cleans the temp file on every function-exit path (success, the
  two `exit 1` FATAL branches, and `set -e` abort). Use `RETURN` (function-scoped),
  not `EXIT`, so sourcing the script for the unit test does not leave a stale trap.
  **Verify** the existing `exit 1` branches still emit their FATAL diagnostics before
  the trap fires (they do — `exit` runs the body first, then RETURN/EXIT traps).
- `jq -s 'add // []'` over a file of N JSON arrays (one per line) yields the
  concatenation; `add` on an empty file yields `null`, so `// []` guards the
  zero-page case (cannot happen — the loop always writes ≥1 page — but defensive).
- Keep `$all_edges` as a shell variable feeding the existing `echo "$all_edges" | jq`
  projections unchanged. (stdin, not argv → safe.)

**`apps/web-platform/infra/inngest-enumerate-reminders.sh`** — apply the *identical*
transformation to its loop (line 104 `local all_edges="[]" ...` + line 126
accumulation). Mirror the exact pattern so the two scripts stay in lockstep (they
already share the eventsV2 query, error envelope, and #5503 purity comments verbatim).

### Phase 3 — enumerate test parity

`apps/web-platform/infra/inngest-enumerate-reminders.test.sh` must get the same RED→GREEN
treatment (overflow probe + structural guard) so the sibling fix can't silently
regress. Mirror Phase 1's two assertions against the enumerate harness's
fixture builders (`make_page`/`make_edge` — the enumerate variant has a different
`make_edge` signature; adapt accordingly). Register in its call list.

### Phase 4 — Local verification

- [ ] `bash apps/web-platform/infra/inngest-inventory.test.sh` → all pass, exit 0.
- [ ] `bash apps/web-platform/infra/inngest-enumerate-reminders.test.sh` → all pass.
- [ ] `bash apps/web-platform/infra/inngest-rearm-reminders.test.sh` and
      `cutover-inngest-workflow.test.sh` → still pass (no contract change, but they
      run in the same infra-validation job; confirm no collateral break).
- [ ] `shellcheck apps/web-platform/infra/inngest-inventory.sh
      apps/web-platform/infra/inngest-enumerate-reminders.sh` → clean (the existing
      files are shellcheck-clean; the new `trap`/`mktemp` lines carry an inline
      `# shellcheck disable=SC2064` for the intentional early-expansion).

### Phase 5 — Live re-run (post-merge operator verification)

After merge + container restart (the `web-platform-release.yml` path-filtered push
restarts the Docker container on any `apps/web-platform/**` merge — see the
automation-feasibility note below; the infra `.sh` files are delivered to the host via
the infra-config push, drift-guarded by `apply-deploy-pipeline-fix.yml:89` which lists
`inngest-inventory.sh`), re-dispatch the cutover workflow with `op=inventory` and
confirm a clean baseline line:

```
::notice::inventory: functions=N event_names=M armed_reminders=K
```

and (separately) `op=enumerate` returns its JSON array without HTTP 500.

**Automation:** `gh workflow run cutover-inngest.yml -f op=inventory` is automatable via
the `gh` CLI; `/soleur:ship` post-merge verification can dispatch it and read the run
log for the `::notice::` line. This is NOT an operator-only step — bake the dispatch +
log-assert into ship's post-merge verification rather than punting to the operator.
The container restart needs no separate step (the merge IS the restart trigger).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (RED→GREEN, inventory):** `inngest-inventory.test.sh` contains a large-edge
      overflow test that FAILs against the pre-fix `--argjson a "$all_edges"` line
      (reproduces `Argument list too long`) and PASSes against the file-spool fix.
      Verified by checking out the line, running the test, observing FAIL, then
      applying the fix and observing PASS.
- [ ] **AC2 (structural guard, inventory):** the test FAILs if
      `grep -qE 'argjson a "\$all_edges"' inngest-inventory.sh` matches (argv form
      reintroduced), and asserts the accumulation reads from a file.
- [ ] **AC3 (RED→GREEN + guard, enumerate):** identical AC1+AC2 coverage in
      `inngest-enumerate-reminders.test.sh` for `inngest-enumerate-reminders.sh`.
- [ ] **AC4:** `git grep -n 'argjson a "\$all_edges"' apps/web-platform/infra/` returns
      **zero** hits after the fix.
- [ ] **AC5:** both scripts still emit their `set -euo pipefail` FATAL diagnostics on a
      malformed-GraphQL page (existing Test for inventory: `test_functions_fetch_failure_is_loud`
      / the eventsV2 malformed branch) and the temp file is cleaned via `trap RETURN`.
- [ ] **AC6 (#5503 purity preserved):** `inngest-inventory.test.sh`'s
      `test_combined_is_pure_json_object` and `test_summary_no_body_leak` still pass —
      the fix changes accumulation, not stream output.
- [ ] **AC7:** `shellcheck` clean on both scripts.
- [ ] **AC8:** PR body uses `Closes #5523` (the fix lands and is correct at merge —
      this is NOT an ops-remediation/post-merge-apply class; the code merge IS the fix).

### Post-merge (operator / ship-automated)

- [ ] **AC9:** `op=inventory` re-run on the live host returns HTTP 200 with a clean
      `::notice::inventory: functions=N event_names=M armed_reminders=K`. (Automatable
      via `gh workflow run cutover-inngest.yml -f op=inventory` + run-log assert.)
- [ ] **AC10:** `op=enumerate` re-run returns its JSON array, HTTP 200, no
      `Argument list too long`.

## Test Scenarios

| Scenario | Setup | Expected |
| --- | --- | --- |
| Small state (existing) | 1 page, few edges | unchanged — `{functions,event_names,armed_reminders}` object |
| Large accumulated state (NEW) | N pages × M edges, running accumulator > 128 KB | exit 0, complete object; pre-fix reproduces `Argument list too long` |
| Empty state (existing) | 1 page, `[]` edges | `{functions:[],event_names:[],armed_reminders:[]}` |
| Malformed page (existing) | page missing `.data.eventsV2` | exit 1, FATAL diagnostic, temp file cleaned |
| argv form reintroduced (NEW structural) | source contains `argjson a "$all_edges"` | structural test FAILs |

## Observability

```yaml
liveness_signal:
  what: "op=inventory / op=enumerate GitHub Actions run emits ::notice:: with non-error counts"
  cadence: "on-demand (operator dispatches cutover-inngest.yml during cutover window)"
  alert_target: "GitHub Actions run status (red run = failed op); workflow is manual, not scheduled"
  configured_in: ".github/workflows/cutover-inngest.yml (op=inventory / op=enumerate branches)"
error_reporting:
  destination: "GitHub Actions run log via ::error:: (HTTP non-200 / non-object body); on-host journald via `logger -t inngest-inventory` for the script-level summary + FATAL cause"
  fail_loud: true   # set -euo pipefail + exit 1 on malformed page / non-array functions; webhook returns non-200 → workflow ::error:: + exit 1
failure_modes:
  - mode: "accumulator exceeds MAX_ARG_STRLEN (THIS BUG)"
    detection: "jq: Argument list too long in run log (HTTP 500 body) — eliminated by the file-spool fix"
    alert_route: "GitHub Actions run failure on op=inventory/op=enumerate"
  - mode: "malformed/empty GraphQL page (inngest server down or wrong Time bound)"
    detection: "FATAL line on stdout (webhook body) + journald ERROR; exit 1 → HTTP non-200"
    alert_route: "::error:: in the cutover run log"
  - mode: "temp-file write failure (disk full / mktemp fails under set -e)"
    detection: "set -e abort with non-zero exit; webhook non-200"
    alert_route: "::error:: in the cutover run log"
logs:
  where: "GitHub Actions run log (workflow ::notice::/::error::); on-host `journalctl -t inngest-inventory` (summary, counts + reminder_ids only)"
  retention: "GitHub Actions default run-log retention; journald host default"
discoverability_test:
  command: "gh run list --workflow=cutover-inngest.yml --limit 1 --json conclusion,databaseId then gh run view <id> --log | grep -E '::notice::inventory:|Argument list too long'"
  expected_output: "a ::notice::inventory: functions=N event_names=M armed_reminders=K line; ZERO 'Argument list too long' occurrences"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — operator-only infrastructure/tooling bug fix.
No UI surface (no files under `components/**`, `app/**`), no regulated-data surface
(touches only `apps/web-platform/infra/*.sh`), no new infrastructure (pure code fix on
already-provisioned host scripts; no new server/secret/vendor/cron). GDPR gate (2.7),
IaC routing gate (2.8), and Architecture Decision gate (2.10) all skip: the fix changes
*how* JSON is accumulated in-process, not what data is processed, where it lives, or any
architectural boundary. ADR/C4: no architectural decision — a competent engineer reading
the existing ADRs + C4 is not misled by this change.

## Files to Edit

- `apps/web-platform/infra/inngest-inventory.sh` — replace argv accumulation (loop
  around line 138–160) with mktemp spool + `jq -s 'add // []'`; add `trap RETURN`.
- `apps/web-platform/infra/inngest-inventory.test.sh` — add large-edge overflow test
  + structural argv-guard; register in the call list (lines 200–210).
- `apps/web-platform/infra/inngest-enumerate-reminders.sh` — identical accumulation fix
  (loop around line 104–132).
- `apps/web-platform/infra/inngest-enumerate-reminders.test.sh` — add the same two
  tests; register in its call list.

## Files to Create

None.

## Open Code-Review Overlap

None — checked via `gh issue list --label code-review --state open` against the four
edited file paths at plan time (no open scope-outs name these infra scripts).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder,
  or omits the threshold fails `deepen-plan` Phase 4.6. This plan's threshold is
  `none` with a stated reason (operator-only, no sensitive path) — compliant.
- **Why the projections do NOT also need file-spooling:** `event_names` and
  `armed_reminders` read `$all_edges` via `echo "$all_edges" | jq` — that is **stdin**
  (pipe), not argv, so `MAX_ARG_STRLEN` does not apply. `$all_edges` as a shell
  variable can hold arbitrarily large strings; only *passing it as a command-line
  argument* (`--argjson`) hits the kernel limit. Do not "fix" the projections by
  spooling them to file — it is unnecessary and would muddy the #5503 purity reasoning.
- **`trap RETURN` vs `EXIT`:** the unit test **sources** the script
  (`BASH_SOURCE[0] == 0` guard at the bottom runs `run_inventory` only on direct exec),
  so a function-scoped `RETURN` trap is correct — an `EXIT` trap registered inside the
  function would persist after the function returns when sourced. Verify the trap
  expands `$edges_file` at registration time (`trap "rm -f '$edges_file'" RETURN` with
  the SC2064 disable), not at fire time, so a later reassignment can't orphan the file.
- **RED-first calibration is load-bearing:** the overflow test is only valid if it
  reproduces `Argument list too long` against the *unpatched* line. Author it, run it
  against current `main`'s code, confirm FAIL, then apply the fix. A test that passes
  both before and after proves nothing about the overflow.
- **Structural-guard grep specificity:** anchor on the exact string
  `argjson a "$all_edges"` — a bare `--argjson` grep would false-positive on the
  legitimate `--argjson first`/`--argjson after` in `build_request_body` and on the
  `--argjson now`/`--argjson f/e/r` in the projections + final object assembly.
- **The fix touches a file listed in `apply-deploy-pipeline-fix.yml:89`** (it lists
  `inngest-inventory.sh` in the FILE_MAP). Confirm the enumerate script is also in that
  map (or its delivery path) so the host actually receives the fixed enumerate script —
  if enumerate is delivered by a different mechanism, the AC10 live re-run will run stale
  code. `grep -n 'inngest-enumerate' .github/workflows/apply-deploy-pipeline-fix.yml`
  at /work time; if absent, add it to the FILE_MAP in the same PR.

## Related

- Issue #5523 (this bug, OPEN at plan time)
- PR #5518 (functions-projection fix that un-masked this defect — not the cause)
- PR #5509/#5510 (the #5509 cutover inventory + #5503 stream-purity invariant)
- Institutional learning:
  `knowledge-base/project/learnings/integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md`
  (same defect class + same tempfile fix, in `github-community.sh`)
