## Dry-run proof

Every block was pulled from the edited site file by `compose.py` (no hand-pasting), run in its own `bash` call with a read-only `gh` shim first on PATH (`type -p gh` = the shim in every case; `pr merge` prints `WOULD-ARM`; writes refused). Every PR used is merged, so nothing could arm. `shim-refused.log`: 0 bytes. No `soleur-exempt-*.head` file left behind.

| # | Block | PR | rc | Last line | Block sha256 (16) |
|---|---|---|---|---|---|
| D1 | drain-checked | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` | sha256:3a126640ee9e8f0e |
| D2 | drain-checked | #12518 | rc=0 | `WOULD-ARM 12518 --squash --auto --match-head-commit 1af1ec063da61a0d2c467895756768f1ec7c1eed` | sha256:419b7b6f0105a23d |
| D3 | roadmap-locked | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` | sha256:0536d7ac887c3fa8 |
| D4 | roadmap-locked | #12633 | rc=0 | `WOULD-ARM 12633 --squash --auto --match-head-commit ee92097453ac789a3a8b4ee7360ed15138cae178` | sha256:425d52b6d1fa4b66 |
| D6 | roadmap-lock-alone | #12633 | rc=1 | `stderr: H: run the arm check in this call` | sha256:d294584d5ab10da4 |
| D7b | drain-exempt-arm | #12694 | rc=1 | `EXEMPT_ARM refused: no read head on file; run the read call` | sha256:cdef8a9a51c61d0b |
| D7-read | drain-exempt-read | #12694 | rc=0 | `EXEMPT_READ head=f0972c275114b6f69cb3769c1840eaab43230578` | sha256:1a577e5ffb543868 |
| D7-arm | drain-exempt-arm | #12694 | rc=0 | `WOULD-ARM 12694 --squash --auto --match-head-commit f0972c275114b6f69cb3769c1840eaab43230578` | sha256:cdef8a9a51c61d0b |
| D9 | dequeue | #12619 | rc=1 | `ARM_CHECK refused: no passing evidence covers the PR head` | sha256:fc73276aeee71e80 |
| D11 | drain-exempt-read | #12691 | rc=1 | `EXEMPT_ARM refused (v): a domain surface, symlink, submodule, binary or unreadable path` | sha256:836091798900f72a |
| D13 | drain-exempt-read | #12633 | rc=1 | `EXEMPT_ARM refused (i): author and fork are deruelle false` | sha256:1411c86ba9de0d64 |
| D14 | drain-exempt-read | #12489 | rc=1 | `EXEMPT_ARM refused (v): a domain surface, symlink, submodule, binary or unreadable path` | sha256:8221af3e88ac46c1 |
| D15 | drain-exempt-read | #11291 | rc=1 | `EXEMPT_ARM refused (v): a domain surface, symlink, submodule, binary or unreadable path` | sha256:f238b1fc6c7c5597 |

Separately, read-only: `git rev-list --first-parent --no-merges 0127b5dc45..7d20e7c1a6` prints `7d20e7c1a61aa99ff7cdaaae66919ca19f51e50b`.
