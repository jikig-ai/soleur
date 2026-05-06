# Learning: User-Brand Impact sections should enumerate by user role, not by surface

## Problem

PR #3296 (`feat-seo-gsc-indexing-fixes`) declared `Brand-survival threshold:
single-user incident`. The plan's `## User-Brand Impact` section enumerated
the deploy.soleur.ai subdomain as the user-brand-critical vector
(Cloudflare Zero Trust Access challenge surface enumerated by Googlebot).
Multi-agent review's `user-impact-reviewer` issued a DISSENT.

The DISSENT cause was not format (the section had concrete artifact + vector
pairs). It was scope. The plan enumerated by SURFACE — one subdomain at a
time — and named only `deploy.soleur.ai` (admin-only, behind CF Access).
The PR's same Transform Rules ruleset also touched `api.soleur.ai`, which
is the Supabase REST root carrying every authenticated app user's login,
conversations, messages, and BYOK token operations. Higher blast radius;
omitted from the section.

The author's mental model was "what's user-brand-critical here?" and only
saw `deploy.soleur.ai` because that's where the new defense-in-depth was
loudest in the brainstorm. The reviewer's mental model was "which user
populations does this diff touch?" — prospect via Google, authenticated app
user via Supabase, legal-document signer via redirect — and immediately
spotted that the second role had no entry.

## Solution

Two layers:

### Plan-time

When writing a `## User-Brand Impact` section, before listing artifacts
and vectors, enumerate USER ROLES the diff touches. Concrete roles for
this codebase:

- Prospect (anonymous, via Google or social link)
- Authenticated app user (Supabase REST/Auth, conversations, messages, BYOK)
- Legal-document signer (consent flows, ToS/PP click-through)
- Admin via Access (deploy.soleur.ai, internal tooling)
- Billing-charged customer (Stripe)
- OAuth installation owner (GitHub App, etc.)

For each role the diff touches, ask: what does this person experience if
this lands broken? If it leaks? Then write artifact + vector pairs grouped
by role, not by subdomain or table.

### Review-time

The `user-impact-reviewer` agent now prescribes role-by-role enumeration
as the first step of failure-mode discovery, called out explicitly as
catching subdomain-by-subdomain blind spots.

## Key Insight

**Surface-by-surface enumeration is the form security threats prefer.**
Threats find the user role you didn't enumerate. If the plan says "this
PR touches deploy.soleur.ai" but the diff also touches api.soleur.ai, the
threat-model gap is invisible to anyone who doesn't independently ask
"who hits each subdomain?". Role-by-role enumeration forces that question
upfront — and the question is cheaper to answer at plan-time than to
discover at review-time DISSENT.

This generalizes beyond subdomain-vs-role. Any time a plan enumerates by
"the things the PR touches", a reviewer enumerating by "the things that
touch the PR" (users, callers, neighbors, downstream consumers) will find
gaps. The plan side is the canvas; the reviewer side is the perspective.
Plans that ALSO enumerate by perspective close the gap before review.

## Session Errors

1. **Pattern-recognition agent reported false-positive P3-1** (16 hardcoded apex URLs in legal markdown) — Recovery: ran the actual CI gate's regex against the worktree `_site/`, returned 0 matches. — Prevention: when a review agent claims "CI will fail" or "regression in N files", run the literal CI gate command against the worktree before treating as P0. Agents may grep against pre-fix state or use a less-anchored regex than the CI gate.

2. **`set -euo pipefail` short-circuited the empty-sitemap guard** in `validate-seo.sh` — Recovery: added `|| true` to the `grep ... | sed ... | sort -u` pipeline so the variable assignment succeeds on empty input. — Prevention: when adding defensive bash guards (`if [[ -z "$VAR" ]]`) in scripts that use `set -euo pipefail`, verify the value-assignment pipeline can return success on the empty-input case. Otherwise the guard never fires — pipefail exits the script before reaching the conditional.

3. **User-impact-reviewer DISSENT on api.soleur.ai coverage** — the load-bearing finding above. Recovery: rewrote the User-Brand Impact section role-by-role; routed pattern to user-impact-reviewer agent definition. — Prevention: see Solution above (role-by-role enumeration at plan time).

4. **PreToolUse `security_reminder_hook` fired on workflow edit** — first Edit call to `.github/workflows/deploy-docs.yml` printed the reminder but the edit didn't land (returned the hook output as an error). Recovery: retry. — Prevention: not warranted; the hook's behavior is intermittent and the reminder content is informational, not a real block.

## Related Learnings

- [`2026-05-05-gsc-indexing-triage-patterns.md`](2026-05-05-gsc-indexing-triage-patterns.md) — sibling learning from the same PR (the SEO-specific patterns).
- [`2026-05-05-brainstorm-capability-gaps-need-repo-grep.md`](2026-05-05-brainstorm-capability-gaps-need-repo-grep.md) — sibling learning on plan-time evidence requirements.
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — the source rule this finding strengthens.

## Tags

category: best-practices
module: user-impact-reviewer, plan, review
