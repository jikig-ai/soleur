// RED-first (cq-write-failing-tests-before) unit tests for the nightly source-vs-live
// Better Stack heartbeat reconcile (#6549 item 2).
//
// The static `heartbeat-reprovision-parity.test.ts` proves a feeder exists in SOURCE; it cannot
// see a heartbeat that is `paused` or absent in LIVE Better Stack (`ignore_changes = [paused]`
// makes the .tf `paused` value only a lower bound). These tests cover the pure reconcile logic
// that closes that gap — synthetic fixtures only (cq-test-fixtures-synthesized-only), no network.

import { describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import type { ManifestEntry } from "../lib/heartbeat-manifest";
import {
  type DiscoveredHeartbeat,
  type LiveHeartbeat,
  parseHeartbeatBlocks,
  parseLogsAlertBlocks,
  reconcileHeartbeats,
  reconcileLogsAlerts,
  stripComments,
} from "../lib/heartbeat-live-reconcile";
import {
  discoverHeartbeatsFromInfra,
  fetchLiveHeartbeats,
  runReconcile,
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

const live = (name: string, paused: boolean): LiveHeartbeat => ({ name, paused });

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

describe("reconcileHeartbeats — item-1 carve-out (count-gated webhook rows never flagged absent)", () => {
  it("does NOT flag a count-gated heartbeat that is absent live", () => {
    const violations = reconcileHeartbeats(
      [unfed("github_webhook_sig_failures")],
      [disc("github_webhook_sig_failures", "soleur-github-webhook-sig-failures-prd", { countGated: true })],
      [], // intentionally absent under the free tier (count = 0)
    );
    expect(violations).toEqual([]);
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
      disc("github_webhook_sig_failures", "soleur-github-webhook-sig-failures-prd", { countGated: true }),
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
    const blocks = parseHeartbeatBlocks(TF);
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
        `resource "betteruptime_heartbeat" "two" {\n  count = 1\n  name = "soleur-two"\n}`,
      );
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
  const okFetch =
    (live: LiveHeartbeat[]) =>
    async () =>
      new Response(JSON.stringify({ data: live.map((h) => ({ attributes: h })), pagination: { next: null } }), {
        status: 200,
      });

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
      expect(result.markers.join("\n")).toContain(
        "SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-reg live=paused reason=fed-but-paused",
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
        data: [{ attributes: { name: "soleur-a", paused: false } }],
        pagination: { next: "https://uptime.betterstack.com/api/v2/heartbeats?page=2" },
      },
      "https://uptime.betterstack.com/api/v2/heartbeats?page=2": {
        data: [{ attributes: { name: "soleur-b", paused: true } }],
        pagination: { next: null },
      },
    };
    const fetchImpl = async (url: string) =>
      new Response(JSON.stringify(pages[url]), { status: 200 });

    const result = await fetchLiveHeartbeats({ token: "t", fetchImpl, sleepImpl: noSleep });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.live).toEqual([
        { name: "soleur-a", paused: false },
        { name: "soleur-b", paused: true },
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
            data: [{ attributes: { name: "soleur-a", paused: false } }],
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
  // Dispatches on URL so the heartbeat and alert reads are distinguishable — and so a read of
  // any OTHER host is refused loudly rather than answered.
  const routed =
    (alerts: unknown[], onOther?: (u: string) => void) =>
    async (url: string) => {
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return page([{ attributes: live("soleur-reg", false) }]);
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
      expect(out).toContain(
        'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-monitor-send-failed-prd live=logs_alert reason=logs-alert-paused detail="too many failures"',
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
      expect(seen).toEqual(["https://uptime.betterstack.com/api/v2/heartbeats"]);
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
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return page([{ attributes: live("soleur-reg", true) }]);
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
      expect(line).toMatch(/detail="too many failures "$/);
      expect(line).not.toMatch(/[\u2028\x7f`]/);
    });
  });

  it("a heartbeat MISMATCH and an alert MISMATCH combine to one rc=2 run carrying both markers", async () => {
    const pausedHb = async (url: string) => {
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return page([{ attributes: live("soleur-reg", true) }]);
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
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return page([{ attributes: live("soleur-reg", false) }]);
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
      if (url === "https://uptime.betterstack.com/api/v2/heartbeats") return page([{ attributes: live("soleur-reg", false) }]);
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
