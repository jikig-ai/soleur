---
title: "feat: LinkedIn Company Page data collection in the community monitor"
date: 2026-06-15
branch: feat-one-shot-linkedin-data-collection
issue: 4049
type: feature
lane: single-domain
brand_survival_threshold: aggregate pattern
status: draft
deepened: 2026-06-15
---

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Research Reconciliation, Phase 1, Phase 4, GDPR Gate, Risks
**Agents used:** code-simplicity-reviewer, architecture-strategist, silent-failure-hunter, test-design-reviewer, legal-compliance-auditor; repo-research-analyst + learnings-researcher (round 1); 4 WebFetch API-contract verifications.

### Key Improvements (applied)

1. **Cut follower demographic-facet collection** (`organizationalEntityFollowerStatistics` geo/industry/seniority/function breakdown). Three independent agents converged: YAGNI (no daily-digest consumer renders segmentation), silent-failure (small-count re-identification + `// 0` masking), and GDPR (the demographic facets are the ONE new undisclosed data category + the only HIGH compliance findings). Cutting it removes the INDEX-join, the most fragile fixture, AND the legal-scope amendment. fetch-metrics now = aggregate share stats + a single follower total.
2. **Defense-in-depth org-cred check** — `exit 1` (NOT `return 1`); run the check INSIDE each fetch command (not just `main()` dispatch — the personal token is live in the spawn env, so dispatch-only re-opens the silent-fallback); `local LINKEDIN_ACCESS_TOKEN=` so the org token cannot leak into the personal path; new test: personal token present + org creds absent → exit 1, no network call.
3. **Shape validation before `// 0` fallbacks** — empty `.elements` / wrong-shape 200 must not render as a real zero; emit an explicit error, let the cron's "log and continue" surface it.
4. **FINDER header threaded through `get_request`** (optional 3rd arg, forwarded on the 429 recursion) — not a forked local curl that would duplicate the only correct HTTP-status-verification + retry path.
5. **Test corrections** — LinkedIn's `handle_response` has NO 403-reason branching and the exit-2 path lives in `get_request` (not `handle_response`); don't copy x-community's 403 tests wholesale. Prefer a source-guard helper over a copied jq-transform string (drift hazard).

### New Considerations Discovered

- networkSizes contract confirmed live (2026-06-15): `GET /rest/networkSizes/urn%3Ali%3Aorganization%3A<id>?edgeType=COMPANY_FOLLOWED_BY_MEMBER` → `{firstDegreeSize}`; the `COMPANY_FOLLOWED_BY_MEMBER` enum is the v202305+ form (matches `LinkedIn-Version: 202602`).
- Posts author-finder requires `X-RestLi-Method: FINDER` header.
- Legal: share stats + follower total are ALREADY fully disclosed (DPD §2.3(p)(ii) "follower growth" + engagement); cutting demographics means no PA15/LIA/DPD scope amendment is needed. The first-Page-Insights-call joint-controller trigger (LIA counsel item #1) still fires, but is naturally gated by the cron's Tier-2 deferral (no sustained consumption until restore).
- Router status conflates posting-creds with read-creds (accepted pre-existing debt; see Phase 2).

# feat: LinkedIn Company Page data collection in the community monitor ✨

## Overview

The Soleur Community LinkedIn app (App `229658411`) now holds the read scopes needed
to consume aggregate Company Page insights directly — no Marketing Developer Platform
(MDP) partner approval required. As verified live **2026-06-15**, `LINKEDIN_ORG_ACCESS_TOKEN`
(Doppler `soleur/prd` + GitHub Actions secret) carries `r_organization_social`,
`rw_organization_admin`, `r_organization_followers` (plus `w_organization_social` for
posting); `LINKEDIN_ORG_ID=129094054`; and `GET https://api.linkedin.com/rest/organizations/129094054`
with `LinkedIn-Version: 202602` returns HTTP 200.

The two LinkedIn read commands in `linkedin-community.sh` were stubbed out under the
(now-disproven, as of 2026-06-15) premise that they required MDP partner approval. This
plan replaces those stubs with real, aggregate-only implementations, wires the cron
community monitor to collect LinkedIn metrics consistent with X/Bluesky, and adds tests.

This closes the LinkedIn data-collection gap tracked in **issue #4049** (whose title —
"file Marketing Developer Platform access request" — describes the now-unnecessary MDP
step; the issue should be closed as obsolete by this PR, see Acceptance Criteria).

**Legal posture (aggregate-only, no new surface):** The Data Protection Disclosure,
Article-30 register, and the LinkedIn Org-Page LIA
(`knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`)
already document aggregate Page Insights consumption as a joint-controller activity
under Art. 6(1)(f). Collection MUST stay aggregate-only: **no per-member data, no
follower-list extraction**. See GDPR / Compliance Gate below.

## User-Brand Impact

**If this lands broken, the user experiences:** the daily community-monitor GitHub issue
and `knowledge-base/support/community/<date>-digest.md` omit LinkedIn metrics, or (worse)
a LinkedIn fetch error halts the digest batch. Mitigation: the prompt's existing
"log the error and continue" batch discipline keeps a single platform failure non-fatal.

