---
issue: 3375
type: docs
classification: ops-only-prod-write
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

# fix: Document X-Robots-Tag api.soleur.ai no-op (DNS-only CNAME bypasses CF edge)

## Overview

PR #3296 added a Cloudflare Transform Rule to inject `X-Robots-Tag: noindex,
nofollow` on `api.soleur.ai` GET responses. Post-apply curl verification on
2026-05-06 confirms the rule does NOT fire — `api.soleur.ai` is a DNS-only
CNAME (`ifsccnjhymdmidffkzhl.supabase.co`), so requests bypass the soleur.ai
zone's Cloudflare edge entirely. The Transform Rule lives on the soleur.ai
zone; only proxied (orange-cloud) records or hostnames whose DNS targets
soleur.ai's edge will trigger it.

**Decision (per issue #3375 recommendation):** Option 3 — leave the rule in
place and document the no-op gap inline, with a follow-up tracker for
re-evaluation if Supabase Custom Domains adds header injection or if
`api.soleur.ai` is ever proxied through soleur.ai's CF edge.

**Rationale:** the rule is dormant infrastructure that fires correctly the
moment `api.soleur.ai` is proxied (Option 1) — removing it (Option 2) makes
that future flip more error-prone. Real indexing exposure is low because
`api.soleur.ai` returns 401/404/403 on every authenticated path; there is
no body content for Google to surface. The X-Robots-Tag was defense-in-depth
against URL-existence-recording. The cost of the no-op is purely
honesty/observability (the curl verification surprise), not user blast
radius — which is why the brand-survival threshold is `aggregate pattern`,
not `single-user incident`.

## Research Reconciliation — Spec vs. Codebase

Verified at plan time (2026-05-06):

| Issue claim                                                              | Codebase reality                                                                 | Plan response                                                                 |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `api.soleur.ai` is DNS-only CNAME → `ifsccnjhymdmidffkzhl.supabase.co`   | `dig +short CNAME api.soleur.ai` → `ifsccnjhymdmidffkzhl.supabase.co.` confirmed | Confirmed; document in comment.                                               |
| `curl -X GET https://api.soleur.ai/` returns 404 with no `x-robots-tag`  | Reproduced 2026-05-06: HTTP/2 404, no `x-robots-tag` header in response          | Confirmed; this is the no-op evidence.                                        |
| `deploy.soleur.ai` rule DOES fire (proxied subdomain)                    | Reproduced 2026-05-06: `x-robots-tag: noindex, nofollow` present                 | Confirmed; comment must distinguish proxied vs DNS-only.                      |
| Other api.soleur.ai consumers exist (validate-url, OAuth probes, tests)  | `apps/web-platform/lib/supabase/validate-url.ts`, `oauth-probe-contract.test.ts`, `client-prod-guard.test.ts` use the hostname; none rely on X-Robots-Tag | None — those consumers are unaffected by the no-op (they care about request URL, not response headers). |

## User-Brand Impact

**If this lands broken, the user experiences:** No new user-facing surface.
This PR only edits comments in `apps/web-platform/infra/seo-rulesets.tf`
and creates a follow-up tracking issue. No runtime path changes; no DNS
changes; no Transform Rule mutations beyond the comment delta. A `terraform
plan` after this change will show only comment-line drift on the existing
`cloudflare_ruleset.seo_response_headers` resource (and may show no diff at
all if Cloudflare's API normalizes comment-only changes — in which case
`terraform apply` is a no-op).

**If this leaks, the user's [data / workflow / money] is exposed via:** Not
applicable — comments do not change runtime behavior. The pre-existing
no-op condition (rule defined, header not emitted) is the documented
state, not an introduced regression.

**Brand-survival threshold:** aggregate pattern.

Rationale: The underlying no-op was the user-brand-critical concern
(see learning `2026-05-06-user-impact-section-by-role-not-surface.md`,
which DISSENT'd PR #3296 specifically because the api.soleur.ai vector
was under-enumerated). However, the no-op's actual user impact is bounded
by Supabase's own response surface — `api.soleur.ai` returns 401/404/403
on every authenticated path with no crawlable body content. The threshold
is `aggregate pattern` because the systemic concern is "we have
infrastructure that looks live but isn't" — a pattern that drifts across
config flips, not a single-user incident.

**Roles considered (per `2026-05-06-user-impact-section-by-role-not-surface.md`):**

