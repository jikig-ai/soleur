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

Every arm ran against a scratch `HOME` under `/var/tmp`. Nothing below wrote to the operator's
`~/.claude`. The instrument for arms 1, 2 and 5 is the deliberately-tiny timeout
(`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=1`), because a *raised* timeout proves nothing — success at the
default is indistinguishable from success at the raised value, so only a value that FORCES failure
is falsifiable.

### Arm 1 — Control: does the instrument fire on this CLI version?

```console
$ HOME=<scratch> CI=true CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=1 \
    claude plugin marketplace add jikig-ai/soleur-marketplace
✘ Failed to add marketplace: ... Git clone timed out after 0s ...
rc=1  elapsed=3s
```

**`measured:`** the instrument fires, deterministically and in 3 s. Every arm below that reads a
timeout as a signal rests on this control.

### Arm 2 — Claim (a): does a settings-file `env` block reach the plugin git path?

Two runs against the same scratch `HOME` shape, differing only in the settings file. The process
environment carried no `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` in either (`env -u` on both).

| `~/.claude/settings.json` | rc | elapsed | outcome |
|---|---|---|---|
| `{"env":{"CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS":"1"}}` | 1 | 4 s | `Git clone timed out after 0s` |
| `{}` (positive control) | 0 | 10 s | `Successfully added marketplace` |

**`measured: TRUE`** — a settings-file `env` block DOES reach the plugin git path. The positive
control is what makes this attributable: without it, the timeout could have been caused by anything
in the scratch environment.

### Arm 3 — Claim (b): does it reach the BACKGROUND refresh?

**`unverified:`** — and this is the claim that actually matters, because the background refresh is
the one that runs without the operator's shell.

The blocker is that the refresh could not be triggered deterministically. With `lastUpdated`
backdated to `1` and `autoUpdate: true`, a `claude plugin list` left `lastUpdated` **unchanged at
`1`** — so `plugin list` does not drive a refresh and cannot be used as the trigger.

**What would verify it:** a real session start (interactive, or `claude -p`) against a backdated
scratch `HOME`, with the settings `env` block set and the process environment clean, observing
whether the clone times out. That consumes API budget and is not deterministic, so it was not run
here. It is explicitly NOT inferred from arm 2: arm 2 establishes the block reaches a foreground
`marketplace add`, which is a different call path from the background refresh.

### Arm 4 — `autoUpdate: false`: persistence, suppression, and the authoritative site

**`measured:` persistence.** A hand-written `autoUpdate: false` in a scratch
`known_marketplaces.json` survived a subsequent CLI invocation byte-identically, `lastUpdated`
included:

```console
before: [{"autoUpdate":false,"lastUpdated":"2026-08-12T20:28:40.690Z"}]
after : [{"autoUpdate":false,"lastUpdated":"2026-08-12T20:28:40.690Z"}]
```

**`unverified:` suppression, and which of the two declaration sites is authoritative.** Both
questions need an observable refresh, and arm 3 established there is no deterministic trigger. The
same session start named in arm 3 would verify both.

**Incidental measured fact, recorded because it contradicts an assumption it would be easy to
make:** a *fresh* `marketplace add` on 2.1.228 records `autoUpdate: null`, not `true`. The legacy
entry on this machine carries `autoUpdate: true`, so that value was written by something other than
a plain present-day `add` — an older CLI, or the install flow. Nothing here establishes which.

### Arm 5 — `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE`, and the destructive path

**`unverified:` — and the reason is a NEGATIVE result worth more than the arm was designed to
produce: the destructive path itself could not be reproduced on 2.1.228.**

Three independent forced-failure instruments were run, each against a scratch checkout carrying a
sentinel file that an in-place reconcile preserves and a re-clone cannot:

| Instrument | Result |
|---|---|
| `add --sparse` with `GIT_TIMEOUT_MS=1` (abort before clone) | checkout intact, sentinel intact, **no `.bak`** |
| `marketplace update` against a remote pointed at a nonexistent repo | checkout intact, sentinel intact, **no `.bak`** |
| `add --sparse` with an unroutable proxy (clone fails mid-flight) | checkout intact, sentinel intact, **no `.bak`** |

