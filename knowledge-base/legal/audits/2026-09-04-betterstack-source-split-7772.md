---
title: "CLO ruling — Better Stack Logs source split for git-data (#7772 / PR #7805)"
type: clo-attestation
date: 2026-09-04
issue: 7772
pr: 7805
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: DISCHARGED
signed_off_at: 2026-09-04
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
disposition_history: "BLOCKED at first review pending six MUST edits (MUST-1..MUST-6) plus two SHOULDs -> all eight landed in PR #7805 -> DISCHARGED 2026-09-04."
tier_classification: "Tier 2 — an Art. 30 amendment that ALSO corrects two PUBLIC documents (`docs/legal/privacy-policy.md` §5.14, `docs/legal/data-protection-disclosure.md` §2.3(m)). The five mirror/SHA/heading gates ARE engaged; both mirrors were edited byte-identically and `legal-doc-shas.ts` re-pinned in the same commit."
semver: "No TC_VERSION bump. The public edits correct a stale region identifier and an unsupported locality; they narrow no right and add no processing."
brand_survival_threshold: single-user incident
written_against: the diff as landed, and DNS re-measured independently rather than inherited
re_evaluation_triggers:
  - "A written vendor statement of the physical processing location and of EEA-only support access for `data_region eu-central-1a` is received. That upgrades PA-8 §(e) from contractual-and-establishment inference to evidence, and is the one open external question."
  - "Any narrowing of `git-data-emit`'s bare-UUID or `/mnt/git-data[-luks]/repositories/` redaction rules, or any change that moves either below the `tail -c 180` cap. That is the condition on which the 90-day window stops being harmless and the PA-8 lawful-basis limb must be re-run."
  - "Creation of any further Logs source on team `520508`, or a change to either source's `logs_retention`."
  - "First arms-length user of the git-data plane (today: none — the `soleur-git-data` server has never been born)."
---

# CLO ruling — Better Stack source split (#7772)

## Disposition

**DISCHARGED.** Six MUST edits and two SHOULDs landed in PR #7805. One question is
routed to external counsel; it is tracked, not blocking, and it is not an operator
decision.

## The measurement that reframed the review

The feared exposure was a NEW REGION: source `2734275` reports `data_region
eu-central-1a`, while four legal artifacts — two of them PUBLIC — pinned `eu-fsn-3`
and asserted "Falkenstein DE". Resolved directly rather than inferred, and
re-measured independently by the implementer before any of it propagated:

```
eu-fsn-3.betterstackdata.com.               CNAME  eu-central-1a.betterstackdata.com.
s2457081.eu-fsn-3.betterstackdata.com.      CNAME  eu-fsn-3.betterstackdata.com.
s2734275.eu-central-1a.betterstackdata.com. CNAME  eu-central-1a.betterstackdata.com.
eu-central-1a.betterstackdata.com.  A  195.63.225.49 .50 .53 .70 .72
```

Both sources resolve, through the same apex, to an **identical five-address A set**.
`eu-central-1a` is not a new cluster; it is the vendor's current name for the cluster
the corpus already called `eu-fsn-3`. The split is a re-partitioning of one
processor's storage on one team (`520508`) — **not a new recipient, not a new
transfer, not a new category of data**. No Art. 13(3) prior-disclosure duty and no
Art. 33/34 assessment arise.

## Holdings

**1. Residency.** A cluster label is not a location attestation, and the corpus had
been treating one as if it were. "Falkenstein DE" was derived from the `fsn`
substring of the old region label; there is no vendor location attestation anywhere
in `knowledge-base/legal/`. The vendor's rename strips the substring and exposes the
inference. The locality is **WITHDRAWN and not replaced** — in the register, the
compliance-posture table, the DPA template, and both public documents. The
`no third-country transfer` conclusion is **SUSTAINED on a different and now
explicit ground**: Better Stack s.r.o. is established in the Czech Republic (EEA)
and its standard DPA terms carry an EU-region commitment. This defect is larger than
the new source and older than this PR: the incumbent's published locality was
unsupported too.

