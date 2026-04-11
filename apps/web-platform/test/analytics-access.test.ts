import { describe, test, expect, beforeEach, afterEach } from "vitest";

// Test the admin access check logic directly.
// The actual check is inlined in the page component as:
//   process.env.ADMIN_USER_IDS?.split(',').includes(user.id)
// We test this exact expression here to verify fail-closed behavior.

function isAdmin(userId: string): boolean {
  return process.env.ADMIN_USER_IDS?.split(",").includes(userId) ?? false;
}

describe("admin access check", () => {
  let originalEnv: string | undefined;

  beforeEach(() => {
    originalEnv = process.env.ADMIN_USER_IDS;
  });

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.ADMIN_USER_IDS;
    } else {
      process.env.ADMIN_USER_IDS = originalEnv;
    }
  });

  test("grants access to a user in the admin list", () => {
    process.env.ADMIN_USER_IDS = "user-1,user-2,user-3";
    expect(isAdmin("user-2")).toBe(true);
  });

  test("denies access to a user not in the admin list", () => {
    process.env.ADMIN_USER_IDS = "user-1,user-2";
    expect(isAdmin("user-99")).toBe(false);
  });

  test("denies access when ADMIN_USER_IDS is empty string", () => {
    process.env.ADMIN_USER_IDS = "";
    expect(isAdmin("user-1")).toBe(false);
  });

  test("denies access when ADMIN_USER_IDS is not set (fail closed)", () => {
    delete process.env.ADMIN_USER_IDS;
    expect(isAdmin("user-1")).toBe(false);
  });

  test("handles single admin user", () => {
    process.env.ADMIN_USER_IDS = "only-admin";
    expect(isAdmin("only-admin")).toBe(true);
    expect(isAdmin("someone-else")).toBe(false);
  });

  test("does not match partial UUIDs", () => {
    process.env.ADMIN_USER_IDS = "abc-123-def";
    expect(isAdmin("abc-123")).toBe(false);
    expect(isAdmin("123-def")).toBe(false);
  });
});
