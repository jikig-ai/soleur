---
title: "feat(engineering): Spec Kit ingestion — consume specs/<NNN>-<name>/ directories as brainstorm/plan input"
type: feat
date: 2026-11-11
slug: feat-spec-kit-ingestion
branch: feat-12531-spec-kit-ingestion
issue: 12531
closes: 12531
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(engineering): Spec Kit ingestion

## Overview

Brainstorm and plan today take free text. This change adds one read-only script under `plugins/soleur/` that those two skills call when the argument is a directory whose last two segments are `specs/<prefix>-<short-name>/`. The prefix is a 3-digit number or a `YYYYMMDD-HHMMSS` timestamp. The script reads `spec.md` (required) and, when present, `plan.md` and `tasks.md`. It projects `spec.md` into the existing Soleur spec template, lists every heading that does not fit in an unmapped appendix, and prints a receipt of what moved, what stayed unmapped, and which names were never opened. `plan.md` and `tasks.md` stay side evidence. Plan still writes Soleur's own `tasks.md` from the projected spec. A missing `spec.md`, any symlink on the directory or on an allow-listed name, or a file over the byte cap stops the intake. If the Soleur spec file already exists, the caller does not run the script and does not replace that file. Customer spec bodies stay out of the Soleur product tree. The change adds no `soleur:go` routing row and no public compatibility claim.

## Research Insights

### Premise Validation

Checked 2026-11-11 before research. Issue #12531 is OPEN and `closedByPullRequestsReferences` is empty. Parent epic #12533 is OPEN. Sibling #12529 is CLOSED by merged PR #12568; that closure is the epic's clean-room precedent, not a resolution of this intake. No ADR matches `Spec Kit`, `spec-kit ingestion`, `external spec directory`, or `specify init`. Collision pre-check exit 10: the only open PR naming #12531 is this branch's draft PR #12653. Foreign `test-all.sh` processes belong to other worktrees and are not an implementation of #12531. Premise holds.

### Property List

1. A directory argument whose final two segments are `specs/<prefix>-<short-name>/` (prefix 3-digit or `YYYYMMDD-HHMMSS`) is intake. A prose mention of that shape is not.
2. Intake reads `spec.md` and stops when that file is missing, unreadable, or not a regular file inside the named directory. The path string is not then used as the feature description.
3. `plan.md` and `tasks.md`, when regular files in that directory, are side evidence. A missing file is receipt `absent`. Their text is not copied into Soleur requirements or Soleur task ids.
4. A user-story heading is an ATX heading whose text contains the case-insensitive tokens `user story` in that order. A standalone `P1` in that heading text, with no standalone `P2` or `P3` in the heading and no `NEEDS CLARIFICATION` in the body, becomes a functional-requirement candidate. The priority token is read from the heading text only. Success criteria become goals. Explicit exclusions become non-goals. Every other heading is an unmapped appendix that is not built from, including a story with no standalone `P1` and a section whose body contains `NEEDS CLARIFICATION`.
5. A receipt listing what moved, what was unmapped, and what was never read exists before the projected Soleur spec is the build contract. A second ingest does not overwrite an existing Soleur spec.
6. The reader does not recurse, follow markdown links, open any name other than the three allow-listed files, write into the source tree, or run a spec initializer.
7. The directory is resolved from the invoking cwd before any worktree `cd`. A symlink on any path component, or on an allow-listed name, fails the whole intake. A file over the byte cap fails the whole intake. `soleur_approval_realpath` is not used.
8. Tests use synthesized fixtures. The Soleur product tree does not commit a customer spec body. The receipt does not print an absolute filesystem path.
9. Brainstorm calls the reader before the empty-description question and the clear-requirements shortcut. Plan calls it on first entry when no Soleur spec exists yet, and reads the Soleur spec afterwards.
10. Docs for this change do not claim Spec Kit support, compatibility, or a partnership.

### Cut List

- Folding `plan.md` and `tasks.md` into the Soleur spec. Property 3 says they stay side evidence. Brainstorm Approach B.
- Skill prose that tells the model to open the directory. It does not buy properties 2, 6, or 7. Brainstorm Approach C.
- A new `soleur:go` routing row. Property 1 is a call inside the existing brainstorm route.
- `one-shot` `FILE_PATH_TARGET` in `plugins/soleur/skills/one-shot/SKILL.md` (anchored `^[^\s]+\.(md|json)$` plus `test -f`). It matches a file, not a directory, so it does not buy property 1. Left as-is.
- Free-text `#$ARGUMENTS` in brainstorm and plan. It does not detect a directory. The script is the mechanism that does.

No issue mechanism is cut because a repo mechanism already buys its property. Authority: `plugins/soleur/skills/{brainstorm,plan,one-shot,go}/SKILL.md` and a `plugins/soleur` search for `spec-kit|ingest-spec|external.spec`.

### Local patterns

- Call site, brainstorm: `plugins/soleur/skills/brainstorm/SKILL.md` heading `## Feature Description`, before the empty-description question and before Phase 0's `cd .worktrees/feat-<name>`. Both clear-requirements arms pass the absolute directory captured before that `cd`.
- Call site, plan: `plugins/soleur/skills/plan/SKILL.md` heading `### 0. Load Knowledge Base Context (if exists)`, only when `knowledge-base/project/specs/<branch>/spec.md` is absent.
- Do not call `soleur_approval_realpath` (`plugins/soleur/scripts/lib/operator-script.sh`). On failure it prints the unresolved path and returns 0.
- Fail-closed shape to copy, not source: `plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh` refuses a symlink before reading (tested by `plugins/soleur/test/ship-pir-action-items-gate.test.sh`). Ruled by CTO agent, 2026-11-11: an allow-listed name is read only when it is a regular file reached without following a symlink. A symlink to another name in the same directory is a refusal, because that would open `research.md` through `spec.md`. `plugins/soleur/scripts/domain-model-drift.sh` uses `realpath -e` and refuses a path outside `--repo` in its read-only modes. Do not source that file (`init` writes).
- Tests: `plugins/soleur/test/*.test.sh` is registered by `scripts/test-all.sh`. Shared script, shared suite: `plugins/soleur/test/spec-kit-intake.test.sh`. Fixtures under `mktemp`.
- No code on this worktree reads an external `specs/<prefix>-<short-name>/` as intake. The blog mention in `plugins/soleur/docs/blog/why-most-agentic-tools-plateau.md` is not a reader.

