import { describe, test, expect } from "bun:test";
import {
  diskTopLevelCount,
  memoryTopLevelCount,
  decideSave,
  refusalMessage,
  runGuardedSave,
  DISK_UNRECOGNIZED,
  fingerprintBytes,
  fingerprintState,
  decideStale,
  hash8,
  savedReplyPath,
  notPersistedMessage,
  recreatedNote,
  loadFidelityFailure,
  isDefiniteSaveFailure,
  saveFailureLine,
  REFUSAL_REASON_CODES,
  NOT_PERSISTED_REASON_CODES,
  REASON_CODES,
  REPLAY_SAFETY_SENTENCE,
  ONLY_COPY_SENTENCE,
  UNTRACKED_HINT,
} from "../skills/pencil-setup/scripts/pencil-save-gate.mjs";

// #11143 — empty-overwrite sentinel (Guard 1). An empty in-memory document
// must never replace an on-disk .pen that holds at least one top-level node.

const penWith = (n: number) => JSON.stringify({ version: "2.9", children: Array.from({ length: n }, (_, i) => ({ id: `n${i}`, type: "frame" })) });

describe("diskTopLevelCount", () => {
  test("counts top-level children", () => {
    expect(diskTopLevelCount(penWith(3))).toBe(3);
    expect(diskTopLevelCount(penWith(0))).toBe(0);
  });
  test("null only for missing or blank text", () => {
    expect(diskTopLevelCount(null)).toBeNull();
    expect(diskTopLevelCount(undefined)).toBeNull();
    expect(diskTopLevelCount("")).toBeNull();
    expect(diskTopLevelCount("   \n")).toBeNull();
  });
  test("non-blank text that is not a .pen document is UNRECOGNIZED, never nothing-to-protect", () => {
    // The engine loads each of these as an EMPTY document without an error,
    // so the next save would destroy hand-recoverable content (#11143 review).
    expect(diskTopLevelCount("{not json")).toBe(DISK_UNRECOGNIZED);
    expect(diskTopLevelCount("# Notes\nnot a pen file")).toBe(DISK_UNRECOGNIZED);
    expect(diskTopLevelCount("<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> x")).toBe(DISK_UNRECOGNIZED);
    expect(diskTopLevelCount('{"version":"2.9"}')).toBe(DISK_UNRECOGNIZED);
    expect(diskTopLevelCount('{"name":"package","version":"1.0.0"}')).toBe(DISK_UNRECOGNIZED);
    expect(diskTopLevelCount("[1,2]")).toBe(DISK_UNRECOGNIZED);
  });
  test("a leading byte-order mark is stripped before parsing", () => {
    expect(diskTopLevelCount(String.fromCharCode(0xfeff) + penWith(3))).toBe(3);
  });
});

describe("memoryTopLevelCount (nonce-anchored, #11168 plan 1.6)", () => {
  const nonce = "a".repeat(32);
  const other = "b".repeat(32);
  const reply = (...lines: string[]) =>
    `OK\n\nGlobal variables (e.g. root) carry over to subsequent calls!\n\n## Print output\n${lines.join("\n")}\n`;
  test("reads the count line that carries this call's nonce", () => {
    expect(memoryTopLevelCount(reply(`TOPLEVEL_COUNT:${nonce}:3`), nonce)).toBe(3);
    expect(memoryTopLevelCount(reply(`TOPLEVEL_COUNT:${nonce}:0`), nonce)).toBe(0);
  });
  test("a line with another nonce is not a count (forged by an earlier reply)", () => {
    expect(memoryTopLevelCount(reply(`TOPLEVEL_COUNT:${other}:3`), nonce)).toBeNull();
    // the real line plus a forged one with the right shape still counts once
    expect(memoryTopLevelCount(reply(`TOPLEVEL_COUNT:${other}:9`, `TOPLEVEL_COUNT:${nonce}:2`), nonce)).toBe(2);
  });
  test("zero or two matching lines are unreadable, never a guess", () => {
    expect(memoryTopLevelCount(reply(), nonce)).toBeNull();
    expect(memoryTopLevelCount(reply(`TOPLEVEL_COUNT:${nonce}:2`, `TOPLEVEL_COUNT:${nonce}:3`), nonce)).toBeNull();
  });
  test("null for everything that is not an OK reply with a count", () => {
    expect(memoryTopLevelCount("", nonce)).toBeNull();
    expect(memoryTopLevelCount(null as any, nonce)).toBeNull();
    expect(memoryTopLevelCount(`Error: boom\nTOPLEVEL_COUNT:${nonce}:3`, nonce)).toBeNull();
    expect(memoryTopLevelCount(JSON.stringify({ nodes: [{ id: "a" }] }), nonce)).toBeNull();
    expect(memoryTopLevelCount(reply(`TOPLEVEL_COUNT:${nonce}:3`), "not-a-nonce")).toBeNull();
  });
});

describe("decideSave", () => {
  test("disk 3 / memory 0 refuses", () => {
    const d = decideSave({ diskCount: 3, memoryCount: 0 });
    expect(d.allow).toBe(false);
    expect(d.reason.length).toBeGreaterThan(0);
  });
  test("disk 1 / memory 0 refuses (not just > 1)", () => {
    expect(decideSave({ diskCount: 1, memoryCount: 0 }).allow).toBe(false);
  });
  test("disk 3 / memory undeterminable refuses", () => {
    expect(decideSave({ diskCount: 3, memoryCount: null }).allow).toBe(false);
  });
  test("disk 0 / memory 0 allows (collapsed target has nothing to protect)", () => {
    expect(decideSave({ diskCount: 0, memoryCount: 0 }).allow).toBe(true);
  });
  test("disk missing or blank allows", () => {
    expect(decideSave({ diskCount: null, memoryCount: 0 }).allow).toBe(true);
    expect(decideSave({ diskCount: null, memoryCount: null }).allow).toBe(true);
  });
  test("an unrecognized disk document refuses whatever memory holds", () => {
    for (const memoryCount of [0, 1, 5, null]) {
      const d = decideSave({ diskCount: DISK_UNRECOGNIZED, memoryCount });
      expect(d.allow).toBe(false);
      expect(d.reason).toMatch(/not a recognizable/);
    }
  });
  test("disk 3 / memory 5 allows", () => {
    expect(decideSave({ diskCount: 3, memoryCount: 5 }).allow).toBe(true);
  });
});

