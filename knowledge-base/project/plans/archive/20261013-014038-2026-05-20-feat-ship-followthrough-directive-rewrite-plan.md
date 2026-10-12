---
title: "feat: rewrite /ship Phase 7 Step 3.5 to emit sweeper-parseable follow-through directive"
date: 2026-05-20
issue: 4190
branch: feat-one-shot-ship-followthrough-directive-4190
lane: single-domain
requires_cpo_signoff: false
deepened_on: 2026-05-20
---

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, Research Reconciliation, Implementation Phases (Phase 0 + Phase 2), Acceptance Criteria, Risks and Sharp Edges
**Gates passed:** Phase 4.6 (User-Brand Impact), Phase 4.7 (Observability), Phase 4.8 (PAT-shape sweep)

### Key Improvements

1. **Live state corrections.** PR #4188 reads MERGED on `main` (commit `bbc08993`) but is NOT in this worktree's base — corrected status from "MERGEABLE/OPEN" to "MERGED on main, not yet in this branch's base" with the implication for AGENTS.md sidecar load order.
2. **Parser line-range citation corrected.** Sweeper parser function `parse_directive` spans `scripts/sweep-followthroughs.sh:36-48` (the `awk '...'` block is lines 37-47). Original plan said `:34-49` (off by 2 on each side).
3. **Awk parser empirically tested** on both single-line and canonical multi-line directives — both shapes parse correctly. Single-line is safe for the precondition gate.
4. **Self-grep scope verified** per 2026-05-20 sharp edge (`2026-05-20-plan-acs-self-grep-scope-and-identifier-source-verification.md`): assertion 3 grep is already scoped to `plugins/soleur/skills/ship/SKILL.md` only — does NOT scan the plan, tasks.md, or learnings. Documented explicitly in the AC.
5. **Defense-in-depth precondition gate.** Step 3.5.E now requires the agent emit identical awk-parser semantics in self-test (extracted from the sweeper script lines 37-47 verbatim, NOT paraphrased) — prevents drift between the agent's self-test and the sweeper's authoritative parser.

### New Considerations Discovered

- **Worktree base lag.** Plan's branch was cut before PR #4188 merged. After this PR rebases on main, `AGENTS.md` will include `wg-pm-class-followthrough-for-operator-dogfood` automatically. Plan does NOT need to re-add the rule.
- **Sweeper's `env -i` allowlist semantics.** The sweeper uses `env -i PATH=$PATH HOME=$HOME <secret>=<value>` (line 99-110). Stub template MUST NOT assume `GH_TOKEN` is in env unless declared via `secrets=GH_TOKEN` — but `GH_TOKEN` IS already in the workflow's env block. Plan now explicitly notes this.
- **Two existing `type: manual` literals in learning files.** `knowledge-base/project/learnings/2026-05-11-manual-dispatch-substitutes-for-scheduled-tick-when-external-dependency-resolves.md` and `knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md` both contain `type: manual` literals as historical documentation. These are intentional and must NOT be edited by this PR — the test assertion is scoped to SKILL.md only.
- **Sweeper workflow concurrency group.** `concurrency.group: schedule-followthrough-sweeper` (line 40 of `.github/workflows/scheduled-followthrough-sweeper.yml`) — a `gh workflow run` triggered manually won't race a cron-tick. Operators may safely dry-run via `-f dry_run=true` without colliding.

# feat: rewrite /ship Phase 7 Step 3.5 to emit sweeper-parseable follow-through directive

Closes #4190 (post-merge — see User-Brand Impact + Sharp Edges; do NOT use `Closes #4190` if any post-merge verification step is filed as a follow-through; see plan body).

## Overview

`/ship` Phase 7 Step 3.5 currently emits a follow-through tracker issue body containing an OLD-convention YAML block:

```yaml
type: manual
manual_because: subjective-design-call
sla_business_days: 5
```

The actual sweeper (`scripts/sweep-followthroughs.sh` + `.github/workflows/scheduled-followthrough-sweeper.yml`) parses ONLY the NEW-convention HTML directive:

```html
<!-- soleur:followthrough
  script=scripts/followthroughs/<name>-<N>.sh
  earliest=<ISO-8601-UTC>
  secrets=<comma-separated-secret-names>
-->
```

A follow-through filed with the old format is **invisible** to the sweeper and rots open until an operator manually revisits. PR #4186 is the live retrofit example (#4178 needed a hand-rolled script + body directive added 1 day post-merge).

This plan rewrites Phase 7 Step 3.5 in `plugins/soleur/skills/ship/SKILL.md` to:

1. Replace the `type:`-keyed YAML schema with the canonical `<!-- soleur:followthrough -->` HTML directive.
2. Generate a stub verification script at `scripts/followthroughs/<feature-name>-<issue-num>.sh` mirroring `scripts/followthroughs/sentry-checkins-3859.sh` (exit 0 PASS / 1 FAIL / other TRANSIENT).
3. Drop the `type: http-200 / dns-txt / dns-a / sql-query / api-curl / manual` branches — the sweeper has no special-case handlers; every verification becomes "write a script that exits 0 on success."
4. Cross-reference the canonical runbook `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` so future skill-readers find the contract.
5. Add a precondition gate: every `follow-through`-labeled issue body emitted by `/ship` MUST contain a parseable directive — verify before `gh issue create` and self-test with the same awk parser the sweeper uses.

## User-Brand Impact

