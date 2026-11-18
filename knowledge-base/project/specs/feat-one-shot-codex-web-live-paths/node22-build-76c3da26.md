---
title: "Codex Web Node 22 compilation and resync observation"
date: 2026-10-05
source_sha: 76c3da268b8bdf086b892e4ce4561f55bf6a0ba4
pr: 9051
status: server-compiled-full-build-and-recovery-unqualified
---

# Node 22 compilation observation

The isolated custom-server and Next-config compilations passed at the source
SHA above. The full Next build failed because network isolation prevented
`app/fonts.ts` from downloading Inter from Google Fonts. No runnable recovery
application or authenticated preview is qualified by these observations.

The tracked-source export included `apps/web-platform`, `plugins/soleur` and
`scripts`, excluding environment files and MCP configuration. Existing
dependency directories were mounted read-only. Docker used cached image
`sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c`,
which reported Node `v22.23.3`. Equality with the production Dockerfile's
pinned image is not established. No image or dependency installation ran.

Each compiler container used `--pull never`, `--network none`, a read-only
root, dropped capabilities, a non-root user and `no-new-privileges`. Only
the source export and disposable `/tmp` were writable. The compiler's
environment was cleared, then supplied PATH, disposable HOME,
`NEXT_TELEMETRY_DISABLED=1`, synthetic Supabase URL/key placeholders and
source-specific BUILD_SHA/BUILD_VERSION. No application runtime, provider
authentication, database or test suite was started.

| Step | Result |
|---|---|
| `node --version` | Exit 0; `v22.23.3`. |
| `next build --webpack` | Exit 1; Inter download failed with `EAI_AGAIN` while network access was disabled. |
| `npm run build:server` | Exit 0; Node 22 custom server bundle produced independently after the Next failure. |
| `esbuild next.config.ts --bundle --format=esm --platform=node --external:@sentry/nextjs --outfile=next.config.mjs` | Exit 0. |

The first wrapper mounted dependencies at paths without a `node_modules`
ancestor. Node could not resolve Next's self-import of its compiled commander
package. The corrected mounts preserve that ancestor; the separate first
attempt log remains retained. This wrapper error and the deliberate font
network refusal do not establish application-code regressions. Sentry's
client-configuration deprecation notice and esbuild's bundle-size advisory
are not runtime verification.

## Retained products and limits

The local ignored directory is
`.soleur/node22-candidate-76c3da26-retry/`. It contains the exact source
export, individual logs and `build-record.json`, completed at
`2026-10-05T15:34:23Z`. Artifacts outside the application source tree avoid
being collected by its recursive TypeScript include. Local availability
must be rechecked before reuse.

| Product, relative to exported application | SHA-256 |
|---|---|
| `dist/server/index.cjs` | `7d2feae8ccab27f6dcac210411d0e442334890881ded64e15848b122a8aa44c8` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

Partial Next products from the failed build are not usable application
artifacts. Neither compilation establishes production dependency parity,
retained-schema recovery, protected-value preservation or admitted-turn
behavior. The [recovery gate](migration-145-recovery-review-5cb81c9d.md#recovery-verdict-and-remaining-gate)
remains open. The existing loopback database was not used: task exclusivity
and wholly synthetic contents have not been established, and server startup
calls `cleanupOrphanedConversations()` before serving application traffic.
Mock authentication also cannot establish genuine authenticated preview.

## Scoped merge verification

The source merge incorporates main
`27f5bc84a509b7276ba16839e18fa22fefbd2b82` as its second parent. The merge resolution
preserves resend and activity-trail props, optional conversation scoping,
the 512-character tool-label bound and all Codex history-transfer schemas.
It adopts main's schema-derived WebSocket admission and discriminator
telemetry, including main's deletion of the duplicate allowlist/test.

Local TypeScript passed after relocating the earlier source export out of
the application's TypeScript scan. Scoped ESLint reported zero errors and
five inherited warnings, involving unchanged unused type imports and grouped
switch cases. The anti-slop scan returned no findings. Semgrep's public
JavaScript, TypeScript and OWASP packs plus Soleur custom rules ran 84 rules
on six merged source files with zero findings.

Independent static data-integrity, agent-native, test-design, security and
user-impact lenses ran in two waves. They found no resolution-introduced
code defect. User-impact review identified two missing plan coverage entries
for cross-conversation activity and stale Working status; the plan now names
the preserved mitigations and inspected regression definitions. These
scoped observations do not complete the outstanding full-branch panel,
authenticated screenshot QA or mode-specific qualification.

[CI run 37331339874](https://github.com/jikig-ai/soleur/actions/runs/37331339874)
and [tenant integration 37331339782](https://github.com/jikig-ai/soleur/actions/runs/37331339782)
completed successfully on this exact source SHA. CLA, secret scan and quality
guards also passed. Future documentation or main-sync commits require their
own exact-head checks. PR #9051 remains draft and Codex default-off.
