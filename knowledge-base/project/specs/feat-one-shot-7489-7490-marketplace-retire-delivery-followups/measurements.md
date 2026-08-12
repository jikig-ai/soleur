# Measurements — legacy marketplace decision and post-delivery follow-ups

Trackers: #7489, #7490. Plan:
`knowledge-base/project/plans/2026-08-12-chore-legacy-marketplace-decision-and-delivery-followups-plan.md`.

Environment for every reading below unless a row says otherwise:

| | |
|---|---|
| Claude Code CLI | `2.1.228` |
| git | `2.53.0` |
| Platform | Linux |

**Redaction.** Every reading committed here is produced with the probe's `--redact` mode, which
covers the four exposure categories named in the plan's `## User-Brand Impact`: home paths, the
names and layout of unrelated local repositories, install timestamps, and machine identifiers.
Unrelated project paths are mapped to stable `<unrelated-local-project-N>` placeholders, which
preserves the two facts a reader needs — how many distinct projects, and which install belongs to
which — while disclosing neither their names nor their layout. The scrub is asserted, not assumed:

```console
$ bash scripts/plugin-legacy-resolver-probe.sh --json --redact \
    | grep -cE '/home/|/Users/|/git-repositories/|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:'
0
```

---

## Phase 1 — Pre-state reading (2026-08-12T20:19:07Z)

Command:

```console
$ bash scripts/plugin-legacy-resolver-probe.sh --json --redact
```

Verdict: **`legacy-present`**.

| Fact | Reading |
|---|---|
| Matched local aliases | `["soleur"]` |
| Sites walked | 7 (0 unreadable) |
| Registrations resolving to `jikig-ai/soleur` | **2** — `user-settings` and `known-marketplaces`, each carrying `autoUpdate: true` |
| Installs resolving to `jikig-ai/soleur` | **1** — `soleur@soleur`, `scope: project`, `projectPath: <unrelated-local-project-2>` |
| Installs with an unresolvable alias | 0 |
| Enabled plugins resolving to the target | 0 |

The install is **project-scoped to a repository other than this one**. That is the fact that
reassigns #7489: removing it changes another project's tooling, so it is a decision rather than a
tidy-up of this repository's own state.

Full site chain as read (paths redacted):

| Site | Status | Registrations resolving to the target |
|---|---|---|
| `managed-settings` (`/etc/claude-code/managed-settings.json`) | absent | — |
| `user-settings` (`<home>/.claude/settings.json`) | present | `soleur` → `jikig-ai/soleur`, `autoUpdate: true` |
| `user-settings-local` | absent | — |
| `project-settings` (`<project>/.claude/settings.json`) | present | none |
| `project-settings-local` | absent | — |
| `known-marketplaces` (`<home>/.claude/plugins/known_marketplaces.json`) | present | `soleur` → `jikig-ai/soleur`, `autoUpdate: true` |
| `installed-plugins` | present | (install site; see above) |

### Two schema facts the plan did not have, both found by running against the real machine

Both were discovered because the probe was pointed at this machine after its synthesized fixtures
were green — the fixtures instantiated one member of each shape-space and production carried
another. Both are recorded here rather than silently accommodated, because each is a shape a
future reader of `installed_plugins.json` or `known_marketplaces.json` will meet.

1. **`installed_plugins.json` maps each `plugin@alias` key to an ARRAY of install records, not to a
   single object.** One plugin id can be installed at several project scopes at once, and each
   scope is its own record. A probe that reads the value as an object reports the first install and
   is silently blind to the rest. The array shape is what this machine carries; the object spelling
   is still accepted by the probe so a differently-versioned CLI does not crash it.

2. **`known_marketplaces.json` carries TWO source shapes.** `{"source":"github","repo":"owner/name"}`
   and `{"source":"git","url":"https://github.com/owner/name.git"}` both occur in the live file
   (`claude-plugins-official` uses the first, `every-marketplace` the second). They denote the same
   kind of thing, so a predicate that reads only `.repo` is blind to every registration written in
   the `url` form. The probe normalises both.

Neither is a defect — they are undocumented shapes. They are not routed upstream: unlike the four
findings in `upstream-reports.md`, nothing here is broken, and an issue describing a schema someone
chose is noise.

---

## Phase 2 — The environment-variable family and the destructive paths

_Filled in by Phase 2. Each arm records the command run and a verdict of `measured:` with a result
or `unverified:` with a statement of what would verify it._

---

## Phase 3 — Post-state reading

_Filled in by Phase 3, under whichever arm is taken and under the headless branch alike._
