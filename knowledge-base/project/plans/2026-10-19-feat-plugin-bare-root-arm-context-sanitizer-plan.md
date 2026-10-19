---
title: "feat(machinery): plugin-level bare-root SessionStart arm + shared context sanitizer"
type: feat
date: 2026-10-19
slug: plugin-bare-root-arm-context-sanitizer
branch: feat-one-shot-10392-10395-sessionstart-sanitizer
issue: 10392
closes: [10392, 10395]
lane: cross-domain
---

# feat(machinery): plugin-level bare-root SessionStart arm + shared context sanitizer

## Overview

Two deferred follow-ups from the session-start bare-root CWD detection that
shipped repo-level in PR #10386 for #10383.

**#10392** asks for a plugin-level `""`-matcher SessionStart arm in
`plugins/soleur/hooks/hooks.json` so the bare-root-anchored-session detection
reaches *other repositories on customer machines* — a population the repo-level
`.claude/hooks/session-rules-loader.sh` arm cannot reach. The arm must reuse
the ADR-099 row-3 repo-layout predicate so a genuinely bare customer repo
(`git init --bare`, mirror, server repo) never gets a misapplied redirect, and
its redirect text must degrade gracefully off this repo's topology. The issue
also asks for an audit of sibling SessionStart scripts
(`.claude/hooks/supabase-loopback-warn.sh`,
`.claude/hooks/memory-backstop-resolve.sh`, `scripts/ensure-kb-index.sh`) for
bare-root write behavior at session start.

**#10395** (security-sentinel P3, deferred from PR #10386 review) reports that
the context-sanitizing strips `tr -d '\000-\037'` (and the loader's
`\000-\010\013-\037` keep-lines variant) pass DEL (0x7F) and UTF-8
U+2028/U+2029, allowing a spoofed line inside `[bare-root-cwd]`-style context
blocks. The fix is a shared sanitizer helper that additionally strips `\x7f`
and the `e2 80 a8` / `e2 80 a9` byte sequences, adopted at every strip site
across `.claude/hooks/` and `plugins/soleur/`.

