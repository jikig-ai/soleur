# Learning: a subagent's scoped absence is not an ecosystem absence — and an archived spec is not "never shipped"

## Problem

During the `/soleur:go 9168` brainstorm, the operator corrected two claims I
had asserted, both within minutes of each other and both avoidable at near-zero
cost:

1. **"There is no Supabase Terraform provider."** A research subagent had
   reported — correctly — that *"no `supabase/supabase` Terraform provider is
   declared in `apps/web-platform/infra/`"*. I restated that scoped finding to
   the operator as if no provider existed at all. In fact
   `supabase/supabase` (registry, v1.9+) manages
   `supabase_project.instance_size`, which dissolved my stated "dashboard-only
   compute change violates the IaC rule" blocker and changed the option set the
   operator was choosing between. **The scope qualifier was the load-bearing
   part** and I dropped it in transit.
2. **"The status page was decided but never shipped."** The archived spec
   (`specs/archive/20260407-…-feat-statuspage/spec.md`) carries `Issue: TBD`
   and the CPO agent inferred unshipped. One `webfetch` of
   `soleur-ai.betteruptime.com` showed it live — it had even recorded that
   day's 39-minute outage. The 2026-04-07 decision was "activate via
   dashboard", so shipping never produced a repo artifact; a committed spec is
   not the delivery surface for a dashboard-side activation.

## Solution

Two probes, both seconds:

- **Scope-check inherited claims before restating them.** When a subagent or
  doc says "no X", repeat it back with its qualifier attached ("no X *in this
  root*") and — if the claim is about a vendor ecosystem, not the repo — spend
  one `web_search`/registry fetch before presenting it to the operator as a
  constraint on their choices. `hr-verify-repo-capability-claim-before-assert`
  covers the repo half; the vendor half is the same posture applied outward.
- **For "was it ever shipped" questions about dashboard-side activations, fetch
  the live surface, not the spec's metadata.** `Issue: TBD` and `status:
  archived` describe the *record*, not the *world*. The status page's existence
  was directly fetchable; the archive state told me only that no tracking
  issue was ever created.

## Key Insight

Both errors share one shape: **a record's state was mistaken for the world's
state** (a scoped repo finding → an ecosystem claim; an unlinked spec → an
unshipped feature). The fix is also one shape: before letting a negative claim
bound an operator's options, run the falsification probe — registry fetch for a
vendor capability, URL fetch for a shipped surface.

## Tags

brainstorm, subagent-prompts, premise-validation, vendor-claims, #9168

## Session Errors

1. Restated a scoped repo finding ("no supabase provider *in the infra root*")
   as an ecosystem claim ("there is no supabase terraform provider") in an
   `AskUserQuestion` option. **Prevention:** carry scope qualifiers verbatim
   through restatement; web-verify vendor-capability negatives before
   presenting them as constraints.
2. Asserted a decided feature was unshipped from spec metadata alone.
   **Prevention:** for externally-shipped deliverables (dashboard activations,
   vendor-side config), fetch the live artifact before declaring it absent.
3. `gh issue create --body-file <relative-path>` rejected by the filing gate —
   needed the absolute path. Already recorded:
   `learnings/workflow-patterns/2026-09-25-issue-filing-gate-body-file-needs-absolute-path-in-worktree.md`.
4. Filed follow-up issue #9186 ("link the status page from a user-facing
   surface") on the premise that nothing user-facing links to it. The operator
   corrected: `apps/web-platform/app/(dashboard)/dashboard-shell.tsx` has
   carried a "Status" nav link to `soleur-ai.betteruptime.com` the whole time —
   one `git grep -n betteruptime.com -- apps/` would have falsified the
   premise before the issue was written. Issue closed not-planned.
   **Prevention:** before filing a "gap" issue asserting an absence, grep the
   literal subject (the URL, the route, the feature name) across the consumer
   surfaces — `apps/`, not just the spec corpus. A spec corpus proves a
   record's absence; the tree proves the feature's.
