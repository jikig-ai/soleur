---
title: "My guard was green with its property inverted, and three claims I published were false"
date: 2026-08-13
category: test-failures
module: apps/web-platform/infra
issues: [7462, 7228, 6500, 7516]
tags: [guards, mutation-testing, terraform, cloud-init, false-claims, review]
---

# Learning: a guard can be 117/117 green with the property it names inverted

## Problem

PR #7516 gave the dedicated inngest host a zot-primary bootstrap pull arm, with a 39-assertion
guard and a 9-case mutation battery built specifically to prove the guard could fail. Both were
green. An 8-agent review panel then found that **one character** defeated both.

## The headline

```diff
# apps/web-platform/infra/cloud-init-inngest.yml, the resolution region's gate
-    if [ -n "$ZOT_EP" ]; then
+    if [ -z "$ZOT_EP" ]; then
       ZIREF="$ZOT_EP/jikig-ai/soleur-inngest-bootstrap:v1.1.24@sha256:6cdaa..."
```

The zot leg is now attempted **only when no endpoint is baked**, and skipped exactly when zot is
configured. Every property the PR claims is inverted. Result: guard **117/117 rc 0**, battery
**9/9 mutants killed rc 0**. The battery did not merely miss it — it *certified* it, because its
baseline passed and all nine rows still killed.

Cause: the assertion was `grep -qE '\[ -n "\$ZOT_EP" \]' <whole file>`. That token occurs
**three** times (docker daemon config, zot login, ref resolution). Inverting the one that gates
the arm left the other two matching. The assertion pinned *that a token existed somewhere*,
never *that the branch it controls has the right sense*.

**Fix:** anchor positionally to the gate that guards the arm.

```bash
ZG_ARM_GATE="$(grep -B2 '^[[:space:]]*ZIREF=' "$DED_CODE_FILE" | grep -E '^[[:space:]]*if \[' | tail -1 || true)"
assert "the gate was FOUND (an unmatched gate must not pass vacuously)" "[[ -n \"\$ZG_ARM_GATE\" ]]"
assert "that gate is a NON-EMPTY test"  "grep -qE '\[ -n \"\\\$ZOT_EP\" \]' <<<\"\$ZG_ARM_GATE\""
```

Mutation-proven: the same inversion now reds.

## Four more defects in the guard itself

### 1. The battery's attribution matched PASS lines

```bash
if ! grep -qF "$expect" "$log"; then   # MISROUTED
```

`assert()` echoes `PASS: $description` **and** `FAIL: $description`. Every row's `$expect` was a
prefix of an assertion *description*, so it was present in the log whether that assertion passed
or failed. Measured: neutering each row's named assertion to `true` left **7 of 9 rows still
reporting KILLED**, and one row was misrouting on the *unmutated* tree. Fix: `grep -E '^  FAIL'
"$log" | grep -qF "$expect"`.

**"9/9 killed" was measuring the guard's exit code, not the named assertion.** That number was
published in the PR body and a commit message before it meant anything.

### 2. The comment strip destroyed executable code

`sed -E 's/#.*$//'` was applied to a file whose redaction expressions use `#` as **sed's own
delimiter**:

```
detail="$(printf '%s' "$detail" | sed -E 's#(://[^:@/]+:)[^@]+(@)#\1REDACTED\2#g; …
                              ->  detail="$(printf '%s' "$detail" | sed -E 's
```

The phone-home's and `inngest-redact.sh`'s **entire scrub patterns** were deleted from what every
assertion reads. Fix: strip full-line comments only (`s/^[[:space:]]*#.*$//`), blanked not
deleted so line numbering survives for ordering assertions.

### 3. `grep -c` counts LINES, not occurrences

The "exactly one GHCR literal" guard was evaded by putting two on one line. Measured: `grep -c`
returns `1`. Fix: `grep -o … | wc -l`.

### 4. No floor over the section's own assertions

Deleting **all 37** Guard-1 assertions left the suite at `78/78`, exit 0. The Row6 anti-vacuity
block floors the guard's *inputs*, which is a different thing. Fix: an **exact** count floor
(`==`, not `>=` — slack is attack budget, and a floor derived from what it guards descends with
it). It caught its own miscount on the first run and is mutation-proven.

## Three claims I published that were false

