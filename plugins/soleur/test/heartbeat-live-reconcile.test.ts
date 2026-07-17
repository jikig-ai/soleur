// RED-first (cq-write-failing-tests-before) unit tests for the nightly source-vs-live
// Better Stack heartbeat reconcile (#6549 item 2).
//
// The static `heartbeat-reprovision-parity.test.ts` proves a feeder exists in SOURCE; it cannot
// see a heartbeat that is `paused` or absent in LIVE Better Stack (`ignore_changes = [paused]`
// makes the .tf `paused` value only a lower bound). These tests cover the pure reconcile logic
// that closes that gap — synthetic fixtures only (cq-test-fixtures-synthesized-only), no network.

import { describe, expect, it } from "vitest";

import type { ManifestEntry } from "../lib/heartbeat-manifest";
import {
  type DiscoveredHeartbeat,
  type LiveHeartbeat,
  parseHeartbeatBlocks,
  reconcileHeartbeats,
} from "../lib/heartbeat-live-reconcile";
import { fetchLiveHeartbeats } from "../scripts/reconcile-live-heartbeats";

// --- Synthetic manifest rows (only .name + .feeder.kind are read by reconcileHeartbeats) ---
type ManifestRow = Pick<ManifestEntry, "name" | "feeder">;

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
    const fetchImpl = async (url: string, init?: RequestInit) => {
      seen.push(url);
      // Assert the Bearer token is only ever attached to the trusted host.
      const auth = new Headers(init?.headers).get("Authorization");
      // Parse the host exactly (never a substring check) — the token may only reach the trusted host.
      if (new URL(url).hostname !== "uptime.betterstack.com") {
        expect(auth).toBeNull();
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
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("error");
    expect(seen).not.toContain("https://evil.example.com/api/v2/heartbeats");
  });

  it("treats a malformed 200 body (no data array) as an error, not a silent empty", async () => {
    const fetchImpl = async () => new Response(JSON.stringify({ nope: true }), { status: 200 });
    const result = await fetchLiveHeartbeats({ token: "t", fetchImpl, sleepImpl: noSleep });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.kind).toBe("error");
  });
});
