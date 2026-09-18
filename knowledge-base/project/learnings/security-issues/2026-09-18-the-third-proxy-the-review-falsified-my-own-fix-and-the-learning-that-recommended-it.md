---
module: System
date: 2026-09-18
problem_type: security_issue
component: tooling
symptoms:
  - "checkDiffPaths derived the protected path set from `git apply --summary` + `--numstat -z` on the invariant that an empty summary means a pure content edit"
  - "an IMPLICIT rename (differing ---/+++ with no rename headers) yields an EMPTY --summary, a destination-only --numstat, rc 0 on apply, and the SOURCE file deleted"
  - "the marker's refusals[] was structurally [] on every real run because it was pushed inside a memoized step.run callback and read outside"
  - "deleting the checkDiffPaths CALL from the handler left every guard green"
root_cause: missing_validation
resolution_type: code_fix
severity: critical
tags: [git-apply, allowlist, inngest-replay, guard-vacuity, mutation-testing, review-panel, third-proxy]
---

# The third proxy: the review falsified my own fix, and the learning that recommended it

## Problem

PR #8276 closed #8274 — a diff-path allowlist bypassable because `git apply` strips one leading
component and the filter matched only `+++ b/`. Plan review had caught that my first fix
(`--numstat -z`) reports only a rename's destination. So I shipped `--summary` as the structural
gate, on the invariant "empty summary ⇔ pure content edit", and wrote a security learning that
morning recommending `--summary` as *"the tool's **authority** output (what it will do)"*.

The 12-seat review panel falsified that invariant, and I reproduced it:

```
diff --git a/plugins/soleur/skills/alpha/SKILL.md b/AGENTS.rules.md
--- a/plugins/soleur/skills/alpha/SKILL.md
+++ b/AGENTS.rules.md
@@ -1,2 +1,3 @@
```

| stage | result |
|---|---|
| `git apply --summary` | **empty**, rc 0 |
| `git apply --numstat -z` | `1\t0\tAGENTS.rules.md` — destination only |
| `diffRemovesHardRule` | 0 matching `-` lines — vacuous |
| `git apply` | rc 0; `AD plugins/soleur/skills/alpha/SKILL.md` — **source deleted**; corpus replaced |

`--summary` reports a rename only when the patch carries explicit `rename from`/`rename to`
headers. Row 4 caught renames only because `git mv` emits them. A model authoring a diff emits
whatever it likes. So the fix closed the *spelling* #8274 reported and left the class open — which
is precisely the rule this same PR added to `plan/SKILL.md`.

Three proxies in a row, each found by the same question: `+++` headers → `--summary` → `--numstat`.
*What input does this format render as nothing?*

The panel found more, all in the code the PR **added**, not the code it fixed:

- **Replay.** `refusals`/`refusalDetail`/`clustersOpened` were pushed inside the memoized
  `apply-and-pr-*` callback and read outside. Inngest replays the body without re-entering a
  completed step's callback, so the marker emitted `[]`/`0` on every real run — byte-identical
  for a quiet corpus, a run that opened two PRs, and a run that refused everything. Five seats
  converged; the repo had documented the mechanism twice (ADR-077 §3; the 2026-07-02 learning).
- **The wire.** Every Guard 2 row drove `checkDiffPaths` in isolation. Deleting the call from the
  handler left both suites green. Two endpoints covered, one wire uncovered.
- **Binary patch.** Empty `--summary`, derives as an allowlisted `M`, no `-` lines (so the hard-rule
  guard is vacuous), and the byte budget catches only growth. One diff cleared every gate and
  replaced the corpus with 5 bytes.
- **Two uninstrumented exits.** One logged at `logger.info` — *below* the level ≥ 40 cut Vector
  applies — so it never reached Better Stack: the #8281 defect inside the #8281 fix.
- **The probe.** `grep -c` over undecoded `raw` is a tautology over the SQL `LIKE` that produced
  the rows, and GitHub webhook bodies reach that source. This PR's own description would have
  closed #8281 on an echo of itself.
- **The census.** A 12-line look-back window broke the moment the error marker grew to 15 lines,
  exactly as pattern-recognition predicted; and its exact-whitespace regex was blind to
  `return {ok:`, multi-line and shorthand returns — the mutation it existed to catch.
- **Guard 2 was satisfiable by a header parser.** A 12-line regex parser that never calls git —
  the construct the SUT's own docblock forbids — passed all 11 rows. Six mutations of
  `TARGET_ALLOW_RE` survived, one of which would refuse 77 of 99 real skill dirs.
- **`code-quality` verified the empty-summary claim across six shapes and pronounced it true.**
  It never tested the seventh.

## Solution

`checkDiffPaths` no longer asks git what a patch *says* it will do. It applies the patch to a
throwaway index (`GIT_INDEX_FILE` + `git apply --cached`) and reads
`git diff-index --cached -z HEAD` in **raw** format — the *effect* on a sandbox, which names both
sides of every operation with both modes by construction. Raw, not `--name-status`: the first
attempt used `--name-status`, which reports a mode-only change as plain `M`, and an all-`M` rule
accepted chmod 644→755 — caught by the pre-existing mode-change row during the rework.

Then, per finding: outcomes returned from the step (not pushed into a closure); a chokepoint
census with an UNCLASSIFIED bucket pinning that every `apply` argv sits behind the derivation and
the handler calls it before the applier; binary hunks refused outright; a post-apply **shrink
floor** (rule count may never fall; target keeps ≥ 85% of its bytes) that asserts the property on
the tree whatever gate a shape slipped past; the two exits instrumented at WARN; the probe
decoding structurally with a positive control and a `trigger == "cron"` requirement (the marker
now carries `trigger` and `run_id`); the census block-scoped, whitespace-tolerant and
comment-stripped; `status` a closed union so an unknown value is a compile error; per-file
assertion floors; `test` removed from the bot's synthetic check-run names (it carries the corpus
linters over the file this cron writes — the #8203 doctrine one cron over).

