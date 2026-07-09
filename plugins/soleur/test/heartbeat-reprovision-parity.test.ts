// Heartbeat reprovision-parity guard (#6242, ADR-103).
//
// RECURRENCE PREVENTION for the PR #6238 class: a `betteruptime_heartbeat` whose ping is
// armed by a DEDICATED HETZNER HOST's boot-time provisioning (an on-host cloud-init cron OR a
// cloud-init-installed systemd timer) was shipped in the same PR as its cron, but
// `terraform apply` creating the heartbeat does NOT redeploy the host — and the host had no
// non-SSH reprovision path, so the cron was never installed and the orphaned heartbeat fired a
// false-positive absence alert.
//
// The invariant (worded per CTO — keyed on the MONITORED HOST'S REMEDIATION, not the cron's
// location, so it correctly covers inngest's systemd timer and does NOT misclassify git-data's
// web-host ping):
//
//   Every non-paused betteruptime_heartbeat whose arming/remediation depends on a dedicated
//   Hetzner host's boot-time provisioning MUST have that host's `<host>-host-replace` dispatch
//   path (a choice option in apply-web-platform-infra.yml + a `-replace='hcloud_server.<host>'`
//   line in its job).
//
// This is a STATIC-ANALYSIS test — zero live infra, no secrets. It parses every
// `betteruptime_heartbeat` block in apps/web-platform/infra/*.tf, reads each block's DECLARED
// `paused` value from source, and diffs against the MANIFEST below (which classifies each
// heartbeat by arming mechanism — the codified, ENFORCED version of the #6242 Audit Matrix,
// Deliverable A).
//
// Load-bearing properties (what makes it catch #6238):
//   1. discovered ⊆ manifest AND manifest ⊆ discovered — a NEW heartbeat with no manifest entry
//      FAILS, forcing the author to declare arming + reprovision (closes the silent-add hole).
//   2. the manifest's declared `paused` must match the SOURCE `paused` (drift guard) — unpausing
//      a dedicated-host-boot heartbeat in .tf without reconciling the manifest FAILS.
//   3. for arming == "dedicated-host-boot" — regardless of the declared `paused` value — the
//      declared replace_target MUST resolve to a real choice option + `-replace='hcloud_server.
//      <host>'` line. The path requirement is deliberately paused-INDEPENDENT for this arming
//      class: 4 of 6 heartbeats carry `lifecycle { ignore_changes = [paused] }`, which decouples
//      the .tf `paused` value from the live Better Stack state (boot-armed heartbeats ship
//      paused=true and are UI-unpaused after first deploy; Terraform never reconciles it), so
//      source `paused` is only a lower bound on liveness. arming ∈ {web-host-cron, app-emit,
//      external-probe} are exempt (their remediation is a web-host/container ci-deploy or an
//      external probe, never a dedicated-host reprovision) — recorded with an exempt_reason.
//
// Run today the guard PASSES: only registry_disk_prd is dedicated-host-boot + non-paused, and
// registry-host-replace exists. It is the mechanical gate that would have caught #6238 (a new
// non-paused dedicated-host-boot heartbeat with no path turns it RED — proven by the non-vacuity
// fixtures at the bottom).

import { describe, test, expect } from "bun:test";
import { resolve } from "path";
import { readFileSync, readdirSync } from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const INFRA_DIR = resolve(REPO_ROOT, "apps/web-platform/infra");
const WEB_PLATFORM_WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-web-platform-infra.yml",
);

type Arming =
  | "dedicated-host-boot"
  | "web-host-cron"
  | "app-emit"
  | "external-probe";

interface ManifestEntry {
  /** The resource name (betteruptime_heartbeat.<name>). */
  name: string;
  arming: Arming;
  /** DECLARED paused value; asserted equal to the value parsed from the .tf source. */
  paused: boolean;
  /**
   * Required IFF arming === "dedicated-host-boot" && !paused. `choice` is the apply_target
   * option; `server` is the `hcloud_server.<host>` the job -replaces.
   */
  replace_target?: { choice: string; server: string };
  /** Required for every entry that is NOT (dedicated-host-boot && !paused). */
  exempt_reason?: string;
}

