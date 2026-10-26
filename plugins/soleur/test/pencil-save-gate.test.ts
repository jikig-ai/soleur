import { describe, test, expect } from "bun:test";
import {
  shouldSkipSave,
  diskTopLevelCount,
  memoryTopLevelCount,
  decideSave,
  refusalMessage,
  runGuardedSave,
  DISK_UNRECOGNIZED,
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

describe("memoryTopLevelCount", () => {
  test("counts nodes from a {nodes: []} batch_get result", () => {
    expect(memoryTopLevelCount(JSON.stringify({ nodes: [{ id: "a" }, { id: "b" }] }))).toBe(2);
    expect(memoryTopLevelCount(JSON.stringify({ nodes: [] }))).toBe(0);
  });
  test("counts a bare array result", () => {
    expect(memoryTopLevelCount(JSON.stringify([{ id: "a" }]))).toBe(1);
  });
  test("null when the shape cannot be determined", () => {
    expect(memoryTopLevelCount("")).toBeNull();
    expect(memoryTopLevelCount(null)).toBeNull();
    expect(memoryTopLevelCount("Error: boom")).toBeNull();
    expect(memoryTopLevelCount('{"other":1}')).toBeNull();
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

describe("runGuardedSave (dependency-injected)", () => {
  const mk = (disk: string | null, mem: string | null) => {
    const calls: string[] = [];
    return {
      calls,
      deps: {
        file: "/d/a.pen",
        source: "save" as const,
        readDisk: async () => {
          calls.push("readDisk");
          return disk;
        },
        probeMemory: async () => {
          calls.push("probeMemory");
          return mem;
        },
        send: async () => {
          calls.push("send:save");
          return "saved";
        },
      },
    };
  };

  test("non-empty disk + empty memory: probe happens, no save is sent", async () => {
    const { calls, deps } = mk(penWith(3), JSON.stringify({ nodes: [] }));
    const r = await runGuardedSave(deps);
    expect(r.saved).toBe(false);
    expect(r.refused).toBe(true);
    expect(r.message).toContain("REFUSED save:");
    expect(calls).toEqual(["readDisk", "probeMemory"]);
  });

  test("the memory check precedes the save when both run", async () => {
    const { calls, deps } = mk(penWith(3), JSON.stringify({ nodes: [{ id: "a" }] }));
    const r = await runGuardedSave(deps);
    expect(r.saved).toBe(true);
    expect(calls).toEqual(["readDisk", "probeMemory", "send:save"]);
  });

  test("missing disk target saves without probing memory", async () => {
    const { calls, deps } = mk(null, null);
    const r = await runGuardedSave(deps);
    expect(r.saved).toBe(true);
    expect(calls).toEqual(["readDisk", "send:save"]);
  });

  test("collapsed 96-byte target saves (nothing to protect)", async () => {
    const { calls, deps } = mk(penWith(0), JSON.stringify({ nodes: [] }));
    const r = await runGuardedSave(deps);
    expect(r.saved).toBe(true);
    expect(calls[calls.length - 1]).toBe("send:save");
  });

  test("undeterminable memory over a non-empty target refuses", async () => {
    const { calls, deps } = mk(penWith(2), "Error: boom");
    const r = await runGuardedSave(deps);
    expect(r.refused).toBe(true);
    expect(calls).not.toContain("send:save");
  });

  test("a probe that THROWS refuses and carries the cause", async () => {
    const calls: string[] = [];
    const r = await runGuardedSave({
      file: "/d/a.pen",
      source: "save",
      readDisk: async () => penWith(3),
      probeMemory: async () => {
        throw new Error("pencil exited during a command");
      },
      send: async () => {
        calls.push("send:save");
        return "saved";
      },
    });
    expect(r.refused).toBe(true);
    expect(r.message).toContain("pencil exited during a command");
    expect(calls).toEqual([]);
  });

  test("a disk read that THROWS refuses (an I/O error is not 'missing')", async () => {
    const calls: string[] = [];
    const r = await runGuardedSave({
      file: "/d/a.pen",
      source: "save",
      readDisk: async () => {
        throw new Error("EACCES: permission denied");
      },
      probeMemory: async () => JSON.stringify({ nodes: [{ id: "a" }] }),
      send: async () => {
        calls.push("send:save");
        return "saved";
      },
    });
    expect(r.refused).toBe(true);
    expect(r.message).toContain("EACCES");
    expect(calls).toEqual([]);
  });

  test("an unrecognized target refuses without probing memory", async () => {
    const { calls, deps } = mk("{not json", JSON.stringify({ nodes: [{ id: "a" }] }));
    const r = await runGuardedSave(deps);
    expect(r.refused).toBe(true);
    expect(calls).toEqual(["readDisk"]);
  });
});