describe("refusalMessage", () => {
  test("names the file, says it was not modified, gives the next step", () => {
    const m = refusalMessage({ file: "/d/a.pen", source: "save", code: "empty", diskCount: 3, memoryCount: 0 });
    expect(m).toContain("REFUSED save:");
    expect(m).toContain("/d/a.pen");
    expect(m).toMatch(/not modified/i);
    expect(m).toContain("open_document");
    expect(m).toMatch(/new file path/i);
    expect(m).toMatch(/do not delete or recreate/i);
  });
  test("names exactly one next step per cause, and always forbids delete-to-bypass", () => {
    const empty = refusalMessage({ file: "/d/a.pen", source: "save", code: "empty", diskCount: 3, memoryCount: 0 });
    const unreadable = refusalMessage({ file: "/d/a.pen", source: "save", code: "empty", diskCount: 3, memoryCount: null, memoryReason: "boom" });
    const garbage = refusalMessage({ file: "/d/a.pen", source: "save", code: "unrecognized", diskCount: DISK_UNRECOGNIZED, memoryCount: 2 });
    for (const m of [empty, unreadable, garbage]) {
      expect(m).toContain("REFUSED save:");
      expect(m).toMatch(/Next step:/);
      expect(m.match(/Next step:/g)!.length).toBe(1);
      expect(m).toMatch(/do not delete or recreate/i);
    }
    // an unreadable probe must not be blamed on a never-loaded file
    expect(unreadable).toContain("boom");
    expect(unreadable).not.toMatch(/never loaded/i);
    expect(unreadable).not.toMatch(/replace the file with an empty document/i);
    expect(garbage).toMatch(/not a recognizable \.pen document/);
    expect(garbage).not.toMatch(/never loaded/i);
  });
  test("the auto-save variant says the edit is applied in memory but not persisted", () => {
    const m = refusalMessage({ file: "/d/a.pen", source: "auto-save", code: "empty", diskCount: 3, memoryCount: 0 });
    expect(m).toMatch(/in memory but not (persisted|saved)/i);
    expect(m).toMatch(/lost on the next open_document/i);
  });
});


describe("refusalMessage: the stale family (#11168)", () => {
  const stale = refusalMessage({ file: "/d/a.pen", source: "auto-save", code: "stale" });
  test("stale: names the change, warns that re-opening discards edits, says re-open then replay in order", () => {
    expect(stale).toContain("REFUSED save:");
    expect(stale).toContain("/d/a.pen was not modified");
    expect(stale).toMatch(/changed on disk since this session loaded or last saved it/);
    expect(stale).toMatch(/another session, git, or an editor such as Pencil Desktop/);
    expect(stale).toMatch(/re-opening discards them/);
    expect(stale).toMatch(/open_document/);
    expect(stale).toMatch(/replay the refused operations in order/);
    expect(stale).toMatch(/one writer per file/);
    expect(stale).toMatch(/do not delete or recreate/i);
    expect(stale).toMatch(/If open_document itself fails/);
    expect(stale.match(/Next step:/g)!.length).toBe(1);
    expect(stale).toMatch(/in memory but not persisted/i);
  });
  test("an unknown or missing code is a programming error, never a message (`changed` is no alias)", () => {
    for (const code of ["changed", "missing", "nope", undefined]) {
      expect(() => refusalMessage({ file: "x.pen", source: "save", code: code as any })).toThrow(/unknown code/);
    }
  });
  test("each state has its own wording, distinct from the others", () => {
    const missing = refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending", restart: "file-missing" });
    const external = refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending", restart: "external-change" });
    const unconfirmed = refusalMessage({ file: "/d/a.pen", source: "save", code: "unknown-baseline", cause: "unconfirmed-save" });
    const postRead = refusalMessage({ file: "/d/a.pen", source: "save", code: "unknown-baseline", cause: "post-save-read-failed" });
    const capture = refusalMessage({ file: "/d/a.pen", source: "save", code: "unknown-baseline", cause: "capture-failed", detail: "ELOOP" });
    const pending = refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending" });
    const restarted = refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending", restart: "restart" });
    expect(missing).toMatch(/no longer exists on disk/i);
    expect(missing).toMatch(/recreate the edits from your context/);
    expect(missing).not.toMatch(/changed on disk since/);
    expect(external).toMatch(/engine reloaded NEW content/);
    expect(external).toMatch(/Nothing on disk was overwritten/);
    expect(external).toMatch(/call open_document on \/d\/a\.pen \(in the Soleur repo[^)]*\), then replay/);
    expect(unconfirmed).toMatch(/last save was not confirmed/i);
    expect(unconfirmed).not.toMatch(/changed on disk since/);
    expect(postRead).toMatch(/could not be read back/i);
    expect(capture).toContain("ELOOP");
    expect(restarted).toMatch(/session restarted/i);
    expect(restarted).toMatch(/earlier edits were discarded/i);
    expect(restarted).toMatch(/not persisted \(a refused, failed or unconfirmed save\)/);
    expect(pending).not.toMatch(/session restarted/i);
    const all = [stale, missing, external, unconfirmed, postRead, capture, pending, restarted];
    for (const m of all) {
      expect(m).toContain("REFUSED save:");
      expect(m.match(/Next step:/g)!.length).toBe(1);
      expect(m).toMatch(/do not delete or recreate/i);
    }
    expect(new Set(all).size).toBe(all.length);
  });
});

