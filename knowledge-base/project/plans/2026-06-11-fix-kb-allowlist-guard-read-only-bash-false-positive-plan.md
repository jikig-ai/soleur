---
title: "fix: kb-domain-allowlist-guard false-positive on read-only Bash commands"
type: bug
date: 2026-06-11
branch: feat-one-shot-kb-allowlist-guard-read-only-guard
lane: procedural
brand_survival_threshold: none
---

# 🐛 fix: kb-domain-allowlist-guard fires advisory `ask` on read-only Bash commands

## Overview

The PreToolUse hook `.claude/hooks/kb-domain-allowlist-guard.sh` is an **advisory** guard
that surfaces a one-time `ask` when a write would introduce a NEW top-level entry under
`knowledge-base/` outside the sanctioned domain set. For **Bash** tool invocations it scans
the command string for a `knowledge-base/<segment>` substring (intended to catch writes like
`mkdir`/`cat >`/`mv`/`tee`).

The scan is a **first-match substring scan over the entire command string** and does not
distinguish a *read reference* from a *write target*. Read-only commands that merely mention
a knowledge-base path (`git show <ref>:knowledge-base/...`, `git ls-tree`, `grep`, `cat`)
trip the `ask`, forcing the operator to manually approve harmless reads.

**Root cause (diagnosed and reproduced — see Research Insights, not re-derived here):**
line 67's regex `knowledge-base/([^/[:space:]\"\']+)` matches `knowledge-base/.gitkeep`
inside `git show main:knowledge-base/.gitkeep` (git `<ref>:<path>` object-read syntax).
`SEGMENT` becomes `.gitkeep`: not in `SANCTIONED_DIRS`/`SANCTIONED_FILES`, no glob metachars
(so the lines 84-86 glob-guard misses it), and `git show` creates no real file (so the
on-disk check at line 110 misses it) → advisory `ask` fires on a pure read.

**Reproduced live** (this worktree, `2026-06-11`): the exact repro command and the standalone
`git show main:knowledge-base/.gitkeep` both return `permissionDecision: "ask"`. SEGMENT
resolves to `.gitkeep`. (Commands in Research Insights.)

## Fix summary

For the **Bash** tool only, fire the advisory `ask` ONLY when the matched
`knowledge-base/<segment>` is an actual **write target**, using a **positive write-verb gate**
(aligns with the hook's stated philosophy at lines 25-27: this gate guards *accidental
taxonomy drift*, not adversarial bypass; completeness against exotic write forms is explicitly
out of scope). Treat a Bash command as a kb write only if it contains EITHER:

1. a **write verb** (`mkdir`, `touch`, `tee`, `git add`, `git mv`, `git rm`, `sed -i`, `cp`,
   `mv`, `install`, `ln`, `rsync`) followed — within the same pipeline/command segment — by a
   `knowledge-base/` path, OR
2. a **redirect** `>` / `>>` whose target is a `knowledge-base/` path.

Read-only references (`git show <ref>:knowledge-base/...`, `git ls-tree`, `git cat-file`,
`git log`, `grep`, `gh ... view`, `cat`, etc.) carry no write verb and no kb-targeted
redirect, so they pass cleanly.

**File tools (Write/Edit/MultiEdit/NotebookEdit) are UNAFFECTED** — their `file_path` is
unambiguously a write target, so current behavior is preserved for them.

## User-Brand Impact

**If this lands broken, the user experiences:** if the gate is *over-tightened* (write-verb
gate too narrow), a genuine accidental new top-level domain write via Bash (`mkdir
knowledge-base/typo`) slips through silently, fragmenting the KB taxonomy — the exact drift
the guard exists to catch. If *under-tightened* (read-vs-write distinction incomplete), the
operator keeps hitting the false-positive `ask` and the bug is not fixed.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this hook is a local
PreToolUse advisory guard over the operator's own working tree. It reads no secrets, touches
no regulated data, and makes no network/DB/prod writes. It only emits an `ask`/pass decision.

