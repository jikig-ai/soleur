import { describe, test, expect } from "vitest";
import { containsSensitiveEnvAccess } from "../server/bash-sandbox";

describe("containsSensitiveEnvAccess", () => {
  test("blocks `env` command", () => {
    expect(containsSensitiveEnvAccess("env")).toBe(true);
  });

  test("blocks `printenv` command", () => {
    expect(containsSensitiveEnvAccess("printenv")).toBe(true);
  });

  test("blocks `set` without flags (lists all vars)", () => {
    expect(containsSensitiveEnvAccess("set")).toBe(true);
  });

  test("blocks echo $SUPABASE_SERVICE_ROLE_KEY", () => {
    expect(containsSensitiveEnvAccess("echo $SUPABASE_SERVICE_ROLE_KEY")).toBe(
      true,
    );
  });

  test("blocks echo ${ANTHROPIC_API_KEY}", () => {
    expect(containsSensitiveEnvAccess("echo ${ANTHROPIC_API_KEY}")).toBe(true);
  });

  test("blocks cat /proc/self/environ", () => {
    expect(containsSensitiveEnvAccess("cat /proc/self/environ")).toBe(true);
  });

  test("blocks echo $BYOK_ENCRYPTION_KEY", () => {
    expect(containsSensitiveEnvAccess("echo $BYOK_ENCRYPTION_KEY")).toBe(true);
  });

  test("blocks echo ${BYOK_ENCRYPTION_KEY}", () => {
    expect(containsSensitiveEnvAccess("echo ${BYOK_ENCRYPTION_KEY}")).toBe(
      true,
    );
  });

  test("allows ls -la", () => {
    expect(containsSensitiveEnvAccess("ls -la")).toBe(false);
  });

  test("allows git status", () => {
    expect(containsSensitiveEnvAccess("git status")).toBe(false);
  });

  test("allows set -euo pipefail (set with flags is not env listing)", () => {
    expect(containsSensitiveEnvAccess("set -euo pipefail")).toBe(false);
  });

  test("allows set -e", () => {
    expect(containsSensitiveEnvAccess("set -e")).toBe(false);
  });

  test("allows echo hello", () => {
    expect(containsSensitiveEnvAccess("echo hello")).toBe(false);
  });

  test("allows npm install", () => {
    expect(containsSensitiveEnvAccess("npm install")).toBe(false);
  });
});
