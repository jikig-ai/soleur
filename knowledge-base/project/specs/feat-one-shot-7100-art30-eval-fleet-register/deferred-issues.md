# Deferred work from #7100 — DEF-0 … DEF-9

This file is the **stable citation target** for the `DEF-N` tokens used in
`article-30-register.md` (PA-31/PA-32/PA-33), the Art. 6(1)(f) LIA and the DPIA screening
memo. Those documents cite `DEF-N`, not issue numbers, so the taxonomy below is load-bearing
and must not be renumbered. The mapping table records which GitHub issue carries each item.

**Why this PR defers them.** #7100's deliverable is an accurate Art. 30(1) record of the system
**as it is**. Every item below is a change to the system itself — source edits to crons, new
notice mechanisms, new tooling. Recording the gap honestly and tracking the fix is defensible;
asserting a fixed state that does not exist is not.

## Mapping

| Token | Item | Issue | Status |
|---|---|---|---|
| DEF-0 | Minimise or cease the PA-32 republication limb (R1–R5), incl. erasure posture | #7119 | BLOCKING |
| DEF-1 | Art. 14 notice to the PA-32 third-party population (overdue since ~2026-03-19) | #7120 | Statutory |
| DEF-1a | Correct the false controllership statements in the public policies | **resolved in this PR** | Done |
| DEF-2 | Register-vs-code drift guard for the PA-31 membership predicate | #7125 | Tooling |
| DEF-3 | Collector-side input minimisation before Anthropic egress (PA-31 / arm B1) | #7124 | Open |
| DEF-4 | Erasure posture for already-published digests | _folded into DEF-0_ | Open |
| DEF-5 | Full DPIA for PA-32 (required and overdue) | #7121 | Statutory |
| DEF-6 | Containment-hook gap — two fleet members run unhooked | #7123 | Defect |
| DEF-7 | Prompt-injection reaching a public publication surface | #7122 | Security |
| DEF-8 | Art. 15 / 20 reachability for published git artifacts | #7126 | Open |
| DEF-9 | Art. 21(1) objection route for the PA-32 population | #7126 | Open |

DEF-4 is folded into DEF-0 because R5 already scopes "a retention/erasure posture for published
artifacts, or an explicit finding that none is possible". DEF-8 and DEF-9 are filed as one
data-subject-rights issue: both ask the same question (how a subject reaches data that lives in
append-only git history) and neither is separately actionable.

---

## DEF-0 — BLOCKING: minimise or cease the PA-32 republication limb

**Labels:** `priority/p1-high` `domain/legal` `compliance/critical` `type/bug`

PA-32 records that **Art. 6(1)(f) is not available** for the republication limb as implemented.
The assessment fails at the necessity limb: publishing usernames and quoted excerpts is not
necessary for operator awareness, because an aggregate count plus a link to the source
discussion serves the purpose identically.

Measured state (2026-07-31): **80** digests published 2026-02-19 → 2026-06-08 to a **public**
repo with **2 forks**; **45** carry a `| User | Issue/PR | Comment |` table; **65** name
stargazers; **zero** deletions have ever occurred. The public-issue limb appears still live.

Remediations, from the LIA Arm B2:

- **R1** — drop the mandated stargazer username list; emit an aggregate count.
- **R2** — replace the commenter table with an issue link plus a count.
- **R3** — move the aggregate-only directive out of the LinkedIn paragraph to digest scope, and
  delete "Brief contextual quotes … with attribution are acceptable".
- **R4** — a **code-level** redaction pass over the digest body and issue body before
  persistence. PA-27's own DPIA residual states that *"a prompt instruction is a claim, not a
  mechanism"* — with more force here, because there is no output allowlist and there **is** a
  publication tool.
- **R5** — a retention/erasure posture for published artifacts, or an explicit finding that none
  is possible and the data must therefore not be published (**DEF-4**).

R1–R3 are prompt-string edits; R4 is a handler-side function. **R4 alone does not remediate the
80 already-published digests** — that is R5/DEF-4.

Until this lands, the register carries a live limb with no lawful basis. That is the honest
record, not an acceptable steady state.

---

## DEF-1 — Art. 14 notice to the PA-32 third-party population (OVERDUE)

**Labels:** `priority/p1-high` `domain/legal` `compliance/critical`

PA-17 carried a #4558 "first third-party-personal-data repository" re-evaluation trigger. It
**fired ~2026-02-19**, when `cron-community-monitor` first published third-party data — before
it was honoured. The Art. 14(3)(a) one-month clock therefore expired **~2026-03-19**.

Data subjects: Discord members, Hacker News posters, GitHub commenters and stargazers whose data
was not obtained from them. No Art. 14(5) exemption has been established; disproportionate
effort under 14(5)(b) must be assessed per sub-population, not asserted wholesale.

Deliverable: a multi-channel notice (repository README/community docs, Discord server notice,
and a statement in the published digest format itself), plus the assessment of which
sub-populations 14(5)(b) genuinely covers.

---

## DEF-2 — Register-vs-code drift guard for the PA-31 membership predicate

**Labels:** `priority/p2-medium` `domain/engineering` `type/chore`

PA-31's membership is a **dated snapshot** of 21 modules, derived from two independent
predicates that currently agree byte-for-byte:

```
grep -lE 'ANTHROPIC_API_KEY' "$D"/{cron,oneshot,event}-*.ts | sort
grep -lE 'spawnClaudeEval\s*\(|resolveClaudeBin\s*\(|postAnthropicMessage\s*\(' "$D"/{cron,oneshot,event}-*.ts | sort
```

