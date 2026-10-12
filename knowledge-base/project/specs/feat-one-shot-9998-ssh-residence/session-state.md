# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9998-ssh-residence/knowledge-base/project/plans/2026-10-12-fix-provisioner-parity-ssh-residence-plan.md
- Status: complete

### Errors
- No Agent/Task tool in the planning subagent's runtime — every skill-prescribed sub-agent spawn (Phase 1 research fan-out, spec-flow analyzer, scoped advisor, domain leaders, plan-review panel, CTO technical rulings) was performed inline instead. Technical forks recorded as `pending - assumed: <default>` rows in decision-challenges.md; disclosed in the plan's Enhancement Summary and Sharp Edges.
- Plan Review could not run as an agent panel — compensated by full sharp-edges catalogue read, lint-guard-contract.py (pass), markdownlint (0 issues), mechanical deepen-plan halt-gate verification, and live baseline runs of both suites.
- No `git push` performed (constraint); planning commits are local on the branch.

### Decisions
- Issue's "zero SSH terraform_data resources outside server.tf" premise is false — 4 legitimate web-1 dialers exist (root_authorized_keys in ci-ssh-key.tf:68; luks_monitor_token_install, luks_monitor_install, workspaces_boot_unlock_install in workspaces-luks.tf). Fix is a `fleet_elsewhere` residence arm PLUS a per-resource, host-scoped, reason-mandatory `EXT_RESIDENCE` allowance + stale-allowance arm — not a blanket rule.
- Residence scope is any `web-\d+` dialer (superset of declared fleet hosts) — fail-closed for future fleet growth; indirect host spellings (var.web_hosts, locals, literal IPs) named as a deliberate residual gap.
- Battery rows G2-19–G2-22 specified; FLOOR (mutations_run) bumps 58 → 62; stale arm anchors on literal `stale EXT_RESIDENCE entry`.
- §1 census deliberately untouched — extending srv-scoping cut at mechanism-minimality (would red the 4 legitimate one-off dialers' destinations).
- Baselines measured: guard 18+9 passed, 0 failed at ~2.4s; mutation battery 94/94 green.

### Components Invoked
- soleur:plan, soleur:deepen-plan (run inline — skill files read from plugin root)
- Mechanical gates: cloud-detect.sh, lint-guard-contract.py, markdownlint-cli2, gh issue/pr view, git ls-files/grep premise validation, both parity suites
- Artifacts: plan file + specs/feat-one-shot-9998-ssh-residence/{spec.md,tasks.md,decision-challenges.md}; commits 36c9596f3b, fca7219dda

## Technical Rulings
- cto_spawns=1 (one batched `soleur:engineering:cto` spawn, 8 rows ruled 2026-10-12; 7 confirmed, row 5 corrected: enclosing-resource resolution is type-generic, not `terraform_data`-pinned — plan amended)

## Work Phase
- Status: implementation complete, suites green
- Guard: `web-host-provisioner-parity.test.sh` 18+12 passed on the real tree (fleet_elsewhere + EXT_RESIDENCE + dropped-header + duplicate-addr arms live, 4 seeded entries resolve)
- Battery: `web-host-provisioner-parity-mutation.test.sh` 113/113 — G2-19..35 red on their anchors, G2-C5/C6 green controls, FLOOR 93 = census, FLOOR_BLOCKS raised 23 → 25 (floor = census)
- §1 confirmed untouched (srv-scoped census unchanged)
- lint-shell-capture-exit --baseline: 0 new findings on both touched files
- Implementation commit: 1ea385f11e; review fix commits: 49861f400f (design-pass P2s), 4b3446532f (heredoc-spoof), c4d32ae5bb (span cap + dup/type guards), 9abcbbed28 (enum exit set + blank_heredocs)
- `test-all.sh --affected` selected=161/611 (infra diff → nested run-registered-suites); queued behind sibling runs (ticket 14) at work-phase end

## Review Phase
- Design-validity pass (design-risk: EXT_RESIDENCE decision table): code-simplicity + architecture seats — 0 P1, 3 P2 (type-erased exemption, non-span attribution, over-declared hosts) — all fixed in 49861f400f
- Main panel: class=code, tier=none (plan-declared with sensitive-path scope-out) — git-history, pattern-recognition, security-sentinel, code-quality + structural-enumeration; shellcheck as bash-native deterministic gate (semgrep skipped — bash-only diff)
- Panel findings → fixes: dup-addr arm (pattern P2), span-capture laundering (security P2-1), winrm/dynamic/server.tf-type/`.terraform`-segment exits (enum U1/U2/U3/U5), non-resource span drop + blank_heredocs (enum U7 + quote-flip), malformed-entry type guards, census/doc drift — commits c4d32ae5bb + 9abcbbed28
- shellcheck: 1 info-level SC1091 (pre-existing source-path artifact, not a finding)
- Fix-round: 6 targeted seats over 4b3446532f..HEAD — landed fixes: comment/string-aware blank_heredocs (P2 blanking-suppression hole found independently by 2 seats), nonres `\n?` brace, TOPLEVEL `\b(?!\s*=)` attribute exclusion, scalar `.tf.json` guards, `dial_text` consolidation, dynamic/winrm carve-out dialect check (RES-A/B), G2-34/35, distinguishing needles, FLOOR=census 93
- Declared residuals (documented, not findings): non-literal dial spellings (G2-C6 pinned), `web-\d+` naming convention, gitignored/nested-repo files, remote module sources, .tf.json duplicate keys, non-connection SSH, `.tf.json` dup-addr blindness, single-quote `'` pairing inside heredoc markers (invalid-HCL-only)
