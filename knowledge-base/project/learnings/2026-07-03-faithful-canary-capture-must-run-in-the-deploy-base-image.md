---
title: "Capturing the Claude Agent SDK's real bwrap argv: env-faithfulness + root + shim gotchas"
date: 2026-07-03
issue: 5913
adr: ADR-079
category: best-practices
tags: [sandbox, bwrap, claude-agent-sdk, ci, capture, seccomp]
---

# Faithful sandbox-canary capture — the four things that bite

Wiring the creds-gated real `--capture` for the faithful sandbox canary (#5913,
ADR-079 deferral B) surfaced four non-obvious facts about snapshotting the
`@anthropic-ai/claude-agent-sdk` bwrap SETUP argv. Each falsified a plausible
assumption in the plan/ADR. Recorded so the next person capturing an SDK's real
sandbox invocation does not re-derive them.

## 1. The SDK's bwrap argv is NOT a pure function of (SDK version, config). It also depends on the HOST FILESYSTEM.

The plan assumed "the captured argv is byte-reproducible by construction." It is
not. The real 0.3.197 argv (176 tokens) embeds three env-dependent axes:
- **per-run random paths** — a network-proxy socket `/tmp/claude-http-<hex>.sock`
  and ~12 `/tmp/claude-empty-<rand>` bind sources (change every capture);
- **host-specific binds** — `/home/<user>/.npm/_logs`, `/tmp/claude-<session>/…`;
- **26 `--setenv NAME VALUE`** env-forwarded vars, some secret-shaped
  (`CLOUDSDK_PROXY_PASSWORD`, and in-container a `HTTPS_PROXY=http://srt:<token>@…`).

Fix: a **canonical projection** (`normalizeCapturedArgv`) that keeps the
seccomp-relevant structure (all `--unshare-*`, `--dev`, `--tmpfs`,
deterministic-const binds, workspace-relative binds), normalizes the workspace
root → `${CANARY_WS}` and random empty-dir sources → `${CANARY_EMPTY}` (substituted
back at replay), and DROPS the non-deterministic/host/secret axes. Do NOT try to
enumerate-and-drop "host-conditional" tokens as a heuristic (see #2) — capture in
the right environment instead.

## 2. capture-env == replay-env == the deploy base image. Host-conditional tokens make an off-image capture unfaithful.

`--tmpfs /etc/ssh/ssh_config.d` is emitted **only when the host has `/etc/ssh`** (a
hardening mount that hides host SSH config from the sandbox). Capturing on an
Ubuntu laptop or the `ubuntu-latest` runner (both have `/etc/ssh`) produces an argv
that is a **superset** of what the prod `node:22-slim` deploy image runs, and
`bwrap: Can't mkdir parents for /etc/ssh/ssh_config.d: Read-only file system`
infra-errors the deploy replay. So the fixture MUST be captured **inside the deploy
base image** (`node:22-slim` + `npm ci`), never on the runner. There are almost
certainly other latent host-conditional tokens (CA bundles, `/etc/machine-id`,
locale files) — capturing in-image eliminates the whole class by construction,
which is strictly safer than a "drop non-universal `/etc/…`" projection rule that
could silently drop a load-bearing hardening mount.

## 3. `permissionMode: "bypassPermissions"` is REFUSED under root. Use `"default"` + `canUseTool`.

`bypassPermissions` maps to `--dangerously-skip-permissions`, and `claude.exe`
hard-refuses it under root ("cannot be used with root/sudo privileges"). CI
containers and `docker run` are root, so the capture turn exits 1 with
`no_tool_call` — while the identical code works on a non-root dev user. Since a
`canUseTool` force-allow callback + `autoAllowBashIfSandboxed` already auto-allow
the single Bash op, use `permissionMode: "default"` — root-compatible and
sufficient. This is the single thing standing between a green in-image capture and
a mysterious `no_tool_call`.

## 4. A bwrap-intercepting PATH shim must answer `bwrap --version`.

The SDK probes bwrap availability with `bwrap --version` (and, with
`failIfUnavailable: true`, skips the sandbox if the probe looks broken). A shim
that records-and-exits-0 for ALL invocations fails the probe → the SDK never does
the real SETUP spawn you want to capture. Have the shim print a plausible
`bubblewrap <version>` for a lone `--version` arg and record everything else.

## Bonus: bwrap 0.11.x combines namespaces — argv replay can't reproduce the #5849 split.

bwrap 0.11.x folds all `--unshare-*` into one `unshare(…|NEWUSER)`, permitted under
both the committed and the pre-#5874 seccomp profiles. The #5849 split-unshare
EPERM comes from the claude CLI's **nested-process structure**, not any argv token,
so replaying `bwrap <argv> -- true` NEVER reproduces it regardless of argv fidelity.
The argv-independent layer-B nested-unshare probe
(`unshare --user --map-root-user unshare --mount --pid`) is the only thing that
discriminates that class. The real-argv replay is a *bwrap-level profile-fidelity*
canary (does the SDK's real setup survive the committed profile on the deploy
bwrap?), not a #5849 discriminator. See ADR-079 §2d.

## Debugging note

The SDK swallows the spawned `claude.exe` stderr behind "Claude Code process exited
with code 1". To see the real error, drive `query()` with the `stderr: (d) => …`
option callback — that surfaced the `--dangerously-skip-permissions` refusal in #3.
