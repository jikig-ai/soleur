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

Epic: #12931 (Ref only; this runbook never closes it). Plan: the file matching
`knowledge-base/project/plans/**/*2026-11-27-chore-cf-phase5-old-login-token-remint-plan.md`. Rulings: the
`decision-challenges.md` beside the bootstrap (section 1 resolves its directory; archive-kb moves both under
`archive/`, so match by glob, never by a fixed path).

This is the token slice of `## Phase 5 — cleanup PR (after Phase 3 verification)` in
`cloudflare-account-migration.md` (the migration runbook). It replaces three read tokens that the old-account-owner
login still owns. It also records where the other three old-login tokens live and when each one goes. The rest of
Phase 5 waits for Phase 3 (tunnel re-home, #12958) and the release redeploy that #12937 blocks.

The bootstrap the migration runbook's Phase 5 deletes is the archived cf-account-migration bootstrap; this runbook's
`bootstrap.sh` is the standing rotation tool (CTO F18) and is never deleted by that cleanup (CTO D4).

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
2. `Agent:` run `bash <B> --list`, then `bash <B> --stage inventory`. Read an inventory row only after the run
   printed `SOLEUR_BOOTSTRAP_STAGE_OK stage=inventory`; a run that ends without it decided nothing, and a key with no
   row is not `none`. Run each write stage per the `soleur:operator-bootstrap` protocol: the plan run (`bash <B>
   --stage <stage>`) prints `SOLEUR_BOOTSTRAP_PLAN stage=<s> operations=<n> digest=<D>`, the
   `SOLEUR_BOOTSTRAP_IMPACT` and `SOLEUR_BOOTSTRAP_ROLLBACK` lines, and the exact apply command on the line after
   `SOLEUR_BOOTSTRAP_APPLY_COMMAND`. Relay the impact and rollback lines verbatim, and issue that printed command
   verbatim at the hold; `<D>` is its `--plan-digest` value. A plan that says `operations=0` is already done.
   `PRECONDITION_FAILED need=<stage>` means run that stage first.
3. `Agent:` map the inventory rows to the next step, per key:

   | Inventory shows (per key) | Next step |
   |---|---|
   | `SOLEUR_P5_REFERENCE source=KEY` and `SOLEUR_P5_STAGED next=absent` | Section 4 scope, then the section 5 mint |
   | `source=KEY` and `SOLEUR_P5_STAGED next=present` | `swap` |
   | `source=PREV` and `SOLEUR_P5_STAGED next=present` (an interrupted swap) | `swap` again: it finishes the copy or only deletes `_NEXT` |
   | `CF_API_TOKEN_AUDIT` row `SOLEUR_P5_HOLDER project=soleur config=dev_personal` or `config=dev_scheduled` `value=old` | the two AUDIT delete holds |
   | `source=PREV` and a manifest holder row `value=old` outside prd_terraform | `holder-copies` |
   | `source=PREV` and every manifest holder `value=new` | `verify` |
   | `verify` printed `SOLEUR_P5_REVOKE_READY key=<KEY>` in this sitting | section 7 revoke |
   | `source=none`, `SOLEUR_P5_STAGED prev=present`, and that key's revoke read-back started `success=false` | that key's `_PREV` delete hold (section 7 step 5) |
   | `source=none` and `SOLEUR_P5_STAGED prev=present`, with no `success=false` read-back on record | stop: `_PREV` does not verify the pinned old id and no revoke explains it; post it on #12931 |
   | `source=none` and `SOLEUR_P5_STAGED prev=absent` | done; run the section 7 closing check |
   | `SOLEUR_P5_UNREADABLE`, `SOLEUR_P5_CENSUS_BLIND`, `SOLEUR_P5_FLOOR_MISSING`, `SOLEUR_P5_REFERENCE source=unknown` or a holder row `value=other` | stop; see section 12 |

4. Logins, in three sittings. A person signs in because each login needs its own password and second factor, which
   the agent never holds:
   1. Old-account-owner login: the section 4 read of the old tokens' policies (only the owning login lists them).
   2. A login that can mint account-owned tokens on the Soleur account: the section 4 permission-group read, the
      section 5 mints and the policy read-back.
   3. Old-account-owner login again: the section 7 revokes.

   The agent asks for the right login at each sitting. It never switches logins itself.

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
| `CF_API_TOKEN_ANALYTICS_READ` | `cloudflare-readonly.sh analytics-*` | `POST /graphql` (`httpRequestsAdaptiveGroups` on the zone) | Zone: Analytics Read, plus Zone Read when the old token's policies carry it (`origin-tls-strict-flip.md` records the original grant as Analytics Read and Zone Read). Owner mint. |
| `CF_API_TOKEN_PAGERULES_READ` | `cloudflare-readonly.sh pagerules-ssl` | `GET /zones/<zone>/pagerules?status=active` | Zone: Page Rules Read |

Reconcile rule, at the mint sitting, before any mint:

1. `Agent:` in the signed-in dashboard session, read the live account permission groups
   (`GET /api/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/tokens/permission_groups`). Return names and 8-character
   id prefixes only. Never type a group name from memory. The mint body (`p5-mint.js`) resolves each name to its full
   id itself and refuses a name that matches no selectable group or more than one, so the prefixes are for the
   record only.
2. `Agent:` read the old token's policies (`GET /api/v4/user/tokens`). This lists only the signed-in login's own
   tokens, so it needs the old-account-owner login. Return group names and resource counts only.
3. Re-scope to the new account and zone. Trim to the endpoints in this table.
4. Post the final groups per key on #12931 with the marker line `P5-SCOPE`. Each mint go cites that comment.

The `P5-SCOPE` set is an allowlist built from this table. It is never the old token's policies with groups trimmed
off. The old policies are read only to surface a consumer this table missed. Every group is a Read group.

## 5. Mint

Each mint is a hold in section 6. These are the rules every mint follows.

**Committed bodies (CTO D1).** The dashboard steps run committed code, never code written at the hold. Beside `<B>`:
`p5-mint.js` (permission-group resolve, account-token POST, policy read-back, sink hand-off), `p5-revoke.js` (the
guarded delete, section 7) and `p5-sink.py` (the 127.0.0.1 receiver), pinned by `p5-browser.sha256`:

```text
p5-mint.js sha256=d358583ec1db78adb924cc797cb63a5976c4d3f67a5ae940c158231049398b87
p5-revoke.js sha256=be0159a2326912e50077cd06c76e6be0e4eb6275105e59d8969fc5035fe86d2b
p5-sink.py sha256=288afd38c1374c1d9863c8689dabede606153d09a2e19ae111da6c561b02cdf8
```

Each JS file is one expression `(args) => async (page) => {...}` that takes a single JSON argument object. The
agent never edits it: it checks the pins, wraps the file with the argument literal the hold names, and runs the
result with Playwright MCP `browser_run_code_unsafe` (`filename:` the run file):

```bash
D="$(dirname <B>)"; (cd "$D" && sha256sum -c --quiet p5-browser.sha256) && mkdir -p "<repo>/.playwright-mcp" && { printf '('; cat "$D/p5-<x>.js"; printf ')(%s)\n' '<ARGS-JSON>'; } > "<repo>/.playwright-mcp/p5-<x>.run.js"
```

`<repo>` is the checkout root; `.playwright-mcp/` is gitignored. The tool echoes the code it ran, so an argument
object carries only ids, names, dates and the sink URL, never a secret. Placeholders: `<YYYYMMDD>` is the mint date
(UTC); `<scratchpad>` is the absolute path of this session's scratchpad directory.

**Before the sitting.** `Agent:` confirm the Playwright MCP server the session uses carries none of `--save-trace`,
`--save-har`, `--save-session`, `--save-video`: run `claude mcp get playwright` (and `claude mcp get
plugin:soleur:playwright` for the plugin server) and read its args. During the sitting, call no
`browser_network_request`, `browser_network_requests`, `browser_console_messages`, snapshot or screenshot.

**Owner and name.** Account-owned on the Soleur account. Name `<key>-soleur-<YYYYMMDD>`, with `<key>` the lowercase key
name (for example `cf_api_token_audit-soleur-20261204`). `expires_on` equal to the 0a/0b expiry, read with:

```bash
doppler run -p soleur -c prd_terraform --no-fallback --only-secrets CF_API_TOKEN_PURGE -- bash -c '(LC_ALL=C; case "$CF_API_TOKEN_PURGE" in ""|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo "refused: bad shape"; exit 1; }; printf "header = \"Authorization: Bearer %s\"\n" "$CF_API_TOKEN_PURGE" | curl --disable --noproxy "*" -sS --max-time 30 --config - https://api.cloudflare.com/client/v4/user/tokens/verify' | jq -r '"success=\(.success) expires_on=\(.result.expires_on // "none")"'
```

It prints only `success=` and `expires_on=` for the 0b `CF_API_TOKEN_PURGE` (a user token, so the user endpoint).

**Form.** Per key, in the mint sitting:

1. `Agent:` start the sink in the background, before the mint:
   `python3 -I "$(dirname <B>)/p5-sink.py" --out "<scratchpad>/<key>.tok"`. It prints
   `SOLEUR_P5_SINK url=http://127.0.0.1:<port>/<nonce>`, then exactly one result line: `result=written` (exit 0),
   `result=refused reason=<r>` (exit 1 or 2) or `result=timeout` (exit 3). It accepts one POST from 127.0.0.1 with
   no `Origin` header, writes the value to a new mode-0600 file and never prints it.
2. The mint hold (section 6) runs `p5-mint.js` with the argument object the hold names. The body reads the permission
   groups, refuses an existing token of the same name, POSTs the token with the session `x-atok`, reads the stored
   policy back, and only then hands the value to the sink by a Node-side `fetch` (never `page.request`, so no trace
   or HAR records it). Any failure after the POST deletes the new token in the same body. It returns only
   `{atok:false}`, `{refused:<r>[,matches]}`, `{status,contentType,success[,id8]}` or `{error:<name>[,...]}`: never
   the value, the atok or a full id.

**Account-owned limits.** Since Cloudflare's 2026-10-01 change, API Token Provisioning members can create account
tokens, and can grant only permissions they hold. The docs do not say whether zone groups are selectable on an
account token, or whether GraphQL accepts one. The permission-group read and the post-swap zone-tag query settle both.
A key whose group the account list lacks is minted user-owned and recorded on #12931. A GraphQL refusal on the
account-owned ANALYTICS token re-mints that key user-owned. A user-owned fallback uses a login other than the
old-account owner; with none available, that mint stays a hold, recorded on #12931 (CTO F21).

**Policy read-back** (CTO F9'), checked inside `p5-mint.js`. It passes only if all of these hold:

- every resource key is exactly `com.cloudflare.api.account.zone.951ce525552201ec6c696b24251abed7` (zone groups) or
  `com.cloudflare.api.account.66d4f93f7397f196544e9fe84c3557c2` (account groups, AUDIT only);
- every resource value is `"*"`, and no key contains `*`;
- every policy has `effect=allow`;
- the group set equals the `P5-SCOPE` set for that key, and the name, expiry and status read back as sent.

An account-scope resource that carries zone groups fails: it grants every zone in the account, including future ones.
On any failure the body deletes the new token and returns `refused:"readback"`; re-mint. Nothing reaches Doppler first.

**After the mint.** The `_NEXT` write is the hold's own command. Then, `Agent:`

1. Compare digests, printing only the verdict. Both reads must succeed and be non-empty:

   ```bash
   set -o pipefail; e="$(printf '' | sha256sum)"; a="$(doppler secrets get <KEY>_NEXT -p soleur -c prd_terraform --plain | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | sha256sum)" || a=fail; b="$(LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/<key>.tok" | sha256sum)" || b=fail; if [[ "$a" == fail || "$b" == fail || "$a" == "$e" || "$b" == "$e" ]]; then echo digest=unreadable; elif [[ "$a" == "$b" ]]; then echo digest=equal; else echo digest=differ; fi; unset a b e
   ```

   Expected: `digest=equal`. `unreadable` or `differ`: stop. Never print the `sha256sum` output.
2. Verify the token at the account endpoint first (the user endpoint only for a user-owned fallback). The value is
   shape-checked before it reaches a header:

   ```bash
   doppler run -p soleur -c prd_terraform --no-fallback --only-secrets <KEY>_NEXT -- bash -c 'v="$<KEY>_NEXT"; (LC_ALL=C; case "$v" in ""|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo "refused: bad shape"; exit 1; }; printf "header = \"Authorization: Bearer %s\"\n" "$v" | curl --disable --noproxy "*" -sS --max-time 30 --config - https://api.cloudflare.com/client/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/tokens/verify' | jq -r '"success=\(.success) status=\(.result.status // "none")"'
   ```

   Expected: `success=true status=active`. An account-owned token is unknown to `/user/tokens/verify`; never read that
   alone as dead.
3. Delete the `.tok` file on EVERY path, the stop paths included (a refused digest, a failed verify, a refused
   read-back): `shred -u "<scratchpad>/<key>.tok" 2>/dev/null || rm -P "<scratchpad>/<key>.tok" 2>/dev/null || rm -f "<scratchpad>/<key>.tok"`
   (stock macOS has no `shred`).
4. Closing check of the sitting: `find "<scratchpad>" -name '*.tok' | grep -c .` prints `0`, and
   `git status --porcelain --ignored | grep -c '\.tok$'` prints `0` in the main checkout and in the worktree.

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
`SOLEUR_P5_REVOKE_READY key=<KEY> old_id=<pinned> new_id=<8> owner=<account|user>`. No stage calls the dashboard,
deletes a token, or writes `soleur-infra-privileged`. The bootstrap runs only committed helper bytes (a working-tree
edit to a tool it runs is `SOLEUR_P5_UNTRUSTED_FILE`), and refuses a redirecting environment (a git location
variable, `DOPPLER_API_HOST`, or an exported function named like a tool it calls: `SOLEUR_P5_ENV_REFUSED`, exit 64).

### Markers

Names, 8-character ids, classes and exit codes only; never a value or a digest.

| Marker | Stage | Meaning |
|---|---|---|
| `SOLEUR_P5_REFERENCE key= source=KEY\|PREV\|none\|unknown` | inventory, verify | where the pinned old id was found; `unknown` = no verdict, re-run |
| `SOLEUR_P5_STAGED key= next= prev=` | inventory | whether `<KEY>_NEXT` and `<KEY>_PREV` exist (`present`/`absent`) |
| `SOLEUR_P5_HOLDER project= config= key= value=old\|new\|other\|absent` | inventory, verify | one census row per config holding the key name |
| `SOLEUR_P5_CENSUS key= configs_read= old_hits=` | inventory, verify | census totals |
| `SOLEUR_P5_CENSUS_BLIND key= source=` | inventory | the reference could not be read, so the census decided nothing |
| `SOLEUR_P5_FLOOR_MISSING name=` / `SOLEUR_P5_CENSUS_FLOOR verdict=fail reason=floor-missing` | inventory, verify | the listing lacks a project or config of the committed floor (CTO D2) |
| `SOLEUR_P5_UNREADABLE project= config= [name=]` | inventory, verify | a listed config or name could not be read; never `absent` |
| `SOLEUR_P5_KEY key= id= status= owner=` | verify | the current `<KEY>` token's identity |
| `SOLEUR_P5_CONSUMER key= sub= gating= rc= line=` / `SOLEUR_P5_GRAPHQL key= zone_tag= errors=` | verify | the consumer read and the ANALYTICS zone-tag gate |
| `SOLEUR_P5_HOLDER_NOT_NEW key= holder= value=` | verify | a manifest holder does not hold the new value |
| `SOLEUR_P5_OLD_HOLDER key= holder=` | verify | a config other than prd_terraform `_PREV` still holds the old value |
| `SOLEUR_P5_VERIFY key= verdict=ok\|fail reason=` | verify | per-key verdict; a final `SOLEUR_P5_VERIFY verdict=` line covers all keys |
| `SOLEUR_P5_REVOKE_READY key= old_id= new_id= owner=` | verify | the only line that admits a revoke, in the same sitting |
| `SOLEUR_P5_SWAPPED key= staging=deleted verified=digest` | swap | the key holds the new token and `_NEXT` is gone |
| `SOLEUR_P5_PREV_NOT_PINNED`, `SOLEUR_P5_PREV_LIVE`, `SOLEUR_P5_KEY_UNEXPECTED`, `SOLEUR_P5_NEXT_NOT_DISTINCT`, `SOLEUR_P5_SWAP_MISMATCH`, `SOLEUR_P5_DELETE_NOT_CONFIRMED` | swap | refusals: `_PREV` not the old token; `_PREV` holds a live non-pinned token; `<KEY>` neither old nor staged; `_NEXT` equals another `CF_API_TOKEN*` key; a copy did not read back; a delete did not take |
| `SOLEUR_P5_COPIED` / `SOLEUR_P5_COPY_MISMATCH` / `SOLEUR_P5_HOLDER_COPY` / `SOLEUR_P5_HOLDER_REFUSED` | swap, holder-copies | a digest-verified copy, a failed one, a planned holder copy, a holder not written |
| `SOLEUR_P5_TOKEN_MALFORMED` / `SOLEUR_P5_TOKEN_UNREACHABLE` | any | a value that is not a token shape; a verify read with no verdict (429, 5xx, transport): re-run, never re-mint |
| `SOLEUR_P5_MANIFEST_INVALID line= reason=` / `SOLEUR_P5_MANIFEST_EMPTY` | any | the manifest block does not parse; fix it in a reviewed PR |

`verify` `reason=` values, in the order it checks them: `unreachable` (re-run), `key-malformed`, `key-unreadable`,
`key-not-verified`, `key-not-active`, `key-is-old` (the swap has not run), `next-staged` (run `swap`), `no-reference`,
`prev-not-active`, `target-ids-not-new`, `consumer-read`, `census-floor`, `census-unreadable`, `old-holder` (run
`holder-copies`, or decide that holder), `census-blind`, `holder-not-new` (run `holder-copies`). Every reason other
than `unreachable` and the three that name a stage to run is a stop: see section 12.

Each line below runs only after the operator's typed go naming that exact command in the session
(`hr-menu-option-ack-not-prod-write-auth`). One typed go may quote all three mint commands together, each named in
full; every other line takes its own go. Bootstrap applies run from a `main` checkout after merge. `<B>` is the path
section 1 printed. A bootstrap apply is the command its plan run printed after `SOLEUR_BOOTSTRAP_APPLY_COMMAND` in
this sitting, issued verbatim, with the `SOLEUR_BOOTSTRAP_IMPACT` and `SOLEUR_BOOTSTRAP_ROLLBACK` lines relayed first.
A mint hold names the `p5-mint.js` argument object in full; `<groups>` is that key's `P5-SCOPE` list, `<expiry>` the
`expires_on` read in section 5, and `<sink>` the `SOLEUR_P5_SINK url=` the sink printed. Each mint go cites the
#12931 `P5-SCOPE` comment. The swap go quotes, per key, the `new_id=` and `owner=` on the plan's
`copy-staged-token` operation line; they must equal the `id8` the mint returned (CTO D5). A revoke hold's `pin` is the
key's pinned id in the bootstrap's `# P5-MANIFEST` block (today `86aa993e`, `dd6d1427`, `5993721f`). In order:

- Hold: Operator-authorizes: account-owned mint of `CF_API_TOKEN_PAGERULES_READ`: `p5-mint.js` (sha256=d358583ec1db78adb924cc797cb63a5976c4d3f67a5ae940c158231049398b87) with `{"account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_pagerules_read-soleur-<YYYYMMDD>","zone_groups":<groups>,"account_groups":[],"expires_on":"<expiry>","sink_url":"<sink>"}`, then `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_pagerules_read.tok" | doppler secrets set CF_API_TOKEN_PAGERULES_READ_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: account-owned mint of `CF_API_TOKEN_AUDIT`: `p5-mint.js` (same sha256) with `{"account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_audit-soleur-<YYYYMMDD>","zone_groups":<zone groups>,"account_groups":<account groups>,"expires_on":"<expiry>","sink_url":"<sink>"}`, then `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_audit.tok" | doppler secrets set CF_API_TOKEN_AUDIT_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: owner mint of `CF_API_TOKEN_ANALYTICS_READ` (account-owned): `p5-mint.js` (same sha256) with `{"account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_analytics_read-soleur-<YYYYMMDD>","zone_groups":<groups>,"account_groups":[],"expires_on":"<expiry>","sink_url":"<sink>"}` or the owner's paste (section 5), then `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_analytics_read.tok" | doppler secrets set CF_API_TOKEN_ANALYTICS_READ_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT -p soleur -c dev_personal --yes > /dev/null` (CTO F20), only after a `bash <B> --stage inventory` run in this sitting printed `SOLEUR_P5_HOLDER project=soleur config=dev_personal key=CF_API_TOKEN_AUDIT value=old`. Rollback (that row proved the deleted value is the old token): `doppler secrets get CF_API_TOKEN_AUDIT -p soleur -c prd_terraform --plain | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | doppler secrets set CF_API_TOKEN_AUDIT -p soleur -c dev_personal --silent > /dev/null` before the swap, or the same with `CF_API_TOKEN_AUDIT_PREV` as the source after it
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT -p soleur -c dev_scheduled --yes > /dev/null`, only after a same-sitting row `SOLEUR_P5_HOLDER project=soleur config=dev_scheduled key=CF_API_TOKEN_AUDIT value=old`; rollback as above with `-c dev_scheduled`
- Hold: Operator-authorizes: `bash <B> --stage swap --apply --plan-digest <D>` (the printed apply command)
- Hold: Operator-authorizes: `bash <B> --stage holder-copies --apply --plan-digest <D>` (the printed apply command)
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_PAGERULES_READ` old id `86aa993e`: `p5-revoke.js` (sha256=be0159a2326912e50077cd06c76e6be0e4eb6275105e59d8969fc5035fe86d2b) with `{"pin":"86aa993e","old_id":"<old_id>","new_id":"<new_id>","new_name":"cf_api_token_pagerules_read-soleur-<YYYYMMDD>","scope":"user"}`, signed in as the old-account-owner login, only after `bash <B> --stage verify` printed `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_PAGERULES_READ old_id=86aa993e` in the same sitting (`<old_id>` and `<new_id>` copied from that line)
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_AUDIT` old id `dd6d1427`: `p5-revoke.js` (same sha256) with `{"pin":"dd6d1427","old_id":"<old_id>","new_id":"<new_id>","new_name":"cf_api_token_audit-soleur-<YYYYMMDD>","scope":"user"}`, only after a same-sitting `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_AUDIT old_id=dd6d1427`
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_ANALYTICS_READ` old id `5993721f`: `p5-revoke.js` (same sha256) with `{"pin":"5993721f","old_id":"<old_id>","new_id":"<new_id>","new_name":"cf_api_token_analytics_read-soleur-<YYYYMMDD>","scope":"user"}`, only after a same-sitting `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_ANALYTICS_READ old_id=5993721f`
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_PAGERULES_READ_PREV -p soleur -c prd_terraform --yes > /dev/null` (only after that key's revoke read-back, section 7 step 4, started `success=false`)
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT_PREV -p soleur -c prd_terraform --yes > /dev/null` (same condition, for that key)
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_ANALYTICS_READ_PREV -p soleur -c prd_terraform --yes > /dev/null` (same condition, for that key)
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_PURGE_PREV` (`9e4ce00e`) with the migration runbook revoke recipe on prd_terraform `CF_API_TOKEN_PURGE_PREV`, at its Phase 3 step 5 only (after the release redeploy that #12937 blocks and a share revoke answering `200`), then `doppler secrets delete CF_API_TOKEN_PURGE_PREV -p soleur -c prd_terraform --yes > /dev/null` on a `success=false` read-back

Not holds (`Agent:`, read-only or GitHub record): every `inventory` and `verify` run, the plan run of each write
stage, the policy and permission-group reads in the signed-in session, the drift checks, and the #12931 and #12983
comments.

After `swap`, `verify` gates ANALYTICS on a minimal GraphQL query that must return the new zone tag with no `errors`
(`zone_tag=match errors=0`). It prints `analytics-health 1` as a non-gating line. The new zone is on the Free plan, so
an `api-error (graphql: ...)` there after a passing zone-tag query is a plan limit: record it on #12931; it does not
block the ANALYTICS revoke.

## 7. Revoke

Use the migration runbook's `## Revoke recipe` read steps (**recipe step 2**, the `_PREV` id read, and **recipe step
4**, the read-back) on prd_terraform `<KEY>_PREV`. Its step 1 inventory is replaced here by this bootstrap's `verify`
(CTO F13), and its step 3 delete body by `p5-revoke.js` (CTO D1):

1. `Agent:` run `bash <B> --stage verify` in the revoke sitting. Go on only for a key with a line
   `SOLEUR_P5_REVOKE_READY key=<KEY> old_id=<8> new_id=<8> owner=<account|user>` printed in this sitting, with
   nothing written to that key since. Match the line by its leading `SOLEUR_P5_REVOKE_READY key=<KEY>` plus one space, and read the
   fields from it.
2. `Agent:` recipe step 2 on prd_terraform `<KEY>_PREV`. Its id prefix must equal the pinned prefix. The old tokens
   are user tokens, so `/user/tokens/verify` answers for them.
3. The revoke hold. Sign in as the old-account-owner login and reload `/profile/api-tokens` first (a page not reloaded
   since sign-in showed 0 tokens on 2026-11-26). Run `p5-revoke.js` with the hold's argument object. Before any
   request it refuses `pin` unless the pin equals `old_id`, and `same-id` when `old_id` equals `new_id`. It then lists
   every page of the login's tokens, needs exactly one id starting with `old_id` (else `{matches:<n>}`), and refuses
   `name` when that token's name equals the new token's `<key>-soleur-<YYYYMMDD>` name (CTO F21). It returns only
   `{atok:false}`, `{refused:<reason>}`, `{matches:<n>}`, `{status,contentType,success}` or `{error:<name>}`.
4. Recipe step 4 read-back: re-run recipe step 2. Only a line that starts `success=false` confirms the revoke. Any
   other output: stop, post it on #12931, keep the key.
5. The `_PREV` key delete holds run once per key, after all three revokes (CTO F14). Between a key's revoke and its
   `_PREV` delete, `inventory` shows `SOLEUR_P5_REFERENCE key=<KEY> source=none` with
   `SOLEUR_P5_STAGED key=<KEY> next=absent prev=present`: that is the expected state, routed by the section 1 table.
   After the delete, `Agent:` re-run `bash <B> --stage inventory`. Expected: `source=none` and
   `SOLEUR_P5_STAGED key=<KEY> next=absent prev=absent`.
6. `Agent:` post on #12931, marker line `P5-REVOKED`: per key, the id prefix, the revoke status, the
   `success=false` read-back and the key gone.

Closing check, `Agent:`

- Run the full drift check, with the personal Doppler token set for that one process only (CTO D3: this is the only
  drift run): `DOPPLER_TOKEN="$(doppler configure get token --plain)" bash scripts/check-cloudflare-token-drift.sh`.
  Run it from the directory where `doppler login` was done (`configure get` resolves by directory scope; an empty
  token fails closed). Expected: no DEAD `CF_API_TOKEN*` value. A DEAD row names a copy to delete, never a rotation.
- Post the post-swap `cloudflare-readonly.sh pagerules-ssl` rule counts on #12931, marker line `P5-PAGERULES-FATE`.
  That is the deferred fate read for `CF_API_TOKEN_PAGERULES_READ`.

Finding the records from a fresh session: `gh issue view 12931 --comments --json comments --jq '.comments[] |
select(.body | test("^P5-(SCOPE|REVOKED|PAGERULES-FATE|TOKEN-FACTS|BOOTSTRAP-POINTER)"; "m")) | .url'`.

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

The bootstrap stays as the rotation tool; the migration runbook's Phase 5 cleanup does not delete it (CTO D4). A
rotation edits the manifest block at the top of the script (key, pinned old id, holders) and regenerates this
runbook's section 2 facts and the section 6 hold lines (their `pin` values and names), then runs sections 4 to 7
again. All three tokens share the 0a/0b expiry, so one sitting rotates them all. Reminder: #13085 (rotate before the
~2027-02-20 expiry). The drift-script expiry warning is #13086.

The tokens this runbook mints are account-owned, so a rotation's `_PREV` is account-owned too:

- its id read (recipe step 2) and read-back (recipe step 4) use `/accounts/66d4f93f7397f196544e9fe84c3557c2/tokens/verify`,
  never `/user/tokens/verify`, which answers `success=false` for an account-owned token and would read as a revoke
  that never happened;
- its revoke runs `p5-revoke.js` with `"scope":"account","account_id":"66d4f93f7397f196544e9fe84c3557c2"`, which lists
  and deletes at `/accounts/<acct>/tokens[/<id>]`;
- a key minted user-owned under the F17 fallback keeps the user-token forms.

## 12. Halt

- Fix forward. Stop at the last verified step, fix in a reviewed PR, re-run.
- A copy that does not read back equal stops the stage. Later keys stay untouched and `<KEY>_NEXT` is kept.
- Never revoke without a `SOLEUR_P5_REVOKE_READY` line from the same sitting.
- Swap rollback, before the old token is revoked: first copy prd_terraform `<KEY>` back to `<KEY>_NEXT`, then copy
  `<KEY>_PREV` over `<KEY>`; a re-run of `swap` re-applies. Copying `_PREV` over `<KEY>` first would destroy the only
  copy of the new token. After the revoke the old token is dead: fix forward.
- `verify` `reason=census-blind`, `census-unreadable` or `census-floor`, or any `SOLEUR_P5_UNREADABLE`,
  `SOLEUR_P5_CENSUS_BLIND` or `SOLEUR_P5_FLOOR_MISSING` line: stop. The census cannot see everything; do not revoke.
  A `FLOOR_MISSING` usually means the Doppler identity lists less than the one that measured the floor (a narrowed
  role): sign in with the identity that lists every floor project, or update the floor in a reviewed PR when a
  project was really removed.
- A holder with `value=other`, or a non-manifest config with `value=old`: stop, post it on #12931, decide that holder
  first.
- A `soleur-infra-privileged` holder of an old value is a stop. No stage writes there. Post it on #12931 and decide it
  in a reviewed change.
- `SOLEUR_P5_UNTRUSTED_FILE` or `SOLEUR_P5_ENV_REFUSED`: run from a clean `main` checkout in a shell without the named
  variable or function. Never commit a local edit to make the check pass.
- `SOLEUR_P5_PREV_LIVE` (a `_PREV` that holds a live token other than the pinned one, a previous rotation's revoke
  skipped) or `SOLEUR_P5_KEY_UNEXPECTED`: stop and post it on #12931; never overwrite it.
- `SOLEUR_P5_NEXT_NOT_DISTINCT`: the staged value equals another `CF_API_TOKEN*` key; re-stage the right `.tok`.
- `429`, `5xx` or a transport failure on a verify read (`SOLEUR_P5_TOKEN_UNREACHABLE`, `reason=unreachable`) is never
  a verdict. Re-run the read; never re-mint on it alone.
- A refused policy read-back: `p5-mint.js` already deleted the new token; re-mint before any Doppler write.
- `SOLEUR_BOOTSTRAP_PLAN_DRIFT` at an apply: the state changed since the plan run (for example a re-staged `_NEXT`,
  which changes the swap op line's `new_id`, CTO D5). Re-run the plan run and take a new go.
