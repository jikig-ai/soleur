# fix: route content-publisher stale-content alerts to ops email, not Discord

**Branch:** `feat-one-shot-fix-content-publisher-discord-ops-alerts`
**Worktree:** `.worktrees/feat-one-shot-fix-content-publisher-discord-ops-alerts/`
**Related learning:** `knowledge-base/project/learnings/2026-03-20-stale-content-publisher-duplicate-warnings.md`
**AGENTS.md rule violated:** `hr-github-actions-workflow-notifications`

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** 4 (Phase 1 test location, Phase 3 workflow wiring, Risks, Research Insights)

### Key Improvements from deepen-plan research

1. **Test framework corrected.** Bats is not installed in this repo and no
   `scripts/test/` directory exists. Canonical convention is
   `scripts/test-<topic>.sh` (top-level in `scripts/`), plain bash, sources
   the production script via `BASH_SOURCE` guard, uses `assert_eq` helpers
   matching `scripts/test-weekly-analytics.sh`. Per learning #2212, never
   prescribe a new test framework without an explicit dependency task.
2. **Workflow gating pattern corrected.** The repo does not use
   `hashFiles()` as a step conditional — it is only used for cache keys.
   Canonical conditional pattern (from `scheduled-terraform-drift.yml:222`
   and `scheduled-ux-audit.yml:207`) is `if: steps.<id>.outputs.<field>
   != ''`, where the preceding `run:` step always executes and sets the
   field only when a condition holds.
3. **Body-construction output location.** Canonical repo pattern writes the
   intermediate HTML to `/tmp/email-body.html` (see
   `scheduled-terraform-drift.yml:216`), not `$GITHUB_WORKSPACE`.
   `$GITHUB_WORKSPACE` would leak the file into the repo directory on a
   stateful runner; `/tmp/` is the correct scratch location.
4. **`content-publisher.sh` is already sourceable.** It has the
   `BASH_SOURCE` guard at line 836, so the new test can `source` it
   without triggering `main`.

## Overview

The daily `scheduled-content-publisher` cron posts an ops-severity "Stale
scheduled content detected" alert to the Discord community webhook when it
finds distribution-content files whose `publish_date` has passed. This
violates AGENTS.md hard rule `hr-github-actions-workflow-notifications`:

> GitHub Actions workflow notifications must use email via
> `.github/actions/notify-ops-email`, not Discord webhooks. Discord is for
> community content only.

Concretely, the 2026-04-22 14:00 UTC cron run posted a stale-content warning
for `2026-04-21-one-person-billion-dollar-company.md` to the `#general`
community channel where end users saw it. The fix moves that one alert path
from Discord to email via the existing composite action.

## Research Reconciliation — Spec vs. Codebase

The feature description makes four factual claims; two are accurate, two are
wrong. The plan is scoped to the accurate ones.

| Spec claim | Reality | Plan response |
| --- | --- | --- |
| `scripts/content-publisher.sh:711-714` calls `post_discord_warning` for stale content | Confirmed. Only caller in the repo (`rg post_discord_warning` = 2 hits: definition at line 321, single call-site at line 714). Helper is 23 lines, lines 321-343. | In scope. Remove helper, remove call-site, replace with file-emit pattern consumed by a workflow step. |
| The stale status mutation (`sed -i 's/^status: scheduled/status: stale/'`) must be preserved per the 2026-03-20 learning | Confirmed. Learning documents that the mutation is what makes the alert idempotent; without it every daily run re-alerts. | Preserved verbatim. The alert path is the only thing that changes. |
| `.github/workflows/scheduled-content-publisher.yml:96-124` posts a failure notification to `DISCORD_WEBHOOK_URL` | **Wrong.** Lines 96-124 are `gh api .../check-runs` calls that create synthetic check-runs so auto-merge can proceed for the status-update PR. They do not touch Discord at all. | Out of scope -- nothing to change. Documented in the "Non-goals" section below. |
| The workflow has a Discord failure-notification step that must be replaced | **Wrong / already done.** Lines 133-139 already use `./.github/actions/notify-ops-email` for the failure path (`if: failure() && steps.publish.outputs.exit_code != '2'`). | Out of scope. |

