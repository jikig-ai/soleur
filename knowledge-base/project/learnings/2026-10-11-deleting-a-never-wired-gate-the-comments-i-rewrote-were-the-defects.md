# Learning: deleting a never-wired gate — the comments I rewrote were the only defects

## Problem

Step B of the zot registry cutover deleted `zot-entry-gate.sh` (a pre-flip go/no-go script nothing
ever invoked), its test, and their two suite-registration rows, then fixed the comments that named
it. The deletion itself was clean: no code, workflow or test referenced the file, the registration
test and every floor stayed green, and the `ci-deploy.sh` diff was comment-only.

Eight of the nine review findings (three P2, five P3) were in the PROSE I wrote to replace the
dangling references, none in the deletion; the ninth was a pre-existing test-row gap. Each prose finding
fell to one command:

- `ci-deploy.sh` said the host probe's `tags/list` read "gets zot's real 403". Only the
  manifest-read 403 had ever been measured, and the probe has no 403 arm (it lands in the
  unexpected-code arm).
- `reusable-release.yml` said a deleted gate "once caught a missing/unsigned copy". The gate was
  never wired and only HEADed manifests, so it never caught anything and could not have seen a
  missing signature.
- `build-inngest-bootstrap-image.yml` said the web-1 probe "now reads" the inngest repo, a live-state
  claim, and said a blocking mirror failure "reaches Slack in both workflows" without the
  draft-exists condition on the BLOCKED step.

## Solution

Rewrite each sentence to state only what a command measured, and hedge the rest ("the `tags/list`
403 is not measured"). The `ci-deploy.sh` edit stayed comment-only, which is what lets the merge's
re-delivery apply be a no-op in behaviour.

## Key Insight

Removing a name from a sentence is authorship, not cleanup. The original text said "the
zot-entry-gate/soak-gate catch a missing/unsigned copy before the flip"; my first rewrite changed the
tense and kept the predicate ("the gate that once caught ... was deleted"), which preserved the
false premise while looking like a correction. When a referent is removed, either delete the whole
claim or re-derive the predicate against the surviving mechanism — never keep the predicate and
swap the subject. This is the additive twin of the dependent-clause re-pointing class in
`2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`.

Three independent seats (pattern, architecture, git-history) converged on the single unmeasured
`tags/list` claim without sharing a premise, which is the signal to treat a finding as real; the
coverage consult's added value on a PR this small was confirming that no code-behaviour class was
absent, not finding new ones.

## Session Errors

1. **A scripted `sed` batch on `tasks.md` failed to parse its second expression after the first had
   run** — Recovery: the error text named it; the 5.4 skip note was appended afterwards. Prevention:
   already covered by the `work` rule that a scripted multi-edit's success is read from the artifact,
   never from the run.
2. **A chained `sleep 240; cat` wait was blocked by the shell guard** — Recovery: switched to
   background completion notifications and a Monitor. Prevention: hook-enforced.
3. **Turn-ending text promised a next action and the Stop hook blocked it** — Recovery: ran the
   action (armed a Monitor) or ended with an explicit BLOCKED reason. Prevention: hook-enforced.
4. **`shellcheck` exited 1 on `ci-deploy.sh` and read as a failure until compared with
   `origin/main`** — Recovery: the 4 distinct findings were byte-identical to main's, so the diff
   introduced none. Prevention: compare a linter's findings against the base tree before reading a
   non-zero exit as caused by the diff.
5. **The fix round ran 4 of the 7 mechanically resolved seats** (pattern, code-quality, git-history,
   security; architecture, performance and agent-native were not re-run) — Recovery: disclosed in the
   review report; the fix diff was comment prose verified against code by the lead. Prevention: none
   needed, but the omission must be named whenever it is made.
6. **Eight unmeasured or overstated claims in my own rewritten prose** (above) — Recovery: fixed inline in two
   commits. Prevention: already stated in the `work` skill ("every causal or universal claim your
   prose ADDS needs its falsifying command run BEFORE you write it"); this session is a measured
   recurrence, not a gap in the rule.

## Tags

category: integration-issues
module: apps/web-platform/infra, .github/workflows, plugins/soleur/skills/ship
