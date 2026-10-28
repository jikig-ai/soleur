# Streaming spike v4 — inngest@4 re-run record (feat-one-shot-8628-inngest-4-upgrade)

**Re-run of:** `knowledge-base/project/specs/archive/20260923-200917-feat-anthropic-spend-reduction/streaming-spike.md` (S1–S8) plus new checkpointing row S9.

**Versions:** SDK `inngest@4.26.0` (npm-resolved under `^4.26.0` — 4.26.1 was inside the repo's `min-release-age=3` floor on 2026-10-28) · server `inngest start` **v1.45.1** (`apps/web-platform/infra/inngest.tf` pin; binary fetched, `inngest version` → `1.45.1-9059f14a7`) · Cloudflare quick tunnel (`cloudflared` linux-amd64 fetched).

## Verdict: NOT RUN — environment could not complete the harness in-session

Per the plan's no-fabrication rule, this record states exactly what was and was not executed. **No S-row verdicts are claimed.**

| Row | Shape | Ran? | Result |
|-----|-------|------|--------|
| S1–S6, S8 | 2026-09-23 matrix, same pass conditions | **NO** | not executed |
| S7 — no-wrapper stream cut (kill-proof) | mid-step cut, app stays up, no `Controller is already closed` | **NO** | not executed |
| S9 — checkpointing matrix (measurement-only; shipped flag is `checkpointing: false` per CTO ruling) | S2 shape ×2 (default-on vs off) | **NO** | not executed |
| Unsigned-POST (201 + 401 envelope) | curl, throwaway keys | **NO** | not executed |
| Registration PUT (`modified:true`, crons planned) | PUT sync row | **NO** | not executed |

## What WAS done

- Fixture prerequisites fetched and verified: `inngest` v1.45.1 binary (`1.45.1-9059f14a7`) and `cloudflared` linux-amd64, both under `/tmp` of the work host — the two environment-side pieces the 2026-09-23 setup needed beyond a branch build.
- Upstream fix re-verified at the resolved version (not just the plan's 4.26.1 inspection): `inngest@4.26.0` published tarball `helpers/stream.js` carries the `cancel()` handler that clears the heartbeat interval, the `closed` flag gating `enqueue`, and the try/catch demoting a late heartbeat write to `logger.debug` — the three mechanisms that make the stream-detach wrapper dead code.
- Unit-level cover retained: `signature-verify.test.ts` still asserts the 401-in-201-envelope contract on the live route POST under `streaming: true` (green; see session-state.md).

## What remains to run (resume recipe)

The S7 kill-proof is the deletion's load-bearing evidence and is still OWED: stand up `next build` from this branch, boot the app with `installCrashHandlers()` and throwaway `signkey-test-*`/`evtkey-test-*` keys under `env -i` + `INNGEST_DEV=0`, run `inngest start` (fetched binary) behind a `cloudflared` quick tunnel (fetched binary), then run the S1–S8 matrix + S9 both-arms measurement. If S7 shows an `Invalid state`/`Controller is already closed` uncaughtException → STOP, restore `stream-detach.ts`, re-scope (plan §R6).

**Do not merge treating this record as spike evidence — S7 has not run.**
