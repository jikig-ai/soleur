---
title: "CLO attestation — #7500 zot_last_err redaction, the public egress it exposed, and the Art. 30 amendments"
type: clo-attestation
date: 2026-09-08
issue: 7500
adr: ADR-211
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: DISCHARGED — no Art. 4(12) personal-data breach on the audited egress; no Art. 33 duty; no Art. 34 duty; NO breach-register row. One Art. 30(1)(d) recipients-limb omission found and closed in the same change. One evidentiary limb NOT RUN and recorded as open.
signed_off_at: 2026-09-08
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-09-08 — the date the CLO measured the published corpus. No earlier anchor is asserted, because no Art. 4(12) event is found; see §Why there is no awareness anchor to run a clock from."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose on the audited facts, so nothing fell due. A BREACH finding on the open limb below would start a FRESH 72h from awareness of that finding."
open_limbs: "ONE. The Better Stack warehouse corpus of `zot_last_err` was NOT read for this attestation. Its conclusion rests on the same topology reasoning as the public egress — corroborating, not equivalent. Condition for closure, and what would reopen this, are stated in §The open evidentiary limb."
tier_classification: "Tier 1 — an internal determination and register amendment. No `docs/legal/**` document is edited, no published page changes, no right is narrowed. The five `docs/legal/**` CI gates (scope-block placement, mirror-drift ratchet, raw-file SHA pin, heading-sequence parity, EXPECTED_COUNT sentinel) are NOT engaged."
semver: "No TC_VERSION bump."
related:
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/breach-register.md
  - knowledge-base/engineering/architecture/decisions/ADR-211-zot-last-err-redaction-at-the-producer-and-the-sink.md
  - knowledge-base/legal/audits/2026-08-counsel-review-7440.md
  - knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md
---

# CLO attestation — #7500, ADR-211, and the PA-8 amendments

This is the v1 internal counsel-review sign-off required by the ship Phase 5.5
Counsel-Review CLO-Attestation Gate. It is performed by the CLO agent, not by the
operator, per the recurring-bug record at
`knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`.
It is an **internal** sign-off. External counsel re-review is reserved for the
re-evaluation triggers at the foot of this file.

## What was referred, and what I actually ruled on

The referral asked for a binding ruling on whether the `zot_last_err` exposure is a
personal-data breach requiring a `breach-register.md` row, plus drafted Art. 30
amendments. Ruling on it required auditing the published corpus rather than accepting
the engineering summary of it, and that audit turned up a second question the referral
did not ask: the register did not record the public egress **at all**.

## Verification actually performed

Everything in this section was run by me on 2026-09-08 in the worktree
`feat-one-shot-7500-zot-last-err-redact`. Figures are from those runs, not restated
from ADR-211 or from the commit messages.

### 1. The published corpus, read in full

`gh issue list --repo jikig-ai/soleur --search 'in:title "[ci/zot-restart-loop] Zot registry restart-loop recurrence detected"' --state all`
returns **exactly one issue**, #7272 (CLOSED). So the corpus audited below is not a
sample of the public egress — it is the whole of it, for the entire life of that
egress.

`gh api --paginate repos/jikig-ai/soleur/issues/7272/comments` returned **100**
comments. Counted over the decoded bodies:

| Measure | Count | ADR-211 says | Agrees |
|---|---|---|---|
| Comments total | 100 | 100 | yes |
| Carrying a `headers` object | 36 | 36 | yes |
| Carrying a `clientIP` | 13 | 13 | yes |
| Mentioning `authorization` | 23 | 23 | yes |

Value-level, which is the part that decides the ruling:

- **`Authorization`:** exactly one rendering across all 23 occurrences —
  `Authorization:[******]`. No second form, and no long base64 adjacent to any of
  them.
- **`clientIP`:** all 13 are `10.0.1.30` (with a varying ephemeral source port).
  ADR-211 records these as "RFC1918 `10.0.x.x`", which is true but weaker than the
  fact: they are one address, the Cloudflare tunnel connector's own private address
  inside the controller's estate. Not a range of client hosts.
- **Header names published:** the 36 header objects carry `Accept`,
  `Authorization` and `User-Agent` and nothing else. Every `User-Agent` is
  `curl/8.5.0` — this host's own liveness probe.
- **Absent from the entire corpus:** `Cookie`, `Set-Cookie`, `X-Api-Key`,
  `Proxy-Authorization`, `X-Amz-Security-Token`, `X-Forwarded-For`. Searched
  case-insensitively; zero hits.