describe("the marker contract: the first line of every refusal is `REFUSED save: [reason=<code>] <file> was not modified.`", () => {
  const first = (m: string) => m.split("\n")[0];
  const cases: Array<[string, any]> = [
    ["empty", { code: "empty", diskCount: 3, memoryCount: 0 }],
    ["empty", { code: "empty", diskCount: 3, memoryCount: null, memoryReason: "boom" }],
    ["unrecognized", { code: "unrecognized", diskCount: DISK_UNRECOGNIZED, memoryCount: 2 }],
    ["stale", { code: "stale" }],
    ["unknown-baseline", { code: "unknown-baseline", cause: "unconfirmed-save" }],
    ["refusal-pending", { code: "refusal-pending" }],
    ["refusal-pending", { code: "refusal-pending", restart: "restart" }],
    ["refusal-pending", { code: "refusal-pending", restart: "external-change" }],
    ["refusal-pending", { code: "refusal-pending", restart: "file-missing" }],
  ];
  for (const [code, args] of cases) {
    test(`reason=${code} ${JSON.stringify(args)}`, () => {
      expect(first(refusalMessage({ file: "/d/a.pen", source: "save", ...args }))).toBe(`REFUSED save: [reason=${code}] /d/a.pen was not modified.`);
    });
  }
  test("the next steps for the recoverable refusals carry the exact UNTRACKED_HINT (ask the user; never commit unprompted)", () => {
    expect(UNTRACKED_HINT).toBe("(in the Soleur repo the open guard needs the path tracked: ask the user, then commit an empty placeholder)");
    for (const code of ["stale", "refusal-pending", "unknown-baseline"]) {
      expect(refusalMessage({ file: "/d/a.pen", source: "save", code })).toContain(UNTRACKED_HINT);
    }
  });
});

describe("the exported reason-code lists (the prose test imports them)", () => {
  test("refusal codes are the five real ones, not-persisted codes the three, REASON_CODES is their union", () => {
    expect([...REFUSAL_REASON_CODES]).toEqual(["stale", "unknown-baseline", "refusal-pending", "empty", "unrecognized"]);
    expect([...NOT_PERSISTED_REASON_CODES]).toEqual(["save-failed", "unconfirmed", "save-incomplete"]);
    expect([...REASON_CODES]).toEqual([...REFUSAL_REASON_CODES, ...NOT_PERSISTED_REASON_CODES]);
  });
  test("every listed code produces a message whose first line carries exactly that code", () => {
    for (const code of REFUSAL_REASON_CODES) {
      const m = refusalMessage({ file: "/d/a.pen", source: "save", code, diskCount: code === "unrecognized" ? DISK_UNRECOGNIZED : 3, memoryCount: 0 });
      expect(m.split("\n")[0]).toBe(`REFUSED save: [reason=${code}] /d/a.pen was not modified.`);
    }
    for (const code of NOT_PERSISTED_REASON_CODES) {
      expect(notPersistedMessage({ code, file: "/d/a.pen" }).split("\n")[0]).toMatch(new RegExp(`^NOT PERSISTED: \\[reason=${code}\\] /d/a\\.pen`));
    }
  });
});

