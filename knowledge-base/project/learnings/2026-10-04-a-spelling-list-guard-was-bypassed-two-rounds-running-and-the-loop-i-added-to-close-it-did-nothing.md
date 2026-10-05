# Learning: a guard built from a list of bad spellings was bypassed two review rounds running, and the loop I added to close one gap was inert

## Problem

PR #9474 adds a dispatch-only, read-only workflow (`web-host-escrow-diagnose.yml`) that holds the workplace Doppler token. Its
shape suite had to prove "this step can run nothing else". Round 1 built that as word lists (a command denylist, a redirect
allow-list, a token-expansion regex). A security seat showed a one-line edit (`printenv TOKEN | rev >> $GITHUB_STEP_SUMMARY`)
passing 107/107. I widened the lists and added a restricted-PATH execution net. Round 2 found the next bypasses (awk `ENVIRON`, a
bare `export`, `timeout`/`awk`/`sed` running a program of their own, an absolute path, `>|`). Two consecutive rounds, two
fresh spellings each: the property is a capability, and a spelling list cannot express a capability.

Three smaller defects had the same root (a check certifying something narrower than its name):

- `while IFS= read -r _ _ f; do unset -f "$f"; done < <(declare -Fx)` never split the line: `IFS=` empty puts the whole line
  into the first variable, `f` is empty, nothing is unset. It looked right and passed every row until a row planted an
  exported function.
- The runbook's `gh run view --log | grep -E 'Verdict:|escrow-split-contract:'` also matches the step's echoed script source
  (GitHub prints the `run:` body into the log), including a `PASS ... live-ok` assignment, on every run. Four seats found it.
- The verification pass found S6 accepted any 40-hex `actions/checkout@` SHA, so the comment "any edit moves the pin" was false for
  the one step that runs before the loader.

## Solution

- Pin the artifact, not the spellings: S16 hashes the check step's normalised body (comments and blank lines dropped, trailing
  spaces/tabs trimmed, a `#` line after a `\` kept). Any edit to what the step runs, in any spelling, reds the suite and must be
  re-pinned in the same diff, where a reviewer sees it. State honestly what that is: it makes a change visible, it is not an
  integrity control (one PR can move workflow and suite together, and no ruleset requires review). Keep the word lists as
  diagnostics, not as the claim. Pin the neighbouring steps exactly too (S5 loader inputs, S6 the checkout SHA, S17 other run
  steps are no-ops).
- Every loop whose purpose is to remove something needs a canary of that thing in the harness (a planted `BASH_FUNC_x%%`
  exported function), and a body mutation that deletes the loop must red.
- A runbook command that reads a CI log is tested by extracting it FROM the runbook text and running it over a log shaped like
  the real one (job/step/timestamp prefix, echoed script wrapped in colour codes). Anchor on the emitted line's structure
  (`Z Verdict: `), take the last such line, and never test for `live-ok`/`PASS` as bare substrings.
- Put what an agent needs in the run LOG: `gh` exposes no job-summary field.

## Key Insight

When a guard's property is "nothing but X can happen", a list of what must not happen loses to the next spelling, twice in a row.
Replace the heuristic with an identity pin on the artifact plus a plain statement of what the pin does not establish, and
falsify every sentence the fix itself adds ("any edit moves it", "re-run window is 90 days": it is 30) before claiming it.

## Session Errors

1. **`IFS=` read loop inert** — Recovery: `read -r _k _t f` without `IFS=`, caught by the new `c_fn` row — Prevention: plant a canary of what a removal loop removes; mutate the loop out and require RED.
2. **Spelling-list guard bypassed two rounds running** — Recovery: S16 body-hash pin — Prevention: after the second fresh bypass of a word list, pin the artifact instead of widening the list.
3. **S6 accepted any 40-hex checkout SHA** — Recovery: exact SHA pin and a swap mutation row — Prevention: when a comment claims "any edit moves X", list every input of the step and pin each one.
4. **Runbook log grep matched echoed script source** — Recovery: timestamp-anchored pattern, a suite row that runs the runbook's own grep over a real-shaped log — Prevention: extract the command from the doc and run it over a real log shape.
5. **I wrote "re-run for 90 days" (it is 30) and `timeout 900` (over the 600 s foreground tool ceiling)** — Recovery: both corrected — Prevention: falsify each universal sentence a fix adds; check a documented wait against the agent tool's ceiling.
6. **Security fix-round seat stopped on a safety classifier** (brief said "construct a working leak edit") — Recovery: re-sent a defensive brief (re-run your own repro, read predicates, name gaps) — Prevention: brief adversarial seats defensively; routed into the review references.
7. **Fix commit added actionlint SC2030/SC2031** (`read -r _ _ f` in a subshell) — Recovery: named the throwaway variables — Prevention: run actionlint after touching a `run:` block.
8. **I reported "2 of 7 seats" when it was 10 of 12; the stop hook flagged an unkept promise** — Recovery: corrected with a `<stop>` tag — Prevention: re-derive the count from the seat list before quoting it.
9. **`git add -A` committed a temp `node_modules` symlink (earlier segment)** — Recovery: `git rm -f`, amend — Prevention: path-scoped `git add`.
10. **Merge conflict, mid-merge false REDs, rule-body-lint over by 1311 bytes, two CodeQL alerts (earlier segment)** — Recovery: union resolution; moved bullets to references; fixed regexes — Prevention: none new.
11. **Forwarded: plan draft rejected by the Write hook (literal secret-write text); two `sleep` calls blocked** — Recovery: reworded, switched to Monitor — Prevention: existing hooks cover it.
12. **Foreground repo-wide grep and checker suite hit the 120 s tool timeout** — Recovery: ran in background — Prevention: background anything repo-wide.
13. **History seat cited commit `72ed4697af` as prior art; it exists but is on another branch, not main** — Recovery: verified with `git cat-file` and `git ls-tree origin/main`, not relied on — Prevention: verify a seat's cited commit before using it.
14. **C8 could not run locally: no acceptable Doppler credential on this machine (earlier segment)** — Recovery: built this read-only workflow so the check runs in CI — Prevention: none new; the PR is the fix.

## Tags
category: logic-errors
module: web-host-escrow-diagnose workflow, review process
