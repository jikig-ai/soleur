---
title: A new workflow job moved other suites' anchors, and a lint fix hid sites from a ratchet
date: 2026-11-23
category: test-failures
module: apps/web-platform/infra (bastion first-boot rehearsal), .github/workflows/infra-validation.yml
tags: [ci, workflow, mutation-testing, ratchet, allowlist, review, cloud-init]
issue: 12941
pr: 12995
---

# Learning: a new workflow job moved other suites' anchors, and a lint fix hid sites from a ratchet

## Problem

PR #12995 added a first-boot rehearsal suite and one CI job. Three things went wrong after the suite itself was already passing.

1. **The registration gate kept losing to sibling spellings.** The gate refused named bad forms of the new job (`|| true`, `secrets.X`, a second `bash <path>`). Round 1 closed 13 listed shapes. Five reviewers then found more: `shell: true {0}`, a `$GITHUB_ENV` pre-step, `toJSON(github)`, `bash -x <path>`, a composite action, a glued job with a commented header.
2. **Inserting the job broke suites that never mention it.** The job went between `deploy-script-tests-fixed` and `deploy-script-tests-done`. At least five other suites hold mutation rows anchored on that boundary or on the aggregator's literal `needs:` list:
   - `betterstack-alert-structure` M-15b/c/d inserted a key before the `deploy-script-tests-done:` header, so it landed on the new job and the mutation "survived".
   - `workspaces-luks-deadman-fired-alert`, `sandbox-alerts`, `registry-zot-credential-shape-alert` and `registry-clientip-not-rfc1918-alert` all pin one literal: the `fi` that ends the last step, a blank line, then the `# Aggregator (#8736)` comment. The inserted job sat between them, so the literal no longer existed.
   - `registry-clientip-not-rfc1918-alert` A1 also matched the three-name `needs:` list verbatim, which the new job extended.

   The first CI run showed betterstack (leg 2/4) and the LUKS row (`deploy-script-tests-fixed`, step 11) together. Every later step of that job stayed hidden behind the LUKS failure. Moving the job restored the shared literal, and only then did A1 go red, at step 18 on a later push.
3. **A shellcheck fix silently lowered a ratchet.** Changing `rm -rf "$SB/$X"` to `rm -rf "${SB:?}/${X:?}"` (SC2115) made `fixture-scan.py` read `${SB:?}` as a guard for the writes below it. The count for that file fell from 9 to 4 while all five `git -C "$SB" add` lines were still there. The gate's failure text offers "LOWER: a real remediation", and I regenerated the baseline before checking which lines had gone.

## Solution

1. Replace the denylist with an allowlist for the one job the gate owns: exact job keys, step kinds, `with:` keys and `${{ }}` expressions, one anchored `run:` line, and one non-comment mention of the suite across all workflows and actions. The gate's header states what remains outside it (the allowed actions, the runner image, a future `workflow_call` caller).
2. Move the job after the aggregator, and change row A1 to delete one list element (`deploy-script-tests-fixed,`) so a later job cannot drift it.
3. Revert the `${SB:?}` edit, silence SC2115 with a directive, and restore the baseline. The count returned to 9.

## Key Insight

- **A job's position in a workflow file is an interface.** Other suites' text anchors depend on who sits next to whom. Before inserting a job, grep the test corpus for both neighbours' names, the comment above the next job, and the literal `needs:` list.
- **When a ratchet count goes DOWN, list the sites that disappeared and confirm each line changed.** A site that is still in the file and no longer counted means the scanner was fooled. `:?` rejects an empty value, not a relative one.
- **Stop adding spellings at the second sibling round.** When the guarded object is one job the repo owns, confine it to what the checker models.

## Session Errors

1. **Plan Write blocked by the IaC hook on `systemctl` words.** Recovery: `iac-routing-ack` marker. **Prevention:** already hook-enforced.
2. **`plan-sharp-edges` read by keyword, not in full.** Recovery: deepen pass. **Prevention:** existing plan skill instruction.
3. **Plan carried three false claims (the job gates merges; `-b` scopes container boots; the offline fixture covers stub routing).** Recovery: deepen corrected them. **Prevention:** existing measure-before-claiming rules.
4. **Fix brief written under the shared git dir; hook refused it.** Recovery: scratchpad. **Prevention:** already in the review reference (#9505).
5. **Trio census rerun used a wrong path (rc 127).** Recovery: `tests/scripts/test-trio-baseline-census.sh`. **Prevention:** one-off.
6. **Shell cwd reset between calls.** Recovery: `cd` into the worktree in each call. **Prevention:** existing harness behaviour; use absolute paths.
7. **`fix-round-seats.sh --files` given a space-separated list; read as one path.** Recovery: newline-separated list. **Prevention:** its documented call uses `changed-paths.sh` output.
8. **`--finding-seats` given a full agent id (`unknown-seat: observability-coverage-reviewer`).** Recovery: added that seat by hand. **Prevention:** read the script's stderr before spawning, as done here.
9. **`ps | awk` wait pattern blocked as self-matching.** Recovery: walked `/proc/*/cwd`. **Prevention:** already hook-enforced.
10. **`rm -rf "$L"` blocked because the hook could not resolve the variable.** Recovery: literal path. **Prevention:** already hook-enforced.
11. **Fix agent A parked on background waiters for hours; its last batch never finished.** Recovery: the lead killed it and ran one combined battery. **Prevention:** existing rule that fix agents finish in the foreground; the brief did not repeat it.
12. **A reviewer's sandboxes vanished mid-run and its driver then mutated the live worktree's template.** Cause of the deletion not established. Recovery: restored the file, confirmed a clean tree at the same HEAD. **Prevention:** drivers use `cd "$SBX" || exit 99` and re-check the directory before each mutation (added to the round-2 briefs).
13. **Job insertion broke at least five sibling suites' anchors, and a failed CI step hid some of them until a later push.** Recovery: job moved, A1 rewritten. **Prevention:** new bullet in `plan-sharp-edges.md`; the existing "select suites by the names edited" brief rule also applies and was not followed.
14. **Runbook code span failed markdownlint (MD038) only in CI.** Recovery: reworded. **Prevention:** include markdownlint on changed docs in the fix-agent battery.
15. **A fix moved the work dir to an env-supplied base and added 77 ratchet sites.** Recovery: `$TMPDIR` for both the work dir and the sweep. **Prevention:** existing rule to brief fix agents on repo-global ratchets by name; the round-2 brief listed neither fixture ratchet.
16. **`${SB:?}` hid five sites and I regenerated the baseline before diagnosing it.** Recovery: reverted both. **Prevention:** new bullet in the review reference.
17. **Round 1's gate fix closed spellings rather than the class.** Recovery: allowlist in round 2. **Prevention:** existing guidance on confining the guarded file to the checker's subset.
18. **The job-move commit claimed all sibling anchors were fixed; the verifier found one more (A1).** Recovery: A1 fixed. **Prevention:** grep every anchor before claiming; CI hides later steps after a failure.
19. **`TaskStop` on an agent that had already exited returned "no task".** Recovery: none needed. **Prevention:** one-off.
20. **I suspected the suite leaked root-owned work dirs; the failure came from my own `find -user` filter.** Recovery: read the cleanup path. **Prevention:** one-off.
21. **The branch went stale during the long run and conflicted with main in `guard-vacuity-floor.test.sh`.** Recovery: merged, kept both promoted entries, re-ran the affected checks. **Prevention:** existing pre-review merge check; repeat it before arming merge.
