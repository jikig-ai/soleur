---
title: "#4781's guard already existed; its REPORTING was the defect, and my own instruments lied four times"
date: 2026-09-24
category: integration-issues
module: sentry-alert-live-fidelity
tags: [sentry, fidelity-probe, frozen-rule, stale-premise, review, mutation-testing, instruments]
issue: 4781
pr: 8654
---

# The guard #4781 asked for already existed; its reporting was the defect

## Problem

#4781 (filed 2026-06-02) asked for a recurrence guard after the four `auth-*` Sentry alert
rules were found with empty trigger conditions and tag filters, and for a correction of the
lore that called their emails a coincidental red herring. By 2026-09 the premise was stale:
the three burst rules were Terraform-owned `sentry_alert` blocks (#7650), `auth-per-user-loop`
was a frozen `sentry_alert` (#8451), and `scripts/sentry-alert-live-fidelity.sh` compared all
four against live Sentry daily and after every apply.

Measured, the probe caught every #4781 shape (rc 1). It **misreported** one: a frozen rule
whose live triggers were emptied left the excluded-trigger scope and was printed as
`UNMANAGED … delete it in Sentry` — a destructive remedy for a rule Terraform owns. The same
line's remedy text had also been silently truncated since #8545 by unescaped backticks that
ran `def` as a shell command.

## Solution

- The undeclared-rule classification moved below the frozen-name derivation into ONE jq pass
  over whole keys; frozen names become `FROZEN RULE LEFT SCOPE` with an id-aware repair.
  Names print through one `SAFE_JQ` (C0, line separators, zero-width and bidi ranges) with
  their live id, plus a `DISPLAY NAME ALTERED` flag when scrubbing changed them.
- Review added: `FROZEN ID MISMATCH` (the pin matched by name only), a parity refusal for
  frozen `.tf` blocks the derivation cannot parse, a scrubbed DRIFT leaf key, an anchored
  drift-workflow verdict grep, and a bash-error guard centralised in the suite's `_run`.
- Lore: dated notes on six learnings, the anchor learning and ADR-031; living runbooks,
  README and comments corrected in place. #4781 closes via PR #8654.

## Key Insight

When an issue's premise is stale, the deliverable is the measurement, and the residue is
often in how the existing guard **reports**, not whether it fires. "rc 1 on every shape"
answered the issue's question and hid a destructive remedy on one of them.

## Session Errors

1. **(forwarded) Full suite exceeded the 2-min tool timeout during planning.** Recovery: re-ran in background. **Prevention:** run this ~5-min suite with `run_in_background` from the start.
2. **Review agents wrote into the session scratchpad and overwrote my fixture `ref.json`, faking a 35-divergence "regression".** Recovery: re-derived the reference from the capture; identity PASS. **Prevention:** brief every seat with a `/var/tmp` sandbox (review/SKILL.md #8292 bullet) and keep the lead's fixtures OUTSIDE the scratchpad agents share; re-derive a fixture before believing a regression.
3. **The Write tool rendered `\u202e` in file content as a literal RLO character.** Recovery: rewrote the bytes to escapes. **Prevention:** write escape-bearing text through a quoted heredoc, then `grep -P '[\x{200b}-\x{202e}]'` the file.
4. **`grep … && python3 fix.py`: the grep matched nothing, so the fix never ran, and the lints after it passed on unchanged files.** Recovery: noticed the missing `ok`. **Prevention:** never gate an edit on a probe with `&&`; run the edit, then assert the changed construct.
5. **A `sed '/…/{N;d}'` cleanup deleted the wrong line of a fix script.** Recovery: targeted Edit. **Prevention:** edit scripts with an exact-match replacement, not a line-range sed.
6. **A commit staging one `.ts` comment ran a 104-min `bun-test` battery and was rejected; the backgrounded wrapper reported exit 0.** Recovery: read `git log` (HEAD unmoved), triaged the reds. **Prevention:** before a `.ts`-staging commit on a branch where the battery is not the point, use `LEFTHOOK_EXCLUDE=bun-test` after running the touched suites; always confirm HEAD moved.
7. **The battery's reds were a behind-main census artifact and a `credentials_required` baseline my own plan moved — neither in my 67 hand-run ratchets.** Recovery: merged main; baselined 22→23. **Prevention:** routed to `plan/references/plan-sharp-edges.md`.
8. **`pgrep -f` blocked by the self-match hook.** Recovery: waited on the task notification. **Prevention:** use `plugins/soleur/scripts/lib/proc.sh`.
9. **F43's `^::error::` check could not see an indented detail line, so dropping `safe` survived.** Recovery: widened to `^[[:space:]]*`. **Prevention:** an injection assertion must match the command anywhere a runner could parse it, and be mutation-proven.
10. **Plan's H1b predicted the guard survives without `LC_ALL=C`; bash translates the prefix.** Recovery: corrected plan, comment and results. **Prevention:** run a prediction before writing it as a harness row.
11. **Plan predicted F35 as M3 collateral; measured green.** Recovery: corrected AC3. **Prevention:** record collateral from the run, not the plan.
12. **My ratchet harness truncated two multi-line `run_suite` commands.** Recovery: re-ran with full commands. **Prevention:** extract registrations with the backslash continuation joined.
13. **The filing gate refused `gh issue create` without a user-visible consequence.** Recovery: `--label meta/machinery`. **Prevention:** probe/guard trackers take `meta/machinery` from the start.
14. **I proposed 7 scope-outs; CONCUR dissented on 5 as ≤100-line fixes.** Recovery: inlined them. **Prevention:** apply the cost-of-filing gate per item before assembling a bundle.
15. **The plan-era lore census missed 5 claim sites (README, server.ts, assert-byok, two learnings).** Recovery: the pattern seat's claim sweep. **Prevention:** sweep by the claim's SUBJECT repo-wide (`configure-sentry-alerts.sh`, `#4781`), not by one phrasing.
16. **The first runbook edit fixed a blockquote and left the dead recipe directly below it.** Recovery: rewrote the whole section. **Prevention:** when correcting a procedure, rewrite the SECTION that carries the runnable command, not the paragraph that describes it.
