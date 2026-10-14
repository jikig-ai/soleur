import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// The MU1 AC-2 fixture App ("Soleur CI Fixture") is created through GitHub's manifest flow
// (bootstrap.sh create-app). Two properties of its manifest were each learned the hard way and
// are pinned here, because nothing else reads this file until a founder is mid-provisioning:
//   1. GitHub rejects a manifest with no redirect_url ("redirect_url wasn't supplied", #10058).
//      It is NOT the web-platform /internal/github-app-init handler the sibling manifests use:
//      the redirect carries a one-time code that converts to the App's private key, so this
//      private CI fixture points at GitHub's own settings page instead of the production app.
//   2. Its key lives in the dev_scheduled Doppler config, so the manifest's own description
//      promises it is harmless on leak: contents:read + metadata:read, no events, not public.
const MANIFEST = JSON.parse(
  readFileSync(
    path.resolve(__dirname, "../infra/github-ci-fixture-app-manifest.json"),
    "utf8",
  ),
) as Record<string, unknown>;

describe("github-ci-fixture-app-manifest.json", () => {
  test("carries a redirect_url on github.com, never the production app", () => {
    const url = new URL(String(MANIFEST.redirect_url));
    expect(url.protocol).toBe("https:");
    expect(url.hostname).toBe("github.com");
  });

  test("permissions are exactly contents:read + metadata:read", () => {
    expect(MANIFEST.default_permissions).toEqual({
      contents: "read",
      metadata: "read",
    });
  });

  test("subscribes to no events, no webhook, and is not public", () => {
    expect(MANIFEST.default_events).toEqual([]);
    expect(MANIFEST.hook_attributes).toBeUndefined();
    expect(MANIFEST.public).toBe(false);
  });
});
