# Review findings — PR #6735 (#6733)

Eight agents reviewed commit `d2eecd2f8` (the bracket design). Their findings
caused the design to be replaced, so most are resolved by *deletion* rather than
by patch. Recorded here because the resolution commits carry `fix(infra)` /
`test(infra)` prefixes and would otherwise leave no review trace.

## Outcome: design replaced

`architecture-strategist` (P1) found the bracket was a compensating control for a
defect removable at source. Verified empirically before acting:

```
bash 3575704 jean 9r DIR 0,50 60 3968310 /tmp/.../mnt/workspaces
before=2026-07-20 02:07:03.697950244 +0200
after =2026-07-20 02:07:03.697950244 +0200   <- read-open does NOT perturb
```

Routed to the `cto` agent (architectural fork, per `work` Phase 1). Binding
ruling: adopt the read-probe, revert the bracket. Implemented in `acd20a4f8`.

## Findings and disposition

| # | Agent | Sev | Finding | Disposition |
|---|---|---|---|---|
| 1 | architecture-strategist | P1 | Bracket unnecessary; probe need not write | **Design replaced** (`acd20a4f8`) |
| 2 | security-sentinel | P1 | `_g4_depth1_fingerprint` fails open — `find`/`sort -z` failure collapses both samples to the empty-input sha, guard passes vacuously, telemetry reports clean | **Deleted with the bracket** |
| 3 | code-quality-analyst | P1 | `g4_bracket_listing_changed` restores on the line before a die saying "refusing to restore" — the one path where a foreign write was *detected* | **Deleted with the bracket** |
| 4 | security-sentinel / data-integrity-guardian | P2 | `strict` restore preempts the straggler abort; `emit_freeze_holders` never runs | **Deleted with the bracket** |
| 5 | security-sentinel | P2 | Residual scope block still an overclaim (same-name recreate, `RENAME_EXCHANGE`) | **Moot** — no restore, no residual |
| 6 | pattern-recognition | P1 | Reproduction suite fails open — defect branch emitted `ok`, passed with *and* without the fix (18/0 with the fix stripped) | **Fixed** (`aa82673a3`): defect branches `fail`, floor 17→29 |
| 7 | pattern-recognition | P2 | `be_n -eq 3`, `C-uncreatable` line-offset window, AC21 checker lacks `[ -s ]` guard | **Fixed / deleted** with the battery rework |
| 8 | test-design-reviewer | P1 | 6 of 7 semantics-changing mutations survived; one-member quantification over multi-member sets | **Fixed** — battery rebuilt; both `phase` call sites now exercised |
| 9 | user-impact-reviewer | P2 | `mktemp` via unpinned `$TMPDIR` could land under `$MOUNT` | **Fixed** — startup assert |
| 10 | user-impact-reviewer | P2 | Plan task 2.9 (`:229` load-bearing flag-set comment) dropped | **Moot** — no `touch -r`, no ctime bump |
| 11 | code-quality-analyst | P2 | Stale `:1428` / `:1019` citations | **Fixed** — content anchors |
| 12 | architecture-strategist | P1 | `manifest_of()` writes `.git/index` into `$STAGING` after C1 certified it | **Fixed** — `--no-optional-locks` |
| 13 | user-impact-reviewer | — | Neither residual could lose data (C1 is `--checksum`; restore touched one inode) | Informational |
| 14 | data-integrity-guardian | — | C1 soundness proven by injection lab: depth-1 create, depth-3 content change, DST ghost all caught with root mtimes forced identical | Informational |

`observability-coverage-reviewer` died on a server error; its lane (do the drift
codes reach a monitored sink?) was verified manually — `emit_drift` sets a
free-form `WL_REASON` consumed by `workspaces_luks_emit` → Sentry, and vector
allowlists by `SYSLOG_IDENTIFIER`, so the five new codes page unregistered.

## Filed as scope-out

None. Every finding was fixed inline or removed by the redesign.

## Verification after resolution

C1 `verify_byte_identity` sha256 identical to `origin/main`. Six suites:
14 / 58 / 62 / 152 / 29 / 79 — 394 assertions, 0 failed, 0 open findings,
0 unmeasured. `shellcheck -S warning` clean.
