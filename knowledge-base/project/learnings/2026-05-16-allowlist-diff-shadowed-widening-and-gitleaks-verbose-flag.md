---
title: "allowlist-diff under-detects shadowed cross-rule widening; gitleaks needs -v to surface finding details"
date: 2026-05-16
type: workflow-issue
related:
  - https://github.com/jikig-ai/soleur/issues/3874
  - https://github.com/jikig-ai/soleur/issues/3268
  - https://github.com/jikig-ai/soleur/issues/3877
tags: [secret-scan, gitleaks, allowlist-diff, ci-gate, defense-in-depth]
---

# allowlist-diff parser under-detects shadowed cross-rule widening

## Problem

PR #3874 widened the per-rule path allowlist on `.gitleaks.toml`'s
`database-url-with-password` rule to include
`knowledge-base/project/learnings/.*\.md$`. The CI `allowlist-diff` gate
(`apps/web-platform/scripts/allowlist-diff.sh`) exists specifically to fire
on this class of edit and require an explicit operator ack (`secret-scan-allowlist-ack`
label OR `Allowlist-Widened-By:` commit trailer).

Local dry-run reported: `allowlist-diff: no allowlist path changes (regex
re-orderings only)`. The trailer we added (`Allowlist-Widened-By: Jean Deruelle`)
became belt-and-suspenders because the gate never would have fired.

## Root cause

`parse-gitleaks-allowlists.mjs` extracts ALL `[[rules.allowlists]] paths`
entries across every rule and emits a **deduped union** (one flat array,
deduplicated). `allowlist-diff.sh` then `comm -13`s the base-union vs
head-union to compute "added paths".

The new path `knowledge-base/project/learnings/.*\.md$` was already in the
deduped union via the `private-key` rule (line 315 on `main`). Adding it
under `database-url-with-password` did not change the **union**, even
though it widened the protection of a **different rule**. The gate is
union-aware, not per-rule-aware — it cannot distinguish "this path is new"
from "this path is now allowlisted for one more rule".

## Why the gate is load-bearing

Each rule in `.gitleaks.toml` represents a distinct secret-shape detector
(database URLs, private keys, JWTs, etc.). Widening rule A's allowlist to
cover a path already in rule B's allowlist still **reduces detection
coverage** for rule A on that path. An operator who relies on the gate
alone (without trailer or label) to enforce review of every widening
would miss this class of change.

In #3874's specific case the widening is intentional and well-precedented
(mirrors the `private-key` rule's #3268 carve-out for the same path).
But a future operator who widens a rule's allowlist toward a path that
happens to already exist under another rule will silently bypass the
gate.

## Fix surface (deferred)

Make the parser emit per-rule tuples `{rule_id, path}` instead of a flat
deduped union, and have `allowlist-diff.sh` compute the per-rule diff.
A second-order benefit: per-rule diffs surface in the sticky comment so
reviewers see *which rule* gained protection-relaxation.

Out of scope for #3874; the trailer was added as defense-in-depth.
Filed as #3877 — although that issue tracks the **placeholder-regex**
widening (the `***` redaction shape gap), the parser fix is a sibling
follow-up that should be filed separately when prioritized.

## Sibling learning: `gitleaks --redact` alone doesn't print finding details

Running `gitleaks git --no-banner --exit-code 1 --redact` reproduces the
failure exit code and the `leaks found: N` warning, but does NOT print
the per-finding `Finding/Secret/RuleID/File/Line/Commit` block on stdout
unless `-v` (verbose) is also passed. The leak details are essential for
diagnosis, so a first invocation without `-v` requires a second
invocation to get them.

**Canonical diagnostic invocation:**

```bash
gitleaks git --no-banner --exit-code 1 --redact -v 2>&1 | tail -40
```

The `--redact` flag scrubs the actual secret value (good — the diagnostic
should not echo secrets), but `-v` is required for the surrounding
metadata.

## Session Errors

1. **Initial gitleaks repro without `-v` surfaced only the count, not the
   file/line/rule.** Required a second invocation with `-v` to get
   diagnostic detail. Recovery: re-ran with `-v`. Prevention: when
   diagnosing a gitleaks failure, default to
   `gitleaks git --no-banner --exit-code 1 --redact -v` from the first call.

2. **allowlist-diff gate appeared to mis-report "no allowlist path
   changes" after a real widening.** Initially read as a script bug;
   tracing through `parse-gitleaks-allowlists.mjs` revealed it is
   working as designed (deduped union), and the actual gap is in the
   gate's per-rule awareness. Recovery: trailer was already in place
   as belt-and-suspenders. Prevention: documented above; consider filing
   the per-rule-tuple refactor when budget allows.

## Prevention

- **When adding a new `[[rules.allowlists]]` block to `.gitleaks.toml`**:
  include the `Allowlist-Widened-By: <name>` commit trailer regardless of
  whether you expect the `allowlist-diff` gate to fire. The gate has a
  known shadowing blind spot for paths already covered by another rule.
- **When debugging a gitleaks CI failure locally**: always pass
  `-v` alongside `--redact`. The two flags are complementary
  (redact scrubs the secret value, verbose surfaces the metadata)
  and neither alone is sufficient for diagnosis.
- **When updating the secret-scanning operator runbook**: if the
  paragraph you're editing contains numeric counts derived from rule
  enumeration (e.g., "Our 13 custom rules each carry the same paths
  allowlist"), sweep for ALL occurrences of that count in the SAME
  paragraph. PR #3874's first commit updated the count on one line
  but not on a sibling line ~15 lines higher; review caught it as P1.
