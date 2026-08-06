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

## Step 2 — Send the welcome message

Send this before or at the first working session. Fill in the bracketed parts.

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
| Knowledge-base growth | Yes | **Yes** — git history on the tester's own `knowledge-base/` tree (requires collaborator access) |
| Returns / session frequency | Yes | **No** |
| Non-engineering agent usage | Yes | **No** |

CLI-era and platform-era data are **not equivalent** and must not be compared as though they were.
State the surface alongside any finding.

---

## Recruitment mix tally

Update this table at Step 1 of every onboarding.

| Tester | Company | Claude Code user? | Surface | Onboarded |
|---|---|---|---|---|
| #1 | Skouer | Yes | Self-hosted CLI | 2026-08-06 |

| | Claude Code users | Non-Claude-Code users |
|---|---|---|
| **Recorded** | 1 | 0 |
| **Ceiling / floor** | ≤ 7 | ≥ 3 |

**Before recruiting tester #8:** confirm the ≥3 non-Claude-Code floor is still reachable. It
cannot be recovered afterwards.

---

## Known gap

No alpha-tester terms exist, and the controller/processor posture for tester-owned repository data
is undetermined — tracked in [#7331](https://github.com/jikig-ai/soleur/issues/7331). Where a
tester's own product holds third-party personal data, resolve #7331 **before** Soleur agents
operate on their repository in earnest. Once resolved, an agreement step belongs in this runbook
between Steps 1 and 2.

## Related

- `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md` — motion start,
  tester #1
- `knowledge-base/engineering/operations/runbooks/beta-crm-third-party-erasure.md` — Art. 17
  erasure when a tester asks to be removed
- ADR-102 — beta-CRM architecture and its write boundary
