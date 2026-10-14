# Decision Challenges — feat-one-shot-6733-c1-verify-root-mtime-tolerance

## UC-1 — Do NOT narrow C1. The diff is self-inflicted by the script's own G4 probe.

**Operator's stated direction:** *"Narrow `verify_byte_diff` to tolerate EXACTLY: transfer
root (`./`) AND directory type AND mtime-only AND zero content flags."*

**Challenge:** the tolerance is unnecessary, and shipping it would permanently weaken the
only integrity gate protecting 8 production workspaces during the repoint — to accommodate
a diff the cutover script causes itself.

**Evidence (measured locally, `rsync 3.4.1`, the script's exact verify invocation):**

`assert_mount_quiesced` creates and removes a **depth-1 entry in the rsync transfer root**:

```bash
# workspaces-cutover.sh:449,454,473
probe="$MOUNT/.luks-g4-probe.$$"
exec 9>"$probe"        # :454  creates it
rm -f "$lout" "$lerr" "$probe"   # :473  removes it
```

and it is called **between the last write pass and the verify**:

```
:1416  pass-2 delta rsync
:1428  assert_mount_quiesced pre-verify   <-- creates + removes a depth-1 entry in $MOUNT
:1430  drop_caches
:1437  verify_byte_identity "$MOUNT" "$STAGING"
```

`$MOUNT` **is** the transfer root, so `./` is `$MOUNT`. Create+remove is a net-zero listing
change that advances the root's mtime and nothing else. Reproduced verbatim:

| Step | Verify output |
|---|---|
| immediately after pass-2 | *(clean)* |
| after running the G4 probe verbatim | `.d..t...... ./` |
| after the probe **with root-mtime save/restore** | *(clean)* |

The pre-verify re-assert landed in `ca85c30bc` (2026-07-19 18:25 CEST, #6701) — **before**
run 29706401639 (22:37Z), the run cited as reproducing the diff on the correct device.

This also explains the key observation from that run directly: the diff appeared identically on
the **wrong** device and the **right** device because the probe perturbs `$MOUNT` (the SRC
side), which is identical in both cases. The device was never the variable.

**Recommendation:** keep C1 fail-closed and **unnarrowed**. Fix the probe so it does not
perturb the tree it is about to certify (save/restore the root mtime at ns precision, or
move the probe fd outside the transferred tree). Three lines, no gate weakened.

**Why this is a User-Challenge and not a silent redirect:** the operator specified the
tolerance approach explicitly and with a detailed conjunct design. The plan does not
implement it, on evidence. Persisted here per ADR-084 headless arm — `ship` renders this
into the PR body and files it as an `action-required` issue for operator review.

**Residual risk if the operator still wants the tolerance:** it is measurably safe against
content (14-case battery), but it would also swallow a genuine future root-level
perturbation by an *unquiesced* writer — the one signal that currently proves nothing wrote
the transfer root after pass-2.
