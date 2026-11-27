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
   | `SOLEUR_P5_REFERENCE source=KEY`, `SOLEUR_P5_STAGED next=absent` and `SOLEUR_P5_PREV state=absent` | Section 4 scope, then the section 5 mint |
   | `source=KEY` and `SOLEUR_P5_PREV state=` anything but `absent` or `pinned` | stop: `_PREV` holds something the next swap would overwrite; see section 12 |
   | `source=KEY` and `SOLEUR_P5_STAGED next=present` | `swap` |
   | `source=PREV` and `SOLEUR_P5_STAGED next=present` (an interrupted swap) | `swap` again: it finishes the copy or only deletes `_NEXT` |
   | `CF_API_TOKEN_AUDIT` row `SOLEUR_P5_HOLDER project=soleur config=dev_personal` or `config=dev_scheduled` `value=old` | the two AUDIT delete holds |
   | `source=PREV` and a manifest holder row `value=old` outside prd_terraform | `holder-copies` |
   | `source=PREV` and every manifest holder `value=new` | `verify` |
   | `verify` printed `SOLEUR_P5_REVOKE_READY key=<KEY>` in this sitting | section 7 revoke |
   | `source=none`, `SOLEUR_P5_PREV state=denied`, and a `P5-REVOKED` record for that key and old id (section 7 lookup), or a `REVOKE_READY` for that key earlier in this sitting | that key's `_PREV` delete hold (section 7 step 6). The prd_terraform `<KEY>_PREV` row then reads `value=revoked` and `verify` prints `verdict=revoked`: both expected (CTO D6) |
   | `source=none` and `SOLEUR_P5_PREV state=denied` with neither | stop: something outside this runbook revoked the old token (a leak auto-revoke, say); post it on #12931 |
   | `source=none` and `SOLEUR_P5_PREV state=` `other`, `malformed`, `unreadable` or `unreachable` | `unreachable` or `unreadable`: re-run inventory. Otherwise stop; see section 12 |
   | `source=none`, `SOLEUR_P5_STAGED next=absent prev=absent` | done; run the section 7 closing check |
   | `source=none` and `SOLEUR_P5_STAGED next=present` | stop: a staged token no manifest pin tracks; post it on #12931 |
   | `SOLEUR_P5_UNREADABLE`, `SOLEUR_P5_CENSUS_BLIND`, `SOLEUR_P5_FLOOR_MISSING`, `SOLEUR_P5_REFERENCE source=unknown`, or a holder row `value=other` other than the revoked-`_PREV` row above | stop; see section 12 |

   When two rows match, the first stop row wins over any step row. Re-read a row's precondition in the same sitting
   before acting on it.

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

1. `Agent:` in the signed-in dashboard session, run `p5-read.js` (section 5) with
   `{"what":"groups","scope":"account","acct":"66d4f93f7397f196544e9fe84c3557c2"}`. It returns group names, scopes
   and 8-character id prefixes only. Never type a group name from memory. The mint body (`p5-mint.js`) resolves each
   name to its full id itself and refuses a name that matches no selectable group or more than one, so the prefixes
   are for the record only.
2. `Agent:` signed in as the old-account-owner login (only the owning login lists its tokens), run `p5-read.js` with
   `{"what":"policies","scope":"user","pin":"<pin>"}` once per key. It returns each policy's effect, group names and
   resource counts by kind, never an id or a value.
3. Re-scope to the new account and zone. Trim to the endpoints in this table.
4. Post the final groups on #12931 as one comment of exactly three lines, one per key, each in this form (the
   arrays are JSON, exact group names; `account_groups` is `[]` for the two zone-only keys):

   ```text
   P5-SCOPE CF_API_TOKEN_AUDIT zone_groups=["<name>",...] account_groups=["<name>",...]
   ```

   The mint hold copies both arrays into its argument object as written. Each mint go cites that comment.

The `P5-SCOPE` set is an allowlist built from this table. It is never the old token's policies with groups trimmed
off. The old policies are read only to surface a consumer this table missed. Every group is a Read group.

## 5. Mint

Each mint is a hold in section 6. These are the rules every mint follows.

