---
title: "origin-tls: analytics token and wrapper subcommand so the /health p90 and 502/520 rate can be read"
date: 2026-11-09
slug: cloudflare-analytics-reader-subcommand
branch: feat-one-shot-cf-analytics-reader-12441
issue: 12441
type: feat
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
closes: none
refs: [12441, 10479, 10205]
---

## Overview

Add a Cloudflare analytics reader to the Class R wrapper `plugins/soleur/scripts/cloudflare-readonly.sh`, bound to the already-minted
read-only token `CF_API_TOKEN_ANALYTICS_READ` with no fallback to any other token, so that the `/health` origin-duration series and the
502/520/525/526 status histogram can be read by an agent without a human. The analytics endpoint is GraphQL (an HTTP POST that only reads),
so the wrapper needs a documented read-only-POST exception limited to fixed query text. The same change records the measured `/health`
result in the strict-flip runbook as a new dated addendum and records the Playwright-under-Node-26 finding as a learning.

## Research Insights

### Premise Validation (Phase 0.6)

Checked 2026-11-09. Issues #12441, #10479 and #10205 are all OPEN (labels `type/chore`, `type/security`, `tracking`). The collision pre-check for #12441 reports exactly one open change naming it: draft PR #12515, which is THIS branch's own WIP draft (head `feat-one-shot-cf-analytics-reader-12441`, no files yet), not a duplicate. #10479 has no open change. Cited artifacts exist on this branch: `plugins/soleur/scripts/cloudflare-readonly.sh` (299 lines, four subcommands), its suite `plugins/soleur/test/cloudflare-readonly.test.sh` (note: under `test/`, not next to the script), `standing-delegation.md` section 9, the runbook section `#### /health p90 after the strict flip: evidence and isolation procedure` (a level-4 heading under the Act 3 record) and ADR-289 (addenda through 2026-11-09 exist). Step 1 of #12441 (the token) is done per the brief; the issue's own text still lists it as open, so the PR body must say it was completed by the owner. Baseline of the existing suite on this worktree: `1038 passed, 0 failed`, 108 of 108 mutation rows caught, about 40 s.

The issue text (written before the brief) says the quantile field names and the time-range cap are UNVERIFIED; the brief supersedes it: the owner proved the first query live and the 9-day window works. Public Cloudflare docs do NOT document `avg{originResponseDurationMs}`, the `quantiles` P50/P90 names, `dimensions{edgeResponseStatus}` or `edgeResponseStatus_in` for `httpRequestsAdaptiveGroups` (docs fact sheet below), so the second query's names rest on live evidence only.

ADR-corpus check for the mechanism (a POST exception to a GET-only read wrapper): ADR-289 (standing delegation, Class R) is the home. Its 2026-11-04 addendum records Cloudflare as a Class R vendor "through the GET-only wrapper"; the widening is an addendum to that ADR, not a new decision and not a rejected alternative. `gh api graphql` is excluded from Class R (item 1) because its query text is caller-supplied; the fixed-query design is the opposite case.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

1. An agent can read the hourly `/health` origin-duration series (count, average, p50, p90) over a bounded window with no human step and no credential handling.
2. An agent can read the hourly counts of edge statuses 502, 520, 525 and 526 over the same window.
3. The only credential used is `CF_API_TOKEN_ANALYTICS_READ`; its absence is `unverified - no-credential`, never a fallback to another token.
4. Nothing except two fixed read-only queries can be sent; a caller cannot widen query text, method, host, path or window beyond one bounded integer.
5. The standing-delegation text tells the truth about what the wrapper sends and which tokens it uses.
6. The measured result is recorded in the runbook append-only, with no causal claim.
7. The Playwright-under-Node-26 install hang is recorded and the repo's install guidance steers away from it.

Mechanisms named in the ask, the property each buys, and what already covers it:

| Mechanism | Buys | Already on main? |
|---|---|---|
| New subcommands in `cloudflare-readonly.sh` | 1-4 | The wrapper already provides the closed set, empty-environment children, token-on-stdin channel and value-free output; extend it, do not build a second reader. A sibling script would be a fourth "vendor wrapper" that the item 2 `through` test pins to exactly three. |
| Read-only-POST exception | 1, 2 | Nothing: no repo mechanism sends a POST read to Cloudflare (`gh api graphql` and the Cloudflare MCP server are explicitly not Class R). `scripts/lib/bearer-curl.sh` (ADR-280) forbids a body from stdin and is the workflow-side library; the wrapper keeps its own single chokepoint by design (the suite rewrites exactly the `CURL=` line). |
| Section 9 amendment | 5 | Required: `the wrapper sends GET only`, `its four subcommands` and the four-token set become untrue; `components.test.ts` pins them. |
| Runbook addendum | 6 | The runbook's own "Still unverified" list and Step C describe the future subcommand; the addendum is append-only. |
| Playwright learning plus one-line install note | 7 | `qa/references/browser-preflight.md` and `agent-browser/SKILL.md` carry the install commands; neither mentions the hang (`agent-browser/SKILL.md` is swept, not content-pinned, by three suites). CI uses Node 22 (`web-platform-release.yml` `node-version: 22`) and is not affected. |

Cut List (mechanisms considered and removed before research): a third `analytics-schema` introspection subcommand is NOT in the ask and was rejected by the CTO ruling (schema discovery row); a per-colo breakdown, a `/robots.txt` control series and percentile fields beyond p50/p90 are not asked for and are cut; a new ADR is cut in favour of an ADR-289 addendum (see Architecture Decision).

### Institutional learnings applied

- `2026-11-04-a-read-only-wrapper-leaked-through-its-helper-children-and-its-own-scoping-clause.md`: the wrapper's `jq` and `date` children must run under `/usr/bin/env -i` with an empty HOME; pin the curl argv by FULL EQUALITY against a stub that refuses any unmodeled flag (a deny-list let `-X POST` through once); give every new test group its own mutation row and floor; a scoping clause that widens an owner limit needs a CTO ruling before its pin test is written.
- `2026-11-03-a-read-only-class-is-only-as-closed-as-its-per-item-pins-and-its-heading-must-not-match-the-trigger-it-feeds.md`: pin each Class R limit inside its own numbered item; presence-only pins survived 20 of 21 widening edits; keep polarity-bearing anchors.
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md`: credential via process substitution, never a pipe (SIGPIPE 141); a token containing a quote or newline injects a curl config directive, so the token-shape guard stays before any request.
- `2026-10-09-a-guard-keyed-on-option-spellings-was-bypassed-by-the-spellings-i-did-not-list.md` and `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-and-a-glob-registered-suite-degrades-the-affected-gate.md`: the stub must `exit 64` on any unmodeled argv and the suite asserts the refusal log is empty.
- `2026-11-09-a-denylist-that-bounds-standing-approvals-does-not-bound-per-command-go-aheads.md`: a read outside Class R's stated limits stays a hold needing a per-command owner go; keep the `Operator-authorizes:` class distinct.
- `2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md` and `2026-10-19-a-precondition-gating-an-irreversible-flip-had-never-run-against-the-live-api.md`: probe the new token against the live endpoint once before relying on it; a green hermetic suite proved the wrong scheme and id class once.
- `2026-10-29-a-runbook-failure-table-written-from-the-plan-contradicted-the-script-it-documents.md`, `2026-09-11-every-sentence-my-runbook-inherited-was-false-when-measured.md`: re-derive every addendum sentence from the live output; do not copy from the brief as verified.
- `2026-03-20-playwright-shared-cache-version-coupling.md`: Playwright browser revisions are exact-match in the shared `~/.cache/ms-playwright`; pin the version in install guidance.
- Learnings format: recent files start `# Learning: <sentence>` then `## Problem`, `## Solution`, `## Key Insight`, `## Session Errors`; filename `YYYY-MM-DD-<sentence-slug>.md` at the top level of `knowledge-base/project/learnings/`.

### Cloudflare GraphQL fact sheet (public documentation, no authenticated call; sources under developers.cloudflare.com/analytics/graphql-api/)

