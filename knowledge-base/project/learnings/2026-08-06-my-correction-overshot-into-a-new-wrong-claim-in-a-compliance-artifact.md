---
date: 2026-08-06
problem_type: logic_error
component: workflow
severity: high
symptoms:
  - "A correction to a legal-citation claim replaced one wrong article with another"
  - "A runbook prescribed a gh command the repo's own PreToolUse hook denies"
  - "A parallel session overwrote a branch-derived spec.md and every local signal stayed green"
root_cause: unverified_replacement_claim
tags: [gdpr, compliance, runbook, worktree, parallel-sessions, acceptance-criteria]
issue: 7329
---

# A correction overshot into a new wrong claim — in the artifact least able to carry one

## Problem

Recording the start of active alpha onboarding (#7329) produced three defects that a green
suite, a clean `git status`, and an eleven-criterion acceptance pass all failed to surface.

## 1. The correction was more wrong than the thing it corrected

I framed a GDPR notice obligation as something to hand the tester in person. The operator pushed
back — correctly, and on the merits: *"It's supposed to be a SaaS product and I never saw a SaaS
product asking users to sign Art 14. in person, it's not scalable either."*

I corrected, and overshot. I asserted **"Art. 13 governs, not Art. 14"** for the beta-CRM record.
That is wrong. Three sources in this repo say so, and they agree:

- the beta-CRM LIA scopes Art. 14 to data *"not obtained from the data subject via a form they
  submitted"* — which covers operator-authored conversation notes **even for a tester who holds a
  platform account**;
- `model.c4:22-24` models the `betaContact` actor as *"An involuntary data subject (Art. 14)"*;
- Art. 30 **PA-30** records the same basis.

Art. 13 governs the **separate** dataset of platform-account data collected at `accept-terms`.

**Why it was easy to miss:** the operator's practical conclusion — nothing signed, nothing in
person — was right under *both* framings. The actionable half of my correction was correct, so
the article swap rode along unexamined. The LIA's own mechanism is *"a short standard notice line
the operator can paste into a first-contact message"*, which is exactly as scalable as the
operator said it should be.

**The general shape: a correction inherits none of the original claim's scrutiny.** The original
framing got challenged. The replacement got adopted. Nothing in between re-derived it.

**Prevention:** when correcting a legal or citation claim, verify the *replacement* against every
source that carries it — here the LIA, the C4 model, and the Art. 30 register — before asserting
it. Cheapest gate: `grep` the register and the model for the subject, not the article number.

## 2. A prescribed recovery lever that cannot clear the thing it is prescribed for

The new per-tester runbook's 2-week-checkpoint step prescribed:

```bash
gh issue create --title "..." --label follow-through --milestone "..." --body "..."
```

`.claude/hooks/follow-through-directive-gate.sh` **denies** exactly that command unless the body
carries a `<!-- soleur:followthrough script=… earliest=… -->` directive plus an exit-code probe.
The runbook would have handed an operator a command blocked on first use.

The label was also semantically wrong, which is the more interesting half. The follow-through
sweeper **auto-closes** an issue when its probe passes. A 2-week interview checkpoint becomes
**due** at 14 days rather than satisfied — auto-closing it would fire precisely when the work
starts. And the work is a conversation, which has no exit-code probe.

Same family as the documented `npm run -w` precedent: a documented invocation that errors the
first time anyone runs it.

**Prevention:** grep `.claude/hooks/` for every command a runbook prescribes. Then ask a second
question the grep cannot answer — do the label's **automation semantics** match the work?
(auto-close-on-probe vs becomes-due).

**RECURRENCE, 2026-08-20 (#7586) — the lever was permitted, exited 0, and was still inert.**
The `apply-web-platform-infra` failure email named exactly one recovery action for a heartbeat
monitor left live-and-unfed: `gh workflow run apply-web-platform-infra.yml -f
apply_target=manual-rerun`. Nothing denies that command. It runs, it succeeds — and it does
nothing, because on the next run the arming function's op/state gate no-ops any monitor whose
status is not `paused`, and a live-and-unfed monitor is precisely *not* `paused`. The lever was
**provably inert for the one condition the email flagged as urgent.**

That is the half a hook-grep structurally cannot see: the command is allowed, and the defect is
in the *precondition of the thing it invokes*. So the check generalizes —

> **Execute the prescribed lever against the exact state the message flags.** Not against a
> healthy state, and not merely "is this command permitted". A lever can be permitted, exit 0,
> and change nothing. When the message calls an item urgent, the fix is to read the invoked
> code's own guard clause and assert the prescribed action's premise against it; the email's
> branches now name Better Stack → Pause, and the `failure` arm says outright that a re-run will
> not clear it. See
> [the channel was silent on the path it was built for](./2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md) §6.

## 3. Two sessions on one branch silently overwrite every branch-derived path

Full detail in **#7334**. Compressed:

Session leases stop `cleanup-merged` from **reaping** an active worktree. Nothing stops a second
session from **entering** one and committing to its branch. Because `specs/feat-<branch>/spec.md`
is branch-derived, the second writer wins — and the first session's acceptance criteria quietly
begin describing a different document. Here, AC13 (*"the spec states Art. 14"*) went from 4
matches to 0 without anything failing.

**Every local signal stayed green.** `git status` was clean, because the other session *committed*
rather than leaving dirt. The commits were ordinary descendants, so nothing read as divergence.
The full suite passed, because both features are documentation. The only tell was a linter
system-note that `spec.md` had changed — which reads like a formatting touch.

**Prevention:** an assertion that `specs/feat-<branch>/spec.md`'s frontmatter agrees with the
current branch would have fired the instant the second spec landed. Candidates in #7334.

## 4. Two acceptance criteria that asserted the wrong predicate (one class)

- **AC6** asserted the *absence* of "in person" substrings. But both artifacts deliberately carry
  the **denial** of in-person delivery — that denial is the operator-facing point. An absence-grep
  cannot distinguish an assertion from a negation, and satisfying it literally would have meant
  deleting the sentences that make the posture unambiguous. Amended to require every match *be* a
  negation.
- **AC10** grepped the diff for CRM write verbs and matched **its own verification command**,
  quoted in the plan file.

Both are the documented *anchor on what is actually asserted, not a bare token* class — recurring
here on prose rather than code. The prose direction is worse in one way: documenting a rule and
asserting it collide, because the documentation becomes false-match surface for the assertion.

## Key Insight

Three of these four are the same failure with different subjects: **a claim was adopted without
being re-derived**. The replacement article, the prescribed command, the acceptance predicate —
each was plausible, each was written by someone (me) who had just been thinking carefully about
the adjacent thing, and each was wrong in a direction that reads as diligence.

The fourth is different and worth separating: the parallel-session collision is not a reasoning
error at all. It is a case where every available signal was green and the defect was structural.

## Session Errors

1. **GDPR article overcorrection** — asserted Art. 13 governs the beta-CRM record; Art. 14 does.
   *Recovery:* corrected at source (spec + brainstorm) before it reached the validation record or
   runbook. **Prevention:** verify a replacement citation against the LIA, the C4 model, and the
   Art. 30 register before asserting it.
2. **Runbook prescribed a hook-denied command** (`--label follow-through` with no directive).
   *Recovery:* fixed inline at review. **Prevention:** grep `.claude/hooks/` for every prescribed
   command, and check the label's automation semantics against the work.
3. **Roadmap table row gained a third cell** in a two-column table; GFM discards the overflow
   silently. *Recovery:* caught immediately by a pipe-count check
   (`awk '{n=gsub(/\|/,"|"); print n}'`). **Prevention:** run the pipe-count check after any
   table-row edit — already documented; applying it is what caught this.
4. **Parallel session overwrote `spec.md`** on the shared branch. *Recovery:* preserved the other
   session's three commits on `feat-kb-blueprint-manifest`, reset this branch, force-pushed.
   **Prevention:** #7334 — assert branch-vs-spec-frontmatter agreement.
5. **AC6 predicate could not distinguish assertion from negation.** *Recovery:* amended the AC
   explicitly rather than quietly satisfying a looser reading. **Prevention:** for negative-space
   ACs over prose, assert the negation form, not substring absence.
6. **AC10 matched its own verification command** quoted in the plan. *Recovery:* re-scoped the
   grep to exclude planning artifacts. **Prevention:** exclude the artifacts that quote a check
   from that check's own scope.
7. **Full suite launched against a tree that then changed under it** (consequence of #4).
   *Recovery:* killed the run, relaunched detached against the clean tree. **Prevention:** the
   "do not edit under the exit gate" rule already exists; it assumes a single writer. See #7334.

## Related

- Issue #7334 — a second session can enter a leased worktree and overwrite the first's spec
- Issue #7331 — alpha-tester terms + controller/processor posture for tester-owned repo data
- `knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md`
- `knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md`
- `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md`
- `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`