### 2. The code, against the claims made about it

- The publication chain is scrubbed before every consumer: the workflow scrubs
  `$out` **before** `printf`, before the `ZOT_ALARM_CAUSE=` extraction, and therefore
  before `$GITHUB_OUTPUT`, the run log, the issue body and the issue comment. Verified
  by reading the ordering in `.github/workflows/scheduled-zot-restart-loop.yml`, not
  inferred from the comment that asserts it.
- `SCRUB_CRED_HDRS` in the checker, `SCRUB_CRED_HDRS` in the workflow and `CRED_HDRS`
  in `cloud-init-registry.yml` (both copies) are byte-identical. Verified by grep,
  four occurrences, one string.
- The producer degrades **closed**: `[ -n "$ZOT_LAST_ERR" ] || { ZOT_LAST_ERR=none; ZOT_ERR_SRC=none; }`
  is downstream of the tier gate and of `redact_sample_lines`, so a suppressed or
  unredactable sample cannot reach the wire as raw text.
- `X-Forwarded-For` is genuinely absent from `HDR_KEEP`, so the §(c) claim that it is
  redacted by the producer allowlist holds.
- `G2-3b` exists at `scripts/zot-restart-loop-alarm-scrub.test.sh` and asserts the
  denylist limit affirmatively (the unanticipated header **survives**). The limit is
  recorded as a measured fact, which is the disposition I required.

### 3. The register, searched for what it does not say

Searched PA-8 §(b) through §(g) and the Vendor Mapping for any record of the public
publication egress — `public repositor`, `public issue`, `github issue`,
`zot-restart-loop`, `ZOT_ALARM`. **Zero hits, corpus-wide.** That finding is the
subject of §Finding 2 below.

## Finding 1 — the referred question. NO breach-register row. Engineering position CONFIRMED.

**Ruling: no Art. 4(12) personal-data breach occurred on the public egress, no Art. 33
duty and no Art. 34 duty arose, and no row is opened in
`knowledge-base/legal/breach-register.md`.**

The reasoning is *not* the one the referral offered, and the difference matters.

**The register's inclusion predicate is conjunctive**, and limb 1 requires "a
breach-shaped fact pattern — an actual or suspected security event **touching personal
data**". On the audited corpus:

- No natural person is identified or identifiable from any published value. The
  addresses identify a machine in the controller's own estate; the sole user-agent is
  the controller's own probe; no free-text field carried an email, a name or a
  `user_id` (zot's identity model has none — its accounts are the `zot-pull` /
  `zot-push` service principals, as PA-8 §(g) already records).
- No credential VALUE was disclosed. All 23 `Authorization` renderings were masked at
  source.

Limb 1 therefore fails and the predicate is not met. Art. 33 and Art. 34 both turn on
Art. 4(12), so neither is engaged.

**Where I depart from the engineering framing.** The engineering position reasons "no
credential and no personal data, therefore not a breach". That is the right answer by
a route that would give the wrong answer on adjacent facts. Precedent in this corpus —
the 2026-09-03 determination on #7797 — indexes a **credential** exposure in the
breach register even where unauthorised access was NOT established, because a
credential gates access to personal data. So "no personal data in the payload" is not
by itself sufficient; "no credential value was rendered either" is the second half,
and it is the half the engineering summary treated as incidental. Both hold here, and
I record that both were checked.

**What I decline to treat as dispositive.** That the exposure was bounded by zot's
vendor default and by the firewall topology goes to *severity and recurrence*, not to
whether Art. 4(12) was engaged. A controller does not get a better Art. 4(12) answer
for having been lucky. The answer here is that nothing personal was in the data — the
luck is why #7500 was necessary, not why the ruling is negative. ADR-211 states this
correctly in its Option 2 rejection; the ruling rests on the corpus, not on the bound.

**Not a breach does not mean not a defect.** Publishing third-party-influenced log
content to a public surface with no controller-owned control in front of it is an
Art. 32(1) adequacy question and an Art. 5(1)(c) minimisation question. Both are
answered by the controls at PA-8 §(g) — one of which is inert. See Finding 3.

## Finding 2 — an Art. 30(1)(d) omission the referral did not name, found and closed here

The Art. 30 register recorded the public publication egress **nowhere**. PA-8 §(d)
enumerated Sentry, Hetzner, Better Stack and the internal rotation — every one a
processor under instruction — while an indeterminate public recipient class had been
receiving samples of this Activity's payload since the alarm began filing.

