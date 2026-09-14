---
title: "The guard pinned the names the plan listed, and the readback read every page unpinned"
date: 2026-09-13
category: workflow-patterns
tags: [drift-guard, mutation-battery, follow-through, better-stack, logtail-provider, pagination, prose-counts, review-panel, one-shot]
issue: 8097
pr: 8110
module: apps/web-platform/infra
---

# The guard pinned the names the plan listed, and the readback read every page unpinned

## Problem

#8097 asked for one Better Stack Logs alert that pages on `SOLEUR_*_SEND_FAILED` / `_REFUSED`
rows from the four web-1 monitor units, verified through web-1's real apply path. The
implementation (ADR-218: `BetterStackHQ/logtail` provider, `logtail_exploration_alert`, a
`terraform_data` probe keyed on a digits-only rev, a daily follow-through, a `logs_alert` arm in
`reconcile-live-heartbeats.ts`) was correct on the happy path. The review panel's structural
roll-up found three defects that shared one shape: **an instrument built from the enumeration
in the plan, not from a census of the tree.**

1. **The drift guard checked the four `emit_refusal()` definers the plan named** and held each
   to `logger -p user.crit`. The property the plan stated was "every crit-level SOLEUR_ marker
   that reaches PRIORITY 2 is either routed through the alert or deliberately excluded". The tree
   had a **fifth** definer (`resend-inbound-bootstrap.sh`, no `logger` at all — it runs in CI),
   `inngest-cutover-flip.sh` emitted a `_REFUSED` at `user.notice` through a backslash-continued
   `logger` line the line-based scan could not see, and nothing asserted that a *new* crit
   `logger` outside `emit_refusal` would be classified at all. A green guard with a fixed name
   list is a sentence about four files.
2. **The follow-through's incident readback walked the Uptime API's `/incidents` list with no
   stop condition and no host pin.** The list is newest-first, 10 per page, 16 pages that day and
   growing. Unbounded, the daily sweeper's cost grows with the account's history; unpinned
   (`curl` following redirects, `pagination.next` taken verbatim), a redirect or a crafted `next`
   would carry the bearer off-host. The plan's scenario read "an incident matching the alert by
   `name` or `cause`" — true of the *first* page on the day it was written.
3. **Seven prose sites said "15" or "16" SSH provisioners after the branch made it 17.** The
   mechanised floor (`web-host-provisioner-parity.test.sh`, zero-slack `FLOOR_RESOURCES`) caught
   the count; `server.tf`'s own header comment, the parity test's prose, the replace-gate library
   and its test, ADR-114's amendment, ADR-154 and `model.c4` did not, because a count in prose has
   no test.

## Solution

