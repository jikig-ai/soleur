import { describe, it, expect } from "vitest";
import { describeDbError } from "@/server/dsar-db-error";

describe("describeDbError", () => {
  it("returns the bare message when nothing else is known (existing assertions keep matching)", () => {
    expect(describeDbError({ message: "boom" })).toBe("boom");
  });

  it("appends the HTTP status for a non-JSON gateway body, the case that carried only a message", () => {
    // postgrest-js sets `error = { message: body }` for a non-JSON body and
    // leaves the HTTP status on the result object, so the status is the only
    // diagnostic beyond the body text.
    expect(
      describeDbError({ message: "Project not specified" }, 200, "OK"),
    ).toBe("Project not specified [status=200 OK]");
  });

  it("includes code and hint when PostgREST supplies them", () => {
    expect(
      describeDbError(
        { message: "relation missing", code: "42P01", hint: "check the schema cache" },
        404,
        "Not Found",
      ),
    ).toBe("relation missing [status=404 Not Found code=42P01 hint=check the schema cache]");
  });

  it("never includes `details`, which can echo row values on a regulated surface", () => {
    const out = describeDbError(
      {
        message: "m",
        details: "Key (email)=(someone@example.com) already exists.",
      } as never,
      409,
    );
    expect(out).not.toContain("someone@example.com");
    expect(out).toBe("m [status=409]");
  });

  it("omits an unknown or zero status (a fetch failure reports status 0)", () => {
    expect(describeDbError({ message: "m" }, 0)).toBe("m");
    expect(describeDbError({ message: "m" }, undefined)).toBe("m");
  });

  it("collapses whitespace and strips control and separator characters from a hostile body", () => {
    const LS = String.fromCharCode(0x2028);
    const body = ["line1", "line2", "\u001b[2Jx", `${LS}y`].join("\n");
    const out = describeDbError({ message: body }, 502);
    expect(out).not.toMatch(/[\r\n]/);
    expect(out).not.toContain("\u001b");
    expect(out).not.toContain(LS);
    expect(out.startsWith("line1 line2 ")).toBe(true);
  });

  it("truncates an oversized body (an HTML error page) to a bounded length", () => {
    const out = describeDbError({ message: "x".repeat(5000) }, 503);
    expect(out.length).toBeLessThan(400);
    expect(out).toContain("...");
    expect(out.endsWith("[status=503]")).toBe(true);
  });

  it("falls back to a stable placeholder when there is no message at all", () => {
    expect(describeDbError({}, 500)).toBe("(no message) [status=500]");
    expect(describeDbError({ message: "   " })).toBe("(no message)");
  });
});