**2. Retention — the ruling's premise was wrong, and the correction makes it stronger.**

> **Superseded 2026-09-04, during implementation.** This holding was drafted on
> "3 days on `2457081`, 90 on `2734275`" and built a per-source divergence argument
> on it. **Both sources are 90 days.** Measured twice, on two endpoint shapes
> (`GET /api/v2/sources` and `GET /api/v2/sources/<id>`): `logs_retention=90` and
> `metrics_retention=90` for each. The `3-day` figure came from
> `betterstack-log-query.md` and was a FREE-TIER value predating the 2026-08-16 move
> to a paid plan; it had already propagated into the Art. 30 register and both
> published legal documents. All corrected in the implementing change.
>
> This also supersedes #7717's PA-8 §(f) entry, which recorded Better Stack retention
> as NOT RECORDED because the account tier cannot be pulled. That is true of the tier
> and false of the retention: `logs_retention` is a **per-source attribute**, not a
> billing field, and it reads directly. Art. 30(1)(f) is discharged for this plane,
> not deferred.
>
> **The disposition is unchanged and the reasoning is now simpler.** There is no
> per-source divergence to explain. "Short retention" is withdrawn as a mitigation
> for the WHOLE Better Stack plane rather than for one source — it never described
> any of it — and what actually carries the balancing is stated per stream below.

PA-8 cited "short retention" as a whole-plane mitigation. At 90 days on every source
that is not true of any of it. It does **not** disturb the LIA's *conclusion*,
because neither stream ever depended on the window — they earn the mitigation
differently:

- `2457081` carries **pseudonymous** identifiers (`userIdHash`, HMAC-SHA256 under a
  Doppler-held pepper the processor does not have). Recital 26 applies for the full
  90 days; the mitigation is the pepper, not the window.
- `2734275` carries **redacted** output. `git-data-emit`'s `_clean` applies a
  bare-UUID rule and a `/mnt/git-data[-luks]/repositories/…` path rule, both ABOVE
  the `tail -c 180` cap, and both SUBSTITUTE rather than hash. `REPO_ROOT` is
  `$GIT_DATA_ROOT/repositories`, so git's own stderr — the realistic carrier, via
  `_gc_run`'s `2>>"$ERRLOG"` and the `gc_report` emit that ships that log — is
  caught by both rules. No identifier is present for a retention window to bound.

So 90 days is not a weakening on either stream. It becomes one on `2734275` the
moment that redaction is narrowed, which is why that is a re-evaluation trigger
above rather than a footnote.

The register now carries the **measured** value per source, and records that
retention is a per-source attribute so a future source cannot be assumed to inherit
it. That is a stronger record than the placeholder it replaces and than the
"NOT RECORDED" that stood in its place.

