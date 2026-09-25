---
title: "fix(preflight): Check 10 decodes YAML quoted-scalar escapes in discoverability_test.command"
date: 2026-09-25
slug: fix-check10-yaml-quoted-command-escapes
branch: feat-one-shot-8102-check10-yaml-quote-escapes
issue: 8102
closes: [8102, 7548]
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# fix(preflight): Check 10 decodes YAML quoted-scalar escapes in `discoverability_test.command`

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Preflight Check 10 executes a plan's `discoverability_test.command`. #8149 taught the runtime to
strip a symmetric quote pair around an inline scalar, but the characters inside the pair are still
passed through raw: a double-quoted scalar's `\"` and `\\` escapes, and a single-quoted scalar's
`''` escape, reach `bash -c` undecoded, so the command that runs is not the command YAML says the
plan declared. The awk/TypeScript parity harness cannot see this class because it carries no
quoted-inline row in its byte-exact set. This plan closes both gaps for #8102 and its duplicate
#7548, and nothing else in Check 10.

## Research Insights

### Premise Validation

- **#8102** OPEN (p2-medium, bug). Its body describes the pre-#8149 state, where quotes were
  not stripped at all. Its 2026-09-25 scope-note comment narrows it to the two remaining gaps:
  undecoded escapes, and no quoted-inline fixture in the parity harness. That comment is the
  premise used here, and it holds.
- **#7548** OPEN. Duplicate of #8102 with one extra ask: *"extend the harness to compare the
  **post-normalization executed string**, not only the gate verdict; otherwise the next asymmetry
  ships the same way."* That ask is in scope, because this PR closes #7548.
- **PR #8149** MERGED 2026-09-14. Verified on `HEAD`: `plugins/soleur/skills/preflight/SKILL.md`
  Step 10.4 carries the `if [[ $CMD != *$'\n'* ]]; then case "$CMD" in \"*\") …` strip. It strips
  quotes and **decodes nothing**. The strip sits in the SKILL.md normalize block, **not** in
  `parse-form-a.awk`, so `parse-form-a.awk` still prints the quoted line verbatim.
