# Decision challenges -- feat-one-shot-9323-path-gate-mutation-batteries

Plan-review Taste / User-Challenge items recorded per ADR-084. `ship` renders this into the PR body.

---

## DC-1 -- Guard 2 (subject-set closure lint) kept although two reviewers recommended cutting it

**Date:** 2026-09-30
**Classification:** User-Challenge (the issue states the direction; two reviewers argue against it)

The issue's own risk mitigation says "derive subject paths from what each battery actually sources (not a hand
list)". DHH and code-simplicity recommended cutting the closure lint as a new static analyzer (ADR-181 already
rejected set-equality). The plan keeps it, bounded by a Phase 0 spike (`--print-affected-set` edges, else a
literal-operand fallback). Default = the operator's stated direction. To cut: delete Guard 2 and its
`lint-orphan-test-suites.sh` edit; the residual (a stale array declines forever on PRs) then rests on
self-inclusion, the battery's own hard-abort on a missing path, and the push/monitor backstop.

## DC-2 -- `scripts/ci-battery-gate-replay.sh` kept although two reviewers recommended a pasted one-liner

**Date:** 2026-09-30
**Classification:** Taste

It is the only credential-free, repo-local command that can serve as the plan's `discoverability_test` (preflight
Check 10 needs a command present in this PR's tree), it supplies the pre-merge run-rate forecast the ADR quotes,
and run-rate drift is the cheap stale-array signal. Cost: <= 30 lines. Alternative: drop it and declare the
follow-through script with `credentials_required` (which bumps `BASELINE_DECLARED_PROBES`).

## DC-3 -- `orphan-process-reaper-mutations` deferred although the issue names it in the next tier

**Date:** 2026-09-30
**Classification:** Taste

Three reviewers converged: the reaper already has a declared affected edge set
(`AFFECTED_SCRIPTS_ORPHAN_PROCESS_REAPER_MUTATIONS_PATHS`), so a second `*_PATHS` array would shadow it. The issue
lists it as a 100-165 s next-tier suite, not a top-five battery. Deferred with a tracking issue; fold it in after
the post-merge measurement by reusing the existing array.

## DC-4 -- CODEOWNERS hardening not added; test-all-affected declared by dependency

**Date:** 2026-09-30
**Classification:** Taste

Deepen-plan architecture review suggested CODEOWNERS entries for the five machinery paths as an out-of-band control
for the trust-root residual (a PR edits the predicate that gates its own batteries). Not added: the CI Required
ruleset (`gh api repos/jikig-ai/soleur/rulesets/14145388`) has only a `required_status_checks` rule, so no
code-owner review is enforced and an entry would be inert. Recorded as residual R2 in ADR-262 instead.
Separately, test-all-affected's census sandbox hardlinks all of `scripts/`; it is declared by dependency (runner,
libs, linter, itself), with the measured `scripts/` prefix (54% arm-rate) as the documented fallback.
