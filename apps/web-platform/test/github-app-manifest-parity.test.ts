import { describe, test, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

// Symbol-parity test for the committed GitHub App manifest.
//
// Asserts:
//   1. apps/web-platform/infra/github-app-manifest.json exists and parses.
//   2. hook_attributes.url template references /api/webhooks/github.
//   3. callback_urls is an array with >= 3 entries (per
//      knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md).
//   4. default_permissions.administration === "write".
//   5. public === false.
//   6. setup_on_update === true.
//   7. redirect_url ends with /internal/github-app-init.
//   8. Every doppler_secret resource name declared in
//      apps/web-platform/infra/github-app.tf (GITHUB_APP_*) has documented
//      coverage — the manifest cannot guarantee CLIENT_SECRET / WEBHOOK_SECRET
//      values (those land via operator paste / random_id), but the secret
//      _names_ must be enumerable so the runbook stays in sync.
//
// Ref #4115.

const REPO_ROOT = path.resolve(__dirname, "../../..");
const MANIFEST_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/github-app-manifest.json",
);
const TF_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/github-app.tf",
);

const EXPECTED_TF_SECRETS = [
  "GITHUB_APP_ID",
  "GITHUB_APP_PRIVATE_KEY",
  "GITHUB_APP_CLIENT_ID",
  "GITHUB_APP_CLIENT_SECRET",
  "GITHUB_APP_WEBHOOK_SECRET",
];

interface Manifest {
  name: string;
  url: string;
  description: string;
  public: boolean;
  redirect_url: string;
  hook_attributes: { url: string; active?: boolean };
  callback_urls: string[];
  setup_url: string;
  setup_on_update: boolean;
  default_permissions: Record<string, string>;
  default_events: string[];
}

describe("github-app-manifest.json symbol parity", () => {
  test("manifest file exists and parses as JSON", () => {
    expect(existsSync(MANIFEST_PATH), `missing ${MANIFEST_PATH}`).toBe(true);
    const raw = readFileSync(MANIFEST_PATH, "utf-8");
    expect(() => JSON.parse(raw)).not.toThrow();
  });

  test("hook_attributes.url template references /api/webhooks/github", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.hook_attributes?.url).toContain("/api/webhooks/github");
  });

  test("callback_urls is an array with >= 3 entries", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(Array.isArray(m.callback_urls)).toBe(true);
    expect(m.callback_urls.length).toBeGreaterThanOrEqual(3);
  });

  test("default_permissions.administration === 'write'", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.default_permissions?.administration).toBe("write");
  });

  test("public === false", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.public).toBe(false);
  });

  test("setup_on_update === true", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.setup_on_update).toBe(true);
  });

  test("redirect_url ends with /internal/github-app-init", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.redirect_url.endsWith("/internal/github-app-init")).toBe(true);
  });

  test("Terraform secret names are all declared in github-app.tf", () => {
    const tf = readFileSync(TF_PATH, "utf-8");
    for (const name of EXPECTED_TF_SECRETS) {
      // Each name appears as `name       = "<NAME>"` in github-app.tf.
      const re = new RegExp(`name\\s*=\\s*"${name}"`);
      expect(
        re.test(tf),
        `expected ${name} to be declared in github-app.tf`,
      ).toBe(true);
    }
  });

  test("manifest provides setup_url + hook_attributes.url + redirect_url templates", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(typeof m.setup_url).toBe("string");
    expect(m.setup_url.length).toBeGreaterThan(0);
    expect(typeof m.hook_attributes?.url).toBe("string");
    expect(typeof m.redirect_url).toBe("string");
  });
});
