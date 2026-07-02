---
title: Extend terraform -target parity guard to cover apply-sentry-infra.yml
issue: 5884
type: chore
branch: feat-one-shot-5884-sentry-target-parity
lane: single-domain
brand_survival_threshold: none
created: 2026-07-02
status: planned
---

# ♻️ chore: Extend terraform `-target` parity guard to cover `apply-sentry-infra.yml` issue-alerts/monitors

Closes #5884.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: no NEW infrastructure. The change wires an already-authored
     terraform resource into the existing apply-sentry-infra.yml apply path; the only
     "operator" reference is a read-only Sentry audit + `gh workflow run` (no SSH, no
     manual install). See ## Infrastructure (IaC). -->

## Overview

`apps/web-platform/infra/sentry/*.tf` is applied by `.github/workflows/apply-sentry-infra.yml`
via an **explicit `-target=` list** in its `terraform plan`/`apply` step, not a
whole-directory apply. A new `sentry_issue_alert` / `sentry_cron_monitor` /
`sentry_uptime_monitor` added to a `.tf` file but forgotten in that `-target=`
list ships in code, passes `terraform validate`, and is **never applied to
Sentry** — an inert alert/monitor with zero runtime signal.

The existing parity guard `plugins/soleur/test/terraform-target-parity.test.ts`
(#5566) covers only `apply-web-platform-infra.yml` + `apply-deploy-pipeline-fix.yml`
against the **main** `apps/web-platform/infra/` tree. It never reads
`apply-sentry-infra.yml` or the `infra/sentry/` root — so the Sentry apply pipeline
has **no drift guard**. This bug has bitten twice already (learning
`2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target.md`;
again in #5875 PR1's `sandbox_startup_failure`).

This plan extends the existing test with a Sentry `describe` block that asserts
every apply-created Sentry resource is either `-target`ed or in a documented
import-only exclusion set — converting "new Sentry alert forgotten in `-target`"
from a silent post-merge inert-alert into a **red test at PR time**.

## Research Insights (verified against worktree, 2026-07-02)

All counts and file paths below were grepped/read directly; no paraphrase from
the issue body.

| Sentry resource type | resources in `infra/sentry/*.tf` | `-target=` lines in workflow | parity |
|---|---|---|---|
| `sentry_cron_monitor`  | 44 | 44 | ✅ fully covered |
| `sentry_uptime_monitor`| 4  | 4  | ✅ fully covered |
| `sentry_issue_alert`   | 19 | 14 | ⚠️ 5-resource gap (see below) |

**The 5-alert issue-alert gap resolves into two classes** (discriminated by
`conditions_v2` shape + the `issue-alerts.tf` header, which states
"IMPORT-ONLY: these resources mirror existing Sentry rules created by the legacy
script. Operator runs `terraform import ...` BEFORE the first apply"):

1. **4 import-only placeholders — correctly un-targeted (exclude):**
   `auth_callback_no_code_burst`, `auth_exchange_code_burst`, `auth_per_user_loop`,
   `auth_signout_burst`. Each has `conditions_v2 = []` + `lifecycle { ignore_changes
   = [conditions_v2, …] }` and the header comment "placeholder is overwritten by
   import." Added in #3811. A target-scoped apply would try to **create a duplicate**
   Sentry rule — they must NOT be targeted. → documented exclusion set.

2. **1 apply-created alert — a genuine MISS (fix):**
   `github_webhook_founder_ambiguous` (added #5482). It carries the real firing
   triple `action_match = "any"` + `conditions_v2 = [{first_seen_event={}},
   {reappeared_event={}},{regression_event={}}]` (byte-identical shape to the
   apply-created, targeted siblings `egress_blocked` / `chat_message_save_failure`)
   and `lifecycle { ignore_changes = [environment] }` **only** — no `conditions_v2`
   ignore. It is **not** in the workflow `-target` set → it is currently an inert
   alert with zero runtime signal: a live *third* instance of the exact bug #5884
   exists to catch. **This PR fixes it by adding its `-target` line** (see Phase 2).

**Why fix (fold-in) rather than snapshot/exclude:** the new guard must be green at
merge. `github_webhook_founder_ambiguous` is neither targeted nor an import-only
placeholder; excluding an apply-created alert would *mask* the very bug the guard
catches. Targeting it is the only correct way to make the guard green — and it
restores the intended live alert (`rf-review-finding-default-fix-inline`).

**Reusable helpers already in the test file** (#5566 block): `stripComments`,
`extractAllResources` (matches `resource "<type>" "<name>"`, excludes `data`
sources), `extractAllTargets` (matches `-target=<type>.<name>`). Sentry types are
lowercase-underscore, so both regexes match Sentry addresses unchanged. `main.tf`
holds only the `provider` block + a `data "sentry_project"` source (no managed
resource) → `extractAllResources` correctly returns nothing from it.

**Separate terraform root:** `infra/sentry/` has its own R2 backend state key
(`web-platform/sentry/terraform.tfstate`, `use_lockfile = false`) and its own
`versions.tf`/`.terraform.lock.hcl`. It does NOT share the
`terraform-apply-web-platform-host` concurrency group — so the concurrency-group /
cloudflared-pin parity block (#4844) is **out of scope** for this workflow (Non-Goals).

**Premise validation (Phase 0.6):** all cited artifacts exist and hold — the test
file, `apply-sentry-infra.yml`, the 4 sentry `.tf` files, the #5875 commit
`63ec236d6` (`sandbox_startup_failure` target registration), and the cited learning.
`kb_tenant_mint_silent_fallback` (#4929 orphan) is confirmed absent from the `.tf`
(state-only orphan) → correctly invisible to `extractAllResources`; reverse-direction
"target points at nothing" remains out of scope (same documented limitation as the
existing guard). Cited-mechanism check vs ADR corpus: consistent with ADR-031
(Sentry-as-IaC); no rejected-alternative collision.

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing artifact — this
is a CI test guard + one alert-target registration. The *downstream* user impact of
the class this guard protects: a webhook founder-attribution failure
(`github_webhook_founder_ambiguous`) firing with **no page reaching the operator**,
so a broken GitHub-webhook attribution path degrades silently.
**If this leaks, the user's data is exposed via:** N/A — the diff touches a bun test
and a CI workflow's `-target` list; it moves no user data and adds no data-processing.
**Brand-survival threshold:** none.
`threshold: none, reason: change is a CI drift-guard test + a single terraform -target
registration for an already-authored resource; no auth/schema/migration/API-route/
user-data surface is touched.`

## Files to Edit

- `plugins/soleur/test/terraform-target-parity.test.ts` — add the Sentry parity
  `describe` block (#5884): new `SENTRY_INFRA_DIR` / `SENTRY_WORKFLOW` constants, a
  frozen `SENTRY_IMPORT_ONLY_EXCLUSIONS` set (the 4 `auth_*` placeholders), a
  `listSentryTfFiles()` walker, and the parity + non-vacuity + regression-anchor
  tests. Reuses `stripComments` / `extractAllResources` / `extractAllTargets`.
- `.github/workflows/apply-sentry-infra.yml` — add **one** line
  `-target=sentry_issue_alert.github_webhook_founder_ambiguous \` inside the
  backslash-continued `terraform plan` command (after the `sandbox_startup_failure`
  target line 258, before `-no-color`). The apply step reuses the saved `tfplan`
  (line ~309 `terraform apply … tfplan`), so only the `plan` step's list needs the
  new target — **verify** the apply step does not re-declare its own `-target` list.
  NOTE: comments must NEVER sit inside the backslash-continued command
  (mid-continuation comment → exit 127, PR #5108).

## Files to Create

- None. (The plan extends the existing test file per the issue's preferred option;
  a sibling test file was considered and rejected — see Alternatives.)

## Implementation Phases

### Phase 1 — RED: add the Sentry parity describe block (test first)

Add to `terraform-target-parity.test.ts`:

```ts
const SENTRY_INFRA_DIR = resolve(REPO_ROOT, "apps/web-platform/infra/sentry");
const SENTRY_WORKFLOW = resolve(REPO_ROOT, ".github/workflows/apply-sentry-infra.yml");

// Import-only sentry_issue_alert placeholders (conditions_v2 = []), created in
// Sentry via `terraform import` of legacy configure-sentry-alerts.sh rules (see
// issue-alerts.tf header + learning 2026-06-12-detector-cron-must-route-…). They
// are DELIBERATELY absent from apply-sentry-infra.yml's -target set — a
// target-scoped apply would try to CREATE a duplicate live rule. FROZEN: do NOT
// grow. A NEW apply-created alert (real conditions_v2) must be TARGETED, not
// added here.
const SENTRY_IMPORT_ONLY_EXCLUSIONS = new Set<string>([
  "sentry_issue_alert.auth_callback_no_code_burst",
  "sentry_issue_alert.auth_exchange_code_burst",
  "sentry_issue_alert.auth_per_user_loop",
  "sentry_issue_alert.auth_signout_burst",
]);

// Floor sentinel — 67 managed resources today (44 cron + 4 uptime + 19 alert).
// `>=` (not `===`) so adding a resource raises the count without a brittle edit;
// the parity assertion enforces correctness, this only guards a parser collapse.
const SENTRY_MIN_RESOURCES = 60;

function listSentryTfFiles(): string[] {
  return readdirSync(SENTRY_INFRA_DIR)
    .filter((f) => f.endsWith(".tf"))
    .map((f) => resolve(SENTRY_INFRA_DIR, f))
    .sort();
}

describe("terraform -target parity — Sentry infra issue-alerts/monitors (#5884)", () => {
  let sentryResources: string[];
  let sentryTargets: Set<string>;

  beforeAll(() => {
    expect(existsSync(SENTRY_INFRA_DIR)).toBe(true);
    expect(existsSync(SENTRY_WORKFLOW)).toBe(true);
    sentryResources = listSentryTfFiles()
      .flatMap((f) => extractAllResources(stripComments(readFileSync(f, "utf8"))))
      .filter((a) => a.startsWith("sentry_"));
    sentryTargets = extractAllTargets(readFileSync(SENTRY_WORKFLOW, "utf8"));
  });

  test(`discovers >= ${SENTRY_MIN_RESOURCES} managed sentry resources (non-vacuity)`, () => {
    expect(sentryResources.length).toBeGreaterThanOrEqual(SENTRY_MIN_RESOURCES);
  });

  test("every apply-created sentry resource is targeted (or a documented import-only exclusion)", () => {
    const uncovered = sentryResources.filter(
      (a) => !sentryTargets.has(a) && !SENTRY_IMPORT_ONLY_EXCLUSIONS.has(a),
    );
    // Non-empty ⇒ a new sentry resource was added without a -target line (the
    // inert-alert class) — add the -target to apply-sentry-infra.yml, or (only
    // for a genuine import-only placeholder) add it to SENTRY_IMPORT_ONLY_EXCLUSIONS.
    expect(uncovered).toEqual([]);
  });

  test("the #5875 regression anchor (sandbox_startup_failure) stays targeted", () => {
    expect(sentryTargets.has("sentry_issue_alert.sandbox_startup_failure")).toBe(true);
  });

  test("the 4 import-only auth_* placeholders are present in .tf yet NOT targeted", () => {
    for (const a of SENTRY_IMPORT_ONLY_EXCLUSIONS) {
      expect(sentryResources).toContain(a);
      expect(sentryTargets.has(a)).toBe(false);
    }
  });

  test("guard FAILS on a synthetic un-targeted apply-created alert (non-vacuity)", () => {
    const synthetic = `resource "sentry_issue_alert" "synthetic_forgotten_alert" { project = "x" }`;
    const parsed = extractAllResources(stripComments(synthetic)).filter((a) =>
      a.startsWith("sentry_"),
    );
    expect(parsed).toEqual(["sentry_issue_alert.synthetic_forgotten_alert"]);
    const uncovered = parsed.filter(
      (a) => !sentryTargets.has(a) && !SENTRY_IMPORT_ONLY_EXCLUSIONS.has(a),
    );
    expect(uncovered).toEqual(["sentry_issue_alert.synthetic_forgotten_alert"]);
  });
});
```

Run `bun test plugins/soleur/test/terraform-target-parity.test.ts`. Expect the
**"every apply-created sentry resource is targeted"** test to FAIL, reporting
`["sentry_issue_alert.github_webhook_founder_ambiguous"]` uncovered. This RED is
the guard proving itself against the live latent miss.

### Phase 2 — GREEN: register the missing apply-created alert

Add exactly this line to `apply-sentry-infra.yml`'s `terraform plan` command,
immediately after line 258 (`-target=sentry_issue_alert.sandbox_startup_failure \`)
and before line 259 (`-no-color -input=false -out=tfplan`), inside the
backslash-continuation (no adjacent comment):

```
            -target=sentry_issue_alert.github_webhook_founder_ambiguous \
```

Confirm the `terraform apply` step reuses the saved `tfplan` (line ~309) and does
**not** re-declare its own `-target` list (if it does, add the line there too).
Re-run the test → all Sentry-block tests GREEN.

### Phase 3 — full-suite regression + docs

- Run the full parity suite (`bun test plugins/soleur/test/terraform-target-parity.test.ts`)
  and the broader bun test surface for the plugin to confirm no sibling regression.
- No README/component-count change (test files are not plugin components).
- PR body: `## Changelog` section (`semver:patch` — bug-class guard + one target),
  `Closes #5884`, and a one-line note that the guard's introduction surfaced and
  fixed a live inert alert (`github_webhook_founder_ambiguous`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes; the new
      `#5884` describe block runs ≥ 5 assertions.
- [ ] The Sentry parity test returns `[]` uncovered — i.e. every `sentry_*` resource
      in `infra/sentry/*.tf` is either in the workflow `-target` set OR in
      `SENTRY_IMPORT_ONLY_EXCLUSIONS` (the 4 `auth_*` placeholders).
- [ ] `grep -c '\-target=sentry_issue_alert.github_webhook_founder_ambiguous'
      .github/workflows/apply-sentry-infra.yml` returns `1`, and the line sits
      inside the backslash-continued `terraform plan` block (not after `-no-color`,
      not adjacent to a comment).
- [ ] Synthetic-fixture test proves the guard FAILS on a new un-targeted
      apply-created alert (non-vacuity).
- [ ] `SENTRY_IMPORT_ONLY_EXCLUSIONS` contains exactly the 4 `auth_*` names and is
      documented as frozen ("do NOT grow; a new apply-created alert must be targeted").
- [ ] Regression anchor asserts `sentry_issue_alert.sandbox_startup_failure` (#5875)
      stays targeted.
- [ ] `existsSync(SENTRY_INFRA_DIR)` / `existsSync(SENTRY_WORKFLOW)` guards present so
      a moved path fails loud, not silently vacuous.

### Post-merge (CI + read-only audit — automatable, no SSH)

- [ ] Confirm the new bun test runs green in CI (`ci.yml` / `infra-validation.yml`
      bun-test job).
- [ ] Confirm `github_webhook_founder_ambiguous` becomes a **live** Sentry rule:
      run `bash apps/web-platform/scripts/sentry-monitors-audit.sh` (read-only) or a
      Sentry API read; if `apply-sentry-infra.yml` did not auto-fire on the workflow
      edit, dispatch it via `gh workflow run apply-sentry-infra.yml` (the workflow's
      destroy-guard halts on any destructive change; a create is non-destructive).

## Domain Review

**Domains relevant:** none

No cross-domain business implications — infrastructure/CI tooling change (test guard
+ one terraform `-target` registration). Engineering (CTO)-only; no Product/UI surface
(no `components/**`, `app/**/page.tsx`, or `layout.tsx` in the Files lists), so the
Product/UX Gate does not fire.

## Infrastructure (IaC)

No **new** infrastructure. The change wires an **already-authored** terraform resource
(`sentry_issue_alert.github_webhook_founder_ambiguous`) into the existing
`apply-sentry-infra.yml` apply path.

- **Terraform changes:** none to `.tf` files; only the workflow `-target` list.
- **Apply path:** cloud-init N/A — the resource applies through the existing
  `apply-sentry-infra.yml` (`terraform plan -target=… → apply tfplan`) on the next
  Sentry-infra apply. Non-destructive (create/refresh of one alert; the workflow's
  destroy-guard halts on any delete). No SSH; no new secret/vendor/host.
- **Drift/distinctness:** the sentry root is a distinct R2 state key from the main
  web-platform root; no shared-lock concern.

## Observability

```yaml
liveness_signal:
  what: the parity test itself is the drift signal (red at PR time on a forgotten -target)
  cadence: every CI run of the bun test suite
  alert_target: PR check (blocks merge on red)
  configured_in: plugins/soleur/test/terraform-target-parity.test.ts
error_reporting:
  destination: CI job failure (bun test non-zero exit)
  fail_loud: true — existsSync guards + non-vacuity floor prevent a silent vacuous pass
failure_modes:
  - mode: new apply-created sentry alert forgotten in -target
    detection: parity test returns it in `uncovered`
    alert_route: red PR check
  - mode: parser/discovery collapse (regex or path regression)
    detection: `discovers >= 60 managed sentry resources` non-vacuity test fails
    alert_route: red PR check
  - mode: github_webhook_founder_ambiguous stays inert post-merge
    detection: post-merge sentry-monitors-audit.sh / Sentry API read shows the rule absent
    alert_route: post-merge audit step (post-merge AC)
logs:
  where: GitHub Actions bun-test job logs
  retention: GitHub default (90d)
discoverability_test:
  command: bun test plugins/soleur/test/terraform-target-parity.test.ts
  expected_output: all tests pass including the #5884 Sentry describe block (no ssh)
```

## Architecture Decision (ADR/C4)

No architectural decision. This is consistent with **ADR-031 (Sentry as IaC)** and
extends the existing #5566 parity-guard pattern; it introduces no new substrate,
ownership boundary, resolver, or trust boundary. **C4:** no impact — Sentry is
already modeled as an external system per ADR-031; this change adds no external
actor, external system, container, or access relationship. (Checked: the change
touches only a test file and a workflow `-target` list; no new correspondent/vendor/
data-store enters the model.)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open issue whose
body references `terraform-target-parity.test.ts` or `apply-sentry-infra.yml`.

## Test Scenarios

1. **Happy parity:** all 44 cron + 4 uptime + 15 apply-created alerts (14 pre-existing
   + `github_webhook_founder_ambiguous` after Phase 2) are targeted → `uncovered = []`.
2. **Import-only exclusion:** the 4 `auth_*` placeholders present in `.tf`, absent from
   `-target`, present in `SENTRY_IMPORT_ONLY_EXCLUSIONS` → not flagged.
3. **Synthetic miss (non-vacuity):** a synthetic un-targeted `sentry_issue_alert`
   parses and is flagged `uncovered` → proves the guard bites.
4. **Regression anchor:** `sandbox_startup_failure` (#5875) stays targeted.
5. **Floor sentinel:** discovery returns ≥ 60 resources → parser did not collapse.

## Non-Goals

- **Reverse-direction guard** ("every `-target` line points at a live resource"): out
  of scope, same documented limitation as the existing #5566/#4844 guard (terraform
  exits 0 on "no resources matched"). `kb_tenant_mint_silent_fallback` (#4929 state
  orphan) is unaffected.
- **Concurrency-group / cloudflared-pin parity** for `apply-sentry-infra.yml`: the
  sentry root has its own state key and does not share the web-platform-host
  concurrency group; the #4844 parity block does not apply.
- **Reclassifying / re-authoring the 4 `auth_*` import-only placeholders**: they are
  intentionally import-only per the `issue-alerts.tf` header; unchanged.
- **Auditing live Sentry state of every resource**: the guard is source-vs-workflow
  static parity; live-state reconciliation is the audit script's job.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **Snapshot the 5-alert gap as an `AUDIT_PENDING`-style set (mirror #5577)** and defer classification to a follow-up issue | Rejected. The learning + `.tf` header already classify all 5 decisively (4 import-only, 1 apply-created miss); no genuine ambiguity remains to snapshot. Snapshotting `github_webhook_founder_ambiguous` would leave a known inert alert live-broken. |
| **Add all 5 to an exclusion set (green with no workflow change)** | Rejected. Excluding an apply-created alert masks the exact bug the guard catches and keeps the founder-attribution alert inert. |
| **Mechanical discriminator** (test parses each alert's `conditions_v2`; empty ⇒ auto-exclude, non-empty ⇒ must-target) | Rejected for now. Cleverer but adds an HCL `conditions_v2`-emptiness parser and would silently auto-exclude a future placeholder that later gains real conditions. The explicit frozen `SENTRY_IMPORT_ONLY_EXCLUSIONS` set mirrors the file's existing `EXCLUSION_ALLOWLIST` / `OPERATOR_APPLIED_EXCLUSIONS` precedent, fails closed, and forces conscious reclassification. Noted as a future option if placeholders proliferate. |
| **New sibling test file** instead of extending | Rejected. The three reusable helpers (`stripComments`, `extractAllResources`, `extractAllTargets`) are module-scoped and unexported; extending the existing file reuses them with zero duplication, matching how the #5566 non-SSH block was added to the same file. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold
  will fail `deepen-plan` Phase 4.6. This one is filled (threshold: none + reason).
- The new `-target` line MUST sit inside the backslash-continued `terraform plan`
  command with no adjacent comment — a mid-continuation comment terminates the
  command and the next `-target=` line runs as a bare command (exit 127; PR #5108).
- Run the test from the **worktree** path, never the bare-repo working copy — a stale
  synced snapshot can mask worktree RED edits (learning
  `2026-06-12-detector-cron-must-route-…` Session Errors).
- `SENTRY_IMPORT_ONLY_EXCLUSIONS` is frozen: a **new** apply-created alert must be
  added to the workflow `-target` list, never to this set. Only a genuine import-only
  placeholder (`conditions_v2 = []` + import header) may join it.
- The line-number references (258/259/309) are drift-prone anchors — the implementer
  MUST re-grep `-target=sentry_issue_alert.sandbox_startup_failure` and `-no-color`
  to locate the insertion point, not trust the numbers verbatim.