**Brand-survival threshold:** none — local tooling ergonomics change with no user-facing
artifact and no data-exposure vector. `threshold: none, reason: PreToolUse advisory guard over
the operator's local working tree; reads no secrets, no regulated-data surface, no network or
prod write.`

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (`knowledge-base/project/specs/feat-one-shot-kb-allowlist-guard-read-only-guard/`
does not exist). The feature description's root-cause diagnosis was verified against the live
hook and matches the codebase exactly. No gap callouts.

| Claim (from task) | Codebase reality | Plan response |
|---|---|---|
| Line 67 regex first-match substring scan matches `.gitkeep` in `git show main:knowledge-base/.gitkeep` | Confirmed: `grep -oE 'knowledge-base/[^/[:space:]"'"'"']+'` on the read string yields `knowledge-base/.gitkeep`; SEGMENT=`.gitkeep` | Add Bash-only write-target gate before the advisory fires |
| Glob-guard (lines 84-86) does not catch `.gitkeep` (no metachars) | Confirmed by reading the guard | Cannot rely on glob-guard; need explicit write-verb gate |
| On-disk check (line 110) misses git-object reads | Confirmed: `git show` writes no real file; `.gitkeep` not on disk at kb root | Cannot rely on existence check; need explicit write-verb gate |
| `tool_name` should be extracted, fail-open if absent | `background-poll-prefer-monitor.sh:81` precedent: `jq -r '.tool_name // empty'`, then `[ "$tool_name" = "Bash" ] \|\| allow` | Mirror this idiom; fail-open when absent |
| Hook is registered for both file tools and Bash | Confirmed: `.claude/settings.json:225,234` — matchers `Write\|Edit\|MultiEdit\|NotebookEdit` and `Bash` | Scope the new gate to the Bash path only |

## Design

### Where the gate goes

The hook's flow (current): extract `TARGET` (file_path // notebook_path // command) → match
`knowledge-base/<segment>` → glob-guard → sanctioned-dir → sanctioned-file → on-disk → fire
`ask`. Every check between the regex match and the final `ask` (glob-guard, sanctioned-dir,
sanctioned-file, on-disk) is a **pass-through branch** (`exit 0`); the ONLY branch that ever
asks is the final one at line 119.

The write-target gate runs **only on the Bash class**, placed immediately **after the regex
match (line 70) and BEFORE the glob-guard (line 84)**. A Bash command that is NOT a write
target `exit 0`s here, skipping the four downstream pass-through checks entirely — which is
safe precisely because they are all pass-throughs (a Bash read never needed them). The gate
therefore adds a NEW pass-through condition for Bash reads and can NEVER convert a pass into an
`ask` nor remove the existing `ask` (a Bash *write* matches a write regex, does not early-exit,
and falls through to the existing logic unchanged). File-tool payloads skip the gate entirely
(IS_BASH is false) and reach the existing logic unchanged.

> **Inline-comment precision (Finding 2, code-reviewer):** the Phase 2 inline comment MUST say
> "Bash reads that pass this gate `exit 0` here; they do not need the downstream checks (all
> pass-throughs). Only Bash *writes* fall through to those checks." Do NOT phrase it as "runs
> after the glob-guard" — placement is BEFORE the glob-guard, and the glob-guard is simply not
> exercised for Bash reads.

### Detecting the Bash class (fail-open on missing `tool_name`)

`tool_name` is extracted via `jq -r '.tool_name // empty'`. The existing test harness payloads
omit `tool_name` (they send `{tool_input:{command:...}}` or `{tool_input:{file_path:...}}`),
so the discriminator must also fall back to the `tool_input` shape:

- **Treat as Bash** when `tool_name == "Bash"` **OR** (`tool_name` is empty AND
  `.tool_input.command` is present AND `.tool_input.file_path` is absent).
- Otherwise (file_path / notebook_path present, or tool_name is a file tool) → **NOT Bash**;
  skip the write-target gate and preserve current behavior.

