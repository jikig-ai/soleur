---
title: Fix the C1 itemized byte-identity verify so the workspaces-luks cutover abort is diagnosable
type: fix
date: 2026-07-19
branch: feat-one-shot-luks-cutover-verify-diag
epic: 6588
adr: ADR-119
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
---

# 🐛 fix: make the C1 itemized byte-identity verify diagnosable (workspaces-luks cutover)

## Enhancement Summary

**Deepened on:** 2026-07-19 · **Sections enhanced:** Vector allowlist decision, Phase 0, Research
Insights (new), AC10. **Method:** direct high-value verification (precedent-diff + verify-the-negative
+ cited-artifact/rule-ID checks) rather than 40-agent fan-out — this is a tightly-scoped single-file
observability fix; the substance gate is the review-time `user-impact-reviewer` (single-user-incident
threshold) + CPO sign-off, not breadth of plan-time agents.

### Key improvements (verified this pass)
1. **AC10 de-risked to a hard confirm:** no test walks `apps/web-platform/infra/*.sh` extracting
   `logger -t` tags (`grep -rln "for .* in .*infra … logger -t"` → 0), so adding
   `logger -t luks-monitor` to `workspaces-cutover.sh` trips **no** drift guard and needs **no**
   `vector.toml` change. `vector-pii-scrub.test.sh` (583 lines) tests the VRL *transforms* only — not
   host-script tag extraction. The `luks-monitor` tag is already in Source 4 (`vector.toml:184`).
