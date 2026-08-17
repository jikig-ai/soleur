# Tasks — fix #7590 Sentry audit rules-API deprecation

Derived from
`knowledge-base/project/plans/2026-08-17-fix-sentry-audit-rules-api-deprecation-plan.md`
(post-plan-review). Scope challenges live in `decision-challenges.md` beside this file.

Target: `apps/web-platform/scripts/sentry-monitors-audit.sh`

---

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Probe all six Sentry endpoints via `doppler run --project soleur --config prd`, using
      **`SENTRY_IAC_AUTH_TOKEN`** (not `SENTRY_AUTH_TOKEN` — Doppler `prd` holds both, with
      different values). Record status + headers for the PR body, naming the token used.
- [ ] 0.2 Confirm `organizations/{org}/workflows/` and `organizations/{org}/detectors/` return
      arrays, carry **no** deprecation headers, and are readable by `SENTRY_IAC_AUTH_TOKEN`. If
      either has gained a deprecation header, stop and re-plan.
- [ ] 0.3 Baseline already measured — `14 passed, 0 failed`. Do not re-derive.

## Phase 1 — Transport seam (blocks every test; do first)

- [ ] 1.1 Add a transport-level seam to `curl_retry` (`CURL_BIN="${CURL_BIN:-curl}"`, or a `curl`
      stub prepended to `PATH`). The existing `SENTRY_FIXTURE_*` seams `cat` a file and `return`
      **before curl runs**, so they cannot express a status, header or retry sequence.
- [ ] 1.2 Define and document the seam contract: how a test declares a status sequence, response
      headers and body per URL. **Read an existing stub first** — `upload-evidence.test.sh`,
      `upload-bypass.test.sh` (both `apps/cla-evidence/scripts/`), or
      `apps/web-platform/infra/doppler-download-error-channel.test.sh` — and match the established
      shape rather than adding a fourth dialect.
- [ ] 1.2a The stub must record the **host actually requested**, so T20b can assert no request left
      `$api_host`. Asserting only "no error" is satisfied by a silently-followed redirect.
- [ ] 1.3 Add the seam to the script header's "Test injection" block.

## Phase 2 — `curl_retry` rewrite (contract change; precedes its consumers)

- [ ] 2.1 Capture response headers with **`-D` only**. Never add `-w` or `-o` inside the wrapper —
      Gates 2/3 pass their own `-w` and read stdout as the status, while Gate 1 and the fetches read
      stdout as the body. Duplicate `-w` is last-wins.
- [ ] 2.2 Parse the status from the **last** `HTTP/` line of the header dump (redirects emit several).
- [ ] 2.3 Classify: retry `429`/`5xx`; never retry `410`/`404`/`401`/`403`.
- [ ] 2.4 Restrict status-based retry to **safe methods**. The Gate 3 `POST /releases/` keeps
      transport-only retry — `probe_ver` is computed once outside the wrapper, so a retried write
      returns 208 and Gate 3 hard-fails with a false scope diagnosis.
- [ ] 2.5 **Classify only, never exit.** Preserve "return last attempt's output, exit 0" — every call
      site is `x=$(curl_retry …)` under `set -euo pipefail`.
- [ ] 2.6 Publish status + header-file path through exported shell variables
      (`CURL_RETRY_LAST_STATUS` / `CURL_RETRY_LAST_HDR`) for the shape check to consume.
- [ ] 2.7 Clean up the header temp file on every path. Keep the bounded 3-attempt ceiling.

## Phase 3 — Deprecation tripwire

- [ ] 3.1 Check captured headers for `x-sentry-deprecation-date` (case-insensitively — `-D`
      preserves wire casing).
- [ ] 3.2 Warn once per distinct endpoint, naming endpoint, date and replacement. Dedupe across a
      paginated fetch.
- [ ] 3.3 Escalate to a failing exit once the deprecation date is inside the configured window; pin
      the window in the ADR amendment and state the escape hatch for an endpoint with no replacement.

