---
title: Founder-stated acceptance check, frozen and separately executed
status: accepted
date: 2026-10-06
supersedes: none
issue: 9578
related: [9578, 9577, 9620, 9588, 7412]
related_adrs: [ADR-175, ADR-229]
tags: [preflight, plan, acceptance, founder, sandbox, freeze, self-hosted, check-13]
brand_survival_threshold: single-user incident
---

# ADR-274: Founder-stated acceptance check, frozen and separately executed

## Status

**Accepted - 2026-10-06 (#9578).** Self-hosted CLI only, Linux first. Hosted Command Center capture is out of scope and waits
on #9620; no marketing, changelog or demo copy may claim this feature before it ships.

## Context

The founder never defines engineering "done" today: acceptance criteria are written by the agent that then does the work. #9578
asks for the founder to state, in their own words and before work starts, what proves a piece of work is done, and for a step other
than `work` to run it. The issue is explicit that this extends the plan's acceptance field and does not build a new engine.

The cost of getting it wrong is a single founder who trusts a "passed" label on broken work, or whose command output leaks a token
into a public repository (`brand_survival_threshold: single-user incident`). So the design is organised around six properties:
the founder states it in their own words; approves the exact runnable text, not a paraphrase; the text cannot change unnoticed;
the check fails before the work (it is not vacuous); a step other than `work` runs it and the result claims only what is true; a
failure stops and asks, and an override is recorded as an override.

## Decision

**A `founder_check:` block under `## Acceptance Criteria` in the plan, frozen by a commit, run by a new preflight Check 13 through
the existing Step 10.5 sandbox.** Everything else follows from not adding a mechanism the six properties do not need.

1. **Capture** (`soleur:plan`, interactive only). The founder's words are stored verbatim as `text`; the agent proposes a literal
   `command` and one literal `expected` substring; the founder approves that exact text. Headless runs ask nothing and write no block.
2. **Must fail first.** `soleur:preflight --founder-check-baseline` runs the check against the pre-work tree. A check that already
   passes is `VACUOUS` and refused; a tooling failure (timeout, command not found, an unhealthy sandbox) is `INVALID`, never a
   baseline fail.
3. **Freeze = the earliest reviewed copy.** The freeze is the plan's copy at the merge base when it was already reviewed on main,
   else the earliest branch commit carrying the block. The freeze commit precedes the first commit outside `knowledge-base/`; an
   ordering violation is a stop-and-ask, not a hard FAIL. Check 13 compares the canonical fields (`kind`, `text`, `command`,
   `expected`, `pins`, `approved_by`, `approved_at`) of HEAD to the freeze, so a reformat passes and any edit stops. `hash:` is an identity shown in the
   log, **not** the integrity control: a hash is self-consistent by construction, and editing the block and recomputing the hash in one
   commit passes a hash check while the freeze comparison still reds it.
4. **A script the work writes is the agent certifying itself.** An interpreter verb (`bash python3 node bun`) is accepted only when
   every repo-relative script it names already exists at the freeze and is recorded in `pins:` by git blob sha. A pinned script edited after the freeze is a change like any other.
5. **Run it only through Step 10.5.** Check 13 sets `CMD` and runs the Step 10.5 fence inside a command substitution; it carries no
   sandbox of its own and `founder-check.py` executes nothing. The Step 10.5 sandbox is **unchanged**; ADR-175's Layers 1 and 2
   apply as written and `credentials_required` gets no waiver (a check needing credentials is a `needs-your-eyes` check).
6. **Authorship anchor.** A block executes without a prompt only when the freeze commit's author email equals the local operator's
   and, when a PR exists, the PR author's login equals the authenticated login. Otherwise it is `UNTRUSTED`: a FAIL in every mode; the exact command and the name on the freeze commit are shown and it never executes. Check 13 is not path-gated like Check
   10, so without this a contributor's PR head carrying a self-consistent plan would run on the operator's machine with no prompt.
7. **Outcome vocabulary.** `PASSED` (ran, returned success), `FAILED`, `FAILED-AS-EXPECTED` and `VACUOUS` (baseline), `INVALID`,
   `SKIP-NOSANDBOX`, `NEEDS-YOUR-EYES` / `FOUNDER-CONFIRMED` (a judgement check: the founder, not a command, decided), `OVERRIDDEN`,
   `UNTRUSTED`, `CHANGED-SINCE-APPROVAL` and `STOPPED-AWAITING-FOUNDER`. A pass is labelled "ran, returned success against
   `<sha>`", never a bare PASS, and the wording constants are pinned by tests and reviewed by the CLO. Headless mode refuses
   `OVERRIDDEN` and `FOUNDER-CONFIRMED`; a failing check there is `STOPPED-AWAITING-FOUNDER`. An agent never decides for the founder.
8. **No output text is ever committed.** `founder-check-log.md` records kind, command, rc, outcome, `attempt_n`, `tested_sha`, the block hash, time, `expected_matched` and, for an override, the reason. Output is shown in the terminal only: a regex scrubber for secret
   shapes has false negatives and a false negative is the single-user leak. The founder is told at every capture that `text` and
   `command` are committed to the repository and that one check does not cover everything.

### ADR-229 verification (no change)

ADR-229 models skill-level lifecycle transitions; `preflight` and `qa` are non-node skills the offline classifier drops. "Check
failed, go back to work" is the existing `ship → work` / `review → work` edge (its doc comment already names "preflight/QA
failed"); "change the check mid-ship" is the declared `work → plan` edge. "Stopped awaiting operator" and "override" are not FSM
concepts. Nothing is added to `ONE_SHOT_CHILD_SKILLS`, `IMPLEMENTATION_TAIL` or `DECLARED_TRANSITIONS`, so `workflow-fidelity.ts`
and `skill-body-budget.json` are untouched. This was verified by a full read of both ADRs; the next reader need not redo it.

## Alternatives Considered

Cited from the plan's Cut List, not restated: a new agent, a new ADR-229 edge, hosted capture in slice 1, running from `qa`
(8 bytes of body headroom, a different authority), a new standalone skill (a `description:` budget at its cap) and generalising
Check 10 in place (its gates and its OR-token matching are wrong for a founder check) were each cut for buying nothing the six
properties need. Extracting the sandbox into a script was rejected here: it conflicts with the pinned inline `BWRAP_ARGS` and
`lint-window-closure-assertion.py`; it is the operator's call if the wrapper proves brittle.

## Consequences

- **Tamper-evident, not tamper-proof.** The authorship anchor compares identity strings that the operator's own agent can also write
  (the same circularity as ADR-175's PR-head case); an agent that rewrites branch history is not stopped by comparisons it also
  controls. Overrides are legible, attributable and visible in the PR diff; they do not authenticate the founder.
- **Host-loopback pivot (#7412) is unchanged and not claimed closed.** `--share-net` keeps the operator's real loopback and egress
  reachable from a check.
- **Stale-pass window.** Preflight runs at ship Phase 5.4; Phase 5.5 gates can mutate code and the Phase 7 behind-sync merges main
  afterwards, and neither is a back-edge. The pass wording, the aggregate row and the log row therefore name the commit tested.
- **Headless reach gap.** One-shot runs give no founder to ask, so a plan with no block skips Check 13 and prints the banner. Reach is
  a tracked follow-up (a pre-supplied block for headless runs needs `ship/SKILL.md` ceiling surgery), not hidden.
- **Linux-first.** bubblewrap is Linux-only (ADR-175), so on macOS a command check cannot run and only a `needs-your-eyes` check can
  be captured. An un-sandboxed run there would contradict ADR-175's fail-closed posture and is not offered.
- **Most real checks may be judgement checks.** The verb list has ten entries, no pipes, a read-only repo and a 15-second cap; test
  runners and builds hit those limits, and `node` / `bun` are not found inside the sandbox on mise or asdf installs. Capture warns the
  founder before approval.
- **The log is evidence, not an authority.** On the abort path `ship` stops before it commits artifacts, so a failure row may never be
  committed.
- **Observability (layer 7).** A self-hosted CLI surface has no Soleur-side sink by design. The signal is the metadata-only
  `SOLEUR_FOUNDER_CHECK_RESULT` marker plus the committed log, read back by `founder-check.py summary`.

## C4 impact

The `contributor` actor's description and its adjacent comment in `model.c4` said the discoverability probe is the one PR-head artifact
preflight executes; they now say plan-declared probes and checks, with no count. No element or relationship is added.

## Addendum — 2026-10-06 (#9578, the 12-seat review round)

> **Supersedes the numbered decisions above where it differs.** Append-only: the text above is kept as written so the change is
> legible. Source of every item: the review of #9637.

1. **`creates:` is cut.** A path that is absent now and present later is a check the work can satisfy by writing the file, so it
   certifies nothing about the founder's intent. The canonical fields are now `kind`, `text`, `command`, `expected`, `pins`,
   `approved_by` and `approved_at`; `hash:` stays in the block (spec FR2/TR1) and is computed by the script, not trusted from it.
2. **UNTRUSTED is a FAIL, not a prompt.** Decision 6 said an interactive run shows the command and asks. A freeze commit's author is a
   name anyone can type, so a "yes" to a contributor-written command is a founder approving something they did not write. The command
   and its author are now shown and nothing runs; the founder states their own check or runs the shown one by hand. A forged operator
   email is also not enough: with a PR present, both the PR author and the authenticated login must be supplied and equal, or the
   verdict is `UNTRUSTED` (`pr-author-unmeasurable`). `--no-pr` is the explicit statement that no PR exists.
3. **File-based interface.** The plan's command, expected text and reason are never typed into a shell word. `verify` writes a decision
   record and the raw command to files; `classify` and `log` read the record; the one-line reason arrives on stdin. A founder's
   quoting, backticks or `$( )` therefore cannot reach a shell, and the static rules (control characters, shell-active tokens, secret
   shapes, the verb gate on the dequoted first word, interpreter operands that are existing pinned repo-relative scripts, and
   `git -c`, `rg --pre` and `curl -K`) run at `verify` as well as in the sandbox.
4. **Archival and renames follow the plan.** Compound moves a plan into `plans/archive/<timestamp>-<name>.md` and a spec directory the
   same way. The freeze is keyed on the plan's identity with the archive prefix stripped, renames are tracked through history, and the
   log path follows an archived spec directory, so archiving a plan no longer reads as "freeze without block".
5. **Re-freeze is a real act.** A deliberate change is a commit whose subject starts `plan: re-freeze founder-stated check`, authored
   by the operator, on a plan that was not already reviewed on main; `verify --candidate --refreeze` baselines it. (Tightened in the second addendum: it must follow an earlier freeze, change the block, and is interactive-only.) Candidate mode is
   refused when a freeze exists without `--refreeze`, and an unresolvable base is `FAIL` when any plan holds a block and `NO-BLOCK`
   when none does.
6. **Headless is declared by the caller, defaulting to headless.** The script cannot see whether a founder is present; the
   references name the predicate (interactive session, no `--headless`, `CI` unset) and default to headless when unsure. Six stopped
   outcomes map to `STOPPED-AWAITING-FOUNDER` with the cause kept, `OVERRIDDEN` needs a reason and a named cause, and a block present
   with no sandbox stops the run in every mode (the interactive "continue" was cut: a gate that went dark must not read as green).
7. **`output_sha256` is dropped from the log** (it let a reader test a guessed output offline) and `commit-log` stages and commits only
   the log, as `founder-check: log`.
8. **What a pin does not cover.** A pin fixes one repository script by blob. What that script imports, reads or calls is not pinned,
   so an interpreter check is only as stable as everything its script loads. Stated in the references so it is not mistaken for a
   guarantee.
9. **Wording.** Every founder-facing sentence now lives in `founder-check.py` (`text <key>`); the references only name the key. The constants went to a second CLO review (see the second addendum); the final wording check is the plan's acceptance item 16.

## Second addendum — 2026-10-07 (#9578, the second review round)

> Append-only. Source: the verification seats (test design, security, CLO second review) run on #9637 after the first fix round.

1. **`log` records a measurement, it does not choose one.** `classify` embeds the verify record's `hash`, `head_sha` and the sha256 of
   the record itself, and refuses a ran-command file (`--command-file`, written by the wrapper) that is not byte-for-byte the
   approved command, so a run of anything else cannot be classified. `log` refuses a classify record that belongs to another verify
   record or polarity, and any outcome the two records do not support (a PASSED over a FAILED classification, a FOUNDER-CONFIRMED
   of a command check, an override naming a cause the records do not show, any override of UNTRUSTED). `verify` and `classify`
   delete the files named by `--out` and `--command-out` before parsing arguments, and an internal error writes a `FAIL` record
   there, so a stale record can never be read as this run's. The wrapper writes the ran-command and stdout files itself and the
   sandbox-health control is `CMD=true` in the wrapper text, never a separate call.
2. **Re-freeze is loud, interactive-only and cannot launder authorship.** It counts only when the plan was frozen earlier on the
   branch and the block changed (a commit that restates the same block changes nothing, so a stranger's freeze stays `UNTRUSTED`).
   The record carries `refreeze: true` and `refrozen_from`. `verify --mode` defaults to headless, which stops on a re-freeze
   (`CHANGED-SINCE-APPROVAL`, reason `refreeze-needs-founder`); an interactive run shows both texts and asks `refrozen-ship-ask` for a command check (for a
   judgement check, `eyes-ask`). The baseline of a re-freeze reports `PASSED` or `FAILED`, never `VACUOUS`: the work usually exists by then, so a pass is
   the normal case, not a vacuous check.
3. **Archived plans compare against main's freeze.** The merge-base lookup finds a plan under every name main knew it by, so a
   docs sweep that edits a plan main already archived is checked against main's block instead of becoming its own freeze.
4. **Wording after the second CLO review** (PASS-WITH-EDITS). Authorship is no longer asserted: UNTRUSTED says the check "could not
   be matched to you as its author" and a separate sentence covers the unreadable-GitHub case; `changed-ask` no longer says the
   text changed (the ordering and a pinned script are also causes, and the row records which); `headless-stop` names only the
   answers the interactive path offers for that cause;
   > **Superseded 2026-10-07 (#9578): that was not true for BLOCK-REJECTED and CHANGED-SINCE-APPROVAL; the third addendum rewrites both next-steps (`STOP_CAUSES`).** `rejected-ask` prints a plain-language reason; `approval-ask`, `eyes-ask`,
   `reason-prompt` and `first-use` state their consequences (a yes runs the check once now, the log is public, a check can send
   what it reads to any address);
   > **Superseded 2026-10-07 (#9578): `approval-ask` is true only for a first command capture; the third addendum adds `approval-ask-eyes`, `approval-ask-change` and `refrozen-ship-ask` for the other three paths.** the answer labels are pinned as `opt-*` constants. `approved_by` is required and secret-scanned.
   A third check of the changed constants precedes ship.
5. **Known limits, unchanged and stated plainly.** Headless and interactive are declared by the caller, and `--mode interactive`
   on `verify` is as unauthenticated as on `log`. `--no-pr` is a declaration the caller makes: under it, a freeze whose commit email
   was forged to equal the operator's is **not** `UNTRUSTED`, because nothing else is compared. Only when both PR logins are supplied
   does a forged email meet an independent check. The verify record and the log row therefore carry `no_pr` and `freeze_source`, and
   the pass is followed by a note when either applies, so a pass that rests on an uncompared author or a re-approved check says so.
   The controls above make a mismatch loud and recorded; they do not prove who is present.
6. **The security seat's findings (second round).** (a) The rules judged the command with Python's shlex while Step 10.5 runs it under
   bash, so `bash $'a.sh'`, `bash [a].sh`, `bash {a,b}.sh` and `git $'-c' …` slipped past the pin and denied-option checks. A command
   is now refused when bash would expand or re-read anything outside single quotes (`$`, globs, tilde, `!`, brace lists), so what
   shlex saw is what bash runs. (b) git is a read-only subcommand allowlist (`rebase -x`, `difftool`, `bisect run`,
   `submodule foreach`, `ls-remote --upload-pack` and every alias can run a program); denied options are matched in bundled clusters
   (`curl -sSK`) and by unique long prefix. (c) The log is never written through a symbolic link at the log, its spec directory or
   any ancestor inside the repository (`O_NOFOLLOW|O_APPEND`), and `commit-log` refuses a link and refuses the default branch; hooks
   stay on, because they are the repository's own gates and the log may be public. (d) The secret scan matches names that merely
   contain a keyword (`GITHUB_TOKEN=`, `DB_PASSWORD=`), `--password`, `--user u:p` and JWTs. (e) `--command-out` exists only for an
   `OK` verdict; other outcomes are shown from an escaped `--display-out` copy. (f) Pins hash with `--no-filters`; git path lists
   are read with `-z`; a blob is size-checked before it is read; a branch over 5000 commits is refused; field lengths are capped.

## Third addendum — 2026-10-07 (#9578, the third CLO wording check, PASS-WITH-EDITS)

> Append-only. Every item below was applied as the CLO drafted it.

1. **A sentence is printed only on a path where it is true.** `approval-ask` stays the first-capture command sentence; a judgement
   check prints `approval-ask-eyes` (no command runs); a section 8 change prints `approval-ask-change` (the work may already exist, a
   pass is expected, and the earlier version is shown); an interactive re-freeze met at ship prints `refrozen-ship-ask` (the change
   is already committed and the run is the ship run).
2. **Answer labels are printed, not typed.** `opt-change` no longer says the new check must fail (a re-freeze baseline is a report);
   the old text survives as `opt-change-new` for a check with no freeze yet. `opt-retry-fixed` is offered for environmental stops,
   where retrying changes nothing until the cause is fixed. The VACUOUS answers are `opt-strengthen`, `opt-eyes` and `opt-drop`.
3. **`refrozen-note` no longer asserts an approval the code cannot see.** It says the approval was recorded under the founder's name
   (the commit email and `approved_by` are both agent-writable, see the second addendum), and the reference prints `refrozen_from`
   immediately before it so "the earlier text is shown above" is true.
4. **`headless-stop` next-steps** for BLOCK-REJECTED and CHANGED-SINCE-APPROVAL now say which answers the founder may be offered
   (change, retry for an environmental cause, confirm, restore, continue), instead of promising a fixed set.
5. **Smaller edits.** `eyes-ask` states that a yes is recorded in the log and the check no longer stops the ship;
   `untrusted-unmeasured` says "compare this check's author with you" (nothing is authenticated); `freeze-without-block` no longer
   says who approved, because it is decided before the authorship anchor; `too-long` names the parts that can be too long. When
   `commit-log` refuses (default branch, symbolic link) the reference tells the founder the log was written but not committed.
6. **Accepted, not changed.** `first-use` lists what the check can read, as a floor and not an "only" (the sandbox also exposes
   `/etc`, `/usr` and, in a worktree, the shared git directory). `pass` says "the check you wrote" even when the freeze came from
   main and no author comparison ran, which `no-pr-note` does not cover; accepted for the single-founder v1 posture.
