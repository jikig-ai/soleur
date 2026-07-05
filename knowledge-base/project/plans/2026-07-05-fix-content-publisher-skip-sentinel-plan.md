---
title: "fix: content-publisher.sh credential-skip return 0 scored as publish (skip sentinel)"
type: fix
issue: 6065
branch: feat-one-shot-6065-content-publisher-skip-sentinel
lane: single-domain
brand_survival_threshold: aggregate pattern
created: 2026-07-05
status: draft
---

# 🐛 fix: content-publisher.sh silent-success — credential-skip `return 0` scored as a publish

Closes #6065.

## Overview

`scripts/content-publisher.sh` scans `distribution-content/` for files with `status: scheduled`
and `publish_date == today`, posts each declared channel, and flips the file to
`status: published` when at least one channel "succeeds".

The bug: every per-channel **skip** path (`no credentials`, `no content`, `gate flag off`,
`no org id`, `tracker-route`) does `return 0`. The caller (`while … case "$channel"`, `:854-899`)
scores `return 0` as a real post → `file_successes++`. With `file_successes > 0` the file is
flipped to `published` (`:905`) even though **nothing reached any network**. A file whose
declared channels were all skipped is marked `published` while posted nowhere — a silent success
the pipeline never re-attempts.

The fix introduces a distinct sentinel return code `3` ("skipped, not attempted") on every
skip path, makes the caller capture `$?` and count `file_skips` separately from `file_successes`,
and only flips `draft→published` when `file_successes > 0` (a real post landed). When a file's
channels were **all** skipped, it stays `scheduled` and a dedup `action-required` GitHub issue is
surfaced ("published nowhere — all channels skipped").

This is orthogonal cleanup of the root cause. The self-healing draft→scheduled promotion +
content-starvation alert + Sentry heartbeat merged in #6059 (`dc23f7d76`) already catch the
**symptom** (a stuck un-posted file goes `stale` next day → starvation alert), so no observability
of the outcome is lost — this fix removes the false `published` state that hid the root cause.

### Why the original deferral framing was wrong

#6065 was deferred out of #6059 with the framing "all-channels-skipped leaves
`file_successes==0 && file_failures==0` → stays `scheduled`." That guard is **unreachable today**
because skips score as successes (`file_successes++`). This fix makes the guard reachable by
routing skips through the sentinel — the guard fires on `file_successes==0 && file_failures==0 &&
file_skips>0`.

## Research Reconciliation — Spec vs. Codebase

The issue names **4** credential-skip sites. Verifying against the code (`set -euo pipefail`
confirmed at `:38`) surfaced **11** skip `return 0` sites of the same bug class across the 5
`post_*` functions. Fixing only the 4 named would leave the identical mask live for the other 7
(e.g. a Bluesky-only file with `BSKY_ALLOW_POST` unset still flips to `published`). The fix
converts all 11.

| Spec / issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| Discord credential-skip at `~:305` | `post_discord :305` (no webhook) `return 0` | → `return 3` |
| X credential-skip at `~:418` | `post_x_thread :418` (no creds) `return 0` | → `return 3` |
| X **also** skips with no tweets | `post_x_thread :431` (empty thread) `return 0` — same mask | → `return 3` (scope-add) |
| LinkedIn credential-skip at `~:596` | `post_linkedin :597` (no token) `return 0` | → `return 3` |
| LinkedIn **also** skips with no content | `post_linkedin :604` (empty section) `return 0` | → `return 3` (scope-add) |
| LinkedIn Company skip paths (unnamed) | `post_linkedin_company :627` (no org token → **tracker-route**), `:632` (no org id), `:637` (`LINKEDIN_ALLOW_POST!=true`), `:644` (no content) — all `return 0` | → `return 3` (see Decision D1 for `:627`) |
| Bluesky credential-skip at `~:687` | `post_bluesky :688` (no creds) `return 0`; **also** `:693` (`BSKY_ALLOW_POST!=true`), `:700` (no content) | → `return 3` (scope-add on `:693`/`:700`) |
| Caller scores `return 0` as success at `~:861/:873/:882/:889/:896` | Confirmed: each `case` arm does `if post_X; then file_successes++ else file_failures++` | Rewrite to `rc=0; post_X \|\| rc=$?; case $rc in 0) successes; 3) skips; *) failures` |
| Status flip at `~:905` | Confirmed `sed -i 's/^status: scheduled/status: published/'` gated on `file_successes>0` | Keep gate; add all-skip `elif` branch |
| "the guard already exists, just make it reachable" | Guard was described but never coded; the decision block (`:902-914`) has only `if successes / elif failures` | Add the `elif file_skips>0` branch |