### Learnings that constrain the script

- `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md` — fail the process on a canonicalize error. Do not fall back to an unresolved path.
- `knowledge-base/project/learnings/security-issues/2026-10-27-exported-containment-primitives-must-self-validate.md` — a last-component `O_NOFOLLOW` still allows an intermediate link. Pin the directory, then open the three basenames.
- `knowledge-base/project/learnings/2026-04-07-symlink-escape-recursive-directory-traversal.md` — do not walk the tree. Open each path component from its parent directory file descriptor. Do not `lstat` a path and then open that same path.
- `knowledge-base/project/learnings/2026-05-15-one-shot-plan-subagent-cwd-divergence.md` — absolutize from the invoking cwd before any worktree `cd`.
- `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md` — parse only the first `---` block.
- `knowledge-base/project/learnings/best-practices/2026-06-05-render-off-tree-return-bytes-and-drop-toctou-with-the-reread.md` — return bytes to the caller. Do not copy them onto a tracked product path.
- `knowledge-base/project/learnings/best-practices/2026-07-23-mirror-measurement-authority-exactly-not-equal-under-a-current-invariant.md` — enforce the byte cap on `fstat` size before the read.
- `knowledge-base/project/learnings/best-practices/2026-11-03-file-system-race-beyond-open-once-proc-fd-reopen-and-held-fifo-handle.md` — reject a non-regular file before reading.
- `knowledge-base/project/learnings/best-practices/2026-06-12-plan-observability-claim-of-per-file-catch-vs-outer-loop-catch.md` — one bad file fails the whole intake. No partial side file in the output.
- `knowledge-base/project/learnings/best-practices/2026-05-20-script-idempotency-and-plan-precondition-reverify.md` — the overwrite test starts from an existing spec and asserts the bytes are unchanged.
- `knowledge-base/project/learnings/test-failures/2026-06-08-onofollow-symlink-test-target-must-be-inside-workspace.md` — the escape fixture stays lexically inside the directory and points outside. Assert a sentinel in the target was never read.
- `knowledge-base/project/learnings/logic-errors/2026-10-05-closed-set-exit-5-reopened-trackers-and-my-probe-suite-never-ran-the-sweepers-entry.md` — invoke the script the way the skill invokes it.

### Functional overlap

Community discovery found no uncovered stack (no flutter, rust, elixir, go, swift, kotlin, or php signature at the repo root). Functional discovery queried three registries and installed nothing. The overlaps wrap the Spec Kit CLI or author specs. They are not a fail-closed projector into Soleur's template. Skip all of them. `github/spec-kit` and `hmuhlestein/HephaestusNG` were not fetched.

### External research decision

Path containment is security-sensitive. The twelve learnings above are this repo's record of the same failure class (symlink escape, last-component-only checks, cwd rebind, frontmatter over-match, cap measured after a strip, FIFO read). Two in-repo readers already show the fail-closed shape. A second survey of generic bash manuals would not change the mechanism Phase 0.6b kept. External research is skipped for that reason.

### Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| TR2 resolves the directory from the invoking cwd before any worktree `cd`. TR6 runs the script on first plan entry when no Soleur spec exists. | Brainstorm's `cd` is in Phase 0, after `## Feature Description`. Direct plan does not `cd`. One-shot `cd`s before it invokes plan. `FILE_PATH_TARGET` does not match a directory. | Call the script at the brainstorm site above, before Phase 0's `cd`, and pass `--cwd`. Plan calls it only when the Soleur spec is absent. Both clear-requirements arms forward the absolute directory captured before that `cd`. One-shot does not edit `FILE_PATH_TARGET`. |
| FR5: a second ingest does not overwrite an existing Soleur spec, including a zero-byte file. TR1: the script does not write. | Brainstorm Phase 3.6 always saves `spec.md`. There is no existence check. | The script prints the receipt and the projected body and writes nothing. Phase 3.6 step 4 does not generate a second spec when a projected body exists. Step 5 does not save over an existing `spec.md`. Existence is the stop. There is no human-edit detector. |
| FR4 projects into the Soleur spec template. | `plugins/soleur/skills/spec-templates/SKILL.md` heading `## spec.md Template` is Problem, Goals, Non-Goals, Functional Requirements, Technical Requirements, and has no frontmatter. Phase 3.6 requires `lane:` and `brand_survival_threshold:`. | The projected body carries that frontmatter plus those sections. Kit headings that are not those sections go only in the unmapped appendix. `lane` stays `cross-domain`. Threshold stays `single-user incident`. |
| TR2 fails the whole intake on any symlink, including a same-directory link, and on a file over the byte cap. | No reader implements this intake. | One constant: 1048576 bytes, `fstat` on the opened descriptor before read. Size equal to the cap is allowed. The directory fd is an `O_NOFOLLOW` walk from `/`. Any symlink is a refusal. |

## Problem Statement / Motivation

Issue #12531: teams that already have `specs/<NNN>-<name>/{spec,plan,tasks}.md` retype that material into brainstorm. The intake is the gap. Demand is unconfirmed. The operator declined to say whether anyone has arrived with a folder. The plan still builds the intake the issue asked for, and it does not claim a tester was blocked. Roadmap placement stays Post-MVP / Later.

## Proposed Solution

