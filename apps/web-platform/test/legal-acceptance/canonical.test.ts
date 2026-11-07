import { describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { KEY_RE, LegalTextError, TEXT_HASH_RE, getLegalText, isCurrent, loadLegalTexts, parseLegalText, textHash } from "@/server/legal-acceptance/canonical";

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

  it("a multibyte fixture hashes the same through the registry loader and sha256sum (bytes, not a re-encoded string)", () => {
    const fix = path.join(__dirname, "fixtures/hash-fixture-multibyte.md");
    const expected = readFileSync(path.join(__dirname, "fixtures/hash-fixture-multibyte.sha256"), "utf8").trim();
    const raw = readFileSync(fix, "utf8");
    expect(raw).toContain("\u2014"); // em dash
    expect(raw).toContain("\u201c"); // curly quote
    const dir = mkdtempSync(path.join(tmpdir(), "legal-multibyte-"));
    writeFileSync(path.join(dir, "multibyte.md"), readFileSync(fix));
    expect(loadLegalTexts(dir).get("multibyte")?.textHash).toBe(expected);
    expect(getLegalText("multibyte", dir).textHash).toBe(expected);
    const sh = spawnSync("sha256sum", [fix], { encoding: "utf8" });
    expect(sh.stdout.split(" ")[0]).toBe(expected);
    // The string-encoding branch agrees too (a latin1 re-encoding would not).
    expect(textHash(raw)).toBe(expected);
  });

  it("refuses a file that is not valid UTF-8 instead of hashing a different value than sha256sum would", () => {
    const bad = Buffer.concat([Buffer.from("---\nversion: 1\n---\nbad "), Buffer.from([0xff, 0xe9]), Buffer.from("\n")]);
    expect(code(() => parseLegalText("bad-bytes", bad))).toBe("bad_bytes");
  });

  it("is sensitive to a trailing newline, a quote and a pipe (a changed text changes the hash)", () => {
    const base = readFileSync(FIX, "utf8");
    expect(textHash(base.slice(0, -1))).not.toBe(EXPECTED);
    expect(textHash(base.replace('"quote"', "'quote'"))).not.toBe(EXPECTED);
    expect(textHash(base.split("|").join("/"))).not.toBe(EXPECTED);
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

  it("every key and text-hash pattern in the migration is the TypeScript pattern (a count, not an any-match)", () => {
    const sql = readFileSync(path.join(__dirname, "../../supabase/migrations/184_legal_acceptance.sql"), "utf8");
    // Full-line comments are removed first: a comment that merely quotes the pattern must not keep the count right after a validation is deleted.
    const code = sql.replace(/^\s*--.*$/gm, "");
    const count = (needle: string) => code.split(needle).length - 1;
    // legal_acceptance.key, legal_reauth_event.key, issue, claim, mark, record
    expect(count(`'${KEY_RE.source}'`)).toBe(6);
    // the same six, plus the row_hash CHECK on legal_acceptance
    expect(count(`'${TEXT_HASH_RE.source}'`)).toBe(7);
    // And the version bound is the TypeScript bound.
    expect(readFileSync(path.join(__dirname, "../../server/legal-acceptance/canonical.ts"), "utf8")).toContain("version.length > 32");
    expect(sql).toContain("char_length(version) BETWEEN 1 AND 32");
    expect(sql).toContain("char_length(p_version) NOT BETWEEN 1 AND 32"); // issue_legal_reauth binds the version
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
  it("getLegalText reads only its own file, so one malformed sibling cannot take every key down", () => {
    const d = mkdtempSync(path.join(tmpdir(), "legal-sibling-"));
    writeFileSync(path.join(d, "good-key.md"), doc("version: 1"));
    writeFileSync(path.join(d, "broken-key.md"), "no front matter at all\n");
    expect(getLegalText("good-key", d).version).toBe("1");
    expect(() => loadLegalTexts(d)).toThrow(); // the full load still refuses the broken file
    expect(code(() => getLegalText("broken-key", d))).toBe("no_front_matter");
  });

  it("getLegalText throws unknown_key for a key with no file and for an invalid key", () => {
    expect(getLegalText("terms-update", dir).version).toBe("1");
    expect(code(() => getLegalText("absent", dir))).toBe("unknown_key");
    expect(code(() => getLegalText("../etc", dir))).toBe("unknown_key");
  });
  it("getLegalText throws a distinct read_failed for a read error that is not a missing file (EISDIR, ENOTDIR), never unknown_key", () => {
    const d = mkdtempSync(path.join(tmpdir(), "legal-readfail-"));
    mkdirSync(path.join(d, "dir-as-file.md")); // reading a directory: EISDIR
    expect(code(() => getLegalText("dir-as-file", d))).toBe("read_failed");
    const notADir = path.join(d, "plain-file");
    writeFileSync(notADir, "x");
    expect(code(() => getLegalText("any-key", notADir))).toBe("read_failed"); // texts dir is a file: ENOTDIR
    // ENOENT (the file or the whole directory is absent) stays unknown_key.
    expect(code(() => getLegalText("absent", d))).toBe("unknown_key");
    expect(code(() => getLegalText("absent", path.join(d, "no-such-dir")))).toBe("unknown_key");
  });
  it("the committed registry loads without error (it is EMPTY until counsel signs off a real text, so this proves the loader and the directory, not any text)", () => {
    expect(() => loadLegalTexts()).not.toThrow();
  });
});
