---
title: "Codex Web — owner approval of the existing Soleur contributor account"
date: 2026-10-04
type: clo-disposition
pr: 9051
attestation-authority: clo
signed_off_by: "CLO agent, targeted internal-control review"
disposition: "Authorized attribution correction pushed; automated CLA verification passed"
written_against: "5cb81c9d97196b7e29e4c4436edb26e77785a75e"
correction_against: "2a084f5d667b724ded7cc6b84c8864d6cf0e4a13"
addendum: "Consent and local implementation — 2026-10-04"
scope: "Existing account attribution and CLA exemption mechanism only"
re_evaluation_triggers:
  - "Account control or the owner's approval changes."
  - "Contributions include rights belonging to an external contributor or employer."
  - "A proposal broadens exemption beyond the approved account or reattributes additional historical commits."
---

# Owner approval and existing commit attribution

The operator stated in this session: "soleur is approved, this is basically
us but I'm not sure why deruelle wasn't used for those commits". This is
attributable approval of the existing `soleur` account for this contribution.
It is not the Individual CLA signing phrase, confirmation of every CLA
representation, or an instruction to rewrite historical authorship.

At the reviewed head, these four commits carry both author and committer
`Soleur <soleur@users.noreply.github.com>`:

- `f3eaa36eb21959f09e1a65d1d52c89cbd2c6ab70`
- `8ac23e92745afc18d48343a1982c7016822c622f`
- `36440e42ea445d7462f4a0372d84266835e0ece9`
- `7d92e66335b7ce6b913229b62b07862eb1953ff7`

The historical cause of that identity selection was not established by this
review. The current owner's identity does not retrospectively prove which
configuration or environment authored those four commits.

## Internal disposition and limits

The owner's approval supports treating this controlled account as an
approved maintainer contribution for this review, rather than asking an
automation account to make a natural person's CLA representations. This
records approval of an exemption rationale; it creates neither a signature
nor a licence grant and does not determine ownership of third-party rights.
No signing, author rewriting, account mutation, or CI-policy change was
performed by this review. The automated CLA gate is still pending until an
authorized mechanism is implemented and verified.

