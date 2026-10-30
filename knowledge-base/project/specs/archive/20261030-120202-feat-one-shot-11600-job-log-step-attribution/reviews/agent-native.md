# Agent-Native Architecture Review — PR #11603

Seat: `soleur:engineering:review:agent-native-reviewer`
Scope reviewed: `git diff origin/main...HEAD` on branch `feat-one-shot-11600-job-log-step-attribution`
Primary surface: `scripts/followthroughs/web-first-deploy-10585.sh` (+94/−20) and its suite; secondary: runbook addition, plan/spec artifacts.
Change class: internal ops probe — no UI, no agent tools, no system-prompt surface. The agent-native lens here is **machine-actionability of the probe's output contract**: the sweeper (`scripts/sweep-followthroughs.sh:845-895`) maps the probe's exit code to a fixed verdict word and republishes the probe's stdout+stderr (folded via the launcher at `sweep-followthroughs.sh:701-705`, sanitized, `tail -c 4000`) verbatim into a tracker-issue comment that agents read and act on.

## Summary

The change recovers trail-step content from attribution-expired job logs (`UNKNOWN STEP`) by slicing the `##[group]Run` region keyed on the step's `started_at` — verbatim the derivation already proven in `git-data-boot-poll-8178.sh:202-209` (confirmed byte-for-byte: same awk program, same global `${log//.../}` CR+BOM strip). The machine-actionable contract is **preserved and strengthened**: exit vocabulary is unchanged ({5,2,3,78}; zero new exit paths — all new failure arms reuse `exit 3`), the zero-parseable CANNOT ESTABLISH message retains its canonical sentence contiguously with the new `recovery_cause` appended after the terminating period, and that suffix is itself greppable and now distinguishes four distinct failure causes where previously the message admitted only "log shape drift". Suite: 69/69 pass on this worktree; the property sweep asserts every driven path exited in {5,2,3,78} (45 runs).

## Contract Verification

| Surface | Location | Before | After | Status |
|---|---|---|---|---|
| Exit vocabulary | `web-first-deploy-10585.sh:103-114` (header), all `exit` sites | {5,2,3,78} | {5,2,3,78} — all new arms reuse `exit 3` | ✅ |
| `zero parseable` tripwire text | `web-first-deploy-10585.sh:322-325` | fixed sentence | same sentence + `recovery_cause` suffix appended after `trail.` | ✅ |
| `recovery_cause` causes | `web-first-deploy-10585.sh:296-318` | n/a | `; no ##[group]Run header at or after <ts> in an attribution-expired log` / `; recovered region held no emitted lines` / `; recovered region emitted no trail-pattern lines` / `; the trail step's jobs-API entry carried no usable started_at` | ✅ greppable per-cause |
| Cause-string injection safety | `web-first-deploy-10585.sh:299,305` | n/a | the only interpolated token `${jstart:0:19}` is reachable only inside the `^[0-9]{4}-…` regex gate — no probe-output laundering path into the issue comment | ✅ |
| Emitted-vs-echoed filter parity | `emit_rows` `web-first-deploy-10585.sh:217-227` | inline awk, named path only | single chokepoint consumed by BOTH named and recovered paths — the two paths can never drift apart on the #9905 ANSI rule | ✅ |
| Suite coverage of the contract | `.test.sh:533-620` | 30-case floor | 9 new UNKNOWN STEP arms + BOM/single-strip mutation pins; floor 30→69 | ✅ |

## Findings

### Critical Issues (Must Fix)

None.

### Warnings (Should Fix)

1. **Named-path / recovered-path tripwire asymmetry (pre-existing residual, now conspicuous)**
   - Location: `web-first-deploy-10585.sh:308-316` vs the tripwire at :322-325
   - The recovered path now treats "region has emitted lines but none match the trail pattern" as a broken channel (`trail=""` → CANNOT ESTABLISH on success). The **named path** retains the older, weaker rule: a trail step whose output parses to lines but contains no pointer/ready pattern line passes the tripwire and silently enrolls nothing — the same degraded-channel shape graded loud on one path and quiet on the other. Not introduced by this PR (the zero-parseable-only check predates it), but the recovered arm demonstrates the stronger check is cheap; consider extending the same pattern-grep guard to the named path, or documenting the asymmetry as a stated residual.

2. **Recovery trigger is all-or-nothing on the named anchor**
   - Location: `web-first-deploy-10585.sh:297` (`if [[ -z "$trail" ]]`)
   - The recovery fires only when the named anchor yields *zero* rows. If GitHub ever returns **partial** attribution (some lines under the step name, the rest under `UNKNOWN STEP`), a half-trail — e.g. pointer attributed, `fresh_boot_ready` not — skips recovery and silently under-enrolls an owed host (quiet-2 instead of CANNOT ESTISH). There is no evidence partial attribution occurs (the measured failure is whole-log `UNKNOWN STEP`), but the failure class it would produce is exactly the quiet-miss this probe exists to prevent. Observation-grade risk; if a belt is wanted, firing recovery whenever `ready_ts` or the pointer set is incomplete — rather than only on empty — closes it, at the cost of merging two trail slices (dedup needed).

### Observations (Consider)

1. **`recovery_cause` bucket label slightly overclaims.** `; no ##[group]Run header at or after <ts> in an attribution-expired log` (:305) is emitted for *any* log where the named anchor failed and no qualifying header exists — including future drift that has nothing to do with attribution expiry (e.g. gh changes the column layout, group markers renamed). An agent routing remediation on the suffix could mis-triage a non-expiry drift as expiry. Low impact: the header-absence half of the message is accurate either way, and rc=3 is the correct verdict regardless of cause label.

2. **`$3` truncation at embedded tabs is unchanged.** Both the old inline awk and the new `print $3 | emit_rows` named path stop field-3 content at the first embedded tab (:291), while the recovered region keeps everything after the second tab. Trail-pattern lines never contain tabs; noted only because the two paths now differ microscopically in this edge.

3. **Plan/spec artifacts are honest about degraded gates.** `decision-challenges.md` discloses `Reviewed-Coverage: sequential-fallback` for every spawn-prescribed gate — good operator-visible provenance, no hidden gaps.

## What Works Well

- **Single-chokepoint filter extraction** (`emit_rows`) is the textbook fix for copy-drift between two consumers of one rule — better than the pre-change shape.
- **Tripwire ordering is correct**: recovery runs *before* the zero-parseable verdict, so attribution expiry is graded as recoverable first and only the unrecoverable residue is loud — exactly the "measurable, never a quiet pass" posture the header documents.
- **The `recovery_cause` suffix makes the CANNOT ESTISH comment *more* agent-actionable**: a reader can now branch on four greppable causes (missing `started_at`, no bounding header, empty region, pattern-less region) instead of one opaque "log shape drifted".
- **Fixture faithfulness**: `ulog` reproduces the measured real shape — bare `Set up job` head, BOM'd subsequent sections, a pre-`started_at` prelude the ts-gate must skip, optional EOF-termination — and pins the `//`-vs-`/` BOM mutation with a second BOM'd section.
- **jq `// "-"` + regex gate** on `started_at` cleanly separates "API carries no start time" from "API carries an unexpected shape", each with its own cause string.

## Agent-Native Score

- Verdict surfaces (exit codes, message substrings, issue-comment republish channel): **fully preserved** — 3/3 contract elements verified by suite and by reading the sweeper.
- **Verdict: PASS** — no critical issues; two warnings are pre-existing/hypothetical residuals, not regressions introduced by this diff.