**Committed bodies (CTO D1, D7).** The dashboard steps run committed code, never code written at the hold. Beside
`<B>`: `p5-read.js` (the two section 4 reads), `p5-mint.js` (permission-group resolve, token POST, policy read-back,
sink hand-off), `p5-revoke.js` (the guarded delete, section 7, and the `retire` delete, section 12) and `p5-sink.py`
(the 127.0.0.1 receiver), pinned by `p5-browser.sha256` and by these values, which each hold quotes:

```text
p5-mint.js sha256=d358583ec1db78adb924cc797cb63a5976c4d3f67a5ae940c158231049398b87
p5-revoke.js sha256=be0159a2326912e50077cd06c76e6be0e4eb6275105e59d8969fc5035fe86d2b
p5-sink.py sha256=288afd38c1374c1d9863c8689dabede606153d09a2e19ae111da6c561b02cdf8
```

Each JS file is one expression `(args) => async (page) => {...}` that takes a single JSON argument object. The
agent never edits it. Before it runs any of them, and before it starts the sink, it checks each file against the
committed blob and the hold's quoted value (`p5-browser.sha256` sits in the same directory, so it is not enough on its
own):

```bash
D="$(dirname <B>)"; ok=1; for f in p5-read.js p5-mint.js p5-revoke.js p5-sink.py; do h="$(git -C "$D" hash-object --no-filters -- "$f")" && r="$(git -C "$D" rev-parse "HEAD:./$f")" && [ -n "$h" ] && [ "$h" = "$r" ] || { echo "SOLEUR_P5_BODY verdict=stop file=$f reason=not-committed"; ok=0; }; done; [ "$ok" = 1 ] && printf '%s  %s\n' '<sha256>' '<file>' | (cd "$D" && sha256sum -c --quiet -) && echo "SOLEUR_P5_BODY verdict=ok file=<file>" || echo "SOLEUR_P5_BODY verdict=stop file=<file>"
```

