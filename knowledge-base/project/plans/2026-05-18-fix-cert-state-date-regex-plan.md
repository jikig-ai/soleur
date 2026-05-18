---
type: bug-fix
lane: single-domain
requires_cpo_signoff: false
issue: 4016
related_prs: [4006]
related_issues: [3976, 3974, 3986]
---

# fix(infra): scheduled-gh-pages-cert-state regex accepts date-only `expires_at` from GH Pages API

## Enhancement Summary

**Deepened on:** 2026-05-18
**Sections enhanced:** 6 (Overview, Research Reconciliation, Acceptance Criteria, Risks, Implementation Phases, Sharp Edges)
**Research sources used:** Live GitHub Pages REST docs (WebFetch), live `gh api /repos/.../pages` response, Ubuntu 24.04 docker repro of `date -u -d` semantics, sibling workflow `scheduled-cf-token-expiry-check.yml` cross-check, learnings `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md` and `2026-04-22-plan-ac-external-state-must-be-api-verified.md`.

### Key Improvements

1. **Confirmed `expires_at` is `string, format: date`** per the official GitHub REST docs — date-only (`YYYY-MM-DD`) is the *specified* contract, not an accident. PR #4006 lifted the strict ISO-datetime regex verbatim from `scheduled-cf-token-expiry-check.yml` (which polls Cloudflare's API returning ISO 8601 datetime) without verifying the GH Pages API contract — a textbook miss against learning `2026-05-12-plan-time-api-contract-verification-...`.
2. **Verified the proposed fix on an Ubuntu 24.04 docker container** (the GHA `ubuntu-latest` base): all four fixture cases (date-only, datetime, garbage, empty) produce the expected exit codes and epoch math. `date -u -d "2026-08-16 23:59:59 UTC" +%s` returns `1786924799` — stable GNU coreutils form.
3. **Documented the API-contract miss as the root-cause class** in Research Reconciliation so the next plan editing similar polling workflows applies the verify-third-party-API-contract gate at write-time, not at run-time.
4. **Added a sibling workflow audit AC** — verify `scheduled-cf-token-expiry-check.yml`'s regex is still correct for the Cloudflare API contract (which DOES return ISO 8601 datetime). Confirmed in deepen-pass: cf-token contract is `ISO 8601` per Cloudflare docs precedent. No fold-in needed; cf-token regex is correct as written.
5. **Confirmed actionlint baseline is clean** on the pre-edit workflow; the edit preserves YAML structure (regex-only change inside an existing `run:` block) so post-edit actionlint will remain clean.
6. **Documented STATE_OVERRIDE interaction** explicitly — when manual smoke-test mode is engaged, `EXPIRES_AT` is cleared (line 120), so the regex block is short-circuited by the existing `-n "$EXPIRES_AT"` guard at line 134. The fix touches neither the smoke-test path nor the state-trip path.

### New Considerations Discovered

- The original PR #4006 plan (`2026-05-18-add-gh-pages-cert-state-daily-poll-plan.md:24`) called out the data shape via the field name (`https_certificate.expires_at`) but referenced the *documentation page* (line 112) without quoting the field's documented type — exactly the failure mode learning `2026-04-22-plan-ac-external-state-must-be-api-verified.md` is designed to catch. The deepen-pass on this fix has explicitly verified the contract via WebFetch + live API.
- Sibling workflow `scheduled-cf-token-expiry-check.yml:92-99` carries the *identical* strict-ISO-datetime regex pattern. For Cloudflare's `expires_at` (ISO 8601 datetime), this is correct — but the visual similarity of the two workflows is what enabled the verbatim copy that broke `scheduled-gh-pages-cert-state.yml`. Adding a one-line code comment in the new branch (`# GitHub Pages API returns date-only per docs — datetime branch is defensive`) is a low-cost guard against future re-paraphrase.
- `expires_at` is `null` when `state` is `bad_authz` or other non-issued states. The existing `-n "$EXPIRES_AT"` guard at line 134 already short-circuits that path; no new handling needed.

## Overview

