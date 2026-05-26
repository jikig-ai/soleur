# Learning: `doppler secrets delete --yes` dumps entire config to stdout

## Problem

Running `doppler secrets delete KEY1 KEY2 -p soleur -c prd --yes` outputs a
formatted table of ALL remaining secrets in the config — not just the deleted
keys. This exposed every production secret (API keys, database URLs, private
keys, tokens) in the terminal session.

## Solution

Always redirect stdout to `/dev/null` when running `doppler secrets delete`:

```bash
doppler secrets delete KEY1 KEY2 -p soleur -c prd --yes > /dev/null
```

Verify deletion separately with a targeted read:

```bash
doppler secrets get KEY1 -p soleur -c prd --plain 2>&1 | grep -q "not found" && echo "DELETED" || echo "STILL EXISTS"
```

## Key Insight

Doppler CLI's `secrets delete` command prints the full remaining config as a
confirmation table. This is by design (shows what's left after deletion) but
is a security hazard in shared terminals, CI logs, or conversation contexts.
The `--yes` flag suppresses the interactive prompt but does NOT suppress the
output table.

## Prevention

- Never run `doppler secrets delete` without `> /dev/null`
- Verify deletion with a separate targeted `doppler secrets get` call
- The same pattern may apply to `doppler secrets set` — verify its output behavior before use

## Tags

category: security-issues
module: doppler
