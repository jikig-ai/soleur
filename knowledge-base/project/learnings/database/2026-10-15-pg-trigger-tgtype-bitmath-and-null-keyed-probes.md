---
title: "pg_trigger.tgtype bit math + probes keyed on columns a migration nulls"
date: 2026-10-15
issue: 10254
tags: [supabase, migrations, verify-sentinel, review-findings]
---

Two review findings on mig 162 worth pinning:

1. **`tgtype` bit layout** (from `scripts/preflight-worm-cascade-contradiction.sh:110`):
   `&1 = ROW`, `&2 = BEFORE`, `&4 = INSERT`, `&8 = DELETE`, `&16 = UPDATE`,
   `&32 = TRUNCATE`, `&64 = INSTEAD OF`. `BEFORE UPDATE ... FOR EACH ROW` =
   **19**, not 23 (=ROW|BEFORE|INSERT|UPDATE) and not 11 (=ROW|BEFORE|DELETE).
   Two independent reviewers derived different wrong values — the repo's own
   preflight script is the authoritative reference; always bitmask-check
   `(& 19) = 19 AND (& 44) = 0` (44 = INSERT|DELETE|TRUNCATE) rather than
   asserting a bare integer. Column lists (`UPDATE OF`) live in `tgattr`,
   not `tgtype`.

2. **A migration that NULLs a column breaks every test probe keyed on it.**
   `anonymise_action_sends` gaining `message_id = NULL` silently broke two
   post-anonymise probes that matched rows by `.eq("message_id", msg.id)` —
   they matched 0 rows, and the re-arm UPDATE became vacuous (0-row UPDATE
   "succeeds" → the P0001 assert proved nothing). Pattern: when a change
   nulls an FK, grep the touched suite for probes keyed on that column and
   re-scope them by row `id` captured at insert.