**Non-skip `return 0` sites deliberately NOT touched** (verified genuine successes / helpers, not
post-skip): `:117`, `:130`, `:218` (frontmatter/validation helpers), `:350` (`emit_stale_event`
no-op), `:540` (`append_to_linkedin_tracker` idempotent-append success), `:740`
(`create_dedup_issue` "already exists"). Converting any of these would be a regression.

**Mirror surface checked, no analogous bug:** `apps/web-platform/server/inngest/functions/content-promotion.ts`
is the TS draft→scheduled promotion mirror — it does **no** network posting or credential checks
(pure frontmatter transition, documented "NO I/O" at `:1-20`), so the skip-mask class does not
exist there. Out of scope.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) the status quo persists — marketing
content silently marked `published` while posted to zero channels, so the audience never sees it
and the operator believes distribution is working; or (b) an over-correction leaves genuinely-
publishable files stuck `scheduled` and re-posting. The fix's guard (`file_successes>0` for the
flip) and the layered `stale`/starvation net bound (b).

**If this leaks, the user's data is exposed via:** N/A — the script posts public marketing
content and creates public `action-required` issues containing marketing copy + case names only.
No PII, no credentials, no regulated-data surface.

**Brand-survival threshold:** aggregate pattern — recurring silent non-publication degrades brand
reach over time. Not a single-user data/money incident, so no per-PR CPO sign-off required.

## Implementation Phases

Phases are ordered by **contract-before-consumer** (the `post_*` functions declare the new
`return 3` contract before the caller consumes it) so no phase leaves dead code, per the
plan-phase-order sharp edge. All changes ship in one atomic PR.

### Phase 1 — Sentinel contract on the 5 `post_*` functions (`scripts/content-publisher.sh`)

Convert each skip `return 0` to `return 3` ("skipped, not attempted"). **Do not** touch the
`return 1` (real-failure) or the genuine-success `return 0` paths.

- `post_discord` — `:305` (no webhook) → `return 3`.
- `post_x_thread` — `:418` (no creds) → `return 3`; `:431` (no tweets) → `return 3`.
- `post_linkedin` — `:597` (no token) → `return 3`; `:604` (no content) → `return 3`.
- `post_linkedin_company` — `:627` (no org token, tracker-route) → `return 3` (**Decision D1**);
  `:632` (no org id) → `return 3`; `:637` (`LINKEDIN_ALLOW_POST!=true`) → `return 3`;
  `:644` (no content) → `return 3`.
- `post_bluesky` — `:688` (no creds) → `return 3`; `:693` (`BSKY_ALLOW_POST!=true`) → `return 3`;
  `:700` (no content) → `return 3`.

Add a one-line convention comment above `post_discord` documenting: `# return 0 = posted;
1 = attempted+failed (fallback issue created); 3 = skipped, not attempted (no cred/content/gate).`

