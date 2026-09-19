---
module: workflow
date: 2026-09-15
problem_type: logic_error
component: verification
symptoms:
  - "An absence query reported 18 then 19 then 15 — the first two counts were instrument failures, not answers"
  - "A grep reported a merged line as missing because its pattern could not span a backtick plus an apostrophe"
  - "A merge silently never ran because its log redirect failed, while the push in the same block succeeded"
  - "A credential fingerprint measured correctly was reported as current state after the operator had rotated it"
  - "A cause was asserted from a commit shape that is identical whether a human or a bot produces it"
root_cause: missing_workflow_step
resolution_type: documentation_update
severity: high
tags: [verification, instruments, positive-control, absence-query, stale-measurement, review, merge-driver, rls]
issues: [7966, 7969, 8186, 8190]
pr: null
synced_to: [review]
---

# Every instrument I checked my own work with returned an answer, and three of them were wrong

## Problem

Four PRs shipped in one session. In every case the defect was in the **verification**, never in
the fix — and each wrong reading was indistinguishable from a right one without a control.

The sharpest instance ran three rounds. Checking a counterparty-facing legal claim about Postgres
RLS required counting tables that are RLS-enabled with **no** `CREATE POLICY`:

| round | instrument | answer | why it was wrong |
|---|---|---|---|
| 1 | `grep -rl 'CREATE POLICY' \| xargs grep -h "ON public.<t>"` | 18 tables | missed multi-line statements; a positive control on `api_keys` returned 0 |
| 2 | `CREATE POLICY\s+"?[A-Za-z0-9_]+"?\s+ON` | 19 tables | a bare-identifier class cannot match a **quoted policy name containing spaces** — `CREATE POLICY "Prevent client health_snapshot update" ON public.users` |
| 3 | `CREATE POLICY\s+(?:"[^"]+"\|[A-Za-z0-9_]+)\s+ON` | **53 RLS-enabled, 15 zero-policy** | controls pass: `conversations`=13, `api_keys`=1, `users`=5, `scope_grants`=3, `action_sends`=2 |

`api_keys`, `users`, `message_attachments` and `team_names` all fell off the list between rounds 2
and 3. Rounds 1 and 2 would have handed a CLO — and through it a signed legal instrument — an
enumeration naming two tables that are correctly policied.

## Key Insight

**For any query of the form "count the things that LACK X", the failure mode is failing to FIND X,
and that is byte-identical to absence.** A broken detector and a clean system produce the same
output. So every absence query needs a **positive control**: name an item that MUST be found, and
require the instrument to find it before you read the count.

This generalises past greps. The same shape appeared four more ways in one session:

- **A pattern that cannot span its own target.** Verifying a merged line, `move .INDEX.md.s header`
  was run against text reading ``move `INDEX.md`'s header``. One `.` cannot match backtick +
  apostrophe, so the check returned 0 and a correctly-merged line was reported as missing. Pair
  every "is the new thing present" with "is the old thing gone" — the second check caught it.
- **A failed redirect that ate the command.** `git merge origin/main > "$SP/m.log" 2>&1` where `$SP`
  had been swept: the redirect fails, the merge never runs, `MERGE_RC=1` — but the `git push` later
  in the same block succeeded (pushing an earlier commit), so the output read like a completed
  rebase. `mkdir -p` the scratch dir in the block that writes to it, and verify the **state** you
  claim (`git log HEAD..origin/main`), not the exit code of the command you believe produced it.
- **`git show --stat` truncates.** It reported 6 added template files where `--name-only
  --diff-filter=A` reports 12 — inside a document whose argument is that claims must be measured.
- **A measurement carries a timestamp; a claim does not.** A Doppler password fingerprint was
  measured correctly, then presented as current state after the operator had rotated it ~5 minutes
  earlier. Re-measure immediately before asserting, especially when the operator can change it.

## The second theme: asserting a cause you cannot distinguish

A skill file gained the sentence "an armed auto-merge performs these server-side updates itself."
A review agent falsified it three ways: no `update-branch`-class event exists in the PR timeline at
all; the commit is `author: <PR author> / committer: GitHub` whether a human clicks the button or
GitHub acts; and the **timing refutes it** — main moved at 23:19:42Z and the branch sat un-updated
for 9h06m with auto-merge armed, while a local merge by the operator sits interleaved among the
GitHub-committed ones.

The fix was to keep the operational fact (every server-side route runs the same driverless merge)
and state plainly that the producer is **not recoverable** after the fact. Before writing a cause,
ask what observation would distinguish it from its alternatives. If none exists, describe the
effect and say the cause is unrecoverable.

