---
title: A stub at the wrong fidelity boundary hid that the SUT never asked for JSONEachRow
date: 2026-10-08
category: workflow-patterns
tags: [workflow-patterns, test-seams, betterstack, clickhouse, fixtures, review-panel]
issue: '#9175'
---

# Learning: a transport stub must honor the transport's contract, not the SUT's hope

## Problem

`inngest-provision-rehearsal-capture.sh` queries Better Stack's ClickHouse over
`betterstack-query.sh`, which runs the SQL **verbatim** — nothing is appended.
ClickHouse's HTTP endpoint defaults to **TabSeparated** output; the capture's
`jq -r '.n'` anchor parse therefore reads 0 on the real path forever — every poll
of every mode would have returned TRANSIENT until the workflow deadline, burning a
paid rehearsal host to produce a verdict that measured nothing.

The capture suite was fully green (23/23) because its stub — `bs-stub.py` — emitted
`{"n": …}` JSON **unconditionally**: it answered what the SUT *wanted*, not what the
transport *delivers*. The seam sat at the wrong fidelity boundary: "same
raw/JSONEachRow contract as the real transport" was asserted in the stub's comment,
never enforced in code. The code-quality review seat caught it by tracing the query
path end-to-end against the sibling (`git-data-rung2-evidence-capture.sh` ends every
SQL in `FORMAT JSONEachRow`).

## Solution

Two-sided fix:

1. The SUT: `FORMAT JSONEachRow` appended to all three queries.
2. The stub: `if "FORMAT JSONEachRow" not in sql: emit TSV` — the harness now models
   the transport's *default*, so a SUT that forgets the clause sees 0 parseable rows
   and the suite goes red.

The general pattern: **when a stub replaces a transport, replicate the transport's
defaults, not just its happy shape** — "the endpoint answers SQL" is not the contract;
"the endpoint answers SQL in TSV unless FORMAT is requested" is. Any fidelity the
fixture skips becomes an unmeasured degree of freedom the SUT can silently violate.

## Sibling findings from the same panel (same root cause class)

- A `doppler run` rc=1 without the script's terminal verdict sentinel is a *wrapper*
  fault, not a host FAIL — the poll must grep the sentinel before interpreting rc
  (mirrors the rung2 fix, which exists because this exact mis-attribution burned a
  paid host once already).
- "Every-row claims" (`zero provision markers after the boundary`) read from a
  `LIMIT 2000` window must either order so truncation can only hide PASS evidence
  (DESC, since violations are newer than anchors) or refuse the bound-hit page.
- `ORDER BY dt ASC` + naive `dt >` boundaries also needed the ClickHouse `'UTC'`
  session-TZ pin — a naive datetime parses in the session timezone.

## Session Errors

1. Test-fixture fidelity masked a P0 (this learning's subject).
   **Prevention:** stubs emit the transport's *default* format; fidelity claims in
   fixture comments get a counterpart assertion in the stub itself.
2. `yes`-eval'd python in the sentinel suite broke on `$OUT` expansion through the
   nested quoting layers.
   **Prevention:** compute positions into shell vars outside `eval` arms; never put
   `$VAR` inside a doubly-eval'd program string.
3. Regex surgery on fixture strings consumed a closing quote → bash syntax error;
   fixed in two passes.
   **Prevention:** when editing fixture blocks by script, verify `bash -n` before
   moving on.
4. Design-pass defects the panel caught: Phase-B required `private_nic_ok`
   (unreachable in the happy path — the nic-wait helper only runs when the IP is
   absent); teardown `destroy` omitted the required `zot_pull_token`; post-reboot
   anchored liveness on the channel whose silence was under test;
   `bootstrap-done-DEGRADED` matched the `bootstrap-done` needle.
   **Prevention:** the two-seat design pass before the panel is what caught these —
   keep it mandatory for mechanism-introducing diffs.
5. `phase-a-since.txt` was written pre-apply but never passed to the phase-A
   capture (`--since` unwired) — a same-run-id re-run's prior-life rows could have
   satisfied the gate.
   **Prevention:** when a file is produced for another step, grep the consumer for
   the read before calling the wiring done; an arm exercising `--since` now exists.
6. `printf 'K=%s' >> $GITHUB_ENV` on a Doppler-fetched value re-shipped the
   newline-injection class the infra-credentials action already fixed (heredoc
   delimiters).
   **Prevention:** sibling code is precedent *including its known defects* — when
   copying, grep the source file for the fix comments (`#7481`, `K=V`) first.
   Filed for the sibling route as #9817.
7. The drift sweep's `scratch_env_probe` emitted `unsatisfiable`/`failed` to a
   channel nobody reads (a green cron log).
   **Prevention:** every probe output needs a consumer check — ask "who fails if
   this arm fires?" before shipping the probe.

## Prevention (aggregate)

- For guard-shaped diffs, the structural-enumeration seat pays for itself: it
  mapped value-space binds (`config = "prd"` inside `.rehearsal` blocks),
  file-shape escapes (`*.tf.json`, `*.auto.tfvars`, module dirs), and language
  surfaces (provisioners, outputs) that address-token greps structurally miss.
  Sentinel suites pinning "the root contains exactly {files}" and "no provisioner
  anywhere" are cheap and close whole classes.
