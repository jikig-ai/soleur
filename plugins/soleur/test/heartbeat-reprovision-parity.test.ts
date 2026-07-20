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
  feederDeliveryProbes,
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
      // -P: the bake probe uses a negative lookahead, which POSIX ERE cannot express.
      // Tracked files only — irrelevant in CI, where the tree is always committed.
      ["grep", "-IPc", re.source, "--", ":!knowledge-base"],
      { cwd: REPO_ROOT, encoding: "utf8" },
    );
    return out
      .split("\n")
      .filter(Boolean)
      .reduce((sum, line) => {
        const n = Number(line.slice(line.lastIndexOf(":") + 1));
        // A NaN here would sum to NaN, make `> 0` false, and report NO violation — a silent
        // false-green, the exact class this module exists to kill. Fail loud instead.
        if (!Number.isFinite(n)) {
          throw new Error(`git grep -c produced an unparseable count line: ${JSON.stringify(line)}`);
        }
        return sum + n;
      }, 0);
  } catch (err: unknown) {
    const status = (err as { status?: number }).status;
    if (status === 1) return 0; // no match — the expected "still unfed" outcome
    throw new Error(`git grep failed (exit ${status}) for /${re.source}/`);
  }
}

/**
 * Strip `#` comment lines. The evidence check runs against this view, not the raw file.
 *
 * Load-bearing, and found by review: `inngest-heartbeat.timer` appears THREE times in its
 * bootstrap script — a variable assignment, the real `systemctl enable` line, and a COMMENT. A
 * raw-file substring check therefore stays GREEN after the arming line is deleted, satisfied by
 * the comment alone. That is prose standing in for a feeder — the exact fiction this module
 * exists to kill — reproduced inside the module's own enforcement.
 */
function stripCommentLines(text: string): string {
  return text
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
}

/**
 * The FEEDER guard (#6537) — the executable half of the arming claim.
 *
 * Forward (kind ∈ {cron,timer}): the evidence file must exist and, on its COMMENT-STRIPPED view,
 * contain the ARMING CONSTRUCT — the line that actually causes the feeder to run. Delete or rename
 * the feeder and this turns RED. A comment cannot satisfy it.
 *
 * Inverse (kind === "none"): the heartbeat must have no feeder by EITHER delivery route this repo
 * uses (see `feederDeliveryProbes`) — a Doppler-secret dereference OR a templatefile bake. This is
 * the forcing function #6537 lacked: the day someone ships a feeder for a heartbeat still declared
 * unfed, CI reds and makes them reconcile the row, instead of the feeder landing while the monitor
 * stays paused for 9 days. Both routes are checked because a deref-only guard would be blind to the
 * bake — which is the route #6537 itself made canonical.
 */
