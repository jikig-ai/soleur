---
date: 2026-07-23
category: test-failures
module: ci-required-checks
issue: 6882
pr: 6883
tags: [ci, guard-test, mutation-testing, vacuity, security-gate, credential-leak, review]
---

# Learning: a CI-guard test that pins the guard's PRESENCE and POSITION does not test that it ENFORCES

## Problem

PR #6883 promotes a resolvable-credential-path CI guard to a blocking required check. Its bot-PR
soundness rests on the composite action REPRODUCING the scan before it posts an unconditional
synthetic green (the earned-green pattern). To pin that, I added parity **Test 8**, asserting:

- **8a** the preflight line `if ! python3 scripts/lint-credential-path-literals.py "${PATHS[@]}"; then`
  exists, and
- **8b/8e** its line number precedes the `gh api …/check-runs` synthetic POST.

I "mutation-proved" it by **deleting the whole `if` line** → 2 FAILs → concluded it had teeth.

`test-design-reviewer` found the mutation my battery missed. A **one-token** change inside the
then-body —

```
exit 1   →   :        (or `true`, or delete the line)
```

leaves the `if` line **byte-identical**, so 8a/8b/8e all stay green, while the guard goes **inert**:
the scan runs, prints its `::error::`, and *falls through* to `git push` + `gh pr create` + the
fabricated synthetic green anyway. That is exactly the fabrication-over-a-reachable-surface the test
claims to be "the enforcement teeth" against.

## Solution

Two additions (mutation-proven this time — the `exit 1`→`:` mutation now trips 8d while 8a/8b/8e stay
green):

- **8d — the enforcement leg.** Walk from the `if` line to the FIRST closing `fi` and require a
  non-zero `exit` in between (`awk -v s="$preflight_line" 'NR>s && /^\s*fi\s*$/{exit} NR>s &&
  /^\s*exit\s+[1-9]/{print "yes";exit}'`). This is the leg the body-neutralization mutation slips
  through.
- **8b re-anchored on the earliest OUTWARD side-effect** (`git push`), not the far-downstream POST.
  A reorder that pushes the bot branch *before* scanning it still passed the POST-anchored check
  (the branch — carrying the bad path — is already public by then). 8e keeps the POST as an
  independent weaker upper bound.

## Key Insight

**My own mutation battery only exercised the mutation I already had in mind.** Deleting the `if` line
tests 8a's *presence* leg; its green was indistinguishable from full coverage. This is the
"a gate certifies placement, not correctness" class
(`2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again.md`)
applied to a security-gate's own test.

The general rule for mutation-proving a guard test: **enumerate mutations that keep the ANCHORED
bytes intact while defanging the BEHAVIOR** — neutralize the body, not delete the head. For any test
that pins an ordering or placement, ask literally: *"which mutation satisfies this assertion while
violating the property?"* If you can name one, the test is vacuous w.r.t. that mutation. And a static
text test guarding a security control must anchor the **failing exit path**, never just the
invocation site — the guard can be silently defanged in-body while the test stays green, which is the
higher-severity direction for a security control.

## Session Errors

1. **The credential-path guard caught my own plan document.** /work precondition 0.1 (full-scan
   green) failed at start because the plan doc I authored quoted a literal home-relative path to the
   Doppler CLI config file while documenting the verification. That doc loads during /work, so the harness would auto-attach
   the operator's real Doppler config — the exact vector the whole PR closes.
   **Prevention:** when writing prose ABOUT a resolvable-credential-path guard, apply the guard's own
   neutralization guidance to the prose — describe the guarded file without a resolvable path
   (directory-only form, descriptive name, or `<placeholder>` segment).

2. **A `grep -v` mutation silently did not mutate (BRE escaping) and reported the baseline as green.**
   My first Test 8 teeth-proof used `grep -vF … '\[@\]'`-style escaping that matched nothing (341→341
   lines); the suite printed the BASELINE pass-count, which reads exactly like "the guard caught
   nothing to catch." I recorded it as green before checking the mutation landed.
   **Prevention:** after applying ANY mutation, assert it LANDED (`diff -q "$bak"` / line-count delta /
   grep the mutated token) before trusting the result — a null result wears a green result's clothes.
   This is already documented in review/SKILL.md and it recurred anyway, which argues for the
   mechanical `diff -q` gate over relying on memory.

3. **Pipeline-masked exit code.** `python3 <linter> | tail; echo "exit=$?"` printed `exit=0` for a
   linter that genuinely exits 1 (`$?` is `tail`'s status). Caught immediately.
   **Prevention:** never read `$?` after a pipeline when the exit code is the measurement — redirect to
   a file and read the status directly.

4. **The plan's Files-to-Edit missed the 4th SSOT encoder.** `tests/scripts/test-audit-ruleset-bypass.sh`
   T-rsc-7 pins the canonical entry count as a deliberate literal ("bumping it is the acknowledgement");
   the full-suite exit gate caught it, not the plan (which named 3 encoders).
   **Prevention:** when a PR changes a required-check set, grep ALL files that enumerate the set OR its
   count — including deliberate-literal guard tests — not just the SSOT data files.

5. **Test 8 presence-not-enforcement gap** (the primary learning above). Caught by test-design-reviewer,
   not by my own mutation battery.
   **Prevention:** the mutation-enumeration rule in Key Insight.

6. **Unrequested 5-agent brainstorm triad spawn** (earlier this session). The brainstorm skill's Phase
   0.5 mandates a CPO+CLO+CTO triad unconditionally, conflicting with
   `wg-zero-agents-until-user-confirms`. Filed #6886 (contested-design).
   **Prevention:** surface the skill-vs-rule conflict to the operator before spawning; tracked in #6886.

## Positive patterns (worth repeating)

- **Held all inline review fixes until every one of the 6 agents returned**, then fixed once — the
  agents were reading the same test file, so editing mid-review would have shown as false
  uncommitted-drift to the file-reading agents (the concurrent-mutation class review/SKILL.md warns
  about).
- **Confirmed the operator before shipping** a required-check ruleset change with repo-wide blast
  radius (every open PR blocks until rebased) rather than auto-merging.

## Related

- `2026-07-23-fabricated-green-unreachability-must-be-rederived-per-gate.md` (the sibling learning from
  this PR's brainstorm — the ALLOWED_PATHS ∩ SCAN_DIRS test)
- `2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again.md`
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- ADR-139 (earned-green preflight for reachable-surface content gates); issues #6882, #6883, #6886
