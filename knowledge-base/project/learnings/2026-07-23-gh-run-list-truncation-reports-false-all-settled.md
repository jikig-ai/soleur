---
module: workflow-tooling / post-merge-completion-monitoring
date: 2026-07-23
problem_type: logic_error
component: gh-cli-completion-monitor
symptoms:
  - "A post-merge monitor watching every workflow on a merge commit reported ALL SETTLED with 20 rows while 4 required workflows were still in_progress"
  - "The JSON was well-formed, the jq correct, the arithmetic correct — nothing errored"
  - "The not-completed count was genuinely 0 for the page the query read, not for the full run set"
root_cause: wrong_assumption
severity: medium
tags:
  - gh-cli
  - pagination
  - completion-detection
  - false-negative
  - monitoring
issue: 6796
synced_to: []
---

# gh run list truncates — a completion-monitor built on it reports a false ALL SETTLED

## Problem

A post-merge Monitor loop watching every workflow on a merge commit reported
`ALL SETTLED` with 20 rows. `Web Platform Release` (the production deploy), `CI`,
`CodeQL` and `Tenant integration` were all still `in_progress`.

```bash
s=$(gh run list --branch main --commit "$SHA" --json workflowName,status,conclusion)
n=$(jq -r '[.[] | select(.status != "completed")] | length' <<<"$s")
[ "$n" = "0" ] && echo "ALL SETTLED"
```

**`gh run list` defaults to ~20 results.** The merge commit had 38 runs. The
first 20 were the fast ones — all completed — so `n` was genuinely `0` *for the
page it read*.

Nothing errored. The JSON was well-formed, the `jq` correct, the arithmetic
correct. The query answered *"are the first 20 runs done?"* rather than *"are all
runs done?"*.

## The tell

Not in the logic — in the **output shape**: exactly 20 rows. A count landing
precisely on a CLI default is the signature. Reading the loop for a bug finds
nothing, because there isn't one; the defect is an unstated assumption about the
data source. Any time a completion count lands exactly on a known page size
(`gh` ~20/30, GitHub API 30/100, `kubectl`/`aws` paginators), treat it as
"truncated read" until a full read proves otherwise.

## Fix

```bash
s=$(gh run list --branch main --commit "$SHA" --limit 60 --json workflowName,status,conclusion)
tot=$(jq 'length' <<<"$s")
# Floor guard: never conclude from a read smaller than what we know exists.
if [ "$tot" -lt "$KNOWN_TOTAL" ]; then echo "WARN truncated read ($tot < $KNOWN_TOTAL)"; continue; fi
```

`--limit` alone only **moves the cliff** rather than removing it — a 39th run
re-hits the same class at `--limit 38`. The floor guard converts a short read
from "looks complete" into "refuse to answer". Establish `KNOWN_TOTAL` from one
full read first, and make it a **floor, never an equality** — scheduled
workflows fire on `main` independently and legitimately grow the count (observed
38 → 47 mid-watch), so an equality check would then wedge forever on a healthy
merge.

## Key insight

A completion detector must distinguish **"nothing left"** from **"nothing
visible"**. Any paginated / filtered / capped source returns an empty remainder
for two different reasons, and the happy path is byte-identical between them.
Ask of any "is it done yet?" check: *what does this return when the source
under-reports?* If the answer is "the same thing it returns when the work is
actually done," the check is unsound regardless of how correct its parsing is.

## Cross-references

- **The robust pattern already in the repo is "poll by identity, not by counting
  a capped source."** `ship`/`postmerge` completion **poll loops** watch a
  specific run by ID or match on `headSha`, which is why they are immune — NOT
  because they carry a `--limit` + floor guard (they do not). When you need
  "is X done?", prefer polling X's own identity over counting a list that a page
  size can silently truncate.
- `plugins/soleur/skills/ship/SKILL.md` **Phase 6.5** ("'No failures' and 'the
  checks ran' are different claims") — the sibling articulation of the same
  class on the check-presence axis: a clean read is not the same as a complete
  read.
- [`2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md`](./2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md)
  — sibling "a clean read and a safe conclusion are different claims."
- **Latent same-class instance (worth an operator follow-up; out of scope to fix
  here):** `ship` Phase 7 Step 2's completion **count** —
  `gh run list --commit <sha> ... | length` with no `--limit` and an
  empty-result fallback that only guards the not-yet-registered case — shares
  this exact shape and could report a false "release verified" on a merge commit
  with more runs than the default page.

## Sharp edge — the class does not respect the review boundary

This defect was reproduced in a throwaway monitoring loop by the very agent that
had, minutes earlier, spent an entire multi-agent review hunting the same class
of defect (existence-vs-effect / clean-read-vs-complete-read gates) in the PR
under review. Monitoring and orchestration code gets none of the scrutiny that
reviewed product code gets — no test, no second reviewer, no mutation pass — so
a class you are expert at catching in reviewed code walks straight into the
harness you wrote to watch the review's own merge. Hold ad-hoc "is it done yet?"
loops to the same "what does this return when the source under-reports?" bar as
the code they watch.