This is the same defect class ADR-211 records for the C4 model ("model the publication
egress the diagram never carried"), and the same class ruled on at
`knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md` — an
Art. 30 Recipients-cell omission over processing that was otherwise covered. It is an
Art. 30(1) record-keeping incompleteness corrected under Art. 5(2). It is **not** an
Art. 4(12) event: nothing was destroyed, lost, altered, or disclosed to an
unauthorised party *that was personal data*, and Art. 33/34 turn on Art. 4(12) rather
than on the completeness of the register. Same disposition as the #7625 waiver already
in the breach register.

**Closed in this change** by the amendment appended to PA-8 §(d), and by the bracket
appended to the GitHub Inc row of the Vendor Mapping. I deliberately did **not**
renumber that row's Activities cell; the amendment contract is additive and a silent
numeric edit is not how a missing activity should appear on a statutory record. The
Notes bracket says so in terms.

## Finding 3 — what I am attesting to in the amendments themselves

I drafted and applied five amendments to `knowledge-base/legal/article-30-register.md`.
Each is additive, each carries a dated `[Amended 2026-09-08 (#7500 / ADR-211): …]`
bracket, and no superseded text was edited or deleted — the two sentences this change
supersedes are **quoted verbatim** inside the brackets that supersede them.

I attest that:

1. **The sink layer is described as a DENYLIST everywhere it appears**, in PA-8 §(g),
   in the Vendor Mapping bracket, and in §(d). The register now states affirmatively
   that an unanticipated header name **survives** it, and cites the test case that
   asserts this. Allowlist language is used for the producer layer **only**, where it
   is exact. Overclaiming here is what created #7500 (the prior amendment's
   host-vs-emitter overclaim), and the amendment says so.
