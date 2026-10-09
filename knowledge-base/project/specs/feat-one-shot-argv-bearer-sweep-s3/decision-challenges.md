# Decision challenges: argv-bearer sweep S3 (headless plan run, 2026-10-09)

Taste and user-challenge items from the plan-review panel and the CPO. Each states the default the plan took and the alternative the lead may choose. None blocks the work phase.

## 1. `workspaces-luks-cutover.yml` is held back to S4 (user-challenge)

- Brief: S3 owns workflow YAML that cannot fire production on merge; this dispatch-only file is in that class.
- Finding (measured on a scratch conversion): adding `--disable --noproxy '*'` to its one Hetzner read reddens 5 rows and the 107-assertion floor of `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh` (curl stub exits 64 on unmodelled flags). That suite is under `apps/web-platform/infra/**`, so editing it fires the production push apply, the web release and `infra-validation`.
- Default taken (A): hold the file back, file an issue with owner and deadline (S4, operator notice), S3 has zero apply exposure.
- Alternative B: convert it and edit the stub; accepts the production apply on merge (operator notice, post-merge outcome check). The last test-only infra edit (S2) applied with no resource changes.
- Alternative C: convert it inline with `--config -` only (stub-compatible, zero infra edit), without the two confinement flags and without the library guard; a weaker form for one Hetzner call whose token is `HCLOUD_TOKEN_READONLY` first with a read/write fallback until ADR-241 O10.

## 2. `canary-status.yml` stays in S3 with a plain checkout (user-challenge)

- Review (DHH): hold this dispatch-only file back too; it is the most expensive site (a hardened `permissions: {}` job gains a checkout and the HMAC move).
- Default taken: keep it in S3 (lead-listed scope), plain `actions/checkout`, `persist-credentials: false`, `contents: read`.
- Alternative: hold it back with item 1, or convert it inline (the S2 pattern) with a parity row.

## 3. HMAC moves kept as `inferred` (taste)

- The two `openssl dgst -hmac` keys on the converted calls (canary-status, inngest-health probe) are outside the literal brief ("curl's argument list"). Default: convert them (a header-only conversion leaves the same call half-fixed). Alternative: leave both to S4 with the other five `-hmac` sites.

## 4. Optional extra proofs that need the lead's go (taste)

- A temporary `pull_request` job that prints `bc_ok` pass/fail per GitHub-only secret (Resend, Anthropic, Sentry, CF Access), added in a throwaway commit and dropped before the PR is marked ready. Default: not run; rely on vendor formats, the live `sentry-audit-gate` run and the visible `::error::` annotation on refusal.
- An active alert-path positive control (one-off dispatch of the composite to the operator's own address). Default: passive first-run table with owner and deadline (merge + 3 days), then this control or a revert of the composite commit.
- A read-only `canary-status.yml` dispatch on the branch (touches the production deploy host). Default: not dispatched.

## 5. `rule-audit.yml` anonymous-token conversion kept (taste)

- Review split: DHH would leave it in baseline E with a comment; the simplicity seat kept it trimmed. Default: convert (ratchet row leaves, no dedicated slice row).

## 6. Plugin release fires on merge (flag, not a challenge)

- The one test-file edit under `plugins/soleur/test/` triggers `version-bump-and-release.yml` (calls `reusable-release.yml`). Not a web deploy. Alternative to avoid it: none found that keeps `heartbeat-reconcile-issue-step.test.sh` green without editing it.

## 7. The scheduled-inngest-health `probe` step is also held back (user-challenge, found at work time)

- Brief: S3 owns `scheduled-inngest-health.yml` (the Better Stack stderr item and the file's three argv sites).
- Finding (measured): converting the `probe` step (HMAC key off `openssl`'s argv, signature and Cloudflare Access pair onto `bc_curl`) reddens 12 rows of
  `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh` (it executes the real step in a fake workspace with no library and a stubbed `openssl`
  and `curl`; the pre-guard records `secret_unset`). That suite is under `apps/web-platform/infra/**`, so editing it fires the production push apply.
- Default taken: revert only the probe step, convert the two census calls and surface the dedicated-host reader's stderr (neither is executed by that suite), and
  hold the probe step (1 Rule E site and its `openssl -hmac`) for S4 with operator notice. The file therefore stays in baseline E with 1 site (not removed).
- Alternative: convert it and edit the infra suite (an `apps/web-platform/infra/**` edit: push apply, web release, `infra-validation`; operator notice and a post-merge
  outcome check). Not taken because the brief defines S3 as the class that cannot fire production on merge.
