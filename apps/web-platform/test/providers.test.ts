import { describe, test, expect } from "vitest";
import {
  PROVIDER_CONFIG,
  EXCLUDED_FROM_SERVICES_UI,
  SERVICE_PROVIDERS,
} from "../server/providers";

describe("PROVIDER_CONFIG", () => {
  test("has 14 providers", () => {
    expect(Object.keys(PROVIDER_CONFIG).length).toBe(14);
  });

  test("every provider has envVar, category, and label", () => {
    for (const [provider, config] of Object.entries(PROVIDER_CONFIG)) {
      expect(config.envVar, `${provider} missing envVar`).toBeTruthy();
      expect(config.category, `${provider} missing category`).toBeTruthy();
      expect(config.label, `${provider} missing label`).toBeTruthy();
    }
  });

  test("env var names are unique", () => {
    const envVars = Object.values(PROVIDER_CONFIG).map((c) => c.envVar);
    expect(new Set(envVars).size).toBe(envVars.length);
  });

  test("categories are valid", () => {
    const validCategories = new Set(["llm", "infrastructure", "social"]);
    for (const config of Object.values(PROVIDER_CONFIG)) {
      expect(validCategories.has(config.category)).toBe(true);
    }
  });
});

describe("EXCLUDED_FROM_SERVICES_UI", () => {
  test("excludes bedrock and vertex", () => {
    expect(EXCLUDED_FROM_SERVICES_UI.has("bedrock")).toBe(true);
    expect(EXCLUDED_FROM_SERVICES_UI.has("vertex")).toBe(true);
  });

  test("does not exclude anthropic", () => {
    expect(EXCLUDED_FROM_SERVICES_UI.has("anthropic")).toBe(false);
  });
});

describe("SERVICE_PROVIDERS", () => {
  test("has 12 providers (14 minus bedrock and vertex)", () => {
    expect(SERVICE_PROVIDERS.length).toBe(12);
  });

  test("does not include bedrock or vertex", () => {
    expect(SERVICE_PROVIDERS).not.toContain("bedrock");
    expect(SERVICE_PROVIDERS).not.toContain("vertex");
  });

  test("includes anthropic and all service providers", () => {
    expect(SERVICE_PROVIDERS).toContain("anthropic");
    expect(SERVICE_PROVIDERS).toContain("cloudflare");
    expect(SERVICE_PROVIDERS).toContain("stripe");
    expect(SERVICE_PROVIDERS).toContain("bluesky");
  });
});
