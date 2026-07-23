---
title: "fix: preflight Check 10 Form A parser mis-reads folded YAML scalars (`command: >-`)"
date: 2026-07-21
type: fix
issue: 6772
branch: feat-one-shot-6772-preflight-folded-scalar-parser
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: preflight Check 10 Form A parser mis-reads folded YAML scalars

🐛 Closes #6772

## Enhancement Summary

**Deepened on:** 2026-07-21
**Agents:** kieran-rails-reviewer, code-simplicity-reviewer, test-design-reviewer, security-sentinel, cpo

### Key improvements over the first draft

1. **Terminator redesigned twice.** The issue's suggested `[a-z_]+:` guard truncates on
   `https://`. My replacement (colon-must-be-followed-by-space) *also* truncated — on a
   real corpus plan with a jq object filter. The final design drops the key regex
   entirely and uses **pure YAML indent semantics**: continuation requires
   `indent > key`, anything at `indent <= key` ends the scalar. Simpler and correct.
2. **Security: the fix opens a fail-open transition.** Empirically, fixing defect 2
   flips **4 corpus plans from REJECT (fail-closed) to EXEC**, and all four run
   `doppler run -p soleur -c prd_terraform`. `env -i` does **not** scrub the credential
   they use. Threshold raised from `none` to `single-user incident`; AC11 now gates on
   the reject-verdict delta.
3. **Parser differential closed.** The draft's continuation rule matched *any* indented
   line, so a **less**-indented line was still consumed — a construct a reviewer reads
   as outside the command but the executor runs. Verified exploitable. `indent > key`
   closes it.
4. **The anchored header regex created a fresh instance of #6772.** `command: >- # note`
   failed the `$` anchor, fell to the inline rule, and returned the literal. Header now
   tolerates a trailing comment.
5. **Two of the draft's "reddening mutations" were dead** (N2, N3 — verified byte-identical
   output under mutation). Mutation protocol gained a reachability step.
6. **CPO caught a false mitigation claim.** The draft cited the newline reject as bounding
   the 4 credentialed flips; those join with a **space** and carry no shell-active token, so
   it covers none of them. The credentialed-CLI reject was moved from tracked to **in this
   PR** (C1), the claim was corrected (C2), and a Phase 4 architecture issue was added (C3).

## Overview

Preflight Check 10 Step 10.4 parses `discoverability_test.command` with a 4-rule awk
handling exactly two YAML scalar shapes: inline (`command: <value>`) and block
(`command: |`). There is no folded-scalar branch. On `command: >-` the **inline rule
matches**, strips the key, and yields the literal `>-` — which then trips Check 10's
*own* shell-active-token reject (the `>` branch in Step 10.5):

```
FAIL: discoverability_test.command contains shell-active token; refusing to run.
```

The check fails closed (safe direction), but the diagnostic points at a nonexistent
shell-injection rather than at the parse. The natural operator response is to reword the
command until the reject stops firing — never noticing the parser never read it.
**A check that cannot parse its input is indistinguishable from a check that ran and
found nothing.**

This plan fixes the parser on **both** surfaces (production awk + TypeScript mirror),
adds the missing behavioural parity guard, fixes a **second pre-existing defect** in the
block-scalar branch, and closes a **parser differential** that review found exploitable.

### Blast radius

Census over non-archive plans (2026-07-21). Counts are **regex-derived**; re-derive at
implementation time rather than trusting them (three reviewers produced 4/17/19 against
my 5/18/20 — the exact count is not load-bearing, the shape distribution is):

| Header form | Approx. plans | Current parse result |
| --- | --- | --- |
| `command: >` (clip) | ~13 | literal `>` → shell-active reject |
| `command: >-` (strip) | ~4–5 | literal `>-` → shell-active reject |
| `command: >+` (keep) | 0 | — |
| `command: \|` (block) | ~19–20 | **swallows the sibling `expected_output:` key** (defect 2) |
| `command: \|-` / `\|+` | 0 | bash → block mode; TS → literal `\|-` (**existing drift**) |
| `discoverability_test: { command: "…" }` (flow mapping) | ~7–13 | **out of scope** — see §Variant Scope |

~17 plans already use the folded form; `>` is roughly **3× more common than `>-`**, so a
fix scoped only to `>-` would leave the majority broken.

**Efficacy caveat (security review F7):** after the fix, ~13 of ~16 folded plans *still*
hit the shell-active reject, because they legitimately contain `|` or `$()`. The fix
removes a **misleading** diagnostic; for most of the folded corpus the diagnostic becomes
*correct* rather than absent. AC11 reports the true unblock count so this is visible
rather than assumed.

## Research Reconciliation — Issue Claims vs. Codebase

| Issue claim | Reality (verified) | Plan response |
| --- | --- | --- |
| Inline rule shadows fold; ordering is load-bearing | **CONFIRMED.** awk evaluates top-down; rule 2 matches `command: >-`, prints `>-`, `exit`s. | Fold rule placed first. F1–F3 pin ordering behaviourally. |
| Suggested guard `^[[:space:]]*[a-z_]+:` stops the fold at the next key | **CONFIRMED for `expected_output:`, but the guard is wrong in three ways.** (a) a continuation starting `https://` matches (`https` ∈ `[a-z_]+`) → truncates. (b) the colon-must-be-followed-by-space repair *still* truncates on a deeper-indented `key: value` — verified against a real corpus plan. (c) any key-regex terminator leaves a **parser differential**: the continuation rule matched *any* indented line, so a **less**-indented line was consumed anyway. | **Drop the key regex entirely.** Pure indent semantics: continuation requires `indent > key`; `indent <= key` exits. See §Phase 2. |
| Only `>-` needs handling | **REFUTED by census.** `>` is ~3× more common. | Handle `>`, `>-`, `>+` via `>[-+]?`. |
| Trailing-space join concern | Real but avoidable; appending leaves a trailing space and defeats byte-exact parity. | **Prepended** separator (`(n++ ? " " : "")`). F4 pins it. |
| The TS mirror needs a parity assertion "if one does not already exist" | **None exists.** The test file asserts only *prose invariants* on SKILL.md; nothing executes the awk. | Real behavioural parity harness (§Phase 3), made tractable by extracting the awk to a file. |
| Revert the single-line workaround if still present | **Not locatable.** `git log -S'command: >-' --since=21.days` and a diff scan for removed `-  command: >` lines return nothing. | Recorded as "nothing to revert". §Workaround Revert. |