## Phase 4 — Fetch migration, pagination, diagnostic, orphan remap

- [ ] 4.1 Replace `fetch_rules()` with `fetch_workflows()` + `fetch_detectors()`. Both replacements
      are **org-scoped**, so the `SENTRY_PROJECT` branch dissolves. Keep `SENTRY_PROJECT` — Gate 2,
      Gate 3 and the report frontmatter still use it.
- [ ] 4.2 Add cursor-following for `detectors/` and `monitors/` (both grow with cron monitors; a
      loud failure there deadlocks the deployment path). `workflows/` may keep a simple loud check.
- [ ] 4.2a **Never follow a `Link` target as given.** Sentry's Link headers are absolute; following
      them sends `SENTRY_IAC_AUTH_TOKEN` wherever the header points. Extract only the `cursor`
      parameter and rebuild the URL from the validated `$api_host`. Read `link_next` in
      `scripts/zot-inventory.sh` first — it documents the `<@attacker.tld/…>` userinfo attack,
      measured against curl 8.18.0, and its rejection arm.
- [ ] 4.2b Add a `MAX_PAGES` ceiling and a truncation counter (`LINK_UNFOLLOWED` shape). Any refusal
      or ceiling-hit must **suppress the clean-state string** — never emit a clean verdict over a
      set that was not fully enumerated.
- [ ] 4.3 Add `SENTRY_FIXTURE_DETECTORS`, and make the detectors fetch **inherit fixture mode**:
      when `SENTRY_FIXTURE_RULES`/`_MONITORS` is set and `_DETECTORS` is not, serve `[]` rather than
      reaching the network — otherwise the 13 existing tests start making live calls and go red.
- [ ] 4.4 Replace the bare `is not a JSON array` error with the self-naming diagnostic: status,
      resolved host, full URL, which fetch, deprecation headers when present, plus a verdict field
      distinguishing "5xx exhausted → re-run" from "410 deprecated → migrate".
- [ ] 4.5 Remap Class A to `monitor_check_in_failure` detectors with empty `workflowIds`; report a
      **count plus the invariant** `class_a_count == cron_detector_count`, not a per-slug list.
- [ ] 4.6 Remap Class B to cron-detector `dataSources[].queryObj.slug` with no live monitor row.
- [ ] 4.7 Remap Class C to workflows with `[.triggers.actions[]?] + [.actionFilters[]?.actions[]?]`
      empty.
- [ ] 4.8 Add the fail-closed extraction guard modelled on Class D's `declared_slugs` check: zero
      cron detectors while `monitors_json` is non-empty is an extraction failure, not a clean org.
- [ ] 4.9 Add not-evaluated states: if `detectors/` fails while `workflows/` succeeds, mark Classes A
      and B not-evaluated and suppress the clean-state string.
- [ ] 4.10 Emit the structured-pass count into the report so "structured found it" is
      distinguishable from "fallback found it" (makes the structured-first property verifiable).
- [ ] 4.11 Retire the `<!-- ids: -->` manifest (no live consumer; adoption complete at 29 resources).
- [ ] 4.12 Correct the report: `Project filter:` frontmatter, the hardcoded clean-state string (it
      enumerates the old class definitions verbatim), the `## Alert Rules` heading, and add
      provenance (source endpoints + orphan-predicate generation).
- [ ] 4.13 Verify the `## Alert Rules` table renderer against the workflows shape — a `null` name
      column is a quiet report regression.

## Phase 5 — Tests

- [ ] 5.1 T15 — workflows+detectors payload yields correct orphans.
- [ ] 5.2 T16 — 410 + deprecation headers produces the self-naming diagnostic (assert on the
      replacement-endpoint substring, not a bare `ERROR` token).
- [ ] 5.3 T17 — deprecation headers on a 200 warn and exit 0.
- [ ] 5.4 T18 — retry classification + stdout byte-identity at both call-site shapes, including
      500-then-208 on the POST.