describe("the shared text contract", () => {
  test("replay-safety: unconfirmed, save-incomplete and the refusal-pending external-change cause say to check whether the edit is already present", () => {
    expect(REPLAY_SAFETY_SENTENCE).toBe(
      "Before replaying, check whether the edit is already present (compare the node count open_document reports, or Get the nodes): this session's own interrupted save may already have written it."
    );
    expect(notPersistedMessage({ code: "unconfirmed", file: "/d/a.pen" })).toContain(REPLAY_SAFETY_SENTENCE);
    expect(notPersistedMessage({ code: "save-incomplete", file: "/d/a.pen" })).toContain(REPLAY_SAFETY_SENTENCE);
    expect(refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending", restart: "external-change" })).toContain(REPLAY_SAFETY_SENTENCE);
    // not where the edit cannot have been written
    expect(notPersistedMessage({ code: "save-failed", file: "/d/a.pen" })).not.toContain(REPLAY_SAFETY_SENTENCE);
  });
  test("only-copy: save-failed and the unrecognized refusal say the in-memory document is the only complete copy and to read it out BEFORE open_document", () => {
    expect(ONLY_COPY_SENTENCE).toBe(
      "If a retry is refused, the in-memory document is the only complete copy: read it out (get_editor_state, or Get/Print inside batch_design) or export it BEFORE calling open_document."
    );
    expect(notPersistedMessage({ code: "save-failed", file: "/d/a.pen" })).toContain(ONLY_COPY_SENTENCE);
    expect(refusalMessage({ file: "/d/a.pen", source: "save", code: "unrecognized", diskCount: DISK_UNRECOGNIZED })).toContain(ONLY_COPY_SENTENCE);
  });
  test("file-missing: restore from version control first", () => {
    expect(refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending", restart: "file-missing" })).toContain(
      "If the file is tracked, restore it from version control first."
    );
  });
  test("a save that failed while the file changed names the changed file and the only copy", () => {
    const m = notPersistedMessage({ code: "save-failed", file: "/d/a.pen", detail: "Save failed: EIO", changed: true });
    expect(m.split("\n")[0]).toMatch(/^NOT PERSISTED: \[reason=save-failed\] \/d\/a\.pen /);
    expect(m).toContain("the file changed during the failed write; the in-memory document is the only complete copy");
    expect(m).not.toMatch(/call save again/);
  });
  test("a recreate whose path changed refuses as unknown-baseline with its own cause", () => {
    const m = refusalMessage({ file: "/d/a.pen", source: "save", code: "unknown-baseline", cause: "recreate-path-changed" });
    expect(m).toMatch(/directory on the way to it is now a link or has moved/);
    expect(m).toContain(UNTRACKED_HINT);
  });
});

describe("notPersistedMessage: `NOT PERSISTED: [reason=<code>] <file> ...`", () => {
  test("save-failed says in memory only, fix the cause, save again, never open_document", () => {
    const m = notPersistedMessage({ code: "save-failed", file: "/d/a.pen", detail: "Save failed: EACCES" });
    expect(m.split("\n")[0]).toBe("NOT PERSISTED: [reason=save-failed] /d/a.pen was not written: the engine reported a failed save (Save failed: EACCES).");
    expect(m).toMatch(/applied in memory only/);
    expect(m).toMatch(/call save again/);
    expect(m).toMatch(/Do NOT call open_document: it discards the edit/);
  });
  test("unconfirmed and save-incomplete carry their code on line one", () => {
    expect(notPersistedMessage({ code: "unconfirmed", file: "/d/a.pen" }).split("\n")[0]).toMatch(/^NOT PERSISTED: \[reason=unconfirmed\] \/d\/a\.pen may or may not have been written/);
    expect(notPersistedMessage({ code: "unconfirmed", file: "/d/a.pen" })).toMatch(/call open_document on \/d\/a\.pen before saving again/);
    expect(notPersistedMessage({ code: "save-incomplete", file: "/d/a.pen", detail: "timeout" }).split("\n")[0]).toBe(
      "NOT PERSISTED: [reason=save-incomplete] /d/a.pen: the edit was applied in memory but the save did not complete (timeout); it is not persisted."
    );
  });
  test("an unknown code is a programming error, not a message", () => {
    expect(() => notPersistedMessage({ code: "nope", file: "x" })).toThrow(/unknown code/);
  });
  test("recreatedNote is the NOTE line of ruling 2", () => {
    expect(recreatedNote("/d/a.pen")).toBe(
      "NOTE: /d/a.pen had been removed from disk (a branch switch, a move or a delete); this save recreated it from the session's copy - tell the user and check that the file belongs at that path"
    );
  });
});

describe("loadFidelityFailure (ruling 6): memory fewer than disk at load", () => {
  const f = "/d/a.pen";
  test("any drop refuses, not only a drop to zero; unreadable and empty are drops", () => {
    expect(loadFidelityFailure({ file: f, diskCount: 5, memoryCount: 3 })).toBe(`${f} holds 5 top-level node(s) on disk but loaded 3; it was not modified`);
    expect(loadFidelityFailure({ file: f, diskCount: 3, memoryCount: 0 })).toMatch(/but loaded empty/);
    expect(loadFidelityFailure({ file: f, diskCount: 3, memoryCount: null })).toMatch(/but loaded unreadable/);
    expect(loadFidelityFailure({ file: f, diskCount: 1, memoryCount: 0 })).not.toBeNull();
  });
  test("equal or more nodes, and nothing on disk, pass", () => {
    expect(loadFidelityFailure({ file: f, diskCount: 3, memoryCount: 3 })).toBeNull();
    expect(loadFidelityFailure({ file: f, diskCount: 3, memoryCount: 9 })).toBeNull();
    expect(loadFidelityFailure({ file: f, diskCount: 0, memoryCount: 0 })).toBeNull();
    expect(loadFidelityFailure({ file: f, diskCount: null, memoryCount: null })).toBeNull();
    expect(loadFidelityFailure({ file: f, diskCount: undefined, memoryCount: 0 })).toBeNull();
  });
  test("a file that is not a .pen document is refused whatever memory holds", () => {
    expect(loadFidelityFailure({ file: f, diskCount: DISK_UNRECOGNIZED, memoryCount: 4 })).toMatch(/not a recognizable \.pen document/);
  });
});

describe("isDefiniteSaveFailure / saveFailureLine (ruling 3)", () => {
  test("a `Save failed:` line with no `Saved` line is definite (ANSI and surrounding stderr noise allowed)", () => {
    expect(isDefiniteSaveFailure("\u001b[31mSave failed: EACCES: permission denied\u001b[39m\n")).toBe(true);
    expect(isDefiniteSaveFailure("[WARN] [IPC] request failed\n[ERROR] Headless editor error\nSave failed: disk full\n")).toBe(true);
    expect(saveFailureLine("[ERROR] x\n\u001b[31mSave failed: disk full\u001b[39m\n")).toBe("Save failed: disk full");
  });
  test("empty, wrong-path, ambiguous and mixed replies are not definite", () => {
    for (const raw of ["", "OK", "Saved /elsewhere.pen", "Save failed? hm", "  Save failed: indented", "Saved /d/a.pen\nSave failed: late", null, undefined, 3]) {
      expect(isDefiniteSaveFailure(raw as any)).toBe(false);
    }
    expect(saveFailureLine("Saved /d/a.pen")).toBe("");
  });
});

describe("fingerprintBytes (canonical JSON, #11168 ruling 11.1)", () => {
  const doc = { version: "2.21", children: [{ id: "n0", type: "frame", name: "a" }] };
  test("hex SHA-256, deterministic, Buffer and string input agree", () => {
    const h = fingerprintBytes(JSON.stringify(doc));
    expect(h).toMatch(/^[0-9a-f]{64}$/);
    expect(fingerprintBytes(Buffer.from(JSON.stringify(doc)))).toBe(h);
    expect(fingerprintBytes(JSON.stringify(doc))).toBe(h);
  });
  test("whitespace, line endings, a BOM and pretty-printing do not change it", () => {
    const h = fingerprintBytes(JSON.stringify(doc));
    expect(fingerprintBytes(JSON.stringify(doc, null, 2))).toBe(h);
    expect(fingerprintBytes(JSON.stringify(doc, null, 2).replace(/\n/g, "\r\n"))).toBe(h);
    expect(fingerprintBytes("\ufeff" + JSON.stringify(doc))).toBe(h);
    expect(fingerprintBytes(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(JSON.stringify(doc))]))).toBe(h);
  });
  test("object key order does not change it, at any depth (arrays keep their order)", () => {
    const a = JSON.stringify({ version: "2.21", children: [{ id: "n0", type: "frame", layout: { gap: 1, mode: "v" } }] });
    const b = JSON.stringify({ children: [{ layout: { mode: "v", gap: 1 }, type: "frame", id: "n0" }], version: "2.21" });
    expect(a).not.toBe(b);
    expect(fingerprintBytes(a)).toBe(fingerprintBytes(b));
    expect(fingerprintBytes(JSON.stringify({ children: [{ id: "a" }, { id: "b" }] }))).not.toBe(
      fingerprintBytes(JSON.stringify({ children: [{ id: "b" }, { id: "a" }] }))
    );
    // a key named like a prototype slot is a key like any other
    expect(fingerprintBytes('{"__proto__":{"a":1},"b":2}')).toBe(fingerprintBytes('{"b":2,"__proto__":{"a":1}}'));
  });
  test("G1a: a document well over 4096 bytes differing only in its LAST node differs (the hash covers the whole document)", () => {
    const big = (tail: string) => JSON.stringify({ children: Array.from({ length: 300 }, (_, i) => ({ id: `n${i}`, name: i === 299 ? tail : `node ${i}` })) });
    const a = big("tail-aaaa");
    const b = big("tail-bbbb");
    expect(a.length).toBeGreaterThan(8192);
    expect(a.length).toBe(b.length);
    expect(fingerprintBytes(a)).not.toBe(fingerprintBytes(b));
  });
  test("a changed value differs, including a same-size one", () => {
    const a = JSON.stringify({ children: [{ id: "x", name: "seed0" }] });
    const b = JSON.stringify({ children: [{ id: "x", name: "seed1" }] });
    expect(a.length).toBe(b.length);
    expect(fingerprintBytes(a)).not.toBe(fingerprintBytes(b));
  });
  test("text that does not parse is hashed as raw bytes, and differs per byte", () => {
    expect(fingerprintBytes("{not json")).toMatch(/^[0-9a-f]{64}$/);
    expect(fingerprintBytes("{not json")).not.toBe(fingerprintBytes("{not jsoN"));
    expect(fingerprintBytes("")).toMatch(/^[0-9a-f]{64}$/);
    expect(fingerprintBytes(Buffer.from([0xff, 0xfe, 0x00]))).toMatch(/^[0-9a-f]{64}$/);
  });
  test("fingerprintState: null is missing, bytes (even blank) are a hash", () => {
    expect(fingerprintState(null)).toEqual({ tag: "missing" });
    const blank = fingerprintState("");
    expect(blank.tag).toBe("hash");
    expect(fingerprintState(JSON.stringify(doc))).toEqual({ tag: "hash", hash: fingerprintBytes(JSON.stringify(doc)) });
  });
  test("hash8 is an 8-hex-char prefix and tolerates a non-hash", () => {
    expect(hash8(fingerprintBytes("x"))).toMatch(/^[0-9a-f]{8}$/);
    expect(hash8(undefined)).toBe("-");
  });
});

