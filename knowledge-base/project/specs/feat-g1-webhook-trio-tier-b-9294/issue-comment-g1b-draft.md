<!-- DRAFT for #9294. Not posted: the owner approves the comment. -->
## G1b is tracked here, as a separate window (Ruled by CTO agent, 2026-10-12)

Scope added to this issue, from the CTO ruling above and measured on `origin/main` on 2026-10-15:

- **What:** the SSH trio, `DEPLOY_SSH_PRIVATE_KEY` (`tls_private_key.ci_ssh`, also in Tier-A-readable state) and `CI_SSH_ACCESS_TOKEN_ID` / `_SECRET`, read by `.github/actions/cf-tunnel-ssh-bridge/action.yml`. It is a second branch-to-root chain on web-1, and ADR-241 did not classify it (the D1 census above now records it).
- **When:** not in the same window as any step of the webhook-trio chain: the SSH bridge is the recovery path if a webhook rotation strands web-1.
- **Blocks:** #8609, alongside the rest of G1.

The webhook-trio plan is `knowledge-base/project/plans/2026-10-15-feat-g1-webhook-trio-tier-b-plan.md` (PR #10376). PR-0 of that chain adds the census and the expiring baseline (`tests/scripts/test-trio-baseline-census.sh`, `tests/scripts/trio-baseline.tsv`) and the ADR-241 amendment of 2026-10-15; it changes no behaviour.

Refs #9294