One new script, `plugins/soleur/scripts/spec-kit-intake.sh`. Brainstorm and plan call it. It does not write. Stdout is the receipt, then a `--- side-evidence ---` block (basename, byte size, sha256, and the file text, labeled not-requirements), then `--- projected ---` and the Soleur spec body. Stderr is empty on the success path. A refusal prints one `intake: <reason>` line on stdout and exits non-zero, with no projected body and no side-evidence body.

`--probe` prints `spec-kit-intake: ok` and exits 0. It opens no directory.

`--cwd <dir> --dir <path>` resolves a relative `--dir` against `--cwd`. An absolute `--dir` is used as given. The skill text captures `pwd` before any worktree `cd` and passes that value as `--cwd`.

The directory's final two segments must match `specs/<prefix>-<short-name>`. Prefix is `^[0-9]{3}$` or `^[0-9]{8}-[0-9]{6}$`. The short-name is one segment matching `^[A-Za-z0-9][A-Za-z0-9_-]*$`. A `.` path component is dropped before that final-two-segment check. A `..` component still exits `intake: not-a-directory`. The check does not normpath and does not collapse `..`. A file path, a missing directory, or any other shape exits `intake: not-a-directory`.

Resolve `--cwd` and `--dir` by string join only. Do not `chdir`. Starting at `/`, open each lexical component with `os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent_fd)`. `ELOOP` or a symlink component is `intake: symlink-escape` and is not reclassified as `not-a-directory`. That component is not followed. Do not `lstat` a path and then `open` that same path. `os.path.realpath` is not used. Failure to open the directory is `intake: not-a-directory`. The directory file descriptor from that walk is the only directory handle.

Open `spec.md`, then `plan.md`, then `tasks.md`, only with `os.open(basename, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dir_fd)`. The canonical-path check is that this directory-fd open succeeded for that same basename. Do not concatenate the walk and compare the concatenation to itself. If `spec.md` is absent, exit `intake: missing-spec` before `plan.md` and `tasks.md` are classified. If `plan.md` or `tasks.md` is absent, the receipt says `absent` and the script continues. A present name that is a symlink exits `intake: symlink-escape` and is not read, including a symlink to another basename in the same directory. `fstat` the opened descriptor before any read. A non-regular file is `intake: not-a-regular-file` and is not read. An open that fails is `intake: unreadable`. `st_size` greater than 1048576 is `intake: over-cap` and is not read. `st_size` equal to 1048576 is allowed. Read at most that `st_size` and never more than 1048576. If a later `fstat` of the same descriptor shows a different size, drop the bytes and exit `intake: over-cap`. One failure fails the whole intake. After the directory is open, emit the first failure in file order. Do not rank reasons across files. A refusal prints one `intake:` line and has no projected body and no side-evidence body. Invoking the script with neither `--dir` nor `--probe` exits non-zero. `--probe` is handled before that check, prints `spec-kit-intake: ok`, exits 0, and opens no directory.

Directory entry names other than the three files are listed from the directory (names only) under `never-read`. `research.md`, `data-model.md`, `contracts`, and `quickstart.md` are always listed there even when absent, so the receipt shows the closed set. The script does not open them, does not recurse, and does not follow markdown links. A directory-entry name that contains a C0 control other than tab, `\x7f`, U+0085, U+2028, U+2029, or the exact marker `--- side-evidence ---` or `--- projected ---` fails the whole intake with `intake: unreadable` and no other stdout. Side-evidence file text is printed with four spaces before every line, so a line in that text cannot be a marker. The only `--- side-evidence ---` and `--- projected ---` lines are the ones the script writes. A projected line that is one of those markers, or a column-0 `moved:`, `unmapped:`, `never-read:`, or digest line, fails the intake with `intake: unreadable` and no other stdout. The caller takes the projected body after that single `--- projected ---` line. Ordinary `---` inside a kit file, including frontmatter, is allowed. Unmapped headings and never-read names are one `unmapped:` or `never-read:` line each, so a comma inside a heading or a directory name stays in that entry. An empty unmapped list emits no `unmapped:` line. `moved: none` stays when nothing moved. A heading named `none` is the line `unmapped: none`.

Projection reads only the `spec.md` bytes. It does not read the side-evidence buffers. A heading is an ATX heading at line start, outside the first frontmatter block and outside a fenced code block. A setext heading is not a heading. Heading text is compared case-insensitively. A delimiter is a line that is `---` followed only by spaces or tabs, and only while no fenced code block is open. A `---` line inside a fence is not a delimiter. The first closed pair of delimiters is frontmatter wherever it starts: lines before the opener stay, the pair is not copied, and a later pair is ordinary text. An opener with no closer is not a block and does not consume the following headings. `NEEDS CLARIFICATION` is case-sensitive. A priority match is a standalone token, so `P2` inside `P2P` does not match. The byte cap is `st_size` before any read. On bytes the cap already accepted, strip ASCII controls other than newline and tab, and also strip `\x7f`, U+0085, U+2028, and U+2029. Repeat that byte strip until a pass removes nothing, then decode strict UTF-8, then drop any remaining U+0085, U+2028, or U+2029. A C0 or DEL byte inside those UTF-8 sequences does not leave the character in the output. Invalid UTF-8 fails `intake: unreadable`. The strip does not change the cap decision.

- A user-story heading is an ATX heading whose text contains the case-insensitive tokens `user story` in that order. An ASCII letter or digit does not continue either token. That boundary is the same ASCII class as the short-name. An underscore or a non-ASCII letter is outside that class. The standalone `P1`, `P2`, or `P3` token is read from the heading text only.
- That heading is an FR candidate only when it has a standalone `P1`, no standalone `P2` or `P3`, and its body does not contain `NEEDS CLARIFICATION`.
- A user-story heading with no standalone `P1`, a user-story heading that also has a standalone `P2` or `P3`, any other heading with a standalone `P2` or `P3`, and any section whose body contains `NEEDS CLARIFICATION` stay unmapped.
- `Success Criteria` maps to Goals.
- `Out of Scope`, `Non-Goals`, and `Exclusions` map to Non-Goals.
- Every other heading is unmapped. A mapped heading whose stripped body is empty is listed by name as unmapped.