describe("decideStale: only an exact missing/hash match allows (plus recreated)", () => {
  const H1 = { tag: "hash", hash: "1".repeat(64) } as const;
  const H2 = { tag: "hash", hash: "2".repeat(64) } as const;
  const MISSING = { tag: "missing" } as const;
  const dec = (baseline: any, current: any, refusalPending = false) => decideStale({ baseline, current, refusalPending });

  test("hash baseline: equal hash allows, different hash is stale", () => {
    expect(dec(H1, H1).allow).toBe(true);
    const stale = dec(H1, H2);
    expect(stale).toMatchObject({ allow: false, code: "stale", arm: true });
    expect(stale.baselineHash).toBe(H1.hash);
    expect(stale.diskHash).toBe(H2.hash);
  });
  test("hash baseline + file removed behind a live session: ALLOW, marked recreated (ruling 2); a missing baseline that stays missing is not recreated", () => {
    expect(dec(H1, MISSING)).toEqual({ allow: true, recreated: true });
    expect(dec(MISSING, MISSING)).toEqual({ allow: true });
    expect(dec(H1, H1)).toEqual({ allow: true });
  });
  test("recreated never overrides the other refusals: pending, unknown baseline", () => {
    expect(dec(H1, MISSING, true)).toMatchObject({ allow: false, code: "refusal-pending" });
    expect(dec({ tag: "unknown", cause: "unconfirmed-save" }, MISSING)).toMatchObject({ allow: false, code: "unknown-baseline" });
  });
  test("missing baseline: still missing allows, a file that appeared is stale", () => {
    expect(dec(MISSING, MISSING).allow).toBe(true);
    expect(dec(MISSING, H1)).toMatchObject({ allow: false, code: "stale", arm: true });
  });
  test("unknown baseline refuses against every current state, with its own cause", () => {
    for (const current of [H1, MISSING]) {
      expect(dec({ tag: "unknown", cause: "unconfirmed-save" }, current)).toMatchObject({
        allow: false,
        code: "unknown-baseline",
        cause: "unconfirmed-save",
      });
    }
    expect(dec({ tag: "unknown", cause: "post-save-read-failed" }, H1).cause).toBe("post-save-read-failed");
  });
  test("an unreadable current state refuses as capture-failed and carries the errno", () => {
    expect(dec(H1, { tag: "unknown", cause: "capture-failed", detail: "ELOOP" })).toMatchObject({
      allow: false,
      code: "unknown-baseline",
      cause: "capture-failed",
      detail: "ELOOP",
    });
  });
  test("no baseline (none) refuses: nothing was loaded to compare against", () => {
    expect(dec({ tag: "none" }, MISSING)).toMatchObject({ allow: false, code: "unknown-baseline" });
    expect(dec(undefined, H1).allow).toBe(false);
    expect(dec({ tag: "weird" }, H1).allow).toBe(false);
  });
  test("refusalPending refuses even when the baseline matches, and does not re-arm", () => {
    expect(dec(H1, H1, true)).toMatchObject({ allow: false, code: "refusal-pending" });
  });
});