This is fail-open per the hook's philosophy: a missing/garbled `tool_name` on a real Bash
command still gets the read-vs-write gate (because `command` is present); a missing
`tool_name` on a file write still reaches the existing `ask` logic (because `file_path` is
present). Verified against existing payload shapes (see Research Insights).

### Write-target detection (the two regexes)

Both regexes MUST be assigned to a shell variable before use in `[[ "$cmd" =~ $RE ]]` — an
inline regex literal containing `;`/`&`/`|` triggers a bash conditional-expression parse error
(verified during prototyping). This mirrors the file's existing pattern of keeping complex
matches readable.

```bash
# (1) write VERB followed — within the same pipeline/command segment — by a kb path.
#     [^|;&]* bounds the match to one segment so a verb in pipeline-stage-1 does NOT
#     match a kb READ in pipeline-stage-2 (e.g. `git ls-tree ... | grep ... ; cat knowledge-base/x`).
KB_WRITE_VERB_RE='(mkdir|touch|tee|sed[[:space:]]+-i|cp|mv|install|ln|rsync|git[[:space:]]+add|git[[:space:]]+mv|git[[:space:]]+rm)[^|;&]*knowledge-base/'

# (2) redirect > or >> whose target is a kb path. Optional fd is NOT needed before > here
#     because we anchor on the > itself then allow optional spaces + optional quote, then
#     literal knowledge-base/. CRITICAL: this must NOT match `>/dev/null` — it doesn't,
#     because the literal `knowledge-base/` must follow the > (verified).
KB_WRITE_REDIR_RE='>>?[[:space:]]*"?'"'"'?knowledge-base/'

if [[ ! "$TARGET" =~ $KB_WRITE_VERB_RE ]] && [[ ! "$TARGET" =~ $KB_WRITE_REDIR_RE ]]; then
  exit 0   # Bash command references a kb path but is not a write target → pass-through.
fi
```

**Why a positive allowlist is correct here** (not exhaustive write-form coverage): lines 25-27
of the hook header already declare that adversarial evasion (`eval`, base64) is out of scope —
the gate exists for *accidental* taxonomy drift. The set above covers every write form a
human or agent realistically uses to create a new top-level kb dir/file. A novel exotic write
form (e.g. `python -c 'open(...).write(...)'`) slipping through is acceptable per the stated
philosophy and matches the parallel carve-out in `no-memory-write.sh` (which lists the same
verb family and explicitly scopes out adversarial evasion).

**Conservative edge:** `mv`/`cp` reading FROM a kb path (e.g. `mv knowledge-base/foo/a /tmp/b`)
matches the verb gate and will reach the downstream sanctioned/on-disk checks — which pass it
through when the segment is sanctioned or already on disk. Only a `mv`/`cp` whose kb arg is a
NEW unsanctioned segment would `ask`; this is rare and correct-enough for an accidental-drift
guard. Documented as a Sharp Edge, not fixed (out of scope per philosophy).

## Files to Edit

- `.claude/hooks/kb-domain-allowlist-guard.sh`
  - **Header comment (lines 22-27):** update the Coverage paragraph to state that the Bash
    path now gates on **write-target detection** (positive write-verb / kb-redirect allowlist),
    so read-only references that merely mention a kb path pass cleanly. Keep the
    "adversarial evasion out of scope" sentence.
  - **After SEGMENT extraction (after line 70), before the glob-guard (line 84):** add the
    Bash-class detection + write-target gate. Include an inline comment explaining the
    read-vs-write distinction, mirroring the style of the existing glob-guard comment
    (lines 72-83): explain *why* a Bash read reference is not a write target, *what* the two
    regexes catch, and the `[^|;&]*` segment-bounding rationale.
  - Extract `tool_name` from the hook input JSON near the existing `jq` extraction
    (mirror `background-poll-prefer-monitor.sh:81` `jq -r '.tool_name // empty'`), fail-open
    if absent.
  - Preserve `set -euo pipefail` and the fail-open philosophy throughout. No subprocess in the
    gate (pure `[[ =~ ]]`), consistent with the existing glob-guard.

