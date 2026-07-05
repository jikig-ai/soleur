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

## Enhancement Summary

**Deepened on:** 2026-07-05
**Agents:** code-simplicity-reviewer, spec-flow-analyzer, observability-coverage-reviewer, Explore (precedent-diff + verify-the-negative + bash correctness), learnings-researcher, repo-research-analyst.

### Key improvements folded in from deepen review

1. **CRITICAL (spec-flow F1) — closed a silent `0/0/0` gap.** A `channels:` value that is whitespace/comma-only (e.g. `channels: ","`) passes the empty-channels guard at `:815`, then every token trims to empty and hits the uncounted `continue` at `:846`, leaving `successes=failures=skips=0` → the decision block falls through with **no issue, no warning, exit 0**. Phase 2 now counts the empty-token path so "published nowhere" surfaces in *all* nowhere cases (the "guard is complete" claim is now actually true).
2. **P1 (observability) — carry the skip reason into the durable issue.** The Inngest spawn (`spawnScriptCapture`, `cron-content-publisher.ts:170-191`) **captures and discards stderr** on every path — so the original "see the workflow run logs for the per-channel skip reason" pointer referenced a non-existent artifact and the §2.9.2 "discriminable in one artifact" claim was false. Each skip path now sets a `SKIP_REASON` (mirroring the existing `DISCORD_LAST_ERROR` global), the caller accumulates per-channel reasons, and `create_nowhere_issue` interpolates them into the issue body — making credential-skip vs empty-section vs gate-off discriminable in the one durable artifact.
3. **Simplicity — dedup + house-style extraction.** The repeated 5× `case "$rc"` collapses into a `tally_rc` helper; the inline issue-body build becomes a named `create_nowhere_issue` function (every other issue creator in the file is a `create_*_*_issue` helper). Net structure is cleaner even with the reason-carrying added.
4. **Precedent-diff.** `scripts/sweep-followthroughs.sh:211-261` is the in-repo precedent for the `local rc=0; cmd || rc=$?; case "$rc" in 0/1/*` idiom under `set -euo pipefail` — the fix matches house style. The `return 3 = skipped` *semantic* is novel (every other non-0/1 return in the tree is an error/fatal code), so the one-line convention comment above `post_discord` is the required signpost.

### New considerations discovered (documented, scoped)

- **spec-flow F2 (pre-existing, out of scope → deferred):** a *partially* published file (one channel succeeds, another skips) flips to `published` and the skipped channel is never re-attempted and gets no issue. Not a regression (pre-fix the skip scored as success identically); tracked as a follow-up (see Alternatives / Deferrals).
- **observability P2 (accepted with backstop):** the all-skip `create_dedup_issue … || true` swallows a `gh` outage; bash has no Sentry SDK, so the cross-day backstop is the file staying `scheduled` → next-day `stale` → #6059 starvation email. Kept `|| true` for consistency with the file's existing fallback-issue pattern.

## Research Insights

