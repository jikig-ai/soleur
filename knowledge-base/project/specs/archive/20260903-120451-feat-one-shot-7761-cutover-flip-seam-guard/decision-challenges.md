# Decision Challenges — feat-one-shot-7761-cutover-flip-seam-guard

Recorded by `plan-review` in headless mode. Each entry argues that a direction the issue or the task
brief stated should change. None was auto-applied; the plan carries the stated direction as its
default and these are surfaced for the operator.

---

## UC1 — Three reviewers argue the in-script seam gate should be cut entirely

**The stated direction.** Issue #7761 proposes: *"Gate the seams on a shape `doppler run` cannot
supply — require an explicit fixture marker that is not a Doppler secret… A name-shape guard is
enough."* The plan implements this as mechanism M1.

**The challenge.** DHH, `code-simplicity-reviewer` and (by implication) CPO independently argued M1
is strictly dominated by M2 (`doppler run --only-secrets` on the unit) and should be deleted:

- There is exactly **one** production caller of the script (`inngest-cutover-flip.service:54`);
  every other reference is a test harness, a comment, or the install path. So M1's coverage is a
  strict subset of M2's on the only path that exists.
- M1 structurally **cannot** reach `BASH_ENV`, `PATH`, `LD_PRELOAD` or `IFS` — the plan concedes
  this. M2 closes all of them, because it filters before `exec`.
- M1's last remaining justification, "a refactor could delete `--only-secrets` from the unit file",
  is exactly what Guard 2's mutation row 1 asserts. The plan ships that guard anyway.
- M1 is the only mechanism that puts new code inside the destructive FSM, in the window before its
  ERR trap is installed.

**Why the plan nevertheless keeps it.** The reviewers' objections were aimed largely at the
*sentinel-file* implementation, which the plan has since replaced with an argv check
(`--fixture-seams`). After that reshape M1 costs roughly fifteen lines plus four one-argument
call-site edits — no sentinel, no `PATH` shadowing, no new suite, no pre-trap filesystem work, and
no change to any of the 147 existing assertions. At that price, defence that travels with the file
against a root-exec primitive on a destructive path is cheap enough to keep.

**Operator decision.** Keep M1 in its argv form (the plan's default), or cut it and ship M2 + M3 +
Guard 2 alone.

---

## UC2 — Split the four sibling units out of this PR

**The stated direction.** The task brief asked: *"Sweep for other `doppler run`-wrapped units whose
scripts exec environment-supplied command seams; if any exist, the fix should cover them
consistently."* Four exist. The plan's original Phase 6 fixed them here.

**The challenge.** DHH, CPO and `architecture-strategist` all argued for splitting, on grounds the
plan now accepts and records:

- The rollout phase dispatches `apply_target=inngest-host` and delivers **none** of the four. They
  install via `soleur-host-bootstrap.sh` (web hosts) and `cloud-init-git-data.yml`. They would merge
  green and sit undeployed indefinitely — web-1 carries `lifecycle{ignore_changes=[user_data]}` and
  has never re-run cloud-init. That reproduces inside this PR the exact failure mode the rollout
  phase exists to prevent.
- Their secret lists are genuinely hard to author correctly, and two independent exhaustive
  derivations disagreed on the same two scripts. Under `--no-exit-on-missing-only-secrets` a wrong
  list is silent — and one of the misses would disable a LUKS-passphrase redactor, shipping the
  passphrase to Sentry and Better Stack.

**Plan disposition.** Split, with a follow-up issue. The follow-up is high value rather than
housekeeping: `git-data-gc.service` currently injects ~129 inherited secrets, including
`SUPABASE_SERVICE_ROLE_KEY`, into the host holding every connected user's source code.

**Operator decision.** Accept the split, or require the siblings in this PR.

---

## UC3 — The brand-survival threshold ladder is inverted

**The challenge (CPO).** By the ladder's own definition this exposure is `aggregate pattern`: a
`FLUSHALL` destroys in-flight jobs for every tenant, and the email payloads belong to correspondents
who are not Soleur users. The tenant count being one today is an adoption-stage accident.

But `single-user incident` requires CPO sign-off, fires `user-impact-reviewer` at review, and blocks
`gh pr ready` on a degraded review — while `aggregate pattern` fires **none** of the three.
Relabelling upward would buy strictly weaker enforcement.

**Plan disposition.** Keep the `single-user incident` label, and file a follow-up so
`aggregate pattern`'s gates become a superset rather than a subset. This is a defect in the shared
ladder, not in this plan.

**Operator decision.** Confirm the follow-up is worth filing.

---

## UC4 — The PR does not close the issue at merge

**The stated direction.** The task brief's deliverable is *"merged PR closing #7761."*

**The challenge.** The merge does not deliver the fix. The script and unit reach the host only
through an image build and a host replace that necessarily run *after* the tag is on `main`. A
`Closes #7761` would auto-close the issue at merge, before the remediation ran — a false-resolved
state, and the exact anti-pattern the ops-remediation convention names.

**Plan disposition.** The PR body carries `Ref #7761`, and the issue is closed by an explicit step
once the post-replace probe passes. The issue does get closed; it is simply not closed *by* the
merge.

**Operator decision.** Accept, or require `Closes` and accept the window of false resolution.