The projected file uses the spec-template sections plus frontmatter `lane: cross-domain` and `brand_survival_threshold: single-user incident`. Unmapped headings are listed by name under `## Unmapped appendix` with the line "Not a requirement. Not built from." The appendix does not copy section bodies. The script's own source and the plugin tree do not contain a customer body.

### Implementation Phases

#### Phase 1: Script and tests

Write `plugins/soleur/test/spec-kit-intake.test.sh` first, with synthesized fixtures under `mktemp`. Then write `plugins/soleur/scripts/spec-kit-intake.sh` until that suite passes. The script writes no file. Containment is `python3` inside the shell wrapper: open each lexical component with `os.open` using `O_RDONLY`, `O_DIRECTORY`, `O_NOFOLLOW`, and `O_NONBLOCK` from the parent directory fd, then open the three basenames with `O_RDONLY`, `O_NOFOLLOW`, and `O_NONBLOCK` from that directory fd, then `os.fstat` and `hashlib.sha256`. Do not `lstat` a path and then open that path. Do not use `os.path.realpath`. Read at most the `fstat` `st_size` and never more than 1048576. If a later `fstat` of the same descriptor shows a different size, drop the bytes and exit `intake: over-cap`. The shell file is the wrapper the probe invokes. It does not call `timeout`, `gtimeout`, `readlink -f`, `stat -c`, `sed -i`, `date -d`, `sha256sum`, or GNU `realpath`. The FIFO case's watchdog is the `timeout`, then `gtimeout`, then bare pattern in `.claude/hooks/git-commit-secret-scan.sh`, around the test only. The suite installs its `EXIT` trap before `mktemp` and does not `source` `test-helpers.sh`. The over-cap row has a same-input positive control at exactly 1048576 bytes. A refusal is final: the skill does not edit the kit directory and re-run, and it does not paste the path as prose. In the same PR, the feature spec's FR2, FR4, FR5, and TR2 already match this plan. That spec edit is not a gate before the suite. Work must not restore the resolved-parent rule or a human-edit detector.

#### Phase 2: Brainstorm call site

In `plugins/soleur/skills/brainstorm/SKILL.md`, under `## Feature Description`, before the empty-description question, before Phase 0's worktree `cd`, and before `**If requirements are already clear:**`. Measured 2026-11-11: the file is 139617 bytes and its ceiling in `plugins/soleur/test/skill-body-budget.json` is 141000, so this edit has 1383 bytes of room. Stay inside that room. A token that is not an existing directory is prose. A sentence that mentions an existing directory of this shape is also prose. The skill does not call the script for either. A directory whose last two segments match this shape is intake. The skill captures `pwd` before the worktree `cd`, runs the script with that `--cwd`, and stops on non-zero. A refusal ends the skill: it does not edit the kit directory, does not run the script again, and does not paste the path as prose. On zero, the skill shows the receipt and keeps the absolute directory captured before the worktree `cd`. The projected body is the feature description only for the Brainstorm anyway arm. Phase 3.6 step 4 does not generate a second spec when a projected body exists. Step 5 writes that projected body verbatim when `knowledge-base/project/specs/<branch>/spec.md` is absent, and does not replace that file when it exists, including zero bytes. When that file exists, including a zero-byte file, the skill does not run the script and does not replace the file. An empty spec directory is not the stop. The One-shot and Plan first arms both pass that absolute directory, not the projected body and not the raw relative token. One-shot forwards it unchanged as plan's arguments. Do not edit `plugins/soleur/skills/one-shot/SKILL.md`. Keep this brainstorm addition inside the 1383-byte ceiling.

#### Phase 3: Plan call site

Measured 2026-11-11: `plugins/soleur/skills/plan/SKILL.md` is 119962 bytes and its ceiling is 120000, so 38 bytes remain. A paragraph does not fit. Work removes the duplicate block that starts at `**Check for knowledge-base directory and load context:**` and ends before `**If knowledge-base/ exists:**` (292 bytes on 2026-11-11). The branch-safety check above it already runs `git branch --show-current`, and steps 3–4 of the surviving list already read the branch spec when it exists. In its place, before step 4, add this line and nothing longer:

`**Spec-kit intake, before step 4.** If the branch spec.md is absent and the argument is an existing specs/<prefix>-<short-name>/ directory, Read references/spec-kit-intake.md and follow it. If that spec file exists, including zero bytes, do not run the script and do not replace it.`

The full procedure goes in the new file `plugins/soleur/skills/plan/references/spec-kit-intake.md`, loaded only at that step. It says: capture `pwd` before any `cd`, run the script, and on non-zero stop without editing the kit directory, without running the script again, and without pasting the path as prose. On success save the projected body as the branch spec, then plan from the saved file. An argument that is already absolute is `--dir` as given, including after one-shot has changed directory. This planning session's branch already has a Soleur spec, so this session does not re-ingest. The call site is still added. Direct plan-first persists the projection, so a later plan reads the file instead of ingesting again. After the edit, `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0.

#### Phase 4: Provenance on the draft PR

`soleur:ship` full-replaces the PR body, so an earlier `gh pr edit` does not survive. When ship writes the body for PR #12653, the last paragraph is the spec's TR4 trailer, and the body has no AGPL or MIT notice. No blog edit, no changelog hero, no "compatible" wording.

## Technical Considerations

