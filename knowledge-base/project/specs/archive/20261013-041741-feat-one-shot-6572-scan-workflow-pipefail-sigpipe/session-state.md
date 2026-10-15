# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-16-fix-scan-workflow-pipefail-sigpipe-plan.md
- Status: complete (scope-verified — diff vs base 39a4bb8dd touched only plans/ + specs/; tree clean)

### Errors
1. **Dirty tree from an interrupted probe (recovered).** A 200-iteration mutation probe timed out
   mid-run, leaving an injected `.lints[]?` in tracked `scripts/supabase-advisor-scan.sh`; restored
   via `git checkout --`. Verified clean at scope-check time. Root cause is a real design defect —
   `SCRIPT` is hardcoded at `:29`, so mutation tests cannot use a scratch copy — now fixed in-plan
   by a `SCRIPT_OVERRIDE` seam (Phase 1) + AC7.
2. **Contaminated measurement (caught).** An early probe read 1/200 false-FAILs on the unfixed file,
   contradicting three reviewers. Re-measured clean: 0/400. The single failure was a concurrent
   reviewer agent mutating the shared script.
3. Two throwaway sweep scripts emitted `[: integer expected` noise (unquoted `grep -c` in a loop);
   cosmetic, results unaffected.

### Decisions
- **The issue's preferred fix does not work.** Measured: `printf '%s' "$code" | grep -q` still
  SIGPIPEs (100/100 at 1.3 MB) — `printf` is still a producer feeding a pipe. Adopted option 3's
  capture-once half; replaced its match half with a here-string (0/100 at every size), which is
  established in-repo idiom (`deploy-status-fanout-verify.test.sh:244`).
- **Corrected the issue's severity premise.** Verified against the live ruleset,
  `scripts/required-checks.txt`, and the rollup's `needs:` that job `deploy-script-tests` is
  **advisory**, not required. Real urgency is noise + latent fail-open, not merge-blocked.
- **Found what the issue missed, then corrected the overclaim.** 3 of 7 sites fail *open* under
  SIGPIPE — including the file's self-described "headline assertion" (`:200`). But SIGPIPE needs a
  2nd `write()`, so under 4096 B it is unreachable (measured 0/300); only `:200` is reachable today.
  7-site scope retained on uniformity + future-growth grounds, re-justified honestly.
- **v1's verification layer was green on the unfixed file** — the panel's convergent finding.
  Replaced with a size-amplified differential (AC3: unfixed 100/100 FAIL vs fixed 100/100 pass),
  mechanized the flag-drift AC (AC4), and cut 6 ceremony ACs.
- **Routed cto's option-1 recommendation as a User-Challenge, not applied** (UC-1 in
  `decision-challenges.md`) — it contradicts the operator's explicit "option 3 preferred" and dhh
  argued the opposite. Cheaply reversible; ship Phase 6 renders it into the PR body.
- **Reversed v1's "no debt exists"** — wrong denominator. Measured 31 same-role sibling guards /
  235 sites under `apps/web-platform/infra/**`; files a narrow tracking issue (UC-2) rather than a
  591-site sweep.

### Components Invoked
`soleur:plan` · `soleur:plan-review` · `soleur:deepen-plan` · agents: `repo-research-analyst`,
`learnings-researcher`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`, `cto` (devex) · `gh` CLI (rulesets/issues/labels) ·
bash measurement probes

Not invoked, with rationale: `functional-discovery` / `agent-finder` (registry lookup is waste for a
bash fix), Step 4.5 advisor consult (single-file, no architecture choice — the 6-agent panel covered
it), no deepen research fan-out (the panel had just cut the plan for over-length).
