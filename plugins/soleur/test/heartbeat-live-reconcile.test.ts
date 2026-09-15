// RED-first (cq-write-failing-tests-before) unit tests for the nightly source-vs-live
// Better Stack heartbeat reconcile (#6549 item 2).
//
// The static `heartbeat-reprovision-parity.test.ts` proves a feeder exists in SOURCE; it cannot
// see a heartbeat that is `paused` or absent in LIVE Better Stack (`ignore_changes = [paused]`
// makes the .tf `paused` value only a lower bound). These tests cover the pure reconcile logic
// that closes that gap — synthetic fixtures only (cq-test-fixtures-synthesized-only), no network.

import { describe, expect, it } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import type { ManifestEntry } from "../lib/heartbeat-manifest";
import {
  type DiscoveredHeartbeat,
  type DiscoveredMonitor,
  type InfraVariables,
  type LiveHeartbeat,
  type LiveMonitor,
  findUnmanagedHeartbeats,
  parseHeartbeatBlocks,
  parseInfraVariables,
  parseLogsAlertBlocks,
  parseMonitorBlocks,
  reconcileHeartbeats,
  reconcileLogsAlerts,
  reconcileMonitors,
  resolveInfraVariables,
  stripComments,
  UnresolvableDeclaration,
} from "../lib/heartbeat-live-reconcile";
import {
  discoverHeartbeatsFromInfra,
  discoverMonitorsFromInfra,
  fetchLiveHeartbeats,
  MAX_PAGES,
  type RunDeps,
  runReconcile,
  VENDOR_FIELD_CAP,
} from "../scripts/reconcile-live-heartbeats";

// --- Synthetic manifest rows (reconcileHeartbeats reads .name + .feeder.kind + .arming_pending) ---
type ManifestRow = Pick<ManifestEntry, "name" | "feeder" | "arming_pending">;

const fedTimer = (name: string): ManifestRow => ({
  name,
  feeder: {
    kind: "timer",
    evidence: { file: "synthetic", pattern: "systemctl enable --now x.timer" },
  },
});
const fedCron = (name: string): ManifestRow => ({
  name,
  feeder: {
    kind: "cron",
    evidence: { file: "synthetic", pattern: "- path: /etc/cron.d/x" },
  },
});
const unfed = (name: string, urlSecret: string | null = null): ManifestRow => ({
  name,
  feeder: { kind: "none", url_secret: urlSecret, tracking_issue: 9999 },
});

const disc = (
  resourceName: string,
  liveName: string,
  opts: { sourcePaused?: boolean; countGated?: boolean } = {},
): DiscoveredHeartbeat => ({
  resourceName,
  liveName,
  sourcePaused: opts.sourcePaused ?? false,
  countGated: opts.countGated ?? false,
});

let liveIdSeq = 1000;
const live = (name: string, paused: boolean, id: string = String(liveIdSeq++)): LiveHeartbeat => ({ id, name, paused });

describe("reconcileHeartbeats — condition (a) live-paused-but-fed (#6537 shape)", () => {
  it("flags a fed heartbeat that is paused in live Better Stack", () => {
    const violations = reconcileHeartbeats(
      [fedTimer("registry_prd")],
      [disc("registry_prd", "soleur-registry-prd")],
      [live("soleur-registry-prd", true)],
    );
    expect(violations).toHaveLength(1);
    expect(violations[0]).toMatchObject({
      resourceName: "registry_prd",
      liveName: "soleur-registry-prd",
      live: "paused",
      reason: "fed-but-paused",
    });
  });

  it("does NOT flag a fed heartbeat that is live-unpaused (armed steady state)", () => {
    const violations = reconcileHeartbeats(
      [fedTimer("inngest_prd"), fedCron("registry_disk_prd")],
      [
        disc("inngest_prd", "soleur-inngest-server-prd"),
        disc("registry_disk_prd", "soleur-registry-disk-prd"),
      ],
      [live("soleur-inngest-server-prd", false), live("soleur-registry-disk-prd", false)],
    );
    expect(violations).toEqual([]);
  });

  it("does NOT flag an UNFED heartbeat that is live-paused (nothing feeds it — not the (a) class)", () => {
    // A kind:"none" monitor that exists live but is paused is a legitimate quiescent state; only a
    // FED heartbeat sitting paused is the 9-days-dark shape.
    const violations = reconcileHeartbeats(
      [unfed("git_data_prd", "GIT_DATA_HEARTBEAT_URL")],
      [disc("git_data_prd", "soleur-git-data-prd")],
      [live("soleur-git-data-prd", true)],
    );
    expect(violations).toEqual([]);
  });

  it("flags a CRON-fed (not just timer-fed) heartbeat that is live-paused", () => {
    // Discriminates the `cron` branch of the `fed` predicate — a cron feeder counts as fed too.
    const violations = reconcileHeartbeats(
      [fedCron("registry_disk_prd")],
      [disc("registry_disk_prd", "soleur-registry-disk-prd")],
      [live("soleur-registry-disk-prd", true)],
    );
    expect(violations).toHaveLength(1);
    expect(violations[0]).toMatchObject({ reason: "fed-but-paused", live: "paused" });
  });

  it("does NOT flag a fed-but-paused heartbeat carrying arming_pending (deferred-arming, ADR-117 FED-but-inert)", () => {
    const armingPending: ManifestRow = {
      ...fedTimer("workspaces_luks"),
      arming_pending: { tracking_issue: 6604 },
    };
    const paused = reconcileHeartbeats(
      [armingPending],
      [disc("workspaces_luks", "soleur-workspaces-luks-prd")],
      [live("soleur-workspaces-luks-prd", true)],
    );
    expect(paused).toEqual([]); // exempt from (a) — its paused state is the owned deferred window
    // But arming_pending does NOT exempt condition (b): a declared-but-absent monitor still surfaces.
    const absent = reconcileHeartbeats(
      [armingPending],
      [disc("workspaces_luks", "soleur-workspaces-luks-prd")],
      [],
    );
    expect(absent).toHaveLength(1);
    expect(absent[0]).toMatchObject({ reason: "absent-live", live: "absent" });
  });
});

describe("reconcileHeartbeats — condition (b) present-in-HCL-absent-live (git_data shape, #6548)", () => {
  it("flags a non-count-gated heartbeat absent from the live payload", () => {
    const violations = reconcileHeartbeats(
      [unfed("git_data_prd", "GIT_DATA_HEARTBEAT_URL")],
      [disc("git_data_prd", "soleur-git-data-prd")],
      [], // live payload omits it entirely
    );
    expect(violations).toHaveLength(1);
    expect(violations[0]).toMatchObject({
      resourceName: "git_data_prd",
      liveName: "soleur-git-data-prd",
      live: "absent",
      reason: "absent-live",
    });
  });

  it("flags a FED heartbeat that is absent-live as (b), not (a)", () => {
    const violations = reconcileHeartbeats(
      [fedTimer("workspaces_luks")],
      [disc("workspaces_luks", "soleur-workspaces-luks-prd")],
      [],
    );
    expect(violations).toHaveLength(1);
    expect(violations[0]).toMatchObject({ live: "absent", reason: "absent-live" });
  });
});

describe("reconcileHeartbeats — item-1 carve-out, EVALUATED (#7884): count resolved to 0 is not expected live", () => {
  const TF = `resource "betteruptime_heartbeat" "github_webhook_sig_failures" {
  count  = var.betterstack_paid_tier ? 1 : 0
  name   = "soleur-github-webhook-sig-failures-prd"
  paused = true
}`;
  const tier = (value: boolean): InfraVariables => new Map([["betterstack_paid_tier", { kind: "bool", value }]]);

  it("does NOT flag a count-gated heartbeat absent live when its count resolves to 0 (free tier)", () => {
    const discovered = parseHeartbeatBlocks(TF, tier(false));
    expect(discovered).toEqual([]); // no instance at all
    expect(reconcileHeartbeats([unfed("github_webhook_sig_failures")], discovered, [])).toEqual([]);
  });

  it("DOES flag it absent-live when its count resolves to 1 (paid tier) — the carve-out is no longer assumed", () => {
    const discovered = parseHeartbeatBlocks(TF, tier(true));
    expect(discovered).toHaveLength(1);
    expect(reconcileHeartbeats([unfed("github_webhook_sig_failures")], discovered, [])).toEqual([
      {
        kind: "heartbeat",
        resourceName: "github_webhook_sig_failures",
        liveName: "soleur-github-webhook-sig-failures-prd",
        live: "absent",
        reason: "absent-live",
      },
    ]);
  });
});

