/**
 * Tests for readAppId() — canonicalizes + validates the GitHub App ID before it
 * becomes the JWT `iss` claim.
 *
 * Root cause (Sentry 00bdfdf1…): @octokit/app and universal-github-app-jwt accept
 * `appId: number | string` and never validate it, so a whitespace-laden
 * (`"3261325\n"` — the exact prod-Doppler shape that fired this issue) or
 * client-id-shaped (`"Iv23…"`) GITHUB_APP_ID is signed verbatim into `iss`, and
 * GitHub rejects the JWT with the opaque "A JSON web token could not be decoded".
 * readAppId is the only pre-GitHub catch point: it trims recoverable surrounding
 * whitespace and throws a loud, self-explaining error for an unrecoverable
 * non-numeric value.
 *
 * PURE string→string tests: no network, no @octokit/app mock, no keypair needed.
 */
import { describe, test, expect } from "vitest";
import { readAppId } from "@/server/github/app-private-key";

describe("readAppId", () => {
  test("AC: a clean numeric App ID passes through unchanged", () => {
    expect(typeof readAppId).toBe("function");
    expect(readAppId("3261325")).toBe("3261325");
  });

  test("AC: trailing newline is stripped (the exact prod-Doppler failure shape)", () => {
    // GITHUB_APP_ID in Doppler prd was "3261325\n" — len 8, trims to 7.
    expect(readAppId("3261325\n")).toBe("3261325");
  });

  test("AC: surrounding whitespace (spaces, tabs, CR) is stripped", () => {
    expect(readAppId("  3261325  ")).toBe("3261325");
    expect(readAppId("\t3261325\r\n")).toBe("3261325");
  });

  test("AC: a client_id-shaped value throws a specific, self-explaining error", () => {
    // The classic confusion: pasting the App's client_id ("Iv23…") instead of
    // the numeric App ID. Must NOT be silently signed into `iss`.
    expect(() => readAppId("Iv23liABCDEFghij")).toThrow(/client_id/i);
  });

  test("AC: a non-numeric value throws (does not reach new App())", () => {
    expect(() => readAppId("not-an-id")).toThrow(/GITHUB_APP_ID/);
  });

  test("AC: empty / whitespace-only value throws (no vacuous-green)", () => {
    // A missing/renamed export would make the call throw TypeError and satisfy a
    // bare toThrow() without exercising the guard — assert it IS a function first.
    expect(typeof readAppId).toBe("function");
    expect(() => readAppId("")).toThrow(/GITHUB_APP_ID/);
    expect(() => readAppId("   \n ")).toThrow(/GITHUB_APP_ID/);
  });

  test("AC: an internal space (not just surrounding) is rejected", () => {
    // "326 1325" trims surrounding ws but the interior space makes it non-numeric.
    expect(() => readAppId(" 326 1325 ")).toThrow(/GITHUB_APP_ID/);
  });

  test("AC: a leading-zero numeric value passes through verbatim (pins the contract)", () => {
    // `^[0-9]+$` accepts leading zeros; GitHub validates the real App↔key binding
    // downstream. Pin the pass-through so a future tightening is a deliberate choice.
    expect(readAppId("007")).toBe("007");
  });

  test("AC: human-looks-numeric near-misses (negative, decimal) are rejected", () => {
    // The realistic "looks numeric but isn't an App ID" shapes.
    expect(() => readAppId("-1")).toThrow(/GITHUB_APP_ID/);
    expect(() => readAppId("3.5")).toThrow(/GITHUB_APP_ID/);
    expect(() => readAppId("3261325.0")).toThrow(/GITHUB_APP_ID/);
  });
});