describe("savedReplyPath", () => {
  test("the path of exactly one `Saved <path>` line, ANSI stripped", () => {
    expect(savedReplyPath("\u001b[32mSaved /d/a.pen\u001b[39m\n")).toBe("/d/a.pen");
    expect(savedReplyPath("Saved /d/with space.pen")).toBe("/d/with space.pen");
  });
  test("anything else is null", () => {
    for (const bad of ["", "Saved", "Saved ", "saved /d/a.pen", "OK\nSaved /d/a.pen", "Saved /d/a.pen\nmore", "Save failed: x", null, undefined]) {
      expect(savedReplyPath(bad as any)).toBeNull();
    }
  });
});

describe("runGuardedSave (dependency-injected, ordering)", () => {
  const nonce = "c".repeat(32);
  const countReply = (n: number) => ({ text: `OK\n\n## Print output\nTOPLEVEL_COUNT:${nonce}:${n}\n`, nonce });
  const H = (c: string) => ({ tag: "hash" as const, hash: fingerprintBytes(c) });

  function mk(opts: {
    disk?: string | null;
    fresh?: string | null | Error;
    mem?: ReturnType<typeof countReply> | Error;
    baseline?: any;
    pending?: boolean;
    saveReply?: string;
    after?: Array<string | null | Error>;
  }) {
    const calls: string[] = [];
    const disk = opts.disk === undefined ? penWith(3) : opts.disk;
    const fresh = opts.fresh === undefined ? disk : opts.fresh;
    let baseline = opts.baseline ?? (disk === null ? { tag: "missing" } : H(disk));
    const after = [...(opts.after ?? [fresh as any])];
    const adopted: any[] = [];
    return {
      calls,
      adopted,
      baseline: () => baseline,
      deps: {
        file: "/d/a.pen",
        source: "save" as const,
        readDisk: async () => {
          calls.push("readDisk");
          return disk;
        },
        probeMemory: async () => {
          calls.push("probeMemory");
          if (opts.mem instanceof Error) throw opts.mem;
          return opts.mem ?? countReply(5);
        },
        readFresh: async () => {
          calls.push("readFresh");
          if (fresh instanceof Error) throw fresh;
          return fresh;
        },
        getBaseline: () => baseline,
        isRefusalPending: () => opts.pending ?? false,
        send: async () => {
          calls.push("send:save");
          return opts.saveReply ?? "Saved /d/a.pen";
        },
        isConfirmed: (raw: string) => raw === "Saved /d/a.pen",
        readAfterSave: async () => {
          calls.push("readAfterSave");
          const next = after.length > 1 ? after.shift() : after[0];
          if (next instanceof Error) throw next;
          return next as any;
        },
        adoptBaseline: (state: any) => {
          calls.push("adopt");
          adopted.push(state);
          baseline = state;
        },
        retryDelayMs: 1,
      },
    };
  }

  test("order: disk read, memory probe, FRESH read, then the save, then the post-save read and adopt", async () => {
    const m = mk({});
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ saved: true, refused: false, confirmed: true });
    expect(m.calls).toEqual(["readDisk", "probeMemory", "readFresh", "send:save", "readAfterSave", "adopt"]);
  });

  test("a stale baseline refuses AFTER the probe and BEFORE any save", async () => {
    const changed = penWith(8);
    const m = mk({ disk: changed, fresh: changed, baseline: H(penWith(5)) });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ saved: false, refused: true, code: "stale", arm: true });
    expect(r.message).toContain("REFUSED save:");
    expect(m.calls).toEqual(["readDisk", "probeMemory", "readFresh"]);
    expect(m.adopted).toEqual([]);
  });

  test("the stale decision uses the fresh read, not the first one (a rewrite during the probe)", async () => {
    const m = mk({ disk: penWith(3), fresh: penWith(7), baseline: H(penWith(3)) });
    const r = await runGuardedSave(m.deps);
    expect(r.refused).toBe(true);
    expect(r.code).toBe("stale");
    expect(m.calls).not.toContain("send:save");
  });

  test("decideSave keeps precedence: empty-over-non-empty keeps its own text and code", async () => {
    const m = mk({ mem: countReply(0), baseline: H(penWith(3)) });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "empty" });
    expect(r.message).toMatch(/in-memory document has 0/);
    expect(m.calls).toEqual(["readDisk", "probeMemory"]);
  });

  test("an unrecognizable disk file keeps its text and code and never probes", async () => {
    const m = mk({ disk: "{not json", fresh: "{not json" });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "unrecognized" });
    expect(m.calls).toEqual(["readDisk"]);
  });

  test("a forged/unreadable count over a non-empty file refuses as empty (unreadable memory)", async () => {
    const m = mk({ mem: { text: `OK\n\n## Print output\nTOPLEVEL_COUNT:${"d".repeat(32)}:5\n`, nonce } });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "empty" });
    expect(r.message).toMatch(/could not be read/);
    expect(m.calls).not.toContain("send:save");
  });

  test("a missing target saves without a probe, with a missing baseline", async () => {
    const m = mk({ disk: null, fresh: null, baseline: { tag: "missing" }, after: [penWith(1)] });
    const r = await runGuardedSave(m.deps);
    expect(r.saved).toBe(true);
    expect(m.calls).toEqual(["readDisk", "readFresh", "send:save", "readAfterSave", "adopt"]);
    expect(m.adopted[0]).toEqual(H(penWith(1)));
  });

  test("a file removed behind a hash baseline is saved and reported recreated (the first read is already null)", async () => {
    const m = mk({ disk: null, fresh: null, baseline: H(penWith(2)), after: [penWith(2)] });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ saved: true, refused: false, recreated: true, baselineHash: H(penWith(2)).hash });
    expect(m.calls).toEqual(["readDisk", "readFresh", "send:save", "readAfterSave", "adopt"]);
    expect(m.adopted[0]).toEqual(H(penWith(2)));
  });

  test("a removed file with delete-every-node semantics is still the sentinel's: decideSave runs first (disk present, memory empty)", async () => {
    const m = mk({ mem: countReply(0), baseline: H(penWith(3)) });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "empty" });
  });

  test("a definite failure keeps the previous baseline and adopts nothing (ruling 3)", async () => {
    const m = mk({ saveReply: "Save failed: EACCES" });
    (m.deps as any).isDefiniteFailure = (raw: string) => /^Save failed:/.test(raw);
    const before = m.baseline();
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ saved: false, refused: false, failed: true, raw: "Save failed: EACCES" });
    expect(r.unconfirmed).toBeUndefined();
    expect(m.adopted).toEqual([]);
    expect(m.baseline()).toBe(before);
    expect(m.calls).not.toContain("readAfterSave");
    expect(r.changedDuringFailedWrite).toBe(false);
    expect(r.arm).toBeFalsy();
  });

  test("a definite failure after which the file differs from the baseline arms the refusal and says the file changed (data integrity)", async () => {
    const m = mk({ saveReply: "Save failed: EIO" });
    (m.deps as any).isDefiniteFailure = (raw: string) => /^Save failed:/.test(raw);
    let reads = 0;
    const original = m.deps.readFresh;
    m.deps.readFresh = async () => (++reads === 1 ? await original() : penWith(1)); // 2nd read = after the failed write: a partial write
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ failed: true, changedDuringFailedWrite: true, arm: true });
    expect(m.adopted).toEqual([]);
    // an unreadable file after the failure makes no claim
    const n = mk({ saveReply: "Save failed: EIO" });
    (n.deps as any).isDefiniteFailure = () => true;
    let k = 0;
    const orig = n.deps.readFresh;
    n.deps.readFresh = async () => {
      if (++k === 1) return await orig();
      throw new Error("EIO");
    };
    expect(await runGuardedSave(n.deps)).toMatchObject({ failed: true, changedDuringFailedWrite: false });
  });

  test("a failed save over a recreate (file already missing) is not 'changed' while the file is still missing", async () => {
    const m = mk({ disk: null, fresh: null, baseline: H(penWith(2)), saveReply: "Save failed: EACCES" });
    (m.deps as any).isDefiniteFailure = () => true;
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ failed: true, recreated: true, changedDuringFailedWrite: false });
  });

  test("a recreate whose path is no longer the canonical one refuses as unknown-baseline/recreate-path-changed, nothing sent", async () => {
    const m = mk({ disk: null, fresh: null, baseline: H(penWith(2)) });
    (m.deps as any).canRecreate = async () => false;
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "unknown-baseline", cause: "recreate-path-changed" });
    expect(m.calls).not.toContain("send:save");
    // a path that is still canonical recreates as before
    const ok = mk({ disk: null, fresh: null, baseline: H(penWith(2)), after: [penWith(2)] });
    (ok.deps as any).canRecreate = async () => true;
    expect(await runGuardedSave(ok.deps)).toMatchObject({ saved: true, recreated: true });
  });

  test("without isDefiniteFailure, or when it says no, the reply is unconfirmed and the baseline becomes unknown", async () => {
    const m = mk({ saveReply: "Save failed: EACCES" });
    expect(await runGuardedSave(m.deps)).toMatchObject({ unconfirmed: true });
    const n = mk({ saveReply: "" });
    (n.deps as any).isDefiniteFailure = () => false;
    expect(await runGuardedSave(n.deps)).toMatchObject({ unconfirmed: true });
    expect(n.adopted).toEqual([{ tag: "unknown", cause: "unconfirmed-save" }]);
  });

  test("wasRestarted's cause reaches the refusal-pending wording", async () => {
    const m = mk({ pending: true });
    (m.deps as any).wasRestarted = () => "external-change";
    const r = await runGuardedSave(m.deps);
    expect(r.message).toMatch(/engine reloaded NEW content/);
    expect(r.message.split("\n")[0]).toBe("REFUSED save: [reason=refusal-pending] /d/a.pen was not modified.");
  });

  test("a fresh read that throws refuses as unknown-baseline/capture-failed with the errno, no save", async () => {
    const err = Object.assign(new Error("loop"), { code: "ELOOP" });
    const m = mk({ fresh: err });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "unknown-baseline", cause: "capture-failed", detail: "ELOOP" });
    expect(m.calls).not.toContain("send:save");
  });

  test("a first disk read that throws refuses (an I/O error is not 'missing') and carries the cause", async () => {
    const m = mk({});
    m.deps.readDisk = async () => {
      throw new Error("EACCES: permission denied");
    };
    const r = await runGuardedSave(m.deps);
    expect(r.refused).toBe(true);
    expect(r.code).toBe("unknown-baseline");
    expect(r.message).toContain("EACCES");
    expect(m.calls).toEqual([]);
  });

  test("a probe that THROWS refuses and carries the cause", async () => {
    const m = mk({ mem: new Error("pen exited during a command") });
    const r = await runGuardedSave(m.deps);
    expect(r.refused).toBe(true);
    expect(r.message).toContain("pen exited during a command");
    expect(m.calls).not.toContain("send:save");
  });

  test("refusalPending refuses on the flag alone, after the probe, before the save", async () => {
    const m = mk({ pending: true });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "refusal-pending" });
    expect(m.calls).not.toContain("send:save");
  });

  test("a reply that is not the confirmed line: not saved, baseline adopted as unknown, nothing read from disk", async () => {
    for (const reply of ["", "Saved /elsewhere.pen", "Save failed: EACCES", "OK"]) {
      const m = mk({ saveReply: reply });
      const r = await runGuardedSave(m.deps);
      expect(r).toMatchObject({ saved: false, refused: false, unconfirmed: true, raw: reply });
      expect(m.adopted).toEqual([{ tag: "unknown", cause: "unconfirmed-save" }]);
      expect(m.calls).not.toContain("readAfterSave");
    }
  });

  test("one transient post-save read error is absorbed by the retry (3 tries)", async () => {
    const body = penWith(4);
    const m = mk({ after: [Object.assign(new Error("busy"), { code: "EBUSY" }), body] });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ saved: true, confirmed: true });
    expect(r.warning).toBeUndefined();
    expect(m.calls.filter((c) => c === "readAfterSave").length).toBe(2);
    expect(m.adopted).toEqual([H(body)]);
  });

  test("three failing post-save reads: success with a warning, baseline unknown (never a duplicate re-apply)", async () => {
    const m = mk({ after: [Object.assign(new Error("busy"), { code: "EBUSY" })] });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ saved: true, refused: false, confirmed: true });
    expect(r.warning).toMatch(/EBUSY/);
    expect(m.calls.filter((c) => c === "readAfterSave").length).toBe(3);
    expect(m.adopted).toEqual([{ tag: "unknown", cause: "post-save-read-failed" }]);
  });

  test("a file missing right after a confirmed save counts as an unreadable post-save state", async () => {
    const m = mk({ after: [null] });
    const r = await runGuardedSave(m.deps);
    expect(r.saved).toBe(true);
    expect(m.adopted).toEqual([{ tag: "unknown", cause: "post-save-read-failed" }]);
  });

  test("the hooks are required: a caller that omits one cannot silently run unguarded", async () => {
    const m = mk({});
    for (const key of ["readFresh", "getBaseline", "adoptBaseline", "isConfirmed", "isRefusalPending", "readAfterSave"]) {
      const deps: any = { ...m.deps };
      delete deps[key];
      await expect(runGuardedSave(deps)).rejects.toThrow(new RegExp(key));
    }
  });
});

