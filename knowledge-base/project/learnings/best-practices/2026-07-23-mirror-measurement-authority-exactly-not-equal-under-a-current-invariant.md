---
title: "Mirror a measurement authority's EXACT per-input treatment — not a simplification that's equal only under a current invariant"
date: 2026-07-23
issue: 6794
pr: 6852
tags: [measurement-parity, fail-open, plan-vs-authority, test-harness, best-practices]
category: best-practices
---

# Mirror a measurement authority exactly, not "equal-under-a-current-invariant"

## Problem

#6794 ported the AGENTS always-loaded byte measurement in `cron-compound-promote.ts`
and `compound-promote.sh` onto the frontmatter-STRIPPED basis so both promoters
match the commit-gate authority (`scripts/lint-agents-rule-budget.py`). The plan
prescribed **"apply `stripFrontmatter` to BOTH files uniformly"** with the
rationale "strip is a no-op on AGENTS.md (no leading `---`), so applying it to
both reproduces the authority exactly."

That is true **today**, but the authority does NOT strip both files. It measures
`b_index = file_bytes(index)` **RAW** and only `b_core = len(strip(core))`. The
uniform-strip simplification is equal to the authority *only under the invariant
"AGENTS.md carries no leading frontmatter."* If AGENTS.md ever gained a `---`
block, the cron would strip it (→ smaller) while the authority counts it raw
(→ larger): the promoter would UNDER-count vs the commit gate — the **dangerous**
direction (a falsely-small always-loaded total can falsely PASS the byte cap) —
and the over-strip guard could not catch it, because stripping a leading block on
the *index* drops no `[id:]` pointer line (the pointers follow the frontmatter).

architecture-strategist flagged this at review (ARCH-1); five plan/deepen agents
and the implementer had accepted the uniform-strip framing.

## Solution

Mirror the authority's **exact per-input treatment**: index RAW, core stripped.

```ts
// BEFORE (equal only while AGENTS.md has no frontmatter):
return measureFileStrippedBytes(indexText, "AGENTS.md")
     + measureFileStrippedBytes(coreText, "AGENTS.core.md");

// AFTER (byte-exact with the authority in ALL cases):
return Buffer.byteLength(indexText, "utf8")           // b_index raw
     + measureFileStrippedBytes(coreText, "AGENTS.core.md"); // b_core stripped
```

Both existing tests stayed green (the invariant test already used raw
`byteLength(indexText)` for the index), confirming the change is behaviour-
preserving today while removing the latent fail-open for tomorrow.

## Key Insight

When code must agree with a measurement/validation **authority** (a linter, a
commit gate, a canonical RPC), reproduce the authority's exact operation on each
input — do not substitute a transformation that is merely *equal to it under a
property that currently holds*. "Equal today" and "equal by construction" are
different guarantees; the gap is exactly a latent fail-open that ships green and
only fires when the invariant later breaks. This is the measurement-parity
sibling of the review catalogue's "cloned pattern drops the precedent's
semantics" family: faithfulness is per-input, not aggregate.

## Secondary: source a colocated CODE dependency from the script's own dir, not `$REPO_ROOT`

`compound-promote.sh` derives `REPO_ROOT` from `${COMPOUND_PROMOTE_FIXTURE_ROOT:-$(git rev-parse --show-toplevel)}`,
and its test harness repoints `REPO_ROOT` to a **minimal fixture tree**. Sourcing
a colocated code dependency (`scripts/lib/frontmatter-strip/strip.sh`) via
`$REPO_ROOT` therefore failed under test (`No such file or directory` → `set -e`
abort → 17 cascading failures). A `strip.sh` is part of the script's **own code
tree**, not the fixture's **data** — resolve it from the script dir:

```bash
_CP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CP_SCRIPT_DIR/lib/frontmatter-strip/strip.sh"
```

Rule: **fixture-overridable `REPO_ROOT` locates DATA; `BASH_SOURCE`-derived dir
locates colocated CODE.** Sourcing code through a test-repointed root breaks the
test, not production.

## Session Errors

1. **`compound-promote.test.sh` broke (17/22 fail) on first strip integration** — sourced `strip.sh` via `$REPO_ROOT`, which the harness repoints to a fixture tree. Recovery: source from `$_CP_SCRIPT_DIR`. **Prevention:** see the secondary insight above — a `.test.sh` that sets a `*_FIXTURE_ROOT` override is the tell that `REPO_ROOT` is data-scoped; source code deps from the script dir.
2. **Full-suite `scripts`/`bun` shards timed out foreground (2 min, then 8 min).** Recovery: ran in background with `/var/tmp` logs. **Prevention:** the full shards re-run the whole repo's suites (>8 min); run heavy shards with `run_in_background` and poll the log, never foreground.
3. **Background bun-shard notification said "exit 0" while `BUN_SHARD_EXIT=1`.** The trailing `echo` masks the command exit. Recovery: grepped the log for the captured `BUN_SHARD_EXIT` + suite summary. **Prevention:** already documented across work/review skills — never trust the bg notification exit; read the captured rc from the log. (The sole failure was the pre-existing `changelog.js` GitHub-API network-timeout flake, unrelated to the diff.)
4. **`find -maxdepth 2` missed the incident logs** (at depth 3: `<wt>/.claude/.rule-incidents.jsonl`). Recovery: broadened the find. **Prevention:** when enumerating per-worktree dotfiles, count the depth (`.worktrees/<name>/.claude/<file>` = 3 from `.worktrees/`) or drop `-maxdepth`.
5. **Foreground `sleep`/`pkill` returned exit 144.** The environment blocks foreground `sleep`. **Prevention:** already in the harness reminder — do not use foreground `sleep`; use a Monitor/until-loop.
6. **`rule-metrics.json` appeared dirty mid-session** (machine-local aggregate regeneration, ADR-091 / #6042). Recovery: `git checkout --` reverted it so it stayed out of the PR diff. **Prevention:** `rule-metrics.json` is machine-local-regenerated; before a review/ship push, confirm the branch diff (`git diff origin/main...HEAD --name-only`) excludes it unless compound intentionally staged it.

Related: [[2026-07-22-rule-metrics-denominator-investigation]] (the #6794 item-1 deliverable).
