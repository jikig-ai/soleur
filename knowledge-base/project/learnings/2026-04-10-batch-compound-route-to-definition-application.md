# Learning: Batch Compound Route-to-Definition Application

## Problem

Four compound route-to-definition proposals accumulated as GitHub issues (#1839, #1763, #1754, #1832) from prior session learnings. Each identified a gap where an agent or skill's documentation lacked a sharp-edge warning about a footgun discovered during real work.

## Solution

Applied 3 proposals as additive sharp-edge bullets to their target files:

- **#1839:** Cloudflare MCP OAuth scope guidance → `infra-security.md` (single-use auth means scope must be right the first time)
- **#1763:** Supabase/PostgREST query syntax warning → `plan/SKILL.md` Sharp Edges (chained modifiers inside `select()` don't work)
- **#1754:** Placeholder secret guidance → `ux-design-lead.md` (realistic API key patterns trigger GitHub push protection on design files)

Closed **#1832** as already fixed — the path in `one-shot/SKILL.md` was already correct on main, likely fixed in commit 479d1315.

## Key Insight

Compound route-to-definition works best when issues are filed with exact file paths and proposed bullet text. This enables direct application without requiring context reconstruction from the original session. Issues that contain the full proposed edit (target file, section, bullet text) can be batch-applied efficiently.

## Session Errors

- **Edit tool rejected unread file** — `plugins/soleur/skills/plan/SKILL.md` was accessed via Grep (context lines) but the Edit tool required a proper Read call. Recovery: re-read with Read tool, then edit succeeded. **Prevention:** Always follow a Grep-based inspection with an explicit Read before editing. The Edit tool does not consider Grep context lines as a "read."

## Tags

category: integration-issues
module: compound, route-to-definition
