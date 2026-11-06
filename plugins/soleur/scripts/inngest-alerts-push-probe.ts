#!/usr/bin/env bun
// Discoverability probe for #11068: do all SIX Inngest-serving Better Stack alert resources
// declare `push = true` in SOURCE? The flip is the measured-acceptance convention (#9168,
// #11001): email stays on, push is additive, and a vendor refusal at apply reverts the
// attribute — a silent source-level revert is exactly what this probe exists to catch.
//
// Credential-free and sub-second: it reads apps/web-platform/infra/*.tf only, through the same
// declaration-grade parser path the drift reconciler uses (codeView + resourceBlocks +
// topLevelAttributes — comments stripped, heredoc bodies blanked, nested blocks skipped, so
// only a REAL top-level `push = true` counts). It says nothing about the LIVE resources (a
// console-side toggle, a vendor refusal) — the merge-triggered apply-web-platform-infra run is
// that measurement.
//
// Standalone file, not a `bun -e` one-liner, because preflight Check 10 (ADR-175) runs the
// plan's discoverability command inside a sandbox behind a shell-active-token reject —
// the inngest-luks-alert-armed-probe.ts precedent.
//
// Exit 0 + "PUSH_ARMED" when all six declare `push = true`; exit 1 +
// "PUSH_MISSING <resource>" naming the first one that does not (or is absent).
import { closeSync, constants, fstatSync, openSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { codeView, listTfFiles, resourceBlocks, topLevelAttributes } from "../lib/heartbeat-live-reconcile";

// argv[2] is a TEST seam only (a synthesized root); the plan's discoverability command
// passes nothing and reads the real root.
const INFRA_DIR = process.argv[2] ?? "apps/web-platform/infra";
const TARGETS: readonly (readonly [string, string])[] = [
  ["logtail_exploration_alert", "inngest_luks_wrong_volume"],
  ["logtail_exploration_alert", "inngest_step_524"],
  ["betteruptime_heartbeat", "inngest_server_probe"],
  ["betteruptime_heartbeat", "inngest_prd"],
  ["betteruptime_heartbeat", "inngest_consumer"],
  ["logtail_exploration_alert", "inngest_luks_key_probe_fail"],
];

const seen = new Set<string>();
const missing: string[] = [];
for (const file of listTfFiles(INFRA_DIR)) {
  const path = join(INFRA_DIR, file);
  // Check-then-read on ONE fd (open + fstat on the descriptor): a path-level
  // lstat→readFileSync pair is the js/file-system-race TOCTOU shape. O_NONBLOCK
  // keeps the open from hanging on a *.tf FIFO before fstat can refuse it.
  const fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK);
  let code: string;
  try {
    if (!fstatSync(fd).isFile()) continue;
    code = codeView(readFileSync(fd, "utf8"));
  } finally {
    closeSync(fd);
  }
  for (const [type, name] of TARGETS) {
    if (seen.has(name)) continue;
    const block = resourceBlocks(code, type).find((b) => b.resourceName === name);
    if (block === undefined) continue;
    seen.add(name);
    if (topLevelAttributes(block.body).get("push") !== "true") {
      missing.push(`${type}.${name}`);
    }
  }
}
for (const [type, name] of TARGETS) {
  if (!seen.has(name)) missing.push(`${type}.${name}`);
}

console.log(missing.length === 0 ? "PUSH_ARMED" : `PUSH_MISSING ${missing[0]}`);
process.exit(missing.length === 0 ? 0 : 1);
