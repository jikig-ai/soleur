---
title: "fix: drift auto-close must not close issues with pending hcloud_server replacements"
date: 2026-10-02
slug: drift-autoclose-skip-hcloud-server-replacement
branch: feat-one-shot-drift-autoclose-hcloud-replace
pr: 9416
live_example: 9382
type: fix
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: drift auto-close must not close issues with pending hcloud_server replacements

Spec lacks a valid `lane:` (no spec.md exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`apply-deploy-pipeline-fix.yml` ends with the step "Auto-close any open drift issues for this stack". It closes
every open `infra-drift` issue whose title matches `infra: drift detected in web-platform` and comments
"Server state was re-aligned with HEAD". That sentence is a claim about the whole stack. The workflow can only
substantiate it for the five `terraform_data` resources it plans with `-target`; the drift issue is filed by
`scheduled-terraform-drift.yml` from an UNTARGETED `terraform plan -detailed-exitcode`. An issue whose plan
carries pending `hcloud_server` replacements (live: #9382 shows `hcloud_server.git_data` and
`hcloud_server.inngest` as `must be replaced`) is closed although nothing replaced those hosts, and the signal
has to be re-filed by the next drift scan.

The fix moves the close decision out of inline YAML into `scripts/infra-drift-autoclose.sh`, which reads each
candidate issue (body AND every comment), and closes it only when the evidence is readable, complete, and shows no
`hcloud_server` lifecycle action. Everything else is skipped with a `::notice::`. A committed suite
(`scripts/infra-drift-autoclose.test.sh`) pins the decision with synthesized fixtures and mutation-proves each
check. The workflow step keeps its name and its `if:` byte-for-byte (an existing AC18 pin in
`apps/web-platform/infra/infra-config-gate.test.sh` asserts the `if:` verbatim) and only its `run:` changes.

## Research Insights

### Premise Validation (Phase 0.6)

- `#9382` is OPEN ("infra: drift detected in web-platform"); its body carries `hcloud_server.git_data must be
  replaced` and `hcloud_server.inngest must be replaced` plus `Plan: 8 to add, 1 to change, 8 to destroy.` — the
  live example is real and currently reachable by the defective step (read with `gh issue view 9382 --json body`).
- PR #9416 is an open draft on this branch. No issue is cited as "to close": `#9382` must NOT be closed by this
  PR (the drift it records is still true). Do not write `Closes #9382` in the PR body.
- Cited paths verified on the worktree: the step at `.github/workflows/apply-deploy-pipeline-fix.yml`
  ("Auto-close any open drift issues for this stack"), `head -c 60000` and the `Plan output (truncated)` +
  `sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'` snippet in `.github/workflows/scheduled-terraform-drift.yml`.
- Mechanism vs ADR corpus: the mechanism (extract a decision script + suite) is not in any ADR's rejected
  alternatives; no architectural decision is made (see `## Architecture Decision`).

### Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| The drift filer HTML-escapes `& < >`, so match the escaped form | Only the EMAIL snippet path escapes (`scheduled-terraform-drift.yml`, `PLAN_SNIPPET=… sed 's/&/\&amp;/g…'`). The issue-body path `cat`s `plan-output.txt` raw — #9382's body contains zero entities. | Still match the escaped form (the brief requires it and a renderer/future producer can route escaped text into an issue): normalize entities and scan raw ∪ normalized. Record that today's issue bodies are raw. |
| The 4000-char snippet titled "Plan output (truncated)" is a truncation source | That title exists only in the email body, not the issue body. | Keep the title as one truncation signal (defense in depth) but do not rely on it: the load-bearing completeness test is a terminator check (below), because the 60000-byte `head -c` cut writes NO marker. |
| Body of the issue shows the plan | Only the FIRST detection writes the plan into the body. Every later scan on a still-open issue posts `Drift still present as of …` + the plan as a COMMENT (`scheduled-terraform-drift.yml`, the `EXISTING` branch). The body goes stale. | Read the body AND every comment (REST, paginated). A replacement in any plan-bearing artifact skips; any plan-bearing artifact that is incomplete skips. |
| Truncation detectable by size (60000) | `sed` redaction runs AFTER `head -c`, shrinking some lines, so a truncated file can land below 60000. A byte threshold is unsound. | Completeness = a terraform terminator is present: the `Plan: N to …` summary line OR the `Note: You didn't use the -out option` footer. Both print after every resource block, so either proves no resource block was cut. |

### Property List (Phase 0.6b)

1. A drift issue that shows a pending `hcloud_server` lifecycle action (replace/destroy/create) stays OPEN, and the
   skip is visible (`::notice::` naming the issue and the reason).
2. Evidence that is unreadable, empty, plan-less, truncated or otherwise not provably complete never yields a close.
3. A readable, complete issue with no `hcloud_server` action still closes, with a comment that does not overclaim.
4. The decision is testable without GitHub, and the workflow step only calls it.

### Cut List (Phase 0.6b)

| Mechanism considered | Property | Disposition |
|---|---|---|
| Close only if the plan touches nothing outside the five `-target` resources (allowlist) | would be the strict form of P1 | CUT — the untargeted plan is perpetually non-zero (`#7904`, noted in `scheduled-terraform-drift.yml`), so an allowlist never admits a real issue and silently disables the step. The brief scopes the defect to `hcloud_server`. |
| Re-run `terraform plan` inside this workflow to verify the host state | P1 | CUT — needs the apply credentials/state path, which the brief puts out of scope ("do not touch infra apply paths"). |
| Byte-size truncation detector (`>= 59000`) | P2 | CUT — redundant with, and weaker than, the terminator check (redaction shrinks lines after `head -c`). |
| Edit the drift issue (label / body note) when skipping | P1 visibility | CUT — `::notice::` in the run log is the required surface; editing the issue adds a write path for no property. |
| Patch `scheduled-terraform-drift.yml` to append an explicit truncation marker | P2 | CUT — out of scope; the terraform footer is already a natural terminator. Recorded below as the cheaper-in-future option. |
| Sentry / alert for skipped closes | — | OUT OF SCOPE (brief). |
| Same fix for `Close #4804 after self-heal verified` and the ledger `gh issue close` | — | NOT NEEDED — checked: the `#4804` step is keyed to one issue and a measured gate (`journald_storage.persistent == true`, plus its own `check_4804` open-state gate); the ledger close runs on an issue the script itself created. Neither closes an issue on a claim wider than what was measured. The drift step is the only `infra-drift` closer in `.github/workflows/` (`grep -rn infra-drift` finds no other). |

### Institutional learnings applied

- `2026-10-01-a-new-consumer-of-a-shared-format-rederives-it-and-the-copies-diverge-fail-open.md` — a new
  consumer of the drift-plan format re-deriving it is the divergence class; the plan therefore names the producer
  lines it parses (`head -c 60000`, the issue-body fence, the comment shape) and pins them with fixtures.
- `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` — the suite must exercise the close CALL
  (stub `gh issue close` recorded), not only the classifier.
- `#7104` verdict gating (comments in the workflow above the step) — the `if:` stays; this PR adds a second,
  evidence-based gate beneath the host-level gate.
- Open code-review overlap: see `## Open Code-Review Overlap`.

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user surface changes. The operator-facing failure is a
  drift issue (a pending production host replacement) closed or left open wrongly: either the next drift scan
  re-files it (today's behavior) or, if the new guard is over-broad, a stale-open issue the operator closes by hand.
- **If this leaks, the user's data is exposed via:** nothing — the script reads issue text through `gh` with the
  workflow's existing `GITHUB_TOKEN` and writes only a comment + close; no new credential, store or egress.
- **Brand-survival threshold:** `none`

`threshold: none, reason: the touched workflow path matches the infra sensitive-path regex only by filename; the change reduces auto-closing of an operator-facing drift signal and adds no user-data, credential or tenant-boundary surface.`

## Architecture Decision

No architectural decision: no new substrate, boundary or resolver; the step keeps its gate and gains an
evidence check. No ADR/C4 change. C4 completeness: external actors/systems touched are GitHub (issue tracker,
already modeled via the workflow→GitHub edges) and the existing `scheduled-terraform-drift` → `apply-deploy-pipeline-fix`
relationship; no actor, system or access relationship is added or changed. `plugins/soleur/test/c4-count-parity.test.sh`
is a derived-cardinality gate over workflow/monitor counts; this PR adds no workflow and no monitor, so it is
unaffected — confirm by running it once at work time (seconds).

## Infrastructure (IaC)

Not triggered: no server, service, secret, vendor account, DNS record or Terraform change; the diff touches a
workflow `run:` body, one repo script, one test suite and fixtures. No apply path is touched or run.

## Technical Design

### The script — `scripts/infra-drift-autoclose.sh`

Two modes, one decision function (single owner of the format knowledge):

- default: the loop used by the workflow step. `gh issue list --label infra-drift --state open -L 200 --search
  "infra: drift detected in web-platform in:title" --json number --jq '.[].number'` (unchanged query). A list
  failure is `::error::` + exit 1 (unchanged: the pre-change step aborted under `set -e` too). Per issue: read the
  body and ALL comments in ONE call (`gh issue view N --json body,comments`, stderr captured to a separate file so
  gh's own "new release" notice cannot corrupt the JSON — the precedent is `scripts/sweep-followthroughs.sh`, which reads
  `--json comments` the same way and fails closed on rc or unparseable JSON). A failing or unparseable read is
  `skip:gh-view-failed` — never a close. The JSON is reshaped with `jq` into the `--classify` envelope. Verdict
  `close` → one call `gh issue close N --reason completed --comment "<text>"` (atomic: the comment can no longer be
  posted on an issue the close then fails to close). Comment text: "Auto-closed by `apply-deploy-pipeline-fix.yml`
  after merge ${MERGE_SHA}. This workflow applies five terraform_data targets; the recorded drift plan(s) on this
  issue showed no pending hcloud_server replacement, so the drift is treated as re-aligned with HEAD." Anything not exactly `close` → `::notice::drift-autoclose: #N left OPEN (<reason>)`.
  Ends with a counter line `considered=C closed=X skipped=S close_failed=F`, mirrored with the per-reason skip
  counts to `$GITHUB_STEP_SUMMARY` (a loop that examined nothing says so, and a producer-format drift that makes
  every issue read `plan-incomplete` shows up as `closed=0` with a reason, not as silence). No conservation
  assertion: with one counter bumped per issue it is a tautology (plan-review).
- `--classify`: reads `{"body": <string>, "comments": [<string>,…]}` on stdin, never calls `gh`, prints exactly one
  line: `close` or `skip:<slug>`, exit 0. EMPTY or whitespace-only stdin is defined as the empty envelope
  (`skip:empty-body` — this is what the discoverability probe prints); non-empty malformed input is `skip:unparseable`. This is the test seam AND the
  discoverability probe (`## Observability`).

Decision function, evaluated per artifact over `T = raw ∪ normalized` (normalize = strip `\r`, decode
`&lt; &gt; &quot; &#39; &amp;` — `&amp;` last, applied twice so `&amp;quot;` also folds):

1. **replacement** — any artifact matches R1 or R2 → `skip:hcloud-server-replacement`.
   - R1: header line `# …hcloud_server.<address> … (must|will) be (replaced|destroyed|created)` (also covers
     `is tainted, so must be replaced` and `will be replaced, as requested`). The address token class is the
     Terraform one, written as the POSIX bracket expression `[][A-Za-z0-9_."'-]+` (`]` FIRST — backslash is literal
     inside a bracket expression, so the `\[\]` spelling ends the class at the first `]` and never matches an indexed
     address; plan-review verified this by running it), exact type `hcloud_server` — `hcloud_server_network.…` is NOT matched
     (boundary decision below).
   - R2: `-/+` or `+/-` followed by `resource "hcloud_server"`.
   - Scope decision (brief says replacement; the same defect applies to the other two lifecycle actions): `destroyed`
     and `created` are included — a pending server destroy/create is equally "host not re-aligned". In-place `~`
     updates are NOT included (ordinary drift noise, would disable the step).
2. **body readable** — body empty/whitespace → `skip:empty-body`; body not plan-bearing → `skip:no-plan-block`.
   Plan-bearing = contains `<summary>Plan output` (after normalization).
3. **truncation marker** — a plan-bearing artifact whose summary reads `Plan output (truncated)` →
   `skip:plan-truncated-marker`.
4. **completeness** — every plan-bearing artifact (body and comments) must contain a terraform terminator:
   `^Plan: [0-9]+ to ` or `^Note: You didn't use the -out option`. Missing → `skip:plan-incomplete`. Terminators sit
   after every resource block, so a `head -c 60000` cut (which writes no marker) cannot retain one unless nothing
   material was cut.
5. else `close`.

Boundary decision, stated so it is a decision and not an accident: a replacement of `hcloud_server_network`,
`hcloud_volume_attachment` or `hcloud_firewall_attachment` ALONE does not skip (those never reach the plan without
the server replacement in practice, and alone they are ordinary non-host drift). A fixture pins the near-miss.

### Why read comments (scope note)

Verified in `scheduled-terraform-drift.yml`: the first scan writes the plan into the issue body; every later scan on
the still-open issue posts the new plan as a comment. A clean body with a later replacement comment would otherwise
close. Union semantics (any artifact) are deliberately fail-closed: an issue that once showed a server replacement
and later looks clean stays open for a human to close — the safe error direction, and the issue's own "Next Steps"
already ends "Close this issue when resolved".

### Workflow change — `.github/workflows/apply-deploy-pipeline-fix.yml`

Replace only the step's `run:` body with `bash "${GITHUB_WORKSPACE}/scripts/infra-drift-autoclose.sh"`. Keep the
step `name`, the `if:` (pinned verbatim by `apps/web-platform/infra/infra-config-gate.test.sh` AC18), and `env`
(`GH_TOKEN`, `MERGE_SHA`). Update the comment block above the step to say the decision lives in the script and why.
`permissions: issues: write` already covers comment+close and the issue read. The `on.push.paths` filter lists neither the script nor the workflow file itself (verified on this branch), so
merging this PR does not trigger an apply run; keep it that way (Sharp Edges).

### Test suite — `scripts/infra-drift-autoclose.test.sh`

House style, copied from `scripts/infra-config-red-alert.test.sh`: single owning sandbox + EXIT trap
(ADR-129 / `#8659`), `CASES` incremented at every call site, accounting identity `PASS+FAIL == CASES` reported
directly, known-negative self-test of `bad()`, then a literal-threshold floor
`DRIFT_MIN_ASSERTIONS=<n>` with `if [[ "$CASES" -lt "$DRIFT_MIN_ASSERTIONS" ]]` reporting via `printf`+`exit 1` (not through
`bad()`), so `scripts/guard-vacuity-floor.test.sh` scores it FIRES. All paths rooted at `$HERE`/`$SANDBOX_ROOT`
(keeps `fixture-relative-assert` and `fixture-dir-operand-assert` baselines unchanged — no `--write-baseline`).

Fixtures are SYNTHESIZED (`cq-test-fixtures-synthesized-only`) under `scripts/fixtures/infra-drift-autoclose/`
(no real ids, tokens or issue text; ids like `1111111`):

| Fixture | Shape | Expected |
|---|---|---|
| `replacement-present.body.md` | full first-detection body, `# hcloud_server.web["web-2"] must be replaced`, `-/+ resource "hcloud_server" "web" {`, `Plan:` + footer | `skip:hcloud-server-replacement` |
| `replacement-escaped-only.body.md` | same, but quotes entity-escaped (`&quot;`) so R1's address class and R2 cannot match raw | `skip:hcloud-server-replacement` |
| `truncated-cut.body.md` | plan cut mid-resource-block, no `Plan:`/footer, no marker, nothing hcloud-looking in the retained prefix | `skip:plan-incomplete` |
| `truncated-title.body.md` | otherwise complete plan whose summary is `Plan output (truncated)`; a second variant has the summary entity-escaped | `skip:plan-truncated-marker` |
| `clean.body.md` | complete plan: in-place `hcloud_firewall_attachment`, `terraform_data.deploy_pipeline_fix must be replaced`, `hcloud_server.web["web-1"]: Refreshing state...`, `hcloud_server_network.x must be replaced` (near-miss) | `close` |
| `clean-crlf.body.md` | the clean body with CRLF line endings (GitHub-edited bodies) | `close` |
| `replacement-crlf.body.md` | the replacement body with CRLF | `skip:hcloud-server-replacement` |
| (inline) empty body | `{"body":"","comments":[]}` | `skip:empty-body` |
| (inline) empty stdin / malformed JSON | `printf ''` and `not json` | `skip:empty-body` / `skip:unparseable` |
| (inline) no plan block | human-written body, no `<summary>Plan output` | `skip:no-plan-block` |
| comment fixtures | clean body + later comment with replacement; clean body + later comment truncated; clean body + clean comment | skip / skip / `close` |
| R1 variant table (inline) | indexed address `hcloud_server.web["web-2"] must be replaced`, `is tainted, so must be replaced`, `will be replaced, as requested`, `will be destroyed`, `will be created`, module-prefixed address | each `skip:hcloud-server-replacement` |
| gh stub e2e | `gh issue view` fails; `gh issue view` returns unparseable JSON; `gh issue list` fails; two issues (clean then replacement) | skip / skip / `::error::` rc 1 / exactly one `gh issue close` call, for the clean one, with `--reason completed` |

The stub `gh` dispatches on argv (it refuses unknown calls with rc 64 and records every call), so a close issued on
the wrong path is observable. A static arm extracts the workflow step by name with `python3` + `yaml` and asserts
its `run:` invokes the script and contains no `gh issue close`, and that `GH_TOKEN`/`MERGE_SHA` are in its `env`.

In-suite mutation battery: each row copies the script into the sandbox, applies one `sed` edit anchored on a FUNCTION
name (not a line number), asserts the edit changed the file (a no-op mutant is a harness FATAL — a vacuous row), and
asserts the targeted fixture's verdict flips to `close` / the stub records a wrong close. See Guard Contract.

### Registration

`scripts/test-all.sh`: one explicit line beside its siblings —
`run_suite "scripts/infra-drift-autoclose" bash scripts/infra-drift-autoclose.test.sh` (next to
`scripts/infra-config-red-alert`). it sits inside the `if want_scripts;` block like its siblings; `scripts/*.test.sh` is not auto-globbed there; `scripts/lint-orphan-test-suites.sh`
reds an unregistered suite. It is cheap, so it takes NO relevance gate. The shard manifest hash-falls-back for an
unlisted label, so `scripts/suite-shard-legs.tsv` is left alone (no regenerate; not a positional insert).
`scripts/guard-vacuity-floor.test.sh` derives the population by shape: after the suite exists, run it once and, if the
new suite scores FIRES, raise `MIN_FIRING_SUITES` by the measured delta only if the ratchet is tight (it is `>=`, grows only; expect no bump if the live population sits well above the floor). Confirm the new label's leg once with `test-all.sh`'s enumerate mode rather than assuming the hash fallback (the #9173 shard-parity regression is why).

## Guard Contract

### Guard 1 — drift auto-close classifier

**Property.** A drift issue is closed only when its body and every comment are readable, every plan they carry is
provably complete, and no plan in them shows an `hcloud_server` replace/destroy/create — for every input shape, not
just the ones fixtured.

**Assembly.** The property quantifies over: (a) the ARTIFACT set — the issue body AND all comments (one `gh issue view --json body,comments` read),
not "the body"; (b) the FORM set — raw text, CRLF, and entity-escaped text (`&lt; &gt; &amp; &quot; &#39;`, single and
double escaped), all folded by one `normalize` before one match; (c) the ACTION set — `must be replaced`,
`will be replaced`, `is tainted, so must be replaced`, `will be destroyed`, `will be created`, and the `-/+`/`+/-`
resource marker; (d) the EVIDENCE-QUALITY set — empty, no plan block, truncation marker, missing terminator, gh read
failure (body or comments); (e) the CLOSE chokepoint — the single `gh issue close` call in the script's loop, reachable
only when the verdict string is exactly `close`. Members drift; the chokepoint is structural: classification and the
close call share one function so no second path can close.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Neuter the replacement check (`has_hcloud_replacement` → `return 1`) | RED: `replacement-present`, R1 variant table and CRLF replacement fixtures flip to `close` |
| 2 | Neuter `normalize` (identity function) | RED: `replacement-escaped-only` and the escaped `truncated-title` flip to `close` |
| 3 | Neuter the terminator check (`has_complete_terminator` → `return 0`) | RED: `truncated-cut` flips to `close` |
| 4 | Neuter the truncation-marker check (`has_truncation_marker` → `return 1`) | RED: `truncated-title` (both variants) flip to `close` |
| 5 | Treat a failed `gh issue view` / comments read as an empty-but-OK read (swallow the non-zero rc) | RED: the gh-failure arms record a `gh issue close` |
| 6 | Treat an empty body as clean (remove the `empty-body` / `no-plan-block` guard) | RED: empty and no-plan fixtures flip to `close` |
| 7 | Dispatch: replace the classifier call in the loop with a constant `close` (loop "runs", decides nothing) | RED: every skip e2e arm records a close |
| 8 | Second member after a compliant first: classify only the FIRST artifact (body) and apply it to all (comments ignored) | RED: `clean body + later replacement comment` flips to `close` |
| 9 | Second member after a compliant first: evaluate only the FIRST issue of the list and reuse its verdict | RED: two-issue e2e records a close for the replacement issue |
| 10 | Reorder: move the terminator check so it runs only on the body, not on plan-bearing comments | RED: `clean body + later truncated comment` flips to `close` |
| 11 | Narrow R1's action alternation to `must be replaced` only | RED: the `will be destroyed` / `will be created` / `will be replaced` table rows flip |

**Harness rows (edits to the SUITE, not the script):**

| # | Edit | Expected |
|---|---|---|
| H1 | Swap `bad()` to record a pass (as in `infra-config-red-alert.test.sh`'s measured swap) | RED via the known-negative self-test |
| H2 | Delete a fixture file / empty the `clean` fixture | RED: fixture-existence floor (each file present and non-empty) |
| H3 | Make the stub `gh issue close` a silent no-op that records nothing | RED: the "exactly one close call, correct issue" assertion |
| H4 | Drop a case call-site `CASES` increment | RED: accounting identity `PASS+FAIL != CASES` |

Must-PASS inputs that are NOT the canonical: `clean-crlf.body.md` (permitted CRLF), `clean body + clean comment`, a
body whose retained text contains `hcloud_server.web["web-1"]: Refreshing state...` and
`hcloud_server_network.x must be replaced` (near-miss) — a guard that rejects everything cannot pass these.
**Anchor.** Not applicable: the verdict is computed from the live issue text on every run; no stored hash, count
or registry is compared.

**Over-time check.** The mutation that defeats this guard AFTER the change lands: the producer starts emitting a
different terminator (e.g. an upgraded terraform rewords the footer) — then every real issue reads
`plan-incomplete` and the step silently never closes anything. Bound: the script's counter line and step summary report
`skipped` per reason, and the fixtures carry the terraform 1.10.5 shapes the workflow pins
(`TERRAFORM_VERSION`); an upgrade PR's own review is the place to re-check the two terminators (Sharp Edges).

### Guard 2 — workflow wiring

**Property.** The auto-close step performs no inline close: the only path from "verdict verified" to
`gh issue close` runs through `scripts/infra-drift-autoclose.sh`.

**Assembly.** The step is located BY NAME in `.github/workflows/apply-deploy-pipeline-fix.yml` (parsed with `yaml`,
not grepped), and its `run:` is the only code that can reach `gh issue close` for `infra-drift` issues — confirmed
repo-wide by `grep -rn infra-drift .github/workflows/` (one closer). Members drift (a later edit can paste the old
loop back or add a second step); the structural check is "this named step's `run:` equals one script invocation and
contains no `gh issue close`".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| W1 | Paste `gh issue close "$n"` back into the step's `run:` | RED: no-inline-close assertion |
| W2 | Change the invoked path (`scripts/infra-drift-autoclose.sh` → `scripts/does-not-exist.sh`) | RED: the invoked path must resolve to a tracked, executable file |
| W3 | Rename the step (the locator finds nothing) | RED: step-found assertion reports 0 matches rather than passing vacuously |

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions run annotations from the auto-close step — one ::notice:: per issue left open, one line per issue closed, and a final counter line considered=C closed=X skipped=S close_failed=F"
  cadence: per apply-deploy-pipeline-fix run that reaches the step (push to main touching the infra paths, or workflow_dispatch)
  alert_target: the workflow run page (annotations) — no new paging channel; a Sentry or alert change is out of scope by brief
  configured_in: scripts/infra-drift-autoclose.sh, invoked from .github/workflows/apply-deploy-pipeline-fix.yml
error_reporting:
  destination: GitHub Actions annotations (::error:: / ::warning::) — CI script, not application server code; the repo's Sentry mirror rule targets app runtime paths
  fail_loud: "::error:: and exit 1 when the issue list cannot be read; ::warning:: when a close call fails"
failure_modes:
  - mode: "the gh issue read (body and comments) fails or is unparseable for an issue"
    detection: "::notice:: reason=gh-view-failed and the issue stays open; counted in skipped"
    alert_route: run annotations
  - mode: "producer changes its terminator or truncation shape so every issue reads plan-incomplete"
    detection: "final counter line shows closed=0 with skipped>0 on runs that previously closed; the fixtures pin the terraform 1.10.5 shapes"
    alert_route: run annotations plus review of any terraform version bump
  - mode: "close call fails after a clean verdict"
    detection: "::warning:: close_failed counted; loop continues to the next issue"
    alert_route: run annotations
logs:
  where: the apply-deploy-pipeline-fix run log for the step "Auto-close any open drift issues for this stack"
  retention: the repository Actions log retention setting (GitHub default 90 days)
discoverability_test:
  command: printf '' | bash scripts/infra-drift-autoclose.sh --classify
  expected_output: skip:empty-body
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI workflow/tooling change; no user-facing UI, legal, financial or marketing
surface. GDPR gate (`2.7`): no regulated-data surface (the script handles issue text about infrastructure only) and
none of the (a)-(d) expansion triggers fire.

## Files to Edit

- `.github/workflows/apply-deploy-pipeline-fix.yml` — step "Auto-close any open drift issues for this stack": replace
  `run:` with the script call; keep `name`, `if:`, `env`; refresh the comment above it.
- `scripts/test-all.sh` — one `run_suite "scripts/infra-drift-autoclose" …` line beside `scripts/infra-config-red-alert`.
- `scripts/guard-vacuity-floor.test.sh` — raise `MIN_FIRING_SUITES` by the measured delta ONLY if the new suite scores
  FIRES (measure first; do not guess).

## Files to Create

- `scripts/infra-drift-autoclose.sh` (mode 100755)
- `scripts/infra-drift-autoclose.test.sh` (mode 100755)
- `scripts/fixtures/infra-drift-autoclose/*.body.md` — the seven file fixtures in the table above (synthesized).

## Open Code-Review Overlap

2 open scope-outs touch a planned file, both on `scripts/test-all.sh`:

- #8659 (33 suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct runs) —
  **Acknowledge:** this plan does not fix the 33 existing suites; the new suite owns a single sandbox root + EXIT trap
  from the start (ADR-129 rule c) so it adds no 34th. The issue stays open.
- #7942 (two mutation batteries named `*.mutation.sh` run in no gate) — **Acknowledge:** different concern (naming
  convention of two other batteries); this suite is `*.test.sh` and registered.

No open code-review issue names `.github/workflows/apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml` or
the new paths.

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`); the Guard Contract matrix above is written BEFORE the script.

1. **RED — fixtures and suite skeleton.** Synthesize the seven fixtures; write `infra-drift-autoclose.test.sh` with the
   harness (sandbox/trap, `CASES`, accounting identity, self-test, floor), the `--classify` table arms, the stub-`gh`
   e2e arms, the workflow wiring arm and the mutation battery. The script does not exist yet: every arm reds.
2. **GREEN — the script.** Write `scripts/infra-drift-autoclose.sh` with the functions the mutation rows anchor on
   (`normalize`, `has_hcloud_replacement`, `is_plan_bearing`, `has_truncation_marker`, `has_complete_terminator`,
   `classify`), the `--classify` mode and the loop. Use `if grep …; then` forms and explicit `|| rc=$?` captures (no
   bare `x=$(grep …)` under errexit — `lint-shell-capture-exit`); no `-e` in the script; every `gh` call is captured into a variable with an explicit `|| rc=$?`, never inside a pipeline (a failing producer is masked by the consumer's rc 0, and `printf '' | jq -s 'add // []'` prints `[]`).
3. **Wire the step.** Swap the `run:` body; confirm `apps/web-platform/infra/infra-config-gate.test.sh` AC18's pinned
   `if:` text is untouched (compare the step's `if:` before/after with `git diff`).
4. **Register + ratchets.** Add the `run_suite` line; set `DRIFT_MIN_ASSERTIONS` to the measured green count; run the
   targeted gates once each (all seconds): the new suite, `scripts/lint-orphan-test-suites.sh`,
   `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/fixture-relative-assert.test.sh`,
   `plugins/soleur/test/fixture-dir-operand-assert.test.sh`, `shellcheck` on both scripts, `scripts/lint-guard-contract.py`
   on this plan. No full battery locally — CI runs the rest.
5. **Mutation proof, recorded.** Run the in-suite battery (it is part of the suite) AND once by hand delete the
   replacement check from a sandbox copy to watch `replacement-present` flip red; paste the measured red output into
   the PR body (not in a repo file).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The decision lives in `scripts/infra-drift-autoclose.sh`; the workflow step's `run:` is one invocation of it and
  contains no `gh issue close` (asserted by the suite's wiring arm, `scripts/infra-drift-autoclose.test.sh` › workflow
  wiring; guards W1-W3).
- [ ] An issue whose body or any comment shows an `hcloud_server` replace/destroy/create (raw or entity-escaped, LF or
  CRLF) is skipped with `::notice::drift-autoclose: #N left OPEN (hcloud-server-replacement)` and is never passed to
  `gh issue close` (`scripts/infra-drift-autoclose.sh` › `classify`, `has_hcloud_replacement`; suite fixtures
  `replacement-*.body.md`, R1 table).
- [ ] An issue whose plan cannot be shown complete (no `Plan:`/footer terminator in any plan-bearing artifact, or a
  `Plan output (truncated)` summary, raw or escaped) is skipped (`has_complete_terminator`, `has_truncation_marker`;
  fixtures `truncated-cut`, `truncated-title`).
- [ ] An empty body, a body with no plan block, and a failed or unparseable `gh issue view` each skip; none
  closes (`classify` empty/no-plan arms; the loop's `gh-view-failed` arm; stub-`gh` e2e).
- [ ] A readable complete issue with no `hcloud_server` action (including the near-miss `hcloud_server_network` row, the
  refresh line, the CRLF variant and clean-body + clean-comment) is closed by exactly one
  `gh issue close N --reason completed --comment …` call.
- [ ] The step's `name`, `if:` and `env` keys are unchanged (`git diff` shows only the `run:` body and the comment block
  above it); `apps/web-platform/infra/infra-config-gate.test.sh` AC18 stays green.
- [ ] Suite registered in `scripts/test-all.sh` (`lint-orphan-test-suites` green); carries a literal-threshold
  `CASES` floor reported via `printf`+`exit 1`, an accounting identity and the known-negative `bad()` self-test;
  `scripts/guard-vacuity-floor.test.sh` scores it FIRES (and `MIN_FIRING_SUITES` is raised by the measured delta).
- [ ] Mutation battery rows 1-11 and W1-W3 each flip their targeted verdict (every mutant is asserted to differ from
  the original script — no no-op rows); harness rows H1-H4 each red.
- [ ] `fixture-relative-assert` and `fixture-dir-operand-assert` baselines unchanged (no `--write-baseline`); fixtures
  synthesized only.
- [ ] `lint-guard-contract.py` passes on this plan; PR body states `Ref #9382` (NOT `Closes`) and records the manual
  delete-the-check red output.

### Post-merge (non-blocking)

- [ ] On the next natural run of the step while #9382 is still open, its log shows `left OPEN (hcloud-server-replacement)`
  for #9382 and the counter line. No production workflow is dispatched to produce this; `soleur:postmerge` reads the
  run via `gh run view`.

## Test Scenarios

- Given #9382's shape (replacement in body, complete terminators), when the step runs, then #9382 stays open with a notice.
- Given a clean body and a later `Drift still present` comment showing `hcloud_server.x must be replaced`, then it stays open.
- Given a body cut by `head -c 60000` mid-block, then it stays open (`plan-incomplete`) even though nothing hcloud-looking is visible.
- Given `gh issue view` failing for one of two listed issues, then the other is still evaluated and only a clean one is closed.
- Given an empty list, then the counter line reads `considered=0 closed=0 skipped=0 close_failed=0` and the step exits 0.
- Given `gh issue list` failing, then `::error::` and exit 1 (pre-change behavior preserved).

## Sharp Edges

- **Do not write `Closes #9382`** — the drift that issue records is real and the fix must leave it open.
- The workflow's `if:` is pinned verbatim by `apps/web-platform/infra/infra-config-gate.test.sh` (AC18); editing it
  there without updating the pin reds the infra suite.
- The terminator regexes and the `Plan output (truncated)` title are a copy of the producer's format
  (`scheduled-terraform-drift.yml`, terraform `TERRAFORM_VERSION` in the workflow). A terraform bump that rewords
  `Note: You didn't use the -out option` degrades to "never closes" (fail-closed), not "closes wrongly" — re-check on a
  version bump. The cheaper long-term form is the producer emitting an explicit end marker (cut above).
- Union semantics mean an issue whose body or any comment ever showed a server replacement never auto-closes, even after
  the host was replaced; the operator closes it by hand ("Close this issue when resolved" is already in its Next
  Steps). This is intentional and recorded in `decision-challenges.md`; the `::notice::` says so.
- A script-only edit must not fire an apply: confirm none of the new paths appear in the workflow's `on.push.paths`
  (`grep -n "scripts/" .github/workflows/apply-deploy-pipeline-fix.yml`); do not add them.
- Mutation rows anchor on function NAMES; if a function is renamed in implementation, update the matrix in the same
  edit or the row becomes a no-op mutant (the harness FATALs on that, by design).
- `gh issue view --json body,comments` must return EVERY comment on a long-lived issue: before relying on it, check on
  any issue with more than 100 comments that `.comments | length` equals the REST count
  (`gh api repos/<o>/<r>/issues/<n> --jq .comments`). If gh truncates, fall back to
  `gh api repos/$GITHUB_REPOSITORY/issues/N/comments --paginate --jq '[.[].body]' | jq -s 'add // []'` (the filter runs
  per page — slurp, or only the last page survives).
- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6; this one carries the
  `none` threshold with its scope-out reason (the touched workflow path matches the sensitive-path regex).