- Verified: `POST https://api.cloudflare.com/client/v4/graphql`, JSON payload `{query, variables}`, `Authorization: Bearer`, query "formatted as a single line string"; envelope `data` and `errors` (`errors: null` on success; failure `data: null` with an `errors` array); error categories map to 400, 401, 403, 429, 500, 503.
- Not found in the docs: whether a GraphQL error arrives as HTTP 200 with an `errors` array or as a 4xx (the wrapper must treat both as errors); a numeric per-plan window or maximum `limit` (a cap exists; the settings node exposes `maxPageSize`); any statement that Zone:Read is needed beyond Analytics Read.
- Verified: filters `datetime_geq` / `datetime_lt` on `httpRequestsAdaptiveGroups`; filter grammar `<field>_<op>` with ops gt lt geq leq neq in (support varies by node); `orderBy: [datetimeHour_ASC]`; `limit` with no cursor pagination; adaptive datasets retain at least 31 days on every plan; `count` is a sampled ESTIMATE (adaptive sampling; `avg{sampleInterval}` carries the weight).
- Not documented for this node: `avg{originResponseDurationMs}`, `quantiles{...P50,P90}`, `dimensions{edgeResponseStatus}` and `originResponseStatus`, `edgeResponseStatus_in`. Introspection (`__schema`) is supported. The docs warn that edge-generated blank 502/503/504 pages are excluded from the legacy error analytics; whether that applies to this dataset is not stated, so the 5xx histogram may under-report and the record must say so.

### CLO ruling (already given; recorded in `decision-challenges.md`)

Class R wording is amended in exactly three Cloudflare sentences (Boundary, item 2, Credentials); the analytics POST stays Class R with the seven conditions listed in the ruling; no GDPR/ePrivacy concern (aggregate figures only, no personal data selected, no new processor); no compliance-posture entry; ADR-289 gets a conditional addendum. Verbatim replacement text is applied in Phase 3 of this plan.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #12441 / brief) | Reality on this branch | Plan response |
|---|---|---|
| "Step 1 owner: create the token ... Done when `doppler secrets --only-names` lists it" (issue text still reads as open) | The brief says it is done and verified active; the plan does not re-check it with a Doppler read (the wrapper reports `no-credential` if it is absent) | PR body states the owner completed step 1; no credential value is read, printed or minted by any phase |
| "The wrapper is GET-only ... one fixed query" | The wrapper has one curl call site pinned by full equality, a stub that refuses any `-X` other than GET, and `components.test.ts` pins "the wrapper sends GET only", "its four subcommands" and a four-token set | CTO option B: a second, separately pinned POST site; every one of those pins is re-derived, not weakened (Phase 1 and Phase 3) |
| "ONE fixed query" (brief item 1) versus "a second fixed query for the 502/520/525/526 histogram" (brief item 2) | Two POST queries, so two subcommands; the CLO ruling already assumes two | Two subcommands, `analytics-health` and `analytics-edge-errors`, each one fixed query |
| "per-plan time-range cap is 9 days at least, verified" | Public docs give no numeric per-plan window (only 31-day retention) | The hours bound is 216 (9 days), the only verified figure; nothing larger is allowed |
| "verify the field names by schema discovery first" (brief item 2) | Public docs do not document the status dimension, `_in` on it, or the duration quantile names; live introspection with the token is a credentialed read outside the wrapper, and a pre-merge run of the branch wrapper is outside Class R (the first live read of a new wrapper is after the merge) | CTO option (ii): docs-level discovery is done (fact sheet above); the first sanctioned live read happens after merge; a wrong field name yields a bounded, diagnosable `api-error`; recorded as an `operator (scope)` row with the owner's typed-go alternative |
| "Fill the 5xx histogram from the new subcommand" | Same constraint: no sanctioned read exists before merge | The runbook records the histogram as `not yet read; first sanctioned read after merge` with the exact command; #12441 stays open (Ref only) as the tracker |
| Runbook Step C and "Still unverified" say the token and subcommand do not exist and the POST exception is not yet reviewed | True when written; stale after this PR | Append-only addendum states what changed; the old rows are NOT edited (owner instruction) |
| The suite sits next to the script | It is `plugins/soleur/test/cloudflare-readonly.test.sh` | Files-to-Edit uses the real path |
| WebSocket 101 probe at 2026-11-08T14:49:20Z (brief) | The only repo record is an issue #10479 comment placing the 101 in the 16:35-16:37Z re-check | Recorded as owner-supplied with both timestamps, neither reconciled |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The change is an on-demand internal reader; a broken subcommand yields `unverified - <reason>` to the agent or owner running it, or a wrong figure in a runbook table. No customer-facing route, page or data path is touched.
- **If this leaks, the user's data / workflow / money is exposed via:** no user data. The credential involved is `CF_API_TOKEN_ANALYTICS_READ` (Analytics:Read, one zone, read-only, expires 2027-02-07); a leak would expose aggregate traffic counts and timings, not visitor-level data, and could not change anything. The wrapper never prints the token, and its stdin-config channel and `env -i` children are re-pinned by the suite.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the earlier wrapper (#10479) carried `single-user incident` because two of its tokens are Terraform-scoped and write-capable; this change adds only a read-only, zone-scoped, aggregate-only token and touches no path in the preflight sensitive-path set (checked against the canonical regex for the four code and doc paths; no match).

## Technical Approach (rulings applied; full rows in `knowledge-base/project/specs/feat-one-shot-cf-analytics-reader-12441/decision-challenges.md`)

### Wrapper design (`plugins/soleur/scripts/cloudflare-readonly.sh`)

- **Chokepoints.** `cf_get` is unchanged (GET only). A new `cf_graphql` is the only POST site: its own `"$CURL"` call, its own closed argv vector `--disable --noproxy '*' -X POST -sS --max-time 20 --max-redirs 0 -w $'\n%{http_code}' --config - "$GQL_URL"` where `GQL_URL="$BASE/graphql"` is a script constant. The stdin config (process substitution, never a pipe) carries exactly three lines: the Authorization header, `header = "Content-Type: application/json"`, and `data-raw = "<escaped body>"`. Escape order: backslash, then double quote.
- **Body pre-flight in `cf_graphql`** (exit 64, fixed message, nothing sent): body begins with the fixed prefix `{"query":"query{viewer{zones(filter:{zoneTag:"` and is a single line with no control characters (a newline or quote would inject a curl config directive). The runtime keyword denylist and byte cap were dropped by CTO ruling (dead code on a compiled-in constant); one static suite row asserts that neither template constant contains `mutation`, `subscription` or `__schema`.
- **Environment.** Every `"$CURL"` site, including the POST site, runs as `/usr/bin/env -i "$CURL" --disable ...`; the suite requires that per site (census equals the number of sites) and has an `env[analytics]` row. Without it a POST site would leak every `CF_API_TOKEN_*` and `DOPPLER_*` variable to curl, and the existing env group only loops over the four GET subcommands.
- **Window.** `t=$(/usr/bin/env -i /usr/bin/date -u +%s)` must match `^[0-9]{10}$`; `end=$((t - t % 3600))`; `start=$((end - H * 3600))`; each formatted with `/usr/bin/env -i /usr/bin/date -u -d @<digits> +%Y-%m-%dT%H:%M:%SZ` and checked against `STAMP_RE`. Complete hours only: `[end - H h, end)`, so the series lags up to one hour.
- **Templates (compiled-in constants; the only substitutions are the zone id and the two stamps).**

  Query 1 (`analytics-health`):

  ```text
  {"query":"query{viewer{zones(filter:{zoneTag:\"<ZONE>\"}){httpRequestsAdaptiveGroups(limit:300,filter:{datetime_geq:\"<START>\",datetime_lt:\"<END>\",clientRequestPath:\"/health\"},orderBy:[datetimeHour_ASC]){count dimensions{datetimeHour} avg{originResponseDurationMs} quantiles{originResponseDurationMsP50 originResponseDurationMsP90}}}}}"}
  ```

  Query 2 (`analytics-edge-errors`):

  ```text
  {"query":"query{viewer{zones(filter:{zoneTag:\"<ZONE>\"}){httpRequestsAdaptiveGroups(limit:1000,filter:{datetime_geq:\"<START>\",datetime_lt:\"<END>\",clientRequestHTTPHost:\"app.soleur.ai\",edgeResponseStatus_geq:500,edgeResponseStatus_lt:600},orderBy:[datetimeHour_DESC]){count dimensions{datetimeHour edgeResponseStatus}}}}}"}
  ```

  Query 1 is exactly the owner-proven shape (path filter only; not host- or `requestSource`-scoped, and the runbook says so). Query 2's range filter replaces the brief's four-status list so 504/522/524 are visible. Query 2 orders `datetimeHour_DESC` (CTO ruling, plan review): if the 1000-row limit is ever reached the dropped rows are the oldest, pre-flip hours, and jq sorts the output ascending by hour then status; `_DESC` is unverified for this node. Query 1 stays ASC (owner-proven; at most 216 hourly groups under `limit:300`).
