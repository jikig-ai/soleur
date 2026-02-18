---
title: "Pass secrets via env var, never as CLI arguments"
category: implementation-patterns
tags: [security, bash, secrets, discord, cli]
module: community
symptom: "Bot token visible in ps aux and shell history"
root_cause: "Passing token as positional argument to script"
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
