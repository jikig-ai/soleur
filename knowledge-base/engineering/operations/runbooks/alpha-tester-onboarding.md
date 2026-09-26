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

The test surface is **decided**: testers #2–#10 onboard onto the **hosted web platform**
(#8880, Approach A). Hosted keeps the cohort's telemetry comparable, is the only surface a
non-Claude-Code founder can reach, and makes #1442 measurable. Tester #1 remains the sole
self-hosted-CLI tester — his data is marked CLI-era wherever a finding cites it (see the
Step 6 caveat), and the CLI surface keeps the local `.soleur/decisions.jsonl` capture for
route/agent-mix signal.

**Screening question** (append to every recruitment DM): *"Do you currently use Claude Code
or another AI coding CLI?"* — one line decides which side of the mix tally a candidate lands
on before any deeper conversation.

**Non-CC first, with a stall valve.** Prioritize non-Claude-Code candidates for testers
#2–#4 — they carry the surface-thesis signal a CC-only cohort cannot produce. **Fallback:**
if no non-CC candidate has signed within 2 weeks of a seat opening, onboard the next
qualified CC tester and keep non-CC outreach running; the ≥3/10 floor still has slack until
tester #8, and an unbounded stall costs more learning than a sequenced seat.

**Channel attribution.** Record `channel:framing` in `beta_contacts.source` (e.g.
`dm:warm-intro`, `waitlist:buttondown`, `dm:direct-outbound`) plus the company-level channel
in the tally row — the cohort funnel's answer to "which channel produces testers" lives
there, not in analytics.

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
    By the end of that first session you'll have one real artifact from your own
    business — not a demo, something you'd use.
  - After that, you use it however you like for about two weeks - no scripted tasks.
  - At the end we'll do a short call about what worked and what was missing.
  - You can stop at any point, for any reason, and you don't owe us a reason.

Getting set up (takes about ten minutes; we'll do the fiddly part together on the call):
https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/tester-docs/alpha-tester-setup.md

Our Slack channel for anything that comes up: [Slack channel link — see the Slack step below]

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

## Step 5 — Run the guided session (hosted path, testers #2–#10)

> **⛔ Before running anything, apply the hard gate.** See §"Operating rule — whose machine, whose
> key, whose purpose?" below. In short: the tester uses **their own Anthropic API key** on their
> own account. A Jikigai-keyed run against tester content needs an Art. 28(3) instrument in place
> first (`knowledge-base/legal/2026-08-06-alpha-tester-processing-annex.md`, currently unexecuted).
> This gate is the reason this runbook exists in its present form — it was crossed on 2026-08-06.

**Live on the call, in order.** Each step is a guided pass — you drive, they watch and approve:

1. **Signup** — invite link → accept terms → name the workspace. (Self-serve-OK list the tester
   can do alone beforehand: terms acceptance, workspace naming, the product tour, joining Slack.)
2. **Anthropic key — the friction wall.** Walk them through creating their own key at
   console.anthropic.com (the setup doc has screenshot-level steps). They paste it into
   `/setup-key`; the platform encrypts it at rest and it never leaves their tenant. Do NOT offer a
   Jikigai key — that is the Posture B trigger, pending the Side Letter.
3. **GitHub connect** — connect their repo live. If it stalls, the doc's skip path applies:
   *"Skip this step — connect later with help."*
4. **First real question → one artifact.** Have them ask one question about their actual business —
   a real one, not a demo prompt — and walk out with one artifact they'd genuinely use.
5. **Day-0 emit verify (CLI-surface testers and dogfooding only).** For a tester on the CLI
   plugin, run `/soleur:go` once during the session and confirm one line lands in
   `.soleur/decisions.jsonl` — this is the stale-install detector at day 0, not day 14. Hosted
   testers have no local plugin; their equivalent signal is the first-conversation funnel stage.

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

### Slack channel

Create a private `#alpha-tester-<company>` channel in the existing Jikigai workspace before the
guided session; invite the tester; pin two messages — the setup doc link and a "what to try next"
note (three starter prompts from the setup doc). Reactive-only cadence: you answer when they post.
**No scripted broadcasts** — a nudge mid-window converts an unassisted return into an assisted one
and contaminates the #1442 signal (see the quiet protocol). Quiet periods in the channel are
*visibility*, not a nudge trigger on their own — the armed `cohort-quiet` check owns that.

### Cohort tag — do it in the same session

After signup, PATCH the tester into the cohort so server-side metrics can filter on them:

```bash
SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
curl -fsS -X PATCH "https://app.soleur.ai/api/internal/cohort" \
  -H "Authorization: Bearer $SECRET" -H "Content-Type: application/json" \
  -d '{"userId":"<their user id>","cohort_key":"alpha"}'
```

Then record `cohort_key=alpha` in the tally row — the runbook row is the non-PII tag↔cohort map
`cohort-status` reconciles against. A signup that stays un-tagged is invisible to `?cohort=alpha`
funnel pulls; the `cohort-quiet` check lists un-tagged recent signups as a safety net.

### Quiet protocol (days 1–10)

The armed `cohort-quiet` check posts a quiet list to the tracking issue at day 3 (and the
checkpoint is armed the same way — see Step 6). Quiet = no non-failed conversation in ≥3 days, or
zero conversations at ≥3 days old — the never-activated tester is the highest churn risk and is
exactly who the predicate exists to catch.

**When a quiet flag fires:** a single human nudge in the Slack channel. Then — the load-bearing
part — record `nudged_at: YYYY-MM-DD` in the tester's tally row. A nudged tester who later returns
is **assisted**, not unassisted; at n=10 the checkpoint template discloses which returns were
assisted so the two signal classes never pool into one number.

---

## Step 6 — File the tracking issue and arm the reminders now

**Do both during onboarding, not afterwards.** A checkpoint that depends on someone remembering
is a checkpoint that does not happen — this is the exact failure tester #1's loop hit.

1. **File the tracking issue** (this is also where the checkpoint comment and the quiet-check
   report land):

```bash
gh issue create \
  --title "checkpoint: 2-week usage review — <Company> (alpha tester #N), due YYYY-MM-DD" \
  --label type/chore \
  --milestone "Phase 4: Validate + Scale" \
  --body "Two-week usage checkpoint for #1442. Onboarded YYYY-MM-DD; due YYYY-MM-DD (+14d).

Company-level only — no personal data in this issue.

Check:
- Cohort funnel: GET /api/admin/analytics?cohort=alpha (admin session)
- KB growth: git log on the tester's own knowledge-base/ tree
- CLI testers: tester runs plugins/soleur/scripts/alpha-metrics.sh and pastes the aggregate
- Assisted vs unassisted: check nudged_at in the runbook tally row before scoring a return

Then proceed to #1443 (exit interview)."
```

2. **Arm the reminders** — one wrapper call posts the 14-day checkpoint comment AND the day-3
   `cohort-quiet` named-check against that issue:

```bash
export INNGEST_MANUAL_TRIGGER_SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET \
  -p soleur -c prd --plain)
bash scripts/arm-checkpoint.sh <N> <tracking-issue-number>
```

   It prints the armed ids (`checkpoint-tester-N-<date>`, `cohort-quiet-tester-N-<date>`). The issue
   comments @-mention the operator, and the checkpoint id embeds its fire date — Inngest dedupes
   on the event id, so a re-armed date under the same id would silently keep the old schedule.

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

## Standing step — re-notify the cohort on every `TC_VERSION` bump

**Why this exists.** The Web Platform forces every principal through `/accept-terms` when
`TC_VERSION` changes. **That mechanism cannot reach a self-hosted CLI tester** — there is no
session, no middleware, and no acceptance record to invalidate. Every tester on the Self-hosted CLI
surface is therefore invisible to the bump, and without this step a version bump silently leaves
the cohort on superseded terms.

**Trigger:** any change to `TC_VERSION` in `apps/web-platform/lib/legal/tc-version.ts`.

**Do this in the same PR as the bump:**

1. Set the `Terms` cell to `superseded-resend-required` for **every** tester currently at `agreed`
   or `sent-awaiting-reply` whose Surface is anything other than Hosted platform.
2. Send each of them the notice below. It is outward-facing correspondence with a named person, so
   the operator sends it — but the text is drafted here so it is never re-authored under time
   pressure, and `TC_BUMP_METADATA.substantiveChange` is the single source for the summary line.
3. On reply, set the cell to `agreed`. A tester left at `superseded-resend-required` has **not**
   been notified, and the gap is visible in this table rather than implied by its absence.

**Drafted notice** — substitute the summary from `TC_BUMP_METADATA.substantiveChange`:

> Subject: Soleur terms updated — no action needed unless you disagree
>
> Hi <name>,
>
> The Soleur Terms & Conditions changed on <date> (version <TC_VERSION>). Because you run Soleur
> on your own machine rather than through the hosted platform, the app cannot show you this in a
> banner, so I am sending it directly.
>
> What changed, in plain terms: <TC_BUMP_METADATA.substantiveChange>.
>
> The full terms are at <https://soleur.ai/legal/terms-and-conditions/>. Nothing you need to do —
> continuing to use Soleur means the updated terms apply. If anything in them does not work for
> you, reply and tell me; I would rather hear it than not.
>
> — Jean

## Exit interview (#1443 instrument — run at the checkpoint or end of window)

Three questions, in this order — the third is the only metric that answers the business question:

1. **Which domain leaders did you actually use — and did anything carry over between sessions?**
   (The compounding probe: multi-domain usage without knowledge-base growth means the compounding
   thesis is wrong; with it, the value proposition holds.)
2. **Did any of my check-ins change whether you came back?** — the nudge-disclosure question;
   reconcile the answer against `nudged_at` in the tally before scoring the return unassisted.
3. **Willingness to pay.** "Would you pay $49/month for this as it stands? What would make it a
   yes?" — the roadmap exit criterion needs ≥3 WTP signals out of 10; this ask is where they come
   from.
4. **Testimonial opt-in** (CMO ask, recorded in CRM): "If this earned it, would you be willing to
   be quoted — a sentence or two, with your name and company?" A yes here is marketing inventory;
   a no costs nothing and tells you something about the experience.

## Tester-#1 repair checklist (owed actions — run these now, off this PR's critical path)

All four are executable today on this runbook alone; none wait on code:

- [ ] **File the overdue 2-week checkpoint** for tester #1 (due ~2026-08-20). Aggregate KB growth
  from the git history + self-reported usage — mark the self-report as such; it decays weekly.
- [ ] **Send the terms re-notification** (#7459) — the terms sent predate `TC_VERSION` 2.5.0;
  the standing-step draft below is the text.
- [ ] **Create the beta-CRM contact** (owner-authenticated, `/dashboard/crm`) — the write gate is
  deliberate; do not script around it.
- [ ] **C9 controller/processor re-run** per #7348 — the legal precondition to tester #2's first
  session; the guided hosted path (tester's own key, their account) is designed to stay Posture A.
- [ ] **Retro problem interview** with tester #1 — flagged post-exposure; never pool with #1440.

## Recruitment mix tally

Update this table at Step 1 of every onboarding. `cohort_key` and `nudged_at` are what
`cohort-status` reconciles — keep them filled.

| Tester | Company | Claude Code user? | Surface | Onboarded | Terms | cohort_key | nudged_at |
|---|---|---|---|---|---|---|---|
| #1 | Skouer | Yes | Self-hosted CLI | 2026-08-06 | `superseded-resend-required` (was `sent-awaiting-reply`; the terms sent predate `TC_VERSION` 2.5.0 — see the standing step below; send tracked at #7459) | — (CLI; no hosted account) | — |

**`Terms` values:** `agreed` (tester replied), `sent-awaiting-reply`, `superseded-resend-required` (a `TC_VERSION` bump landed after the terms were sent; a fresh notice is owed), or `not-required`. Update at
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
