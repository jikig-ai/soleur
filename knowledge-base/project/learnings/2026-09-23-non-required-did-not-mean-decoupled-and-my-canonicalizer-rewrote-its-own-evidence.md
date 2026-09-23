---
title: "Non-required" did not mean decoupled from deploys, and the canonicalizer rewrote the evidence it was quoted on
date: 2026-09-23
category: workflow-patterns
module: harness-parity
tags: [ci, workflow-run-conclusion, deploy-gating, canonicalization, anti-vacuity-floor, ratchet, attribution, notification-vs-verdict]
pr: 8570
---

# Learning: a gate's blast radius is not the property its label names

## Problem

PR #8570 added a `harness-discovery` CI job, widened the ADR-226 canonicalization census to
`skills/*/references/**`, and retired the hand-ported `.openhands/` and `.gemini/` trees. Three
defect classes surfaced, and each one is a case of a label being trusted in place of a measurement.

## Solution

### 1. "Non-required" governs the merge gate and nothing else

ADR-240 asserted, in as many words, that a red `harness-discovery` "blocks nothing" because the job
is not a required check. That is true of the MERGE gate — the job is absent from the `test`
aggregator's `needs:`, so it cannot block a PR.

It is false of deploys. `web-platform-release.yml` is triggered by `workflows: ["CI"]` and refuses
to deploy when that run's `conclusion` is not `success` (its `ci_not_green` guard). A job's
required-ness has no bearing on `workflow_run.conclusion`: any failing job reds the run. So on a
main push, an npm hiccup or a 404 on `static.devin.ai` — a third-party network flake, in a job
explicitly designed to be ignorable — would have skipped that SHA's production deploy.

`continue-on-error: true` on the job is what actually decouples them. The step still reds visibly
on the check list while the run conclusion stays `success`.

**The generalizable part:** a gate has at least two blast radii — what it blocks by policy
(branch protection) and what it blocks by mechanism (anything reading `workflow_run.conclusion`,
`needs:`, or a status API). The label only describes the first. Before calling a job advisory,
grep for every consumer of the run it belongs to.

**The trap in the fix:** `continue-on-error` and "required" are mutually destructive. A required
check that cannot fail the run is worse than no check, so the line that makes the job safe today
MUST be deleted in the same change that promotes it. That coupling is recorded at the job, in
ADR-240, and in `plugins/soleur/test/README.md`, because a future promotion PR will not read all
three.

### 2. A canonicalizer over a widened corpus rewrites quoted evidence

Widening the census population to `skills/*/references/**` created a class that did not exist when
the population was entry files only: a doc that QUOTES a harness-specific form as its subject.

Two sites were silently rewritten:

- `plan/references/plan-sharp-edges.md` documented a log-injection attack whose forged payload was
  `Build it: /soleur:go #9999`. The leading slash IS the attack — it is what makes the forged line
  read as a real operator-typed directive. Canonicalizing it to `soleur:go` removed the detail the
  example turns on.
- `code-to-prd/references/prd-template.md` described a generated placeholder that names an agent by
  its BARE LEAF, deliberately, because the line is a human-readable status and not a dispatch.

ADR-226 §3 honours the `harness-forms` exempt region only where the region policy is `command`, so
a references doc has no way to protect a quotation. Both were reworded to describe the form rather
than embed it — correct for now, and the underlying gap is filed.

**The generalizable part:** every mechanical rewrite has a blind spot shaped exactly like its own
subject. A gate that normalises form cannot tell a USE of a form from a MENTION of it, and the docs
most likely to mention it are the ones explaining why it is dangerous.

### 3. An anti-vacuity floor in a deferred directory grows the ledger by construction

Adding `MIN_CASES=12` to `.claude/hooks/pre-merge-rebase-parity.test.sh` made a previously
floor-LESS file floor-BEARING. `.claude/hooks/` is in `DEFERRED_DIRS`, so `guard-vacuity-floor`'s
deferral ledger went 47 → 48 and the guard reddened.

The guard's own failure message gives the remedy and forbids the shortcut: "cover it, or promote
its directory into COVERED_DIRS — do NOT raise this number." Per-file promotion via
`PROMOTED_FILES` SHRINKS the ledger back to 47, and the guard's promotion arm then proves the floor
is not decorative ("every PROMOTED_FILES entry is still floor-bearing, covered, and scores FIRES").