// The codified #6242 Audit Matrix (Deliverable A). One row per heartbeat; adding a heartbeat to
// the .tf files WITHOUT adding a row here FAILS the discovered⊆manifest assertion.
const MANIFEST: ManifestEntry[] = [
  {
    name: "github_webhook_sig_failures",
    arming: "app-emit",
    paused: true,
    exempt_reason:
      "app/container emits the ping (webhook route pings on sig-failure); remediation is a container ci-deploy, not a dedicated-host reprovision.",
  },
  {
    name: "github_api_429_sustained",
    arming: "app-emit",
    paused: true,
    exempt_reason:
      "app/container emits the ping; remediation is a container ci-deploy, not a dedicated-host reprovision.",
  },
  {
    name: "git_data_prd",
    arming: "web-host-cron",
    paused: true,
    exempt_reason:
      "PUSH heartbeat armed by an (unshipped, #5274 PR C) WEB-HOST probe cron over the private net — NOT a git-data cloud-init cron. Reprovisioning git-data would not even arm it, so its remediation is web-host ci-deploy. (git-data-host-replace exists for immutable-redeploy compliance, not to arm this heartbeat.)",
  },
  {
    name: "inngest_prd",
    arming: "dedicated-host-boot",
    paused: true,
    // Currently paused → exempt from the path requirement, but a path exists anyway (ADR-100).
    replace_target: { choice: "inngest-host-replace", server: "hcloud_server.inngest" },
    exempt_reason:
      "paused=true today (its on-host systemd timer's cron is armed at boot but the heartbeat is UI-unpaused only after first deploy); path exists regardless.",
  },
  {
    name: "registry_prd",
    arming: "web-host-cron",
    paused: true,
    exempt_reason:
      "registry LIVENESS heartbeat armed by an (unshipped, Phase-3) WEB-HOST probe cron; remediation is web-host ci-deploy, not the registry cloud-init.",
  },
  {
    name: "registry_disk_prd",
    arming: "dedicated-host-boot",
    paused: false,
    // The #6238 exemplar: on-host cron /etc/cron.d/zot-disk-heartbeat (cloud-init-registry.yml)
    // → MUST have a reprovision path. registry-host-replace re-runs cloud-init → installs it.
    replace_target: { choice: "registry-host-replace", server: "hcloud_server.registry" },
  },
];

/** Strip `#` and `//` line comments, quote-aware (mirrors terraform-target-parity.test.ts). */
function stripLineComment(line: string): string {
  let inStr = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"' && line[i - 1] !== "\\") {
      inStr = !inStr;
      continue;
    }
    if (!inStr && c === "#") return line.slice(0, i);
    if (!inStr && c === "/" && line[i + 1] === "/") return line.slice(0, i);
  }
  return line;
}

function stripComments(text: string): string {
  return text.split("\n").map(stripLineComment).join("\n");
}

interface DiscoveredHeartbeat {
  name: string;
  paused: boolean;
  file: string;
}