### The terminator trap, twice

Draft 1 used the issue's `[a-z_]+:` — truncates on `https://`.

Draft 2 used `[A-Za-z_][A-Za-z0-9_]*:([[:space:]]|$)` and claimed empirical verification.
That verification covered only `https://` and capitalisation. Review found a **real corpus
plan** it breaks —
`knowledge-base/project/plans/2026-07-03-fix-seccomp-loaded-sha-deploy-status-discriminators-plan.md`,
whose folded command ends in a jq object filter:

```
    https://deploy.soleur.ai/hooks/deploy-status | jq
    '{matches: .seccomp_profile_loaded_matches_host,
      host_present: .seccomp_profile_host_present, host_sha: .seccomp_profile_host_sha256}'
```

`host_present:` is followed by a space → the terminator fires and cuts the command
mid-jq-expression. Exactly the outcome §User-Brand Impact names as *worse* than the
reported bug.

**Draft 3 (final) drops the key regex.** YAML already defines the rule: a block or folded
scalar ends at the first non-empty line indented **less than or equal to** the key that
opened it. No key detection needed. This is simpler, matches the spec, and closes the
parser differential below.

### Parser differential (security review F4) — the draft was exploitable

The draft's continuation rules were `/^[[:space:]]+[^[:space:]]/` — *any* indented line.
The terminator's `indent <= key` guard was ANDed with the key regex, so it only gated
lines that **looked like keys**. A less-indented non-key line was still consumed.
Verified in block mode:

```yaml
    command: |
      curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/inngest
  touch /tmp/BLOCK_LESS_INDENT_PWN
    expected_output: "200"
```

→ passed the reject, and the `touch` **ran**. A YAML parser ends the scalar at that
dedent; a human reviewer reads the line as outside the command. Since trust-on-PR-review
is the stated primary mitigation, a construct that reads differently to the reviewer and
the executor defeats it directly. `indent > key` on continuations closes this.

### Defect 2 (pre-existing): block scalar over-consumes

The block branch has **no terminator** — it relies on indentation:

```awk
mode=="block" && /^[[:space:]]+[^[:space:]]/ { print; next }   # matches ANY indented line
mode=="block" && /^[[:space:]]*[^[:space:]]/ { exit }          # only reached at column 0
```

`  expected_output: "200"` is indented, so rule 3 matches it first — the swallowed key
becomes a second command.

**Corrected severity** (draft 1 overstated it): `bash -c` runs the line, `expected_output:`
is not found, rc=127 goes to **stderr**, stdout is unchanged — so `matchExpected` usually
reaches the same verdict. The real damage is that `$?` reflects the bogus second command,
corrupting the rc-based states 4/5/7 of the decision matrix. Roughly 8 of ~19 block plans
have `expected_output` on the immediately-following line.

The same indent terminator fixes this at zero incremental cost — literally the same rule
line. **But it is also the source of the fail-open transition below.**