`<file>` and `<sha256>` are the pair the hold quotes (the sink's pair for the sink). Only `verdict=ok` lets the step
go on. Then it builds the run file. The argument is passed as a JSON string that the body parses, so it can only ever
be data (CTO D9):

```bash
A="$(jq -ce 'if type=="object" then . else error("not an object") end' <<<'<ARGS-JSON>' | jq -Rs .)" && mkdir -p "<repo>/.playwright-mcp" && { printf '('; cat "$D/<file>"; printf ')(JSON.parse(%s))\n' "$A"; } > "<repo>/.playwright-mcp/<file>.run.js"
```

It runs the run file with Playwright MCP `browser_run_code_unsafe` (`filename:` the run file). `<repo>` is the
checkout root; `.playwright-mcp/` is gitignored. The tool echoes the code it ran, so an argument object carries only
ids, names, dates and the sink URL, never a secret. Placeholders: `<YYYYMMDD>` is the mint date
(UTC); `<scratchpad>` is the absolute path of this session's scratchpad directory.

**Before the sitting.** `Agent:` confirm the Playwright MCP server the session uses carries none of `--save-trace`,
`--save-har`, `--save-session`, `--save-video`: run `claude mcp get playwright` (and `claude mcp get
plugin:soleur:playwright` for the plugin server) and read its args. During the sitting, call no
`browser_network_request`, `browser_network_requests`, `browser_console_messages`, snapshot or screenshot.

**Owner and name.** Account-owned on the Soleur account (`"owner":"account"`). Name `<key>-soleur-<YYYYMMDD>`, with `<key>` the lowercase key
name (for example `cf_api_token_audit-soleur-20261204`). `expires_on` equal to the 0a/0b expiry, read with:

```bash
set -o pipefail; doppler run -p soleur -c prd_terraform --no-fallback --only-secrets CF_API_TOKEN_PURGE -- bash -c '(LC_ALL=C; case "$CF_API_TOKEN_PURGE" in ""|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo "refused: bad shape" >&2; exit 1; }; printf "header = \"Authorization: Bearer %s\"\n" "$CF_API_TOKEN_PURGE" | curl --disable --noproxy "*" -sS --max-time 30 --config - https://api.cloudflare.com/client/v4/user/tokens/verify' | jq -er '"success=\(.success) expires_on=\(.result.expires_on // "none")"' || echo verdict=no-read
```

It prints only `success=` and `expires_on=` for the 0b `CF_API_TOKEN_PURGE` (a user token today, so the user
endpoint). `verdict=no-read`, or no `success=true` line: stop; the read decided nothing. `p5-mint.js` refuses an
`expires_on` less than 30 days away, so a sitting close to the 0a/0b expiry rotates 0a/0b first (section 11).

**Form.** Per key, in the mint sitting:

1. `Agent:` once the operator is ready to type the mint go, start the sink as a background task:
   `python3 -I "$(dirname <B>)/p5-sink.py" --out "<scratchpad>/<key>.tok"`, and read the `url=` from that task's
   output. The sink lives 15 minutes and takes one request; a sink that timed out or answered once needs a new sink,
   a new URL and a new go. It prints
   `SOLEUR_P5_SINK url=http://127.0.0.1:<port>/<nonce>`, then exactly one result line: `result=written` (exit 0),
   `result=refused reason=<r>` (exit 1 or 2) or `result=timeout` (exit 3). It accepts one POST from 127.0.0.1 with
   no `Origin` header, writes the value to a new mode-0600 file and never prints it.
2. The mint hold (section 6) runs `p5-mint.js` with the argument object the hold names. The body reads the permission
   groups, refuses an existing token of the same name, POSTs the token with the session `x-atok`, reads the stored
   policy back, and only then hands the value to the sink by a Node-side `fetch` (never `page.request`, so no trace
   or HAR records it). Any failure after the POST deletes every token of that name in the same body. It returns only
   the shapes in the browser returns table below: never the value, the atok or a full id.
3. `Agent:` on `success:true` with an `id8`, and the sink's `result=written`, post on #12931 one comment whose first
   line is `P5-MINTED key=<KEY> id8=<id8> name=<name> owner=<account|user>` (CTO D9). The swap go and the revoke
   argument read the id and name from that record, not from memory.

**Account-owned limits.** Since Cloudflare's 2026-10-01 change, API Token Provisioning members can create account
tokens, and can grant only permissions they hold. The docs do not say whether zone groups are selectable on an
account token, or whether GraphQL accepts one. The permission-group read and the post-swap zone-tag query settle both.
A key whose group the account list lacks is minted user-owned and recorded on #12931. A GraphQL refusal on the
account-owned ANALYTICS token (`verify` `reason=consumer-read` with `SOLEUR_P5_GRAPHQL ... errors=` non-zero) re-mints
that key user-owned. The user-owned mint is the same `p5-mint.js` with `"owner":"user"` and
`"refuse_ids":["86aa993e","dd6d1427","5993721f"]`: it lists the signed-in login's own tokens first and refuses
`old-owner-login` if any starts with a pin, so it can never run as the old-account owner (CTO D7, amending F17 and
F21). It is its own hold, recorded on #12931; with no other login available it stays a hold.

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
   set -o pipefail; doppler run -p soleur -c prd_terraform --no-fallback --only-secrets <KEY>_NEXT -- bash -c 'v="$<KEY>_NEXT"; (LC_ALL=C; case "$v" in ""|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo "refused: bad shape" >&2; exit 1; }; printf "header = \"Authorization: Bearer %s\"\n" "$v" | curl --disable --noproxy "*" -sS --max-time 30 --config - https://api.cloudflare.com/client/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/tokens/verify' | jq -er '"success=\(.success) status=\(.result.status // "none")"' || echo verdict=no-read
   ```

   Expected: `success=true status=active`. `verdict=no-read` or no `success=` line: stop. An account-owned token is unknown to `/user/tokens/verify`; never read that
   alone as dead.
3. Delete the `.tok` file on EVERY path, the stop paths included (a refused digest, a failed verify, a refused
   read-back): `shred -u "<scratchpad>/<key>.tok" 2>/dev/null || rm -P "<scratchpad>/<key>.tok" 2>/dev/null || rm -f "<scratchpad>/<key>.tok"`
   (stock macOS has no `shred`).
4. Closing check of the sitting. List every directory that could hold a `.tok` (the scratchpad, the main checkout,
   and the worktree when there is one); `find` fails on a path that does not exist, so a wrong path cannot pass:

   ```bash
   set -o pipefail; n="$(find "<scratchpad>" "<repo>" -name '*.tok' -not -path '*/.git/*' | wc -l)" && echo "tok_files=${n// /}" || echo tok_check=unreadable
   ```

   Expected: `tok_files=0`. Anything else: delete the listed files with the step 3 command and re-run.

There is no paste fallback (CTO D7). A failed hand-off has already deleted the token: start a new sink and re-mint.

**Browser returns.** Every result the bodies can give, what it means and what to do. A row that says a token may
exist means a live token nothing holds: list it by name and delete it in the same sitting with `p5-revoke.js`
`mode:"retire"` (section 12), under its own hold.

<!-- p5-browser-returns:start -->
(filled from the bodies' return shapes)
<!-- p5-browser-returns:end -->

## 6. Stages and holds

The bootstrap's stages are `inventory` (read), `swap` (write), `holder-copies` (write) and `verify` (read). `swap`
copies `<KEY>` to `<KEY>_PREV`, reads it back by digest, then copies `<KEY>_NEXT` to `<KEY>`, reads it back, and only
then deletes `<KEY>_NEXT`. `holder-copies` writes prd_terraform `<KEY>` to each manifest holder that still holds the
old value. `verify` prints `SOLEUR_P5_VERIFY key=<KEY> verdict=ok|fail reason=<r>` and, on `ok`,
`SOLEUR_P5_REVOKE_READY key=<KEY> old_id=<pinned> new_id=<8> owner=<account|user>`. No stage calls the dashboard,
deletes a token, or writes `soleur-infra-privileged`. The bootstrap runs only committed helper bytes (a working-tree
edit to a tool it runs is `SOLEUR_P5_UNTRUSTED_FILE`), and refuses a redirecting environment (any `GIT_*` variable,
`BASH_ENV` or `ENV`, `DOPPLER_API_HOST`, or any exported function: `SOLEUR_P5_ENV_REFUSED`, exit 64).

### Markers

Names, 8-character ids, classes and exit codes only; never a value or a digest.

| Marker | Stage | Meaning |
|---|---|---|
| `SOLEUR_P5_REFERENCE key= source=KEY\|PREV\|none\|unknown` | inventory, verify | where the pinned old id was found; `unknown` = no verdict, re-run |
| `SOLEUR_P5_STAGED key= next= prev=` | inventory | whether `<KEY>_NEXT` and `<KEY>_PREV` exist (`present`/`absent`) |
| `SOLEUR_P5_PREV key= state=pinned\|denied\|other\|malformed\|unreadable\|unreachable\|absent [id=] [owner=]` | inventory, verify | the identity of prd_terraform `<KEY>_PREV` at both endpoints; `denied` = both refused it (revoked); `unreachable`/`unreadable`: re-run (CTO D6) |
| `SOLEUR_P5_HOLDER project= config= key= value=old\|new\|revoked\|other\|absent` | inventory, verify | one row per listed config for the key's name, plus prd_terraform `<KEY>_PREV`; `absent` = that config lacks the name; `revoked` = the `_PREV` row after the revoke |
| `SOLEUR_P5_CENSUS key= configs_read= old_hits=` | inventory, verify | census totals |
| `SOLEUR_P5_CENSUS_BLIND key= source=` | inventory | the reference could not be read, so the census decided nothing |
| `SOLEUR_P5_FLOOR_MISSING name=` / `SOLEUR_P5_CENSUS_FLOOR verdict=fail reason=floor-missing` | inventory, verify | the listing lacks a project or config of the committed floor (CTO D2) |
| `SOLEUR_P5_UNREADABLE project= config= [name=]` | inventory, verify | a listed config or name could not be read; never `absent` |
| `SOLEUR_P5_KEY key= id= status= owner=` | verify | the current `<KEY>` token's identity |
| `SOLEUR_P5_CONSUMER key= sub= gating= rc= line=` / `SOLEUR_P5_GRAPHQL key= zone_tag= errors=` | verify | the consumer read and the ANALYTICS zone-tag gate |
| `SOLEUR_P5_HOLDER_NOT_NEW key= holder= value=` | verify | a manifest holder does not hold the new value |
| `SOLEUR_P5_OLD_HOLDER key= holder=` | verify | a config other than prd_terraform `_PREV` still holds the old value |
| `SOLEUR_P5_VERIFY key= verdict=ok\|fail\|revoked reason=` | verify | per-key verdict (`revoked`: the old token is gone, the `_PREV` delete is next); a final `SOLEUR_P5_VERIFY verdict=` line covers all keys |
| `SOLEUR_P5_REVOKE_READY key= old_id= new_id= owner= old_owner=` | verify | the only line that admits a revoke, in the same sitting; the revoke's `scope` is `old_owner` |
| `SOLEUR_P5_SWAPPED key= staging=deleted verified=digest` | swap | the key holds the new token and `_NEXT` is gone |
| `SOLEUR_P5_PREV_NOT_PINNED`, `SOLEUR_P5_PREV_LIVE`, `SOLEUR_P5_KEY_UNEXPECTED`, `SOLEUR_P5_NEXT_NOT_DISTINCT`, `SOLEUR_P5_SWAP_MISMATCH`, `SOLEUR_P5_DELETE_NOT_CONFIRMED` | swap | refusals: `_PREV` not the old token; `_PREV` holds a live non-pinned token; `<KEY>` neither old nor staged; `_NEXT` equals another `CF_API_TOKEN*` key; a copy did not read back; a delete did not take |
| `SOLEUR_P5_COPIED` / `SOLEUR_P5_COPY_MISMATCH` / `SOLEUR_P5_HOLDER_COPY` / `SOLEUR_P5_HOLDER_REFUSED` | swap, holder-copies | a digest-verified copy, a failed one, a planned holder copy, a holder not written |
| `SOLEUR_P5_TOKEN_MALFORMED` / `SOLEUR_P5_TOKEN_UNREACHABLE` | any | a value that is not a token shape; a verify read with no verdict (429, 5xx, transport): re-run, never re-mint |
| `SOLEUR_P5_MANIFEST_INVALID line= reason=` / `SOLEUR_P5_MANIFEST_EMPTY` | any | the manifest block does not parse; fix it in a reviewed PR |
| `SOLEUR_P5_BODY verdict=ok\|stop file=` | section 5 check | a browser body or the sink is (or is not) the committed, pinned file |

`verify` `reason=` values, in the order it checks them: `unreachable` (re-run), `key-malformed`, `key-unreadable`,
`key-not-verified`, `key-not-active`, `key-is-old` (run `swap`), `next-staged` (run `swap`), `no-reference`,
`prev-not-active`, `target-ids-not-new`, `consumer-read`, `census-floor`, `census-unreadable`, `old-holder` (run
`holder-copies`, or decide that holder), `census-blind`, `holder-not-new` (run `holder-copies`). Every reason other
than `unreachable` and the four that name a stage to run is a stop: see section 12.

Each line below runs only after the operator's typed go naming that exact command in the session
(`hr-menu-option-ack-not-prod-write-auth`). One typed go may quote all three mint commands together, each named in
full; every other line takes its own go. Bootstrap applies run from a `main` checkout after merge. `<B>` is the path
section 1 printed. A bootstrap apply is the command its plan run printed after `SOLEUR_BOOTSTRAP_APPLY_COMMAND` in
this sitting, issued verbatim, with the `SOLEUR_BOOTSTRAP_IMPACT` and `SOLEUR_BOOTSTRAP_ROLLBACK` lines relayed first.

Placeholders, each filled before the go and quoted in it:

- `<zone groups>` and `<account groups>`: the two JSON arrays on that key's `P5-SCOPE` line, copied as written.
- `<expiry>`: the `expires_on` read in section 5. `<sink>`: the `url=` the sink printed for that key.
- `<new_id>`, `<new_name>`: the `id8=` and `name=` on that key's `P5-MINTED` record (section 7 lookup).
- `<old_id>`, `<old_owner>`: from that key's same-sitting `SOLEUR_P5_REVOKE_READY` line.
- A revoke hold's `pin` is the key's pinned id in the bootstrap's `# P5-MANIFEST` block (today `86aa993e`,
  `dd6d1427`, `5993721f`).

