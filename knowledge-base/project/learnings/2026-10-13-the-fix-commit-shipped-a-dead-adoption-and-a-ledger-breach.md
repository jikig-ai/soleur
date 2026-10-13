# Learning: the fix commit shipped a dead adoption and a ledger breach — review's fix round caught both

## Problem

PR #10189's main review panel produced 14 findings; the fix commit
(`4a6efd7707`) closed them and, in doing so, introduced three new defects the
panel had never seen — the classic least-audited-surface problem, measured
again:

1. **A silently-dead adoption block.** The new
   `plugins/soleur/skills/skill-security-scan/test/parse-override.test.sh`
   copied the opportunistic scratch-session adoption block from
   `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — including
   the literal `_SCRATCH_LIB="$SCRIPT_DIR/../../../scripts/lib/scratch-root.sh"`.
   The source suite sits 3 levels deep; the new one sits 5. `[[ -f ]]`
   failed by construction → `source` skipped → `begin` undefined → the whole
   block was inert in every environment, and the suite still reported 14/14
   green. THREE independent fix-round seats caught it; the suite itself could
   not, because the guard's design ("degrade, never block") erases the
   failure mode it was asked to measure.
2. **A meta-guard ledger breach.** The P2 fix "add an assertion floor" added
   `if (( PASS < 14 ))` — which made the suite floor-bearing under
   `guard-vacuity-floor.test.sh`'s sweep, in a `DEFERRED_DIRS` directory,
   growing the shrink-only ledger 47 → 48 past `MAX_DEFERRED`. The remedy
   (PROMOTED_FILES entry) is conventional — but nothing told the fix author
   the floor shape has ledger consequences until a seat ported the guard's
   derivation by hand.
3. **An unspliced cleanup.** The adoption bound a root but the suite's EXIT
   trap never named `_soleur_scratch_cleanup` — every clean run would have
   leaked a marker-bearing root, the exact class the PR pays down.

All three were invisible to the suite's own green. The verification-pass
fresh-eyes seat then caught two more P3s (CRLF block-map false-reject; no
tab-denial pin), both fixed in the same arc.

## Solution

- Path fixed to five `..`, the `[[ -f ]]` degrade replaced by load-bearing
  FATALs (missing lib, missing `begin`, missing `_soleur_scratch_cleanup` —
  each exits 2), and `_soleur_scratch_cleanup || true` spliced into the
  suite's EXIT trap per the lib's TRAP CONTRACT. Verified empirically: a run
  under a private TMPDIR binds a `soleur-run.*` root and the splice reclaims
  it.
- `parse-override.test.sh` PROMOTED as a FILE in `guard-vacuity-floor.test.sh`
  (narrative block + cumulative list append; `MAX_DEFERRED` untouched —
  shrink-only ratchet). Guard green 23/23.
- CRLF normalized (`sub(/\r$/,"")` at the top of the presence awk) and a
  tab-separation reject arm added.

## Key Insight

**A fix commit is a fresh diff with fresh defect surface — the fix round is
where the reviewed artifact actually converges.** Every defect above passed
the panel because the panel reviewed the pre-fix tree; the mechanism that
closed the loop was seats re-running their own repros against the fix range,
not a re-read of the branch.

Two transferrable rules:

- **A `[[ -f ]]`/`command -v` degrade guard makes a wrong path
  indistinguishable from an absent dependency.** When the thing being guarded
  is the point of the block (adoption, not optional decoration), the correct
  posture is fail-closed: assert the file exists, assert the function it
  should define exists after sourcing. "Never block the suite" applies to
  environmental failure (`begin` failing at runtime → `|| true`), not to a
  path that can only be wrong because the edit was wrong.
- **Adding a recognized floor shape to a suite under a `DEFERRED_DIRS`
  directory moves the vacuity-floor ledger — run `guard-vacuity-floor.test.sh`
  in the same commit** (or accept the promotion: literal bound on the `if`,
  reported by `echo`/`printf` + `exit` never through the suite's own
  helpers, instrument self-test). Same class for any ratcheted counter:
  the meta-guard's arm list lives in the file's own header — read it before
  touching a counted shape.

## Session Errors

1. **`_SCRATCH_LIB` copied at wrong relative depth** (`../../../` for a
   5-deep suite) — Recovery: fix-round seats caught it (3 seats converged);
   corrected path + FATAL-on-missing — **Prevention:** when porting a sourced
   block across depth boundaries, re-derive the path with `realpath -m` before
   committing, and assert the dep resolved (the suite now does).
2. **`(( PASS < N ))` floor grew the deferred ledger past MAX_DEFERRED** —
   Recovery: PROMOTED_FILES entry per the file's own ~15-documented
   precedents — **Prevention:** run `guard-vacuity-floor.test.sh` whenever a
   diff adds a floor shape under `DEFERRED_DIRS`; the guard's narrative
   convention is self-describing.
3. **Missing `_soleur_scratch_cleanup` splice in the new suite's EXIT trap**
   — Recovery: spliced per the lib's TRAP CONTRACT — **Prevention:** the
   adoption block is a 3-part pattern (source+gate, begin, stub+splice);
   porting only two thirds leaves a per-run root leak.
4. **Duplicate `[[ -f "$_SCRATCH_LIB" ]]` FATAL left after restructuring** —
   Recovery: deleted (seat flagged unreachable) — **Prevention:** re-read the
   block top-to-bottom after restructuring edits; a moved check leaves its
   shadow behind.
5. **Subagent context lacks Task-spawn** (forwarded from plan phase) —
   Recovery: inline substitution, recorded in decision-challenges.md —
   **Prevention:** pipeline documents the substitution explicitly; no new
   guardrail proposed.
6. **`pipeline-tally.sh incr` rejects multi-dimension calls** — Recovery:
   one incr per dimension — **Prevention:** one-off API shape; read usage
   before batching.
7. **`pgrep -f <suite>` self-matched the probing shell**, reporting a
   completed suite "STILL RUNNING" — Recovery: verified by log tail —
   **Prevention:** match on `/proc/<pid>/cwd` or exclude `pgrep`'s own pid.
8. **`sed` pattern missed a backticked literal** in the guard narrative —
   Recovery: applied via edit tool — **Prevention:** check `git diff` after
   programmatic edits; a silent no-match leaves a stale literal.
9. **Unguarded `grep -rn` wandered into `node_modules/`** — Recovery: scoped
   to the KB path — **Prevention:** scope sweeps with `--glob '!node_modules'`
   or `git grep` on tracked paths only.
10. **Phase-3 work agent hit a transient rate limit mid-flight** — Recovery:
    lead completed its verification sequentially — **Prevention:** transient;
    the on-disk artifact inspection pattern worked.
11. **Forwarded path guesses (earlier context):** `find` on a nonexistent
    `agents/` dir, an empty `CLAUDE_PLUGIN_ROOT` probe, and a guessed
    `git-tripwire.ts` location — Recovery: resolved real paths via
    `find -name`/`ls` before use — **Prevention:** one-off; verify a path
    exists before scripting against it.

## Null-guardrail note (Phase 1.5 step 3.6)

Item 1's class is now covered per-file by the FATAL-on-missing checks this PR
shipped. A *generic* guardrail — "every sourced adoption block must assert
its function resolved" — was considered and NOT wired: it is a lint over a
two-site pattern, and the convention is already pinned by the `test-all.sh`
exemplar + this file's own FATAL comments. If a third port slips, promote
then; per headless-mode rules a step-3.6 finding is never auto-accepted.

## Tags

category: workflow-issues
module: parse-override / scratch-session / review-pipeline