// ---------------------------------------------------------------------------
// Round 3: the failed-write cause, the unconfirmed replay hint, the canonical-path check
// on every save over a hashed baseline.

describe("refusal-pending cause `failed-write` (a failed save that changed the file)", () => {
  const m = refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending", restart: "failed-write" });
  const stale = refusalMessage({ file: "/d/a.pen", source: "save", code: "refusal-pending" });

  test("says the file changed during a failed write, the in-memory document is the only complete copy, and read it out BEFORE open_document", () => {
    expect(m.split("\n")[0]).toBe("REFUSED save: [reason=refusal-pending] /d/a.pen was not modified.");
    expect(m).toContain("the file changed during a failed write");
    expect(m).toContain("the in-memory document is the only complete copy");
    expect(m).toContain(ONLY_COPY_SENTENCE);
    expect(m).toMatch(/call open_document on \/d\/a\.pen/);
    expect(m.match(/Next step:/g)!.length).toBe(1);
    expect(m).toMatch(/do not delete or recreate/i);
  });
  test("is not the stale-flavoured generic text, which blames an external change and has no only-copy sentence", () => {
    expect(stale).not.toContain(ONLY_COPY_SENTENCE);
    expect(m).not.toMatch(/refused because the file changed on disk/);
    expect(m).not.toBe(stale);
  });
});