Each `_NEXT` write runs only after that key's mint returned `success:true` with an `id8` and its sink printed
`result=written`; the `[ -s ... ]` test refuses a missing or empty `.tok`. Each mint go cites the #12931 `P5-SCOPE`
comment. The swap go quotes, per key, the `new_id=` and `owner=` on the plan's `copy-staged-token` operation line,
which must equal that key's `P5-MINTED` `id8=` and `owner=` (CTO D5, D9); a key whose plan has no
`copy-staged-token` line (an interrupted swap that only deletes `_NEXT`) has nothing to quote. In order:

- Hold: Operator-authorizes: account-owned mint of `CF_API_TOKEN_PAGERULES_READ`: `p5-mint.js` (sha256=<sha-mint>) with `{"owner":"account","account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_pagerules_read-soleur-<YYYYMMDD>","zone_groups":<zone groups>,"account_groups":[],"expires_on":"<expiry>","sink_url":"<sink>"}`, then `[ -s "<scratchpad>/cf_api_token_pagerules_read.tok" ] && LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_pagerules_read.tok" | doppler secrets set CF_API_TOKEN_PAGERULES_READ_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: account-owned mint of `CF_API_TOKEN_AUDIT`: `p5-mint.js` (same sha256) with `{"owner":"account","account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_audit-soleur-<YYYYMMDD>","zone_groups":<zone groups>,"account_groups":<account groups>,"expires_on":"<expiry>","sink_url":"<sink>"}`, then `[ -s "<scratchpad>/cf_api_token_audit.tok" ] && LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_audit.tok" | doppler secrets set CF_API_TOKEN_AUDIT_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: owner mint of `CF_API_TOKEN_ANALYTICS_READ` (account-owned): `p5-mint.js` (same sha256) with `{"owner":"account","account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_analytics_read-soleur-<YYYYMMDD>","zone_groups":<zone groups>,"account_groups":[],"expires_on":"<expiry>","sink_url":"<sink>"}`, then `[ -s "<scratchpad>/cf_api_token_analytics_read.tok" ] && LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/cf_api_token_analytics_read.tok" | doppler secrets set CF_API_TOKEN_ANALYTICS_READ_NEXT -p soleur -c prd_terraform --silent > /dev/null`
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT -p soleur -c dev_personal --yes > /dev/null` (CTO F20), only after a `bash <B> --stage inventory` run in this sitting printed `SOLEUR_P5_HOLDER project=soleur config=dev_personal key=CF_API_TOKEN_AUDIT value=old`. Rollback (that row proved the deleted value is the old token), with `<src>` = `CF_API_TOKEN_AUDIT_PREV` when that inventory printed `SOLEUR_P5_STAGED key=CF_API_TOKEN_AUDIT ... prev=present`, else `CF_API_TOKEN_AUDIT`: `set -o pipefail; doppler secrets get <src> -p soleur -c prd_terraform --plain | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | doppler secrets set CF_API_TOKEN_AUDIT -p soleur -c dev_personal --silent > /dev/null`, then a same-sitting inventory that must print that config's row `value=old`
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_AUDIT -p soleur -c dev_scheduled --yes > /dev/null`, only after a same-sitting row `SOLEUR_P5_HOLDER project=soleur config=dev_scheduled key=CF_API_TOKEN_AUDIT value=old`; rollback as above with `-c dev_scheduled`
- Hold: Operator-authorizes: `bash <B> --stage swap --apply --plan-digest <D>` (the printed apply command)
- Hold: Operator-authorizes: `bash <B> --stage holder-copies --apply --plan-digest <D>` (the printed apply command)
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_PAGERULES_READ` old id `86aa993e`: `p5-revoke.js` (sha256=<sha-revoke>) with `{"pin":"86aa993e","old_id":"<old_id>","new_id":"<new_id>","new_name":"<new_name>","scope":"<old_owner>"}`, signed in as the old-account-owner login, only after `bash <B> --stage verify` printed `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_PAGERULES_READ old_id=86aa993e` in the same sitting
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_AUDIT` old id `dd6d1427`: `p5-revoke.js` (same sha256) with `{"pin":"dd6d1427","old_id":"<old_id>","new_id":"<new_id>","new_name":"<new_name>","scope":"<old_owner>"}`, only after a same-sitting `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_AUDIT old_id=dd6d1427`
- Hold: Operator-authorizes: revoke `CF_API_TOKEN_ANALYTICS_READ` old id `5993721f`: `p5-revoke.js` (same sha256) with `{"pin":"5993721f","old_id":"<old_id>","new_id":"<new_id>","new_name":"<new_name>","scope":"<old_owner>"}`, only after a same-sitting `SOLEUR_P5_REVOKE_READY key=CF_API_TOKEN_ANALYTICS_READ old_id=5993721f`
- Hold: Operator-authorizes: `doppler secrets delete CF_API_TOKEN_PAGERULES_READ_PREV -p soleur -c prd_terraform --yes > /dev/null`, only after a same-sitting inventory printed `SOLEUR_P5_PREV key=CF_API_TOKEN_PAGERULES_READ state=denied` and that key's `P5-REVOKED` record is posted (section 7)
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

This replaces the migration runbook's `## Revoke recipe` for these three keys. Its step 1 inventory is this
bootstrap's `verify` (CTO F13), its step 3 delete is `p5-revoke.js` (CTO D1), and its id read and read-back are the
bootstrap's own `SOLEUR_P5_PREV` line, which asks both the account and the user endpoint (CTO D6). The recipe's
user-endpoint read is not used here: it answers `success=false` for an account-owned token that is still live.

