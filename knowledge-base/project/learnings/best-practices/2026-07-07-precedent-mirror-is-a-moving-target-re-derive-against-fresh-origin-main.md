---
title: A "1:1 precedent mirror" is a moving target — re-derive the precedent against fresh origin/main at review time
date: 2026-07-07
category: best-practices
tags: [terraform, doppler, precedent-mirror, merge-base, sibling-pr, review, infra]
issue: 6178
pr: 6180
related_learnings:
  - 2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md
  - 2026-06-30-migration-number-collision-mid-pipeline.md
  - 2026-06-14-all-members-drift-guard-must-rebase-before-ship.md
  - 2026-05-20-rebase-before-applying-agents-md-plan-edits.md
---

# A "1:1 precedent mirror" is a moving target — re-derive against fresh origin/main

## Problem

`inngest-host.tf` was authored by mirroring `zot-registry.tf` "1:1" (its own header comment
says so). The mirror was faithful **to the precedent as it existed at the branch's merge-base**.
But a sibling PR (#6189, commit `f0241a2bc`, "zero-operator zot provisioning — add
doppler_environment") had landed on `origin/main` *after* that merge-base, adding a
**load-bearing** `resource "doppler_environment" "registry_prd"` and switching every isolated-
project secret's `config` from the literal `"prd"` to `doppler_environment.registry_prd.slug`.

Reason it's load-bearing: a TF-created `doppler_project` is created **BARE** — Doppler does NOT
auto-add a `prd` config. Without the `doppler_environment` resource, the secrets' `config = "prd"`
fail at the operator's first apply with `Doppler Error: Could not find requested config 'prd'`.

So the "1:1 mirror" reproduced the **pre-fix** shape and silently inherited the exact bug #6189
had just fixed in the precedent. `terraform validate` passed (it doesn't resolve Doppler configs);
the drift-guard test only asserted the *project* exists, not the environment. The apply-blocker
was invisible to every local gate — caught only at multi-agent review by the `pattern-recognition`
and `code-quality` agents, both of which had been prompted to **`git fetch origin main` and
re-derive the diff against fresh origin/main**.

## Solution

Add the missing `doppler_environment.inngest_prd` (slug `prd`) and repoint all 5 isolated-project
resources' `config` to `doppler_environment.inngest_prd.slug` — forcing both the create-ordering
dependency edge and the config's existence. Then add the new resource to the parity test's
`OPERATOR_APPLIED_EXCLUSIONS` + the `apply_target=inngest-host` dispatch `-target` set (a net-new
managed resource must be covered or the parity guard fails).

## Key Insight

**A precedent file is not a snapshot — it is a moving target.** "Mirror precedent X 1:1" is only
correct against `X @ origin/main HEAD`, never against `X @ your-merge-base`. Sibling PRs land
FIXES to the precedent (a new load-bearing resource, a guard, an ordering edge) between when you
branch and when you review; a mirror authored at merge-base inherits every pre-fix bug.

This is the **content-fidelity** sibling of the number-space collisions already documented
(ADR-ordinal — [[2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains]]; migration
number — [[2026-06-30-migration-number-collision-mid-pipeline]]). Same root cause (concurrent
sibling PRs invalidate a merge-base assumption), different axis: those are about *which number is
free*, this is about *whether your copy still matches the thing it claims to copy*.

**Prevention (cheap, review-time):** whenever a PR authors a file whose comment claims to mirror a
precedent (`grep -l "mirror.*\.tf\|1:1"`), or more generally on any precedent-cloned infra file,
`git fetch origin main && git log <merge-base>..origin/main -- <precedent-file>` (or `git diff
<merge-base> origin/main -- <precedent-file>`). If the precedent changed since the merge-base,
diff your mirror against the precedent's *current* HEAD shape and confirm every load-bearing
addition is carried forward. The review skill's `code-quality`/`pattern-recognition` spawn prompts
already say "re-derive against fresh origin/main" — this is exactly the catch it's for; make the
precedent-file re-diff an explicit step for any "mirrors X" PR.

## Session Errors (this session)

- **Precedent-mirror inherited a pre-fix bug (this learning).** Recovery: added
  `doppler_environment.inngest_prd` + repointed configs at review. Prevention: re-derive the
  precedent against fresh origin/main HEAD, not the merge-base, for any "mirrors X" file.
- **ADR-098 ordinal collision** (sibling #6181 merged ADR-098 after the session-start rebase).
  Recovery: renumbered mine to ADR-100 across 12 files. Prevention: already documented —
  [[2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains]]; re-check the next-free
  ADR number at review/ship time, never trust the plan-quoted number.
- **IaC-routing hook false-positives on out-of-band-secret documentation.** Editing plan/tasks
  prose describing the sanctioned non-TF-minted `INNGEST_POSTGRES_URI`/`INNGEST_HEARTBEAT_URL`
  out-of-band pattern (an established `inngest.tf` doctrine) tripped `hr-all-infrastructure-
  provisioning-servers`. Recovery: the `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` comment
  is the sanctioned escape; for pure checkbox flips, change only the marker char (reuse already-
  passing text). Prevention: one-off workaround exists; low-value to retune the hook.
- **ci-deploy.test.sh timed out at 300s** (heavy suite, runner speed — not a failure). A
  backgrounded `bash cmd > log; echo EXIT=$?` reported the trailing echo's exit while ci-deploy
  inside hit exit 124. Recovery: re-ran at 560s → 110/0; verified the real log (2 "FAIL" strings
  were inside PASS-line descriptions). Prevention: already documented — a bg "exit 0" is not proof;
  grep the runner's own summary.
- **Plan not at the given relative path** (bare-root CWD vs worktree). One-off — the plan lived in
  the worktree; `cd` into `.worktrees/<branch>` resolved it.
