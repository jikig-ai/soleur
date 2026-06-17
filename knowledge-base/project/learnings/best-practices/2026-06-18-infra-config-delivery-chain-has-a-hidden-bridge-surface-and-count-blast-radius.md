# Learning: adding a webhook-delivered host file touches the full delivery CHAIN (incl. the hidden pass-environment bridge) + a count-assertion blast radius — not just the trigger-surface matrix

category: best-practices
module: apps/web-platform/infra (infra-config delivery), #5509

## Problem

#5509 added a new no-SSH host script (`inngest-inventory.sh`). The plan's "Registration Surface Matrix" enumerated 11 surfaces (server.tf hash, ship array/regex/prose, gate-test TRIGGER_FILES, apply-dpf paths, push payload, FILE_MAP, install DEST_SPEC, hooks.json.tmpl). /work implemented all 11 and every gate test passed — yet the feature was silently broken.

Two gaps the matrix + the green suite missed:

1. **The hidden 12th surface — the `pass-environment-to-command` bridge.** The `infra-config` webhook hook (`hooks.json.tmpl`) maps each pushed payload key (`inngest_inventory_sh_b64`) to an env var (`INNGEST_INVENTORY_SH_B64`) via a `pass-environment-to-command` array. The matrix listed push-payload (surface 7) and FILE_MAP (surface 8) but NOT this bridge between them. Without the bridge entry, the b64 is pushed but never reaches the handler as an env var → `infra-config-apply.sh` records `missing_env` and writes the file NOWHERE → `GET /hooks/inngest-inventory` 500s. The deploy-trigger gate test (which guards surfaces 1/2/3/5/6) is structurally blind to it. Caught only by `deployment-verification-agent` tracing the b64-key → env-var → FILE_MAP → DEST chain end-to-end.

2. **Count-assertion blast radius.** Adding the 12th entry to FILE_MAP + DEST_SPEC broke ~6 hardcoded `11`/`10` count assertions across `infra-config-apply.test.sh` (`files_written`/`files_total` happy + partial, helper-invoked-once-per-file, prod-mode files_written) and `infra-config-install.test.sh` (managed-dests-accepted, FILE_MAP/DEST_SPEC cardinality), PLUS the apply test's `setup()` b64-export list and the install test's hardcoded `specs` array. The happy-path test's own green run didn't show it until the FILE_MAP entry landed; it surfaced as a wave of failures on the full infra-suite run.

## Solution / durable rule

When adding a webhook-delivered host file, the delivery CHAIN is: push payload key → **`pass-environment-to-command` bridge** → handler FILE_MAP env var → install DEST_SPEC → on-disk path. Every link must carry the new file, and the THREE b64 surfaces (push payload, FILE_MAP, pass-environment) must enumerate the SAME key set. #5509 added a parity test in `infra-config-apply.test.sh` (`test_b64_delivery_parity`) asserting `push payload keys ↔ FILE_MAP env vars ↔ pass-environment envnames` are identical — it fails (RED-proven) if any future managed file skips the bridge. This is the delivery-chain analogue of #5505's `apply-deploy-pipeline-fix.yml` paths parity test.

Companion mechanical reflex: adding a managed file to FILE_MAP/DEST_SPEC shifts every hardcoded count in the sibling test suites. Before declaring done, `grep -rnE 'files_(written|total)|managed dests|once per file|"1[0-9]"' apps/web-platform/infra/infra-config*.test.sh` and bump each count, AND add the new b64 to the apply test's `setup()` exports + the install test's `specs` array (the fixture blast radius of `cq-test-fixtures-synthesized-only` for a registered-file-set).

## Key Insight

A "registration matrix" is a hypothesis about completeness; the parity TEST is the proof. The surface most likely to be omitted is the one BETWEEN two listed surfaces (the push→FILE_MAP bridge) — it doesn't look like a registration site, it looks like plumbing. Enumerate the full data-flow chain (not the discrete file list) and guard each hop with a parity assertion. Same root lesson as #5505 (guard the actuating surface), one layer deeper: the actuating surface for *delivery* is the env-var bridge, not the trigger filter.

## Session Errors

1. **Missed the `pass-environment-to-command` bridge — the script would be pushed but never written (missing_env → op=inventory 500).** Recovery: added the bridge entry + a 3-way parity test. Prevention: the parity test now fails-closed on any managed file absent from the bridge; this learning documents the full delivery chain so the matrix isn't trusted as complete.
2. **Adding the 12th FILE_MAP/DEST_SPEC entry broke ~6 hardcoded count assertions + 2 fixture lists across the infra-config suites.** Recovery: bumped 11→12, added the 12th b64 export + specs entry. Prevention: grep the infra-config test suites for count literals + fixture arrays when adding a managed file (documented above).
3. **op=inventory `functions` silently fell back to `[]` on a degraded /v1/functions read** (false-clean before/after baseline). Recovery: fail-loud (exit 1 → webhook non-200). Prevention: covered by `cq-silent-fallback-must-mirror-to-sentry` — a baseline-capture's degraded read must be loud, never a silent empty.
4. **terraform validate failed with "providers not cached" until `terraform init -backend=false`.** Recovery: ran init first. Prevention: one-off; the work skill's infra-validation step already prescribes init-then-validate.

## Tags
category: best-practices
module: infra-config, delivery-chain, webhook, drift-guard, #5509
related: [[2026-06-18-coupled-registration-must-guard-the-actuating-surface]], [[2026-06-18-destructive-datastore-migration-backup-inventory-after-diff]]
