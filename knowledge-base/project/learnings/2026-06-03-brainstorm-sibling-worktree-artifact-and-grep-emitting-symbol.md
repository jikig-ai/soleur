# Learning: during brainstorm premise probes, check sibling worktrees for "missing" artifacts, and verify "signal X exists" by grepping the emitting symbol

## Problem

Two premise-verification misses surfaced during the #4849 chat-write-absence-alert
brainstorm — both produced a *transiently wrong* framing that later evidence corrected:

1. **"Cited artifact missing on main."** The pre-worktree premise probe ran
   `git show main:knowledge-base/engineering/ops/post-mortems/chat-rls-workspace-id-outage-postmortem.md`
   and got nothing, so the source PIR (the document the issue's "factor 2" follow-up
   is derived from) looked absent. The existing brainstorm guidance covers the
   bare-repo-lag case ("if `git show` fails, defer until inside the worktree and
   re-grep") but not this case: the doc genuinely was **not on `main`** — it was
   live on a **sibling worktree** (`feat-ui-visual-qa-gate`), authored by the same
   incident response, not yet merged. A `main`-only existence check is a
   false-negative whenever the cited artifact is in-flight on another branch.

2. **"Sentry signal does not exist."** A domain leader (CTO) grepped the literal
   prose string `Failed to save user message` to test whether the issue's "Option B"
   (alert on that op) was viable, found it only as the thrown `Error.message`
   (`cc-dispatcher.ts:1505`), and concluded the op didn't exist → "Option B not
   viable." The *alertable* identifier is the op **slug** `persist-user-message`
   (`CC_OP_SLUGS.persistUserMessage`, `cc-dispatcher.ts:1502`), emitted via
   `reportSilentFallback` with a `pg_code` tag. The signal exists; the prose-string
   grep missed it. This nearly inverted the recommended approach.

## Solution

1. **"Missing on main" ⇒ check sibling worktrees before recording a gap.** When a
   cited artifact (PIR, ADR, prior brainstorm, spec) is absent at `git show main:<path>`,
   run `git worktree list` and `git show <branch>:<path>` (or read
   `.worktrees/<sib>/<path>` read-only) for each active sibling before concluding it
   doesn't exist. In-flight docs commonly lag the prevention follow-up that
   references them — the PIR-and-its-follow-up-issue pair is the canonical instance.

2. **"Signal X exists" ⇒ grep the emitting symbol, not the prose.** To verify a
   log/metric/Sentry signal is present, grep the **constant/slug/tag that names it
   at the emit site** (`CC_OP_SLUGS.*`, the `op:` value, the tag key), not the
   human-readable message a user would read. A thrown `Error.message` and the
   queryable `op`/tag are different surfaces; a prose grep tests the wrong one. This
   is the emit-side mirror of the existing brainstorm rule "verify *is-X-wired* by
   grepping the specific consuming symbol."

## Key Insight

A `main`-only or prose-string check answers a *narrower* question than the one the
brainstorm is actually asking. "Does this artifact exist?" really means "exists
anywhere reachable, including unmerged sibling branches." "Does this signal exist?"
really means "is it emitted under a queryable identifier," which is the slug/tag at
the emit site — never the human-readable message. Both misses share a shape:
**the verification queried the wrong surface, and a faster, narrower tool returned a
confident false negative.** Widen the surface to match the question before letting a
negative bound the option space.

## Session Errors

1. **Cited PIR appeared missing on `main`.** Recovery: found it on sibling worktree
   `feat-ui-visual-qa-gate` and read it there. **Prevention:** check sibling
   worktrees (`git worktree list` + `git show <branch>:<path>`) before recording a
   cited artifact as a gap (this learning; candidate brainstorm Sharp-Edge bullet).
2. **CTO false-negative "op `Failed to save user message` doesn't exist."** Recovery:
   repo-research grepped `CC_OP_SLUGS.persistUserMessage` and confirmed
   `op:persist-user-message` is emitted. **Prevention:** verify "signal exists" by
   grepping the emitting slug/tag, not the prose message (this learning; mirrors the
   existing consuming-symbol rule).
3. **Spec write blocked by the IaC-routing PreToolUse hook** (infra-language
   pattern match). Recovery: added an `## Infrastructure (IaC)` section + an
   `iac-routing-ack` comment — the work is genuinely 100% Terraform
   (`sentry_issue_alert` via `apply-sentry-infra.yml`), no manual step.
   **Prevention:** none needed — the hook fired correctly; the fix is to make the
   IaC routing explicit in the spec, which the gate is designed to elicit. Already
   hook-enforced.

## Tags
category: integration-issues
module: brainstorm / premise-verification
issues: 4849
related_learnings:
  - knowledge-base/project/learnings/2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md
  - knowledge-base/project/learnings/2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md