describe("reconcileHeartbeats — OK path + mixed realistic set", () => {
  it("returns no violations when every in-scope heartbeat reconciles", () => {
    const manifest: ManifestRow[] = [
      fedTimer("inngest_prd"),
      fedTimer("registry_prd"),
      fedCron("registry_disk_prd"),
      unfed("git_data_prd", "GIT_DATA_HEARTBEAT_URL"),
      unfed("github_webhook_sig_failures"),
    ];
    const discovered: DiscoveredHeartbeat[] = [
      disc("inngest_prd", "soleur-inngest-server-prd"),
      disc("registry_prd", "soleur-registry-prd"),
      disc("registry_disk_prd", "soleur-registry-disk-prd"),
      disc("git_data_prd", "soleur-git-data-prd"),
      // github_webhook_sig_failures: count resolved to 0 → no discovered instance at all
    ];
    const livePayload: LiveHeartbeat[] = [
      live("soleur-inngest-server-prd", false),
      live("soleur-registry-prd", false),
      live("soleur-registry-disk-prd", false),
      live("soleur-git-data-prd", false), // present + unpaused → git_data fine this run
      // webhook row absent (count-gated) → carved out
    ];
    expect(reconcileHeartbeats(manifest, discovered, livePayload)).toEqual([]);
  });

  it("surfaces both a condition-(a) and a condition-(b) violation together, discriminated by reason", () => {
    const violations = reconcileHeartbeats(
      [fedTimer("registry_prd"), unfed("git_data_prd", "GIT_DATA_HEARTBEAT_URL")],
      [
        disc("registry_prd", "soleur-registry-prd"),
        disc("git_data_prd", "soleur-git-data-prd"),
      ],
      [live("soleur-registry-prd", true)], // registry paused, git-data absent
    );
    expect(violations).toHaveLength(2);
    const reasons = violations.map((v) => v.reason).sort();
    expect(reasons).toEqual(["absent-live", "fed-but-paused"]);
  });
});

describe("parseHeartbeatBlocks — brace-matched .tf parse with comment stripping", () => {
  const TF = `
resource "betteruptime_heartbeat" "registry_prd" {
  name       = "soleur-registry-prd"
  paused     = true # NOTE: a stray "count =" token in this comment must NOT set countGated
  sort_index = 0
}

resource "betteruptime_heartbeat" "webhook_x" {
  count     = var.betterstack_paid_tier ? 1 : 0
  name      = "soleur-webhook-x-prd"
  paused    = true
}

resource "betteruptime_heartbeat" "no_paused_attr" {
  name = "soleur-no-paused-prd"
}
`;

  it("extracts resourceName, liveName, sourcePaused, and countGated per block", () => {
    const blocks = parseHeartbeatBlocks(TF, new Map([["betterstack_paid_tier", { kind: "bool", value: true }]]));
    const byName = Object.fromEntries(blocks.map((b) => [b.resourceName, b]));

    expect(byName.registry_prd).toMatchObject({
      resourceName: "registry_prd",
      liveName: "soleur-registry-prd",
      sourcePaused: true,
      countGated: false, // the comment's "count =" is stripped
    });
    expect(byName.webhook_x).toMatchObject({
      liveName: "soleur-webhook-x-prd",
      countGated: true, // real `count =` meta-arg
    });
    // A block with no explicit `paused` defaults to active (false) — conservative reading, mirrors
    // heartbeat-reprovision-parity.test.ts.
    expect(byName.no_paused_attr).toMatchObject({
      liveName: "soleur-no-paused-prd",
      sourcePaused: false,
      countGated: false,
    });
  });

  it("throws on an unbalanced block (defensive — never silently drop a heartbeat)", () => {
    expect(() =>
      parseHeartbeatBlocks(`resource "betteruptime_heartbeat" "broken" {\n  name = "x"\n`),
    ).toThrow(/unbalanced/i);
  });
});

describe("stripComments — preserves `#` / `//` inside quoted strings", () => {
  it("does not truncate a value that legitimately contains a `#` or `//` in a string literal", () => {
    // If the in-string guard is dropped, `# real config` would be cut and the closing `}` lost.
    const src = `name = "a#b//c" # real trailing comment\nkeep = true`;
    const out = stripComments(src);
    expect(out).toContain('name = "a#b//c"'); // the in-string # and // survive
    expect(out).not.toContain("real trailing comment"); // the real comment is stripped
    expect(out).toContain("keep = true");
  });
});

