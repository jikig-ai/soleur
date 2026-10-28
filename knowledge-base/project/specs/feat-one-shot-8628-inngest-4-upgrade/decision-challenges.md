# Decision Challenges — feat-one-shot-8628-inngest-4-upgrade

Recorded per the technical-ruling-delegation rule. This planning subagent has no
nested agent-spawn tool; technical rulings are either evidence-cited here or
marked `pending - assumed: <default>` for the implementer/ship pipeline.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Checkpointing: leave v4 default-on vs `checkpointing: false` on the client | technical | pending - assumed: leave default-on (upstream docs mark self-hosted supported); spike row S9 decides — any S-row failing under checkpointing while passing with it off flips to `checkpointing: false` with the row cited |
| Replacement app-side telemetry for retired `inngest-stream-consumer-cancel` / `inngest-stream-drain-error` ops | technical | pending - assumed: no replacement; drop detection stays on the server-side `inngest_step_524` Better Stack needle (existing mechanism); fnId/stepId attribution loss accepted and recorded in the ADR-243 observability table |
| `containedHasProcFd` seam shape for non-Linux/procfs-absent test coverage | technical | pending - assumed: a deliberate seam consistent with the file's existing `@internal test seam` precedent (exported-for-test optional parameter), not a module-mock of `process.platform` |
| Error-prefix family naming in the contained-write helpers | technical | pending - assumed: keep the single `writeDigestFileContained:` family prefix (one grep family) with a per-operation detail token in the message; implementer may pick per-helper prefixes if review prefers |
| `streaming: true` vs deprecated `"force"` parity | technical | Ruled 2026-10-28 with cited evidence: use `streaming: true` — v4.26.1 types declare `streaming?: true \| false`; `"force"`/`"allow"` are deprecated (inngest-js #1303). Parity verified by S2/S3 + unsigned-POST spike rows, not assumed |
| Target version: `^4.21.0` (issue's named fix version) vs `^4.26.1` (latest stable) | technical | Ruled 2026-10-28 with cited evidence: `^4.<latest stable>` — the ask restores the `^` range, and the createStream fix is present in all 4.x ≥ 4.21; 4.26.1 is the published latest at plan time |
| `bun.lock` regeneration (working note) | technical | Ruled 2026-10-28 with cited evidence: no bun.lock exists in this repo — `scripts/lint-dual-lockfile.sh` (ADR-191) asserts zero tracked bun lockfiles as an existence property; only `apps/web-platform/package-lock.json` regenerates via `npx --yes npm@11 install --package-lock-only` |
| Brand-survival threshold | operator (challengeable) | `single-user incident` — the serve handler is shared with the founder-facing BYOK leader loop; a regression can double-bill the founder's key or stall the loop. `requires_cpo_signoff: true` recorded in the plan frontmatter |

## Not Yet Specified

(none)
