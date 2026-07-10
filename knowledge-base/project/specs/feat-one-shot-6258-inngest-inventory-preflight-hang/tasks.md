# Tasks — fix inngest cutover pre-flight scan hang (#6258)

Plan: `knowledge-base/project/plans/2026-07-09-fix-inngest-cutover-preflight-scan-hang-plan.md`
lane: cross-domain (no spec.md — defaulted, fail-closed)
brand_survival_threshold: single-user incident (requires_cpo_signoff)

Deepen corrections folded in — see plan §"Deepen-Plan Findings (2026-07-09)".

## Phase 0 — Reproduce + measure (diagnosis-first, no mutation)

- [ ] 0.1 Re-run `op=inventory` + `op=verify`; record exact `HTTP <code>` per op from run logs.
- [ ] 0.2 Read live inngest-attributable pool (Management-API, read-only) at rest + during scan; classify 000 (hang) vs 500 (EMAXCONNSESSION).
- [x] 0.3 RESOLVED: `inngest-registry-probe.sh` is single-shot (no loop) → marker + `--connect-timeout` only, no deadline/ceiling. (Re-confirm at /work.)
- [ ] 0.4 Confirm `vector.service` ships from the co-located web host (`betterstack-query.sh --grep inngest`); resolve the "0 hits" cause. Do NOT assert without checking.
- [ ] 0.5 FEASIBILITY EXHIBIT (load-bearing): `inngest/inngest:v1.19.4` harness measures pages/corpus + per-page latency, and MUST show the all-events `event_names` scan fits the inventory deadline at raised `PAGE_SIZE`. If not → raise deadline+outer budget (under 30-min cap) or reconsider async. Do not /work on an unexhibited mechanism.

## Phase 1 — Bound + reduce scans (abandon-safe) [RED first]

- [ ] 1.1 Wall-clock deadline via `date +%s` delta (precedent ci-deploy.sh:1524-1535, NOT `SECONDS`), captured at run_inventory entry BEFORE fetch_functions. SUM-BOUND: clamp each page curl to remaining budget `--max-time=$((DEADLINE_S-elapsed))` (≥1) so `deadline+per_page ≤ outer`. Defaults: inv 22s, df 50s.
- [ ] 1.2 Page ceiling (`MAX_PAGES`), gated "about to fetch page > MAX_PAGES while hasNextPage=true" (exact-fit breaks clean).
- [ ] 1.3 Cost reduction — completeness by CONSTRUCTION: (a) armed_reminders via dedicated `eventNames:["reminder.scheduled"]` full-365d query (precedent enumerate-reminders.sh:82) — NEVER narrow inventory FROM_TS; (b) event_names via raised PAGE_SIZE (lossless) on the all-events scan; (c) doublefire via `functionIDs`+page-ceiling, window ⊇ cutover window (NOT a narrowed time window → false missed-ticks/double-fire).
- [ ] 1.3a Shared loud-abort helper: deadline + ceiling + existing empty-endCursor guard all `exit 1` (NEVER `break`) + `SOLEUR_*_TIMEOUT` marker; exit maps to webhook non-200.
- [ ] 1.4 `--connect-timeout` on every per-page curl incl. registry-probe.

## Phase 2 — Timeout hierarchy + bounded retry (NO wrapper)

- [ ] 2.1 Assert SUM bound `in-script deadline + per-page ≤ outer` (via remaining-budget clamp), not ordering.
- [ ] 2.2 NO `/usr/bin/timeout` hooks.json wrapper (dropped — Finding 10). hooks.json.tmpl NOT edited.
- [ ] 2.3 Bounded retry ONLY on op=inventory + op=verify TRANSPORT curls (not registry_empty precondition, not DI-C3 gate :565, not health probe). Same PR as bounding.

## Phase 3 — Observability marker (MANDATORY) — journald-ONLY

- [ ] 3.1 Emit `SOLEUR_INNGEST_PREFLIGHT_{START,DONE,TIMEOUT}` via `logger -t "$LOG_TAG" … 2>/dev/null||true` ONLY (NO `echo` — stdout is the JSON body). Mirror marker() FORMAT + C0/DEL+U+2028/2029 sanitizer (git-lock-chardevice-sweep.sh:81-82).
- [ ] 3.2 START = literal first line of run_inventory/run_probe (before fetch_functions). Fields {op,host,window,page_ceiling,deadline_s} on START; {pages_scanned,elapsed_ms,pages_timed_out,last_curl_exit,reason} on TIMEOUT — curl-exit field splits stall (exit 28) vs slow-scan.
- [ ] 3.3 Grep-confirm the three tags in `vector.toml` allowlist (L134/144/145) — this grep IS the drift guard (vector-pii-scrub.test.sh has none). No vector.toml edit.

## Phase 4 — Tests (RED→GREEN)

- [ ] 4.1 Per-script: deadline/ceiling `exit 1` (not break) + stdout NOT jq-parseable object; DIFFERENTIAL completeness (old vs new projection on same large corpus, reminder at each receivedAt band + cron name past page 1); FROM_TS byte-identical; doublefire window ⊇ cutover window; purity (no `://`, no `@…:…@`, errors→enum); marker journald-only + stdout stays JSON; START-first even on functions-query fail.
- [ ] 4.2 `cutover-inngest-workflow.test.sh`: SUM-bound timeout; abort→webhook non-200 (CODE!=200 cause-branch, not 200 shape guard); retry scoping.
- [ ] 4.3 shellcheck clean; `ship-deploy-pipeline-fix-gate.test.ts` green (no new script; TRIGGER_FILES unchanged).

## Phase 5 — ADR + runbook + verify-close

- [ ] 5.1 Create `ADR-106` (amends ADR-105; cross-ref ADR-105:109-143 §Precondition, don't re-derive two-writer); re-verify ordinal at /ship.
- [ ] 5.2 Update runbook §pool-pressure + §Dedicated-host cutover: pre-flight-hang triage + `SOLEUR_*` query + op=verify verdict≠transport-200 note.
- [ ] 5.3 (post-merge, automated in /ship) after auto-apply: op=inventory HTTP 200 (primary); op=verify sub-probe transport no 000/500 (job may halt at registry_empty — NOT gated); health-probe still 200; query START marker; `gh issue close 6258` with evidence. PR body uses `Ref #6258`.
