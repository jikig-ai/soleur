---
date: 2026-09-23
issue: 8209
pr: 8563
category: security-issues
module: infra-credentials
problem_type: security_issue
tags: [credentials, github-actions, terraform, doppler, mutation-testing, guards, vacuity]
---

# Learning: every fix I shipped to close a defect carried the same defect

## Problem

PR #8563 evicts four repo-secret-reachable credentials from Doppler `prd_terraform`
(ADR-241's two-tier model). Four review rounds produced 30+ findings. The striking thing
is not how many there were — it is that **the highest-severity ones were in the fixes,
not in the feature**, and each reproduced the exact class the fix existed to close.

Five in a chain, each discovered only because the previous one was:

1. **The feature broke the before state.** Census row G1g forbids reading a Tier-B name
   from `prd_terraform` outside the loader. I satisfied it by *deleting* 15 inline
   `HCLOUD_TOKEN=$(doppler secrets get …)` reads and replacing them with
   `${HCLOUD_TOKEN:-}`. Those sites run **outside** the `doppler run` wrapper, and the
   loader's legacy arm exported nothing — so between merge and operator step O3 every
   stock-preflight gate, the drift orphan sweep, the rung-2 hard reset and the root-key
   attestation would abort on an empty token. The comment three lines above each site
   said so verbatim ("an outage, not a tripwire"). Satisfying a guard by removing the
   thing it guards is not satisfying it.

2. **The fix for (1) was a branch-to-main RCE.** It exported with
   `printf 'HCLOUD_TOKEN=%s\n' >> "$GITHUB_ENV"`. That value comes from `prd_terraform`,
   which the branch-nameable `DOPPLER_TOKEN_WRITE` repo secret can write until O11 — so
   `tok\nBASH_ENV=/tmp/x` writes a **second line** into `$GITHUB_ENV`, and Actions honours
   `BASH_ENV` and `LD_PRELOAD` in every later `run:` step. Arbitrary code execution in a
   main-only job, from a branch, through the exact substitution path the action exists to
   close. `--preserve-env` is no defence: the loader is the thing doing the write.

3. **The test for (2) failed in the opposite direction.** My first assertion was a plain
   `grep -qx 'BASH_ENV'` over `$GITHUB_ENV` — which matches a line **inside a heredoc
   body**. A correctly *contained* value would have been reported as an injection. The
   assertion had to parse `$GITHUB_ENV` the way Actions parses it (a `NAME<<` + delimiter
   line opens a body that is data until the delimiter line).

4. **The fix for (1) was a silent no-op the whole time.** The legacy arm's
   `doppler secrets get` had **no `DOPPLER_TOKEN=` prefix** while the Tier-B arm two
   screens below did, and the step's `env:` binds no `DOPPLER_TOKEN`. So the read ran
   unauthenticated, exited non-zero, `2>/dev/null` hid the reason, `|| legacy_hcloud=""`
   turned the failure into a value, and the arm took its "no token available" branch —
   warning about a missing **secret**. Every symptom of the fix working was present.
   Nothing was exported.

5. **The test could not see (4), because the stub answered regardless of the token.** Rows
   1b and 1c were green over an arm that exported nothing.

The same shape, twice more, outside that chain:

- **DP-11 F8.** I widened `reviewers` to `reviewers OR main-only branch policy` so the
  new reviewer-less Tier-B environment could pass, and wrote in the comment that this was
  *"strictly STRONGER than the old check"*. A disjunction is strictly **weaker** than
  either side. Emptying `web_platform_infra_apply`'s reviewer list now passed — converting
  the sole human authorization for a host birth into an auto-approve, which is verbatim
  the harm the `#6730` comment ten lines above says declaring that environment exists to
  prevent.
- **The assertion that names the U1 harm could not detect it.** `github-app-manifest-parity`
  asserts `removed { lifecycle { destroy = false } }` on the App's live runtime key. The
  haystack was raw text, so

  ```hcl
  lifecycle {
    # was: destroy = false
    destroy = true
  }
  ```

  matched the **comment** and passed while the next apply would delete the key every
  connected user's GitHub connection depends on. Its block slicer also ended at the first
  column-0 `}`, so indenting one closing brace — valid HCL — ran the slice into the next
  `removed` block and captured **its** `destroy = false`. The comment above that slicer
  explains that hazard and claims the slicing fixes it. Two spaces restore it.

## Solution

**Fix at the seam the guard sanctions, not at the call sites.** The outage fix belongs in
the loader's legacy arm — one place, reaching all 15 consumers including ones the PR never
touched, and zero bytes in a workflow that is 2 KB from a hard size gate.

**Every `$GITHUB_ENV` write uses the heredoc-delimiter form**, with a per-line mask. Never
`printf 'K=%s\n'` for a value the writer does not control.

**Make the stub authenticate.** A fail-closed stub that answers regardless of credentials
cannot see a missing credential. The refusal text is shaped like the vendor's real one so
the arm's auth-vs-absence branch meets something it would actually meet.

**Separate could-not-measure from measured-bad** at every such read. `legacy_token_unauthorized`
and `hcloud_token=absent` send an operator to opposite places; conflating them sends someone
to Doppler to add a key that is already there.

**A widening needs a ratchet.** `REVIEWERS_RATCHET` (measured off the tree, not guessed)
keeps the old strict property for the four environments that already had reviewers; the
disjunction is available only to environments that never gated on a human. An unmatched
ratchet entry is itself an error, or renaming an environment silently leaves the ratchet.

**Comment-strip and brace-match every haystack** whose matches are claims about what a
tool will do. Terraform does not read comments; neither should the assertion.

**Parameterize the walk so a synthetic fixture can drive it.** Every deployment policy on
the live tree says `branch_pattern = "main"`, so the pattern test could be deleted outright
and stay green. `policyPatternsFor(files)` takes its file list for exactly this reason.

## Key Insight

**A fix commit is the least-audited surface in the diff, and the defect class it names is
the one it is most likely to carry.** The mechanism is not carelessness — it is that the
author is holding the defect's *shape* in mind while writing new code in the same shape.
Five of this session's findings sat inside commits whose subject line was closing that
exact class.

Three consequences worth generalising:

- **Grade the fix as its own change.** Before reading anything else, read the fix's NEW
  code for the class it claims to close, and ask whether it was applied to the INSTANCE or
  to the CLASS.
- **"Anchored on a call-form a comment cannot produce" is necessary and not sufficient.**
  The haystack must also be comment-stripped, scoped to the region under test, and the
  match unique within it.
- **A guard that can only ever demonstrate its pass branch is not a guard.** If every
  member of the live population already satisfies the property, deleting the check is
  green. That needs a synthetic fixture or a seam — a mutation of the SUT cannot reach it.

And one about instruments: **`guard-vacuity-floor` caught me**. It reported
`no-longer-floor-bearing` for the loader suite because a `<<` inside a **comment** opened a
phantom heredoc in its parser, whose tag never appears, whose body ran to EOF, and which
swallowed that suite's own anti-vacuity floor. The arm was right — the floor really had
left the covered set. A file-selected suite set structurally cannot return a repo-global
ratchet, because the ratchet references none of the changed files.

## Session Errors

- **Satisfied a census row by deleting the read it governs, breaking the before state.**
  Recovery: moved the read into the loader's legacy arm where the census sanctions it.
  **Prevention:** when a guard forbids a construct, ask where the construct is *allowed*
  and move it there; deleting it is only correct when nothing consumed it. Grep the
  consumers before deleting.

- **Wrote a `$GITHUB_ENV` injection into the fix for that outage.** Recovery: heredoc
  delimiter form at both sites, per-line mask, mutation row driving the exact attack.
  **Prevention:** treat every `>> "$GITHUB_ENV"` as an injection site unless the value is
  a literal. Already routed to the review skill.

- **The injection test matched inside the heredoc BODY (false positive direction).**
  Recovery: wrote an `env_keys()` awk parser that reads `$GITHUB_ENV` the way Actions does.
  **Prevention:** when asserting that a value was *contained*, the assertion must model the
  consumer's parser; a substring test cannot distinguish data from a key.

- **The legacy arm's `doppler secrets get` had no `DOPPLER_TOKEN=` prefix while the
  sibling arm did — the whole fix was a silent no-op for two commits.** Recovery: prefix
  added, `2>/dev/null` replaced with stderr capture, auth failure and absent key separated.
  **Prevention:** when two arms of one file do the same vendor call, diff them. An
  asymmetry between sibling arms is the cheapest defect to find and the easiest to miss.

- **The test's `doppler` stub answered regardless of the token, so it could not see that.**
  Recovery: the stub now authenticates and refuses with vendor-shaped text.
  **Prevention:** a fail-closed stub must fail closed on *every* precondition the real
  thing enforces, not only on the command name.

- **Claimed in a comment that a widened check was "strictly STRONGER"; it was strictly
  weaker.** Recovery: `REVIEWERS_RATCHET`, and the false sentence deleted rather than left
  standing beside its correction. **Prevention:** for every causal or universal sentence a
  diff ADDS, name the command that falsifies it and run it. `A || B` is never stronger
  than `A`.

- **Three guards were satisfiable by a comment** (`destroy = false`, the census's alias
  licence, the read-only-first allowance). Recovery: comment-stripped haystacks and
  command-position matching. **Prevention:** any assertion about what a tool will do must
  read what the tool reads.

- **A `removed` block made the root-key root unappliable**: the partial backend had no
  `-backend-config` consumer (the loader step carried no `id:`) and the `8209_custody_forget`
  jq arm specified in the ADR, runbook and tasks.md was never written. Recovery: both wired.
  **Prevention:** a plan item that appears in three documents and no diff is a delivery gap;
  grep the artifact for each promised identifier before claiming the phase is done.

- **`verdict=legacy_app_key_evicted` existed in three documents and no code.** Recovery:
  implemented at all four consumers plus census row G4e. **Prevention:** same as above —
  grep every verdict/identifier a document promises.

- **Guard 5 was declared in the ADR and in the census's own header comment, and implemented
  nowhere.** The only repo-wide hit for `plan_only` outside YAML was that comment.
  Recovery: rows G5a/G5b/G5c, a fixture, three mutants. **Prevention:** a comment that
  asserts a guard exists is a claim; `git grep` it.

- **Broke the repo-global `guard-vacuity-floor` ratchet with a `<<` inside a comment.**
  Two of my three fix attempts were wrong — I added a space, which that parser explicitly
  allows (`<<-?[[:space:]]*`). Recovery: a non-identifier character after the `<<`.
  **Prevention:** run the repo-global ratchets on every change, not the file-selected set;
  no query over changed files returns a guard that references none of them.

- **A Python insertion landed inside a heredoc** because the `# ── Guard 2 ──` anchor
  matched an earlier occurrence in a comment; the script silently became broken and the
  census reported "0 files scanned". Recovery: `max(...)` over all matches plus a manual
  relocation. **Prevention:** when inserting by anchor, assert the anchor is unique, or
  select the occurrence explicitly.

- **Used `step_bodies` before its definition**; the census crashed with 0 verdicts and the
  suite surfaced no traceback — only the G0 floor fired. Recovery: moved the helpers above
  first use. **Prevention:** the floor did its job, but a crashed instrument should print
  *why*; a floor that reports "0 verdicts" without the cause costs a debugging round.

- **The G0 floor reported through `fail()`** — the one helper a crash or launder disarms.
  Recovery: `printf` + `exit`, per ADR-193, which this file's own header states.
  **Prevention:** already a rule; the recurrence is the finding.

- **Took a RED reading of `cutover-inngest-workflow.test.sh` from a tree a subagent was
  concurrently mutating.** Recovery: re-measured three times (stably green) and against
  `origin/main`. **Prevention:** a verdict from a tree another agent is mutating is not a
  verdict. Re-measure before reporting, and prefer disjoint file sets when delegating.

- **Guessed a mutation row's landing count (2) where the harness measured 4.** Recovery:
  corrected the expectation, not the harness. **Prevention:** a mutation row whose edit
  lands on the wrong number of lines is not testing what its name says.

- **Exceeded my own AC6 byte margin twice** (488,464 and 488,952 against 488,000).
  Recovery: relocated prose to the job-rationale runbook behind canonical
  `# Rationale: … §<id>` pointers. **Prevention:** check the byte gate in the same edit
  that adds a comment to that workflow; it has ~2 KB of headroom.

- **Shortened a `# Rationale:` pointer and broke the sibling gate** that requires every
  `## <id>` heading in that runbook to have a matching pointer. Recovery: restored the
  full-path form and paid for it elsewhere. **Prevention:** the pointer form is load-bearing
  syntax, not prose.

- **Two guards were made unsatisfiable by the change and only CI said so** (AC8b's exact
  `if: always()`, and the rung-2 SHA-pin check rejecting a `./` local composite action).
  Recovery: widened each to one exhaustively-spelled alternative, with mutants proving the
  original defect still reds, plus a non-vacuity floor on the pin exemption.
  **Prevention:** when adding a conjunct to a workflow `if:` or a new `uses:`, grep the
  suites that read that workflow — 20 of them here — before pushing.

- **The PR was `CONFLICTING`/`DIRTY`, which suppressed every `pull_request` workflow**, so
  the previously-green check set was green-but-*incomplete* rather than green.
  Recovery: merged `origin/main`, resolved the `PROMOTED_FILES` collision as a union.
  **Prevention:** `gh pr view --json mergeable` before reading a check set as a verdict; an
  absent check is not a passing one.

- **ADR ordinal collided three ways** (239 claimed by this branch, #8211 and a shard branch;
  240 taken). Recovery: yielded to ADR-241 after re-measuring across every origin ref.
  **Prevention:** already in the plan's Sharp Edges — re-run the all-refs probe immediately
  before merge. It fired exactly as written.

- **`amends:` frontmatter named ADR-168 where ADR-169 is amended**, and the eviction
  sentinel `EVICTED_SEE_ADR_238` pointed at a third ADR. Recovery: both corrected.
  **Prevention:** frontmatter is machine-readable and review-invisible; check it against the
  ADRs that actually carry a superseding callout.

- **The renumber sweep rewrote a file a subagent was concurrently editing.** Recovery: the
  subagent's edits survived; verified afterwards. **Prevention:** do not run a repo-wide
  sweep while a delegated agent holds any file.

- **Ran `bun test` on a vitest-only path** (`apps/web-platform/**` is in bunfig's
  `pathIgnorePatterns`), which reported "no test files matched" — not a failure.
  **Prevention:** read the runner's own invocation (`grep run_suite scripts/test-all.sh`)
  rather than inferring it from the filename.

- **Boundary call, stated rather than buried:** `git-data-rung2-rehearsal.test.sh` matches
  the `git-data-*.test.sh` glob the operator fenced off for the parallel #8211 session. I
  measured that PR #8564 does not touch that file before editing it, and the alternative
  was to drop the credential loader from that workflow. **Prevention:** when a fence is
  specified by glob but justified by ownership, measure the actual overlap and say so in
  the commit and the report.

## Prevention

Highest-leverage, in order:

1. **Grade every fix commit as its own change**, for the class it names. Already a rule in
   `review/SKILL.md` §0; this session is its fourth citation and the first where the
   author and the reviewer were the same process.
2. **`$GITHUB_ENV` heredoc-only** for any value not a literal.
3. **Diff sibling arms** of the same vendor call in one file.
4. **Ratchet every widening**, from a measured set.
5. **Run the repo-global ratchets** (`guard-vacuity-floor`, `lint-diagnosis-claims`,
   `fixture-relative-assert`) on every change — the file-selected set cannot see them.
6. **Re-measure before reporting** any verdict taken while another agent held the tree.

## Related

- `knowledge-base/project/learnings/2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md`
- `knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`
- `knowledge-base/project/learnings/2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md`
- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`
- ADR-241, PR #8563, issues #8609 (R1) and #8610 (R6)

## Tags

category: security-issues
module: infra-credentials
