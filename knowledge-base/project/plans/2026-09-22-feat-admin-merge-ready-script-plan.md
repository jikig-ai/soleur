---
title: "feat: admin-merge-ready.sh — prove every required check is present and green before any --admin merge"
date: 2026-09-22
slug: feat-admin-merge-ready-script
branch: feat-one-shot-8500-admin-merge-ready-script
issue: 8500
closes: 8500
type: feat
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# feat: admin-merge-ready.sh — prove every required check is present and green before any `--admin` merge

## Overview

Issue #8500: two PRs (#8458, #8439) were admin-merged while required checks were absent, pending or red. The rule "every required context must be **present and green** on the current SHA" already exists, but only as prose plus an inline bash block in `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` step 2. Agents write their own watch loops, and the obvious one (`gh pr checks --required`, wait until nothing is pending) passes vacuously for a required check that has not been created yet. That happened on #8458: the aggregate `test` job only exists after every `test-scripts` shard finishes, so the loop saw 25 of 26 contexts green and never saw `test`.

This plan adds one shared, tested script, `plugins/soleur/scripts/admin-merge-ready.sh <PR> <head-sha>`, as the only permitted answer to "may this PR be admin-merged?". It then:

1. replaces the inline block in `settle-then-admin-merge.md` with a call to the script;
2. wires `ship`, `merge-pr`, `one-shot` and `drain-prs` so any `gh pr merge --admin` is preceded by the script (exit 0 required) and carries `--match-head-commit <head-sha>`;
3. corrects `schedule/SKILL.md:212`, which presents `gh pr checks --required` as a sufficient CI gate;
4. adds a suite with the #8458 mutation row (N required, N−1 present, all present green → must exit non-zero and name the absent context), plus a wiring lint.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality (probed 2026-09-22) | Plan response |
|---|---|---|
| "`CI Required` ruleset lists 26 contexts" | `gh api repos/{o}/{r}/rules/branches/main` returns **two** `required_status_checks` rules: ruleset 14145388 (`CI Required`, 24 contexts) and 13304872 (`CLA Required`: `cla-check`, `cla-evidence`). 26 is the union. | The script takes the **union of every** `required_status_checks` rule, never "the first". Mutation row R7 tests a context that exists only in the second rule. |
| Required contexts are identified by name | Each entry carries `integration_id`; `CodeQL` is pinned to 57789 (GHAS), the rest to 15368 (github-actions). | Match check runs by name **and** `app.id == integration_id` when the rule pins one. Row R8: a `CodeQL` run from app 15368 reads ABSENT. |
| Inline block picks "newest run" by `started_at` sort | A queued re-run has `started_at: null`, so a string sort puts it FIRST (oldest). An older `success` then masks a pending re-run. On #8458's head, `detect-changes` has 4 rows and `Analyze (python)` has 2, so duplicates are normal. | Pick the latest run per (name, app) by check-run **`id`** (monotonic), not by timestamp; this matches GitHub's own latest-run rule. Row R4 is the null-`started_at` re-run. |
| Check-runs endpoint returns all runs | The `filter` query parameter defaults to `latest`. | Request `filter=all` and choose by max `id` ourselves, so correctness does not depend on the server-side default. |
| Ruleset API is the only source of required checks | `gh api repos/{o}/{r}/branches/main/protection` → 404 "Branch not protected"; `branches/main` shows `required_status_checks.contexts: []`. No classic protection. | Read rulesets only. Record in the script header that classic protection is not consulted because this repo has none (a documented limit, not a silent gap). |
| Inline block ignores legacy commit statuses ("reads ABSENT, fails closed") | `repos/{o}/{r}/commits/<sha>/statuses` is empty on #8458's head; every one of the 26 required entries carries an `integration_id`. | The script does not read statuses at all. A required entry with a null `integration_id` is refused with exit 3 (`unpinned required context … unsupported`), so the gap fails closed, loudly, instead of being a dormant code path (plan-review: DHH P0-1). |
| One-shot and drain-prs call `gh pr merge --admin` | Neither does in prose today: one-shot:352 forbids a self-issued `gh pr merge`, and drain-prs:82 uses `--squash` (no `--admin`). The #8458 merge was an agent acting on operator authorization **outside** the skill text. | Wiring = an explicit rule in each skill: an operator-authorized `--admin` merge goes through the script and `--match-head-commit`. The wiring lint (Guard 2) makes this checkable. |
| `gh pr checks --required` respects required checks | It lists only checks that **exist**; an uncreated required context is invisible (issue #8500 §Why). | `schedule/SKILL.md:212` is rewritten to say so and to name the script. |
| `monitor-pr-checks.sh` is the canonical poll loop | Line 237 exits 0 with `CHECKS SETTLED, ALL GREEN, AUTO-MERGE NOT ARMED — … needs an explicit merge`, computed from `gh pr checks --json name,bucket`: the same existing-checks-only view. An agent can read that line as "safe to admin-merge". | Append to that message a pointer that an `--admin` merge still requires `admin-merge-ready.sh` exit 0. The exit code and the line prefix stay unchanged (the suite matches the prefix). |

## Research Insights

**Premise Validation.** #8500 is OPEN, not closed by any PR. PR #8537 is OPEN and edits `settle-then-admin-merge.md` line 26 (the "It fails closed" sentence), `ship/SKILL.md` (~2152, ~2450) and `merge-pr/SKILL.md` (~269). None of those hunks overlap the lines this plan changes (step 2 of the reference, ship:2414, merge-pr ~519, schedule:212). If #8537 merges first, rebase: its only edit to the reference is one sentence in the paragraph after the classifier, which this plan leaves alone. Paths cited in the issue exist on `origin/main`: `settle-then-admin-merge.md`, `schedule/SKILL.md:212` (the verbatim sentence "use `gh pr checks --required` for CI gating … GitHub CLI already respects the repo's required checks configuration"). The #8458 head `285cc098…` check-run timeline was fetched and matches the issue: `test` has one row, `completed/failure` at 11:16:40Z (created after the 10:56:53Z merge), and `test-scripts (3/3)` is `failure`.

**Property List (Phase 0.6b).**

- P1: A `--admin` merge happens only when every context required by the base branch's active rulesets is **present** on the exact head SHA being merged.
- P2: …and the **latest** run of each such context concluded `success`, `skipped` or `neutral`.
- P3: When P1 or P2 fails, the caller learns **which** contexts are ABSENT, PENDING or FAILED, by name.
- P4: The head merged is the head checked (no push can slip in between).
- P5: An agent reading a skill's merge instructions cannot find a path to `--admin` that skips P1–P4.
- P6: No skill documents `gh pr checks --required` as a sufficient CI gate.

**Cut List.**

- Inline bash in the reference → replaced by the script (P1–P3); keeping both would be two sources of truth.
- `scripts/required-checks.txt` as the required set → cut. It is a bot-synthetic list that deliberately omits `CodeQL` (see its header); the ruleset API is the authority. Grepped: `scripts/required-checks.txt` header, lines 1–45.
- PreToolUse hook for human/agent `gh pr merge --admin` → **deferred** (out of scope per the brief unless trivial). It is not trivial here: it must parse the PR number and `--match-head-commit` out of arbitrary Bash, call the network from a hook, and follow the repo's hook conventions (co-located `.test.sh`, `.claude/hooks/README.md` table, `.claude/settings.json` registration). File a follow-up issue in the work phase (task 5.2).
- New ADR → cut (see `## Architecture Decision`).

**Scoped advisor consult (Phase 4.5), applied.** (1) The wait moved inside the script (`--wait`; plan-review later folded the draft's exits 4/5 into 1 with distinct verdicts), because a caller-written loop is the #8458 root cause, and the reference's old retry one-liner retried stale/error exits and returned 0 after 20 failed attempts. (2) Real-shape fixtures captured read-only from a merged PR (now the base every Guard 1 row derives from, H1), because stub JSON only encodes the plan's guesses about API shapes. (3) Worst-of across check suites: adopted in the draft, then **cut** at plan-review (stricter than GitHub; no required name spans two suites). Not adopted: a test-only flag that skips the PR-state check. A bypass flag on a safety gate is a worse trade than R21 plus the live smoke against an OPEN PR.

**Plan review (DHH, Kieran, code-simplicity, CTO devex), applied.** Mechanical findings were auto-applied:

- Commit-statuses path cut; an unpinned context is refused with exit 3.
- Check-suite worst-of cut.
- Exits 4/5 folded into 1 with distinct verdicts.
- `--interval`, `--heartbeat-every` and `--repo` cut; the three-consecutive-errors rule cut.
- Guard 2's 15-line window replaced by a same-fence check. The two pre-existing `behind_exhausted` echo lines, which would have redded Guard 2, were added to Files to Edit (Kieran P0).
- The merge loop retries only the base-modified race.
- The `--paginate --slurp` flatten and the partial-page failure row were added, plus the `/`-in-branch encoding row.
- The Observability YAML was fixed and the AC row lists completed.

Taste / User-Challenge findings (ship the hook now; a `--merge` mode; `harness.ts` per-harness wiring; drop the one-shot/drain-prs wiring; drop the #8537 rebase step) were persisted to `knowledge-base/project/specs/feat-one-shot-8500-admin-merge-ready-script/decision-challenges.md`. The operator's stated scope (wire all four skills; rebase over #8537) is kept as the default.

**Relevant files (probed).**

- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md:43-62` — inline `ADMIN-MERGE-READY` block (step 2); `:64` step 4 merge; `:65` step 5 retry loop.
- `plugins/soleur/skills/ship/SKILL.md:2414` — Phase 7 hatch paragraph, pointer to the reference.
- `plugins/soleur/skills/merge-pr/SKILL.md:464,484,519` — hatch trigger lines and reference pointer.
- `plugins/soleur/skills/one-shot/SKILL.md:352` — "do NOT issue `gh pr merge` yourself".
- `plugins/soleur/skills/drain-prs/SKILL.md:82,123` — `gh pr merge <N> --squash`; the sharp edge "cannot bypass server-side required checks".
- `plugins/soleur/skills/schedule/SKILL.md:212` — the `--required` recommendation.
- `plugins/soleur/scripts/monitor-pr-checks.sh:237` — the "ALL GREEN, AUTO-MERGE NOT ARMED" exit 0.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh:512,517` — pins `settle-then-admin-merge\.md` in the hatch_check line (the filename must not change).
- Test pattern to mirror: `plugins/soleur/scripts/sync-pr-behind.test.sh` (PATH-stubbed `gh` that **refuses unexpected argv with exit 64**, instrument self-test of pass/fail helpers per ADR-193) and `plugins/soleur/test/monitor-pr-checks.test.sh`.
- Marker precedent: `plugins/soleur/scripts/resolve-regenerable-conflicts.sh:268` (`SOLEUR_REGEN_ON_CONFLICT paths=%s rc=0`).
- Test registration: `scripts/test-all.sh` `SUITE_GLOBS` includes `plugins/soleur/scripts/*.test.sh`, so a co-located suite auto-registers; `scripts/lint-orphan-test-suites.sh` checks this.

**API facts (probed live, read-only).**

- `GET repos/{o}/{r}/rules/branches/main` → array of rules; `type == "required_status_checks"` entries carry `ruleset_id` and `parameters.required_status_checks[] = {context, integration_id}`. The endpoint is paginated (`per_page` default 30); call it with `--paginate`.
- `GET repos/{o}/{r}/commits/{sha}/check-runs?per_page=100&filter=all` → `.check_runs[] {id, name, status, conclusion, app.id, started_at}`; paginate.
- `gh --version` 2.101.0.

**Institutional learnings applied.**

- `knowledge-base/engineering/operations/post-mortems/admin-merge-required-check-absent-postmortem.md`: the incident record for #8458. "The agent reported a count (25) as a verdict without comparing it to the ruleset (26)." Its Action Items table lists #8500 as `open`; the work phase flips that row once this PR merges (task 5.3).
- `knowledge-base/project/learnings/2026-03-05-defer-ci-gating-to-gh-pr-checks.md`: the origin of the `schedule/SKILL.md:212` advice. It was right about not re-implementing rollup filtering in jq and wrong about sufficiency. The rewrite keeps the first half.
- `knowledge-base/project/learnings/2026-03-20-github-required-checks-skip-ci-synthetic-status.md` and `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md`: commit statuses and check runs are separate primitives, and a ruleset entry pinned to `integration_id` 15368 is **not** satisfied by a status. This is why statuses count only for entries without `integration_id` (R12) and why the integration-id match exists (R8).
- `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md`: why the hatch exists at all, and why step 2 is the only check (`--admin` bypasses the whole rule).
- `knowledge-base/project/learnings/2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md`: test at N−1 (R1), N (H1) and N+extra (H2, 50 non-required runs), and with more than one absent member (R3). Do not test only the boundary point.
- `knowledge-base/project/learnings/2026-07-29-four-checks-reported-the-right-answer-for-the-wrong-reason.md`: an exit code alone is not proof. Every RED row also asserts the **named** context and the marker verdict, and the usage/error paths use distinct exit codes (2, 3) from not-ready (1).
- The learnings-researcher also recommended keeping the inline block's `started_at` sort "verbatim". **Rejected** with evidence: a queued re-run has `started_at: null` (see Reconciliation row 3); selection is by `id`.

**CLAUDE.md / AGENTS conventions applied.** `hr-verify-repo-capability-claim-before-assert` (every capability claim above was probed); Monitor tool, not backgrounded loops, for polling (`hr-monitor-not-run-in-background-for-polling`); guard contracts with a mutation matrix (plan §2.12).

## Proposed Solution

### The script: `plugins/soleur/scripts/admin-merge-ready.sh`

```text
admin-merge-ready.sh <PR> <head-sha> [--wait [--timeout SEC]]
admin-merge-ready.sh --help
```

Without `--wait` it checks once. With `--wait` it polls every 60s until a terminal verdict, so **no caller writes its own watch loop** (a hand-written loop is the #8458 root cause). Callers host `--wait` in the Monitor tool with `persistent: true`, the same way `monitor-pr-checks.sh` is hosted. The repo is resolved by `gh` itself (the `{owner}/{repo}` placeholders), so there is no `--repo` flag. `gh api` has no `-R`, and no caller needs one (plan-review: Kieran P1-5 / DHH P1-4). Behaviour:

0. **`--help`** prints the usage, the exit-code table and the marker grammar (including the literal `SOLEUR_ADMIN_MERGE_READY`) to stdout and exits **0**. This is also the Observability discoverability probe.
1. **Args.** `<PR>` must match `^[0-9]+$`; `<head-sha>` must be a full 40-hex SHA (a short SHA would make `--match-head-commit` ambiguous); `--timeout` (default 3600) must be a positive integer. Otherwise usage on stderr, the marker with `verdict=error`, exit **2**.
2. **Preconditions.** `command -v gh jq` or verdict `error`, exit **3**.
3. **PR head and base.** `gh pr view <PR> --json state,headRefOid,baseRefName`. `state != OPEN` → `NOT-OPEN: PR is <state>`, verdict `stale`, exit **1**. `headRefOid != <head-sha>` → `STALE: head is <actual>, not <head-sha>`, verdict `stale`, exit **1** (P4: the caller re-reads the SHA and restarts). A failed call → exit 3. In `--wait` mode this is re-checked on **every** poll, so a push during the wait ends it instead of certifying a SHA that is no longer the head.
4. **Required set.** `gh api --paginate --slurp "repos/{owner}/{repo}/rules/branches/<base, jq @uri-encoded>"` into a temp file; check the exit status before reading it (a page-2 failure must not leave page-1 rows behind as a partial answer). `--slurp` wraps the pages in an outer array, so flatten with `add` before selecting. Result: the union over **every** `required_status_checks` rule of `{context, integration_id}`, deduplicated. A failed call **or an empty set** → `ERROR: required set unreadable or empty`, exit 3. An empty set never means "nothing is required": that is exactly the vacuous state this script exists to reject. **Any entry with a null `integration_id`** → `ERROR: unpinned required context <name> unsupported`, exit 3. Every current entry is pinned (probed: all 26), so a status-reported context cannot be verified by app. Supporting commit statuses is left to the PR that introduces the first unpinned context (plan-review: DHH P0-1, simplicity).
5. **Check runs.** `gh api --paginate --slurp "repos/{owner}/{repo}/commits/<sha>/check-runs?per_page=100&filter=all"` into a temp file, exit status checked; flatten with `[.[].check_runs[]]` (never read `.total_count`). A failed call → exit 3.
6. **Classify each required entry** in one `jq` program. It iterates the **required set**, never the check list, and makes no early exit:
   - candidates = check runs with `name == context` and `app.id == integration_id`;
   - no candidate → **ABSENT**;
   - otherwise the latest is the candidate with the max `id`. `id` is monotonic, so a queued re-run (whose `started_at` is null) counts as newest. This mirrors GitHub, which uses the latest run per name and app. Mapping: `completed` + `success|skipped|neutral` → GREEN (GitHub treats all three as passing for a required check; cite the GitHub "About status checks" docs URL in the script header at work time so nobody later "fixes" `skipped` into a failure); `queued|in_progress|waiting|requested|pending` → PENDING; `completed` + anything else (`failure`, `cancelled`, `timed_out`, `action_required`, `stale`, `startup_failure`, unknown) → FAILED.
   - **Known limit, stated in the header:** if two workflows ever emit a job with the same required name, the newer run wins, as it does on GitHub. Probed 2026-09-22 on #8458's head: the only names with runs in more than one check suite (`detect-changes`, `Analyze (python)`, `Analyze (javascript-typescript)`) are not required.
7. **Output.** One line per non-green context: `ABSENT  <context>`, `PENDING <context> (<status>)`, `FAILED  <context> (<conclusion>)`, in required-set order. Then exactly one marker line, last:

   ```text
   SOLEUR_ADMIN_MERGE_READY verdict=<ready|not-ready|stale|timeout|error> pr=<N> sha=<sha> required=<n> absent=<json-array> pending=<json-array> failed=<json-array>
   ```

   The name arrays are compact JSON (`["test"]`) because context names contain spaces and parentheses (`waiver discipline (issue:#NNN trailer)`).

   **Exit codes (the contract every caller branches on).** The exit code says whether to merge; the verdict says what to do next.

   | Exit | Verdict(s) | Meaning | Caller action |
   |---|---|---|---|
   | 0 | `ready` | every required context present and green on this head | merge with `--match-head-commit <sha>` |
   | 1 | `not-ready` | something ABSENT/PENDING/FAILED (one-shot), or a required context FAILED (`--wait`: terminal, no point waiting) | stop; report the named contexts |
   | 1 | `stale` | PR not OPEN, or head moved off `<sha>` | re-read the head SHA and restart the wait |
   | 1 | `timeout` | `--wait` budget spent with contexts still ABSENT/PENDING | stop; report; never merge |
   | 2 | `error` | usage | fix the call |
   | 3 | `error` | `gh`/`jq` missing, API failure (including on any `--wait` poll), empty required set, unpinned context | stop; never merge |

   Every path, including usage and errors, prints the marker line, so a caller grepping for it never sees silence. (Plan-review folded the draft's separate exits 4 and 5 into 1: the caller action for exit 5 was identical, and for exit 4 the verdict already carries the distinction. DHH P2-6, simplicity.)

   **`--wait` emission** follows the `monitor-pr-checks.sh` contract: one line when the set of non-green contexts changes, plus a heartbeat every 5 polls when nothing changed. Emitting on every poll would be ~60 identical lines over the hour, and the Monitor tool auto-stops a watch that emits too many events. There is exactly one marker line at the end. Interval (60s) and heartbeat (every 5 polls) are constants, not flags.
8. **Header comment.** Why the script exists (#8458/#8439), why `gh pr checks --required` is insufficient, why `id` rather than `started_at`, why the union over rulesets, the integration-id match, the unpinned-context refusal, the same-name known limit, the classic-protection limit (the repo has none), the exit-code table, and the test-only `ADMIN_MERGE_READY_SLEEP` seam.

Implementation note: use `set -uo pipefail` (not `-e`) and check each `gh` exit status explicitly, as `monitor-pr-checks.sh` does. Temp files go under `mktemp -d` with an `EXIT` trap. The poll sleep is `"${ADMIN_MERGE_READY_SLEEP:-sleep}" 60`; the suite sets `ADMIN_MERGE_READY_SLEEP=true`. The seam changes how long a poll waits, never what it decides.

### Wiring (the only permitted path to `--admin`)

The canonical recipe, written once in `settle-then-admin-merge.md` and referenced everywhere else. **Step 2 (the wait)** runs in the Monitor tool with `persistent: true`:

```bash
SHA=$(gh pr view <N> --json headRefOid --jq .headRefOid)
bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/admin-merge-ready.sh" <N> "$SHA" --wait --timeout 3600
```

Exit 0 → go to the merge. Exit 1 with `verdict=stale` → re-read `SHA` and restart step 2. Any other non-zero exit → stop and report the named contexts.

**Steps 4–5 (the merge)**, also inside a Monitor (foreground `sleep` is blocked). The script re-checks before every attempt. Only GitHub's `Base branch was modified` race is retried, and the loop ends with an explicit verdict, so an exhausted loop can never read as success:

```bash
merged=0
for i in $(seq 1 20); do
  bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/admin-merge-ready.sh" <N> "$SHA"; rc=$?
  (( rc == 0 )) || { echo "ADMIN-MERGE ABORTED rc=$rc (verdict=stale: re-read SHA, restart step 2; otherwise stop)"; break; }
  if err=$(gh pr merge <N> --squash --admin --match-head-commit "$SHA" 2>&1); then merged=1; break; fi
  grep -q 'Base branch was modified' <<<"$err" || { echo "ADMIN-MERGE ABORTED: $err"; break; }
  sleep 18   # the backoff the pre-#8500 one-liner used for the same race
done
(( merged == 1 )) && echo "ADMIN-MERGED $SHA" || { echo "ADMIN-MERGE NOT LANDED"; exit 1; }
```

The advisor consult and Kieran/simplicity review found three defects in the one-liner this replaces: it retried stale and error exits as if they were pending; it returned the last `sleep`'s 0 after 20 failed attempts; and it retried every merge failure (auth, 405), not only the race.

- **`settle-then-admin-merge.md` step 2:** delete the inline `REQ=…/RUNS=…/bad=…` block and the "A shared script for this is tracked in #8500" sentence. Replace them with the `--wait` call and the exit/verdict actions above. Keep the paragraph explaining why `gh pr checks --required` is vacuous and why `--admin` bypasses the whole `required_status_checks` rule, since that reasoning stays true. Point readers to the script header for the mechanics, which removes the "reads check RUNS only / legacy STATUS reads ABSENT" sentence.
- **Steps 4 and 5** become the single merge block above. `gh pr merge <N> --squash --admin --match-head-commit "$SHA"` appears only inside it, in the same fenced block as, and after, the script call.
- **`ship/SKILL.md:2384` and `merge-pr/SKILL.md:484`** (the `[ship.phase7.behind_exhausted]` echo inside the mirrored poll blocks): change the recommendation text `(gh pr merge --squash --admin after confirming required checks are green on the current SHA — full procedure: …)` to `(admin-merge-ready.sh <PR> <sha> must exit 0, then gh pr merge --squash --admin --match-head-commit <sha> — full procedure: …)`. Make the edit **byte-identical in both files**: `ship-phase-7-poll-fixtures.test.sh` asserts that the two blocks mirror each other, and it pins only the `hatch_check` line, not this one (verified: its `admin` matches are lines 512/517, `hatch_check` only). Without this edit, Guard 2's same-line rule reds on these two pre-existing lines (Kieran P0-1, simplicity).
- **`ship/SKILL.md:2414`:** add one sentence: any `--admin` merge (hatch or operator-authorized) requires `admin-merge-ready.sh <PR> <sha>` exit 0 and `--match-head-commit <sha>`; `gh pr checks --required` is not a substitute.
- **`merge-pr/SKILL.md` (§5.2, near :519):** the same sentence.
- **`one-shot/SKILL.md:352`:** one clause on the "do NOT issue `gh pr merge` yourself" paragraph: if the operator explicitly authorizes an admin merge, it goes through `settle-then-admin-merge.md` step 2 (`admin-merge-ready.sh`), never through a hand-rolled `gh pr checks --required` watch (the #8458 shape).
- **`drain-prs/SKILL.md` §Sharp edges (:123):** add one **separate** bullet (never on the line that already says `gh pr merge --squash`, so no line carries both `gh pr merge` and `--admin` and trips Guard 2): "An operator-authorized admin merge removes the server-side check the bullet above relies on; it goes through `settle-then-admin-merge.md` step 2 (`admin-merge-ready.sh`) instead."
- **`schedule/SKILL.md:212`:** rewrite to say that `gh pr checks --required` lists only checks that exist, so a required check not yet created is invisible (#8458). A workflow gating on it must compare against the ruleset's required set, and an admin merge must call `admin-merge-ready.sh`.
- **`monitor-pr-checks.sh:237`:** append the sentence `Before any --admin merge, admin-merge-ready.sh <PR> <sha> must exit 0 — this line reads only checks that exist.` (preceded by one space) The exit code and the line prefix are unchanged.

## Implementation Phases

### Phase 1 — Tests first (RED)

0. **Capture the real-shape base fixture, read-only.** Pick a recently merged PR whose head has every required check green (`gh pr list --state merged --limit 5 --json number,headRefOid`). Fetch `rules/branches/main` and `commits/<sha>/check-runs?filter=all&per_page=100` (paginated). Trim each with `jq` to the fields the script reads: `type`, `ruleset_id`, `parameters.required_status_checks`; `id`, `name`, `status`, `conclusion`, `app.id`. Commit the result under `plugins/soleur/test/fixtures/admin-merge-ready/`, with a README line naming the source PR, the SHA, the capture date and the ruleset IDs. `plugins/soleur/test/fixtures/` already holds sibling suites' fixtures and is outside the `lint fixture content` path pattern (`.github/workflows/secret-scan.yml`). The trimmed JSON carries no URLs, logins or emails; the suite asserts that with `grep -c -e 'https://' -e '@'` returning 0. **Every Guard 1 row is derived from this base by a `jq` edit** (R1 = base with `test` deleted). No hand-written 26-name set exists (DHH P1-3, simplicity).
1. Write `plugins/soleur/scripts/admin-merge-ready.test.sh` (the Guard 1 matrix below) with a PATH `gh` stub that dispatches on the full argv and refuses anything else with exit 64 (the `sync-pr-behind.test.sh` pattern). Run it. The missing-SUT FATAL must fire; then create an empty executable SUT and confirm every row fails, each for the reason its row names.
2. Write `plugins/soleur/test/admin-merge-ready-wiring.test.sh` (Guard 2). Run it: it must be RED on the current tree (the inline block is present, `schedule:212` still has the sentence, and the two `behind_exhausted` echo lines lack `--match-head-commit`).

### Phase 2 — Script (GREEN)

3. Implement `plugins/soleur/scripts/admin-merge-ready.sh` (mode 755) per §Proposed Solution, and run the suite until every row passes. Then apply R2's SUT mutation by hand once, confirm R1 reds, revert, and record the result in the PR body.
4. Live read-only smoke (no merge): run the script against an OPEN PR's current head (this feature's own PR once it exists), once plain and once with `--wait --timeout 120`, and paste both outputs into the PR body. Never run `gh pr merge`.

### Phase 3 — Wiring (GREEN for Guard 2)

5. Edit `settle-then-admin-merge.md`, `ship/SKILL.md` (:2384 and :2414), `merge-pr/SKILL.md` (:484 and ~:519), `one-shot/SKILL.md`, `drain-prs/SKILL.md`, `schedule/SKILL.md` and `monitor-pr-checks.sh` as listed under Wiring.
6. Re-run the two new suites, `plugins/soleur/test/monitor-pr-checks.test.sh`, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (mirror parity), markdownlint on the edited `.md` files, and `shellcheck` on the new scripts.

### Phase 4 — Ship

7. Rebase check for #8537 (operator-requested): `gh pr view 8537 --json state`. If it is MERGED, run `git fetch origin main && git merge origin/main`. The only expected overlap is the "It fails closed" sentence in the reference (line 26), which this plan does not edit, so keep #8537's sentence verbatim and re-run the Phase 3 suites.
8. File the deferred hook follow-up issue (see Non-Goals) and cite it in the PR body.
9. In `knowledge-base/engineering/operations/post-mortems/admin-merge-required-check-absent-postmortem.md` §Action Items, change the #8500 row's status from `open` to `fixed by #<this PR>`.

## Files to Create

- `plugins/soleur/scripts/admin-merge-ready.sh`
- `plugins/soleur/scripts/admin-merge-ready.test.sh`
- `plugins/soleur/test/admin-merge-ready-wiring.test.sh`
- `plugins/soleur/test/fixtures/admin-merge-ready/` (the real-shape base JSON, trimmed, plus a provenance README)

## Files to Edit

- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` (step 2 block, steps 4–5)
- `plugins/soleur/skills/ship/SKILL.md` (:2384 `behind_exhausted` echo; Phase 7 hatch paragraph ~:2414)
- `plugins/soleur/skills/merge-pr/SKILL.md` (:484 `behind_exhausted` echo, byte-identical to ship's; §5.2 hatch pointer ~:519)
- `plugins/soleur/skills/one-shot/SKILL.md` (:352)
- `plugins/soleur/skills/drain-prs/SKILL.md` (§Sharp edges, new bullet after :123)
- `plugins/soleur/skills/schedule/SKILL.md` (:212)
- `plugins/soleur/scripts/monitor-pr-checks.sh` (:237 message only)
- `knowledge-base/engineering/operations/post-mortems/admin-merge-required-check-absent-postmortem.md` (§Action Items, #8500 row status)

No `description:` frontmatter is edited, so the skill-description budget check (Phase 1.8) does not apply.

## Open Code-Review Overlap

None. Checked the 72 open `code-review` issues against each file path above; no issue body names any of them.

## Non-Goals

- **PreToolUse hook that runs the script on `gh pr merge … --admin`** (human and agent merges). Deferred per the brief ("out of scope unless trivial"). The nearest template, `.claude/hooks/ship-net-issue-flow-gate.sh`, is 213 lines plus a 378-line suite, which is not trivial. Plan-review (CTO P0) argued it is the only control that reaches an agent acting outside skill text, which is the exact #8458 path. That argument is recorded as a User-Challenge in `knowledge-base/project/specs/feat-one-shot-8500-admin-merge-ready-script/decision-challenges.md`. The tracking issue is filed in Phase 4, with the re-evaluation criterion "another `--admin` merge lands with a required context not green".
- Commit-status (legacy) required contexts: refused with exit 3 until one exists (see step 4).
- `plugins/soleur/lib/harness.ts` `pollInstructions()` per-harness wiring (Grok/Devin wake patterns for the marker). Recorded as a Taste finding in `decision-challenges.md`.
- Changing the ruleset, bypass actors, or `bypass_mode` (IaC in `infra/github/`).
- Replacing `monitor-pr-checks.sh`'s check counting with ruleset-aware counting. That monitor serves the auto-merge path, where the server enforces required checks.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Keep the inline block, fix its `started_at` sort | Still prose that every agent must copy; issue §Why #1 is precisely "it is prose, not code". |
| Use `scripts/required-checks.txt` as the required set | Deliberately omits `CodeQL` and serves the bot-synthetic path; drifts from the rulesets. |
| Use `gh pr checks --required` plus a count comparison | Needs the count from somewhere; a name-level diff against the ruleset is what gives P3. |
| GraphQL `statusCheckRollup.contexts` with `isRequired` | `isRequired` is evaluated per existing context, so an absent context is still invisible. |
| Worst-of across check suites for a duplicated name | Stricter than GitHub: a stale failed suite from a close/reopen would block forever, and FAILED is terminal under `--wait`. No required name spans two suites today (Kieran P1-2, simplicity). |
| A `--merge` mode inside the script (CTO P1) | Would put the merge action inside a read-only readiness check. Recorded as Taste in `decision-challenges.md`; the prose block above is fixed instead. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur-driven PR admin-merged with a required check absent or red, so `main` (and, after CI, a production deploy decision) carries an unverified change. This is the #8458 shape: push CI on the merge commit failed.
- **If this leaks, the user's workflow is exposed via:** no data exposure. The script reads check metadata with the caller's existing `gh` token and writes only to stdout.
- **Brand-survival threshold:** `aggregate pattern`. A single bad admin merge is caught by `main`'s push CI and by the deploy arm's `ci_not_green` skip; repeated ones erode trust in the merge machinery.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_ADMIN_MERGE_READY marker line, printed as the last stdout line of every invocation (including usage and API errors); under --wait also a change line or a heartbeat every 5 polls"
  cadence: "one --wait invocation per Monitor task, polling every 60s up to --timeout; one plain invocation before each merge attempt"
  alert_target: "the invoking agent session's Monitor output, which the operator sees"
  configured_in: "plugins/soleur/scripts/admin-merge-ready.sh"

error_reporting:
  destination: "stdout marker verdict=error plus a stderr line naming the failed gh call; exit 3"
  fail_loud: "verdict=error, not-ready, stale or timeout with per-context ABSENT/PENDING/FAILED lines; any non-zero exit is a hard stop for every caller"

failure_modes:
  - mode: "required set unreadable (API error, auth), empty, or containing an unpinned context"
    detection: "script exits 3 with verdict=error; suite rows R9 and R12"
    alert_route: "invoking session's Monitor output"
  - mode: "a required context has not been created yet (aggregator absent)"
    detection: "ABSENT <context> line, verdict=not-ready, exit 1; suite row R1"
    alert_route: "invoking session's Monitor output"
  - mode: "head moved between check and merge"
    detection: "verdict=stale exit 1 before the merge (re-checked every --wait poll and before every merge attempt); --match-head-commit makes GitHub refuse the merge after"
    alert_route: "invoking session's Monitor output"
  - mode: "required contexts never finish"
    detection: "--wait ends with verdict=timeout exit 1 naming the ABSENT/PENDING contexts"
    alert_route: "invoking session's Monitor output"
  - mode: "a skill reintroduces --admin without --match-head-commit, or the inline block returns"
    detection: "plugins/soleur/test/admin-merge-ready-wiring.test.sh fails in CI (test-scripts shard)"
    alert_route: "PR check failure"

logs:
  where: "stdout/stderr of the invoking session (Monitor transcript); CI logs for the suites"
  retention: "session transcript lifetime; GitHub Actions log retention for CI"

discoverability_test:
  command: "bash plugins/soleur/scripts/admin-merge-ready.sh --help"
  expected_output: "SOLEUR_ADMIN_MERGE_READY"
```

`--help` exits 0 with no network and no credentials, and prints the marker grammar, so preflight Check 10 row 12 can PASS it. The usage-error path exits 2, which Check 10 would not treat as a pass.

## Guard Contract

### Guard 1 — admin-merge-ready.sh readiness verdict

**Property.** The script exits 0 only when every context required by any active `required_status_checks` rule on the PR's base branch has a latest check run on `<head-sha>` (matched by name and pinned integration id) whose conclusion is `success`, `skipped` or `neutral`, and `<head-sha>` is the PR's current head.

**Assembly.** Two inputs flow through one classifier: (a) the required set, from `gh api --paginate --slurp repos/{o}/{r}/rules/branches/<base>`, the union over every `required_status_checks` rule (today two rulesets: 14145388 and 13304872); (b) check runs from `commits/<sha>/check-runs?filter=all`, paginated. The chokepoint is the single `jq` classification program, which iterates the **required set** (not the check list) and emits one verdict per entry. Driving the iteration from the required set is load-bearing: iterating over present checks is exactly the #8458 defect. A second chokepoint is the PR-head/state comparison (P4), run once per check and once per `--wait` poll.

**Mutation matrix.** Every fixture is a `jq` edit of the captured real-shape base.

| # | Mutation / fixture | Expected |
|---|---|---|
| R1 | **#8458 row:** base (26 required across both rulesets, all present and green) with the `test` check run deleted | RED: exit 1, stdout has `ABSENT  test`, marker `verdict=not-ready` and `absent=["test"]` |
| R2 | SUT edit: iterate over check runs instead of the required set | R1 goes green, so the suite reds (the dispatch row) |
| R3 | Base with the 2nd and the last required contexts deleted, the 1st still present and green | RED; both are named (a check that stops at the first failure is caught) |
| R4 | `enforce`: keep its `success` run, add a newer re-run (higher `id`) with `status: queued`, `started_at: null` | RED: `PENDING enforce (queued)` (defeats a `started_at` sort) |
| R5 | `test` set to `completed/failure` | RED: `FAILED  test (failure)` |
| R6 | Conclusion `stale` / `cancelled` / an unknown value | RED: FAILED (fail closed on unknown) |
| R7 | `cla-evidence` (only in the second ruleset) deleted | RED: `ABSENT  cla-evidence` (defeats reading only the first rule) |
| R8 | `CodeQL`'s run `app.id` changed from 57789 to 15368 | RED: `ABSENT  CodeQL` |
| R9 | Rules API stub exits non-zero; separately rules returns `[]`; separately check-runs page 2 exits non-zero after page 1 succeeded | each exit 3, `verdict=error` (a guard that reports "0 required" and exits 0 is vacuous; a partial page is not an answer) |
| R10 | PR `headRefOid` differs from `<head-sha>` | exit 1, `verdict=stale` |
| R11 | Check runs split across two pages with `test` only on page 2; the stub serves page 2 only when `--paginate` is in argv | must-PASS; SUT edit dropping `--paginate` reds it |
| R12 | A required entry with `integration_id: null` | exit 3, `verdict=error`, names the context |
| R13 | PR state `MERGED` | exit 1, `verdict=stale` |
| R14 | Usage: no args, non-numeric PR, 7-char SHA, `--timeout 0` | exit 2, marker `verdict=error` printed |
| R15 | Base branch `feat/x` (PR view reports it) | the stub accepts only `rules/branches/feat%2Fx`; must-PASS proves the `@uri` encoding |
| R16 | `--wait`: `test` absent on poll 1, `in_progress` on poll 2, `success` on poll 3 | exit 0 after 3 polls; one change line per poll that changed |
| R17 | `--wait`: `test` turns `failure` on poll 2 | exit 1 immediately, `verdict=not-ready` (no waiting on a terminal red) |
| R18 | `--wait`: `headRefOid` changes on poll 2 | exit 1, `verdict=stale` |
| R19 | `--wait --timeout` spent with `test` still absent | exit 1, `verdict=timeout`, `absent=["test"]` |
| R20 | `--wait`: rules API fails on poll 2 | exit 3, `verdict=error` |

**Harness rows.**

- H1 (must-PASS, canonical): the unmodified captured base → exit 0, `verdict=ready`, `required=26`, `absent=[] pending=[] failed=[]`. This row is the proof against GitHub's real shapes: the rulesets union, the `app.id`/`integration_id` values and the check names are not the plan's guesses.
- H2 (must-PASS, non-canonical, permitted differences): the base with some `success` changed to `skipped`/`neutral`, plus, for one required name, an older `failure` run with a lower `id` (same `app.id`), plus 50 extra non-required check runs → exit 0. This is what catches a guard that rejects everything.
- H3 (suite edit → RED): the `gh` stub refuses any argv it was not written for (exit 64). Changing the SUT to query a different endpoint (e.g. `rulesets` instead of `rules/branches/<base>`) must turn rows RED rather than silently reading the right fixture.
- H4 (suite anti-vacuity): an instrument self-test of `pass`/`fail` (the ADR-193 pattern from `sync-pr-behind.test.sh`), and a final assertion that the number of cases run equals the declared case count. An early `exit 0` inside a helper, or a case lost in a `$( )` subshell, then reds the suite. The `--wait` rows run with `ADMIN_MERGE_READY_SLEEP=true`, so the suite finishes in seconds.

**Anchor.** Not applicable: the guard compares live API data (or its captured base), not a stored value it also certifies.

### Guard 2 — admin-merge wiring lint

**Property.** Every line in `plugins/soleur/` that tells an agent to run `gh pr merge` with `--admin` also carries `--match-head-commit`; in the reference, the one merge block runs `admin-merge-ready.sh` before `gh pr merge` in the same fenced block; no file presents `gh pr checks --required` as a sufficient gate; and the inline `ADMIN-MERGE-READY` block is gone.

**Assembly.** The same-line rule's population is **derived, not listed**: `git ls-files 'plugins/soleur/**/*.md' 'plugins/soleur/**/*.sh'` (excluding `*.test.sh` and `plugins/soleur/test/`), then every line that contains both `gh pr merge` and `--admin`, in either order. That grep is the chokepoint, so a fifth skill that adds an `--admin` merge later is covered without editing the lint. Today it matches 3 lines: the reference's merge block and the two `behind_exhausted` echoes. Fixed-position assertions:

- `settle-then-admin-merge.md` must not contain `RUNS=$(gh api` or `ADMIN-MERGE-READY $SHA`.
- Its fenced block containing `gh pr merge` must contain an `admin-merge-ready.sh` line before it.
- `schedule/SKILL.md` must not contain `already respects the repo's required checks configuration`.
- Each of `ship/SKILL.md`, `merge-pr/SKILL.md`, `one-shot/SKILL.md`, `drain-prs/SKILL.md` must reference `admin-merge-ready.sh` (the operator-specified wiring set).

The 15-line proximity window from the draft is cut (DHH P0-2, simplicity; CTO suggested same-fence).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| W1 | Remove `--match-head-commit` from the reference's merge line | RED |
| W2 | In a temp copy of the tree, add a new skill file containing `gh pr merge 1 --squash --admin` | RED: the population is derived; this is a second member after a compliant first |
| W3 | Reinsert the old inline `RUNS=$(gh api …)` block | RED |
| W4 | Restore the `schedule/SKILL.md:212` sentence | RED |
| W5 | Guard's own dispatch: the glob matches zero `--admin` lines (e.g. glob typo) | RED: the lint asserts at least 3 matching lines before judging any |
| W6 | Move the `admin-merge-ready.sh` line below `gh pr merge` in the reference's merge block, or delete it | RED |

**Harness rows.** W-H1 (must-PASS, non-canonical): a line `gh pr merge 1 --admin --squash --match-head-commit "$SHA"` with the flags in a different order → PASS. W-H2: the lint takes the tree root as an argument, and every W row runs the **real** lint against a temp copy (`cp -r` into `mktemp -d`), not a re-implementation.

**Anchor.** Not applicable (no stored value).

## Architecture Decision (ADR/C4)

Skipped: no architectural decision. This adds a tooling script and changes skill prose; no ownership boundary, substrate, trust boundary or ADR changes. The C4 model describes the product (web platform, integrations), not the merge tooling; no new external system or actor is introduced (the script calls the GitHub API that the `ship`/`merge-pr` flows already call). ADR-032 (branch protection as IaC) is unchanged: the rulesets stay as they are.

## Infrastructure (IaC)

Not applicable: no new infrastructure.

## Acceptance Criteria

- [ ] AC1: `plugins/soleur/scripts/admin-merge-ready.sh` exists, is executable, and implements §Proposed Solution. `bash plugins/soleur/scripts/admin-merge-ready.test.sh` passes every Guard 1 row (R1, R3–R20, H1–H4), and R2's SUT mutation reds R1 (verified once by hand; result recorded in the PR body).
- [ ] AC2: The #8458 mutation row (R1: the real-shape base with `test` deleted, every other required context present and green) exits 1 and prints `ABSENT  test` and `absent=["test"]` in the marker.
- [ ] AC3: `--help` exits 0 and prints `SOLEUR_ADMIN_MERGE_READY`. Every other exit path prints the marker as its last line, with a verdict from `ready|not-ready|stale|timeout|error`.
- [ ] AC4: In `settle-then-admin-merge.md`, `RUNS=$(gh api` is absent and step 2 calls `admin-merge-ready.sh … --wait`. The merge block runs the script before every attempt, stops on any non-zero exit, retries only `Base branch was modified`, uses `--match-head-commit "$SHA"`, and ends with `ADMIN-MERGE NOT LANDED` plus exit 1 when no attempt landed.
- [ ] AC5: `ship/SKILL.md`, `merge-pr/SKILL.md`, `one-shot/SKILL.md` and `drain-prs/SKILL.md` each reference `admin-merge-ready.sh`. The two `behind_exhausted` echo lines carry `--match-head-commit` and are byte-identical, and `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` passes (mirror parity).
- [ ] AC6: `schedule/SKILL.md` no longer presents `gh pr checks --required` as a sufficient CI gate and explains why (checks that do not exist yet are invisible).
- [ ] AC7: `plugins/soleur/test/admin-merge-ready-wiring.test.sh` passes on the final tree, and each of W1–W6 reds it.
- [ ] AC8: `monitor-pr-checks.sh`'s ALL-GREEN-NOT-ARMED line points to the script, and `plugins/soleur/test/monitor-pr-checks.test.sh` passes.
- [ ] AC9: The PR body carries the two live read-only smoke outputs (plain and `--wait`), each ending in a marker line.
- [ ] AC10: If #8537 is MERGED at ship time, the branch contains `origin/main` and the reference's "It fails closed" paragraph matches #8537's text verbatim.
- [ ] AC11: The deferred PreToolUse-hook follow-up issue exists and is linked from the PR body. The post-mortem's #8500 action-item row no longer reads `open`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (internal merge tooling and skill prose; no user-facing surface, no data, no vendor).

## Test Scenarios

- Given 26 required contexts with 25 present and green, when the script runs, then it exits 1 and names `test` as ABSENT (R1).
- Given every required context present and green, plus an older failed run of one of them, when the script runs, then it exits 0 (H2).
- Given a queued re-run newer than a success, when the script runs, then it reports PENDING (R4).
- Given the PR head moved, when the script runs, then it exits 1 with `verdict=stale` (R10; R18 mid-wait).
- Given `--wait` and a required check that turns red, when it turns red, then the wait ends at once with exit 1 (R17).
- Given the merge block's attempts all hit the base-modified race, when the loop ends, then it prints `ADMIN-MERGE NOT LANDED` and exits 1, never 0. Given a non-race merge error, then it aborts on the first attempt.
- Given the rules API fails, returns no rules, or check-runs page 2 fails, when the script runs, then it exits 3 with `verdict=error` (R9).
- Given a skill line with `gh pr merge --admin` and no `--match-head-commit`, when the wiring lint runs, then it fails (W1, W2).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh:512,517` pins the filename `settle-then-admin-merge.md`. Do not rename the reference.
- The `gh` stub must dispatch on the **full argv**, including `--paginate` and the query string, and refuse anything else. A stub that answers every `gh api` call with the same fixture puts the seam above the request shape and hides R7/R11-class defects.
- Do not run the script's live smoke with a merge: this pipeline never runs `gh pr merge`.
- Context names contain spaces, parentheses, `#` and `:`. Never split on whitespace; keep names inside `jq` and emit JSON arrays in the marker.
