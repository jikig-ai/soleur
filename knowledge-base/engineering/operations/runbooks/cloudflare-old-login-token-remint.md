---
title: "Runbook: re-mint the old-login Cloudflare read tokens on the Soleur account (#12931 Phase 5 token slice)"
category: infrastructure
tags: [cloudflare, doppler, tokens, rotation, migration]
date: 2026-11-27
triggers:
  - cloudflare-readonly.sh pagerules-ssl answers token-lacks-scope on the new zone
  - cloudflare-readonly.sh change-history answers token-lacks-scope on the new account
  - cloudflare-readonly.sh analytics-health answers api-error on the new zone
  - token-drift DEAD credential for CF_API_TOKEN_AUDIT, CF_API_TOKEN_ANALYTICS_READ or CF_API_TOKEN_PAGERULES_READ
  - rotate the Soleur-account read tokens before the ~2027-02-20 expiry (#13085)
---

# Runbook: re-mint the old-login Cloudflare read tokens on the Soleur account

Epic: #12931 (Ref only; this runbook never closes it). Plan:
`knowledge-base/project/plans/2026-11-27-chore-cf-phase5-old-login-token-remint-plan.md`. Rulings:
`knowledge-base/project/specs/feat-one-shot-12931-phase5-token-remint/decision-challenges.md`.

This is the token slice of `## Phase 5 — cleanup PR (after Phase 3 verification)` in
`cloudflare-account-migration.md` (the migration runbook). It replaces three read tokens that the old-account-owner
login still owns. It also records where the other three old-login tokens live and when each one goes. The rest of
Phase 5 waits for Phase 3 (tunnel re-home, #12958) and the release redeploy that #12937 blocks.

This runbook uses the migration runbook's `## Conventions` unchanged: the owner markers, no SSH, no secret on screen,
the stdin pipe form and the one-newline strip `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}'`.
`Operator-authorizes:` marks a production act; it runs only on a typed go that names the exact command
(`hr-menu-option-ack-not-prod-write-auth`). `Agent:` marks a read-only step the agent runs unprompted.

## 1. Orient

Start here in a fresh session.

1. `Agent:` resolve the bootstrap from the repo root of a `main` checkout. archive-kb moves the spec directory, so
   match by glob. Exactly one match, else stop:

   ```bash
   B="$(git ls-files --full-name ':(top)*feat-one-shot-12931-phase5-token-remint/bootstrap.sh')"; if [[ $(printf '%s\n' "$B" | grep -c .) -eq 1 ]]; then B="$(git rev-parse --show-toplevel)/$B"; printf 'SOLEUR_P5_BOOTSTRAP path=%s\n' "$B"; else printf 'SOLEUR_P5_BOOTSTRAP verdict=stop matches=%s\n' "$(printf '%s\n' "$B" | grep -c .)"; false; fi
   ```

   On `verdict=stop`, stop. A shell variable does not survive between agent tool calls. Write the printed absolute
   path literally wherever a later line says `<B>`.
2. `Agent:` run `bash <B> --list`, then `bash <B> --stage inventory`. Run each write stage per the
   `soleur:operator-bootstrap` protocol: the plan run prints a digest `<D>` and the `SOLEUR_BOOTSTRAP_IMPACT` and
   `SOLEUR_BOOTSTRAP_ROLLBACK` lines; relay them verbatim. A plan that says `operations=0` is already done.
   `PRECONDITION_FAILED need=<stage>` means run that stage first.
3. `Agent:` map the inventory rows to the next step, per key:

   | Inventory shows | Next step |
   |---|---|
   | `SOLEUR_P5_REFERENCE source=KEY` and the `swap` plan run shows nothing staged | Section 4 scope, then the section 5 mint |
   | `source=KEY` and the `swap` plan run shows a staged `<KEY>_NEXT` | `swap` |
   | `CF_API_TOKEN_AUDIT` row `value=old` in `soleur/dev_personal` or `soleur/dev_scheduled` | the two AUDIT delete holds |
   | `source=PREV` and a manifest holder row `value=old` outside prd_terraform | `holder-copies` |
   | `source=PREV` and every manifest holder `value=new` | `verify` |
   | `verify` printed `SOLEUR_P5_REVOKE_READY key=<KEY>` in this sitting | section 7 revoke |
   | `source=none` and no `<KEY>_PREV` row | done; run the section 7 closing check |
   | `source=none` and a `<KEY>_PREV` row | stop: `_PREV` does not hold the pinned old id; post it on #12931 |
   | `SOLEUR_P5_UNREADABLE` or a holder row `value=other` | stop; see section 12 |

4. Logins. The mint sitting needs a login that can mint account-owned tokens on the Soleur account. The revoke sitting
   needs the old-account-owner login, which owns all six old tokens. The agent asks for the right login. It never
   switches logins itself.

## 2. Facts

Six user tokens remain on the old-account-owner login. Sources: #12931 comment 7205049710 (a fresh
`/profile/api-tokens` load, 2026-11-26) and the plan's reads of 2026-11-27. Each holder was matched by verify id. No
value was printed. Ids here are non-secret 8-character prefixes.

| Id prefix | Dashboard name | Holder(s) (project/config) | Measured on the new zone or account | Disposition |
|---|---|---|---|---|
| `dd6d1427` | soleur-security-audit | `CF_API_TOKEN_AUDIT` in `soleur/dev`, `soleur/dev_personal`, `soleur/dev_scheduled`, `soleur/prd_terraform` | `change-history` -> `unverified - token-lacks-scope` | Re-mint. After it, held only in prd_terraform and dev; the dev_personal and dev_scheduled copies are deleted (CTO F20). |
| `5993721f` | soleur-analytics-read-p90 | `CF_API_TOKEN_ANALYTICS_READ` in `soleur/prd_terraform` | `analytics-health 1` -> `unverified - api-error` | Re-mint (owner mint). |
| `86aa993e` | soleur-pagerules-read | `CF_API_TOKEN_PAGERULES_READ` in `soleur/prd_terraform` | `pagerules-ssl` -> `unverified - token-lacks-scope` (reads as unknown, not as "no page rules") | Re-mint, then the post-swap fate read (`P5-PAGERULES-FATE`). |
| `9e4ce00e` | soleur-purge-shared-tokens | `CF_API_TOKEN_PURGE_PREV` in `soleur/prd_terraform` | Not read in this slice. The 0b `CF_API_TOKEN_PURGE` replaced it; the running containers still hold it until the release redeploy. | Revoke at migration runbook Phase 3 step 5 (section 8). |
| `34acd675` | soleur-origin-ca | `CF_API_TOKEN_ORIGIN_CA` in `soleur-infra-privileged/prd` (verify `status=active expires=none`) | Scope unread. `GET /certificates?zone_id=` answers `success=true count=0` for the new zone, the old zone and an all-zero zone id, so it is not a scope instrument. | Re-scope at migration runbook Phase 3 step 4 (#12958). |
| `bb4a334a` | soleur-workspaces-luks-header-r2 | `CF_API_TOKEN_R2` in `soleur-infra-privileged/prd` (a user token, `status=active expires=none`) | Not applicable: R2 stays on the old account (ADR-329). | Keep. |

Holder search scope: a names-only census of all nine Doppler projects the agent's identity lists. `CF_API_TOKEN*` names
exist only in `soleur` (16 configs) and in `soleur-infra-privileged/prd` (`CF_API_TOKEN_ORIGIN_CA`, `CF_API_TOKEN_R2`).
A copy of a value under some other key name was not searched for (CTO F2').

Ids (from the migration runbook's `### Ids (not secrets)` table): new account `66d4f93f7397f196544e9fe84c3557c2`, new
zone `951ce525552201ec6c696b24251abed7`. The old zone and account are never a target.

## 3. Constraints

From the migration runbook's `## Phase 5 — cleanup PR (after Phase 3 verification)`, quoted:

> - Stage the old value as `<KEY>_PREV` before overwriting `<KEY>`, so the revoke recipe reads the old id.
> - Check by digest or verify id, never by key name, that no config's `<KEY>` still holds the old value.
> - Treat `CF_API_TOKEN_ANALYTICS_READ` as an owner mint (`origin-tls-strict-flip.md`).
> - Run `cloudflare-readonly.sh pagerules-ssl` on the new zone before deciding the fate of
>   `CF_API_TOKEN_PAGERULES_READ`. That read is pinned in `components.test.ts`. If the token is scoped to the
>   old zone, the read fails with a scope or zone-access error; that means "unknown", not "no page rules".

Also:

- Never print a token value. Ids print at most 8 characters. Digests are compared, never printed.
- No SSH, anywhere (`hr-no-ssh-fallback-in-runbooks`).
- The old zone stays read-only. Nothing here writes to it.
- No gh-pages cert reissue with `probeOnly:false` before migration runbook Phase 3 step 5.
- One token per key.
- Expiry equal to the 0a/0b expiry, read at the mint sitting (about 2027-02-20, CTO F18), so one sitting rotates all.

## 4. Scope table

| Key | Consumer | Endpoints read | Candidate permission groups |
|---|---|---|---|
| `CF_API_TOKEN_AUDIT` | `cloudflare-readonly.sh change-history`; the infra-security agent | Account: `GET /accounts/<acct>/logs/audit`, `/accounts/<acct>/audit_logs`, `/accounts/<acct>`, `/accounts/<acct>/alerting/v3/policies`. Zone: `settings`, `dns_records`, `ssl/certificate_packs`, `firewall/rules` | Account: Account Settings Read (the audit-log endpoints accept it), Notifications Read. Zone: Zone Settings Read, DNS Read, SSL and Certificates Read, Firewall Services Read |
| `CF_API_TOKEN_ANALYTICS_READ` | `cloudflare-readonly.sh analytics-*` | `POST /graphql` (`httpRequestsAdaptiveGroups` on the zone) | Zone: Analytics Read. Owner mint. |
| `CF_API_TOKEN_PAGERULES_READ` | `cloudflare-readonly.sh pagerules-ssl` | `GET /zones/<zone>/pagerules?status=active` | Zone: Page Rules Read |

Reconcile rule, at the mint sitting, before any mint:

1. `Agent:` in the signed-in dashboard session, read the live account permission groups
   (`GET /api/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/tokens/permission_groups`). Return names and 8-character
   id prefixes only. Never type a group name from memory.
2. `Agent:` read the old token's policies (`GET /api/v4/user/tokens`). This lists only the signed-in login's own
   tokens, so it needs the old-account-owner login. Return group names and resource counts only.
3. Re-scope to the new account and zone. Trim to the endpoints in this table.
4. Post the final groups per key on #12931 with the marker line `P5-SCOPE`. Each mint go cites that comment.

The `P5-SCOPE` set is an allowlist built from this table. It is never the old token's policies with groups trimmed
off. The old policies are read only to surface a consumer this table missed. Every group is a Read group.

## 5. Mint

Each mint is a hold in section 6. These are the rules every mint follows.

**Before the sitting.** `Agent:` confirm the Playwright MCP config carries none of `--save-trace`, `--save-har`,
`--save-session`, `--save-video`. During the sitting, call no `browser_network_request`, `browser_network_requests`,
`browser_console_messages`, snapshot or screenshot.

**Owner and name.** Account-owned on the Soleur account. Name `<key>-soleur-<YYYYMMDD>`, with `<key>` the lowercase key
name (for example `cf_api_token_audit-soleur-20261204`). `expires_on` equal to the 0a/0b expiry.

**Form.** The migration runbook's `### 0a and 0b: mint the new-account tokens` hand-off, with one change: the
`page.evaluate` POST goes to `/api/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/tokens` with the session `x-atok`. The
`page.request.post` sink to `127.0.0.1` and its mode-0600 file in the session scratchpad stay unchanged. Mint and
policy read-back run in one `browser_run_code_unsafe` body. The body returns only names, 8-character prefixes, counts,
statuses and `e.name`. The POST response, `result.value`, `x-atok` and the full id stay Node-local.

**Account-owned limits.** Since Cloudflare's 2026-10-01 change, API Token Provisioning members can create account
tokens, and can grant only permissions they hold. The docs do not say whether zone groups are selectable on an
account token, or whether GraphQL accepts one. The permission-group read and the post-swap zone-tag query settle both.
A key whose group the account list lacks is minted user-owned and recorded on #12931. A GraphQL refusal on the
account-owned ANALYTICS token re-mints that key user-owned. A user-owned fallback uses a login other than the
old-account owner; with none available, that mint stays a hold, recorded on #12931 (CTO F21).

**Policy read-back** (CTO F9'). Pass only if all of these hold:

- every resource key is exactly `com.cloudflare.api.account.zone.951ce525552201ec6c696b24251abed7` (zone groups) or
  `com.cloudflare.api.account.66d4f93f7397f196544e9fe84c3557c2` (account groups, AUDIT only);
- every resource value is `"*"`, and no key contains `*`;
- every policy has `effect=allow`;
- the group set equals the `P5-SCOPE` set for that key.

An account-scope resource that carries zone groups fails: it grants every zone in the account, including future ones.
On any failure, delete that new token in the same session and re-mint. Nothing reaches Doppler first.

**After the mint.** The `_NEXT` write is the hold's own command. Then, `Agent:`

1. Compare digests, printing only the verdict:

   ```bash
   a="$(doppler secrets get <KEY>_NEXT -p soleur -c prd_terraform --plain | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | sha256sum)"; b="$(LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/<key>.tok" | sha256sum)"; if [[ "$a" == "$b" ]]; then echo digest=equal; else echo digest=differ; fi; unset a b
   ```

   Expected: `digest=equal`. Never print the `sha256sum` output.
2. Verify the token at the account endpoint first (the user endpoint only for a user-owned fallback):

   ```bash
   doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$<KEY>_NEXT" \
     | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://api.cloudflare.com/client/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/tokens/verify' \
     | jq -r '"success=\(.success) status=\(.result.status // "none")"'
   ```

   Expected: `success=true status=active`. An account-owned token is unknown to `/user/tokens/verify`; never read that
   alone as dead.
3. `shred -u "<scratchpad>/<key>.tok"`.
4. `git status --porcelain` in the main checkout and in the worktree. Expected: no new untracked file.

**ANALYTICS paste fallback.** If the hand-off fails for the owner mint, the owner types the value in the owner's own
terminal, never in the chat, never with the `!` prefix and never in argv. The ANALYTICS mint hold covers it:

```bash
read -rs v; printf '%s' "$v" | doppler secrets set CF_API_TOKEN_ANALYTICS_READ_NEXT -p soleur -c prd_terraform --silent >/dev/null; unset v
```

## 6. Stages and holds

The bootstrap's stages are `inventory` (read), `swap` (write), `holder-copies` (write) and `verify` (read). `swap`
copies `<KEY>` to `<KEY>_PREV`, reads it back by digest, then copies `<KEY>_NEXT` to `<KEY>`, reads it back, and only
then deletes `<KEY>_NEXT`. `holder-copies` writes prd_terraform `<KEY>` to each manifest holder that still holds the
old value. `verify` prints `SOLEUR_P5_VERIFY key=<KEY> verdict=ok|fail reason=<r>` and, on `ok`,
`SOLEUR_P5_REVOKE_READY key=<KEY> old_id=<pinned> new_id=<8>`. No stage calls the dashboard, deletes a token, or writes
`soleur-infra-privileged`.

Each line below runs only after the operator's typed go naming that exact command in the session
(`hr-menu-option-ack-not-prod-write-auth`). One typed go may quote all three mint commands together, each named in
full; every other line takes its own go. Bootstrap applies run from a `main` checkout after merge. `<B>` is the path
section 1 printed. `<D>` is the digest the stage's plan run prints, relayed verbatim with its `SOLEUR_BOOTSTRAP_IMPACT`
and `SOLEUR_BOOTSTRAP_ROLLBACK` lines. The `_NEXT` writes are the migration runbook's `### 0a and 0b` hand-off step 2
command with `<KEY>` substituted. Each mint go cites the #12931 `P5-SCOPE` comment. In order:

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

Not holds (`Agent:`, read-only or GitHub record): every `inventory` and `verify` run, the plan run of each write
stage, the policy and permission-group reads in the signed-in session, the drift checks, and the #12931 and #12983
comments.

After `swap`, `verify` gates ANALYTICS on a minimal GraphQL query that must return the new zone tag with no `errors`
(`zone_tag=match errors=0`). It prints `analytics-health 1` as a non-gating line. The new zone is on the Free plan, so
an `api-error (graphql: ...)` there after a passing zone-tag query is a plan limit: record it on #12931; it does not
block the ANALYTICS revoke.

## 7. Revoke

Use the migration runbook's `## Revoke recipe`, steps 2 to 4, on prd_terraform `<KEY>_PREV`. Its step 1 inventory is
replaced here by this bootstrap's `verify` (CTO F13):

1. `Agent:` run `DOPPLER_TOKEN="$(doppler configure get token --plain)" bash <B> --stage verify` in the revoke
   sitting. `verify` runs `scripts/check-cloudflare-token-drift.sh --only <KEY>`, which reads only `DOPPLER_TOKEN`
   (it snapshots and unsets it); without it `verify` fails `reason=drift` and never reads ok. The token goes into
   the environment, never argv or the screen. Go on only for a key with a line `SOLEUR_P5_REVOKE_READY key=<KEY>`
   printed in this sitting, with nothing written to that key since.
2. `Agent:` recipe step 2 on prd_terraform `<KEY>_PREV`. Its id prefix must equal the pinned prefix.
3. Recipe step 3 is the revoke hold. Sign in as the old-account-owner login and reload `/profile/api-tokens` first
   (a page not reloaded since sign-in showed 0 tokens on 2026-11-26). The body takes three literals: the pinned
   prefix, the `REVOKE_READY` `old_id` and the `new_id`. It refuses unless the first two are equal and differ from
   `new_id`. It also refuses a dashboard match whose name equals the new token's `<key>-soleur-<YYYYMMDD>` name
   (CTO F21). It returns only `{atok: false}`, `{matches: <n>}`, `{refused: <reason>}`,
   `{status, contentType, success}` or `{error: e.name}`.
4. Recipe step 4 read-back: re-run recipe step 2. Only a line that starts `success=false` confirms the revoke. Any
   other output: stop, post it on #12931, keep the key.
5. The `_PREV` key delete holds run once per key, after all three revokes (CTO F14). Then `Agent:` re-run
   `bash <B> --stage inventory`. Expected: `source=none` and no `<KEY>_PREV` row.
6. `Agent:` post on #12931, marker line `P5-REVOKED`: per key, the id prefix, the revoke status, the
   `success=false` read-back and the key gone.

Closing check, `Agent:`

- Run the full `bash scripts/check-cloudflare-token-drift.sh`. Expected: no DEAD `CF_API_TOKEN*` value. A DEAD row
  names a copy to delete, never a rotation.
- Post the post-swap `cloudflare-readonly.sh pagerules-ssl` rule counts on #12931, marker line `P5-PAGERULES-FATE`.
  That is the deferred fate read for `CF_API_TOKEN_PAGERULES_READ`.

A later rotation of an account-owned token revokes it with
`DELETE /accounts/66d4f93f7397f196544e9fe84c3557c2/tokens/<id>`, not the user-token path.

## 8. `CF_API_TOKEN_PURGE_PREV`

Revoke `9e4ce00e` only at migration runbook Phase 3 step 5, after a share revoke answers `200`. Use that runbook's
`## Revoke recipe`. Its step 1 inventory is the archived #12931 bootstrap, which covers PURGE. This bootstrap does not
handle PURGE (CTO F15). The running containers still hold the old purge token until the release redeploy, and #12937
blocks that redeploy. The hold is the last line of section 6.

## 9. Origin CA and R2

- **Origin CA** (`34acd675`): held in `soleur-infra-privileged/prd` as `CF_API_TOKEN_ORIGIN_CA`. Its re-scope to the
  new zone is migration runbook Phase 3 step 4, owned by #12958 (CTO F7). Nothing here touches it.
- **R2** (`bb4a334a`): held in `soleur-infra-privileged/prd` as `CF_API_TOKEN_R2`. It stays: the old account keeps R2
  (ADR-329).

No stage writes `soleur-infra-privileged`.

## 10. GitHub repo secrets

The repo secrets `CF_API_TOKEN` and `CF_ACCOUNT_ID` exist. Both were last updated 2026-11-02, before the move, so they
hold pre-move values. GitHub does not let anyone read them back. Their only reader is
`scheduled-followthrough-sweeper.yml`, through `scripts/followthroughs/ga-lb-pool-soak-6027.sh`. That script checks
only presence and shape, then exits NOT YET before any network call while Load Balancing is off.

They stay as they are (CTO F3). Before Load Balancing returns, repoint them to a least-privilege Load Balancing read
token on the new account. That is a precondition of #12983 (marker `P5-GH-SECRET` on that issue).

## 11. Rotation

The bootstrap stays as the rotation tool. The Phase 5 cleanup PR does not delete it. A rotation edits only the
manifest block at the top of the script (key, pinned old id, holders), then runs sections 4 to 7 again. All three
tokens share the 0a/0b expiry, so one sitting rotates them all. Reminder: #13085 (rotate before the ~2027-02-20
expiry). The drift-script expiry warning is #13086.

## 12. Halt

- Fix forward. Stop at the last verified step, fix in a reviewed PR, re-run.
- A copy that does not read back equal stops the stage. Later keys stay untouched and `<KEY>_NEXT` is kept.
- Never revoke without a `SOLEUR_P5_REVOKE_READY` line from the same sitting.
- `verify` `fail reason=census-blind` (zero old hits) or `SOLEUR_P5_UNREADABLE`: stop. The census cannot see; do not
  revoke.
- A holder with `value=other`, or a non-manifest config with `value=old`: stop, post it on #12931, decide that holder
  first.
- A `soleur-infra-privileged` holder of an old value is a stop. No stage writes there. Post it on #12931 and decide it
  in a reviewed change.
- `429`, `5xx` or a transport failure on a verify read is `unreachable`, never a verdict. Re-run the read; never
  re-mint on it alone.
- A failed policy read-back: delete the new token and re-mint before any Doppler write.
