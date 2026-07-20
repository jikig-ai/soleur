---
title: "Buy the datum, then read it — and the diagnostic key may not be the close-criterion key"
date: 2026-07-17
tags: [diagnosis, observability, telemetry, followthrough, docker, protecthome, drift-guard]
issues: [6497, 6565, 6528, 6616]
category: workflow-patterns
---

# Buy the datum, then read it with the right telemetry key

## Problem

A P1 (`#6497`) — the zot/GHCR `docker login` gate on the web-platform deploy hosts failed and
four prior diagnosis attempts were wrong, every time by **reading code instead of executing**
("active" matched inside "inactive"; a head-truncated grep produced a false-absent; a price
check stood in for a stock check; a silent host nearly read as success). The drift hypothesis
(credential aging on the 121-day web-1) was falsified when a 3-day host failed identically, and
an htpasswd re-bake converged both users while `login_failed` continued.

## Solution — the two-phase arc

**Phase 1 (prior PR #6528): buy the datum.** When a root cause is genuinely unknown and
diagnosis keeps failing on inference, do not guess again — ship a **self-reporting instrument**
that makes the *next* occurrence name its own failure mode. #6528 replaced a `>/dev/null 2>&1`
discard with a structured hatch (`class`, `rc`, `stderr_chars`, `stdout_chars`, `kw`, `tok`,
`docker_ver`) on every failed `docker login`, and split the `unclassified` bucket into named
modes. It did **not** fix the login — it "bought the datum".

**Phase 2 (this session): read the datum, then the fix is direct.** The instrument fired on the
next deploy. A live Better Stack pull (55 failed-login lines, 12h) showed a uniform signature —
`class=cred_store kw=errsaving,erofs errno_chars=22`, `stderr_chars>0`, `stdout_chars=0`. That
one line discriminated four hypotheses decisively: `errsaving,erofs` = docker authenticated but
could not **persist** the credential — "error saving credentials" on a **read-only filesystem**.
Traced to `ci-deploy.sh` writing `/home/deploy/.docker/config.json` under `webhook.service`'s
`ProtectHome=read-only` mount (not in its `ReadWritePaths`) → EROFS. The fix followed in one
file: `export DOCKER_CONFIG=/mnt/data/deploy-docker` (an existing `ReadWritePath`), per the
2026-04-06 ProtectHome-relocate precedent.

## Key insight

Two generalizable lessons, both earned this session:

1. **When diagnosis-by-inference keeps failing, stop inferring and buy the datum.** An instrument
   that names the failure is cheaper than a fifth wrong guess, and it converts an unbounded search
   into a single measured read. The instrument PR is a legitimate, shippable deliverable on its own
   — its close criterion is "failures are now well-named", NOT "failures stopped".

2. **The diagnostic telemetry key and the close-criterion telemetry key can live in different
   planes.** The instrument tagged `host_id` (`hetzner-<id>`) onto **Sentry** only — it was never
   written into the journald `ZOT_GATE`/`PRELUDE` lines that reach **Better Stack**. The repair's
   post-deploy soak reads Better Stack (no-SSH), so it could not group by `host_id`. It had to
   group by journald-native `_MACHINE_ID` (per-host, reliable, mints fresh on a `-replace`;
   immune to the `#6616` `host_name` mislabel). Before writing a per-host close criterion, verify
   the per-host key actually exists **in the plane the criterion reads** — measure it live, don't
   assume the diagnostic tag is present everywhere.

Corollary: the repair issue is a **different issue** from the instrument issue. `#6497` = "the
gate cannot name its own failure" (satisfied by the instrument, closes on its own "well-named"
soak); `#6565` = "repair the login failure" (closes on the "failures stopped" soak). Enrolling
the repair soak on the instrument issue would let the instrument's soak auto-close it on a
still-broken world.

## Session Errors

1. **One-shot collision gate aborted the first invocation** — I passed a *closed* contextual
   citation (`#4017`) in the args; the closed-issue gate cannot distinguish a citation from a
   work target. **Recovery:** re-invoked with the closed refs scrubbed to date-anchored prose,
   keeping only the OPEN work-target `#N`. **Prevention:** already documented
   (`2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`) — the standing fix is to
   scrub every closed `#N` to prose before invoking one-shot; I hit it anyway, so treat "does this
   arg cite any closed issue?" as a pre-invocation checklist item, not a thing to remember.
2. **Mis-framed the work target as `#6497`** (the instrument/observability issue) when the repair
   issue was `#6565`. **Recovery:** the plan subagent caught it; I verified both issue titles live.
   **Prevention:** when an issue is labeled `observability`/`follow-through` and its body says "once
   the instrument names the mode", it is the *instrument* issue — grep for a sibling "repair" issue
   before routing the fix.
3. **Authored two vacuous drift-guard assertions** — they pinned literal line-shapes, so three
   realistic mutations (`export DOCKER_CONFIG="$HOME/.docker"`, a bare keyword-less reassignment,
   a `--config <path>` on a `docker run` continuation line) all produced dual-false-PASS.
   **Recovery:** test-design-reviewer found them; hardened to pin the invariant (exactly-one
   `DOCKER_CONFIG` assignment + `--config <path>` forbid) and mutation-proved RED on all three.
   **Prevention:** knowing about the vacuous-guard class does **not** immunize your own guards — an
   independent adversarial mutation pass on self-authored guards is non-optional. A guard whose
   deletion/inversion leaves the suite green pins nothing; mutate a sandbox copy and confirm RED.
4. **Line-number citation drift** — a +22-line code insert shifted downstream line numbers while
   plan/DC-2 cited the pre-insert numbers. **Recovery:** switched to content anchors.
   **Prevention:** `cq-cite-content-anchor-not-line-number` already covers this — cite a content
   anchor (`printf 'enoent,'`, the `host_id: $h` jq tag), never a bare line number, especially
   when the same PR inserts lines above the citation target.
5. **A flaky pre-existing test (`bwrap-fail` canary rollback) flipped RED→GREEN** and briefly read
   as a regression from my change. **Recovery:** a clean re-run passed; the deterministic mock
   never touches `DOCKER_CONFIG`, confirming a flake. **Prevention (one-off):** for a suspected
   regression on an untouched test, re-run once before diagnosing — a health-check-timing canary
   flakes independent of the diff.
6. **A `run_in_background` bash with an inner `&`** double-detached the test from harness tracking,
   forcing manual polling. **Prevention (one-off):** for a long test you want the completion
   notification for, use `run_in_background` OR a trailing `&` + explicit `nohup`, not both.
