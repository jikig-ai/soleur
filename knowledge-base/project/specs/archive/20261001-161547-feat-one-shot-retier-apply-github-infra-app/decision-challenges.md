# Decision challenges: feat-one-shot-retier-apply-github-infra-app

This file comes from headless (one-shot) planning. It records taste and user-challenge decisions for
`ship`, which renders them into the PR body and files them as an `action-required` issue. Every
entry keeps the recorded direction as its default; nothing here was applied against it.

## DC-1: Deleting `board-status-sync.yml`'s dead legacy soleur-ai arm (not adopted)

- **Class:** user-challenge. It adds a third workflow to a scope the operator stated as
  `apply-github-infra.yml` plus `apply-web-platform-infra.yml::entrypoint_audit`.
- **Adopted:** leave `board-status-sync.yml` untouched. Census G4e moves to an exact `== 1`, whose
  one member is that arm. The arm keeps refusing the `EVICTED_SEE_ADR_241` sentinel with
  `verdict=legacy_app_key_evicted`.
- **Alternative (DHH plan review, P0):**
  - After O10 the legacy branch can only ever hit the sentinel refusal. Its runs are green only
    because `soleur-board` mints first.
  - Deleting it would turn G4e into "zero readers of `GITHUB_APP_PRIVATE_KEY` anywhere": an
    absence check with no stored pin.
  - Once the Doppler name is gone, the row could retire.
  - The cost is one more `.github/workflows` file in the PR, still UNTRUSTED-CI. A missing board
    pair would then fail with "board App pair missing" instead of the sentinel verdict.
- **Revisit when:** the operator wants the soleur-ai key name gone from every CI path, or the P1
  bypass-actor follow-up lands and #8209 O13 deletes the `prd_terraform` App key.
