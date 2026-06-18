---
title: "fix(inngest): op=inventory eventsV2 accumulation overflows ARG_MAX (jq --argjson)"
date: 2026-06-18
type: fix
issue: 5523
branch: feat-one-shot-5523-inngest-inventory-argmax
lane: procedural
brand_survival_threshold: none
status: complete
---

# 🐛 fix(inngest): op=inventory eventsV2 accumulation overflows ARG_MAX (jq --argjson)

## Enhancement Summary

**Deepened on:** 2026-06-18
**Gates passed:** 4.6 User-Brand Impact (none-threshold + sensitive-path scope-out
bullet added), 4.7 Observability (5-field schema present), 4.8 PAT-shaped vars (none),
4.9 UI-wireframe (no UI surface). 4.4 Precedent-diff + 4.45 verify-the-negative ran.

### Key Improvements (vs. the Phase-1 plan)
1. **Trap-scope correction (load-bearing).** The Phase-1 plan prescribed
   `trap ... RETURN`. Empirically verified at deepen time that **a RETURN trap does NOT
   fire on `exit`** — the two `exit 1` FATAL branches would leak the spool temp file.
   Corrected to `trap ... EXIT` registered *inside* `run_inventory`/`run_enumerate`
   (safe because the sourced-by-test bottom guard means the function — and thus the
   trap — is never registered when the script is sourced).
2. **Second argv site found.** The verify-the-negative pass found inventory line 186
   (final object assembly `jq -nc --argjson f ... --argjson r "$armed"`) is ALSO an
   argv site. Documented as a follow-up (bounded re-arm projection, not the reported
   overflow) so a future high-volume host doesn't silently re-trip the same class.