function checkFeeders(
  manifest: ManifestEntry[],
  fileExists: (rel: string) => boolean,
  readFile: (rel: string) => string,
  probeHit: (re: RegExp) => boolean,
): string[] {
  const violations: string[] = [];

  for (const e of manifest) {
    const f = e.feeder;

    if (f.kind === "cron" || f.kind === "timer") {
      // Two DISTINCT messages: "the evidence file is gone" and "the file is there but the feeder
      // is not in it" are different failures with different fixes, and collapsing them sends the
      // next reader looking in the wrong place. (grep -F distinguishes them by exit code — 2 vs 1
      // — for the same reason.)
      if (!fileExists(f.evidence.file)) {
        violations.push(
          `heartbeat "${e.name}": feeder evidence file "${f.evidence.file}" does not exist — the declared ${f.kind} cannot be arming it.`,
        );
        continue;
      }
      // Fixed-string containment (grep -F semantics) over code only: the pattern is a literal
      // arming construct, so regex interpretation would only invent metacharacter bugs.
      if (!stripCommentLines(readFile(f.evidence.file)).includes(f.evidence.pattern)) {
        violations.push(
          `heartbeat "${e.name}": "${f.evidence.file}" exists but its CODE does NOT contain the arming construct "${f.evidence.pattern}" — the ${f.kind} was renamed, removed, or survives only in a comment, so nothing feeds this heartbeat.`,
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
    for (const probe of feederDeliveryProbes(e.name, f.url_secret)) {
      if (probeHit(probe)) {
        violations.push(
          `heartbeat "${e.name}": declared UNFED (feeder.kind="none") but /${probe.source}/ now matches — a feeder shipped. Reconcile this row to {kind:"cron"|"timer"} with its arming construct, then arm the heartbeat (verify a real ping lands BEFORE unpausing — #6210).`,
        );
      }
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

  test("the manifest covers exactly the discovered heartbeats (no orphans either way)", () => {
    // Derived, never a hardcoded census. A literal `toBe(6)` was removed here (#6537 review): the
    // set assertions (1a)/(1b) above ALREADY red on an un-manifested 7th heartbeat, with a far
    // better message — while the literal ALSO reds on a sibling who does the work CORRECTLY
    // (adds the .tf AND the row), and turns main red behind them if this branch merges first.
    // That is the all-members-drift-guard-vs-concurrent-sibling trap; the literal bought nothing
    // the set assertions don't, and cost that.
    expect(MANIFEST.length).toBe(collectHeartbeats().length);
  });

  test("registry_disk_prd is the only dedicated-host-boot heartbeat that is SOURCE-unpaused", () => {
    // Named for what it measures. `paused` here is parsed from .tf SOURCE, and this module's own
    // premise is that source != live: inngest_prd is source-paused and LIVE unpaused. Calling this
    // set "live" would be the same species of false claim the PR exists to correct.
    const discovered = collectHeartbeats();
    const sourceUnpaused = MANIFEST.filter(
      (e) =>
        e.arming === "dedicated-host-boot" &&
        !discovered.find((d) => d.name === e.name)!.paused,
    ).map((e) => e.name);
    expect(sourceUnpaused).toEqual(["registry_disk_prd"]);
  });
});

describe("feeder manifest — every arming claim is executable (#6537)", () => {
  const realExists = (rel: string) => existsSync(resolve(REPO_ROOT, rel));
  const realRead = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf8");
  const realProbe = (re: RegExp) => gitGrepCount(re) > 0;

  test("every declared feeder's evidence resolves, and every unfed row is honest", () => {
    expect(checkFeeders(MANIFEST, realExists, realRead, realProbe)).toEqual([]);
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

  test("git_data_prd is now FED by the web-host probe timer — the tripwire fired and was reconciled (#6548)", () => {
    // Was the "still unfed by BOTH routes" tripwire. #5274 PR C (#6548) shipped web-git-data-probe.sh,
    // which dereferences GIT_DATA_HEARTBEAT_URL — so the deref route now matches, EXACTLY the forcing
    // function #6537 designed firing. The row is reconciled from {kind:"none"} to a timer feeder;
    // assert the flip landed AND the deref route is genuinely live (the tripwire's inverse).
    const e = MANIFEST.find((m) => m.name === "git_data_prd")!;
    expect(e.feeder.kind).toBe("timer");
    if (e.feeder.kind === "timer") {
      expect(e.feeder.evidence.file).toBe("apps/web-platform/infra/server.tf");
      expect(e.feeder.evidence.pattern).toBe("systemctl enable --now web-git-data-probe.timer");
    }
    expect(gitGrepCount(/\$\{?GIT_DATA_HEARTBEAT_URL\}?/)).toBeGreaterThan(0);
  });

  test("the guard is DEREFERENCE- and BAKE-anchored, not name-anchored (the traps it replaces)", () => {
    // Trap 1 — name-anchored counting. A bare-name grep for GIT_DATA_HEARTBEAT_URL matches the
    // secret's own `name =` definition, the WEB_*_KEY indirection var names, and operator prose —
    // none of which is a feeder. The deref grep matches only the real read. #5274 PR C (#6548)
    // shipped the probe, so git_data is now FED: BOTH counts are > 0, but the bare-name count
    // STRICTLY EXCEEDS the deref count — the extra hits are definitions/prose, exactly the
    // over-counting a name-anchored guard would have mistaken for feeders.
    const gitDataBareName = gitGrepCount(/GIT_DATA_HEARTBEAT_URL/);
    const gitDataDeref = gitGrepCount(/\$\{?GIT_DATA_HEARTBEAT_URL\}?/);
    expect(gitDataDeref).toBeGreaterThan(0); // the probe now dereferences it for real (#6548)
    expect(gitDataBareName).toBeGreaterThan(gitDataDeref); // bare-name over-counts defs + prose
    // Positive control: inngest also dereferences its URL for real.
    expect(gitGrepCount(/\$\{?INNGEST_HEARTBEAT_URL\}?/)).toBeGreaterThan(0);

    // Trap 2 — deref-only blindness. registry_prd's feeder BAKES its URL via templatefile and
    // dereferences nothing, so a deref-only guard is blind to the very route #6537 canonized.
    // The bake probe sees it; and it must NOT fire on a `value =` secret/output definition.
    const [registryBake] = feederDeliveryProbes("registry_prd", null);
    expect(gitGrepCount(registryBake)).toBeGreaterThan(0);
    const [gitDataBake] = feederDeliveryProbes("git_data_prd", null);
    expect(gitGrepCount(gitDataBake)).toBe(0); // only `value = ...url` exists — a definition
  });
});

describe("feeder guard is load-bearing (non-vacuity, #6537)", () => {
  const exists = (rel: string) => existsSync(resolve(REPO_ROOT, rel));
  const read = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf8");
  const noFeeder = () => false;

  const base: ManifestEntry = {
    name: "synthetic_prd",
    arming: "dedicated-host-boot",
    paused: true,
    feeder: {
      kind: "timer",
      evidence: {
        file: "apps/web-platform/infra/cloud-init-registry.yml",
        pattern: "systemctl enable --now zot-liveness-heartbeat.timer",
      },
    },
    replace_target: { choice: "registry-host-replace", server: "hcloud_server.registry" },
  };

  test("a feeder whose evidence FILE is missing FAILS", () => {
    const m: ManifestEntry[] = [
      { ...base, feeder: { kind: "timer", evidence: { file: "apps/web-platform/infra/does-not-exist.yml", pattern: "x.timer" } } },
    ];
    const v = checkFeeders(m, exists, read, noFeeder);
    expect(v.some((x) => x.includes("does not exist"))).toBe(true);
  });

  test("a feeder whose ARMING CONSTRUCT is absent FAILS — with a DIFFERENT message than a missing file", () => {
    // The drift case that matters: the file survives a refactor, the unit is renamed, and the
    // heartbeat silently stops being fed. Distinct message => the reader looks IN the file, not
    // FOR the file.
    const m: ManifestEntry[] = [
      { ...base, feeder: { kind: "timer", evidence: { file: "apps/web-platform/infra/cloud-init-registry.yml", pattern: "systemctl enable --now renamed-away.timer" } } },
    ];
    const v = checkFeeders(m, exists, read, noFeeder);
    expect(v.some((x) => x.includes("does NOT contain"))).toBe(true);
    expect(v.some((x) => x.includes("does not exist"))).toBe(false);
  });

  test("a COMMENT mentioning the unit does NOT satisfy the evidence check", () => {
    // The class review caught: `inngest-heartbeat.timer` occurs 3x in its bootstrap script and one
    // is a comment, so a raw-file substring check stays green after the arming line is deleted —
    // prose standing in for a feeder, inside the guard built to kill prose. The comment-stripped
    // view is what closes it. `# Posted to Better Stack every 60s by inngest-heartbeat.timer.` is
    // a real comment in that file; a bare-name pattern would match it, the arming construct
    // cannot.
    const m: ManifestEntry[] = [
      { ...base, feeder: { kind: "timer", evidence: { file: "apps/web-platform/infra/inngest-bootstrap.sh", pattern: "Posted to Better Stack every 60s" } } },
    ];
    const v = checkFeeders(m, exists, read, noFeeder);
    expect(v.some((x) => x.includes("does NOT contain"))).toBe(true);
  });

  test("an unfed row with NO tracking issue FAILS (no owner => the #6537 shape)", () => {
    const m: ManifestEntry[] = [
      { name: "orphan_prd", arming: "app-emit", paused: true, exempt_reason: "x", feeder: { kind: "none", url_secret: null, tracking_issue: 0 } },
    ];
    const v = checkFeeders(m, exists, read, noFeeder);
    expect(v.some((x) => x.includes("positive tracking_issue"))).toBe(true);
  });

  test("an unfed row that GAINS a feeder FAILS — the forcing function, on either delivery route", () => {
    // Simulates #5274 PR C shipping the git-data probe while the row still claims "none". This is
    // the assertion whose ABSENCE let registry_prd sit paused for 9 days while its comment claimed
    // a feeder existed.
    const m: ManifestEntry[] = [
      { name: "unfed_prd", arming: "web-host-cron", paused: true, exempt_reason: "x", feeder: { kind: "none", url_secret: "SOME_HEARTBEAT_URL", tracking_issue: 1 } },
    ];
    const v = checkFeeders(m, exists, read, () => true);
    expect(v.some((x) => x.includes("a feeder shipped"))).toBe(true);
  });

  test("the real manifest's evidence patterns are ARMING CONSTRUCTS, not bare names or boilerplate", () => {
    // Replaces a `pattern.length > 8` proxy that certified LENGTH, not specificity: review showed
    // "permissions" (11 chars, 9 hits in the same file) satisfied it. A pattern must be the
    // construct that ARMS the feeder, and must occur a bounded number of times in its own file —
    // boilerplate like `root:root` occurs everywhere and would prove nothing.
    for (const e of MANIFEST) {
      if (e.feeder.kind === "none") continue;
      const { file, pattern } = e.feeder.evidence;
      expect(pattern).toMatch(/^(systemctl enable --now [\w.-]+\.timer|- path: \/etc\/cron\.d\/[\w.-]+)$/);
      expect(file).toMatch(/^apps\/web-platform\/infra\//);
      const hits = stripCommentLines(read(file)).split(pattern).length - 1;
      expect(hits).toBeGreaterThan(0);
      expect(hits).toBeLessThanOrEqual(2); // bounded: a pattern matching everywhere proves nothing
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
      { name: "paused_boot_prd", arming: "dedicated-host-boot", paused: true, feeder: { kind: "none", url_secret: null, tracking_issue: 6537 } },
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
      { name: "newhost_boot_prd", arming: "dedicated-host-boot", paused: false, feeder: { kind: "none", url_secret: null, tracking_issue: 6537 } },
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
        feeder: { kind: "none", url_secret: null, tracking_issue: 6537 },
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
        feeder: { kind: "none", url_secret: null, tracking_issue: 6537 },
        replace_target: { choice: "inngest-host-replace", server: "hcloud_server.inngest" },
        exempt_reason: "paused",
      },
    ];
    const violations = checkHeartbeatParity(discovered, manifest, workflow);
    expect(violations.some((v) => v.includes("inngest_prd") && v.includes("reconcile"))).toBe(true);
  });
});
