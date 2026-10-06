# Decision Challenges — feat-one-shot-8278-zot-log-channel-span

## 2026-10-06 — Mechanism choice: dt-bounded boot scope vs. literal per-row `boot_id=` envelope stamp

**Class:** user-challenge (operator direction is the default; recorded for ship to surface)

**Operator's stated direction:** fix #8278 with the shape the issue prescribes —
"grade and delivery proof from one awk pass scoped to the newest real boot,
delivery keyed on a token only the delivered producer can emit".

**What the plan chose:** probe-only design — the newest real boot is derived from
host-scoped `SOLEUR_ZOT_DISK` control rows (` zot_last_err=` head cut), and
envelope rows are bounded to that boot by the ingest-assigned `dt` column, all in
one awk pass. Delivery keys on `log_shipper_post_fail=` / boot-stamped
DROPPED/BOOT rows on that same boot. No producer change.

**What the issue's parenthetical literally says:** "read `boot_id` from the
trusted region of each graded row" — envelope rows carry no `boot_id` today, so
the literal reading requires adding it to the envelope in
`apps/web-platform/infra/cloud-init-registry.yml` (Alternative A in the plan).

**Why the plan deviates from the literal reading:** (a) the template diff would
fire `registry-host-replace-dispatch.yml` on merge — a destructive replace of the
fleet's sole image-pull path for a p3 latent defect; (b) a head-inserted field
breaks the **enrolled** `zot-upload-ceiling-7556.sh` (live tracker #7556), and
even the suffix form forces the same replace plus a transition window where no
envelope row can be graded; (c) the properties the issue names — one pass, one
boot, producer-keyed delivery — are all satisfied without it.

**Revisit if:** per-row binding is ever required (e.g., a future finding shows
the ±5-min boundary window matters), fold the envelope `boot_id=` suffix into a
template change that already rides a scheduled replace.
