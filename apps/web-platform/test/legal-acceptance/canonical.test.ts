import { describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { KEY_RE, LegalTextError, getLegalText, isCurrent, loadLegalTexts, parseLegalText, textHash } from "@/server/legal-acceptance/canonical";

const FIX = path.join(__dirname, "fixtures/hash-fixture.md");
const EXPECTED = readFileSync(path.join(__dirname, "fixtures/hash-fixture.sha256"), "utf8").trim();

const doc = (front: string, body = "Text.\n") => `---\n${front}\n---\n${body}`;
const code = (fn: () => unknown): string => {
  try {
    fn();
  } catch (e) {
    return e instanceof LegalTextError ? e.code : "other";
  }
  return "none";
};

describe("text hash", () => {
  it("matches the shared fixture in TypeScript and in the shell (sha256sum) — one value, two implementations", () => {
    const raw = readFileSync(FIX);
    expect(raw.toString()).toContain("|");
    expect(raw.toString()).toContain('"');
    expect(raw.at(-1)).toBe(0x0a); // trailing newline is part of the hashed bytes
    expect(textHash(raw)).toBe(EXPECTED);
    const sh = spawnSync("sha256sum", [FIX], { encoding: "utf8" });
    expect(sh.status).toBe(0);
    expect(sh.stdout.split(" ")[0]).toBe(EXPECTED);
  });

  it("is sensitive to a trailing newline, a quote and a pipe (a changed text changes the hash)", () => {
    const base = readFileSync(FIX, "utf8");
    expect(textHash(base.slice(0, -1))).not.toBe(EXPECTED);
    expect(textHash(base.replace('"quote"', "'quote'"))).not.toBe(EXPECTED);
    expect(textHash(base.replace("|", "/"))).not.toBe(EXPECTED);
  });

  it("refuses CR so the hash is the same on every platform", () => {
    expect(code(() => textHash("a\r\nb\n"))).toBe("bad_bytes");
    expect(code(() => textHash(Buffer.from([0x61, 0x0d, 0x0a])))).toBe("bad_bytes");
  });
});

describe("parseLegalText", () => {
  it("parses version, valid_until and body; the hash covers the whole file including front matter", () => {
    const raw = doc("version: 2026-11-01\nvalid_until: 2026-12-31", "Body line.\n");
    const e = parseLegalText("terms-update", raw);
    expect(e).toMatchObject({ key: "terms-update", version: "2026-11-01", validUntil: "2026-12-31", body: "Body line.\n" });
    expect(e.textHash).toBe(textHash(raw));
    expect(parseLegalText("terms-update", doc("version: 2026-11-02", "Body line.\n")).textHash).not.toBe(e.textHash);
  });

  it("rejects a bad key, a missing front matter, a missing or long version and a malformed valid_until", () => {
    expect(code(() => parseLegalText("Bad_Key", doc("version: 1")))).toBe("bad_key");
    expect(code(() => parseLegalText("-lead", doc("version: 1")))).toBe("bad_key");
    expect(code(() => parseLegalText("ok", "no front matter\n"))).toBe("no_front_matter");
    expect(code(() => parseLegalText("ok", doc("other: 1")))).toBe("bad_version");
    expect(code(() => parseLegalText("ok", doc(`version: ${"x".repeat(33)}`)))).toBe("bad_version");
    expect(code(() => parseLegalText("ok", doc("version: 1\nvalid_until: tomorrow")))).toBe("bad_valid_until");
  });

  it("the key pattern is the database CHECK pattern", () => {
    const sql = readFileSync(path.join(__dirname, "../../supabase/migrations/184_legal_acceptance.sql"), "utf8");
    expect(sql).toContain(`'${KEY_RE.source}'`);
  });
});

describe("isCurrent", () => {
  const e = parseLegalText("k", doc("version: 1\nvalid_until: 2026-12-31"));
  it("is current through the end of valid_until (UTC) and expired after it", () => {
    expect(isCurrent(e, new Date("2026-12-31T23:59:59Z"))).toBe(true);
    expect(isCurrent(e, new Date("2027-01-01T00:00:00Z"))).toBe(false);
  });
  it("is always current without valid_until", () => {
    expect(isCurrent(parseLegalText("k", doc("version: 1")), new Date("2099-01-01T00:00:00Z"))).toBe(true);
  });
});

describe("registry loading", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "legal-texts-"));
  writeFileSync(path.join(dir, "terms-update.md"), doc("version: 1"));
  writeFileSync(path.join(dir, "README.md"), "# not a key\n");
  writeFileSync(path.join(dir, "Bad_Name.md"), "ignored\n");
  writeFileSync(path.join(dir, "notes.txt"), "ignored\n");

  it("loads only files whose name is a valid key", () => {
    expect([...loadLegalTexts(dir).keys()]).toEqual(["terms-update"]);
  });
  it("getLegalText throws unknown_key for a key with no file and for an invalid key", () => {
    expect(getLegalText("terms-update", dir).version).toBe("1");
    expect(code(() => getLegalText("absent", dir))).toBe("unknown_key");
    expect(code(() => getLegalText("../etc", dir))).toBe("unknown_key");
  });
  it("the committed registry parses (every committed text is valid)", () => {
    expect(() => loadLegalTexts()).not.toThrow();
  });
});