- `.claude/hooks/kb-domain-allowlist-guard.test.sh`
  - Add the failing-first test cases enumerated in **Test Scenarios** below. Add a
    `invoke_bash_named()` helper that injects `tool_name: "Bash"` so at least one new case
    exercises the explicit-`tool_name` path (the existing `invoke_bash` omits it, exercising
    the fail-open-by-shape path). Keep all existing T1-T12 green (they must not regress).

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED: add failing tests first (cq-write-failing-tests-before)

Add the new cases to `kb-domain-allowlist-guard.test.sh`. Run the suite; the read-reference
PASS cases (T13, T14, T15) MUST fail against the current hook (they currently `ask`), proving
the bug is captured. The regression-guard ASK cases (T16-T18) and the sanctioned-write PASS
case (T19) and the file-tool ASK case (T20) should already pass (they assert current/unchanged
behavior) — confirm they do.

### Phase 2 — GREEN: implement the gate

Edit `kb-domain-allowlist-guard.sh`:
1. Extract `TOOL_NAME` via `jq -r '.tool_name // empty'` from `$INPUT` (alongside the existing
   `TARGET` extraction; reuse the same fail-open `2>/dev/null` style).
2. After `SEGMENT="${BASH_REMATCH[1]}"`, compute `IS_BASH` (tool_name == Bash, OR tool_name
   empty AND `.tool_input.command` present AND `.tool_input.file_path` absent).
3. If `IS_BASH` and neither write-target regex matches `$TARGET` → `exit 0`.
4. Update the header comment block (lines 22-27) and add the inline read-vs-write comment.

Re-run the suite; all cases (old + new) must pass.

### Phase 3 — Verify no regression in registration semantics

Confirm `.claude/settings.json` still routes file tools and Bash to the same hook (no change
needed there). Run `bash -n .claude/hooks/kb-domain-allowlist-guard.sh` and
`shellcheck .claude/hooks/kb-domain-allowlist-guard.sh` if available; run the full hook test:
`bash .claude/hooks/kb-domain-allowlist-guard.test.sh`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash .claude/hooks/kb-domain-allowlist-guard.test.sh` exits 0 with all cases passing
      (existing T1-T12 plus new T13-T20).
- [ ] The exact repro command (Research Insights) piped through the hook returns NO
      `permissionDecision` (pass-through), not `ask`.
- [ ] `git show main:knowledge-base/.gitkeep` (standalone) → pass-through.
- [ ] `grep -r knowledge-base/foo .` → pass-through.
- [ ] `mkdir knowledge-base/newdomain` (Bash) → still `ask`.
- [ ] `echo x > knowledge-base/newdomain/file.md` (Bash) → still `ask`.
- [ ] `git add knowledge-base/newdomain/file.md` (Bash) → still `ask`.
- [ ] `mkdir knowledge-base/engineering/x` (Bash, sanctioned domain) → pass-through.
- [ ] File-tool Write to `knowledge-base/newdomain/x.md` (`tool_name: "Write"` or file_path
      payload) → still `ask` (unaffected).
- [ ] `echo x >/dev/null 2>&1` style redirects in a read command do NOT cause `ask`
      (the redirect regex requires a literal `knowledge-base/` after `>`).
- [ ] `set -euo pipefail` preserved; the gate uses pure `[[ =~ ]]` (no new subprocess).
- [ ] Header comment block (lines 22-27) updated to describe Bash write-target gating; inline
      read-vs-write comment added in the glob-guard comment style.
- [ ] PR body uses `Closes #<issue>` only if a tracking issue exists; otherwise `Ref`.

## Test Scenarios

Helpers (extend the existing harness):
- `invoke_bash` — current: `{tool_input:{command:...}}`, no `tool_name` (fail-open-by-shape path).
- `invoke_bash_named` — NEW: `jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'`.
- `invoke_write` — current: `{tool_input:{file_path:...}}`.
- `invoke_write_named` — OPTIONAL: `{tool_name:"Write", tool_input:{file_path:...}}` for one
  explicit file-tool case.

