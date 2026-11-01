# Decision Challenges — feat-one-shot-8595-monitor-guard-parity

Headless one-shot planning run for issue #8595 (epic #10390 PR 3). This harness
has no Agent/Task tool, so the `soleur:plan-review` panel and fresh CTO
rulings could not be spawned. Rows the epic-ownership pass already ruled carry
`Ruled by CTO agent, 2026-11-01:` verdicts; arm-selections inside a ruled
option set and executions of the ruled residual are recorded `taste` with an
`assumed:` verdict; one row cites a directly on-point precedent ruling from a
sibling branch.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Scope of the #8595 residual — how much of the issue still needs a diff | technical | Ruled by CTO agent, 2026-11-01: Ship only the test-(c3) failure-message residual plus evidence-of-satisfaction, no new monitors or suites - the issue is ~90% already satisfied on origin/main by later drift: PR #9303 (b2cebec0d6, 2026-09-30) added the reverse-direction (c3) test; the #8450 crontab-parity and #8495 watchdog-dispatch-clock-parity blocks in sentry-monitor-iac-parity.test.ts cover the cadence leg; the AC2 residual is a second-arg vitest message prescribing removal. Re-verified at HEAD 2026-11-01: (c3) present, all 16 NON_INNGEST_MONITORS entries resolve to tf name = attributes (zero stale), 13/13 suite green. |
| Disposition of the issue's `checkin_margin_minutes ≡ interval` leg — drop as documented Non-Goal vs pin the vacuity | taste | assumed: drop as a documented Non-Goal — the CTO ruling delegated the arm choice to the plan ("either drop that leg as a documented Non-Goal or pin the vacuity explicitly"), so arm-selection is editorial within a ruled set; Non-Goal chosen because the leg's condition ("where the tf comment documents that convention") is unsatisfiable by design — cron-monitors.tf comments explicitly refute margin == interval and the file declares zero type="interval" monitors — and a vacuity pin would guard prose comments the issue never asked to guard. |
| Sibling (d) `KNOWN_UNMONITORED_SLUGS` staleness check carries the identical bare-`expect(stale).toEqual([])` message defect — fold its message line into this diff or descope | taste | assumed: descope — the CTO ruling sized the residual at one test-message change and issue #8595 names NON_INNGEST_MONITORS only, so staying inside the ruled scope is execution, not a new ruling; the (d) mirror is recorded as a fold-in candidate in the plan's Non-Goals for review discretion. |
| `plan-review` reviewer panel not spawned (no Agent/Task tool in this harness) — is an in-process gate pass sufficient before `soleur:work` | technical | Ruled by CTO agent, 2026-10-12: no panel re-run required before implementation (precedent ruling on the identical harness residual, recorded on feat-one-shot-9963-syslog-systemd-journald-path) - the missing-panel residual is disclosed in the plan, every mechanical gate ran in-process (premise validation, guard-contract lint, infra lint, markdownlint, AC command execution), and plan-review may still run at the review stage. |
| Brand-survival threshold `none` | taste | assumed: none — a failure-message string in an internal CI guard test; worst outcome is a less actionable red required check, no user-facing artifact or data exposure. Challengeable per the template's own marker. |
| Sibling (d) fold-in disposition at review | taste | folded in at review (commit ef768927cb) — the descope row's own delegation ("fold-in candidate for review discretion") executed on three convergent seat flags (pattern-recognition, code-quality-analyst, test-design-reviewer); identical defect class, same file, ~4 lines, RED-verified. |
| Structural-enumeration seat map (extractor over-inclusion A1-A7, self-pinning B1-B7, message persistence M1-M4) | technical | scope-out filed as #11825 — pre-existing guard design properties outside the ruled residual; fixing the parser changes extractTfMonitorNames() semantics for (c2) too and is a separate PR. |
