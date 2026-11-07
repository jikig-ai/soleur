/**
 * #12197 / #12011 (CTO ruling 2, 2026-11-07): the published `{version: sha256}` pin and the exact key set of the legal-text registry.
 *
 * `PUBLISHED` is an APPEND-ONLY history. After a text's first merge to main, a changed byte comes with a new `version` and a
 * new appended row; an existing row's sha is never edited (review rule in texts/README.md). The pin proves consistency, not
 * integrity: the text and its pin can be edited in one diff. What makes an in-place edit visible is the append-only shape
 * in review, and the database `UNIQUE (founder_id, key, text_hash)` keeps the hash of every decision actually recorded.
 *
 * Three sources must name the same keys (three-way set equality): the files the loader serves, `PUBLISHED`, and the card
 * kind declared in `LEGAL_TEXT_KIND`. The hash is checked twice, once through the loader and once by an independent read
 * of the file bytes, so a wrong loader and a wrong pin cannot agree by accident.
 */
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { TEXTS_DIR, loadLegalTexts } from "@/server/legal-acceptance/canonical";
import { LEGAL_TEXT_KIND } from "@/lib/legal-acceptance-copy";

interface Pin {
  kind: string;
  /** version -> sha256 of the file's raw bytes. Append-only. */
  versions: Record<string, string>;
}

const PUBLISHED: Record<string, Pin> = {
  "founder-acceptance-record": {
    kind: "acknowledgement",
    versions: { "2026-11-07": "43eef1162d0c8148b7fe5d62adaa116d0102249794163302592453ce9ce983f1" },
  },
};

interface Served {
  key: string;
  version: string;
  /** sha256 the loader recorded. */
  textHash: string;
  /** sha256 of an independent read of the file bytes, or null when the file could not be read. */
  fileHash: string | null;
}

const SHA_RE = /^[0-9a-f]{64}$/;
const sorted = (a: Iterable<string>): string[] => [...a].sort();

/** Every problem between what the registry serves, what is pinned and what is declared. Empty when consistent. */
export function checkPins(served: Served[], pins: Record<string, Pin>, declared: Readonly<Record<string, string>>): string[] {
  const out: string[] = [];
  if (served.length === 0) out.push("no registry text found: the registry is empty (a check over zero keys is vacuous)");
  const servedKeys = sorted(served.map((e) => e.key));
  const pinnedKeys = sorted(Object.keys(pins));
  const declaredKeys = sorted(Object.keys(declared));
  const missing = (a: string[], b: string[]): string[] => a.filter((k) => !b.includes(k));
  for (const k of missing(servedKeys, pinnedKeys)) out.push(`${k}: served key has no pin in PUBLISHED (add the pinned version and sha256)`);
  for (const k of missing(pinnedKeys, servedKeys)) out.push(`${k}: pinned key is not served (the text file is missing or was renamed)`);
  for (const k of missing(servedKeys, declaredKeys)) out.push(`${k}: served key has no declared card kind in LEGAL_TEXT_KIND`);
  for (const k of missing(declaredKeys, servedKeys)) out.push(`${k}: declared card kind for a key that is not served`);

  for (const e of served) {
    const pin = pins[e.key];
    if (!pin) continue;
    const versions = Object.keys(pin.versions);
    for (const [v, sha] of Object.entries(pin.versions)) if (!SHA_RE.test(sha)) out.push(`${e.key}: pinned sha256 for version ${v} is malformed`);
    const shas = Object.values(pin.versions);
    if (new Set(shas).size !== shas.length) out.push(`${e.key}: two pinned versions share one sha256 (a version bump with no byte change)`);
    const highest = versions.sort()[versions.length - 1];
    if (e.version !== highest) out.push(`${e.key}: served version ${e.version} is not the highest pinned version ${highest}`);
    const pinned = pin.versions[e.version];
    if (pinned === undefined) out.push(`${e.key}: served version ${e.version} has no pinned sha256`);
    else {
      if (e.textHash !== pinned) out.push(`${e.key}: the loader hash ${e.textHash} differs from the pin ${pinned} for version ${e.version} (changed bytes need a new version and a new pin row)`);
      if (e.fileHash === null) out.push(`${e.key}: the file could not be read for the independent hash`);
      else if (e.fileHash !== pinned) out.push(`${e.key}: the independent file hash ${e.fileHash} differs from the pin ${pinned} for version ${e.version}`);
    }
    const kind = declared[e.key];
    if (kind !== undefined && kind !== pin.kind) out.push(`${e.key}: declared kind ${kind} differs from the pinned kind ${pin.kind}`);
  }
  return out;
}

/** What the registry serves, with an independent hash of the file bytes. `fileFor` lets a harness row point the independent read at the wrong file. */
function readServed(dir: string = TEXTS_DIR, fileFor: (key: string) => string = (k) => `${k}.md`): Served[] {
  return [...loadLegalTexts(dir).values()].map((e) => {
    let fileHash: string | null = null;
    try {
      fileHash = createHash("sha256").update(readFileSync(path.join(dir, fileFor(e.key)))).digest("hex");
    } catch {
      fileHash = null;
    }
    return { key: e.key, version: e.version, textHash: e.textHash, fileHash };
  });
}