1. `Agent:` run `bash <B> --stage verify` in the revoke sitting. Go on only for a key with a line
   `SOLEUR_P5_REVOKE_READY key=<KEY> old_id=<8> new_id=<8> owner=<account|user> old_owner=<account|user>` printed in
   this sitting, with nothing written to that key since. Match the line by its leading
   `SOLEUR_P5_REVOKE_READY key=<KEY>` plus one space, and read the fields from it. `new_id` must equal that key's
   `P5-MINTED` `id8`; else stop.
2. The revoke hold. Sign in as the old-account-owner login and reload `/profile/api-tokens` first (a page not reloaded
   since sign-in showed 0 tokens on 2026-11-26). Run `p5-revoke.js` with the hold's argument object. Before any
   request it checks the argument shapes and, for `scope:"user"`, that `pin` is one of the committed old pins. It
   lists every page of the login's tokens, needs exactly one id starting with `old_id`, and refuses a target whose
   name is the new token's name or has the `-soleur-<YYYYMMDD>` form (CTO F21). Its returns are in the section 5
   browser returns table.
3. Read-back: `Agent:` run `bash <B> --stage inventory`. Only `SOLEUR_P5_PREV key=<KEY> state=denied` confirms the
   revoke. `unreachable` or `unreadable`: re-run. `pinned`: the delete did not take; stop, post it on #12931.