- [ ] 5.5 T19 — Class B against the detector binding; a generic tag value is not flagged.
- [ ] 5.6 T20 — pagination followed, not truncated.
- [ ] 5.6a T20b — hostile Link target refused (absolute URL, and `@`-bearing userinfo form). Assert
      the stub's recorded host, and that the clean-state string is suppressed.
- [ ] 5.6b T20c — `MAX_PAGES` ceiling terminates the loop and sets the truncation counter.
- [ ] 5.7 T21 — extraction-failure guard.
- [ ] 5.8 Refixture the rules-shaped tests the schema change invalidates (T3/T5/T8/T9/T11/T12).
- [ ] 5.9 Add the per-guard harness rows (tests of the suite, not the script), including the
      Guard 1 mutation-3 anti-vacuity floor — which lives in the **suite**, not the script.
- [ ] 5.10 Fixtures synthesized per `cq-test-fixtures-synthesized-only` — invented org/project/slug
      values, low-entropy ids. No captured production payload.

## Phase 6 — Docs, workflow corrections, follow-up

- [ ] 6.1 ADR-031 amendment: endpoint mapping + header provenance; brownout-not-removal citing
      `versions.tf`'s 2026-07-17 "transient" misread; Class A predicate change and its invariant;
      the `curl_retry` defect and repair; the write-probe idempotency restriction; the tripwire and
      its escalation window.
- [ ] 6.2 Correct deprecated-path references in the ADR body **in place**, not only by appending.
- [ ] 6.3 Fix the script header's now-false "joins the two on `monitor.slug` references" description.
- [ ] 6.4 Document the `SENTRY_IAC_AUTH_TOKEN` → `SENTRY_AUTH_TOKEN` env-rename trap in the header.
- [ ] 6.5 Remove **both** false required-check claims from `.github/workflows/sentry-audit-gate.yml`
      (header line 1 and line 18).
- [ ] 6.6 Fix `.github/workflows/reusable-release.yml`'s stale audit-failure warning (it quotes an
      error string the script cannot emit and a `de.sentry.io` default corrected in May).
- [ ] 6.7 Retire the stale first-time adoption runbook in `apps/web-platform/infra/sentry/README.md`
      (it says 4 rules; there are 29).
- [ ] 6.8 File the Decision 6 follow-up: *"Split Sentry Audit Gate into a hermetic gates job and an
      advisory live-API job"*, labels `type/chore` + `domain/engineering`, first AC
      *"`AUDIT_MODE=gates` exists and `apply-sentry-infra.yml` uses it."*

## Phase 7 — Verification

- [ ] 7.1 Work through all 22 Acceptance Criteria in the plan.
- [ ] 7.2 `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` — green, count ≥ 14 + new.
- [ ] 7.3 `bash tests/scripts/test-sentry-monitors-audit-class-d.sh` — all 13 pass.
- [ ] 7.4 `bash scripts/lint-orphan-test-suites.sh` — `0 orphaned`. **Do not** add a `run_suite`
      line for the unit suite; it is already glob-registered and an explicit line double-registers it.
- [ ] 7.5 AC14 gate-block byte-identity diff (anchored awk form from the plan — the naive range
      self-matches and returns 364 lines instead of 61).
- [ ] 7.6 PR body: endpoint table naming the token, the env-rename trap, Decision 6's
      recommendation, and `Closes #7590`.

---

## Do NOT do

- Do **not** add `-w` or `-o` inside `curl_retry` (breaks Gate 1, both fetches, and Gates 2/3).
- Do **not** add an explicit `run_suite` line to `scripts/test-all.sh` for the unit suite.
- Do **not** size any retry to the brownout window (H4 is UNKNOWN; the window is a Sentry-side
  runtime option).
- Do **not** map workflow ids to rule ids by name (duplicate names are legal in Sentry).
- Do **not** delete Class A or add `AUDIT_MODE=gates` without an explicit decision — both are
  recorded as scope challenges in `decision-challenges.md`.