3. **Precedent-diff grounding.** The mktemp+trap+`jq -s 'add // []'` fix is matched
   against in-repo precedents: `github-community.sh:294` (identical paginate→tempfile→
   slurp, the same #5523-class learning's fix) and `ci-deploy.sh`/`infra-config-install.sh`
   (mktemp+trap convention). The only deliberate divergence (EXIT scope) is justified.
4. **Sensitive-path scope-out.** Verified the `apps/[^/]+/infra/` path DOES match
   preflight Check 6.1's regex; added the required `threshold: none, reason:` bullet so
   ship-time preflight Check 6 won't FAIL.

### New Considerations Discovered
- `MAX_ARG_STRLEN` (~128 KB), not `getconf ARG_MAX` (2 MB), is the real ceiling —
  reproduced the exact error at 870 KB argv on this branch.
- The enumerate final projection reads via stdin, so enumerate has exactly ONE site to
  fix and no line-186 equivalent — the two scripts are NOT perfectly symmetric.

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
blast radius, no regulated-data surface.

- `threshold: none, reason:` the diff path `apps/[^/]+/infra/` DOES match the preflight
  Check 6.1 sensitive-path regex (it is an infra dir), but the change is a JSON
  *accumulation mechanism* swap (argv → file I/O) in read-only operator-only cutover
  diagnostics that read/emit no credentials, secrets, or end-user data and process no
  regulated data — so the threshold is correctly `none`. This scope-out bullet is
  required because the path matches the regex (deepen-plan Phase 4.6 Step 2 / preflight
  Check 6).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [x] `git grep -n 'argjson a "\$all_edges"' apps/web-platform/infra/` returns exactly
      two hits: `inngest-inventory.sh:154` and `inngest-enumerate-reminders.sh:126`
      (proves the fix scope; if a third appears, extend scope).
- [x] Confirm both scripts run `set -euo pipefail` (they do) so a failed `mktemp` or
      write aborts loudly rather than silently producing a partial accumulator.
- [x] Re-confirm the fix locally: `tmp=$(mktemp); echo '[{"a":1}]' >>"$tmp"; echo '[{"a":2}]' >>"$tmp"; jq -s 'add' "$tmp"` → `[{"a":1},{"a":2}]`. (verified: 2026-06-18)

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
# shellcheck disable=SC2064  # expand $edges_file NOW (the trap body must capture this
# value, not re-evaluate it at fire time). EXIT (not RETURN) — see the trap-scope note.
trap "rm -f '$edges_file'" EXIT
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
- **Trap scope — use `EXIT`, registered INSIDE `run_inventory` (verified at deepen
  time, this corrects an earlier draft that said `RETURN`):** a `RETURN` trap does
  **NOT** fire when the function `exit`s — the two `exit 1` FATAL branches would leak
  the temp file under `RETURN`. Empirically verified: a `RETURN` trap fires on normal
  function return but is skipped on `exit`; only an `EXIT` trap fires on `exit`.
  Registering `trap 'rm -f ...' EXIT` *inside* `run_inventory` is safe for the
  sourced-by-test design because the bottom guard
  (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) means `run_inventory` is **never called**
  when the script is sourced — so the EXIT trap is never registered in the test shell.
  (The inventory test invokes the script via `bash "$TARGET"` (direct exec, line 62);
  the enumerate test additionally `source`s the script to unit-test `build_request_body`
  (line 168) but never calls `run_enumerate`, so the in-function EXIT trap is still
  never registered during sourcing.) This cleans the temp file on ALL paths:
  success (`return`/normal end → EXIT fires), both `exit 1` FATAL branches, and
  `set -e` abort.
- The `exit 1` FATAL branches still emit their diagnostics before the EXIT trap fires
  (`exit` runs pending output, then EXIT traps).
- `jq -s 'add // []'` over a file of N JSON arrays (one per line) yields the
  concatenation; `add` on an empty file yields `null`, so `// []` guards the
  zero-page case (cannot happen — the loop always writes ≥1 page — but defensive).
- Keep `$all_edges` as a shell variable feeding the existing `echo "$all_edges" | jq`
  projections unchanged. (stdin, not argv → safe.)
- **Second `--argjson` site — the final object assembly at line 186.** The verify pass
  found that `jq -nc --argjson f "$functions" --argjson e "$event_names" --argjson r "$armed"`
  (line 186) is ALSO an argv site. `$functions` and `$event_names` are small (sorted/
  unique name lists). `$armed` is the *projected* armed-reminder set — bounded by the
  count of still-armed `reminder.scheduled` events with future fire + non-terminal runs,
  each a 4-field record (`reminder_id`, `fire_at`, `actor`, `action`). On the live host
  this is far smaller than the raw edge set (the overflow source), but it is not
  provably < `MAX_ARG_STRLEN`. **Decision:** keep line 186 as-is for the minimal fix
  (the reported overflow is the edge accumulator; `$armed` at realistic re-arm volumes
  is small), BUT add a follow-up scope-out note (see Sharp Edges) so a future host with
  thousands of armed reminders does not silently re-trip the same class at line 186.
  If `/work` finds it trivial to also route line 186's three projections through a
  here-string (`jq -nc '...' <<<"$(jq -nc ...)"`) or temp files, fold it in — but it is
  not required to close #5523.

**`apps/web-platform/infra/inngest-enumerate-reminders.sh`** — apply the *identical*
transformation to its loop (line 104 `local all_edges="[]" ...` + line 126
accumulation): same `mktemp` + in-function `trap ... EXIT` + per-page `>> "$edges_file"`
+ post-loop `jq -s 'add // []'`. Mirror the exact pattern so the two scripts stay in
lockstep (they already share the eventsV2 query, error envelope, and #5503 purity
comments verbatim). The enumerate test sources the script for the `build_request_body`
unit test (line 168) but never calls `run_enumerate`, so the in-function EXIT trap is
never registered during sourcing — verified safe at deepen time. Enumerate's final
projection (`records=$(echo "$all_edges" | jq ...)`) already reads via stdin (`echo |
jq`), so enumerate has NO second argv site equivalent to inventory's line 186 — only
the one accumulation line needs the fix.

### Phase 3 — enumerate test parity

`apps/web-platform/infra/inngest-enumerate-reminders.test.sh` must get the same RED→GREEN
treatment (overflow probe + structural guard) so the sibling fix can't silently
regress. Mirror Phase 1's two assertions against the enumerate harness's
fixture builders (`make_page`/`make_edge` — the enumerate variant has a different
`make_edge` signature; adapt accordingly). Register in its call list.

### Phase 4 — Local verification

- [x] `bash apps/web-platform/infra/inngest-inventory.test.sh` → all pass, exit 0.
- [x] `bash apps/web-platform/infra/inngest-enumerate-reminders.test.sh` → all pass.
- [x] `bash apps/web-platform/infra/inngest-rearm-reminders.test.sh` and
      `cutover-inngest-workflow.test.sh` → still pass (no contract change, but they
      run in the same infra-validation job; confirm no collateral break).
- [x] `shellcheck apps/web-platform/infra/inngest-inventory.sh
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

- [x] **AC1 (RED→GREEN, inventory):** `inngest-inventory.test.sh` contains a large-edge
      overflow test that FAILs against the pre-fix `--argjson a "$all_edges"` line
      (reproduces `Argument list too long`) and PASSes against the file-spool fix.
      Verified by checking out the line, running the test, observing FAIL, then
      applying the fix and observing PASS.
- [x] **AC2 (structural guard, inventory):** the test FAILs if
      `grep -qE 'argjson a "\$all_edges"' inngest-inventory.sh` matches (argv form
      reintroduced), and asserts the accumulation reads from a file.
- [x] **AC3 (RED→GREEN + guard, enumerate):** identical AC1+AC2 coverage in
      `inngest-enumerate-reminders.test.sh` for `inngest-enumerate-reminders.sh`.
- [x] **AC4:** `git grep -n 'argjson a "\$all_edges"' apps/web-platform/infra/` returns
      **zero** hits after the fix.
- [x] **AC5:** both scripts still emit their `set -euo pipefail` FATAL diagnostics on a
      malformed-GraphQL page (existing Test for inventory: `test_functions_fetch_failure_is_loud`
      / the eventsV2 malformed branch). The spool temp file is cleaned on ALL exit paths
      via an in-function `trap 'rm -f ...' EXIT` (NOT `RETURN` — RETURN does not fire on
      `exit`; verified at deepen time). Add a test asserting no `mktemp`-pattern temp file
      survives a FATAL run (e.g. snapshot `ls /tmp` before/after, or trap-fire stub).
- [x] **AC6 (#5503 purity preserved):** `inngest-inventory.test.sh`'s
      `test_combined_is_pure_json_object` and `test_summary_no_body_leak` still pass —
      the fix changes accumulation, not stream output.
- [x] **AC7:** `shellcheck` clean on both scripts.
- [x] **AC8:** PR body uses `Closes #5523` (the fix lands and is correct at merge —
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

## Risks & Mitigations — Precedent Diff (deepen-plan Phase 4.4)

The fix is a **pattern-bound behavior** (mktemp spool + cleanup trap + `jq -s` slurp).
Verified against repo precedent at deepen time:

| Pattern | Canonical precedent (verified) | Plan's form | Diff / rationale |
| --- | --- | --- | --- |
| Paginated-array merge via tempfile + `jq -s` | `plugins/soleur/skills/community/scripts/github-community.sh:294` — `... --paginate \| jq -s 'add // []' > "$tmpfile"` then `jq '...' "$tmpfile"` (the fix from the cited #5523-class learning) | `echo "$resp" \| jq -c '.data.eventsV2.edges // []' >> "$edges_file"` per page, then `all_edges=$(jq -s 'add // []' "$edges_file")` | **Same pattern.** github-community spools the raw paginated output once; we spool one `edges` array per loop iteration. Both collapse with `jq -s 'add // []'`. The `// []` guard is identical. |
| `mktemp` + cleanup trap in infra `.sh` | `apps/web-platform/infra/ci-deploy.sh:92,137`; `infra-config-install.sh:123-124` (`tmp=$(mktemp ...); trap 'rm -f "$tmp"' EXIT`); `canary-bundle-claim-check.sh:45` | `edges_file=$(mktemp); trap "rm -f '$edges_file'" EXIT` **registered inside `run_inventory`** | **Same `EXIT` verb as the precedents; scope differs by registration site.** Infra precedents register `EXIT` at top level because they are *executed*, never sourced. `inngest-inventory.sh` / `inngest-enumerate-reminders.sh` ARE sourced by their unit tests (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard runs `run_inventory` only on direct exec). Registering the `EXIT` trap *inside* `run_inventory` means it is never set when sourced (the function is never called) and fires on ALL exec-path exits — normal return, `exit 1` FATAL, `set -e`. `RETURN` would be wrong: it does not fire on `exit` (verified at deepen), leaking the spool file on the FATAL branches. |
| `mktemp` failure under `set -e` | `ci-deploy.sh:92` handles `mktemp` failure explicitly; most infra sites let `set -e` abort | `set -euo pipefail` is already in both scripts → a failed `mktemp` aborts loudly (acceptable: a disk-full host should fail the inventory, not silently truncate) | No explicit handler needed; the loud abort is the desired failure mode for a diagnostic that must not emit a partial baseline. |

No novel pattern — every element has an in-repo precedent. The only deliberate
divergence from the precedents is the trap *registration site* (inside the function vs
top-level), forced by the sourced-for-test design; the trap verb (`EXIT`) matches the
precedents.

## Files to Edit

- `apps/web-platform/infra/inngest-inventory.sh` — replace argv accumulation (loop
  around line 138–160) with mktemp spool + `jq -s 'add // []'`; add in-function `trap ... EXIT`.
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
  `none`; the infra-dir path matches preflight Check 6.1's sensitive-path regex, so the
  section carries the required `threshold: none, reason:` scope-out bullet — compliant.
- **Why the projections do NOT also need file-spooling:** `event_names` and
  `armed_reminders` read `$all_edges` via `echo "$all_edges" | jq` — that is **stdin**
  (pipe), not argv, so `MAX_ARG_STRLEN` does not apply. `$all_edges` as a shell
  variable can hold arbitrarily large strings; only *passing it as a command-line
  argument* (`--argjson`) hits the kernel limit. Do not "fix" the projections by
  spooling them to file — it is unnecessary and would muddy the #5503 purity reasoning.
- **`trap ... EXIT` registered INSIDE the function (NOT `RETURN`) — verified at deepen
  time:** the obvious instinct is `RETURN` (function-scoped, won't leak into the
  sourcing test shell), but **a `RETURN` trap does not fire on `exit`** — the two
  `exit 1` FATAL branches would leak the spool file. Empirically confirmed: `RETURN`
  fires on normal return, is skipped on `exit`; only `EXIT` fires on `exit`. The
  sourced-by-test concern is still handled: the bottom guard means `run_inventory` /
  `run_enumerate` is never *called* when sourced, so an EXIT trap registered *inside*
  that function is never registered in the test shell (verified: the enumerate test
  sources the script for `build_request_body` but never calls `run_enumerate`). Expand
  `$edges_file` at registration time (`trap "rm -f '$edges_file'" EXIT` with the SC2064
  disable), not at fire time, so a later reassignment can't orphan the file.
- **Second argv site at inventory line 186 (follow-up, NOT required for #5523):** the
  final object assembly `jq -nc --argjson f "$functions" --argjson e "$event_names"
  --argjson r "$armed"` also passes data via argv. `$functions`/`$event_names` are small
  name lists; `$armed` is the bounded re-arm projection. At realistic re-arm volumes
  this is far below `MAX_ARG_STRLEN`, so it is NOT the reported overflow and is left
  as-is for the minimal fix. A host with thousands of still-armed reminders could
  re-trip the SAME class here — if `/work` finds the here-string/temp-file conversion
  trivial, fold it in; otherwise file a follow-up scope-out issue so it isn't lost.
  (Enumerate has no equivalent — its final projection reads `$all_edges` via stdin.)
- **RED-first calibration is load-bearing:** the overflow test is only valid if it
  reproduces `Argument list too long` against the *unpatched* line. Author it, run it
  against current `main`'s code, confirm FAIL, then apply the fix. A test that passes
  both before and after proves nothing about the overflow.
- **Structural-guard grep specificity:** anchor on the exact string
  `argjson a "$all_edges"` — a bare `--argjson` grep would false-positive on the
  legitimate `--argjson first`/`--argjson after` in `build_request_body` and on the
  `--argjson now`/`--argjson f/e/r` in the projections + final object assembly.
- **Both scripts are in the host-delivery FILE_MAP (verified at deepen time):**
  `apply-deploy-pipeline-fix.yml` lists `apps/web-platform/infra/inngest-enumerate-reminders.sh`
  (line 85) AND `apps/web-platform/infra/inngest-inventory.sh` (line 89), so the host
  receives both fixed scripts after merge — the AC9/AC10 live re-runs will execute the
  patched code, not stale code. No FILE_MAP edit needed.

## Related

- Issue #5523 (this bug, OPEN at plan time)
- PR #5518 (functions-projection fix that un-masked this defect — not the cause)
- Issue #5509 / PR #5510 (the cutover inventory + #5503 stream-purity invariant — #5509
  is the umbrella issue, #5510 the merged PR)
- Institutional learning:
  `knowledge-base/project/learnings/integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md`
  (same defect class + same tempfile fix, in `github-community.sh`)