Every guard mutation-proven. One survivor documented as equivalent **with its enumeration**
(without `-M`/`-C`, every non-`M` diff-index status carries `000000` on one side, so the mode check
refuses first).

Seven commits: `a0467ee75`, `c4b731672`, `7ccfbb6f7`, `8df5db86c`, `4af296d10`, `0927d672c`, and
the trailer. `Reviewed-Coverage: full 12/12 agents`.

## Key Insight

**A report format that reads as authoritative is one more input shape to enumerate.** Three
formats in a row each had a shape they rendered as nothing, and each was recommended — by me, in
writing — as the fix for the previous one. The learning written in the confidence of having just
found the second bypass is exactly when the third is least suspected. When a guard derives its
protected set from a tool, prefer the tool's **effect on a sandbox** over any of its **reports**
about intended effect. If you must read a report, ask what it renders as nothing, and put that
input in a row before you trust the empty case.

**A fix's own guards are the least-audited surface in the diff, and they fail open.** Nine of the
panel's blocking findings were in code this PR added to *prove* the fix. A guard suite green before
and after the fix pins nothing; write the stub that passes it before believing it.

## Session Errors

1. **A background commit notified "exit code 0" while the recorded `COMMIT_RC=124`.** The 0 was
   the trailing `git log`; `timeout` had killed the commit and left a `flock` orphan that would
   have made two writers on one index if I had retried blind. — Recovery: read the recorded rc
   line, reaped the orphan by pid after confirming its cwd, retried with the sanctioned
   `LEFTHOOK=0` and the manual gates disclosed in the message. — **Prevention:** the notification
   is authoritative for liveness only; read the `*_RC=` line you wrote immediately after the
   command, and check for a surviving hook process before any git-write retry (already in
   work/SKILL.md; this is a second measured instance).
2. **Ran `lint-shell-capture-exit` without `--baseline` and read "203 NEW findings" as the diff's.**
   The CI form reports 0. — Recovery: read `test-all.sh` for the invocation it uses. —
   **Prevention:** a lint run without its CI flags is a different instrument; copy the invocation
   from the runner before quoting its verdict.
3. **Three `X_RC=$?` readings were the rc of a trailing `echo`/`tail`.** — Recovery: re-ran with
   the rc captured immediately after the command. — **Prevention:** `$?` binds to the immediately
   preceding command; never put a pipe or a second command between the command and its rc read.
4. **The Edit tool interpolated ` `-style escapes into literal control bytes**, producing an
   unterminated regex. — Recovery: rewrote the line via python with a landing assertion. —
   **Prevention:** write escape-bearing regexes through a quoted heredoc, and grep the file for
   the literal backslash afterwards.
5. **`cd ..` from `apps/web-platform` landed in `apps/`**, so a lint "ran" against a nonexistent
   path and its rc was `echo`'s. — Recovery: absolute paths. — **Prevention:** never `cd ..` in a
   compound command; use the worktree-absolute path.
6. **The window-closure lint rejected my `// window-assembly:` declaration inside a docblock.** —
   Recovery: moved it to a line comment. — **Prevention:** none needed; the checker's message says
   so, and it working is the point.
7. **Wrote "tracked in #8293's scope" into the plan before doing it.** — Recovery: replaced with the
   actual fix (a status union) the same pass. — **Prevention:** never write a tracking claim into a
   committed artifact before the tracker exists.
8. **A scratch-repo `git commit` was blocked by the commit-to-main guard**, on a throwaway repo
   with a `probe` branch. — Recovery: measured via the index only (`git add` + `apply --cached`),
   which needs no commit. — **Prevention:** index-only measurement for git-behaviour probes.
9. **A `&&` chain broke at `git mv` (untracked file) and a `;`-separated `rm -f` still deleted the
   issue body file.** — Recovery: rebuilt the body from `gh issue view`. — **Prevention:** never mix
   `&&` and `;` in one line that ends with a delete.
10. **The census's mutation-row anchor went stale the moment I changed the emit call** — caught by
    its own `not.toBe(src)` landing assertion rather than reporting a false pass. — Recovery:
    re-anchored on the call verb plus the distinguishing status. — **Prevention:** every
    `src.replace()` mutation row carries `expect(mutated).not.toBe(src)`; anchor on the construct's
    stable head, not its full argument list.
11. **My first ground-truth derivation used `--name-status` and accepted a mode-only change** —
    caught by the pre-existing row 8. — Recovery: switched to raw `diff-index` format, which
    carries both modes. — **Prevention:** run the existing suite before believing a rewrite; the
    row that reds is telling you which shape the new derivation cannot see.
12. **I wrote the security learning's Prevention bullet recommending `--summary` hours before the
    review measured it as the third proxy.** — Recovery: a same-day addendum on that learning. —
    **Prevention:** the primary learning above; and a learning written the same session as the fix
    it describes should say so, because its confidence is the fix's confidence.

## Related

- `2026-09-18-my-fix-for-the-allowlist-bypass-shipped-a-second-bypass.md` (same directory) — the
  second proxy, with the addendum this session added.
- `best-practices/2026-07-02-inngest-side-effect-outside-step-run-duplicates-on-replay.md` and
  ADR-077 §3 — the replay mechanism, documented twice before it bit here.
- `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md` — the wire class.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — the
  stub-that-passes discipline.
- #7517 — the bash-suite sibling of the 174 vacuous vitest tests (#8315).
