# Review synthesis — PR #8206 (#8189)

Panel (12 seats, report-only): security-sentinel, structural-enumeration, test-design-reviewer, user-impact-reviewer,
architecture-strategist, observability-coverage-reviewer, code-quality-analyst, pattern-recognition-specialist,
git-history-analyzer, data-integrity-guardian, performance-oracle, code-simplicity-reviewer.
Plus three RED suites from the `TEST_GROUP=scripts` shard.

Structural-cause roll-up: **the guards pin step CONTENT, never the WIRING between steps** — five findings are instances
(allowlist not gating the apply; fingerprint export unpinned; ROTATE_RAW env mapping unpinned; notify `if:` substring;
cutover step gating). Owed by the structural-enumeration seat; test-design found them by mutating gating, not content.
Second roll-up: **the anchor is read from the object it protects** (printed fingerprint from Hetzner, 5 seats).

## Fix inline (all pr-introduced)

### Group A — root-key workflow + its suite

| # | Sev | Finding | Seats |
|---|---|---|---|
| A1 | P1 | Allowlist refusal does not gate the apply: `continue-on-error` on `allowlist` or `if: always()` on apply stays 104/0. Pin: no `continue-on-error` on allowlist, no `if:` on any step from allowlist through apply; mutation rows. | test-design |
| A2 | P2 | Printed fingerprint comes from the Hetzner listing (forgeable). Derive from Terraform state `tls_private_key.git_data_root` (verify `public_key_fingerprint_sha256` format) via piped jq; refuse unless equal to the Hetzner-derived value. | arch, security, simplicity, code-quality, pattern |
| A3 | P2 | Rotation: remove the `rotate_read_token` exception entirely (it accepts delete-only / no-op "rotations" and D3's key rotation cannot run through it anyway). Allowlist stays additive-only; D3 + runbook say any rotation (token or key) is a reviewed PR adding a typed arm for exactly its addresses. | arch, security, simplicity, code-quality, pattern, data-integrity |
| A4 | P2 | Allowlist admits a create of ANY address/type and ignores `importing`/`previous_address`. Pin the expected create address set (the 7 D-1 addresses); refuse importing/moved. | structural |
| A5 | P2 | Re-mint after state loss passes as additive. Refuse a create of `tls_private_key.git_data_root` when `apps/web-platform/infra/git-data-root-key.fingerprint` exists in the checkout. | arch, data-integrity |
| A6 | P2 | Notify job `if:` checked by substring; mail step `if: false` survives. Exact compare. | test-design |
| A7 | P3 | Fingerprint step: explicit `set -euo pipefail`, `::error::verdict=git_data_root_key_fingerprint_unreadable` on each capture failure; header wording "non-success except a run-level cancel". | observability, code-quality |
| A8 | P3 | `_ok` verdict helper not self-tested; mutant floor counted on landed edits not RED verdicts. | test-design |
| A9 | P3 | Lock parity row hardcodes versions; keep parity, drop the literal. | arch |

### Group B — arm, gates, apply-web-platform-infra export

| # | Sev | Finding | Seats |
|---|---|---|---|
| B1 | P1 | `GIT_DATA_ROOT_KEY_FINGERPRINT_FILE` export in both gate steps pinned by nothing (delete or re-point: all suites green). Pin exactly one export of the literal committed path before each gate call, plus a delete mutation row. | test-design, pattern |
| B2 | P2 | Arm refusal is a bare `echo`; the replace job's `::error::` names volumes/LUKS/NIC. Emit `::error title=git-data-root-key-arm::verdict=… reason=<word>` (word only). | observability, pattern |
| B3 | P2 | One generic remedy contradicts the runbook breach trigger. Per-reason remedy: `fingerprint_file_missing`/`data_source_absent` → dispatch/commit/re-dispatch; `fingerprint`/`key_count`/`name` → do NOT re-anchor, open an incident (runbook › Breach-triage trigger); `server_keys` → plan-shape defect. | arch |
| B4 | P2 | `lint-trap-tempfile-ownership` RED: arm `mktemp` with no owning trap. Replace the temp file with `ssh-keygen -l -E sha256 -f - <<<"$public_key"` (verify on OpenSSH; remove the TMPDIR guard with it). | scripts shard, simplicity |
| B5 | P2 | `plan-gate-preamble` RED: a lib grading a plan is named off the `*-gate.sh` glob so coverage derivation cannot see it. Follow the suite's prescribed remedy. | scripts shard |
| B6 | P2 | Root-key fixture block copied into both gate suites (+ arm variant). Move into `tests/scripts/lib/gate-suite-harness.sh`. | code-quality, simplicity |
| B7 | P3 | Arm/`key.tf` header "anchor outside a repo-secret holder's reach" holds only for `main` dispatches (replace job has no environment). Qualify. | security, arch, data-integrity |
| B8 | P3 | `mutant_red` in the arm suite not self-tested. | test-design |

### Group C — cutover script, flag precheck, cutover workflow, suites, CI

| # | Sev | Finding | Seats |
|---|---|---|---|
| C1 | P2 | `refuse_if_unmounted` labels transport failures (rc 124/255/141/96) `old_store_unmounted`; map them to `probe_failed rc=`. | observability |
| C2 | P2 | Flag precheck collapses token-absent / invalid / wrong-scope / network into `flag_read_failed rc=1`. Emit `flag_token_absent` on empty token; map captured stderr (never printed) to fixed reason words; verify `DOPPLER_CONFIG` read with the same token equals `prd` (wrong-scope token would otherwise read a missing secret as unset). | observability, security, code-quality |
| C3 | P2 | Store-empty probe can read 0 for a non-empty store: dangling symlink, missing `$OLD_REPOS` on a mounted root, remount between SSH sessions. One remote command re-checks mount identity (`findmnt -T` source == `$OLD_ROOT` source); dangling symlink or missing dir → `probe_failed`. | data-integrity |
| C4 | P2 | Guard 3 census (token references) runs only on infra-path PRs and matches secret names case-sensitively. Extract to a suite run on every PR (scripts group) and match case-insensitively. | code-quality, structural |
| C5 | P2 | `guard-vacuity-floor` RED: deferral ledger grew 47→49 (two new floor-bearing suites in deferred dirs). Cover them (mutation arm) — do NOT raise the number. | scripts shard |
| C6 | P2 | `deploy-script-tests` headroom ~1.08x after this PR (20-min cap, ~1000 s baseline). Raise `timeout-minutes` with the dated re-derivation note the comment block requires. | performance |
| C7 | P2 | Cutover workflow step gating unpinned (`if: false` on confirm, `continue-on-error` on key_fetch/secrets_check, teardown `if false`). | test-design |
| C8 | P3 | Nested ssh timeouts: `ConnectTimeout 10` on the web-1 hop so a slow jump does not eat git-data's budget. | performance |
| C9 | P3 | Stale comments in `git-data-cutover.sh`: access_gate "mutating steps"/"before any host mutation"; `#8189 provisions it` remedy → name `apply-git-data-root-key.yml`; exit code 1 undocumented; `web-2 retired #6538` (false). `infra-validation.yml` comment "precedes every host mutation". | code-quality, user-impact, pattern |
| C10 | P3 | `mutant_red` not self-tested (precheck, access); two `grep … | grep -q` under pipefail (access lines ~262, ~907). | test-design |

### Group D — docs

| # | Sev | Finding | Seats |
|---|---|---|---|
| D1 | P2 | Runbook: remedies + breach-triage routing for `store_not_empty` / `flag_already_true` (flag off in Doppler prd + redeploy; open incident, re-run erasure for affected userIds). | user-impact |
| D2 | P2 | Runbook: blocked-recovery window (merge → fingerprint PR) — erasure events are expected there; escape hatch if the root-key apply cannot succeed (reviewed PR reverting the arm call); heartbeat `pending`/empty-output bullets. | user-impact, observability |
| D3 | P2 | ADR-220: D3 rotation text (reviewed PR adds typed arm; A3); key reach "any 10.0.1.0/24 foothold"; breach trigger includes `secrets: inherit` receivers; anchor holds on `main` dispatches; restore two in-place edits of dated text with Superseded markers; move the two rejected downtime alternatives into the amendment; name which rotation "needs no replace" means. | arch, user-impact |
| D4 | P3 | ADR-149 addendum future tense; `model.c4` keep a TARGET marker until D1b flips; plan Downtime wording "up to the 30 s timeout". | arch, user-impact |
| D5 | P2 | Stale non-hash-bound comments: `git-data-luks.tf` header + rotation paragraph, `variables.tf` `git_data_luks_volume_size` description, `workspaces-luks-cutover.yml` "Mirrors git-data-cutover.yml", `git-data-remove.test.sh` T12, `scripts/followthroughs/phase3-ga-soak-5274.sh` header, Article 30 (g)(1) step name. | code-quality, arch, pattern, user-impact |

## Issue bodies updated (done)

- #8209: added the repo-secret and state-object reach paths (security P2-1).
- #8211: web-2 coverage, `release_freeze` recovery accounting, freeze-sentinel writer contract + absence probe, store-probe not a wipe precondition, hash-bound stale comments, rotation-arm rule.

## Wontfix (with rationale)

- Simplicity #2 (drop the real-mode refusal): the refusal costs ~20 lines and fails a stale local caller loudly instead of exiting 0 with a misleading summary; kept.
- Simplicity #4/#5/#12 and the doc-sprawl table: polish-only duplication; the drift risk is addressed where a guard pins a literal (B1, A9). Not filed.
- Structural A2 (post-bridge unsaved apply), A6 (other dispatch jobs), A10 (operator-local full apply), A11 (rescue/API), C2 banner capture: pre-existing on `main` and not exacerbated by this PR; the full-apply exclusion is ADR-096 design.
- Performance #5 git-data-state queuing: documented in the runbook already.
- `git-data-pre-receive.sh` stale comment: carried on #8093 (hash-bound status disputed; not edited here).
