---
name: http-retry-backoff
description: "This skill should be used when outbound network calls fail intermittently and need bounded retries with exponential delay and jitter."
---

@@GROK_BLOCK@@

# Http Retry Backoff

## When to use

- A flaky upstream returns transient errors
- A request storm follows a brief outage

## Steps

- Identify which failures are transient
- Cap the attempt count and the total wait
- Add jitter to every delay
- Log each retry with its attempt number

## Sharp edges

- Never retry a request that is not safe to repeat
- A retry without a cap hides an outage

See [PURPOSE.md](./PURPOSE.md) for why this skill exists, the nearest existing skill, and its history.
