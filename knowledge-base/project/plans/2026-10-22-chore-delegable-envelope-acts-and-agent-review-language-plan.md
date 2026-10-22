---
title: "chore: make the Inngest TLS envelope acts delegable and make 'review' mean the agent review pipeline"
date: 2026-10-22
slug: delegable-envelope-acts-and-agent-review-language
branch: feat-one-shot-delegable-prod-acts-agent-review
issue: 10136
type: chore
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Overview

Workflow and documentation change only. The owner's statement of 2026-10-22 is that no human should be needed to review a pull request or a technical decision (at worst the CTO agent or the agent review pipeline), because Soleur users are not technical. This plan carries out the CTO ruling of the same date in four parts: the runbook's post-merge act envelope, the hold routing in the go command and the one-shot skill, the ship skill's undeferred operator-step gate, and the review wording across skills and agents. Three design forks left open by the ruling were closed by a second CTO ruling (F1, F2, F3 in `knowledge-base/project/specs/feat-one-shot-delegable-prod-acts-agent-review/decision-challenges.md`).

Refs epic #10205 and item #10136. The PR body uses `Ref` only, never `Closes`. The spec directory carries no `spec.md` (this is a one-shot run without a brainstorm), so `lane:` defaulted to `cross-domain` (fail-closed).

### Owner constraints (binding on this plan and on the work phase)

- The PR **stops before merge**: no `gh pr merge`, no `--auto`, no postmerge. The pipeline ends with the PR reviewed and ready for the owner's own merge decision.
- Touches **no production system** and **dispatches no workflow**. It only edits Markdown, one hook test and one bun test. The reads used for verification (`gh run view`, `gh api .../comments`, `git show origin/main:...`) are read-only.
- **No Doppler writes** (and no Doppler reads).
- Wording: say "unavailable" or "disruption", never "outage".
- Test suites run **one at a time with stdin from `/dev/null`**.
- Net issue flow: **no new issue is filed** unless a gate demands it (none is expected; see Deferral check).

## Research Insights

### Premise Validation (Phase 0.6)

Checked by command, all read-only:

- #10205 (epic) and #10136 are OPEN; PR #10783 is the draft for this branch.
- The runbook section exists: `### Production Envelope for the post-merge acts (A0 to A7)` in `knowledge-base/engineering/operations/runbooks/inngest-server.md` (about line 1437).
- Facts the CTO asked to verify against `origin/main` at planning time (455031400c; it later moved to 06836baf, and the planned files are unchanged between the two):
  1. `apps/web-platform/infra/cloud-init.yml:794` is the line `[ -f /mnt/data/inngest-link/inngest-ca.pem ] || install -o deploy -g deploy -m 0644 /dev/null /mnt/data/inngest-link/inngest-ca.pem`, an EMPTY placeholder, and the comment above it says `ci-deploy.sh installs the real PEM`.
  2. The `ci-deploy.sh` header (TRUST-ANCHOR ORDERING) states the CA is touched only when https is resolved and is installed through `_inngest_link_install` into `$INNGEST_LINK_DIR/inngest-ca.pem` only after the host-side self-gate passes.
  3. `scripts/inngest-link-flip.sh` `flip_cmd_flip` runs `flip_apply_flag "pending:..."`, `flip_dispatch_redeploy`, then `flip_verify` (which reads the handshake hook and requires `result=pass`), and only then `flip_apply_flag 1`.
  4. `verified_rc=77` before the flip: reproduced locally against a throwaway TLS listener with curl 8.23 (an empty `--cacert` file gives exit 77, no CA at all gives 60). The host's curl version was not read, so the runbook says "is expected" and cites the repo facts as the cause.
- Run IDs: apply run 39400431311 (workflow_dispatch, success, 2026-10-20) and cutover run 39445004559 (workflow_dispatch, success, 2026-10-20) exist and concluded `success`. The `iid` and the `tls-health` values come from the CTO ruling and the owner's record; they were not re-read (that needs a Doppler-backed query, which this PR must not do).
- **Delta from the ruling:** PR #10501 (act A0) merged on 2026-10-20 and #10405 merged 2026-10-19. A1 lists "#10501 merged" as its precondition and the ruling records A1 done, so A0 is recorded done as well.
- No Standing Delegation marker comment exists on #10205 (the marker-filtered comment listing is empty). The runbook therefore says form (b), an in-session per-command go, is the only live authority until a delegation is recorded.
- ADR corpus check (Phase 0.6 item 4): ADR-289 already chose "recorded operator consent plus a drift guard" (Option H) and rejected a PreToolUse enforcement hook (Option E) and a wrapper (Option F). This plan applies ADR-289, it does not change its Decision. Its rejected-alternatives table is the reason F1 changes no detection and adds no hook exemption.

### Property List (Phase 0.6b)

1. The runbook never tells a reader to run a check that cannot pass before the flip (the handshake before the CA is installed).
2. The runbook's act table records what already ran (A0, A1, A1b) so nobody re-dispatches a replace.
3. A reader can tell, per act, whether it needs the owner personally (human gate) or may run on a recorded Standing Delegation or a typed per-command go.
4. An epic with production holds reaches the CTO "Own the epic" flow and the standing-delegation question is asked once, even when the brief is one line.
5. A delegated act written into a PR body does not trip the undeferred operator-step gate, and a genuine operator step still does.
6. No skill, agent or runbook text tells a PR or a technical decision to wait for a human reviewer.
7. No hard safety rule is weakened without a stated compensating control; `hr-menu-option-ack-not-prod-write-auth`, `wg-cla-signed-author-before-merge` and the CI and CLA rulesets are untouched.

