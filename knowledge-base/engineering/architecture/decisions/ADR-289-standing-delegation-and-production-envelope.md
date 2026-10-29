---
title: Production-mutating authorization is satisfiable by a verified Standing Delegation plus a CTO Production Envelope
status: adopting
date: 2026-10-15
supersedes: none
issue: 10333
related: [10333, 9757, 10348, 10361]
related_adrs: [ADR-084, ADR-083, ADR-277, ADR-159, ADR-178, ADR-249, ADR-260, ADR-264, ADR-285]
tags: [authorization, delegation, cto, production, non-technical-operator]
brand_survival_threshold: single-user incident
---

# ADR-289: Production-mutating authorization is satisfiable by a verified Standing Delegation plus a CTO Production Envelope

## Status

**Adopting.** The mechanism ships in PR #10348. The status moves to `accepted` after the first real delegated act has run end to end
under it (the epic #9757); that flip is mechanical and is not a deferral. The ordinal was verified free against `origin/main` and
every `origin/*` branch ref (highest ADR-287) and is re-verified at ship. This ADR extends ADR-084 and does not supersede it.

What this mechanism is, in one sentence: a recorded, revocable, expiring operator consent plus a drift guard that keeps the
executed command identical to a committed, allowlisted line. It is NOT separation of duties. The same `gh` identity posts the
record and the CTO agent authors, commits and runs the envelope, so a misbehaving agent is not stopped by it; a cooperating one is
kept inside what the operator agreed to and leaves an attributable trail. Independence from the agent's identity arrives with the
receipt hook tracked in #10361.

## Context

Hard rule `hr-menu-option-ack-not-prod-write-auth` made destructive writes against shared production, and ADR-084's closed
operator-only list made the production-mutating category, a per-command go-ahead from the operator. Soleur's users are not
technical: they cannot judge a command, so the per-command question either stalls the epic or gets answered by reflex, which is
the failure the rule exists to prevent. A resume brief's own `HOLDS` list had the same defect; it was treated as the operator's
even when each hold was a checkable fact.

On 2026-10-15 the founder ruled (quoted exactly in the compound learning): the CTO should own the decision and proceed
autonomously to complete the arc or epic, and the workflow and skills should be improved to that effect because users are not
technical. The design question was how to satisfy that without removing the one control that guards single-user incidents: one
unauthorized merge or workflow dispatch on a user's repository ends trust in "the CTO owns it".

### What the amended rule gives up

Be exact about the loss. Commit `fa06eef79a` (#2883, 2026-04-24) wrote that "the load-bearing safety net is the per-command
confirmation (user reads the exact command before approving)", and
`knowledge-base/project/learnings/2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` (#2618) records the incident
behind it: an agent read a menu "A" as authorization for an unattended production infrastructure change (the `-auto-approve` form). Inside a recorded delegation, for merge,
dispatch and revert only, this ADR removes the operator's per-command read of the exact command. The words merge, dispatch and
revert name intents; the closed command set is merge, ready, dispatch of a named workflow file and PR creation (`gh pr create
--fill`, scoped by a Scope item that names the act), and never a hook-gated form. It also makes the epic-start
confirmation a deliberate, single menu-style acknowledgement that DOES extend to commands the operator never saw. The rule's
sentence "Menu acks and prior approvals never cover new commands" is therefore paired with an explicit second path: a Standing
Delegation that `plugins/soleur/scripts/delegation-verify.sh` reports valid (exit 0; any other result is no authority). The trade
is accepted because the question is plain-language, names act classes, is recorded verbatim and is revocable, and because the
allowlist below bounds what a "Yes" can mean.

The widening is larger than "merge, ready and a named file". Dispatching a named workflow file can run a CI production apply
that has no environment reviewer. The example is `apply-web-platform-infra.yml` with `apply_target=registry-host-replace`, the
exact act in the live #9757 scope. The verifier binds the file name and the `-f` inputs, not what the workflow does. Inputs named
`confirm` or `rollback_ack*` are the typo-guards of the destructive host create/replace and credential-rotation targets, so the
verifier rejects any `gh workflow run` that passes one, with the `non-delegable-command` verdict; those targets stay
operator-only. The rest of a delegated dispatch is a production change that no human reads command by command. This was
reviewed by the CTO agent on 2026-10-18 on founder instruction (users are not asked; the CTO reviews when no human does). The
ack row for the rule records the same facts.

### Precedents

- **Not every production-mutating act was per-command before this ADR.** ADR-260 section 2 (Accepted, 2026-09-28) lets a scheduled
  watchdog POST a restart on the prd project "without a per-occurrence human ack", an "express, bounded deviation from
  `hr-menu-option-ack-not-prod-write-auth`" justified by a recorded delegation, a trigger predicate and a circuit breaker. Ship also
  arms auto-merge of an ordinary PR without a per-merge ack (`wg-after-marking-a-pr-ready-run-gh-pr-merge`). ADR-289 follows the
  ADR-260 shape (the ADR records the delegation, the bounds fail closed) for a different class of act.
- **Why merge and dispatch differ from the operator-script class.** ADR-249 rejects prompt, nonce and hookify-style acknowledgements
  and makes a production write by an operator script "a person-at-a-terminal step on purpose"; ADR-264 builds a harness-approved,
  one-time, command-bound receipt for the same class and records the residual "an agent that reads the hook can mint its own
  receipt". Those scripts take arbitrary shell and hold credentials. A merge or dispatch under this ADR is one of four fixed command
  shapes (`gh pr merge`, `gh pr ready`, `gh workflow run <file>`, `gh pr create`) that run through GitHub's own gates (required
  checks, merge queue, rulesets) and are revertible by a revert PR. That bounds the act; it does not make a dispatched workflow
  safe, because the allowlist binds the workflow file name and inputs, not what the workflow does (see residuals).
- **Receipts.** The execution receipt below is the ADR-264 idea at much lower strength: the CTO writes it, so it carries the same
  residual ADR-264 states. #10361 is the stronger follow-up (a receipt the agent cannot write).
- **Identity.** ADR-285 shows a GitHub App (soleur-infra) authoring CI-side writes. It cannot serve here: a local session has no
  App installation token, and the delegation must be provably the operator's own words posted from their machine. Option G is
  revisited under the flip conditions.
- **Hook-to-plugin anchoring.** ADR-178 is the precedent for a repo-local hook reaching into `plugins/soleur/`. This ADR removes
  the only hook that would have done so (ruling R2), so no new hook-to-plugin dependency is added.
- **Prior art on standing grants.** ADR-159 rejected a standing root-restart grant ("a grant is pure surface"). The rule has been
  loosened three times, each argued from operational friction: #2883 (2026-04-24), ADR-260 (2026-09-28) and this ADR (2026-10-15).
  A future reviewer should weigh that trend; it is the reason the ack row for this rule asks for human review.

## Considered Options

- **Option A: keep the per-command operator go-ahead only.** Pros: zero new surface. Cons: a non-technical operator cannot judge a
  command, so every epic stalls on a question they cannot answer. Rejected.
- **Option B: a pinned local copy of the delegation.** Pros: no network. Cons: a copy cannot see revocation, expiry or an edit.
  Rejected (CTO ruling T1).
- **Option C: trust an act-class label written by the CTO.** Pros: simple. Cons: the same agent would attest its own authority.
  Rejected (T3). The executed command must be a byte-identical full line of a committed envelope, that line must match the closed
  command allowlist (V1), and the cited Scope item's text must name that command's target (V2).
- **Option D: a dedicated `epic-driver` or `production-change` skill now.** Pros: one named runner. Cons: the epic-driver is
  covered by the CTO agent's "Own the epic" interface; the production-change runner has no consumer until the first delegated act
  has run. Epic-driver rejected, production-change deferred to a follow-up issue (T8).
- **Option E: a PreToolUse hook that enforces byte-identical execution.** Pros: execution becomes the authorization point. Cons:
  `prod-write-defer-gate.sh` and `guardrails.sh` are ruled unchanged, and a new hook adds a surface this slice cannot test.
  Rejected for now; it is #10361.
- **Option F: a `delegated-exec.sh` wrapper that verifies and runs in one step.** Pros: verification and execution cannot be
  separated. Cons: it hides the inner command from the unchanged text-matching guards and is itself an execution surface.
  Rejected (CTO ruling C1).
- **Option G: a GitHub App identity or web-UI posting for the delegation comment.** Pros: author differs from the agent's identity.
  Cons: a local session has no App installation token (ADR-285's App serves CI-side writes only), and web-UI posting conflicts with
  the non-technical-user constraint. Rejected (CTO ruling C2); revisited under the flip conditions.
- **Option H (chosen): recorded operator consent plus a drift guard.** A recorded Standing Delegation plus a CTO-authored
  Production Envelope, checked by one shared verifier. The earlier "two independent keys" framing is withdrawn: both artifacts are
  produced by the same agent identity, so they are not independent factors (see Status).

## Decision

**Option H.** Production-mutating stays on the operator-only list as a CATEGORY. It becomes satisfiable by a recorded delegation and
an envelope checked together:

1. **The Standing Delegation.** An issue comment on the epic: line 1 exactly `<!-- soleur-delegation v1 -->`, authored by a real
   user (not a bot, and not posted through a GitHub App) who is the repository owner or holds `admin` permission, with a verbatim
   operator quote of at least 40 bytes, a `Confirmation:` line that starts with `Yes`, numbered Scope items, the fixed
   Excluded paragraph, and an expiry no later than 30 days after creation. The epic closing also ends it. Revocation is deleting or
   editing the comment. The operator gives it once, in plain language, at epic start; the calling skill writes the record through
   `delegation-verify.sh render` and reads it straight back through `verify`.
2. **The Production Envelope.** A committed `## Production Envelope` section authored by the CTO: delegation URL, `Epic: #N`, Scope
   item number, the exact command(s) in a fenced block, blast radius, machine-checkable `Gate:` preconditions, verification
   commands, abort, a named rollback (at least three words, never "none" or "irreversible") and stop conditions. The executed
   command is a byte-identical full line of that block.

### Verifier decisions (V1 to V5)

These close the gaps the review found between what the earlier text said and what the code enforced.

- **V1 allowlist.** Every line of every `Command:` block, and every `--command` value, must match exactly one of
  `gh pr merge <N> [--squash|--merge|--rebase] [--auto]`, `gh pr ready <N>`, `gh workflow run <file>.yml|.yaml [-f k=v]...`,
  `gh pr create --fill [--head <branch>] [--base <branch>]`. Any character outside `[A-Za-z0-9 ._=:/@+,-]` rejects the line
  (`command-not-delegable`). The earlier denylist stays as a second layer, widened, but it is no longer the gate: a denylist over text
  a shell later re-interprets is bypassed by quoting.
- **V2 scope binding.** The cited Scope item's text must name the command's target as a whole token (the PR number and the word
  merge or ready; the workflow file name; the word revert), else `scope-mismatch`. Before this, only the item's number
  was checked.
- **V3 epic binding.** The envelope carries `Epic: #N`, which must equal the issue number of the delegation comment
  (`envelope-incomplete`, `epic-mismatch`). Any valid delegation on any open epic can no longer authorize any envelope.
- **V4 envelope read from git.** The envelope path must be relative, free of `..` and glob characters, and inside the current
  repository; its bytes are read with `GIT_LITERAL_PATHSPECS=1 git show HEAD:<path>`, never from the working tree, and the tree
  mode must be a regular file. A symlink, a glob-named untracked file or a file in another repository no longer verifies. On
  success the verifier prints `verified-envelope-sha256`.
- **V5 audit needs a time.** `--audit` requires `--at <ISO8601 UTC>` and enforces `created_at <= at <= expiry`, skipping only
  `epic-closed`. A bare `--audit` that skipped expiry as well is gone; plain `verify` enforces expiry and epic-open against now.

### What stays non-delegable

User-data loss or sole-copy destruction, money, legal exposure, brand, scope, force-push to main, bypassing required checks or
rulesets, editing the delegation, credential rotation that can lock users out, anything on third-party or tenant systems, and any
act whose rollback is not named. Under V1 most of this is not reachable at all: only four command shapes verify. Acts that
`prod-write-defer-gate.sh` recognises still defer to the harness approval prompt; a delegation does not bypass it. The Excluded
paragraph is a fixed template sentence, compared after whitespace normalisation; the earlier ten-keyword check is removed because
it only caught a malformed record, which a same-identity agent can always write well formed.

### The verifier is the single chokepoint, and its trust base

`plugins/soleur/scripts/delegation-verify.sh` holds every validity conjunct. The Technical-Ruling Gate
(`technical-ruling-gate.sh`, delegation arm), the hold evaluator (`hold-gate-eval.sh`) and the CTO's own pre-execution call all call
it; none re-implements a check. Exit 0 is valid, 1 is invalid, 2 is unverifiable and always blocks its caller. There is no seam in
the script: no flag or variable makes it answer `valid`. The trust base is outside the script: `PATH` (`gh`, `jq`, `git`, `date`),
the `gh` authentication, and the working tree the script itself is read from. A PR that edits the verifier is judged by its own edit;
CI's mutation suite is the only backstop, and the flip conditions below name pinning to `origin/main`. The format lives in one
reference, `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`, and a test instantiates its templates
and requires the verifier to accept them.

### Mechanical holds

A resume brief's holds become `Gate:` predicates that `hold-gate-eval.sh` evaluates at the ship draft exit and a second time at the
start of Phase 6.45, before the plan and spec are archived (the last point at which they are readable); any hold it cannot evaluate
STANDS. The grammar is `Gate: pr-merged <N>` and `Gate: no-inflight-run <workflow-file>` only. **`command` and `run-green` are
deferred. The first real consumer re-adds them, and only by CTO ruling.** (Ruling R1; an unknown kind makes the evaluator exit 2 and
the hold stands.) With no `Delegation:` line in the plan, the evaluator exits 3 before any other check and the legacy prose path is
unchanged. `soleur:go` routes an epic's production holds to the CTO outside the eval-gated routing block; the trigger, its hold-list
sources and its negative cases are defined in `go.md` Step 1.5, which is the authority (see the 2026-10-22 addendum below); a
message that merely says "ask the operator" is an ordinary message.

### What the ship gate checks (execution receipts)

The Technical-Ruling Gate does not and cannot prove what ran. After each delegated act the CTO itself (`cto.md` step 6) posts the
receipt and records the row `Authorized by delegation <url>, envelope <path>, ran <ISO UTC>` (class `operator
(production-mutating)`) in `decision-challenges.md`; it replaces the plan-time row for that act. Receipt enforcement fires ONLY for
rows carrying `ran`: the gate cannot know that an act happened that no row names, so a row without `ran` gets the plain strict
`verify` and no receipt check. For a row carrying `ran` the gate checks that the delegation was in force at that time
(`verify --audit --at <ran>`) and that the epic holds a **receipt**: a comment starting
`<!-- soleur-delegated-act v1 delegation=<url> envelope=<path> sha256=<verified-envelope-sha256> result=ok|rolled-back run=<url|none> -->`
followed by a plain sentence. The exact rules, which are the gate's contract:

- every field matches exactly: the delegation URL and the envelope string equal the row's, `sha256` equals the verifier's
  `verified-envelope-sha256`, and `result` is `ok` or `rolled-back`;
- the receipt was created inside the delegation's life (not before the delegation, not after the end of its expiry day), is not in
  the future, and was created after the `ran` instant it vouches for;
- it was never edited (`updated_at` equals `created_at`) and was posted by a person (`user.type` is `User`), not a bot or App;
- its `author_association` is OWNER, MEMBER or COLLABORATOR; a missing association is a mismatch;
- each receipt satisfies at most one row, so three rows cannot share one receipt;
- a `ran` time in the future is `delegation-invalid`.

A missing, mismatched or unreadable receipt exits 2 (`receipt-missing`, `receipt-mismatch`, `receipt-unreadable`). So the gate
establishes that a receipt exists, is attributable to a repository participant, sits in the right window and matches the envelope;
it does not establish that the recorded command is the command that ran, because the CTO writes the receipt. The calling skill also
states each delegated act in-session and lists delegated acts in the run summary, so the operator can see them.

### CTO interfaces

`cto.md` gains a Rule interface and an Own-the-epic interface behind a prompt-keyed selector with its frontmatter description
unchanged, so no agent mirror regenerates.

### Rulings recorded in this round

Ruled by CTO agent, 2026-10-15:

- **R1.** Defer `Gate: command` and `Gate: run-green` (code, tests and grammar removed). The evaluator then runs no repository
  script, which restores AP-024 for it. Flip: the first real consumer re-adds them, by CTO ruling only.
- **R2.** Remove the delegation arm from `pre-ask-technical-fork-gate.sh`; the hook and its suite are restored to their
  `origin/main` versions, and the hook-side GitHub edge leaves the C4 model. The arm denied only a question `cto.md` already forbids
  asking, and the deny text read as a grant of execution. Flip: re-add the arm only after an observed instance of an agent asking
  a question a live delegation covers.
- **R3.** Enforce execution receipts in the gate as described above. #10361 is the stronger follow-up.
- **R4.** Keep `pr-overlap-preflight.sh` in this PR, hardened, as the separate section below.

### Accepted residuals

Each is a statement of what this design does not prevent.

- **Shared gh identity.** The delegation is posted through the same `gh` identity as the agent. The `Confirmation:` line, the
  40-byte quote, the 30-day cap and edit-as-revocation are tamper-evidence and an audit trail, NOT prevention: a same-identity
  agent can still render and post a record, delete and re-create a comment (which resets the "never edited" check), or author the
  envelope. The verifier cannot tell who typed a comment, only which account posted it.
- **The envelope is not pinned to `origin/main`.** V4 reads the committed HEAD blob, but HEAD may be an unpushed local commit that
  no one reviewed, and the CTO authors it. Flip: require the envelope blob to equal `origin/main` once one delegated act has run (so
  an envelope needs a merged PR first), or when #10361 lands, whichever comes first.
- **Verifier trust base.** `PATH`, the `gh` authentication and the working-tree copy of the scripts (verifier, gate and hold
  evaluator, all read from the branch under review) are trusted (see above). Flip: refuse at ship when a PR that touches one of
  these scripts also carries a delegation row, or run them from `origin/main`.
- **The receipt is authored by the CTO.** It is evidence of a claim, not proof of execution.
- **`ran` is self-asserted, now bound to a receipt window.** The act time in a row is written by the same agent that did the act. It
  is no longer free: the delegation must have been in force at that time, the receipt must exist inside the delegation's life and
  not in the future, and a receipt cannot be reused across rows. A row that omits `ran` skips the receipt check altogether.
- **A hold discharges when its condition is true, whoever the hold is reserved to.** The evaluator checks facts (`pr-merged`,
  `no-inflight-run`); it cannot read that a hold was worded as the operator's decision. The mitigation is the `Operator-reserved:`
  grammar: a hold whose words begin with it always stands, and the evaluator exits 2 and does not probe its gates. The old
  allowance, that the CTO could clear a hold on the operator's spoken say-so, is not a delegable path: `operator-holds.md` section 1
  still says an `Operator-reserved:` hold is cleared only by the operator saying so, after which the CTO removes or rewrites the line.
  That removal is an agent edit on a conversational claim, so it is covered by the same shared-identity residual as the record
  itself. A hold not marked so, an unusual spelling of the prefix, and a gate that does not mention the hold's target remain the
  CTO's authoring and review's check.
- **The second look precedes the archive commit, not the arming.** The pre-arming check (hold re-evaluation, overlap preflight,
  vehicle lookup) runs at the start of Phase 6.45, because afterwards the plan and the decision challenges are archived and no
  longer readable at their live paths. "Immediately before arming" is therefore not literally true: the archive commit, the CI wait
  and the queue lie between. `no-inflight-run` is true only at an instant, so a run that starts and ends inside that gap is not seen.
  Closing it needs the archived paths. Envelopes must not live in the directories ship archives (`knowledge-base/project/specs`,
  `plans`, `brainstorms`): an archived envelope path no longer exists at HEAD, and its whole-file fingerprint moves with every edit
  of that file. A vehicle row written at Phase 6.45 reaches the PR body through the normal body update.
- **Text in the envelope other than the `Command:` block is vetted by a denylist, not an allowlist.** `Verification:`, `Abort:`,
  `Stop conditions:` and `Rollback:` are checked against the denylist (Rollback also against the command grammar for its backticked
  spans), because the CTO runs them. Plain prose in those parts is read by the CTO and is not parsed. Known limits: a denylist is dodged by a wrapper or prefix word
  (`timeout 5 kubectl ...`); comment markers inside a code fence can hide a line from the check; hidden-text constructs other than
  HTML comments are counted as live scope; scope negation is a word list, so phrasings such as "unless" or "avoid" are not seen;
  a Rollback span is not bound to the cited Scope item; and two PR numbers in one Scope item both count as covered.
- **A same-identity author can always forge a record** (the first residual). The review panel's verification pass found no P1: every
  finding that remains either fails closed or is listed here.
- **`updated_at` and reactions.** The verifier treats any `updated_at` different from `created_at` as edited (the strict reading;
  it fails closed). Whether a reaction moves `updated_at` was not probed with a write. As an observation only, not proof for this
  repository: a read-only look at `cli/cli` found 8 of 8 reacted comments with `updated_at` equal to `created_at`. If a reaction
  does move it here, a legitimate record is read as `edited` and the epic stalls with a plain re-record message.
- **A dispatched workflow is trusted by name.** The allowlist binds the workflow file and its inputs; what the workflow does is
  bounded by the envelope's blast radius and rollback and by the Excluded list, not by the verifier.
- **Revocation stops the next act.** Deleting the comment makes the next `verify` fail; it does not recall an auto-merge already
  armed or a run already dispatched. This ADR does not rely on the stop path to disarm them.
- **A gate may encode a hold unfaithfully.** The operator's wording stays beside the `Gate:` lines so a weakened gate is visible in
  review; whether a gate faithfully encodes a hold remains the CTO's authoring and review's check.

### What would flip the identity ruling

An App identity usable for local-session comment writes, one observed self-authorization, or a hook-written receipt of the
operator's answer to the confirmation question that the comment must cite (#10361, the cheapest strict route).

## Consequences

**Easier.** A non-technical operator is asked once, in plain language, and never a technical question; the CTO completes the epic
inside a recorded envelope. Revoking, expiring, closing the epic or editing the comment stops the autonomy with no code change.
Every state the machinery cannot evaluate leaves the old behaviour (hold stands, gate fails). A session with no recorded delegation
behaves exactly as before, including a plan whose `## Operator Holds` section is free prose.

**Harder.** One more authorization path to keep honest: three callers depend on the verifier, so a change to it is a change to all
three and needs the full mutation suite. The unedited check is strict and may stall an epic on a benign `updated_at` movement.
The live canonical delegation on #9757 predates `Confirmation:` and verifies `invalid`; it is re-recorded at first use, an
operator-confirmed act outside this PR.

**Amends.** ADR-084's closed operator-only list: its production-mutating category is now satisfiable by delegation plus envelope. An
`Amended by ADR-289` pointer is appended to ADR-084. `hr-technical-fork-is-not-an-operator-question` is left byte-unchanged
because it says "category". The `hr-menu-option-ack-not-prod-write-auth` body gained the second path (a delegation the verifier
reports valid) in place of a prose description of one, with its manifest hash regenerated and an append-only ack row that asks for
human review by @deruelle and records the dispatch widening.

**Verified by.** `plugins/soleur/scripts/delegation-verify.test.sh` pins the typo-guard rejection: the dispatch
`apply-web-platform-infra.yml -f apply_target=registry-host-replace` still verifies as valid inside a Scope item that names the
file, the same line plus `-f confirm=...` or `-f rollback_ack_luks_writes=...` (and the `-F`, `--field`, `--raw-field`, glued and
`=` spellings) is refused with `non-delegable-command`, and mutants that delete or narrow the pattern are killed.

**Follow-ups tracked as issues.** The `soleur:production-change` skill (envelope pre-flight, merge, watch, verify, rollback),
a delegated-act digest for the operator digest, and the receipt hook (#10361).

## Cost Impacts

None. The verifier makes read-only `gh api` calls; no new vendor, subscription or recurring cost. Each call is bounded by `timeout`
or `gtimeout` where one exists; a host with neither is reported `unverifiable reason=tool-missing` rather than run uncapped, so no
cap is promised beyond that.

## NFR Impacts

None against a tracked NFR. The change adds no runtime service; it touches plugin scripts and documentation.

## Principle Alignment

- AP-004 (Agent-native parity): Aligned. An agent can complete an epic a human could, under a recorded human decision.
- AP-007 (Exhaust automation before manual steps): Aligned. Operator steps shrink to one confirmation per epic.
- AP-011 (ADRs for architecture decisions): Aligned. This is the record.
- AP-020 (Untrusted input at the agent boundary): Aligned by removal. The delegation arm of the ask hook is REMOVED (ruling R2), so
  nothing in this change lets the model-controlled tool-call envelope produce a grant. Flip: re-add the arm only after an observed
  instance of an agent asking a question a live delegation covers.
- AP-024 (A verification surface does not actuate): Aligned. The verifier reads and reports. The hold evaluator now runs no
  repository script, because `Gate: command` and `Gate: run-green` are deferred (ruling R1); its only write is a `git fetch` of the
  default branch (local ref state) for `pr-merged`. Flip: the first real consumer re-adds them, by CTO ruling only.

## Separable section: PR overlap preflight

`plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh` is not part of the authorization decision above and is recorded
separately (ruling R4: kept in this PR, in its own commit range, which the PR body names so it can be split if review load
requires). It is read-only. It stops a merge only for a duplicate or a CTO-designated vehicle, and only on the strength of an
open PR by an OWNER, MEMBER or COLLABORATOR; shared files alone, or any other author, are informational. It adds a second
advisory step in the merge path that fails open on an unreadable list (exit 2 continues with a visible notice), which is why
it carries its own deadline and disclosure and why nothing in the authorization path depends on it.

## Diagram

The C4 model shows the CTO component and one read-only edge to GitHub from the plugin side (verifier, hold evaluator, ship gate's
receipt read of the epic's comments, overlap preflight; authenticated per-user reads of the user's own repository). There is no hook-side edge: the delegation arm was removed
(R2). See `knowledge-base/engineering/architecture/diagrams/model.c4`.

## Addendum 2026-10-22 (#10783)

The hold-list source of the `soleur:go` trigger widened from the brief alone to any of: the brief, the body of an open epic (read
only when its `author_association` is OWNER, MEMBER or COLLABORATOR), or the `## Operator Holds` section of a plan the brief or
epic names. `go.md` Step 1.5 is the authority for the trigger. The trigger only routes; it never discharges a hold. Its author
check is weaker than the delegation's admin-author rule and grants no authority: every production act still needs a valid
recorded Standing Delegation, verified by `delegation-verify.sh`, or an in-session per-command go (the runbook's Production
Envelope for the Inngest TLS acts records which acts are envelope-delegable and which are in-session go only).

## Addendum 2026-10-29 (#9927)

The `soleur:go` trigger gained a classification-only form: a label plus open items (owner-side, blocked or waiting) that belongs
to an open epic the brief cites, found in the brief or in an owner-authored epic body, routes to the CTO to be classified, not to
a delegation. `go.md` Step 1.5 stays the authority for the trigger and is not restated here. The route uses the existing Rule
interface (a prompt that never starts `Own the epic`) and discharges nothing: it records no delegation, calls no `render` and
leaves every hold standing. A list in which nothing is delegable raises no epic-start question and files no `Standing-delegation`
issue. The author check is on the issue creator, not the last editor; this is inherited from the 2026-10-22 widening and is closed
by one snapshot that is never re-read, by passing the items as untrusted data, and by epic text only ever moving an item toward
the operator.
