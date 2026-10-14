# Decision Challenges — feat-one-shot-7100-art30-eval-fleet-register

Recorded headless per ADR-084 (`decision-principles.md`). The operator's stated direction is
the default and has been followed in the plan; these are challenges to it, surfaced for the
operator rather than silently applied. `/ship` renders this into the PR body and files it as
an `action-required` issue.

---

## UC-1 — The docs-only scope is the failure mode this PR exists to close

**Class:** User-Challenge (operator's stated direction) · **Raised by:** `cto` (Phase 2.5),
independently reproduced by the planner.

**Operator's stated direction.** The pipeline instruction for #7100 sets a hard scope: *"this
PR touches `knowledge-base/legal/**` ONLY … NO source-file or workflow-YAML changes."* The
plan follows it.

**The challenge.** The Art. 30 record this PR authors enumerates 21 Anthropic-egressing
Inngest modules. Under a docs-only scope, the **only** thing keeping that enumeration true
after the next cron lands is the diligence of the next author — which is precisely how the
gap being fixed came to exist. The plan's mitigation (an egress predicate, a dated snapshot,
and a named residual with a tracked follow-up issue) was assessed as **not defensible**, for
a concrete reason rather than a stylistic one:

> `scripts/check-pa-22.sh` was written to guard the PA-22 register entry and **is wired into
> no workflow** — `git grep check-pa-22 .github/` returns zero hits — while
> `knowledge-base/project/specs/feat-4379-anthropic-leader-loop/tasks.md` task 6.3 asserts
> "both wired to CI in `.github/workflows/ci.yml`. Confirmed passing locally." The script has
> been dead since it was authored. **A tracked follow-up issue is the same instrument that
> produced the dead sentinel now being cited as prior art.**

Worse, this PR's own Phase 3 edit to the Anthropic Vendor Mapping row can silently break that
script's `Anthropic.*PA-22.*autonomous` assertion — adding a *fourth* failure mode to a
sentinel nobody runs.

**What the challenge asks for.** Roughly 40 lines, in the same PR:

1. `apps/web-platform/test/server/anthropic-egress-register-sweep.test.ts` — a vitest source
   sweep asserting (a) the two independent membership predicates agree, (b) the derived set
   equals PA-31's recorded snapshot, (c) the `.github/` `secrets.ANTHROPIC_API_KEY` grep
   equals PA-32's snapshot, and (d) every CLI member either appears in
   `CRON_BASH_ALLOWLISTS` or is on an explicit, comment-justified exception list. Vitest
   rather than a `scripts/*.sh` sibling **specifically because** it needs zero CI wiring —
   the existing `test/**/*.test.ts` include picks it up, and the wiring step is the one that
   demonstrably did not happen last time.
2. Wire or delete `scripts/check-pa-22.sh`.

**Cost of accepting the challenge:** the PR is no longer docs-only (one new test file, one
line in `ci.yml` or one deletion). **Cost of declining:** the register's integrity rests on
author diligence, and the failure is silent — the record simply becomes false, which is the
Art. 30(1) defect the counsel review already found once.

**Disposition in the plan:** the operator's docs-only scope is followed. The sweep is
`## Deferred Work` item 2, strengthened with the dead-sentinel evidence, and PA-31's `(g)`
tail carries the absence as a named accepted residual. **This challenge is the reason to
revisit that.**

---

## UC-3 — Two published legal documents are now false, and the docs-only scope excludes the fix

**Class:** User-Challenge (operator's stated direction) · **Raised by:** `clo` (Phase 2.5).
**Severity: the highest in this session.**

`docs/legal/privacy-policy.md` §4.4 currently tells the public:

> "If you interact with the Soleur GitHub repository (e.g., opening issues, submitting pull
> requests, starring the repository), GitHub collects data… This is standard GitHub platform
> behavior and **is not controlled by Soleur**."

That is **affirmatively false**. Jikigai ingests exactly that data, transmits it to Anthropic,
and republishes it — stargazer usernames and commenter handles with comment snippets — to a
world-readable repository. `docs/legal/gdpr-policy.md` §2.2 compounds it, describing Anthropic
requests as using *"the user's own API key"* with *"Soleur does not intermediate, intercept, or
store any data exchanged"* — the BYOK carve-out framing, materially incomplete for the
Jikigai-keyed fleet.

This is **the same failure class as counsel review #7086 Finding 4**: a record that invites a
reader to exclude a live surface. Finding 4 was rated BLOCKING.

**The challenge.** This PR's entire purpose is register accuracy. Shipping it under a
`knowledge-base/legal/**`-only scope produces an internal register that is **contradicted by
the published, outward-facing policy** — and the published one is what a data subject or a
supervisory authority reads first. Correcting §4.4 is one sentence.

**Cost of accepting:** `docs/legal/privacy-policy.md` + its Eleventy mirror +
`apps/web-platform/lib/legal/legal-doc-shas.ts` (mechanical SHA refresh). No `TC_VERSION` bump
— that policy governs `terms-and-conditions.md` only, so no forced user re-acceptance.
**Cost of declining:** the PR knowingly leaves a false public statement standing about the
exact processing it is registering.

**Disposition in the plan:** operator's scope followed; the correction is `## Deferred Work`
item 1a and PA-32's `(b)` cell records that the public statement is currently inconsistent
with the activity. **Strongly recommend accepting this one.**

---

## UC-4 — The record will state that a live limb has no lawful basis

**Class:** User-Challenge (consequence the operator must see, not a scope change).
**Raised by:** `clo` (Phase 2.5).

CLO's assessment is that Art. 6(1)(f) is **not available** for `cron-community-monitor`'s
republication limb as implemented — it fails at the **necessity** limb before balancing is
reached, because an aggregate count plus a source link serves the digest's purpose identically
without naming anyone. Art. 17 is not implementable against git history and two forks. And
PA-30's own LIA already rejected *"git-committed PII, an Art. 17 impossibility"* for a
different activity, so the register would contain both positions unless this is faced.

Consequently PA-32 will record that a **live, five-month-old, materialised** limb of the
processing lacks a lawful basis, and that the remediation (R1–R5 in the plan) is source work
this PR cannot perform. R1–R3 are prompt-string edits; R4 is a small handler-side redaction
function. CLO's estimate: about a day, not a quarter.

The operator should know that this is what an honest record says, and that the alternative —
asserting a basis the processing does not have — is the exact defect #7100 exists to fix. The
plan does not soften it.

---

## UC-2 — Two crons have no containment hook, which changes what the record may claim

**Class:** Mechanical-with-scope-consequence · **Raised by:** `cto` (Phase 2.5).

Not a challenge to operator direction — it is a finding the plan has already absorbed (D8) —
but it carries a scope question the operator should see.

`cron-daily-triage.ts` and `cron-follow-through-monitor.ts` never call
`setupEphemeralWorkspace`, so they run with **no** `PreToolUse` hook, **no** command
allowlist, **no** `runHookSelfTest`, and from the prod container CWD rather than an ephemeral
clone. The substrate's own committed probe evidence records that `--allowedTools` alone does
**not** fail-close.

The plan's disposition is to **record it accurately** — scope the Art. 32 allowlist TOM to
the members that actually have it, and name these two as exceptions whose sole compensating
control is the Tier-2 nftables egress firewall. That is the correct docs-only response and it
is what the plan does.

The alternative — **remediate the hook gap** so the record can make the uniform claim — is
source work and therefore out of scope here. The operator should decide whether an accurate
record of a real containment gap is the desired end state, or an interim one. Filed as
`## Deferred Work` item 6.