The `poll-cert-state` step in `.github/workflows/scheduled-gh-pages-cert-state.yml` validates `https_certificate.expires_at` against a strict ISO datetime regex (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}`). The GitHub Pages API actually returns a date-only value (`"2026-08-16"`), so every cron fire short-circuits to `exit 1` with `##[error]Unexpected expires_at format from API: '2026-08-16'`.

Symptoms (from issue #4016 / run [26043693478](https://github.com/jikig-ai/soleur/actions/runs/26043693478)):

- Sentry heartbeat pages with `error` status — but for an API-format-mismatch, not a real cert trip.
- The trip-condition logic (days-remaining math, auto-issue filer, recovery auto-close) never executes.
- The 21-day advance-warning premise of PR #4006 (and the 2026-05-18 cert outage post-mortem) is currently **not delivered**.

Fix: widen the regex to accept BOTH `YYYY-MM-DD` (the actual API shape) AND full ISO datetime (defensive — keep accepting it if the API ever upgrades). For date-only values, treat as end-of-day UTC for the days-remaining calculation so the threshold check stays conservative (a cert expiring at 23:59:59 UTC on day N is "0 days remaining" when polled at 00:00 UTC on day N, not "-1 days").

## User-Brand Impact

**If this lands broken, the user experiences:** continued silent cert-expiry risk — the daily poll continues to error-out with API-format-mismatch, so a real cert trip in the [now, 21d-before-expiry] window goes undetected until the cert actually expires and `soleur.ai` returns Cloudflare 526 (the exact failure the 2026-05-18 incident produced).

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no user data path; the workflow reads a public-ish vendor metadata endpoint with `GITHUB_TOKEN` and writes issues to this repo. No regulated-data surface.

**Brand-survival threshold:** aggregate pattern — a single failed cron fire is not user-facing; an aggregate pattern of failed fires (i.e., the current state) is what produces the cert-expiry blindspot. CPO sign-off not required.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| Issue body: "the workflow's `poll-cert-state` step asserts the API's `expires_at` matches an ISO datetime regex" | Confirmed at `.github/workflows/scheduled-gh-pages-cert-state.yml:135-138` — exact regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}` | Replace with two-branch conditional accepting date-only OR full ISO datetime. |
| Issue body: API returns `"2026-08-16"` | Confirmed by failed run [26043693478](https://github.com/jikig-ai/soleur/actions/runs/26043693478) log line `##[error]Unexpected expires_at format from API: '2026-08-16'`. Re-confirmed in deepen-pass via live `gh api /repos/jikig-ai/soleur/pages \| jq '.https_certificate'` → `{"state":"approved","expires_at":"2026-08-16","expires_at_type":"string"}`. | Date-only is the canonical shape; ISO datetime kept as a tolerated alternate. |
| **PR #4006 plan (`2026-05-18-add-gh-pages-cert-state-daily-poll-plan.md`) — implicit `datetime` assumption.** The PR-#4006 plan named the data shape via field name (`https_certificate.expires_at`) but did not quote the documented TYPE; the regex was lifted verbatim from `scheduled-cf-token-expiry-check.yml` (which polls Cloudflare and DOES receive ISO 8601 datetime). | **Official GitHub REST docs (`docs.github.com/en/rest/pages/pages#get-a-github-pages-site`) specify `https_certificate.expires_at` as `string, format: date`** (WebFetched 2026-05-18). RFC 3339 §5.6 full-date = `YYYY-MM-DD`, no time component. | Document the API-contract miss in the deepen-pass so the verify-third-party-API-contract gate (learning `2026-05-12-plan-time-api-contract-verification-...`) is applied at write-time on future polling workflows. The fix here is the load-bearing remediation. |
| Suggested fix uses `date -u -d "$EXPIRES_AT 23:59:59 UTC" +%s` | Verified locally (Ubuntu 26.04 / uutils coreutils 0.8.0) AND in `docker run --rm ubuntu:24.04 bash -c '...'` (GHA `ubuntu-latest` base, GNU coreutils): `date -u -d "2026-08-16 23:59:59 UTC" +%s` → `1786924799`. Date-only `date -u -d "2026-08-16" +%s` → `1786838400`. Difference = 86399 s ≈ 1 day. ISO datetime `date -u -d "2026-12-31T12:00:00Z" +%s` → `1798718400`. Garbage `date -u -d "not-a-date"` → `exit 1` with `date: invalid date 'not-a-date'`. | Use the EOD-UTC form so a same-day poll reports `0d remaining`, not `-1d`. Conservative for the WARN_DAYS=21 threshold. |
| **Sibling workflow `scheduled-cf-token-expiry-check.yml:92-99` carries the identical strict-ISO-datetime regex.** | Cloudflare's `expires_at` IS ISO 8601 datetime (precedent at the cf-token workflow comment line 92: `# Validate ISO 8601 format before passing to date`). The cf-token regex is correct against its own API contract — no fold-in needed. | Out of scope for #4016. Add a one-line code comment to the new GH Pages branch noting `# GitHub Pages API returns date-only per docs — datetime branch is defensive` to guard against future re-paraphrase. |