**If this lands broken, the user experiences:** follow-through tracker issues filed during `/ship` Phase 7 Step 3.5 are again invisible to the daily sweeper, so the post-merge verification (e.g., Sentry monitors received check-ins, OAuth callback survived a redeploy, Doppler env-var landed) never auto-closes the issue — operator must manually revisit days/weeks later, or the issue rots open and silently rots the verification gap (e.g., the #4121 → #4178 → PM3 chain that uncovered two production bugs only because PM3 *was* a real follow-through).

**If this leaks, the user's workflow is exposed via:** N/A — no user data or credentials touched by this change. The directive only references committed `scripts/followthroughs/*.sh` paths; the sweeper's path-allowlist (`SCRIPTS_ROOT="scripts/followthroughs"` in `scripts/sweep-followthroughs.sh:107`) already refuses arbitrary paths.

**Brand-survival threshold:** aggregate pattern — a single broken follow-through is recoverable (manual close + retrofit per PR #4186 model); the brand cost is the accumulated-rot pattern over many ships if the gap stays unfixed.

`threshold: aggregate pattern, reason: per-ship verification gap that accumulates over time; no single ship is brand-survival.`

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "the actual daily sweeper (`Scheduled: Follow-Through Sweeper` workflow → `scripts/sweep-followthroughs.sh`) expects the NEW convention" | Verified: `.github/workflows/scheduled-followthrough-sweeper.yml:33-44`; parser function `parse_directive` at `scripts/sweep-followthroughs.sh:36-48` (the `awk '...'` block spans lines 37-47), uses `awk '/<!-- *soleur:followthrough/, /-->/'` and only handles `script=`/`earliest=`/`secrets=`. No `type:` fork. | Adopt verbatim. |
| "Cross-reference the runbook `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`" | File present, 80 lines, canonical fields + security model documented. | Adopt; link from SKILL.md template + emit as `See` reference in stub script header. |
| PR #4186 is the retrofit example | `gh pr view 4186 --json mergeable` → `MERGEABLE`, `state: OPEN`. PR introduces `scripts/followthroughs/manifest-drift-suppress-deletion-4178.sh` (not present on `main` yet; verified via `cat scripts/followthroughs/manifest-drift-suppress-deletion-4178.sh` → "No such file or directory"). | Treat as model-not-dependency. Plan must NOT prescribe importing #4186's script. Acceptance Criteria reference is INFORMATIONAL ("model"), not blocking. |
| PR #4188 is the wg-* rule codifying the target convention | `gh pr view 4188 --json state` → `MERGED` (commit `bbc08993` on main). The wg-rule `wg-pm-class-followthrough-for-operator-dogfood` is on main's AGENTS.md + AGENTS.rest.md but NOT yet in this worktree's base (branch was cut earlier). Diff adds the rule to AGENTS.md pointer index + body to AGENTS.rest.md. | Treat as informational. The rule body already names the canonical directive shape — this plan IS the surface that implements the rule for /ship. After rebase, the rule will be visible in this branch's AGENTS.md automatically. |
| "Drop the `type: http-200 / dns-txt / dns-a` branches — the sweeper has no special handlers" | Verified: `scripts/sweep-followthroughs.sh` only branches on script exit code (0/1/other). The OLD-convention `scheduled-follow-through.yml` referenced in current SKILL.md:1270 is the LEGACY daily monitor — superseded by `scheduled-followthrough-sweeper.yml`. | Confirm and remove the legacy `type:`-branch enumeration from SKILL.md. |
| "the daily monitor lacks Doppler secret access; widening that scope is a separate PR" (current SKILL.md:1276) | Outdated: the current `scheduled-followthrough-sweeper.yml` already exports `SENTRY_AUTH_TOKEN` (line 62) and the env block accepts new secrets per the runbook's directive-declared allowlist. | Replace prose with "to add a new secret to a follow-through, add the secret to `scheduled-followthrough-sweeper.yml` `env:` block AND declare it in the directive's `secrets=` clause." |
| "clo_routable: true field" (current SKILL.md:1296) | The `clo_routable` field is an old-convention YAML field with no consumer in the new directive shape. `/soleur:go`'s classification table currently parses `manual_because:` — needs separate routing path (out of scope for this PR). | Move legal-attestation routing prose to a `### Optional: legal-attestation follow-throughs` subsection that emits a directive with `script=scripts/followthroughs/<name>-<N>.sh` calling out to `/soleur:go #N` invocation as the verification body (i.e., the script asks the operator to run `gh issue view <N>` and confirms by reading a checkpoint comment). Defer cross-skill `clo_routable` routing to a separate scope-out issue (see Open Code-Review Overlap). |
| Operator-only steps that genuinely cannot become a script (CAPTCHA, OAuth consent, subjective design call) | The new convention's "exit 0 = PASS / exit 1 = FAIL / other = TRANSIENT" mechanism still works for operator-checked items: the script can `gh issue view <N> --comments` and grep the comment body for a sentinel string the operator pastes. Pattern: operator types `RESULT: PASS` in a comment; script greps for `^RESULT: PASS$` and exits 0. | Add as an explicit pattern under "Operator-confirmed scripts" in the SKILL.md rewrite; emit the stub script with the grep-comment pattern when item-classification flags it as subjective. |

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` ran; greps against the planned file list (`plugins/soleur/skills/ship/SKILL.md`, `scripts/followthroughs/` paths, `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`).

**Result:** None for the planned edit surface. (Verified zero hits via `jq -r --arg path "plugins/soleur/skills/ship/SKILL.md" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json` and equivalent for the two other paths.)

**Adjacent scope-outs filed by this plan (NOT in this PR):**

- **`clo_routable` routing field deprecation.** The current SKILL.md:1296 documents a `clo_routable: true` YAML field that `/soleur:go` is documented (in the prose) to consume to route to the `clo` agent. The new directive convention has no `clo_routable=` field. This plan documents legal-attestation follow-throughs via the operator-confirmation pattern (script `gh issue view --comments`) but does NOT remove the cross-skill `/soleur:go` routing — that's a separate /soleur:go skill edit. **Defer:** File a tracking issue post-merge with title `chore(soleur:go): port clo_routable: true YAML routing to <!-- soleur:followthrough --> body sentinel` and body that names the comment-sentinel pattern this plan introduces.

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 Step 3.5 rewrite (lines ~1238-1316; ~80 lines of removed `type:`-keyed prose; ~110 lines of new directive-emitting prose + stub-script template). The neighboring `Step 3.6` (migration verification) and `Step 3.7` (Terraform provisioner gate) stay untouched.
- `plugins/soleur/skills/ship/references/` — NEW: add `followthrough-stub-template.sh` (a reusable bash template the rewritten Step 3.5 reads via `cat` to scaffold per-PR scripts).
- `plugins/soleur/test/ship-followthrough-directive.test.sh` — NEW: bats-style `.test.sh` (project convention; matches sibling `ship-deploy-pipeline-fix-gate.test.ts` family in same dir). Asserts: (a) the rewritten template, when run against a fixture PR-body checklist, emits an issue body that the same `awk` parser used in `scripts/sweep-followthroughs.sh:36-48` extracts a valid `script` + `earliest` from; (b) `earliest` is a parseable ISO-8601 UTC timestamp; (c) `script` path starts with `scripts/followthroughs/`.

## Files to Create

- `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` — bash template that the rewritten Step 3.5 prose instructs the agent to `cp` and customize. Header includes set-uo-pipefail, exit-semantics docs, sentinel `# soleur:followthrough-stub vN`, and a TODO block for the verification body.
- `plugins/soleur/test/ship-followthrough-directive.test.sh` — see Files to Edit. Idiomatic shell test using `bash` + `awk` + `date -d`; runs locally via `bash plugins/soleur/test/ship-followthrough-directive.test.sh`. CI hook: `bun test plugins/soleur/test/` already discovers `.test.sh` files via the wrapper at `test-helpers.sh`.
- `plugins/soleur/test/fixtures/followthrough-directive/` — fixture directory:
  - `pr-checklist-input.md` — sample PR body with a `- [ ] ⏳ <description>` row
  - `expected-issue-body.md` — golden output the test compares against (directive + body template)
  - `expected-stub-script.sh` — golden output the test compares against (the scaffolded stub)

## Implementation Phases

### Phase 0 — Preconditions and Discovery

0.1. Confirm dependency PRs are still mergeable: `gh pr view 4186 --json mergeable,state` and `gh pr view 4188 --json mergeable,state`. Both should be MERGEABLE/OPEN. **No-block:** this plan does not depend on either landing first; it implements the convention they document.

0.2. Re-grep sweeper parser to confirm directive grammar is unchanged from the runbook:

```bash
awk '/<!-- *soleur:followthrough/, /-->/ { print }' knowledge-base/engineering/operations/runbooks/followthrough-convention.md
```

Expected: emits the canonical 4-line example block. Note the awk-self-match risk (sharp edge: 2026-05-15 awk-self-match-and-marker-conjunction): the `/start/,/end/` range matches the start line through the next line matching `/-->/`. Verify the parser handles single-line directives (rare) AND multi-line directives (canonical).

0.3. Probe the awk parser against a malformed directive to confirm it fails closed (returns nothing, NOT garbage):

```bash
printf '<!-- soleur:followthrough garbage=value -->\n' | awk '/<!-- *soleur:followthrough/, /-->/ { for (i=1;i<=NF;i++) { if ($i ~ /^script=/) print $i } }'
```

Expected: empty output. (Confirms the directive without `script=` is ignored — the sweeper's `[[ -z "${script:-}" ]]` early-return at line 81 handles it.)

0.4. Inventory current Phase 7 Step 3.5 issue-body emitters. `sed -n '1238,1316p' plugins/soleur/skills/ship/SKILL.md` is the section in scope. Confirm no other `/ship` step emits a `follow-through` label.

### Phase 1 — Stub-script template

1.1. Create `plugins/soleur/skills/ship/references/followthrough-stub-template.sh`. Header:

```bash
#!/usr/bin/env bash
# Follow-through verification stub (template).
#
# Mirror of scripts/followthroughs/sentry-checkins-3859.sh.
# Generated by /ship Phase 7 Step 3.5; customize the TODO block below.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS         (close-criteria met; sweeper closes the issue)
#   1 = FAIL         (criteria not met; sweeper comments, leaves open)
#   * = TRANSIENT    (network error, unexpected state; sweeper retries next sweep)
#
# Required secrets: declare via the directive `secrets=` clause AND add to
# .github/workflows/scheduled-followthrough-sweeper.yml env: block.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

# soleur:followthrough-stub v1

# TODO: replace this block with the verification body.
# Examples:
#   - HTTP probe: curl -sS -o /dev/null -w '%{http_code}' "$URL" | grep -q '^200$' && exit 0 || exit 1
#   - SQL probe:  via doppler run -- psql "$SUPABASE_URL" -c "SELECT ..." | jq ... && exit 0 || exit 1
#   - GH probe:   gh run list --workflow <wf>.yml --status success --limit 1 --json conclusion | jq -e ... && exit 0 || exit 1
#   - Operator-confirmed: gh issue view <N> --comments --json comments \
#                          | jq -re '.comments[].body' | grep -qE '^RESULT: PASS$' && exit 0 || exit 1

echo "TRANSIENT: stub not customized" >&2
exit 2
```

1.2. Verify the sentinel `# soleur:followthrough-stub v1` survives the cp (idiomatic anchor for grep-based detection in tests + future migrations).

1.3. Sanity-test the template runs:

```bash
bash plugins/soleur/skills/ship/references/followthrough-stub-template.sh; echo "exit=$?"
# Expected: TRANSIENT line on stderr, exit=2
```

### Phase 2 — Rewrite SKILL.md Step 3.5 (RED → GREEN)

**RED (write the test first):**

2.1. Create `plugins/soleur/test/fixtures/followthrough-directive/` with three fixture files:

  - `pr-checklist-input.md`:

    ```text
    ## Test plan

    - [ ] ⏳ Verify Sentry monitors received first check-in (sentinel: scheduled-realtime-probe)
    - [x] Local: bun test passed
    ```

  - `expected-issue-body.md`: contains the canonical `<!-- soleur:followthrough -->` block plus the standard Source PR / Created by / Created lines from current SKILL.md template, with placeholders for `<ITEM_DESCRIPTION>`, `<PR_NUMBER>`, `<YYYY-MM-DD>`, `<SCRIPT_PATH>`, `<EARLIEST_UTC>`. The test renders the template with known values and diffs.

  - `expected-stub-script.sh`: byte-for-byte copy of the template from 1.1 with the sentinel line preserved.

2.2. Create `plugins/soleur/test/ship-followthrough-directive.test.sh`. Idiomatic shell test:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
FIXTURE_DIR="$REPO_ROOT/plugins/soleur/test/fixtures/followthrough-directive"
PARSER='/<!-- *soleur:followthrough/, /-->/ {
  gsub(/^<!-- *soleur:followthrough/, "")
  gsub(/-->/, "")
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
    if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
    if ($i ~ /^secrets=/)  { sub(/^secrets=/, "", $i);  print "secrets "  $i }
  }
}'

# Assertion 1: golden issue body parses into a valid script + earliest pair.
out=$(awk "$PARSER" "$FIXTURE_DIR/expected-issue-body.md")
script_path=$(echo "$out" | awk '/^script /{print $2}')
earliest=$(echo "$out" | awk '/^earliest /{print $2}')

if [[ -z "$script_path" ]]; then
  echo "FAIL: parser extracted empty script path" >&2; exit 1
fi
case "$script_path" in
  scripts/followthroughs/*) : ;;
  *) echo "FAIL: script path '$script_path' not under scripts/followthroughs/" >&2; exit 1 ;;
esac
if [[ -z "$earliest" ]]; then
  echo "FAIL: parser extracted empty earliest" >&2; exit 1
fi
date -u -d "$earliest" +%s >/dev/null 2>&1 || { echo "FAIL: earliest '$earliest' is not parseable by date -u -d" >&2; exit 1; }

# Assertion 2: stub template carries the sentinel line.
grep -qE '^# soleur:followthrough-stub v[0-9]+$' "$REPO_ROOT/plugins/soleur/skills/ship/references/followthrough-stub-template.sh" \
  || { echo "FAIL: stub template missing sentinel line" >&2; exit 1; }

# Assertion 3: SKILL.md Step 3.5 no longer carries OLD-convention `type: manual`/`type: http-200`/...
if grep -nE '^\s*type:\s*(manual|http-200|dns-txt|dns-a|sql-query|api-curl)\s*$' "$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"; then
  echo "FAIL: SKILL.md still emits OLD-convention type: keyed YAML — must use <!-- soleur:followthrough --> directive" >&2
  exit 1
fi

# Assertion 4: SKILL.md references the canonical runbook.
grep -qF 'knowledge-base/engineering/operations/runbooks/followthrough-convention.md' "$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md" \
  || { echo "FAIL: SKILL.md Step 3.5 does not reference the canonical runbook" >&2; exit 1; }

echo "PASS: ship-followthrough-directive contract"
```

  Run: `bash plugins/soleur/test/ship-followthrough-directive.test.sh` — expect FAIL on assertions 3 + 4 (SKILL.md not yet rewritten) and possibly 1 + 2 (fixtures not yet created). This is the RED.

**GREEN (rewrite SKILL.md):**

2.3. In `plugins/soleur/skills/ship/SKILL.md`, replace the `## Verification` template block (lines 1261-1312 in current file, the `type: manual / type: http-200 / ... / clo_routable` enumeration) with the new directive-emitting block. Keep the surrounding scaffolding (`## Follow-Through Item`, `**Source PR:**`, `**Created by:**`, `**Created:**`, the migration filename anchor, the callback URL closure gate) unchanged.

  New `## Verification` block (replacement target):

  ````markdown
  ## Verification

  ```html
  <!-- soleur:followthrough
    script=scripts/followthroughs/<feature-name>-<ISSUE_NUM>.sh
    earliest=<ISO-8601-UTC>
    secrets=<comma-separated-secret-names-or-omit>
  -->
  ```

  Canonical convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
  The directive is parsed daily by `.github/workflows/scheduled-followthrough-sweeper.yml`
  via `scripts/sweep-followthroughs.sh` — exit 0 PASS / exit 1 FAIL / other TRANSIENT.

  **Step 3.5.A — Generate the stub script.** For each item, scaffold a stub at
  `scripts/followthroughs/<feature-name>-<ISSUE_NUM>.sh` by copying
  `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` and customizing
  the TODO block. Make the script executable (`chmod +x`). Mirror the structure of
  `scripts/followthroughs/sentry-checkins-3859.sh` (the canonical reference).

  **Step 3.5.B — Choose a verification pattern.** Default to automated per
  `hr-no-dashboard-eyeball-pull-data-yourself`:

  - **HTTP probe** (canary, status page): `curl -sS -o /dev/null -w '%{http_code}' "$URL" | grep -q '^200$' && exit 0 || exit 1`
  - **DNS probe**: `dig +short +time=5 +tries=2 TXT example.com | grep -qF "$EXPECTED" && exit 0 || exit 1`
  - **SQL probe** (Supabase prd): scaffold via `/soleur:schedule --once` so the workflow brings its own Doppler env; the follow-through script then queries the workflow run status via `gh run list --workflow <name>.yml --status success`.
  - **GitHub Actions probe**: `gh run list --workflow <wf>.yml --status success --created '>=<earliest>' --json conclusion | jq -e 'length > 0'`
  - **Operator-confirmed** (CAPTCHA, OAuth consent, subjective design call): the script `gh issue view <N> --comments --json comments | jq -re '.comments[].body' | grep -qE '^RESULT: PASS$'` — operator types `RESULT: PASS` in an issue comment when verification is done. This is the legitimate use of operator-confirmed exit-0 — the script reads the human verdict, not the human reads a dashboard.

  Bare "operator manually checks" with NO scripted gate is non-compliant with
  `hr-no-dashboard-eyeball-pull-data-yourself` AND `wg-pm-class-followthrough-for-operator-dogfood`
  (#4188). If the operator-confirmed pattern is unsuitable, the verification is not
  follow-through-shaped — file a regular GitHub issue without the `follow-through` label.

  **Step 3.5.C — Declare needed secrets.** If the script reads any `process.env.X` /
  `$X` value beyond `GH_TOKEN` / `GH_REPO` / `HOME` / `PATH`, declare each as a
  comma-separated value in the directive's `secrets=` clause AND add the secret to
  `.github/workflows/scheduled-followthrough-sweeper.yml` `env:` block (the sweeper
  passes ONLY allowlisted vars into the script's environment per the directive's
  `secrets=` clause). Omit `secrets=` entirely if no secrets are needed.

  **Step 3.5.D — Choose `earliest`.** ISO-8601 UTC, formatted `YYYY-MM-DDTHH:MM:SSZ`.
  Default `now + 24h` for HTTP/DNS probes; `now + 48h` for cron-triggered probes
  (allows ≥2 cron windows to fire); `now + 5 business days` for operator-confirmed
  patterns. Sweeper skips the issue until `now >= earliest`.

  **Step 3.5.E — Precondition gate.** Before `gh issue create`, the agent MUST self-test
  the body it composed. Pipe the proposed body through the same awk parser the sweeper
  uses (extracted to `scripts/sweep-followthroughs.sh:36-48`) and assert that:
  (1) `script` extracted is non-empty AND begins with `scripts/followthroughs/`,
  (2) `earliest` extracted parses cleanly via `date -u -d "$earliest" +%s`,
  (3) the script path exists on disk and is executable.
  If any assertion fails, warn the operator, do NOT create the issue, and offer to
  scaffold the missing pieces. **Why:** PR #4178 was filed with the OLD-convention
  YAML and rotted open for ~24h until #4186 retrofitted it. The precondition gate
  is the cheapest forward defense.

  **Step 3.5.F — Operator-only ack.** When the chosen pattern is operator-confirmed
  (Step 3.5.B), append a `## Operator instructions` block to the issue body explaining
  the `RESULT: PASS` / `RESULT: FAIL` comment sentinel.

  **Legal-attestation follow-throughs** (replaces former `clo_routable: true` field):
  for legal-source verification, use the operator-confirmed pattern (Step 3.5.B) with
  body instruction `Run /soleur:go #<this issue> to invoke the CLO agent for verification`.
  The script reads the operator's `RESULT: PASS` comment after CLO completes; the
  cross-skill `/soleur:go` routing remains a separate concern (out of scope; tracked
  in Open Code-Review Overlap).
  ````

  The migration filename anchor (current SKILL.md:1204) and the Callback URL closure gate
  (current SKILL.md:1206-1236) stay verbatim — they augment the issue body but do not
  conflict with the directive shape.

2.4. Update the **"Why this matters"** paragraph at the end of Step 3.5 (current SKILL.md:1316) to add:

  > PR #4178 was filed via the OLD-convention YAML emitter and rotted open for ~24h until PR #4186 retrofitted it; this rewrite (PR for #4190) prevents the regression class. See `knowledge-base/project/learnings/2026-05-20-test-stubs-env-and-csp-gates-miss-runtime-bugs.md`.

2.5. Re-run `bash plugins/soleur/test/ship-followthrough-directive.test.sh` — expect PASS on all 4 assertions. This is the GREEN.

### Phase 3 — Self-dogfood: emit fixture issue body and parse-trip

3.1. From the rewritten SKILL.md prose, manually generate an issue body for a hypothetical follow-through with `script=scripts/followthroughs/test-fixture-9999.sh`, `earliest=2026-05-22T18:00:00Z`. Write to `/tmp/followthrough-fixture-body.md`.

3.2. Pipe through the sweeper's awk parser:

```bash
awk '/<!-- *soleur:followthrough/, /-->/ {
  gsub(/^<!-- *soleur:followthrough/, ""); gsub(/-->/, "")
  for (i=1; i<=NF; i++) {
    if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
    if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
    if ($i ~ /^secrets=/)  { sub(/^secrets=/, "", $i);  print "secrets "  $i }
  }
}' /tmp/followthrough-fixture-body.md
```

Expected output:

```text
script scripts/followthroughs/test-fixture-9999.sh
earliest 2026-05-22T18:00:00Z
```

3.3. Confirm `date -u -d "2026-05-22T18:00:00Z" +%s` returns a valid epoch.

### Phase 4 — Verify components.test.ts budget headroom

4.1. The plan adds a new file under `plugins/soleur/skills/ship/references/` (NOT a new skill). The skill description budget cap (`plugins/soleur/test/components.test.ts`) governs SKILL.md `description:` field word counts — NOT body lines or sibling reference files. Running the test should confirm no budget regression:

```bash
bun test plugins/soleur/test/components.test.ts
```

Expected: green. No change to any `description:` field in this PR.

### Phase 5 — Commit, push, open PR

5.1. Stage:

```bash
git add plugins/soleur/skills/ship/SKILL.md \
        plugins/soleur/skills/ship/references/followthrough-stub-template.sh \
        plugins/soleur/test/ship-followthrough-directive.test.sh \
        plugins/soleur/test/fixtures/followthrough-directive/ \
        knowledge-base/project/plans/2026-05-20-feat-ship-followthrough-directive-rewrite-plan.md \
        knowledge-base/project/specs/feat-one-shot-ship-followthrough-directive-4190/
```

5.2. Commit with conventional message: `feat(ship): emit sweeper-parseable follow-through directive (replaces type: manual YAML, closes #4190)`.

5.3. PR body MUST include `Closes #4190` (no post-merge verification step is filed; the test asserts the new template at /work time, not at sweep time).

  PR body also includes Changelog section (`semver:minor` — modifies skill behavior) and Brand-survival threshold per AGENTS.md.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/skills/ship/SKILL.md` Phase 7 Step 3.5 emits `<!-- soleur:followthrough -->` directive (verified via grep: `grep -F 'soleur:followthrough' plugins/soleur/skills/ship/SKILL.md` returns ≥2 lines — opening + closing).
- [ ] SKILL.md Phase 7 Step 3.5 contains NO `type: manual` / `type: http-200` / `type: dns-txt` / `type: dns-a` / `type: sql-query` / `type: api-curl` as a YAML key-value (verified via the test assertion 3 regex `^\s*type:\s*(manual|http-200|dns-txt|dns-a|sql-query|api-curl)\s*$`).
- [ ] SKILL.md Step 3.5 references the canonical runbook path verbatim: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (verified via `grep -F`).
- [ ] `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` exists, is executable, contains the sentinel line `# soleur:followthrough-stub v1`, and exits 2 (TRANSIENT) when run uncustomized (verified via `bash plugins/soleur/skills/ship/references/followthrough-stub-template.sh; test $? -eq 2`).
- [ ] `plugins/soleur/test/ship-followthrough-directive.test.sh` is present and passes (all 4 assertions: directive-parseability of golden body, script-path under `scripts/followthroughs/`, ISO-8601 earliest parses, sentinel line in template, SKILL.md has no OLD-convention `type:` keys, SKILL.md references runbook).
- [ ] Precondition-gate prose in SKILL.md Step 3.5.E names the awk parser at `scripts/sweep-followthroughs.sh:36-48` and the three assertions (script-prefix, date-parseable, script exists+executable).
- [ ] Operator-confirmed pattern (`grep -qE '^RESULT: PASS$'`) is documented in SKILL.md Step 3.5.B for the CAPTCHA/OAuth-consent/subjective-design-call use cases.
- [ ] `bun test plugins/soleur/test/components.test.ts` is green (no skill-description budget regression — this PR adds no SKILL.md `description:` text).
- [ ] PR body contains `Closes #4190` (load-bearing — the rewrite is self-contained and verified at PR time; no post-merge step).
- [ ] PR body has Brand-survival threshold disclosed as `aggregate pattern` (matches plan).

### Post-merge (operator)

- [ ] None. The rewrite is verified at PR time via `bash plugins/soleur/test/ship-followthrough-directive.test.sh`; the sweeper itself is not touched. Next `/ship` invocation that triggers Phase 7 Step 3.5 will exercise the new template path — that's a dogfood opportunity, not an operator gate.

## Test Scenarios

1. **Happy path.** Operator runs `/ship` Phase 7 Step 3.5 on a PR with a `- [ ] ⏳ Verify cron monitor receives check-in` item. Agent scaffolds `scripts/followthroughs/cron-monitor-checkin-9001.sh`, fills the TODO with a `gh run list` probe, writes an issue body with the canonical directive, self-tests via the precondition gate, creates the issue. Sweeper picks it up next day; if `now >= earliest`, runs the script; on exit 0, closes the issue.

2. **Old-convention regression.** Test asserts SKILL.md no longer contains the OLD `type: manual` literal. If a future edit reintroduces it (e.g., copy-paste from a learning), assertion 3 fails CI.

3. **Operator-confirmed path.** Operator runs `/ship` for a PR with `- [ ] ⏳ Manually verify legal-doc against EUR-Lex Art. 7`. Agent scaffolds `scripts/followthroughs/eur-lex-art-7-attestation-NNNN.sh` that runs `gh issue view NNNN --comments --json comments | jq -re '.comments[].body' | grep -qE '^RESULT: PASS$'`. Issue body instructs operator to run `/soleur:go #NNNN` (which invokes CLO) and post `RESULT: PASS` when done.

4. **Precondition-gate trip.** Operator's agent attempts to emit a body with `script=arbitrary/elsewhere/path.sh`. Self-test catches the prefix violation, refuses to create the issue, offers to scaffold under `scripts/followthroughs/`.

5. **Missing `earliest`.** Body is missing the `earliest=` line. Self-test trips on assertion 2 (empty earliest). Agent warns + offers to default to `now + 24h`.

## Domain Review

**Domains relevant:** engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (inline by planner — no external Task spawn warranted for a SKILL.md rewrite that does not touch app code, schema, or external surfaces).

**Assessment:** This is a skill-template surgery that aligns operator-facing prose with already-shipped infra (the sweeper + canonical runbook). No new infrastructure, no new vendor, no schema change, no new env-var contract. The risk surface is "future ships emit a malformed directive" — addressed by the precondition-gate self-test + the standalone `ship-followthrough-directive.test.sh` contract.

### Product/UX Gate

Not relevant — no user-facing surface modified. The change is operator-facing skill prose; the only "users" are agents running `/ship` and operators reading the generated issue body.

## Infrastructure (IaC)

Skipped silently. The plan introduces no new infrastructure surface. It modifies skill prose + one reference file + tests. The sweeper workflow (`.github/workflows/scheduled-followthrough-sweeper.yml`) is referenced but not touched; new secrets, if needed by a specific future follow-through, are added there per directive `secrets=` clause (this is the existing convention, not a new one).

## Observability

**Liveness signal:**
- what: the test `plugins/soleur/test/ship-followthrough-directive.test.sh` passing on every PR touching `plugins/soleur/skills/ship/SKILL.md`
- cadence: every PR (CI on `test` job)
- alert_target: GitHub PR check
- configured_in: `plugins/soleur/test/` is picked up by the existing `bun test` runner in CI

**Error reporting:**
- destination: stderr → CI log → red check on PR
- fail_loud: yes — assertion failure exits 1 with explanatory message

**Failure modes:**
- mode: SKILL.md re-introduces OLD-convention `type:` YAML — detection: assertion 3 in `ship-followthrough-directive.test.sh` — alert_route: CI red
- mode: Stub template loses sentinel line — detection: assertion 2 — alert_route: CI red
- mode: Golden issue body fails awk-parser — detection: assertion 1 — alert_route: CI red
- mode: Runbook cross-reference dropped — detection: assertion 4 — alert_route: CI red

**Logs:** CI run logs — retained per GitHub Actions default (90 days)

**Discoverability test:**
- command: `bash plugins/soleur/test/ship-followthrough-directive.test.sh`
- expected_output: `PASS: ship-followthrough-directive contract`

No `ssh ` in the discoverability command.

## Research Insights

**Best Practices (informed by deepen-pass):**

- **Mirror the parser, do not re-author it.** The precondition gate's awk parser MUST be a verbatim copy from `scripts/sweep-followthroughs.sh:36-48` — paraphrasing risks drift. The plan's test (`ship-followthrough-directive.test.sh`) and the SKILL.md prose both reference the same parser block, copied verbatim. **Why:** PR #3550 + the 2026-05-11 learning on grammar-drift in awk-range parsers — divergence between authoritative and self-test parsers always favors the malformed input passing one and failing the other, surfacing only at sweeper-fire time.
- **Sentinel placement.** The `# soleur:followthrough-stub v1` sentinel goes on a line of its own (no trailing comment) so `grep -qE '^# soleur:followthrough-stub v[0-9]+$'` catches version bumps via the `v\d+` suffix and ignores any future hand-added comments on the same line.
- **Exit-2 default for stub.** The uncustomized stub exits 2 (TRANSIENT) instead of 0 (PASS) or 1 (FAIL) — a stub that accidentally ships uncustomized leaves the issue OPEN, never closes a follow-through prematurely. The sweeper retries TRANSIENT next day, surfacing the gap as repeated comments rather than silent success.

**Operator-confirmed pattern (verified):**

- `gh issue view <N> --comments --json comments | jq -re '.comments[].body' | grep -qE '^RESULT: PASS$'` is the canonical operator-attestation form. `--json comments` + `jq -re` is preferred over `--comments` text mode because the JSON form is robust against comment-body line-prefixes that could otherwise match accidentally. The anchored `^RESULT: PASS$` regex catches only operator-typed sentinel lines, not paraphrased prose.

**Defense layers (decision rationale):**

- Layer 1 (test-time): `ship-followthrough-directive.test.sh` ensures SKILL.md prose stays correct.
- Layer 2 (skill-prose-time): Step 3.5.E precondition gate self-tests every body before `gh issue create`.
- Layer 3 (sweep-time): `scripts/sweep-followthroughs.sh` rejects malformed bodies or out-of-allowlist script paths (defense-in-depth — already shipped).
- Each layer catches a different class of failure; none alone is sufficient. Layer 1 catches future SKILL.md regressions; Layer 2 catches per-PR mistakes by the agent; Layer 3 catches malicious or tampered issue bodies.

**Edge cases handled:**

- **Single-line directive.** Awk parser tested empirically — emits correct `script`/`earliest` even when the directive is on one line. Plan prescribes canonical multi-line shape but the parser accepts both.
- **Missing `secrets=` clause.** Sweeper handles `secrets=` absence at line 102 (`if [[ -n "${secrets:-}" ]]`) — the field is genuinely optional. Plan's stub template defaults to NO secrets (no `secrets=` line).
- **Worktree base lag.** PR #4188's `wg-pm-class-followthrough-for-operator-dogfood` is on main but not this worktree's base. The plan does NOT depend on the rule being loaded at /work time — the rule documents the convention, this PR implements it.

**References:**

- Sweeper script: `scripts/sweep-followthroughs.sh` (especially lines 25 SCRIPTS_ROOT, 36-48 parser, 99-110 env allowlist)
- Sweeper workflow: `.github/workflows/scheduled-followthrough-sweeper.yml` (especially lines 39-41 concurrency, 55-65 env block)
- Canonical runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- Reference verification script: `scripts/followthroughs/sentry-checkins-3859.sh` (canonical exit-semantics example)
- Failure-mode learning: `knowledge-base/project/learnings/2026-05-20-test-stubs-env-and-csp-gates-miss-runtime-bugs.md`
- AGENTS.md rules: `hr-no-dashboard-eyeball-pull-data-yourself`, `wg-use-closes-n-in-pr-body-not-title-to`, `wg-pm-class-followthrough-for-operator-dogfood` (new on main via #4188)

## Risks and Sharp Edges

- **awk-range self-match.** The sweeper's parser uses `/<!-- *soleur:followthrough/, /-->/` — `awk '/start/,/end/'` returns the start line through the next `/-->/` match. If a single-line directive `<!-- soleur:followthrough script=X -->` is malformed (no trailing newline before the closing `-->`), the awk loop may behave unexpectedly. The plan's golden fixture uses the canonical multi-line shape; if a future skill emits single-line, the precondition gate catches.
- **Sentinel-line drift.** The `# soleur:followthrough-stub v1` line is the anchor the test uses to confirm the template was copied (vs. hand-written). If a developer hand-writes a verification script (perfectly fine), the sentinel is absent — but the sentinel is checked on the *template* file, not on production scripts. Test assertion 2 grepts `references/followthrough-stub-template.sh` specifically.
- **`Closes #4190` semantic.** This is the rare follow-through-class plan where `Closes` is correct — the PR's pre-merge tests verify the rewrite contract. The rewrite has no post-merge verification step. Per `wg-use-closes-n-in-pr-body-not-title-to`, `Closes #4190` belongs in the PR body.
- **PR #4186 / #4188 are informational, not blocking.** This plan does NOT require either PR to land first. PR #4188 documents the rule this plan implements for /ship; PR #4186 is the model retrofit. Plan can ship orthogonally; if both land first, the changelog gets cleaner provenance text.
- **clo_routable deferral.** This plan does not migrate the cross-skill `/soleur:go` `clo_routable` routing field. The legal-attestation follow-through is documented via the operator-confirmation pattern (script-grep on `RESULT: PASS` comment), which is the new-convention equivalent. A separate scope-out is filed for the `/soleur:go` skill edit. Acceptable risk: legal-attestation follow-throughs filed during the gap render correctly under the new template (operator pastes `RESULT: PASS` after running `/soleur:go #N`), so no regression — the deferred work is a UX simplification, not a correctness fix.
- **Self-grep scope (2026-05-20 sharp edge).** Assertion 3 in `ship-followthrough-directive.test.sh` greps `plugins/soleur/skills/ship/SKILL.md` only — NOT the plan, tasks.md, or learnings. This is by design: the plan body contains the literal `type: manual` string as documentation of what's being removed; learnings at `2026-05-11-manual-dispatch-substitutes-for-scheduled-tick-when-external-dependency-resolves.md` and `workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md` contain `type: manual` as historical record. None of these are sweeper input. If a future change widens assertion 3's scope to `**/*.md`, those literals would false-positive — keep the scope narrow.
- **Parser-drift guard (verbatim copy).** The precondition-gate awk parser in SKILL.md Step 3.5.E and in `ship-followthrough-directive.test.sh` MUST be a verbatim copy of `scripts/sweep-followthroughs.sh:36-48`. Future edits to either copy without updating both create drift between the test-time gate and the sweep-time runtime. The plan does NOT prescribe a shared parser module (out of scope — would require Python/Bun script extraction); the verbatim-copy convention is the cheap defense. A test-helper that diffs the three copies could be added in a follow-up if drift surfaces.
- **PR #4188 already-merged.** The wg-rule `wg-pm-class-followthrough-for-operator-dogfood` is on main but not yet in this worktree's base. After this PR's automatic rebase-on-main during ship, the rule will be visible in AGENTS.md. Do NOT re-add it in this PR.

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here; threshold = `aggregate pattern`.

## References

- Issue: #4190
- Related PRs (informational, not blocking): #4186 (retrofit example), #4188 (wg-* rule)
- Canonical runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- Sweeper script: `scripts/sweep-followthroughs.sh`
- Sweeper workflow: `.github/workflows/scheduled-followthrough-sweeper.yml`
- Reference verification script: `scripts/followthroughs/sentry-checkins-3859.sh`
- Failure-mode learning: `knowledge-base/project/learnings/2026-05-20-test-stubs-env-and-csp-gates-miss-runtime-bugs.md`
- Current /ship Phase 7 Step 3.5 surface: `plugins/soleur/skills/ship/SKILL.md` lines ~1238-1316