2. **Precedent-diff:** the itemized `%i %n` parse is **deliberately unique** to `workspaces-cutover.sh`
   — the sibling `git-data-cutover.sh` uses a `verify_set_identity` (per-repo `for-each-ref` +
   `rev-list sha256`, `:239-277`), NOT an itemized rsync. This is intentional (the C1 header at
   `workspaces-cutover.sh:24-27`: a rev-list identity "passes while dropping the working-tree +
   refs/checkpoints/* data"). So there is **no repo precedent** for the parse — scrutinize the regex —
   but the *emit / guard / scrub* patterns all have precedent (below).
3. **All cited rule IDs are ACTIVE** in AGENTS.md (`hr-menu-option-ack-not-prod-write-auth`,
   `hr-no-ssh-fallback-in-runbooks`, `hr-observability-as-plan-quality-gate`,
   `hr-weigh-every-decision-against-target-user-impact`, `wg-ui-feature-requires-pen-wireframe`).
   ADR-119 file + `infra-validation.yml` `luks-monitor.test.sh` step (~:379) exist.

## Research Insights (precedent-diff — deepen Phase 4.4)

Pattern-bound behaviors and their in-repo precedents (the parse is novel; everything else is matched):

| Pattern in this plan | Precedent (verbatim shape) | Fit |
| --- | --- | --- |
| `logger -t "$TAG" --` on its own line, `TAG` a real assignment | `luks-monitor.sh:34-38` (`logger -t "$LOG_TAG" --`, own line so the extractor "sees this channel"); `infra-config-apply.sh:220`; `web-private-nic-guard.sh` | **Match** — adopt `LUKS_LOG_TAG="luks-monitor"` real assignment + own-line `logger -t "$LUKS_LOG_TAG" --`. |
| SOLEUR_ plain-text stdout marker, `KEY=value` shape | `SOLEUR_INFRA_CONFIG_HOOK_ORPHAN dangling_hook_command=… reason=…` (`infra-config-apply.sh:220`); `SOLEUR_PRIVATE_NIC nic_ok=… converged_by=…` | **Match** — `SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF feature=… op=… count=… icode=… path=…`. |
| Sourced-detection guard (define funcs when sourced, run body when executed) | `workspaces-luks-emit.sh:84` (`if [ "${BASH_SOURCE[0]}" = "${0}" ]; then workspaces_luks_emit; fi`) | **Match (inverse)** — guard = `if sourced → return`. |
| `_vscrub` structural-byte scrub before log interpolation | `workspaces-luks-emit.sh:33` `_wl_scrub() { … tr -d '"\\' \| tr -cd '[:print:]'; }` | **Match** — `_vscrub` strips CR/LF + non-printable (marker is not JSON, so drop the `"`/`\` deletion; keep control-char strip). |
| Itemized `rsync -aHAXi … --out-format='%i %n'` diff parse | **None** — `git-data-cutover.sh` uses set-identity, not itemized rsync | **Novel** — no precedent; the `^(\*deleting\|[<>ch.*][fdLDS])` count regex is the scrutiny point (case d in the test proves it counts attribute-only codes). |

**Verify-the-negative (deepen Phase 4.45) — every negative claim probed:**
- "no new Vector allowlist entry needed" → **confirmed** (`luks-monitor` ∈ Source 4 `vector.toml:184`; Source 4 filters `SYSLOG_IDENTIFIER`, not `op=`).
- "no test extracts logger tags from the cutover script" → **confirmed** (0 hits; `vector-pii-scrub.test.sh` tests VRL transforms only).
- "git-data-cutover is not a precedent for the itemized verify" → **confirmed** (it uses `verify_set_identity`).

## Overview

On 2026-07-19 the first real `/workspaces` LUKS cutover (GitHub Actions run **29676994044**,
`dry_run=false`) **safe-aborted**: freeze / luksFormat / escrow / rsync all succeeded, then the C1
itemized verify found **"1 difference"** and correctly refused to repoint. DP-6 auto-rolled-back to
the plaintext mount and web-1 stayed healthy — the fail-closed gate did its job.

But the operator **cannot tell what that 1 difference was**, and that is the bug. The verify block
(`apps/web-platform/infra/workspaces-cutover.sh:408-416`) has two defects:

1. **stderr folds into the count.** `rsync -aHAXi … --out-format='%i %n' > "$vlog" 2>&1` merges the
   verify-rsync's STDERR into the same file that `DIFF_N="$(grep -c . "$vlog")"` counts. A single
   benign stderr warning (`file has vanished`, `some files/attrs were not transferred`) is counted
   as a "difference," indistinguishable from a real byte diff.
2. **the evidence is discarded before it is logged.** On failure the script `die()`s with **only the
   count**, then `rm -f "$vlog"` — throwing away the offending path + itemize code. Nobody can tell
   whether the diff was a real content difference (`>f……`), an mtime-only diff (`.f..t…`), a
   directory-mtime diff (`.d..t…`), or the stderr artifact from defect 1.

**This fix is observability + the stderr-fold bug ONLY.** It does **NOT** change the gate threshold
(still 0 real content differences) and does **NOT** narrow which itemize codes count. The verify must
still require 0 real content differences and must still fail-closed if the verify rsync itself errors.
The single goal: the **next** operator-approved real cutover self-reports exactly which path and
itemize code caused the abort — in the run log and Better Stack, **no SSH**.

Ship as a normal reviewed + merged PR. No infra dispatch, no cutover re-run — the operator
re-approves the real cutover separately after this merges.

## User-Brand Impact

**If this lands broken, the user experiences:** the next real cutover aborts again and is *still*
undiagnosable (best case, unchanged pain) — OR, in the catastrophic case, a regression in the
stream-separation refactor (a too-narrow itemize regex, counting the wrong stream, or a swallowed
`die`) silently **weakens the byte-identity gate**, letting a future cutover false-green a partial
data copy and repoint onto an incomplete LUKS volume before the plaintext is wiped in Phase 5.

**If this leaks, the user's workspace file paths are exposed via:** the new SOLEUR_ diagnostic marker
ships up-to-40 workspace file paths (`workspaces/<ws-id>/…`) to Better Stack + the workflow run log.
Soleur is a single-operator product; the sole data subject is the founder (their own git-workspace
contents). Volume is capped (~40 lines), the sink already carries host diagnostics, and Vector's
`pii_scrub_string` transform runs on the line. See §Observability for the accepted trade-off.

**Brand-survival threshold:** single-user incident. The verify is THE byte-identity gate before the
irreversible plaintext wipe; a weakened gate on a single-operator product = total sole-copy data loss
for the entire userbase. The fix therefore edits a load-bearing gate and MUST preserve fail-closed
semantics exactly. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review-time.

## Research Reconciliation — Spec vs. Codebase

| Claim (task grounding) | Reality (verified this session) | Plan response |
| --- | --- | --- |
| Verify block at `workspaces-cutover.sh:408-416` | Confirmed. Verify block 408-416; pass-2 delta rsync at :399; `sync`+`drop_caches` at :406-407; `die()` at :36. | Edit only 408-416 (+ a new function near :178). Do NOT touch :399/:406/:407 semantics. |
| Emit via SOLEUR_ marker "the telemetry layer already ingests" | Two channels exist: (1) **Sentry** direct-curl via `workspaces_luks_emit`/`emit_drift` (`feature=workspaces-luks op=workspaces-luks-drift`); (2) **Better Stack** via `logger -t <tag>` → journald SYSLOG_IDENTIFIER → Vector Source 4 (`vector.toml:141-194`). The `luks-monitor` tag is **already allowlisted** (`vector.toml:184`). | The itemized-path marker rides the **existing `luks-monitor` tag** → **no new Vector allowlist entry needed**. `op=workspaces-luks-verify-diff` is a log *field*, not a Vector filter key. See §"Vector allowlist decision". |
| "cutover-gate test … tests/scripts/lib/workspaces-luks-cutover-gate.sh" | That file is a **Terraform destroy-guard** (validates `terraform show -json`), unrelated to the runtime C1 verify. | Add a **new behavioral test** `apps/web-platform/infra/workspaces-luks-verify.test.sh` (executes the counting/gating logic with a stubbed rsync). Static-shape assertions can also live in `workspaces-luks-header.test.sh`. |
| Bundle ships the cutover script + siblings | `workspaces-luks-cutover.yml:175` tars an **explicit file list**: `workspaces-cutover.sh workspaces-luks-emit.sh luks-monitor.sh luks-monitor.{service,timer}`. | Keep the verify logic **inline in `workspaces-cutover.sh`** (already shipped) → **no tar-manifest change**. This is the decisive reason to reject the "extract to a new sourced sibling" alternative. |

## Vector allowlist decision (task: "confirm whether the new op needs an allowlist entry")

**No new Vector allowlist entry is required**, provided the marker is shipped via `logger -t
luks-monitor`. Rationale:
- Vector **Source 4** (`sources.host_scripts_journald`) filters by **exact `SYSLOG_IDENTIFIER`**
  (the `logger -t <tag>` tag), NOT by the `op=` field. `luks-monitor` is already in the allowlist
  (`vector.toml:184`, added by #6604 for this exact feature).
- `logger -t luks-monitor` sets `SYSLOG_IDENTIFIER=luks-monitor` → the line is admitted by Source 4
  → traverses `pii_scrub_*` → Better Stack. This is the identical path the existing
  `SOLEUR_INFRA_CONFIG_HOOK_ORPHAN` plain-text marker already uses.
- web-1 runs Vector (Source 4's `luks-monitor` entry exists precisely so the daily probe on web-1
  reaches Better Stack), so a marker emitted on web-1 during the cutover flows to Better Stack.
- **Verified (deepen pass):** no test walks `apps/web-platform/infra/*.sh` extracting `logger -t` tags
  (0 hits repo-wide), and `vector-pii-scrub.test.sh` tests only the VRL *transforms*, not host-script
  tag extraction. So reusing `luks-monitor` trips **no** drift guard and needs **no** `vector.toml`
  change. Still adopt the documented `luks-monitor.sh:34-38` shape (`LUKS_LOG_TAG="luks-monitor"` real
  assignment + `logger -t "$LUKS_LOG_TAG" --` on its own line) as cheap insurance / convention match.

> If a future decision ever wants a *distinct* SYSLOG_IDENTIFIER for verify-diff, THAT would require a
> new `vector.toml` Source 4 entry **and** the `vector-pii-scrub.test.sh` exact-tag drift-fixture
> update. Reusing `luks-monitor` avoids both. (Documented so the next planner sees the trade-off.)

## Files to Edit

- **`apps/web-platform/infra/workspaces-cutover.sh`** — the fix.
  - Add a `verify_byte_identity <src> <dst>` function (and a small `emit_verify_diff` marker helper)
    near the other emit/drift helpers (after `emit_drift`, ~line 178).
  - Add a **sourced-detection guard** before the main body (before the `ROLLBACK` block, ~line 234):
    `if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0 2>/dev/null || true; fi` — so the test can
    `source` the script to obtain the functions without executing the cutover main body (and without
    arming `trap cleanup EXIT`). Executed runs (`bash …/workspaces-cutover.sh`) are unaffected.
  - Replace the inline verify block (408-416) with a call to `verify_byte_identity "$MOUNT" "$STAGING"`.
- **`apps/web-platform/infra/workspaces-luks-header.test.sh`** — (optional, matching existing style)
  add static mutation-shape assertions that the verify captures stdout/stderr **separately** and does
  NOT `rm` the evidence before logging (drift guard, cheap; behavioral coverage is the new file below).
- **`.github/workflows/infra-validation.yml`** — register the new test as a step (next to the
  `luks-monitor.test.sh` step, ~line 379).
- **`knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`**
  — one-line addendum to the observability section documenting the new
  `op=workspaces-luks-verify-diff` Better Stack marker as the itemized-diff channel (ADR-119 already
  documents `op=workspaces-luks-drift`). Keeps the recorded telemetry taxonomy honest. **Not** a new
  ADR / not an architectural decision (see §Architecture Decision).

## Files to Create

- **`apps/web-platform/infra/workspaces-luks-verify.test.sh`** — behavioral mutation-style test.
  Sources `workspaces-cutover.sh` (sourced-detection guard defines functions only), overrides
  `rsync` / `logger` / `die` / `log` / `emit_drift` with stubs, and runs `verify_byte_identity`
  in a subshell per case (die stub → `exit 1`), asserting on captured stdout + stderr + the stubbed
  marker log. Harness style mirrors `git-data-luks.test.sh` (predicate + `$(… || true)`,
  mutation-tested). See §Test Scenarios.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)
- Re-read `workspaces-cutover.sh:396-442` and confirm line anchors before editing.
- Confirm rsync `--out-format='%i %n'` itemize shape: first char ∈ `<>ch.*`, second ∈ `fdLDS`
  (attribute-only lines start `.`, e.g. `.f..t……`/`.d..t……`), plus the `*deleting  ` form.
  Count regex: `^(\*deleting|[<>ch.*][fdLDS])`. This counts **every** itemize code (does NOT narrow)
  and excludes stderr warning lines + blank lines.
- (Resolved in deepen: no `infra/*.sh` logger-tag extractor exists → no drift-guard concern.) Adopt
  the `luks-monitor.sh:34-38` `logger -t "$LUKS_LOG_TAG" --` own-line + real-assignment shape anyway.
- Confirm `logger` + `mktemp` are available on the target (util-linux; yes).

### Phase 1 — `verify_byte_identity` (the counting fix, defect 1)
Replace the merged-stream capture with **separate** stdout / stderr capture and rc gating:
```sh
verify_byte_identity() {            # $1=src $2=dst
  local src="$1" dst="$2" vout verr rc diff_n
  vout="$(mktemp)"; verr="$(mktemp)"
  # --dry-run hardcoded (one typo from wiping). %i %n itemize to STDOUT; warnings to STDERR.
  rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n' \
    "$src"/ "$dst"/ >"$vout" 2>"$verr"; rc=$?
  # Fail-closed rc-check PRESERVED — surface the verify rsync's own stderr.
  if [ "$rc" -ne 0 ]; then
    emit_verify_diff "rc=$rc" "$vout" "$verr" verify_rsync_error
    rm -f "$vout" "$verr"
    die "the itemized verify rsync itself FAILED (rc=$rc) to run to completion — cannot certify DST==SRC (C1); stderr: $(tail -3 "$verr" 2>/dev/null)"
  fi
  # Count ONLY itemize-shaped STDOUT lines (stderr can no longer inflate this).
  diff_n="$(grep -cE '^(\*deleting|[<>ch.*][fdLDS])' "$vout" || true)"
  if [ "$diff_n" -ne 0 ]; then
    emit_verify_diff "$diff_n" "$vout" "$verr" verify_byte_diff   # logs BEFORE rm + die
    rm -f "$vout" "$verr"
    die "itemized rsync verify found $diff_n difference(s) — DST is not byte-identical to SRC (C1); see the SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF marker for the offending path(s)+code(s)"
  fi
  rm -f "$vout" "$verr"
}
```
Note: `die` message must reference stderr from `$verr` **before** the `rm` (order matters — do not
`rm` then `tail`). The snippet above is illustrative; /work fixes the ordering (capture the tail into
a var before `rm`).

### Phase 2 — `emit_verify_diff` (the diagnostic, defect 2) — BEFORE die, BEFORE rm
Print the capped itemized lines to stdout (run log) AND emit the SOLEUR_ marker to Better Stack +
run log. Cap ~40 with a `+N more` note. Reuse the existing `luks-monitor` tag. Also page Sentry via
the existing `emit_drift` (discriminating reason, existing `op=workspaces-luks-drift` — no Sentry
filter change).
```sh
VERIFY_DIFF_CAP=40
LUKS_LOG_TAG="luks-monitor"          # real assignment (satisfies the emitter-extractor contract)
_vscrub() { printf '%s' "${1:-}" | tr -d '\r\n' | tr -cd '[:print:]'; }  # strip CR/LF/control (log-injection)
emit_verify_diff() {                 # $1=count $2=vout $3=verr $4=reason
  local count="$1" vout="$2" reason="$4" shown k=0 line
  log "C1 verify FAILED ($reason): $count difference(s). Itemized (capped ${VERIFY_DIFF_CAP}):"
  # Human view to the run log.
  head -n "$VERIFY_DIFF_CAP" "$vout" | while IFS= read -r line; do log "  DIFF $line"; done
  [ "$count" -gt "$VERIFY_DIFF_CAP" ] && log "  … +$((count - VERIFY_DIFF_CAP)) more"
  # Structured marker: summary + up-to-cap per-diff rows, each to Better Stack (logger) AND run log (echo).
  local summary="SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF feature=workspaces-luks op=workspaces-luks-verify-diff count=$count reason=$(_vscrub "$reason") host=$(hostname)"
  echo "$summary"; logger -t "$LUKS_LOG_TAG" -- "$summary" 2>/dev/null || true
  while IFS= read -r line && [ "$k" -lt "$VERIFY_DIFF_CAP" ]; do
    local icode="${line%% *}" path; path="$(_vscrub "${line#* }")"
    local row="SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF feature=workspaces-luks op=workspaces-luks-verify-diff count=$count idx=$k icode=$(_vscrub "$icode") path=$path"
    echo "$row"; logger -t "$LUKS_LOG_TAG" -- "$row" 2>/dev/null || true
    k=$((k + 1))
  done < "$vout"
  # Sentry page (existing op), discriminating reason — belt for the Better Stack marker.
  emit_drift "workspaces_luks_${reason}"
}
```
Sanitize each `path=`/`icode=`/`reason=` value with `_vscrub` (strip CR/LF + non-printable) to
prevent a crafted filename from injecting a spurious log line / `::notice::` (log-injection sharp
edge). Put `path=` LAST so a path containing spaces is captured whole.

### Phase 3 — Sourced-detection guard + call-site swap
- Insert the sourced-detection guard before the `ROLLBACK` block (~line 234).
- Replace the inline 408-416 block with: `verify_byte_identity "$MOUNT" "$STAGING"`.
- `verify_byte_identity` must be called **directly** (not in `$(…)`/a pipe) so `die`'s `exit 1`
  propagates and the EXIT trap → rollback fires (sharp edge — subshell would swallow the exit).

### Phase 4 — Tests
Create `workspaces-luks-verify.test.sh` (behavioral) + optional static assertions in
`workspaces-luks-header.test.sh`; register the behavioral test in `infra-validation.yml`.

### Phase 5 — ADR-119 addendum
One-line note in the observability section: `op=workspaces-luks-verify-diff` (Better Stack, via the
`luks-monitor` tag) is the itemized-diff channel; `op=workspaces-luks-drift` remains the at-rest page.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 (stream separation):** `verify_byte_identity` captures rsync stdout and stderr into
  **separate** temp files; the count reads only the stdout file. Assert via grep on
  `workspaces-cutover.sh`: no `2>&1` in the verify rsync; `>"$vout" 2>"$verr"` present.
- **AC2 (count is itemize-shaped):** `DIFF_N`/`diff_n` derives from
  `grep -cE '^(\*deleting|[<>ch.*][fdLDS])'` over the **stdout** file (not `grep -c .`), so codes are
  NOT narrowed and stderr cannot inflate it. Threshold unchanged: gate fails iff count ≠ 0.
- **AC3 (fail-closed preserved):** verify rsync `rc != 0` → `die` with a message that includes the
  verify rsync's **stderr** tail ("verify rsync itself FAILED"). (Behavioral case (c).)
- **AC4 (evidence logged before discard):** on count ≠ 0 (or rc ≠ 0), the capped itemized lines +
  the `SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF` marker are emitted **before** any `rm` of the temp files
  and **before** `die`. Assert the `emit_verify_diff` call precedes `rm`/`die` in source order.
- **AC5 (marker shape):** the marker line carries `feature=workspaces-luks`,
  `op=workspaces-luks-verify-diff`, `count=`, and per-diff `icode=` + `path=` (path last); shipped via
  `logger -t luks-monitor` (Better Stack) AND `echo` (run log). Cap = 40 with a `+N more` note.
- **AC6 (behavioral test — case a):** a stubbed verify-rsync emitting a benign **STDERR** warning
  (`file has vanished …`) with **rc=0** and empty stdout → `verify_byte_identity` does **NOT** die and
  emits **no** diff marker (proves stderr no longer inflates `DIFF_N`).
- **AC7 (behavioral test — case b):** a stubbed real content diff on **stdout**
  (`>f+++++++++ workspaces/ws1/secret.txt`, rc=0) → `verify_byte_identity` **dies**, AND the emitted
  diagnostic (marker + stdout) **contains `workspaces/ws1/secret.txt`** and its itemize code.
- **AC8 (behavioral test — case c):** a stubbed verify-rsync **hard error** (rc=23, stderr text) →
  `verify_byte_identity` **dies** with the "verify rsync itself FAILED" message including the stderr.
- **AC9 (behavioral test — case d, codes-not-narrowed):** an mtime-only diff (`.f..t...... …`) and a
  dir-mtime diff (`.d..t...... …`) on stdout each still **fail** the gate and appear in the diagnostic
  (proves the itemize regex counts attribute-only codes, not only `>f……`).
- **AC10 (no Vector allowlist regression):** the marker uses tag `luks-monitor` (already allowlisted,
  `vector.toml:184`); no `vector.toml` Source 4 change is required. Verified in deepen: no
  `infra/*.sh` `logger -t` tag-extractor exists, so no drift-guard suite gates on the cutover script's
  new emit. `vector-pii-scrub.test.sh` remains green (it tests VRL transforms, not tag extraction).
- **AC11 (no semantic change to untouched steps):** `workspaces-cutover.sh:399` (pass-2 delta rsync),
  `:406` (`sync`), `:407` (`drop_caches`) are byte-unchanged; DRY_RUN gating unchanged; the gate
  threshold is still 0 and no itemize code is excluded.
- **AC12 (test registered):** `infra-validation.yml` runs
  `bash apps/web-platform/infra/workspaces-luks-verify.test.sh`; the suite is green in CI.
- **AC13 (mutation integrity):** each behavioral assertion is mutation-tested (a deliberately broken
  copy — e.g. re-merge stderr with `2>&1`, or revert to `grep -c .` — MUST flip the relevant case to
  failing), per the `git-data-luks.test.sh` convention.

### Post-merge (operator)
- **AC14:** none required by this PR. The operator re-approves the real cutover
  (`workspaces-luks-cutover.yml`, `dry_run=false`) separately. If it aborts again on the C1 verify,
  the `SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF` marker in the run log + Better Stack now names the path(s)
  and itemize code(s) — no SSH. `Automation: not feasible` (menu-ack workflow_dispatch on sole-copy
  data per `hr-menu-option-ack-not-prod-write-auth`; out of scope for this PR).

## Observability

```yaml
liveness_signal:
  what: workspaces-luks-verify.test.sh green in CI (infra-validation.yml) proves the counting/gating/marker paths
  cadence: every PR + push touching apps/web-platform/infra
  alert_target: CI red → PR blocked
  configured_in: .github/workflows/infra-validation.yml
error_reporting:
  destination: Sentry (emit_drift → workspaces_luks_emit, op=workspaces-luks-drift, discriminating reason=workspaces_luks_verify_byte_diff) + Better Stack (SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF via logger -t luks-monitor, op=workspaces-luks-verify-diff)
  fail_loud: yes — verify count≠0 or rc≠0 → die (exit 1) → EXIT trap → rollback → emit_drift(rollback_engaged)
failure_modes:
  - mode: real byte/content diff (>f……), mtime-only (.f..t…), or dir-mtime (.d..t…)
    detection: itemize-shaped stdout line counted; capped path+code emitted to run log + Better Stack
    alert_route: Sentry page + Better Stack marker (op=workspaces-luks-verify-diff) + workflow run-log abort
  - mode: verify rsync itself errors (rc≠0)
    detection: rc gate; verify rsync stderr tail surfaced in the die message + marker
    alert_route: same as above (reason=verify_rsync_error)
  - mode: benign stderr warning (file vanished / attrs not transferred), rc=0
    detection: routed to the SEPARATE stderr file; NOT counted → does not trip the gate
    alert_route: n/a by design (no longer a false abort)
logs:
  where: GitHub Actions run log (SSH stdout stream) + Better Stack (Vector Source 4, luks-monitor tag)
  retention: Better Stack Logs (source 2457081); run log per GitHub retention
discoverability_test:
  command: "Better Stack Logs query: op:workspaces-luks-verify-diff (or grep the workflow run log for SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF)"
  expected_output: "on a real C1 abort: count=N + per-diff icode=/path= rows naming the offending workspace path(s); zero rows on a clean verify"
```
**Path-in-logs trade-off (accepted):** the marker ships up-to-40 workspace file paths to Better Stack.
Single-operator product → sole data subject is the founder (own workspace contents); volume capped;
sink already carries host diagnostics; `pii_scrub_string` runs on the line; values `_vscrub`-sanitized.
The path IS the diagnostic value the task requires ("which path caused the abort"). Reviewer question
(non-blocking): full path vs basename — default full path per the task's explicit ask.

## Domain Review

**Domains relevant:** Engineering (infra/observability). Product/UX: none (no user-facing surface —
no file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`; a host bash script + a CI
test + one ADR line). GDPR: borderline (workspace paths → logs) — noted in §Observability; canonical
regulated-data regex not matched (no schema/migration/auth/API route); advisory only.

### Engineering
**Status:** carried into deepen-plan (Step 2). At `single-user incident` threshold the deepen-plan
triad (data-integrity-guardian + security-sentinel + architecture-strategist) is the substance gate;
`user-impact-reviewer` runs at review-time. CPO sign-off required at plan time (`requires_cpo_signoff:
true`) — the technical approach (observability-only, gate semantics unchanged) is the single product
ack; CLO/CTO brainstorm concerns are reflected in §User-Brand Impact + §Sharp Edges.

### Product/UX Gate
Not applicable — infrastructure/tooling change, NONE tier (no UI-surface file in Files to Edit/Create).

## Architecture Decision (ADR/C4)

**No new ADR; no C4 change.** This is a bug fix on an existing surface: the verify's data-integrity
contract (0 real content diffs, all itemize codes counted, fail-closed on rsync error) is **unchanged**
— only stream handling + diagnostics change. A future engineer reading ADR-119 + C4 is not misled
about the system. The one in-scope doc task is a **one-line ADR-119 addendum** recording the new
`op=workspaces-luks-verify-diff` Better Stack marker in the observability taxonomy (ADR-119 already
documents `op=workspaces-luks-drift`) — an addendum to an existing ADR, not a new decision. C4 model
files (`model.c4`/`views.c4`/`spec.c4`) carry no element for the verify sub-step; external
actors/systems/data-stores are unchanged (no new vendor, actor, or access relationship) — no C4 edit.

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue references `workspaces-cutover.sh` or the verify block;
to be re-confirmed at /work via `gh issue list --label code-review --state open` grep of the two
edited file paths.)

## Test Scenarios (behavioral harness — `workspaces-luks-verify.test.sh`)

Harness: `source` the cutover script (sourced-detection guard → functions only); override `rsync`,
`logger`, `die`, `log`, `emit_drift` as shell functions; run each case in a subshell
(`( … verify_byte_identity SRC DST )`) with `die` stubbed to `exit 1`; capture stdout+stderr+rc and
the marker log (a file `logger` appends to). Each case is mutation-tested.

- **Case a — benign stderr, no abort:** stub rsync → rc=0, stdout empty, stderr
  `"file has vanished: \"$src/x\"\nrsync warning: some files vanished before they could be transferred (code 24)"`.
  Assert: no `die` (subshell rc=0), marker log empty. Mutation: revert to `2>&1`+`grep -c .` → case
  MUST flip to failing (stderr counted).
- **Case b — real content diff aborts + path visible:** stub rsync → rc=0, stdout
  `">f+++++++++ workspaces/ws1/secret.txt"`. Assert: `die` fired; captured stdout + marker log both
  contain `workspaces/ws1/secret.txt` and the `>f` code. Mutation: drop `emit_verify_diff` before
  `die` → path-visibility assertion MUST fail.
- **Case c — hard error fails closed:** stub rsync → rc=23, stderr `"rsync error: … (code 23) …"`,
  stdout empty. Assert: `die` fired with "verify rsync itself FAILED" AND the message/marker carries
  the stderr. Mutation: remove the rc-check → case MUST flip (a rc=23 with empty stdout would pass).
- **Case d — codes not narrowed:** stub rsync → rc=0, stdout `".f..t...... workspaces/ws1/a\n.d..t...... workspaces/ws1/"`.
  Assert: `die` fired (count=2), both lines in the diagnostic. Mutation: narrow the regex to `^>f` →
  case MUST flip (attribute-only codes uncounted).
- **Case e — clean verify passes:** stub rsync → rc=0, stdout empty. Assert: no `die`, no marker.

## Sharp Edges

- **Do NOT call `verify_byte_identity` in a subshell / pipe / `$(…)`** in the cutover main body — a
  subshell swallows `die`'s `exit 1` and the EXIT-trap rollback never fires. Call it directly (the
  test isolates cases in its OWN subshells, which is correct there).
- **Capture the stderr tail into a var BEFORE `rm`**ing the temp files — `die "$(tail "$verr")"` after
  `rm -f "$verr"` prints nothing. Same for the marker: `emit_verify_diff` reads `$vout` before any rm.
- **`emit_verify_diff` must run BEFORE both `rm` and `die`** (defect 2 is precisely "rm before log").
- **Log-injection:** a workspace filename is the founder's own content but still `_vscrub` every
  interpolated `path=`/`icode=`/`reason=` (strip CR/LF + non-printable) so a crafted name cannot inject
  a spurious `SOLEUR_…`/`::notice::` line (mirrors the annotation-CRLF-strip + `_wl_scrub` precedents).
- **Sourced-detection guard placement:** put it AFTER the new functions are defined and BEFORE the
  main body / `trap cleanup EXIT`, so sourcing in the test defines the verify machinery without arming
  the trap or running the cutover. Executed runs (`bash …`) evaluate the guard as a no-op.
- **rsync exit-code semantics:** the rc-check treats ANY non-zero as fail-closed (incl. 23/24). During
  a quiesced freeze a vanished-file exit-24 means the freeze invariant was violated — failing closed is
  correct. Do NOT relax the rc-check to "tolerate 24" (the task says preserve fail-closed).
- **A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan Phase 4.6** — this one
  is filled with a concrete artifact + exposure vector + `single-user incident` threshold.
- **Marker line length:** journald + Vector truncate long lines (`pii_scrub_string` slices >10000
  chars). Per-diff rows (one path each) stay short; the cap (40) bounds total volume.

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| **Extract the verify into a new sourced sibling** `workspaces-luks-verify.sh` (mirroring `workspaces-luks-emit.sh` / `cutover-gate.sh`) | **Rejected.** Couples to the `workspaces-luks-cutover.yml:175` tar manifest (must add the file, or the cutover `die`s at source time — or worse, a fail-open `[ -f ] && .` skips the verify = false-green). Inline-function + sourced-guard keeps the logic in the already-shipped `workspaces-cutover.sh` with zero bundle change. Lower blast radius on a sole-copy-data script. |
| **Only fix the stderr fold (defect 1), leave the count-only `die`** | Rejected. Diagnosability (defect 2) is the stated bug — the operator still couldn't tell which path aborted run 29676994044. |
| **Emit the itemized paths to Sentry tags** (new `op=workspaces-luks-verify-diff` on the Sentry channel) | Rejected as the primary channel. Sentry tags are size-bounded and would need the sentry_issue_alert `op IS_IN` filter widened. Better Stack (via the already-allowlisted `luks-monitor` tag) carries the itemized list with no filter/allowlist change; Sentry still gets a page via the existing `op=workspaces-luks-drift` reason. |
| **Relax the gate to tolerate mtime-only / dir-mtime diffs** | Rejected — explicitly out of scope: "do NOT narrow which itemize codes count." The fix makes those diffs *visible*, not *tolerated*. |
