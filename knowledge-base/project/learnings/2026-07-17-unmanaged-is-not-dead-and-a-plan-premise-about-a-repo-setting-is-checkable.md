---
date: 2026-07-17
issue: 6589
pr: 6582
tags: [terraform, iac, plan-quality, premises, github, squash]
category: workflow-patterns
---

# "Unmanaged" is not "dead", and a plan premise about a repo setting is checkable in one command

Two premise failures from the same plan (#6589 v2, *after* a 7-agent review panel). Both
were stated as fact, both were load-bearing, and both were falsifiable in under a minute.
They fail in opposite directions, which is the useful part: one would have caused an
incident, the other would have shipped a gate that trains the exact blindness the plan
elsewhere refuses to train.

---

## 1. "Not in Terraform" ⇒ "dead" — the inference that nearly deleted prod monitoring

**The plan said (Phase 5c):** delete Sentry uptime monitor `1422253`, $1.00/mo. Reasoning
quoted verbatim:

> State has 4 uptime, `.tf` has 4, **live has 5**: never Terraform-managed, so Terraform
> cannot destroy it. **Executor:** a one-line `curl -X DELETE`.

**What one live read showed:**

| monitor | url | interval | managed |
|---|---|---:|---|
| `soleur-ai-apex` | `https://soleur.ai/` | 300s | ✅ |
| `soleur-ai-www` | `https://www.soleur.ai/` | 300s | ✅ |
| `soleur-ai-changelog-deep` | `https://soleur.ai/changelog/` | 600s | ✅ |
| `soleur-ai-acme-carveout-probe` | `https://soleur.ai/.well-known/…` | 300s | ✅ |
| **`1422253`** | **`https://app.soleur.ai`** | **60s** | ❌ |

Every managed uptime monitor watches the **marketing site**. The one marked for deletion is
the only one watching the **production application**, at the tightest cadence of the five,
`status=active`.

**The inference is invalid.** *Unmanaged* and *dead* are different properties. The plan
treated absence-from-IaC as evidence of worthlessness, when it is equally evidence of
**drift** — and drift is most dangerous exactly where something important was set up
outside the process.

The plan's own OQ3 contained the refutation and dismissed it:

> Creation mechanism of uptime id `1422253` — untraced; Sentry-only. **Does not block 5c.**

Untraced provenance is *the reason to look*, not a reason to proceed. "I don't know why this
exists" and "therefore I may delete it" is a non-sequitur that reads as diligence because
the unknown was explicitly acknowledged.

**Blast radius:** deleting it drops `app.soleur.ai` from two independent uptime vendors to
one, against a `single-user incident` brand threshold — and `model.c4:271` says in terms:

> `betterstack` is a SECOND-SOURCE vendor that pages independently precisely so a Sentry
> outage is survivable. **Do not 'consolidate' the two — the redundancy is the design.**

A brand-survival control, traded for **$1.00/mo**, in a plan whose own Overview argues *"The
win is not the $42/mo."*

### The rule

**Before deleting an unmanaged live resource, ask what it is DOING, not what manages it.**
One read of its config answers it. Concretely, for any "orphan cleanup":

- resolve each target's **function** (what URL / queue / table / cadence does it serve?),
- compare against what the managed set already covers — an orphan that covers something
  nothing else covers is not an orphan, it is **the only thing standing there**,
- treat "provenance untraced" as **blocking** for a delete, never as a footnote.

### Related but distinct: the same word, the other direction

The same PR's **Class D** detector ("live monitor with no `.tf` block") is the *correct* use
of this observation: it **flags** undeclared live resources. What it must never do is
license *undeclared ⇒ deletable*. Flagging asks a question; 5c answered it without looking.

---

## 2. A premise about a repo SETTING, stated as fact, shaping the whole design

**The plan said** — and built its central Phase 3.4 on:

> `[ack-destroy]` must sit in the **merge commit**, authored in GitHub's squash UI — **the
> author cannot pre-stage it from the branch**, and nothing tells them before they click.

From this it derived: the PR-time gate can only ever be a **red flag** (fail on a destroying
PR, tell the human to type the ack in the squash box later).

**One command falsifies it:**

```
$ gh api repos/:owner/:repo --jq '.squash_merge_commit_message'
COMMIT_MESSAGES
```

The squash body is composed from the **branch commit messages**. Confirmed against a real
merged squash commit: each commit's SUBJECT is prefixed `* `, and each commit's BODY lines
are carried **verbatim**. So:

- `[ack-destroy]` on its own line in a commit **body** → lands line-anchored in the squash
  body → **matches** the apply gate's `(^|\n)\[ack-destroy\]($|\n)`
- `[ack-destroy]` as a commit **subject** → becomes `* [ack-destroy]` → **does not match**

The ack **is** pre-stageable. The premise was false.

### Why it mattered — the plan contradicted itself

Under the false premise, the gate is **permanently red on every correct delete PR**: red
becomes the expected state of doing the right thing. The plan rejects precisely this
mechanism 30 lines earlier, for `[ack-create]`:

> a blanket `[ack-create]` would fire on the normal add-a-monitor flow and **train
> ack-blindness, eroding `[ack-destroy]` with it**.

A plan cannot reject a mechanism in one phase and adopt it in the next. The false premise
was the only thing hiding the contradiction — and the argument against it was already
written, in the same document.

With the premise corrected, the gate greens on a pre-staged ack: red means "you have not
acknowledged", green means "you have". That is a gate; the other thing is a siren.

### The second-order obligation

Once green **means** "the ack will reach the merge commit", green is a *claim about a repo
setting*. So the setting gets **verified, not assumed**: the gate fails closed if
`squash_merge_commit_message != COMMIT_MESSAGES`. Otherwise flipping one repo setting
silently greens the PR gate while the apply reds — the original bug, one layer up.

This is the whole etiology of #6589: *a known hole, documented in prose, that nobody
re-checked for two months*. Shipping the fix with an unchecked premise inside it would have
been the same mistake in a nicer font.

### The rule

**A plan's claim about a vendor/platform SETTING is a precondition, not a fact — and it is
usually one API call away.** Cheaper than the design it justifies:

- `gh api repos/:owner/:repo --jq '.squash_merge_commit_message'`
- `gh api repos/:owner/:repo/rulesets` (a "required check" claim)
- `gh api repos/:owner/:repo --jq '.visibility, .forks_count'` (a fork-PR threat model)

The tell for this class: a plan sentence of the form **"X is impossible, therefore we must
Y"**, where Y is worse and X is a platform behaviour. Check X. The reviewers did not — seven
of them — because the claim was plausible, specific, and about a system none of them had a
reason to doubt.

---

## The pattern across both

Both premises were **assertions about a system's current state** made from memory or
inference rather than a read:

- *"never Terraform-managed, so it cannot matter"* — inferred worth from management
- *"the author cannot pre-stage it"* — inferred a platform behaviour

Both survived a 7-agent plan review, because a review panel checks **reasoning**, and the
defects were in **facts the reasoning stood on**. Fresh facts are the one thing another
reader cannot supply.

At `/work` time the corrective is mechanical: for every plan claim about live state or
platform behaviour that a decision depends on, **run the read before writing the code**. It
cost two commands here and prevented one prod incident and one self-contradicting design.