**Net scope:** one call-site + helper-function removal in
`scripts/content-publisher.sh`, one new workflow step that consumes a file
emitted by the script, and the `DISCORD_WEBHOOK_URL` env var removal from
the `publish` step once no consumer remains.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body
--limit 200` and greped for `content-publisher.sh` and
`scheduled-content-publisher.yml` in the result bodies. **No matches.** No
open scope-outs touch the files this plan edits.

## Non-goals

- **Issue #2712** (P1 pillar-page build). Distinct deliverable; same topic,
  different asset. Do NOT fold into this PR.
- Workflow lines 96-124 (synthetic check-runs for status-update PR
  auto-merge). Not a Discord path; out of scope.
- Workflow lines 133-139 (failure-notification email). Already correct.
- Discord community-content posting paths (`post_discord`,
  `x-community.sh`, `linkedin-community.sh`, `bsky-community.sh`, blog
  distribution via `post_discord` to `DISCORD_BLOG_WEBHOOK_URL`). These are
  end-user content, not ops alerts -- rule `hr-github-actions-workflow-notifications`
  explicitly exempts them.
- **Why did the 2026-04-21 file go stale in the first place?** Secondary
  question. File-level inspection shows `channels: discord, x, bluesky,
  linkedin-company` was set and `publish_date: 2026-04-21` was in the past
  by the time the 2026-04-22 cron ran. The real question is why the
  2026-04-21 cron at 14:00 UTC did not publish it. That is a separate
  investigation (`scheduled-content-generator.yml` behavior, 14:00 UTC vs.
  file mtime race, channel-specific posting failures). **Filed as a
  follow-up issue before this PR ships** -- see "Deferrals" section below.

## Hypotheses (Why did the alert land in Discord?)

Not an SSH/network-outage symptom, so Phase 1.4 checklist does not apply.
The misrouting is a direct code-path bug, not a resolver or connectivity
problem:

1. **Confirmed root cause.** `post_discord_warning` was introduced alongside
   the stale-detection path in 2026-03-20. At that time, the AGENTS.md
   rule `hr-github-actions-workflow-notifications` did not yet exist (it
   landed after the Discord community/ops separation). The stale path is
   residue from before the email-ops pattern was standardized; 19 other
   workflows migrated to `notify-ops-email` but `content-publisher.sh` was
   missed because the alert lives inside a bash script, not directly in the
   workflow YAML grep target.

No alternate hypotheses worth investigating -- the misroute is deterministic.

## Implementation Phases

### Phase 1 -- RED: failing bash test for the alert path

Location: `scripts/test-content-publisher-stale-alert.sh` (new file,
top-level in `scripts/`).

Framework: plain bash with `assert_eq` helpers, matching the existing
`scripts/test-weekly-analytics.sh` convention. Sources
`scripts/content-publisher.sh` via the existing `BASH_SOURCE` guard at
line 836 so the test can call internal functions without running `main`.
No new dependencies. Bats is NOT installed and NOT used anywhere in the
repo -- verified via `command -v bats` (missing) and `find . -name
"*.bats"` (zero results). Per learning #2212, never prescribe a new
test framework without reconciling with the "no new dependencies"
intent of a bug-fix PR.

Test skeleton (matches the canonical pattern):

```bash
#!/usr/bin/env bash
# test-content-publisher-stale-alert.sh -- Unit tests for the stale-content
# alert path. Sources content-publisher.sh (guarded by BASH_SOURCE) to
# test emit_stale_event and the stale-detection loop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=content-publisher.sh
source "$SCRIPT_DIR/content-publisher.sh"