Both arms of the variable — set and unset — produced identical results in every instrument, so the
variable's effect **could not be differentiated**: the branch it governs never executed.

The strings are real and present in the 2.1.228 bundle
(`git pull failed, will re-clone:`, `sparse-checkout reconcile requires re-clone:`, a
`` `${t}.bak` `` rename, and a later `rm(m)` + `rm(`${m}.bak`)` pair). But a string is not a
behaviour. On the evidence actually obtained, **the claim that a failed refresh destroys the
checkout is NOT reproducible on this version**, and the `rm` of both the checkout and its `.bak`
sits in what reads as a *removal/cleanup* path, where deleting both is defensible rather than a
defect.

**Consequence, carried into Phases 5 and 6.** This is the claim that set the plan's
`single-user incident` threshold and that the routing table sends upstream as a NEW issue. It is
not filed: opening an issue on a third party's repository asserting a destructive failure this
session could not reproduce would be precisely the unverified-inference-stated-as-fact failure the
plan cites as a constraint. What is reportable — and what the runbook now says — is the measured
half: `--sparse` against an existing checkout forces a re-clone (arm 6).

**What would verify it:** a reproduction on the version the original observation came from, or an
instrument that reaches the rename before the clone fails. Neither was found here.

### Arm 6 — The `--sparse` re-clone hazard

Scratch `HOME`, plain `marketplace add`, a sentinel planted inside the resulting checkout, then the
same marketplace added again **with** `--sparse .claude-plugin`:

| Observation | Before | After |
|---|---|---|
| sentinel file | present | **gone** |
| `.git` inode | `18358039` | **`18358110`** |
| `.git/info/sparse-checkout` | absent | **present** |

**`measured: TRUE`** — applying `--sparse` to an EXISTING plain checkout forces a full re-clone; it
does not reconcile in place. Three independent signals agree, and the changed inode rules out the
sentinel simply having been deleted.

The consequence is size-dependent and that is where the user harm lives: this measurement used the
small marketplace repo (232 KiB, 8 s). Against the 181 MiB monorepo the same forced re-clone is the
329 s operation previously measured, which cannot complete inside the CLI's 120 s default. So the
runbook's existing advice — reach for `--sparse` when the legacy channel must be kept — instructs a
stranded user into an operation that will not finish. Corrected in the runbook under Symptom 2.

An earlier run of this arm is void and is not counted: the sentinel write failed because the
checkout directory is named after the marketplace ALIAS (`soleur-marketplace`), not after the
`owner-repo` slug that appears in the CLI's own clone-progress line. The re-run above discovers the
directory rather than assuming its name, and hard-fails if the sentinel is not present after the
write — a harness that cannot set up must abort, not produce a confident wrong verdict.

### Arm 7 — `marketplace remove` symmetry

```console
after add    : known_marketplaces.json ["soleur-marketplace"]  settings.extraKnownMarketplaces ["soleur-marketplace"]
after remove : known_marketplaces.json []                      settings.extraKnownMarketplaces []
probe verdict: clean  (matched_registration_count=0)
```

**`measured: TRUE`** — `remove` cleans BOTH declaration sites. Arm A's "no resolver remains" outcome
is therefore true as stated and needs no additional hand-removal step.

### Arm 8 — The rest of the environment family, recorded not measured

Enumerated from the 2.1.228 binary, which is the defining artefact rather than the documentation:

```console
$ strings "$(readlink -f "$(command -v claude)")" | grep -aoE 'CLAUDE_CODE_PLUGIN_[A-Z0-9_]+' | sort -u
CLAUDE_CODE_PLUGIN_BINARY_ASSETS
CLAUDE_CODE_PLUGIN_CACHE_DIR
CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS
CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE
CLAUDE_CODE_PLUGIN_PREFER_HTTPS
CLAUDE_CODE_PLUGIN_SEED_DIR
CLAUDE_CODE_PLUGIN_USE_ZIP_CACHE
```

