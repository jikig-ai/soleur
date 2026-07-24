# Decision Challenges — #6897 ledger re-home + legal reconcile

Headless one-shot: taste / user-challenge decisions surfaced by the plan-review panel
(architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer). Recorded here for the
operator; `ship` renders these into the PR body + files an `action-required` issue. The plan's
default direction is retained (operator's stated direction is the default).

## UC-1 (User-Challenge) — Must #6897 close at all, or stay open as the umbrella bound?

**Challenge (code-simplicity-reviewer):** the minimal-correct answer might be **0 new issues** —
leave #6897 OPEN as the residual-teardown bound, since it already bounds all 8 exceptions. Closing
it is what forces the re-home + new-issue cost.

**RESOLVED (operator, 2026-07-24): KEEP #6897 OPEN — 0 new issues, net-issue-flow = 0.** When the plan
surfaced that closing #6897 orphans the exceptions and grows the backlog +2 (opposite of "draining"),
the operator chose to keep #6897 as the umbrella homing these *ongoing* bounded exceptions (they are
not one-time fixes). Phase 1 (tracker creation) and Phase 2 re-homing are CUT; the ledger/C4 `#6897`
refs stay. The PR is `Ref #6897` (not Closes) + the legal reconciliation + a read-only ledger
verification. This supersedes the task's original "`Closes #6897`" framing.

## UC-2 (Taste) — Issue count — MOOT (superseded by UC-1 resolution)

The 3-vs-4-vs-parents question is moot: **0 issues are filed** (UC-1 resolved to keep #6897 open). No
teardown/posture/zot trackers are created; #6897 continues to bound all residual exceptions.

## UC-3 (User-Challenge, RESOLVED by operator 2026-07-24) — the legal over-claim: qualify now vs. hold for teardown

**Finding (legal-compliance-auditor, Phase 3):** a **material over-claim** (the #6588 P1 class). The
published legal docs (`privacy-policy.md:298,519`; `gdpr-policy.md:44`; `data-protection-disclosure.md:189,276`
+ the three "Last Updated" changelog notes + all Eleventy mirrors) assert, unqualified, that "stored
workspace git data sits on a **LUKS-encrypted volume (encryption at rest)**." That is true of the LIVE
store (web-1 `/mnt/data` on the `workspaces_luks` mapper, cutover 2026-07-23) but reads as *all copies
encrypted*, while two **attached plaintext ext4 backstop volumes** (`hcloud_volume.workspaces` server.tf:1569,
`hcloud_volume.git_data` git-data.tf:196) still hold pre-cutover copies of that data on seizable Hetzner
block volumes. Seizing a backstop yields plaintext → the "(encryption at rest)" completeness claim is
currently over-stated. API-key AES-256-GCM + TLS-in-transit claims are SUBSTANTIATED.

**Two remediation paths (auditor):**
- **Path 1 (infra):** run the DL-2 wipe + detach/destroy the backstops → the existing wording becomes
  unconditionally true, no doc edit. **UNAVAILABLE now** — operator set zero-live-infra-mutation and
  `git_data` is the deliberate rollback backstop *pending* DL-2.
- **Path 2 (wording):** qualify the published claim — scope to the live store + disclose the retained
  backstop. Proposed (preserved for teardown-time if wording is chosen later): *"stored **live** workspace
  git data sits on a LUKS-encrypted volume (encryption at rest) (a superseded pre-cutover plaintext volume
  is retained only as a rollback backstop pending secure teardown)"*.

**RESOLVED (operator, 2026-07-24): HOLD the legal fix.** Do NOT edit published legal copy in this PR.
The over-claim is pre-existing and is cured by **Path 1** when the backstop teardown lands — which is
already tracked by #6897 (stays open) and the ledger rows' `reevaluate_when` (`hcloud_volume.workspaces`:
workspaces_luks cutover confirmed irreversible → detach+destroy; `hcloud_volume.git_data`: git_data_luks
cutover confirmed → DL-2 wipe). #6897's legal-recon checkbox stays open, bound to that teardown. This
overrides the plan's "material over-claim MUST be folded inline" default — recorded here as an explicit,
auditable operator decision. If the teardown slips materially, revisit Path 2 (qualify the wording).

## Note — plan-time sign-off is CLO, not CPO (fixed contradiction)

The threshold is `single-user incident` (legal-claim-vs-reality axis, the #6588 blast radius), but
Product = NONE (zero UI). The plan-time domain sign-off is therefore **CLO** (legal), not CPO
(product); `user-impact-reviewer` runs at review time per the threshold. The original
`requires_cpo_signoff: true` frontmatter contradicted Product=NONE and was corrected.
