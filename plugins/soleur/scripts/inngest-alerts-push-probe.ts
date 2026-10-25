#!/usr/bin/env bun
// Discoverability probe for #11068: do the three Inngest-serving Better Stack alert resources
// declare `push = true` in SOURCE? The flip is the measured-acceptance convention (#9168,
// #11001): email stays on, push is additive, and a vendor refusal at apply reverts the
// attribute — a silent source-level revert is exactly what this probe exists to catch.
//
// Credential-free and sub-second: it reads apps/web-platform/infra/*.tf only. It says nothing
// about the LIVE resources (a console-side toggle, a vendor refusal) — the merge-triggered
// apply-web-platform-infra run is that measurement.
//
// Standalone file, not a `bun -e` one-liner, because preflight Check 10 (ADR-175) runs the
// plan's discoverability command inside a sandbox behind a shell-active-token reject —
// the inngest-luks-alert-armed-probe.ts precedent.
//
// Exit 0 + "PUSH_ARMED" when all three declare `push = true`; exit 1 +
// "PUSH_MISSING <resource>" naming the first one that does not (or is absent).
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { listTfFiles, stripComments } from "../lib/heartbeat-live-reconcile";

// argv[2] is a TEST seam only (a synthesized root); the plan's discoverability command
// passes nothing and reads the real root.
const INFRA_DIR = process.argv[2] ?? "apps/web-platform/infra";
const TARGETS: readonly (readonly [string, string])[] = [
  ["logtail_exploration_alert", "inngest_luks_wrong_volume"],
  ["logtail_exploration_alert", "inngest_step_524"],
  ["betteruptime_heartbeat", "inngest_server_probe"],
];

function skipString(code: string, start: number): number {
  for (let i = start + 1; i < code.length; i++) {
    if (code[i] === "\\") i++;
    else if (code[i] === '"') return i + 1;
  }
  return code.length;
}

// Body of `resource "<type>" "<name>" { … }` with comments already stripped; null when absent.
function blockBody(code: string, type: string, name: string): string | null {
  const open = `resource "${type}" "${name}" {`;
  const at = code.indexOf(open);
  if (at === -1) return null;
  let depth = 0;
  for (let i = at + open.length - 1; i < code.length; i++) {
    const ch = code[i];
    if (ch === '"') {
      i = skipString(code, i) - 1;
    } else if (ch === "{") {
      depth++;
    } else if (ch === "}" && --depth === 0) {
      return code.slice(at + open.length, i);
    }
  }
  return null;
}

const seen = new Set<string>();
const missing: string[] = [];
for (const file of listTfFiles(INFRA_DIR)) {
  const code = stripComments(readFileSync(join(INFRA_DIR, file), "utf8"));
  for (const [type, name] of TARGETS) {
    if (seen.has(name)) continue;
    const body = blockBody(code, type, name);
    if (body === null) continue;
    seen.add(name);
    if (!/^\s*push\s*=\s*true\s*$/m.test(body)) missing.push(`${type}.${name}`);
  }
}
for (const [type, name] of TARGETS) {
  if (!seen.has(name)) missing.push(`${type}.${name}`);
}

console.log(missing.length === 0 ? "PUSH_ARMED" : `PUSH_MISSING ${missing[0]}`);
process.exit(missing.length === 0 ? 0 : 1);
