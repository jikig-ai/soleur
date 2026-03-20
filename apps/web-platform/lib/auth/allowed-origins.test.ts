import { describe, it, expect, vi } from "vitest";
import { getAllowedOrigins } from "./allowed-origins";

describe("getAllowedOrigins", () => {
  it("returns production origins in production", () => {
    vi.stubEnv("NODE_ENV", "production");
    const origins = getAllowedOrigins();
    expect(origins.has("https://app.soleur.ai")).toBe(true);
    expect(origins.has("http://localhost:3000")).toBe(false);
  });

  it("returns dev origins in development", () => {
    vi.stubEnv("NODE_ENV", "development");
    const origins = getAllowedOrigins();
    expect(origins.has("https://app.soleur.ai")).toBe(true);
    expect(origins.has("http://localhost:3000")).toBe(true);
  });
});
