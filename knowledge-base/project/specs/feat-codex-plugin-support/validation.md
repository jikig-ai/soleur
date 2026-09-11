# Codex support validation

Date: 2026-09-11. Runtime: Codex CLI 0.154.0, Bun 1.3.11.

## Review

Reviewed the implementation for canonical-source reuse, installed-path
resolution, shell argument handling, config preservation, environment
isolation, workflow successor fidelity, and accuracy of support claims.
Review ran sequentially; no independent subagent review is claimed.

Findings fixed:

- A single custom skill root hid 95 canonical skills; use two explicit roots.
- Native skill metadata contains qualified names, not bare names.
- A setup-only directory was incorrectly counted as a skill.
- A fixture initially ran the source hook instead of its installed copy.
- Legacy welcome tests inherited Codex markers; isolate the simulated harness.
- Codex loads worktree hooks from the shared root; install configuration there.
- Marketplace sparse checkout requires repeated flags.

No unresolved finding remains in the changed implementation. The deliberately
unsupported surfaces are recorded in the plan and onboarding guide.

## QA

| Check | Result |
| --- | --- |
| Native marketplace registration and installation | PASS |
| Native installed skill discovery | 98 enabled skills: 95 workflows plus three wrappers |
| Native hook discovery | Six plugin hooks, two repository hooks, zero errors |
| Canonical agent resolution | All 68 agents resolve to their own definition paths |
| Adapter, routing, component, welcome and package suites | 1,371 tests pass |
| Installer safety and worktree suite | Three tests pass |
| Markdown lint | PASS |
| Shell and JavaScript syntax | PASS |
| ADR ordinal guard | PASS |
| LikeC4 regeneration | PASS: 71 elements, 144 relations, 73 views |
| Diff whitespace check | PASS |

The discovery probe makes no model calls and executes no hooks. Hook trust is
unchanged; the user reviews definitions in Codex. Every autonomous workflow
has not been run end-to-end.

## Existing findings

The unchanged root lockfile reports two high-severity npm audit packages:
js-yaml and liquidjs. Tracked in
[#8065](https://github.com/jikig-ai/soleur/issues/8065); no dependency changes
are included in Codex support.
