---
title: "chore(cloudflare): Phase 5 token slice - re-mint the old-login read tokens on the Soleur account (Ref #12931)"
date: 2026-11-27
slug: chore-cf-phase5-old-login-token-remint
branch: feat-one-shot-12931-phase5-token-remint
issue: 12931
type: chore
lane: single-domain
domain: engineering
brand_survival_threshold: none
---

# chore(cloudflare): Phase 5 token slice - re-mint the old-login read tokens on the Soleur account

Ref #12931 (epic stays open; never `Closes`). Ref #12937 (release deploys blocked; gates the `CF_API_TOKEN_PURGE_PREV`
revoke). Draft PR #13084. Follow-ups filed at plan time: #13085 (rotate before the ~2027-02-20 expiry), #13086
(`expires_on` warning in the drift script).

## Review Amendments (2026-11-27)

The review round and fix round 1 on PR #13084 produced nine CTO rulings, recorded as D1-D9 in the
`decision-challenges.md` beside the bootstrap (match it by glob,
`knowledge-base/project/specs/**/feat-one-shot-12931-phase5-token-remint/decision-challenges.md`, because archive-kb
moves the directory). Where this plan says otherwise, those rows win: D1 adds the committed browser bodies and their
suite; D2 adds the census floor; D3 removes the drift gate from `verify`; D4 keeps the migration runbook untouched; D5
binds the `_NEXT` token's id and owner into the approved swap plan; D6 routes the state between a revoke and the
`_PREV` delete; D7 adds the user-owned mint and `p5-read.js` and drops the paste fallback; D8 replaces the swap
rollback; D9 adds the `P5-MINTED` record, author-filtered lookups and data-only arguments.

## Enhancement Summary

**Deepened on:** 2026-11-27
**Sections enhanced:** 9 (Runbook mint and revoke, Bootstrap identity and census, Operator Holds, Files to Edit, Guard
Contract, Acceptance Criteria, Observability, Scope table, Tasks)
**Agents used:** `soleur:engineering:review:security-sentinel`, `soleur:engineering:review:test-design-reviewer`,
`soleur:engineering:research:best-practices-researcher` (Cloudflare account-owned tokens, official docs), a
`standard`-tier verify-the-negative and attribution pass, `soleur:engineering:cto` (rulings F20, F21).

### Key Improvements

1. Policy read-back now accepts only exact resource keys (`com.cloudflare.api.account.zone.951ce525...` for zone
   groups, `com.cloudflare.api.account.66d4f93f...` for account groups), so an account-wide zone grant fails.
2. Every browser body returns only names, prefixes, counts and statuses; no trace/HAR/session capture flags; digests
   are compared, never printed.
3. AUDIT lives only where a consumer reads it (prd_terraform, dev); its other two old copies are deleted by hold
   (CTO F20). New tokens are named `<key>-soleur-<YYYYMMDD>` and the revoke refuses a name match (CTO F21).
4. The infra-security agent has three generated harness copies; the work phase regenerates them with the three sync
   scripts and checks them with `--check`.
5. The Guard Contract rows now name the code mutant each kills and assert refusal text; the `swap` order is observed
   inside the write window by a logging stub.

### New Considerations Discovered

- Cloudflare docs list the account-token endpoints, `expires_on` and IP conditions, and open account-token creation
  to API Token Provisioning members since 2026-10-01; they do not say whether zone groups are selectable on an
  account token or whether GraphQL accepts one. The mint sitting's permission-group read and the post-swap
  zone-tag query settle both.
- The audit-log endpoints accept Account Settings Read, per the Cloudflare permissions reference.
- Every cited issue, PR, rule id, learning path and label resolved live (verify pass, 2026-11-27).

## Overview

Epic #12931 moved the soleur.ai zone to the Soleur Cloudflare account. Six user tokens owned by the old-account
login remain (#12931 comment 7205049710). This plan prepares the replacement procedure for three of them (the audit,
analytics-read and page-rules-read tokens), records where the Origin CA and R2 tokens live, schedules the
purge-backup revoke for its runbook step, keeps the R2 token, and records the repository-secret gap the 0a revoke
left open. The work phase runs only reads and repository edits. Every mint, Doppler write and revoke is an
`Operator-authorizes:` hold, run after merge from `main` through a staged bootstrap.

This is the **token slice** of migration runbook Phase 5 only. The rest of Phase 5 (deleting the migration machinery,
legacy-account object deletes, ADR-329 flip) waits for Phase 3 verification, which needs open draft PR #12958 (tunnel
re-home) to merge and the release redeploy that #12937 blocks. This plan does not duplicate #12958 and does not edit
the migration runbook (CTO F1).

**Revision note (plan review, 2026-11-27).** The first draft carried a seven-stage bootstrap (whole-config census,
pre-swap probe with old-zone negative controls, separate `prev`, `drop-prev`, PURGE handling). The simplicity panel
(DHH, code-simplicity) and the correctness panel (Kieran, advisor, sharp-edges pass) fired on the same mechanisms, so
the rule "prefer delete over fix" applied. The old tokens already fail on the new zone, so a pre-swap probe protects
nothing that a post-swap `verify` does not, and a 403 on the `status=moved` old zone proves nothing. CTO re-rulings
F2' and F9'-F19 (decision-challenges.md) set the four-stage shape below.

## Research Reconciliation - Spec vs. Codebase