Seven names. The four not exercised above — `_BINARY_ASSETS`, `_CACHE_DIR`, `_SEED_DIR`,
`_USE_ZIP_CACHE` — are recorded here with behaviour **unmeasured** and deliberately do not enter the
runbook: four knobs nobody will set, in a document read during an outage, is anti-value.

### Phase 2 verdict summary

| Arm | Subject | Verdict |
|---|---|---|
| 1 | Instrument control | `measured` |
| 2 | Settings `env` block reaches the git path | `measured: true` |
| 3 | Settings `env` block reaches the background refresh | `unverified` |
| 4 | `autoUpdate:false` persistence / suppression / authoritative site | `measured` (persistence) + `unverified` (suppression, site) |
| 5 | `KEEP_MARKETPLACE_ON_FAILURE`, destructive path | `unverified` — destructive path not reproducible |
| 6 | `--sparse` forces a re-clone | `measured: true` |
| 7 | `remove` cleans both sites | `measured: true` |
| 8 | Remaining env family | recorded, `unmeasured` |

---

## Phase 4 — The canary's reference transport, decided by measurement

The plan prescribed per-file fetches from `raw.githubusercontent.com`, pinned to the delivered
commit. That was correct about the *semantics* and wrong about the *transport*, which only a live
run could show. Three transports were measured against the real published channel:

| Transport | Result |
|---|---|
| Per-file over `raw.githubusercontent.com` (~890 sequential requests) | **Unusable.** Not finished after 30 min against a 15-min job budget. Raised intermittent `reference_unreadable` findings on files that return HTTP 200 in isolation (verified: the named file returns 200, and 10 rapid fetches all succeed). |
| Whole-repo tarball from `codeload.github.com` | **Worse.** `curl` timed out at 300 s having received 28,382,559 bytes of a ~181 MiB archive; the extract failed and no plugin subdir materialised. |
| `git archive <sha> -- plugins/soleur` from the checkout the job already holds | **Viable.** No network. Full run **117 s**, `compared=896 expected=896`, all three conjuncts green. |

Final live reading, against the real channel:

```console
$ bash scripts/plugin-delivery-canary.sh
canary-counts| compared=896 expected=896
canary-conjuncts| completeness=green integrity=green freshness=green
canary-finding| every delivery assertion holds at 154302d32114abba3165ce47daefe5bfe508d02f
rc=0, 117 s
```

**Why the first two failures are recorded rather than just fixed.** Both produced findings that
*named the delivery channel* while the fault was in the canary's own invocation — an alarm that
blames the thing it watches. On a daily schedule that is the cry-wolf failure, and it would have
trained the operator to ignore the one signal this change adds.

**One exclusion earned its place, measured.** The delivered tree carries `.in_use/<pid>` — a lock
directory the CLI writes *into* the install path (observed member `.in_use/143463`). It is runtime
bookkeeping owned by the CLI, not content the repository serves, so it can never appear in the
reference. Note the direction: this is delivered-**more**. The 891-vs-894 delivered-**fewer** delta
the plan cited is a different question and stays unattributed, so it would still surface as
`incomplete_delivery` with each path named.

---

## Phase 3 — The decision, and the post-state reading

### Mode branch

**Attached.** The session ran in the main agent loop with an operator present, not inside a Task
subagent, and stdin was a TTY. Both signals the plan names were checked, and they are a
CONJUNCTION: a `/soleur:one-shot` context is explicitly not by itself a headless signal, so the
attached branch is the correct one and `decision-challenges.md` was not written.

### The question, and the answer

Asked once, with Phase 2's verdicts attached. Arm A was offered normally (its precondition, arm 7,
measured true). Arm B was offered **carrying its unverified label** — `autoUpdate: false`
persistence is measured but suppression and the authoritative site are not — rather than being
presented as equivalent to a measured arm. No arm was withdrawn, because Phase 2 falsified nothing.