- **Measured bug (not inferred).** I ran the real Step 10.4 chain, extracted from SKILL.md and
  executed with bash (the prototype for Phase 2's test), on
  `command: "printf '%s+' \"a b\" c"`. It yields `$CMD` = `printf '%s+' \"a b\" c`. Bash then runs
  `printf` with the arguments `"a`, `b"` and `c`. YAML means `printf '%s+' "a b" c`, which prints
  `a b+c+`.
- **The parity harness today.** P1 (`preflight-discoverability-test.test.ts`, "P1 awk and TS
  agree byte-exactly on every Form-A fixture") has **zero** quoted-inline rows. The one quoted
  row lives in **P2** ("P2 known divergence — inline quote stripping (TS strips, awk does not)"),
  and that row asserts the divergence. The only test covering the runtime strip is **F1d**, and
  F1d is positional (a regex over SKILL.md lines). No test executes it.

### Corpus measurement (plan time, `knowledge-base/**/*.md`)

The scratch scripts are `corpus.py`, `oracle.ts` and the bash loops; the numbers below are their
output:

| Quantity | Value |
|---|---|
| Inline `command:` scalars, double-quoted / single-quoted | 502 / 22 |
| Double-quoted scalars that contain any backslash escape | 77 (in 77 files) |
| Escape tally inside double-quoted scalars (left-to-right scan) | `\"` = 257, `\\` = 22, **every other escape = 0** |
| Single-quoted scalars that contain `''` | 3 |
| Commands whose executed string changes under the decode | 80 |
| Of those 80: bash-syntax-invalid before → after (`bash -n -c`) | 11 → 2 (**9 repaired, 0 newly broken**) |
| Step 10.5 shell-active reject verdict flips under the decode | **0** |
| Prototype decode agrees with `Bun.YAML.parse` (independent YAML oracle) | 517 of 520 parseable. The 3 misses are `"…"  # trailing comment` lines, which the symmetric-pair rule leaves untouched today and after this change. All 3 contain `&&` or `$VAR`, so the shell-active reject fires either way |
| Single-line quoted commands reaching the SKILL.md strip from Form B or block/fold (not inline) | **0 of 921** |

The last row is what makes it safe to delete the SKILL.md strip: the strip does work only for
inline scalars, and the parser now handles every one of those.

### Relevant files

- `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`: the inline rule
  `!mode && /^[[:space:]]*command:/ { sub(...); print; exit }`. The runtime of record.
- `plugins/soleur/skills/preflight/SKILL.md` Step 10.4: the FORM_A_AWK fenced block, then the
  "Normalize `$CMD` ONCE" fenced block, which holds the #8149 case-strip. Step 10.5 holds the
  shell-active reject `if [[ "$CMD" =~ (\$\(|\`|…|$'\n'|\$\{?[A-Za-z_]) ]]`.
- `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh`: `CMD_DEQ="${CMD//[\"\'\\]/}"`
  removes every `"`, `'` and `\` before it reads the verb.
- `plugins/soleur/test/lib/discoverability-test-parser.ts`: `parseCommand` inline path
  `return stripQuotes(inlineKey[1].trim())`. `stripQuotes` is shared with `parseExpected` and
  `parseCredentialsRequired`.
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: `FORM_A_FIXTURES` + `reg()` +
  `expectBoth()` + `runAwk()`, the P1/P2/P3 describe, F1c/F1d in the "#7393 F" describe, and the
  "#7453" describe. The #7453 describe **executes a slice of SKILL.md bash**, which is the
  precedent for the executed-string test below.
- `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`: `MIN_TESTS=132`,
  `MIN_ASSERTIONS=539` and `MIN_MANIFEST_LINES=126`. All three are ratcheted to the measured value
  with no slack. The manifest is `plugins/soleur/test/fixtures/check10-test-manifest.txt`: line 39
  is F1d and line 72 is the P2 quote row.
- The fixture dir `plugins/soleur/test/fixtures/preflight-check-10/` holds `01-…` to `10-…` today.
  The next free number is `11-`.
- The pinned runtime is `.bun-version` = `1.4.2`, and `Bun.YAML.parse` exists on it. I checked
  that it decodes `\"`, `\\` and `\n` in double-quoted scalars and `''` in single-quoted ones. No
  existing test uses `Bun.YAML` yet.
- Local awk is gawk 5.4.1. CI's `ubuntu-latest` `awk` is mawk. The suite asserts
  `/mawk|GNU Awk|gawk/`. The prototype uses only POSIX awk (`substr`, `length`, `[[:space:]]`).

### Institutional learnings applied

- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` and
  `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` (cited
  from plan Phase 2.12). Both are why the Guard Contract below carries harness rows and a
  must-PASS non-canonical row, and why expected values come from a YAML parser rather than from a
  hand-written table the same diff could edit.
- The SKILL.md comment at Step 10.4 names the failure class: "Gating one form while executing
  another is a laundering gap … the parity harness only compares the GATE". The executed-string
  test exists to close that class.
- `2026-05-07-edit-tool-old-string-mangles-u2028-u2029-escapes.md`. Escape-heavy fixtures go in a
  **file**, not in JS string literals. The expected values use `String.raw`, so no JS escaping
  layer sits between the fixture and the parser. Verify the bytes with `od -c`.
- `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`. Shell-level escape handling corrupts
  silently. That is why a real YAML parser (`Bun.YAML`) serves as the oracle, not a second
  hand-written decoder.

### Related issues (not in scope)

- #7403: a probe registry that would replace the command-parse surface entirely. Its
  re-evaluation trigger (b), "the parse surface produces a correctness bug", has fired with
  #8102 and #7548. AC10 records this on #7403 for re-triage. This fix does not pre-empt it: the
  decode it adds (one awk function and one TS mirror) is small to delete when the registry lands.
- #8448: `bun`/`node` probes exit 127 in the sandbox on mise hosts. For that reason this plan's
  own `discoverability_test` uses `grep`.
- #6795: `expected_output` as a YAML block scalar. That concerns the expected field, not the
  command.

### Property List (Phase 0.6b)

1. **P-EXEC.** For an inline double-quoted `command:` scalar, the string reaching `bash -c` equals
   the YAML value for the `\"` and `\\` escapes.
2. **P-SQ.** For an inline single-quoted scalar, the string reaching `bash -c` equals the YAML
   value (`''` becomes `'`).
3. **P-SCOPE.** No other input changes: unquoted scalars, mismatched pairs, block and fold
   scalars, Form B commands, `expected_output` and `credentials_required` keep their bytes.
4. **P-GATE.** The Step 10.4 verb-gate verdict and the Step 10.5 shell-active and ssh verdicts
   stay the same for every input. Only the executed string changes.
5. **P-PARITY.** The runtime's executed string and the TS mirror's executed string are compared
   by a test that **executes** the runtime chain, so the next asymmetry turns a test red.

### Cut List (Phase 0.6b)

- **"Also fix `stripQuotes` for `parseExpected` and `parseCredentialsRequired`"** → buys no
  property. Their runtimes (`EXPECTED=$(awk …)`, the `CREDS_REQ` case-strip) decode nothing, so
  decoding in the mirror alone would *open* a mirror/runtime asymmetry. The decode is scoped to
  the command path through a new sibling `decodeQuotedScalar()`. `stripQuotes` is untouched.
- **"Extract the Step 10.4 normalization into a new `scripts/normalize-cmd.sh`"** (the
  parse-form-a.awk / probe-verb-gate.sh precedent) → P-PARITY is already bought by executing the
  SKILL.md fenced blocks in place (the #7453 precedent), and a new file would need ADR-179
  plugin-root wiring. Cut.
- **"Decode the full YAML 1.2 escape set (`\n`, `\t`, `\xNN`, `\uNNNN`, …)"** → buys no property
  on the corpus (0 occurrences), and it would turn a shell-level `\n` into a real newline that
  trips the Step 10.5 newline reject. Cut. This is the documented negative control.
- **Cut at plan review** (see §Plan Review):
  - The executable verdict-invariance test (R), the `REJ` row, and the `probe-verb-gate.sh`
    spawn. P-GATE is proved in prose, and R re-proved an identity.
  - The separate YAML-oracle guard. It is merged into Q as the source of expected values.
  - The positional F1d rewrite. It is replaced by a no-reassignment scan that covers a window E
    cannot see.
  - The section-order assertion. It is replaced by the ID-set row.
  - Most of the hand mutation pass. Two observed mutations remain.

### Gates that do not fire

- **ADR/C4 (Phase 2.10):** skipped. The change moves a string transform one layer down (from the
  SKILL.md normalize block into the parser the TS mirror already models). No trust, dispatch or
  ownership boundary moves, and ADR-175's Layer 1/2/3 description stays true.
- **IaC, GDPR, Encryption Posture:** no store, no infrastructure, no regulated data.
- **Skill description budget:** no SKILL.md `description:` edit.

## Research Reconciliation — Spec vs. Codebase

| Claim in the ask | Reality on `HEAD` | Plan response |
|---|---|---|
| "The symmetric-quote strip already landed in PR #8149 (Step 10.4)" | True. It lives in the SKILL.md **normalize block**, after `parse-form-a.awk`. The awk still prints `"…"` verbatim. | The decode moves **into the awk inline rule**, where the TS mirror already strips (`parseCommand` inline path). The SKILL.md strip is **deleted**, not extended. See the next row for why. |
| "Fix … in the runtime (SKILL.md Step 10.4 bash block)" | By the time `$CMD` reaches the normalize block, the block cannot tell an inline scalar (YAML-quoted, has escapes) from a single-line block or fold scalar, or from a Form B fence (both literal, no escapes). The P1 byte-exact harness executes `parse-form-a.awk`, not SKILL.md. | The decode goes in the one layer that knows the scalar is inline, and that P1 already executes. SKILL.md Step 10.4 still changes: its strip and comment go, and prose documents the decode. The runtime of record is still what changes. This is recorded as a decision challenge (`specs/<branch>/decision-challenges.md`) because it moves the edit site the ask named. Measured cost of deleting the SKILL.md strip: **0 of 921** corpus commands reach it from a non-inline source. |
| "… AND in the TS mirror (stripQuotes)" | `stripQuotes` has **three** callers: `parseCommand`, `parseExpected` and `parseCredentialsRequired`. The runtimes of the last two decode nothing. | Add a sibling, `decodeQuotedScalar()`, called only from `parseCommand`'s inline path. `stripQuotes` keeps its behaviour, and its comment is corrected: the SKILL.md `case` it cites as its runtime twin is being deleted, so it now names the `CREDS_REQ` case. |
| "the awk/TS parity harness has no quoted-inline fixture" | P1 has none. P2 has exactly one, asserting the two sides **disagree**. | The P2 quote row is retired. Quoted-inline cases become P1 rows (both sides agree byte-exactly) and get a new executed-string test that runs the real SKILL.md chain (#7548's ask). |
| "add fixtures under `plugins/soleur/test/fixtures/preflight-check-10/`" | Existing plan-shaped fixtures fence their YAML. P3 **forbids a fence** in a parity fixture, because a fence makes `parseCommand` fall back to Form B. | One new file, `11-quoted-inline-scalars.md`, with one **unfenced** `## Observability` section per case. The directory is markdownlint-ignored (`.markdownlintignore`: `plugins/soleur/test/fixtures/`). |

## Problem Statement

`bash -c` receives the characters *between* the quotes, but YAML says the value is those
characters **after escape processing**. On 80 corpus commands the two differ (see the corpus
table above). Example:

```text
command: "curl -s -H \"Authorization: Bearer x\" https://h/api"
  YAML value : curl -s -H "Authorization: Bearer x" https://h/api          -> one -H argument
  executed   : curl -s -H \"Authorization: Bearer x\" https://h/api        -> -H gets `"Authorization:`, then `Bearer`, then `x"` as URLs
```

Nine of the 80 are not even valid bash as executed today. After decoding, all nine parse. The
original #8102 asymmetry shipped green because the harness that guards the parser never saw a
quoted inline row. P2 asserted the disagreement as expected, and the only test of the runtime
strip (F1d) was positional.

## Proposed Solution

There is one decoder, implemented twice (the awk runtime and the TS mirror) with byte-exact
parity, plus one new test that executes the real SKILL.md Step 10.4 chain (#7548's ask).

### Decode contract (normative, applies to the inline `command:` scalar only)

1. Trim leading and trailing whitespace **only to decide** whether the value is quoted. Return
   the value **unchanged** if the trimmed value is shorter than **3** characters, or if it does
   not start and end with the **same** quote character (`"` or `'`). That covers unquoted values,
   mismatched pairs, `"…" # trailing comment`, and the empty scalars `""` and `''`.
   *(The minimum is 3, not 2, because of plan review [Kieran P0]. Decoding `""` to an empty line
   makes the runtime's `if [[ -z "$CMD" ]]` fall through to **Form B** and run whatever fence
   follows. Measured: a fenced `printf LAUNDERED` ran. Today `""` FAILs as "empty after
   normalization", and it still does.)*
2. Double-quoted: strip the pair, then do **one left-to-right pass** over the body: `\"` → `"`,
   `\\` → `\`. **Every other backslash sequence passes through byte-for-byte**, both characters:
   `\n`, `\t`, `\/`, `\x41`, `\u00e9`, and a lone trailing `\`.
3. Single-quoted: strip the pair, then `''` → `'` in one pass. Backslashes are literal.
4. Block (`|`) and fold (`>`) scalars and Form B commands are **never** decoded. YAML block
   content is literal, and Form B is a markdown fence.
5. The decode runs **once**. Nothing downstream strips or decodes again.

**Why rule 2 deliberately diverges from YAML 1.2 on `\n` and the rest.** YAML would turn
`"printf 'ok\n'"` into a command containing a real newline. Step 10.5 rejects newlines (its
block-chaining reject), so a probe that runs fine today would start to FAIL. An author who writes
`\n` inside a probe means the shell or `printf` escape. The corpus has **zero** double-quoted
scalars that use any escape outside `{\", \\}`, so the divergence costs nothing measurable. It is
stated in SKILL.md and pinned by the `NEG-LF` row, which asserts that our value **differs** from
the YAML parser's.

### Interaction with the Step 10.5 shell-active reject (and the verb gate and the ssh reject)

The decode **cannot change any verdict**. It changes only the executed string. Proof over bytes:

- **Removed bytes.** The decode removes exactly one byte per escape: a `\` (from `\"` or `\\`) or
  a `'` (from `''`). None of the token sets contains `\`, `'` or `"`. That covers the Step 10.5
  regex (`$( \` <( >( ; && || | > < & NEWLINE ${ $X`), the ssh regex, and the verb gate's input
  (`CMD_DEQ="${CMD//[\"\'\\]/}"`). So no existing match contains a removed byte, and every match
  survives unchanged.
- **No new match can form.** Each removal keeps the other half of its escape (`"`, `\` or `'`) in
  place, so the neighbours of the removed byte never become adjacent. A new multi-byte token, such
  as `$(` from `$\(`, cannot appear. The output bytes (`"`, `\`, `'`) are not tokens either, so
  no single-byte match can appear. The `^` and `$` anchors are safe for the same reason: the kept
  byte holds the position.
- **The verb gate.** It deletes every `"`, `'` and `\` before it reads the verb, so
  `dequote(decoded) == dequote(raw)` holds identically.
- **A decoded `"` is quote syntax, not a shell-active token.** It changes how bash *splits*
  words, which is the point of the fix, and the reject regex was never quote-aware.
  `"printf \"a;b\""` is rejected both before and after the change, because the raw `;` byte is
  present either way.

Corpus replay: **0 verdict flips** across the 80 changed commands. The proof stays in prose. Plan
review cut the planned executable invariance test (see §Plan Review). It re-proved an identity:
`CMD_DEQ` deletes every byte the decode touches, and the one realistic regression (widening the
decode to `\n`) is already caught by the `NEG-LF` row on both surfaces.

**What does change: bash syntax validity, and quoting context.** A decoded `"` is a real bash
quote. A plan whose YAML value is broken shell (for example `"printf \"x"`, which decodes to
`printf "x`) now fails with `rc=2` instead of running a mangled command. On the corpus the net
effect is **+9 commands that parse and 0 that stop parsing**. For the same reason, a decoded
value can move a character between quoted and unquoted context (a glob, say). That is not new
capability: every decoded value could already be written as a plain unquoted scalar before this
change. The Step 10.5 sandbox bounds what either spelling can reach.

## Technical Approach

### Files to Edit

1. `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`
   - Add `function yaml_inline_scalar(v, …)` implementing the decode contract. Use POSIX awk
     only: `substr`, `length`, `sub`, `[[:space:]]`, and the string constants `"\\"` and `"\""`.
     No `gensub`, no `\x` escapes, no `IGNORECASE`, because operators run preflight on macOS BWK
     awk and CI may run mawk. Sketch, validated on gawk 5.4.1 against every fixture below and
     against the 524 corpus inline scalars:

     ```awk
     function yaml_inline_scalar(v,   t, q, n, body, out, i, c, d) {
       t = v; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
       n = length(t); q = substr(t, 1, 1)
       if (n < 3 || (q != "\"" && q != "'") || substr(t, n, 1) != q) return v
       body = substr(t, 2, n - 2); out = ""
       for (i = 1; i <= length(body); i++) {
         c = substr(body, i, 1); d = substr(body, i + 1, 1)
         if (q == "\"" && c == "\\" && (d == "\"" || d == "\\")) { out = out d; i++; continue }
         if (q == "'" && c == "'" && d == "'") { out = out "'"; i++; continue }
         out = out c
       }
       return out
     }
     ```

   - The inline rule becomes
     `!mode && /^[[:space:]]*command:/ { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print yaml_inline_scalar($0); exit }`.
     **Rule order is unchanged.** The fold and block header rules stay ahead of the inline rule
     (#6772, AC1). The unchanged-value branch returns `v` verbatim, trailing whitespace included,
     so none of the 21 existing P1 fixtures changes bytes. Kieran verified this.
   - Header comment: add an `inline "…"/'…'` bullet to the scalar-shapes list and a two-line
     statement of the contract.
2. `plugins/soleur/test/lib/discoverability-test-parser.ts`
   - Add `export function decodeQuotedScalar(value: string): string`, which mirrors
     `yaml_inline_scalar()`. Use the ASCII trim (the existing `H` class) for the quote decision.
     Then decode with **one global regex per quote style**, since a global `replace` is a single
     left-to-right, non-overlapping pass:
     `body.replace(/\\(["\\])/g, "$1")` for double-quoted and `body.replace(/''/g, "'")` for
     single-quoted. Measured: it is byte-identical to the awk prototype on 530 inputs (the corpus
     plus edge cases).
   - `parseCommand` inline path: `return decodeQuotedScalar(inlineKey[1].trim());`.
   - `stripQuotes` behaviour is **unchanged**. Correct its comment, which says it mirrors the
     SKILL.md `CMD` case: that case is being deleted, so name the `CREDS_REQ` case instead. Also
     state that it decodes nothing, on purpose.
3. `plugins/soleur/skills/preflight/SKILL.md` (Check 10 only)
   - Step 10.4 Form A table: add one row, **inline quoted** (`command: "…"` / `'…'`), decoded
     once by `parse-form-a.awk`. State the decoded set, the pass-through set (`\n` and the rest),
     that `""` and `''` stay unchanged, and that block and fold are never decoded. This is the
     **single** prose statement of the contract. Plan review asked for fewer copies; this one and
     the awk header comment are the only two.
   - "Normalize `$CMD` ONCE" block: **delete** the #8149 strip
     (`if [[ $CMD != *$'\n'* ]]; then case … esac fi`) and its 12-line comment. Replace them with
     a 3-line bash comment. It says: decoding happens once, in the parser; a strip here would
     double-decode `command: "'x'"` into `x`; and this block and the `FORM_A_AWK=` block are
     **executed verbatim by preflight-discoverability-test.test.ts (E, #7453)**, so keep their
     anchor lines unique and their fences intact [CTO Rec C]. Update the lead-in sentence "the
     parity harness only compares the GATE", which is no longer true now that E compares the
     executed string.
   - Sharp Edges: no new bullet. The two statements above are enough.
   - **No other Check 10 edits** (scope rule). Do not touch the `CREDS_REQ` block, the
     `EXPECTED` read, Step 10.5, or the decision matrix.
4. `plugins/soleur/test/preflight-discoverability-test.test.ts`
   - **Fixture loader (module scope).** Load `11-quoted-inline-scalars.md` with
     `extractAllObservabilityBlocks`, and read each section's ID from its `# case: <ID>` line.
     Then `reg(id, "both", section)` every section into `FORM_A_FIXTURES`. P1 and P3 now cover
     them, with no change to their bodies.
   - **Shared SKILL.md slicer.** Hoist the #7453 describe's `FORM_A_AWK=` → `AWK_RC=$?` slice
     into a module-level helper, and add a second helper that slices the normalize fence
     (`uniqueIndex` on the F1c anchor `CMD="$(printf '%s' "$CMD" | sed`, up to the next line that
     starts with three backticks). #7453 reuses the helper, unchanged in behaviour.
   - **New describe, "#8102 quoted inline scalars"**, with the rows listed in Test Scenarios
     (Q, E and the fence row).
   - Delete the test "P2 known divergence — inline quote stripping (TS strips, awk does not)".
     The divergence converged, so the row now asserts something false. The mutation it killed
     (one surface decodes, the other does not) is still killed by P1 and Q. Keep the CRLF P2 row.
   - **Replace F1d** with "F1d after normalization no CMD assignment precedes the exec (#8102)".
     It scans comment-stripped lines from the normalize anchor to `^DT_OUT=\$\(`, and asserts
     that the only `CMD=` / `CMD+=` assignments are the three normalize lines [Kieran P1-4]. That
     covers a re-added strip in a *later* fence, which E's slice cannot see. It also keeps the
     old F1d's "strip before the gate" intent, generalised. Both panels fired on F1d.
     Simplification said delete it; correctness showed a gap only this row covers. It stays as a
     replacement, not an addition.
5. `plugins/soleur/test/fixtures/check10-test-manifest.txt`
   - The gate extracts `test("…")` and backtick-literal names, so a per-case template test enters
     the manifest as **one** template line. **Test names contain no quote or backslash
     characters** [Kieran P1-5, CTO Rec D]: IDs are ASCII (`Q ${id} …`, `E ${id} …`), and the
     detail goes in the assertion message.
   - Add the new names, remove the retired P2 line, and replace the F1d line. Then **regenerate
     with `LC_ALL=C sort -u`**, because the gate runs `sort -c`. Never edit by line number.
6. `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`: set `MIN_TESTS`,
   `MIN_ASSERTIONS` and `MIN_MANIFEST_LINES` to the **measured green values**. They only ever go
   up, per the file's contract. (The manifest already holds 134 lines against a floor of 126, so
   "no slack" is aspirational today. Ratchet it to the measured value anyway.)

### Files to Create

1. `plugins/soleur/test/fixtures/preflight-check-10/11-quoted-inline-scalars.md`. Plan-shaped
   front matter and title, then one **unfenced** `## Observability` section per case. P3 forbids
   a fence in a parity fixture. Each section is pure YAML with a leading `# case: <ID>` YAML
   comment. A top-of-file note says the expected values are derived from `Bun.YAML`, except for
   the named deviations. All values are synthesized (`cq-test-fixtures-synthesized-only`).
   Every cell below was **measured**: the gawk prototype, `Bun.YAML.parse`, and `bash -c`.

| ID | `command:` line (file bytes) | Decoded / executed | Expected source | Why the row exists |
|---|---|---|---|---|
| DQ1 | `"printf '%s+' \"a b\" c"` | `printf '%s+' "a b" c` → `a b+c+` | oracle | `\"` decode (the #8102 bug) |
| DQ2 | `"printf '%s+' 'a\\b'"` | `printf '%s+' 'a\b'` → `a\b+` | oracle | `\\` decode |
| DQ3 | `"printf '%s+' 'a\\\"b' 'x\\n'"` | `printf '%s+' 'a\"b' 'x\n'` | oracle | single left-to-right pass (`\\\"`, `\\n`) |
| SQ1 | `'printf ''%s+'' ''a b'''` | `printf '%s+' 'a b'` → `a b+` | oracle | `''` decode |
| NEST | `"'printf 200'"` | `'printf 200'` (one level only) | oracle | a double decode turns E red |
| PLAIN | `printf '%s+' \"a\"` (unquoted) | unchanged | oracle | must-PASS: plain scalars are untouched |
| NEG-CROSS-SQ | `'printf ''%s+'' \"a\"'` | `printf '%s+' \"a\"` | oracle | no `\` decode inside `'…'` |
| NEG-CROSS-DQ | `"printf '%s+' ''"` | `printf '%s+' ''` | oracle | no `''` decode inside `"…"` |
| NEG-BLOCK | `command: \|` then (indented 4) `"printf '%s+' \"a\""` | unchanged literal | oracle (clip LF dropped) | block content is never decoded [Kieran P1-3: the fully quoted line makes this row non-vacuous] |
| NEG-FOLD | `command: >-` then (indented 4) `"printf '%s+' \"a\""` | unchanged literal | oracle | fold content is never decoded |
| NEG-LF | `"printf 'ok\n'"` | `printf 'ok\n'` (backslash-n kept) | **explicit** (YAML gives a real LF) | the deliberate `\n` pass-through |
| NEG-MISMATCH | `"printf \"x\"'` | unchanged, escapes included | **explicit** (YAML throws) | decode only inside a symmetric pair |
| NEG-EMPTY | `""` | `""` unchanged | **explicit** (YAML gives the empty string) | no Form B fall-through [Kieran P0] |

2. `plugins/soleur/test/fixtures/preflight-check-10/12-empty-quoted-command-with-fence.md`. A
   plan-shaped fixture **with** a fenced YAML block, used only by the E fence row (it is not a
   parity fixture). Its `discoverability_test` has `command: ""`, followed by a second fenced
   block containing `printf LAUNDERED`. It pins that the runtime never falls through to Form B
   for an empty quoted scalar.

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong preflight Check 10 verdict at ship
  time on a plan whose `discoverability_test.command` is YAML-quoted. That is either a false
  FAIL (for example row 10b, "not on the sandbox PATH") that blocks a correct PR, or a probe that
  runs a different command from the one the plan declares. The operator sees a misleading
  preflight row in the ship output. No end-user surface is involved.
- **If this leaks, the user's workflow is exposed via:** nothing new. The executed string runs
  inside the existing Step 10.5 bwrap sandbox, and this change does not touch its boundary. Every
  decoded value could already be written as a plain unquoted scalar, so the decode gives a plan
  author no command they could not already declare. The byte proof above shows that no reject or
  gate verdict changes.
- **Brand-survival threshold:** none
- `threshold: none, reason:` the diff touches only the preflight skill's parser, its test mirror,
  and test fixtures. None of those match `SENSITIVE_PATH_RE` (checked: `parse-form-a.awk`,
  `preflight/SKILL.md`, `discoverability-test-parser.ts` and the test file all return `no`), and
  no user data or credential path is involved.

## Observability

```yaml
liveness_signal:
  what: "preflight Check 10 per-PR verdict line (PASS / FAIL row 9 / row 10b) for any plan with a YAML-quoted discoverability_test.command"
  cadence: "per soleur:ship run (Phase 4 preflight)"
  alert_target: "the ship run's preflight aggregate table, which blocks PR-ready on FAIL"
  configured_in: "plugins/soleur/skills/preflight/SKILL.md Check 10 Step 10.4-10.6"

error_reporting:
  destination: "the preflight Check 10 stdout row in the operator's ship transcript (local CLI, observability layer 7; no server surface)"
  fail_loud: "FAIL: discoverability_test.command ... rc=127 (row 10b) or a row-11 stdout mismatch naming the executed command"

failure_modes:
  - mode: "awk and TS decoders drift (a new escape decoded on one side only)"
    detection: "P1 byte-exact parity plus the Q rows over 11-quoted-inline-scalars.md fail in the plugins bun shard in CI"
    alert_route: "required CI check red on the PR"
  - mode: "a second quote strip or decode is re-added after the parser (double decode)"
    detection: "E NEST row (runs the real Step 10.4 chain) and the F1d no-reassignment scan fail in CI"
    alert_route: "required CI check red on the PR"
  - mode: "the suite silently stops running these rows"
    detection: "preflight-check10-suite-integrity.test.sh manifest and floors (scripts shard)"
    alert_route: "required CI check red on the PR"

logs:
  where: "the ship transcript and the CI job log for the plugins shard"
  retention: "GitHub Actions log retention (90 days)"

discoverability_test:
  command: grep -c '^function yaml_inline_scalar(' plugins/soleur/skills/preflight/scripts/parse-form-a.awk
  expected_output: "1"
```

The probe is deliberately **unquoted** at the YAML level, a plain scalar that no decode touches.
It therefore gives the same result under the pre-fix installed runtime and the post-fix one. It
uses `grep`, not `bun` (see #8448), and it passes the verb gate and the Step 10.5 reject (checked
at plan time with `probe-verb-gate.sh` and `rejectReason`: both accept it).

## Guard Contract

### Guard 1 — quoted-inline decode parity, anchored to a YAML parser (P1 + Q)

**Property.** For every inline `command:` scalar, `parse-form-a.awk` and `parseCommand()` emit
byte-identical strings. For a YAML-quoted scalar, that string is the YAML value, except for the
three named deviations (`NEG-LF`, `NEG-MISMATCH`, `NEG-EMPTY`).

**Assembly.** There is one producer per surface, and the property quantifies over both: (1) the
awk **inline rule**, the only rule that emits an inline value (the fold and block rules emit
continuation lines, and `NEG-BLOCK` and `NEG-FOLD` pin those); (2) `parseCommand`'s
`INLINE_KEY_RE` branch. The comparison chokepoint is `FORM_A_FIXTURES` plus P1's loop. Every
fixture section enters **only** through the ID-keyed loader, so a new section is covered with no
code change. The **expected** value is `Bun.YAML.parse(section).discoverability_test.command`,
with block clip-LF removed, unless the ID is in the explicit `DEVIATIONS` map. That makes the
YAML parser the anchor, and a table edited to match a broken implementation is impossible by
construction [simplicity: merge the oracle into Q; CTO: keep an anchor outside the diff].

**Mutation matrix:**

| # | Mutation (design-derived) | Expected |
|---|---|---|
| 1 | awk inline rule prints `$0` again (decode call removed) | RED: P1 + Q on DQ1, DQ2, DQ3, SQ1, NEST |
| 2 | awk decoder widened to also map `\n` → LF (TS unchanged) | RED: P1 + Q `NEG-LF` |
| 3 | awk drops the symmetric-pair check | RED: Q `NEG-MISMATCH` |
| 4 | minimum length back to 2 | RED: Q `NEG-EMPTY` + E fence row |
| 5 | the decode is applied to block/fold continuation lines too | RED: Q `NEG-BLOCK` / `NEG-FOLD` |
| 6 | **own dispatch**: the loader returns 0 sections, or the fixture IDs and the expected-ID set disagree | RED: `expect(new Set(ids)).toEqual(new Set(EXPECTED_IDS))` (one row covers count and identity; no order assertion) |
| 7 | **second member after a compliant first**: corrupt only the LAST section's decode | RED: that section's own Q row (per-case template, never first-hit-and-stop) |
| 8 | TS-only: `decodeQuotedScalar` swapped for the old `stripQuotes` | RED: P1 on DQ1, DQ2, DQ3, SQ1 |
| 9 | a sequential two-pass decoder (`\\`→`\` then `\"`→`"`) | RED: Q `DQ3` |

**Harness rows:** H1: delete a section from the fixture file → RED on the ID-set row. H2: move
an ID into `DEVIATIONS` with a wrong expected value → RED on that row. Must-PASS rows are `PLAIN`
and `NEG-CROSS-DQ`. They differ from the canonical DQ1 in ways the contract permits, so a guard
that decoded or rejected everything would fail there.

**Anchor.** `Bun.YAML` at the version in `.bun-version` sits outside the diff. A weakening needs
a Bun change, or an explicit entry in `DEVIATIONS`, which is a visible 1-line diff. The O-row
failure message names `.bun-version` and reads "if the Bun pin just moved, the oracle moved, not
the parser" [CTO Rec B].

### Guard 2 — executed-string parity over the real SKILL.md chain (E + F1d), closing #7548

**Property.** For every fixture section, the `$CMD` that Step 10.4 leaves for the verb gate,
Step 10.5 and the exec equals the case's expected decoded value (normalized), and equals
`normalizeCommand(parseCommand(section))`. Nothing after normalization reassigns `CMD`.

**Assembly.** The runtime chain is two fenced bash blocks, **extracted from SKILL.md and
executed**: `FORM_A_AWK=` through `AWK_RC=$?` (the #7453 slice), then the rest of that fence
(the `EXPECTED` read and the Form B fallback), then the normalize fence. They run with
`CLAUDE_PLUGIN_ROOT=<repo>/plugins/soleur`, `PREFLIGHT_TMP=<tmpdir>` and `set -uo pipefail`,
and the script ends with `printf '%s' "$CMD"`. The chain was prototyped at plan time: rc 0, and
the Form B fallback lies inside the slice. The anchors are **code lines**, resolved through
`uniqueIndex`. The window after the normalize fence, up to `DT_OUT=$(`, is covered by F1d's
no-reassignment scan. F1c already pins the ordering of normalization before the gate, the reject
and the exec.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | re-add the #8149 `case "$CMD" in \"*\") …` strip to the normalize block | RED: E `NEST` (`'printf 200'` → `printf 200`) |
| 2 | **reorder**: remove the awk decode and add an equivalent decode as a new line *after* the normalize fence | RED: E (decoded expectation) and F1d (a new `CMD=` before `DT_OUT`) |
| 3 | **own dispatch**: an anchor fails to resolve, or an extracted block is empty | RED: `uniqueIndex` count = 1, plus content assertions (`CMD=$(awk -f "$FORM_A_AWK"`, `sed -e '/^[[:space:]]*#/d'`) |
| 4 | the chain exits early (a wrong plugin root trips the `test -r` guard) | RED: `rc === 0` and non-empty `$CMD` on positive rows |
| 5 | minimum length back to 2 (Form B fall-through) | RED: E fence row (`$CMD` must not contain `LAUNDERED`) |

**Harness row:** stubbing E's runner to return `normalizeCommand(parseCommand(section))` is
**not** enough on its own to pass E, because E also asserts the **expected decoded value**
[Kieran P1-2]. Combined with Guard 1 mutation 1, the stub goes RED.

## Acceptance Criteria

- [ ] AC1. `parse-form-a.awk`'s inline rule emits the decode-contract value. Every row in the
  fixture table produces the "Decoded" column byte-for-byte under gawk **and** mawk (the suite's
  banner test accepts either, so CI may resolve either one). Run mawk locally from a container or
  an installed `mawk`, not only gawk. Code lines use no GNU-only constructs:
  `grep -vE '^[[:space:]]*#' plugins/soleur/skills/preflight/scripts/parse-form-a.awk | grep -cE 'gensub|IGNORECASE|\\x'`
  prints `0`.
- [ ] AC2. P1 is green with the 13 new rows (`parseCommand` and `runAwk` byte-identical), and
  every Q row equals its expected value (oracle or `DEVIATIONS`).
- [ ] AC3. The P2 "inline quote stripping" test is gone. The CRLF P2 test is untouched.
- [ ] AC4. The SKILL.md normalize block contains no quote strip. The new F1d passes.
  Re-adding the #8149 strip turns E `NEST` RED: record the observed failure line in the PR body.
- [ ] AC5. E passes over every section of fixture 11, and the fence row passes over fixture 12.
  Run against `origin/main`'s awk and SKILL.md (a scratch copy), E is RED on DQ1, because the
  expected decoded value differs. That is the RED-first evidence (`cq-write-failing-tests-before`).
- [ ] AC6. `parseExpected` on the DQ2 section returns `a\\b+` (two backslashes: the expected path
  does not decode). `stripQuotes` behaviour is unchanged, which the existing `parseExpected` and
  `parseCredentialsRequired` tests show by staying green.
- [ ] AC7. `bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh` passes, with the
  three floors at the measured green values and the manifest regenerated with `LC_ALL=C sort -u`.
  No manifest line contains `"` or `\`.
- [ ] AC8. `bun test plugins/soleur/test/preflight-discoverability-test.test.ts plugins/soleur/test/observability-schema-parity.test.ts`
  passes. G1's `BASELINE_DECLARED_PROBES` is unchanged, because this plan declares no
  `credentials_required`.
- [ ] AC9. In SKILL.md, the diff touches only Step 10.4's Form A table and the normalize block:
  `git diff origin/main...HEAD -- plugins/soleur/skills/preflight/SKILL.md` shows hunks only
  there. Step 10.5, the decision matrix and the `CREDS_REQ` block are unchanged.
- [ ] AC10. The PR body carries `Closes #8102` and `Closes #7548` (in the body, not the title). A
  comment on #7403 records that its re-evaluation trigger (b), "the parse surface produces a
  correctness bug", fired with #8102 and #7548, so it can be re-triaged [CTO Rec A]. Posting that
  comment is a `soleur:work` / `soleur:ship` step, not an operator step.

## Test Scenarios

Every scenario lives in `plugins/soleur/test/preflight-discoverability-test.test.ts`, in the new
"#8102 quoted inline scalars" describe unless stated otherwise. Test names are ASCII with no
quote characters.

- **Q (per case, both surfaces).** Given each fixture section, `runAwk(section)` and
  `parseCommand(section)` both equal `expected(id)`. `expected(id)` is `DEVIATIONS[id]` when the
  ID is listed there; otherwise it is the `Bun.YAML` value (with block clip-LF dropped). Template
  name: `Q ${id} awk and TS emit the YAML value`.
- **Q-ids.** The set of fixture IDs equals `EXPECTED_IDS` (13 entries). This covers loader
  dispatch, count and identity in one row, with no order assertion.
- **E (executed string).** For each section, the extracted SKILL.md chain returns `rc === 0` and
  prints a `$CMD` that equals both `normalizeCommand(expected(id))` and
  `normalizeCommand(parseCommand(section))`. Template name:
  `E ${id} the Step 10.4 chain leaves the decoded command`.
- **E-fence.** Fixture 12 goes through the chain. `$CMD` does not contain `LAUNDERED`, and it
  equals `normalizeCommand(parseCommand(block))` (a literal `""`, which then fails the verb gate
  as empty on both surfaces).
- **Scope (P-SCOPE).** `parseExpected(DQ2 section) === String.raw\`a\\b+\``.
- **F1d** (in the "#7393 F" describe). From the normalize anchor to `^DT_OUT=\$\(`, with comments
  stripped, the only `CMD` assignments are the three normalize lines.
- **Regression.** The existing tests stay green unchanged: "Form A — a YAML-quoted inline scalar
  is the string INSIDE the quotes (#8149)", "I1 inline command is unchanged", F1-F5, N1-N7, B1-B3,
  E1, and the #7453 describe (which now uses the hoisted slicer).

## Implementation Phases

1. **RED.** Create both fixtures, and check the backslashes with `od -c` rather than by reading
   the file. Add the loader, the shared slicer, the Q, E, E-fence and scope rows, and the new
   F1d. Run them. Today's awk strips nothing, so Q is RED on every quoted row (DQ1-3, SQ1, NEST,
   NEG-LF, NEG-CROSS-*). Q stays green only on PLAIN, NEG-BLOCK, NEG-FOLD, NEG-MISMATCH and
   NEG-EMPTY. E is RED on DQ1-3, SQ1 and NEST, because it asserts the decoded value. E-fence is
   RED on its equality: today's #8149 strip empties `""`. It is still green on "no `LAUNDERED`",
   because the fallback runs before the strip. F1d is RED, because the #8149 strip's `CMD="${CMD#…}"`
   lines are assignments after the three normalize lines. Q-ids passes.
2. **GREEN, awk.** Add `yaml_inline_scalar` and the inline-rule call. Run under gawk and mawk.
3. **GREEN, TS.** Add `decodeQuotedScalar` (the regex form), wire up `parseCommand`, and fix the
   `stripQuotes` comment.
4. **SKILL.md.** Delete the normalize-block strip, add the Form A row and the executed-verbatim
   comment, and retire the P2 quote row.
5. **Two hand mutations**, run in a scratch copy (never `git stash`, per
   `hr-never-git-stash-in-worktrees`): re-add the #8149 strip (E `NEST` must go RED), and set the
   awk minimum length back to 2 (Q `NEG-EMPTY` and E-fence must go RED). Record both observed
   lines in the PR body. The other matrix rows are covered structurally by named rows, so they
   are not re-run by hand [DHH/simplicity: shrink the mutation pass].
6. **Ratchet.** Regenerate the manifest and run the suite-integrity gate. Set the three floors to
   the measured values.

## Non-Goals

- `expected_output` and `credentials_required` escape decoding. Their runtimes decode nothing, and
  parity holds today. Changing both sides is a separate behaviour change with no corpus evidence
  of need.
- `"…"  # trailing comment` inline scalars (3 corpus hits). All three already contain `&&` or
  `$VAR`, so Step 10.5 rejects them regardless, and there is no measured user-visible effect.
  This is documented here instead of filed, per `wg-when-deferring-a-capability-create-a`.
- YAML escapes beyond `{\", \\}` (see the NEG-LF rationale above).
- Single-line quoted commands from a **Form B fence**. Deleting the SKILL.md strip means a fenced
  `"curl …"` line now reaches bash with its quotes, since fenced shell text is literal. Measured:
  0 of 921 corpus commands. `NEG-BLOCK` and `NEG-FOLD` keep the block and fold arms undecoded as
  the corpus grows.
- Unicode-whitespace trim parity between JS `.trim()` on the `parseCommand` input and awk
  `[[:space:]]`. This is pre-existing, it matters only for Unicode space *outside* the quotes, no
  fixture carries it, and this change does not widen it.
- #7403 (the probe registry). Its trigger fired (see AC10), but building it is not this PR.
- CTO Rec E (rewording the suite-integrity header to "exact-at-ratchet, floor-thereafter") is
  declined as out of scope for this item.

## Open Code-Review Overlap

None. I checked `gh issue list --label code-review --state open` bodies against every path in
Files to Edit and Files to Create; there were 0 matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an internal tooling fix to the preflight skill's
parser and its tests: no user-facing surface, no pricing, legal, marketing or ops impact.

## Plan Review

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer` (per-mechanism), and `soleur:engineering:cto`
(named panel, devex lens; activated by the code/tooling Files to Edit). The design and UX panels
were not activated, because the plan has no UI surface. Plan-time advisor consult: an ADR-083
advisor-tier subagent.

**Applied (Mechanical):**

- **Kieran P0.** The minimum quoted length is 3, so `""` and `''` stay unchanged. That closes
  the Form B fall-through that was measured running a fenced `printf LAUNDERED`. Added the
  `NEG-EMPTY` row and fixture 12.
- **Kieran P1-2.** E asserts the expected decoded value, not only parity with the mirror, so it
  is RED on `main`. The RED-phase list is corrected.
- **Kieran P1-3.** NEG-BLOCK and NEG-FOLD continuations are fully quoted lines, so the
  "decode continuations" mutation actually reddens them.
- **Kieran P1-4.** F1d is replaced by a no-`CMD=`-reassignment scan from the normalize anchor to
  `DT_OUT=`.
- **Kieran P1-5 and CTO Rec D.** The manifest is regenerated with `LC_ALL=C sort -u`, per-case
  tests use template names, and no test name contains a quote or a backslash.
- **Kieran P2-8.** The User-Brand "no new capability" argument now rests on "every decoded value
  was already writable as a plain scalar", not on the verdict proof alone.
- **DHH P1-a and simplicity.** Guard 4 (R), `REJ` and the invariance AC are cut; the proof
  stays in prose.
- **Simplicity.** The oracle is merged into Q as the expected-value source, with explicit
  `DEVIATIONS`. The order assertion is replaced by an ID-set row. The TS decoder uses the
  single-pass regex form, byte-identical to the awk on 530 inputs. The #7453 slicer is reused.
  The contract is stated in prose in two places, not three.
- **DHH P1-e.** The hand mutation pass is reduced to the two observed mutations that close the
  issues.
- **Advisor.** The NEG-FOLD row was added, and the decision challenge was recorded before coding.
- **CTO Rec B and Rec C.** The oracle failure message names `.bun-version`. The SKILL.md comment
  flags that both fenced blocks are executed verbatim by tests.
- **CTO Rec A.** A #7403 re-triage comment is added as AC10.

**Declined, with reasons:**

- **DHH P1-b (move the oracle out of the suite).** The CTO and simplicity reviewers both wanted
  an anchor outside the diff. The merged form costs one call per row, and the pin-bump risk is
  handled by the failure message.
- **DHH P1-c (delete F1d).** Kieran P1-4 found a real gap that only a positional scan covers: a
  strip re-added in a later fence. It stays as a replacement, not an addition.
- **DHH P2-a (drop NEG-BLOCK and NEG-FOLD).** Kept. They are the only non-corpus evidence that
  deleting the SKILL.md strip stays safe as the corpus grows, as the advisor noted.
- **Advisor (extract normalization to a script).** Cut; see the Cut List. Code-line anchors
  resolved through `uniqueIndex` are already load-bearing for #7453 and F1c.
- **CTO Rec E (rewording the suite-integrity header).** Out of scope for this item.

**Taste and User-Challenge:** one, DC-1: the decode site moves from the SKILL.md bash block to
the parser. It is persisted to `knowledge-base/project/specs/feat-one-shot-8102-check10-yaml-quote-escapes/decision-challenges.md`.

## Dependencies & Risks

- **mawk vs gawk.** The awk must be POSIX. `substr`, `length` and `sub` with `[[:space:]]` are
  supported by mawk 1.3.4 (which the existing file already relies on for `[[:space:]]`). Risk:
  mawk string-constant escapes. Use only `"\\"` and `"\""`. AC1 requires a real mawk run.
- **Suite-integrity exact floors.** They must be ratcheted to the measured value, never
  "approximately". A mismatch is a hard RED in the scripts shard.
- **The #7453 describe executes a SKILL.md slice ending at `AWK_RC=$?`.** It moves onto the
  hoisted module-level slicer with unchanged behaviour. The FORM_A fence is not edited, and its
  four tests must stay green unmodified.
- **The `Bun.YAML` oracle is new to the repo.** A `.bun-version` bump that changes YAML edge
  cases can turn Q red on an unrelated PR. The failure message names `.bun-version`, so the
  person bumping it can triage it at once. The alternative (hand-written expected values) was
  rejected because the same diff can edit a hand-written table.
- **Installed-plugin skew at ship.** Check 10 at ship time runs the *installed* plugin's runtime
  (ADR-179), not the worktree's. This PR does not touch sensitive paths, so Check 10 does not fire
  on it. Plans shipped after the release pick up the decode.

## References

- Issues: #8102 (and its 2026-09-25 scope-note comment), #7548, #8149 (merged), #7403, #8448, #6772.
- Code: `plugins/soleur/skills/preflight/scripts/parse-form-a.awk` (inline rule),
  `plugins/soleur/skills/preflight/SKILL.md` Step 10.4 ("Normalize `$CMD` ONCE") and Step 10.5
  (shell-active reject), `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh`
  (`CMD_DEQ`), `plugins/soleur/test/lib/discoverability-test-parser.ts` (`parseCommand`,
  `stripQuotes`), `plugins/soleur/test/preflight-discoverability-test.test.ts` (P1/P2/P3, F1c/F1d,
  #7453).
- YAML 1.2.2 §7.3.1 (double-quoted escapes) and §7.3.2 (single-quoted `''`), used via the
  `Bun.YAML` oracle at bun 1.4.2.
