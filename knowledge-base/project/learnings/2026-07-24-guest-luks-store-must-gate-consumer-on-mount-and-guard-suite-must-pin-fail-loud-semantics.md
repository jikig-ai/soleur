# Learning: guest-side volume encryption must gate the consuming service on the actual mount, and its guard suite must pin fail-loud SEMANTICS not token presence

**Date:** 2026-07-24
**Feature:** #6895 — guest-side LUKS for `hcloud_volume.registry` (the zot OCI-registry store) + encryption-posture ledger flip
**PR:** #6926

## Problem

Adding guest-side LUKS to the registry volume (mirroring `git_data_luks`) shipped past the implementation phase green — mutation-tested guard 30/30, `lint-encryption-posture.py --repo-sweep` PASS, terraform fmt clean — yet a 5-agent review found a **production P1** and three **vacuous test guards** that all read green.

### The production P1 (converged by observability + architecture reviewers)

The LUKS mount block and the zot-launch block are **separate cloud-init `runcmd` entries**. cloud-init logs a failed entry and **continues to the next one** (no `set -e` across entries). So on *any* LUKS-mount failure arm — empty key, the wrong-TYPE FATAL-refuse arm (the ADR-096 `registry-host-replace` footgun), or a closed mapper after reboot — `/var/lib/zot` was left as the empty root-disk dir created by `mkdir -p`, and the zot-launch block ran `docker run … -v /var/lib/zot:/var/lib/zot …` **without checking the mount**. zot then served an empty store answering `/v2/` with 401 → the liveness feeder (treats `200|401` as alive) and the disk heartbeat both stayed **GREEN**. The plan's entire safety story ("fail-loud ⇒ zot never starts ⇒ Better Stack liveness-absence alert") was **false against the code**: zero telemetry was indistinguishable from healthy. The lean template's precedent (`cloud-init-git-data.yml`) gates its service on the mount; the registry silently dropped that invariant.

### The three vacuous guards (test-design reviewer, confirmed on sandbox copies)

The new `registry-luks.test.sh` mutation battery was internally sound (every one of its 15 mutations flipped its own predicate) but pinned the wrong thing on the three highest-value security semantics:

- **A1** asserted the `blkid TYPE` else→refuse arm's *reason string* but not that it `exit 1`s. Stripping `; exit 1` from the `*)` arm left the suite 30/30 green while the refuse-and-halt guarantee was gone (fall-through to `luksFormat`/`mount` on a plaintext device).
- **A6** asserted the empty-key guard's `[ -n … ]` *presence*, not that its `||` branch halts. Flipping `exit 1`→`exit 0` stayed green (fall-through to `luksFormat` with an empty passphrase).
- **A11**'s `grep 'After=network-online.target'` was **file-global**, satisfied by a sibling `zot-liveness-heartbeat.service` unit; deleting the ordering from `registry-luks-open.service` stayed green.

## Solution

All findings were pr-introduced and small → fixed inline (`eb020ac92`), zero scope-out:

- **Gate the consumer on the mount.** Before `docker run … zot`: `findmnt -no SOURCE /var/lib/zot | grep -qx /dev/mapper/registry || { echo "[zot] FATAL … refusing to serve an empty/unencrypted store" >&2; exit 1; }`. This makes the plan's fail-loud invariant *true*: a failed mount now stops zot, the heartbeat genuinely goes absent, and every named `alert_route` fires. Restores git-data parity.
- **Pin the guards on exit-code semantics.** A1 now requires `exit 1` co-located with the refuse reason (+ a mutation that strips it → RED); A6 requires the guard's `||` branch to carry `exit 1` (+ a flip mutation → RED); A11 awk-extracts the `registry-luks-open.service` unit block and scopes the ordering greps to it. Added A16 asserting the new mount-gate. Floor 30→34.
- **Boot-open hardening (F2):** added the provision block's 30×2s device-wait to `registry-luks-open.sh`, and had the NIC-guard self-heal invoke it (not just `mount -a`, which can only remount an *already-open* mapper) so a closed mapper self-heals within the 5-min cron instead of waiting for a reboot.
- Content-anchor citations (not line numbers) in `zot-registry.tf`; `>&2` on the FATAL echo; SC2034 suppressions.

## Key Insight

Two generalizable rules, both **recurrences** of documented review classes (see `plugins/soleur/skills/review/SKILL.md` "Defect Classes"):

1. **A new persistent store's at-rest encryption is only as safe as the gate on the CONSUMER of that store.** Encrypting the volume is necessary but not sufficient: if the consuming service can start on the *unmounted* path (an empty dir, a fallback), a failed encryption boot degrades **silently behind whatever liveness signal the service already has** — worse than a loud failure, because it reads as healthy. When the volume mount and the service launch are separate steps in a continue-on-error runner (cloud-init `runcmd`, a compose file, a systemd target without `RequiresMountsFor`), the service MUST re-assert the mount (`findmnt … == the mapper`) and fail loud before serving. Check the LEAN precedent you're mirroring for exactly this gate — dropping it is easy and invisible.

2. **A mutation-tested guard suite must anchor each assertion on the fail-loud SEMANTICS (the `exit 1`, the halt), not on token PRESENCE.** A guard that greps for the reason string / the `[ -n … ]` test / a file-global unit directive passes identically whether the code halts or falls through — the exact regression it exists to catch survives it. The author's own green mutation battery is a floor, not proof: it only covers the mutations the author imagined. Litmus per assertion: *name a mutation that satisfies the grep while violating the property* — if you can, the guard is vacuous. Scope every unit/block grep to the specific block (awk-extract), never file-global.

## Session Errors

1. **Consumer not gated on the mount (production P1).** Recovery: `findmnt` mount-gate before `docker run zot`. Prevention: when mirroring a lean guest-LUKS template for a service-backed store, confirm the consumer re-asserts the mount and fails loud — the precedent's service-bootstrap gate is the thing most easily dropped. (Recurrence of the review catalogue's "new store encryption posture" + "self-healing guard must fail-safe on its own instrument" families.)
2. **Guard suite pinned presence not exit-code (A1/A6/A11 vacuous).** Recovery: re-anchor on `exit 1` + block-scope + add flip mutations. Prevention: `mutation battery only covers what you mutate` — for every guard whose correctness is a *direction/halt*, require a mutation that removes the halt and confirm RED. (Recurrence of the documented mutation-vacuity class.)
3. **Stale `:741-746` citations after a ~100-line insertion.** Recovery: repoint to content anchor. Prevention: `cq-cite-content-anchor-not-line-number` — never a bare line range into a churning file.
4. **F2 boot-open silent-success + impotent self-heal; missing `>&2`.** One-off hardening; fixed inline.
5. **shellcheck SC2034 unused vars.** One-off; suppressed with justification.

## Tags
category: infrastructure
module: encryption-posture / cloud-init / zot-registry