PASS=0
FAIL=0
assert_eq() { local l="$1" e="$2" a="$3"
  if [[ "$e" == "$a" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $l: expected '$e', got '$a'" >&2; fi
}
```

Test cases (all must fail before Phase 2):

1. **Stale detection emits to `$GITHUB_OUTPUT`-style file, not Discord.**
   Fixture: a distribution-content file with `status: scheduled` and
   `publish_date` = yesterday. Stub `curl` to `fail 99` (proves no HTTP
   call is made). Run the stale-detection loop. Assert:
   - `curl` was never called (`curl` stub records zero invocations).
   - The emit file (path TBD in Phase 2 -- `${STALE_EVENTS_FILE:-/tmp/stale-events.txt}`)
     contains one line with the filename and publish_date.
   - File's frontmatter transitions to `status: stale` (pin exact
     post-state value per `cq-mutation-assertions-pin-exact-post-state`:
     `.toBe("stale")`, not `toContain`).
2. **Second run is idempotent.** Run the loop twice against the same
   fixture. Assert the emit file contains exactly one entry (not two)
   and the file is still `status: stale`. Directly verifies the
   2026-03-20 learning invariant.
3. **Missing emit-file path still works (no-op fallback).** Unset
   `STALE_EVENTS_FILE`; run the loop. Assert the function does not
   crash and logs a warning to stderr. Required because the script may
   run outside the workflow (local invocation, other workflow that
   doesn't wire the output).

### Phase 2 -- GREEN: replace `post_discord_warning` with file-emit

Location: `scripts/content-publisher.sh`.

Two atomic edits:

1. **Replace the call-site at line 714.**

   Before:

   ```bash
   if [[ "$publish_date" < "$today" ]]; then
     echo "WARNING: Stale scheduled content: $(basename "$file") (publish_date: $publish_date)" >&2
     post_discord_warning "**Stale scheduled content detected**\n\nFile: $(basename "$file")\nPublish date: $publish_date\nStatus: scheduled\n\nThis content was scheduled for a past date and was not published. Update the publish_date or set status to draft."
     sed -i 's/^status: scheduled/status: stale/' "$file"
     continue
   fi
   ```

   After:

   ```bash
   if [[ "$publish_date" < "$today" ]]; then
     echo "WARNING: Stale scheduled content: $(basename "$file") (publish_date: $publish_date)" >&2
     emit_stale_event "$file" "$publish_date"
     sed -i 's/^status: scheduled/status: stale/' "$file"
     continue
   fi
   ```

   The `sed` idempotency mutation stays verbatim between the emit and the
   `continue`. Moving it would regress the 2026-03-20 learning.

2. **Delete `post_discord_warning` (lines 321-343) and add
   `emit_stale_event`.**

   ```bash
   # --- Ops alert emit (workflow consumes and emails ops) ---
   # Writes one line per stale file to STALE_EVENTS_FILE. The workflow
   # reads the file in a subsequent step and calls notify-ops-email.
   # If STALE_EVENTS_FILE is unset (local run), log and no-op so the
   # script remains locally testable.
   emit_stale_event() {
     local file="$1"
     local publish_date="$2"
     if [[ -z "${STALE_EVENTS_FILE:-}" ]]; then
       echo "Info: STALE_EVENTS_FILE unset; stale event not persisted." >&2
       return 0
     fi
     printf '%s\t%s\n' "$(basename "$file")" "$publish_date" >> "$STALE_EVENTS_FILE"
   }
   ```

   Format is TSV (filename<TAB>publish_date), one event per line. The
   workflow aggregates lines into an HTML `<ul>` for the email body.

3. **Remove now-dead env var `DISCORD_WEBHOOK_URL` from the `publish`
   step** in `scheduled-content-publisher.yml` **only if** no other
   caller remains. Verify via `rg '\bDISCORD_WEBHOOK_URL\b'
   scripts/content-publisher.sh`. Expected result: zero hits after the
   helper is deleted. (Line 287's `DISCORD_BLOG_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}`
   fallback in `post_discord` is a community-content path and keeps the
   env var alive -- do NOT remove it from the workflow if that fallback
   is still present.)

   **Read the grep result first.** If `DISCORD_WEBHOOK_URL` is still
   consumed by `post_discord` fallback for community content, leave the
   workflow env var intact. Do not remove env vars whose consumers
   still exist -- that breaks the blog-channel fallback.

### Phase 3 -- GREEN: workflow wires the file-emit to notify-ops-email

Location: `.github/workflows/scheduled-content-publisher.yml`.

Three edits, all in the `publish` job:

1. **Declare the emit-file path as an env var on the `publish` step
   (line 49-75, the `run` step).** Add to the `env:` block:

   ```yaml
   STALE_EVENTS_FILE: ${{ runner.temp }}/stale-events.txt
   ```

   Using `runner.temp` gets auto-cleanup between runs and is already
   the pattern used by `notify-ops-email/action.yml:36`.

2. **Add a new step after "Publish content" and before "Commit status
   updates via PR"** that reads the file and invokes the email action.
   The pattern matches `scheduled-terraform-drift.yml:196-227` and
   `scheduled-ux-audit.yml:206-232` verbatim: a body-building step that
   always runs and conditionally sets the `body` output, followed by a
   gating step that invokes the email action only when the output is
   non-empty. `hashFiles()` is NOT used -- it is a cache-key function
   and the repo does not use it as a step conditional (verified via
   `rg hashFiles .github/workflows/` returning a single cache-key hit).

   ```yaml
   - name: Build stale-alert email body
     id: stale_email
     if: always()
     env:
       STALE_EVENTS_FILE: ${{ runner.temp }}/stale-events.txt
       SERVER_URL: ${{ github.server_url }}
       REPO: ${{ github.repository }}
       RUN_ID: ${{ github.run_id }}
     run: |
       if [[ ! -s "$STALE_EVENTS_FILE" ]]; then
         echo "No stale events; skipping email body."
         exit 0
       fi
       { echo "<p><strong>Stale scheduled content detected</strong></p>"
         echo "<p>The following files had <code>status: scheduled</code> but a past <code>publish_date</code>. Status was transitioned to <code>stale</code> to prevent re-alerting. Update <code>publish_date</code> or set <code>status: draft</code>.</p>"
         echo "<ul>"
         while IFS=$'\t' read -r filename publish_date; do
           printf '<li><code>%s</code> (publish_date: <code>%s</code>)</li>\n' "$filename" "$publish_date"
         done < "$STALE_EVENTS_FILE"
         echo "</ul>"
         printf '<p>Run: <a href="%s/%s/actions/runs/%s">#%s</a></p>\n' "$SERVER_URL" "$REPO" "$RUN_ID" "$RUN_ID"
       } > /tmp/stale-email-body.html

       { echo 'body<<EOF_BODY'
         cat /tmp/stale-email-body.html
         echo 'EOF_BODY'
       } >> "$GITHUB_OUTPUT"

   - name: Email notification (stale content)
     if: steps.stale_email.outputs.body != ''
     uses: ./.github/actions/notify-ops-email
     with:
       subject: '[ALERT] Scheduled content went stale (content-publisher)'
       body: ${{ steps.stale_email.outputs.body }}
       resend-api-key: ${{ secrets.RESEND_API_KEY }}
   ```

   Notes:
   - The body-building `run:` uses `{ ... } > /tmp/file` and
     `{ ... } >> "$GITHUB_OUTPUT"` forms; column-0 heredoc terminators
     are avoided per `hr-in-github-actions-run-blocks-never-use`. The
     EOF terminator `EOF_BODY` is GitHub Actions' documented multiline
     output form (not a shell heredoc inside a YAML literal block) --
     `body<<EOF_BODY ... EOF_BODY` is the intended pattern.
   - `always()` on the builder ensures stale events emitted during a
     partial-failure `publish` run still get emailed. `continue-on-error`
     is not needed; the builder's only failure mode is a malformed
     events file, which the `[[ ! -s ]]` guard short-circuits.
   - The gate step is conditional on a non-empty `body` output (NOT
     `always()`), so a run with zero stale events sends zero emails.

3. **Leave the existing "Email notification (failure)" step at lines
   133-139 untouched.** It already uses `notify-ops-email` correctly
   for workflow-level failures.

### Phase 4 -- Verify & cleanup

1. Run the bats suite (Phase 1 tests) and confirm GREEN.
2. `rg 'post_discord_warning' scripts/ .github/` -- expect zero hits.
3. `rg 'DISCORD_WEBHOOK_URL' scripts/content-publisher.sh` -- expect
   exactly 3 hits (lines 12 doc comment, 287 `post_discord` fallback,
   290 warning message). Those are community-content paths and are
   preserved.
4. `actionlint .github/workflows/scheduled-content-publisher.yml`
   (install to `~/.local/bin` if missing per AGENTS.md).
5. `bash -n scripts/content-publisher.sh` (parse check).
6. `shellcheck scripts/content-publisher.sh` (advisory; pre-existing
   warnings are out of scope, but new ones must be addressed).

## Files to Edit

- `scripts/content-publisher.sh` -- remove `post_discord_warning` (lines
  321-343), add `emit_stale_event`, swap call-site at line 714.
- `.github/workflows/scheduled-content-publisher.yml` -- add
  `STALE_EVENTS_FILE` env var to the `publish` step, add two new steps
  (build body + email invocation) between "Publish content" and "Commit
  status updates via PR".

## Files to Create

- `scripts/test-content-publisher-stale-alert.sh` -- three-case bash
  test per Phase 1, matching `scripts/test-weekly-analytics.sh`
  convention (plain bash, `set -euo pipefail`, sources production
  script via `BASH_SOURCE` guard, uses local `assert_eq` helper,
  exits 0 on all-pass and 1 on any fail).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `rg 'post_discord_warning' scripts/ .github/` returns zero hits.
- [x] `rg 'DISCORD_WEBHOOK_URL' scripts/content-publisher.sh` returns
  only community-content-path hits (3 in the pre-edit baseline; 3 after
  edit -- identical).
- [x] Phase 1 bash test passes GREEN (9/9 assertions).
- [x] `actionlint .github/workflows/scheduled-content-publisher.yml`
  passes.
- [x] `bash -n scripts/content-publisher.sh` passes.
- [ ] PR body contains `Closes #2797` (added at ship time).
- [x] Follow-up issue #2798 filed for "why did 2026-04-21 content go
  stale?" (secondary question) -- milestoned to Post-MVP / Later.

### Post-merge (operator)

- [ ] Trigger the workflow manually via `gh workflow run
  scheduled-content-publisher.yml --ref main` per AGENTS.md rule
  `wg-after-merging-a-pr-that-adds-or-modifies`.
- [ ] Verify the run log shows "Build stale-alert email body" step
  executed (or skipped with no stale events, both valid).
- [ ] If any file is currently stale: verify an email landed in
  `ops@jikigai.com` with subject `[ALERT] Scheduled content went stale
  (content-publisher)` and NO Discord post landed in the community
  channel.
- [ ] If no stale content exists: accept the no-email / no-Discord
  outcome (there is nothing to alert on).

## Deferrals

**Follow-up issue to file before ship (per AGENTS.md
`wg-when-deferring-a-capability-create-a`):**

- **Title:** `investigate: why did 2026-04-21 distribution content not publish on its scheduled date`
- **Body:** File `knowledge-base/marketing/distribution-content/2026-04-21-one-person-billion-dollar-company.md`
  had `status: scheduled`, `publish_date: 2026-04-21`, and
  `channels: discord, x, bluesky, linkedin-company`. The 2026-04-22
  cron correctly flagged it as stale, but the 2026-04-21 14:00 UTC
  cron should have published it first. Investigate: (1) did the
  2026-04-21 workflow run succeed? (2) did the file exist in the
  distribution directory at the time of the 2026-04-21 cron (possible
  PR-merge timing race)? (3) were any of the 4 channels failing?
- **Label:** `type/bug`, `priority/p3-low` (verify label names via
  `gh label list --limit 100 | grep priority` per rule
  `cq-gh-issue-label-verify-name`).
- **Milestone:** `Post-MVP / Later`.

## Test Scenarios

Covered by Phase 1 bats tests. Summary:

1. Single-run stale detection emits one event line, no HTTP calls, file
   transitions to `stale`.
2. Double-run stale detection is idempotent (one event line total).
3. Unset `STALE_EVENTS_FILE` no-ops gracefully.

End-to-end verification happens at post-merge via manual workflow
dispatch.

## Risks

- **Bats framework absent.** Confirmed -- `command -v bats` returns
  nothing and `find . -name "*.bats"` returns zero matches. Plan now
  prescribes plain bash with `assert_eq` matching `test-weekly-analytics.sh`.
- **Scratch-file location.** `/tmp/stale-email-body.html` matches the
  drift workflow (`/tmp/email-body.html`). `runner.temp` is used only
  for the cross-step events file (the TSV). Do not write the HTML
  body under `$GITHUB_WORKSPACE` -- it would show up in `git status`
  and risk being committed by the "Commit status updates via PR" step.
- **`hashFiles` is not the repo's gating pattern.** The plan's first
  draft proposed `hashFiles(...) != ''` as a step conditional. Repo
  grep shows `hashFiles` is used once (`ci.yml:145`) and only as a
  cache key. The canonical pattern is a preceding `run:` step that
  always executes and conditionally sets an output (`if [[ ! -s ]] &&
  exit 0`), then gating the next step on `steps.<id>.outputs.<field>
  != ''`. This plan now follows that pattern.
- **Idempotency regression.** If a future refactor moves the `sed`
  mutation before the emit, a second daily run will fire again. The
  Phase 1 test case #2 (double-run) is the regression guard.
- **`emit_stale_event` hidden state.** The file accumulates across a
  single run. If a future caller runs the loop multiple times within
  one workflow step (e.g., during a retry), events duplicate. Not a
  concern today -- the loop runs once per workflow -- but a doc-comment
  on `emit_stale_event` about append-only semantics is included.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change
(GitHub Actions + bash script). Does not touch user-facing product,
legal, finance, marketing copy, or customer-facing flows. The only
external side effect is routing internal ops alerts from one channel
(Discord) to another (email) that both parties are already in.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
| --- | --- | --- | --- |
| **Emit-to-file + workflow-reads** (chosen) | Clean separation, script remains locally testable, workflow owns email orchestration, matches AGENTS.md `hr-in-github-actions-run-blocks-never-use` construction pattern. | Two files to edit. | Chosen. |
| Script directly invokes Resend API | One-file change. | Leaks `RESEND_API_KEY` secret into the script's env, duplicates `notify-ops-email` logic, every future ops script would need the same curl/auth/retry. Violates separation of concerns. | Rejected. |
| Re-use `DISCORD_WEBHOOK_URL` but target a `#ops-alerts` Discord channel | No workflow YAML change. | Violates `hr-github-actions-workflow-notifications` flat-out. Rule says email, not ops-Discord. | Rejected. |
| Emit to `$GITHUB_OUTPUT` directly (no file) | One fewer artifact. | `$GITHUB_OUTPUT` has a 1 MiB total cap per step and the stale list is unbounded in theory. File is safer and trivially cheaper. | Rejected. |

## Research Insights

- **Existing `notify-ops-email` pattern (19 call-sites).** Verified via
  `rg 'notify-ops-email' .github/workflows/`. Every one follows one of
  two shapes: (a) inline HTML `body:` (short message), (b) a preceding
  step that builds the body and pipes to `$GITHUB_OUTPUT` via
  `body<<EOF_BODY` multiline output. This plan uses (b) since the
  body enumerates a list of files.
- **Canonical multiline `$GITHUB_OUTPUT` body pattern.** Verified from
  `scheduled-terraform-drift.yml:216-219` and `scheduled-ux-audit.yml:216-224`:

  ```bash
  { echo "<p>...</p>"; ... } > /tmp/email-body.html
  { echo 'body<<EOF_BODY'; cat /tmp/email-body.html; echo 'EOF_BODY'; } >> "$GITHUB_OUTPUT"
  ```

- **Canonical step-gate pattern** (from same files): the body-builder
  sets the output only when the condition holds (`exit 0` early when
  the source file is empty), and the downstream step gates on
  `steps.<id>.outputs.<field> != ''`. `hashFiles` is NOT used for
  step conditionals in this repo.
- **`notify-ops-email/action.yml`** sends to a hardcoded
  `ops@jikigai.com` via Resend HTTP API. HTML is allowed in the body
  (confirmed by the `html: $html` parameter construction at action.yml
  line 34). Matches AGENTS.md user-email `ops@jikigai.com`.
- **Test convention.** `scripts/test-<topic>.sh` (top-level), plain
  bash with `set -euo pipefail`, sources production script via
  `BASH_SOURCE` guard, uses local `assert_eq` helper, PASS/FAIL
  counters, `exit $FAIL`. See `scripts/test-weekly-analytics.sh` for
  the canonical form. No bats, no `scripts/test/` directory.
- **Script sourceability.** `scripts/content-publisher.sh` already has
  the sourceability guard (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]];
  then main "$@"; fi` at line 836). The new test can `source` the
  script and call `emit_stale_event` directly.
- **2026-03-20 learning.** `sed -i 's/^status: scheduled/status:
  stale/'` is the idempotency guarantee; the workflow commits the
  file mutation back to main via the "Commit status updates via PR"
  step. This plan preserves the mutation byte-for-byte, placed
  between the emit and the `continue`.
- **No directional ambiguity.** The spec is clear: Discord -> email,
  not email -> Discord. No confirmation needed.
- **No secondary email-path changes.** Workflow line 133-139 already
  uses `notify-ops-email` for workflow-level failures. No other
  Discord ops-alert paths in the workflow or script.

## Exit Criteria

- All Acceptance Criteria pre-merge checkboxes satisfied.
- PR approved, CI green, auto-merge queued.
- Follow-up issue filed for the secondary (why did 2026-04-21 content
  go stale) question.
- `/soleur:compound` run before commit (per rule
  `wg-before-every-commit-run-compound-skill`).