- **Discriminate exit codes, never "any non-zero = X".** Per `knowledge-base/project/learnings/best-practices/2026-07-03-enforcement-probe-must-discriminate-exit-codes-not-any-failure-as-safe.md`, the caller must branch `0` / `3` / `*` explicitly — the `tally_rc` `case` does exactly this.
- **set-e-safe capture (verified).** `local rc=0; post_X "$file" || rc=$?` is correct under `set -euo pipefail` (the call sits on the LHS of `||`, so errexit is suppressed and `$?` is the call's code). **Gotcha to avoid:** never `local rc=$(post_X …)` — `local` is itself a command, so `$?` would reflect `local`'s status (0) and mask the real code (and defeat errexit). Two statements are mandatory.
- **`tally_rc` dynamic-scope dependency.** The helper mutates `main`'s `local` counters via bash dynamic scoping; this works only because the channel loop runs in the current shell (`done < <(...)`, not a pipeline subshell) — the same property the existing counters already rely on. Do not refactor the loop into a pipeline.
- **Verify-the-negative (all confirmed):** `return 3` never escapes `main()` (only `exit 0/1/2` at `:756/:762/:768/:774/:923`); the 6 non-post `return 0` sites (`:117/:130/:218/:350/:540/:740`) are genuine helper successes; `content-promotion.ts` has zero network/credential surface (self-documented "NO I/O"); the existing bash test sources under the `BASH_SOURCE` guard and stubs `curl` via function override (extendable to `gh`/`create_dedup_issue`).

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

**At each skip site, set a module-scope `SKIP_REASON` before `return 3`** (mirroring the existing
`DISCORD_LAST_ERROR` global at `:330`, declared near the top of the script). Reuse the short reason
the site already echoes to stderr — e.g. `SKIP_REASON="no credentials"`, `"empty section"`,
`"gate flag off (BSKY_ALLOW_POST)"`, `"no org id"`, `"no org token (routed to tracker)"`. The
caller (Phase 2) reads `SKIP_REASON` on `rc==3` so the durable "published nowhere" issue can
name *which* reason applied to *which* channel — the stderr line itself is discarded by the
Inngest spawn (`spawnScriptCapture` captures + drops stderr), so the reason must be carried in a
variable, not left on stderr.

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

1. Declare the new counters/accumulator next to `file_failures=0` / `file_successes=0` (`:839-840`):
   `local file_skips=0` and `local -a file_skip_reasons=()`.
2. Add a **`tally_rc`** helper (near the other helpers, above `main`) that dedups the repeated
   outcome branch and, on skip, records the channel + reason. It mutates `main`'s `local` counters
   via bash dynamic scoping — valid because the channel loop runs in the current shell
   (`done < <(...)`, not a pipeline subshell). Precedent for the whole idiom:
   `scripts/sweep-followthroughs.sh:211-261`.

   ```bash
   # tally_rc <rc> <channel> — score one channel's post_* return.
   # 0 = posted, 3 = skipped (record reason), else = attempted+failed.
   tally_rc() {
     local rc="$1" channel="$2"
     case "$rc" in
       0) file_successes=$((file_successes + 1)) ;;
       3) file_skips=$((file_skips + 1))
          file_skip_reasons+=("${channel}: ${SKIP_REASON:-skipped}") ;;
       *) file_failures=$((file_failures + 1)) ;;
     esac
   }
   ```
3. Rewrite each `case "$channel"` arm to the **set-e-safe** capture (bare `cmd; rc=$?` would trip
   errexit under `set -euo pipefail`; never `local rc=$(cmd)` — `local` masks `$?`):

   ```bash
   x)
     local rc=0
     post_x_thread "$file" || rc=$?
     tally_rc "$rc" "$channel"
     ;;
   ```

   Apply the same shape to `linkedin-personal`, `linkedin-company`, `bluesky`.
4. **Discord** keeps its caller-side content-guard + fallback-issue creation. Fold the sentinel in;
   the `*` branch must run the fallback-issue creation (which `tally_rc`'s generic `*` arm does not),
   so Discord keeps an inline `case` rather than calling `tally_rc`:

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
         3) file_skips=$((file_skips + 1))
            file_skip_reasons+=("${channel}: ${SKIP_REASON:-skipped}") ;;
         *) echo "Warning: Discord posting failed. Creating fallback issue." >&2
            create_discord_fallback_issue "$discord_content" "$DISCORD_LAST_ERROR" || true
            file_failures=$((file_failures + 1)) ;;
       esac
     else
       echo "Warning: No $section content found in $(basename "$file"). Skipping Discord." >&2
       file_skips=$((file_skips + 1))
       file_skip_reasons+=("${channel}: empty section")
     fi
     ;;
   ```
5. **Unknown-channel** arm (`:849-852`) currently `continue`s without counting. Before `continue`:
   `file_skips=$((file_skips + 1)); file_skip_reasons+=("${channel}: unknown channel")`.
6. **Empty-token `continue` (`:846`, spec-flow F1 — closes the silent `0/0/0` gap).** The
   `[[ -z "$channel" ]] && continue` swallows whitespace/comma-only channel tokens that pass the
   `:815` non-empty guard (e.g. `channels: ","`). Count it so a degenerate channel list still
   surfaces a "published nowhere" issue instead of falling through silently:
   `[[ -z "$channel" ]] && { file_skips=$((file_skips + 1)); file_skip_reasons+=("(empty channel token)"); continue; }`.

### Phase 3 — Decision block: only flip on real success; surface all-skip (`scripts/content-publisher.sh :902-914`)

Keep the existing `if file_successes>0` (flip to `published`) and `elif file_failures>0`
(`failures++`, exit 2) arms unchanged. Insert the all-skip branch:

Extract a named `create_nowhere_issue` helper (house-style — every other issue creator in the file
is a `create_*_*_issue`) that interpolates the **per-channel skip reasons** collected in Phase 2
so the durable artifact is self-discriminating (P1 fix — the stderr reason stream is discarded by
the Inngest spawn, so it must live in the issue body, NOT a "see run logs" pointer):

```bash
create_nowhere_issue() {
  local case_name="$1"; shift
  local reasons_list="$1"   # newline-joined "channel: reason" lines
  local title="[Content Publisher] Published nowhere -- all channels skipped for $case_name"
  local body
  body=$(printf '## Content Posted Nowhere\n\nEvery declared channel for **%s** was skipped — nothing reached any network. The file remains `status: scheduled`.\n\n**Per-channel skip reason:**\n\n%s\n\nProvide the missing credentials / enable the gate flag / fix the empty section, then re-run.' \
    "$case_name" "$reasons_list")
  create_dedup_issue "$title" "$body" "action-required,content-publisher"
}
```

Decision block (`:902-914`) — keep the existing `if file_successes>0` (flip `published`) and
`elif file_failures>0` (`failures++`, exit 2) arms unchanged; insert the all-skip branch:

```bash
if [[ "$file_successes" -gt 0 ]]; then
  # unchanged: flip to published, published++