| Claim | Reality | How it was caught |
|---|---|---|
| "GHCR retained as break-glass" | AP-016 **LAPSED 2026-07-30 (#7071)** — the PAT is REVOKED, so the leg returns a guaranteed 401. The host's boot now depends **entirely** on zot | `grep AP-016 principles-register.md` |
| "Each runcmd `- \|` item is its OWN shell" | cloud-init's `shellify()` concatenates them into ONE `/bin/sh`. Documented in `cloud-init.yml` twice, `nic-wait-gate.test.sh`, and the 2026-07-06 errexit-leak post-mortem | agent cited the four in-repo sites |
| "One query covers both hosts" | `soleur-boot-emit` POSTs to Sentry only; `inngest-boot-phone-home.sh` to Better Stack only. No single query sees both | traced both emitters |

Claim 2 is the instructive one: I reported *catching a `docker login ""` bug* whose stated
mechanism was wrong — `$ZOT_EP` **would** have been inherited. The fix (re-derive from the baked
file) is still right; the reason given for it was not. **A correct fix with a wrong rationale
teaches the next reader something false**, and here the false thing was the exact belief a
post-mortem exists to prevent.

## A design defect: re-importing what the root already owns

`zot-registry.tf` already declares `local.zot_pull_user` and `random_password.zot_pull` **in the
same root**, feeding `doppler_secret.zot_pull_token` and the registry's own htpasswd. The plan's
Phase 2 added two operator-supplied `TF_VAR_*` variables for those values. Three consequences:

1. **Rotation staleness.** `doppler run --name-transformer tf-var` snapshots env *before*
   terraform starts, so an apply carrying `-replace=random_password.zot_pull` writes the NEW
   password to the htpasswd while templating `user_data` from the OLD snapshot — the replaced
   host boots unable to log in. That is the *same* "baked credential goes stale with no refresh
   channel" failure **#7462 exists to fix**, reintroduced on a second credential.
2. **Whole-apply hazard.** Terraform resolves ALL root variables before `-target` pruning, so an
   unprovisioned no-default var fails the entire merge apply. The plan *documented and accepted*
   this. Reading the in-root resource removes it instead.
3. It broke every `terraform test` run block.

**Gate:** before adding a root variable for a value, `grep` the root for a `local`/`resource`
that already produces it. The comment one line above mine already said *"the EXISTING local, not
a new derivation"* — and I did not apply that rule to the credential.

## `terraform validate` says nothing about `terraform test`

Adding a required no-default root variable breaks **every** `terraform test` run block:

```
The module under test for run block "reject_non_eu_location" has a required
variable "zot_pull_token" with no set value.
```

`terraform validate` passes throughout — it never resolves variable **values**. My local gate ran
`fmt -check` + `init` + `validate` and reported clean. CI caught it. This repo's own work-phase
guidance documents the trap, scoped to `lifecycle.precondition` diffs; my trigger was *adding a
required variable*, which the existing wording does not name.

Second gap in the same pass: **`terraform fmt -check .` does not recurse.** It never looked at
`tests/` at all. Use `-recursive`.

## Four `producer | grep -q` SIGPIPE flakes

Under `set -o pipefail`, `grep -q` closes the pipe on its FIRST match, the producer takes SIGPIPE
(141), and pipefail fails the pipeline **even though grep matched** — a false NEGATIVE that fires
only when the match is early enough that the producer is still writing. It presents as an
unreproducible flake.

Surfaced honestly: the battery's sandbox baseline went RED on an assertion that had passed in the
worktree seconds earlier, and the battery **ABORTED rather than scoring nine mutations against a
red baseline**. Re-running passed 9/9 — which is the tell for this class, not evidence it was
fine.

## This PR falsified a downstream gate

`zot-soak-6122.sh`'s code-corroboration arm anchors on the **web host's** syntax
(`IREF=.*$ZURL`, `soleur-boot-emit`). Measured against this implementation both return **zero**
hits. Left alone, once #6500 is legitimately closed the ADR-096 Phase-5 blocker would emit
`blocker-closed-but-condition-unmet` **forever**, on a factually false premise — and the
realistic end state is someone deleting a safety gate.

Its harness case 7 had the mirror-image defect: it relied on *the real repo* still having no zot
path. That is **corpus accident**, and it expired the moment the repo was fixed. Replaced with a
synthetic GHCR-only fixture.

## Key Insight

Every defect in this session reduces to one sentence: **a check that cannot distinguish the
property from a proxy for the property is green in both worlds.** The proxies here were a token's
*presence* (not the branch's sense), a log line's *text* (not its PASS/FAIL polarity), a file's
*line count* (not its occurrence count), and *the repo's current state* (not the condition under
test).

The corollary that cost the most: **a mutation battery is evidence about the mutations its author
imagined.** Mine was rigorous on one axis — delete/relocate/substitute a line in the SUT — and
silent on five others (dispatch, fixture direction, extractor uniqueness, set cardinality,
harness normalisation). Reviewers should audit a battery's **axes**, not its count. N mutations
on one axis is one mutation.

## Session Errors

1. **Never ran `terraform test`** despite adding required root variables. — Recovery: CI caught it; added dummies, then removed both variables entirely. — **Prevention:** the work skill's terraform-test trigger extended to name "adds/removes a root variable".
2. **`terraform fmt -check` without `-recursive`** — never inspected `tests/`. — Recovery: re-ran recursively. — **Prevention:** same bullet.
3. **Re-imported a credential the root already owns.** — Recovery: rewired to `local.zot_pull_user` + `random_password.zot_pull.result`; deleted both vars. — **Prevention:** grep the root before adding a variable.
4. **Published "9/9 mutants killed"** when attribution matched PASS lines. — Recovery: scoped to `^  FAIL`; corrected the PR body and this learning. — **Prevention:** review-skill bullet.
5. **Comment strip destroyed executable lines.** — Recovery: full-line-only strip. — **Prevention:** same bullet.
6. **`grep -c` as an occurrence count.** — Recovery: `grep -o | wc -l`. — **Prevention:** same bullet.
7. **No assertion-count floor** (documented class, recurred). — Recovery: exact floor, mutation-proven. — **Prevention:** already documented; recurrence recorded here.
8. **Dark-safe assertion pinned a token, not the gate.** — Recovery: positional anchor. — **Prevention:** already documented; recurrence recorded.
9. **Asserted "each runcmd item is its own shell"** — false, and I reported a "defect caught" on that wrong mechanism. — Recovery: corrected in code, plan, ADR, PR body. — **Prevention:** review-skill bullet on inherited framings.
10. **Asserted "GHCR retained as break-glass"** — AP-016 lapsed. — Recovery: corrected in 3 artifacts. — **Prevention:** same bullet.
11. **Asserted "one query covers both hosts"** across 4 artifacts. — Recovery: corrected. — **Prevention:** same bullet.
12. **Committed the guard batch before confirming the battery passed** — it had gone red. — Recovery: diagnosed the SIGPIPE flake, fixed 4 sites. — **Prevention:** run BOTH suites before `git commit`, not after.
13. **Read a third session's suite log as my own** (`/var/tmp/infra-suites.KqLzoyPJ`). — Recovery: resolved `SOLEUR_SUITE_LOGDIR` from `/proc/<pid>/environ`. — **Prevention:** already documented (`hr`-class); recurrence recorded.
14. **`pgrep -f run-registered-suites` matched my own measurement command**, briefly reporting a runner in my worktree that was my own grep. — Recovery: filtered to processes actually *executing* a runner. — One-off.
15. **CWD drift** broke a python edit (`FileNotFoundError`). — Recovery: re-ran from the correct directory. — One-off.
16. **Ran `lint-shell-capture-exit` without its baseline** → 215 "NEW" findings vs the true 1. — Recovery: used the correctly-baselined run. — One-off.
17. **Row3 ordering assertion left `L_ZPULL`/`L_PRE` off its `-n` guard** — the same fail-open the block above documents as fixed. — Recovery: guarded. — **Prevention:** covered by the review bullet.
18. **Four `| grep -q` SIGPIPE sites** (3 pre-existing) in a guard I was adding to. — Recovery: all four converted. — **Prevention:** rule recorded at the file's counters.
19. **`git-history-analyzer` stalled** — provenance coverage incomplete for this review. — One-off (tool); recorded so the gap is visible.
20. **Wrote the assertion floor as 42; actual 40.** — Recovery: the floor caught itself on first run. — One-off (and evidence the floor works).
21. **Three battery mutator anchors broke** when I changed the code they anchor on. — Recovery: re-anchored on commands rather than expression shapes. — **Prevention:** a mutator keyed to an expression's exact shape is coupled to every future edit of it.
22. **Claimed AC1's literal command returned 3; actual 2.** — Recovery: corrected before it propagated. — One-off.

## Related

- ADR-096 (zot migration) — amended 2026-08-13
- AP-016 in `principles-register.md` — LAPSED, the fact that inverts the risk picture
- `2026-07-06-web-2-fresh-boot-silent-errexit-leak-postmortem.md` — the runcmd-is-one-shell fact
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — the class this recurred from