- **Grammar.** Four old subcommands: exactly one argument. `analytics-health` and `analytics-edge-errors`: exactly two, the second a whole number of hours matching `^[1-9][0-9]{0,2}$` (under `LC_ALL=C`) and at most 216, no default. Arity and hours are validated before `load_credential`. `--list` stays single-argument and prints the six names. Token binding: both analytics arms set `TOKVAR=CF_API_TOKEN_ANALYTICS_READ` and call `load_credential zone`; nothing else reads it; `CF_API_TOKEN_ANALYTICS_READ` joins the xtrace refusal list.
- **Verdicts (`guard_gql`; `guard_body` keys on `.success`, which GraphQL does not return).** 2xx with non-empty `.errors`: `api-error` (14); a 2xx with no errors and `zones: []`: `unverified - no-zone-access` (14, not 11; the header says, like the 401/403 note, that a zone not visible to the token and a wrong zone id are not distinguished; the reason joins the Records vocabulary); `zones` with more than one element or any other wrong shape: `bad-response (shape)`; 400: `api-error`; 401: `token-invalid` (11); 403: `token-lacks-scope` (11); other statuses as today. The `authz` extension-code mapping was cut by CTO ruling (unverifiable before merge). On `api-error` print at most the first error message as `api-error (graphql: <msg>)`, under the CLO's four limits: error path only and first message only, on the single status line; in-full match of `^[A-Za-z0-9 ._:'"/()-]{1,160}$`, no `bearer`, `token` or `authorization` (case-insensitive), no copy of the live token (checked in bash, because the jq lines cannot carry the token), and nothing shaped like an IP address (a dotted quad, or two or more colons with hex digits); a refused message prints plain `api-error`; the message is data, never copied into a Records line (record `other: api-error` only), an issue, a pull request, a commit message or a plan file, and never selects a command, target or token. No other part of the response body is ever printed.
- **Projection (CTO rulings, plan review).** One JSON line per run. `analytics-health`: `{subcommand, window_hours, rows, note, series:[{hour, count, avg_ms, p50_ms, p90_ms}]}`. `analytics-edge-errors`: `{subcommand, window_hours, rows, truncated, note, by_status:{<status>:<sum of counts>}, hourly:[{hour, status, count}]}` where `by_status` is a plain group of every observed status in 500..599 (group by status, key as a string, sum of counts; no `other_5xx`, no named-four special case) and `hourly` is sorted ascending by hour then status. `hour` must match the existing RFC pattern; `count` an integer in 0..1e12; `status` an integer in 500..599; durations numbers in 0..1e7 rounded to one decimal. Any wrong type or out-of-range value on `hour`, `count` or `status`, or a non-null out-of-range duration, is `bad-response (shape)` (no `invalid_rows` counter); a JSON null for avg/p50/p90 passes through as null. `truncated` is emitted for `analytics-edge-errors` only (when rows reach 1000). One fixed `note` string per subcommand: for `analytics-health`, `count is a sampled estimate (adaptive sampling); durations are origin response time for /health, not host- or requestSource-scoped`; for `analytics-edge-errors`, `counts are sampled estimates (adaptive sampling); edge-generated blank 502/503/504 pages may be under-reported by this dataset`. `project()` takes the per-query limit through its own `--argjson` name (it currently hardwires `LIMIT=50`, pinned by the census); re-pin that deliberately.
- **Header contract updates.** New subcommand list, the token binding line, a "read-only POST exception" paragraph (two fixed queries, one integer, token bound with no fallback, body on the stdin config), the one stated exception to "Messages are fixed, single-line and value-free" (the bounded `graphql:` message), Records mapping lines `Cloudflare analytics-health (F) #12441` and `Cloudflare analytics-edge-errors (G) #12441` (evidence only, never a gate, `Unverified:` until the first sanctioned read), the token expiry date 2027-02-07 (also on the `token-invalid` Records line), the unverified-claims list (the status dimension, the range operators, `_DESC` ordering on this node), a reason-to-next-action table in the Records mapping (`api-error (graphql: unknown field ...)` means a fix PR, cap two; `no-zone-access` means check the zone id and the token's zone; `token-invalid` means rotation, the owner's credential change; `no-credential` means the Doppler config lacks the token), fixed value-free arity messages that say the analytics subcommands take hours 1-216, and terse wording throughout (the header is already about 110 lines). Sweep the stale count with a scoped census, not a repository-wide grep: `git grep -n -i -w -E 'four|4' -- plugins/soleur/scripts/cloudflare-readonly.sh plugins/soleur/test/cloudflare-readonly.test.sh plugins/soleur/test/components.test.ts plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md plugins/soleur/agents/engineering/cto.md`, classify every hit (live stale count to fix, or a false positive) and fix the live ones: the wrapper header title line, the `--list` comment and the `# --- the four reads ---` banner; the suite's "four arms plus", "exactly four cf_get" and "exactly four token variables" comments and assertions; `CF_FOUR` and the other four-name pins in `components.test.ts`. The ADR-289 historical addenda are exempt (they must keep saying four), and `cto.md` is confirmed not to enumerate subcommands (its Cloudflare sentence only names the wrapper).

### Section 9 and ADR text

The CLO's verbatim replacement text is applied to the three Cloudflare sentences of `standing-delegation.md` section 9 (Boundary vendor sentence; item 2 Cloudflare clause; Credentials Cloudflare clause); the CLO's HTML-escaped `&lt;subcommand&gt;` in its output means the real text keeps the literal `<subcommand>` already pinned by `components.test.ts`. The CLO's second ruling (plan review) is applied too: item 2 gains the CLO's inserted sentence about the bounded GraphQL error message directly before "the wrapper never prints a rule `expression`", and the hours-back parenthetical is replaced with the CLO's amended wording (digits only and in range before use, refused with nothing sent otherwise; kept after ", as a status" and unbackticked so the `its six subcommands` slice still counts six names; the pinned invocation `<subcommand>` is unchanged). The ADR-289 addendum gains the CLO's one sentence on the message. The ADR-289 addendum is titled `## Addendum 2026-11-09 (Ref #12441, #10479, #10205)` (a `## Addendum 2026-11-09 (Ref #12443)` already exists, so the title carries the refs) and is conditioned on the merge; earlier addenda added no frontmatter pointer key, so the only frontmatter edit is appending 12441 to `related:`.

## Implementation Phases

### Phase 0 — Prerequisites (no repository change)