/** Extract every `betteruptime_heartbeat` block (brace-matched) with its declared `paused`. */
function parseHeartbeats(stripped: string, file: string): DiscoveredHeartbeat[] {
  const header =
    /resource\s+"betteruptime_heartbeat"\s+"([A-Za-z0-9_]+)"\s*\{/g;
  const out: DiscoveredHeartbeat[] = [];
  let m: RegExpExecArray | null;
  while ((m = header.exec(stripped)) !== null) {
    const name = m[1];
    const openBrace = header.lastIndex - 1;
    let depth = 0;
    let end = -1;
    for (let i = openBrace; i < stripped.length; i++) {
      if (stripped[i] === "{") depth++;
      else if (stripped[i] === "}") {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    if (end === -1) {
      throw new Error(`Unbalanced braces for betteruptime_heartbeat.${name}`);
    }
    const body = stripped.slice(openBrace, end + 1);
    const pm = /\bpaused\s*=\s*(true|false)\b/.exec(body);
    // A heartbeat with no explicit `paused` defaults to active (paused=false) in the provider —
    // the conservative (stricter) reading, so an omission cannot silently exempt a live heartbeat.
    out.push({ name, paused: pm ? pm[1] === "true" : false, file });
  }
  return out;
}

function listInfraTfFiles(): string[] {
  return readdirSync(INFRA_DIR)
    .filter((f) => f.endsWith(".tf"))
    .map((f) => resolve(INFRA_DIR, f));
}

function collectHeartbeats(
  files: string[] = listInfraTfFiles(),
): DiscoveredHeartbeat[] {
  const out: DiscoveredHeartbeat[] = [];
  for (const file of files) {
    out.push(...parseHeartbeats(stripComments(readFileSync(file, "utf8")), file));
  }
  return out;
}

/** Does the workflow enum offer `<choice>` as an apply_target option? */
function hasChoiceOption(workflow: string, choice: string): boolean {
  return new RegExp(`^\\s*-\\s*${choice}\\s*$`, "m").test(workflow);
}

/** Does the workflow carry a `-replace='<server>'` line? */
function hasReplaceLine(workflow: string, server: string): boolean {
  const esc = server.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`-replace=['"]${esc}['"]`).test(workflow);
}

/**
 * The core guard. Returns a list of violation strings (empty === PASS). Pure over its inputs so
 * synthetic fixtures can drive it without touching the real files.
 */
function checkHeartbeatParity(
  discovered: DiscoveredHeartbeat[],
  manifest: ManifestEntry[],
  workflow: string,
): string[] {
  const violations: string[] = [];
  const manifestByName = new Map(manifest.map((e) => [e.name, e]));
  const discoveredByName = new Map(discovered.map((d) => [d.name, d]));

  // (1a) discovered ⊆ manifest — every real heartbeat must be classified.
  for (const d of discovered) {
    if (!manifestByName.has(d.name)) {
      violations.push(
        `heartbeat "${d.name}" (in ${d.file}) is NOT in the MANIFEST — declare its arming + reprovision-path classification (#6242 recurrence guard).`,
      );
    }
  }
  // (1b) manifest ⊆ discovered — no stale manifest row for a removed heartbeat.
  for (const e of manifest) {
    if (!discoveredByName.has(e.name)) {
      violations.push(
        `manifest row "${e.name}" has no matching betteruptime_heartbeat in the .tf files — remove the stale row.`,
      );
    }
  }

  for (const e of manifest) {
    const d = discoveredByName.get(e.name);
    if (!d) continue; // already reported as stale above

    // (2) manifest paused must match SOURCE paused (drift guard).
    if (e.paused !== d.paused) {
      violations.push(
        `heartbeat "${e.name}": manifest declares paused=${e.paused} but the .tf source declares paused=${d.paused} — reconcile (an unpause in source must be reflected in the manifest so the path requirement re-evaluates).`,
      );
    }

    // (3) arming == "dedicated-host-boot" → the replace path must exist, INDEPENDENT of the
    // declared `paused` value. This is deliberately stricter than "non-paused MUST have a path":
    // 4 of 6 heartbeats carry `lifecycle { ignore_changes = [paused] }` (git_data_prd,
    // inngest_prd, registry_prd, registry_disk_prd), which DECOUPLES the .tf `paused` value from
    // the live Better Stack state — the established pattern ships boot-armed heartbeats
    // `paused = true` and UI-unpauses them after first deploy, and Terraform never reconciles it.
    // So source `paused` is only a LOWER BOUND on liveness; keying the path requirement on it
    // would leave the exact #6238 hole open (a future paused=true + ignore_changes + UI-unpaused
    // boot-armed heartbeat with no path). Requiring the path for the whole boot-armed class closes
    // that hole and stays green today (inngest is paused but HAS a path; registry_disk is
    // non-paused and HAS a path). Corroborated by security-sentinel P3 + pattern-recognition F4.
    const requiresPath = e.arming === "dedicated-host-boot";

    if (requiresPath) {
      if (!e.replace_target) {
        violations.push(
          `heartbeat "${e.name}" is arming=dedicated-host-boot but declares no replace_target — a boot-armed heartbeat MUST have a <host>-host-replace path regardless of its source \`paused\` value (ignore_changes=[paused] decouples source from live state; the #6238 class).`,
        );
      } else {
        if (!hasChoiceOption(workflow, e.replace_target.choice)) {
          violations.push(
            `heartbeat "${e.name}": replace_target choice "${e.replace_target.choice}" is not an apply_target option in the workflow.`,
          );
        }
        if (!hasReplaceLine(workflow, e.replace_target.server)) {
          violations.push(
            `heartbeat "${e.name}": no \`-replace='${e.replace_target.server}'\` line found in the workflow for choice "${e.replace_target.choice}".`,
          );
        }
      }
    } else {
      // Every non-dedicated-host-boot entry (web-host-cron / app-emit / external-probe) is exempt
      // from the path requirement — its remediation is a web-host/container ci-deploy or an
      // external probe, never a dedicated-host reprovision — and must carry an exempt_reason.
      if (!e.exempt_reason) {
        violations.push(
          `heartbeat "${e.name}" is exempt from the path requirement (arming=${e.arming}) but records no exempt_reason.`,
        );
      }
    }
  }
  return violations;
}

describe("heartbeat reprovision-parity guard — current state (#6242, ADR-103)", () => {
  const workflow = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");

  test("every discovered heartbeat is classified and the invariant holds", () => {
    const discovered = collectHeartbeats();
    const violations = checkHeartbeatParity(discovered, MANIFEST, workflow);
    expect(violations).toEqual([]);
  });

  test("the census is exactly 6 heartbeats (matches the Audit Matrix)", () => {
    // The `6` is the documented Audit-Matrix count and a deliberate tripwire: a sibling PR that
    // lands a 7th heartbeat turns this RED, forcing an explicit manifest classification (the
    // intended forcing function). The manifest length is DERIVED from the discovered count (not a
    // second hardcoded literal) so a manifest/census reconcile is one edit here + the new row.
    expect(collectHeartbeats().length).toBe(6);
    expect(MANIFEST.length).toBe(collectHeartbeats().length);
  });

  test("registry_disk_prd is the sole dedicated-host-boot + non-paused heartbeat today", () => {
    const discovered = collectHeartbeats();
    const live = MANIFEST.filter(
      (e) =>
        e.arming === "dedicated-host-boot" &&
        !discovered.find((d) => d.name === e.name)!.paused,
    ).map((e) => e.name);
    expect(live).toEqual(["registry_disk_prd"]);
  });
});

describe("heartbeat reprovision-parity guard is load-bearing (non-vacuity, AC3)", () => {
  const workflow = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");

  test("an un-manifested heartbeat FAILS the guard", () => {
    const discovered: DiscoveredHeartbeat[] = [
      ...collectHeartbeats(),
      { name: "rogue", paused: false, file: "synthetic.tf" },
    ];
    const violations = checkHeartbeatParity(discovered, MANIFEST, workflow);
    expect(violations.some((v) => v.includes('"rogue"') && v.includes("MANIFEST"))).toBe(true);
  });

  test("a PAUSED dedicated-host-boot heartbeat with NO replace path ALSO FAILS (paused-independence — the #6238 ignore_changes hole)", () => {
    // The load-bearing regression guard for security-sentinel P3 / pattern-recognition F4: a
    // boot-armed heartbeat shipped `paused=true` (+ `ignore_changes=[paused]`, UI-unpaused later)
    // with no path is the exact #6238 shape. The path requirement MUST fire even though source
    // paused=true. Mutation check: reverting `requiresPath` to `... && !d.paused` flips this GREEN.
    const discovered: DiscoveredHeartbeat[] = [
      { name: "paused_boot_prd", paused: true, file: "synthetic.tf" },
    ];
    const manifest: ManifestEntry[] = [
      { name: "paused_boot_prd", arming: "dedicated-host-boot", paused: true },
    ];
    const violations = checkHeartbeatParity(discovered, manifest, workflow);
    expect(
      violations.some(
        (v) => v.includes("paused_boot_prd") && v.includes("no replace_target"),
      ),
    ).toBe(true);
  });

  test("a non-paused dedicated-host-boot heartbeat with NO replace path FAILS the guard", () => {
    // Synthetic: a new heartbeat armed by a fictional host's boot cron, no path declared.
    const discovered: DiscoveredHeartbeat[] = [
      { name: "newhost_boot_prd", paused: false, file: "synthetic.tf" },
    ];
    const manifest: ManifestEntry[] = [
      { name: "newhost_boot_prd", arming: "dedicated-host-boot", paused: false },
    ];
    const violations = checkHeartbeatParity(discovered, manifest, workflow);
    expect(
      violations.some(
        (v) => v.includes("newhost_boot_prd") && v.includes("no replace_target"),
      ),
    ).toBe(true);
  });

  test("a dedicated-host-boot heartbeat whose choice option is ABSENT FAILS the guard", () => {
    const discovered: DiscoveredHeartbeat[] = [
      { name: "phantom_prd", paused: false, file: "synthetic.tf" },
    ];
    const manifest: ManifestEntry[] = [
      {
        name: "phantom_prd",
        arming: "dedicated-host-boot",
        paused: false,
        replace_target: { choice: "phantom-host-replace", server: "hcloud_server.phantom" },
      },
    ];
    const violations = checkHeartbeatParity(discovered, manifest, workflow);
    expect(violations.some((v) => v.includes("phantom-host-replace"))).toBe(true);
    expect(violations.some((v) => v.includes("hcloud_server.phantom"))).toBe(true);
  });

  test("unpausing a dedicated-host-boot heartbeat in source without reconciling the manifest FAILS (drift)", () => {
    // Source says paused=false; manifest still says paused=true → drift violation.
    const discovered: DiscoveredHeartbeat[] = [
      { name: "inngest_prd", paused: false, file: "inngest.tf" },
    ];
    const manifest: ManifestEntry[] = [
      {
        name: "inngest_prd",
        arming: "dedicated-host-boot",
        paused: true,
        replace_target: { choice: "inngest-host-replace", server: "hcloud_server.inngest" },
        exempt_reason: "paused",
      },
    ];
    const violations = checkHeartbeatParity(discovered, manifest, workflow);
    expect(violations.some((v) => v.includes("inngest_prd") && v.includes("reconcile"))).toBe(true);
  });
});
