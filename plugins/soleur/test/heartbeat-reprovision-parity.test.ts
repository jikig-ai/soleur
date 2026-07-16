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
import { readFileSync, readdirSync, existsSync } from "fs";
import { execFileSync } from "child_process";
import {
  MANIFEST,
  countUrlSecretConsumers,
  type Arming,
  type Feeder,
  type ManifestEntry,
} from "../lib/heartbeat-manifest";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const INFRA_DIR = resolve(REPO_ROOT, "apps/web-platform/infra");
const WEB_PLATFORM_WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-web-platform-infra.yml",
);

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
 * Count lines in the repo (excluding knowledge-base/ prose) matching `re`.
 *
 * `git grep` exits 1 on "no match" — a NORMAL result here, not an error — and >1 on real failure,
 * so the two must not be conflated: swallowing all non-zero exits would make a broken grep look
 * like "zero consumers", i.e. would report an unfed heartbeat as correctly unfed for the wrong
 * reason. That is the same false-green this whole module exists to prevent, so it fails loud.
 */
function gitGrepCount(re: RegExp): number {
  try {
    const out = execFileSync(
      "git",
      ["grep", "-IEc", re.source, "--", ":!knowledge-base"],
      { cwd: REPO_ROOT, encoding: "utf8" },
    );
    return out
      .split("\n")
      .filter(Boolean)
      .reduce((sum, line) => sum + Number(line.slice(line.lastIndexOf(":") + 1)), 0);
  } catch (err: unknown) {
    const status = (err as { status?: number }).status;
    if (status === 1) return 0; // no match — the expected "still unfed" outcome
    throw new Error(`git grep failed (exit ${status}) for /${re.source}/`);
  }
}

/**
 * The FEEDER guard (#6537) — the executable half of the arming claim.
 *
 * Forward (kind ∈ {cron,timer}): the declared evidence must exist on disk AND contain the pattern.
 * A feeder that is deleted or renamed turns this RED. This is what a comment could never do.
 *
 * Inverse (kind === "none" + a url_secret): that secret must still have ZERO dereferencing
 * consumers. This is the forcing function, and it is the assertion #6537 needed and lacked: the
 * day someone ships a feeder for a heartbeat still declared unfed, CI goes red and makes them
 * reconcile the row — instead of the feeder landing while the monitor stays paused for 9 days.
 */
