# Phase 0 — Precondition Verification (#5318)

**Verified-at:** 2026-06-15 (live probes against production Flagsmith project 39082 + Doppler soleur/dev).

## 0.1 Flagsmith DELETE contract (live probe, throwaway feature `zz-probe-5318-deltest`)

| Step | Result |
|---|---|
| `POST /projects/39082/features/` (create) | 201, `feature_id` returned |
| `GET /projects/39082/features/?q=<name>` exact-filter | resolves `(id, name)` |
| `DELETE /projects/39082/features/{id}/` | **HTTP 204** (key HAS `Delete feature` perm — no 403) |
| re-`GET ?q=<name>` exact-filter | `[]` (invisible after delete) |
| re-`POST` same name | **HTTP 201 — name IS REUSABLE** after soft-delete (unique index ignores soft-deleted rows) |
| cleanup DELETE of re-created feature | 204 |

**AC3(f) resolved:** the deleted flag name is **reusable** (create→delete→recreate round-trips cleanly). No name-conflict to assert.

## 0.2 Doppler delete behavior + verify-form

- `doppler secrets delete <K> -p soleur -c dev --yes > /dev/null` → returns 0, stdout suppressed. The `> /dev/null` is mandatory (per `2026-05-26` learning — delete dumps full remaining config to stdout without it).
- **Verify-deletion form CORRECTION:** the plan assumed `grep -q 'not found'`. The ACTUAL missing-key output is:
  `Doppler Error: Could not find requested secret: <K>` with **exit code 1**.
  So the verify form in delete.sh uses the **specific message** `grep -q 'Could not find requested secret'` (or the non-zero exit of `doppler secrets get ... >/dev/null 2>&1`), NOT `'not found'`. AC3(e) and AC4(c) greps updated to match.

## 0.3 Budget headroom

- Re-measured at /work time: **Total 2071 / 2071 words, headroom 0** (matches plan baseline; no merge drift).
