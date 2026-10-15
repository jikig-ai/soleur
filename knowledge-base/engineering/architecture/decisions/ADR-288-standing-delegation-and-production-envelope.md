---
title: Production-mutating authorization is satisfiable by a verified Standing Delegation plus a CTO Production Envelope
status: adopting
date: 2026-10-15
supersedes: none
issue: 10333
related: [10333, 9757, 10348]
related_adrs: [ADR-084, ADR-083, ADR-277]
tags: [authorization, delegation, hooks, cto, production, non-technical-operator]
brand_survival_threshold: single-user incident
---

# ADR-288: Production-mutating authorization is satisfiable by a verified Standing Delegation plus a CTO Production Envelope

## Status

**Adopting.** The mechanism ships in PR #10348. The status moves to `accepted` after the first real delegated act has run end to end
under it (the epic #9757); that flip is mechanical and is not a deferral. The ordinal was verified free against `origin/main` and
every `origin/*` branch ref (highest ADR-287) and is re-verified at ship. This ADR extends ADR-084 and does not supersede it.

## Context

Hard rule `hr-menu-option-ack-not-prod-write-auth` and ADR-084's closed operator-only list made every production-mutating act
(merging a change to the live product, dispatching a deploy workflow, a revert) a per-command go-ahead from the operator. Soleur's
users are not technical: they cannot judge a command, so the per-command question either stalls the epic or gets answered by
reflex, which is the failure the rule exists to prevent. A resume brief's own `HOLDS` list had the same defect; it was treated as the
operator's even when each hold was a checkable fact.

On 2026-10-15 the founder ruled (quoted exactly in the compound learning): the CTO should own the decision and proceed
autonomously to complete the arc or epic, and the workflow and skills should be improved to that effect because users are not
technical. The design question was how to satisfy that without removing the one control that guards single-user incidents: one
unauthorized merge or workflow dispatch on a user's repository ends trust in "the CTO owns it".

## Considered Options

- **Option A: keep the per-command operator go-ahead only.** Pros: zero new surface. Cons: a non-technical operator cannot judge a
  command, so every epic stalls on a question they cannot answer. Rejected.
- **Option B: a pinned local copy of the delegation.** Pros: no network in the hook. Cons: a copy cannot see revocation, expiry or
  an edit, and could deny a question when no valid delegation exists. Rejected (CTO ruling T1).
- **Option C: trust an act-class label written by the CTO.** Pros: simple. Cons: the same agent would attest its own authority.
  Rejected (T3): the executed command must be a byte-identical full line of a committed envelope the delegation's Scope covers.
- **Option D: a dedicated `epic-driver` or `production-change` skill now.** Pros: one named runner. Cons: the epic-driver is
  covered by the CTO agent's "Own the epic" interface; the production-change runner has no consumer until the first delegated act
  has run. Epic-driver rejected, production-change deferred to a follow-up issue (T8).
- **Option E: a PreToolUse hook that enforces byte-identical execution.** Pros: execution, not the question, becomes the
  authorization point. Cons: `prod-write-defer-gate.sh` and `guardrails.sh` are ruled unchanged, and a new hook adds a surface this
  slice cannot test. Rejected for now; the residual is stated below and the receipt-checking hook is a tracked follow-up.
- **Option F: a `delegated-exec.sh` wrapper that verifies and runs in one step.** Pros: verification and execution cannot be
  separated. Cons: it hides the inner command from the unchanged text-matching guards (`prod-write-defer-gate.sh`,
  `guardrails.sh`) and is itself an execution surface. Rejected (CTO ruling C1); the same objection rules out any execution proxy.
- **Option G: a GitHub App identity or web-UI posting for the delegation comment.** Pros: author differs from the agent's identity.
  Cons: no App identity exists for local-session comment writes, and posting through the web UI conflicts with the
  non-technical-user constraint. Rejected (CTO ruling C2); revisited under the flip conditions below.
- **Option H (chosen): a two-key model.** A recorded Standing Delegation plus a CTO-authored Production Envelope, checked by one
  shared verifier.

## Decision

**Option H.** Production-mutating stays on the operator-only list as a CATEGORY. It becomes satisfiable by two keys held together:

1. **Key one, the Standing Delegation.** An issue comment on the epic: line 1 exactly `<!-- soleur-delegation v1 -->`, authored by a
   real user (not a bot) who is the repository owner or holds `admin` permission, with a verbatim operator quote of at least 40
   characters, a `Confirmation:` line carrying the operator's answer, numbered Scope items, a complete Excluded list, and an expiry
   no later than 30 days after creation. The epic closing also ends it. Revocation is deleting or editing the comment. The
   operator gives it once, in plain language, at epic start; the calling skill writes the record through
   `delegation-verify.sh render` and reads it straight back through `verify`.
2. **Key two, the Production Envelope.** A committed `## Production Envelope` section authored by the CTO: delegation URL, Scope
   item number, the exact command in a fenced block, blast radius, machine-checkable `Gate:` preconditions, verification
   commands, abort, a named rollback and stop conditions. The executed command is a byte-identical full line of that block.

**What stays non-delegable.** User-data loss or sole-copy destruction, money, legal exposure, brand, scope, force-push to main,
bypassing required checks or rulesets, editing the delegation, credential rotation that can lock users out, anything on third-party
or tenant systems, and any act whose rollback is not named. A closed text denylist backs the list in the verifier
(`non-delegable-command`): `git push`, `--admin`, rulesets or branch-protection writes, secret-store set or delete, `terraform` or
`tofu` apply, destroy and import, `rm -r`, `gh repo delete`, `gh secret`. Acts that `prod-write-defer-gate.sh` recognises still
defer to the harness approval prompt; a delegation does not bypass it.

**The verifier is the single chokepoint.** `plugins/soleur/scripts/delegation-verify.sh` holds every validity conjunct. The
Technical-Ruling Gate (`technical-ruling-gate.sh`, delegation arm), the ask hook (`pre-ask-technical-fork-gate.sh`, delegation
arm), the hold evaluator (`hold-gate-eval.sh`) and the CTO's own pre-execution call all call it; none re-implements a check. Exit
0 is valid, 1 is invalid, 2 is unverifiable and always blocks its caller (the hook alone treats 2 as "ask the question"). There is
no test seam in production code: nothing in the environment can make it answer `valid`. The format lives in one reference,
`plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`, and a test instantiates its templates and requires
the verifier to accept them.

**Mechanical holds.** A resume brief's holds become `Gate:` predicates (`pr-merged`, `no-inflight-run`, `run-green`, `command`) that
`hold-gate-eval.sh` evaluates at ship Phase 6; any hold it cannot evaluate STANDS. `soleur:go` routes a brief carrying the tokens
`HOLDS` or "ask the operator" to the CTO, outside the eval-gated routing block. `pr-overlap-preflight.sh` stops a merge only for a
duplicate or a CTO-designated vehicle; shared files alone are informational.

**CTO interfaces.** `cto.md` gains a Rule interface and an Own-the-epic interface behind a prompt-keyed selector with
its frontmatter description unchanged, so no agent mirror regenerates.

### Accepted residuals

Each is a statement of what this design does not prevent.

- **Shared gh identity.** The delegation is posted through the same `gh` identity as the agent. The `Confirmation:` line, the
  40-character quote, the 30-day cap and edit-as-revocation are tamper-evidence and an audit trail, NOT prevention: a same-identity
  agent can still forge a record. The verifier cannot tell who typed a comment, only which account posted it.
- **The unedited check is observed, not proven.** The verifier treats any `updated_at` different from `created_at` as edited (the
  strict reading). The planned throwaway-comment probe that would record how GitHub moves `updated_at` for a reaction was NOT run,
  because it needs a GitHub write this slice did not make. GitHub's observed behaviour for reactions is therefore UNVERIFIED. If a
  reaction moves `updated_at`, the strict reading turns a legitimate record into `edited` and the epic stalls with a plain
  re-record message; it fails closed, never open. The live fact pinned at plan time is only that a never-touched comment has equal
  stamps.
- **Byte-identical execution depends on the CTO.** The verifier prints `verified-command:` and `verified-sha256:`; the CTO runs that
  line. Nothing at execution time re-checks it; the ship gate row audits it afterwards. A receipt-checking PreToolUse hook that keeps
  the guards seeing the real command text is the stricter direction (follow-up issue).
- **The hook arm is repo-local.** Soleur users elsewhere get the verifier, the gate and the hold evaluator, not the deny backstop.
- **A gate may encode a hold unfaithfully.** The operator's wording stays beside the `Gate:` lines so a weakened gate is visible in
  review; whether a gate faithfully encodes a hold remains the CTO's authoring and review's check.

### What would flip the identity ruling

An App identity usable for local-session comment writes, one observed self-authorization, or a hook-written receipt of the
operator's answer to the confirmation question that the comment must cite (the cheapest strict route).

## Consequences

**Easier.** A non-technical operator is asked once, in plain language, and never a technical question; the CTO completes the epic
inside a recorded envelope. Revoking, expiring, closing the epic or editing the comment stops the autonomy with no code change.
Every state the machinery cannot evaluate leaves the old behaviour (hold stands, question is asked, gate fails). A session with no
recorded delegation behaves exactly as before.

**Harder.** One more authorization path to keep honest: four callers depend on the verifier, so a change to it is a change to all
four and needs the full mutation suite. The unedited check is strict and may stall an epic on a benign `updated_at` movement.
The live canonical delegation on #9757 predates `Confirmation:` and verifies `invalid`; it is re-recorded at first use, an
operator-confirmed act outside this PR.

**Amends.** ADR-084's closed operator-only list: its production-mutating category is now satisfiable by delegation plus envelope. An
`Amended by ADR-288` pointer is appended to ADR-084. `hr-technical-fork-is-not-an-operator-question` is left byte-unchanged
because it says "category". The `hr-menu-option-ack-not-prod-write-auth` body gained the second path, with its manifest hash
regenerated and an append-only ack row.

**Follow-ups tracked as issues.** The `soleur:production-change` skill (envelope pre-flight, merge, watch, verify, rollback),
a delegated-act digest for the operator digest, and the receipt-checking hook.

## Cost Impacts

None. The verifier makes read-only `gh api` calls capped at 5 seconds each; no new vendor, subscription or recurring cost.

## NFR Impacts

None against a tracked NFR. The change adds no runtime service; it touches plugin scripts, a repo-local hook and documentation.

## Principle Alignment

- AP-004 (Agent-native parity): Aligned. An agent can complete an epic a human could, under a recorded human decision.
- AP-007 (Exhaust automation before manual steps): Aligned. Operator steps shrink to one confirmation per epic.
- AP-011 (ADRs for architecture decisions): Aligned. This is the record.
- AP-020 (Untrusted input at the agent boundary): Aligned. The tool-call envelope the hook receives is model-controlled, so the
  hook only denies a question and allows on any failure; it never grants anything.
- AP-024 (A verification surface does not actuate): Aligned. The verifier and hold evaluator only read and report.

## Diagram

The C4 model shows the CTO component and two read-only edges to GitHub: the plugin side (verifier, hold evaluator, overlap
preflight) and the hook side (delegation deny arm, 5 second cap, any failure allows the question). See
`knowledge-base/engineering/architecture/diagrams/model.c4`.
