---
title: "A label filter is not an authorship bound — auto-labelers poison dedupe populations"
date: 2026-11-03
category: security-issues
tags: [github-actions, codeql, dedupe, issue-labels, fail-closed, review-catch]
---

# A label filter is not an authorship bound — auto-labelers poison dedupe populations

## Problem

`.github/workflows/codeql-to-issues.yml` deduped tracker filings with
`gh search issues "sec: CodeQL alert #N repo:… is:issue is:open"`. The `sec:`
token parses as a search qualifier, so the query was invalid, `gh` exited 1,
and `|| true` left `EXISTING` empty — the workflow re-filed a tracker on every
daily run (~190 live duplicates across 9 alerts; blame showed the mask dated
to #2042, 2026-04-13, not the recent #8593 rewrite the plan first blamed).

The prescribed fix (bounded `gh issue list --label type/security --json title`
+ anchored jq `startswith("sec: CodeQL alert #N ")`) was adopted — but the plan
rejected the sibling gate's `--author app/github-actions` scope with the
premise "strangers on a public repo cannot self-apply labels". Two review
seats refuted it: `.github/workflows/auto-label-security.yml` applies
`type/security` to ANY `^sec:` title on open/edit, so on this public repo any
account can mint a labeled `sec: CodeQL alert #N` issue and suppress the real
tracker — silent suppression of a security signal.

## Solution

- Author-scope the dedupe read (`--author app/github-actions`; both filers
  create issues via `GITHUB_TOKEN` so cross-filer dedupe survives).
- Hoist the list read once per run, fail-CLOSED on fetch/parse failure
  (`::warning` + `exit 0`, mirroring the in-file `close-orphans` job) — a
  dedupe that silently reads empty IS the original bug.
- `jq -e 'type == "array"'`, not `jq -e .` — a valid-but-non-array body would
  pass the weaker check and then read empty per-alert.
- `length >= 200` saturation `::warning` — `--limit` caps silently evict.

## Key Insight

When a plan rejects a hardening flag on a premise about WHO can carry a
label/token/scope, the premise to falsify is the GRANT PATH, not the
self-application path: enumerate every workflow/bot that bestows the
credential (`grep -rln "add-label" .github/workflows`), not just the user's
ability to apply it themselves. Second-order: a `|| true` (or `--search`)
dedupe read is a fail-open control — the empty set is indistinguishable from
"no trackers", and only a validated, anchored read makes failure loud.

## Prevention

- **Guard Contract row (applies beyond this PR):** any dedupe/blocklist read
  whose empty result continues a WRITE path must (a) carry a sufficient bound
  AND a saturation warning, (b) validate payload shape, (c) scope the
  population to a trust anchor (author, app, label-with-grant-path-audit),
  (d) fail closed — never `|| true` into the write path.
- **Blame-verify history claims in plans:** the plan asserted the defect was
  introduced by a recent rewrite; `git blame` showed the mask predated it by
  ~6.5 months. A 15-second blame check at plan time would have dated it.

## Session Errors

1. Planning subagent could not spawn nested agents — plan/deepen fan-outs ran
   inline. **Prevention:** none needed (harness limitation, already recorded).
2. `technical-ruling-gate.sh` rejects `pending - assumed` cells — deferred
   items filed as issue #12004. **Prevention:** gate worked as designed.
3. Removing the last live `gh search` broke the command-family corpus pin —
   pinned `search:false` with a restore-on-reintroduction tripwire.
   **Prevention:** when a diff retires the last instance of a scanned family,
   expect corpus/census pins to move and update them in the same commit.
4. Plan's `--author` rejection premise was false (auto-labeler grants the
   label). **Prevention:** the grant-path enumeration above — plan-time
   premise checks must include auto-bestowal surfaces, not just self-service.