| # | Input | Via | Expect |
|---|---|---|---|
| T13 | the exact repro command (multi-statement, contains `git show main:knowledge-base/.gitkeep >/dev/null 2>&1`) | `invoke_bash` | pass-through (no decision) |
| T14 | `git show main:knowledge-base/.gitkeep` | `invoke_bash` | pass-through |
| T15 | `grep -r knowledge-base/foo .` | `invoke_bash` | pass-through |
| T15b | the repro command via `invoke_bash_named` (explicit `tool_name:"Bash"`) | `invoke_bash_named` | pass-through (exercises tool_name path) |
| T16 | `mkdir knowledge-base/newdomain` | `invoke_bash` | `ask` (regression guard) |
| T17 | `echo x > knowledge-base/newdomain/file.md` | `invoke_bash` | `ask` (regression guard) |
| T18 | `git add knowledge-base/newdomain/file.md` | `invoke_bash` | `ask` (regression guard) |
| T19 | `mkdir knowledge-base/engineering/x` | `invoke_bash` | pass-through (sanctioned domain) |
| T20 | `knowledge-base/newdomain/x.md` | `invoke_write` (file tool) | `ask` (unaffected) |
| T20b | `knowledge-base/newdomain/x.md` via `invoke_write_named` (`tool_name:"Write"`) | `invoke_write_named` | `ask` (unaffected, explicit tool_name) |
| T21 | `echo "cp x > knowledge-base/y is the move cmd" > /tmp/notes.txt` | `invoke_bash` | `ask` — **documented-acceptable** false positive (quoted-string `> knowledge-base/`); locks Sharp-Edge Finding 1 so a future regex edit cannot silently "fix" it and regress T17 |
| T22 | `sed "s/a/b/" knowledge-base/engineering/x.md` (read-only `sed`, no `-i`) | `invoke_bash` | pass-through — verb regex requires `sed[[:space:]]+-i`, so a read-only `sed` over a sanctioned path is not a write; locks the `-i`-anchored verb boundary |
| T23 | `mv knowledge-base/project/foo.md /tmp/` (kb is SOURCE, sanctioned segment) | `invoke_bash` | pass-through — verb matches but SEGMENT=`project` is sanctioned, so the sanctioned-dir check passes it; locks the kb-as-source behavior against a future verb-regex narrowing |

