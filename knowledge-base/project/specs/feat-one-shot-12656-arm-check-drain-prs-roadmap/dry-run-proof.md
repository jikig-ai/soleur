## Dry-run proof

Every block was pulled from the edited site file by `compose.py` (no hand-pasting), run in its own `bash` call with a read-only `gh` shim first on PATH (`type -p gh` = the shim in every case; `pr merge` prints `WOULD-ARM`; writes refused). Every PR used is merged, so nothing could arm. Re-run 2026-11-13 from the working tree of the commit that adds rows D16-D18 (D3, D4 and D6 re-hashed after the roadmap block gained `exit "$rc"`); the hatch rows ran with `CLAUDE_PLUGIN_ROOT` set to the main checkout's plugin, since the block refuses a root inside the checkout. `shim-refused.log`: 0 bytes.

| # | Block | PR | rc | Last line | Block sha256 (16) |
|---|---|---|---|---|---|
| D1 | drain-checked | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` | sha256:3a126640ee9e8f0e |
| D2 | drain-checked | #12518 | rc=0 | `WOULD-ARM 12518 --squash --auto --match-head-commit 1af1ec063da61a0d2c467895756768f1ec7c1eed` | sha256:419b7b6f0105a23d |
| D3 | roadmap-locked | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` | sha256:4d76a5e4dfa40943 |
| D4 | roadmap-locked | #12633 | rc=0 | `WOULD-ARM 12633 --squash --auto --match-head-commit ee92097453ac789a3a8b4ee7360ed15138cae178` | sha256:ba7190e2a67645c1 |
| D6 | roadmap-lock-alone | #12633 | rc=1 | `stderr: H: run the arm check in this call` | sha256:47010155851ce486 |
| D9 | dequeue | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` | sha256:fc73276aeee71e80 |
| D16 | settle (hatch step 2) | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` (before `admin-merge-ready.sh`) | sha256:f2e52d8d9155e14d |
| D17 | settle (hatch step 2) | #12518 | rc=4 | check and `H == SHA` tie pass; `admin-merge-ready.sh` then reports `NOT-OPEN: PR is not open` (merged) | sha256:138848606447c82f |
| D18 | settle-carry (was-green variant) | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` | sha256:e2fbbe43241d78c3 |

Blocks ran under a `gh` shim as plain `bash` files, so no PreToolUse hook (`.claude/hooks/pre-merge-rebase.sh`) saw them; a shim rc=0 is not proof that an arm passes in a session. The drain-prs exempt-arm rows (D7, D11, D13-D15) were removed with the exempt arm (CTO ruling R1, 2026-11-13).

Separately, read-only: `git rev-list --first-parent --no-merges 0127b5dc45..7d20e7c1a6` prints `7d20e7c1a61aa99ff7cdaaae66919ca19f51e50b`.
