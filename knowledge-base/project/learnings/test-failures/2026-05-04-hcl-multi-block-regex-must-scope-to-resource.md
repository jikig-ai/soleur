---
module: System
date: 2026-05-04
problem_type: test_failure
component: testing_framework
symptoms:
  - "Self-healing parity test extracted basenames from the wrong triggers_replace block in server.tf"
  - "Test asserted [\"disk-monitor.sh\"] but expected the 5-element deploy_pipeline_fix list"
root_cause: incorrect_scope
resolution_type: test_fix
severity: low
tags: [regex, terraform, hcl, parity-tests, self-healing-tests, ship-gate, dpf]
related_pr: "#3068 fix"
related_learnings:
  - 2026-04-29-cross-language-regex-and-terraform-indirect-reference.md
---

# HCL Multi-Block Regex Must Scope to the Owning Resource

## Problem

Closing #3068 required adding a self-healing test that derives the trigger-file
list from `apps/web-platform/infra/server.tf` itself, so future additions to
`terraform_data.deploy_pipeline_fix.triggers_replace` automatically fail the
suite until `TRIGGER_FILES` (and therefore the gate's bash array + `DPF_REGEX`)
catch up.

First implementation matched the wrong block:

```ts
const blockMatch = serverTf.match(
  /triggers_replace\s*=\s*sha256\(join\(",", \[([\s\S]*?)\]\)\)/,
);
```

Test failed with:

```
Expected: ["canary-bundle-claim-check.sh", "cat-deploy-state.sh",
           "ci-deploy.sh", "hooks.json.tmpl", "webhook.service"]
Received: ["disk-monitor.sh"]
```

## Root Cause

`apps/web-platform/infra/server.tf` declares **7** `triggers_replace`
assignments across distinct resources:

```text
line  62: terraform_data.disk_monitor_install         (sha256(join(",", [...])))
line 100: terraform_data.fail2ban_install             (sha256(join(",", [...])))
line 140: terraform_data.fail2ban_sshd_local          (sha256(file(...)))
line 219: terraform_data.deploy_pipeline_fix          (sha256(join(",", [...])))
line 287: terraform_data.seccomp_bwrap                (sha256(file(...)))
line 323: terraform_data.apparmor_bwrap_profile       (sha256(file(...)))
line 350: terraform_data.orphan_reaper                (sha256(file(...)))
```

A non-greedy regex run against the full file matches the **first** block — the
disk-monitor list — not the deploy_pipeline_fix list at line 219. The test
extracted basenames from the wrong resource and reported a single-element
result that had nothing to do with the gate under test.

## Solution

Locate the resource block first by string indexing, then run the
`triggers_replace` regex against that slice:

```ts
const resourceStart = serverTf.indexOf(
  'resource "terraform_data" "deploy_pipeline_fix"',
);
expect(resourceStart).toBeGreaterThanOrEqual(0);
// Slice to the next `\nresource ` heading (or EOF if it's the last resource).
const nextResource = serverTf.indexOf("\nresource ", resourceStart + 1);
const resourceBlock = serverTf.slice(
  resourceStart,
  nextResource === -1 ? undefined : nextResource,
);

const blockMatch = resourceBlock.match(
  /triggers_replace\s*=\s*sha256\(join\(\s*",\s*"\s*,\s*\[([\s\S]*?)\]\s*\)\s*\)/,
);
```

The `\nresource ` upper bound (with the leading newline) is load-bearing — bare
`resource ` would also match `resource_block` etc. inside comments or strings.
Slicing to `undefined` when no following resource exists handles the
last-resource-in-file case.

## Key Insight

**HCL is a block-structured language; regex parsers must scope to a block
before attribute extraction.** Any attribute name that can repeat across
resources (`triggers_replace`, `lifecycle`, `provisioner`, `connection`,
`tags`, `labels`) is a multi-match risk. A non-greedy regex over the whole
file silently selects the first occurrence, and the failure mode is
"test extracts plausible-looking but wrong data," not "test errors out" —
which is the worst kind of test bug because it reads as a correctness signal.

The fix has two ingredients:

1. **Resource-block scoping**: `serverTf.indexOf('resource "<type>" "<name>"')`
   bounds the search before any attribute regex runs.
2. **Resource-end heuristic**: `\nresource ` (newline-anchored) reliably bounds
   the upper edge in the typical HCL convention where each resource starts at
   column 0.

For the `deploy_pipeline_fix` case, this also matters because `local.hooks_json`
is referenced inside `triggers_replace` and resolved against a top-of-file
`locals { hooks_json = templatefile(...) }` block — the block-scoped extraction
yields the `local.<name>` token, then a separate file-level lookup resolves it
to the `templatefile()` filename. Two-pass: scope locally for the trigger list,
then resolve indirections globally.

## Prevention

When asserting infrastructure-as-code structure from tests, enforce the
two-step pattern:

1. Locate the owning resource by exact match (`'resource "<type>" "<name>"'`).
2. Bound to the next `\nresource ` heading or EOF.
3. Apply attribute-level regexes to the slice, not the file.

The test file at `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`
now demonstrates this pattern in the "every basename hashed by triggers_replace
appears in TRIGGER_FILES" case — copy it for any future
multi-block parser test.

## Session Errors

- **Self-healing test regex grabbed the wrong `triggers_replace` block.**
  Recovery: scope to `resource "terraform_data" "deploy_pipeline_fix"`
  via `indexOf` + `\nresource ` upper bound before applying the attribute
  regex. Prevention: this learning + the inline pattern in
  `ship-deploy-pipeline-fix-gate.test.ts`. No AGENTS.md rule needed —
  bun:test surfaces the mismatch with a diff that names the wrong basename
  in seconds (discoverability exit per `wg-every-session-error-must-produce-either`).

## Cross-References

- PR #3038 — original gate landing (4 triggers)
- Issue #3068 — gate omitted `canary-bundle-claim-check.sh` (5th trigger)
- Issue #3061 — 10th drift; resolved 2026-04-30
- `knowledge-base/project/learnings/test-failures/2026-04-29-cross-language-regex-and-terraform-indirect-reference.md`
  — sibling learning on cross-language regex equality + indirect locals reference
- `apps/web-platform/infra/server.tf` line 219 — `terraform_data.deploy_pipeline_fix`
- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` — pattern reference
