# Decision challenges (plan phase, 2026-10-26)

Headless plan run inside a Devin CLI subagent — **no Agent/Task tool exists in this harness**, so every technical row is recorded `pending - assumed: <default>` per the technical-ruling-delegation rule's no-agent fallback rather than routed to `soleur:engineering:cto`. The pipeline (or operator) can still override any row; none was surfaced interactively.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Redis credential delivery: aclfile vs generated `requirepass` include-file vs wrapper-script argv | technical | pending - assumed: aclfile — keeps the secret off argv entirely, stores SHA256 in memory (`ACL LIST`/`GETUSER` never return cleartext; `CONFIG GET requirepass` would), `redis://:pw@` client auth unchanged via the default user, Redis ≥6 is satisfied (Ubuntu 24.04 ships 7.x). Include-file recorded as the fallback if a version wall is hit. |
| Site-2 mechanism: rendered wrapper script (`inngest-server-launch.sh`, `@@BACKEND_ENV@@` inside, `@@BACKEND_FLAGS@@` stays on unit argv) vs all-in-script flags | technical | pending - assumed: wrapper script with flags on argv — near-forced: `--postgres-max-open-conns` on the unit's ExecStart is the durable sentinel for ci-deploy.sh:4247/:5868, inngest-inventory.sh:438, inngest-wiped-volume-verify.sh:247 and the cloud-init latch (~:1543). Moving it falsifies all four. |
| Corpus stage scope: expansions inside `bash -c` bodies only vs all `-c` bodies (incl. dash `sh -c`) | technical | pending - assumed: `bash -c` only — the exploit class (SHELLOPTS / BASH_ENV / `-x`) is bash-specific; the six outer `/bin/sh -c` units' `$D`/`$DOPPLER_TOKEN` expansions are not traceable by this vector, and flagging them would be permanent ack noise. Widening is a deliberate later edit. |
| `@@SENTINEL@@` fragment resolution in the new stage | technical | pending - assumed: include — without it the durable `BACKEND_ENV` arm's `$${INNGEST_REDIS_PASSWORD}` (inngest-bootstrap.sh:1747) is invisible to the stage and the guard certifies the site it was built to catch. |
| Drop `doppler run` from the `inngest-redis.service` ExecStart entirely | technical | pending - assumed: drop — with aclfile delivery `redis-server` needs no injected name; the unit stays in the doppler-run population via the new `--only-secrets`-bound ExecStartPre, so the guard's view is unchanged. |
| `--only-secrets INNGEST_REDIS_PASSWORD` on the acl writer's ExecStartPre | technical | pending - assumed: bound — the writer reads exactly one name; same #7761 hygiene the unit's sibling guards already prescribe. |
| `inngest-redis.service` ExecStart drops `doppler run` (vs keeping it for uniformity) | technical | pending - assumed: drop — minimalism ladder; the only consumed injected name was the password. |
| Brand-survival threshold: `aggregate pattern` vs `single-user incident` | taste | pending - assumed: aggregate pattern — both failure directions are fleet-wide (all users' background jobs stall / shared infra credentials leak), not one user's record; challengeable per the section's note. |
| `lane: cross-domain` on a 1-subsystem infra fix | taste | pending - assumed: kept — no `spec.md` exists for this branch to carry a `lane:` value, so the fail-closed default applies (plan Phase "Save Tasks": empty/invalid → cross-domain). |

## Deferred / operator items

- None blocking. The issue itself notes the signing-key residual's rotation is operator-gated (#10382) and the dedicated host's fix takes effect at the sanctioned host replace (#10390 arc) — no plan-phase action owed.
