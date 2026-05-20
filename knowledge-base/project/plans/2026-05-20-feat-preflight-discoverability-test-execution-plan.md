---
date: 2026-05-20
type: feature
issue: 4162
branch: feat-one-shot-4162-preflight-discoverability-test
lane: single-domain
requires_cpo_signoff: false
---

# Plan — Execute `discoverability_test.command` at Ship Time (Preflight Check 10)

## Overview

Add **Check 10** to `plugins/soleur/skills/preflight/SKILL.md` that EXECUTES the
`discoverability_test.command` declared in the plan body's `## Observability`
section instead of only verifying that the field exists. Close the
"declared-but-unverified" hole in `hr-observability-as-plan-quality-gate`.

Path-gated on the canonical sensitive-path regex (Check 6 SSOT). Re-uses Check
6's plan-file resolution. Result matches the 7-row matrix in issue #4162.
Invariant gate per `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`:
SKIP only when truly indeterminate; FAIL when the invariant is contradicted
(typo'd hostname → DNS failure → FAIL; missing `discoverability_test.command`
on a sensitive-path diff → FAIL).

## Problem

`hr-observability-as-plan-quality-gate` (plan Phase 2.9 + deepen-plan Phase 4.7)
mandates a `discoverability_test.command` that runs WITHOUT SSH. Both gates are
**static** — they verify the field is present and non-placeholder, but neither
executes the command. PR #4148 shipped a plan whose Observability block declared:

```yaml
discoverability_test:
  command: |
    curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 \
      https://web-platform.soleur.ai/api/inngest
  expected: 200 or 401
```

The hostname `web-platform.soleur.ai` does not resolve. The real prod hostname
is `app.soleur.ai` (`apps/web-platform/infra/variables.tf` `app_subdomain`
default). The typo was inherited verbatim from issue #4118's body and flowed
through **five gates** (plan → deepen-plan → work → review → ship) plus the
PR body, the committed runbook, and post-merge operator instructions — caught
only when the operator hit DNS failure live. Fix landed in #4159; runbook on
`main` carried the wrong hostname until then.

Pattern class: **a fact copied verbatim from an issue body becomes binding once
it lands in a plan/spec/runbook — even when the fact is a bare URL that takes
5 ms of `curl` to falsify.** Static gates produce *declared-verifiable*, which
is strictly worse than no declaration because they generate false confidence.

## User-Brand Impact

- **If this lands broken, the user experiences:** A future Soleur self-host
  user reads the PR-body operator step (or the committed runbook) and hits DNS
  failure. They assume the service is broken when only the documented hostname
  is wrong. Brand-cost: "the runbook is misleading on the very first command."
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A —
  this is an availability/integrity defect in operator-facing documentation,
  not a confidentiality vector. No regulated data is read or written by the
  proposed check; `curl` is a one-shot HTTP probe against the same endpoints
  operators run by hand today.
- **Brand-survival threshold:** `aggregate pattern` — a single wrong runbook
  is recoverable; the systemic class (declared-verifiable ops that nobody
  executes) is the brand-survival concern. Same threshold as #4148's parent
  framing: availability defects → aggregate pattern unless tied to a
  single-user data event.

## Hypotheses

(Not applicable — this is a code-change feature with a known root cause, not a
debugging task. No network-outage trigger pattern fires.)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** 8 (citation-verification, bash-prescription validation, regex correctness, fixture grounding, AC sharpening, sharp-edge expansion, line-number verification, plan-fixture vs live-DNS sanity)

### Key Improvements