describe("unknown-baseline cause unconfirmed-save carries the replay-safety sentence", () => {
  test("the unconfirmed save may have written the edit: check before replaying", () => {
    const m = refusalMessage({ file: "/d/a.pen", source: "save", code: "unknown-baseline", cause: "unconfirmed-save" });
    expect(m).toContain(REPLAY_SAFETY_SENTENCE);
    expect(m.match(/Next step:/g)!.length).toBe(1);
  });
  test("a cause that cannot have written the edit does not carry it", () => {
    for (const cause of ["no-baseline", "capture-failed", "recreate-path-changed"]) {
      expect(refusalMessage({ file: "/d/a.pen", source: "save", code: "unknown-baseline", cause })).not.toContain(REPLAY_SAFETY_SENTENCE);
    }
  });
});

describe("the canonical-path check runs on every save over a hashed baseline, not only a recreate", () => {
  const nonce = "d".repeat(32);
  const countReply = (n: number) => ({ text: `OK\n\n## Print output\nTOPLEVEL_COUNT:${nonce}:${n}\n`, nonce });
  const disk = penWith(3);
  const mk = (canRecreate: () => Promise<boolean>) => {
    const calls: string[] = [];
    const base = { tag: "hash" as const, hash: fingerprintBytes(disk) };
    return {
      calls,
      deps: {
        file: "/d/a.pen",
        source: "save" as const,
        readDisk: async () => disk,
        probeMemory: async () => countReply(3),
        readFresh: async () => disk,
        getBaseline: () => base,
        isRefusalPending: () => false,
        send: async () => {
          calls.push("send:save");
          return "Saved /d/a.pen";
        },
        isConfirmed: (raw: string) => raw === "Saved /d/a.pen",
        readAfterSave: async () => disk,
        adoptBaseline: () => {},
        canRecreate,
        retryDelayMs: 1,
      },
    };
  };

  test("a present, unchanged file whose path is no longer canonical refuses as unknown-baseline/recreate-path-changed; nothing is sent", async () => {
    const m = mk(async () => false);
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "unknown-baseline", cause: "recreate-path-changed" });
    expect(m.calls).not.toContain("send:save");
    // the text must not claim the file was removed: it was not
    expect(r.message).toMatch(/directory on the way to it is now a link or has moved/);
    expect(r.message).not.toMatch(/was removed from disk/);
  });
  test("a canonical path saves as before, and the check ran", async () => {
    let asked = 0;
    const m = mk(async () => {
      asked++;
      return true;
    });
    expect(await runGuardedSave(m.deps)).toMatchObject({ saved: true });
    expect(asked).toBe(1);
  });
  test("a thrown check is a refusal, never an allow", async () => {
    const m = mk(async () => {
      throw new Error("EACCES");
    });
    expect(await runGuardedSave(m.deps)).toMatchObject({ refused: true, cause: "recreate-path-changed" });
    expect(m.calls).not.toContain("send:save");
  });
});