4. `Agent:` straight away, post on #12931 one comment per key whose first line is
   `P5-REVOKED key=<KEY> old_id=<old_id> new_id=<new_id> new_name=<new_name> owner=<owner>`, then the revoke result and
   the `state=denied` line. This record is what routes the `_PREV` delete in a later session (section 1), and the next
   rotation reads `new_id` and `owner` from it.
5. Between a key's revoke and its `_PREV` delete, `inventory` shows `source=none`, `SOLEUR_P5_PREV state=denied`,
   the prd_terraform `<KEY>_PREV` row `value=revoked`, and `verify` prints `verdict=revoked`: all expected, routed by
   the section 1 table.
6. The `_PREV` delete holds run once per key, after all three revokes (CTO F14). After each delete, `Agent:` re-run
   `bash <B> --stage inventory`. Expected: `source=none`, `SOLEUR_P5_STAGED key=<KEY> next=absent prev=absent`.

Closing check, `Agent:`

- Run the full drift check, with the personal Doppler token set for that one process only (CTO D3: this is the only
  drift run). Turn off tracing first (`set +x`), so the token cannot be echoed:
  `set +x; env -u DOPPLER_CONFIG -u DOPPLER_ENVIRONMENT DOPPLER_PROJECT=soleur DOPPLER_TOKEN="$(doppler configure get token --plain)" bash scripts/check-cloudflare-token-drift.sh`.
  Run it from the directory where `doppler login` was done (`configure get` resolves by directory scope; an empty
  token fails closed). Expected: no DEAD `CF_API_TOKEN*` value. A DEAD row names a copy to delete, never a rotation.
