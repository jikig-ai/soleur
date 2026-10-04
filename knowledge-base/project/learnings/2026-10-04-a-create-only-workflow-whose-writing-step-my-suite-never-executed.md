# Learning: the one step that writes state was the one step my 169-row suite never ran

## Problem

PR #9481 added `apply-web-escrow-create.yml`, a dispatch-only, create-only workflow that creates five Terraform resources
holding a LUKS passphrase copy (threshold: single-user incident). Its suite had 169 rows and 35 mutants, all green. A 13-seat
review still found a P1 in the step that writes state, and 12 P2s, almost all in the verification rather than the workflow:

- **The `apply` step read `rc=$?` under inherited errexit.** A step with no `shell:` key runs as `bash -e {0}`; `set -uo
  pipefail` cannot clear `-e`. A failed apply died at the `terraform` line and the recovery `::error::` (re-dispatch creates
  only the remainder; a secret not in state needs a person) was unreachable. The repo documents this class as ADR-170 and
  gates it with `lint-workflow-errexit-capture.py`, which fails on the new file in CI.
- **The suite never executed plan, init or apply.** Its stub `terraform` answered only `show -json`, and the harness ran
  step bodies under `bash -eo pipefail`, which is the explicit-`shell: bash` form, not what GitHub runs for this step. The
  apply step was pinned by regexes; a trailing comment (`-auto-approve # tfplan`), a double space, `-chdir`, an env-borne
  `TF_CLI_ARGS_plan`, or an extra step all passed them.
- **The names precondition restated literals.** A `name_of()` map (address to secret name) and a `CFG` literal were copied
  from the `.tf`, default-open (`*) printf ''` plus `continue` skipped an unmapped secret), and a missing names file was read as
  "all absent". A repointed `config` (override file) or renamed secret would create over a live key with the suite green.
- **My own fixes introduced a second wave:** a runbook `doppler secrets delete` with no `-y` (fails EOF non-interactively), a
  verify `grep -cx` over a bordered table (always 0, and exits 1 on the success path), the delete placed before the
  inherited-name stop rule, a Summary that started printing a block to stdout (workflow-command injection through an
  unvalidated `plan_only`), an inert-mutant "scorer control" whose polarity could not detect a scorer that always says
  killed, and a stub env var named `TF_LOG` that collided with the new `unset TF_LOG` in the code under test.

## Solution

- Execute every step body that mutates or decides, under the shell GitHub really uses (`bash --noprofile --norc -e` for a
  step with no `shell:`), against stubs that log argv and the env they saw; assert the failure branch (`rc=7` plus the
  annotation), not only the happy path. Pin whole argv, not a regex over the file.
- Derive what a guard checks from the graded artifact, not from a copy: the gate now reads `after.project/config/name` of
  every `doppler_secret` create from the plan JSON, refuses an absent or wrong field, and writes the names the live check
  uses; the suite ties names, project and config to the `.tf` files (T37).
- A scorer control must be able to say "survived": a decoy spec (`DECOY:T1`, an inert edit scored against a row it cannot
  redden) must be reported SURVIVED, and the suite fails if the scorer says killed.
- Pin every hygiene line a fix adds (umask, EXIT trap, `persist-credentials`, `working-directory`) with a row and a mutant;
  deleting each had left the suite green.
- Print a sentinel for empty fields (`@tsv` plus IFS tab collapses empty columns and mislabels the destination).

## Key Insight

A suite's coverage is bounded by which step BODIES it actually executes and in which SHELL, not by how many rows it has: the
rows were dense around the guards the author was thinking about (gate, names, reader) and absent around the step the guards
exist to protect. Ask of any workflow suite: *name each step that writes, and the row that runs it to failure under the
production shell.* And a name, config or address list a guard compares is only a guard if it is read from the artifact being
graded; a restated copy is a second declaration that drifts silently.

## Session Errors

1. **A Bash call whose text contained `git stash list` was blocked** (`hr-never-git-stash-in-worktrees`, hook). Recovery:
   re-ran without it. Prevention: the hook already enforces it; avoid the word in diagnostics.
2. **The harness lacked `GITHUB_SERVER_URL`** so the validate step died under `set -u` (3 rows red). Recovery: added the
   `GITHUB_*` variables to the harness env. Prevention: a step harness must set every variable the real runner sets and the
   step reads (derive the list from the step body).
3. **A `grep` printed four 3 KB `PROMOTED_FILES` lines** (`hr-never-run-commands-with-unbounded-output`). Recovery: continued
   with `cut`. Prevention: pipe `cut -c1-200`/`head` on any grep over a file known to hold long lines.
4. **Two patch scripts failed on nested triple quotes** (the mutant block lived inside a Python string). Recovery: wrote the
   block to a file and read it. Prevention: when a patch must embed code that itself contains quotes, write it to a file.
5. **The `doppler secrets delete` text in my runbook edit was blocked by the repo hook** (a real defect: the command printed
   all remaining secrets). Recovery: added `> /dev/null`; a review seat then found the missing `-y`. Prevention: run each
   command the docs prescribe (flags via `--help`, or a probe with an invalid token) before writing it.
6. **The step harness ran under `-eo pipefail`, not GitHub's `bash -e {0}`**, and never ran apply: a P1 shipped past 169 rows.
   Prevention: see Solution; the review skill's defect-class list now carries the shell-and-execution check.
7. **A harness env var named `TF_LOG` collided with a new `unset TF_LOG` in the code under test.** Recovery: renamed to
   `STUB_TF_LOG`. Prevention: namespace every stub variable (`STUB_*`).
8. **`test-infra-privileged-tier-census` G4c failed because the branch was behind `main`** (two `.tf` resources landed after the
   fork). Recovery: merged `origin/main`. Prevention: a base-ref ratchet that fails with no related diff is a staleness signal;
   merge main before diagnosing.
9. **The history seat reported unverified or wrong facts** (a "600+ line addendum" for a ~59-line one). Recovery: treated its
   report as weak evidence. Prevention: a shallow all-sound report from a seat is not coverage; weigh by what it measured.

Triage: items 1, 3, 4, 8, 9 one-off; 2, 5, 6, 7 recurring classes, folded into this PR (fix-now-inline) and the review skill bullet.

## Tags
category: test-failures
module: .github/workflows, apps/web-platform/infra