elif [[ "$file_failures" -gt 0 ]]; then
  failures=$((failures + 1))   # unchanged: fallback issues exist, drives exit 2
elif [[ "$file_skips" -gt 0 ]]; then
  # All declared channels skipped — posted nowhere. Leave status: scheduled so the
  # file re-attempts on the next same-day run and (per #6059) goes stale → starvation
  # alert the following day. Surface a dedup action-required issue naming each skip reason.
  echo "WARNING: $CASE_NAME posted nowhere — all $file_skips declared channel(s) skipped." >&2
  local reasons_joined
  reasons_joined=$(printf '- %s\n' "${file_skip_reasons[@]}")
  create_nowhere_issue "$CASE_NAME" "$reasons_joined" || true   # gh outage → #6059 stale/starvation net is the cross-day backstop
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
  `create_dedup_issue`/`create_nowhere_issue` was called once with a title containing "Published
  nowhere" and labels `action-required,content-publisher`, and `main` exits 0.
- **Reason discrimination in the issue body:** `channels: bluesky,linkedin-personal`, Bluesky creds
  unset (→ "no credentials") + LinkedIn token set but "LinkedIn Personal" section empty (→ "empty
  section") → the captured issue body contains BOTH `bluesky: no credentials` and
  `linkedin-personal: empty section` (proves the durable artifact discriminates skip reasons, not
  a "see run logs" pointer).
- **Real success dominates:** two channels, one stubbed to succeed (rc 0) + one skipped (rc 3)
  → file flips to `status: published`, no "published nowhere" issue.
- **Failure wins over skip (spec-flow F3, multi-channel):** `channels: discord,bluesky`, Discord
  stubbed to fail (rc 1) + Bluesky skipped (rc 3), no success → `0/1/1` → `failures>0`, exit 2,
  Discord fallback issue created, NO "published nowhere" issue (the `elif file_failures` arm wins
  over `elif file_skips`). This exercises the `elif` ordering with `skips>0` present, which a
  single-channel `0/1/0` fixture does not.
- **Silent `0/0/0` gap closed (spec-flow F1):** `channels: ","` (or `channels: " "`) → passes the
  `:815` guard, all tokens trim empty → the empty-token path counts a skip → file stays
  `scheduled` and a "Published nowhere" issue IS created (proves the degenerate channel list no
  longer falls through silently).

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

- `scripts/content-publisher.sh` — Phases 1-3 (11 `return 0`→`3` conversions + `SKIP_REASON` at each;
  `file_skips` counter + `file_skip_reasons` accumulator; `tally_rc` helper; set-e-safe capture in
  5 `case` arms; count the empty-token `:846` + unknown-channel `:849` skip paths (F1);
  `create_nowhere_issue` helper with per-channel reasons; all-skip decision branch; convention comment).
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
- [ ] AC3 — Skip counting is **behavioral, not shape-grepped** (per the deepen shape-grep-AC
  caution): the Phase 4 integration tests assert that (a) an all-skip file stays `status: scheduled`
  with a "Published nowhere" issue, (b) a degenerate `channels: ","` file also surfaces the issue
  (F1), and (c) the issue body enumerates per-channel skip reasons. `grep -q 'local file_skips=0'`
  and `grep -q 'file_skip_reasons' scripts/content-publisher.sh` confirm the counter + accumulator
  exist; correctness is proven by AC7, not by a literal-increment count.
- [ ] AC4 — Exit-code capture is set-e-safe: `grep -c '|| rc=$?' scripts/content-publisher.sh`
  returns `≥ 5` (one per channel `case` arm; no bare `cmd; rc=$?` and no `local rc=$(…)` form,
  which would trip / mask `set -e`).
- [ ] AC4b — The all-skip issue body carries per-channel reasons (P1): the reason-discrimination
  integration test asserts the captured `create_nowhere_issue` body contains both
  `bluesky: no credentials` and `linkedin-personal: empty section`, and the plan/impl contains **no**
  "see the workflow run logs" pointer for skip reasons (`grep -c 'workflow run logs'
  scripts/content-publisher.sh` returns `0`).
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
  destination: dedup GitHub issue labelled action-required,content-publisher ("Published nowhere -- all channels skipped for <CASE_NAME>"), harvested by operator-digest; the issue BODY carries the per-channel skip reason (SKIP_REASON captured in a variable, not stderr — the Inngest spawn discards stderr)
  fail_loud: yes — dedup issue is created every run until the file posts or goes stale (one open issue per stuck file, deduped on exact title); on gh outage the #6059 stale/starvation net is the cross-day backstop
failure_modes:
  - mode: all declared channels skipped (published nowhere)
    detection: create_nowhere_issue (emitted FROM the script — in-surface for the blind cron worker); issue body enumerates "channel: reason" for every skip, so credential-skip vs empty-section vs gate-off is discriminable in the one durable artifact (reason carried in SKIP_REASON var, NOT the discarded stderr stream)
    alert_route: operator-digest (action-required issues) + GitHub issue list
  - mode: file stays scheduled → next-day run flips it to stale
    detection: emit_stale_event → content-starvation alert (#6059)
    alert_route: notify-ops-email
  - mode: a channel attempted and failed (unchanged)
    detection: per-channel fallback issue + exit 2 → cron-content-publisher.ts:692 WARN
    alert_route: GitHub issue + Inngest run log
logs:
  where: dedup issue body (per-channel "channel: reason"). NB: stderr Warning lines exist but are captured-and-discarded by spawnScriptCapture (cron-content-publisher.ts:170-191) — not a durable log surface, which is why the reason is carried into the issue body instead
  retention: GitHub issues (indefinite until closed)
discoverability_test:
  command: gh issue list --state open --label action-required --label content-publisher --search "Published nowhere in:title"
  expected_output: one open issue per file currently stuck posted-nowhere (empty when all scheduled content posts)
```

**2.9.2 (blind cron worker):** the `content-publisher.sh` process runs inside the Inngest
cloud-task spawn, not directly inspectable, and **stderr is captured-and-discarded** by
`spawnScriptCapture` (`cron-content-publisher.ts:170-191`). The `failure_modes` detection above is
therefore **in-surface via the durable GitHub issue**, not stderr: `create_nowhere_issue` is called
from inside the script, and its body carries the per-channel `SKIP_REASON` (captured in a variable),
so "no credentials" vs "empty section" vs "gate off" is discriminable in the one artifact without
SSH and without relying on the dropped stderr stream.

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
- **`0/0/0` silent gap (spec-flow F1 — fixed, don't regress).** The `:815` empty-channels guard
  only checks the raw `$channels` string is non-empty; a whitespace/comma-only value (`channels:
  ","`) passes it, then every token trims empty and hits the `:846` `continue`. Phase 2 step 6
  counts that path so the file surfaces a "Published nowhere" issue instead of falling through with
  no signal. The "all-skip guard is complete" claim is only true because BOTH `:846` (empty token)
  and `:849` (unknown channel) are now counted — do not drop either.
- **`SKIP_REASON` global pattern.** Mirrors the existing `DISCORD_LAST_ERROR` module-scope global.
  It is read by `tally_rc` immediately after each `post_*` call, so it is not clobbered between the
  skip and its capture (single-threaded). Declare it near `DISCORD_LAST_ERROR` and reset is not
  required (each skip site sets it before `return 3`).
- **`tally_rc` dynamic-scope dependency (don't refactor the loop into a pipeline).** `tally_rc`
  mutates `main`'s `local file_successes/file_failures/file_skips/file_skip_reasons` by name via
  bash dynamic scoping — valid only because the channel loop runs in the current shell
  (`done < <(...)`). Converting the loop to `... | while` (subshell) would silently break all
  counters, not just the new one. Precedent for the idiom: `scripts/sweep-followthroughs.sh:211-261`.
- **`return 3 = skipped` is a novel semantic in this tree.** Every other non-0/1 return in the repo
  is an error/fatal code (`return 2` reject, `return 4` fatal-missing-dep, `return 99` flock). The
  one-line convention comment above `post_discord` is the required signpost so a future reader does
  not mistake `3` for a failure.
- **Partial-publish drops a skipped channel forever (spec-flow F2 — pre-existing, out of scope).**
  When one channel succeeds and another skips (`successes>0 && skips>0`), the file flips to
  `published` and the skipped channel is never re-attempted and gets no issue. This is NOT a
  regression (pre-fix the skip scored as a success identically) and is orthogonal to #6065's
  "all channels skipped" scope — deferred to a follow-up (see Alternatives / Deferrals). Do not
  expand this PR to cover it.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| Fix only the 4 issue-named credential-skip sites | Leaves the identical mask on the other 7 skip paths (gate-off, empty-section, no-org-id) — same bug, incomplete fix. |
| All-skip → increment `failures` (exit 2) | Overloads exit 2 ("attempted + failed") with "never attempted"; emits WARN every run in credential-less envs (noise); would also require editing the TS wrapper's log message. Kept as documented alternative for reviewers. |
| Emit a Sentry event on all-skip | Credential-less non-posting (e.g. LinkedIn Company pre-#4046) is a legitimate steady state; per-run Sentry events would be noise. The **dedup** GitHub issue (one per stuck file, now carrying per-channel reasons) is the right, non-flooding surface; #6059 starvation alert covers true drought. The reason strings also let operator-digest distinguish a benign "no credentials" skip from an anomalous "empty section despite creds" without a separate louder channel. |
| Special-case `:627` tracker-route as non-skip | Reintroduces the publish mask for a company post that never landed on LinkedIn; uniform `return 3` is simpler and correct (Decision D1). |
| Extract `tally_rc` used by ALL five arms incl. Discord | Discord's `*` branch must also create a fallback issue, which the generic helper does not — Discord keeps an inline `case`. The other four arms use `tally_rc`. |

## Deferrals (file at ship via the deferral-tracking gate)

- **spec-flow F2 — partial-publish silently drops a skipped channel.** When a file publishes to at
  least one channel but a *declared* channel was skipped (e.g. `discord` succeeds, `bluesky` has no
  creds), the file flips to `published` and the skipped channel is never re-attempted and gets no
  issue. Pre-existing (not introduced or worsened by this fix) and orthogonal to #6065's
  "all channels skipped" scope. **Re-evaluation criterion:** fold into the next content-publisher
  change, or when a real "declared channel silently never posted on a published file" incident is
  observed. **Milestone:** Post-MVP / Later. File a GitHub issue (`content-publisher`, plus
  `deferred-scope-out` if that label exists) at ship time.