**Note (`:627` tracker-route, Decision D1):** this path already appends a durable record to the
LinkedIn rolling tracker (#4046) via `append_to_linkedin_tracker`, then `return 0`. Returning `3`
(skip) keeps it out of `file_successes` (the company post never landed on LinkedIn). The tracker
remains the primary durable record; the generic all-skip issue is a benign secondary surface if
company is the file's only channel. Recommended for uniform correctness — flagged for reviewers.

### Phase 2 — Caller: capture exit code, count skips separately (`scripts/content-publisher.sh :839-900`)

1. Add `local file_skips=0` next to `file_failures=0` / `file_successes=0` (`:839-840`).
2. Rewrite each `case "$channel"` arm to a **set-e-safe** exit-code capture (the script runs under
   `set -euo pipefail`, so a bare `cmd; rc=$?` would trip errexit before the capture — use the
   `|| rc=$?` idiom, matching `2026-07-03-enforcement-probe-must-discriminate-exit-codes…`):

   ```bash
   x)
     local rc=0
     post_x_thread "$file" || rc=$?
     case "$rc" in
       0) file_successes=$((file_successes + 1)) ;;
       3) file_skips=$((file_skips + 1)) ;;
       *) file_failures=$((file_failures + 1)) ;;
     esac
     ;;
   ```

   Apply the same shape to `linkedin-personal`, `linkedin-company`, `bluesky`.
3. **Discord** keeps its caller-side content-guard + fallback-issue creation. Fold the sentinel in:

   ```bash
   discord)
     local discord_content
     discord_content=$(extract_section "$file" "$section")
     if [[ -n "$discord_content" ]]; then
       DISCORD_LAST_ERROR=""
       local rc=0
       post_discord "$discord_content" || rc=$?
       case "$rc" in
         0) file_successes=$((file_successes + 1)) ;;
         3) file_skips=$((file_skips + 1)) ;;
         *) echo "Warning: Discord posting failed. Creating fallback issue." >&2
            create_discord_fallback_issue "$discord_content" "$DISCORD_LAST_ERROR" || true
            file_failures=$((file_failures + 1)) ;;
       esac
     else
       echo "Warning: No $section content found in $(basename "$file"). Skipping Discord." >&2
       file_skips=$((file_skips + 1))   # count empty-content Discord as a skip so the all-skip guard is complete
     fi
     ;;
   ```
4. **Unknown-channel** arm (`:849-852`) currently `continue`s without counting. Add
   `file_skips=$((file_skips + 1))` before `continue` so a file whose only declared channels are
   unknown is also caught by the all-skip guard (a "published nowhere" state today).

### Phase 3 — Decision block: only flip on real success; surface all-skip (`scripts/content-publisher.sh :902-914`)

Keep the existing `if file_successes>0` (flip to `published`) and `elif file_failures>0`
(`failures++`, exit 2) arms unchanged. Insert the all-skip branch:

```bash
if [[ "$file_successes" -gt 0 ]]; then
  # unchanged: flip to published, published++
elif [[ "$file_failures" -gt 0 ]]; then
  failures=$((failures + 1))   # unchanged: fallback issues exist, drives exit 2
elif [[ "$file_skips" -gt 0 ]]; then
  # All declared channels skipped — posted nowhere. Leave status: scheduled so
  # the file re-attempts on the next same-day run and (per #6059) goes stale →
  # starvation alert on the following day. Surface a dedup action-required issue.
  echo "WARNING: $CASE_NAME posted nowhere — all $file_skips declared channel(s) skipped." >&2
  local nowhere_title="[Content Publisher] Published nowhere -- all channels skipped for $CASE_NAME"
  local nowhere_body
  nowhere_body=$(printf '## Content Posted Nowhere\n\nAll declared channels for **%s** were skipped (no credentials, gate flag off, or empty section) — nothing reached any network. The file remains `status: scheduled`.\n\n**Declared channels:** %s\n\nSee the workflow run logs for the per-channel skip reason (each skip echoes a `Warning:` to stderr). Provide the missing credentials / enable the gate / fix the section, then re-run.' "$CASE_NAME" "$channels")
  create_dedup_issue "$nowhere_title" "$nowhere_body" "action-required,content-publisher" || true
fi
```

**Decision D2 — exit code for all-skip:** do **not** increment `failures` (keep exit 0). Rationale:
exit 2 in `cron-content-publisher.ts:695` means "attempted, some failed, fallback issues created"
— semantically distinct from "never attempted." Credential-less environments (forks, LinkedIn
Company pending #4046) legitimately skip every run; exiting 2 every run would be noise and mislabel
the wrapper's WARN log. Observability is layered instead: the **dedup `action-required` issue**
(operator-visible via `operator-digest`) + the file staying `scheduled` → next-day `stale` →
#6059 starvation alert. The Sentry heartbeat (`scheduled-content-publisher`) still reports the run
completed. Alternative (exit 2) documented in Alternatives — flag for reviewers.

The script's header "Exit codes" doc block (`:34-37`) stays `0/1/2`: `return 3` is an **internal
function return** consumed inside `main()`; it never escapes as a process exit code.

### Phase 4 — Test coverage (`scripts/test-content-publisher-stale-alert.sh` → rename `scripts/test-content-publisher.sh`)

The existing bash test sources the production script under the `BASH_SOURCE` guard and stubs
`curl`. It is currently an **orphan** (not wired into `test-all.sh`). Rename it to
`test-content-publisher.sh` (scope is now broader than stale-alert; only self-referencing header
comments + the new `run_suite` line reference it) and add:

**Unit tests (source script, unset envs, assert `return 3`):**
- `post_discord "x"` with no webhook → rc 3.
- `post_x_thread <fixture>` with no X creds → rc 3; with creds but empty thread section → rc 3.
- `post_linkedin <fixture>` no token → rc 3; token set + empty section → rc 3.
- `post_linkedin_company <fixture>` no org token (stub `append_to_linkedin_tracker`) → rc 3;
  org token set + `LINKEDIN_ALLOW_POST` unset → rc 3.
- `post_bluesky <fixture>` no creds → rc 3; creds set + `BSKY_ALLOW_POST` unset → rc 3;
  creds + gate on + empty section → rc 3.
- `post_discord` **success** path unchanged: webhook set + stubbed `curl` returning HTTP `2xx`
  → rc 0 (regression guard that success is not mislabelled a skip).

**Integration tests (`main()` on a temp fixture dir, stub `gh`/`create_dedup_issue`):**
- **Regression (the bug):** `status: scheduled`, `publish_date == today`, `channels: discord`,
  no creds → after `main()`, file frontmatter is still `status: scheduled` (NOT `published`),
  `create_dedup_issue` was called once with a title containing "Published nowhere" and labels
  `action-required,content-publisher`, and `main` exits 0.
- **Real success dominates:** two channels, one stubbed to succeed (rc 0) + one skipped (rc 3)
  → file flips to `status: published`, no "published nowhere" issue.
- **Failure path preserved:** a channel stubbed to fail (rc 1) with no success → `failures>0`,
  exit 2, no "published nowhere" issue (the `elif file_failures` arm wins).

Follow the existing test's fixture + `assert_eq` + stub-flag-file conventions. Stub `gh`/
`create_dedup_issue` the way the existing test stubs `curl` (a wrapper that records invocation to
a temp flag file). `date +%Y-%m-%d` for the publish_date so the fixture is "today".

### Phase 5 — Wire the test into CI (`scripts/test-all.sh`)

In the `want_scripts` block (before the `fi` at `:156`), add:

```bash
run_suite "scripts/content-publisher" bash scripts/test-content-publisher.sh
```

This closes the pre-existing orphan-test gap (fold-in, since we are already editing this file and
adding the coverage it should have gated).

## Files to Edit

- `scripts/content-publisher.sh` — Phases 1-3 (11 `return 0`→`3` conversions; `file_skips` counter;
  set-e-safe exit-code capture in 5 `case` arms + unknown-channel; all-skip decision branch;
  convention comment).
- `scripts/test-content-publisher-stale-alert.sh` → **rename** `scripts/test-content-publisher.sh`
  — Phase 4 (update header comment to reflect broader scope; add unit + integration cases).
- `scripts/test-all.sh` — Phase 5 (one `run_suite` line).

## Files to Create

None (test file is a rename + extension, not a new file).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `grep -cE '^\s*return 3' scripts/content-publisher.sh` returns `11` (every named skip
  path routed through the sentinel).
- [ ] AC2 — No skip `return 0` remains in the 5 `post_*` functions: for each of
  `post_discord`/`post_x_thread`/`post_linkedin`/`post_linkedin_company`/`post_bluesky`, a manual
  read confirms every non-success/non-failure early-return is `return 3` (the 6 non-post `return 0`
  sites at `:117/:130/:218/:350/:540/:740` are unchanged).
- [ ] AC3 — Caller declares `local file_skips=0` and each channel `case` arm plus the
  unknown-channel and empty-Discord branches increment `file_skips` on skip:
  `grep -c 'file_skips=$((file_skips + 1))' scripts/content-publisher.sh` returns `≥ 6`.
- [ ] AC4 — Exit-code capture is set-e-safe: `grep -c '|| rc=$?' scripts/content-publisher.sh`
  returns `≥ 5` (no bare `cmd; rc=$?` form, which would trip `set -e`).
- [ ] AC5 — The status flip remains gated on real success:
  `grep -A2 'file_successes.*-gt 0' scripts/content-publisher.sh` shows the
  `status: scheduled → published` `sed` only inside that arm; the all-skip `elif file_skips`
  branch does **not** flip status.
- [ ] AC6 — The all-skip branch calls `create_dedup_issue` with a "Published nowhere" title and
  `action-required,content-publisher` labels (verified by read + the AC8 integration test).
- [ ] AC7 — `bash scripts/test-content-publisher.sh` exits 0 (all unit + integration cases pass),
  including the regression test asserting an all-skipped file stays `status: scheduled`.
- [ ] AC8 — `bash -n scripts/content-publisher.sh` and `bash -n scripts/test-content-publisher.sh`
  parse clean; `shellcheck scripts/content-publisher.sh` surfaces no new warnings vs. main
  (if `shellcheck` available — `command -v shellcheck` first).
- [ ] AC9 — `scripts/test-all.sh` runs the new suite: `grep -c 'test-content-publisher.sh'
  scripts/test-all.sh` returns `1`, and `TEST_GROUP=scripts bash scripts/test-all.sh` includes
  and passes the `scripts/content-publisher` suite.
- [ ] AC10 — The orphaned old filename is gone: `test ! -f scripts/test-content-publisher-stale-alert.sh`
  and no dangling references (`grep -rn 'test-content-publisher-stale-alert' . --exclude-dir=.git`
  returns nothing outside this plan/spec).
- [ ] AC11 — PR body uses `Closes #6065` (this is a code fix that resolves at merge, not an
  ops-remediation — `Closes`, not `Ref`).

### Post-merge (operator)

None — the fix is a pure code change on the already-provisioned cron surface (`web-platform-release.yml`
restarts the container on merge; the next scheduled `cron-content-publisher` run exercises it). No
migration, no infra, no vendor mint, no dashboard step.

## Domain Review

**Domains relevant:** Marketing (advisory)

### Marketing

**Status:** reviewed (inline — mechanical correctness fix)
**Assessment:** `cron-content-publisher` is CMO-owned (`routine-metadata.ts:56`, domain
"Marketing"). This fix has no strategy or messaging implication — it ensures declared distribution
content actually reaches its channels instead of being silently marked `published` while posted
nowhere, which strictly improves marketing reach fidelity. No brand-voice or content-copy change.
The relevance-gated `cmo` lens in `plan-review` will confirm; no separate domain-leader spawn
warranted for a mechanical exit-code correction.

### Product/UX Gate

Not applicable — no UI surface. Files edited are `scripts/*.sh` (no path matches
`components/**/*.tsx`, `app/**/page.tsx`, or the UI-surface term list). Tier: NONE.

## Observability

```yaml
liveness_signal:
  what: existing Sentry heartbeat (monitor slug "scheduled-content-publisher", #6059) — unchanged
  cadence: daily 14:00 UTC (cron-content-publisher)
  alert_target: Sentry Crons monitor
  configured_in: apps/web-platform/server/inngest/functions/cron-content-publisher.ts:59,771-811
error_reporting:
  destination: dedup GitHub issue labelled action-required,content-publisher ("Published nowhere -- all channels skipped for <CASE_NAME>"), harvested by operator-digest; per-channel skip reason echoed to stderr → GitHub Actions / Inngest run logs
  fail_loud: yes — dedup issue is created every run until the file posts or goes stale (one open issue per stuck file, deduped on exact title)
failure_modes:
  - mode: all declared channels skipped (published nowhere)
    detection: create_dedup_issue "Published nowhere ..." (emitted FROM the script — in-surface for the blind cron worker); issue body enumerates the declared channels so credential-skip vs empty-section is discriminable in one artifact
    alert_route: operator-digest (action-required issues) + GitHub issue list
  - mode: file stays scheduled → next-day run flips it to stale
    detection: emit_stale_event → content-starvation alert (#6059)
    alert_route: notify-ops-email
  - mode: a channel attempted and failed (unchanged)
    detection: per-channel fallback issue + exit 2 → cron-content-publisher.ts:692 WARN
    alert_route: GitHub issue + Inngest run log
logs:
  where: GitHub Actions / Inngest cron run logs (stderr Warning per skip); dedup issue body
  retention: GitHub issues (indefinite until closed); Inngest run logs (platform default)
discoverability_test:
  command: gh issue list --state open --label action-required --label content-publisher --search "Published nowhere in:title"
  expected_output: one open issue per file currently stuck posted-nowhere (empty when all scheduled content posts)
```

**2.9.2 (blind cron worker):** the `content-publisher.sh` process runs inside the Inngest
cloud-task spawn, not directly inspectable. The `failure_modes` detection above is **in-surface** —
the `create_dedup_issue` call and the per-skip stderr `Warning:` lines are emitted from inside the
script, and the dedup issue body lists the declared channels, discriminating "no credentials" vs
"empty section" vs "gate off" without SSH.

## Architecture Decision (ADR / C4)

No architectural decision. `return 3` is a **local convention within one script** (an internal
function-return sentinel consumed inside `main()`), not a cross-cutting substrate, tenancy, trust,
or resolver change. C4 completeness check against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): the external
actors/systems (Discord, X, LinkedIn, Bluesky, GitHub Issues) and their access relationships are
**unchanged** by this fix — the script already posted to them; this only corrects how the *result*
is scored. No new external actor, external system, data store, or access relationship. A competent
engineer reading the existing ADRs + C4 would not be misled about the system after this ships →
skip (no `.c4` edit, no ADR).

## Open Code-Review Overlap

None. Queried open `code-review` issues (`gh issue list --label code-review --state open`) against
`content-publisher.sh`, `test-content-publisher`, and `test-all.sh` — no matches.

## Test Scenarios

| Scenario | Setup | Expected |
| --- | --- | --- |
| Bug regression | `channels: discord`, today, no `DISCORD_*` webhook | stays `status: scheduled`; "Published nowhere" dedup issue created; exit 0 |
| Real success | `channels: discord`, webhook set, stubbed curl 2xx | flips to `status: published`; no dedup issue |
| Success + skip mix | `channels: discord,bluesky`; Discord succeeds, Bluesky creds unset | flips to `published`; skip does not block |
| Attempt failure | `channels: bluesky`, creds set, post script fails (rc 1) | `failures++`, exit 2; fallback issue; no "Published nowhere" |
| All gate-off | `channels: bluesky`, creds set, `BSKY_ALLOW_POST` unset | stays `scheduled`; "Published nowhere" issue |
| Empty section | `channels: linkedin-personal`, token set, no "LinkedIn Personal" section | stays `scheduled`; "Published nowhere" issue |
| Unknown channel only | `channels: mastodon` (maps to no section) | stays `scheduled`; "Published nowhere" issue |

## Risks & Sharp Edges

- **`set -e` exit-code capture (load-bearing).** The script runs `set -euo pipefail`. A bare
  `post_x_thread "$file"; rc=$?` trips errexit on any non-zero return **before** the capture. Use
  `rc=0; post_x_thread "$file" || rc=$?` (AC4). The `if post_X; then` form the code uses today is
  set-e-safe but cannot capture the specific code 3 — that's why the rewrite is required.
- **Discriminate exit codes, do not collapse.** Per
  `knowledge-base/project/learnings/best-practices/2026-07-03-enforcement-probe-must-discriminate-exit-codes-not-any-failure-as-safe.md`,
  the caller must branch `0` / `3` / `*` explicitly. Treating "any non-zero as failure" would
  mislabel a `return 3` skip as a `file_failures++` (spurious exit 2 + a fallback issue for a
  channel that was never attempted).
- **Tracker-route (`:627`) double-surface.** Converting the LinkedIn-Company no-org-token path to
  `return 3` means a company-only file with the tracker route can also trip the all-skip issue
  (the tracker already recorded it). Benign (different title, deduped) but noted for reviewers
  (Decision D1) — alternative is to special-case `:627` back to a non-skip "handled" state, which
  reintroduces the mask for the company post that never landed. Recommended: keep uniform `3`.
- **Exit-code semantics for all-skip (Decision D2).** Chosen exit 0 (not 2) so credential-less
  environments do not emit a WARN every run and the wrapper's "partial failure" log stays accurate.
  Observability is preserved via the dedup issue + the #6059 stale/starvation net. If reviewers
  prefer a louder signal, the alternative is `failures++` (exit 2 → non-fatal WARN in
  `cron-content-publisher.ts:692`) — would also require updating that log message to cover
  "published nowhere," touching `apps/web-platform/server/inngest/functions/cron-content-publisher.ts`
  (a code-class file → would then trigger a fuller Observability/2.9 pass).
- **Re-attempt window is same-day only.** "Leave scheduled → re-attempt" only helps if the cron
  fires again on the publish day. The following day, `publish_date < today` flips the file to
  `stale` (`:804`) → starvation alert. This is intended (layered with #6059), not infinite
  re-attempt — do not assume the file retries indefinitely.
- **Orphan test wiring.** The existing `test-content-publisher-stale-alert.sh` is not in
  `test-all.sh`; the rename + `run_suite` line (Phase 5) is what makes the new coverage actually
  gate CI. Verify with `TEST_GROUP=scripts bash scripts/test-all.sh` (AC9), not just a bare
  `bash scripts/test-content-publisher.sh`.
- **Stub `gh`/`create_dedup_issue` in tests.** The integration tests run `main()`, which reaches
  `create_dedup_issue` (calls `gh`). The test must stub these (as the existing test stubs `curl`)
  or the suite fails on missing `GH_TOKEN` / network.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| Fix only the 4 issue-named credential-skip sites | Leaves the identical mask on the other 7 skip paths (gate-off, empty-section, no-org-id) — same bug, incomplete fix. |
| All-skip → increment `failures` (exit 2) | Overloads exit 2 ("attempted + failed") with "never attempted"; emits WARN every run in credential-less envs (noise); would also require editing the TS wrapper's log message. Kept as documented alternative for reviewers. |
| Emit a Sentry event on all-skip | Credential-less non-posting (e.g. LinkedIn Company pre-#4046) is a legitimate steady state; per-run Sentry events would be noise. The **dedup** GitHub issue (one per stuck file) is the right, non-flooding surface; #6059 starvation alert covers true drought. |
| Special-case `:627` tracker-route as non-skip | Reintroduces the publish mask for a company post that never landed on LinkedIn; uniform `return 3` is simpler and correct (Decision D1). |
