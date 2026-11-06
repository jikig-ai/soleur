Ref #11857. Ref #10205.

## What this does, and the worst case

The nightly drift scan reads Doppler through one read-only token per config. Live Doppler has 16 configs; the scan only covers 13. This adds the three missing ones (`prd_git_data`, `prd_workspaces_luks_marker`, `prd_workspaces_luks_web`) and raises the "at least this many" floor from 13 to 16, so a scan that silently covers fewer than all 16 shows up as degraded instead of green.

Worst case: the three new tokens can read every secret in the `prd` config plus each branch's own secrets, and that includes the disk passphrases for the volumes that hold customers' repositories and workspaces, and the escrow credentials for their headers. All 16 tokens sit in one repository-level secret that any developer who can push a workflow branch to the repository could read; that was already true for the 13, and it is an accepted residual here (scoping the secret to a protected environment is the follow-up, not done in this PR). Revoking a token afterwards stops future reads but cannot un-read a passphrase: a leaked disk passphrase needs a header re-key or a volume cutover. The tokens are read-only and each is limited to one config (a test now pins that), the values never appear in the plan output or logs, and a half-finished mint fails loudly (the scan reports `degraded 13/16`) rather than silently covering less.

Nothing has been applied, dispatched or minted by this PR. It is a draft and unarmed.

## Needs you

- Approve the mint by merging this pull request with `gh pr merge 12100 --squash`. Merging starts the infrastructure apply, which creates three Doppler read tokens and republishes the drift-scan secret. (operator: production-mutating)

## What the agents already decided

- The CTO agent ruled that all three configs get a token, with no carve-out for the marker config (it holds no unique secret but reads the full `prd` root, so it is as sensitive as the others).
- The CTO agent ruled against the dependency edge to `git_data_prd` that the issue asked for: that config is applied by hand, and an edge from a per-merge token would pull it into every merge's plan and could break every later infrastructure merge. The edges to the two workspaces configs, which are already in the per-merge targets, are added, and a new test pins both halves.
- The CPO agent said no sign-off beyond your merge is needed; the user-impact and security review seats ran and found no blocking issue.
- Fixed from review: a test now pins `access = "read"` on the token; the blast-radius text in the code and plan was corrected (sixteen tokens, the branch-workflow vector, the marker token); the ADR now lists the exact edits a revocation needs (floor, run-time check, inventory-removal acknowledgement, `[ack-destroy]`).
- Known and unverified, recorded in the plan: whether a crash between Doppler creating a token and the state write leaves an orphan token or blocks the retry (checked by the CTO agent's post-merge step: list tokens per config, expect exactly one each, and confirm all 16 config names exist). A failed apply blocks later infrastructure merges until a fix-forward PR; a retry only helps transient causes.

## What merging does

- Starts the infrastructure apply (plan shape: 3 creates and 1 in-place update of the drift map secret).
- Until the map is republished a drift scan that runs in that window reports `degraded 13/16`; normally that is minutes and usually no scan runs.
- Does not change the app or any running host.

## Verification (local, hermetic)

- `token-drift-workflow-causes.test.sh` 402/402; `terraform-target-parity.test.ts` 359 pass (new ordering row mutation-proven with 6 mutants); `check-cloudflare-token-drift.test.sh` 98/98; `terraform fmt -check`, ruling gate, guard-contract and infra lints green.
- The affected-index ratchet exits 1 on a duplicate accept row in `scripts/ci-pr-affected-audit.accept.tsv` and 25 new-pair entries; none involve this change's paths (not caused by this PR; not verified on a clean `main`).
- `terraform validate` was not run (no initialised provider cache; remote state reads are out of bounds here).
- The only workflow that runs on this PR and touches production state is `infra-validation`'s `plan` job (read-only `terraform plan`, posts a comment). Apply workflows run only on push to `main`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