- **Prospect (anonymous Googlebot):** Could record `api.soleur.ai`'s URL existence in CT-log enumeration. Today: 401/404 surface only; no body to index. No regression from this PR.
- **Authenticated app user (Supabase REST/Auth/Realtime):** Hits api.soleur.ai for every login, session, conversation read, BYOK operation. Cares about latency and reliability — NOT about response-header indexing controls. Unaffected.
- **Legal-document signer / billing customer / GitHub OAuth owner / admin:** None of these roles route through `api.soleur.ai` for indexable surfaces. Unaffected.

`threshold: aggregate pattern` — the section is required because
`apps/web-platform/infra/**` is a sensitive path (per preflight Check 6),
and this row provides the rationale; no per-PR sign-off required.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/seo-rulesets.tf` rule for `api.soleur.ai` GET responses (current lines ~257-275) carries an inline comment block stating: (a) the rule is currently a no-op because api.soleur.ai is DNS-only CNAME → Supabase, (b) the rule is intentionally retained so it fires automatically if/when the hostname is proxied through soleur.ai's edge, (c) re-evaluation criteria with link to the follow-up tracker.
- [ ] The comment block names the load-bearing fact: Cloudflare Transform Rules on the `soleur.ai` zone only fire on traffic that transits soleur.ai's CF edge — DNS-only records bypass the edge, so the rule is silently a no-op until the record is proxied.
- [ ] The comment cites the post-apply verification (`curl -X GET https://api.soleur.ai/` returns no `x-robots-tag` header on 2026-05-06) and the contrast with `deploy.soleur.ai` (proxied; rule DOES fire).
- [ ] A new GitHub issue is created (label: `infrastructure`, `seo`; milestone: `Post-MVP / Later`) tracking the re-evaluation, with re-evaluation criteria: (1) Supabase Custom Domains adds header-injection feature, OR (2) `api.soleur.ai` is migrated to soleur.ai's edge (orange-cloud + Origin Certificate). The comment in `seo-rulesets.tf` references this issue number.
- [ ] PR body uses `Closes #3375` (the issue is closed when the comment + tracker land — there is no post-merge operator action; this is NOT an ops-remediation class).
- [ ] `terraform plan` (against the prd_terraform Doppler config) shows either zero diff or comment-only drift on `cloudflare_ruleset.seo_response_headers`. No rule add/remove/reorder. No expression mutation. No `enabled` toggle.
- [ ] All existing tests pass (no new tests required — comment-only change to `.tf`).

### Post-merge (operator)

- [ ] If `terraform plan` showed comment-only drift on the resource, run `terraform apply` from `apps/web-platform/infra/` against the prd_terraform Doppler config. If `terraform plan` showed zero diff, no apply is needed.
- [ ] Verify the post-apply state matches the pre-apply state by re-running `curl -sI -X GET https://api.soleur.ai/` and confirming the response is unchanged (still no `x-robots-tag` header — that's the EXPECTED state until the rule fires from a proxied record).
- [ ] Verify `curl -sI -X GET https://deploy.soleur.ai/` still returns `x-robots-tag: noindex, nofollow` — the sibling rule on the same ruleset must not have regressed.

## Files to Edit

- `apps/web-platform/infra/seo-rulesets.tf` — extend the inline comment on the `api.soleur.ai` rule (current lines ~257-275 inside `cloudflare_ruleset.seo_response_headers`) to document the no-op condition. The header-block comment at the top of the response-headers ruleset (current lines ~230-248) may also gain a one-line pointer to the per-rule comment.

## Files to Create

- None (a new GitHub issue is created via `gh issue create`, not a repo file).

## Open Code-Review Overlap

`gh issue list --label code-review --state open` queried 2026-05-06
against the path `seo-rulesets.tf` and the substring `api.soleur.ai` —
zero matches. None.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — comment-only infrastructure
documentation change. The runtime behavior under all roles
(Prospect, Authenticated app user, Admin via Access, Billing customer,
Legal signer, OAuth installation owner) is unchanged. The change is
internal-engineering hygiene: a future operator running `curl` against
`api.soleur.ai` will see the inline comment explain why the rule does
not fire, instead of misdiagnosing it as a Terraform regression.

## Implementation Phases

### Phase 1 — Extend the inline comment in `seo-rulesets.tf`

1. Read the existing rule block in `apps/web-platform/infra/seo-rulesets.tf`
   (the `api.soleur.ai` rule currently at lines ~257-275 inside
   `cloudflare_ruleset.seo_response_headers`).

2. Add a comment block immediately above the `rules { ... }` declaration
   for the `api.soleur.ai` rule. The block must include, in order:

   - **Current state (no-op):** "This rule is currently a no-op as of
     2026-05-06. `api.soleur.ai` is a DNS-only CNAME →
     `ifsccnjhymdmidffkzhl.supabase.co` (Supabase Custom Domain).
     Cloudflare Transform Rules declared on the `soleur.ai` zone only
     fire on traffic that transits soleur.ai's CF edge (proxied /
     orange-cloud records). DNS-only CNAMEs bypass the edge entirely,
     so this Transform Rule never sees the request."

   - **Evidence:** "`curl -sI -X GET https://api.soleur.ai/` returns
     HTTP 404 with no `x-robots-tag` header (2026-05-06). Compare
     `deploy.soleur.ai`, also on this ruleset but proxied through
     soleur.ai's edge — its rule fires correctly
     (`x-robots-tag: noindex, nofollow` confirmed live)."

   - **Why retained:** "Kept intentionally. If `api.soleur.ai` is ever
     proxied through soleur.ai's edge (Option 1: orange-cloud record +
     Supabase Origin Certificate at the edge), this rule fires
     automatically without further code changes. Removing the rule
     would make that future flip more error-prone (silent re-exposure)."

   - **Re-evaluation tracker:** "Re-evaluate if (1) Supabase Custom
     Domains adds a response-header-injection feature (eliminates the
     need for an edge rule), or (2) operator chooses to proxy
     `api.soleur.ai` through soleur.ai's edge. Tracking issue: #<NEW>."

   - **Practical risk:** "Real indexing exposure is low because
     `api.soleur.ai` returns 401/404/403 on every authenticated path
     under Googlebot's anonymous identity — there is no body content to
     index. X-Robots-Tag was defense-in-depth against
     URL-existence-recording (`Crawled - not indexed` GSC bucket)."

