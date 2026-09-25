---
title: "My ancestry gate was sound; its harness and its recovery text were not"
date: 2026-09-25
category: integration-issues
module: ci / inngest-bootstrap publish + ADR-232 pin bump
tags: [ci, git-ancestry, guard-design, mutation-testing, remediation-text, oci-provenance]
issue: 8747
pr: 8775
---

# Learning: my ancestry gate was sound; its harness and its recovery text were not

## Problem

#8747: a `vinngest-v*` tag cut on an unmerged PR commit built a production bootstrap image
and its ADR-232 auto-bump merged main's pin 93 minutes before the source PR. The fix added
an `ancestry` stage to the bump script (authoritative — the bump runs main's copy) and a
refusal step to the build job (defence-in-depth — a tag push runs the TAGGED commit's YAML).

The design survived review unchanged. What did not survive was everything around it:

1. **The harness modelled a repository no runner has.** `harness_repo` kept a local `main`
   branch and published only `refs/remotes/origin/main`. A real `actions/checkout@v4` tag
   checkout with `fetch-depth: 0` has NO local branches, a detached HEAD, and EVERY branch as
   `refs/remotes/origin/*` — including the PR branch that carries the unmerged commit. So a
   mutant accepting "reachable from any remote branch" (the #8747 shape, verbatim) and a
   mutant using bare `main` as the base were both 342/342 green.
2. **The recovery text was the dangerous part of the gate.** The refusal said "delete the tag,
   re-cut it on main, re-run this job." In the state right after merge — main PINS off-main
   `v1.1.39` — every bump refuses and names `v1.1.39`. Followed literally, that deletes the
   live pin's tag; the next refusal names `v1.1.38`; and the data-integrity seat reproduced
   the cascade ending in an auto-merged DOWNGRADE to `v1.1.25`. Re-using the name also moves
   the pinned digest and lets zot GC the old one. "Re-run this job" either loops on the
   commit binding or pins a stale GHCR image on the non-max path.
3. **The binding checked nothing on the path that needed it.** Under `mirror_only` the build
   builds nothing, so "the commit the build checked out" is just where the tag points NOW.
   A tag re-pointed from off-main X to main M, whose rebuild never happened, passed ancestry,
   the binding, and the digest cross-check — with auto-merge armed (reproduced).
4. **Two shape asserts were satisfied by comments.** `check_block 'ref: main'` matched the
   comment `` `ref: main`, NOT the tag tree``, so `ref: ${{ github.sha }}` stayed green; the
   refusal step's `if:` was pinned only in a suite that runs as an ADVISORY check.

## Solution

- **Runner-shaped harness:** trunk published as `refs/remotes/origin/main`, then HEAD
  detached and the local branch deleted; every side commit also published as
  `refs/remotes/origin/pr-<x>`. Plus must-PASS rows the tip-only and first-parent mutants
  fail (tag on an older main commit; true merge), and a Record→Refuse CHAIN row (the steps
  were only ever tested with `HEAD_SHA` handed in by the test).
- **Pinned-tag-aware remediation:** when the off-main target IS the current pin, the refusal
  forbids deleting/re-cutting it and says "cut a NEW, higher version on main"; otherwise
  "delete it, wait for the PR to merge, tag the squash-merge commit as a NEW version — never
  a re-used name; that push runs its own publish; do not re-run this job." A pin above every
  remaining tag is refused at `resolve` as a downgrade.
- **Provenance binding:** the build stamps `org.opencontainers.image.revision=<commit>` into
  the image config (the digest covers it); the bump reads it with `crane config` and requires
  it to equal the target's commit. No label (every legacy image) ⇒ opened HELD. The raw label
  is never echoed (registry free text).
- **Parsed-YAML shape rows** (exact `ref: main`, exact `if:`, exact dispatch `ref:`
  expression, exactly one checkout) in the REQUIRED suite, with an `END|<n>` sentinel instead
  of a hand-kept row count.
- Battery 2: 32/33 killed; the survivor (bare tag lookup) is equivalent on a runner and was
  pinned anyway (I14).

## Key Insight

**A gate is three artifacts, and review attention goes to the one that is already right.**
The predicate got the design review, the CTO consult and the mutation battery; the harness
and the remediation text got nothing, because the harness "is just test setup" and the
message "is just prose". But the harness decides which mutants CAN be seen (a fixture with a
local `main` and no PR branch cannot see the two most plausible wrong bases), and the
remediation text is an instruction an operator — often an agent — executes verbatim during
the exact transition state the change creates. Ask per gate: *what does the runner's ref
layout look like, and does my fixture have it?* and *if someone follows this message
literally, in today's production state, twice, where do they end up?*

## Session Errors

1. **Usage limit killed the planning subagent (and a nested attribution agent) mid-deepen.** — Recovery: resumed the same agent via SendMessage, which kept its uncommitted plan edits. — **Prevention:** resume, never respawn, a limit-killed agent (review/SKILL.md Gate 2b already says so); one-off.
2. **Orphaned background wait loop failed (`return` outside a function).** — Recovery: re-run. — **Prevention:** one-off; a wait loop is a script body, use `exit`/`break`.
3. **Battery-2 worktree created with `git worktree add … HEAD` from the repo root, i.e. the wrong commit.** The control printed 198 (the pre-PR count) instead of 416. — Recovery: recreated at the branch SHA. — **Prevention:** pass an explicit SHA (`git -C <wt> rev-parse HEAD`) to `worktree add`, and always read the unmutated control's COUNT, not just its rc.
4. **`echo "$(basename $t) rc=$?"` reported `basename`'s status**, hiding three red ratchets (tails said `SOME TESTS FAILED` beside `rc=0`). — Recovery: `bash "$t" > "$l"; rc=$?` on its own line. — **Prevention:** the documented work/SKILL.md trap; never put `$?` inside an expansion that runs a command.
5. **`assert_out_has` passed a needle starting with `--` to `grep -qF` as an option.** — Recovery: `grep -qF -- "$2"`. — **Prevention:** every assertion helper that greps a caller-supplied needle takes `--`.
6. **YAML step name `Post to Slack (publish refused, #8747)` was truncated at ` #` (a comment).** Caught by a parsed-YAML shape row, not by actionlint. — Recovery: quoted the name. — **Prevention:** quote any `name:` containing ` #`; select steps by exact parsed name so truncation reds.
7. **The CI fixture-dir-operand ratchet reddened on an unguarded `git -C "$dir"` in the new harness.** — Recovery: `assert_fixture_dir "$dir"`. — **Prevention:** work/SKILL.md 6.6 already requires running `fixture-dir-operand-assert` + `fixture-relative-assert` before the first commit of new shell-test code; run them, don't wait for CI.
8. **Adding a second Slack step broke the mirror-only suite's "first step whose name mentions slack" selector.** — Recovery: select by exact name. — **Prevention:** select steps by exact name or `id`, never by substring; a substring selector is silently re-pointed by a sibling addition.
9. **fixture-scan's write-verb `merge` also matches the read-only `merge-base`** (the pattern ends `)\b`, and `-` is a word boundary). — Recovery: ran the diagnostic in a `cd` subshell. — **Prevention:** add `(?!-)` after the verb group; filed as a tracked issue (different subsystem).
10. **`git stash list` slipped into a command and the hook blocked the call.** — Recovery: removed. — **Prevention:** one-off; the hook is the enforcement.
11. **The local affected gate never left the queue (position 3–4 behind sibling worktrees).** — Recovery: stopped it and relied on CI's full battery plus directly-run consumer suites. — **Prevention:** state which evidence covered which commit; one-off contention.
12. **web-platform-build failed on a transient Google Fonts fetch.** — Recovery: the next push re-ran it. — **Prevention:** one-off.
13. **Four design defects shipped into review** (the recovery text's delete-the-pin cascade, the `mirror_only` provenance hole, the non-runner-shaped harness, comment-satisfiable shape asserts). — Recovery: fixed inline, battery 2 32/33. — **Prevention:** for a gate, (a) build fixtures from the runner's actual ref layout, (b) replay the remediation message literally against the post-merge production state, (c) pin YAML shape with parsed-value equality in a REQUIRED suite.

## Tags
category: integration-issues
module: .github/scripts/bump-inngest-bootstrap-pin.sh, .github/workflows/build-inngest-bootstrap-image.yml