A sibling instance: the silent-failure case for a generated-artifact merge was written backwards
("only ONE side added files" — one-sided is in fact the safe case), then **over**-corrected to
"both sides ADDED the same number of files". The generator derives its count from `wc -l` of a row
TSV, so the real predicate is the header **value** moving; two sides deleting the same number
collide identically. Only the third framing survived review. A correction is a new claim, not an
inheritor of the original finding's credibility.

## What worked

- **Flagging your own unverified claims to a review panel.** A four-agent panel on a **nine-line**
  docs change returned 8 findings, every one in the prose the PR added and none in the surrounding
  file. The single P1 landed on the exact claim the review brief had marked "inherited from an
  earlier session, NOT re-measured". Naming your weakest claim to reviewers demonstrably directs
  them at it.
- **Convergence from different methods.** Two agents with different prompts independently reduced
  five surface findings to one framing error. The mechanism was then reproduced a third way
  (`git merge-file`, no repo and no commits) rather than trusting either agent's reproduction.
- **Cheap deterministic gates before the expensive panel.** A CI gate (`Block PR body citing files
  not in diff`) caught a real defect the panel did not look for; running the gate's own script
  locally named the exact offender in one command.

## Session Errors

1. **Reported a credential fingerprint as current after the operator rotated it.** Recovery: re-read
   the issue and retracted. **Prevention:** re-measure operator-mutable state immediately before
   asserting it; a measurement is timestamped, a claim is not.
2. **Used `gh pr update-branch` on a PR where both sides had moved the knowledge-base count.** The
   server-side merge cannot run the `kb-index` driver; it took a green branch red, then `DIRTY`.
   **Prevention:** already fixed in `merge-pr/SKILL.md` and `drain-prs/SKILL.md` via #8190 — cite it,
   do not re-document.
3. **Asserted an indistinguishable cause** (auto-merge as the server-side updater). **Prevention:**
   name the observation that would separate the cause from its alternatives before writing it.
4. **Wrote the silent-failure predicate backwards, then over-corrected.** **Prevention:** treat your
   own correction as a fresh claim requiring its own measurement.
5. **`git show --stat` undercounted 12 files as 6.** **Prevention:** use `--name-only
   --diff-filter=A` for any count of added files.
6. **Two consecutive broken instruments on an absence query.** **Prevention:** positive control on
   every absence query — see Key Insight.
7. **A grep that could not span backtick+apostrophe reported a merged line as missing.**
   **Prevention:** pair presence checks with an old-value-gone check.
8. **A swept scratchpad made a merge silently not run while the push succeeded.** **Prevention:**
   `mkdir -p` in the same block; assert the resulting state, not the exit code.
9. **PR body cited a file not in the diff**, tripping a CI gate. **Prevention:** the gate already
   enforces this; run its script locally rather than inferring from the job name. Do not reach for
   the opt-out label — the gate's complaint was correct.
10. **Armed a duplicate monitor**; the supersede hook flagged a watch that `TaskStop` then reported
    as already gone. **Prevention:** stop the flagged task anyway — a redundant `TaskStop` costs
    nothing, two monitors on one PR produce duplicate reports.
11. **Offered a legal-posture decision to the operator as their call.** `review/SKILL.md` Step 1
    disposition 4 routes Art. 28(3)(c) notice-adequacy to the `clo` agent for a binding ruling with
    drafted wording, and states that weight is not a routing signal. This was the **second**
    instance in one session. **Prevention:** when a finding feels consequential, that is the reason
    to route it to the domain owner, not past them.
12. **Passed a stale rule-budget figure into compound** (37574 against an actual 42640).
    **Prevention:** the skill already mandates running the linter rather than quoting a remembered
    number — that mandate is what caught it.

## Verification ledger

- Merged and verified from **merged main** with positive controls: #8186 (`cdee39de1`), #8190
  (`35b9f088c`). Old wrong predicate occurs 0 times; `INDEX.md` header 6559 == 6559 rows.
- `kb-index-merge-driver.test.sh` 78 passed / 0 failed, AC17 green, on two different trees.
- `plugin-component-test` 2738 pass / 0 fail across three runs; `markdown-lint`, `gitleaks-staged`,
  `migrated-rule-id-lint`, `skill-security-scan-advisory` green.
- Merge mechanism reproduced independently via `git merge-file`: same count + far-apart rows =
  CLEAN and wrong; same count + adjacent rows = CONFLICT; differing counts = CONFLICT.
- Zero-policy enumeration: 53 RLS-enabled / 15 zero-policy, instrument validated against 5 positive
  controls.

## Tags

category: workflow
module: verification