3. Optionally add a one-line breadcrumb pointer at the top of the
   `cloudflare_ruleset.seo_response_headers` block (lines ~230-248)
   noting that one of the three rules is currently a no-op (see
   per-rule comment) — keeps a future skim of the header comment
   honest.

4. Verify the comment is syntactically valid HCL (`#` line comments,
   no `*/` token in body). Run `terraform fmt apps/web-platform/infra/`
   to confirm formatting.

5. Run `terraform plan` against prd_terraform Doppler config from
   `apps/web-platform/infra/`. Expected outcome: zero diff (Cloudflare
   API does not surface comment-only changes) OR comment-only drift
   on `cloudflare_ruleset.seo_response_headers`. If the plan shows
   ANY rule add/remove/reorder/expression-mutation, STOP and
   investigate — that's a regression, not the intended change.

### Phase 2 — Create the re-evaluation tracker issue

1. Run `gh issue create` with:

   - **Title:** `infra: Re-evaluate api.soleur.ai X-Robots-Tag no-op (proxy or remove)`
   - **Body:** describe the no-op condition, cite issue #3375 and
     `seo-rulesets.tf`, list the two re-evaluation criteria
     (Supabase header-injection feature OR operator proxies
     api.soleur.ai), and note that this issue is the canonical
     tracker referenced from the inline `seo-rulesets.tf` comment.
   - **Labels:** `infrastructure`, `seo`
   - **Milestone:** `Post-MVP / Later`

2. Capture the new issue number from `gh issue create` output.

3. Update the inline comment in `seo-rulesets.tf` to reference the
   captured issue number (`Tracking issue: #<NEW>` → `Tracking
   issue: #N`).

### Phase 3 — Verify and commit

1. Run `terraform fmt apps/web-platform/infra/` once more — comment
   addition must not break formatting.

2. Run `terraform validate` from `apps/web-platform/infra/` — confirm
   the file still parses.

3. Commit: `docs(infra): document api.soleur.ai X-Robots-Tag no-op
   (DNS-only CNAME bypasses CF edge) (#3375)`.

4. PR body uses `Closes #3375` — the deliverable IS the comment + the
   tracking issue; there is no post-merge operator action other than
   the optional `terraform apply` if comment-only drift surfaces.

## Test Strategy

This is a comment-only `.tf` change. No new unit tests, no integration
tests, no test framework dependencies.

**Verification is empirical and load-bearing:**

1. Pre-implementation: re-run `curl -sI -X GET https://api.soleur.ai/`
   and confirm absence of `x-robots-tag`. (Already done 2026-05-06 —
   reproduced.)

2. Post-implementation: re-run the same curl and confirm UNCHANGED
   state — no `x-robots-tag` header on api.soleur.ai. The expected
   state is still no-op until the rule fires from a future
   orange-cloud flip.

3. Sibling-rule non-regression: re-run `curl -sI -X GET
   https://deploy.soleur.ai/` and confirm `x-robots-tag: noindex,
   nofollow` is still present. The api.soleur.ai comment edit must
   not perturb the deploy.soleur.ai rule.