1. **Every cited PR/issue verified live via `gh` CLI** (#4148 MERGED, #4118 CLOSED, #4159 OPEN, #4116 CLOSED, #4117 CLOSED, #4066 MERGED, #4123 MERGED, #2887/#2903 verified, #4085 MERGED, #3488/#3010 verified — see Research Insights table).
2. **SSOT regex byte-equality empirically confirmed** between `preflight/SKILL.md:398` and `deepen-plan/SKILL.md:348` — the only difference is leading whitespace from the markdown context. AC2's grep pattern (`grep -cF "SENSITIVE_PATH_RE='^(apps/web-platform"`) tolerates both contexts.
3. **Prescribed bash patterns validated empirically** — `DT_OUT=$(timeout 15s bash -c "$CMD"; printf 'RC:%d' "$?")` correctly captures rc=0/6/124 and multi-line stdout. Trailing-newline trap identified and folded into Sharp Edges.
4. **Reject-regex pair validated empirically** — `(^|[[:space:]]|/)ssh([[:space:]]|$)` correctly rejects `ssh user@host` and `/usr/bin/ssh foo`, lets `ssh-free.md` and `xssh` through; substitution-token reject `(\$\(|\`|\<\(|\>\()` correctly catches `$(...)`, backticks, process subs.
5. **Hostname canon confirmed** — `apps/web-platform/infra/variables.tf:88 default = "app.soleur.ai"`. `dig +short web-platform.soleur.ai` returns empty; `dig +short app.soleur.ai` returns `172.67.188.7`/`104.21.7.210`. The #4148 typo is mechanically detectable.
6. **PR #4148 plan-as-merged available at `f2b2f959` on `main`** — fixture `04-dns-fail.md` can snapshot the Observability block directly via `git show f2b2f959:knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md`.
7. **AC12 grep corrected** — `\b` is a word-boundary, not a space-anchor; original AC12 would have missed trailing-space `ssh ` tokens in prose. Replaced with the canonical `(^|[[:space:]])ssh([[:space:]]|$)` form mirroring Check 10's reject regex.
8. **Phase 1 "six checks" sentence drift confirmed live** — line 61 of `preflight/SKILL.md` reads "Run these six checks ..." but the file has 9 checks today. Count-free rewrite is the cheapest fix; flagged in Files-to-Edit.

### New Considerations Discovered

- **Stdout always carries a trailing newline** from `bash -c`. The matcher MUST normalize before substring comparison or `expected_output: 200` will fail when stdout is `200\n`.
- **AC2 currently returns 1 hit** on `main` (Check 6 only); after the work phase adds Check 10 it must return ≥2. This is the regression-test contract for the SSOT mirror.
- **`grep -cF` on the SSOT pattern tolerates the 2-space indentation difference** between `preflight/SKILL.md` (top-level) and `deepen-plan/SKILL.md` (inside a markdown bullet). Verified empirically.
- **Form B parsing reality** — confirmed PR #4148 uses prose `Expected output:` at line 179 of the merged plan; the canonical schema (template line 62) uses YAML key `expected_output:`. Both must be accepted.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Re-use Check 6's plan-file resolution logic" | Verified: `preflight/SKILL.md:422-448` (Step 6.3) implements exactly this: scrub PR body of HTML comments and fenced code blocks, then extract `knowledge-base/project/plans/[^[:space:])"`]+\.md` and load it. | Lift Step 6.3a–6.3c verbatim into a shared subsection ("Shared plan-file resolution"); have Check 6 and Check 10 both call it. Avoid copy-paste drift. |
| "Path-gated on the canonical sensitive-path regex" | Verified: SSOT lives at `preflight/SKILL.md:398` (Check 6 Step 6.1) AND `deepen-plan/SKILL.md:348` (Phase 4.6 Step 2). Mirroring rule documented in both. | Check 10 re-uses the same regex literal AND adds a third sync-pointer comment so the SSOT triplet does not drift. |
| "Result matrix matches the 7-row table" | The issue body's matrix has **8 logical rows** (no plan / no Observability block / no command / DNS fail / timeout / mismatched output / expected output / auth-gated) but lists 7 prose rows by collapsing "expected output" PASS into "command returns expected" PASS. | Implement as 8 numbered states with one PASS terminal — matches issue intent. |
| "Plan declares `expected:` value" (issue body) | The canonical schema (`plan-issue-templates.md:62`) uses `expected_output:` as the YAML key. PR #4148's plan used the prose form `Expected output: 200 (or 401 ...)` after a fenced code block, NOT a YAML key. | Parser must accept BOTH: `expected_output:` (canonical key) AND `expected:` (looser prose form). Document explicit precedence; surface an Observability-template harmonization follow-up issue if drift is non-trivial. |
| "Backfill regression test against PR #4148's plan-as-merged" | The plan file at `knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` is on `main` (commit `f2b2f959`) with the typo at lines 177, 379, and 237. | Snapshot the relevant Observability block into a fixture file under `plugins/soleur/test/fixtures/preflight-check-10/`. The fixture is the test input; the live plan file is NOT read during tests (tests must not depend on `main` history). |
| "Check 6 covers `wg-block-pr-ready-on-undeferred-operator-steps`" overlap (out-of-scope per issue) | Confirmed: `ship/SKILL.md` Phase 5.5 covers the undeferred-operator-step gate (`ship-undeferred-operator-step-gate.test.ts`). That gate catches "operator runs <thing>" without `(Tracks|Refs) #NNNN`; Check 10 catches "<thing>" being syntactically wrong/unreachable. Different defect class — no overlap. | Acknowledge in Out-of-Scope (issue already deferred this investigation). |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "plugins/soleur/skills/preflight/SKILL.md" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
jq -r --arg path "plugins/soleur/test/" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

**Result:** _Run during /work Phase 0 — record results here before Phase 1
begins. If non-empty, classify each match as Fold-in / Acknowledge / Defer per
plan-skill Phase 1.7.5._

## Implementation Phases

### Phase 0: Preconditions (before any edit)

1. **Verify the cached path-set helper exists.** `grep -n 'PREFLIGHT_TMP' plugins/soleur/skills/preflight/SKILL.md` — Check 10 must use the same Phase 0 Step 0.1 cache as Checks 1, 2, 5, 6, 7, 8.
2. **Verify the canonical sensitive-path regex literal.** Read `preflight/SKILL.md:398` and `deepen-plan/SKILL.md:348` — both literals MUST be byte-identical. If they have drifted (untracked PR landed), file a follow-up and fix on this branch.
3. **Verify Check 6 Step 6.3 plan-file resolution.** Read `preflight/SKILL.md:422-448`. Confirm: (a) `awk` strips fenced code blocks, (b) `perl -0777` strips HTML comments, (c) the plan-path grep pattern is `knowledge-base/project/plans/[^[:space:])"`]+\.md`. These are the exact behaviors Check 10 will reuse.
4. **Run live preflight against `feat-one-shot-4162-preflight-discoverability-test` once** (`/soleur:preflight --headless` OR the equivalent bash sequence) to capture baseline PASS/SKIP profile BEFORE adding Check 10. Record results in `session-state.md`.
5. **Live-falsify the typo'd hostname** so the regression-test fixture's expectation is empirically grounded: `dig +short web-platform.soleur.ai` (expect: empty); `dig +short app.soleur.ai` (expect: non-empty IP); `curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/api/inngest` (expect: 200 or 401). Document the three outputs in `session-state.md`.

### Phase 1: Refactor Check 6 Step 6.3 into a Shared Subsection

Hoist Step 6.3 (the plan-file resolution that builds `$COMBINED`) out of Check
6 into a new sub-section at the top of Phase 1 called **"Shared Plan-File
Resolution (used by Checks 6 + 10)"**. Check 6 calls it; Check 10 calls it.

**Files to Edit:**

1. `plugins/soleur/skills/preflight/SKILL.md`
   - Insert new sub-section `### Shared Plan-File Resolution` BEFORE Check 1
     (right after the "Phase 1: Run All Checks in Parallel" heading + the
     `Assertion: Not-Bare-Repo` block).
   - The sub-section MUST emit a single output `$COMBINED` (mktemp path),
     trap-cleaned, containing scrubbed PR body + (if a plan link is present)
     scrubbed plan file.
   - Edit Check 6 Step 6.3 to read: "Call **Shared Plan-File Resolution**
     (above). `$COMBINED` is the input to Step 6.4." — delete the duplicated
     awk/perl/grep blocks from Check 6.
   - Sync-pointer comment in the shared block: `# SSOT for plan-file
     resolution. Mirrored consumers: Check 6 Step 6.4, Check 10 Step 10.3.`

**Why hoist first?** If Check 10's prose copies-and-pastes Step 6.3, the next
maintainer who edits Check 6 alone will silently desync Check 10. The hoist is
the DRY move the issue acceptance criterion already calls for.

### Phase 2: Add Check 10 (Discoverability Test Execution)

**Files to Edit:**

1. `plugins/soleur/skills/preflight/SKILL.md`
   - Insert `### Check 10: Discoverability Test Execution` AFTER Check 9 (line
     ~601, BEFORE the existing `### Check 7` block that sits at end-of-file by
     historical insertion order). Numerical name `Check 10` is correct — the
     existing file already has Check 7 placed after Check 9, so the
     non-monotonic file order is precedent.
   - Body follows the structure below (see §"Check 10 Body" in this plan).

2. `plugins/soleur/skills/preflight/SKILL.md` — fast-path SKIP table (line ~44)
   - Add row: `| 10 (Discoverability test) | Zero matches for the canonical sensitive-path regex (re-use Check 6 SSOT). |`

3. `plugins/soleur/skills/preflight/SKILL.md` — aggregate Phase 2 table
   (line ~647)
   - Add row: `| Discoverability Test Execution | PASS/FAIL/SKIP | <details> |`

4. `plugins/soleur/skills/preflight/SKILL.md` — Phase 1 opening sentence
   (line ~61: "Run these six checks ...")
   - Update count phrase. Current count is wrong already (the file has 9
     checks, not 6); silently extending "six" to "seven" by adding Check 10
     would compound the drift. Replace with a count-free phrasing: "Run all
     checks below (plus the Not-Bare-Repo assertion) as parallel Bash tool
     calls." File a tracker if the count phrase has further drift sources.

#### Check 10 Body

```markdown
### Check 10: Discoverability Test Execution

**Path-gated** on the canonical sensitive-path regex (single source of truth;
re-use Check 6 Step 6.1's `SENSITIVE_PATH_RE`). The path predicate runs against
`"$PREFLIGHT_TMP/preflight-diff-files.txt"` (cached in Phase 0 Step 0.1).
Otherwise return **SKIP** with note: "No sensitive paths touched — no
Observability block required."

**Rationale:** `hr-observability-as-plan-quality-gate` mandates a
`discoverability_test.command` that runs WITHOUT SSH. Plan Phase 2.9 and
deepen-plan Phase 4.7 enforce field presence; neither executes the command.
PR #4148 shipped with `curl https://web-platform.soleur.ai/api/inngest` — a
typo'd hostname that fails DNS resolution. Five gates passed; the operator
caught it. This check closes the "declared-verifiable but unverified" gap.

Invariant gate per `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`:
SKIP only when truly indeterminate; FAIL when the invariant
("the documented command actually works against the live world") is
contradicted.

**Step 10.1: Sensitive-path gate (re-use Check 6 SSOT).**

```bash
set -uo pipefail
# SSOT: see Check 6 Step 6.1; this literal MUST stay byte-identical.
SENSITIVE_PATH_RE='^(apps/web-platform/(server|supabase|app/api|middleware\.ts$)|apps/web-platform/lib/(stripe|auth|byok|security-headers|csp|log-sanitize|safe-session|safe-return-to|supabase)|apps/web-platform/lib/(legal|auth)/|apps/[^/]+/infra/|.+/doppler[^/]*\.(yml|yaml|sh)$|\.github/workflows/.*(doppler|secret|token|deploy|release|version-bump|web-platform|infra-validation|cla|cf-token|linkedin-token).*\.ya?ml$)'
grep -E "$SENSITIVE_PATH_RE" "$PREFLIGHT_TMP/preflight-diff-files.txt"
```

If `grep` exits non-zero, return **SKIP** with note: "No sensitive paths
touched."

**Step 10.2: Resolve the plan file (Shared Plan-File Resolution).**

Call **Shared Plan-File Resolution** (above Check 1). The output `$COMBINED`
contains the scrubbed PR body concatenated with the scrubbed plan file (when
a `knowledge-base/project/plans/*.md` link is present in the PR body).

If `$COMBINED` is empty (no PR available — `gh pr view` failed), return
**SKIP** with note: "No PR available — Check 10 deferred to next preflight
run after PR creation."

`$PLAN_PATH` is set by Shared Plan-File Resolution; if empty (sensitive-path
diff but no plan link in PR body), return **SKIP** with note: "Sensitive-path
diff but no plan file referenced from PR body. Cannot extract
discoverability_test.command. (If the PR uses inline Observability in the PR
body, copy the plan file into the body via a `knowledge-base/project/plans/`
link.)"

**Step 10.3: Extract the `## Observability` block from the plan file.**

```bash
# Extract everything between `^## Observability` and the next `^## ` heading.
awk '/^## Observability/{in=1; next} /^## /{if (in) exit} in' "$PLAN_PATH" > /tmp/preflight-observability.txt
test -s /tmp/preflight-observability.txt || { echo "FAIL: Plan touches sensitive paths but `## Observability` block is missing. See hr-observability-as-plan-quality-gate."; exit 1; }
```

If the block is missing, return **FAIL** with: "Sensitive-path diff but plan
file `<PLAN_PATH>` is missing the `## Observability` block. See
`hr-observability-as-plan-quality-gate`. Add the section per
`plugins/soleur/skills/plan/references/plan-issue-templates.md`."

**Step 10.4: Extract `discoverability_test.command` and `expected_output`.**

The plan-template schema (`plan-issue-templates.md:60-62`) defines:

```yaml
discoverability_test:
  command:         # one command an operator can run LOCALLY (no ssh)
  expected_output: # canonical "everything OK" output
```

In practice, plans use TWO shapes — strict YAML AND looser prose with a fenced
code block followed by "Expected output: …" (PR #4148 uses the latter). The
parser MUST accept both forms.

**Form A — strict YAML (canonical):**

```yaml
discoverability_test:
  command: curl -fsS ... https://app.soleur.ai/api/inngest
  expected_output: "200"
```

Detection: `awk '/^[[:space:]]*command:/'` returns the value on the same line
after the colon, OR the next non-blank line if the value is a YAML `|`
block-scalar.

**Form B — prose + fenced block (PR #4148 shape):**

```markdown
- **discoverability_test.command:**
  ```bash
  curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/api/inngest
  ```
  Expected output: `200` (or `401` with HMAC challenge). Anything else = absent.
```

Detection: find the first `discoverability_test` line in the Observability
block; from that point, locate the first fenced code block (``` … ```) — its
contents are the command. Then locate the first line matching
`^[[:space:]]*Expected output:` (case-insensitive) — its value is the
expected.

Parser pseudo-code (will be implemented as bash in the SKILL.md):

```bash
# Form A first (anchored YAML key — strongest signal).
CMD=$(awk '
  /^[[:space:]]*command:[[:space:]]*\|/  { mode="block"; next }
  /^[[:space:]]*command:/                { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; exit }
  mode=="block" && /^[[:space:]]+[^[:space:]]/ { print; next }
  mode=="block" && /^[[:space:]]*[^[:space:]]/ { exit }
' /tmp/preflight-observability.txt)

EXPECTED=$(awk '
  /^[[:space:]]*expected_output:/ { sub(/^[[:space:]]*expected_output:[[:space:]]*/, ""); print; exit }
' /tmp/preflight-observability.txt)

# Fallback to Form B (fenced block under `discoverability_test.command:` prose).
if [[ -z "$CMD" ]]; then
  CMD=$(awk '
    /discoverability_test/ { found=1 }
    found && /^[[:space:]]*```/ { fence=!fence; if (!fence && lines>0) exit; next }
    found && fence { print; lines++ }
  ' /tmp/preflight-observability.txt)
fi

if [[ -z "$EXPECTED" ]]; then
  EXPECTED=$(grep -iE '^[[:space:]]*Expected output:' /tmp/preflight-observability.txt | head -1 | sed -E 's/^[[:space:]]*Expected output:[[:space:]]*//I')
fi
```

If `$CMD` is empty after both attempts, return **FAIL** with: "Plan
`<PLAN_PATH>` declares an Observability block but no
`discoverability_test.command` could be parsed. See
`plugins/soleur/skills/plan/references/plan-issue-templates.md` §Observability
for the canonical YAML schema."

**Reject SSH commands** (defense-in-depth; deepen-plan Phase 4.7 already
rejects, but Check 10 must FAIL if drift slips through):

```bash
if [[ "$CMD" =~ (^|[[:space:]]|/)ssh([[:space:]]|$) ]]; then
  echo "FAIL: discoverability_test.command contains ssh; rule violation per hr-observability-as-plan-quality-gate."
  exit 1
fi
```

**Step 10.5: Sanitize and execute with a tight timeout.**

```bash
# Defense-in-depth: reject command-substitution and process-substitution
# tokens before exec (the command came from a trusted plan file but
# defense-in-depth costs nothing).
if [[ "$CMD" =~ (\$\(|\`|\<\(|\>\() ]]; then
  echo "FAIL: discoverability_test.command contains command/process substitution; refusing to exec."
  exit 1
fi

# Execute with 15s wall-clock cap, capture stdout + exit code separately.
DT_OUT=$(timeout 15s bash -c "$CMD" 2>/dev/null; printf 'RC:%d' "$?")
DT_RC="${DT_OUT##*RC:}"
DT_STDOUT="${DT_OUT%RC:*}"

# Log-injection guard before any echo (re-use Check 5's sanitize() pattern).
sanitize() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'; }
DT_STDOUT_SAFE=$(sanitize "$DT_STDOUT")

# Trailing-newline normalization. `bash -c "echo 200"` returns "200\n"; the
# matcher must compare without the trailing newline or "200" never matches.
# (Sanitize() above STRIPS C0 controls 0x00-0x1f INCLUDING \n, so DT_STDOUT_SAFE
# is already newline-free — but document the dependency explicitly so a future
# sanitize() refactor that preserves \n does not silently break matching.)
```

The 15-second cap is a hard ceiling. Plans typically prescribe `curl --max-time
10`; the 15 s outer cap accommodates 10 s curl + 5 s DNS + handshake without
giving the curl invocation infinite headroom if it lacks `--max-time`.

**Step 10.6: Decision matrix (8 states, 1 PASS terminal).**

| # | State | Detection | Result | Rationale |
| --- | --- | --- | --- | --- |
| 1 | No PR linked plan file | `$PLAN_PATH` empty after Shared Plan-File Resolution | **SKIP** | Indeterminate — Check 6 will fire if a section is required; Check 10 cannot run without a plan file. |
| 2 | Plan exists, no `## Observability` block | `awk` returns empty in Step 10.3 | **FAIL** | Sensitive-path diff requires an Observability block per `hr-observability-as-plan-quality-gate`. |
| 3 | Block exists, no `discoverability_test.command` parsed | `$CMD` empty after both Form A + B attempts | **FAIL** | Rule violation — the load-bearing field of the schema is missing. |
| 4 | Command DNS-fails | `$DT_RC == 6` (curl: "Could not resolve host") | **FAIL** | The hostname-typo class — the exact #4148 regression. |
| 5 | Command times out | `$DT_RC == 28` (curl) OR `$DT_RC == 124` (timeout(1)) | **FAIL** | Endpoint unreachable; DNS resolved but no response in 15 s. |
| 6 | Command returns a code/output the plan's `expected_output` does NOT include | `$DT_STDOUT_SAFE` not present in `$EXPECTED` (substring OR list-member match) | **FAIL** | Plan's expectation drifted from production reality. |
| 7 | Command requires creds not in Doppler (auth-gated probe) | `$DT_RC == 22` AND HTTP 401/403 AND `$EXPECTED` does NOT explicitly list 401/403 | **SKIP** | Auth-gated probe with no operator creds; surface diagnostic suggesting to add a Doppler-fetched probe variant. |
| 8 | Command returns expected output | All other paths — `$DT_RC == 0` AND stdout matches `$EXPECTED` | **PASS** | Invariant proven by live execution. |

**Expected-output matching semantics.** When `$EXPECTED` is a comma-separated
or "or"-joined list (e.g., `200 or 401`, `200, 401`, `["200","401"]`),
tokenize on `,|or|\bor\b|[`"\[\]]+` and treat as a list. Match if any token
is a non-empty substring of `$DT_STDOUT_SAFE`. When `$EXPECTED` is a single
value, substring-match. The tokenizer accepts both `200` and `"200"` (the
canonical YAML scalar form).

**Step 10.7: Headless mode behaviour.**

On **FAIL**, abort with the diagnostic table (command, exit code, sanitized
stdout, expected). On **PASS** or **SKIP**, continue silently.

**Step 10.8: Interactive mode behaviour.**

On **FAIL**, present the failure reason + sanitized command + diagnostic and
offer **AskUserQuestion**:

1. "Fix the plan's `discoverability_test.command` now" — open the plan file at
   the line of the `discoverability_test:` key. Re-run Check 10.
2. "Skip — temporarily defer (logs a trim-tracker issue)" — `gh issue create
   --label 'priority/p3-low,chore'` with the failure as the body. Continue
   the preflight run with this check noted as DEFERRED. Records why operator
   chose to skip.
3. "Abort — fix elsewhere" — stop the pipeline.

**Result:**

- **PASS** — Sensitive-path diff with valid plan-linked Observability block
  AND command executed AND output matches `expected_output`.
- **FAIL** — Sensitive-path diff with any of: missing Observability block,
  missing `discoverability_test.command`, command requires SSH, command
  contains shell substitution, DNS failure, timeout, or output mismatch.
- **SKIP** — No sensitive paths touched, OR no PR available, OR no plan file
  linked from PR body, OR command is auth-gated with no operator creds.
```

### Phase 3: Tests

**Files to Create:**

1. `plugins/soleur/test/preflight-discoverability-test.test.ts`
   - Test harness: `bun:test` (matches every sibling preflight/skill-doc
     test).
   - Pattern: read `preflight/SKILL.md` once, extract Check 10 body via the
     `### Check 10` heading boundary, regex-assert the load-bearing
     invariants (SSOT regex literal byte-equal to Check 6, Phase 2 table row
     exists, fast-path table row exists, 8-state matrix exists, `ssh ` reject
     regex present, etc.).
   - **Behavior tests** for the parser + decision matrix:
     - Implement the parser pure-functions in TypeScript so they can be
       unit-tested (extractObservabilityBlock, parseCommand, parseExpected,
       matchExpected, classifyResult).
     - Each pure function MUST mirror the bash behavior exactly — the test
       file imports a small `lib/discoverability-test-parser.ts` that the
       SKILL.md prose links as the canonical reference implementation.
   - 8 test rows mapping to the 8 decision states (one fixture file per row;
     fixtures live under `plugins/soleur/test/fixtures/preflight-check-10/`).

2. `plugins/soleur/test/fixtures/preflight-check-10/01-no-plan-link.md` —
   PR body without a `knowledge-base/project/plans/*.md` reference.
3. `plugins/soleur/test/fixtures/preflight-check-10/02-no-observability-block.md` —
   plan file missing `## Observability`.
4. `plugins/soleur/test/fixtures/preflight-check-10/03-no-command-field.md` —
   Observability block present but `discoverability_test.command` empty.
5. `plugins/soleur/test/fixtures/preflight-check-10/04-dns-fail.md` — plan
   declares `curl https://web-platform.soleur.ai/api/inngest` (the #4148
   regression fixture, captured verbatim from the surfacing plan).
6. `plugins/soleur/test/fixtures/preflight-check-10/05-timeout.md` — plan
   declares `curl --max-time 1 https://10.255.255.1/` (RFC5737-ish
   unreachable; if flaky in CI, replace with a deterministic fake via
   `bash -c 'sleep 20'`).
7. `plugins/soleur/test/fixtures/preflight-check-10/06-mismatch.md` — plan
   declares `expected_output: 200` and the (mocked) command returns `404`.
8. `plugins/soleur/test/fixtures/preflight-check-10/07-auth-gated.md` — plan
   declares an authenticated probe (401 without creds); `expected_output`
   does NOT list 401.
9. `plugins/soleur/test/fixtures/preflight-check-10/08-pass.md` — plan
   declares `curl https://app.soleur.ai/api/inngest` returning 200/401.

**Mocking strategy.** Rows 4, 5, 6, 7, 8 need command execution. The TS test
MUST NOT actually `dig` or `curl` — that introduces non-determinism + network
dependence in CI. Implement the executor as a pure function with injected
exec stub:

```ts
type ExecResult = { rc: number; stdout: string };
type Executor = (cmd: string, timeoutMs: number) => Promise<ExecResult>;

function classifyDiscoverabilityResult(
  cmd: string,
  expected: string,
  exec: Executor,
): Promise<"PASS" | "FAIL" | "SKIP" | { result: "FAIL"; reason: string }>;
```

The tests inject a stub executor that returns canned `(rc, stdout)` tuples
per fixture. Real network calls happen ONLY in headless preflight runs
against a live PR — never in `bun test`.

**Regression test — PR #4148's plan-as-merged (issue AC explicit).**
Snapshot the Observability block from
`knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md`
(commit `f2b2f959`) into fixture `04-dns-fail.md`. The test asserts the
fixture contains the literal `web-platform.soleur.ai`, mocks the stub
executor to return `(rc=6, stdout="")` (the canonical curl DNS-failure
shape), and asserts `classifyDiscoverabilityResult` returns FAIL with reason
matching `/DNS|resolve|hostname/i`. This is the issue's explicit regression
contract.

### Phase 4: Documentation Sweep

**Files to Edit:**

1. `plugins/soleur/skills/preflight/SKILL.md` — Sharp Edges section (if
   present at file end; if absent, add one) gets a new bullet about the
   triple-SSOT (Check 6 / Check 10 / `deepen-plan` Phase 4.6) and the
   load-bearing requirement to keep the regex byte-identical.

2. `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md` — add a "Re-evaluation" footnote pointing at PR for this issue: "Preflight Check 10 partially answers the re-evaluation criterion (executable verification of the declaration). Full retirement deferred until a `discoverability_test:` block in `spec.md` frontmatter becomes the SSOT parsed by CI."

3. `knowledge-base/project/learnings/best-practices/2026-05-20-preflight-check-10-discoverability-test-execution.md` (new) — companion learning capturing: (a) the 5-gate bypass that motivated the check, (b) the typo'd-hostname pattern class, (c) the Form A vs Form B parser duality (canonical schema vs. PR #4148 prose-with-fence shape), (d) why this is an invariant gate (FAIL not SKIP on missing/typo), (e) cross-reference to `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`.

### Phase 5: Acceptance Validation

Run the full suite locally:

```bash
bun test plugins/soleur/test/preflight-discoverability-test.test.ts
bun test plugins/soleur/test/components.test.ts        # description budget
python3 scripts/lint-agents-rule-budget.py             # AGENTS budget unchanged
python3 scripts/lint-rule-ids.py                       # rule-id linter
grep -nE 'SENSITIVE_PATH_RE' plugins/soleur/skills/preflight/SKILL.md plugins/soleur/skills/deepen-plan/SKILL.md  # triple-SSOT verify
```

All MUST exit 0. Then run preflight live against the PR (after PR creation
in /ship Phase 0):

```bash
# In the worktree, after PR exists:
/soleur:preflight --headless
```

Expected: Check 10 PASS (this plan's own `## Observability` block declares a
working `discoverability_test.command`).

## Files to Edit

- `plugins/soleur/skills/preflight/SKILL.md` (insert Shared Plan-File
  Resolution sub-section, refactor Check 6 Step 6.3, insert Check 10, update
  Phase 1 count phrase, append fast-path SKIP row, append Phase 2 aggregate
  table row, Sharp Edges)
- `knowledge-base/project/learnings/best-practices/2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md`
  (Re-evaluation footnote)

## Files to Create

- `plugins/soleur/test/preflight-discoverability-test.test.ts`
- `plugins/soleur/test/fixtures/preflight-check-10/01-no-plan-link.md`
- `plugins/soleur/test/fixtures/preflight-check-10/02-no-observability-block.md`
- `plugins/soleur/test/fixtures/preflight-check-10/03-no-command-field.md`
- `plugins/soleur/test/fixtures/preflight-check-10/04-dns-fail.md`
- `plugins/soleur/test/fixtures/preflight-check-10/05-timeout.md`
- `plugins/soleur/test/fixtures/preflight-check-10/06-mismatch.md`
- `plugins/soleur/test/fixtures/preflight-check-10/07-auth-gated.md`
- `plugins/soleur/test/fixtures/preflight-check-10/08-pass.md`
- `plugins/soleur/test/lib/discoverability-test-parser.ts` (pure parser
  + classifier; the SKILL.md bash IS the production runtime, but the TS
  mirror is the canonical reference implementation for testing.)
- `knowledge-base/project/learnings/best-practices/2026-05-20-preflight-check-10-discoverability-test-execution.md`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `### Check 10: Discoverability Test Execution` exists in
  `plugins/soleur/skills/preflight/SKILL.md` between Check 9 and Check 7
  (file-order precedent).
- [ ] **AC2.** Check 10 re-uses Check 6 Step 6.1's `SENSITIVE_PATH_RE` literal
  byte-for-byte. Verify: `grep -cF "SENSITIVE_PATH_RE='^(apps/web-platform" plugins/soleur/skills/preflight/SKILL.md` returns ≥ 2 (Check 6 + Check 10 + optional Sharp Edges sync-pointer).
- [ ] **AC3.** Check 10 calls **Shared Plan-File Resolution** for plan-path
  extraction; Check 6 also calls it (no copy-paste duplication). Verify:
  `grep -c 'Shared Plan-File Resolution' plugins/soleur/skills/preflight/SKILL.md` returns ≥ 3 (header + 2 callers).
- [ ] **AC4.** The 8-state decision matrix exists in Check 10 and the
  PASS-state count is exactly 1. Verify the matrix table by `grep -cE
  '^\| [0-9]+ \|' plugins/soleur/skills/preflight/SKILL.md` ≥ 8 inside the
  Check 10 block, with one row containing `**PASS**`.
- [ ] **AC5.** Both parser forms documented: `grep -E 'Form A|Form B'
  plugins/soleur/skills/preflight/SKILL.md` returns ≥ 2 matches inside the
  Check 10 block.
- [ ] **AC6.** Check 10 rejects `ssh ` commands explicitly (defense-in-depth
  even though deepen-plan Phase 4.7 already rejects). Grep: `grep -E
  '\\\(\\^\\\|\[\[:space:\]\]\\\|/\\\)ssh' plugins/soleur/skills/preflight/SKILL.md` ≥ 1 match.
- [ ] **AC7.** Fast-path SKIP table row for Check 10 exists (line ~44 area).
- [ ] **AC8.** Phase 2 aggregate table row for "Discoverability Test
  Execution" exists (line ~647 area).
- [ ] **AC9.** `plugins/soleur/test/preflight-discoverability-test.test.ts`
  exists and `bun test` against it exits 0 with 8 tests covering the 8
  decision states + 1 regression test (PR #4148 fixture).
- [ ] **AC10.** Regression test asserts the fixture
  `04-dns-fail.md` contains the literal `web-platform.soleur.ai` AND that
  the classifier returns FAIL when the stub executor returns `(rc=6,
  stdout="")`.
- [ ] **AC11.** `plugins/soleur/test/lib/discoverability-test-parser.ts`
  exists, exports the four pure functions named in Phase 3 ("Mocking
  strategy"), and is referenced from the Check 10 body as the canonical
  reference implementation.
- [ ] **AC12.** No new `ssh ` token is present in this PR's own plan file's
  `## Observability` block (sanity grep, mirroring Check 10's reject regex
  exactly): `awk '/^## Observability/{flag=1; next} /^## /{flag=0} flag'
  knowledge-base/project/plans/2026-05-20-feat-preflight-discoverability-test-execution-plan.md
  | grep -E '(^|[[:space:]])ssh([[:space:]]|$)'` returns 0 matches. (Note:
  `\bssh \b` is wrong — `\b` is a word-boundary, not space-anchor; the form
  above mirrors the canonical Check 10 reject regex byte-for-byte.)
- [ ] **AC13.** This PR's OWN plan file has a `## Observability` block whose
  `discoverability_test.command` is `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` (a non-network
  probe is acceptable since the change is a skill+test, not infra). Expected
  output: `8 pass`.
- [ ] **AC14.** `python3 scripts/lint-agents-rule-budget.py` exits 0 (no
  AGENTS budget regression — this PR adds zero AGENTS-rule bytes).
- [ ] **AC15.** `bun test plugins/soleur/test/components.test.ts` exits 0 (no
  skill description budget regression — Check 10 adds skill body, NOT
  description).

### Post-merge (operator)

- [ ] **AC-post-1.** Operator runs the live preflight against the next
  sensitive-path PR after merge and observes Check 10 firing (PASS or FAIL,
  not SKIP). Tracks completion via PR-body checkbox on the FIRST PR to merge
  after this one whose diff matches `SENSITIVE_PATH_RE`. Tracks #4162.

## Test Scenarios

- Given a PR diff with no sensitive paths (e.g., a docs-only change), when
  preflight runs, then Check 10 returns SKIP with note "No sensitive paths
  touched."
- Given a sensitive-path PR with no plan file linked in the PR body, when
  preflight runs, then Check 10 returns SKIP with note about no plan link.
- Given a sensitive-path PR linking a plan missing `## Observability`, when
  preflight runs, then Check 10 returns FAIL with the missing-section
  diagnostic.
- Given a sensitive-path PR linking a plan with Observability block but no
  `discoverability_test.command`, when preflight runs, then Check 10 returns
  FAIL with the missing-command diagnostic.
- Given a sensitive-path PR linking a plan whose
  `discoverability_test.command` is `curl ... web-platform.soleur.ai/...`,
  when preflight runs, then `dig`/`curl` returns DNS failure (rc=6) and
  Check 10 returns FAIL — the #4148 regression case.
- Given a sensitive-path PR linking a plan whose command times out (>15 s),
  when preflight runs, then Check 10 returns FAIL with the timeout
  diagnostic.
- Given a sensitive-path PR linking a plan declaring `expected_output: 200`
  but the live endpoint returns 503, when preflight runs, then Check 10
  returns FAIL with the mismatch diagnostic (catches endpoint-drift, not
  just typos).
- Given a sensitive-path PR linking a plan declaring an auth-gated probe
  returning 401 without `expected_output: 401`, when preflight runs, then
  Check 10 returns SKIP with diagnostic suggesting to add the auth shape OR
  provision Doppler creds for the probe.
- Given a sensitive-path PR linking a plan with a working command (200 or
  401 returned, matches expected), when preflight runs, then Check 10
  returns PASS.

## Out of Scope (Deferred)

- **Broadening Phase 4 Playwright-first audit to cover CLI-shaped operator
  steps** (`curl`, `gh`, `terraform`, `ssh`, `systemctl`). Different defect
  class (operator steps that should be agent-executed). Tracked separately;
  not in this PR. **Re-evaluation:** when a second instance of the
  "operator runs a CLI command we could have run for them" class surfaces in
  the post-#4148 sample window.
- **Investigating overlap with `wg-block-pr-ready-on-undeferred-operator-steps`**
  (PR-H #4066). The two gates target different defect classes
  (`wg-block-pr-ready-...` catches "step is declared but not Refs/Tracks
  an issue"; Check 10 catches "the step's literal command is wrong or dead").
  No overlap identified; deferring formal cross-reference until 1+ month of
  Check 10 in production reveals interaction patterns.
- **Promoting `discoverability_test:` to `spec.md` frontmatter parsed by a
  dedicated CI workflow.** The hard rule's Re-evaluation criterion already
  cites this as the long-term direction. Out of scope for this PR; Check 10
  is the bridge primitive while the frontmatter migration matures.
- **Auth-gated probe support via Doppler-fetched creds** (Row 7 currently
  SKIPs). The skip path emits a diagnostic suggesting the right shape; a
  follow-up PR can add a `discoverability_test.creds:` sub-field that names
  a Doppler key for the operator-side probe variant. **Re-evaluation:**
  when the first plan whose authenticated endpoint cannot be probed
  unauthenticated triggers this skip.

## Domain Review

**Domains relevant:** Engineering (CTO).

This is a pure-engineering / pure-tooling change: it adds a check in a skill
file, accompanied by a TypeScript test harness. No product, marketing, legal,
finance, sales, support, or operations implications.

### Engineering (CTO)

**Status:** auto-assessed (single-domain lane).
**Assessment:** Low-risk additive change. New parallel check in an existing
6→7→...→10-check parallel pipeline; failure mode is a FAIL pre-merge for the
exact bug class the issue describes. No prod runtime impact (preflight is
local/CI tooling, not deployed). Re-uses two SSOTs (sensitive-path regex,
plan-file resolution) rather than copying — DRY discipline reduces drift
surface. Defense-in-depth `ssh ` reject and command-substitution reject
cover the (low) trust-in-plan-file risk.

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

**Result: not applicable.** Touched files: `plugins/soleur/skills/preflight/SKILL.md` (skill prose), `plugins/soleur/test/preflight-discoverability-test.test.ts` (test harness), 9 fixture files (markdown), 1 TS parser helper, 1 learning file. None match the regulated-data canonical regex (no schema/migration/auth/API surfaces). None of the four extended triggers fire: (a) no new LLM-on-operator-data processing, (b) brand-survival threshold is `aggregate pattern` (not `single-user incident`), (c) no new cron reading from learnings/specs, (d) no new artifact distribution surface. Gate skipped.

## Infrastructure (IaC)

**Result: not applicable.** Zero new infrastructure resources, secrets, vendors, DNS records, TLS certs, firewall rules, monitoring webhooks, or persistent runtime processes. Pure skill-file + test-harness edit. Phase 2.8 trigger set does not fire.

## Observability

[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]

- **liveness_signal:** The `preflight-discoverability-test.test.ts` test
  suite in CI. Cadence: per-PR via the standard `bun test plugins/soleur/test/`
  job. Alert target: CI red on PR; bot-fixer or operator addresses.
  Configured in: `package.json` `scripts.test` + `.github/workflows/test.yml`
  (existing — Check 10 inherits the suite's CI coverage).
- **error_reporting:** GitHub Actions failure on the test job (loud, visible
  on every PR). No Sentry path because preflight runs locally / in CI, not
  in the deployed runtime.
- **failure_modes:**
  1. Parser drift between SKILL.md bash and TS reference impl. Detection:
     test suite runs both forms (A + B) against all 8 fixtures; if the bash
     prose changes shape without a TS-mirror update, the test fails.
     Alert: CI red.
  2. SSOT regex drift (Check 6 vs Check 10 vs deepen-plan Phase 4.6).
     Detection: AC2 grep asserts byte-identical literal. Alert: CI red.
  3. Live preflight returns false-FAIL because a plan's command relies on
     network availability that is flaky from the CI runner. Detection:
     observed via repeat-run patterns; mitigation is the 15 s timeout +
     auth-gated SKIP row.
- **logs:** GitHub Actions workflow run logs (default retention 90 days);
  local preflight runs print to operator terminal (no persistent log).
- **discoverability_test:**
  - **command:**
    ```bash
    bun test plugins/soleur/test/preflight-discoverability-test.test.ts
    ```
  - **expected_output:** `8 pass`
    (Non-network probe — the change is skill/test code, not infra. The check
    proves the parser + classifier behave as documented across all 8
    decision states.)

## Sharp Edges

- **Parser duality (Form A YAML vs Form B prose+fence).** PR #4148 used
  Form B; canonical template uses Form A. Both must be accepted. A future
  template-harmonization PR may collapse to one form; until then, the
  parser MUST support both OR Check 10 will silently SKIP on currently-valid
  plans.
- **Triple-SSOT regex (Check 6 + Check 10 + deepen-plan Phase 4.6).** The
  three literals MUST stay byte-identical. AC2's grep is the load-bearing
  drift guard. A future PR that changes one literal without updating the
  others will pass `tsc`/`lint` but silently bypass either Check 6 or
  Check 10 on a class of sensitive-path diffs. The mitigation is the
  sync-pointer comment in each block.
- **TS parser is a REFERENCE impl, not the runtime.** The bash in SKILL.md
  IS the runtime; the TS file exists so the 8 decision states can be
  unit-tested without subshells. If they ever drift, the bash wins and the
  TS file is the bug. Tests assert the bash prose contains the canonical
  control-flow markers (e.g., `# Form A first` comment), making drift loud.
- **`bash -c "$CMD"` is intentional.** The plan-file is trusted (operator
  authored, reviewed in PR review). The defense-in-depth substitution-token
  reject + the 15 s timeout cover the residual exposure. Do NOT replace
  with `exec`/`eval` patterns or try to "safely tokenize" the command —
  plan-declared commands include pipes, redirects, and multi-line forms
  that `eval`-style approaches mangle.
- **A plan whose `## Observability` declares a `discoverability_test.command`
  containing `$()` or backticks will FAIL Check 10's substitution-reject —
  by design. Plans should compose the command literally; complex probes
  belong in a tracked helper script the plan references (e.g., `bash
  plugins/soleur/skills/preflight/probe-inngest.sh`).
- **Expected-output substring matching is permissive.** A plan declaring
  `expected_output: 200` and an endpoint returning `200 OK\nServer: ...`
  PASSes (substring match). A plan declaring `expected_output: 200` and an
  endpoint returning `1200` ALSO PASSes (false positive). For tighter
  matching, the plan should declare a more distinctive expected (e.g.,
  `HTTP/2 200` or include `--write-out` formatting in the command).
  Document this in the companion learning.
- **The 15 s outer timeout is hard.** If a plan declares `curl --max-time
  30`, Check 10 will kill it at 15 s. Plans MUST size their probes to the
  Check 10 cap, not the reverse. Document in the failure diagnostic so the
  operator knows to lower the command's own timeout.
- **The check fires per-preflight, not per-CI-run.** A passing Check 10
  result captures the state at the moment preflight runs. If the live
  endpoint goes down between preflight and merge, the merge still ships.
  This is acceptable — Check 10's purpose is to catch typos and dead
  endpoints, not to be a runtime SLO. Don't expand scope to "block merge
  if endpoint is intermittent."
- **`bash -c "$CMD"` stdout always ends in `\n`.** Empirically verified:
  `bash -c "echo 200"` returns `200\n`, not `200`. The `expected_output`
  matcher MUST normalize trailing newlines before substring comparison,
  or `expected_output: 200` fails when production correctly emits `200\n`.
  Step 10.6 substring-match must be implemented as `${DT_STDOUT_SAFE%$'\n'}`
  (or stricter trim) before the contains-check, NOT raw `$DT_STDOUT`.
- **`grep -cF` on the SSOT pattern tolerates indentation drift** — Check 6's
  SSOT lives at top-level (`SENSITIVE_PATH_RE='...`), Check 10's will also be
  top-level, and the deepen-plan mirror at `deepen-plan/SKILL.md:348` is
  indented 2 spaces (inside a markdown bullet). AC2's prescribed grep
  pattern (`grep -cF "SENSITIVE_PATH_RE='^(apps/web-platform"`) matches all
  three contexts because `grep -cF` is substring-based and ignores leading
  whitespace. Anchoring the AC's grep with `^` would break this — keep it
  un-anchored.
- **The `\b` word-boundary trap.** Bash `[[ $x =~ \bssh \b ]]` matches
  `ssh ` only when whitespace is on BOTH sides AND a word-boundary fires;
  trailing-EOF or trailing-newline `ssh ` does NOT match. Always use
  `(^|[[:space:]])ssh([[:space:]]|$)` — the canonical Check 10 reject
  form — when checking for the `ssh ` token in operator-facing prose.
  AC12 was initially miswritten with `\b`; corrected to the canonical form
  during deepen-pass.
