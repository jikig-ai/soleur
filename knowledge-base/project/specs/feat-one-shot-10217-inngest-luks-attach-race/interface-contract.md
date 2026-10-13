# Interface Contract: inngest LUKS attach-race fix (#10217)

Generated for Tier 0 lifecycle parallelism, 2026-10-13. All shapes below are as RULED by `soleur:engineering:cto` 2026-10-13 (see `decision-challenges.md` D1–D8) — the CTO overrode parts of the plan's assumed text; this contract is the binding form.

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `apps/web-platform/infra/cloud-init-inngest.yml` (ONLY this file — it embeds both `wait_dev` bodies and the `inngest-luks-open.sh` write_files payload) |
| Agent 2 (Tests) | `apps/web-platform/infra/inngest-redis-luks.test.sh`, `apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` |

Docs (`ADR-142`, `inngest-luks-cutover-6894.md`), `session-state.md`, `tasks.md` — coordinator-owned, written after integration.

## Public Interfaces

### `wait_dev <path>` — signature UNCHANGED, both bodies rewritten identically

Two bodies, byte-identical shape, in `cloud-init-inngest.yml`:
- the `LUKSEOF` runcmd stage body (~line 1674)
- the `inngest-luks-open.sh` payload body (~line 189)

Ruled shape (D1/D4/D7):
- Bound is a **literal `300`** in each body — NOT a `${VAR-…}` expansion. No `INNGEST_LUKS_ATTACH_WAIT_S` token anywhere in the file (no env seam, no `attach_wait_invalid`, no validation block).
- Keep the existing counted `sleep 1`-per-pass loop shape (never the clock).
- Probe once immediately (bound 0 still probes exactly once).
- Re-run the WHOLE predicate each pass: `-b <path> && blockdev --getsize64 <path> > 0` (the existing predicate — verify against the file; keep it verbatim).
- On a miss emit one wait-start line; on resolution emit an appeared-after line — through each file's OWN existing emitter channel (`luks_emit`/`emit`), same style as today.
- `return 1` after the bound; all six call sites keep their post-wait semantics byte-identically (canonical FATALs unchanged, `staging_absent` still tolerated non-fatal).
- Exactly ONE `udevadm settle --timeout=10 >/dev/null 2>&1 || true` AFTER the loop inside each body — NOT per pass.
- `set -euo pipefail` discipline: predicate is an `&&` chain in a condition context; helper called directly, never `$( )`; no `((n++))` from 0.
- The `doppler run … -- bash -s <<'LUKSEOF'` invocation is byte-identical to main — no `env -u`, nothing inserted.

### `ensure_mount <source> <mountpoint>` — NEW function in `inngest-luks-open.sh` (D2/D8)

- `mountpoint -q <mp>` → no-op fast path (zero writes, zero extra emits beyond the arm's existing ones on a healthy boot).
- fstab write: `<source> <mp> ext4 defaults,nofail 0 2` — replace-in-place semantics matching the stage's `fstab_set`, assert exactly one line for the mountpoint; write failure → `fail reopen_fstab`.
- `mkdir -p <mp>`; `mount <mp>` — fstab-driven (never re-type source/options); mount failure → `fail reopen_mount`.
- Success → `emit reopen_mount`.
- Call sites — EVERY verified arm: pointer canonical (`"$MAPPER"` → `/mnt/data` before `exit 0`), pre-cutover `crypto_LUKS` (same), pre-cutover ext4-skip (`"$DEV"` → `/mnt/data`, after the `reopen_skip_plaintext` emit — emit stays truthful, nothing was opened), staging (`"$STAGING_MAPPER"` → `/mnt/data-luks` after `open_as`), AND the `open_as` already-open noop path (the incident's exact post-state).

### Unit + contract changes (D2/D8)

- `inngest-luks-open.service` gains `After=systemd-remount-fs.service` (keeps `DefaultDependencies=no`, `Before=local-fs.target`/`inngest-redis.service`) — binding: prevents the fstab write/`mkdir -p` racing a read-only root on boot ≥2.
- Script header contract comment + unit `Description=` updated to: "opens, then completes the mount for the arm it verified — never formats, never mkfs".
- New emit tokens: `reopen_mount`, `reopen_fstab`, `reopen_mount` (fail detail) — same `inngest-luks-stage` journald tag family as existing emits.

### Constraints both agents share

- Terraform template escaping in `cloud-init-inngest.yml`: bare `$` inside `write_files` payloads; `$${` only where a brace follows; `%%{`/`%{` for template directives (#6894 incident).
- Do NOT touch `cloud-init-git-data.yml`, `git-data-bootstrap.sh`, `inngest-redis-bootstrap.sh`, `inngest-luks-cutover.sh`, `.tf` files, `.github/workflows/*`.
- PARKED PR #10081 overlaps this file textually — keep pre-cutover-arm edits minimal and symmetric.
- `inngest-redis-luks-loopback.test.sh` runs under sudo in CI only — do NOT run it locally; `inngest-redis-luks.test.sh` runs plain.
