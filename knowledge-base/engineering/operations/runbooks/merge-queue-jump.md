# Merge-queue jump runbook

> Moves an urgent PR to the head of the `main` merge queue via
> `scripts/merge-queue-jump.sh` (GraphQL `enqueuePullRequest(jump: true)`).
> Deliberate middle tier between waiting serially and `gh pr merge --admin`.
> Issue: #11678 · Governing record: ADR-270 (jump-path addendum).

## Urgency bar

Jump only when the PR's merge is time-critical **and** the serial wait is the
load-bearing delay:

- prod-down / user-visible breakage with the fix ready
- security fix whose exposure window matters
- data-loss / corruption remediation

Not for routine haste. A jump **rebuilds every in-progress queue entry**
(each queued PR re-verifies against the new ordering — ~45–50 min of runner
time per in-flight entry), so a casual jump taxes the very queue it skips.
If you are the only entry in the queue, a jump buys nothing.

## The tiered model (pick the narrowest sufficient act)

| Tier | Command | Gate kept? | Use when |
|---|---|---|---|
| Queue | `gh pr merge N --squash --auto` | full | default — every routine PR |
| **Jump** | `scripts/merge-queue-jump.sh N --reason "…" --yes` | full (integrated merge-queue checks) | urgent PR behind others |
| Admin merge | `gh pr merge N --squash --admin` | **none** — bypasses required checks | queue itself is broken (ADR-270 §Wedge) |

A jump keeps the integrated merge-queue verification path; `--admin` does not.
Never reach for `--admin` for speed — it is the wedge-escape tool, and its use
lands on the CLO's designed-exception ledger with an attribution comment.

## How to jump

```bash
scripts/merge-queue-jump.sh <pr-number> --reason "prod-down: checkout 500s" [--yes]
```

- `--reason` is required — it is the deliberate-act record and is posted
  verbatim on the PR as the attribution comment.
- Interactive (TTY): you'll type `jump` to confirm after the script prints
  the in-flight entry count. Non-TTY (scripts, agents): `--yes` is required —
  a bare non-interactive run refuses.
- Already merged? The script exits 0 — nothing to do.
- Armed but not yet enqueued (auto-merge set, GitHub's enqueue lag): the
  jump enqueues at the front directly.
- **Never-armed**: refused — run `gh pr merge N --squash --auto` first.
- The script re-reads `headRefOid` + entry state after confirmation; a push
  in the gap rejects with a stale-head error — re-run to pin the new head.
- Exit 3 = the jump succeeded but the attribution comment failed to post:
  record `actor: reason` on the PR by hand — the jump is already live.

## Cost and blast radius

- Every entry in flight rebuilds from the front on a jump. The script prints
  the count before you confirm; multiply by ~50 min of runner time to price it.
- Under `max_entries_to_merge = 3` (grouped merging), a jumped PR inserts at
  position 1 and joins the next group boundary — it does not split an
  in-flight `merge_group` build.
- The CLA synthetic's coverage is unaffected: it verifies the candidate's
  `merge_group` checks, which re-run for the jumped entry like any other.

## Manual dequeue + re-enqueue (only if the mutation is rejected)

Prefer the script's single-mutation path. If `enqueuePullRequest` is rejected
(permission, schema drift), the manual fallback — admin UI "Jump the queue"
toggle on the PR page — exists but has the same rebuild cost.

A manual `dequeuePullRequest` + re-enqueue emits a
`RemovedFromMergeQueueEvent`: concurrent `--queue-state` watchers
(`monitor-pr-checks.sh`, `drain-prs`) read it as a REAL dequeue and can fire
their one-re-enqueue recipe, racing your jump. **Before any manual dequeue,
fence live watchers**: close other ship/drain sessions, or accept that the
queue order may be re-arranged by a tail re-enqueue (~2–3.5 min after removal,
per the measured auto re-queue).

## Re-evaluation trigger (deferred capability)

If jump cadence becomes routine (more than ~1/week sustained), file the
label-triggered workflow as a follow-up — it needs the soleur-infra App token
mint (`hr-github-app-auth-not-pat`, ADR-241 G7f registration) and a
labeler-authorization gate; ADR-285 shows `github-actions[bot]`-armed
enqueues get zero `merge_group` runs, so the workflow must mint the App token,
never `GITHUB_TOKEN`.

## Auth

The script runs under your own `gh auth login` scopes (contents + pull-requests
write — the same authority the UI toggle needs). No new credential surface.