### Cut List (Phase 0.6b)

- New AGENTS.rules.md rule or rule edit -> property 6 -> already covered by `rf-never-skip-qa-review-before-merging` ("Review-gated = `soleur:review` RAN ... never that a person approves") and `hr-technical-fork-is-not-an-operator-question`. Cut: zero AGENTS edits, budget lint untouched.
- New hook exemption or a mechanical delegation check inside `ship-operator-step-gate.sh` -> property 5 -> the unchanged phrasing-based detection plus an authoring form already buys it (ruled F1, ADR-289 Option E rejected). Cut.
- New standalone "epic driver" skill -> property 4 -> the CTO "Own the epic" interface already exists (ADR-289 Option D). Cut.
- Edits to workflow files, `apps/web-platform` code or CI rulesets -> property 6 -> none is needed (only prose assumes a human). Cut.
- Machine-checkable `## Production Envelope` sections for A0 to A4 -> property 3 -> not buildable honestly now: A0 and A1 already ran and no Standing Delegation exists yet; the CTO writes the envelope file when it owns the epic under a recorded delegation (standing-delegation.md section 2). Cut; the runbook says so.

### Institutional learnings applied

- `knowledge-base/project/learnings/workflow-patterns/2026-10-15-the-founder-said-the-cto-owns-the-decision-and-soleur-users-are-not-technical.md`: the standing-delegation design this plan extends.
- `knowledge-base/project/learnings/workflow-patterns/2026-10-18-a-standing-approval-can-only-name-prs-that-exist-and-the-fix-i-was-asked-for-was-already-merged.md`: a delegation Scope item can only name acts that can already be named, and a claim about a delivery path must be grepped before it is written. Applied: the A0 and A1 done facts and the placeholder facts were checked, and the runbook says a delegated run needs its own committed envelope.
- `knowledge-base/project/learnings/2026-10-04-an-allow-list-of-line-shapes-is-not-a-closed-sequence-and-a-text-matching-hook-stops-delegated-agents-silently.md`: delegated agents hit text-matching hooks; the work phase writes files containing hook-trigger text with the Write tool and keeps Bash commands short.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "the CTO found no 'Own the epic' in skills/go/SKILL.md or skills/one-shot/SKILL.md" | Confirmed for those two files, but `plugins/soleur/commands/go.md` Step 1.5 already carries the Own-the-epic spawn, the ask-once wording, the render recipe and the stop sequence; `one-shot/SKILL.md` has a one-sentence pointer (headless form only) | Extend Step 1.5 (list source) and widen the one-shot pointer; add no second definition |
| "go.md Step 1.5 already defines a HOLDS/OWNER-GATED trigger" | True, but the list must sit inside the brief itself, so "continue epic #10205" skips it | F2: the list may also come from the open epic body or a named plan's `## Operator Holds` |
| (3) "verify ... that the gate does not count a delegation-covered act" | False as written: the gate and the hook count phrasing and have no delegation awareness (a bullet starting with the word Operator and a verb such as run, an `Operator:` heading bullet and an `AC-PM3` bullet all match; a bullet starting `Delegated act (CTO, ...)` does not) | F1: document the authoring form, change no detection, add test rows |
| "A1 and A1b done on 2026-10-20" | Both runs exist and succeeded; A0 (PR #10501) merged the same week | Record A0, A1, A1b done; A0 is a delta, flagged above |
| A1's mechanism line has `-f reason='PR 10501 inngest link TLS'` | A delegated envelope line must be on the closed command grammar: values may not hold spaces or quotes | Runbook note: a delegated line uses a space-free `reason` token |
| `fix-issue/SKILL.md` cites `scheduled-bug-fixer.yml` as the independent gate | No such workflow file exists in the repo (`git ls-files` finds only archived plans); the re-check is `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` | Fix the documentation pointer (prose only) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "we shouldn't need a human review, at worse a CTO or Agents Review" [brief] | Phase 4 (review language), Phase 3 (ship) | mapped |
| 2 | "Update our workflow, skills and agents to ensure we improve this." [brief] | Phases 1 to 4 | mapped |
| 3 | "redefine A2 as \"the handshake inside A3's flip_verify ... plus a post-flip re-run of /hooks/inngest-tls-handshake expecting result=pass\"; strike A2 from A3's preconditions" [brief] | Phase 1, steps 1a and 1b | mapped |
| 4 | "fix the sentence that the hook \"answers meaningfully only after the A1 replace\"" [brief] | Phase 1, step 1c | mapped |
| 5 | "record A1 and A1b as done on 2026-10-20 ... and add a general line: a replace whose user_data already carries the TLS listener satisfies A1" [brief] | Phase 1, step 1d | mapped |
| 6 | "rewrite the section header and the A0, A1, A3, A4 rows so these CTO-envelope acts are delegable" [brief] | Phase 1, step 1e | mapped |
| 7 | "KEEP owner-human: A1b `inngest-cutover` environment approval (GitHub required reviewer), A5 credential rotation, A6/A7 owner-signed legal records, money, sole-copy data loss, force-push/ruleset bypass, any 'ask me before' hold" [brief] | Phase 1, step 1f | mapped |
| 8 | "when an epic has production holds, default to the CTO \"Own the epic\" flow and ask the standing-delegation question once" [brief] | Phase 2 | mapped |
| 9 | "verify, and if false fix, that wg-block-pr-ready-on-undeferred-operator-steps does not count a delegation-covered act as an undeferred operator step" [brief] | Phase 3 | mapped |
| 10 | "make \"review\" mean the agent review pipeline (soleur:review / CTO agent) ... Scope this by grep, list every hit, change only those that really assume a human technical reviewer" [brief] | Phase 4 and the hit tables | mapped |
| 11 | "Do NOT touch hr-menu-option-ack-not-prod-write-auth, wg-cla-signed-author-before-merge, the CI/CLA rulesets"; "the plan must state that the PR stops before merge ... touches no production system; dispatches no workflow; no Doppler writes"; "Test suites one at a time with stdin from /dev/null. Net-issue-flow: file no new issues unless a gate demands it." [brief] | Owner constraints; Kept table; Acceptance Criteria 12 and 13 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Fix-issue pointer to `cron-bug-fixer.ts` instead of `scheduled-bug-fixer.yml` | "do not weaken any hard safety rule without a stated compensating control" [brief] | asked (the compensating control must point at a file that exists; CTO F3 item 1) |
| `go-hold-routing.test.sh` positive and negative rows | "ask the standing-delegation question once" [brief] | asked (the trigger change must be pinned by the test that pins the paragraph; CTO F2) |
| A0 recorded done in the runbook | "record A1 and A1b as done on 2026-10-20" [brief] | inferred — A1's own precondition is "#10501 merged", verified merged 2026-10-20, so leaving A0 pending would contradict the A1 record |
| Hook test rows in `ship-operator-step-gate.test.sh` and a bun case | "verify, and if false fix" [brief] | asked (the fix for ask 9 is an authoring form; the form needs a pinning test; CTO F1) |
| `review/SKILL.md` Introduction paragraph | "cite rf-never-skip-qa-review-before-merging and hr-technical-fork-is-not-an-operator-question" [brief] | asked |

### Split Assessment

- Subsystems touched: 3 — `knowledge-base/engineering/operations/runbooks`, `plugins/soleur/{commands,skills,test}`, `.claude/hooks` (tests only); plan artifacts under `knowledge-base/project` are not counted
- Planned files: 14 edited, 2 plan artifacts created | Estimated changed lines: about 260
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. All parts share one ruling and one review; the code surface is docs plus three test files.

## Proposed Solution

Prose edits with test pins where a test already guards the text. No behavior in apps, workflows or hooks changes.

### Phase 1 — Runbook: `inngest-server.md` section "Production Envelope for the post-merge acts (A0 to A7)"

All edits are inside `knowledge-base/engineering/operations/runbooks/inngest-server.md` (the section at about lines 1437 to 1500; related sentences at about lines 1395 and 1580; the bug-fixer table at about lines 3412 to 3414 is Phase 4).

- **1a. A2 redefinition.** Replace the A2 row. New content: "A2: handshake verification = the handshake inside A3's `flip_verify` (`scripts/inngest-link-flip.sh` runs it after the pending redeploy installs the CA, before the `1` write) plus a post-flip re-run of `/hooks/inngest-tls-handshake` expecting `result=pass`". Authority cell: part of the A3 authority. Mechanism: the existing hook GET recipe. Success evidence keeps the one-line `result=pass` body and the web-2 canary note. Rollback unchanged (read-only, none).
- **1b. A3 preconditions.** Strike A2 so "A1 and A2 green" reads "A1 green". Add that the post-flip A2 re-run is part of A3's success evidence.
- **1c. Hook sentence.** The last sentence of "Calling the handshake hook (A2)" becomes: "...the real hook was not called, because it answers meaningfully only after the CA is installed (`cloud-init.yml:794` creates an EMPTY placeholder, the `[ -f ... inngest-ca.pem ] || install ... /dev/null` line; `ci-deploy.sh` installs the real CA only in the https arm; `verified_rc=77` before the flip is expected)."
- **1d. Done record.** Add a "Done" paragraph under the section intro: A0 merged 2026-10-20 (PR #10501, merge queue); A1 done 2026-10-20 (apply run 39400431311, reason "#10390 arc window", iid 171349604, `tls-health` `listener=1`, `served_sha256` = `cert_sha256`); A1b done 2026-10-20 (`cutover-inngest.yml -f op=resume`, run 39445004559). General line: "A replace whose user_data already carries the TLS listener satisfies A1, so A1 is not re-dispatched." In the A0, A1 and A1b rows mark status done and keep the row text as the procedure of record.
- **1e. Header, intro and the A0, A1, A3, A4 rows (delegable).** Keep the heading text (the index entry and links reference "A0 to A7"). Rewrite the intro: authority is one of (a) a valid recorded Standing Delegation on #10205 whose Scope names the act, or (b) an in-session per-command go typed by the owner naming the command. Replace the "owner's own dated go" and "a menu acknowledgement is not a go" wording with that pair, keeping one sentence that a menu acknowledgement is neither form (`hr-menu-option-ack-not-prod-write-auth`, unchanged). Rename the column "Owner go and due date" to "Authority and due date". State that as of 2026-10-22 no delegation is recorded, so form (b) is the only live authority until one is. State that these rows are the readable envelope and a delegated run also needs the machine-checkable `## Production Envelope` section of standing-delegation.md section 2 in its own committed file, one line per command on the closed grammar (a delegated `reason` value holds no spaces, so the A1 example uses a token form). The A3 row keeps "the go is procedural" (`infra-privileged` has no required reviewer, ADR-241) and adds that a delegated run is bound by the verifier, the envelope and the receipt. A4's rollback dispatch (`action=off`) is covered by a Scope item naming `inngest-link-flip.yml`.
- **1f. Kept owner-human (no delegation covers them).** State in the intro and mark in the Authority cell: A1b's `inngest-cutover` environment approval (a GitHub required reviewer), A5 credential rotation, A6 and A7 owner-signed records (A7 keeps "SIGNED BY OWNER (human, not an agent)"), money, sole-copy data loss, force-push or ruleset bypass, and any hold the owner worded as "ask me before". "A failed replace waits for a FRESH owner go before any re-dispatch" stays unchanged (an owner-reserved hold).
- **1g. Consistency sweep inside the runbook.** The "authorization is procedural" paragraph ("the owner's own dated go (act A3 below)") and "Replace the Inngest host (act A1, with its own owner go)" use the new authority wording. The two "blocks the A1 go" notes stay (A1 is done; they remain accurate history).

### Phase 2 — `go.md` Step 1.5 and `one-shot/SKILL.md` (F2)

- **2a. `plugins/soleur/commands/go.md` Step 1.5** (outside the eval-gated block, which stays byte-identical). Keep: 'BOTH', `HOLDS:`, `OWNER-GATED`, "does not by itself make a hold list", the bare `ask the operator` rule, `fail closed`, `ask once`, and every token the test pins. Add, inside the same paragraph or as one further bullet before "Headless", the **list source**. The structured list may come from (1) the brief, (2) the OPEN epic's body, read with one bounded `gh issue view <N> --json body` and fenced code stripped, or (3) a `## Operator Holds` section in a plan file that the brief or epic body names by path and that exists on main (`git cat-file -e origin/main:<path>`; `git ls-files` reads the index, not main). "The epic has production holds" means a `HOLDS:` line or `OWNER-GATED` heading with at least one item, or an `## Operator Holds` section with at least one `- Hold:` item that carries a `Gate:` line or an `Operator-reserved:` line (cite the container format of `operator-holds.md` section 1 by link, do not restate the `Gate:` grammar). Prose ("after the soak", "waiting on") never counts, a closed epic never triggers, the runbook's envelope table is not a source (it describes acts, not holds on this epic), and a non-production epic has no such structure so it never triggers. When it triggers: default to the CTO Own-the-epic flow; in an attached session ask the epic-start question once here, before the worktree exists; headless: keep the literal `do not ask`, search for an existing open `action-required` issue for the epic first, file ONE (naming the ACTION, carrying the Scope items and expiry, pointing at the standing-delegation.md wording instead of copying it), and repeat the same sentence in the final summary so the first attached session asks once. The paragraph must not contain the repo-relative prefix `plugins/soleur/` (a pinned violation token) and keeps the `${CLAUDE_PLUGIN_ROOT}` forms. **Two existing sentences must be reworded, not only supplemented**: "It routes only when a resume or handoff brief carries BOTH an epic reference (`#N`) and a structured list of operator holds" keeps `only when` and `BOTH` but says the list is in the brief, in the epic body, or in the named plan; and the closing "A paraphrased handoff without the epic reference and the `HOLDS:` list falls through to normal routing" gets the same widening.
- **2b. `plugins/soleur/skills/one-shot/SKILL.md`** (the line "A direct run whose brief carries `#N` and a `HOLDS:` list"). Widen to "... or whose epic body or plan carries it, as go.md Step 1.5 defines the trigger", keeping the substrings `follows go.md Step 1.5 in headless form` and `` `HOLDS:` `` that the test greps. No second definition of the trigger.
- **2c. Test pins.** `go-hold-routing.test.sh` is a static token pin over the paragraph text, so it cannot test routing: add "paragraph states X" pins only. Extend `evaluate()` with new `V:` checks (list-source sentence present; `git cat-file -e origin/main` form; closed-epic and prose-only exclusions stated; runbook table named as not a source), add each token to `ALL_PROPS`, and add mutation rows that red on each (each row increments `nrows`). Adding to `ALL_PROPS` alone is not enough: nothing would emit the token. The headless wording is already pinned by existing rows, so no new headless row.
- **2d.** `cto.md` needs no edit (its Own-the-epic interface already returns the epic-start wording). `cto-interface-selector.test.sh` extracts go.md's spawn cue, so it is run after the go.md edit.

### Phase 3 — `ship` Phase 5.5 (F1)

- **3a. Verification result (recorded in the PR body):** the gate and `.claude/hooks/ship-operator-step-gate.sh` have no delegation awareness; they count phrasing. A delegated act written as a bullet starting with the word Operator and a verb, as an `Operator:` heading bullet, or as an `AC-PM<N>` bullet IS counted.
- **3b. Fix: authoring form, no detection change.** In `plugins/soleur/skills/ship/SKILL.md` section "Undeferred Operator-Step Gate" (insert immediately before the next heading, `### Soak-Gated Follow-Through Enrollment Gate`; the Undeferred section runs from its own heading to that one, and the Technical-Ruling Gate section that `components.test.ts` pins starts later, so the paragraph must not land past it) add one short paragraph: an act covered by a Production Envelope and carried out by the CTO agent under a recorded Standing Delegation is written in the PR body as `Delegated act (CTO, Standing Delegation <comment-url>): <act in words>`. It is not an operator step in the sense of `hr-never-label-any-step-as-manual-without` because the agent performs it. The form applies only to an act covered by an envelope (a receipt exists or the act is envelope-covered). At this gate the ship agent runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh" verify --delegation <url>` on the cited URL as a documented prose step (not a hook exemption). The regex and the four options stay untouched.
- **3c. Test rows (both tests are regex mirrors, not hook runs).** `.claude/hooks/ship-operator-step-gate.test.sh` copies the detection regex and checks match or no-match only: add one row proving the `Delegated act (CTO, ...)` bullet does NOT match and one proving a bullet starting with the word Operator and a verb (citing a delegation URL) DOES match. `plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts` carries its own `DETECT_REGEX` and an `undeferredCount` mirror: add the "still blocks without a Tracks companion" case there, plus one assertion that the skill section names the form (this assertion is also the mutation row for deleting the form). The hook script and the SKILL regex stay byte-identical; the test copies are not tied to them by any drift check (a known property of both suites, not widened here).

### Phase 4 — Review language (F3), every hit listed

`AGENTS.rules.md` gets **zero** edits: `rf-never-skip-qa-review-before-merging` (its sentence "Review-gated = `soleur:review` RAN ... never that a person approves") and `hr-technical-fork-is-not-an-operator-question` already carry the rule. The empty merge-base diff of those files is the proof; nothing needs adding.

Grep method: two case-insensitive passes over `AGENTS.rules.md`, `plugins/soleur/skills`, `plugins/soleur/agents` and `plugins/soleur/commands` (phrasings: human review, reviewer or approval or gate, manual review, needs a human, awaiting review, review-gated, ready for review, owner or founder or operator reviews, CODEOWNERS, required reviewers, peer review), plus one pass over `apps/web-platform/server`, `.github/workflows`, `scripts` and `.claude/hooks` to list code-side hits (listed, not edited).

**Changed (really assume a human technical reviewer):**

| # | File and anchor | Today | Change | Compensating control |
|---|---|---|---|---|
| 1 | `plugins/soleur/skills/fix-issue/SKILL.md`: description (line 3), intro (line 16), PR-body template, the `Ref` paragraph, Phase 5.5 label text | "open a PR for human review", "Human review required before merge", "the human reviewer decides when to close the issue", "label for human review" | "agent review via the drain-prs `needs-review` tier"; the review pass decides when the issue closes; label names and `Ref #N` (never Closes) unchanged; fix the stale Phase 5.5 note from `scheduled-bug-fixer.yml` (absent from the repo) to `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` (label assertion, single-file diff check, `p3-low` check). The wording must not claim the review happens automatically (nothing schedules drain-prs) | `cron-bug-fixer.ts` mechanical gate (unchanged) and `triage-prs.sh` routing `bot-fix/review-required` and unlabeled PRs to `needs-review` (verified: the label branch and the fallback branch) |
| 2 | `plugins/soleur/skills/model-launch-review/SKILL.md`: the lead paragraph and the sentence after the audit table | "flags the rest for human sign-off", "reported in the PR body for human sign-off" | "CTO agent ruling" for items 2 to 6; any change that raises spend or edits the `MODEL_PRICING` billing constant stays operator authorization (money); item 1 stays the only auto-applied item | money stays operator-only |
| 3 | `plugins/soleur/commands/sync.md`: Rule Prune Analysis intro | "a human reviews each issue and decides whether to prune" | a CTO agent ruling per `hr-technical-fork-is-not-an-operator-question`, recorded "Ruled by CTO agent"; the command still only files issues and never edits AGENTS.md; default verdict is keep; zero enforcement hits alone is never prune evidence (the log records enforcement events only); a rule whose purpose is user data, production authorization, GDPR or money is never pruned on a zero-hit shortlist (legal parts go to the CLO); the prune itself is a normal PR through `soleur:review` | default-keep verdict and the exclusion list (new, stated) |
| 4 | `plugins/soleur/skills/deepen-plan/SKILL.md`: "Deduplicate and prioritize" list | "Flag conflicting advice for human review" | route conflicting advice to the CTO agent; conflicts on the operator-only list (money, scope, priority and schedule, irreversible-act authorization, legal risk, brand) still go to the operator | operator-only list kept |
| 5 | `plugins/soleur/skills/plan/SKILL.md`: "AI-Era Considerations" checklist | "Document any AI-generated code that needs human review" | name the file and the concern for a closer `soleur:review` pass | review pipeline |
| 6 | `plugins/soleur/skills/test-fix-loop/SKILL.md`: the "On success" note | "The user reviews and commits via `soleur:ship` or manually" | "Fixes are staged, not committed; commit through `soleur:ship`, which runs review." Keep the manual commit option and say a manual commit does not skip review because merge stays review-gated | `rf-never-skip-qa-review-before-merging` |
| 7 | `knowledge-base/engineering/operations/runbooks/inngest-server.md`: bug-fixer auto-merge gate table (three rows) | "review PR manually", "requires human review before merge" (x2) | the two multi-file and non-p3-low rows: "agent review via the drain-prs `needs-review` tier"; the missing-label row: the PR carries neither label and falls into `needs-review` through `triage-prs.sh`'s fallback branch, and the missing label is an agent defect to fix in fix-issue Phase 6 ("exactly one of the two labels") | same as row 1 |
| 8 | `plugins/soleur/skills/review/SKILL.md`: Introduction | (no statement of what review means) | one short paragraph citing `rf-never-skip-qa-review-before-merging` and `hr-technical-fork-is-not-an-operator-question` by id, without restating rule text: review is this agent pipeline, findings are fixed inline, technical decisions go to the CTO agent, the operator-only list is unchanged | the two rules themselves |

**Kept unchanged on purpose (so the sweep is auditable):**

| File and anchor | Why kept |
|---|---|
| `ship/SKILL.md` and `work/SKILL.md` "true human gate" passages (CAPTCHA, OTP, passkey, push-MFA, payment card, hardware token) | genuine operator-only gates (`hr-never-label-any-step-as-manual-without`) |
| `test-browser`, `xcode-test`, `review/references/review-e2e-testing.md` ("pause for human input or verification" on OAuth, email, payment) | credential entry and payment are operator-only |
| `AGENTS.rules.md` line 30 and `operator-bootstrap` (the person approves each production write at the harness prompt) | `hr-menu-option-ack-not-prod-write-auth` and the bootstrap rules, untouched |
| `invoice` (Stripe `human_confirmation`), `social-distribute`, `community`, `agents/support/community-manager.md` (brand association check, external posting), `ux-design-lead.md` and `plan-founder-check.md` (founder design and text approval), `content-writer` ("manual review recommended" for citations) | brand, money and design taste are operator-only |
| `gdpr-gate/references/legal-consent.md` (Art. 22 human-review override), `plan/SKILL.md` copywriter agent-error note (brand copy) | legal and brand |
| `commands/go.md` environment-approval passage ("a human gate") | kept per the CTO ruling (A1b-class approvals) |
| `review/SKILL.md` "human-review gate" dependency trigger shape, `kb-glossary` and `triage` (the founder types the concept slug), `product-roadmap` ("manual review is needed": scope and priority) | operator-class decisions or reminder shapes |
| `constraint-scaffold` stage-b template ("human merge gate"), `provision-github` (required reviewer is the security control that caps `actions:write`), `ship/references/settle-then-admin-merge.md` (an UNTRUSTED-CI change is merged by the owner by hand), `drain-prs` (a maintainer approves a fork run) | generated user-repo CI cannot run `soleur:review`; the others are security controls or ruleset-bypass territory |
| `schedule/SKILL.md` ("waiting on a human reviewer" when a user repo disallows auto-merge) | describes a user repo's GitHub setting, not this pipeline |
| `work/references/key-principles.md` ("faster feedback than waiting for human review"), `plan/SKILL.md` rhetorical "human review misses", `every-style-editor`, `compound-capture`, `changelog` fallback lists, `reproduce-bug` label text | benign wording or fallbacks; no human technical reviewer assumed |
| `wg-cla-signed-author-before-merge`, `hr-menu-option-ack-not-prod-write-auth`, the CI and CLA rulesets | explicit non-goals of the brief |
| code-side hits (`apps/web-platform/server/*` including `cron-bug-fixer.ts`, `agent-runner.ts`, `cc-dispatcher.ts`; `.github/workflows`; `scripts`; `.claude/hooks` strings) | editing app code or workflows deploys to production on merge; out of scope (owner constraint: no production touch) |

### Phase 5 — Verification (one suite at a time, stdin from `/dev/null`)

In this order, each as its own command ending `</dev/null`:

1. `bash plugins/soleur/test/go-hold-routing.test.sh </dev/null`
2. `bash plugins/soleur/test/cto-interface-selector.test.sh </dev/null`
3. `bash .claude/hooks/ship-operator-step-gate.test.sh </dev/null`
4. `bun test plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts </dev/null`
5. `bun test plugins/soleur/test/components.test.ts </dev/null` (skill description budget and the Technical-Ruling Gate window)
6. `python3 scripts/lint-infra-no-human-steps.py <each edited .md under knowledge-base and plugins> </dev/null` (the runbook and skills are scanned; the linter fails on a human-actor word next to an infrastructure verb on adjacent lines, so new runbook sentences keep the two apart; run it and read its verdict)
7. `markdownlint-cli2` over the edited Markdown plus this plan and `tasks.md` (no hard tabs, a blank line before every list; read the exit code on its own line, never through a pipe)
8. A residual grep proving no remaining "human review" or "human reviewer" in the files in the Changed table, and `git diff origin/main...HEAD -- AGENTS.rules.md AGENTS.md` is empty (three-dot, merge-base form, so a sibling merge to main cannot redden it).

If a runner crashes, apply `wg-when-a-test-runner-crashes-segfault-oom`; never run suites in parallel.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `plugins/soleur/commands/go.md` (Step 1.5 only; the eval-gated block stays byte-identical)
- `plugins/soleur/skills/one-shot/SKILL.md`
- `plugins/soleur/skills/ship/SKILL.md` (Undeferred Operator-Step Gate section only)
- `plugins/soleur/skills/review/SKILL.md` (Introduction paragraph)
- `plugins/soleur/skills/fix-issue/SKILL.md`
- `plugins/soleur/skills/model-launch-review/SKILL.md`
- `plugins/soleur/commands/sync.md`
- `plugins/soleur/skills/deepen-plan/SKILL.md`
- `plugins/soleur/skills/plan/SKILL.md`
- `plugins/soleur/skills/test-fix-loop/SKILL.md`
- `plugins/soleur/test/go-hold-routing.test.sh`
- `.claude/hooks/ship-operator-step-gate.test.sh`
- `plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`

Path check: each path above was confirmed with `git ls-files`. The `fix-issue` description (line 3) changes a sentence; its word count must not grow. Re-run the skill-description budget at work time and trim a sibling clause if headroom is under 10 words (`cq-skill-description-budget-headroom`).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-delegable-prod-acts-agent-review/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-delegable-prod-acts-agent-review/decision-challenges.md` (already written)

## Open Code-Review Overlap

Query of the 95 open `code-review` issues against the Files to Edit list: `#4133` (follow-through: schema parity test for the `## Observability` block) names `plugins/soleur/skills/plan/SKILL.md` and `plugins/soleur/skills/deepen-plan/SKILL.md`. **Acknowledge:** a different concern (the Observability block schema); this plan edits one sentence in each file and does not touch that block. It stays open. No other overlap.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled on 2026-10-22 on all four parts (T1 to T4) and again on three design forks (F1 to F3), recorded in `decision-challenges.md`. The ruling is the domain assessment; no brainstorm preceded this plan. Product/UX: no user-facing page, component or copy is created or modified (the Files lists contain no UI-surface path), so that gate is NONE. Legal: A6 and A7 stay owner-signed and untouched and the Excluded list of the Standing Delegation record is unchanged, so no new legal posture is introduced. Operations: the runbook edit records existing facts and changes the wording of authority only.

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent carrying out a production act (for example the Inngest link flip) on wording looser than the owner intended, which would show up as a brief unavailable or degraded scheduler for the owner's product, or a PR parked waiting for a reviewer who does not exist.
- **If this leaks, the user's workflow is exposed via:** nothing new. No credential, token or tenant data is read or written; the only recorded identifiers are public run IDs and an instance id already in the issue history.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** aggregate, not single-user: the wording only widens who may authorize an act while the hard controls (admin-authored delegation, closed command grammar, byte-identical envelope line, receipt, hook-gated forms still prompting) are untouched and each kept owner-human act is named; a single bad wording could affect every user of the scheduler, which is why the kept list and the compensating controls are explicit.

Compensating controls for the safety-adjacent edits: `delegation-verify.sh` (single chokepoint), the Production Envelope grammar (four command shapes), `hold-gate-eval.sh` at ship Phase 6 step 5, the ran-row and receipt check in `technical-ruling-gate.sh`, `prod-write-defer-gate.sh` (unchanged), and `hr-menu-option-ack-not-prod-write-auth` (untouched).

## Gates skipped, with reasons

- Observability (Phase 2.9): Files to Edit have no code-class file under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts`; the changes are documentation and tests. Skipped.
- Encryption posture (Phase 2.11): no persistent store or new connection. Skipped.
- GDPR gate (Phase 2.7): no regulated-data surface. Skipped.
- IaC routing (Phase 2.8): no new infrastructure; the runbook documents existing dispatches. Skipped.
- Guard Contract (Phase 2.12): the deliverable edits no guard; Phase 3 adds two rows to an existing test and leaves detection unchanged. Skipped.
- ADR and C4 (Phase 2.10): no architectural decision is made. ADR-289 already records the Standing Delegation design and rejected the hook-exemption alternative this plan also declines. A reader of ADR-289 and the C4 views is not misled after this ships. Skipped.

## Acceptance Criteria

- [ ] AC1. The runbook section heading keeps "A0 to A7"; the A2 row is redefined as the flip_verify handshake plus a post-flip re-run expecting `result=pass`, and the A3 preconditions no longer name A2 (`git grep -n 'A1 and A2 green' knowledge-base/engineering/operations/runbooks/inngest-server.md` returns nothing).
- [ ] AC2. The hook sentence reads "only after the CA is installed" with the `cloud-init.yml:794` placeholder, the `ci-deploy.sh` https-arm and the `verified_rc=77` clauses; the old phrase "only after the A1 replace" is gone (grep).
- [ ] AC3. A0, A1 and A1b are recorded done with run ids 39400431311 and 39445004559 and iid 171349604, and the line "a replace whose user_data already carries the TLS listener satisfies A1, so A1 is not re-dispatched" is present.
- [ ] AC4. In the runbook (collapse line wraps first: `tr '\n' ' ' < <file>`), "owner's own dated go" and "A menu acknowledgement is not a go" no longer appear anywhere (this covers the intro, the authorization paragraph and the replacement-sequence step); the short anchors "valid recorded Standing Delegation" and "in-session per-command go" appear in the intro and in each of the A0, A1, A3, A4 authority cells; one sentence says a menu acknowledgement is neither form.
- [ ] AC5. The runbook intro names each owner-human item (grep each anchor: `required reviewer`, `A5`, `A6`, `A7`, `SIGNED BY OWNER (human, not an agent)`, `sole-copy`, `force-push`, `ask me before`) and the A1b, A5, A6, A7 Authority cells say `owner-human`.
- [ ] AC6. `go.md` Step 1.5 carries the pinned literals plus the new list-source sentence (`go-hold-routing.test.sh` passes with its new `V:` checks), the reworded `only when ... BOTH` and closing sentences, and the `origin/main` existence check form; the eval-gated block hash equals the merge base (the test's anchor row).
- [ ] AC7. `one-shot/SKILL.md` points to go.md Step 1.5 for the widened trigger and keeps `follows go.md Step 1.5 in headless form` and `HOLDS:`.
- [ ] AC8. `ship/SKILL.md` documents the `Delegated act (CTO, Standing Delegation <comment-url>): ...` form and the prose verification step; `DETECT_RE` in the skill and `GROUP_A` to `GROUP_D` in the hook are byte-identical to `origin/main` (`git diff origin/main...HEAD -- .claude/hooks/ship-operator-step-gate.sh` is empty); the new rows prove the form passes and a bullet starting with the word Operator and a verb, citing a delegation URL, still blocks.
- [ ] AC9. Every Phase 4 Changed row is applied: `git grep -n -iE 'human review|human reviewer|human sign-off|review (PR )?manually' -- <the Changed files>` returns no line that assumes a human technical reviewer (list any remaining hit with its reason in the PR body); `git diff origin/main...HEAD --name-only` contains none of the Kept-table files.
- [ ] AC10. `git diff origin/main...HEAD -- AGENTS.rules.md AGENTS.md scripts/retired-rule-ids.txt` is empty (the corpus is untouched, so the budget lint has nothing to measure).
- [ ] AC11. All Phase 5 suites pass, run one at a time with stdin from `/dev/null`.
- [ ] AC12. `git diff origin/main...HEAD --name-only | grep -E '^\.github/|^AGENTS|^scripts/retired-rule-ids'` prints nothing, and `hr-menu-option-ack-not-prod-write-auth` and `wg-cla-signed-author-before-merge` are not in the diff (`git diff origin/main...HEAD -U0 | grep -c 'id: hr-menu-option-ack-not-prod-write-auth\|id: wg-cla-signed-author-before-merge'` is 0).
- [ ] AC13. The PR body uses `Ref #10205` and `Ref #10136` only (`gh pr view --json body --jq .body | grep -ciE 'closes|fixes|resolves'` is 0); the PR is left unmerged (`gh pr view --json state,mergedAt` shows OPEN and null) and the session ran no `gh pr merge`, no workflow dispatch, no Doppler command and no `gh issue create` (the work-phase command log is the evidence).
- [ ] AC14. No line added outside this plan file uses the word "outage" (`git diff origin/main...HEAD -U0 -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' | grep -i outage` returns nothing).

## Test Scenarios

- Static pin: Step 1.5 states that an open epic body with an `OWNER-GATED` heading and one item, reached from a one-line brief such as "continue epic #10205", counts as the hold list and routes to the CTO Own-the-epic flow.
- Static pin: Step 1.5 states that prose such as "after the soak" never counts.
- Static pin: Step 1.5 states that a closed epic never triggers and that the runbook's envelope table is not a source.
- Given a brief that points only at the runbook table, Step 1.5 does not route.
- Regex mirrors: the `Delegated act (CTO, Standing Delegation <url>): flip the link flag` bullet does not match the detection regex; a bullet starting with the word Operator and a verb, followed by a delegation URL and no `Tracks` companion, matches and counts as undeferred in the bun `undeferredCount` mirror.
- Mutation rows (each shown to fail when the guarded text is removed): delete the Step 1.5 list-source sentence; delete the authoring form from the ship section. Each reds with its own violation token. (The `Own the epic` and `BOTH` tokens are already pinned by existing rows.)

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Exempt delegation-cited bullets inside the hook or the skill regex | Rejected (F1, ADR-289 Option E): a URL in free PR-body text cannot carry the envelope and command binding the verifier needs, and a network call in a PreToolUse hook adds fail-open modes |
| Edit `AGENTS.rules.md` to define "review" | Rejected: `rf-never-skip-qa-review-before-merging` already defines it; AGENTS budget and ADR-151 conventions favor skill and runbook text |
| Trigger Step 1.5 on an epic reference alone, or read the runbook table as a trigger source | Rejected (F2): would ask a spurious question for any epic that touches `inngest-server.md` |
| Change the fix-issue workflow or `cron-bug-fixer.ts` PR text | Rejected: code and workflow edits deploy on merge; this PR touches no production system |

## Dependencies & Risks

- **The go.md paragraph test is strict.** The paragraph runs from the Step 1.5 heading to the next heading; the `plugins/soleur/` prefix is a pinned violation and the eval-gated block must stay byte-identical. Mitigation: run `go-hold-routing.test.sh` after each go.md edit.
- **Text-matching lint.** `lint-infra-no-human-steps.py` scans the runbook and skills. Mitigation: Phase 5 step 7.
- **Delegated-form misuse** (a real operator step labelled "Delegated act"). Bounded by the receipt and ran-row requirement; a cross-check, if ever added, is a technical-ruling-gate WARN (CTO dissent recorded).
- **Nothing schedules drain-prs**, so "agent review via the drain-prs needs-review tier" is worded as the route a bot-fix PR takes when that skill runs, never as an automatic guarantee (CTO dissent recorded).
- **No-merge handoff.** After review and QA the PR is left for the owner's merge decision. The PR body's first line answers "does merging this alone mutate production?": no, it changes Markdown, skills, a hook test and a bun test only, and no workflow's `paths:` trigger or `-target=` set is touched (`ship-operator-step-gate.sh` itself is not edited, only its test).

## Deferral check

No item is deferred to a later phase. The Cut List and Kept tables are decisions with reasons, not deferrals, so no tracking issue is filed (net issue flow).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or holds placeholder text fails `deepen-plan` Phase 4.6; this plan fills it.
- `cq-cite-content-anchor-not-line-number` applies to code comments; the runbook is Markdown (exempt) and the brief explicitly asks for `cloud-init.yml:794`, so the content anchor is quoted beside the line number.
- Write files that contain hook-trigger text with the Write tool and keep Bash commands short (learning 2026-10-04); the plan-write guard also rejects the literal phrase pairing the word operator with a run or install verb, so the plan describes those bullets indirectly.