function checkFeeders(
  manifest: ManifestEntry[],
  fileExists: (rel: string) => boolean,
  readFile: (rel: string) => string,
  countConsumers: (secret: string) => number,
): string[] {
  const violations: string[] = [];

  for (const e of manifest) {
    const f = e.feeder;

    if (f.kind === "cron" || f.kind === "timer") {
      // Two DISTINCT messages: "the evidence file is gone" and "the file is there but the feeder
      // is not in it" are different failures with different fixes, and collapsing them into one
      // message sends the next reader looking in the wrong place. (grep -F itself distinguishes
      // them by exit code — 2 vs 1 — for the same reason.)
      if (!fileExists(f.evidence.file)) {
        violations.push(
          `heartbeat "${e.name}": feeder evidence file "${f.evidence.file}" does not exist — the declared ${f.kind} cannot be arming it.`,
        );
        continue;
      }
      // Fixed-string containment (grep -F semantics): the pattern is a literal unit/path name, so
      // regex interpretation would only invent metacharacter bugs.
      if (!readFile(f.evidence.file).includes(f.evidence.pattern)) {
        violations.push(
          `heartbeat "${e.name}": feeder evidence file "${f.evidence.file}" exists but does NOT contain "${f.evidence.pattern}" — the ${f.kind} was renamed or removed, so nothing feeds this heartbeat.`,
        );
      }
      continue;
    }

    // kind === "none" — an honest declaration, but it costs an owner.
    if (!Number.isInteger(f.tracking_issue) || f.tracking_issue <= 0) {
      violations.push(
        `heartbeat "${e.name}": feeder.kind="none" requires a positive tracking_issue (who owns building the feeder — or deleting the heartbeat). An unfed monitor with no owner is exactly the #6537 shape.`,
      );
    }
    if (f.url_secret !== null && countConsumers(f.url_secret) > 0) {
      violations.push(
        `heartbeat "${e.name}": declared UNFED (feeder.kind="none") but its url_secret ${f.url_secret} now has consumers — a feeder shipped. Reconcile this row to {kind:"cron"|"timer"} with evidence, then arm the heartbeat (verify a real ping lands BEFORE unpausing — #6210).`,
      );
    }
  }

  return violations;
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

describe("feeder manifest — every arming claim is executable (#6537)", () => {
  const realExists = (rel: string) => existsSync(resolve(REPO_ROOT, rel));
  const realRead = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf8");
  const realCount = (secret: string) => countUrlSecretConsumers(secret, gitGrepCount);

  test("every declared feeder's evidence resolves, and every unfed row is honest", () => {
    expect(checkFeeders(MANIFEST, realExists, realRead, realCount)).toEqual([]);
  });

  test("every heartbeat declares a feeder (no silent omission)", () => {
    for (const e of MANIFEST) {
      expect(e.feeder).toBeDefined();
      expect(["cron", "timer", "none"]).toContain(e.feeder.kind);
    }
  });

  test("registry_prd is FED by the on-host timer and is dedicated-host-boot (#6537's fix)", () => {
    // The row this PR inverts. Before: arming="web-host-cron" + an exempt_reason citing a probe
    // cron that was never written — which is where the bug hid for 9 days. After: armed by the
    // registry's own cloud-init, which makes the replace_target requirement fire (intended).
    const e = MANIFEST.find((m) => m.name === "registry_prd")!;
    expect(e.arming).toBe("dedicated-host-boot");
    expect(e.feeder.kind).toBe("timer");
    expect(e.replace_target).toEqual({
      choice: "registry-host-replace",
      server: "hcloud_server.registry",
    });
    // A dedicated-host-boot row must NOT carry an exempt_reason — it is not exempt.
    expect(e.exempt_reason).toBeUndefined();
  });

  test("GIT_DATA_HEARTBEAT_URL still has zero consumers — the inverse assertion is live, not theoretical", () => {
    // This is the tripwire for the sibling never-unpaused monitor. It passes today because the
    // probe is genuinely unbuilt. When #5274 PR C ships it, this goes RED — on purpose.
    expect(realCount("GIT_DATA_HEARTBEAT_URL")).toBe(0);
  });

  test("the consumer count is DEREFERENCE-anchored, not name-anchored (the trap this replaces)", () => {
    // Load-bearing, and found the hard way: `git grep -c GIT_DATA_HEARTBEAT_URL` returns hits for
    // the secret's own .tf definition and a line of operator prose in a heredoc — NEITHER is a
    // feeder. A name-anchored count would report a feeder that does not exist, which is precisely
    // the fiction this manifest replaces. So assert the discriminator directly:
    //   bare name  -> matches (prose/definition exist)
    //   dereference -> does not (no feeder exists)
    expect(gitGrepCount(/GIT_DATA_HEARTBEAT_URL/)).toBeGreaterThan(0);
    expect(realCount("GIT_DATA_HEARTBEAT_URL")).toBe(0);
    // And the positive control: the one heartbeat that IS armed dereferences its URL.
    expect(realCount("INNGEST_HEARTBEAT_URL")).toBeGreaterThan(0);
  });
});

describe("feeder guard is load-bearing (non-vacuity, #6537)", () => {
  const exists = (rel: string) => existsSync(resolve(REPO_ROOT, rel));
  const read = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf8");
  const noConsumers = () => 0;

  const base: ManifestEntry = {
    name: "synthetic_prd",
    arming: "dedicated-host-boot",
    paused: true,
    feeder: { kind: "timer", evidence: { file: "apps/web-platform/infra/cloud-init-registry.yml", pattern: "zot-liveness-heartbeat.timer" } },
    replace_target: { choice: "registry-host-replace", server: "hcloud_server.registry" },
  };

  test("a feeder whose evidence FILE is missing FAILS", () => {
    const m: ManifestEntry[] = [
      { ...base, feeder: { kind: "timer", evidence: { file: "apps/web-platform/infra/does-not-exist.yml", pattern: "x.timer" } } },
    ];
    const v = checkFeeders(m, exists, read, noConsumers);
    expect(v.some((x) => x.includes("does not exist"))).toBe(true);
  });

  test("a feeder whose evidence PATTERN is absent FAILS — with a DIFFERENT message than a missing file", () => {
    // This is the drift case that matters: the file survives a refactor, the unit is renamed, and
    // the heartbeat silently stops being fed. Distinct message => the reader looks in the file,
    // not for the file.
    const m: ManifestEntry[] = [
      { ...base, feeder: { kind: "timer", evidence: { file: "apps/web-platform/infra/cloud-init-registry.yml", pattern: "renamed-away.timer" } } },
    ];
    const v = checkFeeders(m, exists, read, noConsumers);
    expect(v.some((x) => x.includes("does NOT contain"))).toBe(true);
    expect(v.some((x) => x.includes("does not exist"))).toBe(false);
  });

  test("an unfed row with NO tracking issue FAILS (no owner => the #6537 shape)", () => {
    const m: ManifestEntry[] = [
      { name: "orphan_prd", arming: "app-emit", paused: true, exempt_reason: "x", feeder: { kind: "none", url_secret: null, tracking_issue: 0 } },
    ];
    const v = checkFeeders(m, exists, read, noConsumers);
    expect(v.some((x) => x.includes("positive tracking_issue"))).toBe(true);
  });

  test("an unfed row whose url_secret GAINS a consumer FAILS — the forcing function", () => {
    // Simulates #5274 PR C shipping the git-data probe while the row still claims "none".
    // Mutation check: this is the assertion whose ABSENCE let registry_prd sit paused for 9 days
    // while its comment claimed a feeder existed.
    const m: ManifestEntry[] = [
      { name: "unfed_prd", arming: "web-host-cron", paused: true, exempt_reason: "x", feeder: { kind: "none", url_secret: "SOME_HEARTBEAT_URL", tracking_issue: 1 } },
    ];
    const v = checkFeeders(m, exists, read, () => 1);
    expect(v.some((x) => x.includes("a feeder shipped"))).toBe(true);
  });

  test("the real manifest's own evidence patterns are non-trivial (a pattern that matches everything proves nothing)", () => {
    // Guards against the lazy fix: satisfying the forward assertion with a pattern so generic it
    // can never fail (e.g. "" or "a"). Every declared pattern must name a specific unit/path.
    for (const e of MANIFEST) {
      if (e.feeder.kind === "none") continue;
      expect(e.feeder.evidence.pattern.length).toBeGreaterThan(8);
      expect(e.feeder.evidence.file).toMatch(/^apps\/web-platform\/infra\//);
    }
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
