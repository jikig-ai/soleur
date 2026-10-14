# Migration checklist — feat-reasoning-chat-boxes (#5370)

Migration: `apps/web-platform/supabase/migrations/105_turn_summary_message_kind.sql`
(+ `.down.sql`). Additive + nullable (`ADD COLUMN IF NOT EXISTS message_kind text`)
+ DO-block CHECK guard (`messages_message_kind_chk`). No `CONCURRENTLY`. No NOT-NULL
sweep — existing writers are unaffected (legacy rows read `message_kind IS NULL`).

## prd apply — pending

Applied automatically on merge via `web-platform-release.yml#migrate` (the
canonical migrate job runs every new `apps/web-platform/supabase/migrations/*.sql`
on deploy). NOT applied pre-merge by design — the column does not exist in prd
until the release workflow runs. Preflight Check 1 re-verifies post-merge via the
release workflow's `verify-migrations` job.

Plan post-merge AC: "Migration 105 applied via `web-platform-release.yml#migrate`
(auto on merge). Automation: feasible."

## dev apply — pending

Same automatic path (the dev deploy runs the migrate job). The post-merge DSAR
DEV probe (plan post-merge AC) exercises a real `turn_summary` row against dev
once applied; the redaction/column contract is unit-verified pre-merge in
`test/server/messages/insert-turn-summary.test.ts` + `test/dsar-turn-summary.test.ts`.
