---
title: "The linter I cited as my oracle passed with the guard deleted — and the code shape the plan said it needed was the one that disarmed it"
date: 2026-09-11
category: security-issues
tags: [rule-d, credential-refusal, classifier, mutation-testing, harness, sentry-pin, transport-confinement, review-panel, 7898]
module: apps/web-platform/infra
issue: 7898
pr: 8073
related:
  - 2026-09-09-six-of-my-errors-were-the-class-i-was-reviewing-for.md
  - 2026-09-07-the-class-recurred-in-three-days-and-every-instrument-was-broken.md
  - 2026-09-10-every-escape-my-mutations-could-not-reach.md
  - 2026-09-08-my-live-verification-could-only-run-where-the-defect-was-invisible.md
---

# Learning: the linter I cited as my oracle passed with the guard deleted

## Problem

PR #8073 drew down #7898 §2 — the five `apps/web-platform/infra/` scripts that forward
`RESEND_API_KEY` (and, in two of them, a Sentry ingest triple) over `curl` with no transport
confinement. The plan named the Rule D classifier (`scripts/lint-shell-trace-credential-refusal.py`)
as the *second oracle* for two of its three guards: "deleting the host `=~` re-flags `sends to
$SENTRY_INGEST_DOMAIN`" (Guard 1 row 5) and "deleting the path `=~` re-flags `sends to $path`"
(Guard 3 row 4). Both were *measured* at plan time — on the UNEDITED files.

At work time, every prescribed shape passed the classifier (`OK: 5 scanned file(s), 0 baselined
(D)`) and every harness went green. Then the mutation battery deleted each guard and re-ran the
linter:

- Guard 3 (bootstrap path allowlist) **deleted → linter still OK.**
- Guard 1 (Sentry host limb) **deleted → linter still OK.**

Both "oracle" rows were vacuous for the shapes that shipped, and the reason for the first one was
the plan's own prescription.

## Root cause

Three properties of the classifier, none visible from reading a green run:

1. **Env-settability is decided by line shape for a positional `local`.** The plan said "split the
   three `local` declarations onto their own lines so `path` is an in-file assignment the classifier
   can see — measured necessary AND harmless". Measured with the guard *present*, both shapes pass,
   so the claim looked true. Measured with the guard *deleted*: `local method="$1" path="$2"` on ONE
   line → `path` reads as never-assigned → env-settable → the pin is REQUIRED (2 violations without
   it). `local path="$2"` on its OWN line → `path` reads as a non-env assignment → pin NOT required →
   linter OK with the allowlist gone. The split the plan called "necessary" was the edit that
   disarmed the oracle.
2. **A destination derived one hop from an env-settable variable is not env-settable to it.** The
   Sentry URL interpolates `${_si_host}` (`${SENTRY_INGEST_DOMAIN%.}` folded with `,,`), which the
   plan needed so the must-PASS uppercase/trailing-dot fixture sends the folded host. `_adjudicated()`
   walks env var → derived var (so a pin on a derived var clears the raw var), never the reverse — so a
   derived operand needs no pin at all.
3. **`_mask_cmdsubs()` masks every `var="$(curl …)"` span**, so the destination limb never runs on a
   captured curl. Every `-w '%{http_code}'` site is captured; converting the two Sentry curls to that
   shape (to get the HTTP code into the marker) moved them out of the classifier's destination limb
   entirely. Only the transport limb (`--disable` first, `--noproxy '*'`) still fires there.

A fourth claim from the panel — that `CURL_INVOKE` misses a path-qualified `/usr/bin/curl` — was
FALSE (the transport limb fires on it; the "linter OK" reading was gap 3 in disguise) and had already
been pasted into `decision-challenges.md` and four harness comments before the simplicity gate
measured it.

## Solution

- Kept the `local` on one line, with the mechanism in the function comment so the next editor does
  not "tidy" it apart; corrected the plan's prescription and its precedent-diff row.
- Made the exec harnesses the guard for the member classes the linter cannot see, and proved it by
  mutation with a pristine-copy restore: host limb deleted, regex loosened four ways, fold dropped,
  second `--noproxy ''`, `-L` added, `/usr/bin/curl`, `--proto` on the loopback curl, an unquoted
  `--noproxy *` from a non-empty cwd, `SSLKEYLOGFILE` dropped from the unset list (a TLS-env canary
  exported by every harness, recorded as `TLS_ENV_LEAK` by the stub) — 17 rows, all RED.
- Wrapped the alarm's Channel 1 in `sentry_checkin()` so the `sentry-dest-pin` region is
  byte-identical to the monitor's at the same indentation; the parity row diffs verbatim, with a
  non-empty + END-marker guard.
- Gave deliberate skips their own marker class (`SOLEUR_<UNIT>_SEND_SKIPPED channel=… reason=
  cooldown|unset|jq`) so the plan-mandated alert rule on `SEND_FAILED` can never page on
  configuration; the Sentry-env-unset branch in both dual-channel scripts was stdout-only and now
  ships a SKIPPED row.
- Anti-vacuity `TOTAL` floors per harness (printf + exit 1, never via the helpers): deleting the sole
  reader row of `curl_violations` in the crm harness had gone 24/24 green.
- Appended the three classifier gaps and the unset-list home to tracker #7898 as register entries
  with a concrete trigger (a classifier-only PR before the next drawdown) — CONCUR from the simplicity
  gate; net-issue-flow 0.

## Key insight

**An oracle that passes with the guard deleted is not an oracle — measure every linter-justified
code shape in BOTH directions.** A plan that says "the linter needs shape X" has usually measured X
only with the guard present, where the linter passes regardless; the sentence that reads as a
constraint is the one that removes the constraint. Before citing any lint as a second oracle for a
guard, delete the guard on a scratch copy and require RED. Same family as "a mutation battery only
covers what you mutate": the guard's INSTRUMENT is a thing to mutate too.

Companion: **a captured curl is invisible to the classifier's destination limb.** The moment a
credentialed `curl` becomes `var="$(curl …)"` (to read `-w '%{http_code}'`), Rule D's destination
pin requirement no longer applies to it. Until the classifier follows a derivation back to its
env-settable source and lints the unmasked operands of a `$(…)` span, the exec harness is the guard
for every captured-curl site — write the harness row, not the linter citation.

## Session Errors

1. **(forwarded, plan phase) two plan writes denied by `iac-plan-write-guard`** on descriptive
   `systemctl` / `doppler secrets set` prose — Recovery: the sanctioned `iac-routing-ack` opt-out +
   rewording. **Prevention:** describe an existing provisioner by resource name (`terraform_data.X`
   re-runs), not by the verb it executes.
2. **(forwarded) three plan-review agents stalled ~25 min** — Recovery: `SendMessage` nudge; all
   returned. **Prevention:** state at spawn that the final message is the deliverable; resume, don't
   respawn.
3. **Phase 2 exit shard gate REFUSED rc=4** (a sibling full-gate run in flight) — Recovery: targeted
   suites as the Phase 2 evidence, full battery at ship. **Prevention:** already the documented
   contract; read `--capacity` first.
4. **`git stash list` typed into a review probe → whole command BLOCKED** by the stash hook —
   Recovery: dropped the probe. **Prevention:** already hook-enforced; the preflight's
   `git rev-parse --verify refs/stash` is the stash-free probe.
5. **The session `grep` shell function returned zero matches on `vector-pii-scrub.test.sh`** (it
   holds non-UTF-8 fixture bytes) — Recovery: `/usr/bin/grep -a`. **Prevention:** when a grep over a
   test file returns nothing for a string `sed` just printed, `type grep` and retry with
   `/usr/bin/grep -a` before concluding absence (routed to `review/SKILL.md`).
6. **The disk-monitor RED harness CRASHED under `set -e`** on `grep -c` returning 0 (exit 1) inside a
   command substitution — Recovery: `|| true`. **Prevention:** a count assignment in a `set -e`
   harness needs `|| true`; a harness that aborts is not RED, it is un-run.
7. **Plan prescription inverted** ("split the locals — measured necessary and harmless") — Recovery:
   measured both shapes with the guard deleted; kept one line; corrected plan + tasks.
   **Prevention:** measure a linter-justified shape WITH the guard deleted (routed to `work/SKILL.md`).
8. **Plan's "linter is the oracle" rows false for the shipped shapes** — Recovery: mutation battery;
   harness rows + parity row are the guard; classifier gaps recorded on #7898. **Prevention:** same
   as 7 — an oracle is proven by a RED, never by a green.
9. **Two sed mutation rows did not land** (pattern mismatch) — Recovery: the `cmp` landing check
   flagged them; redone in Python with `assert old in s`. **Prevention:** already the documented
   contract; keep the landing check.
10. **A batch patch script asserted a wrong tail anchor** for `resource-monitor.test.sh`, patching
    one file and aborting before the second — Recovery: re-ran with the right anchor.
    **Prevention:** one file per script invocation, or assert every anchor before writing any.
11. **`echo 84 >` overwrote the trap-lint highwater file's comment header** — Recovery: restored from
    `git show origin/main:` and edited the number. **Prevention:** `sed -i` the number, never
    redirect over a file with a header.
12. **An inherited panel claim pasted before verification** ("`CURL_INVOKE` misses `/usr/bin/curl`")
    reached `decision-challenges.md` and four harness comments; the simplicity gate falsified it.
    Recovery: corrected all five sites. **Prevention:** for every causal claim a review seat hands
    you, run its falsifying command before writing it anywhere — the compound rule already says so.
13. **PR #8023 merged mid-review; AC4 went red at QA** (`+2` in the D baseline vs a moved main) —
    Recovery: clean rebase; ACs written as `main − 5` held (65 → 60). **Prevention:** the plan
    anticipated it; re-run `gh pr view <sibling>` before every baseline-touching step.
14. **"byte-identical" claimed while the parity row stripped indentation** — Recovery: the
    `sentry_checkin()` wrapper made it literally true and the row now diffs verbatim.
    **Prevention:** a parity claim in a comment must be the parity the test performs.
15. **(ship) the incident-PIR gate fired on the archived plan for a preventive-hardening PR with no
    live event** — its paragraph strip handles the `if this lands broken` framing, but two plan
    sentences sit outside any marked paragraph: the deepen-plan hypotheses header's own negation
    ("the plan body names no outage") and a Non-Goals consequence sentence ("the user meets the
    outage"). Recovery: recorded the verdict and the two matched sentences in the PR body's gate
    notes; no PIR authored for a non-event. **Prevention:** the gate's negation window
    (`scripts/ship-incident-pir-gate.sh` › `DROP_RE`) should admit `names no <outage-term>` the
    way the soak gate already strips negated declarations; and a deepen-plan template sentence
    that names the vocabulary it is denying belongs inside a fenced or marked block. Documented
    in place per `wg-when-deferring-a-capability-create-a`; the trigger for a fix is the next
    preventive-hardening plan that cites its plan path in the PR body.

## Cost

11-agent panel + simplicity gate + coverage consult ≈ 1.45M subagent tokens; planning ≈ 0.74M. The
panel's yield was real (0 P1, 13 P2, 20 P3 — 31 fixed inline, 17 new mutants killed), but two seats
(git-history, performance) returned no actionable finding and the structural-enumeration seat's map
was the single highest-value output. On a guard-shaped bash PR the cheap instruments — the
deterministic lints and a mutation battery that mutates the ORACLE — should run before the panel.