**Answer: arm A — migrate that project onto the published channel.**

### Arm A, executed (2026-08-12T20:35:46Z)

Run from the install's own `projectPath` with `--scope project`, which is the caveat that makes the
difference between migrating the right install and silently creating a second one at user scope:

| Step | Result |
|---|---|
| `claude plugin marketplace add jikig-ai/soleur-marketplace` | `✔ Successfully added marketplace: soleur-marketplace` |
| `claude plugin install soleur@soleur-marketplace --scope project` | `✔ Successfully installed (scope: project)` |
| `claude plugin uninstall soleur@soleur --scope project` | `✔ Successfully uninstalled plugin: soleur` |
| `claude plugin marketplace remove soleur` | `✔ Successfully removed marketplace: soleur` |
| orphan reclaim, behind the runbook's print-then-delete check | 26 MiB freed |

### Post-state reading

```console
$ bash scripts/plugin-legacy-resolver-probe.sh --json --redact
{"verdict":"clean","matched_aliases":[],
 "summary":{"site_count":7,"unreadable_site_count":0,"matched_registration_count":0,
            "target_install_count":0,"unknown_install_count":0,
            "target_enabled_count":0,"unknown_enabled_count":0}}
```

| Artefact | Pre-state | Post-state |
|---|---|---|
| Registrations resolving to `jikig-ai/soleur` | 2 (both `autoUpdate: true`) | **0** |
| Installs resolving to `jikig-ai/soleur` | 1 (project scope) | **0** |
| `<home>/.claude/plugins/marketplaces/soleur` | 378 MiB | **absent** |
| `<home>/.claude/plugins/cache/soleur` | 26 MiB | **absent** |
| Live Soleur install | `soleur@soleur` `0.0.0-dev` | `soleur@soleur-marketplace`, project scope |

**This satisfies #7489's FIRST closing condition, not merely its second.** The tracker offered two
ways to close — confirmation that no install remains on the `soleur@soleur` id, or a recorded
decision to keep the entry live with the consequence accepted. The plan expected only the second to
be reachable. The probe now returns `clean` on the one machine in the beta population, so the
stronger condition is met by measurement.

Two things it does NOT establish, stated so the close is not read as more than it is:

- The monorepo marketplace ENTRY remains published and reachable. Retiring it was measured to buy
  nothing for a stranded install (the checkout is cloned before the manifest is read) and is
  recorded in ADR-182 as a rejected alternative. So "no install remains" is a statement about this
  machine, not about the channel.
- `clean` is a statement about the machines probed. There is exactly one in the beta population, so
  here the two coincide; that coincidence is a property of the population size and will stop
  holding the moment it grows.

### Two measured facts the arm produced incidentally

1. **`marketplace remove` reclaims the 378 MiB checkout itself.** The runbook's reclaim section
   warns only about the plugin CACHE being left behind. On 2.1.228 the marketplace checkout is
   removed by `remove`; only `cache/soleur` (26 MiB, not the ~9.6 MiB the runbook quotes) survived.
   The cache figure grows per update, which is the compound-version orphan ADR-182 records — this
   machine had accumulated two version directories.

2. **The unidentified 8-character half of the compound version is CONSTANT across deliveries.**

   | Install | `version` | `gitCommitSha` |
   |---|---|---|
   | earlier today | `43c7d3d79542-31fddb37` | `43c7d3d79542e0909b…` |
   | this migration | `0d6443960662-31fddb37` | `0d644396066262b32…` |

   The 12-character half tracks the delivered commit and equals `main` HEAD both times
   (`git ls-remote … HEAD` = `0d644396066262b32884a2faec10e317857bea5e`). The 8-character half is
   **byte-identical across two different delivered commits**, so it is not a commit identifier at
   all — it is stable per plugin or per marketplace entry. This is sharper than the plan's
   "unidentified" and is what goes upstream: not "we cannot explain this string", but "this half
   does not vary with the content it purports to identify".
