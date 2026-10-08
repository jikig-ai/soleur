# Phase 0 measurements (argv-bearer sweep S2)

Counts and verdicts only. No credential value was printed, echoed or compared in the clear. Measured 2026-10-08 on the
feature branch (tree identical to `origin/main` for source files).

## 0.1 Census commands

| Measure | Result |
|---|---|
| `grep -c 'openssl dgst -sha256 -hmac' scripts/cutover-inngest.sh` | 19 |
| `x-api-key:` on argv outside tests and fixtures | 3 files: the S3 composite action `anthropic-preflight/action.yml`, `scripts/compound-promote.sh`, `scripts/learning-retrieval-bench.sh` |
| `-hmac` operand census (scripts, community scripts, `.github/actions`), files and per-file count | cutover-inngest 19; x-community 1; x-setup 1; check-deploy-script-parity 1; four followthrough probes 1 each; `track.sh` 2 (S4); the lint's own docstring 1 |
| Baseline E before this change | 32 files / 65 sites |
| `-u`/`--user` curl sites repo-wide (`git grep -nE '^\s+(-u\|--user) "'`) | 3 curl sites (`betterstack-query.sh`, `apps/cla-evidence/infra/bootstrap.sh`, `apps/cla-evidence/scripts/r2-conditional-put.sh`); `ci-deploy.sh` is `docker run --user`, not curl |
| Heartbeat-URL pattern census (D9 regex) | 7 files hit; 0 real carriers in S2 files; 5 hits are the `$HBODY` response-body variable of the Hetzner helpers (`web2-rebirth.sh`, `web-host-reboot.sh`, two workflows), the rest are host files under `apps/web-platform/infra/`. A name-based sweep also finds `web-git-data-probe.sh` and `luks-monitor.sh` there |
| Source files in `git diff --name-only origin/main...HEAD` before Phase 1 | 0 (four knowledge-base files only) |

## 0.2 Runtime image toolset (pinned `node:22-slim` digest from the Dockerfile)

| Tool | Bare base image | Base plus the Dockerfile's apt layer (`ca-certificates git bubblewrap socat qpdf jq openssh-client`, then `curl`) |
|---|---|---|
| openssl | **absent** | present (OpenSSL 3.0.22, pulled in as a dependency of `ca-certificates`) |
| python3 | absent | absent |
| node | present | present |
| od, tr, base64, bash (5.2) | present | present |
| curl, jq | absent | present |

The plan's expectation "openssl present on the base image" is wrong for the bare image and right for the real runner image:
`openssl` arrives only through the apt layer (as `ca-certificates`' dependency), so the plugin's HMAC depends on that layer, as the
hosted `require_openssl` already does. `python3` is absent in both, so D3 stands: bash plus `openssl dgst` over stdin for the plugin,
python3 only on GitHub-hosted runners. The `git grep -n python3 apps/web-platform/Dockerfile` count is 0.

## 0.3 Credential shape counts (Doppler `soleur`, config `prd_terraform`; verdict counts only)

| Credential | Class tested | Pass | Multi-line |
|---|---|---|---|
| `BETTERSTACK_QUERY_USERNAME` | non-empty, no `:`, `"`, backslash, control | 1 of 1 | 0 |
| `BETTERSTACK_QUERY_PASSWORD` | non-empty, no `"`, backslash, control (colon allowed) | 1 of 1 | 0 |
| `CF_ACCESS_CLIENT_ID` | `^[A-Za-z0-9._~+/=-]+$` | 1 of 1 | 0 |
| `CF_ACCESS_CLIENT_SECRET` | same | 1 of 1 | 0 |
| `ANTHROPIC_API_KEY` (`prd_terraform`) | same | 1 of 1 | 0 |
| `ANTHROPIC_API_KEY_CI` (`prd_terraform`) | same | 1 of 1 | 0 |
| `ANTHROPIC_API_KEY` (`prd`) | same | 1 of 1 | 0 |
| `WEBHOOK_DEPLOY_SECRET` | non-empty only | 1 of 1 | 0 |

The Better Stack, Cloudflare Access and `ANTHROPIC_API_KEY_CI` names are not in the `prd` config (reported unmeasured there, present and
measured in `prd_terraform`). No conversion is stopped by this measurement.

## 0.3b Byte sweep (real curl 8.22.0, `user = "AA<byte>BB:pw"` through `--config -` with `--libcurl` as the oracle)

Bytes 0x01 to 0x7f (127 cases): 124 delivered verbatim as one `CURLOPT_USERPWD` with one `CURLOPT_URL`; **3 change parsing: 0x0a (newline),
0x22 (double quote), 0x5c (backslash)**. The deny-list for the Better Stack guard is exactly those three plus control characters (kept as the
superset the plan names). A first run reported four because the oracle's C-literal decoder did not unescape `\?`; with the decoder fixed the
count is three, which matches the plan's deepen-time measurement.

## 0.4 Infra-suite partition (scratch tree from `scripts/soleur-sandbox.sh`, suite run read-only, nothing under `apps/web-platform/infra/` edited)

| Scratch variant of `scripts/cutover-inngest.sh` | Suite result (floor 1069) |
|---|---|
| Unmodified | 1069 passed, 0 failed (needs `knowledge-base/.../inngest-server.md` copied in: the sandbox omits knowledge-base and one row greps it) |
| All 19 HMAC sites converted | 1066 passed, **3 failed**: `#6617 probe arms make exactly 2 network/tool calls` plus the two `#8054 mutate[rpg ...]` rows whose unmutated file no longer satisfies the property (all three are the same tool census over the `registry-probe)` to `rearm)` range) |
| 17 converted, **sites at the `registry-probe)` arm and the `doublefire-probe)` arm held back** | 1069 passed, 0 failed |
| Same 17 plus the `SOLEUR_CREDENTIAL_REFUSED script=cutover-inngest reason=token_shape` line added to the four `unusable" >&2; return 2; }` arms | 1069 passed, 0 failed |

Held-back set, confirmed: the two sites inside the `registry-probe)` .. `rearm)` range (the `registry-probe)` arm and the `doublefire-probe)`
arm; both are `SIG=$(printf '' | openssl dgst -sha256 -hmac ...)` at content anchors `registry-probe)` and `doublefire-probe)`). The other 17 are
outside the range (the first at the pre-range site, the rest after `rearm)`). Exactly the plan's expectation; no third site moves.

Canonical snippet (final form with the empty-key exit): 198 bytes, `HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())'`.
Oracle against `openssl dgst -sha256 -hmac` on a synthetic key: empty body, JSON body and a trailing-newline body all equal (3 of 3, 64 hex);
an empty key and an unset key both exit 1. The snippet is 198 bytes, not the 173 bytes recorded before the empty-key exit was added.

## 0.5 Working tree

`git status --short` was empty at the start; nothing from the main checkout is staged or modified here (`.mcp.json` is clean).

## 0.6 RED counts

Phase 1 (lint suite, measured against the unmodified lint with the new fixtures and rows in place): 32 new assertions, **26 RED, 6 green**
(the green six are the four must-pass and xfail rows, the fixture-count floor, and the seeded-lower sandbox row, which is satisfied for the wrong
reason before the arm exists). All 26 turned green with the arm. RED rows for the later phases are written first inside their own phase, against the
script they convert (each later phase's first step), so they are not pre-drafted here.
