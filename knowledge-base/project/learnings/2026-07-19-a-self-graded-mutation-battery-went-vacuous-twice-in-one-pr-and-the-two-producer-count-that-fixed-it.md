---
module: apps/web-platform/infra/{workspaces-cutover.sh,workspaces-luks-staging.test.sh}
date: 2026-07-19
problem_type: test_failure
component: shell_script
symptoms:
  - "cutover luksFormat'd + luksOpen'd but never mkfs'd, so `mount \"$MAPPER\" \"$STAGING\"` failed and was swallowed under `set -uo pipefail` with no -e"
  - "8 users' sole-copy source rsynced onto a plain directory on the ROOT DISK while every gate reported success"
  - "a 16-mutation battery reporting all-RED and 73 passing cases stayed 73/0 GREEN when an INDEPENDENT reviewer deleted the staging positive control outright"
  - "after that fix, the suite stayed 73/0 GREEN when the fail-closed staging mount — the PR's own title — was replaced with `|| true`"
  - "a plan-asserted 'no .tf touched so the infra apply won't fire' was false; the filter is directory-scoped and five .sh files triggered a live prod terraform apply"
root_cause: self_graded_mutation_battery_and_single_derived_set_quantifier
severity: critical
tags: [luks, cutover, mutation-testing, vacuous-test, self-graded-battery, quantifier-guard, fail-open, swallowed-failure, unattended-path, probe-failure-asymmetry, path-filter, lint-false-positive]
issue: 6588
pr: 6704
synced_to: [review, qa, work]
---

# A self-graded mutation battery went vacuous twice in one PR — and the two-producer count that fixed it

`Ref #6588` / PR #6704 / commit `bec339250`. The P0: `workspaces-cutover.sh` `luksFormat`'d the
device and `luksOpen`'d the mapper but **never ran `mkfs`**. The mapper held no filesystem, so
`mount "$MAPPER" "$STAGING"` failed with `wrong fs type`; under `set -uo pipefail` **with no `-e`**
and an unguarded `mount`, that failure was swallowed, and the whole cutover copied **8 users' sole
copy of their source onto a plain directory on the ROOT DISK** while every gate reported success.
C1 caught it as a single itemize diff — `.d..t...... ./` — because the rsync vocabulary can express
"this file differs" and **cannot** express *"correct copy, wrong target."*

> **Disposition note.** The headline class here is documented — one day earlier, in
> [2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md](./2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md),
> and before that in
> [2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md](./2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md)
> and [2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md](./2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md).
> This file exists for two things those do not carry: the **recurrence measurement** (§1 — the class
> recurred *inside* the PR whose own thesis is "a gate that certifies X must anchor X", one day after
> being written down) and a **mechanical disposition** (§2 — the two-producer count, which is a
> different construct from "mutate more"). §3–§5 are new material.

---

## 1 (PRIMARY) — a self-graded battery measures only the mutations its author imagined

The PR shipped a **16-mutation battery, every mutation RED for its predicted reason**, over
**73 passing cases**. Reported as high confidence. Then, twice:

**Vacuity 1.** An *independent* mutation — delete the staging positive control outright, rather
than perturb it — left the suite **73/0 GREEN**. Nothing in the battery deleted a control, because
the author's mental model of "mutation" was *alter an arm*, never *remove the observer*.

**Vacuity 2.** After that was fixed, a second independent hunt found the suite **also stayed 73/0
GREEN** when the fail-closed staging mount — **the behaviour in the PR's own title** — was replaced
with `|| true`. Root cause: the happy-path fixture pre-satisfied `FINDMNT_STAGING_SRC`, so the
*downstream* mount-source positive control passed whether or not the mount had succeeded. The
run still died — at `source_not_mapper` — so an **rc-only assertion could not see the difference**.