- The `CF_API_TOKEN_PAGERULES_READ` fate read, on the new token:
  `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh pagerules-ssl`. Post its
  first line and rule counts on #12931, marker line `P5-PAGERULES-FATE`. Then:

  | Result | Fate |
  |---|---|
  | `cloudflare-readonly: pagerules-ssl ok` with one or more active page rules | keep the key: a consumer still reads them |
  | `ok` with zero active page rules | keep it for now; deleting the key and its consumer is a reviewed PR, not a step here |
  | `unverified - ...` | stop: the new token cannot read page rules; post it on #12931 and re-check the `P5-SCOPE` group |

Finding the records from a fresh session (only unedited comments by the operator's own login, newest first; CTO D9):

```bash
me="$(gh api user --jq .login)" && gh api --paginate repos/jikig-ai/soleur/issues/12931/comments --jq ".[] | select(.user.login == \"$me\" and .created_at == .updated_at) | select(.body | test(\"^P5-(SCOPE|MINTED|REVOKED|PAGERULES-FATE|TOKEN-FACTS|BOOTSTRAP-POINTER)\"; \"m\")) | [.created_at, .html_url, (.body | split(\"\n\")[0])] | @tsv" | sort -r
```

Take the newest record per key. Two `P5-SCOPE` comments that disagree, a `P5-MINTED` whose `id8` differs from the
swap plan's `new_id`, or no record where a step needs one: stop.

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
again. The new pins are the `new_id` values on the `P5-REVOKED` records. All three tokens share the 0a/0b expiry,
so rotate 0a/0b first (migration runbook) and read the new expiry from `CF_API_TOKEN_PURGE` at whichever verify
endpoint answers for its owner; `p5-mint.js` refuses an expiry less than 30 days away. Reminder: #13085 (rotate
before the ~2027-02-20 expiry). The drift-script expiry warning is #13086.