- 0.1 Re-run the baseline: `bash plugins/soleur/test/cloudflare-readonly.test.sh` must report `1038 passed, 0 failed` and `108 of 108` before any edit (measured in planning at 40 to 70 s depending on load), and record the pass count of `bun test plugins/soleur/test/components.test.ts` as its baseline. Optionally confirm the token name is present with `doppler secrets --only-names -p soleur -c prd_terraform` (names only; never a value).
- 0.2 Real-curl escape proof (local, no Cloudflare traffic; CTO's one unverified item): with `/usr/bin/curl`, a one-shot loopback listener (`python3 -I`, port 127.0.0.1 only) and a config built exactly as `cf_graphql` will build it (`data-raw`, not `data`), confirm the received body byte-equals the intended JSON. The planner already proved the same with a `data` key; `data-raw` is the untested variant. If it differs, fall back to argv `--data-raw` and re-pin the vector (record in `decision-challenges.md` as a superseding CTO row). Record the result as a `Checked:` line in the PR body.
- 0.3 The owner's proven query text was searched for in planning (comments of #12441 and #10479, the PR 12434 body) and not found; the PR body asks the owner to diff the two templates against the query they ran and says so. No further search phase.

### Phase 1 — Tests first (RED), `plugins/soleur/test/cloudflare-readonly.test.sh`

Per `cq-write-failing-tests-before`. Because the pristine control fails while RED (which voids the mutation battery through `CONTROL_BAD`), take RED evidence from `CF_RO_GROUPS=<groups>` runs, not from the full battery. Add, before the wrapper change:

- Stub: compute `url` first; `-X GET` refused for the GraphQL URL; `-X POST` accepted only for it; for POST require stdin to carry exactly one `Authorization` line, one `Content-Type: application/json` line and one `data-raw` line.
- Wire: parameterise `check_wire` by vector name (`EXP` / `EXP_POST`) instead of copying it; closed vector by full equality plus controls (duplicated `-X`, glued `-XPOST`, vector with no URL). The "stdin is exactly one line" row stays scoped to the four GET subcommands. Every `"$CURL"` line must start `/usr/bin/env -i "$CURL" --disable` (per-site census equals the site count) and an `env[analytics]` row proves the POST child gets an empty environment.
- Body (from `stdin.log`): fixed prefix, single line, zone id equals env, both stamps match `STAMP_RE`, `end` on the hour, `end - start` equals H*3600, the template with the three values masked equals the compiled-in constant (run at H=1 and H=216 only; a different-H comparison shows only the start stamp differs), a hostile `CF_ZONE_ID` refused 64 on an analytics arm (one row proving the arm reaches `load_credential`), and one static row that neither template constant contains `mutation`, `subscription` or `__schema`. The two query templates are kept deliberately duplicated in the suite in one marked block (they are the pin; each of at most two field-name fix PRs is a two-place edit).
- Clock: deterministic through the existing fakedate pattern (`make_variant`), with `10#$t` in the arithmetic; never compare with the test's own `date +%s`. A `[ -x /usr/bin/date ]` preflight exits 14 like change-history, and a bad `date +%s` stamp exits 64 value-free.
- Token binding: only the four old tokens set, both analytics subcommands exit 10 and curl is uncalled; only the analytics token set, the four old ones exit 10 and the analytics token never appears in their argv or stdin; a planted `CF_API_TOKEN` is never used; 401/403 mirrors.
- Grammar (all exit 64, curl uncalled, no token needed): `0`, `217`, `-1`, `07`, `1.5`, empty, an extra argument, a missing argument, a unicode digit, `5` plus a trailing newline, an old subcommand with a second argument, an analytics subcommand with one; plus a row on the fixed arity message text (it says the analytics subcommands take hours 1-216).
- Group loops: every group that iterates `SUBS` with one argument (token, env, status, shape, tools including the `nodate` and `fakedate_*` variants) gets analytics rows through a second array for the two analytics names; `SUBS` stays the four GET names.
- Projection with hostile values: HTTP 200 with `errors` gives `api-error` and the bounded message; a message with a newline, an escape character, 161 characters, `Bearer`/`token`/`authorization`, a copy of the live token, a dotted quad or a colon-hex string is omitted (plain `api-error`); 400 gives `api-error`; 2xx with `zones: []` gives `unverified - no-zone-access` (exit 14); `zones` with two elements, out-of-range or wrong-typed `hour`/`count`/`status`/duration, a status outside 500..599, `data: null` and an empty body give `bad-response (shape)`; a JSON null duration passes through; `analytics-edge-errors` ordering is ascending in the output, `by_status` sums, and `truncated` is true at 1000 rows.
- Floors re-pinned to exact new values, stated in the acceptance criteria: `-ge 108` (mutation rows), `-ge 400` (assertions), `PROJ_FLOOR=46`, `EXERCISED -ge 12`, the refuse floor, and the `LEAK_NEEDLES` floor (13 members and `-ge 12` today; 14 members and `-ge 14` after the analytics fake token is added, so dropping the needle is caught). Also re-pin the token-variable lists (`BASE_ENV`, the xtrace loop list, the wire and env token loops), the census expect-strings (`== 5` to 7 arm terminators, W6.9; `exactly one curl call site` to two, G1.4 and G1.4b; the `LIMIT=50` literal and `--argjson limit` text), mutation G1.7 (which anchors `if [ "$#" -ne 1 ]; then`), anchors that stop being unique with two curl sites (`/usr/bin/env -i "$CURL"`, `"$CURL" --disable`; run the suite and fix every `anchor matched 2 times`), and W4.16's loop-line anchor if a group is added.
- Mutation rows: those in the Guard Contract.

### Phase 2 — Wrapper (GREEN)

Implement the design above in `cloudflare-readonly.sh`; write the arity check with `if` or `case "$1"`, NOT a second `case "$SUB" in ... esac` (the suite's `dispatcher_block` awk concatenates every such block and would corrupt the arm census and label parity); run the suite; then run the mechanical anchor sweep (every `anchor matched 2 times` row re-anchored and mirrored at the POST site) and the `git grep` sweep for the stale count of four.

### Phase 3 — Doc parity and decision records

- 3.1 `standing-delegation.md` section 9: apply the CLO text.
- 3.2 `components.test.ts`: `its six subcommands` slice (count 6; keep every new token in the hours text unbackticked so `backticked()` stays at six), five-token set equality (including `CF_API_TOKEN_ANALYTICS_READ`) and the wrapper `TOKVAR` equality (five), the PAIRS row for the `ssl-mode`, `config-entrypoint`, `pagerules-ssl` or `change-history` list, the PAIRS row for the `unverified - no-credential` when `CF_API_TOKEN_AUDIT` sentence (keep that sentence's wording intact when the CLO text is applied), the REQUIRED `the wrapper sends GET only` marker (item 2 in the per-item REQUIRED table) and the Cloudflare-clause `GET only` check (the item 2 clause test) replaced by the new wording, a new pin `the two analytics subcommands each send one POST`, a new pin on the bounded-message sentence, `VENDOR_SENTENCE` updated to the CLO sentence, and the `hostTokens(clause)` host set staying exactly `["api.cloudflare.com"]`; the polarity test (no `permits`, `except`, `unless`, `but` in the Cloudflare clause) stays and is re-run.
- 3.3 ADR-289: dated addendum (with the CLO's sentence on the bounded error message) and `related:` gains 12441; records the invariant change (one GET site plus one separately pinned POST site) and the pins that enforce it. No C4 change.
- 3.4 Run `bun test plugins/soleur/test/components.test.ts` and the full cloudflare suite.

### Phase 4 — Runbook addendum (append-only)

Insert a new `##### Addendum 2026-11-09: origin response time for /health (Cloudflare analytics)` at the end of the `#### /health p90 after the strict flip` section, immediately before `#### What was NOT run before the flip`. No existing row is edited. Its first line reads: `Read this first: this addendum supersedes the "Token prerequisite" paragraph, the Step C text that says the token and subcommand do not exist, and the "Real 502/520 rate" row of the open-checks table below` (rows named by anchor text, never by line number). Figures are recorded verbatim, and where the owner-supplied numbers do not agree with each other the addendum says so instead of fixing them: the hourly split 171 h + 45 h is 216 against the 217 rows stated (the 2026-11-07T23Z hour straddling the flip is not named), and "about +385 ms" is not the difference of the stated p90 medians (855 − 477 = 378 ms); both are noted as unreconciled. Contents, each figure labelled `owner-supplied, not re-derived by this wrapper`: 217 hourly rows from 2026-10-31T20Z to 2026-11-09T20Z; before the flip (171 h) median hourly p50 332 ms and p90 477 ms; after (45 h) p50 269 ms and p90 855 ms; daily median hourly p90 flat at 462-645 ms for 11-01 to 11-07 (11-02 was 645), then 851 ms on 11-08 and 859 ms on 11-09; the step coincides with the strict flip at 2026-11-07T23:43Z; p50 did not rise, only the tail (about +385 ms); the tail clusters near 850 and 1390 ms; the :80 and :443 servers set the same `keepAliveTimeout` (`ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS`), so a shorter :443 keep-alive is ruled out; the remaining candidates (a new-connection TLS handshake on the Cloudflare-to-origin hop, redeploy restarts, TLS CPU) are NOT separated, and no cause is claimed. Also: the 5xx histogram row reading `not yet read; first sanctioned read after merge` with the exact command (`doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh analytics-edge-errors 216`, run from a fresh checkout where `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` is empty); the caveats (sampled counts, possible under-reporting of edge-generated pages, `/health` query not host-scoped, complete hours only, series lags up to one hour, the 216-hour window cannot reproduce the owner's 217-row window); the median jq one-liner, which names its input file (the committed evidence file `knowledge-base/engineering/operations/runbooks/evidence/<UTC date>-analytics-health-216h.json`, written in the post-merge follow-up, not in this PR) and takes `--arg lo`/`--arg hi` hour bounds so the next person reproduces it; a ready-to-paste handoff for the post-merge loop (preflight `git fetch origin main` then `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` empty, the two exact commands, and the reason-to-next-action table); the reconciliation of Step C's request shape (it listed `clientRequestHTTPHost` and `requestSource: "eyeball"`; query 1 drops them) and of the token description (the runbook says Analytics:Read and Zone:Read, the owner-supplied token is Analytics:Read on one zone); the live-verify result (`RESULT: PASS fresh conversation persisted and appeared in the rail via=reload elapsed=48s checks=33`, 2026-11-09): the work phase makes ONE bounded re-derivation attempt (a `gh run view <id> --log` read of `web-platform-release.yml` runs from 2026-11-09, at most 20 runs, `timeout 60` each, output only through `grep -a -m1` and `cut -c1-260`, never a whole log) and records `Checked: live-verify PASS, run <id>` on a match, else `owner-supplied ... not re-derived by this PR; the CI log was searched and the line was not found` with the number of runs searched (the CTO's own bounded search of the 20 newest runs, 15 on 2026-11-09, found no match); the unauthenticated WebSocket upgrade `101` through the strict hop recorded as owner-supplied at 2026-11-08T14:49:20Z per the brief, with the #10479 comment (issuecomment-6725639019, an agent session, posted 2026-11-08T18:54:17Z, placing the 101 in the 16:35-16:37Z re-check) cited beside it, stating that the two times conflict, that neither was re-derived, that the PR claims neither as the probe time, that it is an upgrade through the strict hop only, and that the signed-in run is not done; and a short "what changed in the status tables above" note (the token and subcommands exist as of this PR; Step C is runnable after merge). The evidence file is out of this PR's scope: it is committed only after the first sanctioned read (post-merge follow-up, a second change; the "ONE PR" instruction covers this PR, and the follow-up is the tracker #12441's remaining work).

### Phase 5 — Learning and Playwright guidance

- 5.1 New learning at the top level of `knowledge-base/project/learnings/` (filename `YYYY-MM-DD-<sentence-slug>.md` with the authoring date, topic: Playwright's browser install stalls under Node 26 and completes under Bun) in the repo's learning format (`# Learning:`, `## Problem`, `## Solution`, `## Key Insight`, `## Session Errors`): Playwright's browser zip extractor (yauzl) stalls under Node 26 (26.12.1 and 26.13.0), stopping mid-file at 0% CPU after the download reaches 100%; the identical install under Bun finishes in under 2 minutes (`bunx --bun playwright install ...`, `bunx --bun @playwright/mcp@0.0.78 install-browser chrome-for-testing`); a manual `unzip` into `~/.cache/ms-playwright/<dir>` plus an `INSTALLATION_COMPLETE` marker also works; CI is unaffected (Node 22 in `web-platform-release.yml`). It states the cause as observed, not root-caused upstream.
- 5.2 One-line guidance in `plugins/soleur/skills/agent-browser/SKILL.md` (the pinned `install-browser` bullet) and in `plugins/soleur/skills/qa/references/browser-preflight.md` (after the install snippet): on Node 26 run the install under Bun (`bunx --bun ...`) because the extractor stalls. Both are one-line doc changes, so no issue is filed for them. Neither file's content is pinned by a test, but `agent-browser/SKILL.md` is swept by three suites (`apps/web-platform/test/plugin-root-anchoring.test.ts`, `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts`, `plugins/soleur/test/scratch-path-collision.test.ts`), so the new line carries no bare plugin path or `/tmp` path and those three suites are run in Phase 6.

### Phase 6 — Verify and open the PR (stop there)

Run the full cloudflare suite, `bun test plugins/soleur/test/components.test.ts`, `bash plugins/soleur/test/c4-count-parity.test.sh`, the three suites that sweep `agent-browser/SKILL.md`, markdown lint on the touched docs, the technical-ruling gate on `decision-challenges.md`, and the repository's affected-test runner (`scripts/test-all.sh --affected`, the gate the PR will face); run `prepush-secret-scan.sh` before every push; push the branch; update the existing draft PR #12515 body (`Ref #12441`, `Ref #10479`, `Ref #10205` only; confirm `closingIssuesReferences` is `[]` before saving the body); run the review panel; do NOT mark ready, arm auto-merge or merge. The PR body lists the four owner-review items from the CLO rulings (widening from four GET reads to six reads two of which POST; the new read-only token; the definition of Class R moving from the HTTP verb to fixed, read-only, aggregate-only; and the one bounded vendor-authored error line that can now reach the transcript, with its alternative of a fixed message), leads with the descoped 5xx histogram and the owner's typed-go alternative, and carries one justification line per issue filed (none are expected: the token-expiry reminder is a comment on #12441 with the date 2027-02-07, not an issue, per CTO ruling).

## Files to Edit

- `plugins/soleur/scripts/cloudflare-readonly.sh`
- `plugins/soleur/test/cloudflare-readonly.test.sh`
- `plugins/soleur/test/components.test.ts`
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`
- `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md`
- `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`
- `plugins/soleur/skills/agent-browser/SKILL.md`
- `plugins/soleur/skills/qa/references/browser-preflight.md`

## Files to Create

- one new file at the top level of `knowledge-base/project/learnings/`, `YYYY-MM-DD-playwright-browser-install-stalls-under-node-26-and-completes-under-bun.md` (authoring date)
- `knowledge-base/project/specs/feat-one-shot-cf-analytics-reader-12441/decision-challenges.md` (already written in planning)
- `knowledge-base/project/specs/feat-one-shot-cf-analytics-reader-12441/tasks.md`

Glob and path verification: every path above was confirmed with `git ls-files` or `ls` on this branch (the wrapper, its suite, `components.test.ts`, `standing-delegation.md`, ADR-289, the runbook, `agent-browser/SKILL.md`, `qa/references/browser-preflight.md`). `scripts/lib/test-affected-paths.sh` already maps the suite to the wrapper and `seo-config-rules.tf`; no edit is needed because no new file joins the suite's read set (the components pins already name the wrapper).

## Open Code-Review Overlap

None. Queried open `code-review` issues against all eight edited paths on 2026-11-09; no match.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-289 (`standing-delegation-and-production-envelope`) with a dated addendum, 2026-11-09 (Ref #12441, #10479, #10205), using the CLO's text, conditioned on the merge; the only frontmatter edit is appending 12441 to `related:` (earlier addenda added no pointer key). Ruled by CTO agent, 2026-11-09: no new ADR. Decision in one line: the Class R Cloudflare reads widen from four GET-only reads to six, the two new ones being fixed read-only POSTs, and the wrapper invariant moves from one GET call site to one GET site plus one separately pinned POST site.

### C4 views
No C4 change. Enumerated against `model.c4`, `views.c4` and `spec.c4` (grep of `cloudflare` edges and `Class R`/`readonly`/`analytics` terms across all three; the deepen pass reads the three files in full): (a) external human actors: none added (the owner and agent sessions already exist as the operator); (b) external systems: Cloudflare is already modelled (`cloudflare = system "Cloudflare"`, edges from `hetzner`, `api`, `github`); the GraphQL Analytics API is an endpoint of the same system, and the model draws no agent-read edges to Cloudflare, Sentry or Better Stack by deliberate omission (ADR-289 2026-11-03 and 2026-11-04 addenda); (c) containers and data stores: none touched; (d) actor-to-surface access relationships: none change. `bash plugins/soleur/test/c4-count-parity.test.sh` is green on the branch baseline (13 passed, 0 failed) and is re-run in Phase 6.

### Sequencing
The addendum is authored now and conditioned on the merge; nothing is deferred to a follow-up issue.

## Observability

```yaml
liveness_signal:
  what: the first stdout line of each wrapper run, `cloudflare-readonly: <subcommand> ok` or `cloudflare-readonly: <subcommand> unverified - <reason>`, plus the exit code (0, 10, 11, 14, 64, 78)
  cadence: per run (an on-demand reader; there is no daemon and no schedule)
  alert_target: the invoking agent or owner session reads the line in-session; nothing pages, by design (observability layer 7, cli-stdout-artifact, the tool-result stdout read in-session)
  configured_in: plugins/soleur/scripts/cloudflare-readonly.sh (output contract in the header)

error_reporting:
  destination: stdout and stderr of the wrapper to the invoking session (layer 7 cli-stdout-artifact); no Sentry DSN, because the wrapper is a Jikigai-internal on-demand reader that is inert wherever the CF_* variables are absent and has no hosted execution path
  fail_loud: a non-zero exit with a fixed value-free line (`no-credential`, `token-invalid`, `token-lacks-scope`, `api-error`, `bad-response (shape)`, `upstream-error`) and, for api-error only, the bounded `graphql:` message

failure_modes:
  - mode: token absent from the Doppler config
    detection: exit 10 and `unverified - no-credential (CF_API_TOKEN_ANALYTICS_READ)` printed on the run itself (layer 7 cli-stdout-artifact)
    alert_route: the invoking session records an Unverified line; the follow-up issue for the token expiry names the date
  - mode: token expired or revoked (expires 2027-02-07)
    detection: HTTP 401 gives exit 11 and `unverified - token-invalid` on the run (layer 7 cli-stdout-artifact)
    alert_route: the invoking session; rotation is the owner's credential change, tracked by one dated follow-up issue
  - mode: wrong GraphQL field or filter name in a fixed query
    detection: a 200 with `errors` or a 400 gives exit 14 and `unverified - api-error (graphql: <bounded message>)` (layer 7 cli-stdout-artifact)
    alert_route: the invoking session; at most two fix PRs, then an Unverified record and one follow-up issue (CTO ruling)
  - mode: token valid but zone not visible, or a wrong zone id
    detection: a 2xx with `zones: []` gives exit 14 and `unverified - no-zone-access` (layer 7 cli-stdout-artifact)
    alert_route: the invoking session checks the zone id and the token's zone; the cause is not distinguished by the wrapper
  - mode: Cloudflare outage or rate limit
    detection: 429 or 5xx gives exit 14 and `unverified - upstream-error` (layer 7 cli-stdout-artifact)
    alert_route: re-run once after a pause; the newest line governs (Records rule in the wrapper header)

logs:
  where: none persisted; the evidence is the `Checked:`/`Unverified:` line in the runbook addendum or the plan's `## Class R Checks`, and the committed aggregate projection file after the first sanctioned read
  retention: git history

discoverability_test:
  command: bash plugins/soleur/scripts/cloudflare-readonly.sh --list
  expected_output: analytics-edge-errors
```

## Guard Contract

### Guard 1 — The wrapper sends a POST only to the fixed GraphQL URL with a compiled-in read-only query

**Property.** Every request the wrapper can make is either a GET to one of four fixed URL templates or a POST to exactly `https://api.cloudflare.com/client/v4/graphql` whose body is a compiled-in read-only query with only a zone id, two stamps and an integer-derived window substituted.

**Assembly.** The request surface is every `"$CURL"` call site in the file (after this change exactly two: `cf_get` and `cf_graphql`), the closed argv vectors `EXP` and `EXP_POST` pinned by full equality in the suite, the stub curl's `-X`/URL rules, the body pre-flight in `cf_graphql`, the two query-template constants, the dispatcher arms that call them, and the stdin config lines. The members drift; the structure is the two call sites and the two vectors, so the suite counts call sites (exactly two), counts `cf_graphql` callers (exactly two, one per analytics arm) and compares the masked body to the constant.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | At the POST site change `-X POST` to `-X GET` | RED (POST vector equality row and stub refusal) |
| 2 | Add a third `"$CURL"` call site (a copy of `cf_graphql`) | RED (call-site census says two) |
| 3 | In `cf_graphql` change `GQL_URL` to a different path or host | RED (POST vector last-argument row and host row) |
| 4 | Interpolate the raw hours argument `$2` into the query body | RED (masked-body equals constant; hostile-integer rows) |
| 5 | Insert `mutation` into a template constant | RED (the static template-keyword row) |
| 6 | Remove the fixed-prefix or control-character check in `cf_graphql` | RED (a tampered-template run and a control-character zone/stamp row are accepted otherwise) |
| 7 | Drop `/usr/bin/env -i` from the POST curl site | RED (per-site `env -i` census and the `env[analytics]` row) |
| 8 | Dispatcher dispatch: remove an analytics arm so the census reports 6 `;;` terminators instead of 7 (the guard's own dispatch cannot report "0 checked" and pass) | RED |
| 9 | Add a third analytics arm after the two compliant ones | RED (arm and `cf_graphql` caller censuses) |
| 10 | Harness row: make the stub accept any `-X` for any URL | RED (a dedicated control feeds the stub `-X POST` to a GET URL and expects a refusal) |
| 11 | Harness row: make the wire group record nothing (blind stub log) | RED (the wire floor, as the existing anti-vacuity control) |
| 12 | Print the whole `errors` array, or a message holding a dotted quad or the live token, on `api-error` | RED (the hostile-message rows) |

Must-PASS inputs that are not the canonical: H=1 and H=216 (the boundaries), an alternate zone id, and an alternate valid token value.

**Anchor.** The pinned vector and constants live in the same file as the code they guard, so a single commit can weaken both; the outside anchors are the `components.test.ts` doc-parity pins (a separate file that must move with any change in the number of subcommands or tokens), the standing-delegation text the owner reviews on the draft PR, and the post-merge rule that the wrapper runs only from a checkout matching a freshly fetched `origin/main`.

### Guard 2 — The analytics token is bound to the two analytics arms with no fallback

**Property.** `CF_API_TOKEN_ANALYTICS_READ` is read only by the two analytics arms, those arms read no other token, and an absent token ends in `no-credential` with zero requests.

**Assembly.** The `TOKVAR=` assignments in the dispatcher (five names after this change), `load_credential`, the xtrace refusal list, the stub's stdin log, the leak needles, and the Credentials sentence in `standing-delegation.md` (pinned by set equality against the wrapper's `TOKVAR` names in `components.test.ts`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Let an analytics arm fall back to `CF_API_TOKEN_AUDIT` when its own token is empty | RED (only-old-tokens-set row expects exit 10 and no curl call) |
| 2 | Bind `analytics-edge-errors` to `CF_API_TOKEN_RULESETS` | RED (token-on-stdin row and the `TOKVAR` set equality) |
| 3 | Dispatcher dispatch: drop `CF_API_TOKEN_ANALYTICS_READ` from the xtrace refusal list | RED (list equals dispatcher names plus `CF_API_TOKEN`) |
| 4 | Let an old subcommand read the analytics token | RED (only-analytics-token-set row: the four old ones exit 10) |
| 5 | Add a sixth token name to the dispatcher after the five compliant ones | RED (census and doc-parity set equality) |
| 6 | Harness row: make the leak scan treat the analytics token as not a needle | RED (the `LEAK_NEEDLES` floor, re-pinned from `-ge 12` to `-ge 14` with 14 members so the drop is visible) |

Must-PASS inputs that are not the canonical: a token value with every allowed punctuation character, and a trailing-whitespace token that is trimmed.

**Anchor.** The doc-parity set equality in `components.test.ts` compares the standing-delegation text with the wrapper's own `TOKVAR` names, so a token can neither be added to the wrapper nor to the text alone; the owner-minted token's scope (Analytics:Read, one zone, expiry 2027-02-07) is the outside control that bounds a weakening.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a subcommand to plugins/soleur/scripts/cloudflare-readonly.sh bound to CF_API_TOKEN_ANALYTICS_READ with NO fallback to another token, plus its test suite extension." [brief] | Phase 1, Phase 2, Guard 2 | mapped |
| 2 | "the CTO agent (soleur:engineering:cto) rules the mechanism for a documented read-only-POST exception limited to ONE fixed query (no caller-supplied query text)" [brief] | Technical Approach, decision rows 1-7 | mapped |
| 3 | "the CLO agent (soleur:legal:clo) rules whether the standing-delegation Class R section 9 wording needs amending; amend it as ruled" [brief] | Phase 3.1, 3.2, 3.3 | mapped |
| 4 | "Record rulings as `Ruled by CTO agent` / `Ruled by CLO agent` in the decision-challenges file." [brief] | `decision-challenges.md` | mapped |
| 5 | "The fixed query is the one already proven live: httpRequestsAdaptiveGroups on zone CF_ZONE_ID, filter clientRequestPath \"/health\", orderBy datetimeHour_ASC ... window parameterised only by hours-back (bounded integer)." [brief] | Query 1 template, grammar (1..216) | mapped |
| 6 | "Also add a second fixed query for the 502/520/525/526 status histogram over the same window (verify the field names by schema discovery first ...)" [brief] | Query 2 template; docs-level discovery done; live verification after merge | mapped (live schema verification descoped to post-merge by CTO ruling; see `operator (scope)` row) |
| 7 | "Record in the runbook ... the measured result as a NEW dated addendum (append-only, never edit the old rows)" [brief] | Phase 4 | mapped |
| 8 | "Fill the 5xx histogram from the new subcommand and record it with the same discipline." [brief] | Phase 4 5xx row | descoped — justification: no sanctioned read of an unmerged wrapper exists (Class R drift rule, CTO option ii); recorded as `not yet read; first sanctioned read after merge` with the exact command; owner may give a typed per-command go to run it pre-merge |
| 9 | "Also record: live-verify against prod PASSED 2026-11-09 (RESULT: PASS ...), and the WebSocket upgrade probe through the strict hop returned 101 at 2026-11-08T14:49:20Z (unauthenticated; not a signed-in check)." [brief] | Phase 4 | mapped |
| 10 | "Record the Playwright finding as a learning (knowledge-base/project/learnings)" [brief] | Phase 5.1 | mapped |
| 11 | "Check whether a repo script/doc that installs Playwright browsers ... should say so, and fix it if it is a one-line change; otherwise file an issue" [brief] | Phase 5.2 (two one-line doc changes; no issue) | mapped |
| 12 | "ONE PR, `Ref #12441`, `Ref #10479`, `Ref #10205` only (never Closes/Fixes ...)" and "stop after the PR is open with review evidence, and do NOT arm auto-merge or mark ready" [brief] | Phase 6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cloudflare-readonly.sh` edit | "Add a subcommand to plugins/soleur/scripts/cloudflare-readonly.sh" | asked |
| `cloudflare-readonly.test.sh` edit | "plus its test suite extension" | asked |
| `standing-delegation.md` edit | "amend it as ruled" | asked |
| `components.test.ts` edit | — | inferred — justification: the suite pins the very sentences the CLO ruling changes ("the wrapper sends GET only", "its four subcommands", the four-token set); without the edit the parity tests go red |
| ADR-289 addendum | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` (plan Phase 2.10): the Class R boundary moves and the ADR that records it must not lag; the CLO ruling also asks for it |
| runbook addendum | "a NEW dated addendum (append-only, never edit the old rows)" | asked |
| learning file | "Record the Playwright finding as a learning" | asked |
| two one-line Playwright doc notes | "fix it if it is a one-line change" | asked |
| `decision-challenges.md` | "Record rulings as `Ruled by CTO agent` / `Ruled by CLO agent` in the decision-challenges file." | asked |
| `tasks.md` | — | inferred — justification: the plan skill's Save Tasks step derives it from the finished plan so `soleur:work` can run |
| Real-curl escape proof (Phase 0.2) | — | inferred — justification: the CTO ruling names it as the one unverified mechanism claim; a stub cannot show how real curl parses the config line |
| Token-expiry comment on #12441 and the date in the header, addendum and Records line (Phase 4, Phase 6) | — | inferred — justification: the CTO ruling (token-expiry row of `decision-challenges.md`) asks for the date to be carried durably; an expired token otherwise reads as `token-invalid` with no pointer to why |

### Split Assessment

- Subsystems touched: 2 (`plugins/soleur`, `knowledge-base`)
- Planned files: 11 (8 edited, 3 created) | Estimated changed lines: 1400 (suite about 700, wrapper about 300, docs and ADR about 300, pins about 100)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the line threshold is exceeded, but the owner asked for ONE PR and the pieces cannot be split green: the doc-parity pins fail unless the wrapper, the standing-delegation text and the tests move together.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/cloudflare-readonly.test.sh` exits 0 and prints `<N> passed, 0 failed` with N above the 1038 baseline, and the mutation line reads `every mutation row ran and was caught (M of M)` with M above 108; the floor literals in the suite (`-ge 108` mutation rows, `-ge 400` assertions, `PROJ_FLOOR=46`, `EXERCISED -ge 12`, the refuse floor, and the `LEAK_NEEDLES` floor, which is `-ge 12` against 13 members today) are each set in the same commit to the count MEASURED after GREEN (read the `N passed` and `M of M` lines and the needle and row counts; `-ge 400` is a loose floor today against 1038 asserted and is raised to just under the new measured total), and the needle list gains the analytics fake token (14 members, floor `-ge 14`), so dropping one row or needle is caught (implementing file: the suite; Phase 1 and 2).
- [ ] Every `"$CURL"` site in the wrapper starts `/usr/bin/env -i "$CURL" --disable`, and the suite's per-site census plus the `env[analytics]` row enforce it (Guard 1 row 7).
- [ ] `2xx` with `zones: []` yields `unverified - no-zone-access` (exit 14); a hostile `graphql:` message (newline, 161 characters, credential word, live token, dotted quad, colon-hex) yields plain `api-error` (projection group).
- [ ] Query 2 text contains `orderBy:[datetimeHour_DESC]` and the output is sorted ascending; `truncated` appears only in `analytics-edge-errors` output (projection group).
- [ ] The suite counts exactly two `"$CURL"` call sites and exactly two `cf_graphql` callers (`cloudflare-readonly.test.sh` source group; Guard 1 rows 2 and 9).
- [ ] The POST argv equals the closed `EXP_POST` vector and the stub refuses `-X POST` for any URL other than the GraphQL URL and `-X GET` for it (wire group, Guard 1 rows 1 and 10).
- [ ] Both analytics subcommands exit 10 with zero curl calls when only the four old tokens are set; the four old subcommands exit 10 when only the analytics token is set (token group, Guard 2 rows 1 and 4).
- [ ] Hours `0`, `217`, `-1`, `07`, `1.5`, empty, `5` plus newline, a unicode digit, a missing and an extra argument all exit 64 with curl uncalled (refuse group).
- [ ] `bun test plugins/soleur/test/components.test.ts` passes with the six-subcommand slice, the five-token set equality, the new `the two analytics subcommands each send one POST` pin and the updated `VENDOR_SENTENCE`; the Cloudflare clause contains none of `permits`, `except`, `unless`, `but` (polarity test).
- [ ] `standing-delegation.md` section 9 changes only the three Cloudflare sentences (the CLO's replacement text, plus the CLO's inserted bounded-message sentence and amended hours parenthetical in item 2); `git diff origin/main...HEAD -- <file>` hunks touch only the Boundary vendor sentence and the item 2 and Credentials Cloudflare clauses (Phase 3.1).
- [ ] The runbook diff is append-only: `git diff --numstat origin/main...HEAD -- knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md` shows a deleted column of 0 (three-dot form, so a moving main cannot turn it red) (Phase 4).
- [ ] The addendum states no cause for the p90 step, labels every owner figure `owner-supplied, not re-derived by this wrapper`, and carries the 5xx row as `not yet read; first sanctioned read after merge` with the exact command.
- [ ] `knowledge-base/project/specs/feat-one-shot-cf-analytics-reader-12441/decision-challenges.md` passes `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh` (rows well formed; every technical row carries `Ruled by CTO agent` or `Ruled by CLO agent`).
- [ ] ADR-289 carries the `## Addendum 2026-11-09 (Ref #12441, #10479, #10205)` heading and its diff is additions only: `git diff --numstat origin/main...HEAD -- knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md` shows 0 deleted lines except the one `related:` line; `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] The learning file exists in the repo's learning format and the two Playwright doc notes are single lines.
- [ ] The PR body references `Ref #12441`, `Ref #10479`, `Ref #10205` only; `gh pr view --json closingIssuesReferences` returns `[]` before the body is saved; it lists the four owner-review items from the CLO rulings and one justification line per filed issue; `prepush-secret-scan.sh` ran before every push; the PR is a draft, not armed, not ready.
- [ ] No credential value appears in any committed file, PR text, log or transcript (the suite's leak needles plus a final `/usr/bin/grep -a` of the diff for the fake-token prefixes and for `Bearer`).

### Post-merge (after the owner's typed go on the merge; tracked by #12441, which stays open)

- [ ] First sanctioned read: from a fresh checkout where `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` is empty, run `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh analytics-health 216` and `... analytics-edge-errors 216`; record `Checked:` or `Unverified:` lines; commit the aggregate projection and the 5xx histogram to the runbook addendum in a docs-only follow-up (append-only). At most two fix PRs if query 2 returns `api-error`.

## Test Scenarios

- Given only the four old tokens, when `analytics-health 24` runs, then exit 10, `unverified - no-credential (CF_API_TOKEN_ANALYTICS_READ)`, curl never called.
- Given a valid token and a stub 200 with an `errors` array, when `analytics-edge-errors 24` runs, then exit 14 and `api-error`, with the message printed only if it passes the charset and word checks.
- Given a 2xx body with `zones: []`, then exit 14 and `unverified - no-zone-access`.
- Given a stub 200 with a `data.viewer.zones[0].httpRequestsAdaptiveGroups` array of three hours, when `analytics-health 3` runs, then one JSON line with `rows` 3, numeric fields rounded to one decimal, and the fixed `note`; a null duration passes through as null, a string count is `bad-response (shape)`.
- Given a fixed fake clock and hours 216, then the recorded body's `end - start` equals 777600 seconds and `end` is on the hour; given hours 217, exit 64 before any token read.
- Given statuses 502, 503 and 520 in the response, when `analytics-edge-errors` projects them, then `by_status` has one key per observed status with summed counts; given status 404 or a non-integer, the run is `bad-response (shape)`.
- Given `CF_ZONE_ID` with a quote or newline, then exit 64 and curl never called.
- Given shell tracing with the analytics token set, then exit 78 and no request.
- Given `--list`, then the six names and no network.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering
**Status:** reviewed
**Assessment:** CTO agent rulings of 2026-11-09 (the technical rows in `decision-challenges.md`, including the plan-review amendments to DESC ordering, the pre-flight checks, the projection, the cut `authz` mapping, the `no-zone-access` reason and the token-expiry handling, plus one operator-scope row): option B for the mechanism, inline validated literals, name and grammar, projection and verdict mapping, post-merge first read, recording discipline, test re-pins, no new ADR. Additional risks recorded: real-curl escape verification, token expiry 2027-02-07, sampled counts, possible under-reporting of edge-generated errors, `/health` not host-scoped.

### Legal
**Status:** reviewed
**Assessment:** CLO agent rulings of 2026-11-09 (two rows: the first amends the three Cloudflare sentences, the second ratifies the bounded GraphQL error message on four limits and adds a fourth owner-review item); the analytics POST reads stay Class R under seven stated conditions; no GDPR or ePrivacy concern (aggregate figures, no personal data selected, no new processor or transfer); no compliance-posture entry; ADR-289 addendum conditioned on the merge; a query that selects any per-visitor dimension must re-run the GDPR gate first.

Product/UX, Marketing, Finance, Operations, Sales and Support: no implication (no user-facing surface, no spend, no new vendor; the token already exists). The mechanical UI-surface override did not fire (no `components/`, `app/` or page path in the file lists), so there is no Product/UX Gate and no wireframe.

## Non-Goals and Deferrals

- A third `analytics-schema` introspection subcommand: rejected by the CTO (widens the CLO ruling); live schema verification happens through the diagnosable `api-error` of the two shipped queries.
- Per-colo breakdown, `originResponseStatus`, a `/robots.txt` control series, percentile fields beyond p50/p90: not asked for.
- Attribution of the p90 step to a cause: explicitly not claimed; separating the remaining candidates needs the post-merge reads and, for the TLS-handshake candidate, a controlled flip-back that is the owner's production decision and is not proposed here.
- Tracking: #12441 (open, Ref only) tracks the post-merge read and the runbook follow-up; the expiry of `CF_API_TOKEN_ANALYTICS_READ` on 2027-02-07 is carried by a comment on #12441 and, durably, by the wrapper header, the runbook addendum and the `token-invalid` Records line (CTO ruling: no standalone issue).

## Sharp Edges

- The `components.test.ts` Cloudflare clause is checked for polarity words (`permits`, `except`, `unless`, `but`); the CLO text avoids them, and any rewording must too. Re-run the test after every wording edit.
- `edit_once` mutation rows fail on anything but exactly one anchor match; adding a second curl site makes `"$CURL" --disable` and `/usr/bin/env -i "$CURL"` anchors ambiguous. Re-anchor and mirror them; never loosen `edit_once`.
- The stub reads stdin only for `--config -`; the POST stdin now has three lines. The existing "stdin is exactly one line" row must stay scoped to the GET subcommands, or it goes red for the wrong reason.
- `guard_body` cannot be reused: GraphQL has no `.success`. A `guard_body`-style check that treats a missing `.success` as `bad` would mask a valid response; a check that treats it as `ok` would mask `errors`.
- `date -u -d @<digits>` and `date -u +%s` both run under `env -i`; the `tool_uses`/`tool_anchored` census counts them and must be re-derived, not bumped by hand.
- Do not run the wrapper live from this branch before merge unless the owner gives a typed per-command go naming the exact command; the Class R drift rule cannot be satisfied by an unmerged file.
- The `&lt;` / `&gt;` in the CLO's reply are display escapes; the repository text keeps literal angle brackets.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one declares `none` with a reason.
- `project()` hardwires `--argjson limit "$LIMIT"` (50) and the census pins the literal; `truncated` needs the per-query limit through its own `--argjson` name, re-pinned on purpose.
- A second `case "$SUB" in ... esac` for arity corrupts `dispatcher_block`; use `if` or `case "$1"`.
- `/usr/bin/env -i` on the POST curl site is not covered by the existing env group (it loops over the four GET subcommands); the per-site census and the `env[analytics]` row exist for that.
- The bounded `graphql:` message is vendor free text on a Class R read: it needs the CLO's four limits (including the dotted-quad/colon-hex refusal), and its token-copy check runs in bash, never in a jq line (the census forbids the token there).
- `scripts/suite-durations.tsv` weights this suite at 1261 ms (`floor`) against about 43 s measured; growth widens the gap, so check the ADR-240 drift advisory when it appears and do not treat it as ours to fix here.
- Public docs contradict nothing here but also do not confirm the status dimension or `_in`; never describe the 5xx histogram as verified until the first sanctioned read returns `ok`.
