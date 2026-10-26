import { describe, test, expect } from "bun:test";
import {
  shouldSkipSave,
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
} from "../skills/pencil-setup/scripts/pencil-save-gate.mjs";

// T2.3 — Auto-save after a failed mutation is the mechanism that produced
// 0-byte .pen files. The adapter's registerMutatingTool and open_document
// unconditionally enqueued save() after a batch_design/open. If the
// mutation errored, pencil's save() ran against a stale or uninitialized
// state and wrote nothing. The gate decides: do NOT save when the
// preceding mutation produced an isError=true classification.

describe("shouldSkipSave", () => {
  test("skips when last classification isError=true", () => {
    expect(shouldSkipSave({ isError: true, text: "Invalid properties: foo" })).toBe(true);
  });

  test("allows save when last classification isError=false", () => {
    expect(shouldSkipSave({ isError: false, text: 'node0="abc"' })).toBe(false);
  });

  test("skips on auth-failure classification", () => {
    expect(shouldSkipSave({ isError: true, text: "Unauthorized" })).toBe(true);
  });

  test("allows save when no prior classification exists (first call)", () => {
    expect(shouldSkipSave(null)).toBe(false);
    expect(shouldSkipSave(undefined)).toBe(false);
  });

  test("allows save when classification is missing isError field", () => {
    // Defensive: if the caller forgets to pass the classification shape,
    // don't block the save (preserves existing behavior).
    expect(shouldSkipSave({ text: "hello" } as any)).toBe(false);
  });

  test("skips when isError is truthy but not strictly true", () => {
    // Defensive: accept any truthy isError value.
    expect(shouldSkipSave({ isError: 1, text: "bad" } as any)).toBe(true);
  });
});

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
    const m = refusalMessage({ file: "/d/a.pen", source: "save", diskCount: 3, memoryCount: 0 });
    expect(m).toContain("REFUSED save:");
    expect(m).toContain("/d/a.pen");
    expect(m).toMatch(/not modified/i);
    expect(m).toContain("open_document");
    expect(m).toMatch(/new file path/i);
    expect(m).toMatch(/do not delete or recreate/i);
  });
  test("names exactly one next step per cause, and always forbids delete-to-bypass", () => {
    const empty = refusalMessage({ file: "/d/a.pen", source: "save", diskCount: 3, memoryCount: 0 });
    const unreadable = refusalMessage({ file: "/d/a.pen", source: "save", diskCount: 3, memoryCount: null, memoryReason: "boom" });
    const garbage = refusalMessage({ file: "/d/a.pen", source: "save", diskCount: DISK_UNRECOGNIZED, memoryCount: 2 });
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
    const m = refusalMessage({ file: "/d/a.pen", source: "auto-save", diskCount: 3, memoryCount: 0 });
    expect(m).toMatch(/in memory but not (persisted|saved)/i);
    expect(m).toMatch(/lost on the next open_document/i);
  });
});


describe("refusalMessage: the stale family (#11168)", () => {
  const stale = refusalMessage({ file: "/d/a.pen", source: "auto-save", stale: "stale" });
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
  test("`changed` is accepted as an alias of stale (the observability probe passes it)", () => {
    expect(refusalMessage({ file: "x.pen", source: "save", stale: "changed" })).toBe(
      refusalMessage({ file: "x.pen", source: "save", stale: "stale" })
    );
  });
  test("each state has its own wording, distinct from the others", () => {
    const missing = refusalMessage({ file: "/d/a.pen", source: "save", stale: "missing" });
    const unconfirmed = refusalMessage({ file: "/d/a.pen", source: "save", stale: "unknown-baseline", cause: "unconfirmed-save" });
    const postRead = refusalMessage({ file: "/d/a.pen", source: "save", stale: "unknown-baseline", cause: "post-save-read-failed" });
    const capture = refusalMessage({ file: "/d/a.pen", source: "save", stale: "unknown-baseline", cause: "capture-failed", detail: "ELOOP" });
    const pending = refusalMessage({ file: "/d/a.pen", source: "save", stale: "refusal-pending" });
    const restarted = refusalMessage({ file: "/d/a.pen", source: "save", stale: "refusal-pending", restarted: true });
    expect(missing).toMatch(/removed|no longer exists/i);
    expect(missing).not.toMatch(/changed on disk since/);
    expect(unconfirmed).toMatch(/last save was not confirmed/i);
    expect(unconfirmed).not.toMatch(/changed on disk since/);
    expect(postRead).toMatch(/could not be read back/i);
    expect(capture).toContain("ELOOP");
    expect(restarted).toMatch(/session restarted/i);
    expect(restarted).toMatch(/earlier edits were discarded/i);
    expect(pending).not.toMatch(/session restarted/i);
    const all = [stale, missing, unconfirmed, postRead, capture, pending, restarted];
    for (const m of all) {
      expect(m).toContain("REFUSED save:");
      expect(m.match(/Next step:/g)!.length).toBe(1);
      expect(m).toMatch(/do not delete or recreate/i);
    }
    expect(new Set(all).size).toBe(all.length);
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

describe("decideStale: only an exact missing/hash match allows", () => {
  const H1 = { tag: "hash", hash: "1".repeat(64) } as const;
  const H2 = { tag: "hash", hash: "2".repeat(64) } as const;
  const MISSING = { tag: "missing" } as const;
  const dec = (baseline: any, current: any, refusalPending = false) => decideStale({ baseline, current, refusalPending });

  test("hash baseline: equal hash allows, different hash is stale, missing is missing", () => {
    expect(dec(H1, H1).allow).toBe(true);
    const stale = dec(H1, H2);
    expect(stale).toMatchObject({ allow: false, code: "stale", arm: true });
    expect(stale.baselineHash).toBe(H1.hash);
    expect(stale.diskHash).toBe(H2.hash);
    expect(dec(H1, MISSING)).toMatchObject({ allow: false, code: "missing", arm: true });
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

  test("a file removed behind a hash baseline refuses as missing (the first read is already null)", async () => {
    const m = mk({ disk: null, fresh: null, baseline: H(penWith(2)) });
    const r = await runGuardedSave(m.deps);
    expect(r).toMatchObject({ refused: true, code: "missing", arm: true });
    expect(m.calls).not.toContain("send:save");
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
