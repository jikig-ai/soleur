---
title: Anthropic Console workspace key (mint, store, rotate, revoke)
category: credential-rotation
issue: 8505
last_verified: 2026-09-23
---

# Anthropic Console workspace key

How a spend-limited Anthropic key is minted for one consumer class, and how it reaches its
consumers. Decision: [ADR-243](../../architecture/decisions/ADR-243-anthropic-keys-partitioned-by-spend-limited-workspace.md).
The Console is the only route: the Admin API cannot set a workspace spend limit, and there is no
Anthropic Terraform provider.

## Records

| Field | `soleur-ci-eval` (#8505) |
|---|---|
| Console login | `jean.deruelle@jikigai.com` (NOT `ops@jikigai.com`, whose org `32aa9791…` is unfunded and unused) |
| Organization | `d8d6285b-f01a-4c5b-8a5b-64808a13949b` ("Jean's Individual Org") |
| Workspace | `soleur-ci-eval`, `wrkspc_01GCfbuC9cVBXiWkkEfnyi4D` |
| Spend limit | $100/month, email notification at $80 (org monthly limit $200,000) |
| Principal | service account `soleur-ci-eval`, `svac_01RNxsX5ywq3BEKkjdsxMd9q`, role Developer |
| Key | name `soleur-ci-eval`, scope `soleur-ci-eval`, expiry Never |
| Fingerprint | `sha256[:12]` = `6400ae16d45a` (production key: `c95e2853ab74`) |
| Input slot | Doppler `soleur/prd_terraform` `ANTHROPIC_API_KEY_CI` |
| Distributed to | Doppler `soleur/ci` `ANTHROPIC_API_KEY`; repo secret `ANTHROPIC_API_KEY` ([anthropic-ci-key.tf](../../../../apps/web-platform/infra/anthropic-ci-key.tf)) |
| Minted | 2026-09-23 by an agent session driving `agent-browser`; the only human step was the email login code |

An empty `soleur-ci-eval` workspace (`wrkspc_015TZi9Jgdbo8mLgiQeRMgCF`, no keys) also exists in the
unused `ops@` org, created before the org mismatch was caught. It holds nothing and bills nothing.

## Mint

1. **Confirm the org before any mutation.** The org that matters is the one the production key
   bills. Read it from a response header, without printing the key:

   ```bash
   doppler run -p soleur -c prd -- bash -c 'curl -sS -D - -o /dev/null https://api.anthropic.com/v1/messages \
     -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
     -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"' \
     | grep -i '^anthropic-organization-id'
   ```

   Compare it with *Settings → Organization → Organization ID* in the Console. Two accounts exist;
   only one is funded.
2. **Log in** with `agent-browser` at `https://platform.claude.com/login` (email login). The one
   human step is reading the emailed login code back to the session.
3. *Settings → Workspaces → Create workspace*, name `<consumer>`.
4. *Settings → Workspaces → `<consumer>` → Spend limits*: *Change limit* to the cap, then
   *Add notification* at 80% and *Save changes*. Reload and read both values back.
5. *Settings → Service accounts → Create service account*, role Developer, add the workspace. On
   its page, *Create key*: name, *Expires* Never, *Scope* the workspace.
   Driving note: clicking the *Scope* combobox or the *Add* button with a pointer closed the dialog
   without creating anything. Focus the control and use the keyboard (`ArrowDown`, `Enter`), and
   re-read refs after every step because they change on each re-render.
6. **Capture without printing.** The key panel renders the key as TEXT, so `get value` finds nothing.
   Follow [agent-browser §Credential safety](../../../../plugins/soleur/skills/agent-browser/SKILL.md):
   `eval` the match straight into a `umask 077` file and print only its length and `sk-ant-` prefix.
   Never snapshot or screenshot the panel.
7. **Validate and store.** A 1-token call with the new key must return HTTP 200 and an
   `anthropic-workspace-id` header equal to the workspace id. Then
   `doppler secrets set <SLOT> -p soleur -c prd_terraform --silent < "$file"`, compare the stored
   value's `sha256[:12]` with the file's, and `shred -u` the file.

## Distribute and verify

```bash
gh workflow run apply-web-platform-infra.yml   # or merge: the apply runs on push to main
bash apps/web-platform/scripts/anthropic-key-distinctness.sh   # must print DISTINCT, exit 0
```

The Terraform preconditions refuse a CI value equal to the production key, so an apply cannot write
the wrong key. A hand edit of Doppler `ci` or of the repo secret is drift; the next apply reverts it.

## Rotate

Mint a new key on the same service account (step 5), store it in the same slot (step 7), apply, run
the distinctness script, then archive the old key in the Console.

## Revoke

*Service accounts → `<account>` → the key → Archive*. Archiving the workspace revokes every key in
it. CI Claude steps then fail loudly (`anthropic-preflight` shows the 401 body); production is
unaffected.

## Reuse for #8614 (production cron key)

Same steps with workspace `soleur-prd-cron` and its own limit. The slot and distribution differ: the
production key is Doppler `prd/ANTHROPIC_API_KEY`, which every `prd_*` branch inherits, so #8614
decides how that slot is written. Minting it also retires the key that sat in the repo secret.