- **Guard: replace the name list with a census.** `betterstack-send-failed-alert.test.sh` now
  scans every non-test `infra/*.sh` and `cloud-init*.yml` for crit-level emit lines
  (`logger -p/--priority …crit|2`, `systemd-cat`, `'<0-2>'`) after a string-aware comment strip
  that joins `\`-continuations, classifies each as *routed through `emit_refusal`*, *allowlisted
  non-paging* (`NON_PAGING_MARKERS`, `NON_CRIT_ALLOWLIST` with a reason each), or
  *unclassified* — the last is red, so a future crit `logger` cannot land unnamed. The allowlist is
  itself checked for staleness (`non-paging allowlist stale:`). The battery grew from 19 to 36
  rows, each attributed by FAIL string, and was driven RED against two neutered guard copies before
  the count was pinned (`EXPECTED_ROWS=36`).
- **Follow-through: bound and pin every read.** `paged_get <host> <path> [stop-epoch]` takes
  `pagination.next` only when it is on the pinned host (`-g --max-redirs 0`, host-only refusal
  message), stops when a page's oldest `started_at` predates the anchor (computed *before* the
  GET), caps at `PAGE_CAP=50`, and redacts `username=`/`password=`/`token=` and the 516 body
  before anything reaches stdout — the sweeper posts stdout verbatim to a public issue. Identity
  (`REV`, `ALERT_NAME`, `CAUSE_PREFIX`) is derived from the `.tf`, never restated. The harness
  grew from 38 assertions / 16 cases to 75 / 24, with per-page `curl` fixtures and an `OFFHOST`
  recorder.
- **Prose: write counts as derived-set language or date them.** Every site now reads "17 as of
  #8097" or points at the floor; the ADR that owns the count carries the dated amendment, the
  others point.

## Key Insight

**"Discover every X" is a property over the tree; the plan's list of X is one reading of it, taken
on the day the plan was written.** A guard that pins the list is green for exactly that reading.
Build the discovery from the tree (a census with an *unclassified* bucket that reds), keep the
plan's list only as the floor (`MIN_CASES`), and drive the battery against a mutant that *adds* an
instance — not just ones that break the known instances. The same shape one level out: a paged
read is a property over the *whole* list; "page 1 contains it today" is a reading, and the
instrument must carry its own stop condition and host pin, because the page count and the
redirect target are the two things that change without a diff.

## Prevention

- When a plan enumerates the instances a guard must cover, the guard's discovery is a census
  over the file set with a red *unclassified* bucket; the enumeration is the floor. Battery row:
  "a sixth definer that the guard has never seen" must red.
- Every paged API read in a follow-through carries `<host pin, stop condition, page cap>` and a
  harness fixture where the target is on page N > 1 and one where it is absent (the walk must
  *stop*, not exhaust).
- A literal count in prose is a claim without a test: either point at the mechanised floor or
  date it ("N as of #issue") so the next reader knows which tree it measured.

## Session Errors

1. **`lint-infra-no-human-steps.py` flagged "operator" four times in the plan** (plan phase) —
   Recovery: rephrased. — **Prevention:** run the lint on the plan before the deepen pass, not
   after; the four hits were the same sentence shape.
2. **deepen-plan Phase 4.8 PAT halt matched `var.betterstack_api_token`** — a vendor token, not a
   GitHub credential; the halt has no vendor exemption. Recovery: recorded in the plan and
   proceeded. — **Prevention:** routed to `deepen-plan/SKILL.md` §4.8 (this PR): a `var.*_token`
   whose `provider` block is not `github`/`integrations/github` is a recorded false positive, not a
   halt.
3. **The repo-research agent asserted the four unit tags live in Vector Source 4 and that
   `user.crit` is PRIORITY 4** — both wrong (`vector.toml`: Source 2, PRIORITY 0-2; syslog crit =
   2). Recovery: corrected against the file. — **Prevention:** a subagent's claim about a config
   file is verified by reading that file before it reaches the plan (`hr-verify-repo-capability-
   claim-before-assert`).
4. **Touched-shard gate REFUSED (rc=4) twice** — sibling worktrees had full-gate runs in flight
   (#7553 class). Recovery: ran every suite referencing a touched file individually with per-suite
   rc. — **Prevention:** already mechanised; the refusal is the design.
5. **One unreproduced red on the new harness under `CI=1`, case name lost to `tail -1`** — 0/79
   on re-runs. Recovery: recorded as UNRESOLVED in session-state. — **Prevention:** the first run
   of a new suite is captured in full (`> log; RC=$?`), never summarised — the work skill's
   wrapper rule, which I re-derived after the fact.
6. **`git commit` with staged `.ts` queued the full battery behind the advisory lock** (three
   sibling full-gate runs). Recovery: killed my own parked tree (verified by `/proc/<pid>/cwd`),
   committed with `LEFTHOOK=0`, ran gitleaks + the scheduled-show-full-output lint by hand, twice.
   — **Prevention:** stage `.ts` and `.sh` in separate commits when siblings hold the lock, or
   wait; `LEFTHOOK=0` only with the skipped linters run by hand and named in the commit.
7. **Monitor script `${done_$s:-}` bad substitution** — exited 1 immediately; nothing lost.
   — **Prevention:** `bash -n` a polling script before backgrounding it.
8. **Plugin-root env unset at session start** → `cleanup-merged` run by hand. — **Prevention:**
   the go skill's `SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified` branch already
   names it; run the manager from the repo path when it prints.
9. **`terraform providers lock -platform=…` added two stray `h1:` hashes for the existing github
   provider; `terraform providers schema -json` fails in the real root** — Recovery: reverted the
   stray lines; pinned the provider in a scratch root for the schema read. — **Prevention:** after
   `providers lock`, diff the lockfile and keep only the new provider's block.
10. **Push rejected non-fast-forward after the rebase** — the remote held only the planning
    commits, already in history. Recovery: `--force-with-lease`. — **Prevention:** rebase, then
    push with `--force-with-lease` in the same step; never a bare `--force`.
11. **Instruments built from the plan's enumeration** (the three defects above) plus harness
    fixture defects the review found: a `none` fixture that ignored the stop epoch (a 25-page walk
    never stopped), a foreign-incident fixture outside the window (the exclusion arm proved
    nothing), `tr '\n"'` leaving a trailing space; battery M14 attribution order, an escaped
    `\"PRIORITY\"` regex, backticks inside double-quoted labels (command substitution). Recovery:
    all fixed in the review commits. — **Prevention:** the Prevention bullets above; and every
    negative-control fixture is placed *inside* the window the positive control uses.
12. **Seven prose sites carried 15/16 after the branch made it 17.** Recovery: the sweep in
    813e3a147, grepping the *subject* ("provisioners", "SSH-delivered", `terraform_data`) repo-wide
    rather than the number. — **Prevention:** Prevention bullet 3; the parity test's floor is the
    only count that is a measurement.
13. **Ran `lint-infra-no-human-steps.py` whole-tree (518 pre-existing hits) before reading how CI
    invokes it (`--changed --base`); guessed two lint script names (rc=127).** — **Prevention:**
    `grep -n '<lint>' .github/workflows/*.yml` and `ls scripts/ | grep` before running a lint by
    hand.
14. **Two stop-hook rejections: the turn ended while waiting on a subagent without
    `<stop>BLOCKED: …</stop>`.** — **Prevention:** a turn that ends waiting carries the marker;
    closing text never names an action not yet taken.

## Related

- ADR-218 — native Better Stack Logs alerts are Terraform-managed via the logtail provider
- `knowledge-base/project/learnings/2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md`
  — a prefix pin is not the property; same shape, argv instead of a name list
- `knowledge-base/project/learnings/2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md`
  — fix applied to the instance, not the class
- `knowledge-base/project/learnings/2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`
  — a count sweep bounded by the diff's file list
- #8124 (`logtail_source` token not marked Sensitive), #8125 (SSH host-key pinning) — deferred