- The script is local. It does not add a network call, a dependency, or a `specify` binary. Host binaries are `bash` and `python3`.
- Security: the directory is untrusted. Containment is the guard contract below. Output strips ASCII control characters other than newline and tab, and also strips `\x7f`, U+0085, U+2028, and U+2029, after the `st_size` cap. The strip repeats until a pass removes nothing, then drops any of those three characters still in the decoded text. The receipt uses basenames, sizes, and sha256, not absolute paths. Side-evidence body lines are indented four spaces.
- Consumers of branch-spec existence, each of which only refuses when the file is present: brainstorm `## Feature Description` together with Phase 3.6 step 5, and plan `### 0. Load Knowledge Base Context`. Neither resumes from that bit. When the file is absent, those two are the writers. A grep of the basename `spec-kit-intake` on 2026-11-11 finds no executor. After this change the executors are the brainstorm call site, the plan reference, `plugins/soleur/test/spec-kit-intake.test.sh`, and `scripts/test-all.sh` through the `plugins/soleur/test/*.test.sh` glob. The affected classifier derives the script edge from the test stem via the sibling `scripts/` fan in `scripts/test-all.sh`. No new `AFFECTED_*_PATHS` row. Work runs `scripts/lint-orphan-test-suites.sh` once the test file is tracked.
- Merging this PR does not apply Terraform or restart a service. The diff is the plugin script, the plugin test, the brainstorm skill, the plan skill, the plan reference, the feature spec, and the plan artifacts.
- `plugins/soleur/skills/brainstorm/SKILL.md` and `plugins/soleur/skills/plan/SKILL.md` `description:` frontmatter are not edited. Phase 1.8 does not fire.
- NFR register: this change adds no production service, route, or datastore. The containment properties are the non-functional bar. No `nfr-register.md` row names this CLI.
- Performance: three files, each capped at 1048576 bytes. No fan-out.

## User-Brand Impact

- **If this lands broken, the user experiences:** a projected Soleur spec that dropped a success criterion, promoted a later story, or treated unmapped text as a requirement, so the build follows the wrong contract.
- **If this leaks, the user's workflow is exposed via:** customer spec prose committed into the Soleur product tree, or AGPL text copied into the BSL repo.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one wrong projection ships the wrong feature for that caller, and one copied AGPL passage contaminates the license. The next tier down would treat this as a private formatting aid.

CPO sign-off is the brainstorm CPO assessment carried forward (unmapped appendix mandatory, later stories are not equal requirements, demand unconfirmed). `soleur:engineering:review:user-impact-reviewer` runs at review time.

A plan whose `## User-Brand Impact` section is empty, or omits the threshold, fails `deepen-plan` Phase 4.6.

## Files to Create

- `plugins/soleur/scripts/spec-kit-intake.sh`
- `plugins/soleur/test/spec-kit-intake.test.sh`
- `plugins/soleur/skills/plan/references/spec-kit-intake.md`

## Files to Edit

- `plugins/soleur/skills/brainstorm/SKILL.md` — call site only, under `## Feature Description` and Phase 3.6's save step.
- `plugins/soleur/skills/plan/SKILL.md` — replace the duplicate knowledge-base list with the spec-kit intake line under `### 0. Load Knowledge Base Context`. The `description:` field stays.
- `knowledge-base/project/specs/feat-12531-spec-kit-ingestion/spec.md` — FR2, FR4, FR5, and TR2 aligned in this plan change. Work must not revert them.

## Open Code-Review Overlap

- #4133 (Schema parity test for the Observability block) mentions `plugins/soleur/skills/plan/SKILL.md`. Acknowledge: this plan adds a call-site paragraph and does not change the Observability schema that issue tracks.

## Observability

```yaml
liveness_signal:
  what: "spec-kit-intake.sh --probe prints spec-kit-intake: ok"
  cadence: per-invocation
  alert_target: the skill caller stops on a non-zero exit
  configured_in: plugins/soleur/scripts/spec-kit-intake.sh
error_reporting:
  destination: stdout reason line to the skill caller
  fail_loud: "non-zero exit and one stdout line starting intake:"
failure_modes:
  - mode: any symlink on a path component or an allow-listed name
    detection: "stdout intake: symlink-escape and exit non-zero; target bytes absent"
    alert_route: the skill stops and does not save a spec
  - mode: allow-listed file cannot be opened
    detection: "stdout intake: unreadable and exit non-zero; body absent"
    alert_route: the skill stops and does not save a spec
  - mode: file larger than 1048576 bytes
    detection: "stdout intake: over-cap and exit non-zero; body absent"
    alert_route: the skill stops and does not save a spec
  - mode: spec.md missing
    detection: "stdout intake: missing-spec and exit non-zero"
    alert_route: the skill stops and does not use the path as a description
logs:
  where: the skill session stdout
  retention: the session transcript
discoverability_test:
  command: bash plugins/soleur/scripts/spec-kit-intake.sh --probe
  expected_output: "spec-kit-intake: ok"
```

Probe run on 2026-11-11, before the script exists, returned exit 127 (`No such file or directory`). Work re-runs the same command after Phase 1 and expects `spec-kit-intake: ok`.

## Guard Contract

### Guard 1 — spec-kit-intake containment

**Property.** A read of `spec.md`, `plan.md`, or `tasks.md` returns bytes only when that basename is opened from the directory file descriptor with `O_NOFOLLOW`, `fstat` shows a regular file, and `st_size` is at most 1048576. The directory file descriptor is the result of opening each lexical component with `O_NOFOLLOW` from its parent. The read is at most that `st_size` and never more than 1048576. Any symlink, non-regular file, unreadable file, or over-cap file fails the whole intake with no projected body.

