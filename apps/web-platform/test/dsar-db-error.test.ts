import { describe, it, expect } from "vitest";
import { describeDbError } from "@/server/dsar-db-error";

// Special characters are built with fromCharCode: an escape like U+2028 written
// in a source file can be turned into the raw character by editing tools, which
// then breaks the file as a string literal.
const ch = (n: number) => String.fromCharCode(n);
const LS = ch(0x2028);
const PS = ch(0x2029);
const ESC = ch(0x1b);
const RLO = ch(0x202e); // right-to-left override (format char)
const ZWSP = ch(0x200b); // zero-width space (format char)
const C1 = ch(0x85); // C1 control (NEL)

describe("describeDbError", () => {
  it("returns the bare message when nothing else is known (existing assertions keep matching)", () => {
    expect(describeDbError({ message: "boom" })).toBe("boom");
  });

  it("appends the HTTP status for a message-only error, the case that carried nothing else", () => {
    // postgrest-js sets `error = { message: body }` for a non-JSON body and
    // leaves the HTTP status on the result object, so the status is the only
    // diagnostic beyond the body text.
    expect(
      describeDbError({ message: "Project not specified" }, 502, "Bad Gateway"),
    ).toBe("Project not specified [status=502 Bad Gateway]");
  });

  it.each([
    {
      name: "status without text",
      error: { message: "m" },
      status: 409,
      statusText: undefined,
      want: "m [status=409]",
    },
    {
      name: "code only",
      error: { message: "m", code: "42P01" },
      status: undefined,
      statusText: undefined,
      want: "m [code=42P01]",
    },
    {
      name: "PostgREST code, longer than a SQLSTATE",
      error: { message: "m", code: "PGRST116" },
      status: 406,
      statusText: "Not Acceptable",
      want: "m [status=406 Not Acceptable code=PGRST116]",
    },
    {
      name: "status 0 (a fetch failure) is omitted",
      error: { message: "m" },
      status: 0,
      statusText: "",
      want: "m",
    },
    {
      name: "negative status is omitted",
      error: { message: "m" },
      status: -1,
      statusText: "x",
      want: "m",
    },
    {
      name: "status outside 100-599 is omitted",
      error: { message: "m" },
      status: 1e21,
      statusText: "x",
      want: "m",
    },
    {
      name: "fractional status is omitted",
      error: { message: "m" },
      status: 1.5,
      statusText: "x",
      want: "m",
    },
    {
      name: "NaN status is omitted",
      error: { message: "m" },
      status: Number.NaN,
      statusText: "x",
      want: "m",
    },
    {
      name: "no message at all",
      error: {},
      status: 500,
      statusText: undefined,
      want: "(no message) [status=500]",
    },
    {
      name: "whitespace-only message",
      error: { message: "   " },
      status: undefined,
      statusText: undefined,
      want: "(no message)",
    },
  ])("$name", ({ error, status, statusText, want }) => {
    expect(describeDbError(error, status, statusText)).toBe(want);
  });

  it("never includes `details` or `hint`, which PostgREST and Postgres can fill with row values", () => {
    const out = describeDbError(
      {
        message: "m",
        details: "Key (email)=(someone@example.com) already exists.",
        hint: "Key (email)=(other@example.com) conflicts.",
      } as never,
      409,
    );
    expect(out).toBe("m [status=409]");
  });

  it("accepts a 5-character SQLSTATE and a PGRST code, and nothing at the length boundaries around them", () => {
    expect(describeDbError({ message: "m", code: "23505" })).toBe("m [code=23505]");
    expect(describeDbError({ message: "m", code: "PGRST116" })).toBe("m [code=PGRST116]");
    expect(describeDbError({ message: "m", code: "2350" })).toBe("m");
    expect(describeDbError({ message: "m", code: "235055" })).toBe("m");
  });

  it("drops a `code` that does not have the shape of a SQLSTATE or PostgREST code", () => {
    for (const code of [
      "has space",
      "a".repeat(17),
      "x]\ny=1",
      "name@example.com",
      "hello",
      "pgrst116",
      "",
    ]) {
      expect(describeDbError({ message: "m", code })).toBe("m");
    }
  });

  it("neutralises hostile statusText the same way as the message", () => {
    const out = describeDbError(
      { message: "m" },
      502,
      `Bad${ESC}[2J${LS}Gateway${RLO}${ZWSP}`,
    );
    expect(out).toBe("m [status=502 Bad [2J Gateway]");
  });

  it("collapses whitespace and strips control, separator, format and C1 characters", () => {
    const body = ["line1", "line2", `${ESC}[2Jx`, `${LS}y${PS}z`, `a${RLO}b${ZWSP}c${C1}d`].join("\n");
    const out = describeDbError({ message: body });
    expect(out).toBe("line1 line2 [2Jx y z a b c d");
    // Spot-check against the raw character classes, independent of the literal above.
    expect(out).not.toMatch(/[\r\n]/);
    expect(out).not.toContain(ESC);
    expect(out).not.toContain(LS);
    expect(out).not.toContain(PS);
    expect(out).not.toContain(RLO);
    expect(out).not.toContain(ZWSP);
    expect(out).not.toContain(C1);
  });

  it("truncates a message at exactly 300 characters and a status text at 120", () => {
    expect(describeDbError({ message: "x".repeat(300) })).toBe("x".repeat(300));
    expect(describeDbError({ message: "x".repeat(301) })).toBe(
      `${"x".repeat(300)}...`,
    );
    expect(describeDbError({ message: "m" }, 502, "t".repeat(120))).toBe(
      `m [status=502 ${"t".repeat(120)}]`,
    );
    expect(describeDbError({ message: "m" }, 502, "t".repeat(121))).toBe(
      `m [status=502 ${"t".repeat(120)}...]`,
    );
  });

  it("truncates by code point, so an astral character is never cut in half", () => {
    const astral = ch(0xd83d) + ch(0xde00); // U+1F600
    const out = describeDbError({ message: astral.repeat(301) });
    expect(out).toBe(`${astral.repeat(300)}...`);
  });

  it("leaves no lone surrogate when the input bound lands inside a surrogate pair", () => {
    const astral = ch(0xd83d) + ch(0xde00);
    // 1199 units, then a pair that straddles the 1200-unit bound.
    const out = describeDbError({ message: `${"x".repeat(1199)}${astral}tail` });
    expect(out).toBe(`${"x".repeat(300)}...`);
    expect(out).not.toMatch(/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/);
  });

  it("replaces a lone surrogate with a space", () => {
    expect(describeDbError({ message: `a${ch(0xd800)}b` })).toBe("a b");
  });

  it("drops a trailing partial email address left by a cut, which the sinks' redaction could not match", () => {
    const out = describeDbError({ message: `${"x ".repeat(149)}jane.doe@example.com` });
    expect(out).not.toContain("@");
    expect(out.endsWith("...")).toBe(true);
    // A complete address inside the cap is left whole (the sinks redact it).
    expect(describeDbError({ message: "who jane.doe@example.com" })).toBe(
      "who jane.doe@example.com",
    );
  });

  it("applies the input bound: real text after more than 1200 characters of whitespace is cut away", () => {
    // Without the prefix cut this would read "tail".
    expect(describeDbError({ message: `${" ".repeat(2000)}tail` }, 500)).toBe(
      "(no message) [status=500]",
    );
  });

  it("bounds the work on a multi-megabyte word-and-space body", () => {
    // ~434 ms unbounded on the review host, ~0.1 ms bounded.
    const huge = "a ".repeat(1_500_000);
    const t0 = performance.now();
    const out = describeDbError({ message: huge }, 502);
    const ms = performance.now() - t0;
    expect(out.length).toBeLessThan(400);
    expect(out.endsWith("[status=502]")).toBe(true);
    expect(ms).toBeLessThan(100);
  });

  it("ignores non-string fields instead of throwing", () => {
    expect(
      describeDbError({ message: 42 as never, code: 7 as never }, 500, {} as never),
    ).toBe("(no message) [status=500]");
  });
});
