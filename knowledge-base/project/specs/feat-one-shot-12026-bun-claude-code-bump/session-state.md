# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-04-fix-bump-claude-code-sdk-bun-1-4-4-pair-plan.md
- Status: complete (plan, plan-review, deepen-plan run; tasks.md committed; commit ff4b11e44a)
- Plan artifact: complete (selector=branch)

### Errors
Session interrupted and resumed; UTC clock jumped ~08:59 -> ~17:10, so the web_egress baseline (1 of 22 workspaces, 2026-11-04T08:59:56Z) is re-run at Phase 1 start and at merge. The issue's acceptance probe `grep -m1 '^Bun v'` is vacuous (matches bare fragment); the plan uses `grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'`.

### Decisions
- Pin exactly claude-code 2.1.311 / agent-sdk 0.3.311 (CTO F1).
- Real-SDK re-proof in a scratch install before any pin moves; one atomic pin commit (CTO F3).
- Standing guard asserting embedded Bun >= 1.4.4 in both binaries (CTO F2); argv-tail pins re-anchored on content (CTO F4).
- Forced scope: model-launch-review Haiku swap (F5), classifier census update, ADR-079/075/278 notes.
- PR 10926: flag comment only, no code change (F6); closing it is the owner's call (F7).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO, CPO, repo-research, learnings, functional-discovery, 5-seat plan-review panel.

cto_spawns=2 (rulings F1-F4 plan-time, F5-F6 batch)

## Work Phase
- Status: complete (2026-11-04 UTC). Commits: b15a8fd972 (F5 swap), ea0a75b39b (atomic pin commit with sdk-bump-verified trailer). Pushed to draft PR 12073.
- Evidence: phase1-evidence.md (scratch proof); branch-head re-proof: 7 runtime files 172 passed with C4_BWRAP_REQUIRED=1, docker masked-/proc arm 54 passed (AppArmor override, CI covers that half), cli-tools stage global install reports Bun v1.4.4 (sha256 86dc1fcc...).
- Fixture re-captured with the Doppler `ci` ANTHROPIC_API_KEY (CTO F13, dev has no key); first capture failed on a new `$HOME/.claude/seed-admin` tmpfs token, fixed with a new placeholder.
- PR 10926 flag comment posted (F6). F7 (close 10926 as superseded) stays an owner decision.
- Open: re-run the prd web_egress count before marking the PR ready and at merge (baseline 1 of 22, re-measured 2026-11-04T17:16:38Z: 1 of 22).

## Review Phase (panel SHA 491b587f68, 13 report-only seats, all returned)
Ledger: raw finding -> canonical defect -> reporting seats -> disposition. Fix commit shown where applied.

| Canonical defect | Seats | Disposition |
|---|---|---|
| P1 `claude-cli-pin-knows-models.test.ts:110` lost `//`, file parses to zero tests, Guard 1 never ran | simplicity, semgrep, data-integrity, pattern, code-quality, architecture, perf, user-impact, git-history, security, test-design | FIXED 998ba4c6f2 (34 passed, Guard 1 printed 1.4.4/1.4.4) |
| P2 Guard 1 real row: `assertEmbeddedBunFloor` call-site mutation survives | test-design | FIXED 998ba4c6f2 (direct per-version floor assertion) |
| P2 `--disable-userns` dropped both sides; b2 mutation (mount after it) survives; rationale vs bwrap 0.8.0 | git-history, test-design, security, user-impact | fix round 2 (row + wording; builder never emits it under our config: enableWeakerNestedSandbox true) |
| P2 stale counts/docs: ADR-053 carve-out, canary-probe-set 483/491/510, betterstack-log-query 206, tf 1764, ADR-272, plan 2.9 Doppler dev, bwrap-shim comment | pattern, agent-native, architecture, git-history, security | fix round 2 |
| P2 non-required checks (`infra-validation`, `sandbox-canary-capture-gate`) described as gates; rollback needs `sdk-bump-verified:` trailer; Better Stack alert narrower than plan says | architecture, user-impact | fix round 2 (wording) + read both runs on the pushed head before ready |
| P2/P3 G2 wording (UUID is the CLI session id, not random) and wildcard pin allowlists any builtin plugin store file | data-integrity, security, user-impact | fix round 2 (keep `agents-md` in the pinned name) |
| P2/P3 two real-SDK suites still on Haiku 4.5 | simplicity, pattern, agent-native, git-history | fix round 2 (swap, re-run with C4_BWRAP_REQUIRED=1) |
| P2 classifier: warning line + denial line is two lines, predicate wants one | agent-native | measure; helper is not used under our config (allowAllUnixSockets true) -> tracker |
| P3 comment/title accuracy (first-pin claim x3, "bind last" title, normalizeSpawnTail JSDoc, SETTINGS_MAPPING minifier claim, seed-admin "HOME only", outer-prctl concurrency, "can never match" reason, #10455 cite) | code-quality, pattern, git-history | fix round 2 |
| Structural gap: guards enumerate a hand-listed name at one reading location (bin/claude.exe, Dockerfile global tree, `.bun-version`, pre-`--dev` mount table, non-`.push` forms) | structural-enumeration, security, user-impact | `.bun-version` floor assertion added; the rest -> one consolidated tracker (Phase 4.2 stays the hard close condition for #12026) |
| P3 simplicity trims, canary wiring mutants, G2 plugins/store scan control, resume-role sentence in User-Brand Impact, scheduled-marketplace-drift 2.1.228 (pre-existing), image +133 MB, watchdog busy-wait | simplicity, test-design, user-impact, perf, git-history | declined or tracker; no behavior change |

Relay to the user: the agent-native seat made one unintended live model call via the ambient CLI login; the AppArmor half of the masked-/proc proof is covered only by CI `infra-validation` (not a required check).