| Claim (source) | Reality (measured 2026-11-27, no value printed) | Plan response |
|---|---|---|
| Origin CA token holder "not yet located" (migration runbook Phase 5) | `soleur-infra-privileged/prd` `CF_API_TOKEN_ORIGIN_CA` verifies `success=true id=34acd675 status=active expires=none` | Recorded in the new runbook. Its re-scope stays at migration runbook Phase 3 step 4, owned by #12958 (CTO F7). |
| R2 token "held as an S3 key pair, outside the search" (Phase 5; comment 7205049710) | `soleur-infra-privileged/prd` `CF_API_TOKEN_R2` verifies as a user token, `id=bb4a334a status=active expires=none` | Recorded as located. It stays: the old account keeps R2 (ADR-329). |
| "Not yet read: each token's zone and account scope" | Functional reads on the new zone/account: `pagerules-ssl` -> `unverified - token-lacks-scope`; `change-history` -> `unverified - token-lacks-scope`; `analytics-health 1` -> `unverified - api-error`. Permission groups still unread. | All three need a re-mint. Permission groups are read at the mint sitting from the dashboard session (CTO F6, F17). |
| `GET /certificates?zone_id=` could show the Origin CA token's scope | It answers `success=true count=0` for the new zone, the old zone and an all-zero zone id | Not a scope instrument; recorded so no later step reads it as one. |
| Search for holders covered "only `CF_*TOKEN*` keys in project `soleur`" (comment 7205049710) | Names-only census of all nine Doppler projects the operator identity lists: `CF_API_TOKEN*` names exist only in `soleur` (16 configs) and `soleur-infra-privileged/prd` (`CF_API_TOKEN_ORIGIN_CA`, `CF_API_TOKEN_R2`) | The narrow census covers every project by name; values under other names are accepted as unseen (CTO F2' dissent: the token is dead after the revoke). |
| Sweeper comment: "These GH secrets do not exist yet" (`scheduled-followthrough-sweeper.yml`, split across two comment lines) | Repo secrets `CF_API_TOKEN` and `CF_ACCOUNT_ID` exist, both updated 2026-11-02 (before the move) | Correct the comment; leave the values (CTO F3); precondition recorded on #12983. |
| `infra-security.md`: ids "canonical source: `apps/web-platform/infra/main.tf`", old zone and account ids hardcoded | `main.tf` holds no ids; Doppler prd_terraform holds the new ids (`951ce525`, `66d4f93f`); Doppler `dev` holds `CF_ZONE_ID` (new) but no `CF_ACCOUNT_ID` | New literals, with the migration runbook's id table named as the source (CTO F19); token verify gains the account endpoint (CTO F17). |
| `cloudflare-readonly.sh` header: the analytics token "expires 2027-02-07" | True of the pre-move token only | Make the header expiry-agnostic (read `expires_on` from the verify answer). |

## Research Insights

**Premise Validation (Phase 0.6).** #12931 is OPEN (no structured HOLDS list); #12937 is OPEN ("Web Platform Release
blocked at the zot mirror"); #12983 is OPEN (Load Balancing decision); PR #13080 MERGED 2026-11-27T10:42:37Z; draft
PR #13084 is this branch. Collision pre-check: #12931 -> PR #13084 (this) and PR #12958; #12937 -> PR #12958.
#12958 (draft, "re-home the CF tunnel and Access gate") owns Phase 3 and edits the migration runbook,
`scripts/check-cloudflare-token-drift.sh`, `scripts/lib/test-affected-paths.sh` and both suite TSVs. This plan takes
no item from #12958's scope. Its only shared files are the three registry files (additive rows about 330 to 2,600
lines from #12958's hunks, measured by the CTO with `gh pr diff 12958`, ruling F11).

**Property List (Phase 0.6b).**

- P1. Each of `CF_API_TOKEN_AUDIT`, `CF_API_TOKEN_ANALYTICS_READ`, `CF_API_TOKEN_PAGERULES_READ` answers its
  consumer reads on the new zone or account.
- P2. Before an old token is revoked, no config of any Doppler project the operator identity lists holds that old
  value under the key's own name outside prd_terraform `<KEY>_PREV`, checked by value digest and verify id, never by
  key name alone. After the revoke, the full drift run finds no DEAD `CF_API_TOKEN*` copy.
- P3. The old value sits in `<KEY>_PREV` before `<KEY>` is overwritten, so the revoke reads the old id, never the new.
- P4. No token value is printed, put in argv, or written to a git work tree at any step.
- P5. The Origin CA and R2 token holders are recorded with verify ids; the R2 token is kept.
- P6. `CF_API_TOKEN_PURGE_PREV` is revoked only at migration runbook Phase 3 step 5, after the release redeploy.
- P7. The GitHub `CF_API_TOKEN`/`CF_ACCOUNT_ID` repo-secret gap is recorded with the condition that ends it.
- P8. Every production act runs only on the operator's typed go naming the exact command.
- P9. The old zone is never mutated; no gh-pages cert reissue with `probeOnly:false` runs before Phase 3 step 5.
- P10. The new tokens are not tied to one login where Cloudflare allows it (account-owned), and their expiry is
  tracked (#13085).

**Cut List (Phase 0.6b and plan review).**

- A `--staged` flag on `cloudflare-readonly.sh` -> P1 -> post-swap `verify` runs the real wrapper (CTO F9).
- Extending the archived #12931 bootstrap -> P2, P3 -> a new bootstrap; Phase 5 deletes the old one (CTO F2).
- Terraform `doppler_secret`/`cloudflare_api_token` resources -> P1 -> ADR-130 and no Terraform consumer
  (terraform-architect verdict).
- Repointing or deleting the GitHub repo secrets now -> P7 -> recording the fact covers it (CTO F3).
- Re-minting the Origin CA token here -> P5 -> Phase 3 step 4 owns it (CTO F7).
- Whole-config every-key census (`secrets download` of every config) -> P2 -> the narrow per-key census plus the full
  drift run after the revoke (CTO F2').
- Pre-swap probe and old-zone negative controls -> P1 -> the minted token's policies read back from the dashboard
  (resources must name only `66d4f93f`/`951ce525`) plus post-swap `verify` (CTO F9').
- Separate `prev` stage -> P3 -> folded into `swap`, so the order lives in code (CTO F2').
- `drop-prev` stage and PURGE in the bootstrap -> P2, P6 -> migration runbook revoke recipe step 4 and Phase 3 step 5
  (CTO F14, F15).
- In-flight-run refusal -> none -> no workflow reads these keys (`grep` over `.github/` finds none).
- Root-first inheritance deferral -> P2 -> every manifest holder written explicitly (CTO F16).

**Value-proposition measurement (0.6c).** Not a cost/performance plan; skipped.

**Relevant files.**

- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: `## Conventions` (stdin pipe
  form, no secret on screen), `## Revoke recipe` (steps 1-4), `### 0a and 0b: mint the new-account tokens` (the
  hand-off), `## Phase 5 — cleanup PR (after Phase 3 verification)` (facts and constraints this plan meets).
- `knowledge-base/project/specs/archive/20261120-013510-feat-one-shot-12931-cf-account-migration/bootstrap.sh` (the
  precedent: `copy_secret`, `plain_get`, `digest_of`, `token_chars_ok`, `token_read` which treats only a JSON
  400/401/403/404 with `success:false` as a denial and everything else as `TOKEN_UNREACHABLE`) and
  `tests/scripts/test-cf-account-migration-bootstrap.sh` (the precedent suite: PATH-stubbed `doppler`/`curl`/`gh`,
  fixture git repo, mutation rows proven to land).
- `plugins/soleur/scripts/lib/operator-script.sh` (the library header is the bootstrap contract;
  `soleur_op_list` prints `SOLEUR_BOOTSTRAP_STAGE_DECL stage=<s> class=<c>`) and
  `plugins/soleur/skills/operator-bootstrap/SKILL.md` + `template.sh` (repo root via
  `git -C "$SCRIPT_DIR" rev-parse --show-toplevel`, never a fixed `../` count).
- `plugins/soleur/scripts/cloudflare-readonly.sh`: `pagerules-ssl` (`GET /zones/<zone>/pagerules?status=active`),
  `change-history` (`GET /accounts/<acct>/logs/audit`), `analytics-*` (GraphQL POST; exit 14 on `api-error`); the
  header's "Token binding (no flag, no fallback; CF_API_TOKEN is never used)" block and the `token-invalid`
  interpretation row.
- `plugins/soleur/agents/engineering/infra/infra-security.md` (AUDIT consumer: zone `settings`, `dns_records`,
  `ssl/certificate_packs`, `firewall/rules`; account `/accounts/<id>`, `audit_logs`, `alerting/v3/policies`; the
  "Token health check" line calls `/user/tokens/verify`).
- `scripts/check-cloudflare-token-drift.sh` (`--only <SUBSTRING>`; grades every `CF_API_TOKEN*` key in the configs
  of `apps/web-platform/infra/doppler-config-inventory.txt`; DEAD needs both the user and the account verify
  endpoint to refuse; header: "Branch configs do NOT inherit values from the `prd` root config", measured
  2026-08-02).
- `scripts/followthroughs/ga-lb-pool-soak-6027.sh` (secret presence and shape gate, then NOT YET while Load
  Balancing is off) and `.github/workflows/scheduled-followthrough-sweeper.yml` (the only `secrets.CF_API_TOKEN`
  reader).
- Registration precedent: `scripts/test-all.sh` (`run_suite "tests/scripts/cf-account-migration-bootstrap" ...`),
  `scripts/lib/test-affected-paths.sh` (`AFFECTED_TESTS_SCRIPTS_CF_ACCOUNT_MIGRATION_BOOTSTRAP_PATHS`, glob edge),
  `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` (rows from
  `python3 scripts/regenerate-shard-manifest.py --incremental --write`).

**Institutional learnings.**

- `2026-11-27-a-procedure-written-for-a-future-pr-drew-every-review-finding.md`: overwriting `<KEY>` before the revoke
  read it revoked the NEW token; a names-only check cannot see an old value; delete a key only on a read-back that
  starts `success=false`; a negative finding names its search scope.
- `2026-05-15-token-namespace-divergence-across-secret-stores.md`: same name in GitHub and Doppler does not mean same
  value.
- `2026-07-10-shared-vendor-key-fingerprint-attribution-and-required-iac-secret-apply-gate.md`: sweep holders by value,
  not by name.
- `2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md` and
  `2026-09-09-a-uniform-verdict-across-implausible-inputs-is-the-instrument-not-the-data.md`: a scope error is
  "unknown"; a probe that answers the same for every input (the Origin CA list, a 403 on a moved zone) measures
  nothing.
- `2026-05-19-playwright-click-navigate-auto-snapshot-leaks-modal-tokens.md`: no snapshot or screenshot after
  "Create Token"; the committed `p5-mint.js` (D1) is the only mint form; it hands the value to the local sink by a Node-side `fetch` and returns only names, prefixes and verdicts.
- `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`: a menu ack is not a go.
- `2026-03-21-cloudflare-api-token-permission-editing.md`: editing a token's permissions does not rotate its value.

**External research.** Skipped: strong local precedent (the 0a/0b mint, swap and revoke ran on 2026-11-26 with this
hand-off). Permission-group names are read live at the mint sitting, never typed from memory. Whether every needed
group exists for account-owned tokens is unverified; the read of `/accounts/66d4f93f.../tokens/permission_groups`
at the mint sitting settles it per key (CTO F17).

**CLI verification.** `doppler configs -p soleur --json` returns `name` and `root` per config (measured: `dev`
`root:true`, `dev_personal` and `dev_scheduled` `root:false`); `doppler secrets --only-names -p <p> -c <c> --json`
lists names; `doppler projects --json` lists nine projects (`id`, `name`).
`scripts/check-cloudflare-token-drift.sh` accepts `--only <SUBSTRING>` (its usage line).
<!-- verified: 2026-11-27 source: local CLI --help and live read-only calls -->

**Functional overlap.** No community skill re-mints Cloudflare tokens with Doppler staging; the repo's own
`soleur:operator-bootstrap` covers the delivery shape. Build in-house.

**Architecture.** No ADR or C4 change: ADR-329 (zone resources on the Soleur account, R2 stays) and ADR-130 (no
Soleur token holds API Tokens:Edit; dashboard mint) already decide this; the plan re-homes three read credentials
under those decisions and changes no boundary.

## Implementation Phases

### Phase 1 - read-only evidence (Agent, work phase)

1. Re-run the facts reads (no value printed; ids at most 8 characters): `/user/tokens/verify` id prefix of every
   holder named in comment 7205049710 and of `soleur-infra-privileged/prd` `CF_API_TOKEN_ORIGIN_CA` /
   `CF_API_TOKEN_R2`; `doppler run -p soleur -c prd_terraform -- bash plugins/soleur/scripts/cloudflare-readonly.sh`
   with `pagerules-ssl`, `change-history`, `analytics-health 1` (expected today: `token-lacks-scope`,
   `token-lacks-scope`, `api-error`); the names-only census of all projects.
2. Post the facts on #12931 (one comment, marker line `P5-TOKEN-FACTS`, Ref only), naming each search's scope in the
   same sentence.

### Phase 2 - the new runbook (`cloudflare-old-login-token-remint.md`)

Sections, in this order:

1. **Orient** - for a fresh session: resolve the bootstrap path (`git ls-files --full-name
   ':(top)*feat-one-shot-12931-phase5-token-remint/bootstrap.sh'`, exactly one match, else stop), run
   `--stage inventory`, and map its rows to the next step (for example `<KEY>_NEXT` present and no `<KEY>_PREV`:
   `swap` is next; `<KEY>` new and a manifest holder old: `holder-copies` is next; `verify` `REVOKE_READY`: the
   revoke is next). Which login each sitting needs: the mint sitting a login that can mint on the Soleur account;
   the revoke sitting the old-account-owner login.
2. **Facts** - the six old-login tokens: id prefix, dashboard name, holder(s) with project/config, measured status
   on the new zone, disposition (re-mint / revoke at Phase 3 step 5 / re-scope at Phase 3 step 4 / keep).
3. **Constraints** - quoted from migration runbook Phase 5 plus: never print a value; no SSH; old zone never
   mutated; no gh-pages cert reissue with `probeOnly:false` before Phase 3 step 5; one token per key; expiry equal to
   the 0a/0b expiry read at the mint (about 2027-02-20, CTO F18).
4. **Scope table** - per key: consumer, endpoints read, candidate permission group(s); the reconcile rule: at the
   mint sitting, read the old token's policies (`GET /api/v4/user/tokens`) and the live account permission groups
   (`GET /api/v4/accounts/66d4f93f.../tokens/permission_groups`) in the dashboard session, returning names and
   8-character id prefixes only; re-scope to the new account/zone; trim to the endpoints in this table; post the
   final groups on #12931 (marker `P5-SCOPE`) before minting.
   - `CF_API_TOKEN_AUDIT`: account `GET /accounts/<acct>/logs/audit`, `/accounts/<acct>/audit_logs`,
     `/accounts/<acct>`, `/accounts/<acct>/alerting/v3/policies`; zone `settings`, `dns_records`,
     `ssl/certificate_packs`, `firewall/rules`. Candidate groups (Cloudflare permissions reference): account
     Account Settings Read (the audit-log endpoints accept it) and Notifications Read; zone Zone Settings Read,
     DNS Read, SSL and Certificates Read, Firewall Services Read.
   - `CF_API_TOKEN_ANALYTICS_READ`: `POST /graphql` (`httpRequestsAdaptiveGroups` on the zone). Candidate group: zone
     Analytics Read. Owner mint.
   - `CF_API_TOKEN_PAGERULES_READ`: `GET /zones/<zone>/pagerules?status=active`. Candidate group: zone Page Rules
     Read.
   - The `P5-SCOPE` group set is an allowlist built from this table, never the old token's policies with groups
     trimmed off; the old policies are read only to surface a consumer this table missed. Every group is a Read
     group.
5. **Mint** - account-owned on the Soleur account (`page.evaluate` POST `/api/v4/accounts/66d4f93f.../tokens` with
   the session `x-atok`, the hand-off sink unchanged), named `<key>-soleur-<YYYYMMDD>`, `expires_on` equal to the
   0a/0b expiry. A key whose group the account permission-group list lacks is minted user-owned, recorded on
   #12931. Account-owned creation is open to API Token Provisioning members since Cloudflare's 2026-10-01 change,
   who can grant only permissions they hold; whether zone groups are selectable on an account token and whether
   GraphQL accepts one are unverified in the docs, so the permission-group read and the post-swap zone-tag query
   settle them (a GraphQL refusal on the account-owned ANALYTICS token re-mints that key user-owned).
   **Policy read-back** (CTO F9', tightened by the security review): pass only if every resource key is exactly
   `com.cloudflare.api.account.zone.951ce525552201ec6c696b24251abed7` (zone groups) or
   `com.cloudflare.api.account.66d4f93f7397f196544e9fe84c3557c2` (account groups, AUDIT only), with value `"*"` and
   no `*` inside a key; every policy `effect=allow`; the group set equals `P5-SCOPE`. An account-scope resource
   carrying zone groups (every zone in the account, including future ones) fails. On failure, delete that new token
   and re-mint. **Browser bodies:** every `browser_run_code_unsafe` body returns only names, 8-character prefixes,
   counts, statuses and `e.name`; the POST response, `result.value`, `x-atok` and the full id stay Node-local; mint
   and policy read-back run in one body. Before the sitting, confirm the Playwright MCP config carries none of
   `--save-trace`, `--save-har`, `--save-session`, `--save-video`; during it, call no `browser_network_request(s)`,
   `browser_console_messages`, snapshot or screenshot. Then the hand-off's `_NEXT` write, a digest compare printed
   as `digest=equal|differ` only (never the `sha256sum` output), verify `true`/`active` (account endpoint first),
   `shred`, `git status --porcelain` clean. The owner's paste fallback for ANALYTICS is typed in the owner's own
   terminal: `read -rs v; printf '%s' "$v" | doppler secrets set CF_API_TOKEN_ANALYTICS_READ_NEXT -p soleur -c prd_terraform --silent >/dev/null; unset v`
   (never the `!` prefix, the chat or argv).
6. **Stages and holds** - the hold lines below, verbatim, in order.
7. **Revoke** - migration runbook revoke recipe steps 2-4 on prd_terraform `<KEY>_PREV`, run only on a `verify`
   line `SOLEUR_P5_REVOKE_READY key=<KEY>` printed in the same sitting with nothing written to that key since (CTO
   F13). The revoke body takes the pinned prefix, the `REVOKE_READY` `old_id` and `new_id` as literals, refuses
   unless the first two are equal and differ from `new_id`, and refuses a dashboard match whose name equals the new
   token's `<key>-soleur-<YYYYMMDD>` name (CTO F21). A user-owned fallback mint uses a login other than the
   old-account owner; with none available, that mint stays a hold recorded on #12931 (CTO F21). Step 4's key delete
   runs once per key after all three revokes (CTO F14). A later rotation of an account-owned token revokes it with
   `DELETE /accounts/66d4f93f.../tokens/<id>`. Closing check: the full
   `bash scripts/check-cloudflare-token-drift.sh` run reports no DEAD `CF_API_TOKEN*` value; a DEAD row names a copy
   to delete, never a rotation. For PAGERULES, post the post-swap `pagerules-ssl` rule counts on #12931 (marker
   `P5-PAGERULES-FATE`): the deferred fate read.
8. **`CF_API_TOKEN_PURGE_PREV`** - revoke `9e4ce00e` only at migration runbook Phase 3 step 5, after a share revoke
   answers `200`, through that runbook's recipe (its step 1 inventory is the archived #12931 bootstrap, which covers
   PURGE). Blocked by #12937.
9. **Origin CA and R2** - holders and ids; Origin CA re-scope at Phase 3 step 4; R2 stays.
10. **GitHub repo secrets** - both exist (2026-11-02), not readable back; the soak exits NOT YET before any call
    while Load Balancing is off; repointing to a least-privilege Load Balancing read token on the new account is a
    precondition of #12983.
11. **Rotation** - the bootstrap stays as the rotation tool (not deleted in Phase 5 cleanup); a rotation edits only
    its manifest block; reminder #13085.
12. **Halt** - fix forward; a copy that does not read back equal stops the stage and keeps `_NEXT`; never revoke
    without a same-sitting `REVOKE_READY`; a `soleur-infra-privileged` holder of an old value is a stop (no stage
    writes there): post it on #12931 and decide it in a reviewed change.

### Phase 3 - the bootstrap (`knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/bootstrap.sh`)

Authored with `soleur:operator-bootstrap` from `template.sh` (line 2 `# SOLEUR-GENERATED-OPERATOR-SCRIPT v2`; sources
`operator-script.sh`; repo-relative paths that survive `archive-kb`; no value in any plan op). A **manifest block** at
the top holds everything a rotation changes (CTO F18):

```text
# key                          | pinned old id | holders (project/config)
CF_API_TOKEN_AUDIT             | dd6d1427      | soleur/prd_terraform soleur/dev
CF_API_TOKEN_ANALYTICS_READ    | 5993721f      | soleur/prd_terraform
CF_API_TOKEN_PAGERULES_READ    | 86aa993e      | soleur/prd_terraform
```

Ids are non-secret 8-character prefixes. AUDIT's holders are only the configs with a named consumer (CTO F20):
`prd_terraform` (`cloudflare-readonly.sh change-history`) and `dev` (`infra-security.md`); its old copies in
`dev_personal` and `dev_scheduled` are deleted by hold before `verify`, so the census still finds exactly one old
copy. New account `66d4f93f7397f196544e9fe84c3557c2`, new zone
`951ce525552201ec6c696b24251abed7`; the old ids are refused as targets. Token identity helper: verify at
`/accounts/66d4f93f.../tokens/verify` first, `/user/tokens/verify` as the fallback; a reply counts as a denial only
when it is a JSON 400/401/403/404 with `success:false` (precedent `token_read`); `429`, `5xx` and transport failure
are `unreachable`, never a verdict. Values pass `token_chars_ok` before any request and ride curl's stdin config.
The prologue keeps the precedent's xtrace refusal (exit 78) and TLS-subversion `unset` line above the library
`source`. Writes reuse the precedent `copy_secret` shape (source digest, stdin pipe into `doppler secrets set
--silent`, destination digest, compare, `COPIED ... verified=digest` or `COPY_MISMATCH`). Census reads: list names
with `doppler secrets --only-names` per config first, then `get` only a listed name; a failed list, or a failed get
on a listed name, is `UNREADABLE`; `absent` means only a successful list without the name. No digest, length or
prefix of a value is printed. Consumer reads print only their first verdict line, and the GraphQL zone-tag gate
reuses the precedent `bearer_config` with a `data =` line and `--max-redirs 0`, discards the body after `jq`, and
prints only `zone_tag=match|mismatch errors=<n>`, so no actor, IP or rule text reaches stdout or the gitignored
`bootstrap-runs.jsonl`.

| Stage | Class | Does | Satisfied when |
|---|---|---|---|
| `inventory` | read | Reference per key: prd_terraform `<KEY>_PREV` if it verifies the pinned id, else prd_terraform `<KEY>` if it does, else `none`; prints `SOLEUR_P5_REFERENCE key= source=PREV\|KEY\|none`. Narrow census: the live config list of every project (`doppler projects`, `doppler configs`), which must contain the committed floor (D2: the `P5-PROJECT-FLOOR` projects, the tracked soleur config inventory and every manifest config); in each config, the key's own name only; prints `SOLEUR_P5_HOLDER project= config= key= value=old\|new\|other\|absent`, `SOLEUR_P5_UNREADABLE project= config=`, `SOLEUR_P5_CENSUS configs_read=<n> old_hits=<n>`. | - |
| `swap` | write | Per manifest key with prd_terraform `<KEY>_NEXT` staged (well-formed, verifies active, id not the pinned one): if no `<KEY>_PREV` verifies the pinned id, refuse unless `<KEY>` verifies it, then copy `<KEY>` -> `<KEY>_PREV` and read back by digest; then copy `<KEY>_NEXT` -> `<KEY>`, read back; delete `<KEY>_NEXT` only after an equal digest. A failed read-back stops the stage, later keys untouched, `_NEXT` kept. | `<KEY>_PREV` verifies the pinned id, `<KEY>` verifies a different active id, no `<KEY>_NEXT` |
| `holder-copies` | write | Every manifest holder other than prd_terraform: value digest equals `<KEY>_PREV`'s -> copy prd_terraform `<KEY>` there, read back; equal to `<KEY>`'s -> no operation; any third value or absent -> refuse naming the holder. Needs `swap` (`PRECONDITION_FAILED need=swap`). | every manifest holder's digest equals prd_terraform `<KEY>`'s |
| `verify` | read | Per key: prd_terraform `<KEY>` verifies active with an id that is not the pinned one; consumer read exits 0 (`cloudflare-readonly.sh pagerules-ssl`, `change-history`; ANALYTICS gates on a minimal zone-tag GraphQL query that must return the new zone tag with no `errors`, and prints `analytics-health 1` as a non-gating line); census: `old_hits` is exactly 1, at prd_terraform `<KEY>_PREV` (zero is `fail reason=census-blind`), zero `UNREADABLE`, no `_NEXT`; every manifest holder reads the new value; the D2 census floor holds. Prints `SOLEUR_P5_VERIFY key= verdict=ok\|fail reason=` and, on `ok` with `source=PREV`, `SOLEUR_P5_REVOKE_READY key= old_id=<pinned> new_id=<8> owner=<account|user>`. | - |

No stage calls the dashboard, deletes a token, writes outside the manifest holders, or writes
`soleur-infra-privileged`.

### Phase 4 - small repository edits

1. `plugins/soleur/agents/engineering/infra/infra-security.md`: new zone `951ce525552201ec6c696b24251abed7` and account
   `66d4f93f7397f196544e9fe84c3557c2` in the id line and the `ZONE_ID=`/`ACCT_ID=` block; the source line names the
   migration runbook's `### Ids (not secrets)` table; note the zone is on the Free plan; the "Token health check"
   line tries `/accounts/$ACCT_ID/tokens/verify` and falls back to `/user/tokens/verify` (CTO F17, F19).
2. `plugins/soleur/scripts/cloudflare-readonly.sh` header (token-binding block and the `token-invalid` interpretation
   row): drop the `2027-02-07` date; say the expiry is the verify answer's `expires_on`.
3. `.github/workflows/scheduled-followthrough-sweeper.yml`: replace the "These GH secrets do / not exist yet"
   comment with the measured fact (both exist, last set 2026-11-02, pre-move values) and the #12983 precondition.
   Comment only.
4. Registration (CTO F11): `scripts/test-all.sh` `run_suite` line beside the precedent;
   `AFFECTED_TESTS_SCRIPTS_CF_OLD_LOGIN_TOKEN_REMINT_BOOTSTRAP_PATHS` in `scripts/lib/test-affected-paths.sh` beside
   the precedent block, with `glob:knowledge-base/project/specs/*feat-one-shot-12931-phase5-token-remint/bootstrap.sh`,
   `operator-script.sh`, `operator-stage-approval.sh`, the suite and the lib file; TSV rows via
   `python3 scripts/regenerate-shard-manifest.py --incremental --write`.

### Phase 5 - tests (write first, per `cq-write-failing-tests-before`)

`tests/scripts/test-cf-old-login-token-remint-bootstrap.sh`, modelled on the precedent suite: fixture git repo with
the bootstrap at its real relative path, PATH-stubbed `doppler` (`get --plain` adds one newline; `set` stores stdin
exactly; `projects`/`configs`/`--only-names` listings), `curl` (verify ids per value on both endpoints, consumer
reads, GraphQL) and `gh`. Synthesized sentinel values only (`cq-test-fixtures-synthesized-only`). Cases: the Guard
Contract rows plus the scenarios under Test Scenarios. Each mutant is proven to land (`cmp` differs, `bash -n`
clean, red at the named step), driven by `bash tests/scripts/test-cf-old-login-token-remint-bootstrap.sh --mutants`.

### Phase 6 - GitHub record (Agent)

1. #12931: the `P5-TOKEN-FACTS` comment (Phase 1) naming the new runbook path and the rulings file. Ref only.
2. #12983: the repo-secret precondition (CTO F3), marker `P5-GH-SECRET`.

## Operator Holds

Each line runs only after the operator's typed go naming that exact command in the session
(`hr-menu-option-ack-not-prod-write-auth`). One typed go may quote all three mint commands together, each named in
full (CTO devex D2); every other line takes its own go. Bootstrap applies run from a `main` checkout after merge;
`<B>` is the absolute path the runbook's Orient step prints, `<D>` the digest the stage's plan run prints, relayed
verbatim with its `SOLEUR_BOOTSTRAP_IMPACT`/`ROLLBACK` lines. The `_NEXT` writes are the migration runbook's
`### 0a and 0b` hand-off step 2 command with `<KEY>` substituted; each mint go cites the #12931 `P5-SCOPE` comment.

- Hold: Operator-authorizes: account-owned mint of `CF_API_TOKEN_PAGERULES_READ` (groups per the `P5-SCOPE` comment, zone `951ce525` only, expiry equal to the 0a/0b expiry) in the signed-in dashboard session, then `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_pagerules_read.tok" | doppler secrets set CF_API_TOKEN_PAGERULES_READ_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: account-owned mint of `CF_API_TOKEN_AUDIT` (groups per the `P5-SCOPE` comment, account `66d4f93f` and zone `951ce525` only, same expiry), then `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_audit.tok" | doppler secrets set CF_API_TOKEN_AUDIT_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: owner mint of `CF_API_TOKEN_ANALYTICS_READ` (account-owned, groups per the `P5-SCOPE` comment, zone `951ce525` only, same expiry) through the hand-off or the owner's paste, then `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_analytics_read.tok" | doppler secrets set CF_API_TOKEN_ANALYTICS_READ_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT -p soleur -c dev_personal --yes > /dev/null` (CTO F20; rollback: copy prd_terraform `CF_API_TOKEN_AUDIT` back with the precedent `copy_secret` form)
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT -p soleur -c dev_scheduled --yes > /dev/null` (same)
- Hold: Operator-authorizes: `bash <B> --stage swap --apply --plan-digest <D>`
- Hold: Operator-authorizes: `bash <B> --stage holder-copies --apply --plan-digest <D>`
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_PAGERULES_READ` old id `86aa993e` by the revoke recipe step 3 `page.request.delete('https://dash.cloudflare.com/api/v4/user/tokens/<id>')`, signed in as the old-account-owner login, only after `bash <B> --stage verify` printed `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_PAGERULES_READ old_id=86aa993e` in the same sitting
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_AUDIT` old id `dd6d1427` by `page.request.delete('https://dash.cloudflare.com/api/v4/user/tokens/<id>')`, only after a same-sitting `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_AUDIT old_id=dd6d1427`
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_ANALYTICS_READ` old id `5993721f` by `page.request.delete('https://dash.cloudflare.com/api/v4/user/tokens/<id>')`, only after a same-sitting `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_ANALYTICS_READ old_id=5993721f`
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_PAGERULES_READ_PREV -p soleur -c prd_terraform --yes > /dev/null` (revoke recipe step 4, only on a read-back that starts `success=false`)
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT_PREV -p soleur -c prd_terraform --yes > /dev/null` (same condition)
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_ANALYTICS_READ_PREV -p soleur -c prd_terraform --yes > /dev/null` (same condition)
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_PURGE_PREV` (`9e4ce00e`) with the migration runbook revoke recipe on prd_terraform `CF_API_TOKEN_PURGE_PREV`, at its Phase 3 step 5 only (after the release redeploy that #12937 blocks and a share revoke answering `200`), then `doppler secrets delete CF_API_TOKEN_PURGE_PREV -p soleur -c prd_terraform --yes > /dev/null` on a `success=false` read-back

Not holds (Agent, read-only or GitHub record): Phase 1 reads, every `inventory`/`verify` run, the plan runs of each
write stage, the policy and permission-group reads in the signed-in session, the drift checks, the #12931 and #12983
comments. Not in this plan at all: the Origin CA re-scope (Phase 3 step 4, #12958), any GitHub-secret write (CTO F3),
any gh-pages cert reissue, any old-zone write.

## Files to Create

- `knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md`
- `knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/bootstrap.sh`
- `tests/scripts/test-cf-old-login-token-remint-bootstrap.sh`
- `knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/tasks.md` (plan phase)

## Files to Edit

- `plugins/soleur/agents/engineering/infra/infra-security.md` (ids, source line, verify fallback)
- Generated copies of that agent, never hand-edited: `.grok/agents/soleur-engineering-infra-infra-security.md`,
  `plugins/soleur/cursor/agents/soleur-engineering-infra-infra-security.md`,
  `plugins/soleur/opencode/agents/engineering/infra/infra-security.md`, regenerated with
  `bun plugins/soleur/scripts/sync-grok-agent-compat.ts`, `bun plugins/soleur/scripts/sync-cursor-name-map.ts` and
  `bun plugins/soleur/scripts/sync-opencode-adapter.ts`, then each run again with `--check` (deepen pass: the
  verify agent found the three copies)
- `plugins/soleur/scripts/cloudflare-readonly.sh` (header comment only: expiry date)
- `.github/workflows/scheduled-followthrough-sweeper.yml` (comment only)
- `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`,
  `scripts/suite-shard-legs.tsv` (registration, additive)

Not edited: `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md` and every other file in
#12958's diff except the three additive registry files (CTO F1, F11).

## Open Code-Review Overlap

- #7942 (mutation batteries named `*.mutation.sh` run in no gate) names `scripts/test-all.sh`. **Acknowledge:** a
  different concern; this plan adds one `run_suite` line and names its suite `test-*.sh`.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
Phase 2.8 reviewed: `soleur:engineering:infra:terraform-architect` was invoked on 2026-11-27 and returned the
bootstrap verdict below. The `doppler secrets set`/`delete` lines in `## Operator Holds` are the migration runbook's
existing hand-off write and revoke-recipe delete, each under a typed go; they cannot be Terraform (see below).

### Terraform changes

None. The three keys stay out of Terraform deliberately: they are operator-minted in the dashboard (ADR-130: no Soleur
token holds API Tokens:Edit, so a `cloudflare_api_token` apply fails 403/9109, the reason
`apps/web-platform/infra/cf-cert-reissue-token.tf` dropped its mint), and they have no Terraform consumer or copy
step (`CF_API_TOKEN_DNS_EDIT` is a `doppler_secret` only because Terraform republishes it into `prd`). No `variable`
block is added, so no value reaches `terraform.tfstate`; the `prd_terraform` `--name-transformer tf-var` exposure of
the new names is ignored by Terraform for undeclared variables.

### Apply path

(c) staged bootstrap script, run after merge from `main`, one approved stage at a time. No host, no downtime. Blast
radius: the read-only diagnostics (`pagerules-ssl`, `change-history`, `analytics-*`, the infra-security API checks)
and the manifest's Doppler keys.

### Distinctness / drift safeguards

- `dev`-family and `prd_terraform` keep their own copies; `holder-copies` writes only manifest holders that held the
  old value (a write to a branch config becomes an override, accepted: the next rotation uses the same manifest).
- Drift: the dead `_PREV` keys are deleted in the revoke sitting (recipe step 4), so
  `scripts/check-cloudflare-token-drift.sh` never grades a revoked value for long; its full run is the closing check.
  It does not scan `soleur-infra-privileged`; this plan writes nothing there.

### Vendor-tier reality check

The new zone is on the Free plan. GraphQL quantile fields may be plan-limited: `analytics-health` printing
`api-error (graphql: ...)` after a passing zone-tag query is a plan limit, recorded on #12931, and does not gate the
ANALYTICS revoke.

## Observability

```yaml
liveness_signal:
  what: "bootstrap verify line SOLEUR_P5_VERIFY key=<KEY> verdict=ok, plus the consumer read exit 0"
  cadence: "once per sitting, after swap and holder-copies; the daily scheduled-terraform-drift token_drift step then grades every CF_API_TOKEN* key"
  alert_target: "#12931 comment per sitting; token-drift DEAD-credential issue from scheduled-terraform-drift.yml"
  configured_in: "knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/bootstrap.sh; .github/workflows/scheduled-terraform-drift.yml"
error_reporting:
  destination: "stage stdout markers SOLEUR_BOOTSTRAP_STAGE_FAILED / PRECONDITION_FAILED / SOLEUR_P5_VERIFY verdict=fail, and the run ledger bootstrap-runs.jsonl"
  fail_loud: "non-zero exit on every refusal; no stage exits 0 on an unreadable config, an unreachable verify or a census with zero hits"
failure_modes:
  - mode: "minted token over-scoped or wrong groups"
    detection: "policy read-back in the dashboard session (resources other than 66d4f93f/951ce525, or groups differing from P5-SCOPE)"
    alert_route: "delete the new token and re-mint before any Doppler write"
  - mode: "copy does not read back equal"
    detection: "digest compare inside swap/holder-copies"
    alert_route: "stage stops, _NEXT kept, STAGE_FAILED"
  - mode: "a holder still holds the old value"
    detection: "census row value=old outside prd_terraform <KEY>_PREV"
    alert_route: "verify fails, no REVOKE_READY, revoke hold not authorized"
  - mode: "a revoked value left under some CF_API_TOKEN* name"
    detection: "full check-cloudflare-token-drift.sh run reports DEAD"
    alert_route: "token-drift issue; fix is a key delete, never a rotation"
  - mode: "token expiry passes unnoticed"
    detection: "reminder issue #13085 (due 14 days before expires_on); drift-script warning tracked in #13086"
    alert_route: "issue assignee"
logs:
  where: "bootstrap-runs.jsonl beside the script; #12931 comments"
  retention: "git history and the GitHub issue (indefinite)"
discoverability_test:
  command: "bash knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/bootstrap.sh --list"
  expected_output: "stage=verify"
```

## Guard Contract

Each matrix row names the input world and the code mutant it kills; a row passes on a correct bootstrap (the stage
refuses with the named reason text) and goes red when its mutant is applied (`--mutants`). Every refusal asserts its
message text, not only the exit code (test-design review, deepen pass).

### Guard 1 - the revoke never sees a live holder of the old value (`verify`'s census and `REVOKE_READY`)

**Property.** `verify` prints `SOLEUR_P5_REVOKE_READY` for a key only when prd_terraform `<KEY>_PREV` verifies the
pinned old id, prd_terraform `<KEY>` verifies a different active id, and no config of any listed Doppler project holds
the old value under that key's name except prd_terraform `<KEY>_PREV`.

**Assembly.** One census function that `inventory` and `verify` call. It quantifies over (a) every config of every
project the live `doppler projects`/`doppler configs` listing returns, never only the manifest or the inventory file,
with a floor: `soleur` must list at least the manifest's configs; (b) the key's own name in each config, read
list-then-get; (c) the reference digest from the `SOLEUR_P5_REFERENCE` rule, recomputed at call time. A failed list
or a failed get of a listed name is `UNREADABLE`, never `absent`. Positive count: exactly one old hit, at `_PREV`.

**Mutation matrix.**

| # | Input world | Must | Mutant killed |
|---|---|---|---|
| 1 | `doppler projects` answers `[]` | `fail reason=census-floor`, no `REVOKE_READY` | floor check deleted (own-dispatch vacuity) |
| 2 | Compliant world; mutant hashes raw `get --plain` output (newline kept) | `fail reason=census-blind` | `old_hits==0` check deleted |
| 3 | `dev` new, `dev_personal` still holds the old value (second member after a compliant first) | fail naming `soleur/dev_personal` | census `break` after the first compliant holder |
| 4 | Project `other`, config `ci` (in no manifest) holds the old value under the key's name | fail naming `other/ci`; `holder-copies` writes nothing there | census loops over manifest configs only |
| 5 | Compliant except `<KEY>` verifies a new id with `status=expired` | `fail reason=key-not-active` | active-status check dropped |
| 6 | `<KEY>_PREV` holds the new value (the #13080 order) | `source=none`, no `REVOKE_READY` | reference taken from `_PREV` by name, not by pinned id |
| 7 | One config's get on a listed name errors | `UNREADABLE`, fail | read error treated as `absent` |

**Harness rows.** RED: a suite edit whose `doppler` stub answers every `get` with an empty value must red rows 3 and
4 (the refusal no longer names `soleur/dev_personal` / `other/ci`) and the must-PASS row. Must-PASS (non-canonical):
`other/ci` holds the NEW value and one `soleur` config lacks the key (`absent`, not `UNREADABLE`): `ok` plus
`REVOKE_READY`.

**Anchor.** The pinned old id prefixes are committed literals answered by the vendor's verify endpoint, so a PR that
edits both a reference and a holder cannot make an old value read as new.

### Guard 2 - `_PREV` holds the old value before `<KEY>` is overwritten (`swap`)

**Property.** `swap` never writes `<KEY>` unless, at that moment, `<KEY>_PREV` verifies the pinned old id.

**Assembly.** One per-key write path inside `swap`; the `_PREV` check sits between the `_PREV` copy and the `<KEY>`
write, and runs for every manifest key that has a `_NEXT`. The `doppler` stub logs each `set <KEY>` with
`prev=<class of the _PREV value at that moment>`, so an order defect is observable inside the window.

**Mutation matrix.**

| # | Input world | Must | Mutant killed |
|---|---|---|---|
| 1 | `<KEY>` not the pinned id, no `_PREV` | refuse, zero writes | precondition check deleted |
| 2 | `_PREV` exists holding a non-pinned value, `<KEY>` not pinned (value, not name) | refuse, zero writes | `_PREV` accepted by name |
| 3 | The `_PREV` copy does not read back equal | stop before the `<KEY>` write, `_NEXT` kept | read-back compare deleted |
| 4 | First key swaps, second key's `_PREV` copy fails (second member) | second key untouched, `_NEXT` kept | loop continues after a failed key |
| 5 | Any swap | every `set <KEY>` log line reads `prev=old` | `<KEY>` write moved above the `_PREV` check (reorder) |
| 6 | Manifest parsed to zero keys | refuse | empty-manifest pass (own-dispatch vacuity) |

**Harness rows.** RED: a stub that corrupts the `<KEY>` write (not `_PREV`) must red row 3, because a `<KEY>` set
appears in the log. Must-PASS: key 1 swapped in an earlier sitting, key 2 staged: writes key 2 only and key 1's
`_PREV` is unchanged.

### Guard 3 - `holder-copies` writes only manifest holders that held the old value

**Property.** `holder-copies` writes a holder only when that holder's value digest equals `<KEY>_PREV`'s, and refuses
the whole stage before any write when a holder holds a third value or lacks the key.

**Assembly.** One loop over the manifest holders of each key, preceded by a full classification pass; each holder is
decided on its own digest.

**Mutation matrix.**

| # | Input world | Must | Mutant killed |
|---|---|---|---|
| 1 | The last holder (`dev`) holds a third value, or lacks the key (parametrized) | refuse naming it, zero writes | write-as-you-go (no up-front classification) |
| 2 | First holder old, second already new (second member) | writes only the first | write without the per-holder digest compare |
| 3 | Run before `swap` | `PRECONDITION_FAILED need=swap` | precondition deleted |

**Harness rows.** RED: a stub `get` that returns the `_PREV` value for every holder must red row 2.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Re-mint CF_API_TOKEN_AUDIT, CF_API_TOKEN_ANALYTICS_READ (owner mint) and CF_API_TOKEN_PAGERULES_READ (run the pagerules read on the new zone first) on the new account" [brief] | Phase 1 read (done 2026-11-27: `token-lacks-scope`), runbook sections 4-7, bootstrap, mint holds | mapped |
| 2 | "staging <KEY>_PREV before overwrite and checking by digest/verify id" [brief] | `swap` (Guard 2), `verify` census (Guard 1) | mapped |
| 3 | "locate the Origin CA token holder (likely soleur-infra-privileged/prd)" [brief] | Reconciliation row 1, runbook section 9 | mapped |
| 4 | "revoke PURGE_PREV at Phase 3 step 5" [brief] | PURGE_PREV hold, runbook section 8 | mapped |
| 5 | "the R2 token stays" [brief] | Reconciliation row 2, runbook section 9 | mapped |
| 6 | "Each re-mint/revoke needs a typed go naming the command" [brief] | `## Operator Holds` | mapped |
| 7 | "the GitHub secret CF_API_TOKEN gap (Phase 5)" [brief] | Phase 4.3, Phase 6.2, runbook section 10 | mapped |
| 8 | "release deploys blocked by #12937 (Ref only)" [brief] | PR body `Ref #12937`; PURGE_PREV hold condition | mapped |
| 9 | "never print token values, no SSH, leave the old zone read-only, no gh-pages cert reissue with probeOnly:false before Phase 3 step 5" [brief] | P4, P9; runbook Constraints; old ids refused as targets | mapped |
| 10 | "Ref only, never close" [brief] | PR body `Ref #12931` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| New runbook | asks 1-9 | asked |
| `bootstrap.sh` | asks 1, 2, 6 | asked |
| Bootstrap suite + registration | - | inferred - justification: the bootstrap writes production Doppler; `hr-multi-step-post-merge-bootstrap-script` and the orphan-suite lint require a registered suite (CTO F11) |
| `infra-security.md` ids and verify fallback | - | inferred - justification: the AUDIT re-mint's consumer hardcodes the old ids and checks only the user verify endpoint, so without this edit it sends the new account-owned token to the old zone and reads it as invalid (CTO F5, F17, F19) |
| `cloudflare-readonly.sh` header date | - | inferred - justification: the ANALYTICS re-mint changes the expiry the header asserts |
| Sweeper comment | ask 7 | asked |
| #12931 / #12983 comments | asks 3, 7 | asked |
| Follow-up issues #13085, #13086 | - | inferred - justification: the 90-day expiry needs a tracked rotation (`wg-when-deferring-a-capability-create-a`, CTO F18) |

### Split Assessment

- Subsystems touched: 3 - `knowledge-base/`, `plugins/soleur/`, `scripts/`+`tests/`+`.github/`
- Planned files: 11 | Estimated changed lines: about 600 (bootstrap about 250, suite about 200, runbook about 120)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (work phase)

- [ ] AC1 `knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md` exists with the twelve
  sections of Phase 2; its facts table names all six id prefixes (`dd6d1427`, `5993721f`, `86aa993e`, `9e4ce00e`,
  `34acd675`, `bb4a334a`) with a disposition each. `grep -oE '[A-Za-z0-9_-]{33,}' <runbook> | grep -vE '^[A-Z0-9_]+$' | grep -c '[A-Z]'`
  prints `0` (all-caps key names such as `CF_API_TOKEN_ANALYTICS_READ_PREV` are excluded), and the same command on a scratch copy carrying a synthesized 40-character mixed-case sentinel prints
  `1` (control).
- [ ] AC2 `bash knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/bootstrap.sh --list` prints four
  `SOLEUR_BOOTSTRAP_STAGE_DECL` lines in table order: `stage=inventory class=read`, `stage=swap class=write`,
  `stage=holder-copies class=write`, `stage=verify class=read`; line 2 is `# SOLEUR-GENERATED-OPERATOR-SCRIPT v2`.
- [ ] AC3 `bash tests/scripts/test-cf-old-login-token-remint-bootstrap.sh` passes, and
  `bash tests/scripts/test-cf-old-login-token-remint-bootstrap.sh --mutants` shows every Guard 1-3 row and harness
  row red at its named step (each mutant `cmp`-differs from the control).
- [ ] AC4 `grep -cE '5af02a2f|4d5ba6f0' plugins/soleur/agents/engineering/infra/infra-security.md` prints `0`; both
  new ids appear; `grep -c 'apps/web-platform/infra/main.tf'` on it prints `0`; `grep -c 'Ids (not secrets)'` and
  `grep -c 'tokens/verify'` on it each print at least `1`, the latter including an `/accounts/` form. The same
  `grep -cE '5af02a2f|4d5ba6f0'` prints `0` on each of the three generated copies, and the three sync scripts' `--check`
  runs exit 0.
- [ ] AC5 `grep -c '2027-02-07' plugins/soleur/scripts/cloudflare-readonly.sh` prints `0` and
  `grep -c 'expires_on' plugins/soleur/scripts/cloudflare-readonly.sh` prints at least `2`;
  `bash plugins/soleur/test/cloudflare-readonly.test.sh` and `bun test plugins/soleur/test/components.test.ts` pass.
- [ ] AC6 `grep -cE 'GH secrets do$|^ *# not exist yet' .github/workflows/scheduled-followthrough-sweeper.yml` prints
  `0` (it prints `2` on `main` today); `grep -c '#12983'` and `grep -c '2026-11-02'` on it each print at least `1`;
  `actionlint .github/workflows/scheduled-followthrough-sweeper.yml` is clean.
- [ ] AC7 `bash scripts/lint-orphan-test-suites.sh` passes with the new suite registered;
  `git diff --quiet origin/main...HEAD -- knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`
  exits 0.
- [ ] AC8 `gh issue view 12931 --comments | grep -c P5-TOKEN-FACTS` and
  `gh issue view 12983 --comments | grep -c P5-GH-SECRET` each print at least `1`; the PR body carries
  `Ref #12931` and `Ref #12937` and no `Closes`/`Fixes` of either.
- [ ] AC9 `find <scratchpad> -name '*.tok' | wc -l` prints `0`, and
  `git status --porcelain --ignored | grep -c '\.tok$'` prints `0` in this worktree and in the main checkout.

### Post-merge (each after its hold's typed go)

- [ ] AC10 Per key: `bash <B> --stage verify` prints `SOLEUR_P5_VERIFY key=<KEY> verdict=ok` and
  `SOLEUR_P5_REVOKE_READY key=<KEY>`. (No drift run here: CTO D3 moved the only drift run to AC11, after the revoke.)
- [ ] AC11 Per old id: the revoke recipe read-back starts `success=false`; after the key delete, `--stage inventory`
  shows no `<KEY>_PREV`; the full drift run exits 0; `gh issue view 12931 --comments | grep -c P5-REVOKED` prints at
  least `1`.
- [ ] AC12 `gh issue view 12931 --comments | grep -c P5-PAGERULES-FATE` prints at least `1` (the post-swap
  `pagerules-ssl` rule counts).
- [ ] AC13 `CF_API_TOKEN_PURGE_PREV` is revoked only after Phase 3 step 5's share-revoke `200`, then its key deleted.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent rulings F1-F19 (2026-11-27) in
`knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/decision-challenges.md`; terraform-architect
verdict: bootstrap path (c), no Terraform resource, dead `_PREV` keys deleted in the revoke sitting, drift checks
after (folded in); plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens, strong-model advisor, sharp-edges
pass) applied as the revision above.

No Product, Marketing, Legal, Finance, Sales, Operations or Support implications: three internal read-only
diagnostics credentials, no user-facing surface, no spend.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; the operator's read-only Cloudflare diagnostics
(`pagerules-ssl`, `change-history`, `analytics-*`, the infra-security agent's API checks) keep answering
`token-lacks-scope`, as they do today.
**If this leaks, the user's data / workflow / money is exposed via:** a leaked AUDIT token reads the Soleur account's
audit log (actor emails, change history) and zone configuration; a leaked analytics or page-rules token reads traffic
aggregates or page rules. None can write. Mitigations: an expiry of about 85 days, one resource scope each, values
never printed.
**Brand-survival threshold:** none

- threshold: none, reason: read-only operator diagnostics tokens with no user data path and no write scope; no
  sensitive path in the diff matches `SENSITIVE_PATH_RE`.

## Test Scenarios

The Guard Contract matrices are the core scenarios; in addition:

- Happy path: `_NEXT` staged for all three keys -> `swap` -> `holder-copies` -> `verify ok` with three
  `REVOKE_READY` lines -> simulated revoke (both verify endpoints refuse) -> key delete -> `inventory` shows
  `source=none` and no `_PREV`; every write stage then plans `operations=0`.
- An account-owned new token: `/user/tokens/verify` refuses, `/accounts/66d4f93f.../tokens/verify` answers active:
  `verify` reads it as new and active.
- `429` or `503` on a verify read: `unreachable`, the stage refuses, never a verdict.
- An apply without a receipt exits 75 and writes nothing; no synthesized value reaches stdout or stderr (grep the
  captured streams for every sentinel).
- A staged value carrying a quote or newline is refused before any curl call.
- ANALYTICS: a zone-tag query that passes plus an `analytics-health` `api-error (graphql: ...)` still reads `ok`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6.
- Never overwrite `<KEY>` before `<KEY>_PREV` holds the old value: the revoke recipe reads `_PREV`, and the wrong
  order revokes the new token (the #13080 P1). `swap` enforces it; a hand edit bypasses it.
- `REVOKE_READY` is valid only in the sitting that printed it, with nothing written to that key since.
- The dashboard token list can be stale after sign-in: reload `/profile/api-tokens` first (2026-11-26 measured 0
  tokens on a stale page).
- The revoke must be signed in as the login that owns the old token (the old-account-owner login); the agent asks,
  never switches logins.
- An account-owned token is unknown to `/user/tokens/verify` (`success:false`); never read that alone as dead.
- `doppler secrets get --plain` appends one newline; every read goes through the one-newline strip, or digests differ.
- A 403 on the `status=moved` old zone proves nothing about a new token's scope; scope is read from the token's
  policies.