A snapshot in a statutory record rots silently: a new cron added tomorrow egresses to Anthropic
with no register entry, and nothing fails. Add a CI guard asserting the two predicates still
agree **and** that the resulting set matches PA-31's recorded snapshot, failing with a message
naming the drifted module. Fold `scripts/check-pa-22.sh` into the same harness.

Anchor the assertion on the heading form `^## Processing Activity 31 — ` — the register has no
`- PA-N` bullet form, and a bare `PA-31` token also matches cross-references.

---

## DEF-3 — Collector-side input minimisation before Anthropic egress

**Labels:** `priority/p2-medium` `domain/engineering`

Distinct from DEF-0, which concerns the **output**. This concerns the **input**.

`cron-community-monitor`'s directives ("do not store raw message transcripts", "never list
individual followers, commenters, or likers") constrain the digest output only. Raw Discord
messages, GitHub comment bodies, HN comment text and stargazer usernames enter the Anthropic
context **regardless**. The LIA records affirmatively that **no PII scrub exists** on
Anthropic-bound content — PA-22's `sanitizePromptString` measure is *not* inherited here.

Deliverable: a collector-side minimisation pass so that content which never needs to reach the
model does not. Anthropic's default 30-day retention applies to whatever is sent, and the
zero-retention amendment is unsigned.

---

## DEF-5 — Full DPIA for PA-32 (REQUIRED and overdue)

**Labels:** `priority/p1-high` `domain/legal` `compliance/critical`

The DPIA screening memo concludes no full DPIA is required for PA-31 or PA-33, but that one **is
required for PA-32** — systematic monitoring of publicly accessible data combined with
publication of third-party personal data. Because the processing has been live since
~2026-02-19, the assessment is **~5 months overdue**; Art. 35 requires it *prior to* processing.

Scope it against the actual population and the R1–R5 outcome — if DEF-0 lands as "cease", the
DPIA documents a discontinued activity and its residual, which is a materially different
document from one assessing an ongoing one.

---

## DEF-6 — Containment-hook gap: two fleet members run unhooked

**Labels:** `priority/p2-medium` `domain/engineering` `type/bug`

13 of the 15 CLI-egress crons run under the containment hook. **`cron-daily-triage`** and
**`cron-follow-through-monitor`** call `resolveClaudeBin()` and spawn the binary directly,
bypassing the helper — so the Art. 32 allowlist TOM **cannot be stated uniformly** across PA-31,
and the register says so rather than overclaiming. Their sole compensating control is the Tier-2
egress firewall.

This is also the reason PA-31 is scoped by an egress predicate: a `spawnClaudeEval`-keyed scope
would have silently excluded both. Route them through the hooked substrate, or document why they
cannot be and what compensates.

---

## DEF-7 — Prompt-injection reaching a public publication surface

**Labels:** `priority/p1-high` `domain/engineering` `type/security`

`cron-community-monitor` ingests attacker-authorable text (Discord messages, HN posts, GitHub
comment bodies) into a model context whose output is **committed to a public repository and
posted to public GitHub issues** under a bot identity with write access — with no output
allowlist between the model and the publication tool.

The publication surface is what makes this materially worse than ordinary injection: a
successful injection does not merely mislead the operator, it publishes attacker-chosen content
under Jikigai's name, permanently, into git history and forks.

Deliverable: an output allowlist or schema-constrained publication path, so model output cannot
determine arbitrary published text. Overlaps R4 in DEF-0.

---

## DEF-8 + DEF-9 — Art. 15/20 reachability and the Art. 21(1) objection route

**Labels:** `priority/p2-medium` `domain/legal`

Filed together: both concern how a data subject exercises rights against data that lives in
append-only git history.

**DEF-8 (Art. 15 / 20).** A subject asking what is held cannot be answered from the database —
their data is in commit objects, in GitHub's commit UI, in every clone and in 2 forks. Define
what a truthful Art. 15 response says, and whether Art. 20 portability engages at all for data
the controller did not receive from the subject.

**DEF-9 (Art. 21(1)).** Where processing rests on legitimate interest, the subject has an
absolute right to object, and the controller must stop unless it demonstrates compelling
legitimate grounds. There is currently **no route** for a Discord member or HN poster to object,
and no defined behaviour if one does. Note the interaction with DEF-0: for the republication
limb there is no legitimate-interest basis to object *to* — the correct response is that the
limb should not be operating.

---

## Net-issue-flow accounting

- **Closing:** 1 (#7100)
- **Filing:** 8
- **Net:** +7

Justification per filing — none could be inlined under the ≤100-line / ≤4-file rule:

| Filing | Why not inlined |
|---|---|
| DEF-0 | Source edits across cron prompt strings plus a new handler-side redaction function; blocking remediation of a live limb. |
| DEF-1 | A statutory notice mechanism across three channels; not a code change and not this PR's scope. |
| DEF-2 | New CI guard plus harness consolidation. |
| DEF-3 | Collector-side minimisation pass over a multi-source ingest path. |
| DEF-5 | A full DPIA is a legal work product, not a diff. |
| DEF-6 | Routing two crons onto the hooked substrate touches the spawn path shared by the fleet. |
| DEF-7 | A discovered security defect in a different subsystem — must stay its own issue and must not be buried in a consolidated tracker. |
| DEF-8+9 | Data-subject-rights plumbing with no existing route; consolidated from two tokens into one issue. |

DEF-1a was **resolved inline in this PR** rather than filed, and DEF-4 was folded into DEF-0,
which is why the net is +7 rather than +9.
