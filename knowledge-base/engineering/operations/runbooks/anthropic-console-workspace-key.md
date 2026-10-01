---
title: Anthropic Console workspace key (mint, store, rotate, revoke)
category: credential-rotation
issue: 8505
last_verified: 2026-09-23
---

# Anthropic Console workspace key

How a spend-limited Anthropic key is minted for one consumer class, and how it reaches its
consumers. Decision: [ADR-244](../../architecture/decisions/ADR-244-anthropic-keys-partitioned-by-spend-limited-workspace.md).
The Console is the only route: the Admin API cannot set a workspace spend limit, and there is no
Anthropic Terraform provider. This page is the single source for the workspace's identifiers.

## Records

| Field | `soleur-ci-eval` (#8505) |
|---|---|
| Console login | the founder's personal Console login, NOT `ops@`, whose separate org is unfunded and unused |
| Organization | `d8d6285b-f01a-4c5b-8a5b-64808a13949b` (the org the production key bills) |
| Workspace | `soleur-ci-eval`, `wrkspc_01GCfbuC9cVBXiWkkEfnyi4D` |
| Spend limit | $100/month, email notification at $80 |
| Principal | service account `soleur-ci-eval`, `svac_01RNxsX5ywq3BEKkjdsxMd9q`, role Developer |
| Key | name `soleur-ci-eval`, scope `soleur-ci-eval`, expiry Never |
| Fingerprint | `sha256[:12]` = `6400ae16d45a` |
| Input slot | Doppler `soleur/prd_terraform` `ANTHROPIC_API_KEY_CI` |
| Distributed to | Doppler `soleur/ci` `ANTHROPIC_API_KEY`; repo secret `ANTHROPIC_API_KEY` ([anthropic-ci-key.tf](../../../../apps/web-platform/infra/anthropic-ci-key.tf)) |
| Minted | 2026-09-23 by an agent session driving `agent-browser`; the only human step was the email login code |

An empty `soleur-ci-eval` workspace (no keys) also exists in the unused `ops@` org, created
before the org mismatch was caught. It holds nothing and bills nothing.

**Consumers of the repo secret**: `ci.yml`, `claude-code-review.yml`,
`fix-constraints-stage-a.yml`, `scheduled-machinery-drain.yml` (dispatched by the production
`cron-machinery-drain`), `test-pretooluse-hooks.yml`. Only the ones running
`.github/actions/anthropic-preflight` soft-skip when the cap binds; see ADR-244.

## Mint

1. **Confirm the org before any mutation.** The org that matters is the one the production key
   bills. Read it from a response header. The key goes to curl through a process substitution,
   never on its command line, where `ps` would show it:

   ```bash
   doppler run -p soleur -c prd -- bash -c 'curl -sS -D - -o /dev/null https://api.anthropic.com/v1/messages \
     -H @<(printf "x-api-key: %s\n" "$ANTHROPIC_API_KEY") -H "anthropic-version: 2023-06-01" \
     -H "content-type: application/json" \
     -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"' \
     | grep -i '^anthropic-organization-id'
   ```

   Compare it with *Settings → Organization → Organization ID* in the Console. Two accounts
   exist; only one is funded.
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
6. **Capture without printing.** The key panel renders the key as TEXT, so `get value` finds
   nothing. Follow [agent-browser §Credential safety](../../../../plugins/soleur/skills/agent-browser/SKILL.md):
   `eval` the match straight into a `umask 077` file. That file holds a JSON STRING (quoted), not
   the raw key — never `cat` it to fix that. Never snapshot or screenshot the panel.
7. **Validate and store**, in ONE Bash call so `umask` and the file path survive:

   ```bash
   umask 077
   F="${SCRATCH:?}/key.json"
   python3 -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1])))' "$F" > "$F.raw"
   curl -sS -D - -o /dev/null https://api.anthropic.com/v1/messages \
     -H @<(printf 'x-api-key: %s\n' "$(cat "$F.raw")") -H "anthropic-version: 2023-06-01" \
     -H "content-type: application/json" \
     -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
     | grep -iE '^(HTTP|anthropic-workspace-id)'
   doppler secrets set <SLOT> -p soleur -c prd_terraform --silent < "$F.raw"
   printf 'file %s  stored %s\n' "$(sha256sum < "$F.raw" | cut -c1-12)" \
     "$(doppler secrets get <SLOT> -p soleur -c prd_terraform --plain | tr -d '\n' | sha256sum | cut -c1-12)"
   shred -u "$F" "$F.raw"
   ```

   The response must be HTTP 200 with `anthropic-workspace-id` equal to the workspace id, and the
   two fingerprints must match.

## Distribute and verify

The merge's `apply-web-platform-infra.yml` run writes both slots (a `workflow_dispatch` re-applies
after a rotation). Then prove distinctness against live Doppler:

```bash
bash apps/web-platform/scripts/anthropic-key-distinctness.sh   # must print DISTINCT, exit 0
```

Terraform checks only the key's `sk-ant-` shape; distinctness from the production key is this
script's job (ADR-244). A hand edit of Doppler `ci` or of the repo secret is drift; the next apply
reverts it. Both resources carry `prevent_destroy`: removing or renaming one needs a `moved {}` or
`removed { lifecycle { destroy = false } }` block, or it deletes the CI key.

## Rotate

Mint a new key on the same service account (step 5), store it in the same slot (step 7), dispatch
the apply, run the distinctness script, then archive the old key in the Console.

## Revoke

*Service accounts → `<account>` → the key → Archive*. Archiving the workspace revokes every key in
it. CI Claude steps behind the preflight then fail loudly with the 401 body; production is
unaffected.

## Reuse for #8614 (production cron key)

Same steps with workspace `soleur-prd-cron` and its own limit. The slot and distribution differ:
the production key is Doppler `prd/ANTHROPIC_API_KEY`, which every `prd_*` branch inherits, so
#8614 decides how that slot is written. The production key sat in the repo secret until this
change, so #8614 must also rotate it.