**3. Materiality and public scope.** The stream stays recorded in PA-8 — not because
it carries an identifier, but because its non-identifiability depends on a redactor,
whose residual is bounded by what has been tested rather than by what is possible.
A stream in that position is recorded, not declared out of scope; that is the posture
PA-8 §(g) already takes for this emitter (#6982).

The two PUBLIC documents **must not** enumerate the second source. Nothing occurs on
the git-data plane: no `soleur-git-data` server exists, and the privacy policy's own
masthead retraction (#6588) says so. Publishing a telemetry stream from a host that
has never been provisioned would re-commit exactly the defect #6588 corrected.
Art. 13/14 require the *recipient* and the *transfer position*; Better Stack is
already named and the recipient set is unchanged.

They **must** still be corrected, for two things that become false on merge: the
region name is stale, and `pinned by per-source ingest URL (https://s2457081…)`
asserted exhaustiveness over an estate that now holds two endpoints.

The internal record is the opposite case. `article-30-register.md` and
`compliance-posture.md` are the Art. 5(2) accountability artifacts and derive the
transfer conclusion from a single source pin; they enumerate both.

**4. Sequencing.** Everything landed before merge — and ForceNew is not the reason.
ForceNew makes the *code* expensive to change after birth; documents are equally
cheap either side of it. The reason is that the false sentences ship on merge whether
or not the host is ever born, and they ship gate-green. Per #7349, none of the five
legal gates would catch any of this: every one compares canonical against mirror, and
two byte-identical copies of a stale region name pass all five.

## What landed

| Ref | Artifact | Change |
|---|---|---|
| MUST-1 | `docs/legal/privacy-policy.md` §5.14 (+ mirror) | processing-location bullet rewritten; retention stated as **90 days**, measured |
| MUST-2 | `docs/legal/data-protection-disclosure.md` §2.3(m) (+ mirror) | source pin rewritten; retention stated as **90 days**, measured, and flagged as per-source |
| MUST-3 | `knowledge-base/legal/article-30-register.md` PA-8 §(e)/§(f)/lawful basis | two sources enumerated; locality withdrawn; retention MEASURED at 90 days per source (superseding #7717's NOT RECORDED); "short retention" withdrawn plane-wide |
| MUST-4 | same file, Better Stack sub-processor row | location cell corrected; dated entry appended |
| MUST-5 | `knowledge-base/legal/compliance-posture.md` | location cell corrected; dated entry appended with both open items |
| MUST-6 | `knowledge-base/legal/data-processing-agreement-template.md` §11.1 + Schedule 2 | region and purpose corrected |
| S-1 | `knowledge-base/legal/audits/2026-08-counsel-review-7440.md` | erratum APPENDED, body not amended (a dated record is append-only) |
| S-2 | `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | second source documented; region aliasing recorded; the "single source" sentence corrected |

> **Amended during implementation — MUST-1(a) and MUST-2(a) dropped a literal a shipped
> gate requires.** The ruling directed dropping the pinned ingest URL from the two public
> documents, reasoning that it "asserts exhaustiveness over an estate that will contain two
> endpoints". That reasoning stands, but the drafting also removed the source ID `2457081` —
> and `validate-vector-config` (#4293 FR5) parses the sink URI out of `vector.toml` and
> requires BOTH the source id and the cluster string to appear in all six disclosure files.
> CI caught it. This ruling's own "Gate mechanics for the implementer" section listed four
> gates and did not include this one, so the instruction was incomplete rather than wrong.
>
> Resolved by restoring `2457081` to both public documents (and both mirrors) **as the source
> for THIS stream**, with an explicit sentence that naming it is not a claim it is the only
> source on the account. That satisfies the drift control and keeps the exhaustiveness fix the
> ruling actually wanted. Both literals verified present in all six files against the gate's
> exact predicate.

Both public mirrors were edited byte-identically and `legal-doc-shas.ts` re-pinned.
Gates run from the worktree root: `check-tc-document-sha.sh` rc=0,
`lint-legal-mirror-drift-baseline.sh --base origin/main` rc=0 (drift within baseline,
not grown), `lint-legal-scope-block-placement.sh --base origin/main` rc=0 (0 blocks
classified — the added lines carry none of the gate's cloud markers, verified against
`--print-vocab`, so this is a correct non-classification and not an unchecked
referent).

## Open, tracked, not blocking

One issue carries both limbs — **#7825**:

1. Execute the Better Stack Vendor DPA, or record the specific published terms relied
   on as the Art. 28(3) "other legal act", with date and mechanism. This is the AC15
   escalation the compliance-posture row has directed since 2026-08-13 and which was
   never filed.
2. Obtain a written vendor statement of the physical processing location and of
   EEA-only support access for `data_region eu-central-1a`, routed via
   `knowledge-base/legal/recommended-tools.md#vendor-msa-review`.

The single question reserved for qualified counsel:

> Does Better Stack's `data_region eu-central-1a` entail EEA-only storage **and**
> EEA-only support access, such that Chapter V is not engaged?

That is a vendor-terms question, not a drafting question, and it cannot be resolved by
reading this repository. Everything else in this ruling is ruled in-house and is final
for v1.