The tokens this runbook mints are account-owned, so a rotation's `_PREV` is account-owned too. The bootstrap's
`SOLEUR_P5_PREV` read asks both endpoints, so the id read and the read-back need no change. The revoke runs
`p5-revoke.js` with `"scope":"<old_owner>"` from the `REVOKE_READY` line (`account` adds
`"account_id":"66d4f93f7397f196544e9fe84c3557c2"`, and lists and deletes at `/accounts/<acct>/tokens[/<id>]`). A key
minted user-owned under the F17 fallback keeps the user forms.

## 12. Halt

- Fix forward. Stop at the last verified step, fix in a reviewed PR, re-run.
- A copy that does not read back equal stops the stage. Later keys stay untouched and `<KEY>_NEXT` is kept.
- Never revoke without a `SOLEUR_P5_REVOKE_READY` line from the same sitting.
- A partial swap has no rollback: re-run `swap`, which resumes every partial state (CTO D8).
- A completed swap whose new token is bad (for example `verify` `reason=consumer-read`), before the old token is
  revoked:
  1. Undo `holder-copies`: for each manifest holder it wrote, the AUDIT rollback form in section 6 with
     `<src>` = `<KEY>_PREV` and that holder's config.
  2. `Agent:` run `bash <B> --stage inventory` and `bash <B> --stage verify`. Go on only when this sitting shows
     `source=PREV`, `SOLEUR_P5_STAGED key=<KEY> next=absent`, `SOLEUR_P5_PREV key=<KEY> state=pinned` and
     `SOLEUR_P5_KEY key=<KEY> id=<the plan's new_id>`.
  3. Operator-authorizes: `set -o pipefail; doppler secrets get <KEY>_PREV -p soleur -c prd_terraform --plain | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | doppler secrets set <KEY> -p soleur -c prd_terraform --silent > /dev/null`,
     then `Agent:` the section 5 digest compare with `<KEY>` and `<KEY>_PREV` as the two reads; it must print
     `digest=equal`.
  4. Operator-authorizes: retire the bad token with `p5-revoke.js` (sha256=<sha-revoke>) and
     `{"mode":"retire","pin":"<bad id8>","retire_name":"<its name>","scope":"<owner>"}` (plus `"account_id"` for
     `account`). It deletes only the one token with that id prefix and that exact name, and refuses any of the old
     pins. The value also stays in Doppler version history, which is why the token itself must go.
  After the revoke the old token is dead: fix forward.
- A mint result whose row in the section 5 browser returns table says a token may exist: list it by name and retire
  it as in step 4 before any re-mint; a same-day re-mint otherwise refuses `name-exists`.
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
- A refused policy read-back with `success:true` on its cleanup: `p5-mint.js` deleted the new token; re-mint before any
  Doppler write. With `success:false`, see the browser returns table.
- `SOLEUR_P5_BODY verdict=stop`: a browser body or the sink is not the committed, pinned file. Run from a clean `main`
  checkout; never edit a body or its pin at a hold.
- `SOLEUR_BOOTSTRAP_PLAN_DRIFT` at an apply: the state changed since the plan run (for example a re-staged `_NEXT`,
  which changes the swap op line's `new_id`, CTO D5). Re-run the plan run and take a new go.
