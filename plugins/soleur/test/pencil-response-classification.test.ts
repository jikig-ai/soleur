import { describe, test, expect } from "bun:test";
import { classifyResponse } from "../skills/pencil-setup/scripts/pencil-response-classify.mjs";

// T2.2 — The adapter's response classifier must mark auth-failure REPL
// strings as errors. The pre-fix classifier only matched /^Error:/,
// /^\[ERROR\]/, and /^Invalid properties:/ — so pencil's auth-failure
// strings passed through as "success" text, which is how a failed
// mutation produced a 0-byte .pen without surfacing to the caller.

describe("classifyResponse — pre-existing error prefixes (regression guard)", () => {
  test("`Error: foo` is still an error", () => {
    const { isError, text } = classifyResponse("Error: something broke");
    expect(isError).toBe(true);
    expect(text).toBe("Error: something broke");
  });

  test("`[ERROR] foo` is still an error", () => {
    const { isError } = classifyResponse("[ERROR] something broke");
    expect(isError).toBe(true);
  });

  test("`Invalid properties: foo` is still an error", () => {
    const { isError } = classifyResponse("Invalid properties: padding is unexpected");
    expect(isError).toBe(true);
  });

  test("normal output (node id dump) is NOT an error", () => {
    const { isError } = classifyResponse('node0="abc"\nnode1="def"');
    expect(isError).toBe(false);
  });

  test("trims trailing/leading whitespace", () => {
    const { text } = classifyResponse("   hello world   \n");
    expect(text).toBe("hello world");
  });

  test("strips ANSI escape sequences", () => {
    const { text } = classifyResponse("\x1b[31mError: red\x1b[0m");
    expect(text).toBe("Error: red");
    expect(classifyResponse("\x1b[31mError: red\x1b[0m").isError).toBe(true);
  });
});

describe("classifyResponse — auth-failure patterns (new)", () => {
  test("`Please run `pencil login`` is an error", () => {
    const { isError } = classifyResponse("Please run `pencil login` to authenticate");
    expect(isError).toBe(true);
  });

  test("`Invalid API key` is an error (case-insensitive)", () => {
    expect(classifyResponse("Invalid API key").isError).toBe(true);
    expect(classifyResponse("invalid api key: expired").isError).toBe(true);
  });

  test("`Unauthorized` is an error (case-insensitive)", () => {
    expect(classifyResponse("Unauthorized").isError).toBe(true);
    expect(classifyResponse("unauthorized: token expired").isError).toBe(true);
  });

  test("HTTP 401 response body is an error", () => {
    expect(classifyResponse("HTTP 401 Unauthorized").isError).toBe(true);
  });

  test("normal text containing `login` in an innocuous context is NOT misclassified", () => {
    // Pattern must be specific to "pencil login" not bare "login"
    const { isError } = classifyResponse('Created login form node node0="abc"');
    expect(isError).toBe(false);
  });
});
