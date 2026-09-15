# ADR-221: Per-harness hook registries with a disposition ledger

- **Date:** 2026-09-15

## Status

Accepted.

## Context

Devin CLI loads `.claude/settings.json` hooks (`read_config_from.claude`),
but its tool wire names are lowercase (`exec`, `write`, `edit`,
`ask_user_question`, `run_subagent`, `skill`) where Claude matchers spell
`Bash`, `Write`, `AskUserQuestion`. Measured in a controlled child session
(`knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md`):

- `Bash` matchers are dead under Devin — the hook is loaded but never
  dispatched (#8205's latent-defect class, ~24 registrations).
- Lowercase twins in the same file DO fire — but unanchored `write`
  over-bound `todo_write`; anchoring (`^write$`) is required.
- Devin loads `.claude/settings.json` AND `.devin/config.json` AND installed
  plugin `hooks.json`, with NO cross-source deduplication — an identical
  SessionStart command fired once per registry source.
- SessionStart source matchers (`startup|resume|clear|compact`) are dead
  under Devin; only the empty matcher `""` fires.
- `.claude` `permissions.*` are not imported; `.devin/config.json`
  permissions use `Exec(prefix)`/`Read(glob)`/`Write(glob)`/`Fetch(pattern)`.
- Hook bodies that gate on `tool_name == "Bash"` fire-then-no-op when the
  matcher is widened but the body is not — the second half of the defect.

The rejected alternative — widening Claude matchers to `^(Bash|exec)$` —
recreates the Grok double-fire class under Devin (both the settings entry
and a `.devin`/plugin entry would dispatch the same call) and falsifies the
file's own semantics ("this registry is Claude-canonical").

## Decision

1. `.claude/settings.json` stays Claude-canonical. Claude matchers keep
   Claude tool names. Anchored lowercase twins (`^write$`,
   `^ask_user_question$`) remain in settings.json — they serve Grok
   (ADR-215-era Guard 2) and coincidentally cover those tools under Devin.
2. `.devin/config.json` is the Devin registry. Every hook that must run
   under Devin and is not covered by a settings twin is bound there with an
   anchored matcher (`^exec$`, `^(edit|multi_edit|notebook_edit)$`, `^edit$`,
   `^skill$`). Permissions are ported to Devin syntax
   (`Bash(prefix:*)` → `Exec(prefix)`; `Read(...)` carried verbatim).
3. `plugins/soleur/hooks/hooks.json` stays the plugin-carrier registry;
   `browser-snapshot-credential-guard.sh` is `covered-by-plugin` pending
   #8155's `^(Bash|exec)$` widening plus a runtime trace (draft-held).
4. In-body `tool_name` gates consume a normalized kind: `hook-input.sh`
   exports `HOOK_TOOL_KIND` via `lib/hook-tool-kind.sh`
   (`exec`→`Bash`, `write`→`Write`, `edit`→`Edit`, `ask_user_question`→
   `AskUserQuestion`, `run_subagent`→`Agent`, `skill`→`Skill`, …).
   `HOOK_TOOL_NAME` stays byte-exact for telemetry. The Python twin in
   `security_reminder_hook.py` is pinned by a parity test.
5. `.claude/hooks/devin-dispositions.tsv` is the audit source of truth: one
   row per registration across all registries plus permissions, with
   disposition ∈ {bind, covered-by-twin, covered-by-plugin, already-fires,
   n/a, skip} and a mandatory reason for non-bound rows.
6. `.claude/hooks/devin-matcher-parity.test.sh` is the drift guard: it
   enumerates the registries with jq (never a hardcoded list),
   regex-EVALUATES every matcher via `jq test()` against the measured Devin
   vocabulary, and fails on missing ledger rows, missing `.devin` bindings,
   unanchored matchers, dead SessionStart source matchers in `.devin`, and
   cross-registry double-fire.

## Consequences

- Devin gets honest, measured parity for the triaged hook set instead of
  24 dead matchers asserted as live coverage.
- Claude behavior is unchanged: no settings matcher was widened; the only
  settings edits anchor existing lowercase twins.
- `Monitor`, `CronCreate`, and `Task`-token hooks carry `n/a`/`skip` rows
  with `SOLEUR_HOOK_SKIP`-style markers — dead-on-Devin is now documented,
  not latent.
- `SessionStart` under Devin fires on `""` only; the four settings
  SessionStart hooks and the plugin `devin-session-start.sh` bind there.
- Adding a hook registration without a ledger row reds the parity test —
  the audit cannot silently rot.
- `.claude` permissions stay dead under Devin by design; the `.devin`
  `permissions` block is the ported analog.

## Verification

`bash .claude/hooks/devin-matcher-parity.test.sh` — 7 sections: coverage
(102 registrations + permissions rows), bind backing, twin backing,
double-fire, SessionStart honesty, ledger hygiene (with must-pass/must-fail
controls), permissions parity. Mutation-checked: deleting a `.devin`
binding or unanchoring a twin turns it red.
