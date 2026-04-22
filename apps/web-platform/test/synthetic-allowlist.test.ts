import { describe, test, expect } from "vitest";
import {
  assertSyntheticEmail,
  SYNTHETIC_EMAIL_RE,
  syntheticEmail,
} from "./helpers/synthetic-allowlist";

describe("assertSyntheticEmail", () => {
  test("accepts a well-formed concurrency-test address", () => {
    expect(() =>
      assertSyntheticEmail(
        "concurrency-test+00000000-0000-0000-0000-000000000000@soleur.dev",
      ),
    ).not.toThrow();
  });

  test("rejects a real-looking email", () => {
    expect(() => assertSyntheticEmail("founder@soleur.ai")).toThrow(
      /Refusing destructive op/,
    );
  });

  test("rejects the right prefix on the wrong domain", () => {
    expect(() =>
      assertSyntheticEmail("concurrency-test+abc@gmail.com"),
    ).toThrow();
  });

  test("rejects an almost-match (missing + suffix)", () => {
    expect(() => assertSyntheticEmail("concurrency-test@soleur.dev")).toThrow();
  });

  test("syntheticEmail() returns a value that satisfies the allowlist", () => {
    const email = syntheticEmail();
    expect(SYNTHETIC_EMAIL_RE.test(email)).toBe(true);
    expect(() => assertSyntheticEmail(email)).not.toThrow();
  });
});