describe("legal-text registry: the published pin and the exact key set", () => {
  it("the registry serves at least one text (a check over zero keys is vacuous)", () => {
    expect(readServed().length).toBeGreaterThan(0);
  });

  it("the real registry, PUBLISHED and LEGAL_TEXT_KIND agree: same keys, pinned hash, declared kind", () => {
    expect(checkPins(readServed(), PUBLISHED, LEGAL_TEXT_KIND)).toEqual([]);
  });

  it("the key set is the same in all three places", () => {
    const served = sorted(readServed().map((e) => e.key));
    expect(served, "keys the loader serves versus PUBLISHED: add or remove the pin row").toEqual(sorted(Object.keys(PUBLISHED)));
    expect(served, "keys the loader serves versus LEGAL_TEXT_KIND: declare the card kind").toEqual(sorted(Object.keys(LEGAL_TEXT_KIND)));
  });

  it("every pinned sha is 64 lowercase hex, the history has no duplicate sha, and the first row is not a placeholder", () => {
    for (const [k, p] of Object.entries(PUBLISHED)) {
      for (const [v, sha] of Object.entries(p.versions)) {
        expect(sha, `${k} ${v}`).toMatch(SHA_RE);
        expect(sha, `${k} ${v}: an all-zero sha is a placeholder`).not.toBe("0".repeat(64));
      }
      expect(new Set(Object.values(p.versions)).size).toBe(Object.keys(p.versions).length);
    }
  });
});

describe("the pin check bites (synthetic rows through the same function)", () => {
  const h = (c: string): string => c.repeat(64);
  const base: Served[] = [{ key: "a-text", version: "2026-11-07", textHash: h("a"), fileHash: h("a") }];
  const pins: Record<string, Pin> = { "a-text": { kind: "acknowledgement", versions: { "2026-11-07": h("a") } } };
  const declared = { "a-text": "acknowledgement" };

  it("must-PASS control: two keys, each with a two-version history, highest served", () => {
    const two: Served[] = [
      { key: "a-text", version: "2026-12-01", textHash: h("b"), fileHash: h("b") },
      { key: "b-text", version: "2027-01-01", textHash: h("d"), fileHash: h("d") },
    ];
    const p: Record<string, Pin> = {
      "a-text": { kind: "acknowledgement", versions: { "2026-11-07": h("a"), "2026-12-01": h("b") } },
      "b-text": { kind: "terms", versions: { "2026-11-07": h("c"), "2027-01-01": h("d") } },
    };
    expect(checkPins(two, p, { "a-text": "acknowledgement", "b-text": "terms" })).toEqual([]);
    expect(checkPins(base, pins, declared)).toEqual([]);
  });

  const only = (problems: string[], needle: string): void => {
    expect(problems.length).toBeGreaterThan(0);
    expect(problems.join("\n")).toContain(needle);
  };

  it("changed bytes with the same version are caught by the loader leg and by the independent leg", () => {
    only(checkPins([{ ...base[0], textHash: h("e") }], pins, declared), "the loader hash");
    only(checkPins([{ ...base[0], fileHash: h("e") }], pins, declared), "the independent file hash");
    only(checkPins([{ ...base[0], fileHash: null }], pins, declared), "could not be read");
  });

  it("a new key with no pin, a pinned key whose file is gone and a key with no declared kind are caught", () => {
    only(checkPins([...base, { key: "zz", version: "2026-11-07", textHash: h("f"), fileHash: h("f") }], pins, { ...declared, zz: "terms" }), "served key has no pin");
    only(checkPins([], pins, declared), "no registry text found");
    only(checkPins([], pins, declared), "pinned key is not served");
    only(checkPins(base, pins, {}), "served key has no declared card kind");
    only(checkPins(base, pins, { ...declared, orphan: "terms" }), "declared card kind for a key that is not served");
  });

  it("a lower served version than the highest pinned, a duplicate sha, a malformed sha and a kind mismatch are caught", () => {
    const hist: Record<string, Pin> = { "a-text": { kind: "acknowledgement", versions: { "2026-11-07": h("a"), "2026-12-01": h("b") } } };
    only(checkPins(base, hist, declared), "is not the highest pinned version");
    const dup: Record<string, Pin> = { "a-text": { kind: "acknowledgement", versions: { "2026-11-07": h("a"), "2026-12-01": h("a") } } };
    only(checkPins([{ ...base[0], version: "2026-12-01" }], dup, declared), "share one sha256");
    only(checkPins(base, { "a-text": { kind: "acknowledgement", versions: { "2026-11-07": "xyz" } } }, declared), "malformed");
    only(checkPins(base, pins, { "a-text": "terms" }), "differs from the pinned kind");
  });

  it("harness row: pointing the independent read at the README is caught (the independent leg is not decorative)", () => {
    const bad = readServed(TEXTS_DIR, () => "README.md");
    expect(bad.length).toBeGreaterThan(0);
    only(checkPins(bad, PUBLISHED, LEGAL_TEXT_KIND), "the independent file hash");
  });
});