**Assembly.** The chokepoint is `spec-kit-intake.sh`. Each lexical component is opened with `O_RDONLY`, `O_DIRECTORY`, `O_NOFOLLOW`, and `O_NONBLOCK` from the parent directory file descriptor, and a symlink component fails closed. The three basenames are opened with `O_RDONLY`, `O_NOFOLLOW`, and `O_NONBLOCK` from that directory file descriptor. `fstat` runs before any read. There is no `lstat`-then-open and no path-string equality check. Brainstorm `## Feature Description` and plan `references/spec-kit-intake.md`, reached from `### 0. Load Knowledge Base Context`, are the two callers. There is no third caller. `soleur_approval_realpath` is not on this path.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `spec.md` is a symlink whose lexical path stays inside the directory and whose target is outside and contains a sentinel | RED, exit non-zero, sentinel absent from stdout |
| 2 | Invoke the script with neither `--dir` nor `--probe` | RED, exit non-zero. Exit 0 here means the guard did not run |
| 3 | `spec.md` is a regular in-directory file and `plan.md` is a symlink that leaves the directory | RED for the whole intake. `spec.md` bytes absent from stdout |
| 4 | Change the suite so the symlink case expects exit 0 | suite RED, because the script still refuses |
| 5 | Directory contains only a regular `spec.md`. `plan.md` and `tasks.md` are absent | PASS. Receipt says `absent` for both. This is not the three-file fixture |
| 6 | Move the size check to after the read, then point `spec.md` at a file larger than 1048576 | RED is required of the real script: `intake: over-cap` and the body absent. A post-read check that prints the body fails this row |
| 7 | `spec.md` is a symlink to `research.md` in the same directory, and `research.md` contains `SENTINEL-RESEARCH` | RED, exit non-zero, `SENTINEL-RESEARCH` absent from stdout |
| 8 | `spec.md` is a regular file whose `st_size` equals 1048576 | PASS. Exit 0. The body is projected |

The script does not write into the caller tree, so there is no first-write exit window to table. When the feature spec is absent, brainstorm Phase 3.6 and the plan call site each save the projected body. When that file exists, neither caller runs the script.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "In `brainstorm`/`plan` intake: detect a `specs/<NNN>-<name>/` path argument" | Phase 2, Phase 3, `spec-kit-intake.sh` prefix check | mapped |
| 2 | "parse the three artifacts into the spec template the pipeline already uses" | Phase 1 projection of `spec.md`. `plan.md` and `tasks.md` are read as side evidence and are not folded into the template | descoped — justification: folding the three files into one spec collides with Soleur's indexed `tasks.md` and mixes plan text into requirements (brainstorm Approach B) |
| 3 | "Read-only on the source format." | Phase 1, the script writes nothing | mapped |
| 4 | "never running `specify init` itself" | Phase 1, no initializer and no network fetch | mapped |
| 5 | "clean re-implementation" | Phase 4 provenance trailer. No HephaestusNG read, no Spec Kit template bytes | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/spec-kit-intake.sh` | "detect a `specs/<NNN>-<name>/` path argument, parse the three artifacts into the spec template the pipeline already uses. Read-only on the source format." | asked |
| `plugins/soleur/test/spec-kit-intake.test.sh` | "Read-only on the source format." | inferred — justification: a read-only claim with no suite can pass while the script writes or follows a symlink |
| `plugins/soleur/skills/brainstorm/SKILL.md` | "In `brainstorm`/`plan` intake" | asked |
| `plugins/soleur/skills/plan/SKILL.md` | "In `brainstorm`/`plan` intake" | asked |
| `plugins/soleur/skills/plan/references/spec-kit-intake.md` | "In `brainstorm`/`plan` intake" | inferred — justification: the plan skill is 38 bytes under its ceiling, so the procedure cannot live in `SKILL.md` |
| `knowledge-base/project/specs/feat-12531-spec-kit-ingestion/spec.md` | "Read-only on the source format." | inferred — justification: plan review on 2026-11-11 found the committed FR2 and TR2 still allowed a same-directory symlink the containment ruling refuses |
| Phase 4 PR trailer | "clean re-implementation" | asked |
| Byte cap 1048576 and refusing every symlink, including a same-directory link to another basename | — | inferred — justification: the issue's read-only intake of an untrusted directory is unsafe without a fail-closed bound, and no existing helper fails closed (`soleur_approval_realpath` returns 0 on failure) |
| P2/P3 and `NEEDS CLARIFICATION` stay unmapped | — | inferred — justification: the brainstorm CPO assessment says later stories and clarification markers are not equal requirements, and the projection is the build contract |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 6 | Estimated changed lines: 750
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] `bash plugins/soleur/scripts/spec-kit-intake.sh --probe` prints `spec-kit-intake: ok` and exits 0 (`plugins/soleur/scripts/spec-kit-intake.sh`).
- [x] A synthesized `specs/001-demo/spec.md` plus optional `plan.md` and `tasks.md` exits 0, the receipt names moved, unmapped, and never-read entries, and the projected body has Goals, Non-Goals, and FR candidates (`plugins/soleur/test/spec-kit-intake.test.sh`).
- [x] A missing `spec.md`, a non-directory, a prefix that is neither 3 digits nor `YYYYMMDD-HHMMSS`, any symlink (including a same-directory link to another basename and a symlinked directory component), a non-regular file, an unreadable file, and a file whose `st_size` is greater than 1048576 each end with one `intake:` line and no projected body. A regular file whose `st_size` equals 1048576 exits 0 (`plugins/soleur/test/spec-kit-intake.test.sh`).
- [x] A sentence that mentions an existing `specs/<prefix>-<short-name>/` directory is not passed to the script. The script, if invoked on a path that is not an existing directory, prints `intake: not-a-directory` (`plugins/soleur/skills/brainstorm/SKILL.md`, `plugins/soleur/test/spec-kit-intake.test.sh`).
- [x] A non-zero intake ends brainstorm and plan. Neither caller edits the kit directory, re-runs the script, or pastes the path as prose (`plugins/soleur/skills/brainstorm/SKILL.md`, `plugins/soleur/skills/plan/references/spec-kit-intake.md`).
- [x] A zero-byte `knowledge-base/project/specs/<branch>/spec.md` stops both brainstorm and plan. Neither runs the script or replaces the file.
- [x] An empty `knowledge-base/project/specs/<branch>/` directory does not stop brainstorm or plan. Both still run intake when `spec.md` is absent.
- [x] Both clear-requirements handoffs pass the absolute directory captured before the worktree `cd` (`plugins/soleur/skills/brainstorm/SKILL.md`).
- [x] `knowledge-base/project/specs/feat-12531-spec-kit-ingestion/spec.md` FR2 and TR2 refuse every symlink, including a same-directory link to another basename, and FR4 keeps a non-`P1` story in the unmapped appendix.
- [x] `research.md` content never appears in stdout. The receipt names it under never-read.
- [x] The script creates and modifies no file in the fixture directory or the repo.
- [x] Brainstorm's `## Feature Description` runs the script before the empty-description question and before the clear-requirements shortcut, and Phase 3.6 does not replace an existing `spec.md` (`plugins/soleur/skills/brainstorm/SKILL.md`).
- [x] Plan's `### 0. Load Knowledge Base Context` runs the script only when the branch spec is absent, and on success saves the projected body as that spec (`plugins/soleur/skills/plan/SKILL.md`).
- [x] The PR body `soleur:ship` writes for #12653 ends with the TR4 provenance trailer and does not contain an AGPL or MIT notice, and neither skill description claims Spec Kit compatibility.
- [x] `bash plugins/soleur/test/spec-kit-intake.test.sh` exits 0.

