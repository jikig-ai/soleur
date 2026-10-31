# Evidence - feat-one-shot-post-merge-leftovers-npm-tally

Work-phase scratch record. The durable copy is the live PR body (`ship` neither reads nor keeps this file).

## npm Publish root cause

- Root cause: the npm-side trusted-publisher entry for `@soleur/opencode` does not exist. With the OIDC wiring from the earlier switch in place, `npm publish` attempts the exchange, npm swallows the failure at verbose log level, and the step dies `ENEEDAUTH`. Latest failing run: 41181530366 (head `d1fa52f922`). The run on `0ca85fb1f7` (41141302808) was still the old workflow and failed `E404` from the expired `NPM_TOKEN`.
- Excluded from the logs: npm CLI too old (step installs `npm@^11` fine), missing `id-token: write` (present on the job), `NODE_AUTH_TOKEN` / `registry-url` interference (removed).
- Fix in this PR: a failure-only step that replays the exchange and prints one `NPM_OIDC_VERDICT=` line with the values the entry must carry, plus a runbook (`knowledge-base/engineering/operations/runbooks/npm-publish-trusted-publisher.md`) and an ADR-310 amendment. The leg stays red until the entry exists (no soft-skip). Tracked in #11633; this PR uses `Ref #11585` and `Ref #11633`, never `Closes`.
- Automation ladder (read-only up to the authorization gate):
  - (a) `npm trust list @soleur/opencode` with the stored token via `doppler run -p soleur -c prd`: `npm error code E401` (401 Unauthorized on `GET /-/package/@soleur%2fopencode/trust`), as expected for a bypass-2FA token. No token value recorded.
  - (b) playwright-attempt: navigated https://www.npmjs.com/package/@soleur/opencode/access; reached the npm sign-in page (redirect to `/login?next=...`); no maintainer session exists in this profile and Doppler holds only `NPM_TOKEN` and `NPM_RECOVERY_CODES`, so password plus 2FA is a human gate. The entry-creating click was not taken (it needs the owner's explicit authorization, decision row T-OP1).
  - (c) `NPM_RECOVERY_CODES` not consumed.
- The one remaining owner step: `npm trust github @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur --allow-publish`, then `gh workflow run npm-publish.yml --ref main`.

## Infra Validation status

- Green on main at `d1fa52f922`: https://github.com/jikig-ai/soleur/actions/runs/41181409788 (2026-10-31T07:38Z). Also green on `6a6cdc0c07`, `0ca85fb1f7` and `85079f73e0`.
- The reported 4/4 red was run 41125333864 (head `f60979559a`, 2026-10-30T20:42Z): `cloud-init pin (v1.1.67) matches latest vinngest-v* tag merged into HEAD (v1.1.68)`. The bot bump `85079f73e0` closed that window. It recurs on every new `vinngest-v*` tag until the bot bump PR merges, so it is a known transient window, not a defect to patch here (CTO ruling R3: no edit to bot-owned pins, no tolerance added).
- One other red: `f532fb99d8` shard 2/4, `cron-egress-nftables.test.sh` rc=124 (361s); a one-off, cause unverified, nothing filed unless it recurs.

## Tally reconciliation

| Source | seats | ci_cycles | fix_rounds | agent_rounds |
|---|---|---|---|---|
| Session tally as reported | 83 | 15 | 1 | 12 |
| Merged PR #11622 body (rendered before merge) | 19 | 1 | 2 | 4 |
| Ledger of the PR's own branch (`feat-one-shot-11569-11572-messages-update-policy-708df7`, last write 2026-10-30T22:06Z) | 19 | 2 | 2 | 4 |
| Ledger of branch `main` (`main-88d050`, last write 2026-10-30T18:43Z, before the 22:54Z merge) | 83 | 15 | 1 | 12 |

- `83/15/1/12` is byte-for-byte the shared ledger keyed to branch `main`: cumulative across sessions, written before the merge, and not attributable to one run. A sibling ledger also reads `ci_cycles=15`.
- The PR's own ledger is `19/2/2/4`; the merged body `19/1/2/4` is correct on three of four dimensions and read `ci_cycles` before one more increment.
- `gh` shows 10 distinct pushed head SHAs on that PR, which neither figure claims (the tally counts instrumented pushes only).
- Corrected line for #11622: `Pipeline-Tally: seats=19; ci_cycles=2; fix_rounds=2; agent_rounds=4`. The merged PR is not edited (CTO ruling R4).
- Generation bug fixed in this PR: `pipeline-tally.sh` treated `main` as an ordinary per-branch ledger that accumulates forever; default-branch ledgers are now init-scoped and `show` discloses it.

## Production state check (read-only)

Measured 2026-10-31T09:46Z through `doppler run -p soleur -c prd` (`DATABASE_URL_POOLER`, `begin read only`; aggregate counts only) and the read-only Sentry token (bearer on curl's stdin config).

| Source | Status | Count | Baseline 2026-10-30 |
|---|---|---|---|
| github | draft | 1912 | 1903 |
| kb-drift | draft | 45 | 45 |
| any | archived | 0 rows | 0 |

- `archived` is still 0: no founder has used Discard or Dismiss yet. That is expected and not a defect; the count should rise above 0 once one does.
- Sentry Discover query `op:discard-send-race`, 14d window: HTTP 200, 0 events.