describe("discoverHeartbeatsFromInfra — reads every .tf, pre-filters, aggregates", () => {
  it("parses heartbeat blocks across multiple .tf files and ignores non-.tf + non-heartbeat files", () => {
    const dir = mkdtempSync(join(tmpdir(), "hb-infra-"));
    try {
      writeFileSync(
        join(dir, "a.tf"),
        `resource "betteruptime_heartbeat" "one" {\n  name = "soleur-one"\n  paused = true\n}`,
      );
      writeFileSync(
        join(dir, "b.tf"),
        `resource "betteruptime_heartbeat" "two" {\n  count = var.paid ? 1 : 0\n  name = "soleur-two"\n}`,
      );
      writeFileSync(join(dir, "variables.tf"), `variable "paid" {\n  type    = bool\n  default = true\n}`);
      writeFileSync(join(dir, "c.tf"), `resource "hcloud_server" "x" {}`); // no heartbeat → skipped
      writeFileSync(join(dir, "notes.md"), `resource "betteruptime_heartbeat" "nope" {}`); // not .tf
      const discovered = discoverHeartbeatsFromInfra(dir).sort((a, b) =>
        a.resourceName.localeCompare(b.resourceName),
      );
      expect(discovered).toEqual([
        { resourceName: "one", liveName: "soleur-one", sourcePaused: true, countGated: false },
        { resourceName: "two", liveName: "soleur-two", sourcePaused: false, countGated: true },
      ]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("runReconcile — tri-state exit contract the drift workflow branches on", () => {
  const noSleep = async () => {};
  // Routes by endpoint: the heartbeats list gets `live`, the (#7884, always-read) monitors list is
  // empty — this infra declares no monitor, so the monitors arm is OK.
  const okFetch =
    (live: LiveHeartbeat[]) =>
    async (url: string) =>
      new Response(
        JSON.stringify({
          data: url.startsWith("https://uptime.betterstack.com/api/v2/heartbeats")
            ? live.map(({ id, ...attributes }) => ({ id, attributes }))
            : [],
          pagination: { next: null },
        }),
        { status: 200 },
      );

  const withInfra = async (
    tf: string,
    fn: (dir: string) => Promise<void>,
  ): Promise<void> => {
    const dir = mkdtempSync(join(tmpdir(), "hb-run-"));
    try {
      writeFileSync(join(dir, "hb.tf"), tf);
      await fn(dir);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };

  const TF = `resource "betteruptime_heartbeat" "reg" {\n  name = "soleur-reg"\n  paused = true\n}`;
  const manifest: ManifestRow[] = [fedTimer("reg")];

  it("token-absent → code 1 + ERROR marker (never touches the network)", async () => {
    const result = await runReconcile("apps/web-platform/infra", { token: "" }, manifest);
    expect(result.code).toBe(1);
    expect(result.markers.join("\n")).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=token-absent");
  });

  it("all reconcile → code 0 + OK marker", async () => {
    await withInfra(TF, async (dir) => {
      const result = await runReconcile(
        dir,
        { token: "t", fetchImpl: okFetch([live("soleur-reg", false)]), sleepImpl: noSleep },
        manifest,
      );
      expect(result.code).toBe(0);
      expect(result.markers.join("\n")).toContain("SOLEUR_HEARTBEAT_RECONCILE_OK");
    });
  });

  it("live-paused fed heartbeat → code 2 + MISMATCH marker", async () => {
    await withInfra(TF, async (dir) => {
      const result = await runReconcile(
        dir,
        { token: "t", fetchImpl: okFetch([live("soleur-reg", true)]), sleepImpl: noSleep },
        manifest,
      );
      expect(result.code).toBe(2);
      expect(result.markers).toContain(
        "SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-reg live=paused reason=fed-but-paused resource=betteruptime_heartbeat.reg",
      );
    });
  });

  it("Better Stack unreachable → code 0 + UNREACHABLE marker (no page)", async () => {
    await withInfra(TF, async (dir) => {
      const result = await runReconcile(
        dir,
        {
          token: "t",
          fetchImpl: async () => new Response("upstream", { status: 503 }),
          sleepImpl: noSleep,
          maxAttempts: 2,
        },
        manifest,
      );
      expect(result.code).toBe(0);
      expect(result.markers.join("\n")).toContain("SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE");
    });
  });

  it("auth failure → code 1 + ERROR marker", async () => {
    await withInfra(TF, async (dir) => {
      const result = await runReconcile(
        dir,
        { token: "t", fetchImpl: async () => new Response("forbidden", { status: 403 }), sleepImpl: noSleep },
        manifest,
      );
      expect(result.code).toBe(1);
      expect(result.markers.join("\n")).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=auth");
    });
  });
});

describe("fetchLiveHeartbeats — flake tolerance + auth (network injected)", () => {
  const noSleep = async () => {};

  it("returns ok with parsed heartbeats on 200, following pagination.next until null", async () => {
    const pages: Record<string, unknown> = {
      "https://uptime.betterstack.com/api/v2/heartbeats": {
        data: [{ id: "11", attributes: { name: "soleur-a", paused: false } }],
        pagination: { next: "https://uptime.betterstack.com/api/v2/heartbeats?page=2" },
      },
      "https://uptime.betterstack.com/api/v2/heartbeats?page=2": {
        data: [{ id: 12, attributes: { name: "soleur-b", paused: true } }],
        pagination: { next: null },
      },
    };
    const fetchImpl = async (url: string) =>
      new Response(JSON.stringify(pages[url]), { status: 200 });

    const result = await fetchLiveHeartbeats({ token: "t", fetchImpl, sleepImpl: noSleep });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.live).toEqual([
        { id: "11", name: "soleur-a", paused: false },
        { id: "12", name: "soleur-b", paused: true },
      ]);
    }
  });

  it("retries transient 5xx up to 3 attempts, then returns unreachable (no page)", async () => {
    let calls = 0;
    const fetchImpl = async () => {
      calls++;
      return new Response("upstream", { status: 503 });
    };
    const result = await fetchLiveHeartbeats({
      token: "t",
      fetchImpl,
      sleepImpl: noSleep,
      maxAttempts: 3,
    });
    expect(calls).toBe(3);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("unreachable");
  });

  it("retries a thrown network error (AbortError/timeout) then returns unreachable", async () => {
    let calls = 0;
    const fetchImpl = async () => {
      calls++;
      throw new Error("The operation was aborted");
    };
    const result = await fetchLiveHeartbeats({
      token: "t",
      fetchImpl,
      sleepImpl: noSleep,
      maxAttempts: 3,
    });
    expect(calls).toBe(3);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("unreachable");
  });

  it("does NOT retry a 401/403 auth failure — returns auth immediately", async () => {
    let calls = 0;
    const fetchImpl = async () => {
      calls++;
      return new Response("forbidden", { status: 403 });
    };
    const result = await fetchLiveHeartbeats({
      token: "t",
      fetchImpl,
      sleepImpl: noSleep,
      maxAttempts: 3,
    });
    expect(calls).toBe(1); // no retry on auth
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("auth");
  });

  it("refuses to follow an off-host pagination.next and never sends the token there (SSRF/exfil guard)", async () => {
    const seen: string[] = [];
    let tokenLeakedOffHost = false;
    const fetchImpl = async (url: string, init?: RequestInit) => {
      seen.push(url);
      // RECORD (never `expect()` inside the mock — the SUT's retry `catch` swallows a thrown assertion,
      // making it inert). We check the recorded flag load-bearingly after the call.
      const auth = new Headers(init?.headers).get("Authorization");
      if (new URL(url).hostname !== "uptime.betterstack.com" && auth !== null) {
        tokenLeakedOffHost = true;
      }
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") {
        return new Response(
          JSON.stringify({
            data: [{ id: "11", attributes: { name: "soleur-a", paused: false } }],
            pagination: { next: "https://evil.example.com/api/v2/heartbeats" },
          }),
          { status: 200 },
        );
      }
      return new Response("{}", { status: 200 });
    };
    const result = await fetchLiveHeartbeats({ token: "secret", fetchImpl, sleepImpl: noSleep });
    // Load-bearing: the token never reached a non-trusted host, and the off-host URL was never fetched.
    // With the host pin removed, BOTH of these fail (the guard is what makes them pass).
    expect(tokenLeakedOffHost).toBe(false);
    expect(seen).not.toContain("https://evil.example.com/api/v2/heartbeats");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("error");
  });

  it("refuses an HTTP 3xx redirect (redirect:manual) — the token is never re-sent to the Location", async () => {
    const seen: string[] = [];
    let tokenLeakedOffHost = false;
    const fetchImpl = async (url: string, init?: RequestInit) => {
      seen.push(url);
      const auth = new Headers(init?.headers).get("Authorization");
      if (new URL(url).hostname !== "uptime.betterstack.com" && auth !== null) {
        tokenLeakedOffHost = true;
      }
      // A MITM/compromised-edge 302 pointing the token at an attacker host.
      return new Response(null, {
        status: 302,
        headers: { location: "https://evil.example.com/collect" },
      });
    };
    const result = await fetchLiveHeartbeats({ token: "secret", fetchImpl, sleepImpl: noSleep });
    expect(tokenLeakedOffHost).toBe(false);
    expect(seen).toEqual(["https://uptime.betterstack.com/api/v2/heartbeats"]); // only the initial URL
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("error");
  });

  it("treats a malformed 200 body (no data array) as an error, not a silent empty", async () => {
    const fetchImpl = async () => new Response(JSON.stringify({ nope: true }), { status: 200 });
    const result = await fetchLiveHeartbeats({ token: "t", fetchImpl, sleepImpl: noSleep });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("error");
  });
});

// ─── #8097 / ADR-218: the `logs_alert` arm ───────────────────────────────────────────────────
// A Better Stack LOGS alert (logtail_exploration_alert) is re-armed by every per-merge apply, so
// the untargeted drift plan cannot detect a vendor-side pause between merges. This arm reads
// GET telemetry.betterstack.com/api/v2/alerts through the SAME injected fetchImpl and reports an
// absent or paused alert as a MISMATCH (rc=2 — the workflow's issue path keys on rc, not on
// marker text). The alert names are DISCOVERED from the .tf, never listed here.
describe("logs_alert arm — reconcileLogsAlerts + parseLogsAlertBlocks (#8097)", () => {
  it("parseLogsAlertBlocks extracts every logtail_exploration_alert name, comment-stripped", () => {
    const tf = [
      `# resource "logtail_exploration_alert" "in_a_comment" { name = "nope" }`,
      `resource "logtail_exploration_alert" "monitor_send_failed" {`,
      `  exploration_id = logtail_exploration.monitor_send_failed.id`,
      `  name           = "soleur-monitor-send-failed-prd" # trailing`,
      `  escalation_target { team_name = "Your team" }`,
      `}`,
      `resource "logtail_exploration_alert" "second" {\n  name = "soleur-second-prd"\n}`,
    ].join("\n");
    expect(parseLogsAlertBlocks(tf)).toEqual([
      { resourceName: "monitor_send_failed", liveName: "soleur-monitor-send-failed-prd" },
      { resourceName: "second", liveName: "soleur-second-prd" },
    ]);
  });

  it("flags a declared alert that is paused live as logs-alert-paused, carrying paused_reason", () => {
    const v = reconcileLogsAlerts(
      [{ resourceName: "monitor_send_failed", liveName: "soleur-monitor-send-failed-prd" }],
      [{ name: "soleur-monitor-send-failed-prd", paused: true, pausedReason: "complexity issues, too many failures" }],
    );
    expect(v).toEqual([
      {
        kind: "logs_alert",
        resourceName: "monitor_send_failed",
        liveName: "soleur-monitor-send-failed-prd",
        live: "logs_alert",
        reason: "logs-alert-paused",
        detail: "complexity issues, too many failures",
      },
    ]);
  });

  it("flags a declared alert missing from the live payload as logs-alert-absent", () => {
    const v = reconcileLogsAlerts(
      [{ resourceName: "monitor_send_failed", liveName: "soleur-monitor-send-failed-prd" }],
      [{ name: "Output utilization high", paused: true, pausedReason: "Manually paused" }],
    );
    expect(v.map((x) => x.reason)).toEqual(["logs-alert-absent"]);
  });

  it("returns no violations when every declared alert is present and unpaused (foreign paused alerts ignored)", () => {
    const v = reconcileLogsAlerts(
      [{ resourceName: "monitor_send_failed", liveName: "soleur-monitor-send-failed-prd" }],
      [
        { name: "soleur-monitor-send-failed-prd", paused: false, pausedReason: "" },
        { name: "Output utilization high", paused: true, pausedReason: "Manually paused" },
      ],
    );
    expect(v).toEqual([]);
  });
});

describe("runReconcile — logs_alert arm through the injected fetchImpl (#8097)", () => {
  const noSleep = async () => {};
  const HB_TF = `resource "betteruptime_heartbeat" "reg" {\n  name = "soleur-reg"\n  paused = false\n}`;
  const ALERT_TF = `resource "logtail_exploration_alert" "monitor_send_failed" {\n  name = "soleur-monitor-send-failed-prd"\n  paused = false\n}`;
  const manifest: ManifestRow[] = [fedTimer("reg")];

  const page = (rows: unknown[]) =>
    new Response(JSON.stringify({ data: rows, pagination: { next: null } }), { status: 200 });
  const hbPage = (h: LiveHeartbeat) => page([{ id: h.id, attributes: { name: h.name, paused: h.paused } }]);
  const MONITORS = "https://uptime.betterstack.com/api/v2/monitors";
  // Dispatches on URL so the heartbeat and alert reads are distinguishable — and so a read of
  // any OTHER host is refused loudly rather than answered.
  const routed =
    (alerts: unknown[], onOther?: (u: string) => void) =>
    async (url: string) => {
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return hbPage(live("soleur-reg", false));
      if (url === MONITORS) return page([]); // #7884: the monitors arm always reads; none declared here
      if (url === "https://telemetry.betterstack.com/api/v2/alerts") return page(alerts);
      onOther?.(url);
      return new Response("unexpected host", { status: 500 });
    };

  const withInfra = async (files: Record<string, string>, fn: (dir: string) => Promise<void>) => {
    const dir = mkdtempSync(join(tmpdir(), "hb-la-"));
    try {
      for (const [n, t] of Object.entries(files)) writeFileSync(join(dir, n), t);
      await fn(dir);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };

  it("paused live alert → code 2 + MISMATCH … live=logs_alert reason=logs-alert-paused detail=\"…\"", async () => {
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(
        dir,
        {
          token: "t",
          fetchImpl: routed([{ attributes: { name: "soleur-monitor-send-failed-prd", paused: true, paused_reason: "too many failures" } }]),
          sleepImpl: noSleep,
        },
        manifest,
      );
      expect(result.code).toBe(2);
      const out = result.markers.join("\n");
      // The ADR-218 / runbook prefix stays byte-identical; `resource=` sits immediately before the
      // quoted vendor text so the vendor text stays last.
      expect(result.markers).toContain(
        'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-monitor-send-failed-prd live=logs_alert reason=logs-alert-paused resource=logtail_exploration_alert.monitor_send_failed detail="too many failures"',
      );
    });
  });

  it("absent live alert → code 2 + reason=logs-alert-absent", async () => {
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(dir, { token: "t", fetchImpl: routed([]), sleepImpl: noSleep }, manifest);
      expect(result.code).toBe(2);
      expect(result.markers.join("\n")).toContain("live=logs_alert reason=logs-alert-absent");
    });
  });

  it("present + unpaused → code 0 and a second OK marker for the logs_alert surface", async () => {
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(
        dir,
        {
          token: "t",
          fetchImpl: routed([{ attributes: { name: "soleur-monitor-send-failed-prd", paused: false, paused_reason: null } }]),
          sleepImpl: noSleep,
        },
        manifest,
      );
      expect(result.code).toBe(0);
      expect(result.markers.join("\n")).toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=logs_alert declared=1 live=1");
    });
  });

  it("no logtail_exploration_alert declared → the alerts endpoint is never read (no new network on legacy roots)", async () => {
    await withInfra({ "hb.tf": HB_TF }, async (dir) => {
      const seen: string[] = [];
      const base = routed([]);
      // Record EVERY url — a recorder that only sees unrouted hosts cannot see the alerts read.
      const fetchImpl = async (url: string) => {
        seen.push(url);
        return base(url);
      };
      const result = await runReconcile(dir, { token: "t", fetchImpl, sleepImpl: noSleep }, manifest);
      expect(result.code).toBe(0);
      expect(seen.filter((u) => u.includes("/api/v2/alerts"))).toEqual([]);
      expect(seen).toEqual(["https://uptime.betterstack.com/api/v2/heartbeats", "https://uptime.betterstack.com/api/v2/monitors"]);
    });
  });

  it("heartbeats endpoint unreachable + alert paused → the arms are independent: UNREACHABLE(heartbeats) + MISMATCH(logs_alert), code 2", async () => {
    const fetchImpl = async (url: string) => {
      if (url === "https://telemetry.betterstack.com/api/v2/alerts") {
        return page([{ attributes: { name: "soleur-monitor-send-failed-prd", paused: true, paused_reason: "too many failures" } }]);
      }
      return new Response("upstream", { status: 503 });
    };
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(dir, { token: "t", fetchImpl, sleepImpl: noSleep }, manifest);
      expect(result.code).toBe(2);
      const out = result.markers.join("\n");
      expect(out).toContain("SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=heartbeats");
      expect(out).toContain("live=logs_alert reason=logs-alert-paused");
    });
  });

  it("heartbeat MISMATCH + alerts auth failure → ERROR wins: code 1 with both markers present", async () => {
    const fetchImpl = async (url: string) => {
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return hbPage(live("soleur-reg", true));
      if (url === MONITORS) return page([]);
      return new Response("forbidden", { status: 403 });
    };
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(dir, { token: "t", fetchImpl, sleepImpl: noSleep }, manifest);
      expect(result.code).toBe(1);
      const out = result.markers.join("\n");
      expect(out).toContain("reason=fed-but-paused");
      expect(out).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=logs_alert reason=auth");
    });
  });

  it("a paused_reason carrying U+2028 / control chars / quotes cannot break the marker line", async () => {
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(
        dir,
        {
          token: "t",
          fetchImpl: routed([{ attributes: { name: "soleur-monitor-send-failed-prd", paused: true, paused_reason: "too\u2028many\x7f\"failures`" } }]),
          sleepImpl: noSleep,
        },
        manifest,
      );
      expect(result.code).toBe(2);
      const line = result.markers.find((m) => m.includes("live=logs_alert"))!;
      // `"` is percent-encoded (not stripped), so the quote cannot close the field early.
      expect(line).toMatch(/detail="too many %22failures "$/);
      expect(line).not.toMatch(/[\u2028\x7f`]/);
    });
  });

  it("a heartbeat MISMATCH and an alert MISMATCH combine to one rc=2 run carrying both markers", async () => {
    const pausedHb = async (url: string) => {
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return hbPage(live("soleur-reg", true));
      return page([]);
    };
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(dir, { token: "t", fetchImpl: pausedHb, sleepImpl: noSleep }, manifest);
      expect(result.code).toBe(2);
      const out = result.markers.join("\n");
      expect(out).toContain("reason=fed-but-paused");
      expect(out).toContain("reason=logs-alert-absent");
    });
  });

  it("refuses an off-host pagination.next on the ALERTS read — the second host pin is exact, not a suffix", async () => {
    let tokenLeakedOffHost = false;
    const fetchImpl = async (url: string, init?: RequestInit) => {
      const auth = (init?.headers as Record<string, string> | undefined)?.Authorization;
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return hbPage(live("soleur-reg", false));
      if (url === MONITORS) return page([]);
      if (url === "https://telemetry.betterstack.com/api/v2/alerts") {
        return new Response(
          // A host sharing the vendor SUFFIX: `endsWith("betterstack.com")` accepts it; only equality refuses.
          JSON.stringify({ data: [], pagination: { next: "https://evil-telemetry.betterstack.com/api/v2/alerts?page=2" } }),
          { status: 200 },
        );
      }
      if (auth) tokenLeakedOffHost = true;
      return new Response("nope", { status: 200 });
    };
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(dir, { token: "secret", fetchImpl, sleepImpl: noSleep }, manifest);
      expect(tokenLeakedOffHost).toBe(false);
      expect(result.code).toBe(1);
      expect(result.markers.join("\n")).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR");
    });
  });

  it("alerts endpoint unreachable (5xx) → UNREACHABLE marker for the arm, never a MISMATCH (no page on a vendor blip)", async () => {
    const fetchImpl = async (url: string) => {
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return hbPage(live("soleur-reg", false));
      if (url === MONITORS) return page([]);
      return new Response("upstream", { status: 503 });
    };
    await withInfra({ "hb.tf": HB_TF, "alerts.tf": ALERT_TF }, async (dir) => {
      const result = await runReconcile(dir, { token: "t", fetchImpl, sleepImpl: noSleep }, manifest);
      expect(result.code).toBe(0);
      const out = result.markers.join("\n");
      expect(out).toContain("SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE");
      expect(out).toContain("surface=logs_alert");
      expect(out).not.toContain("MISMATCH");
    });
  });
});

// ─── #7884 Guard 2: Better Stack live inventory reconcile ─────────────────────────────────────
// Property: every live Better Stack uptime monitor and heartbeat is accounted for by exactly one
// resolved Terraform declaration (monitors by literal URL, heartbeats by resolved name), every
// declared instance is live, every declared monitor's live type/keyword/paused equals its
// declaration, and every outcome is a marker whose routing tokens vendor text cannot forge.
// Synthetic fixtures only (cq-test-fixtures-synthesized-only); network injected.

const UPTIME = "https://uptime.betterstack.com";
const MON_URL = `${UPTIME}/api/v2/monitors`;
const HB_URL = `${UPTIME}/api/v2/heartbeats`;
const HEALTH = "https://app.soleur.ai/health";
const APP = "https://app.soleur.ai/";
const WEBHOOK = "https://soleur.ai/api/webhooks/github";
const KW = '"supabase":"connected"';

// A `web_hosts`-shaped variable: quoted keys, nested object values, a multi-line `type`, and
// trailing `validation {}` blocks whose strings carry braces (`{1,3}`) — the resolver must read only
// the top-level keys of the default.
const G2_VARIABLES_TF = `
variable "web_hosts" {
  description = "Web-host cluster {keys immutable}"
  type = map(object({
    location    = string
    private_ip  = string
    server_type = optional(string, "cx33")
  }))
  # default = { "web-9" = {} }  <- a commented-out default must not be read
  default = {
    "web-1" = { location = "hel1", private_ip = "10.0.1.10" }
    "web-2" = { location = "hel1", private_ip = "10.0.1.11", server_type = "cpx22" }
  }
  validation {
    condition     = alltrue([for h in values(var.web_hosts) : can(regex("^10\\\\.0\\\\.1\\\\.[0-9]{1,3}$", h.private_ip))])
    error_message = "web_hosts private_ip must be in 10.0.1.0/24 {default = nope}."
  }
}

variable "betterstack_paid_tier" {
  type    = bool
  default = false
}
`;

const G2_MONITORS_TF = `
resource "betteruptime_monitor" "app_health" {
  monitor_type       = "keyword"
  url                = "https://app.soleur.ai/health"
  pronounceable_name = "soleur app database readiness"
  required_keyword   = "\\"supabase\\":\\"connected\\""
  paused             = false
}

resource "betteruptime_monitor" "app" {
  paused       = false
  url          = "https://app.soleur.ai/"
  monitor_type = "status"
}

resource "betteruptime_monitor" "github_webhook_failures" {
  count        = var.betterstack_paid_tier ? 1 : 0
  url          = "https://soleur.ai/api/webhooks/github"
  monitor_type = "expected_status_code"
}
`;

const G2_HEARTBEATS_TF = `
resource "betteruptime_heartbeat" "reg" {
  name   = "soleur-reg"
  paused = true
  lifecycle {
    ignore_changes = [paused]
  }
}

resource "betteruptime_heartbeat" "web_zot_consumer" {
  for_each = var.web_hosts
  name     = "soleur-web-zot-consumer-\${each.key}"
  paused   = true
}

resource "betteruptime_heartbeat" "web_nic_guard" {
  for_each  = var.web_hosts
  name      = "soleur-web-nic-guard-\${each.key}"
  team_name = "Your team"
}
`;

const G2_MANIFEST: ManifestRow[] = [fedTimer("reg"), unfed("web_zot_consumer"), unfed("web_nic_guard")];

const monRow = (
  id: string | number,
  url: unknown,
  o: { type?: string; kw?: string | null; paused?: boolean; name?: string; extra?: Record<string, unknown> } = {},
) => ({
  id,
  type: "monitor",
  attributes: {
    url,
    monitor_type: o.type ?? "status",
    required_keyword: o.kw === undefined ? null : o.kw,
    paused: o.paused ?? false,
    pronounceable_name: o.name ?? `monitor ${id}`,
    ...o.extra,
  },
});
const hbRow = (id: string | number, name: string, paused = false, extra: Record<string, unknown> = {}) => ({
  id,
  type: "heartbeat",
  attributes: { name, paused, ...extra },
});
const COMPLIANT_MONITORS = () => [monRow("101", HEALTH, { type: "keyword", kw: KW }), monRow("102", APP)];
const COMPLIANT_HEARTBEATS = () => [
  hbRow("201", "soleur-reg"),
  hbRow("202", "soleur-web-zot-consumer-web-1"),
  hbRow("203", "soleur-web-zot-consumer-web-2"),
  hbRow("204", "soleur-web-nic-guard-web-1"),
  hbRow("205", "soleur-web-nic-guard-web-2"),
];

const listPage = (rows: unknown[], next: string | null = null) =>
  new Response(JSON.stringify({ data: rows, pagination: { next } }), { status: 200 });

type Route = (url: string) => Response;
interface G2Input {
  files?: Record<string, string | null>;
  monitors?: unknown[] | Route;
  heartbeats?: unknown[] | Route;
  deps?: RunDeps;
  seen?: string[];
}
interface G2Result {
  code: number;
  markers: string[];
  out: string;
}

/** Every G2 run's markers — the marker-key property assertion runs over all of them. */
const G2_OUTPUTS: string[][] = [];

async function g2(input: G2Input = {}): Promise<G2Result> {
  const dir = mkdtempSync(join(tmpdir(), "hb-g2-"));
  const files: Record<string, string | null> = {
    "variables.tf": G2_VARIABLES_TF,
    "monitors.tf": G2_MONITORS_TF,
    "heartbeats.tf": G2_HEARTBEATS_TF,
    ...input.files,
  };
  const route = (spec: unknown[] | Route | undefined, fallback: () => unknown[], url: string) =>
    typeof spec === "function" ? spec(url) : listPage(spec ?? fallback());
  const fetchImpl = async (url: string) => {
    input.seen?.push(url);
    if (url === MON_URL || url.startsWith(`${MON_URL}?`)) return route(input.monitors, COMPLIANT_MONITORS, url);
    if (url === HB_URL || url.startsWith(`${HB_URL}?`)) return route(input.heartbeats, COMPLIANT_HEARTBEATS, url);
    return new Response("unrouted", { status: 404 });
  };
  try {
    for (const [name, text] of Object.entries(files)) if (text !== null) writeFileSync(join(dir, name), text);
    const r = await runReconcile(dir, { token: "t", fetchImpl, sleepImpl: async () => {}, maxAttempts: 1 }, G2_MANIFEST, input.deps);
    G2_OUTPUTS.push(r.markers);
    return { ...r, out: r.markers.join("\n") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** Routing tokens of a marker line: only the text before its first `"` is ever routed on. */
const preQuoteTokens = (line: string) =>
  line
    .split('"')[0]
    .trim()
    .split(/\s+/)
    .filter((t) => /^(surface|reason|resource|id)=/.test(t));
const mismatchLines = (r: G2Result) => r.markers.filter((m) => m.startsWith("SOLEUR_HEARTBEAT_RECONCILE_MISMATCH "));
const BIDI_OR_INVISIBLE = new RegExp(
  `[${[[0x200b, 0x200f], [0x202a, 0x202e], [0x2066, 0x2069], [0xfeff, 0xfeff]]
    .map(([a, b]) => `${String.fromCharCode(a)}-${String.fromCharCode(b)}`)
    .join("")}]`,
);

// Rows the H1 harness re-runs with a no-op `reconcileMonitors` — each MUST go RED there.
const H1_ROWS: { row: string; input: () => G2Input; assert: (r: G2Result) => void }[] = [
  {
    row: "1 unmanaged live monitor",
    input: () => ({ monitors: [...COMPLIANT_MONITORS(), monRow("9", "https://example.soleur.ai/")] }),
    assert: (r) => {
      expect(r.code).toBe(2);
      expect(r.markers).toContain(
        'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=9 url="https://example.soleur.ai/" name="monitor 9"',
      );
      // The arm summary still prints (positive control), and never lists the unmanaged id.
      expect(r.markers).toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=2 live=3 matched=101,102");
    },
  },
  {
    row: "2 second live monitor on the declared health URL",
    input: () => ({ monitors: [...COMPLIANT_MONITORS(), monRow("103", HEALTH, { type: "keyword", kw: KW })] }),
    assert: (r) => {
      expect(r.code).toBe(2);
      expect(r.out).toContain(`surface=monitors reason=unmanaged-live id=101 dup=url url="${HEALTH}"`);
      expect(r.out).toContain(`surface=monitors reason=unmanaged-live id=103 dup=url url="${HEALTH}"`);
      // Neither is picked as managed, so neither yields a drift row or a matched id.
      expect(r.out).not.toContain("monitor-config-drift");
      expect(r.markers).toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=2 live=3 matched=102");
    },
  },
  {
    row: "4 monitors endpoint empty while declarations exist",
    input: () => ({ monitors: [] }),
    assert: (r) => {
      expect(r.code).toBe(2);
      expect(r.markers).toContain(
        `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=betteruptime_monitor.app_health url="${HEALTH}"`,
      );
      expect(r.markers).toContain(
        `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=betteruptime_monitor.app url="${APP}"`,
      );
      // count resolved to 0 → not expected live
      expect(r.out).not.toContain("github_webhook_failures");
    },
  },
  {
    row: "7 declared keyword monitor live as status",
    input: () => ({ monitors: [monRow("101", HEALTH, { type: "status", kw: KW }), monRow("102", APP)] }),
    assert: (r) => {
      expect(r.code).toBe(2);
      expect(mismatchLines(r)).toEqual([
        'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=101 resource=betteruptime_monitor.app_health field=monitor_type detail="declared=keyword live=status"',
      ]);
    },
  },
  {
    row: "17 live monitor on a count-gated (default false) declaration's URL",
    input: () => ({ monitors: [...COMPLIANT_MONITORS(), monRow("104", WEBHOOK, { type: "expected_status_code" })] }),
    assert: (r) => {
      expect(r.code).toBe(2);
      expect(r.out).toContain(`surface=monitors reason=unmanaged-live id=104 url="${WEBHOOK}"`);
    },
  },
];

describe("Guard 2 (#7884) — resolveInfraVariables / declaration resolution", () => {
  it("reads only top-level keys of a literal map default (nested objects + validation blocks skipped) and bool defaults", () => {
    const vars = parseInfraVariables(G2_VARIABLES_TF);
    expect(vars.get("web_hosts")).toEqual({ kind: "map", keys: ["web-1", "web-2"] });
    expect(vars.get("betterstack_paid_tier")).toEqual({ kind: "bool", value: false });
  });

  it("a non-literal default is `other`, and a variable without a default is absent", () => {
    const vars = parseInfraVariables(
      `variable "a" {\n  default = local.x\n}\nvariable "b" {\n  type = string\n}\nvariable "c" {\n  default = { web-1 = 1, "web 2" = 2 }\n}`,
    );
    expect(vars.get("a")).toEqual({ kind: "other" });
    expect(vars.has("b")).toBe(false);
    expect(vars.get("c")).toEqual({ kind: "map", keys: ["web-1", "web 2"] });
  });

  it("for_each = var.<map> yields one instance per key with ${each.key} substituted; count = var.<bool> ? 1 : 0 yields 1 or 0", () => {
    const vars = parseInfraVariables(G2_VARIABLES_TF);
    expect(parseHeartbeatBlocks(G2_HEARTBEATS_TF, vars).map((h) => `${h.resourceName}:${h.liveName}`)).toEqual([
      "reg:soleur-reg",
      "web_zot_consumer:soleur-web-zot-consumer-web-1",
      "web_zot_consumer:soleur-web-zot-consumer-web-2",
      "web_nic_guard:soleur-web-nic-guard-web-1",
      "web_nic_guard:soleur-web-nic-guard-web-2",
    ]);
    const monitors: DiscoveredMonitor[] = parseMonitorBlocks(G2_MONITORS_TF, vars);
    expect(monitors).toEqual([
      { resourceName: "app_health", url: HEALTH, monitorType: "keyword", requiredKeyword: KW, paused: false },
      { resourceName: "app", url: APP, monitorType: "status", requiredKeyword: "", paused: false },
    ]);
  });

  it("an UnresolvableDeclaration names the resource as <type>.<name>", () => {
    const vars = parseInfraVariables(G2_VARIABLES_TF);
    let caught: unknown;
    try {
      parseHeartbeatBlocks(`resource "betteruptime_heartbeat" "bad" {\n  for_each = var.betterstack_paid_tier\n  name = "x-\${each.key}"\n}`, vars);
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(UnresolvableDeclaration);
    expect((caught as UnresolvableDeclaration).resource).toBe("betteruptime_heartbeat.bad");
  });
});

describe("Guard 2 (#7884) — mutation matrix rows 1-19", () => {
  it("baseline: the compliant fixture is GREEN with OK markers on both uptime arms and an INVENTORY line", async () => {
    const r = await g2();
    expect(r.code).toBe(0);
    expect(r.markers).toEqual([
      "SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats checked=5 live=5",
      "SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=2 live=2 matched=101,102",
      "SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=2 heartbeats=5 total=7",
    ]);
  });

  for (const h of H1_ROWS) {
    it(`row ${h.row} → RED`, async () => {
      h.assert(await g2(h.input()));
    });
  }

  it("row 3: an unmanaged monitor only on page 2 is still reported", async () => {
    const seen: string[] = [];
    const r = await g2({
      seen,
      monitors: (url) =>
        url === MON_URL ? listPage(COMPLIANT_MONITORS(), `${MON_URL}?page=2`) : listPage([monRow("9", "https://example.soleur.ai/")]),
    });
    expect(seen).toContain(`${MON_URL}?page=2`);
    expect(r.code).toBe(2);
    expect(r.out).toContain('surface=monitors reason=unmanaged-live id=9 url="https://example.soleur.ai/"');
    expect(r.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=3 heartbeats=5 total=8");
  });

  it("row 5: live heartbeat soleur-web-zot-consumer-web-1-old → unmanaged-live", async () => {
    const r = await g2({ heartbeats: [...COMPLIANT_HEARTBEATS(), hbRow("301", "soleur-web-zot-consumer-web-1-old")] });
    expect(r.code).toBe(2);
    expect(mismatchLines(r)).toEqual([
      'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=heartbeats reason=unmanaged-live id=301 name="soleur-web-zot-consumer-web-1-old"',
    ]);
  });

  it("row 6: live heartbeat soleur-web-zot-consumer-web-3 (a key the default does not have) → unmanaged-live", async () => {
    const r = await g2({ heartbeats: [...COMPLIANT_HEARTBEATS(), hbRow("302", "soleur-web-zot-consumer-web-3")] });
    expect(r.code).toBe(2);
    expect(r.out).toContain('surface=heartbeats reason=unmanaged-live id=302 name="soleur-web-zot-consumer-web-3"');
  });

  it("row 6b: two live heartbeats sharing a declared name → both unmanaged-live dup=name", async () => {
    const r = await g2({ heartbeats: [...COMPLIANT_HEARTBEATS(), hbRow("303", "soleur-reg")] });
    expect(r.code).toBe(2);
    expect(r.out).toContain('surface=heartbeats reason=unmanaged-live id=201 dup=name name="soleur-reg"');
    expect(r.out).toContain('surface=heartbeats reason=unmanaged-live id=303 dup=name name="soleur-reg"');
  });

  it("row 7: one monitor-config-drift row per drifted field (required_keyword, paused, and all three at once)", async () => {
    const kw = await g2({ monitors: [monRow("101", HEALTH, { type: "keyword", kw: '"supabase":"ok"' }), monRow("102", APP)] });
    expect(mismatchLines(kw)).toEqual([
      'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=101 resource=betteruptime_monitor.app_health field=required_keyword detail="declared=%22supabase%22:%22connected%22 live=%22supabase%22:%22ok%22"',
    ]);
    const paused = await g2({ monitors: [monRow("101", HEALTH, { type: "keyword", kw: KW, paused: true }), monRow("102", APP)] });
    expect(mismatchLines(paused)).toEqual([
      'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=101 resource=betteruptime_monitor.app_health field=paused detail="declared=false live=true"',
    ]);
    const all = await g2({ monitors: [monRow("101", HEALTH, { type: "status", kw: null, paused: true }), monRow("102", APP)] });
    expect(all.code).toBe(2);
    expect(mismatchLines(all).map((l) => /field=([a-z_]+)/.exec(l)?.[1])).toEqual(["monitor_type", "required_keyword", "paused"]);
    // AC8 shape: drift rows AND the drifted id in the arm summary's matched= list.
    expect(all.markers).toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=2 live=2 matched=101,102");
  });

  it("row 8: a declaration present only inside a `#` comment does not account for its live object", async () => {
    const commented = G2_MONITORS_TF.replace(
      /resource "betteruptime_monitor" "app" \{[\s\S]*?\n\}/,
      (block) => block.split("\n").map((l) => `# ${l}`).join("\n"),
    );
    expect(commented).not.toBe(G2_MONITORS_TF);
    const r = await g2({ files: { "monitors.tf": commented } });
    expect(r.code).toBe(2);
    expect(r.out).toContain(`surface=monitors reason=unmanaged-live id=102 url="${APP}"`);
  });

  const UNRESOLVABLE = (resource: string) =>
    `SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=unresolvable-declaration resource=${resource}`;

  it('row 9: heartbeat name = "soleur-${local.x}" → rc 1 unresolvable-declaration', async () => {
    const r = await g2({ files: { "bad.tf": `resource "betteruptime_heartbeat" "bad" {\n  name = "soleur-\${local.x}"\n}` } });
    expect(r.code).toBe(1);
    expect(r.markers).toContain(UNRESOLVABLE("betteruptime_heartbeat.bad"));
    // Fail closed: no heartbeats verdict is computed from a partial declared set.
    expect(r.out).not.toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats");
    expect(r.out).not.toContain("surface=heartbeats reason=unmanaged-live");
  });

  it("row 10: heartbeat for_each = local.hosts → rc 1 unresolvable-declaration", async () => {
    const r = await g2({
      files: { "bad.tf": `resource "betteruptime_heartbeat" "bad" {\n  for_each = local.hosts\n  name = "soleur-\${each.key}"\n}` },
    });
    expect(r.code).toBe(1);
    expect(r.markers).toContain(UNRESOLVABLE("betteruptime_heartbeat.bad"));
  });

  it("row 11: heartbeat count = 2 → rc 1 unresolvable-declaration", async () => {
    const r = await g2({ files: { "bad.tf": `resource "betteruptime_heartbeat" "bad" {\n  count = 2\n  name = "soleur-bad"\n}` } });
    expect(r.code).toBe(1);
    expect(r.markers).toContain(UNRESOLVABLE("betteruptime_heartbeat.bad"));
  });

  it("row 12: two declared monitors on the same URL (different files) → rc 1 unresolvable-declaration", async () => {
    const r = await g2({
      files: { "zz-dup.tf": `resource "betteruptime_monitor" "app_again" {\n  monitor_type = "status"\n  url = "https://app.soleur.ai/"\n}` },
    });
    expect(r.code).toBe(1);
    expect(r.markers).toContain(UNRESOLVABLE("betteruptime_monitor.app_again"));
    expect(r.out).not.toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors");
  });

  it("row 13: monitors read 401 while heartbeats read OK → rc 1, no INVENTORY line", async () => {
    const r = await g2({ monitors: () => new Response("unauthorized", { status: 401 }) });
    expect(r.code).toBe(1);
    expect(r.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=auth");
    expect(r.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats");
    expect(r.out).not.toContain("SOLEUR_HEARTBEAT_RECONCILE_INVENTORY");
  });

  it("row 14: monitors endpoint 5xx after retries → UNREACHABLE surface=monitors, no OK surface=monitors, no INVENTORY", async () => {
    const r = await g2({ monitors: () => new Response("upstream", { status: 503 }) });
    expect(r.code).toBe(0);
    expect(r.out).toContain('SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=monitors detail="HTTP 503"');
    expect(r.out).not.toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors");
    expect(r.out).not.toContain("SOLEUR_HEARTBEAT_RECONCILE_INVENTORY");
  });

  it('row 15: a monitors row whose id is "9x", or without a string url, is an ERROR (rc 1) — never skipped', async () => {
    const badId = await g2({ monitors: [...COMPLIANT_MONITORS(), monRow("9x", "https://example.soleur.ai/")] });
    expect(badId.code).toBe(1);
    expect(badId.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=error");
    expect(badId.out).not.toContain("SOLEUR_HEARTBEAT_RECONCILE_INVENTORY");
    const noUrl = await g2({ monitors: [...COMPLIANT_MONITORS(), monRow("9", 42)] });
    expect(noUrl.code).toBe(1);
    expect(noUrl.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=error");
    const hbBadId = await g2({ heartbeats: [...COMPLIANT_HEARTBEATS(), hbRow("-1", "soleur-x")] });
    expect(hbBadId.code).toBe(1);
    expect(hbBadId.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=error");
  });

  it("row 16: monitors unmanaged-live while the heartbeats arm ERRORs → rc 1 AND both markers printed", async () => {
    const r = await g2({
      heartbeats: () => new Response("forbidden", { status: 403 }),
      monitors: [...COMPLIANT_MONITORS(), monRow("9", "https://example.soleur.ai/")],
    });
    expect(r.code).toBe(1);
    expect(r.out).toContain('SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=auth detail="HTTP 403"');
    expect(r.out).toContain('SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=9 url="https://example.soleur.ai/"');
  });

  it("row 18: vendor text cannot forge routing tokens; bidi/invisible characters never survive; fields are capped", async () => {
    const RLO = String.fromCharCode(0x202e);
    const ZWSP = String.fromCharCode(0x200b);
    const r = await g2({
      monitors: [
        ...COMPLIANT_MONITORS(),
        monRow("9", `https://example.soleur.ai/ id=1 resource=betteruptime_monitor.app"`, {
          name: `x id=1 reason=monitor-config-drift ${RLO}evil${ZWSP}" dup=url`,
        }),
        monRow("10", "https://example.soleur.ai/long", { name: "n".repeat(500) }),
      ],
      heartbeats: [...COMPLIANT_HEARTBEATS(), hbRow("304", `hb id=2 resource=betteruptime_heartbeat.reg ${RLO}"`)],
    });
    expect(r.code).toBe(2);
    const line = r.markers.find((m) => m.includes("id=9"))!;
    expect(preQuoteTokens(line)).toEqual(["surface=monitors", "reason=unmanaged-live", "id=9"]);
    expect(line).toContain(`name="x id=1 reason=monitor-config-drift evil%22 dup=url"`);
    const hbLine = r.markers.find((m) => m.includes("id=304"))!;
    expect(preQuoteTokens(hbLine)).toEqual(["surface=heartbeats", "reason=unmanaged-live", "id=304"]);
    for (const m of r.markers) expect(m).not.toMatch(BIDI_OR_INVISIBLE);
    // Exactly the grammar's own quotes: `%22` encoding keeps every vendor field to one quoted span.
    expect(line.split('"').length - 1).toBe(4);
    const long = r.markers.find((m) => m.includes("id=10"))!;
    expect(/name="(n*)"/.exec(long)?.[1].length).toBe(VENDOR_FIELD_CAP);
  });

  it("row 19: pagination.next pointing at /api/v2/heartbeats on the monitors arm, or repeating its own URL → rc 1", async () => {
    const tokenSentTo: string[] = [];
    const switched = await g2({
      seen: tokenSentTo,
      monitors: () => listPage(COMPLIANT_MONITORS(), `${HB_URL}?page=2`),
    });
    expect(switched.code).toBe(1);
    expect(switched.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=error");
    expect(tokenSentTo.filter((u) => u.startsWith(HB_URL))).toEqual([HB_URL]); // only the heartbeats arm's own read

    const loop = await g2({ monitors: () => listPage(COMPLIANT_MONITORS(), MON_URL) });
    expect(loop.code).toBe(1);
    expect(loop.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=error");

    const port = await g2({ monitors: (u) => (u === MON_URL ? listPage([], `${UPTIME}:8443/api/v2/monitors?page=2`) : listPage([])) });
    expect(port.code).toBe(1);

    let pages = 0;
    const endless = await g2({
      monitors: (u) => {
        pages++;
        const n = Number(new URL(u).searchParams.get("page") ?? "1");
        return listPage([], `${MON_URL}?page=${n + 1}`);
      },
    });
    expect(endless.code).toBe(1);
    expect(pages).toBe(MAX_PAGES);
    expect(endless.out).toContain(`pagination exceeded ${MAX_PAGES} pages`);
  });

  it("the vendor's real pagination.next shape (`?page=N&per_page=M`) is followed", async () => {
    const r = await g2({
      monitors: (u) =>
        u === MON_URL
          ? listPage([COMPLIANT_MONITORS()[0]], `${MON_URL}?page=2&per_page=1`)
          : listPage([COMPLIANT_MONITORS()[1]]),
    });
    expect(r.code).toBe(0);
    expect(r.out).toContain("matched=101,102");
  });
});

describe("Guard 2 (#7884) — harness rows H1-H6", () => {
  it("H1: a no-op reconcileMonitors (DI seam) turns rows 1, 2, 4, 7, 17 RED", async () => {
    const noop: RunDeps = { reconcileMonitors: () => [] };
    for (const h of H1_ROWS) {
      const r = await g2({ ...h.input(), deps: noop });
      expect(() => h.assert(r)).toThrow();
    }
  });

  it("H2 must-PASS: live web-1/web-2 instances against templated declarations over a web_hosts-shaped default", async () => {
    const r = await g2();
    expect(r.code).toBe(0);
    expect(mismatchLines(r)).toEqual([]);
    expect(r.out).not.toContain("${");
    expect(r.out).toContain("SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats checked=5 live=5");
  });

  it("H3 must-PASS: shuffled live arrays carrying unknown extra attributes", async () => {
    const r = await g2({
      monitors: [monRow("102", APP, { extra: { regions: ["eu"], foo: { bar: 1 } } }), monRow("101", HEALTH, { type: "keyword", kw: KW, extra: { status: "up" } })],
      heartbeats: [...COMPLIANT_HEARTBEATS()].reverse().map((h) => ({ ...h, attributes: { ...h.attributes, period: 60, url: "redacted" } })),
    });
    expect(r.code).toBe(0);
    expect(r.out).toContain("matched=101,102");
  });

  it("H4 must-PASS: a live monitor renamed (same URL, type, keyword)", async () => {
    const r = await g2({ monitors: [monRow("101", HEALTH, { type: "keyword", kw: KW, name: "renamed by hand" }), monRow("102", APP)] });
    expect(r.code).toBe(0);
  });

  it('H5 must-PASS: status monitors whose live required_keyword is "" or null against an undeclared keyword', async () => {
    for (const kw of ["", null]) {
      const r = await g2({ monitors: [monRow("101", HEALTH, { type: "keyword", kw: KW }), monRow("102", APP, { kw })] });
      expect(r.code).toBe(0);
    }
  });

  it("H6 must-PASS and non-vacuous: the real apps/web-platform/infra resolves with no UnresolvableDeclaration", () => {
    const REAL = join(import.meta.dir, "..", "..", "..", "apps", "web-platform", "infra");
    const vars = resolveInfraVariables(REAL);
    const heartbeats = discoverHeartbeatsFromInfra(REAL, vars);
    const monitors = discoverMonitorsFromInfra(REAL, vars);
    expect(monitors.map((m) => m.url)).toContain(HEALTH);
    for (const h of heartbeats) expect(h.liveName).not.toContain("${");
    // Every templated (for_each) heartbeat declaration in the real root resolves to ≥1 instance.
    const templated = new Set<string>();
    for (const f of readdirSync(REAL).filter((n) => n.endsWith(".tf"))) {
      const text = stripComments(readFileSync(join(REAL, f), "utf8"));
      for (const m of text.matchAll(/resource\s+"betteruptime_heartbeat"\s+"([a-z0-9_]+)"\s*\{[^}]*?\bfor_each\s*=/g)) templated.add(m[1]);
    }
    expect(templated.size).toBeGreaterThan(0);
    for (const name of templated) {
      expect(heartbeats.filter((h) => h.resourceName === name).length).toBeGreaterThanOrEqual(1);
    }
  });
});

describe("Guard 2 (#7884) — pure reconcile units", () => {
  const dm = (resourceName: string, url: string, o: Partial<DiscoveredMonitor> = {}): DiscoveredMonitor => ({
    resourceName,
    url,
    monitorType: "status",
    requiredKeyword: "",
    paused: false,
    ...o,
  });
  const lm = (id: string, url: string, o: Partial<LiveMonitor> = {}): LiveMonitor => ({
    id,
    url,
    name: "",
    monitorType: "status",
    requiredKeyword: null,
    paused: false,
    ...o,
  });

  it("reconcileMonitors: absent-live, drift and unmanaged carry the discriminated kind", () => {
    expect(reconcileMonitors([dm("a", "https://a/")], [])).toEqual([
      { kind: "monitor", reason: "absent-live", resourceName: "a", url: "https://a/" },
    ]);
    expect(reconcileMonitors([], [lm("7", "https://b/", { name: "b" })])).toEqual([
      { kind: "unmanaged", surface: "monitors", reason: "unmanaged-live", id: "7", url: "https://b/", name: "b", dup: false },
    ]);
  });

  it("findUnmanagedHeartbeats: undeclared name and dup=name", () => {
    const declared = [disc("x", "soleur-x")];
    expect(findUnmanagedHeartbeats(declared, [live("soleur-x", false, "1"), live("soleur-y", false, "2")])).toEqual([
      { kind: "unmanaged", surface: "heartbeats", reason: "unmanaged-live", id: "2", name: "soleur-y", dup: false },
    ]);
    expect(findUnmanagedHeartbeats(declared, [live("soleur-x", false, "1"), live("soleur-x", true, "3")]).map((u) => u.id)).toEqual(["1", "3"]);
  });

  it("reconcileHeartbeats iterates concrete for_each names (no ${each.key} false absent-live)", () => {
    const vars = parseInfraVariables(G2_VARIABLES_TF);
    const discovered = parseHeartbeatBlocks(G2_HEARTBEATS_TF, vars);
    const liveHbs = COMPLIANT_HEARTBEATS().map((h) => live(h.attributes.name, false, String(h.id)));
    expect(reconcileHeartbeats(G2_MANIFEST, discovered, liveHbs)).toEqual([]);
    const missingWeb2 = liveHbs.filter((h) => h.name !== "soleur-web-nic-guard-web-2");
    expect(reconcileHeartbeats(G2_MANIFEST, discovered, missingWeb2)).toEqual([
      { kind: "heartbeat", resourceName: "web_nic_guard", liveName: "soleur-web-nic-guard-web-2", live: "absent", reason: "absent-live" },
    ]);
  });
});

describe("Guard 2 (#7884) — marker-key property over every fixture's output", () => {
  it("each MISMATCH line has exactly one resource= and/or one id= routing token before its first quote (never zero, never two of a kind)", () => {
    const all = G2_OUTPUTS.flat().filter((m) => m.startsWith("SOLEUR_HEARTBEAT_RECONCILE_MISMATCH "));
    expect(all.length).toBeGreaterThan(20); // non-vacuous: the matrix above produced many rows
    for (const line of all) {
      const tokens = preQuoteTokens(line);
      const resources = tokens.filter((t) => t.startsWith("resource="));
      const ids = tokens.filter((t) => t.startsWith("id="));
      expect(resources.length <= 1 && ids.length <= 1 && resources.length + ids.length >= 1).toBe(true);
      for (const t of resources) expect(t).toMatch(/^resource=[a-z_]+\.[a-z0-9_]+$/);
      for (const t of ids) expect(t).toMatch(/^id=[0-9]+$/);
    }
  });
});