Both issues are `meta/machinery` + `domain/engineering`; #10395 is
`type/security`. One PR closes both because the new plugin hook's own context
emit is itself a sanitize site — landing the shared helper first makes the
hook's emit correct by construction.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10392` / `gh issue view 10395` — both **OPEN**, fetched in
  full. Titles and labels recorded in frontmatter (`type/security` on #10395).
- `gh pr view 10386` — **MERGED** 2026-10-19 ("session-start bare-root CWD
  detection + redirect (#10383)"). The deferral premise holds.
- Every file both issues cite exists on `origin/main`:
  `.claude/hooks/session-rules-loader.sh`, `.claude/hooks/bare-root-cwd-guard.sh`,
  `.claude/hooks/supabase-loopback-warn.sh`,
  `.claude/hooks/memory-backstop-resolve.sh`, `scripts/ensure-kb-index.sh`,
  `.devin/config.json`, `plugins/soleur/hooks/hooks.json`,
  `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`.
- ADR-099 line 45 **explicitly records the plugin `""`-matcher arm as deferred
  to #10392** — this plan is that deferral being executed, not a new proposal.
- Proposed-mechanism vs ADR corpus: the detection mechanism (three-term
  config-FILE predicate) is ADR-099/ADR-173-canonical and already deployed at
  three sites. A "create a lib for the predicate" mechanism would touch three
  pinned working copies for no new property — see Cut List.
- Nothing stale found; the premise holds as written.

### Property List (Phase 0.6b)

1. **P1** — a session anchored at a row-3 bare repo root in a repo *other than*
   soleur, on a machine with the plugin installed, receives the bare-root
   advisory at session start.
2. **P2** — a genuinely bare customer repo (`git init --bare`, mirror, server
   repo) and every non-bare shape receive **no** redirect (no false positives).
3. **P3** — every SessionStart script's bare-root write behavior is
   enumerated, and writes that buy nothing at a bare root (untracked scratch
   the sync overlay preserves forever) are suppressed where cheap.
4. **P4** — no context-boundary strip site in `.claude/hooks/` or
   `plugins/soleur/` passes DEL or U+2028/U+2029; one shared helper defines
   the byte contract.

### Mechanism → Property check (Phase 0.6b)

| Mechanism the ask names | Property bought | Already on origin/main? |
|---|---|---|
| Plugin `""`-matcher SessionStart arm | P1 | No — repo arm is repo-level only; plugin `hooks.json` has no bare-root entry |
| Shared sanitizer helper | P4 | Partially — `scripts/lib/strip-log-injection.sh` exists but (a) is unreachable from `plugins/soleur/` at runtime (plugin ships only `plugins/soleur/**`), (b) encodes a *different* byte contract (log/`$GITHUB_OUTPUT` injection: keeps `\t`, strips `\n`, skips most of C0), and (c) has no keep-lines variants. Not reusable for the context-boundary contract |
| Row-3 predicate (three-term config-FILE) | P2 | Yes — verbatim at `bare-root-cwd-guard.sh`, `bare-head-self-heal.sh`, `git-repo-readiness-diag.sh`, parity-pinned by `git-repo-readiness-diag.test.sh` (8 fixture classes). Reuse the convention: a fourth inline copy + parity coverage, not a fourth abstraction |

### Cut List (Phase 0.6b)

- **Predicate lib extraction** (migrate the three existing inline copies to a
  shared predicate lib) → buys no new property; the parity-test convention
  already keeps the copies honest and the refactor touches three tested,
  working scripts. Cut. The *new* consumers get the predicate the same way the
  existing ones did: an inline copy pinned by the same fixture classes.
- **Unify `strip-log-injection.sh` with the new helper** → different stated
  byte contract for a different threat surface (GitHub-output/log injection vs
  agent-context injection). Merging would either weaken the log helper or
  over-strip its `$GITHUB_OUTPUT` domain. Cut — documented disposition instead.
- **Rewrite `hold-gate-eval.sh` `clean_text()` onto the helper** → it is
  already a *superset* (`[:cntrl:]` + `\xc2[\x80-\x9f]` + `\xe2\x80[\x8b-\x8f\xa8-\xae]` +
  `\xe2\x81[\xa6-\xa9]` + BOM). Adopting the helper would narrow it. Cut —
  recorded as already-superset in the census.

### Repo research (inline — sequential-fallback; no Task spawn surface)

- **Predicate copies (3, parity-pinned):** `bare-head-self-heal.sh:44-49`,
  `bare-root-cwd-guard.sh:46-49`,
  `plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh:72-74`.
  Verdict parity asserted over 8 fixture classes in
  `plugins/soleur/test/git-repo-readiness-diag.test.sh` D5 (bare / plain /
  masked / wtmask / sym / truebare / imposter / nonrepo). A `git init --bare`
  root fails the first term (`<dir>/.git` is absent — the git dir IS the
  root), which is exactly the P2 discriminator.
- **Repo arm wiring:** `.claude/settings.json` SessionStart
  `startup|resume|clear|compact` → `session-rules-loader.sh`, which calls the
  guard as a time-boxed child (5 s) and forwards only marker + `[bare-root-cwd]`
  lines, control-stripped, capped at 12 (`session-rules-loader.sh:333-347`).
  `.devin/config.json` `""` matcher reaches the same loader via a
  `hook_root` resolver that already handles bare roots.
- **Plugin SessionStart envelope contract:** `additionalContext` via
  `hookSpecificOutput.hookEventName:"SessionStart"` (learning
  `2026-03-04-sessionstart-hook-api-contract.md`); `""` matcher fires under
  Devin (devin-dispositions.tsv row for `devin-session-start.sh`, EC§3) and on
  every source under Claude Code.
- **Registration machinery:** `.claude/hooks/devin-matcher-parity.test.sh`
  requires a `soleur-plugin` row in `.claude/hooks/devin-dispositions.tsv` for
  every `hooks.json` registration — adding the entry without the row goes RED.
- **Overlay semantics:** `sync_bare_files` (`worktree-manager.sh:4474+`)
  materializes a full HEAD mirror — every tracked file exists at the bare
  root — but is *additive for untracked paths*. Gitignored runtime files
  (`.claude/.memory-backstop*`, `.claude/.session-manifests/`,
  `knowledge-base/INDEX.md`, `.kb-index.stamp`) written at the bare root
  persist there forever. This is the "overlay materialization" the audit
  ask names.
- **Byte-equal-copy precedent:** `.claude/hooks/memory-backstop.sh` ≡
  `plugins/soleur/hooks/memory-backstop.sh` (byte-identical, pinned by
  `plugins/soleur/test/backstop-parity.test.ts`); `lib/log-rotation.sh` and
  `lib/hook-tool-kind.sh` share the same dual-home shape. The
  "duplicate + parity pin" convention is how files that must exist in both
  runtime topologies are kept honest.
- **Canonical sanitize form already exists inline at 8+ sites** —
  `LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed -e 's/\xe2\x80\xa8//g' -e 's/\xe2\x80\xa9//g'`
  (e.g. `prod-write-defer-gate.sh:404`, `agent-token-tee.sh:97`,
  `ship-kb-archive-gate.sh:778`, `domain-model-drift.sh:321` which also strips
  NEL `\xc2\x85`). Consolidating absorbs these into the helper rather than
  inventing a new contract.
- **`tr` octal-only caveat** (learning `2026-05-11-tr-does-not-interpret-hex-escapes.md`):
  `tr -d '\x7f'` strips literal `x`/`7`/`f`. DEL must be `\177` octal.
- **Session-start helper-extraction patterns** (learning
  `2026-03-14-bare-repo-helper-extraction-patterns.md`): sourced libs use
  `return` not `exit`, never call `set`, no global pollution; relative `../`
  arithmetic must be traced per consumer depth.
- **C4 model already carries a DRIFT note** counting SessionStart plugin hooks
  ("now registers SIX"; `model.c4` agentRunner description ~line 117). A new
  hook makes it seven — the description + drift note are an in-scope edit,
  and the note's stated remedy ("fold them into the description in a change
  that also regenerates model.likec4.json") applies.
- **Sequential-fallback precedent:** this subagent harness has no Task/run_subagent
  surface; the #10383 pipeline recorded the same condition and had its five
  technical rows confirmed by a batched CTO spawn post-hoc. Same posture here:
  technical rulings are `pending - assumed:` rows in
  `specs/<branch>/decision-challenges.md`.

### Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| #10392: "sibling SessionStart scripts ... audit ... for their own bare-root write behavior" | `supabase-loopback-warn.sh` is read-only; `ensure-kb-index.sh` materializes 4 gitignored files at a bare root; `memory-backstop-resolve.sh` → `memory-backstop.sh` writes `.claude/.memory-backstop.{jsonl,lock,stamp}` at `project_dir` = bare root; `devin-session-start.sh` can write `/.devin/` when toplevel resolution is empty AND the process runs as root | Audit table in this plan + README; fixes for ensure-kb-index + devin-session-start; keep-disposition for backstop ledger (pending-assumed) |
| #10395: "any sibling `tr -d '\000-\037'` strips" | Census found ~17 adoption sites plus already-canonical, superset, and non-context strips (see Strip-Site Census) | Every site gets an explicit adopt / already-canonical / superset / out-of-scope disposition |
| Implicit: the plugin arm can reference `worktree-manager.sh` | Customer repos don't carry it; the plugin cache copy does (`${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/...`) but is soleur-tuned | Redirect text is generic `git worktree add`; the soleur-hint line is gated on the plugin script existing |

## Problem Statement / Motivation

The bare-root misanchor measured in #10383 is not soleur-specific: any repo
using the row-3 layout (bare repo stored inside `<root>/.git` with a synced
overlay at the root) exposes the same failure — sessions anchored there do
file-touching work outside any branch. The plugin's distribution channel
(`git-subdir` of `plugins/soleur` onto customer machines) is the only surface
that reaches those repos at session start. Separately, the advisory blocks the
gate emits are only as trustworthy as their sanitizers; the P3 finding shows a
consistent gap class (DEL + LS/PS) across a codebase that already half-fixed it
site-by-site — the fix is consolidation, not another one-off.

## Proposed Solution

### Workstream A — shared context sanitizer (#10395)

Create `context-sanitize.sh`, a sourced bash lib in two byte-equal copies:

- `.claude/hooks/lib/context-sanitize.sh` — for `.claude/hooks/` consumers.
- `plugins/soleur/scripts/lib/context-sanitize.sh` — for plugin consumers
  (`plugins/soleur/hooks/`, `plugins/soleur/scripts/`,
  `plugins/soleur/skills/*/scripts/`). `plugins/soleur/` is the only tree
  present in both runtime topologies (repo checkout + plugin cache); repo-side
  hooks keep their own copy rather than reaching across the tree, matching the
  memory-backstop dual-home convention.

Three functions (pipe filters, stdin → stdout; all `LC_ALL=C`):

| Function | `tr -d` set | Then | For sites that… |
|---|---|---|---|
| `soleur_ctx_sanitize` | `'\000-\037\177'` | `sed -e $'s/\xc2\x85//g' -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g'` | single-line fields |
| `soleur_ctx_sanitize_lines` | `'\000-\010\013-\037\177'` | same sed | multi-line blocks (keep `\t` `\n`) |
| `soleur_ctx_sanitize_nl` | `'\000-\011\013-\037\177'` | same sed | keep `\n` only (strips `\t` too) |

NEL (`\xc2\x85`) is included because it is the same line-break class and two
existing sites already strip it; adding it everywhere is strictly stronger.
`\177` is octal — `tr` does not interpret `\xHH` (measured learning). The sed
patterns MUST use `$'…'` ANSI-C quoting (the `prod-write-defer-gate.sh:404`
form), never a bare `'s/\x…'` — BSD sed on macOS does not interpret `\xHH`
(a bare-quoted pattern silently matches literal characters and strips
nothing), and this lib's consumers run on customer machines. The lib test's
byte fixtures are what pin this; a grep-level pin (`grep -n "\$'s/"` on both
copies) belongs in `context-sanitize.test.sh`.

**Adoption mechanics per consumer:** source the copy if readable
(`[[ -r "$_ctx_lib" ]] && . "$_ctx_lib"`); if the function is still undefined
(`declare -F`), define a same-name fallback carrying the site's *pre-change*
strip set — never weaker than today, so an unreadable lib degrades to status
quo rather than to zero protection or a hook crash (the loader's
`emit_core_only_fallback` posture, applied per-site).

### Workstream B — plugin-level bare-root arm (#10392 item 1)

New script `plugins/soleur/hooks/bare-root-cwd-guard.sh` (same basename as the
repo hook on purpose — dual-home naming convention; the tree disambiguates):

1. Read the SessionStart envelope on stdin; extract `.cwd` via `jq`. No `jq`
   or no envelope → `exit 0` (silent; a SessionStart hook that cannot emit
   valid JSON must emit nothing).
2. Scrub inherited `GIT_*` location variables (same unset list as the repo
   guard — `GIT_DIR` pointed elsewhere must not redirect the probe).
3. If `git -C "$cwd" rev-parse --show-toplevel` returns non-empty → a
   worktree → exit 0. Else apply the three-term predicate to `$cwd` itself
   (same root-only narrowing as the repo arm — a bare-root *subdirectory*
   session stays silent; `go.md`'s `--is-bare-repository` routing guard is
   the documented in-bare-subdir backstop).
4. **Dedup:** if the target repo already carries its own arm —
   `grep -l 'SOLEUR_BARE_ROOT_CWD' "$root"/.claude/hooks/*.sh` hits AND a
   settings/devin registry references `session-rules-loader.sh` — exit 0
   (the repo arm reports; double-injection would duplicate the block on every
   soleur-repo bare-root session forever).
5. Emit `{"hookSpecificOutput":{"hookEventName":"SessionStart",
   "additionalContext": ...}}` containing one
   `SOLEUR_BARE_ROOT_CWD source=plugin-session-start` marker line plus a
   bounded `[bare-root-cwd]` block whose redirect text is **topology-generic**:
   `git worktree add <path> <branch>` — no `plugins/soleur/...` path, no
   `worktree-manager.sh` — plus one conditional line naming the plugin-side
   manager only when
   `"${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh"`
   exists on the machine. The path is run through `soleur_ctx_sanitize`.

   `source=plugin-session-start` is the telemetry discriminant the issue's
   re-evaluation criterion asks for: `SOLEUR_BARE_ROOT_CWD` is already in
   `MARKER_RE` (`apps/web-platform/server/git-lock-marker-telemetry.ts:170`,
   MIRRORED-NOT-PAGED), and the source token separates repo-arm from
   plugin-arm fires without a registry change.

6. Register in `plugins/soleur/hooks/hooks.json` as a new `SessionStart` entry
   with `"matcher": ""`, command
   `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bare-root-cwd-guard.sh"`, `"timeout": 10`,
   and add the required `soleur-plugin` row to
   `.claude/hooks/devin-dispositions.tsv` (disposition `already-fires` —
   `""` matcher fires under Devin, same evidence class as
   `devin-session-start.sh`).

### Workstream C — sibling SessionStart write audit (#10392 item 2)

See the audit table below; code changes only where marked **fix**.

## Bare-Root SessionStart Write Audit

Every script reachable at session start, its bare-root write behavior, and
disposition. "Overlay materialization" = an untracked write under the bare
root that `sync_bare_files` never prunes.

| Script | Bare-root writes at session start | Disposition |
|---|---|---|
| `session-rules-loader.sh` | `.claude/.session-manifests/<id>.json` (~100 B, gitignored) | **keep** — standing CTO ruling 2026-10-15 (prior spec): the manifest is the forensic record of the misanchor (SOC 2 CC6.1); suppressing discards evidence |
| `supabase-loopback-warn.sh` | none — read-only docker probe (`supabase-local.sh assert`), exits before the probe when the wrapper is absent | **clean** — no change; note it still runs its assert probe at a bare root (harmless, read-only) |
| `memory-backstop-resolve.sh` → `memory-backstop.sh` | `.claude/.memory-backstop.jsonl` (append log, rotated by `lib/log-rotation.sh`), `.lock`, `.stamp` at `project_dir` = bare root | **keep** — bounded + rotated; same forensic reasoning as manifests; protection must still run at a misanchored session. `pending - assumed:` ruling row |
| `scripts/ensure-kb-index.sh --soft` | `INDEX.md`, `kb-tags.txt`, `kb-categories.txt`, `.kb-index.stamp` under `<bare-root>/knowledge-base/` (4 untracked files, permanent overlay scratch; at a bare root the git half of the fingerprint degrades to `ls-files` only) | **fix** — skip regen when `git -C "$KB_DIR" rev-parse --is-inside-work-tree` is not `true`. One line, covers bare roots and non-checkout `--kb-dir` targets; a masked-config worktree degrades to skip (safe direction — that shape is already broken per ADR-173) |
| `devin-session-start.sh` (plugin) | `mkdir -p "$_sentinel_root/.devin"` — when `rev-parse --show-toplevel` is empty at a bare root this becomes `/.devin`; on a uid-0 host the write lands at filesystem root (`assert_fixture_dir` accepts absolute `/*` paths) | **fix** — skip the sentinel write when `_sentinel_root` is empty or non-absolute; a bare-root session emits context only |
| `codex-session-start.sh` (plugin) | none — pure `jq -n` emit | **clean** |
| `welcome-hook.sh`, `version-banner.sh`, `compaction-state.sh`, `ext-filter-detect.sh` (plugin SessionStart arms) | banner/state writes under `$HOME`/`XDG`, not the repo | **clean** — out of repo-write scope |

## Strip-Site Census & Dispositions (#10395)

Every `tr -d` site in `.claude/hooks/` and `plugins/soleur/` classified.
"Canonical" = already `C0+DEL` + `e2 80 a8/a9` sed.

**Adopt — strip-all variant (`soleur_ctx_sanitize`):**

- `.claude/hooks/bare-root-cwd-guard.sh:53` (safe_root — currently no DEL)
- `.claude/hooks/session-rules-loader.sh:383` (WS_WORKTREE — no DEL)
- `.claude/hooks/session-rules-loader.sh:474` (TMPFS alarm — no DEL)
- `.claude/hooks/agent-token-tee.sh:97` (canonical → helper)
- `.claude/hooks/pre-merge-rebase.sh:833` (DEL yes, LS/PS no)
- `.claude/hooks/prod-write-defer-gate.sh:404,432` (canonical → helper), `:433` (DEL, no LS/PS)
- `.claude/hooks/monitor-arm-recorder.sh:72` (weakest — only `\n\t`; passes ESC/DEL/LS/PS today)
- `plugins/soleur/hooks/operator-stage-approval.sh:345` `clean()` (DEL, no LS/PS)
- `plugins/soleur/scripts/run-in-pid-namespace.sh:74` (DEL, no LS/PS)
- `plugins/soleur/scripts/resolve-regenerable-conflicts.sh:168` (DEL, no LS/PS)
- `plugins/soleur/skills/ship/scripts/battery-owed.sh:53` (canonical → helper)
- `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh:278,279` (`[:cntrl:]` — DEL yes, LS/PS no)

**Adopt — keep-lines variant (`soleur_ctx_sanitize_lines`):**

- `.claude/hooks/session-rules-loader.sh:342` (BARE_CWD_BLOCK — no DEL)
- `.claude/hooks/ship-kb-archive-gate.sh:778` (canonical → helper)
- `.claude/hooks/cla-signed-author-gate.sh:109` (canonical → helper)
- `.claude/hooks/ship-unpushed-commits-gate.sh:166` (canonical → helper)
- `plugins/soleur/scripts/domain-model-drift.sh:321,322` (canonical + NEL → helper)

**Adopt — newline-only variant (`soleur_ctx_sanitize_nl`):**

- `plugins/soleur/scripts/resolve-regenerable-conflicts.sh:50` (DEL, no LS/PS)

**Adopt-equivalent (not a `tr` site, same boundary):**

- `.claude/hooks/session-rules-loader.sh:371-373` — jq `gsub("[[:cntrl:]]";"")`
  on MCP server-name keys: append `| gsub("\\u2028|\\u2029";"")` (jq decodes
  `\u` escapes inside program string literals) so committed-config JSON keys
  cannot smuggle a line break into the roster.

**Already canonical — no code change, recorded:**

- `plugins/soleur/skills/preflight/SKILL.md:470,937,1266` and
  `plugins/soleur/skills/preflight/references/check-13-founder-check.md:81`
  (prescriptive doc snippets carrying the exact canonical form)

**Superset — leave as-is:**

- `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh:76` `clean_text()` —
  strips strictly more (`[:cntrl:]` + C1 range + wider `\xe2` classes + BOM).

**Out of scope — different contract or trusted input:**

- `.claude/hooks/pre-closing-technical-fork-gate.sh:94` — normalization for
  cue matching (transforms to spaces; output never reaches context), not a
  boundary sanitize.
- `scripts/lib/strip-log-injection.sh` + consumers — log/`$GITHUB_OUTPUT`
  injection domain with a deliberately different byte set (Cut List).
- `memory-backstop-resolve.sh` `resolver_emit` fallback + `memory-backstop.sh`
  `rfrom_sanitized` — bash `//[[:cntrl:]]` on resolver-owned literal text and a
  resolver-set path; not a `tr` strip, weakest-realistic threat, and any edit
  costs the byte-equal-copy + `BACKSTOP_REVISION` bump machinery.
  Disposition recorded, not adopted (decision-challenges row).
- `pre-closing-technical-fork-gate` U+2028 is unmatched in NORM — noted for
  completeness; NORM is match-input, not context output.

## Technical Considerations

- **Topology constraint (load-bearing):** the plugin ships only
  `plugins/soleur/**` via `git-subdir`. A plugin-side script can never reach
  `scripts/lib/` or `.claude/` on a customer machine — hence the dual-home
  lib copies. Repo-side `.claude/hooks/` consumers source their adjacent
  `lib/` copy; plugin consumers source `plugins/soleur/scripts/lib/` via
  per-depth `../` arithmetic (community scripts need `../../../scripts/lib/`,
  per the helper-extraction learning — trace each consumer's depth at
  implementation).
- **The lib file itself:** `# shellcheck shell=bash`, no `set`, functions
  return via pipes only, `BASH_SOURCE` direct-exec guard mirroring
  `strip.sh`.
- **`tr` portability:** `\NNN` octal only; `\177` for DEL. `LC_ALL=C` on both
  `tr` and `sed` (byte semantics; the canonical sites already do this).
- **Byte-sequence correctness:** `e2 80 a8`/`e2 80 a9`/`c2 85` are unambiguous
  UTF-8 sequences — `e2`/`c2` are lead-only bytes, `80`/`a8`/`a9`/`85` are
  continuation-only — so a byte-level `sed` cannot corrupt valid UTF-8.
- **Predicate reuse:** the new hook carries the fourth inline copy of the
  three-term predicate; `git-repo-readiness-diag.test.sh` D5's parity loop is
  extended to a 3-way verdict (repo guard + diag + plugin arm) over the same
  8 fixture classes.
- **Envelope trust:** `.cwd` is harness-provided but flows into context —
  sanitize before emit (the hook's own adopt-site). The dedup grep reads repo
  files the hook does not control — bounded (`grep -l`), read-only.
- **Attack surface enumeration (security-fix template):** every path
  attacker-influenceable bytes reach agent context/operator display —
  (a) envelope `.cwd` → `safe_root`/`WS_WORKTREE`/plugin emit; (b) helper
  stdout → `BARE_CWD_BLOCK` prefix-filter + strip; (c) committed-config MCP
  keys → jq gsub; (d) cron-written tmpfs alarm → strip; (e) `git log` output
  (commit subjects are arbitrary bytes) → the three keep-lines gate sites +
  `cla-signed-author-gate`; (f) `tool_input.description` →
  `monitor-arm-recorder` ledger; (g) captured stderr →
  `pre-merge-rebase` `REGEN_WHY`; (h) PR/branch fields in staged-approval +
  ship-gate displays. All enumerated sites are covered by the census; the
  residual un-checked class is *new* sites added later — that is what
  Guard 1's drift sentinel covers.
- **NFR:** `knowledge-base/engineering/architecture/nfr-register.md` — the
  touchpoints are session-start latency (hook stays time-boxed ≤10 s at the
  registration; predicate is three local git calls) and fail-open posture
  (every new path exits 0 / emits nothing on failure).

## User-Brand Impact

- **If this lands broken, the user experiences:** a session-start advisory
  block that either mislabels a healthy bare customer repo as misanchored
  (wrong redirect text in context) or still renders a spoofed line inside a
  `[bare-root-cwd]` block — advisory text only, no refused operation.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  session cwd path and MCP server names, both already inside the same
  on-machine session context — no data leaves the host.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** every emit is an advisory context
  line on the same machine; the worst landing is a wrong advisory, not a
  refused write, a leak, or a production mutation — no `single-user incident`
  vector is reachable.
- `threshold: none, reason: machinery hooks/libs under .claude/, plugins/,
  scripts/ — no sensitive-path-regex match (no apps/ surface, infra, doppler,
  or credential workflow touched)`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_BARE_ROOT_CWD marker in SessionStart additionalContext (source=plugin-session-start discriminates the new arm); already registered MIRRORED-NOT-PAGED in MARKER_RE (apps/web-platform/server/git-lock-marker-telemetry.ts:170)"
  cadence: "per SessionStart at a row-3 bare root"
  alert_target: "none — advisory marker read in-session; mirrored not paged"
  configured_in: "plugins/soleur/hooks/hooks.json SessionStart '' entry + .claude/hooks/session-rules-loader.sh child call"
error_reporting:
  destination: "no external sink — hooks exit 0 on every path; a broken arm degrades to no-marker, which is indistinguishable from a non-bare session by design (the probe below is the canary)"
  fail_loud: "bash scripts/bare-root-cwd-guard-probe.sh prints all three lines on a healthy host; a missing line is the operator-visible failure"
failure_modes:
  - mode: "plugin arm fires on a genuinely-bare customer repo (false-positive redirect)"
    detection: "'truebare' fixture class in bare-root-cwd-plugin-guard.test.sh asserts silence; a live misfire surfaces as source=plugin-session-start telemetry on a repo without the overlay shape"
    alert_route: "test suite red (design-time); MIRRORED-NOT-PAGED (runtime)"
  - mode: "context-sanitize lib unreadable at a strip site → site silently reverts to its pre-fix strip set (DEL/LS/PS pass again)"
    detection: "context-sanitize.test.sh asserts the lib resolves from every adopt site's source path; the drift sentinel greps for raw tr -d strips outside the lib + disposition list"
    alert_route: "test suite red"
  - mode: "ensure-kb-index regen wrongly skipped on a real worktree"
    detection: "ensure-kb-index.test.sh worktree row asserts regen still runs when is-inside-work-tree is true"
    alert_route: "test suite red"
logs:
  where: "stdout JSON envelope additionalContext; .claude/.session-manifests/<id>.json"
  retention: "gitignored, local to the checkout"
discoverability_test:
  command: "bash scripts/bare-root-cwd-guard-probe.sh"
  expected_output: "sanitizer-ok"
```

(`scripts/bare-root-cwd-guard-probe.sh` is extended in this PR to also pipe a
fixture envelope through the plugin hook and a DEL+NEL+LS/PS fixture through
the lib, printing `SOLEUR_BARE_ROOT_CWD source=plugin-session-start` then
`sanitizer-ok` as the last line; `expected_output` matches only if every arm
ran to completion.)

## Guard Contract

### Guard 1 — context-strip drift sentinel

**Property.** No `tr -d '\000-…` (or `[:cntrl:]`) strip feeding a
context/display boundary exists outside the two `context-sanitize.sh` copies
and the recorded disposition list — a new raw strip site must fail CI, not
silently reintroduce the DEL/LS/PS gap.

**Assembly.** `grep -rnE "tr -d ('\\\\0|'\[)" .claude/hooks/ plugins/soleur/`
filtered to production (non-`.test.sh`) files, chokepointed through the
sentinel check inside `context-sanitize.test.sh`; the disposition list is a
literal set in the same test (each entry names file + disposition).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `bare-root-cwd-guard.sh:53` to raw `tr -d '\000-\037'` | RED — sentinel flags an unlisted strip |
| 2 | Delete the sentinel's own enumeration (grep returns 0 hits) | RED — floor: the lib's own function defs must match the pattern, so 0 total hits is vacuous |
| 3 | Add a second raw strip at a new file after a compliant first site | RED — new file not in disposition list |
| 4 | Edit the test harness so `grep` matches nothing (e.g. pattern typo to `\\\\000-` no-match) | RED — floor assertion on ≥1 hit from the lib defs |
| 5 | Rename `hold-gate-eval.sh` `clean_text()` off the disposition list | RED — listed path must exist on disk |

### Guard 2 — lib copy parity

**Property.** The two `context-sanitize.sh` copies are byte-identical — a
fix applied to one tree can never silently diverge the contract the other
tree's sessions run under.

**Assembly.** The two committed paths; chokepoint: `cmp` in
`context-sanitize.test.sh` (the `backstop-parity.test.ts` precedent).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append a comment to one copy only | RED — `cmp` differs |
| 2 | Weaken one copy's `tr` set (drop `\177`) | RED — `cmp` + byte-contract fixture |
| 3 | Delete the parity check from the suite | RED — harness row: suite asserts the check ran (count of `cmp` invocations ≥1) |
| 4 | Both copies present but one is a symlink | RED — `cmp -s` still true but the test asserts `-f` regular file on both |

### Guard 3 — predicate verdict parity (extension)

**Property.** The plugin arm's inline predicate agrees with the repo guard
and the readiness diag on every repository shape — a copy that drifts (e.g.
drops the gitdir-identity term) must redden the shared fixture battery.

**Assembly.** `git-repo-readiness-diag.test.sh` D5 parity loop extended from
2-way to 3-way over the existing 8 fixture classes; chokepoint: the loop
itself — every member runs every shape.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plugin arm drops the `--absolute-git-dir` identity term | RED — `imposter` fixture fires in plugin arm only |
| 2 | Plugin arm reads `core.bare` from effective config (`git config --get`) instead of `--file` | RED — `wtmask` fixture fires in plugin arm only |
| 3 | Parity loop skips the plugin arm (2-way again) | RED — harness row: assertion counts 3 verdicts per shape, and an injected divergence on shape `bare` must be caught |
| 4 | Plugin hook silently exits 127 (missing shebang/`set -e` path) on every shape | RED — `bare` fixture must fire; silent-127 reads as no-fire |

### Guard 4 — registration parity (existing mechanism, new row)

**Property.** Every `hooks.json` registration has a disposition row —
mechanical, already enforced by `devin-matcher-parity.test.sh`.

**Assembly.** `plugins/soleur/hooks/hooks.json` SessionStart entries ×
`devin-dispositions.tsv` `soleur-plugin` rows.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add the hooks.json entry, no TSV row | RED — T1 missing-row report |
| 2 | TSV row with wrong matcher column (`startup` vs `""`) | RED — byte-exact `grep -F` match fails |
| 3 | Remove the enum's plugin scan | RED — harness row: existing T1 structure; a missing plugin.tsv input file is a CANONFAIL |

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`:
the §Rejected/deferred bullet that reads "Plugin-level `hooks.json` `""`-matcher
arm for cross-repo bare roots: deferred to #10392" is updated to record the
shipped arm (script path, `source=plugin-session-start` marker discriminant,
dedup rule, topology-generic redirect). The line-39 capabilities bullet gains
the plugin arm as a third emitter under the same predicate. In-scope task in
Phase E — not a follow-up issue.

### C4 views

Read of all three model files (`model.c4` 998 lines, `views.c4` 131,
`spec.c4` 54) against the actor/system/relationship rubric:

- **External actors:** none new — the hook fires inside an existing session
  on the same machine; no human actor sends or receives data.
- **External systems/vendors:** none new — no network edge; `git`, `jq`,
  `sed`, `tr` are local binaries.
- **Containers/data stores:** no new element — `plugins/soleur/hooks/` is
  inside the already-modeled `platform.plugin` / `platform.engine.hooks`
  surface.
- **Access relationships:** unchanged — SessionStart context injection is an
  existing modeled channel.

**One falsified description must be fixed in the same PR:** `model.c4`'s
`agentRunner` component description enumerates plugin SessionStart hooks and
carries a `// DRIFT (2026-10-18 audit)` note asserting a count of SIX and
naming the override surface (`SOLEUR_DISABLE_*` web overrides). This PR adds a
seventh (`bare-root-cwd-guard.sh`). The description + drift note are updated
to name it, state it needs no web override (self-scopes: silent on every
non-bare workspace, which includes the non-bare Concierge clones), and record
that it is jq-gated like its siblings. `model.likec4.json` regeneration is
folded in per the drift note's own stated remedy; the C4 validation tests
(`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`) run
after the edit.

### Sequencing

No soak-gated slice; the ADR amendment lands with the code.

## Files to Create

- `plugins/soleur/hooks/bare-root-cwd-guard.sh` — plugin SessionStart arm
  (envelope → predicate → dedup → emit).
- `.claude/hooks/lib/context-sanitize.sh` — shared sanitizer (repo copy).
- `plugins/soleur/scripts/lib/context-sanitize.sh` — shared sanitizer
  (plugin copy, byte-equal).
- `.claude/hooks/lib/context-sanitize.test.sh` — byte-contract fixtures +
  copy parity + drift sentinel (Guards 1–2).
- `plugins/soleur/test/bare-root-cwd-plugin-guard.test.sh` — 8 fixture
  classes + dedup + envelope shapes + emit contract for the plugin arm.

## Files to Edit

- `plugins/soleur/hooks/hooks.json` — new SessionStart `""` entry (+timeout).
- `.claude/hooks/devin-dispositions.tsv` — new `soleur-plugin` row.
- `.claude/hooks/session-rules-loader.sh` — 3 strip sites → lib; jq gsub
  LS/PS addition.
- `.claude/hooks/session-rules-loader.test.sh` — fixture bytes asserting
  DEL/U+2028/U+2029 stripped in BARE_CWD_BLOCK + worktree line.
- `.claude/hooks/bare-root-cwd-guard.sh` — strip site → lib.
- `.claude/hooks/bare-root-cwd-guard.test.sh` — separator-laden path fixture.
- `.claude/hooks/agent-token-tee.sh` — `sanitize_field` → lib.
- `.claude/hooks/pre-merge-rebase.sh` — `REGEN_WHY` strip → lib.
- `.claude/hooks/ship-kb-archive-gate.sh` — ROWS strip → lib (lines variant).
- `.claude/hooks/prod-write-defer-gate.sh` — 3 sites → lib.
- `.claude/hooks/cla-signed-author-gate.sh` — OFFENDERS strip → lib.
- `.claude/hooks/ship-unpushed-commits-gate.sh` — COMMIT_LIST strip → lib.
- `.claude/hooks/monitor-arm-recorder.sh` — DESC strip → lib (upgrade).
- `plugins/soleur/hooks/operator-stage-approval.sh` — `clean()` → lib.
- `plugins/soleur/scripts/run-in-pid-namespace.sh` — first-line strip → lib.
- `plugins/soleur/scripts/domain-model-drift.sh` — `esc_anchor`/`esc_stmt` → lib.
- `plugins/soleur/scripts/resolve-regenerable-conflicts.sh` — `_clean()` +
  line-168 strip → lib (nl + strip-all variants).
- `plugins/soleur/skills/ship/scripts/battery-owed.sh` — `_sanitize()` → lib.
- `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh` — 2 strips → lib.
- `scripts/ensure-kb-index.sh` — non-worktree guard (audit fix).
- `scripts/ensure-kb-index.test.sh` — bare-root + non-worktree rows.
- `plugins/soleur/hooks/devin-session-start.sh` — empty `_sentinel_root` guard.
- `plugins/soleur/test/git-repo-readiness-diag.test.sh` — D5 parity 2→3-way.
- `scripts/bare-root-cwd-guard-probe.sh` — extend: plugin-arm emit + sanitizer
  fixture, `sanitizer-ok` last line.
- `.claude/hooks/README.md` — plugin arm section + audit dispositions +
  sanitizer lib note.
- `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`
  — deferred→shipped amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ regenerate
  `model.likec4.json`) — SessionStart hook count/drift note.

## Implementation Phases

### Phase 0 — Tests first (`cq-write-failing-tests-before`)

Write `context-sanitize.test.sh` (RED: lib absent), the plugin-arm test
fixtures (RED: hook absent), the ensure-kb-index non-worktree row (RED:
guard absent), and the loader/guard separator fixtures (RED: DEL/LS/PS pass
today). Commit the RED state.

### Phase 1 — Shared lib + probe

Create both `context-sanitize.sh` copies + `context-sanitize.test.sh` GREEN +
extend `scripts/bare-root-cwd-guard-probe.sh`.

### Phase 2 — Adoption sweep

`.claude/hooks/` sites first (loader last among them, since its test asserts
envelope shape positionally), then `plugins/soleur/` sites. Each site: source
block + call-site swap + `declare -F` fallback carrying the pre-change strip.
Run each touched file's existing suite as it lands.

### Phase 3 — Plugin arm

Script + hooks.json entry + TSV row + new test + parity extension. Then
`devin-matcher-parity.test.sh` and `repo-hook-launchers.test.ts` (registered
command strings) must pass.

### Phase 4 — Audit fixes

ensure-kb-index guard + test row; devin-session-start empty-root guard.

### Phase 5 — Docs & model

README section + dispositions, ADR-099 amendment, model.c4 fix +
`model.likec4.json` regen + C4 tests.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "A plugin-level hooks.json \"\"-matcher SessionStart arm would cover bare-root-anchored sessions in OTHER repos on customer machines" [#10392] | Workstream B: `plugins/soleur/hooks/bare-root-cwd-guard.sh` + hooks.json entry + TSV row | mapped |
| 2 | "a genuinely bare customer repo (git server/mirror) must not get a misapplied redirect; the repo-layout predicate (ADR-099 row 3) already discriminates, but the redirect text must degrade gracefully off this repo's topology" [#10392] | Workstream B steps 3–5 (predicate reuse, generic `git worktree add` text, gated soleur-hint) + AC2/AC4 | mapped |
| 3 | "Audit .claude/hooks/supabase-loopback-warn.sh, memory-backstop-resolve.sh, and scripts/ensure-kb-index.sh for their own bare-root write behavior at session start" [#10392] | `## Bare-Root SessionStart Write Audit` + Workstream C fixes + README disposition table | mapped |
| 4 | "revisit after the repo-level gate ships and SOLEUR_BARE_ROOT_CWD telemetry shows whether non-repo-registered sessions still anchor" [#10392] | `source=plugin-session-start` marker discriminant (Workstream B step 5) | mapped |
| 5 | "A shared sanitizer helper that additionally strips \\x7f and the UTF-8 sequences e2 80 a8 / e2 80 a9, adopted at each strip site" [#10395] | Workstream A lib + census adoption + Guards 1–2 | mapped |
| 6 | ".claude/hooks/bare-root-cwd-guard.sh (safe_root strip)" [#10395] | Files-to-Edit entry | mapped |
| 7 | ".claude/hooks/session-rules-loader.sh (WS_WORKTREE, TMPFS alarm, BARE_CWD_BLOCK strips)" [#10395] | Files-to-Edit entry (3 sites) | mapped |
| 8 | "Any sibling tr -d '\\000-\\037' strips across .claude/hooks/ and plugins/soleur/" [#10395] | `## Strip-Site Census & Dispositions` — every site classified | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| `plugins/soleur/hooks/bare-root-cwd-guard.sh` + hooks.json entry | asks 1–2 | asked |
| `context-sanitize.sh` ×2 + lib test | ask 5 | asked |
| Adoption edits at census sites | asks 5–8 | asked |
| Dedup check inside plugin hook | "must not get a misapplied redirect" (ask 2) — a double-block on this repo's own sessions is a misapplied emission of the same class | inferred — justification: without it the arm double-injects on every soleur-repo bare-root session |
| `devin-dispositions.tsv` row | — | inferred — justification: `devin-matcher-parity.test.sh` T1 enforcement; registration without the row fails CI |
| `ensure-kb-index.sh` non-worktree guard | ask 3 (audit → fix) | asked |
| `devin-session-start.sh` empty-root guard | ask 3 (audit → fix) | asked |
| Probe extension (`bare-root-cwd-guard-probe.sh`) | — | inferred — justification: `## Observability` discoverability_test must execute a committed script (Check 10) |
| jq gsub LS/PS addition (loader:371-373) | "sibling tr -d strips" spirit — same context boundary, same byte class | inferred — justification: leaving LS/PS open on the adjacent boundary would fix the class in name only |
| README / ADR-099 / model.c4 edits | — | inferred — justification: ADR-099 records the deferral this ships; model.c4's hook census falsifies without the count fix; README is the durable audit home |
| `plugins/soleur/test/git-repo-readiness-diag.test.sh` parity extension | — | inferred — justification: the repo's predicate-drift mechanism is this parity loop; a 4th copy without it breaks the convention |

### Split Assessment

- Subsystems touched: 4 — `.claude`, `plugins`, `scripts`, `knowledge-base`
- Planned files: 32 (27 edits + 5 creates) | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR — thresholds crossed on counts, declined on
  shape**: the diff is ~80% mechanical one-line strip swaps behind one lib
  definition, the two issues were bundled into one one-shot branch by the
  operator, and splitting at the lib boundary would ship a plugin hook that
  sanitizes with the old byte set in the interim PR.

## Acceptance Criteria

- [ ] **AC1** `jq '.hooks.SessionStart[] | select(.matcher=="")' plugins/soleur/hooks/hooks.json` contains an entry whose command resolves to `plugins/soleur/hooks/bare-root-cwd-guard.sh` with a `timeout`; `grep -F "soleur-plugin	plugins/soleur/hooks/bare-root-cwd-guard.sh	SessionStart" .claude/hooks/devin-dispositions.tsv` hits.
- [ ] **AC2** On the 8 fixture classes, the plugin hook fires ONLY on `bare` (emits `SOLEUR_BARE_ROOT_CWD source=plugin-session-start` + `^[bare-root-cwd] ` lines) and is silent on plain/masked/wtmask/sym/truebare/imposter/nonrepo — asserted in `plugins/soleur/test/bare-root-cwd-plugin-guard.test.sh`.
- [ ] **AC3** On a fixture carrying `.claude/hooks/*SOLEUR_BARE_ROOT_CWD*` + a settings/devin registration for `session-rules-loader.sh`, the plugin hook emits nothing (dedup).
- [ ] **AC4** The emitted block contains `git worktree add` and contains NO `plugins/soleur/` path on a generic fixture; the soleur-hint line appears only when `${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh` exists.
- [ ] **AC5** `cmp .claude/hooks/lib/context-sanitize.sh plugins/soleur/scripts/lib/context-sanitize.sh` exits 0; `context-sanitize.test.sh` fixtures prove DEL, NEL, U+2028, U+2029, and ESC are stripped in all three variants while `\t`/`\n` survive only in the documented variants.
- [ ] **AC6** The drift sentinel runs clean: every production `tr -d '\000-…`/`[:cntrl:]` site outside the lib is either adopted or on the recorded disposition list in `context-sanitize.test.sh`.
- [ ] **AC7** `session-rules-loader.test.sh` asserts a BARE_CWD_BLOCK built from separator-laden fixture output contains no DEL/U+2028/U+2029 byte.
- [ ] **AC8** `ensure-kb-index.sh --soft` writes no file under a row-3 bare-root fixture's `knowledge-base/` and still regenerates in a normal worktree fixture (`ensure-kb-index.test.sh` new rows).
- [ ] **AC9** `devin-session-start.sh` with `DEVIN_*` set and an unresolvable toplevel writes nothing outside the sandbox (no `/.devin`) and still emits its envelope.
- [ ] **AC10** Green: `bare-root-cwd-guard.test.sh`, `session-rules-loader.test.sh`, `devin-matcher-parity.test.sh`, `git-repo-readiness-diag.test.sh` (3-way), `ensure-kb-index.test.sh`, `context-sanitize.test.sh`, `bare-root-cwd-plugin-guard.test.sh`, `backstop-parity.test.ts`, `repo-hook-launchers.test.ts`, plus each edited file's own suite (`ship-kb-archive-gate.test.sh`, `pre-merge-rebase.test.sh`, `prod-write-defer-gate.test.sh`, `ship-unpushed-commits-gate.test.sh`, `cla-signed-author-gate` suite, `agent-token-tee.test.sh`, `memory-backstop-resolve.test.sh` untouched, `devin-cloud-mode.test.ts`, `devin-plugin.test.ts`).
- [ ] **AC11** `.claude/hooks/README.md` documents the plugin arm, the audit dispositions, and the shared sanitizer; ADR-099's deferred-bullet records the shipped arm; `model.c4`'s SessionStart census names seven hooks and the C4 tests pass.
- [ ] **AC12** PR body carries `Closes #10392` and `Closes #10395`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (sequential-fallback — no Task spawn surface; inline
assessment recorded, `Reviewed-Coverage: sequential-fallback`)
**Assessment:** machinery/tooling change inside Soleur's own hook substrate.
Architectural surface already governed by ADR-099/ADR-173; this plan executes
an ADR-recorded deferral rather than making a new architectural commitment.
Risk concentrated in (a) predicate fidelity on customer topologies — mitigated
by 3-way fixture parity; (b) dual-home lib drift — mitigated by byte-equal
parity guard; (c) hook reliability on customer machines — never-blocks
contract (exit 0 / emit nothing on every failure path), jq-gated emit.

**Brainstorm-recommended specialists:** none (no brainstorm ran).

No Product/UX, Legal, Marketing, Sales, Finance, Support, or Operations
surface: no `.tsx`/`app/**` files → mechanical UI-surface override does not
fire; no regulated-data surface → GDPR evaluated inline per Phase 2.7(d):
the plugin hook reads the envelope `cwd` (a local path that may embed a
username) and re-emits it sanitized into the same on-machine session context —
no new processing activity, no cross-controller movement, no Art. 9 data, no
external transmission. No compliance-posture write warranted.

## Test Scenarios

- Given a row-3 bare-overlay fixture and an envelope `{"cwd":"<root>"}`, when the plugin hook runs, then stdout parses as a SessionStart envelope whose additionalContext contains `SOLEUR_BARE_ROOT_CWD source=plugin-session-start` and only `[bare-root-cwd]`-prefixed lines. `integration`
- Given fixtures for plain clone, masked config, worktreeConfig mask, symlinked `.git`, `git init --bare`, imposter `.git` subdir, and non-repo dir, when the hook runs, then it prints nothing and exits 0. `integration`
- Given a soleur-shaped fixture carrying `.claude/hooks/*SOLEUR_BARE_ROOT_CWD*` plus a settings registration, when the hook runs, then it prints nothing (dedup). `integration`
- Given a root path containing `\x7f`, `\xe2\x80\xa8`, `\xe2\x80\xa9`, `\xc2\x85`, and `\x1b`, when each sanitizer variant runs, then none of those bytes survive and `\n`+`\t` survive only in the `lines` variant, `\n` only in `nl`. `unit`
- Given `GIT_DIR` pointed at a plain clone while cwd is a bare root, when the hook runs, then it still fires (env scrub). `integration`
- Given no `jq` on PATH, when the hook runs, then exit 0 with no output. `unit`
- Given a bare-root fixture with `knowledge-base/` present, when `ensure-kb-index.sh --soft` runs, then no INDEX/tags/categories/stamp file is created; in a worktree fixture the same call regenerates. `integration`
- Given `DEVIN_PROJECT_DIR` set and an empty `--show-toplevel`, when `devin-session-start.sh` runs, then no `/.devin` write occurs and the envelope still emits. `unit`
- Mutation battery (Guards 1–4): each matrix row produces the stated RED. `integration`

## Success Metrics

- Zero `tr -d '\000-…` context-boundary strips outside the lib + disposition
  list (sentinel count = lib sites only).
- `SOLEUR_BARE_ROOT_CWD source=plugin-session-start` observable on a
  non-soleur row-3 fixture; zero fires on `truebare`/`plain` fixtures.
- All named suites green; no regression in `session-rules-loader` envelope
  positional contract (lines 1-5 unchanged).

## Dependencies & Risks

- **Risk:** the plugin hook fires in hosted Concierge web sessions
  (hooks.json command hooks execute there per the model.c4 description) —
  **mitigation:** predicate self-scopes; Concierge workspaces are non-bare
  clones → silent. No `SOLEUR_DISABLE_*` override needed (recorded in the
  C4 fix).
- **Risk:** a customer repo that vendored soleur's `.claude/hooks/` without
  wiring them → dedup suppresses the plugin arm while no repo arm fires —
  **mitigation:** dedup requires BOTH the marker file AND a registry
  reference to `session-rules-loader.sh`; a vendored-but-unwired copy fails
  the second term and the plugin arm still fires.
- **Risk:** `declare -F` fallbacks drift from the lib — **mitigation:** each
  fallback carries the site's *pre-change* strip (documented safe direction),
  and the sentinel enumerates the lib's own defs, keeping the floor honest.
- **Risk:** byte-equal copies edited in one tree only — **mitigation:**
  Guard 2 `cmp` + regular-file assertion.
- **Dependency:** `jq` for envelope parse+emit (existing loader requirement);
  `git` for the predicate; `timeout` optional (registration `timeout: 10` is
  the harness bound).
- **Open code-review overlap dispositions:** #7208 (memory-backstop
  hardening — acknowledge: this plan deliberately does not edit the
  byte-equal backstop copies); #7218 (cla-signed-author-gate unsigned-identity
  coverage — acknowledge: orthogonal to the strip adoption at line 109);
  #8659 (test-helpers EXIT-trap class incl. battery-owed — acknowledge:
  unrelated to its `_sanitize` site).

## Open Code-Review Overlap

3 open scope-outs touch these files: #7208 (memory-backstop hardening),
#7218 (cla-signed-author-gate coverage), #8659 (EXIT-trap incident-sandbox
class). Fold in / acknowledge / defer: **acknowledge all three** — each is a
different concern than the sanitizer/adoption surface this plan edits (see
Dependencies & Risks for per-issue rationale). None double-counts a filing:
no new scope-out is authored for these concerns here.

## Non-Goals

- PreToolUse hard-deny at bare roots — #3206's scope (refuses rather than
  advises).
- Migrating the three existing inline predicate copies to a shared lib —
  Cut List; the parity convention covers drift.
- Refactoring `strip-log-injection.sh` or `hold-gate-eval.sh` `clean_text()` —
  different byte contracts.
- Widening detection to bare-root *subdirectories* — deliberate narrowing
  retained (go.md Step-1 is the documented backstop).
- Overlay/scratch cleanup at the bare root — #10391 (operator-gated).

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| One physical lib under `plugins/soleur/` sourced by `.claude/hooks/` too | Creates a repo→plugin runtime dependency direction that inverts the layering the dual-home convention exists to avoid; a byte-equal pair costs one `cmp` line |
| Extend `strip-log-injection.sh` with variants | Wrong byte contract domain (log injection keeps `\t`, drops most of C0); conflating two threat surfaces reopens #3561's drift class |
| Plugin hook emits `systemMessage` instead of `additionalContext` | The marker's channel is agent context; `systemMessage` is operator-visible only and would not reach the model (contract per SessionStart learning) |
| Auto-create a worktree on detection | Rejected in the #10383 ruling and unchanged: a hook cannot `cd` the session and mints branches unasked |
| `--is-bare-repository` instead of the config-FILE predicate | ADR-173: reports `true` on a masked-config normal clone (false-positive redirect) — the exact harm #10392 forbids |

## References & Research

- Predicate: `.claude/hooks/bare-root-cwd-guard.sh:46-49`,
  `bare-head-self-heal.sh:44-49`,
  `plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh:72-74`
- Parity battery: `plugins/soleur/test/git-repo-readiness-diag.test.sh` (D5)
- Canonical sanitize form: `.claude/hooks/prod-write-defer-gate.sh:404`,
  `.claude/hooks/agent-token-tee.sh:97`, `plugins/soleur/scripts/domain-model-drift.sh:321`
- Registration ledger: `.claude/hooks/devin-dispositions.tsv`,
  `.claude/hooks/devin-matcher-parity.test.sh`
- Topology: ADR-099 rows 2–3 + deferred-arm bullet; ADR-173 (config-FILE reads)
- Envelope contract: learning `2026-03-04-sessionstart-hook-api-contract.md`
- `tr` octal: learning `2026-05-11-tr-does-not-interpret-hex-escapes.md`
- Dual-home convention: `plugins/soleur/test/backstop-parity.test.ts`
- Prior spec: `knowledge-base/project/specs/archive/20261015-174125-feat-bare-root-anchor-gate/decision-challenges.md`
- Telemetry registry: `apps/web-platform/server/git-lock-marker-telemetry.ts:170`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — filled above.
- Every added FR/AC names its implementation location; the two lib paths are
  stated verbatim so no "which copy is canonical" ambiguity reaches
  `soleur:work`.
- The `""` matcher in `devin-dispositions.tsv` is the two-character sentinel
  `""`, not empty — the TSV field contract collapses genuine empties.
- Do NOT widen `--is-bare-repository` anywhere new (ADR-173) and do NOT reach
  for `git rev-parse --show-toplevel` as a bareness test — it is a worktree
  test only.
- The loader's envelope positional contract (STAMP/manifest/session-context
  on lines 1-5) is asserted positionally by its suite — the sanitizer swap
  must not reorder lines.
- Sequential-fallback disclosure: every gate that names an agent spawn was
  executed inline; `Reviewed-Coverage: sequential-fallback` is recorded in
  Domain Review and the decision-challenges file.
