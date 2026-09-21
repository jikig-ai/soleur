# Tasks — fix: route op=registry-probe's non-200 branch through the dark-host gate

Plan: `knowledge-base/project/plans/2026-09-20-fix-registry-probe-dark-gate-plan.md`
Branch: `feat-one-shot-8079-registry-probe-dark-gate` · Issue: #8079 · Lane: single-domain (engineering)

> **Read `## Premise Correction` and `## Review Corrections` FIRST.** The issue argues from a
> pre-arm world that ended 2026-09-15. And the arm has **no `else`** (C1) — restructuring it is
> Phase 2, before any new logic, or a non-exiting `dark)` falls into the 200-path shape check and
> prints the raw body.

## 1. Phase 0 — live state and rebase

- [ ] 1.1 `doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh`. Expect `cutover_flag=done`, `server_active=active`, `http_code=200`. If it reads `rolled-back`/`aborted`, `dark` becomes the live branch, D8's `done` remedy is fixture-only, and Test Scenario 4 must be labelled synthetic.
- [ ] 1.2 Re-sync `main` (PR #8389 touches ADR-100 and `plugins/soleur/test/fixture-relative-assert.baseline.txt`).
- [ ] 1.3 Baselines are already measured in the plan's `## Research Insights` — re-run only if main moved.

## 2. Phase 1 — `_bs_read_remedy` (D4), alone

- [ ] 2.1 Read the function and its doc comment.
- [ ] 2.2 Add TRAILING `step="${5:-2.0}"`. **Do not touch either `execute)` call site.**
- [ ] 2.3 Replace all **nine** `::error::2.0 ` prefixes with `$step ` (the ninth is the trailing "NOTHING about the dedicated host was measured" summary).
- [ ] 2.4 Update the doc-comment signature line.
- [ ] 2.5 Update `mutate_file`'s known-negative `sed` to the new comment text.
- [ ] 2.6 Add the census assertion: inside the function body, `grep -c '::error::2\.0 '` is 0 and `grep -c '::error::\$step '` equals the total `::error::` line count.
- [ ] 2.7 Suite green; the two `probe read:` renders unchanged (necessary, not sufficient — there is no `heartbeat read:` render).

## 3. Phase 2 — restructure the arm (C1), before any new logic

- [ ] 3.1 Convert to `if [[ "$CODE" != "200" ]]; then <non-200> else <200 path unchanged> fi`.
- [ ] 3.2 Region-open marker immediately BEFORE `SIG=$(printf '' | openssl …)`; close marker immediately before the arm's `;;`.
- [ ] 3.3 Confirm the region sources cleanly under the existing render driver (it sets `BASE`/`WEBHOOK_SECRET`/`CF_ACCESS_*`/`INNGEST_HOST*` but NOT `CODE`/`BODY` — starting at `SIG=` is what avoids `CODE: unbound variable` under `set -u`). Verify, do not assume.
- [ ] 3.4 Suite green at 665 — structure-only.

## 4. Phase 3 — the 2.0 text corrections

- [ ] 4.1 Amend `:1434` and `:1515` to key on the `registry_empty=` marker (D9).
- [ ] 4.2 Add the Better Stack ingest/quota clause to 2.0's `silent)` remedy (D8).
- [ ] 4.3 Re-run; both renders pin prefixes only.

## 5. Phase 4 — the non-200 branch

- [ ] 5.1 `webhook_path` pre-refusal naming `op=inventory` **with the 200-vs-non-200 discrimination rule in the string**, before any Better Stack read.
- [ ] 5.2 Signature notice; the webhook body once, CR/LF-stripped, as a plain line.
- [ ] 5.3 Guarded `source` of the gate lib.
- [ ] 5.4 `mktemp -d` then IMMEDIATELY `trap 'rm -rf "$RPG_DIR"' EXIT`.
- [ ] 5.5 Two reads (24h probe / 30m heartbeat), stderr to files, rc into `RPG_PROBE_RC`/`RPG_HB_RC`.
- [ ] 5.6 `: > "$RPG_EMIT"`, then the gate call with `|| RPG_RC=$?`.
- [ ] 5.7 Emit read loop behind the shape regex; its inner `case` arms **single-line** (D10.1).
- [ ] 5.8 `dark)` — rc/token agreement, the D2 notice + two-clause warning (field named `registry_empty` with NO trailing `=`), NO exit.
- [ ] 5.9 `flag_armed)` — D8's **2×2**: outer on `__UNREAD__` picks the sample, inner picks `done` vs `armed|flipping|flushed`. Four messages. The probe-row `done` branch carries the ≤60-min staleness qualifier and must not interpolate `RPG_HB_AGE`.
- [ ] 5.10 `done` output shape: short `::error::` headline, ordered steps as plain lines, dispatchable read FIRST (`scheduled-inngest-health.yml`), then `inngest-host-state.sh` with prerequisites stated, then `inngest-host-replace`.
- [ ] 5.11 `host_serving)`, `silent)` per D8; `unreadable)`/`fsm_unreadable)` delegate with `"registry-probe"`.
- [ ] 5.12 The other five tokens: 2.0's host fact + one op-appropriate line. Do not author five bespoke strings.
- [ ] 5.13 `*)` sanitised, names the GATE as the defect. Every non-`dark` arm exits 1; every remedy ends `Do NOT SSH the host.`; none names a mutating op (D5).
- [ ] 5.14 Do NOT write `/hooks/deploy-status` into a code comment inside the arm (latent `hooks/deploy` collision).

## 6. Phase 5 — suite extension

- [ ] 6.1 D7 row 1 — per-arm census **plus** whole-file total `-eq 2`.
- [ ] 6.2 D7 rows 2/5 — one `PROBE_ARMS_CODE` with comments removed and the quoted ARGUMENT of each annotation `echo` stripped (not the line); the existing assertions ship unedited.
- [ ] 6.3 D7 row 3 — keep the total loop ban, allowlist the one known loop header.
- [ ] 6.4 D7 row 4 — re-aim `NO request body` so `-d`/`-T` must be adjacent to a `curl` (C2).
- [ ] 6.5 D7 row 5 — `FLQ_SITES` 6 → 8 with the enumerating message extended.
- [ ] 6.6 D10 guards: token coverage via the existing loop; plumbing parity by prefix normalisation; cross-arm remedy guard + `# twin:` comments.
- [ ] 6.7 Probe-arm static rows, region extraction + selection control, renders (scenarios 1-17), mutation rows M1.1-M1.5 and M2.1-M2.12.
- [ ] 6.8 **Do NOT** rename `render_2_0` and **do NOT** add re-aims for the two phantom assertions (C3).
- [ ] 6.9 Run the suite, read `_DISPATCHED` from its own failure message, set `_EXACT_FLOOR`. **Re-measure after the FINAL rebase.** Do not grow the itemised delta comment.

## 7. Phase 6 — runbook and gates

- [ ] 7.1 Runbook edits, each located by SECTION HEADING (edit (b) shifts the others). § "Cutover procedure" is NOT edited.
- [ ] 7.2 Include: the concurrency group in the operator-facing direction; "a red `restart-inngest-server` run is not a statement about this host".
- [ ] 7.3 Run and record verbatim: both suites, the dark-gate lib suite, the four repo-global ratchets BY HAND, `bash -n`, `shellcheck` if available.
- [ ] 7.4 Verify AC1-AC17 each against a named assertion or render, not by inspection.

## 8. Ship

- [ ] 8.1 Post the plan's `## Premise Correction` to #8079 before merge (plan `## Follow-Through Directives`).
- [ ] 8.2 PR body: `Closes #8079`; state which suites ran — `--capacity` measured CONTENDED, so do not claim a full gate.
- [ ] 8.3 `ship` Phase 6 renders `decision-challenges.md` (UC1 mechanism scope, UC2 dispatchable host-state, UC3 floor convention) into the PR body and files the `action-required` issue.
