---
title: "Shipping a credentialed live-reconcile CI job: workflow-copy fidelity, SSRF on paginated fetches, and the two Sentry-monitor parity tests"
date: 2026-07-17
category: best-practices
module: observability
issue: 6549
tags: [observability, github-actions, sentry, ssrf, workflow-copy, parity-test]
---

# Shipping a credentialed live-reconcile CI job (#6549 item 2)

## Problem

Building a nightly source-vs-live Better Stack heartbeat reconcile (a CI job that reads a vendor
API with a Bearer token, reconciles against a manifest, and pages on mismatch) surfaced four
recurring traps — each caught by review/CI, none by the plan or the green unit suite.

## Key insights

### 1. When you copy a workflow precedent, copy its FAIL-SAFE expressions verbatim — do not re-derive them

The new job mirrored the drift-check job but the Sentry check-in status was re-derived as
`rc == '1' && 'error' || 'ok'`. The precedent is `(exit_code == '0' || exit_code == '2') && 'ok' || 'error'`.
The difference is fail-**open** vs fail-**safe**: an empty `rc` (early-job failure → the reconcile
step is skipped) or an abnormal crash exit (137 OOM / 139 SIGSEGV / 124 timeout) evaluates the
re-derived form to `ok` — the job is broken but Sentry hears "alive". On the liveness monitor of a
job whose entire purpose is killing the 9-days-dark class, that reintroduces the exact defect. Three
review agents converged on it. **Rule: a copied precedent's status/exit expression is a contract, not
a starting point — mirror it, and additionally normalize any exit outside the script's own contract
into the error path (`if rc not in {0,1,2}: ::error:: + rc=1`).**

### 2. A credentialed fetch that follows response-body URLs OR HTTP redirects must pin the host — twice

`fetchLiveHeartbeats` followed `pagination.next` from the response body with the Bearer token
attached. Two exfil surfaces, both closed only after review:
- **Body-driven**: pin every `pagination.next` to the trusted host via `new URL(u).hostname === HOST`
  (never a `startsWith`/substring check — semgrep `js-incomplete-url-substring-sanitization` flags it,
  and it is genuinely bypassable).
- **HTTP-redirect**: `fetch` defaults to `redirect: "follow"`, which auto-follows a 3xx `Location`
  (MITM/DNS-takeover/compromised-edge) with the token still attached — the body-pin never sees it.
  Set `redirect: "manual"` and reject any 3xx fail-closed.

### 3. A NEW GHA-fired Sentry cron monitor needs TWO parity tests updated, not one

`apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` is one-way (code→IaC) and
**tolerates** GHA-fired monitors with no Inngest slug — so adding a `monitor-slug:` + the
`sentry_cron_monitor` resource satisfies it automatically. But `function-registry-count.test.ts`'s
`(c2)` assertion ("every cron-monitors.tf resource maps to a registered cron function OR GHA
workflow") requires the slug to be added to its `NON_INNGEST_MONITORS` set — a GHA-fired monitor
with no Inngest counterpart is otherwise flagged **phantom**. The plan anticipated only the first
test. **Rule: when adding a GHA-workflow-fired Sentry monitor (final `sentry-heartbeat` step, no
`cron-*.ts`), add its slug to `NON_INNGEST_MONITORS` in the same PR** — mirror the existing
`scheduled-terraform-drift` / `scheduled-supabase-advisor-scan` entries.

### 4. A `.c4` source edit is not done until `model.likec4.json` is regenerated

Editing `knowledge-base/engineering/architecture/diagrams/model.c4` passed `c4-code-syntax.test.ts`
and `c4-render.test.ts`, but the committed `model.likec4.json` (a rendered artifact) went stale and
`c4-model-freshness.test.sh` — which only runs in the full `test-all.sh` suite, not the touched-file
loop — failed. **Rule: after any `.c4` edit, run `bash scripts/regenerate-c4-model.sh` and commit the
updated `model.likec4.json` in the same change.** The render tests do not check the committed artifact.

## Session Errors

1. **`TaskCreate` schema not loaded** — array param rejected (schema not in the deferred-tool set). Recovery: used the plan's `tasks.md` as the checklist. **Prevention:** one-off; call `ToolSearch select:TaskCreate` first if formal task tracking is needed.
2. **Ad-hoc standalone `tsc --types node` failed** ("Cannot find type definition file for 'node'"). Recovery: confirmed `plugins/soleur` has no tsconfig/tsc gate — `bun test` is the authoritative gate there. **Prevention:** don't ad-hoc-invoke tsc for `plugins/soleur`; rely on `bun test`.
3. **Stale `model.likec4.json`** failed `c4-model-freshness.test.sh` in the full suite. Recovery: `scripts/regenerate-c4-model.sh` + commit. **Prevention:** insight #4 above (route-to-definition applied).
4. **semgrep flagged the SSRF *test*** (`url.startsWith` substring check). Recovery: `new URL().hostname`. **Prevention:** insight #2 — host comparison, never substring, in tests too.
5. **P1 Sentry-status fail-open** — re-derived instead of copied. Recovery: mirror the drift job + abnormal-rc normalizer. **Prevention:** insight #1.
6. **SSRF vector** on `pagination.next` + `redirect:follow`. Recovery: host-pin + `redirect:manual`. **Prevention:** insight #2.
7. **Inert SSRF test assertion** (`expect` inside the injected mock, throw swallowed by the SUT's retry `catch`). Recovery: capture a boolean, assert load-bearingly after the call. **Prevention:** already documented in `review/SKILL.md`'s vacuity catalogue ("assertions placed inside injected mocks whose throws the SUT's own catch swallows").
8. **Plan Phase 4.2 missed `function-registry-count.test.ts` (c2)**. Recovery: added the slug to `NON_INNGEST_MONITORS`. **Prevention:** insight #3.
