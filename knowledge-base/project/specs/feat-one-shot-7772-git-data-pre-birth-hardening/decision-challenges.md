# Decision Challenges — feat-one-shot-7772-git-data-pre-birth-hardening

Recorded at deepen-plan time, headless. These are places where the review round and the session model
agree the operator's **stated direction** should change. Per ADR-084 the operator's direction is the
default, so nothing here was applied — `ship` renders this into the PR body and files it as an
`action-required` issue.

---

## DC-1 — The "ONE PR" instruction is justified for Item B only; C and D have no hash argument

**Operator's stated direction.** *"Land ALL remaining pre-birth hardening for the git-data host in ONE PR,
before any rung-2 rehearsal dispatch."* The stated reason is that the rehearsal gate binds a hash over
`cloud-init-git-data.yml` plus its `file()`-bound payloads, so any later edit costs a second paid dispatch.

**The challenge.** That reason is true, and it covers **one** of the four items. Measured against
`git_data_rung2_user_data_sha256()`, whose own neighbouring comment states the exclusion explicitly —
*"It does NOT bind the templatefile ARGUMENTS"*:

| Item | Touches the hashed set? | Hash moves? |
|---|---|---|
| **A** — per-source token | No (root variables + module args + test arms) | **No** |
| **B** — nftables metadata drop | `cloud-init-git-data.yml` | **Yes — the only one** |
| **C** — Sentry route | No (separate Terraform root, separate workflow) | **No** |
| **D** — stale prose | No (a `.test.ts` comment and a `.sh` ABORT string) | **No** |

Item A still has a *soft* pre-rehearsal argument — D1 wants the rehearsal to attest prod's real ingest
channel, and a rehearsal firing before A attests the old shared sink. That is a semantic argument, not the
hash constraint, and the plan now says so. Items C and D have neither: C lands in a different root behind
`apply-sentry-infra.yml`, and D is four comment lines.

**What the reviewer recommended.** Ship B (+A on the soft argument) here; split C to its own PR; fold D into
whatever merges next. That would remove Phases 5-6, roughly six acceptance criteria, the new test file, and
several test scenarios from this PR's review surface.

**Why it was NOT applied.** Splitting is a change to the operator's stated scope, not a mechanical
correction. The plan keeps all four items and instead **corrects the justification**, which was the part
that was actually wrong: the Overview and Item C/D sections no longer claim the hash forces them, and state
the honest reasons — C is cheap, zero-downtime, and matters most on the first boot when nobody is watching;
D is a four-line correction to birth-route artifacts that assert falsehoods.

**One sequencing note if the operator does choose to split.** D4 makes C depend on B: the
`gitdata_nftables_metadata` stages do not exist until B ships. Ship C covering `betterstack_ingest` only,
then add the two nftables stage values inside B's PR — a one-token edit to an `IS_IN` list plus one filter
value on the fatal rule.

**Re-evaluation trigger.** Before `/work` begins, if the operator wants a smaller review surface.

---

## DC-2 — The IPv6 metadata drop is a precautionary rule against an address Hetzner does not document

**What the plan does.** Ships `meta skuid != 0 ip6 daddr fe80::a9fe:a9fe drop` alongside the IPv4 rule.

**The challenge.** Two reviewers independently flagged it. Hetzner documents **no** IPv6 metadata endpoint —
the service is IPv4-only at `169.254.169.254` and is itself what supplies the IPv6 configuration to
cloud-init. `fe80::a9fe:a9fe` is an OpenStack/Azure convention, not a Hetzner one, so if Hetzner ever ships
IMDSv6 there is no reason to expect it at that address. The rule therefore matches nothing today and would
likely still match nothing later, while reading as IPv6 coverage.

**Why it was kept.** It was verified to load cleanly alongside the IPv4 rule in an `inet` table (V1), costs
one line, and breaks nothing. The concrete harm the reviewers named — that it encoded a magic count into the
observability probe — **was** real and **has been fixed**: the discoverability test now asserts `>= 1`
against the render rather than exactly `2` against the source, so cutting the line later is free.

**Recorded as taste, not mechanics.** Either choice is defensible. If the operator prefers to cut it, the
edit is one line plus a comment recording the gap and its re-evaluation trigger.

**Re-evaluation trigger.** If Hetzner documents an IPv6 metadata endpoint, replace the guessed address with
the documented one.
