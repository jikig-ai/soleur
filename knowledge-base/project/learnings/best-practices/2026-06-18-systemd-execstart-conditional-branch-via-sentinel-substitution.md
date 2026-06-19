---
title: "Conditionally branch a single-quoted systemd ExecStart via sentinel + bash param-expansion (not sed)"
date: 2026-06-18
category: best-practices
module: apps/web-platform/infra
tags: [systemd, bash, inngest, deploy, doppler, heredoc]
issue: 5547
pr: 5550
---

# Learning: branch a systemd ExecStart on a runtime flag without losing literal `$${…}` tokens

## Problem

The inngest durable-backend rollout (#5450/#5459) wrote the durable
`ExecStart` (`--postgres-uri … --redis-uri …`) **unconditionally** in
`inngest-bootstrap.sh`, then ran the Redis bootstrap best-effort. A host
without Redis got the durable ExecStart and crash-looped on
`127.0.0.1:6379` for ~3.5h (#5542). The fix (#5547) had to branch the
ExecStart: durable only when Redis is verifiably active, else a SQLite-only
fail-safe — **without** expanding the `$${INNGEST_*}` Doppler tokens that
the single-quoted heredoc (`<<'UNITEOF'`) exists to preserve.

## Solution

Keep the heredoc single-quoted; put a literal **sentinel** on the ExecStart
line, then substitute it AFTER the heredoc is written, gated on a flag
computed earlier:

```bash
# heredoc (literal $${…} survive because of <<'UNITEOF')
ExecStart=… /usr/local/bin/inngest start … --sqlite-dir /var/lib/inngest @@BACKEND_FLAGS@@ --signing-key "$${INNGEST_SIGNING_KEY#signkey-prod-}" …
UNITEOF

if [[ "$REDIS_READY" == "1" ]]; then
  BACKEND_FLAGS='--postgres-uri "$${INNGEST_POSTGRES_URI}" --redis-uri "redis://:$${INNGEST_REDIS_PASSWORD}@127.0.0.1:6379" --postgres-max-open-conns 25'
else
  BACKEND_FLAGS=''           # SQLite-only fail-safe
fi
unit_content="$(cat "$UNIT_FILE")"
unit_content="${unit_content//@@BACKEND_FLAGS@@/$BACKEND_FLAGS}"
printf '%s\n' "$unit_content" > "$UNIT_FILE"
```

## Key Insight

- **Use bash `${var//pat/repl}`, NEVER `sed`.** The durable fragment contains
  `/`, `&`, and `$$` — all of which sed's replacement string mangles. Bash
  parameter substitution inserts the replacement value verbatim and does NOT
  re-expand `$$` inside it (the fragment is single-quoted at assignment, so the
  literal `$${…}` is preserved end-to-end: systemd unescapes `$$`→`$`, then the
  `doppler run`-wrapped `bash -c` expands the injected env).
- `"$(cat FILE)"` strips trailing newlines; `printf '%s\n'` restores exactly
  one → byte-correct unit file.
- The empty-fragment (SQLite) branch leaves a harmless double space
  (`--sqlite-dir /var/lib/inngest  --signing-key`); `bash -c` collapses it.
- **Ordering is load-bearing:** compute the flag AFTER the
  `/etc/default/inngest-server` env-file materialization (the Redis unit reads
  it for the Doppler password) and BEFORE the heredoc write. All of it must stay
  OUTSIDE the `SKIP_BINARY_INSTALL` short-circuit so a same-version redeploy that
  newly delivers Redis flips SQLite→durable.
- **Existing-host deploy bypasses the OCI ENTRYPOINT.** `ci-deploy.sh`'s
  `case "inngest")` runs the bootstrap directly on the host (the Alpine extract
  container has no `systemctl`), so it must `docker cp` the staged assets itself
  — the cloud-init fresh-host path does this, the existing-host path silently
  did not. When mirroring delivery between the two paths, diff them: the
  existing-host path is the one that loses ENTRYPOINT-staged files.
- **Degraded state must surface on a tag the destination actually ships.** A
  0-exit fail-safe deploy's marker is dropped if it rides the bootstrap stderr
  (ci-deploy reads that only on non-zero exit). The authoritative no-SSH carrier
  is the `verify_inngest_health` `logger -t ci-deploy` advisory (LOG_TAG is in
  Vector's allowlist → Better Stack) + a distinct deploy-status reason
  (`success_degraded_durability`). NOTE the residual: this signal is
  deploy-time-only; a continuous between-deploy detector is scoped out to #5553.

## Session Errors

1. **IaC-routing PreToolUse hook fired twice on descriptive systemd/systemctl
   prose during the plan phase.** — Recovery: added the `<!-- iac-routing-ack -->`
   opt-out (the plan introduces no new infra) + rephrased one bare `systemctl`.
   Prevention: already-covered — the `iac-routing-ack` comment is the designed
   escape hatch for infra plans that only describe existing host resources.
2. **`ci-deploy.test.sh` shows 2 pre-existing failures at HEAD on this machine**
   ("missing doppler CLI exits with error", "doppler_unavailable reason"). —
   Root cause: this machine has apt-installed `doppler` at `/usr/bin`, which is
   on the test's hardened PATH (`/usr/local/bin:/usr/bin:/bin:…`); the test
   comment assumes "real doppler lives in ~/.local/bin", so the missing-doppler
   simulation finds the real binary. CI is green (doppler not on its base PATH).
   Prevention: on THIS machine, treat those 2 ci-deploy.test.sh failures as a
   known local-env artifact, not a regression — re-run a failing case without
   the real doppler on PATH (or trust CI) before investigating. Not worth a fix
   (local-only, CI-green, test not in the PR's scope).
3. **`TaskCreate` called with a `tasks` array (wrong schema).** — Recovery: the
   tool returns the correct one-task-per-call schema; switched to lightweight
   tracking. Prevention: one-off; TaskCreate takes `subject`+`description`, one
   call per task.
