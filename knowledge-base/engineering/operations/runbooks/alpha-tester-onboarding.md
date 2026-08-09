---
title: Alpha-tester onboarding (per tester, Phase 4 validation protocol)
type: runbook
date: 2026-08-06
issue: 7329
roadmap: knowledge-base/product/roadmap.md (rows 4.1-4.5)
adr: knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
lia: knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md
article-30: knowledge-base/legal/article-30-register.md (PA-30)
---

# Runbook — Alpha-tester onboarding

**When to use.** Onboarding a founder as an alpha tester of Soleur, against the Phase 4 validation
protocol (roadmap rows 4.1–4.5). Target cohort is 10 founders. Run this once per tester, in order.

**Protocol issues.** [#1439](https://github.com/jikig-ai/soleur/issues/1439) recruit ·
[#1440](https://github.com/jikig-ai/soleur/issues/1440) problem interview ·
[#1441](https://github.com/jikig-ai/soleur/issues/1441) guided onboarding ·
[#1442](https://github.com/jikig-ai/soleur/issues/1442) usage tracking ·
[#1443](https://github.com/jikig-ai/soleur/issues/1443) exit interview

**The one rule that outranks the rest:** never commit a tester's name, email, or any personal
identifier to git. Step 3 explains why and where it goes instead.

---

## Step 1 — Qualify against the recruitment mix

**Check the tally at the bottom of this runbook before extending an invitation.**

#1439 requires **at least 3 of 10 founders to NOT be current Claude Code users** (CMO-review
constraint). Recruiting seven Claude Code users first makes the constraint unsatisfiable, and it
is only detectable at tester #10 unless tracked from the start.

To determine whether a candidate is already a Claude Code user, check their repository for
`CLAUDE.md`, `.agents/`, `.claude/`, or a `skills/` tree.

**Hard check:** before recruiting **tester #8**, confirm at least one non-Claude-Code user has
been recorded, and that the remaining slots can still reach 3. After #8 the constraint cannot be
recovered.

Also decide the test surface now, because it determines what Step 6 can measure:

- **Hosted web platform** — full telemetry; #1442 is measurable.
- **Self-hosted CLI plugin** — no server-side telemetry; see the Step 6 caveat.

---

## Step 2 — Send the welcome message and the terms

Send this before or at the first working session. Fill in the bracketed parts. The two
record-keeping paragraphs are not optional garnish — they are the notice and the terms. Copy the
block from **here**, never from a file under `knowledge-base/legal/`: those carry a DRAFT banner
that must not reach a tester.

```text
Hi [name],

Thanks for agreeing to be one of Soleur's first alpha testers.

Here's what to expect:
  - We'll do a guided setup session together to get Soleur running on your project.
  - After that, you use it however you like for about two weeks - no scripted tasks.
  - At the end we'll do a short call about what worked and what was missing.
  - You can stop at any point, for any reason, and you don't owe us a reason.

Getting set up: [link to setup instructions for their chosen surface]

One note on record-keeping: I keep private notes of our conversations so I can
follow up properly. That's on a legitimate-interest basis, the notes are visible
only to me, and they're deleted after 24 months at the latest. If you'd rather I
didn't, or you want them erased sooner, just email legal@jikigai.com and it's done
- no explanation needed.

The terms, briefly. Using Soleur means agreeing to
https://soleur.ai/legal/terms-and-conditions - which applies from the moment you
install it, not just on the website. No fee or obligation. What's in your private
repository stays confidential; I won't publish it. [If you've given me repo
access: I read only your knowledge-base git history, to see whether the alpha is
working, and I'll drop it whenever you say.] When the alpha ends I revoke access,
delete my copies, and confirm in writing. If you send logs, strip others' personal
details first.

[your name]
```

**Why the last paragraph is there.** It is the Art. 14 notice required by the beta-CRM LIA. The
CRM records conversation notes *about* the tester rather than data they submitted through a form,
which makes them an involuntary third-party data subject — so the notice obligation is Art. 14,
and it applies **whether or not** they also hold a platform account.

**It is a message, not a ceremony.** Nothing is signed, nothing happens in person. The LIA
specifies exactly this: a short standard notice line the operator can paste into a first-contact
message.

**If the tester signs up to the hosted platform**, they additionally receive the Art. 13 notice
through the existing `accept-terms` privacy-policy flow. That covers their *account* data. It does
**not** replace the paragraph above, which covers the CRM notes.

**Why the terms paragraph is there.** A self-hosted CLI tester never passes through the platform's
`accept-terms` flow, so nothing had ever shown them the Terms — while the Terms themselves bind on
**installing**. That is the gap #7331 closed. The paragraph is the notice; asking for a one-line
reply is the assent evidence.

> **Do not reinstate the withdrawn lead.** An earlier draft opened this paragraph with *"it runs on
> your machine, on your key — I can't see your repo."* It is warm, quotable, and **false in both
> halves for tester #1**: the 2026-08-06 session ran on the operator's machine under a Jikigai key,
> and the operator does hold repository access. It is exactly the sentence a copywriter would keep.
> Do not.

### Step 2b — Tester #1 only: the retroactive note

Tester #1 was onboarded on 2026-08-06, **before** any of the above existed, and one guided session
already ran under a Jikigai Anthropic key. Send this **in addition to** — not merged into — the
welcome block, so it reads as the correction it is rather than as boilerplate.

```text
One correction I owe you from our setup session.

That session ran on my machine using my own Anthropic API key rather than yours.
Two things follow that you should know. Your content passed through my Anthropic
account, which currently has a 30-day retention window on it - for our session that
expires around 5 September. And while the work was what you asked for, I was also
learning from how Soleur handled your codebase, which is my own purpose, not yours.

I should have had an agreement in place with you before that session, and I didn't.
The terms above are that agreement going forward; they don't apply backwards, and
I'm not going to pretend otherwise.

From now on I'll use your machine and your key, or I won't run it at all.
```

**What this message is and is not.** It is candour about a lawfulness-and-documentation gap. It is
**not** a personal-data breach notification: no security control failed and the disclosure was
requested, so no Art. 33 clock is running. Do not escalate it into one, and do not soften it into
nothing.

**What it must not claim.** Do not tell the tester "no personal data was involved." The
reconstruction supports a narrower statement — no records from their venture database were read,
and the working material was schema, configuration, tests and documentation — but a fixtures file
containing officer records was present in the tree and a read of it cannot be positively excluded.
See `knowledge-base/project/specs/feat-one-shot-7331-alpha-tester-terms-dpa/session-scope-reconstruction.md`.

---

## Step 3 — Record the tester

> ### Do not put personal data in git
>
> The tester's name, email, and any other personal identifier go in the **beta-CRM database
> only**. Never in a knowledge-base file, a commit message, a PR body, a plan, or an issue.
>
> Git history is permanent. Committed third-party personal data is an **Art. 17 erasure
> impossibility** — it cannot be deleted on request, and the repository is public and forkable.
> The database boundary is load-bearing, not a style preference. See the beta-CRM LIA; Article 30
> PA-32 reaches the same conclusion independently for a different activity.
>
> In git, refer to the tester by **company name and repository URL only.**

**Create the CRM contact** in the web platform (`/dashboard/crm`), as the authenticated owner.

- **Entry stage: `evaluating`** (probability 0.5) — past `qualified` (recruited and actively
  onboarding), short of `committed` (no agreement, no willingness-to-pay signal).
- `beta_contact_stage_transitions` is **append-only**. The entry stage cannot be silently
  corrected later, so set it deliberately.

**This step cannot be automated, by design.** Migration `126_beta_crm.sql` REVOKEs
`INSERT`/`UPDATE`/`DELETE` from `PUBLIC`, `anon`, `authenticated` and `service_role`; per ADR-102
there is no service-role write pipeline. Writes go only through `auth.uid()`-pinned
`SECURITY DEFINER` RPCs as an authenticated owner. If the web platform is unavailable, record the
gate and the unblock condition in the tester's validation record and create the contact once it is
serving — do not script around the boundary.

---

## Step 4 — Seed the protocol issues

Comment on the protocol issues so the cohort state is visible without reading this runbook:

- **#1439** — record the tester as recruit *N* of 10, whether they are an existing Claude Code
  user, and the updated mix tally.
- **#1440 / #1441** — record which stage this session was, and **any deviation from the
  #1440-before-#1441 order**, with the reason. A guided-onboarding session that precedes the
  problem interview contaminates the discovery signal; say so explicitly so the finding is not
  later pooled with clean data.

Company-level only, per Step 3.

---

## Step 5 — Run the session and observe

> **⛔ Before running anything, apply the hard gate.** See §"Operating rule — whose machine, whose
> key, whose purpose?" below. In short: use the **tester's** machine and the **tester's** API key, or
> do not run. A Jikigai-keyed run against tester content needs an Art. 28(3) instrument in place
> first (`knowledge-base/legal/2026-08-06-alpha-tester-processing-annex.md`, currently unexecuted).
> This gate is the reason this runbook exists in its present form — it was crossed on 2026-08-06.

#1441's stated observations. Capture these in `interview_notes` (database, not git):

- **Which domain leader they reach for first.** This is the single highest-signal observation in
  the protocol — it tests the core thesis that founders want an AI organization rather than an
  engineering assistant.
- **Where they get stuck.** Setup friction, vocabulary that does not land, moments they expected
  something to happen and it did not.
- **What they try that does not exist.** Feature requests are weak signal; attempted actions are
  strong signal.
- **Anything they say about paying**, unprompted. #1443 asks directly later; unprompted signal
  before the ask is worth more.

Do not demo. If the tester is exploring, let them explore badly — that is the data.

---

## Step 6 — Schedule the 2-week checkpoint now

**File the checkpoint issue during onboarding, not afterwards.** A checkpoint that depends on
someone remembering is a checkpoint that does not happen.

```bash
gh issue create \
  --title "checkpoint: 2-week usage review — <Company> (alpha tester #N), due YYYY-MM-DD" \
  --label type/chore \
  --milestone "Phase 4: Validate + Scale" \
  --body "Two-week unassisted usage checkpoint for #1442. Onboarded YYYY-MM-DD; due YYYY-MM-DD (+14d).

Company-level only — no personal data in this issue.

Check:
- KB growth: git log on the tester's own knowledge-base/ tree
- Returns and agent-mix: see the measurability caveat below

Then proceed to #1443 (exit interview)."
```

> **Do not use `--label follow-through` here.** That label routes into the automated
> follow-through sweeper, which requires a `<!-- soleur:followthrough script=… earliest=… -->`
> directive and an exit-code probe —
> `.claude/hooks/follow-through-directive-gate.sh` **denies** the `gh issue create` outright
> without one. It is also the wrong semantics: the sweeper *auto-closes* an issue when its probe
> passes, whereas this checkpoint becomes **due** at 14 days rather than satisfied. The work here
> is a conversation, which has no exit-code probe. Put the due date in the title instead.

### Measurability caveat — carry this with every #1442 finding

#1442 tracks returns, knowledge-base growth, and non-engineering agent usage. **On a self-hosted
CLI plugin there is no server-side telemetry**, so most of it is not observable.

| #1442 metric | Hosted platform | Self-hosted CLI |
|---|---|---|
| Knowledge-base growth | Yes | **Yes** — git history on the tester's own `knowledge-base/` tree. **Does NOT require collaborator access:** a tester-supplied `git log --stat`, or commit/file/directory counts, yields the same figure. Collaborator access buys independent verifiability, not the metric — and it is what puts Jikigai in a controller posture (PA-35). Prefer the aggregate route. |
| Returns / session frequency | Yes | **No** |
| Non-engineering agent usage | Yes | **No** |

CLI-era and platform-era data are **not equivalent** and must not be compared as though they were.
State the surface alongside any finding.

---

## Recruitment mix tally

Update this table at Step 1 of every onboarding.

| Tester | Company | Claude Code user? | Surface | Onboarded | Terms |
|---|---|---|---|---|---|
| #1 | Skouer | Yes | Self-hosted CLI | 2026-08-06 | `sent-awaiting-reply` (sent retroactively — onboarding began before the terms existed) |

**`Terms` values:** `agreed` (tester replied), `sent-awaiting-reply`, or `not-required`. Update at
Step 1. A tester at `sent-awaiting-reply` may still be worked with; a tester at blank has not been
sent anything and that is the state this column exists to make visible.

| | Claude Code users | Non-Claude-Code users |
|---|---|---|
| **Recorded** | 1 | 0 |
| **Ceiling / floor** | ≤ 7 | ≥ 3 |

**Before recruiting tester #8:** confirm the ≥3 non-Claude-Code floor is still reachable. It
cannot be recovered afterwards.

---

## Operating rule — whose machine, whose key, whose purpose?

This replaces the former "Known gap" section. The posture **was** determined on 2026-08-06:
`knowledge-base/legal/audits/2026-08-06-alpha-tester-controller-processor-determination.md`.

Apply one question before any session against a tester's content — **whose machine, whose API key,
whose purpose?**

| Posture | Condition | Jikigai's role | What you need first |
|---|---|---|---|
| **A** | All three the tester's | **Neither** controller nor processor | Nothing. This is the default and the safe one. |
| **B** | Tester content reaches a Jikigai machine, credential or account | **Processor** | An Art. 28(3) instrument, **before** the run |
| **C** | Jikigai reads tester content for **Soleur's own** purpose | **Controller** | A lawful basis + LIA + Art. 14 notice |

### The four Posture B triggers

1. The tester connects their repository to the **hosted platform**.
2. **The operator runs Soleur agents against tester code or data on the operator's own machine
   under a Jikigai Anthropic key**, at the tester's request (guided onboarding, a debugging
   session). — **⚠ THIS FIRED on 2026-08-06 with tester #1.** The instrument it requires did not
   exist. That is the whole reason this section exists; see the determination.
3. The tester sends a repository copy, database dump, fixture, `.env`, or DB credential by any
   channel.
4. Jikigai holds any credential to a tester system (their hosting, their database, a deploy token).

Triggers 1, 3 and 4 have **not** fired. Treat them as prospective.

### ⛔ Hard gate — no Jikigai-keyed runs against tester content

**Until an Art. 28(3) instrument is in place with that tester: use the tester's machine and the
tester's own API key, or do not run.**

This is the one control that depends on nobody drafting anything, and it is what makes deferring
counsel spend legitimate rather than negligent. It is not advice — it is the precondition for
running a guided session at all.

If a future tester makes a Jikigai-keyed run genuinely unavoidable, **that** is the moment to buy
the single counsel review of the bilateral instrument — once, reusable across all ten testers.

### Collaborator access on a tester's repository

**Standing rule: do not accept it.** It buys **independent verifiability** of one #1442 metric of
three — not the metric itself, which a tester-supplied `git log --stat` or a commit/file/directory
count yields without any access (see the measurability caveat above, which states this in the same
terms; an earlier draft of this section said the access bought the metric, contradicting it).

**Tester #1 is an exception, and it is papered rather than pretended away.** The operator holds
collaborator access to Skouer's private repository and reads its `knowledge-base/` tree for #1442.
That is Posture C — Jikigai as controller. It is recorded at **PA-35** in the Article 30 register
and assessed in
`knowledge-base/legal/legitimate-interest-assessments/2026-08-06-alpha-tester-repo-observation-lia.md`.

The LIA's own recommendation is to **re-derive the metric to non-personal aggregates** (commit
counts, file counts, directory growth) rather than reading repository content — same metric, out of
Art. 4(1) scope almost entirely, costs nothing. Prefer that for testers 2–10 rather than repeating
the exception by inertia.

**Never republish observed content.** Nothing read under this access may enter a Soleur commit,
issue, digest, case study or marketing artifact. This is the PA-32 failure mode (80 digests
published carrying third-party handles, never deleted) and it is named here so it cannot be reached
by inattention.

### Offboarding — at end of alpha

- Revoke collaborator access on every tester repository.
- Delete local clones and retained feedback artifacts.
- Confirm in writing to the tester within **30 days**.

## Related

- `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md` — motion start,
  tester #1
- `knowledge-base/engineering/operations/runbooks/beta-crm-third-party-erasure.md` — Art. 17
  erasure when a tester asks to be removed
- ADR-102 — beta-CRM architecture and its write boundary