## Domain Review

**Domains relevant:** Product, Engineering, Legal, Marketing

**Brainstorm-recommended specialists:** none

### Engineering

**Status:** reviewed
**Assessment:** Carry-forward from the 2026-11-11 brainstorm, tightened by the 2026-11-11 CTO ruling. One tested read-only script. `spec.md` required. `plan.md` and `tasks.md` are side evidence. Fail closed on any symlink, a non-regular file, an unreadable file, a missing `spec.md`, and a file over the byte cap. Resolve the path before the worktree `cd`. Do not use `soleur_approval_realpath`. Plan review on 2026-11-11 (architecture, security, and Kieran) aligned FR2, FR4, FR5, and TR2 in the feature spec with this plan. The suite is written from this plan. Work must not restore the resolved-parent rule or a human-edit detector. Code-simplicity asked to delete the shell wrapper. Not applied: the 2026-11-11 CTO ruling names `plugins/soleur/scripts/spec-kit-intake.sh`, and this review's CTO devex seat found that wrapper operable.

### Legal

**Status:** reviewed
**Assessment:** Carry-forward. Public MIT Spec Kit docs may be read. No AGPL duty if HephaestusNG stays unread. Provenance trailer on the PR. Do not commit customer spec prose into the Soleur product tree. The brainstorm CLO said `soleur:gdpr-gate` does not apply to this path as specified. Plan Phase 2.7 still ran because the brand threshold is `single-user incident`. Gate result is below. No Critical finding.

### Marketing

**Status:** reviewed
**Assessment:** Carry-forward. No announcement and no compatibility wording. Intake must not imply that plan review is optional. Plan still writes Soleur's own `tasks.md`.

### Product

**Status:** reviewed
**Assessment:** Carry-forward from the brainstorm CPO. The unmapped appendix is mandatory. Later stories are not equal requirements. Demand is unconfirmed. Product/UX tier is none: the files to create and edit are a shell script, a shell test, two skill markdown files, one skill reference, and the feature spec. No UI-surface path. Pencil is not used.

gdpr-gate (advisory, this plan, 2026-11-11): no schema, migration, auth route, or `.sql` file. The five v1 checks (Art. 6, Art. 5(1)(e), Art. 17, Chapter V, Art. 9) have no column to match. No Critical finding. Customer prose can contain personal data; the script returns it to the caller and the product tree does not commit it.

## Test Scenarios