**If this leaks, the user's data is exposed via:** N/A for end-user PII — the org token
reads the operator's OWN Company Page aggregate insights, not third-party-user data. The
GDPR-relevant exposure is the aggregate demographic facets of *followers* (counts by
geo/industry/seniority). Mitigation: the script keeps only aggregate counts (never
per-follower records), and the cron digest summarizes/aggregates per the existing
"do not store raw transcripts" rule.

**Brand-survival threshold:** `aggregate pattern` — a single broken run degrades one
daily digest, not a per-user incident. (No `requires_cpo_signoff` frontmatter; section
present per preflight Check 6.)

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS) | Reality (verified 2026-06-15) | Plan response |
| --- | --- | --- |
| fetch-metrics should return "follower statistics" via `organizationalEntityFollowerStatistics` | `organizationalEntityFollowerStatistics` **lifetime** call no longer returns `totalFollowerCounts` (per Microsoft Learn `li-lms-2026-06`, updated 2026-05-13). A single follower total comes from a separate `networkSizes` endpoint. The lifetime stats call returns ONLY segmented demographic facets (counts by geo/industry/seniority/function). | **[Deepened — scope cut]** fetch-metrics does NOT call `organizationalEntityFollowerStatistics`. The follower total comes from `networkSizes` only: `GET /rest/networkSizes/urn%3Ali%3Aorganization%3A<id>?edgeType=COMPANY_FOLLOWED_BY_MEMBER` → `{firstDegreeSize}` (confirmed live 2026-06-15; `COMPANY_FOLLOWED_BY_MEMBER` is the v202305+ enum, matches `LinkedIn-Version: 202602`; scope `rw_organization_admin`). The demographic-facet breakdown is intentionally excluded — no daily-digest consumer renders segmentation, it is the only undisclosed legal-data-category, and small-count cross-tabs risk re-identification. |
| fetch-metrics should return "page/share statistics" via `organizationalEntityShareStatistics` | Confirmed. Lifetime call returns clean aggregate `totalShareStatistics` (`impressionCount`, `uniqueImpressionsCount`, `clickCount`, `likeCount`, `commentCount`, `shareCount`, `engagement`). No pagination, aggregate-only. | fetch-metrics calls `organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=urn%3Ali%3Aorganization%3A<id>` and surfaces `totalShareStatistics`. |
| URL-encode the URN colons as `%3A` | Confirmed — Restli 2.0 form (which the existing `get_request` already advertises via `X-Restli-Protocol-Version: 2.0.0`) requires `urn%3Ali%3Aorganization%3A<id>`. | Endpoint strings hardcode `%3A` encoding. |
| fetch-activity should return recent org page posts | Confirmed: `GET /rest/posts?author=urn%3Ali%3Aorganization%3A<id>&q=author&count=N&sortBy=LAST_MODIFIED` with header `X-RestLi-Method: FINDER`, requires `r_organization_social`. Returns `{paging, elements:[{id, author, commentary, publishedAt, createdAt, lifecycleState}]}` — aggregate post metadata, no per-member data. | fetch-activity calls the Posts author-finder. **[Deepened — decision]** Thread the `X-RestLi-Method: FINDER` header through `get_request` as an optional 3rd positional arg (forwarded on the 429-retry recursion at `:144`), NOT a fetch-activity-local curl — a local curl would fork the only correct copy of the `%{http_code}`-verification + 429-retry discipline. `get_request` is GET-only (post path is separate `post_request`), so the blast radius is GET callers only. `commentary` is operator-authored Page-public content; if a post `@mentions` a member it flows to the digest, but the LIA's no-`@mention` posting TOM bounds this — note in code, no filter needed. |
| "Verify whether community-router.sh needs a route" | Router uses `exec "$SCRIPT_DIR/$script" "$@"` — a **passthrough**. `community-router.sh linkedin fetch-metrics` already reaches `linkedin-community.sh fetch-metrics`. No route addition needed. | No router dispatch change. Only consider the `required_env_vars` registry note (see Phase 2). |
| Require `LINKEDIN_ORG_ACCESS_TOKEN` + `LINKEDIN_ORG_ID` for these commands | Confirmed both exist in the codebase already (`cron-content-publisher.ts` `PUBLISHER_ENV_KEYS`, `content-publisher.sh` constructs `urn:li:organization:${LINKEDIN_ORG_ID}`). `linkedin-community.sh` currently uses only `LINKEDIN_ORG_ACCESS_TOKEN` (reassigned into `LINKEDIN_ACCESS_TOKEN` for org posts, line 335) and does NOT reference `LINKEDIN_ORG_ID`. | New fetch commands add an org-cred check requiring BOTH vars, then reassign `LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"` before calling `get_request` (mirroring `cmd_post_content`). |
| cron prompt currently says "LinkedIn (if enabled): skip — log enabled (posting only)" | Confirmed at `cron-community-monitor.ts:173`. **Critical caveat:** the handler is currently **Tier-2 deferred** (`deferIfTier2Cron` early-returns and SKIPS the claude spawn). Prompt edits will not fire live until the cron is restored from `TIER2_DEFERRED_CRONS`. | Edit the prompt anyway (it is a verbatim-extracted constant with anchor-string regression tests, and is the documented source of truth). Note the deferral in the plan; no behavioral verification possible until restore — flag in Observability. |

## User-Brand Impact note: see section above.

## Implementation Phases

### Phase 0 — Preconditions (read-before-write, verify-before-assert)

