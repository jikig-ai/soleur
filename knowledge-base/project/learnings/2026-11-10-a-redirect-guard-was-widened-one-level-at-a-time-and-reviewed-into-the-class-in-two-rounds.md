# Learning: a redirect guard was widened one level at a time, and two review rounds were needed to reach the class

## Problem

Host-side git (git the server runs outside the agent sandbox, in a workspace whose `.git` an agent session authored)
was moved onto one shared helper (`server/host-git.ts`, Ref #9601). The first implementation closed the carriers the
plan listed, and the first review panel (13 seats) found carriers the plan had not listed. The fix for each one closed
the INSTANCE the reviewer measured, not the CLASS, so the next round found the next instance:

- A `.git` that redirects to another repository: the guard refused `commondir` and a symlinked or gitfile `.git`. Round 1
  measured symlinked `refs/` and `objects/` entries, `objects/info/alternates` and `info/grafts`. The fix then scanned
  ONE level below `.git`. Round 2 measured `refs/heads/<x>` and `logs/**` symlinks one level further down. The final
  guard walks `refs/` and `logs/` recursively (bounded) and the comment says what it still does not examine.
- A remote that resolves a push by NAME: the explicit-URL push was meant to close `remote.git-data.pushurl`. A remote
  NAMED by the explicit URL defeated it (git resolves the argument as a remote name first). The first fix refused every
  `remote.<name>.*` key except two names, which refused an ordinary `upstream` remote and `remote.pushDefault`; the
  final rule refuses only URL-shaped names.
- A `-c` hardening block cannot beat a global `--git-dir` in argv. The first argv check scanned the tokens before the
  subcommand but only knew to skip the value of `-c` and `-C`, so a value-taking global (`--attr-source HEAD
  --git-dir=X`) hid it. The final rule allowlists the pre-subcommand tokens instead of denylisting names.
- A refusal that fails closed was SILENT at the first gate (`hasRemote` swallowed it as "no remote"), so the new
  reporting code was unreachable. Two seats (user-impact, data-integrity) found it independently.

The same PR family had written this lesson down the day before (`2026-11-09-a-guard-rewrite-closed-the-reported-bypass-and-opened-two-narrower-ones.md`),
and the review header already says to check whether a fix was applied to the instance or the class. Knowing the rule
did not stop the first fix round from repeating it.

## Solution

- Enumerate the class from the mechanism, then WALK it: the question for a redirect guard is "what else under this
  directory can make git read or write another repository's store", answered by a bounded recursive no-symlink walk plus
  a list of files whose presence redirects (`commondir`, `alternates`, `http-alternates`, `grafts`), not by a list of the
  paths a seat happened to measure.
- Allowlist, do not denylist, when the input is a command line: the helper now accepts only `-C`, `-c` and three
  argument-less globals before the subcommand and refuses every other dash token.
- Make each reachable refusal observable at the FIRST gate that can see it, with a test that asserts the report, not
  only the effect. A mutation that removes the report must fail a test.
- Run the mutation battery against every new control and read the SURVIVORS: seven of the mutants that first survived
  were real gaps (a census that only matched identifier-valued `allowProtocol`, a provisioning pre-check with no
  observable effect, a refusal report nothing asserted). Each was closed by a test that discriminates, then re-killed.
- Fixing the class also means fixing the prose: the same sentence ("symlinks deeper than X are not examined") had to be
  made true in the code comment, the ADR addendum, the plan addendum and the PR body, and a verification seat still
  found one stale paragraph.

## Key Insight

A reviewer's measurement names an instance. The fix is the class, and the class is found by asking "what is the
mechanism, and what else does it reach", then proving the guard by walking the mechanism rather than by listing the
measured members. A depth-N scan, a list of N remote names and a denylist of N option names each closed exactly what
had been measured and nothing else. Budget two review rounds for a guard whose input an adversary controls, and brief
the second round on the CLASS ("what other member of this family does the fix still miss"), not on the repro.

## Session Errors

- **A hook rejected a Bash call that created paths and committed in one invocation.** Recovery: split into separate
  calls and wrote the spike as a script file. Prevention: one concern per Bash call in a worktree with the guardrail
  hook; already enforced by the hook, no new rule.
- **The technical-ruling gate rejected decision-challenges rows whose shape was not "Ruled by CTO agent, <date>: ...".**
  Recovery: rewrote the rows and reclassified mechanical rows as `taste`. Prevention: write ruling rows in the gate's
  shape the first time; the gate message already names it.
- **The `no-unused-vars` ESLint baseline grew 74 to 75 (an unused import).** Recovery: used the import in real rows.
  Prevention: run the repo's lint on the touched files before committing, not only the suites.
- **A literal `StrictHostKeyChecking=no` in a test tripped the no-TOFU scanner.** Recovery: assembled the string from
  two literals. Prevention: assemble forbidden-literal fixtures at runtime; the scanner's message says so.
- **Restructuring `git-auth.ts` broke two mutation anchors in `approval-guard1-mutation.test.sh`.** Recovery: restored
  the hardened arm's lines byte-identical. Prevention: before editing a file, `git grep` for tests that anchor on its
  source text (they are invisible to a file-selected run).
- **CI failed a parity test (`git-data-stale-clone-push.test.sh`) that pins the replication push argument text.** The
  local file-selected run could not see it. Recovery: updated its two anchors. Prevention: after changing a server
  file, `git grep -l '<file>.ts'` across `*.sh`, `*.py`, `*.yml` and `scripts/` and run those suites by name (this is the
  existing "file-selected run cannot see a repo-global pin" rule, applied late).
- **The pre-push gate was SIGKILLed (exit 137) while seven review seats were running on the same host.** The gate gave
  no verdict. Recovery: treated CI as the verdict. Prevention: do not run the local gate while a panel is running; it
  needs the memory the seats use.
- **The mutation harness's pristine-file list did not include a file one mutant edited (`ensure-workspace-repo.ts`),
  so a failed run left the source mutated.** Recovery: `git status` showed it; `git restore --source=HEAD` fixed it.
  Prevention: derive the pristine list from the mutant table instead of keeping a second list, and always end a battery
  with `git status --short` (the harness's own restore check did catch it).
- **The harness's restore check failed on uncommitted edits to a file it also mutates.** Recovery: commit before a
  battery. Prevention: the battery should refuse to start on a dirty tree.
- **Two self-written controls were vacuous.** A "the foreign repository moved" control compared `count-objects` output
  to the empty string (always true), and an `ext::` control ran under a fixture environment that already excluded `ext`.
  Recovery: caught on self-review, replaced with a before/after comparison and a bare environment. Prevention: a
  control must be run against its own negative once (the lead's mutation battery now does this for the guards).
- **A fix landed one level short, twice.** See Problem. Prevention: brief fix rounds on the class, and walk the mechanism.
- **A fixed census regex matched only identifier values, so a string-literal `allowProtocol` passed it.** Found by a
  surviving mutant, not by review. Recovery: match any value token. Prevention: mutate the census itself.
- **I left a stale paragraph in the PR body twice** (a file listed as unhardened after it was routed through the
  helper; "not measured" for writes that were measured). Prevention: after a routing change, grep the claim's SUBJECT
  (the file name) across the ADR, plan, PR body and test comments, not the old phrase.

## Tags

category: security-issues
module: apps/web-platform/server/host-git
