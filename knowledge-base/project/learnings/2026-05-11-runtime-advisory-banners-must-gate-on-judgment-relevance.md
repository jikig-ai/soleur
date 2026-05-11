---
title: Runtime advisory banners must gate on judgment relevance, not gate-internal state alone
date: 2026-05-11
category: best-practices
tags: [gdpr-gate, advisory-gate, banner-fatigue, signal-to-noise, trust-binding]
ref-pr: 3541
ref-issues: [3535, 3536, 3540]
related-learnings:
  - 2026-05-11-multi-agent-review-vendor-pipeline-trust-model.md
  - 2026-05-10-content-vendoring-pin-policy-brainstorm.md
---

# Runtime advisory banners must gate on judgment relevance

## Problem

PR #3541 added a "trust-binding" defense to the gdpr-gate: when `GH_TOKEN` is absent and the gate cannot verify the workflow's last-run timestamp, it emits an operator-attested-mode banner so the operator knows the staleness signal is operator-controlled rather than workflow-anchored.

The initial implementation emitted the banner whenever `cron_days_stale == 999 && notice_days_stale != 999`, BEFORE the regulated-data path check. The user-impact-reviewer multi-agent review caught this as a P1: in subagent shells (`/soleur:plan` Phase 2.7, `/soleur:work` Phase 2 exit, Claude Code skill harnesses), `GH_TOKEN` is typically absent. Every commit on every PR — regulated or not — would emit the banner. Operators learn to ignore it. A real backdate-induced banner on a regulated PR is invisible in the noise.

The plan's own GDPR Compliance Gate section had named this exact concern ("Otherwise … would emit the operator-attested banner spuriously on every invocation, training operators to ignore it") then shipped without the fix. The PR's mitigation was named, then dropped.

## Solution

Gate the banner emit on `${#matched[@]} > 0` — fire ONLY when the gate is actually judging a regulated-data path. The banner becomes "this regulated PR has a degraded gate" instead of "the gate is in degraded mode (which is the default in subagent shells)".

```bash
if (( ${#matched[@]} > 0 )); then
  echo "gdpr-gate: regulated-data path touched (${matched[*]}); run /soleur:gdpr-gate" >&2
  emit_incident hr-gdpr-gate-on-regulated-data-surfaces applied \
    "regulated-data path touched: ${matched[0]}" 2>/dev/null || true

  # Operator-attested-mode banner — fires ONLY when (a) a regulated path
  # is being judged this commit AND (b) the cron binding is unavailable.
  if [[ "$cron_days_stale" == "999" && "$notice_days_stale" != "999" ]]; then
    printf 'ℹ gdpr-gate: operator-attested mode (no GH_TOKEN available — cron-run timestamp unverified, falling back to NOTICE last-verified)\n'
    emit_incident gdpr-gate-cron-binding unavailable \
      "no-token-or-gh-cli" 2>/dev/null || true
  fi
fi
```

## Key Insight

A runtime advisory banner has two failure modes:

1. **False negative** — banner doesn't fire when it should. Caught by self-test + integrity gates.
2. **False positive at scale** — banner fires when it doesn't matter. Caught by … nobody, because every individual fire is "technically correct." Operators silently filter it out, the signal degrades to noise.

**Mitigation:** ask "does the gate have a meaningful judgment to communicate this turn?" If the answer is no (no regulated path being judged), suppress the banner regardless of internal gate state.

This is distinct from pre-existing staleness banners (30d/90d) which signal a long-term operational state (`the gate's rules are stale at any rate`). Those banners legitimately fire on every commit because the operational state IS gate-internal. The operator-attested-mode banner signals a per-judgment state and must scope to per-judgment relevance.

**Generalizes to:** any advisory output whose meaning depends on "what is the gate doing on THIS invocation?" vs. "what is the gate's persistent state?". The former must gate on relevance; the latter can fire unconditionally.

## Tags
category: best-practices
module: gdpr-gate, advisory-gates

## Session Errors

- **Truncated test-all output masked actual result.** `bash scripts/test-all.sh 2>&1 | tail -60` discarded most output; the visible "30/31 suites passed" was from a separate partial run. Re-running with `> /tmp/test-all-full.log` showed all 31/31 actually passed. **Recovery:** captured full output to a file. **Prevention:** for long sequential test runners, capture to a file via `>` and grep for FAIL/ERROR; relying on `| tail -N` to extract a summary loses suite-level coverage AND can show stale data from a prior incomplete run if the file is reused.

- **`diff` in an `&&` chain stranded the test NOTICE in modified state.** Pattern: `cp bak f && sed mutate f && diff bak f && cp bak f`. `diff` exits 1 on difference (the expected outcome of the sed mutation), short-circuiting the `&&` chain before the restore `cp` ran. Required `git checkout -- f` to recover. **Recovery:** manual git restore. **Prevention:** when `diff` is used as a verification step in an `&&` chain, wrap with `|| true` (`diff bak f || true`) or use `;` between mutate/verify/restore steps so a non-zero diff exit doesn't break the cleanup.

- **PreToolUse security-reminder hook on Write of GitHub Actions workflow file.** Advisory print about command-injection risks; did not block. Re-issued Write with an explicit security comment in the workflow file noting only `github.token` is used. **Recovery:** retry Write. **Prevention:** already handled by the hook's advisory design.
