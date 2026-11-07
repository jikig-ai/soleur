---
title: "Sentry groups by message, a lost grant read as a denial, and an outage read as off"
category: integration-issues
module: egress-audit-read-path
tags: [sentry, observability, rpc, 42501, feature-flags, plpgsql, plan-cache, migrations, dev-ledger, legal-copy]
date: 2026-10-26
pr: 11115
issue: 9545
---

# Learning: Sentry groups by message, a lost grant read as a denial, and an outage read as off

## Problem

PR #11115 (the member-readable egress audit log, brand-survival threshold single-user incident) passed its own
plan review, a 14-mutant battery against the live RPC, tsc, eslint and 247 targeted tests. A 13-seat review panel
then found 26 unique defects (about 95 raw), two of them P1, and a 9-seat fix round found one more P1 inside the
fixes. Every one lived in the failure arms, the observability of those arms, or a claim in prose.

1. **Any SQLSTATE 42501 was treated as the expected membership denial.** The RPC raises 42501 with a constant message
   for a non-member, but the engine raises the same code ("permission denied for function") when the EXECUTE grant is
   lost. The loader rendered both as "You no longer have access to this workspace", never mirrored, so a grant drift
   would have shown every member that card with no Sentry event. The migration header even said the constant message
   existed to tell them apart; the loader never read `message`, and its test passed `message: "x"`.
2. **A fallback flag read hid as "off".** `getRuntimeFlag` never throws on a Flagsmith outage; it returns the env
   mirror (off in production). The reader's `catch -> "unknown"` branch was therefore unreachable, and an outage showed
   "Recording isn't on" and omitted the recording notice for an organisation that may be recording. Four comments
   claimed the opposite.
3. **Sentry groups message events by message text; level and tags do not split a group.** The page's paged
   `workspace_read_error` and the card's unpaged `hint_workspace_read` used the same static string. The card runs on
   every Scope Grants load with a tighter bound, so it would create the group first; the page's later events would join
   a group whose first event did not match the paging rule's `op in (...)` filter, and the page's alert would stay dark
   until someone resolved the group. The op-contract test compared op sets and could not see it.
4. **A STABLE definer RPC called per page view flips to a generic plan after five calls in a session.** Measured on a
   1.8M-row table: 19-34 ms for calls 1-5, 510-600 ms from call 6 (it walked the `last_seen` index across all
   workspaces). `SET plan_cache_mode = force_custom_plan` fixed it. Separately, ranking every (host, decision) group
   with `row_number()` and `count(*)` to return 200 rows cost 8-9 s at the 1.44M-group worst case; a top-N with
   `LIMIT n + 1` and `EXISTS ... OFFSET n` for `truncated` brought it to 4-6 s.
5. **I edited migration 177 in place after CI had applied it to the shared dev project.** `tenant-integration` had
   passed on the pushed head, so dev held the old body; the dev-ledger guard says a migration applied to dev is as
   immutable as a merged one. The branch carried the paired `.down.sql`, so the sanctioned route was the
   `dev-ledger-reconcile` workflow (dry run, then `execute=true`), after which CI applied the final body fresh.
6. **Removing the `title` hover time left the same datum in `<time dateTime>`.** The CLO's condition (no absolute time
   anywhere a reader can see it) was fixed on the attribute named in the ruling, not on the datum. Caught by the CLO's
   own verification pass and by two seats.
7. **Public legal text asserted the dialog's behaviour unconditionally** ("switching on shows the owner a notice") while
   the code showed it only when collection was on or unverifiable, and only to owners. The fix was to make the code the
   conditional one (a conditional lead plus the full notice, one constant) and the text say so, not to weaken either.

## Solution

- **Discriminate the denial by the constant message prefix**, not the code: `code === "42501" &&
  message.startsWith("egress audit: ")` is `forbidden`; any other 42501 is a paged `rpc_error` with a sanitised
  `pg_code` tag (5-char SQLSTATE or `PGRST\d{3}`, else `none`/`other`). A contract test binds every 42501 `RAISE` in the
  migration to the loader's exported prefix constant, and rejects the condition-name spellings.
- **Every op gets its own static message**, and the op-contract test derives the paged and unpaged sets from the loader
  source (`fault(` / `warn(` / `onFault(` literals, comment-stripped), asserts the call-site count equals the literal
  count (a computed op cannot hide), and asserts no message literal appears under two ops.
- **Readers get a tri-state flag** (`readRuntimeFlagDetailed` returns `{value, fellBack}`; the reader helper maps
  `fellBack` to `"unknown"`); ingest keeps the plain boolean. An outage renders the unavailable state, never
  "Recording isn't on".
- **Bound every read the page makes** (pointer 2 s, collection and web-access reads 1.5 s each; card 600/800/800 ms and
  1.2 s overall) with the existing `bounded()` race, and keep the reads that depend on authorisation AFTER the RPC.