## Research Insights

**Best Practices (from `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md`):**

- When a plan FR/AC names a specific third-party API endpoint, query parameter, HTTP verb, or filter shape, verify the **contract** at plan-write time via WebFetch of the canonical docs URL, OpenAPI/Swagger grep, or sandbox curl. The PR #4006 plan named the field but did not quote the documented type — exactly the failure mode the learning is designed to catch.
- The fix here applies the gate retroactively: WebFetch returned `"string, format: date"` from `docs.github.com/en/rest/pages/pages?apiVersion=2022-11-28`; live `gh api` confirms `expires_at = "2026-08-16"` of JSON type `string`.

**Best Practices (from `2026-04-22-plan-ac-external-state-must-be-api-verified.md`):**

- AC claims about external-service state (Doppler values, Supabase rows, Cloudflare applied state, GitHub secret presence, GH Pages cert state) must be verified via the actual API at plan time. Code-grep confirms consumers exist, NOT that the state holds the expected shape — these are different questions.

**Implementation Details (verified fixture run on Ubuntu 24.04, GHA-equivalent):**

```bash
# Three fixture cases for the proposed fix
EXPIRES_AT="2026-08-16"
# Branch 1: date-only → EXPIRES_EPOCH=1786924799, DAYS_REMAINING=90 (relative to 2026-05-18), exit=0

EXPIRES_AT="2026-12-31T12:00:00Z"
# Branch 2: ISO datetime → EXPIRES_EPOCH=1798718400, DAYS_REMAINING=226, exit=0

EXPIRES_AT="not-a-date"
# Branch 3: rejected → ::error::Unexpected expires_at format from API: 'not-a-date', exit=1
```

**Edge Cases:**

- `expires_at` is `null` when `state` is `bad_authz` or any non-issued state. The existing `-n "$EXPIRES_AT"` guard at line 134 already short-circuits that path; no new handling needed in either branch.
- `STATE_OVERRIDE` smoke-test mode (workflow_dispatch input) clears `EXPIRES_AT` at line 120, so the regex block is short-circuited by the `-n` guard above; the fix does NOT alter the smoke-test surface.
- Empty-string `EXPIRES_AT` falls through to the `else` (rejected) branch in the fix — but cannot reach the regex block at runtime due to the upstream `-n` guard. Defense-in-depth: the rejection of empty string is the *desired* fallback if a future edit removes the `-n` guard.

**Anti-Patterns to Avoid:**

- DO NOT remove the `-n "$EXPIRES_AT"` guard at line 134 thinking the regex now handles empty input — both layers are load-bearing (the guard avoids reaching the regex when state is non-issued; the regex enforces format when a non-empty value arrives).
- DO NOT replace `date -u -d` with `date -d` to "simplify" — explicit UTC matters when GitHub Actions runner-image timezone could drift (none currently, but the `-u` flag is the drift-resilient form).
- DO NOT use `date -Iseconds` to "normalize" the input — the input value is what we're validating; normalization would mask the API-contract drift.

**References:**

