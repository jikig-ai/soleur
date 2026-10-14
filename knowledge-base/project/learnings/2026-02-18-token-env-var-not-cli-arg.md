---
title: Pass secrets via env var, never as CLI arguments
date: 2026-02-18
category: implementation-patterns
tags: [security, bash, secrets, discord, cli]
symptoms: [Bot token visible in ps aux and shell history]
module: community
synced_to: [infra-security]
root_cause: Passing token as positional argument to script
---

# Pass secrets via env var, never as CLI arguments

## Problem

When a bash script accepts a secret (e.g., Discord bot token) as a CLI argument, that value is visible to any user on the system via `ps aux` and persists in shell history files.

## Solution

Use a dedicated environment variable (e.g., `DISCORD_BOT_TOKEN_INPUT`) instead:

```bash
# BAD: token visible in ps aux and ~/.bash_history
./discord-setup.sh validate-token "MTIz.abc.xyz"

# GOOD: token only in process environment
DISCORD_BOT_TOKEN_INPUT="MTIz.abc.xyz" ./discord-setup.sh validate-token
```

The script validates the env var is set and refuses to accept the token as a positional argument.

## Additional measures

- Suppress `curl` stderr (`2>/dev/null`) during requests with auth headers to prevent debug output leaking the token
- Write `.env` files with `chmod 600` (set permissions before writing secrets, not after)
- Never echo the token value in error messages

> **Superseded 2026-10-10 (#9597 S4):** the "Suppress `curl` stderr (`2>/dev/null`) during requests with auth headers" measure above no longer applies to a
> call made through `scripts/lib/bearer-curl.sh` (`bc_curl`) or its inline wrappers. The argument guard refuses `--verbose` and `--trace*`, so curl cannot
> echo the request headers, and the refusal marker `SOLEUR_CREDENTIAL_REFUSED` is printed to stderr inside the command substitution, so silencing stderr
> would discard the only line that tells a refused credential from a transport failure. See the "Curl's stderr is intentionally NOT silenced" section of the
> 2026-10-10 addendum to `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md`.
