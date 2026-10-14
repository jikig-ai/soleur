---
title: The deploy arm that said success had deployed someone else's commit
date: 2026-09-20
category: workflow-issues
module: ship, postmerge
issues: [8391, 8308, 8276]
---

# Learning: the deploy arm that said success had deployed someone else's commit

## Problem

Shipping #8308 (PR #8391) cost five CI cycles, four landing conflicts, and two
CI-only test failures — and then, at the very last gate, nearly recorded a false
production verification.

`ship/SKILL.md`'s merge→deploy protocol says to select the deploy arm by
`event=workflow_run` on the full 40-char merge SHA, wait for its `deploy` job, and
require `/health` `build_sha == merge sha`. Followed literally, every one of those
steps returned a green answer about a run that was **not this merge's**.

| fact | value |
|---|---|
| merge SHA | `91c8bdccf6f90eea38ceb55c76382867023ce287` |
| arm the documented query returned | `35493486054` — `head_sha=91c8bdccf`, `deploy` **success**, `live-verify` **success** |
| SHA that arm's `resolve-target` checked out | `4d46b72c8bf69d47111e7899815ced424577b398` |
| CI completion for `4d46b72c8` | `06:09:16Z` |
| that arm's start | `06:09:22Z` |
| the merge's own CI at that moment | `in_progress` |
| the merge's real arm | `35494298736`, created `06:28:00Z` — 19 minutes later |

## Root cause

**A `workflow_run` run's `head_sha` is the default-branch tip at trigger time, not
the commit it deploys.** The deploy arm is triggered by CI *completion*, so it
always lags its own merge by a full CI run. During that lag `main` has already
advanced — to your merge. GitHub therefore stamps the PREVIOUS merge's arm with
YOUR SHA, both arms match `event=workflow_run AND head_sha=<your sha>`, and the API
returns the older one first.

The skill already *warned* about the lag — "the deploy arm lags its merge by the
whole CI run, so the newest deploy-arm run is usually the previous PR's". Its
prescribed filter could not implement that warning, because the lagging arm carries
the new SHA. The remedy for #8276 reproduced #8276.

## Solution

Identify the arm by **what it deploys**, never by what it is labelled.
`resolve-target` checks out the commit it is about to deploy and logs the SHA:

```bash
RT=$(gh api --paginate "repos/{owner}/{repo}/actions/runs/${RUN}/jobs" \
  --jq '.jobs[]|select(.name=="resolve-target")|.id' | head -1)
gh api --allow-escape-sequences "repos/{owner}/{repo}/actions/jobs/${RT}/logs" \
  | grep -oE 'depth=1 origin [0-9a-f]{40}' | head -1
```

If that SHA is not your merge, it is another merge's arm: discard it and wait,
because yours cannot exist until your own CI run completes.

`--allow-escape-sequences` is load-bearing — without it `gh api` refuses the body,
exits 1, and writes **zero bytes**, which reads exactly like "the job produced no
log".