The fix is pinned in-file at the `Tmf` block header in `workspaces-luks-staging.test.sh`
("FINDMNT_STAGING_SRC is deliberately NOT pre-satisfied here … The REASON is therefore the
load-bearing assertion, not the rc"), and asserted by `Tmfb`, which requires
`reason=mount_failed` and **not** the downstream `source_not_mapper`.

**Twice in one PR, a suite could not fail on the guard it existed to protect.** Note the recursion:
this happened inside the change whose entire thesis is that a gate must anchor the thing it names.

**Falsifiable tell, cheap to run:** when a fail-closure is guarded only by "the run dies", ask
*which* assertion dies. If a downstream control already dies for its own reason, the upstream gate
is unobserved. **Assert the reason, never the rc.** And: a battery graded by its own author is
evidence about the author's imagination, not about the suite — the only mutation that counts is one
chosen by someone who did not write the assertions.

## 2 — the durable fix is a quantifier over TWO INDEPENDENT producers, not a set-difference over one

The obvious guard — derive the arm set from the SUT, diff against the arms the suite exercised — is
structurally incapable of catching a **deleted** arm. Deleting a producer removes it from the
DERIVED set and the OBSERVED set *simultaneously*, so `comm -23` stays empty. **The guard goes
blind exactly when it should fire**, and shrinks silently in lockstep with the SUT.

`TQ1a` in `workspaces-luks-staging.test.sh` fixes this by counting **two independent producers**
against each other inside `prepare_staging_target`'s function body:

```bash
N_FAIL_ARMS="$(grep -cE '^ *emit_staging_target fail ' "$PSTBODY" || true)"
N_FN_DRIFT="$(grep -cE '^ *emit_drift staging_'        "$PSTBODY" || true)"
```

Every fail arm is paired 1:1 with an `emit_drift staging_*`. Delete a marker and the drift call
stays, so the counts diverge by exactly one — an **exact count diff**, not a silent shrink. A floor
check (`-lt 5`) fails the block loudly if the extraction itself breaks, so "un-run" cannot read as
"green".

It proved itself immediately: it **flagged two arms added by concurrent SUT fixes as uncovered**,
before any human noticed them.

**Generalize:** a coverage guard whose oracle is derived from the artifact it guards must count a
*second, independent* producer of the same fact. One derived set is self-referential, and
self-reference is exactly the blindness in §1.

## 3 — when you fix a swallowed failure, sweep EVERY site running that teardown, especially the unattended one

The pre-PR repoint path had `umount "$STAGING" 2>/dev/null || true`. The fix made it fail loud:

```bash
umount "$STAGING" || { emit_drift staging_umount_failed; die "cannot umount $STAGING before the repoint …"; }
```

`rollback()` also gained a `$STAGING` umount before its `cryptsetup close`. But
**`arm_dead_man()`'s `systemd-run` command — the only restore path that runs when nobody is
watching — originally carried the identical gap**, and was fully silenced (`cryptsetup close
${MAPPER_NAME} 2>/dev/null`, no staging umount at all).

<!-- lint-infra-ignore start: retrospective incident analysis. The paragraph below describes what
     the failure mode WOULD have done to an unattended host in order to explain why the dead-man
     arm was fixed. It prescribes no step to anybody; the fix is in the merged script. -->

Consequence had it shipped: an abort mid-freeze with a dropped SSH session leaves a mapper open and
mounted at `$STAGING` — a **complete DECRYPTED copy of every user's source, live indefinitely, with
zero telemetry**. The next run's stray-directory guard does not surface it, because `$STAGING` is
then a *mountpoint*, not a stray directory.

<!-- lint-infra-ignore end -->

**Two orthogonal review agents converged on this independently.** Both fixes are in `bec339250`;
the dead-man arm now umounts `$STAGING` and emits a `reason=mapper_close_failed` logger marker on a
failed close, anchored by the in-file comment *"umount ${STAGING} BEFORE the close, in lockstep with
rollback()"*.

**Rule:** a swallowed-failure fix is not done at the first call site. `grep` for every site running
that teardown *sequence* — and fix the unattended copies first, because those are the ones with no
observer to notice.

## 4 — a failed probe is not proof of absence, and the asymmetry survives into the destructive arm

`blkid … || true` collapsed **rc 4 (usage), rc 8 (ambivalent), ENOENT, EACCES, EIO, and
blkid-simply-absent-from-PATH** all into `fs_type=""` — which selects the **`mkfs` arm**. Only
**rc=2** means "no filesystem." Concrete loss: a prior run completes the hours-long bulk copy, the
next run's probe fails for any of those reasons, and `mkfs` runs over the complete good copy.

The merged guard is three-armed and total: an explicit `command -v blkid` check
(`emit_staging_target fail blkid_absent`), an rc allowlist of exactly `{0,2}`
(`emit_staging_target fail blkid_probe_failed`), and `-p` to force a low-level superblock probe
that bypasses the `/run/blkid/blkid.tab` cache — a stale cached entry is as dangerous as a failed
probe when one arm destroys and another refuses.

<!-- lint-infra-ignore start: retrospective incident analysis. The paragraph below is advice to the
     agent about auditing probe arms in source, not a prescribed operator infra step; the sentinel
     reads "verify"/"sweep" next to an actor pronoun and cannot tell the two apart. -->

**The knowledge was already in this file.** The same script's G4 assert already named this exact
asymmetry — *"reads 'the probe failed' as 'the mount is clean'"*. It had been applied to the
**safe** arm and not to the **destructive** one. When you write down a probe-failure asymmetry,
sweep the destructive arms in the same file before you close the tab; those are where the
asymmetry costs data rather than a retry.

<!-- lint-infra-ignore end -->

## 5 — two smaller findings, each falsifiable

**5a — a path filter is directory-scoped, not extension-scoped.** The plan asserted "no `.tf` files
touched, so the infra apply won't fire." False. `.github/workflows/apply-web-platform-infra.yml`
filters on `"apps/web-platform/infra/**"` — a **directory** glob. Five `.sh` files under that
directory triggered a **live prod terraform apply**. Outcome was benign (0 added / 0 changed / 0
destroyed), but the claim was wrong, and "benign this time" is not the property the plan asserted.
**Read the filter; never infer it from the file extensions in your diff.**

**5b — the infra lint reliably false-positives on retrospective incident analysis.** The
human-actor + infra-imperative co-occurrence model in `scripts/lint-infra-no-human-steps.py` cannot
distinguish *"a human must run X"* (the bug it exists to catch) from *"a human ran X, and here is
why that was the failure"* — because a post-mortem **must** describe operator actions to explain
what went wrong. This plan drew **10 hits, all analytical prose**; one landed on a sentence stating
that the freeze must **NOT** be triggered. The disposition is the documented one: a **scoped**
`lint-infra-ignore start` … `end` HTML-comment region carrying a reason string (never a file-wide
carve, and never a rewrite that blunts the analysis). This file uses two, in §3 and §4.

A second-order trap worth its own line: the marker is recognised **only** as an HTML comment, and
the recogniser does not care that it sits in explanatory prose. Writing the literal opening comment
inside a sentence *about* the mechanism opened a real region and made this very file fail
**fail-closed** with `unterminated … region`. When documenting a comment-delimited carve-out,
render the marker as inline code without the comment delimiters, as above.

## Files

- `apps/web-platform/infra/workspaces-cutover.sh` — `prepare_staging_target()` (mkfs guard, three-arm
  blkid guard, `emit_staging_target` arms), `rollback()`, `arm_dead_man()`, the repoint umount.
- `apps/web-platform/infra/workspaces-luks-staging.test.sh` — `Tmf`/`Tmfb`/`Tmfc` (staging mount
  fail-closure), `TQ0`/`TQ1`/`TQ1a` (arm-coverage quantifier).
- `.github/workflows/apply-web-platform-infra.yml` — the directory-scoped `paths:` filter (§5a).
- `scripts/lint-infra-no-human-steps.py` — the co-occurrence sentinel and its ignore-region contract (§5b).