## Security Findings (from deepen-plan review — all empirically reproduced)

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| F4 | MED-HIGH | Continuation rules consumed **less**-indented lines → reviewer/executor differential, verified exploitable | **Fixed inline** — `indent > key` |
| F2/F3 | HIGH | Fixing defect 2 flips **4 corpus plans REJECT → EXEC**; all 4 run `doppler run -p soleur -c prd_terraform`. `env -i` does **not** scrub this credential: the Doppler CLI reads a live `dp.ct.*` token from `~/.doppler/`, and Step 10.5 preserves `HOME="$HOME"` | **Fixed inline** — credentialed-CLI reject added to Step 10.4 alongside the existing `ssh` reject (CPO condition C1). Threshold raised; AC11 gates on the reject-verdict delta as the residual control |
| F1 | HIGH (pre-existing) | Newline is **not** in the Step 10.5 reject set, so block mode is an unguarded command-chaining primitive (verified: a second line `touch /tmp/PWNED` executed) | **Fixed inline** — add `\n` to the reject set. **Scope note (CPO condition C2): this closes block-mode chaining ONLY and contributes ZERO coverage to the 4 folded flips**, which join with a space and contain no shell-active token. Verified: both flip commands pass the reject even with `\n` in the set |
| F5 | MED | `awk -f <missing>` → rc=2 + empty stdout; `set -uo pipefail` does not abort (command-substitution rc is discarded), so `$CMD` is empty and Form B silently parses a **different** command. `CLAUDE_PLUGIN_ROOT` is **unset** in a plain session | **Fixed inline** — resolve via `git rev-parse --show-toplevel`; hard-fail on awk rc≠0 instead of falling through |
| F6 | LOW-MED | Fold + trailing `\` mangles the command (`\` + injected space = escaped space). Two corpus plans use trailing `\` | Fixture + `.awk` header note |
| F7 | INFO | ~13 of ~16 folded plans still reject post-fix (legitimate `\|`/`$()`) | AC11 reports true unblock count |

**Credentialed-CLI reject — folded in, not tracked (CPO condition C1).** The draft deferred
this as "a Check 10 policy change affecting plans this PR does not touch." That inverts
causality: **this PR is what makes those plans executable.** The capability change and the
policy change are the same change; splitting them ships the exposure in PR 1 and the
mitigation in PR 2. `plugins/soleur/skills/plan/SKILL.md` also codifies the rule directly —
at `single-user incident` threshold, scope-outs justified by "next-most-likely entry not
covered" are anti-pattern: ship inline or downgrade the threshold.

It is also **thesis-consistent**. §Overview argues the win is that the diagnostic becomes
*correct* rather than absent; for the flip set the reject delivers exactly that
("credentialed CLI; refusing to run" instead of a silent credentialed execution). F7
already concedes ~13 of ~16 folded plans still reject, so the marginal unblock loss is
noise.

## User-Brand Impact

**If this lands broken, the user experiences:** preflight FAILs a well-formed plan with a
shell-injection diagnostic naming a defect the plan does not have; or (if the terminator
is over-broad) silently truncates the probe so Check 10 renders a verdict on a partial
command; or (if the differential is left open) executes a line the PR reviewer read as
being outside the command.

**If this leaks, the user's data/workflow/money is exposed via:** preflight
auto-executing a plan-authored command with the operator's **live Doppler CLI token**
reachable. Verified: this change moves 4 corpus commands from never-executed to
auto-executed, all of them `doppler run -p soleur -c prd_terraform -- <repo script>`.
`env -i` scrubs env vars but not file-backed CLI auth, because `HOME` is deliberately
preserved. The exposure vector is a plan file authored in a PR — trust-on-PR-review — but
the surface is genuinely wider after this change than before it.

**Brand-survival threshold:** single-user incident.

Raised from `none` after the security review falsified the draft's "no new exposure
surface" claim.

**CPO sign-off: GRANTED WITH CONDITIONS (2026-07-21)** — C1 (fold the credentialed-CLI
reject into this PR, AC14), C2 (correct the false `\n` mitigation claim), C3 (file the
Phase 4 ambient-credential architecture issue, AC15). All three are applied above; C1 and
C2 were prerequisites to `/work`. CPO also noted the threshold is honest **only if C1
lands** — shipping as drafted would have made it `aggregate pattern`, since `prd_terraform`
governs shared production infra credentials reaching every user, not one.
`user-impact-reviewer` runs at review time.

## Variant Scope

| Variant | In scope | Why |
| --- | --- | --- |
| `>-`, `>`, `>+` | ✅ | `>`/`>-` cover ~17 corpus plans. `>+` is zero-usage but one character (`>[-+]?`); excluding it leaves a third silent variant. One table-driven fixture, not three. |
| `\|-` / `\|+` | ✅ (alignment) | Zero usage, but bash and TS **already disagree** (bash prefix-matches into block mode; TS's anchored regex falls to inline and returns the literal). Ten characters closes a real drift. B3 pins it. |
| Trailing comment on the header (`command: >- # note`) | ✅ | Anchoring the header to `$` **created a fresh instance of #6772**. Header tolerates `[[:space:]]*(#.*)?$`. |
| Explicit indent indicators (`>2`, `\|4`) | ❌ | Zero usage. Falls to the inline rule → literal → reject. Fails closed. |
| Chomping semantics | ❌ | Value goes to `bash -c`; `$(…)` strips trailing newlines. All three indicators treated identically. |
| Flow mapping `discoverability_test: { command: … }` | ❌ (tracked) | ~7–13 plans; FAILs state 3 **honestly** today ("no command could be parsed"), unlike #6772. AC12. |
| Inline quote stripping (`command: "curl …"`) | ❌ (tracked) | TS strips, awk does not — pre-existing on both surfaces, orthogonal to folded scalars. AC12; asserted as a **known divergence** in the harness so it is not silently omitted. |
| Credentialed-CLI reject (`doppler`/`gh`/`aws`/`supabase`/`stripe`) | ✅ | **Folded in per CPO condition C1** — this PR is what makes the 4 credentialed commands executable, so the mitigation ships with the capability. AC14. |

## Files to Edit

- `plugins/soleur/skills/preflight/SKILL.md` — Step 10.4 (call the extracted awk, hard-fail on rc≠0, add the credentialed-CLI reject, update Form A prose); Step 10.5 (add `\n` to the reject set).
- `plugins/soleur/test/lib/discoverability-test-parser.ts` — `parseCommand()` + `SUBST_REJECT_RE`.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — fixtures + parity harness.

## Files to Create

- `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200`, body-matched against each
path via standalone `jq --arg`: **None.**

## Architecture Decision (ADR/C4)

Not applicable. A bug fix on an existing surface — no ownership/tenancy boundary move, no
new substrate, no resolver/trust-boundary change, no ADR divergence. Extracting the awk to
a sibling `scripts/` file is a file-layout change already sanctioned by
`plugins/soleur/AGENTS.md`.

**C4 completeness check:** all three of `model.c4`, `views.c4`, `spec.c4` reviewed against
this change's actors and systems. No external human actor (the parser reads a repo-local
file authored by the existing operator role), no external system or vendor (pure text, no
network), no container or data store (the parse runs in-process in the preflight shell),
no actor↔surface access relationship changed. No C4 edit required.

## Infrastructure (IaC)

Not applicable. No server, service, secret, DNS record, cron, vendor account, or
persistent runtime process.

## Domain Review

**Domains relevant:** none