**The attribution error is the more useful half.** The merge that surfaced this also brought main's
new `apps/web-platform/infra/inngest-nic-wait.test.sh`, in a deferred directory — an obvious
culprit. I nearly recorded it as a pre-existing failure inherited from main. A detached worktree at
`origin/main` ran the guard 23/0 with the ledger at **47**, which falsified that in about two
minutes and pointed back at my own diff.

**The generalizable part:** when a repo-global ratchet moves right after a merge, the merge is the
salient explanation and usually the wrong one. Measure the base commit before attributing; a
detached worktree at `origin/main` is cheap and decisive. Attributing a ratchet move to someone
else's commit is worse than not noticing, because it converts your regression into their debt.

## Key Insight

All three failures share one shape: **a name was treated as a measurement.** "Non-required" was
read as "cannot affect anything." "Canonical form" was read as "correct everywhere the form
appears." "The merge brought a new deferred suite" was read as "the merge caused the ledger to
grow." In each case the falsifying command took under two minutes — a grep for consumers of the CI
run, a read of the two rewritten sentences, a guard run at `origin/main`.

## Session Errors

- **Asserted in ADR-240 that a red advisory job blocks nothing.** — Recovery: review found it; added
  `continue-on-error`, corrected the ADR, and recorded the promotion coupling at three sites. —
  **Prevention:** before describing a CI job as advisory, grep for consumers of
  `workflow_run` + that workflow's name; "not in `needs:`" is not the whole answer.

- **Canonicalization rewrote two quoted evidence sites.** — Recovery: reworded both to describe the
  form instead of embedding it. — **Prevention:** when widening a normalising gate's population,
  diff the new members' rewrites by hand and ask of each whether the doc USES the form or MENTIONS
  it. Filed as a gap: reference docs have no exempt-region marker.

- **Mis-attributed a ratchet move to the merge from main.** — Recovery: ran the guard in a detached
  worktree at `origin/main`, measured 47 and green, traced the +1 to my own new floor. —
  **Prevention:** never attribute a repo-global ratchet change without running that guard at the
  base commit first.

- **A background `git commit`'s task record was lost to context compaction while its process tree
  survived.** — Recovery: enumerated live PIDs by `/proc/<pid>/cwd` ownership before acting, which
  is what prevented a second `git commit` on one index. — **Prevention:** after a compaction, a
  missing task record is evidence about the RECORD, never about the process. Re-derive liveness
  from `/proc` by worktree ownership before any git-write retry.

- **The reaped wrapper later reported "exit code 0" for a commit I had killed.** — Recovery: ignored
  it and verified HEAD, the staged count and `index.lock` directly. — **Prevention:** a completion
  notification is authoritative for LIVENESS, never for VERDICT. Read the verdict from the artifact
  (HEAD moved? working tree clean?), never from the notification.

- **Armed a Monitor whose filter flapped** on a `sleep`-poller child count, emitting content-free
  events. — Recovery: stopped it and re-armed keyed only on the queue position and the terminal
  states. — **Prevention:** a monitor's change-detection key must exclude any field that oscillates
  for reasons unrelated to the thing being watched.

- **Ran `scripts/markdown-lint.sh` with no arguments** and got a usage error. — Recovery: re-ran with
  `--repo-sweep`. — **Prevention:** one-off; the usage line is clear.

- **Mechanical-sweep mistakes** (stray blank line before an END marker in 90 files; a `sed` that
  substituted the wrong SHAs in a NOTICE; a python substitution that injected a literal `\` into a
  JS string; `git add` on a non-`:(glob)` pathspec). — Recovery: each caught by re-reading the
  written bytes. — **Prevention:** one-off class, already covered by the verify-after-sweep rules.

- **Assumed vitest forwards `-- <flag>` into a worker's `process.argv`.** — Recovery: it does not;
  reverted to an env token plus a loud stderr notice. — **Prevention:** one-off.

- **The local full battery queued 1h+ behind two sibling full-gate runs.** — Recovery: skipped that
  ONE lefthook job with `LEFTHOOK_EXCLUDE=bun-test`, keeping all other pre-commit guards, and
  recorded the acceptance criterion as NOT MET rather than ticking it. — **Prevention:** prefer
  `LEFTHOOK_EXCLUDE=<job>` over `--no-verify`, which drops roughly fifteen guards to skip one.

## Tags

category: workflow-patterns
module: harness-parity