- unit: Given `specs/001-demo/spec.md` with a Success Criteria heading and an ATX heading whose text contains `User Story` and a standalone `P1`, when the script runs, then Goals contain the success text and the story is an FR candidate. Given that standalone `P1` only in the body, when the script runs, then the section stays unmapped. Given a heading whose text has a standalone `P1` and a standalone `P2`, when the script runs, then the section stays unmapped.
- unit: Given a heading `success criteria` in any letter case, when the script runs, then that section maps to Goals.
- unit: Given `Out of Scope`, `Non-Goals`, and `Exclusions` headings, when the script runs, then each maps to Non-Goals.
- unit: Given a P2 story, a P3 story, a user-story heading with no standalone `P1`, and a section whose body contains `NEEDS CLARIFICATION`, when the script runs, then each is in the unmapped appendix and not under Functional Requirements.
- unit: Given a user-story heading that contains `P2P` and a standalone `P1`, and no `NEEDS CLARIFICATION`, when the script runs, then the story is an FR candidate.
- unit: Given `needs clarification` in a different case inside a standalone-`P1` story, when the script runs, then that marker does not unmap the story.
- unit: Given frontmatter whose only copy of `SENTINEL-FM` sits between the first pair of `---` delimiters, when the script runs, then the projected requirements do not contain `SENTINEL-FM`.
- unit: Given a fenced code block whose text contains an ATX `P1` user-story heading, when the script runs, then that fenced heading is not an FR candidate. A setext heading is not a heading.
- unit: Given `plan.md` absent and `tasks.md` present, when the script runs, then the receipt says `absent` for `plan.md` and the projected requirements do not contain a kit task id.
- unit: Given `tasks.md` absent and `plan.md` present with `SENTINEL-PLAN-ONLY`, when the script runs, then the receipt says `absent` for `tasks.md` and the projected body does not contain `SENTINEL-PLAN-ONLY`.
- unit: Given both side files absent, when the script runs, then the receipt says `absent` for both and the exit is 0.
- unit: Given `plan.md` containing `SENTINEL-PLAN-ONLY`, when the script runs, then that sentinel appears only under `--- side-evidence ---` and is absent from the projected body.
- unit: Given `specs/20261111-120000-demo/spec.md`, when the script runs, then the exit is 0. Given `specs/12-demo` or `specs/001-.dot`, when the script runs, then stdout is `intake: not-a-directory`.
- unit: Given `spec.md` missing inside a matching directory, when the script runs, then stdout is `intake: missing-spec` and there is no projected body.
- unit: Given a token that is not an existing directory, when the skill intake rule is applied, then the skill does not call the script. The script, if invoked on that path, prints `intake: not-a-directory`.
- unit: Given a sentence that mentions an existing `specs/<prefix>-<short-name>/` directory and is not itself that path, when the brainstorm and plan intake rules are applied, then neither skill calls the script.
- unit: Given a symlink `spec.md` that points outside the directory at a file containing `SENTINEL-OUTSIDE`, when the script runs, then exit is non-zero and stdout does not contain `SENTINEL-OUTSIDE`.
- unit: Given `spec.md` as a symlink to `research.md` in the same directory and `research.md` containing `SENTINEL-RESEARCH`, when the script runs, then stdout is `intake: symlink-escape` and does not contain `SENTINEL-RESEARCH`.
- unit: Given a directory component that is a symlink to a directory holding `spec.md` with `SENTINEL-DIRLINK`, when the script runs, then stdout is `intake: symlink-escape` and does not contain `SENTINEL-DIRLINK`.
- unit: Given a regular `spec.md` and a leaving symlink `plan.md` or `tasks.md`, when the script runs, then exit is non-zero and the `spec.md` body is absent from stdout.
- unit: Given a FIFO at `spec.md`, bounded by a timeout, when the script runs, then stdout is `intake: not-a-regular-file` and the FIFO is not read.
- unit: Given mode `000` on `spec.md` and a non-root euid, when the script runs, then stdout is `intake: unreadable`. When the suite's euid is 0, it runs that case under a non-root euid. If no non-root user exists, that case fails closed instead of passing.
- unit: Given `spec.md` whose `st_size` is greater than 1048576, when the script runs, then stdout is `intake: over-cap` and does not contain the file body. The same holds when the over-cap file is `plan.md` or `tasks.md` after a valid `spec.md`.
- unit: Given `spec.md` whose `st_size` equals 1048576, when the script runs, then the exit is 0.
- unit: Given `research.md` containing `SENTINEL-RESEARCH`, a `contracts/` file containing `SENTINEL-CONTRACT`, and a markdown link in `spec.md` to a file containing `SENTINEL-LINK`, when the script runs, then none of those sentinels appear in stdout and the receipt lists `research.md`, `data-model.md`, `contracts`, and `quickstart.md` under never-read.
- unit: Given `spec.md` whose mapped section contains the byte `0x07` between two visible words, when the script runs, then the projected body contains those words with `0x07` removed, stdout has no ASCII control character other than newline and tab, and stdout does not contain the fixture absolute path.
- unit: Given `plan.md` whose text contains a line that is exactly `--- projected ---`, when the script runs, then that line is indented under side-evidence and the projected body is the script's projection. Given a directory entry name that contains a newline, when the script runs, then stdout is `intake: unreadable` and there is no projected body.
- unit: Given a relative `--dir` and `--cwd`, when the script runs, then the relative path resolves against `--cwd`. Given an absolute `--dir`, when the script runs, then that path is used as given.
- unit: Given neither `--dir` nor `--probe`, when the script runs, then the exit is non-zero and stdout is not `spec-kit-intake: ok`.
- unit: Given an existing feature `spec.md`, when the brainstorm and plan caller rules are applied, then that file's bytes are unchanged and neither caller invokes the script. The script itself never writes the file.
- unit: Given a zero-byte `knowledge-base/project/specs/<branch>/spec.md`, when the brainstorm and plan caller rules are applied, then neither caller invokes the script and the file remains zero bytes.
- unit: Given an empty `knowledge-base/project/specs/<branch>/` directory and no `spec.md`, when the brainstorm and plan caller rules are applied, then both callers still run the script.
- unit: Given no feature `spec.md` and a successful projection, when the plan caller rule is applied, then the caller saves the projected body before planning continues.
- unit: Given a non-zero script result, including stdout `intake: missing-spec`, when the brainstorm and plan caller rules are applied, then each caller stops, does not edit the kit directory, does not run the script again, and does not paste the path as the feature description.
- unit: Given a relative `specs/<prefix>-<short-name>/` argument, when either clear-requirements handoff runs after a worktree `cd`, then the child receives the absolute directory captured before that `cd`, and plan saves the projection.
- unit: Given `--probe`, when the script runs, then stdout is `spec-kit-intake: ok` and the script opens no directory.

No e2e scenario. No browser surface. No external service. These scenarios are the acceptance cases for the spec-flow gaps.

## Success Metrics

- The suite `plugins/soleur/test/spec-kit-intake.test.sh` exits 0.
- A directory argument is intake. A sentence that mentions the same shape is not.
- An existing Soleur spec is byte-identical after a second intake attempt.

## Dependencies & Risks

- Founder-stated check: the operator declined the capture question on 2026-11-11. No `founder_check` block.
- Demand is unconfirmed. Shipping the intake does not promote the roadmap item off Post-MVP / Later.
- A kit heading wording this map does not recognize lands in the appendix. That is the safe direction. The receipt is what makes the drop visible.
- One-shot's file-path pre-scan will still ignore a directory. Both clear-requirements arms pass the absolute directory into plan, which runs the script when no spec exists yet. `plugins/soleur/skills/one-shot/SKILL.md` stays unchanged.

## References & Research

- Issue: #12531. Epic: #12533. Draft PR: #12653.
- Spec: `knowledge-base/project/specs/feat-12531-spec-kit-ingestion/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-11-11-spec-kit-ingestion-brainstorm.md`
- Template: `plugins/soleur/skills/spec-templates/SKILL.md` heading `## spec.md Template`
- Rejected helper: `plugins/soleur/scripts/lib/operator-script.sh` function `soleur_approval_realpath`
- Public directory shape, nominative only: GitHub Spec Kit `specs/<prefix>-<short-name>/` with `spec.md`, `plan.md`, `tasks.md`. No template text is copied.