- [x] Confirm stub line numbers still match: `linkedin-community.sh` `cmd_fetch_metrics()` (362-366) and `cmd_fetch_activity()` (368-372); usage/comment headers at lines 7-8 and 385-386.
- [x] Re-grep the cron test anchor lists and `buildSpawnEnv` positive/negative classes (`cron-community-monitor.test.ts:190-273`) so edits target the current line set.
- [x] Confirm `get_request` signature is `(endpoint, depth)` — query string MUST be baked into the `endpoint` arg (unlike `x-community.sh` which passes a 2nd query arg). The Bearer header reads `LINKEDIN_ACCESS_TOKEN`.
- [x] Confirm no negative-class substring collision: no negated var in the cron test contains the substring `LINKEDIN_ORG_ACCESS_TOKEN` or `LINKEDIN_ORG_ID` (verified 2026-06-15 — none do). New positive-class additions are safe.
- [x] deepen-plan: confirm exact `networkSizes` endpoint + the `X-RestLi-Method: FINDER` header requirement for the Posts author-finder against the installed `LinkedIn-Version: 202602`.

### Phase 1 — `linkedin-community.sh`: real fetch-metrics + fetch-activity

File: `plugins/soleur/skills/community/scripts/linkedin-community.sh`

- [x] **Add an org-read credential check** — new helper `require_org_credentials()` that fails LOUD with **`exit 1`** (NOT `return 1` — the script runs `set -euo pipefail`; a `return 1` consumed in a conditional/pipeline does NOT terminate, re-opening the fall-through. Mirror `require_credentials:44-54` which uses `exit 1`, NOT `cmd_post_content`'s `return 1` guard at `:264`). Fail when `LINKEDIN_ORG_ACCESS_TOKEN` OR `LINKEDIN_ORG_ID` is unset, with stderr naming the missing var(s) — **never silent-fallback to the personal token** (learning `2026-04-26-linkedin-org-token-fallback-silent-400.md`).
- [x] **Defense-in-depth ordering** — `require_org_credentials` runs BOTH at `main()` dispatch AND as the first line INSIDE `cmd_fetch_metrics`/`cmd_fetch_activity`. Dispatch-only enforcement is insufficient: the personal `LINKEDIN_ACCESS_TOKEN` is live in the cron spawn env (`buildSpawnEnv`), so any future direct call to the command function (test source, new code path) would silently fall back to it. The check must precede the token reassignment.
- [x] **fetch-metrics** (`cmd_fetch_metrics`): after the cred check, scope the org token function-locally: `local LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"` (so `get_request`'s Bearer header uses the org token without leaking into the personal path — strictly safer than the line-335 global mutation). Build the org URN as `urn%3Ali%3Aorganization%3A${LINKEDIN_ORG_ID}`, then TWO aggregate calls:
  - `get_request "/rest/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=urn%3Ali%3Aorganization%3A${LINKEDIN_ORG_ID}"` → `.elements[0].totalShareStatistics` (impressions, uniqueImpressions, clicks, likes, comments, shares, engagement).
  - `networkSizes`: `get_request "/rest/networkSizes/urn%3Ali%3Aorganization%3A${LINKEDIN_ORG_ID}?edgeType=COMPANY_FOLLOWED_BY_MEMBER"` → `.firstDegreeSize`.
  - **Shape validation before fallbacks** (silent-failure HIGH-1): `handle_response`'s 2xx branch validates only JSON parseability, not shape. Before composing, assert `.elements[0].totalShareStatistics` is a non-null object; if `.elements` is empty (`[]` — e.g. token lacks ADMINISTRATOR role on the org) or the shape is wrong, emit an explicit error to stderr and exit 1 — do NOT let `// 0` turn structural absence into a fake "0 impressions" zero. Apply `// 0`/`// null` only to genuinely-optional sub-fields.
  - **Partial-failure policy for networkSizes** (silent-failure HIGH-2): the networkSizes call must not abort the (more important) share-stats result. Capture its failure so `total_followers` degrades to `null` with a stderr warning rather than `get_request`'s default `exit` — i.e. invoke it in a subshell whose non-zero exit is tolerated, not inline where `set -e`/`get_request`'s `exit` would kill the whole command.
  - Compose `{ org_id, total_followers, share_statistics: {...} }` to stdout via `jq -n`. No demographic facets (cut). Do NOT copy `post_request`'s `{}`-plus-warning soft-success idiom (`:206-213`) — an unexpected metrics shape is an error, not a warning.
- [x] **fetch-activity** (`cmd_fetch_activity`): cred check + `local` token scoping (as above), then the Posts author-finder `get_request "/rest/posts?author=urn%3Ali%3Aorganization%3A${LINKEDIN_ORG_ID}&q=author&count=10&sortBy=LAST_MODIFIED"` with the `X-RestLi-Method: FINDER` header threaded via `get_request`'s new optional arg. Emit `{ posts: [{ id, commentary, published_at, lifecycle_state }] }` — post metadata only, no commenter/liker identities. Use INDEX/`//` fallbacks per `2026-03-10-jq-generator-silent-data-loss.md`.
- [x] **Thread the FINDER header through `get_request`** (architecture decision): add an optional 3rd positional arg `extra_header`; conditionally `-H "$extra_header"` in the curl; **forward it on the 429-retry recursion at `:144`** (`get_request "$endpoint" "$((depth+1))" "$extra_header"`) or a 429 retry silently drops the header and fails. Mirrors how `x-community.sh` threads `query_params` through its recursion.
- [x] **Update comment/usage headers**: lines 7-8 (top usage block) and 385-386 (main() usage) — replace "(requires Marketing API)" / "(Marketing API)" with the org-read-scope description (e.g. "(org read scopes: r_organization_social, rw_organization_admin)"). Date-anchored historical note: "Implemented 2026-06-15; the prior MDP-approval premise was incorrect — the org token already carries the read scopes." Also document `LINKEDIN_ORG_ACCESS_TOKEN`+`LINKEDIN_ORG_ID` as required env for the fetch commands in the top env-var block.
- [x] **Update `main()` dispatch** (lines 393-405): fetch-metrics/fetch-activity case arms run `require_org_credentials` before dispatching (the old stubs ran credential-free). Keep `post-content`'s existing `require_credentials` path unchanged.
- [x] Preserve exit-code conventions: 0 success, 1 error, 2 retryable (the existing `get_request`/`handle_response` enforce 429→retry→exit 2; reuse them). Note the exit-2 path lives in `get_request:122-125`, NOT in `handle_response`.

### Phase 2 — `community-router.sh` (verify; likely no change)

File: `plugins/soleur/skills/community/scripts/community-router.sh`

- [x] **No dispatch route needed** — `exec` passthrough already routes `linkedin fetch-metrics` / `fetch-activity`.
- [x] **Decision (deepen-plan):** the `linkedin` registry entry's `required_env_vars` is `LINKEDIN_ACCESS_TOKEN,LINKEDIN_PERSON_URN` (posting creds), which gates the `cmd_platforms` "enabled/disabled" status. The cron prompt instructs the agent to skip a platform shown "disabled". For fetch-metrics to be reachable in the digest, LinkedIn must show "enabled". Options: (a) leave as-is and rely on the existing posting creds being present in the spawn env (they are, per `buildSpawnEnv`), or (b) document that org-read readiness is a separate axis. Default: **leave the registry entry unchanged** (changing it would couple platform-status to org-read creds, a semantic the rest of the router does not use) and instead ensure the cron prompt explicitly attempts fetch-metrics when LinkedIn is enabled. Record the chosen option in the spec.

### Phase 3 — `cron-community-monitor.ts`: collect LinkedIn data

File: `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`

- [x] **Edit `COMMUNITY_MONITOR_PROMPT`** (line 173): replace
  `- LinkedIn (if enabled): skip — log "enabled (posting only)".`
  with an instruction to collect data via the router, consistent with X/Bluesky, e.g.:
  `- LinkedIn (if enabled): append \`bash plugins/soleur/skills/community/scripts/community-router.sh linkedin fetch-metrics\` to the same call (and optionally \`... linkedin fetch-activity\`). If it fails, log and continue.`
  Use the **literal router path** in every invocation (no shell-var) per the containment-hook allowlist discipline already documented in the prompt (lines 163-166).
- [x] **Update the `## LinkedIn Activity` digest section** instruction (line 186 already lists `## LinkedIn Activity` as an optional section) so the agent includes LinkedIn total followers + aggregate post engagement (impressions/likes/comments/shares), aggregate-only. To distinguish "LinkedIn quiet" from "LinkedIn broken" (silent-failure MEDIUM-2 + `hr-no-dashboard-eyeball-pull-data-yourself`), instruct the agent: if the LinkedIn fetch fails, write an explicit `## LinkedIn Activity` line "collection failed: <reason>" rather than silently omitting the section.
- [x] **Extend `buildSpawnEnv`** (lines 236-255): add `LINKEDIN_ORG_ACCESS_TOKEN: process.env.LINKEDIN_ORG_ACCESS_TOKEN` and `LINKEDIN_ORG_ID: process.env.LINKEDIN_ORG_ID` to the explicit allowlist (NOT a spread). Update the surrounding comment block (lines 220-235) to list the two new community-read vars.
- [x] **Update the SHAPE-DIFF / buildSpawnEnv comment** (lines 33-36) listing the community vars so the inline doc stays accurate.
- [x] **Resilience:** no handler-logic change — the prompt's per-batch "log the error and continue" already matches the existing X/Bluesky pattern; a LinkedIn fetch failure must not halt the batch.
- [x] **Deferral note:** add a one-line code comment near line 173 that the LinkedIn collection step only fires once `cron-community-monitor` is restored from `TIER2_DEFERRED_CRONS` (the handler currently early-returns via `deferIfTier2Cron`). Do NOT attempt to un-defer the cron in this PR (out of scope; see Non-Goals).

### Phase 4 — Tests

**4a. Shell-command tests** — new file `test/linkedin-community.test.ts` (root `test/`, bun:test), mirroring `test/x-community.test.ts`:

- [x] Credential validation: fetch-metrics / fetch-activity with no org creds → exit 1, stderr names the missing var(s). With only `LINKEDIN_ORG_ACCESS_TOKEN` set (no `LINKEDIN_ORG_ID`) → exit 1.
- [x] **Silent-fallback negative test (must-have, silent-failure CRITICAL-2)**: org creds absent BUT personal `LINKEDIN_ACCESS_TOKEN=personal` set → still exit 1, NO network call, and stderr does NOT contain "401"/"expired" (proves no fall-through to the personal token).
- [x] jq-transform unit tests fed via stdin (the `Bun.spawnSync(["jq", TRANSFORM], { stdin })` pattern): synthesized `organizationalEntityShareStatistics` and Posts author-finder fixtures → assert the composed aggregate JSON shape + missing-field fallbacks. **Empty-elements fixture**: a 200 with `{elements: []}` must NOT emit a fake `total_followers: 0` / zero share-stats — it must signal the abnormal/empty shape (silent-failure HIGH-1). **Fixtures synthesized only — no real tokens, no real API calls** (`cq-test-fixtures-synthesized-only`). Prefer a source-guard helper that exercises the REAL script transform over a copied jq-string literal (the x-community pattern hardcodes the transform in the test → silent drift; LinkedIn's source guard at `:409` makes the helper approach viable).
- [x] `handle_response` tests via a `test/helpers/test-handle-response-linkedin.sh` (sources `linkedin-community.sh` via its `:409` source guard). **Assert LinkedIn's ACTUAL handler shape, not x-community's**: LinkedIn `handle_response` has NO 403-reason branching (single generic `.message // .code // "Access denied"` at `:91`) — assert 403 → exit 1 + generic message only; do NOT copy x-community's three 403-reason tests. The 429→exit-2 retry-exhaustion lives in `get_request:122-125` (depth guard), NOT in `handle_response` — assert exit 2 by calling `get_request` at `depth=3` (the guard short-circuits before any curl, so still no network), not via the handle_response helper.
- [x] Use `describeIfJq` guard and `NO_CREDS_ENV` / a `FAKE_ORG_CREDS_ENV` (`LINKEDIN_ORG_ACCESS_TOKEN=test`, `LINKEDIN_ORG_ID=12345` — synthetic, not the real org ID; fixture hygiene).
- [x] **TDD ordering** (`cq-write-failing-tests-before`): at /work, write the credential + transform tests RED before implementing `require_org_credentials` / `cmd_fetch_metrics`.
- [x] **Register the new suite in `scripts/test-all.sh`**: root `test/*.test.ts` suites are NOT glob-discovered — they are explicitly named in the `want_bun()` block (`test-all.sh:147-149`, block `146-150`). Add `run_suite "test/linkedin-community" bun test test/linkedin-community.test.ts`. Without this the suite silently never runs (Sharp Edge: test path must satisfy the runner's discovery). AC verifies the suite name appears in the runner output.

**4b. Cron-monitor source-shape tests** — `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` (vitest):

- [x] **buildSpawnEnv positive class** (lines 191-206): add `LINKEDIN_ORG_ACCESS_TOKEN` and `LINKEDIN_ORG_ID` to the `it.each` list (assertion form `expect(buildEnvBody).toContain(`${key}: process.env.${key}`)`).
- [x] **buildSpawnEnv negative class** (lines 212-258): NO change — verified no negated var collides with the new names.
- [x] **Prompt anchor regression** (lines 102-175): add an anchor for the new LinkedIn invocation, e.g. `["bash plugins/soleur/skills/community/scripts/community-router.sh linkedin fetch-metrics", "LinkedIn fetch-metrics invocation (literal path)"]`. Confirm the OLD anchor `"LinkedIn (if enabled): skip"` is NOT currently asserted (it is not — safe to remove from the prompt).
- [x] Keep all existing anchors intact (verbatim-extraction discipline — learning `2026-06-01-cron-producer-classification-must-read-full-prompt-including-noop-branch.md`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `cmd_fetch_metrics` and `cmd_fetch_activity` no longer contain the substrings `Marketing API` or `MDP partner` (grep returns 0 in the two function bodies AND the usage/comment headers).
- [x] `bash plugins/soleur/skills/community/scripts/linkedin-community.sh fetch-metrics` with no org creds exits 1 (via `exit`, not `return`) and stderr names `LINKEDIN_ORG_ACCESS_TOKEN` / `LINKEDIN_ORG_ID` (no network call).
- [x] Silent-fallback negative: org creds absent + `LINKEDIN_ACCESS_TOKEN=personal` set → exit 1, no network, stderr has no "401"/"expired".
- [x] Endpoint strings contain `%3A`-encoded URNs (`urn%3Ali%3Aorganization%3A`), the `organizationalEntityShareStatistics` path, and the `networkSizes/...?edgeType=COMPANY_FOLLOWED_BY_MEMBER` path. **No `organizationalEntityFollowerStatistics`** (demographic facets cut).
- [x] jq-transform unit tests pass for synthesized share-stats + posts fixtures (aggregate shape; missing-field fallbacks); the empty-`elements` fixture does NOT render fake zeros.
- [x] `scripts/test-all.sh` (TEST_GROUP=bun) runs `test/linkedin-community.test.ts` (suite appears in output) and passes.
- [x] `cron-community-monitor.test.ts` passes with the new positive-class members and the new prompt anchor; full suite green via `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and the vitest run.
- [x] `buildSpawnEnv` allowlist contains `LINKEDIN_ORG_ACCESS_TOKEN` and `LINKEDIN_ORG_ID` and still contains no `...process.env` spread and no `X_ALLOW_POST`.
- [ ] PR body uses `Closes #4049` (the issue's MDP premise is obsolete; this PR resolves the underlying data-collection gap). PR has `## Changelog` + `semver:minor` label (new command capability).

### Post-merge (operator) — none

- [ ] No operator step required. `LINKEDIN_ORG_ACCESS_TOKEN` + `LINKEDIN_ORG_ID` already exist in Doppler `soleur/prd` and as GitHub Actions secrets (verified 2026-06-15). The cron remains Tier-2-deferred independently of this PR; restoring it is tracked separately (Non-Goals).

## Non-Goals / Out of Scope

- **Restoring `cron-community-monitor` from `TIER2_DEFERRED_CRONS`** — the handler early-returns via `deferIfTier2Cron`; un-deferring requires the per-construct Bash-allowlist / egress work tracked in the Tier-2 restore effort (#5018 / #5046 lineage). Deferral tracking: note in the spec and reference the existing Tier-2 restore issue rather than filing a new one.
- **Per-member / follower-list extraction, time-bound demographic series, ad/sponsored analytics** — explicitly excluded to keep collection aggregate-only per the LIA.
- **`networkSizes` historical trend storage** — fetch-metrics returns a point-in-time aggregate; no time-series persistence.

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7] — triggered by (a) new processing activity using an external API on Page-Insights data and (d) artifact distribution (plugin update). Run `/soleur:gdpr-gate` against this plan + the new shell code at /work time.

**Deepened (legal-compliance-auditor, 2026-06-15):** The original "no new legal surface"
claim held for lawful basis but NOT for disclosed data scope — the follower
**demographic facets** (counts by geo/industry/seniority/function) were the one new
undisclosed data category (HIGH) AND carried a small-count re-identification risk
(MEDIUM). **This plan now CUTS demographic-facet collection** (Phase 1 / Research
Reconciliation), which resolves both findings: the two remaining metrics — aggregate
share statistics and the single follower total (`networkSizes.firstDegreeSize`) — are
ALREADY fully enumerated in DPD §2.3(p)(ii) ("aggregate engagement metrics … follower
growth"), PA15, and the 2026-05-19 LIA. **No PA15 / LIA / DPD scope amendment is
required.**

Remaining gate items for /work:
- **Joint-controller trigger (LIA counsel item #1):** this PR is the first code path that
  issues a real Page Insights API call — the LIA flags the C-210/16 / Art. 26 written-
  arrangement confirmation as outstanding "before sustained consumption." This is
  naturally gated by the cron's Tier-2 deferral (no sustained consumption until restore).
  Record the trigger as fired; resolve the JCA-acceptance note before the cron is restored.
- **fetch-activity `commentary`:** operator-authored Page-public post text. If a post
  `@mentions` a member it flows to the digest, but the LIA's no-`@mention` posting TOM
  bounds this — document in code, no inbound filter needed.
- **Confirm aggregate-only:** no per-follower records, no follower-list extraction, no
  commenter/liker identities in fetch-activity output, no facet cross-tabulation.

## Infrastructure (IaC)

None. Pure code change against already-provisioned secrets (`LINKEDIN_ORG_ACCESS_TOKEN`,
`LINKEDIN_ORG_ID` already in Doppler `soleur/prd` + GitHub Actions). No new server,
secret, vendor, or persistent runtime process. Phase 2.8 skip conditions met.

## Observability

```yaml
liveness_signal:
  what: cron-community-monitor's existing Sentry monitor "scheduled-community-monitor" (output-aware heartbeat — RED if no digest issue filed in run window)
  cadence: daily 08:00 UTC (when restored from Tier-2 deferral)
  alert_target: Sentry cron monitor scheduled-community-monitor
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf + resolveOutputAwareOk in handler
error_reporting:
  destination: Sentry via reportSilentFallback (handler) + per-batch stderr logging (prompt "log the error and continue")
  fail_loud: yes — org-cred-missing exits 1 with descriptive stderr; LinkedIn API non-2xx routes through handle_response (exit 1/2)
failure_modes:
  - mode: org token expired / wrong scope (401/403)
    detection: handle_response prints "HTTP 401/403 for <endpoint>" to stderr; cron-linkedin-token-check.ts independently monitors LINKEDIN_ORG_ACCESS_TOKEN TTL
    alert_route: stderr in cron run log + existing linkedin-token-check Sentry monitor
  - mode: LinkedIn fetch fails mid-digest
    detection: prompt "log the error and continue" — digest still produced without LinkedIn section
    alert_route: digest content (LinkedIn section absent) + cron heartbeat stays green if issue filed
  - mode: prompt edit lands but cron stays Tier-2-deferred
    detection: deferIfTier2Cron posts an honest on-schedule check-in; no live LinkedIn collection until restore
    alert_route: documented in code comment; not a regression (pre-existing deferral)
logs:
  where: Inngest run logs (handler) + Sentry (reportSilentFallback) — NO ssh required
  retention: per existing Inngest/Sentry retention
discoverability_test:
  command: grep -l "linkedin fetch-metrics" apps/web-platform/server/inngest/functions/cron-community-monitor.ts
  expected_output: cron-community-monitor.ts
  note: source-presence probe — the cron is Tier-2-deferred (no live endpoint until restore), so this confirms the collection wiring is in the handler without an SSH/live dependency. Behavioral coverage is the cron vitest suite (CI webplat shard) + the live router fetch-metrics verified at QA 2026-06-15.
```

## Domain Review

**Domains relevant:** Legal (advisory — pre-covered), Support (community monitor owner)

### Legal

**Status:** reviewed (legal-compliance-auditor, 2026-06-15)
**Assessment:** Aggregate Page Insights consumption is already disclosed (DPD §2.3(p)(ii),
Article-30 PA15, 2026-05-19 LIA). The auditor's only HIGH findings concerned the follower
**demographic facets** (undisclosed data category + small-count re-identification) — which
this plan now CUTS. The two retained metrics (aggregate share stats + single follower
total) are fully within the disclosed scope: **no PA15/LIA/DPD scope amendment required.**
Remaining: record the first-Page-Insights-call joint-controller trigger (LIA counsel item
#1), naturally gated by the Tier-2 deferral. CLO sign-off not required (threshold =
aggregate pattern, not single-user incident). GDPR gate (Phase 2.7) re-confirms at /work.

### Support

**Status:** reviewed
**Assessment:** This is the community-manager / cron-community-monitor surface. Change is
additive (one more platform's aggregate metrics in the daily digest), consistent with
existing X/Bluesky collection. No new user-facing surface.

### Product/UX Gate

Not applicable — no UI surface. No file under `components/**`, `app/**/page.tsx`, or
`app/**/layout.tsx`. Mechanical UI-surface override did not fire. Tier: NONE.

## Open Code-Review Overlap

None — checked open `code-review`-labelled issues against the planned file set
(`linkedin-community.sh`, `community-router.sh`, `cron-community-monitor.ts`,
`cron-community-monitor.test.ts`, new `test/linkedin-community.test.ts`,
`scripts/test-all.sh`); to be re-confirmed at /work Phase 0 via the `gh issue list
--label code-review` two-stage jq query.

## Risks & Mitigations (Precedent-Diff Gate — Phase 4.4)

**Pattern-bound behavior: org-token reassignment for the org-read path.** Precedent exists
at `linkedin-community.sh:328-336` (`cmd_post_content` does `LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"`
as a GLOBAL mutation, guarded by `return 1` on missing token). **Diff for the new fetch
commands:** use a function-LOCAL `local LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"`
instead of the global mutation, and `exit 1` (not `return 1`) in the cred check. This is
strictly safer than the precedent (org token cannot leak into the personal path; missing
creds reliably terminate under `set -e`). Rationale: the precedent's global mutation is
safe only because each `exec`'d invocation runs one command then exits — but the `local`
form removes that latent assumption at near-zero cost.

**Pattern-bound behavior: `X-RestLi-Method: FINDER` header on a GET.** No precedent in this
repo (novel). Closest analog: `x-community.sh`'s `get_request` threads `query_params`
through its 429-retry recursion. The new `get_request` optional-header arg mirrors that
threading shape. Flag for reviewer scrutiny: the 429-retry recursion MUST forward the
header (`:144`).

**Risk: networkSizes is the only follower-total source.** If the call fails, `total_followers`
degrades to `null` (not abort) per the partial-failure policy in Phase 1. Aggregate-only,
no PII risk. Endpoint contract confirmed live 2026-06-15.

**Risk: shape-blind 2xx.** `handle_response` validates JSON parseability only; empty
`.elements` (no ADMINISTRATOR role) would otherwise render as fake zeros. Mitigated by the
explicit shape check in Phase 1 + the empty-elements fixture test in Phase 4a.

## Premise Validation

Checked 2026-06-15: (1) Issue #4049 is OPEN; its title describes the now-unnecessary MDP
access request — the ARGUMENTS' premise that MDP approval is NOT needed is correct, and
the issue should close as obsolete. (2) All cited code artifacts exist on origin/main
with stubs at the exact cited lines (`linkedin-community.sh:362-372`, prompt line 173).
(3) Org token scopes/endpoints verified against current Microsoft Learn docs
(`li-lms-2026-06` moniker, matching `LinkedIn-Version: 202602`): both stat endpoints
require `rw_organization_admin` + ADMINISTRATOR role; Posts author-finder requires
`r_organization_social`. (4) One reality correction carried into Research Reconciliation:
lifetime follower stats no longer return a single total count (needs `networkSizes`).
(5) Legal artifacts (DPD, Article-30, LIA) exist and pre-cover aggregate Page Insights —
"no new legal surface" holds. No rejected-alternative ADR found for this mechanism.

## Research Insights (file:line citations)

- Stub source: `plugins/soleur/skills/community/scripts/linkedin-community.sh:362-372` (both stubs), usage headers `:7-8`, `:385-386`; org-token reassignment precedent `:328-336`; `get_request(endpoint, depth)` `:118-145` (Bearer reads `LINKEDIN_ACCESS_TOKEN`); `handle_response` `:63-111` (429→retry, exit 2 on exhaustion).
- Router passthrough: `plugins/soleur/skills/community/scripts/community-router.sh:58-78` (`exec`); `linkedin` registry entry `:16` (`required_env_vars=LINKEDIN_ACCESS_TOKEN,LINKEDIN_PERSON_URN`).
- Cron handler: `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — prompt LinkedIn line `:173`, `buildSpawnEnv` `:236-255`, comment block `:220-235` + `:33-36`, Tier-2 defer `:270-279`.
- Cron tests: `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` — positive class `:190-206`, negative class `:208-273`, prompt anchors `:102-175`.
- Shell test convention: `test/x-community.test.ts` (bun:test, `describeIfJq`, `NO_CREDS_ENV`/`FAKE_CREDS_ENV`, jq-transform via stdin); helper `test/helpers/test-handle-response.sh`; runner registration `scripts/test-all.sh:147-149` (explicit `run_suite`, NOT glob-discovered); `bunfig.toml` excludes `apps/web-platform/**` from bun.
- LinkedIn vars already in codebase: `cron-content-publisher.ts` `PUBLISHER_ENV_KEYS`; `scripts/content-publisher.sh` builds `urn:li:organization:${LINKEDIN_ORG_ID}`; `cron-linkedin-token-check.ts` monitors org token TTL.
- Legal: `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`, `knowledge-base/legal/article-30-register.md`, `docs/legal/data-protection-disclosure.md`.
- API contracts verified via Microsoft Learn (`li-lms-2026-06`):
  - Follower stats: `GET /rest/organizationalEntityFollowerStatistics?q=organizationalEntity&organizationalEntity=urn%3Ali%3Aorganization%3A<id>` — scope `rw_organization_admin`; lifetime call no longer returns `totalFollowerCounts`. <!-- verified: 2026-06-15 source: learn.microsoft.com/.../organizations/follower-statistics -->
  - Share stats: `GET /rest/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=urn%3Ali%3Aorganization%3A<id>` → `totalShareStatistics{impressionCount,uniqueImpressionsCount,clickCount,likeCount,commentCount,shareCount,engagement}`; no pagination. <!-- verified: 2026-06-15 source: learn.microsoft.com/.../organizations/share-statistics -->
  - Posts author-finder: `GET /rest/posts?author=urn%3Ali%3Aorganization%3A<id>&q=author&count=N&sortBy=LAST_MODIFIED` + header `X-RestLi-Method: FINDER` — scope `r_organization_social`. <!-- verified: 2026-06-15 source: learn.microsoft.com/.../shares/posts-api -->

## Relevant Learnings

- `2026-04-26-linkedin-org-token-fallback-silent-400.md` — fail LOUD when org token missing; never silent-fallback to lesser-scope token.
- `2026-04-09-linkedin-org-access-token-for-company-page-posts.md` — LinkedIn tokens are scope-bound; org operations need the org token.
- `2026-03-10-jq-generator-silent-data-loss.md` — use `INDEX()` joins, not generator-style joins, to preserve records.
- `2026-05-29-http-verification-gates-must-check-status-not-just-transport.md` — capture `%{http_code}` and verify 2xx before parsing (existing `handle_response` already does this; preserve it).
- `2026-06-03-platform-disabled-despite-creds-check-spawn-env-allowlist.md` — explicit spawn-env allowlists silently drop unlisted vars; add the org vars to `buildSpawnEnv` AND its positive-class test.
- `2026-06-01-cron-producer-classification-must-read-full-prompt-including-noop-branch.md` — preserve verbatim anchors when editing the prompt.
- `2026-06-03-always-create-cron-turn-budget-exhaustion-drops-last-step-artifact.md` — adding a LinkedIn batch step adds turns; `--max-turns 80` already raised; deepen-plan to confirm headroom (one extra fetch call is small).
- `2026-05-30-shell-assert-value-embed-breaks-on-apostrophes.md` / `2026-05-05-extracted-bash-functions-need-self-contained-state.md` — test-helper hygiene if a sourced helper is added.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- Root `test/*.test.ts` suites are explicitly named in `scripts/test-all.sh` — a new suite NOT added there silently never runs. (Phase 4a covers this.)
- The cron is Tier-2-deferred: the prompt edit is testable via source-shape assertions but NOT live-verifiable until the cron is restored. Do not claim live LinkedIn collection in the PR body.
- `get_request` takes only `(endpoint, depth)` — bake the full query string into `endpoint`; do not assume an x-community-style 2nd query arg exists. (This plan ADDS an optional 3rd `extra_header` arg for the FINDER header — forward it on the 429 recursion.)
- Org-cred check MUST use `exit 1`, not `return 1` (the `cmd_post_content:264` precedent uses `return 1` which `set -e` can swallow in a conditional/pipeline). Use `local LINKEDIN_ACCESS_TOKEN=` inside the fetch commands, NOT the global mutation at `:335`.
- `handle_response` validates JSON parseability but NOT shape — an empty `.elements` 200 (no ADMINISTRATOR role) would render as fake zeros under `// 0`. Add an explicit shape check before fallbacks.
- Don't copy x-community's 403-reason tests: LinkedIn's `handle_response` has no reason branching; the exit-2 path lives in `get_request`, not `handle_response`.
- Demographic-facet collection is intentionally OUT — re-adding it reopens the undisclosed-data-category + small-count re-identification findings (cut per deepen-plan, 3-agent convergence).
- Negative-class substring safety: confirmed no negated var collides with `LINKEDIN_ORG_*`; re-verify at /work if the negative list changes.
- Typecheck/test commands for `apps/web-platform` MUST be `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and `./node_modules/.bin/vitest run <path>` — NOT `npm run -w`.
