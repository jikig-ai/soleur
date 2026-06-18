# Learning: executing a live durable-backend credential rotation + argv→env redeploy safely (#5560)

## Problem

#5560 required moving inngest's durable Postgres/Redis secrets out of `/proc/<pid>/cmdline` (argv) into the environment, AND rotating the two exposed credentials, AND redeploying the durable backend — without taking down the substrate that powers scheduled reminders/crons. Several non-obvious traps surfaced executing it live.

## Key insights

### 1. `doppler_secret` with `ignore_changes = [value]` is NOT rotated by tainting its source alone
The documented rotation (`terraform taint random_password.inngest_redis_password_prd`) regenerates the password in tfstate, but `ignore_changes = [value]` on the consuming `doppler_secret` **suppresses the propagation** — Doppler (and the running service) keep the OLD value. Correct rotation: `terraform apply -replace` on BOTH the `random_password` AND the `doppler_secret` (re-creating the secret writes the new value on *create*, which `ignore_changes` does not gate). Verify with a plan showing `~ value = (sensitive value)` on the doppler_secret before applying. This flaw applies to every `random_id`/`random_password` → `doppler_secret` pair with `ignore_changes=[value]`.

### 2. Running terraform locally against the R2 backend: raw backend creds + `--name-transformer tf-var` together
The apply workflow uses `doppler run --name-transformer tf-var`, which prefixes ALL secrets — clobbering the raw `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` the S3/R2 backend needs (→ `No valid credential sources / SSO OIDC` errors). Pre-`export` the raw backend creds, THEN layer `doppler run --name-transformer tf-var` (it merges, preserving the pre-set raw vars while injecting `TF_VAR_*`). Apply a reviewed saved plan with `-auto-approve` (the workflow's own pattern) once the user has authorized the rotation.

### 3. Two-phase redeploy to de-risk a credential rotation + behavior-change deploy
When a single redeploy would BOTH change behavior (argv→env) AND apply rotated credentials, split it: **Deploy 1** ships the behavior change with the credential UNCHANGED (zero downtime on that dependency) — this validates the risky assumption (here: does `inngest start` honor `INNGEST_POSTGRES_URI`/`INNGEST_REDIS_URI` env-binding, not just `inngest dev`?) against a still-valid credential. **Then** rotate the credential + a quick second deploy. If the behavior change were broken, Deploy 1 reveals it without ALSO having broken the credential. The Supabase "Reset password breaks existing connections" warning makes the Postgres-reset→reconnect window unavoidable; minimize it by building the image first and doing reset→Doppler-update→deploy in tight succession (Doppler updated BEFORE the reset since the running service doesn't re-read until restart).

### 4. `durability_state=durable` is the no-SSH proof that secrets left argv
You cannot `hr-no-ssh-fallback` read `/proc/cmdline` to prove secrets are out of argv. But if the new bootstrap has ZERO `--postgres-uri`/`--redis-uri` flags and the external watchdog reports `durability_state=durable` (which requires inngest to have connected to BOTH Postgres and Redis via the env-based config), that IS the proof: the durable backend is up *via env*, so the secrets are in env, not argv — and with the rotated passwords (durable requires both auth to succeed). Validate behavior changes by their observable health signal, not by inspecting the host.

### 5. Capturing a dashboard-generated secret without leaking it into the transcript
Supabase's password-reset dialog offers "Generate a password" (fills an input) — prefer it over typing a chosen password (which would enter the Playwright tool-call transcript). Read the input value via `browser_evaluate(filename: …)` to a file under the allowed root (NOT the transcript), URL-encode it, pipe it into `doppler secrets set` via stdin, then `shred` the file. The a11y snapshot can still capture the field value — scan the `.playwright-mcp/*.yml` snapshots for the value and delete them (they are untracked runtime artifacts, but delete anyway).

## Also this session (#5562/#5563)
- GNU `tr -d '\r\n\f\v\x7f\x85'` does NOT parse `\xNN` as hex — it deletes the LITERAL chars `x,7,f,8,5`. A sanitizer using it corrupts content (turned `pool_exhausted`→`pool_ehausted` → misclassification) AND fails to strip ESC (0x1b, the ANSI-injection vector). Use `LC_ALL=C tr -d '\000-\037\177'` (octal, byte-safe) + a `sed` for multi-byte unicode separators. Never route a controlled enum through a content-mutating sanitizer — sanitize only untrusted strings.
- A `-target`-scoped apply silently never applies a resource with no matching `-target=` line (the #5566 class). Parity guards must cover NON-SSH resources, not just SSH `terraform_data`.

## Tags
category: best-practices
module: inngest, infra, secrets, terraform, observability
