---
title: "A two-word `awk -v` mapped the helper's crash onto its designed failure code — every recovery read 'unrecoverable' and nothing distinguished it"
date: 2026-11-01
category: workflow-issues
module: scripts/followthroughs (git-data-rehearsal-evidence.sh, web-fresh-boot-zot-8651.sh)
tags: [awk, shell-quoting, attribution-expiry, designed-rc, fail-closed, follow-through, fixtures, devin]
issue: 11607
pr: 11786
---

# Learning: a helper whose designed failure code matches its own crash signature cannot tell them apart

## Problem

PR #11786 ports #11603's `UNKNOWN STEP` attribution-expiry recovery (#11600) to the two
sibling probes named in #11607: `web-fresh-boot-zot-8651.sh` (near-verbatim port) and
`git-data-rehearsal-evidence.sh` (adapted — it reads whole-run logs, so its new
`step_region` helper adds a field-1 job-name pre-filter and re-attributes each region
line as `<job>\t<step>\t<ts> <content>` into a scratch file the UNCHANGED
`lcount`/`lfirst`/refs awks re-read — one parse grammar, no second copy to drift).

`step_region` defines a graded protocol: rc 0 = region sliced, rc 1 = the step did not
run (designed absence), rc 2 = the step ran but the region cannot be sliced — a FAILED
READ the callers map to `UNREAD(<token>)`, never a printed zero. Its slice command was
carried in as:

```bash
awk -F "$TAB" -v jn "$jn" -v ps="${st:0:19}" -v stn="$pfx" '…' "$log" >"$STEP_REGION_FILE"
[[ -s "$STEP_REGION_FILE" ]] || return 2
```

`-v` binds its operand by POSITION in `var=value` form: `-v jn` consumes `jn` as the
operand — not in `var=value` form, so awk prints a usage error and writes nothing
(the call's `2>/dev/null` makes even that invisible). The redirect still creates the
region file empty, `[[ -s ]]` fails, and the helper returns **2 — its designed
"ran but unsliceable" code — for every input**, including sliceable ones. Every
recovery on every aged log would have reported "unrecoverable", wearing the
protocol's own honest verdict. `git log -S 'awk -v jn '` finds nothing: the defect
never reached a commit because the new UNKNOWN STEP fixture rows went must-RED —
the sibling-job decoy fixture (run 2214) exists to prove recovery SUCCEEDS from the
step's own job region, so a dead helper fails loudly instead of reading as a
legitimate rc 2.

## Port gate honored: re-evaluate each sibling's population window

Issue #11607's re-evaluation criterion ran before the port and changed the *reason*,
not the decision. Both windows span the ~2-3-week attribution boundary, but
differently: the zot probe reads the newest web-2 replace/create job with no age
bound — and its tracker #8651 closed 2026-09-30, so the 14-day closed-lookback
retired the probe ~2026-10-14. Conclusion: live exposure dormant, exposure
latent-total on any re-enrollment (a re-enrolled probe would misread a proven boot
on its first sweep, in the silent shape a sweeper cannot distinguish from "never
ran") — port still warranted, dormancy sharpened the case rather than removing it.
The rehearsal collector takes owner-pasted run ids (unbounded age by construction).
Rulings recorded in `decision-challenges.md`; the dormant-probe class is covered in
`2026-10-15-dormant-followthrough-probe-is-not-a-standing-detector.md`.

## Solution

One argv for the assignment: `-v jn="$jn"` (committed at
`scripts/followthroughs/git-data-rehearsal-evidence.sh` `step_region`). No protocol
change needed — the fixture suite, not a new exit code, is what made the crash
visible; asserting the recovery path itself (not only the outer verdict shapes) is
the check that names this defect class.

## Key Insight

When a helper's protocol reserves a return code for a DESIGNED failure ("ran but
cannot be sliced"), any internal crash that produces the same observable signature —
empty output reaching the same return path — is indistinguishable from it.
`2>/dev/null` completes the disguise. Two defenses: keep the designed outcome and
the crash signature separable (a distinct code for the tool-crash path, or let the
tool's stderr survive), and pin the recovery path RED — a suite that only asserts
the outer verdict cannot distinguish "tool died at argv parse" from "input was
genuinely unsliceable"; at least one fixture must expect the recovery to SUCCEED.

The shell fact itself: `awk -v name "$val"` is not `awk -v name="$val"`. `-v` takes
ONE operand in `var=value` form — split across two argv entries, the name becomes
the operand (and trips the `var=value` validation on gawk) while the value falls
into the program-text position; either way nothing is written.

## Session Errors

1. **`awk -v jn "$jn"` (two words) → every `step_region` call returned its designed
   rc 2.** — Recovery: must-RED UNKNOWN STEP fixtures named it before commit; quoted
   `-v jn="$jn"`. — Prevention: no repo check validates awk `-v` operand arity
   (shellcheck doesn't); the covering guardrail is the fixture suite — when porting
   a graded-rc helper, pin at least one fixture where the recovery SUCCEEDS, not
   only the verdict shapes on failure.
2. **`git -C "$VAR" commit` denied by `git-commit-secret-scan-undeterminable`
   (Devin).** The hook resolves the commit's target repo out of the command TEXT — a
   variable, `$(...)`, `~`, or glob cannot be expanded to a literal directory, so the
   staged content cannot be attributed to a checkout and it fails CLOSED (the scan
   never ran). — Recovery: literal absolute path in the same command
   (`cd /abs/worktree && git commit` or `git -C /abs/worktree commit`), per the
   hook's own repair text. — Prevention: under Devin the `git -C`/`cd` operand must
   be literal text, not an expansion; this is the `git-commit-secret-scan` arm of
   the #8254 class (2026-09-17 learning, updated with this instance).
3. **Review P2: `TRAIL_PATTERN` became a replicated literal across
   `web-first-deploy-10585.sh` and `web-fresh-boot-zot-8651.sh`** (the port copied
   the regex — a second copy of a guarded literal is a drift surface). — Recovery:
   byte-parity assertion added to the zot suite (fix commit 6a88a909a0). —
   Prevention: known class — a literal replicated into a sibling script needs a
   parity pin in ONE of the two suites; see
   `2026-10-25-third-copy-of-a-security-guard-needs-a-parity-row.md` and
   `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`.
4. **Devin pipeline constraint (expected, not an error):** no `run_subagent` inside
   planning/work/review subagents — every phase ran
   `Reviewed-Coverage: sequential-fallback` end-to-end with the trailer disclosure.
   Documented convention (2026-10-24 learning); no action.

## Related Issues

- #11607 (the port this learning came from) and PR #11786; #11600 / PR #11603 (the
  upstream fix ported); #11609 (decision-challenge discharged by the PR body);
  #11583 (standing watchdog, context only).
- Technique provenance: `git-data-boot-poll-8178.sh` (#8262) —
  `2026-09-18-the-measured-facts-my-resume-brief-handed-me-were-the-defects.md`.
- Attribution discipline: `2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md`.
- Dormancy/lookback: `2026-10-15-dormant-followthrough-probe-is-not-a-standing-detector.md`.
- The wider spine (a check that cannot report):
  `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`.
- Literal-parity class: `2026-10-25-third-copy-of-a-security-guard-needs-a-parity-row.md`,
  `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md`.
- Devin hook cwd class: `2026-09-17-devin-envelope-omits-cwd-precommit-guard-false-deny.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
  §"Sharp edges for `gh run view --log` probes" (awk `-v` edge appended this PR).