2. **Every amendment carries a delivery-state qualifier for the producer half.** PA-8
   §(g) states that Layer 1 is inert until the next `registry-host-replace`, that no
   part of it governs any byte leaving the host until then, and that the paragraph must
   not be read as current processing until a dated delivery entry is appended in the
   shape of the 2026-08-13 (#7455) entry. §(d) and the Vendor Mapping bracket repeat
   the qualifier rather than relying on a cross-reference, because a reader following a
   pointer from the Vendor Mapping to §(g) is exactly the reader who would otherwise
   take the control as in force.
3. **The asymmetry is stated, not left to inference:** the sink is in force at merge,
   the producer is not, and the layer that is in force is the weaker of the two, on the
   worse of the two egresses.
4. **No GFM cell-count trap was introduced.** All five amended rows were verified after
   the edit to render with the same cell count as their siblings (2 for the PA-8 table,
   6 for the Vendor Mapping), using an escape-aware split, and their raw pipe counts are
   byte-identical to `origin/main`.

## The open evidentiary limb — stated rather than implied

**The Better Stack warehouse corpus of `zot_last_err` was NOT read for this
attestation.** What I audited is the public egress, exhaustively. The warehouse corpus
is larger by construction: it carries every 5-minute `SOLEUR_ZOT_DISK` heartbeat since
delivery, not only the crash-loop windows the alarm republishes, and it has been
receiving the field with no `redact()` in the path throughout.

My conclusion for that surface rests on the **topology** reasoning already attested at
PA-8 §(c) — that ingress is intra-`10.0.1.0/24` plus a Cloudflare tunnel, so every
observable `clientIP` is RFC1918 and the only observed client is the host's own probe.
That reasoning is corroborating, not equivalent to an observed-value audit, and I
record it as such rather than presenting a topology verification as a corpus finding.
This is the same distinction the 2026-08-13 (#7455) re-attestation drew at §(c), and I
hold to it.

**What would close the limb:** a read of `SOLEUR_ZOT_DISK` rows over the delivery
window asserting that no `zot_last_err` value carries a credential-bearing header name
outside the five denylisted names, and no non-RFC1918 `clientIP`. **What would reopen
this determination:** any such value found.

I did not run it here for two reasons, both recorded rather than convenient: it needs a
warehouse read credential this session does not hold, and it is a materially different
piece of work from the ruling that was referred. It does not block the ruling, because
the ruling is scoped to the egress I audited and says so in the register.

## Two pre-existing conditions, and whether they bear on this ruling

Both were flagged in the referral as out of scope to fix. I confirm both, and record
whether either changes the answer.

- **gdpr-gate corpus 121 days stale (`POSTURE_FAIL`; #7255 / #7857).** Verified:
  `notice-frontmatter.sh days-stale` returns **121** against `last-verified: 2026-05-10`,
  which is >90 and therefore `POSTURE_FAIL`. **Does not bear on this ruling.** The gate
  is an advisory detection-rule scanner over diffs; the determination here rests on an
  exhaustive read of an actual published corpus, not on a rule scan. It does mean that
  no automated compliance signal on this branch should be treated as coverage.
- **Better Stack Art. 28(3) instrument NOT EXECUTED (#7529; vendor location statement
  #7825).** Verified still open in the Vendor Mapping. **Does not change the Art. 4(12)
  answer**, on the reasoning already fixed in the register by the 2026-09-03 (#7717)
  correction: Art. 33 and Art. 34 turn on Art. 4(12), not on whether an instrument was
  executed, and the Art. 28(3) gap is a lawfulness-and-documentation defect of a
  different class. It does bear on the *warehouse* limb above in one specific way,
  which I state rather than bury: the sample has been flowing unredacted to a processor
  with no executed processor instrument, so the "authorised disclosure to a processor
  under instruction" framing that normally disposes of a warehouse egress is weaker
  here than the register's older brackets make it sound. That is a #7529 problem, not a
  #7500 problem, and I am not resolving it here.

## Why there is no awareness anchor to run a clock from

An awareness anchor exists to start the Art. 33(1) 72-hour clock. No Art. 33 duty
arose, so no clock started and none fell due. The 2026-09-08 date in the frontmatter is
the date I measured the corpus, recorded so a reader can date the evidence — it is not
an awareness anchor for a breach, and must not be read as one. Had the corpus contained
a credential or a public address, the anchor would have been the date of that finding,
not the date of first publication, and the 72 hours would have run from there.

## What I am explicitly NOT attesting to

Stated affirmatively, because an attestation that does not bound itself is the defect
ADR-211 exists to prevent.

1. **Not attesting that the sink layer is complete.** It is a denylist. An
   unanticipated header name survives it and is published in the clear. I am attesting
   that this limit is accurately recorded, not that it is closed.
2. **Not attesting to the Better Stack warehouse corpus.** See the open limb above.
   No observed-value audit was run there.
3. **Not attesting to `clientIP`.** It is unmasked on both paths by design (#7530). Its
   non-personal character is **topology-dependent** and the dependence is a live
   re-evaluation trigger, not a settled conclusion.
4. **Not attesting to the producer control being in force.** It is inert. I attest that
   the register says so, in every place a reader could otherwise take it as in force.
5. **Not attesting to injection safety.** Republishing an attacker-chosen `User-Agent`
   into a public issue body is a markdown / at-mention injection surface. Redaction does
   not address it, no control in this change addresses it, and no gate governs runtime
   publication of third-party output to a public artifact by agent-authored automation.
   This is recorded in ADR-211's Consequences and in PA-8 §(g)(iv).
6. **Not attesting to the correctness of the engineering decision.** Whether the
   producer/sink split is the right architecture is a CTO call, made in ADR-211. I
   assessed its legal description, not its design.
7. **This is a v1 internal sign-off.** It is not external legal advice, and every
   register amendment remains draft material for professional legal review under the
   triggers below.

## Re-evaluation triggers

- **Any inbound rule admitting public ingress to zot**, or any configuration landing a
  forwarded public address in a top-level zot field. This converts `clientIP` into
  Art. 4(1) personal data on a path neither layer redacts, and it invalidates the
  corpus finding in Finding 1 prospectively. `hcloud_firewall.registry` carrying zero
  `rule` blocks is the invariant; a change to it re-opens this file.
- **A `registry-host-replace` firing.** Layer 1 becomes live at that moment. A dated
  delivery entry must be appended to PA-8 §(g) in the shape of the 2026-08-13 (#7455)
  entry at §(d), recording the boot id and the first readback — the same discipline
  that entry applied.
- **Any credential-bearing header name outside the five denylisted names appearing in
  zot's output**, since it survives Layer 2 and Layer 1 is inert.
- **The open warehouse limb being run**, with any adverse value found.
- **First arms-length (non-operator) user, EEA-out processing, or a regulated-industry
  tenant.** These are the standing triggers for **external** counsel re-review of this
  attestation and of the amendments it covers.
