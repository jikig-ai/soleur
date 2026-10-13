---
title: Batch sed/python edits that report "applied" but never matched — assert `old in s` or measure after
date: 2026-10-13
category: engineering
tags: [workflow-guard, test-fixtures, python-edits, silent-failure, review-loop]
symptoms: [three review seats independently found the loopback suite dead at its first arm: a render assert flagged `/usr/bin/udevadm` while no rebind existed — because the python `s.replace` that was supposed to add it never matched and printed 'edits applied' anyway]
module: pipeline fix-round editing
synced_to: []
component: process
problem_type: workflow_issue
resolution_type: process-correction
root_cause: a heredoc python batch-edit treated `str.replace` as fallible-but-verified when it is neither — no assertion that the needle existed, no post-write grep of the result; the multi-line escaped needle silently never matched
severity: medium
---

# A replace that reports "edits applied" is not evidence the edit landed

## Problem

During the PR #10228 fix round I batch-applied loopback edits with a heredoc
python block. One `s.replace(needle, replacement)` — the `/usr/bin/udevadm` →
PATH-stub rebind — used an over-escaped multi-line needle that never matched.
The script printed `edits applied` and moved on. Meanwhile a *separate* edit in
the same batch added an `udevadm-still-absolute` assert — so the suite now
asserted a rebind that did not exist. Three independent review seats caught it:
`render_stage` → `unavailable` → `exit 2` at the first arm; the whole tier-2
behavioral suite was dead on HEAD while the structural tier stayed green.

A second instance, same shape: my `render_reopen` `/etc/default/` assert fired
on a *comment-only* provenance mention the script never writes — the assert was
authored against an imagined surface, not the rendered output (which I never
produced locally).

## Solution

- `s.replace(old, new)` in a batch script MUST be preceded by `assert old in s`
  (or followed by `assert new in s`) — the cost is one line per edit and it
  turns every silent no-match into a loud failure at write time.
- After any "the render should no longer contain X" change, render once and
  grep — a 5-second `awk|sed` pipeline replay would have caught both instances
  before review seats did.
- Asserts about a stubbed command must be written against what the stub
  actually records: the sleep recorder appends `"$*"` (argv = `1`), so
  `grep -c 'sleep' "$ARM_SLP"` is always 0 — `-s` + `wc -l` is the real
  liveness predicate. The suite's own message already used `wc -l`; the assert
  contradicted it.

## Key Insight

Batch-edit failure modes are asymmetric: a wrong edit is caught by tests, but a
MISSING edit is caught by nothing unless the missing thing was pinned. The pair
"add an assert + add the mechanism it asserts" is a *two-edit transaction* —
half-landing it produces a suite that certifies its own impossibility. Same
class as #7539/#8323 (correction sweeps that measured the string, not the
claim): verify the POST-STATE exists, not the exit code of the edit script.

A corollary worth pinning: the suite that only ever runs under sudo on CI gets
no local verification — reviewable render asserts in it are how a wrong render
is caught early, but they are also a new way to kill the whole suite; each one
must be replayed against a real render before committing.

## Session Errors

1. **Python `s.replace` silent no-match** (the `/usr/bin/udevadm` rebind never
   landed; assert did) — **Prevention:** `assert old in s` before `s.replace`,
   or a post-write `grep -F` verification; never trust the script's own
   "applied" print.
2. **`findmnt -no SOURCE | head -1` in `ensure_mount`** — reads the shadowed
   bottom layer of a stack; the repo documents this exact defect at
   `inngest-luks-cutover.sh:313`. **Prevention:** when a codebase documents a
   defect pattern, grep the whole diff for the pattern's other spellings
   before committing; the final shape (pop wrong layers until the kernel-served
   top reads congruent, bounded at 8) is what a "cannot read a shadow" policy
   converges to.
3. **W2 liveness assert that can never be true** (`grep -c 'sleep'` on an
   argv-only recorder log). **Prevention:** author recorder asserts by reading
   the stub's `printf` format, not the command's name.
4. **`render_reopen` `/etc/default/` assert flagged a comment** — over-broad
   literal. **Prevention:** render the target once and grep before writing a
   survivor assert; distinguish "writes to X" from "mentions X in a comment".
5. **CLA check failed on `devin@cognition.ai` commits** — this repo's CLA
   allowlist contains the operator account (`deruelle`) and named bots, not
   `devin-ai-integration[bot]`; pipeline commits must carry the ambient
   signed identity. **Prevention:** match the repo's committer convention
   (`git log` on sibling Devin PRs shows `deruelle`) rather than a generic
   bot identity.
6. **Stale `$B3_FSTAB` fixture tripped the new `reopen_pointer_lost` refusal** —
   an earlier arm's fstab line survived `arm_reset`. SUT behavior was correct;
   the fixture was untruthful. **Prevention:** when a new refusal keys on
   persisted fixture state, enumerate which fixtures carry that state across
   `arm_reset` boundaries.
7. **INNGEST_GZIP_BUDGET exceeded** — the size model's early-warning bracket,
   resolved by the file's own documented "modest re-baseline" pattern.
   **Prevention:** for infra diffs touching cloud-init payloads, run the bun
   size test (`bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`)
   locally before push — it exists and runs without sudo.
8. **lint-infra-no-human-steps flagged deferred-orchestrator prose** — wrapped
   in `<!-- lint-infra-ignore -->` regions per the linter's own remediation
   text. One-off.
9. **Forwarded (plan phase):** the env-seam design (`INNGEST_LUKS_ATTACH_WAIT_S`
   / `env -u` / `attach_wait_invalid`) was overturned by CTO D4 after the
   sibling shipped without it. **Prevention:** when a sibling session shipped
   the same fix first, read its MERGED diff before drafting seams — the
   sibling's review already removed them.
