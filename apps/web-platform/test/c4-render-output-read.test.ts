// Guard 5 (#8696), direct (non-production) path: the host never follows,
// over-reads, or blocks on what likec4 leaves in its output dir. (The
// sandboxed path has no host output dir: the model comes back over a capped
// stdout — c4-render-sandbox.test.ts.) REAL filesystem, no mocks — the
// properties under test (O_NOFOLLOW, O_NONBLOCK, fstat type/size) are kernel
// behaviour a mock cannot exhibit.
import { describe, it, expect, afterEach } from "vitest";
import { execFileSync } from "node:child_process";
import {
  closeSync,
  constants,
  mkdirSync,
  mkdtempSync,
  openSync,
  rmSync,
  symlinkSync,
  truncateSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { RAW_MODEL_READ_CAP, readRenderOutput } from "@/server/c4-render";
import { C4_MODEL_JSON } from "@/lib/c4-constants";

const VALID_MODEL = JSON.stringify({ elements: { a: { id: "a" } }, views: { index: {} } });
const OUT = C4_MODEL_JSON;

let dirs: string[] = [];
let fifos: string[] = [];
function tmp(): string {
  const d = mkdtempSync(join(tmpdir(), "c4-out-read-"));
  dirs.push(d);
  return d;
}

afterEach(() => {
  // A reader blocked on a FIFO would hang the worker: open the write end
  // non-blocking and close it so any such reader sees EOF.
  for (const f of fifos) {
    try {
      closeSync(openSync(f, constants.O_WRONLY | constants.O_NONBLOCK));
    } catch {
      // no reader attached
    }
  }
  fifos = [];
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
  dirs = [];
});

describe("readRenderOutput (Guard 5)", () => {
  it("must-PASS: a regular file holding a valid model is returned", async () => {
    const d = tmp();
    writeFileSync(join(d, OUT), VALID_MODEL);
    expect(await readRenderOutput(d)).toEqual({ ok: true, raw: VALID_MODEL });
  });

  it("row 1/2: a symlink to a sentinel holding a valid model is rejected, sentinel bytes never returned", async () => {
    const d = tmp();
    const sentinelDir = tmp();
    const sentinel = join(sentinelDir, "other-tenant-model.json");
    writeFileSync(sentinel, VALID_MODEL.replace('"a"', '"SENTINEL"'));
    symlinkSync(sentinel, join(d, OUT));
    const res = await readRenderOutput(d);
    expect(res).toEqual({ ok: false, why: "symlink" });
    expect(JSON.stringify(res)).not.toContain("SENTINEL");
  });

  it("row 3: a FIFO is rejected without blocking", async () => {
    const d = tmp();
    const f = join(d, OUT);
    execFileSync("mkfifo", [f]);
    fifos.push(f);
    const res = await Promise.race([
      readRenderOutput(d),
      new Promise<"blocked">((r) => setTimeout(() => r("blocked"), 1_000)),
    ]);
    expect(res).toEqual({ ok: false, why: "not a regular file" });
  });

  it("row 4: a file one byte over the cap is rejected without being read", async () => {
    const d = tmp();
    const f = join(d, OUT);
    writeFileSync(f, "");
    truncateSync(f, RAW_MODEL_READ_CAP + 1); // sparse: no RAM or disk spent
    expect(await readRenderOutput(d)).toEqual({ ok: false, why: "too large" });
  });

  it("must-PASS: a directory named model.likec4.json is rejected, not thrown", async () => {
    const d = tmp();
    mkdirSync(join(d, OUT));
    expect(await readRenderOutput(d)).toEqual({ ok: false, why: "not a regular file" });
  });

  it("an absent output is rejected as absent", async () => {
    expect(await readRenderOutput(tmp())).toEqual({ ok: false, why: "absent" });
  });
});