## Risks

- **Comment drift over time.** The comment names a specific date
  (2026-05-06) and a specific Supabase project ref
  (`ifsccnjhymdmidffkzhl`). If Supabase rotates the project ref or
  if the operator flips api.soleur.ai to orange-cloud, the comment
  becomes stale. **Mitigation:** the tracking issue (Phase 2) is the
  source-of-truth for re-evaluation; the comment is a snapshot. The
  comment explicitly says "as of 2026-05-06" so a future reader knows
  to re-verify.

- **Terraform `plan` may show no diff at all.** Cloudflare API may
  normalize comment-only changes to a no-op delta. **Mitigation:**
  Acceptance Criterion permits both zero-diff and comment-only drift.
  Either is acceptable. Operator only runs `apply` if drift surfaces.

- **Comment block in HCL.** HCL `#` line comments are safe; verify no
  `*/` artifacts (HCL also accepts `/* ... */` block comments and
  embedding `*/` inside line-comment text triggers no parse error,
  but is jarring to readers). **Mitigation:** keep the comment as
  `#` line-comments only.

- **Tracking issue title drift.** If the Phase 2 issue title differs
  from what the comment block names, future grep-based audits
  produce false negatives. **Mitigation:** the comment links to the
  issue by number, not by title. Title can drift; number is stable.

## Sharp Edges

- Comment-only changes to Terraform-managed Cloudflare resources
  produce non-deterministic plan output — sometimes Cloudflare API
  surfaces the comment delta, sometimes it normalizes it away.
  Document the expected outcomes (zero diff OR comment-only drift)
  in the AC so the operator doesn't misread either as a regression.

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan has a complete section with a
  named threshold (`aggregate pattern`) and concrete role
  enumeration — verified before requesting deepen-plan.

- The comment cites a date (`2026-05-06`) and a Supabase project ref
  (`ifsccnjhymdmidffkzhl`). Both can drift. The drift mitigation is
  the Phase 2 tracking issue, not the comment itself — the comment
  is intentionally a snapshot.

- Per AGENTS.md `hr-all-infrastructure-provisioning-servers`, all
  Cloudflare ruleset changes go through Terraform — never the
  Cloudflare API directly. This plan respects that: the change is to
  the `.tf` source of truth, with `terraform apply` as the (optional)
  post-merge step if Cloudflare surfaces the comment delta.

- This is NOT an ops-remediation-class plan (`type: docs`, not
  `ops-remediation`). The PR body uses `Closes #3375`, not
  `Ref #3375`, because the deliverable lands at merge time (the
  comment + tracking issue) — there is no post-merge remediation gate
  whose success determines whether #3375 is resolved.

## Alternative Approaches Considered

| Option                                                | Tradeoffs                                                                                              | Decision                          |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------- |
| Option 1: Proxy api.soleur.ai through soleur.ai's CF edge | Pros: rule fires; cleanest end state. Cons: requires Supabase Origin Certificate, second TLS terminator, latency cost, complex setup. Affects every authenticated app user's REST/Auth/Realtime traffic. | **Deferred** — tracked as Phase 2 issue's re-evaluation criterion (2). High blast radius for a defense-in-depth-only header.          |
| Option 2: Remove the rule from Terraform              | Pros: honest about the dormant state. Cons: a future operator flipping api.soleur.ai to orange-cloud has to re-add the rule from memory; silent re-exposure window during the flip.                       | **Rejected** — removes a safety net for a future config flip.                                                                          |
| **Option 3: Leave the rule + comment + tracker (chosen)** | Pros: cheapest; rule fires automatically if api.soleur.ai is ever proxied; explicit documentation prevents future operator from misdiagnosing the no-op as a Terraform regression. Cons: comment maintenance over time. | **Chosen** — matches the issue's recommendation; lowest implementation cost; preserves the safety-net property of Option 1's future state without paying Option 1's complexity now. |

## References

- Issue #3375 (this issue)
- PR #3296 (the SEO/GSC fixes that introduced the no-op rule)
- `apps/web-platform/infra/seo-rulesets.tf` lines ~230-275 (the
  ruleset and rule definition being commented)
- `knowledge-base/project/learnings/2026-05-05-gsc-indexing-triage-patterns.md`
- `knowledge-base/project/learnings/2026-05-06-user-impact-section-by-role-not-surface.md`
  (this learning is exactly why role-by-role enumeration appears in
  this plan's User-Brand Impact section)
- AGENTS.md `hr-all-infrastructure-provisioning-servers` (Terraform-only
  for Cloudflare changes)
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact`
  (User-Brand Impact section requirement)