- **Record fixture arguments**: the loader test's fake now records `select`, `.eq(column, value)` and `abortSignal`,
  throws on an unknown table or column list, and exposes only `select()` on `from()` like the real client.
- **Dev ledger**: dry run showed `would-discard 177... eligible=1 down=1 later-rows=0`, execute reported
  `discarded=1`; the next CI run applies the final body.

## Key Insight

A failure arm is only as good as the thing that tells it from its neighbour. Three of the defects are the same shape:
two different situations produced one observable (42501; flag "off"; one Sentry group), and the tests asserted each
situation separately, never that the observables differ. When a diff adds a distinction in prose or in a header
comment ("this message exists to tell them apart"), the review question is *which consumer reads the distinguishing
field, and which test would go red if it stopped reading it*. Sentry's grouping rule in particular is not visible in
any code: it needs the vendor's behaviour, so the repo-side proxy is "no static message appears under two ops".

## Session Errors

1. **Stopped after the gdpr-gate report instead of continuing the Phase 2 exit** (the operator asked "why did you
   stop?"). Recovery: resumed with the affected-test verdict. **Prevention:** a gate skill's report is a step, not a
   turn boundary; end a turn only on a stated `Paused:` / `Blocked:` reason.
2. **Closing messages that named a next action tripped the unkept-promise Stop hook** several times while waiting for
   background seats. Recovery: ended with one `Paused: <what I am waiting on>` sentence. **Prevention:** when waiting
   on a notification, say only what has landed and end with the `Paused:` label.
3. **The affected-test gate was `budget-deferred` (rc=6) after 35 minutes queued behind sibling worktrees' full-gate
   runs**, so it produced no verdict. Recovery: read rc and the log's terminal line, not the notification; ran the
   targeted suites and the repo-global ratchets by name; CI is authoritative. **Prevention:** run
   `scripts/test-all.sh --capacity` before launching the gate and skip it when contended.
4. **`pgrep -f` was blocked by the self-match hook.** Recovery: read the rc file and log instead. **Prevention:** none
   needed; the hook worked.
5. **Gate commands run from a stale `cd apps/web-platform` returned rc=127** (relative script paths). Recovery: re-ran
   from the repo root. **Prevention:** begin every gate command with an absolute `cd <worktree root> && pwd`.
6. **`soleur-sandbox.sh new` reset the shell cwd to the bare repo root, and `rm` of the sandbox then deleted the cwd**
   (`getcwd` errors). Recovery: used absolute paths in the next call. **Prevention:** `cd` to the worktree before any
   sandbox call and again after; never rely on the persisted cwd across a sandbox allocation.
7. **Edited migration 177 in place after `tenant-integration` had applied it to dev** (finding 5 above). Recovery:
   sanctioned reconcile workflow. **Prevention:** before editing a migration during review, check whether
   `tenant-integration` has run on the PR; routed as a bullet in the review skill's migration defect-classes reference.
8. **Plan premise "migration 164 is free" was wrong** (claimed by open draft PRs; highest ordinal on any `origin/*` ref
   was 176). Recovery: 177, probed across all remote refs. **Prevention:** already routed to the plan skill's `references/plan-sharp-edges.md`.
9. **Brainstorm claims refuted by research:** `resolveCurrentWorkspaceId` does not validate membership and falls back to
   the user id; a function-level `statement_timeout` does not re-arm the running statement; a route plus a 429 state
   machine was unnecessary. Recovery: plan rewritten. **Prevention:** none beyond measuring before ruling.
10. **Wireframe/tooling frictions:** `open_document` refused an untracked `.pen` (committed a skeleton first; routed to
    the design agent earlier); gitleaks flagged the adapter `fileToken` (key removed per save); export files are named
    by frame name; no `clock` icon (used `hourglass`); empty spacer frames collapsed. **Prevention:** recorded in the
    design agent and the earlier learning.
11. **A mistaken `ScheduleWakeup` outside `/loop`.** Recovery: cancelled with `stop: true`. **Prevention:** use it only
    inside `/loop`.
12. **Mutation survivors M3 (probe tenant filter), M12 (lower `last_seen` bound), M13 (`search_path` pin)** after the
    first 14-mutant battery; fixed by adding a same-bucket workspace-B row, an out-of-window row and a shape test.
    **Prevention:** the battery had not edited the probe's workspace predicate; enumerate the axes, not the count.
13. **A banner headline contained the forbidden word "complete"** across the view and 20 `.pen` nodes; reworded and
    re-exported. **Prevention:** run the forbidden-word scan over the wireframe text nodes when the view's scan changes.
14. **`<time dateTime>` kept the removed hover time in the DOM** (finding 6). Recovery: plain `<span>`; tests assert no
    `<time>` and no ISO string in the markup. **Prevention:** when a ruling removes a datum from a surface, sweep every
    attribute and element that carries it, not the one the ruling named.

## Tags

category: integration-issues
module: egress-audit-read-path