No cross-domain implications — internal tooling change. No UI-surface path in Files to
Edit/Create, so the Product/UX Gate is skipped. (The `single-user incident` threshold
requires CPO sign-off per §User-Brand Impact, handled at the plan gate, not via a domain
sweep finding.)

## Implementation Phases

Phase order is load-bearing: contract (awk) → mirror (TS) → guard (parity harness).
Reversing it makes the harness green against a half-applied fix.

### Phase 1 — RED: fixtures first

Add the §Test Matrix fixtures; confirm the fold/terminator/differential cases are **red**
against the unmodified parser. **Capture the failure output verbatim** — it is the primary
non-vacuity evidence (§Mutation Verification). Confirm the absence-assertions (N1, N5, B1,
S1) fail for over-consumption, not malformed fixtures.

### Phase 2 — Extract the awk to a real file, then fix it

**Why extract.** The awk lives in a markdown fence: nothing lints it, nothing executes it,
and a parity test must regex-scrape it back out of prose — then needs a second guard
against the scrape silently returning empty. A guard against your own harness's fragility
is the tell. `plugins/soleur/AGENTS.md` already sanctions `skills/<name>/scripts/`.

Create `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`. **This program is
verified — every rule below was run against the fixture set and the live corpus before
being written here:**

```awk
# Form A parser for preflight Check 10 Step 10.4 — the production runtime of record.
# Mirrored (non-authoritatively) by plugins/soleur/test/lib/discoverability-test-parser.ts.
# If the two drift, THIS FILE WINS and the mirror is the bug.
#
# Scalar shapes for `command:`:
#   inline   `command: curl …`
#   block    `command: |`  `|-`  `|+`   → continuations joined with NEWLINE
#   folded   `command: >`  `>-`  `>+`   → continuations joined with SPACE
#
# Scalar extent follows YAML: a continuation is any non-empty line indented MORE than the
# `command:` key; the first line indented <= the key ends the scalar. No key-name matching
# is used — a key regex both truncates legitimate content (a jq object filter's
# `host_present:`) and leaves a differential where a LESS-indented non-key line is still
# consumed, which a PR reviewer reads as outside the command but the shell executes.
#
# Chomping indicators (-/+) are accepted but not modelled: the value goes to `bash -c` and
# $(…) strips trailing newlines regardless.
#
# CAVEAT (folded + trailing backslash): folding joins with a space, so a continuation
# ending in `\` yields `\ ` — an escaped space, not a line continuation. YAML folding
# consumes the backslash as ordinary text too, so this is spec-correct, but the executed
# command differs from the one a reviewer reads. Prefer block (`|`) for commands using
# trailing-backslash continuations.

function indent(s,   t) { t = s; sub(/[^[:space:]].*$/, "", t); return length(t) }

# Folded/block headers. MUST precede the inline rule: `/^[[:space:]]*command:/` also
# matches `command: >-` and would print the literal indicator, which then self-rejects
# against Step 10.5's shell-active `>` branch (#6772). The `(#.*)?$` tail is load-bearing —
# anchoring to a bare `$` makes `command: >- # note` fall through to inline and reproduce
# #6772 exactly.
/^[[:space:]]*command:[[:space:]]*>[-+]?[[:space:]]*(#.*)?$/  { mode = "fold";  key = indent($0); next }
/^[[:space:]]*command:[[:space:]]*\|[-+]?[[:space:]]*(#.*)?$/ { mode = "block"; key = indent($0); next }

# Inline.
/^[[:space:]]*command:/ { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; exit }

# Blank lines are legal inside a scalar and carry no indentation — skip before the
# terminator, or indent()==0 would end every scalar at the first blank line.
mode && /^[[:space:]]*$/ { next }

# Scalar ends at the first line indented <= the opening key. Covers sibling keys, parent
# keys, the closing ``` of the YAML fence, and column-0 prose in one rule.
mode && indent($0) <= key { exit }

# Continuations (reached only when indent > key).
mode == "fold"  { sub(/^[[:space:]]+/, ""); printf "%s%s", (n++ ? " " : ""), $0; next }
mode == "block" { sub(/^[[:space:]]+/, ""); print; next }

END { if (mode == "fold" && n) printf "\n" }
```

In `SKILL.md` Step 10.4, replace the inlined program and **hard-fail on a load error**
(F5 — a missing/unreadable script yields rc=2 + empty stdout, which `set -uo pipefail`
does not catch, so Form B would silently parse a different command):

```bash
FORM_A_AWK="$(git rev-parse --show-toplevel)/plugins/soleur/skills/preflight/scripts/parse-form-a.awk"
test -r "$FORM_A_AWK" || { echo "FAIL: Check 10 parser missing at $FORM_A_AWK"; exit 1; }
if ! CMD=$(awk -f "$FORM_A_AWK" "$PREFLIGHT_TMP/preflight-observability.txt"); then
  echo "FAIL: Check 10 Form A parser errored (awk rc=$?); refusing to fall through to Form B."
  exit 1
fi
```

Path resolves via `git rev-parse --show-toplevel` (the form already used at
`plugins/soleur/skills/incident/test/redact-sentinel.test.sh`), **not**
`${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` — `CLAUDE_PLUGIN_ROOT` is unset in a plain session,
making that form CWD-relative.

In `SKILL.md` **Step 10.4**, add the credentialed-CLI reject immediately after the existing
`ssh` reject, whose form it mirrors (C1):

```bash
if [[ "$CMD" =~ (^|[[:space:]]|/)(doppler|gh|aws|supabase|stripe)([[:space:]]|$) ]]; then
  echo "FAIL: discoverability_test.command invokes a credentialed CLI (doppler/gh/aws/supabase/stripe); refusing to run. Check 10 executes with the operator's ambient file-backed CLI auth reachable (env -i does not scrub it — \$HOME is preserved). Use an unauthenticated probe, or see <AC15 issue> for the credentialed-probe design."
  exit 1
fi
```

Verified against the corpus: rejects all 4 flip commands; leaves `curl …`,
`bun test …`, and `bash <script>` probes untouched. The `/` alternative catches
`/usr/local/bin/gh`.

In `SKILL.md` **Step 10.5**, add newline to the reject set (F1):

```bash
if [[ "$CMD" =~ (\$\(|\`|\<\(|\>\(|\;|\&\&|\|\||\||\>|\<|\&|$'\n'|\$\{?[A-Za-z_]) ]]; then
```

**Scope of the newline reject (C2):** it closes block-mode command chaining only. The 4
folded flips join with a **space** and contain no shell-active token — verified to pass the
reject even with `\n` in the set. The credentialed-CLI reject above is what covers them;
AC11's flip enumeration is the residual control for whatever neither anticipates.

Update Step 10.4's Form A prose to name inline, block **and** folded shapes.

**Deliberate changes beyond the reported fold gap:**

1. **Block header widened** `\|` → `\|[-+]?[[:space:]]*(#.*)?$`. Behaviour-preserving for
   every corpus form; aligns bash with the TS mirror's anchored regex. B3 pins it.
2. **Indent terminator applied to `mode=="block"`** — fixes defect 2. Same rule line as the
   fold fix; splitting means a second PR editing the identical program with a guaranteed
   conflict, for zero incremental lines.
3. **Continuations require `indent > key`** — closes the F4 differential on both modes.
4. **Newline added to the Step 10.5 reject** — closes F1; bounds this PR's own fail-open
   contribution.

**Explicitly NOT changed** (rejected from draft 2): stripping indentation in block mode as
a *parity* concession. Block continuations are dedented here because the indent-relative
model requires it, not to match the mirror — the authoritative runtime is never bent to
match an acknowledged-buggy mirror.

### Phase 3 — Mirror in TypeScript + parity harness

`parseCommand()`: add the fold branch ahead of the inline match; widen the block header
(including the `(#.*)?$` tail); replace the multi-line branch with the same indent model
(`indent > key` continuation, `indent <= key` exit, blank-line skip); fold joins with `" "`
and no trailing separator. Align blank-line handling to the awk (awk drops them; TS
currently pushes `""`) — **bash wins** per the file header. Add `\n` to `SUBST_REJECT_RE`.

**Parity harness** — the guard that does not exist today:

- For every Form-A fixture, run `awk -f plugins/soleur/skills/preflight/scripts/parse-form-a.awk`
  via `Bun.spawn` and compare stdout (trailing newline trimmed) to `parseCommand(block)`.
- **State the surface per matrix row.** Some mutations are awk-side only (F4's join
  operator), some TS-side only (B3). A row that does not name its surface is untestable.
- **Restrict to Form-A inputs and assert the restriction (P3).** `parseCommand()` runs
  Form A *then falls back to Form B*; in bash those are two separate programs. Every
  harness fixture must contain a `command:` key and no competing fenced block.
- **Do not normalize away real differences.** Draft 2 normalized block indentation, which
  would have blinded the harness to the exact drift "bash wins" exists to arbitrate. The
  indent model makes both surfaces dedent identically, so no normalization is needed —
  assert byte equality.
- **Enumerate every known divergence explicitly**, so AC8 is not a tautology: inline quote
  stripping (TS strips, awk does not) **and** CRLF handling (TS splits on `/\r?\n/`, awk
  leaves an embedded `\r`). Assert each as a *known-difference expectation* so a change on
  either side reddens and forces a decision.
- Assert the interpreter (`awk --version` / `mawk` vs `gawk`) so a CI image swap surfaces
  as a named failure rather than a mystery diff.

### Phase 4 — GREEN + verification

`bash scripts/test-all.sh`, then §Mutation Verification and AC11's corpus re-parse
**including the reject-verdict delta**.

## Test Matrix

Every case names its **surface** and the concrete mutation that reddens it. A case with no
reachable such mutation pins nothing — see the reachability step in §Mutation Verification.

### Permissive — the fold parses

| # | Surface | Fixture | Assertion | Reddening mutation |
| --- | --- | --- | --- | --- |
| F1–F3 | both | Table-driven over `[">", ">-", ">+"]` × `["", " # trailing comment"]`, each + 2 continuations | parsed == space-joined single line; **`!== the indicator`** | Delete the fold rule → literal indicator. Narrowing `>[-+]?`→`>-` reddens the `>`/`>+` rows. **Removing `(#.*)?` from the header reddens the comment column** — that mutation is #6772 reproducing. |
| F4 | awk | `command: >-`, one continuation | parsed == that line, **no leading/trailing space** | Change the join to append (`"%s "`) → trailing space |
| F5 | both | fold whose continuation ends in a trailing `\` (F6) | parsed matches the documented escaped-space form; `.awk` header documents it | Silently "repair" the backslash → assertion fails |

### Restrictive — the fold does NOT over-consume

The half a parser-widening suite structurally forgets. Three of these came from review.

| # | Surface | Fixture | Assertion | Reddening mutation |
| --- | --- | --- | --- | --- |
| N1 | both | fold + sibling `  expected_output: "200"` at the **same** indent as `command:` | command lacks `expected_output`; `parseExpected` still returns `200` | Delete the terminator → key swallowed |
| N1b | both | fold + a **parent-level** key at indent **less** than `command:` | command lacks it | Change `<=` to `==` → the `<` half is unpinned (draft 2 asserted only the `=` half) |
| N5 | both | fold with a **deeper-indented** jq object filter (`'{matches: .a,` / `  host_present: .b}'`), modelled on the real corpus plan | command contains `host_present` | Reintroduce any key-regex terminator → truncates mid-jq |
| S1 | both | **less-indented non-key line** mid-scalar (`  touch /tmp/PWN` under a 4-indent `command:`) — the F4 security differential | command does **not** contain `touch` | Revert continuations to `/^[[:space:]]+[^[:space:]]/` → the line is consumed and executes |
| N3 | both | dedent to column 0, then **indented content resumes** | command stops at the dedent | Delete the terminator → the resumed indented content is appended. *(Draft 2's fixture used only a `## ` heading and column-0 prose — verified **byte-identical under mutation**, i.e. it pinned nothing. Column-0 lines match no continuation rule, so they are dropped whether or not the exit rule exists.)* |
| N6 | both | blank line **inside** a fold and inside a block | blank skipped, scalar continues | Delete the blank-line rule → `indent("")==0 <= key` ends the scalar at the blank |

### Non-shadowing — existing forms stay green

| # | Surface | Fixture | Assertion | Reddening mutation |
| --- | --- | --- | --- | --- |
| I1 | both | inline `command: curl -fsS https://x/health` | unchanged | Delete the inline rule → empty |
| B1 | both | `command: \|` + sibling `expected_output:` | command lacks `expected_output` (**defect 2 pin**) | Remove the terminator from block mode |
| B2 | both | `command: \|` + 2 continuations | joined with `\n`, **not** a space; both surfaces dedent | Swap the fold/block join operators |
| B3 | both | `command: \|-` **with continuation lines** | enters block mode on both surfaces | Revert the TS block regex to `/^\s*command:\s*\|\s*$/`. *(Draft 2's fixture had no continuations → empty on both surfaces → parity passed trivially.)* |
| E1 | both | `command: >-` with **no** continuations | returns empty (falls to Form B / FAIL state 3); **not** `">-"` | Make the fold branch emit the header |
| R1 | both | block scalar with a second line `touch /tmp/PWNED` (F1) | Step 10.5 **rejects** (newline is a shell-active token) | Remove `$'\n'` from the reject set → passes and executes |
| R2 | both | folded `command: >` resolving to `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 90m --grep X` (verbatim from a real flip plan) | Step 10.4 **rejects** as a credentialed CLI (C1) | Remove the credentialed-CLI reject → the command passes **both** rejects and executes with the operator's live Doppler token. This is the fail-open transition the fix creates. |
| R3 | both | `command: curl …`, `command: bun test …`, `command: bash <script>` | **not** rejected by the credentialed-CLI branch | Broaden the reject to a bare substring match (drop the `(^\|[[:space:]]\|/)` … `([[:space:]]\|$)` word boundaries) → false-rejects any command containing `gh` as a substring |

**Ordering note (honest scope):** the mutation "move the inline rule ahead of the fold
rule" reddens F1–F4 but **not** I1. I1 pins only that the inline path survives; F1–F4 pin
ordering. Stated so a future reader does not mistake I1 for ordering coverage.

### Parity

| # | Assertion | Reddening mutation |
| --- | --- | --- |
| P1 | For every Form-A fixture, `parse-form-a.awk` output == `parseCommand()` output, **byte-exact** (no normalization) | Apply the fix to only one surface |
| P2 | Known divergences (inline quote stripping, CRLF) asserted **as known differences** | Silently omit them → AC8 becomes a tautology |
| P3 | Every harness fixture has a `command:` key and no competing fenced block | Add a Form-B-only fixture → constraint assertion reddens instead of a spurious parity failure |

## Mutation Verification

**Phase 1's RED-first run is the primary non-vacuity evidence** and covers every case
failing before the fix (F1–F3, F4, N1, N1b, N5, S1, N6, B1, R1, P1). Recording its output
is mandatory; re-deriving it with a sandbox protocol is redundant work.

The sandbox protocol applies to the cases RED-first **cannot** cover — already green before
the fix, where only a deliberate mutation proves they pin anything: **I1, N3, B2, B3, E1,
F5, P2, P3.**

1. `cp` the `.awk` and `discoverability-test-parser.ts` into a scratch sandbox, plus a
   second pristine backup.
2. Apply exactly one mutation from the matrix.
3. **Prove the mutation landed**: `diff <pristine> <mutated>` non-empty, hunk contains the
   intended change. A mutation that silently no-ops yields a green suite that looks like a
   passing verification.
4. **Prove the mutation is reachable** — run the mutated parser against the case's fixture
   and confirm the **output differs** from baseline. *A mutation that lands and still
   produces byte-identical output invalidates the fixture, not the protocol.* Draft 2 had
   two such dead mutations (N2, N3); step 3 alone cannot catch them. This step is the one
   that would have.
5. Run the suite; confirm the **named** case reddens (assert on the specific test name — an
   unrelated failure is not evidence).
6. Restore; confirm green.

Record the table (case → mutation → landed-diff → output-delta → failing test name) in the
PR body alongside the Phase 1 RED output.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `plugins/soleur/skills/preflight/scripts/parse-form-a.awk` exists; its fold
      rule precedes its inline rule, verified by **first-match** capture (a later comment
      mentioning the pattern must not flip the result).
- [ ] **AC2** — Fold header accepts `>`, `>-`, `>+` **and** a trailing comment, on both
      surfaces. Assert behaviourally via F1–F3, not by grepping for a literal regex string
      (an equivalent rewrite like `>[+-]?` must not fail the AC).
- [ ] **AC3** — F1–F5 green: all three indicators, with and without a trailing comment,
      parse to the space-joined form with no trailing space.
- [ ] **AC4** — N1 **and N1b** green: the scalar ends at a sibling key **and** at a
      less-indented parent key (both halves of `<=`); `parseExpected()` still returns `200`.
- [ ] **AC5** — N5 **and S1** green: a deeper-indented `key: value` inside the command does
      **not** truncate it, **and** a less-indented non-key line is **not** consumed. S1 is
      the security differential — it must be red before the fix.
- [ ] **AC6** — B1 green: `command: |` no longer swallows the sibling key (defect 2).
- [ ] **AC7** — I1, B2, B3, N3, N6, E1 green: inline/block otherwise unchanged; block joins
      with `\n`, fold with `" "`; blank lines skipped; both stop at the fence close.
- [ ] **AC8** — Parity harness passes: byte-exact agreement on every Form-A fixture, with
      known divergences asserted **as known** (P2) and the Form-A restriction asserted (P3).
- [ ] **AC9** — PR body records the Phase 1 RED output **and** the sandbox mutation table
      for the eight already-green pins, including the **step-4 reachability** column.
- [ ] **AC10** — `bash scripts/test-all.sh` green (repo `package.json` `scripts.test`).
      Do **not** substitute a bare `bun test` — see §Sharp Edges.
- [ ] **AC11** — **Corpus re-parse with reject-verdict delta (the gating criterion).** Run
      the old and new parsers over the `## Observability` block of every non-archive plan
      matching `^[[:space:]]*command:[[:space:]]*[>|]`. For each, report: parsed command
      (old, new), and the **Step 10.5 reject verdict before and after**. Assert every new
      parse is non-empty, is not a bare indicator, and contains no `expected_output`.
      **Enumerate every plan whose verdict flips REJECT → EXEC and require explicit
      reviewer sign-off on that list in the PR body.** Baseline measured 2026-07-21: **4
      flips, all `doppler run -p soleur -c prd_terraform`.** A flip count above baseline
      without sign-off blocks merge. Also report the true unblock count (F7).
- [ ] **AC12** — Two tracking issues filed: (a) flow-mapping shape
      `discoverability_test: { command: … }`; (b) inline quote-stripping divergence.
      *(The credentialed-CLI reject was item (c) in the draft; folded into this PR per CPO
      condition C1 — see AC14.)*
- [ ] **AC13** — R1 green: a block scalar carrying a second command line is **rejected** by
      Step 10.5 (newline in the reject set). Red before the fix — verified today that such
      a payload passes and executes.
- [ ] **AC14** — **Credentialed-CLI reject lands in this PR** (CPO condition C1). R2 green:
      every one of the 4 flip commands is rejected at Step 10.4 with the credentialed-CLI
      diagnostic. R3 green: `curl`/`bun test`/`bash <script>` probes are **not** rejected.
      AC11's flip enumeration must show **0 plans reaching execution with a credentialed
      CLI** after the fix.
- [ ] **AC15** — Phase 4 roadmap issue filed for the ambient-credential architecture (CPO
      condition C3, CPO Finding 4): *Check 10 should not require ambient operator
      credentials to prove a liveness signal is real.* Mark it a CTO architecture decision —
      whether the answer is a minted short-lived read-only credential per probe, or
      shape-verification instead of execution, is a spec-time call. Filed against Phase 4
      (Validate + Scale), **separate** from AC12's parser-scope trackers, because the
      exposure compounds as plan authorship extends beyond the operator.

### Post-merge (operator)

None. Every step is automatable in-session via Bash + the repo test runner.

## Workaround Revert

The issue notes a workaround applied at discovery — rewriting the command onto a single
long line — and asks whether it is still present.

**Searched and not found.** `git log --since=21.days -S'command: >-' -- knowledge-base/project/plans/`
returns four commits, none collapsing a folded scalar; a diff scan for removed
`-  command: >` lines returns nothing. **There is nothing to revert.** Recorded explicitly
so a future reader does not re-run the search.

The ~17 folded-form plans need **no** edit — they are correct YAML; the parser was wrong.
AC11 verifies they parse correctly rather than changing them.

## Observability

```yaml
liveness_signal:
  what: >-
    preflight Check 10 parses discoverability_test.command from all three YAML
    scalar shapes (inline, block, folded) and reaches an execution verdict rather
    than self-rejecting at the shell-active-token gate
  cadence: every /soleur:preflight run on a sensitive-path diff
  alert_target: the preflight run itself (fail-closed; FAIL aborts the pipeline)
  configured_in: plugins/soleur/skills/preflight/scripts/parse-form-a.awk (called from SKILL.md Step 10.4)
error_reporting:
  destination: preflight stdout diagnostic + non-zero exit (headless aborts the pipeline)
  fail_loud: true
failure_modes:
  - mode: fold rule shadowed by the inline rule (regression of #6772)
    detection: fixtures F1-F5 in preflight-discoverability-test.test.ts
    alert_route: CI test failure on the PR
  - mode: scalar over-consumes (swallows a sibling key) or under-consumes (truncates on
      an https:// or deeper-indented key inside the command)
    detection: fixtures N1, N1b, N5, N3, N6, B1
    alert_route: CI test failure on the PR
  - mode: parser differential — a less-indented line a reviewer reads as outside the
      command is executed anyway
    detection: fixture S1
    alert_route: CI test failure on the PR
  - mode: parser script missing or unreadable at runtime, silently falling through to
      Form B and parsing a different command
    detection: Step 10.4 test -r guard + awk rc check (hard FAIL, no fallthrough)
    alert_route: preflight FAIL on the run itself
  - mode: awk and TS mirror drift apart
    detection: parity harness P1/P2/P3 (executes the production .awk directly)
    alert_route: CI test failure on the PR
logs:
  where: preflight run output (stdout); no persisted log — the check is synchronous
  retention: CI run retention (90 days)
discoverability_test:
  command: bun test plugins/soleur/test/preflight-discoverability-test.test.ts
  expected_output: "0 fail"
```

**Note on this block's own form:** `command:` above is deliberately **inline**.
`plugins/soleur/skills/**` and `plugins/soleur/test/**` are absent from
`SENSITIVE_PATH_RE` (verified at `SKILL.md:477`), so Check 10 SKIPs on this PR and a folded
form would not self-block — but an inline command removes the dependency entirely and
avoids a plan that can only be validated by the fix it proposes. The `what:` field uses
`>-` freely; only `command:` is affected by the defect.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| The terminator truncates legitimate command content | Draft 1 (`[a-z_]+:`) and draft 2 (colon-plus-space) both did. The final design uses **no key regex** — pure YAML indent semantics. N5 pins the jq case that broke draft 2; N1/N1b pin both halves of `<=`. |
| A less-indented line reads as outside the command but executes | `indent > key` on continuations. S1 pins it; verified exploitable before the fix. |
| Defect 2's fix flips corpus plans from fail-closed to executing | **Real and measured: 4 flips, all `doppler run -c prd_terraform`.** Bounded by (a) the **credentialed-CLI reject at Step 10.4** (AC14, R2) — the load-bearing control, which rejects all 4 — and (b) AC11's reject-verdict delta requiring explicit sign-off on the flip list, as the residual control for a class neither reject anticipates. Threshold raised to `single-user incident`; `user-impact-reviewer` runs at review. **The draft cited `\n` as bound (a); that was false** — see the next row. |
| Newline chaining in block mode | `\n` added to the Step 10.5 reject set (R1). Pre-existing, but this plan widens what reaches the reject, so it is fixed here. **Scope (C2): this covers block-mode chaining ONLY and contributes zero coverage to the 4 folded flips**, which join with a space and carry no shell-active token — verified to pass the reject even with `\n` in the set. Do not cite it as a mitigation for the flip class. |
| Extracting the awk introduces a load-failure path | `test -r` guard + hard-fail on awk rc≠0 — **no fallthrough to Form B**. Path via `git rev-parse --show-toplevel`, not `CLAUDE_PLUGIN_ROOT` (unset in a plain session). |
| Widening the block header regresses an existing plan | Zero corpus usage of `\|-`/`\|+`; all bare `command: \|` plans still enter block mode. AC11 re-parses the whole corpus. |
| Parity harness passes vacuously | P3 asserts Form-A-only fixtures; P2 asserts known divergences as known; byte-exact comparison with no normalization. |
| Fixing only one surface | Phase ordering (awk → TS → parity) + AC8. |
| Fold + trailing `\` silently mangles the command | Documented in the `.awk` header; F5 pins the behaviour; the note recommends block (`\|`) for such commands. |

## Sharp Edges

- **`bunfig.toml` `pathIgnorePatterns`.** Root sets `[".worktrees/**", "apps/web-platform/**"]`.
  Work happens inside `.worktrees/feat-one-shot-6772-…/`, but paths resolve relative to the
  worktree root, so `plugins/soleur/test/**` is collected normally. Run the suite **from the
  worktree root**; invoking `bun test` from the bare repo against a `.worktrees/…` path
  silently matches zero files and reports success.
- **`scripts.test` is `bash scripts/test-all.sh`.** AC10 must use it — orphan suites that
  only the full-suite exit gate exercises are exactly the class this change could break.
- **Rule order is the whole bug.** Any edit reordering `parse-form-a.awk` can silently
  reintroduce #6772 — the inline rule matches every `command:` line. AC1 and F1–F3 are the
  pins; do not remove them when refactoring.
- **Anchoring the header regex is a bug generator.** A bare `$` anchor made
  `command: >- # note` reproduce #6772 exactly. Any future tightening of the header must
  keep a comment-tolerant tail and re-run the F1–F3 comment column.
- **`mode &&` is safe, but not for the obvious reason.** `mode` is uninitialized (`""` →
  falsy) and only ever assigned the string literals `"fold"`/`"block"` (truthy). awk's
  strnum rule would make a `"0"` *read from input* falsy — a string literal is exempt. Do
  not "simplify" this into a comparison against an input-derived value.
- **`indent()` on a blank line returns 0**, which is `<= key` for every scalar. The
  blank-line skip rule must stay **above** the terminator or every scalar ends at its first
  blank line (N6).
- **`env -i` does not scrub file-backed CLI auth.** Step 10.5 preserves `HOME`, so the
  Doppler CLI's `~/.doppler/` token remains reachable by any command Check 10
  executes. Do not cite `env -i` as a mitigation for credential-bearing commands.
- **The shell-active reject does not bound a space-joined fold.** Folding produces a single
  line with no `;`/`|`/`$()`, so a folded scalar passes the Step 10.5 reject by
  construction — it can only append *arguments*, never chain a command. That makes fold
  strictly safer than block for injection, but it also means **no token in the Step 10.5
  set constrains what a folded command *is***. Only Step 10.4's verb rejects (`ssh`,
  credentialed CLIs) do. A future reviewer reasoning "the reject will catch it" about a
  folded command is reasoning about the wrong gate — this is the exact error CPO caught in
  the draft.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.**
