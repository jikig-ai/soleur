// Unit tests for the git-lock marker telemetry hook (#4826 observability follow-up):
// the pure extractor, tool_response coercion, and the PostToolUse hook's fail-open
// classification (wedge → error, diag-only → warn, non-Bash → no-op).
import { describe, test, expect } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";
import {
  extractGitLockMarkers,
  toolResponseToText,
  createGitLockMarkerHook,
} from "../server/git-lock-marker-telemetry";

const DIAG =
  "SOLEUR_GIT_LOCK_DIAG file=.git/config.lock type=chardevice owner=nobody perms=666 mtime=1 age=1140 mount=tmpfs rdev=1:3 whiteout=no";
const UNREMOVABLE =
  'SOLEUR_GIT_LOCK_UNREMOVABLE file=.git/config.lock type=chardevice rdev=1:3 errno=none reason=non-regular-lock hint="observed non-regular config lock"';
const WEDGE =
  "worktree wedge: could not apply shared-config prerequisites in .git (see errors above).";
const TEMP_WEDGED =
  'SOLEUR_GIT_LOCK_TEMP_WEDGED file=config.soleur-tmp type=temp-write-failed reason=lockless-temp-unwritable hint="glob mask"';

describe("extractGitLockMarkers", () => {
  test("pulls each marker sentinel out of surrounding bash noise", () => {
    const text = ["Preparing worktree", DIAG, "  updating files", UNREMOVABLE, "done"].join("\n");
    const markers = extractGitLockMarkers(text);
    expect(markers.map((m) => m.line)).toEqual([DIAG, UNREMOVABLE]);
  });

  test("classifies UNREMOVABLE / TEMP_WEDGED / 'worktree wedge' as wedged; DIAG as not", () => {
    expect(extractGitLockMarkers(DIAG)[0]?.wedged).toBe(false);
    expect(extractGitLockMarkers(UNREMOVABLE)[0]?.wedged).toBe(true);
    expect(extractGitLockMarkers(WEDGE)[0]?.wedged).toBe(true);
    expect(extractGitLockMarkers(TEMP_WEDGED)[0]?.wedged).toBe(true);
  });

  test("returns [] for output with no markers, and for empty input", () => {
    expect(extractGitLockMarkers("just some normal git output\nProsuming worktree")).toEqual([]);
    expect(extractGitLockMarkers("")).toEqual([]);
  });

  test("does not match a marker token embedded mid-line (anchored to line start)", () => {
    expect(extractGitLockMarkers("echo SOLEUR_GIT_LOCK_DIAG is the sentinel name")).toEqual([]);
  });

  test("bounds output: caps the number of markers even on a flood", () => {
    const flood = Array.from({ length: 500 }, () => UNREMOVABLE).join("\n");
    expect(extractGitLockMarkers(flood).length).toBeLessThanOrEqual(12);
  });

  test("truncates an over-long marker line", () => {
    const long = `${UNREMOVABLE} ${"x".repeat(2000)}`;
    const [m] = extractGitLockMarkers(long);
    expect(m.line.length).toBeLessThanOrEqual(601);
    expect(m.line.endsWith("…")).toBe(true);
  });
});

describe("toolResponseToText", () => {
  test("passes a string through", () => {
    expect(toolResponseToText(DIAG)).toBe(DIAG);
  });
  test("joins stdout + stderr on an object response", () => {
    expect(toolResponseToText({ stdout: "out", stderr: "err" })).toBe("out\nerr");
  });
  test("flattens an array of text content blocks", () => {
    expect(toolResponseToText([{ type: "text", text: DIAG }, { type: "text", text: "x" }])).toBe(
      `${DIAG}\nx`,
    );
  });
  test("unknown shapes yield empty string (no markers)", () => {
    expect(toolResponseToText(42)).toBe("");
    expect(toolResponseToText(null)).toBe("");
    expect(toolResponseToText({ foo: 1 })).toBe("");
  });
});

describe("drift guard: every sentinel the shell script emits is mirrored", () => {
  // The extractor's MARKER_RE is a hand-maintained copy of the sentinel names in
  // worktree-manager.sh. If the script gains/renames a SOLEUR_GIT_LOCK_* sentinel and
  // this copy is not updated, the new wedge signal would go silently unmirrored — the
  // exact blindness this feature closes. Pin the two in sync: every `echo "SOLEUR_GIT_LOCK_*`
  // literal in the script must be matched by extractGitLockMarkers.
  test("extractor matches every SOLEUR_GIT_LOCK_* sentinel echoed by worktree-manager.sh", () => {
    const script = readFileSync(
      join(
        __dirname,
        "../../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh",
      ),
      "utf8",
    );
    const sentinels = [...script.matchAll(/echo "(SOLEUR_GIT_LOCK_[A-Z_]+)/g)].map((m) => m[1]);
    const unique = [...new Set(sentinels)];
    expect(unique.length).toBeGreaterThan(0); // non-vacuous: the script DOES emit sentinels
    for (const name of unique) {
      const sample = `${name} file=.git/config.lock type=chardevice rdev=1:3`;
      expect(
        extractGitLockMarkers(sample).length,
        `sentinel ${name} echoed by worktree-manager.sh is not matched by the telemetry extractor — update MARKER_RE`,
      ).toBe(1);
    }
  });
});

describe("createGitLockMarkerHook", () => {
  const call = (input: unknown) =>
    createGitLockMarkerHook("/ws/abc")(input as never, undefined, {} as never);

  test("is a no-op for non-Bash tools", async () => {
    const out = await call({ tool_name: "Read", tool_response: UNREMOVABLE });
    expect(out).toEqual({});
  });

  test("is a no-op for Bash output with no markers", async () => {
    const out = await call({ tool_name: "Bash", tool_response: "Preparing worktree\ndone" });
    expect(out).toEqual({});
  });

  test("returns {} (observe-only) when markers ARE present", async () => {
    const out = await call({ tool_name: "Bash", tool_response: `${DIAG}\n${UNREMOVABLE}` });
    expect(out).toEqual({});
  });

  test("never throws — fail-open on a malformed input", async () => {
    const weird = { get tool_name() { throw new Error("boom"); } };
    await expect(call(weird)).resolves.toEqual({});
  });
});
