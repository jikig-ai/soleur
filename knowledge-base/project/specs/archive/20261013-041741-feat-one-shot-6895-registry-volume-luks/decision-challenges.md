---
title: "Decision challenges — feat(#6895) registry volume guest-side LUKS"
issue: 6895
---

# Decision challenges — feat(#6895)

## D4 guarded `registry-luks-recut` dispatch deferred to follow-up

**Operator's stated direction.** Scope this PR to **cloud-init + Terraform + ledger flip only**
(the guest-side LUKS apparatus for `hcloud_volume.registry` + the ledger row flip
`plaintext-exception → luks`). The guarded `registry-luks-recut` `workflow_dispatch` (plan D4(ii))
is explicitly OUT of scope for this PR.

<!-- lint-infra-ignore start -->
<!-- Deferred-orchestrator prose: the paragraphs below describe the SANCTIONED gated operator recut
     (an OPERATOR_APPLIED_EXCLUSION `-replace` / the deferred guarded dispatch #6929) that runs
     OUTSIDE any per-PR apply — not a human-run step this PR executes. -->
**Architecture reviewer's counter-argument.** The guarded three-`-replace` dispatch removes a
load-bearing operator **footgun**: without it, the only recut path is a bare, error-prone
`terraform apply -replace` of volume + attachment + host *together*, and the operator can easily
reach instead for the existing `registry-host-replace` dispatch — which **preserves** the plaintext
volume and boots it straight into the D1/B `blkid TYPE` else→FATAL refuse arm, darking the registry.
Adding the guarded dispatch is code-only (unfired ⇒ zero live mutation), so the footgun-removal
argues for including it in this PR.

**Resolution — DEFERRED.** The dispatch is deferred to a follow-up tracking issue (the operator
scoped this PR to cloud-init + Terraform + ledger). The floor holds regardless:
- The **D4(ii) tracking issue** is filed with re-evaluation criteria + the "Phase 4: Validate + Scale"
  milestone (`Tracks #6929`).
- The **"wrong-dispatch (`registry-host-replace`) = FATAL" footgun** is flagged prominently in **both**
  the PR body **and** the ADR-096 amendment (this PR), so the hazard is recorded even though the
  guarded vehicle that would eliminate it lands later.
- The sanctioned `OPERATOR_APPLIED_EXCLUSION` three-`-replace` apply remains the interim recut vehicle
  until the guarded dispatch ships.
<!-- lint-infra-ignore end -->
