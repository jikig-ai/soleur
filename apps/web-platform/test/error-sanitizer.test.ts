import { describe, test, expect } from "vitest";
import { sanitizeErrorForClient } from "../server/error-sanitizer";
import { KeyInvalidError } from "../lib/types";

describe("sanitizeErrorForClient", () => {
  test("KeyInvalidError preserves user-facing message", () => {
    const err = new KeyInvalidError();
    expect(sanitizeErrorForClient(err)).toBe(
      "No valid API key found. Please set up your key first.",
    );
  });

  test("known operational errors map to safe messages", () => {
    expect(sanitizeErrorForClient(new Error("Workspace not provisioned"))).toBe(
      "Your workspace is not ready yet. Please try again shortly.",
    );
    expect(sanitizeErrorForClient(new Error("No active session"))).toBe(
      "No active session. Please start a new conversation.",
    );
    expect(
      sanitizeErrorForClient(
        new Error("Review gate not found or already resolved"),
      ),
    ).toBe("This review prompt has already been answered.");
    expect(sanitizeErrorForClient(new Error("Conversation not found"))).toBe(
      "Conversation not found. Please start a new session.",
    );
    expect(sanitizeErrorForClient(new Error("Review gate timed out"))).toBe(
      "The review prompt timed out. Please start a new session.",
    );
    expect(
      sanitizeErrorForClient(new Error("Invalid review gate selection")),
    ).toBe("Invalid selection. Please choose one of the offered options.");
    expect(
      sanitizeErrorForClient(new Error("Session aborted: user disconnected")),
    ).toBe("Your session was disconnected. Please reconnect to continue.");
  });

  test("Unknown leader maps to safe message", () => {
    expect(
      sanitizeErrorForClient(new Error("Unknown leader: evil_leader")),
    ).toBe("Invalid domain leader selected.");
  });

  test("unknown Error produces generic message", () => {
    const err = new Error("ECONNREFUSED 127.0.0.1:5432");
    expect(sanitizeErrorForClient(err)).toBe(
      "An unexpected error occurred. Please try again.",
    );
  });

  test("non-Error thrown value produces generic message", () => {
    expect(sanitizeErrorForClient("string error")).toBe(
      "An unexpected error occurred. Please try again.",
    );
    expect(sanitizeErrorForClient(null)).toBe(
      "An unexpected error occurred. Please try again.",
    );
    expect(sanitizeErrorForClient(42)).toBe(
      "An unexpected error occurred. Please try again.",
    );
  });

  test("Supabase internal error does not leak", () => {
    const err = new Error(
      'relation "public.conversations" does not exist',
    );
    expect(sanitizeErrorForClient(err)).not.toContain("relation");
    expect(sanitizeErrorForClient(err)).not.toContain("public.");
    expect(sanitizeErrorForClient(err)).toBe(
      "An unexpected error occurred. Please try again.",
    );
  });

  test("interpolated createConversation error does not leak Supabase details", () => {
    const err = new Error(
      "Failed to create conversation: permission denied for table conversations",
    );
    expect(sanitizeErrorForClient(err)).not.toContain("permission denied");
    expect(sanitizeErrorForClient(err)).not.toContain("table");
    expect(sanitizeErrorForClient(err)).toBe(
      "An unexpected error occurred. Please try again.",
    );
  });

  test("byok configuration error does not leak server config", () => {
    const err = new Error(
      "BYOK_ENCRYPTION_KEY must be a 64-character hex string (32 bytes)",
    );
    expect(sanitizeErrorForClient(err)).not.toContain("BYOK");
    expect(sanitizeErrorForClient(err)).not.toContain("hex");
    expect(sanitizeErrorForClient(err)).toBe(
      "An unexpected error occurred. Please try again.",
    );
  });

  test("crypto decryption error does not leak implementation details", () => {
    const err = new Error(
      "Unsupported state or unable to authenticate data",
    );
    expect(sanitizeErrorForClient(err)).toBe(
      "An unexpected error occurred. Please try again.",
    );
  });

  test("SDK auth error does not leak API details", () => {
    const err = new Error("Invalid API Key");
    expect(sanitizeErrorForClient(err)).toBe(
      "An unexpected error occurred. Please try again.",
    );
  });

  test("SDK resume error returns friendly message", () => {
    const err = new Error(
      "Claude Code returned an error result: No conversation found with session ID: 544e6cdb-461b-40f6-bd78-498893569a6e",
    );
    expect(sanitizeErrorForClient(err)).toBe(
      "Session resume failed. Falling back to conversation history.",
    );
  });

  test("SDK resume error does not leak session UUID", () => {
    const uuid = "544e6cdb-461b-40f6-bd78-498893569a6e";
    const err = new Error(
      `Claude Code returned an error result: No conversation found with session ID: ${uuid}`,
    );
    const result = sanitizeErrorForClient(err);
    expect(result).not.toContain(uuid);
    expect(result).not.toContain("session ID");
  });
});