Landed in `postmerge/SKILL.md` Phase 3.7 (the predicate's canonical home) rather
than `ship/SKILL.md`, which points at it: ship's body sits 42 bytes under its
`lint-skill-body-budget` ceiling, so it has no room for an addition and the honest
fix location was the one with headroom.

## Key insight

**Every instrument at this gate answered a question adjacent to the one I asked.**
Three of them, in the same run:

- The **run label** answered "what was `main` when this fired", not "what does this
  deploy".
- **`live-verify: success`** answered "did the job finish", not "did live
  verification run" — every substantive step, the harness included, was `skipped`
  by a changed-file gate; only `Emit result to Sentry` and `Enforce live-verify
  gate` executed. A job's conclusion is a verdict about the job, never about the
  check it is named after.
- **`/health`** on the apex answered with an empty body at rc 0 under
  `curl -sf … || echo ""`. My own monitor printed `SERVED_SHA_MISMATCH served=` —
  labelling could-not-measure as measured-bad, inside the watch built to prevent
  exactly that. The canonical host is `app.soleur.ai`
  (`web-platform-release.yml:1288,1483`).

Any one of the three, read at face value, reports "PR deployed and verified" while
production runs the previous build. All three agreed, and all three were wrong
about the same thing.

## Session Errors

**Deploy-arm mis-selection (near-miss false production verification)** — the
documented selector returned the previous merge's arm, fully green, stamped with my
SHA. Recovery: read `resolve-target`'s checkout from the job log; the real arm
appeared 19 min later and `/health` then matched the merge exactly.
**Prevention:** the `postmerge` Phase 3.7 edit in this PR — identify by deploy
target, never by `head_sha`.

**`live-verify: success` credited as live verification** — the job was green with
its harness step skipped. Recovery: read the step list. **Prevention:** recorded in
the same Phase 3.7 edit.

**`/health` probed on the apex, and an empty body labelled a mismatch** — two
errors in one: wrong host, and could-not-measure reported as measured-bad.
Recovery: used `app.soleur.ai` and added a retry loop that reports `UNRESOLVED`.
**Prevention:** same edit names the host and the semantics.

**A backticked close-keyword line for #8308 closed nothing** — `closingIssuesReferences` read
`[]` for the PR's entire life; GitHub's parser ignores a keyword in a code span,
while `auto-close-scan.sh` greps text and calls it a match. Recovery: removed the
backticks; the field populated and the merge then resolved issue #8308 as intended. **Prevention:** assert
the FIELD in the positive direction too, not just the negative one ship already
documents.

**The branch had no CI run at all until its conflicts cleared** — `CONFLICTING`
from first push means GitHub cannot compute `refs/pull/N/merge` and dispatches
nothing, so `gh pr checks` read zero failures over zero checks for hours. In
parallel the local `TEST_GROUP=all` battery was refused four times (rc=4, sibling
worktrees) and never once acquired the lock in ~60 min of queueing. Two real
defects sat behind that pair of non-signals and both surfaced on the first
dispatched run. **Prevention:** assert required contexts by NAME, present and
green — never `pending == 0`.

**A monitor whose break condition was unsatisfiable** — `CodeQL` is a required
context that sits in `skipping` and never reaches `pass`, so "all required ==
pass" could never fire and its 30-minute silence was indistinguishable from "still
running". Recovery: treat `pass` OR `skipping` as terminal and print
`mergeStateStatus` alongside. **Prevention:** when writing a watch, ask what value
each element can actually reach.

**R3d's `git commit` ran in the parent shell with no git identity** — `fresh_ws`
calls `git_fixture_env` inside a command substitution, so its exported identity
dies with the subshell. Fatal on every CI runner (`fatal: empty ident name`),
invisible on a developer box with a global `user.email`. Recovery: both
parent-shell write sites now run in a subshell that calls the helper first;
verified in both directions against a reproduced identity-less environment
(pre-fix rc=128, post-fix 157/0). **Prevention:** a fixture helper that works by
exporting cannot be called through `$(...)`.

**An apostrophe inside `"${v:?word}"` desynchronises bash 5.3's parser** — the
parse died ~80 lines later on an unrelated `(`, naming a line that had not changed.
**Prevention:** recorded at the call site in `go-session-gates.test.sh`.

**Four landing conflicts from generated artifacts in the diff** —
`rule-metrics.json` (one producer per PR; took `main`'s copy so the branch stops
diffing it), `INDEX.md` twice (the `kb-index` driver GitHub cannot run; cured by
sync + push), and `model.likec4.json` (a real conflict, resolved by re-running the
generator against the merged `model.c4` rather than taking a side — it is
byte-gated on `main`). **Prevention:** the front-loaded post-sync freshness sweep
that ran the four repo-global ratchets before pushing, instead of letting CI report
them 35 minutes later.

**Local `main` lagged `origin/main`** (`a6044bf11` vs `91c8bdccf`) — reading
postmerge Phase 4 via `git show main:` would have reported five present files as
MISSING. **Prevention:** already documented; addressing by merge SHA is what
avoided it.

## Related

- #8276 — the original served-SHA gate this defect was reached through
- `ship/SKILL.md` merge→deploy protocol; `postmerge/SKILL.md` Phase 3.7
- `knowledge-base/project/learnings/2026-09-20-every-instrument-that-answered-instead-of-failing.md` — the pre-merge half of the same session
