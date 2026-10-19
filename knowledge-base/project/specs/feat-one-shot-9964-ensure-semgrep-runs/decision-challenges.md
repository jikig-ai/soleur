# Decision Challenges — #9964

| # | Decision | Status | Ruling |
|---|----------|--------|--------|
| 1 | Probe = `semgrep --version` (not `--help`) | ruled - by issue | Issue text sanctions either; `--version` is the lighter probe and the one the issue names first. |
| 2 | Dead-but-resolvable shim falls through to install path (not a shim-repair) | ruled - by issue | Issue: "on failure fall through to the install path (brew → pipx → pip --user) instead of reporting present." Script must not delete/reorder user binaries. |
| 3 | "Install succeeded but binary still shadowed by dead shim" shares exit 1 with "install failed", plus a diagnostic naming the resolved-but-dead path | ruled - confirmed | CTO: caller treats all non-zero identically; rc 1 already means "remediation attempted, no runnable semgrep". Caveat: diagnostic must print `command -v semgrep` result plus captured `--version` stderr. |
| 4 | Dead shim + no installer available → exit 2 (shim treated as absent) | ruled - confirmed | CTO: rc 1 requires an install attempt; rc 2 = "no remediation path exists". Caveat: stderr must name the dead shim path and direct at shim removal, not installer install. |
| 5 | Bounded-when-available probe | ruled - amended | CTO: `timeout 30`/`gtimeout 30` when present, unbounded fallback — a mandatory gate that can hang is the same worst-shape class as a vacuous pass. |

### CTO caveat carry-through (rows to honor in work)
- Re-probe via `semgrep --version` after EVERY installer success branch (pipx/pip lines re-checked resolution only in the old code).
- rc-2 diagnostic names the dead shim path and the shim-removal action.
- Header comment (lines 12-15) + SKILL.md:358 restate rc 1 = "install attempted but semgrep still does not run"; rc 2 covers dead-shim-no-installer — same PR, doc/code drift is the defect class.