(T8/T11/T12 already cover Bash-mkdir-ask, comment-glob-skip, and grep-regex-skip respectively;
T13-T15 add the read-reference-via-`git show`/`grep` cases the old logic mishandled.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — local developer-tooling (PreToolUse hook) change. No
Product/UX surface (no file under `components/**`, `app/**/page.tsx`, etc.). No engineering
infra, no finance/legal/marketing/ops/sales/support implications.

## Observability

Skipped (silent): this plan edits only `.claude/hooks/*.sh` (local PreToolUse guard) — it does
NOT touch `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and
introduces no new infrastructure surface. The hook's existing `emit_incident` telemetry (a
`warn` event on each fire) is unchanged. Per Phase 2.9 skip conditions, no `## Observability`
schema is required for a pure local-hook change.

## Infrastructure (IaC)

None — pure local-file code change against `.claude/hooks/`. No server, service, cron, vendor
account, DNS, secret, or runtime process introduced.

## Research Insights

**Live reproduction (this worktree, 2026-06-11):**

The exact repro command and the standalone read both returned `permissionDecision: "ask"`:
```bash
HOOK=.claude/hooks/kb-domain-allowlist-guard.sh
export CLAUDE_PROJECT_DIR="$(pwd)"
printf '%s' 'git show main:knowledge-base/.gitkeep' | jq -Rs '{tool_input:{command:.}}' | bash "$HOOK" \
  | jq -r '.hookSpecificOutput.permissionDecision'   # -> ask
echo "git show main:knowledge-base/.gitkeep" | grep -oE 'knowledge-base/[^/[:space:]"'"'"']+'  # -> knowledge-base/.gitkeep
```

**Detection regexes verified against all required cases** (writes matched, reads rejected
including `>/dev/null`, `>out.txt`, and pipeline-stage-2 kb reads). Both regexes MUST be
assigned to a variable before `[[ =~ ]]` — an inline literal with `;`/`&` causes a bash
conditional parse error (observed during prototyping).

**Precedent:** `background-poll-prefer-monitor.sh:81-82` extracts `tool_name` and gates on
Bash:
```bash
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool_name" = "Bash" ] || allow
```

**Sibling carve-out:** `no-memory-write.sh` (lines 14-19) lists the same write-verb family
(`tee`, `cat >`, `printf >>`, `cp`, `mv`, `sed -i`) and explicitly scopes out adversarial
evasion — this plan's positive allowlist mirrors that philosophy.

**Payload-shape discrimination (verified):** Bash payload → `tool_name:null, file_path:null,
command:true`; file-tool payload → `tool_name:null, file_path:set, command:false`. The
`IS_BASH = (tool_name==Bash) OR (tool_name empty AND command present AND file_path absent)`
discriminator keeps existing tests green and is fail-open.

**Hook registration:** `.claude/settings.json:225,234` — two matcher blocks route the same
hook: `Write|Edit|MultiEdit|NotebookEdit` and `Bash`. No settings change needed.

**Conventions (CLAUDE.md / AGENTS.md):** `cq-write-failing-tests-before` (RED first);
`hr-always-read-a-file-before-editing-it`; `cq-rule-ids-are-immutable` (no rule-id touched).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold
  `none` with a sensitive-path scope-out reason since the diff touches `.claude/hooks/` only,
  not a regulated-data surface.)
- The two write-target regexes MUST be assigned to shell variables before use in `[[ =~ ]]`;
  an inline literal containing `;`/`&`/`|` triggers a bash conditional-expression parse error
  (verified during prototyping). Tests must therefore include a multi-statement command (T13)
  to exercise the `[^|;&]*` segment boundary.
- The redirect regex (`>>?[[:space:]]*"?'?knowledge-base/`) deliberately requires the literal
  `knowledge-base/` immediately after the `>`/spaces/quote — a naive `>` presence check would
  re-introduce the false positive on `>/dev/null 2>&1` (present in the repro). Any future edit
  to this regex MUST re-run T13 + the `>/dev/null` AC.
- `mv`/`cp`/`rsync` reading FROM a kb path (kb is the *source*, not the dest) matches the verb
  gate and would `ask` only if the kb segment is NEW+unsanctioned. This is rare and acceptable
  for an accidental-drift guard; not fixed (exotic write/read-form completeness is out of scope
  per the hook header philosophy).
- **String-literal false positive (Finding 1, code-reviewer):** the redirect regex is not
  quote-aware. A command like `echo "cp x > knowledge-base/y is the move command" > /tmp/notes.txt`
  contains the substring `> knowledge-base/` *inside a quoted argument* and matches the redirect
  regex, yielding an advisory `ask` even though the real redirect target is `/tmp/notes.txt`.
  This is the SAME class as the `mv`/`cp`-source edge: low-probability, produces only an
  advisory `ask` (never a deny, never a block), and exotic-form completeness is explicitly out
  of scope per the hook header philosophy. **Documented as acceptable, NOT fixed** — a future
  edit MUST NOT "fix" this in a way that regresses the genuine `echo x > knowledge-base/...`
  write detection (T17). T21 (below) locks this behavior as a known-acceptable `ask`.
- The fail-open discriminator treats a Bash payload with a garbled/missing `tool_name` (but a
  present `command` field) as Bash. If a future harness change sends both `command` AND
  `file_path` in one payload, `file_path` takes precedence in `TARGET` extraction (line 52-57
  order) and the gate treats it as a file tool — acceptable, since file writes are
  unambiguous write targets.