> **Superseded 2026-10-04 (PR #9051):** The operator subsequently authorized
> the four-commit correction, and the implementing agent adopted the verified
> rewritten graph locally. The automated CLA gate remains pending; see the
> consent and implementation addendum below. The earlier sentence records
> the initial review's actions, not the later implementation.

Two mechanisms have materially different scope:

| Mechanism | Effect and authorization boundary |
| --- | --- |
| Correct the four historical automation identities to `deruelle` | Selected and explicitly authorized after the initial account-approval statement. Implemented locally with a retained backup and verified unchanged trees, messages, timestamps, topology and unaffected identities; guarded remote update and exact-head CLA CI verification remain pending at this addendum. Uses the existing maintainer exemption without expanding repository policy. |
| Add exact login `soleur` to the existing allowlist | Preserves historical attribution but exempts future contributions by that login. The owner approved this account; an implementation must make the continuing scope clear rather than treating a one-PR approval as an undisclosed policy expansion. It must reach the base branch through a separate reviewed policy PR before PR #9051 can use it. |

> **Superseded 2026-10-04 (PR #9051):** The original correction row said the
> present account-approval statement did not authorize rewriting. That
> finding about the original statement remains accurate; the subsequent
> explicit permission below supplies the missing authorization. The row
> now records that correction's operative status.

## Exact policy and evidence requirements if allowlisting is selected

Change the single quoted `with.allowlist` scalar in
`.github/workflows/cla.yml`, retaining all existing entries and adding only
the exact GitHub login `soleur`; do not match a display name, arbitrary
email, wildcard, or the distinct `soleur-ai[bot]` principal.
Update `SAMPLE_CLA_YML_ALLOWLIST` and the expected parsed list in
`apps/web-platform/test/cla-evidence/allowlist.test.ts` in the same change.
Its exact-set assertion deliberately rejects one-file policy drift. Keep
the negative unknown-login and GitHub Actions DB-ID controls intact.

No duplicate allowlist or parser change is required:
`apps/web-platform/scripts/cla-evidence/build-bypass.ts` reads the tracked
workflow and delegates to `allowlist.ts`'s `parseAllowlistLine()`. Preserve
the quoted scalar format and the base-ref checkout in
`.github/workflows/cla-evidence.yml`. The workflow uses
`pull_request_target`; putting an exemption only on the governed PR head
cannot clear its own gate. Do not bypass that invariant.

The evidence sidecar's `ACTOR_LOGIN` and `ACTOR_ID` come from
`github.event.pull_request.user`, not commit authors. PR #9051 is authored
by `deruelle`; adding `soleur` does not make this PR produce a quarterly
`soleur` record. Preserve the existing evidence workflow and its archive;
do not manufacture a signing record or claim a new `soleur` bypass record
was written without observing a qualifying event and upload result.

The general archive semantics are verified against `allowlist-bypass.ts`'s
`buildBypassRecord()` and `bypassRecordKey()`. The prior internal bypass
ruling at `2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` is
fact-specific to measured nil evidence loss during an outage; it is not
blanket authority to bypass this PR's failing CLA gate. The Convergence
correspondence's prohibition on allowlisting external contributors instead
of recording their grants remains applicable to that external-contributor
case; the present review does not amend it.

## Remaining Codex Web gates

This disposition has no bearing on API credentials, managed-auth
permission, spend enforcement, vendor terms, transfer assessment, live
qualification, authenticated screenshot QA, deployment, or flag exposure.
The PR remains draft and the feature remains default-off under the existing
qualification record. This is an internal v1 CLO review, not external
counsel's opinion or the operator's execution of a CLA.

## Consent and local implementation — 2026-10-04

The operator answered **"yes"** to this exact question:

> To clear the CLA attribution mismatch without changing repository policy,
> may I correct only the four Soleur-attributed commits on PR #9051 to
> deruelle? I'll preserve a backup, verify unchanged file contents, and
> update this draft branch with a guarded force-push. This makes no CLA
> signing statement.

That consent authorizes the specific attribution correction and guarded
branch update. It does not authorize adding an account to the repository
allowlist, signing a CLA, or asserting unconfirmed CLA representations.

The implementing agent reports preparation in an isolated scratch clone,
independent verification of the rewritten commit graph, and local adoption
using compare-and-swap `update-ref`. The retained backup is
`backup/codex9051-cla-5cb81c9d`, pointing to original head
`5cb81c9d97196b7e29e4c4436edb26e77785a75e`. The adopted local head is
`2a084f5d667b724ded7cc6b84c8864d6cf0e4a13` before committing this addendum.

Exactly the four named commits' author and committer identities were
corrected to the existing `deruelle` identity. The resulting mapping is:

| Original commit | Corrected commit |
| --- | --- |
| `f3eaa36eb21959f09e1a65d1d52c89cbd2c6ab70` | `f781df49259b8cc9da518f69be2ba9067f5afa5b` |
| `8ac23e92745afc18d48343a1982c7016822c622f` | `67260db3fab8e7607e35e82226da502468efa614` |
| `36440e42ea445d7462f4a0372d84266835e0ece9` | `44afb7eeb35ed6cd2ef0637b3c45faa0a8d84b5e` |
| `7d92e66335b7ce6b913229b62b07862eb1953ff7` | `da2e40aab2dd917119289b55089771cde3f242d4` |

The implementing agent's verification reports 31 descendant commit IDs
changed through the rewrite, with all trees, messages, timestamps and
parent topology preserved, and no additional identity changes. This CLO
addendum records that verification report; it does not claim to have
repeated the graph comparison or run local suites.

At this addendum, the correction is implemented locally. Remote adoption
through the authorized guarded force-push and exact-head automated CLA
verification are still pending. No repo-policy expansion, CLA signature,
provider authorization, qualification approval or production-write
authorization follows from this consent.

## Remote verification — 2026-10-04

The guarded update from original head `5cb81c9d97196b7e29e4c4436edb26e77785a75e`
to `384a9ad761afeb4d188018c0f12c25b0955f9558` succeeded after the correction
and evidence commit. The [CLA Assistant run 37201350251](https://github.com/jikig-ai/soleur/actions/runs/37201350251)
completed with `success` on that exact pushed head. This supersedes the earlier
pending local/remote verification findings for this correction. No signing
statement or repository allowlist change occurred. Later commits require their
own exact-head verification; this finding does not discharge Codex mode or
promotion gates.