- GH REST docs: `https://docs.github.com/en/rest/pages/pages?apiVersion=2022-11-28` — `https_certificate.expires_at` documented as `string, format: date`
- RFC 3339 §5.6 (full-date grammar)
- Sibling precedent: `.github/workflows/scheduled-cf-token-expiry-check.yml:92-99` (correct ISO 8601 datetime regex for Cloudflare API)
- Failed run: [26043693478](https://github.com/jikig-ai/soleur/actions/runs/26043693478)
- Live API: `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate'` → `{"state":"approved","expires_at":"2026-08-16",...}`

## Hypotheses

None — the failure mode is fully diagnosed in the issue body and confirmed by the linked workflow run log. No SSH/network surface; no IaC routing required (single-file `.github/workflows/` edit).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/scheduled-gh-pages-cert-state.yml` accepts `EXPIRES_AT="2026-08-16"` without exiting 1, and computes `EXPIRES_EPOCH=1786924799` (EOD UTC).
- [ ] `.github/workflows/scheduled-gh-pages-cert-state.yml` continues to accept `EXPIRES_AT="2026-12-31T12:00:00Z"` (defensive — API may upgrade) and computes `EXPIRES_EPOCH=1798718400`.
- [ ] `.github/workflows/scheduled-gh-pages-cert-state.yml` still rejects `EXPIRES_AT="not-a-date"` / `EXPIRES_AT="2026/08/16"` / `EXPIRES_AT="08-16-2026"` with `::error::Unexpected expires_at format from API: '<value>'` and `exit 1`. Error-message literal (`Unexpected expires_at format from API`) is preserved verbatim so any operator dashboard or Sentry breadcrumb keyed on it continues to fire.
- [ ] `DAYS_REMAINING` for `EXPIRES_AT="2026-08-16"` polled on a UTC day equals `floor((EOD_UTC_2026-08-16 - now) / 86400)` — verified by stepping through with `bash -c '<extracted snippet>'` against the modified `run:` body (the canonical-form check from sharp edge `bash -c '<extracted snippet>'`, NOT `bash -n <file.yml>`).
- [ ] `actionlint .github/workflows/scheduled-gh-pages-cert-state.yml` is clean (baseline confirmed clean pre-edit at deepen-pass).
- [ ] `shellcheck` over the extracted `run:` block reports no new findings (baseline shellcheck warnings, if any, captured pre-edit and re-confirmed post-edit).
- [ ] The new branch adds a one-line code comment: `# GitHub Pages API returns "string, format: date" per docs — datetime branch is defensive.` (Prevents future re-paraphrase from `scheduled-cf-token-expiry-check.yml`.)
- [ ] PR body uses `Closes #4016` (regular bug fix, applied at merge, not ops-remediation — the fix is in-code, no post-merge operator action required for resolution).
- [ ] No edit to `scheduled-cf-token-expiry-check.yml` — its strict-ISO regex is correct for the Cloudflare API contract.

### Post-merge (operator / automated via `/soleur:ship`)

- [ ] Trigger one manual run with the real API state: `gh workflow run scheduled-gh-pages-cert-state.yml --ref main`. Expected: green run, no `expires_at format` error, heartbeat = ok, `days_remaining` populated as an integer ≥ 1 (current cert expires 2026-08-16; expected ~90 days remaining).
- [ ] Trigger a smoke-test run with `state_override="bad_authz"` and confirm the alert path still files an issue (defends against breaking the trip-condition logic). Expected: heartbeat = error, issue filed under `[cert-poll] soleur.ai cert state = bad_authz`.
- [ ] Close the auto-filed smoke-test issue via `gh issue close <N>`.

  Automation feasibility: all three steps are `gh workflow run` / `gh issue list` / `gh issue close`. They run post-merge on `main` because the workflow file must be on the default branch for `workflow_dispatch` to dispatch from there. `/soleur:ship` already runs `gh workflow run` for modified workflows on merge (per ship/SKILL.md:508-1177); this plan inherits that path.

## Test Strategy

This is a workflow-shell change. The repo convention for workflow tests is to extract the `run:` body and invoke it with `bash -c '<snippet>'` against fixture inputs (per the sharp edge: `bash -c` on extracted shell, never `bash -n <file.yml>`). No new test framework is required.

Three fixture cases run inline during `/work` Phase 3 (RED-GREEN):

1. **Date-only happy path** — `EXPIRES_AT="2026-12-31"`, expect days-remaining computed against `2026-12-31 23:59:59 UTC`, no exit 1.
2. **Datetime defensive path** — `EXPIRES_AT="2026-12-31T12:00:00Z"`, expect days-remaining computed against the exact timestamp, no exit 1.
3. **Garbage rejection** — `EXPIRES_AT="not-a-date"`, expect `::error::Unexpected expires_at format from API: 'not-a-date'` and `exit 1`.

A `bash -c '<extracted snippet>'` harness against these three fixtures is sufficient. No bats / no new dependency.

## Files to Edit

- `.github/workflows/scheduled-gh-pages-cert-state.yml` — replace the single regex-and-`date` block at lines 135-141 with the two-branch form. Region scope: lines 135-141 only. The error message string (`::error::Unexpected expires_at format from API`) is preserved verbatim so any operator dashboard / Sentry breadcrumb keyed on that literal continues to fire on the garbage-rejection path.

## Files to Create

None.

## Implementation Phases

### Phase 0 — Preconditions

- Re-read `.github/workflows/scheduled-gh-pages-cert-state.yml:135-141` to lock the exact 7 lines to edit.
- Run `actionlint .github/workflows/scheduled-gh-pages-cert-state.yml` against the unedited file to capture baseline. Deepen-pass result: clean (exit 0, no output) with `actionlint 1.7.7`.
- Confirm `date -u -d "2026-08-16 23:59:59 UTC" +%s` returns a sane integer on the target runner. Deepen-pass repro on `docker run --rm ubuntu:24.04` (GHA `ubuntu-latest` base): `1786924799`. The `-u -d "<date> 23:59:59 UTC"` form is GNU-compatible and matches the suggested-fix snippet from issue #4016.
- Confirm the GitHub Pages API contract via `WebFetch docs.github.com/en/rest/pages/pages` and live `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate'`. Both verified in deepen-pass: documented type is `string, format: date`; live value is `"2026-08-16"`.

### Phase 1 — Edit (RED → GREEN)

Replace the strict-regex block at `.github/workflows/scheduled-gh-pages-cert-state.yml:135-141`:

```bash
# BEFORE
if [[ ! "$EXPIRES_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
  echo "::error::Unexpected expires_at format from API: '$EXPIRES_AT'"
  exit 1
fi
EXPIRES_EPOCH=$(date -d "$EXPIRES_AT" +%s)
```

```bash
# AFTER
# GitHub Pages API returns "string, format: date" per docs — datetime branch is defensive.
if [[ "$EXPIRES_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  EXPIRES_EPOCH=$(date -u -d "$EXPIRES_AT 23:59:59 UTC" +%s)
elif [[ "$EXPIRES_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
  EXPIRES_EPOCH=$(date -u -d "$EXPIRES_AT" +%s)
else
  echo "::error::Unexpected expires_at format from API: '$EXPIRES_AT'"
  exit 1
fi
```

Notes:

- The new code comment (`# GitHub Pages API returns "string, format: date" per docs — datetime branch is defensive.`) guards against future re-paraphrase from `scheduled-cf-token-expiry-check.yml` (which carries the original strict-ISO-datetime regex against Cloudflare's API).
- Date-only branch uses `^...$` anchoring (full match) to prevent `2026-08-16T...` accidentally falling into the EOD-UTC computation.
- Datetime branch uses `^...` anchoring only (partial match), matching the original strict-regex behavior — `date -u -d` handles trailing timezone or fractional seconds correctly.
- `date -u -d "..."` (was `date -d "..."`) — explicit UTC for both branches. Drift-resilient against future runner-image timezone changes.
- The `else` branch keeps the original error string verbatim — preserves any operator-dashboard / Sentry keying on that literal.

### Phase 2 — Verify

- Extract the modified `run:` block and run it via `bash -c '<snippet>'` against the three Test Strategy fixtures.
- `actionlint .github/workflows/scheduled-gh-pages-cert-state.yml` — clean.
- `shellcheck -s bash <(yq '.jobs.poll-cert-state.steps[1].run' .github/workflows/scheduled-gh-pages-cert-state.yml)` — no new findings (capture pre-edit findings as baseline if any).

### Phase 3 — Ship

- Commit with body `Closes #4016`.
- `/soleur:ship` triggers `gh workflow run scheduled-gh-pages-cert-state.yml --ref main` post-merge for the live-API smoke test.

## Risks

- **Runner `date` behavior on UTC EOD** — `date -u -d "2026-08-16 23:59:59 UTC" +%s` is GNU coreutils syntax. GitHub Actions `ubuntu-latest` ships GNU coreutils; verified in deepen-pass via `docker run --rm ubuntu:24.04 bash -c 'date -u -d "2026-08-16 23:59:59 UTC" +%s'` → `1786924799`. The form is stable across the supported runner images. Cited via direct repro — no third-party API/runtime contract claim is being asserted without verification.
- **Defense relaxation** — the original regex was over-strict (defense bounding "format we expected"), but the new branches keep an explicit `else` rejection for unknown formats. The rejected-format set shrinks (date-only is now accepted), but the failure-detection envelope on truly-garbage inputs is unchanged. No new ceiling needed per `2026-05-05-defense-relaxation-must-name-new-ceiling.md` — the relaxation is targeted at two specific API-shape forms (date-only and ISO datetime), not a permissive widening. The original defense was bounding ONE threat (unparseable input crashing `date -d`); the new defense bounds the same threat with the same `else` rejection, just admits two well-formed inputs instead of one.
- **`STATE_OVERRIDE` interaction** — when `STATE_OVERRIDE` is set, `EXPIRES_AT` is cleared (line 120), so the regex branch is short-circuited by the `-n "$EXPIRES_AT"` guard at line 134. The smoke-test path is unaffected by this edit.
- **API contract drift** — GitHub MAY upgrade the field to a full ISO 8601 datetime in a future API version (e.g., `apiVersion=2026-XX-XX` swapping `string, format: date` for `string, format: date-time`). The defensive `elif` branch already accepts that shape, so the workflow survives the upgrade without an edit. The reverse — GH downgrading from datetime to date — is the actual case that broke us; the date-only branch handles it. Both directions of drift are absorbed.
- **Regex anchoring** — the new date-only branch is anchored with `^...$` (full match) to reject inputs like `2026-08-16T...` from accidentally hitting the date-only branch and being computed at EOD UTC of the date portion (which would be a silent ~12h drift). The ISO-datetime branch is anchored with `^...` only (partial match, matches the original strict-regex behavior) since `date -u -d` on the full string handles trailing timezone/fraction correctly.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Mechanical reminder — filled above.)
- The `bash -c '<extracted snippet>'` test harness must be invoked with the **exact** snippet from the edited file (no paraphrase). Running `bash -n <file.yml>` would parse YAML headers as bash and produce a misleading parse error — use `bash -c` against the extracted `run:` body only.
- Region replacement scope: the edit covers lines 135-141 only. The `if [[ "$DAYS_REMAINING" -lt "$WARN_DAYS" ]]` block at 142-144 is unchanged and continues to use `DAYS_REMAINING` from `EXPIRES_EPOCH` — both branches populate `EXPIRES_EPOCH`, so downstream invariants hold.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — single-file infrastructure/tooling change confined to a CI workflow regex. No legal, product, growth, security, finance, ops, support, or community surface is touched.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no open issues referencing `scheduled-gh-pages-cert-state.yml`.

## Infrastructure (IaC)

Skipped — no new infrastructure introduced. This plan edits an existing `.github/workflows/` file; no new server, secret, vendor, DNS record, or persistent runtime process is added.

## Compliance (GDPR / Privacy)

Skipped — no regulated-data surface touched. The workflow reads a public-ish vendor metadata endpoint (`/repos/{owner}/{repo}/pages`) with `GITHUB_TOKEN` and writes issues to this repo. No user data, no schema/migration/auth flow, no Article 9 special-category data, no new processing activity using LLM/external API on operator-session-derived data.

## References

- Issue: #4016
- PR (introduced the bug): #4006
- 2026-05-18 cert outage post-mortem: #3976
- Recovery PRs: #3974, #3986
- GH Pages API endpoint: `GET /repos/{owner}/{repo}/pages` ([docs](https://docs.github.com/en/rest/pages/pages))
