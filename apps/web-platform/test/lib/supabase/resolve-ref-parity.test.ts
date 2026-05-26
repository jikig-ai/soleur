// Parity test for apps/web-platform/lib/supabase/resolve-ref.ts (TS) and
// apps/web-platform/scripts/lib/supabase-ref-resolver.sh (bash).
//
// Both implementations gate the security-critical anchored regex
// `^[a-z0-9]{20}\.supabase\.co$`. A future widening of the canonical
// (preview envs, .io support) must update both sides in lockstep — this
// test catches drift.
//
// Bash invocation is isolated in a subprocess via spawnSync; the
// vi.mock("node:dns") factory does NOT leak into the child. Mirrors the
// existing PATH-shimmed fake-dig pattern from supabase-ref-resolver.test.sh
// (T5 / T6).

import { spawnSync } from "node:child_process";
import { writeFileSync, mkdtempSync, chmodSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { resolveCnameSpy } = vi.hoisted(() => ({
  resolveCnameSpy: vi.fn<(host: string) => Promise<string[]>>(),
}));

vi.mock("node:dns", () => ({
  promises: { resolveCname: resolveCnameSpy },
}));

// Resolve the bash helper path from the test file's location so the
// invocation does not depend on process.cwd() (vitest is launched from
// apps/web-platform/, but a future config change could move it).
const BASH_HELPER = resolve(
  __dirname,
  "..",
  "..",
  "..",
  "scripts",
  "lib",
  "supabase-ref-resolver.sh",
);

interface Fixture {
  name: string;
  url: string;
  // CNAME mock: array returned by dnsPromises.resolveCname (TS side) and
  // the line printed by fake `dig` (bash side, with trailing dot preserved).
  // null means resolveCname throws (NXDOMAIN); fake dig prints nothing.
  cname: string[] | null;
  // Expected ref or null (rejected by both impls).
  expected: string | null;
  // Whether the fast path applies (canonical URL) — if true, no `dig` call
  // is made on either side.
  fastPath: boolean;
}

const FIXTURES: Fixture[] = [
  {
    name: "canonical *.supabase.co URL",
    url: "https://abcdefghijklmnopqrst.supabase.co",
    cname: null,
    expected: "abcdefghijklmnopqrst",
    fastPath: true,
  },
  {
    name: "canonical with trailing slash",
    url: "https://abcdefghijklmnopqrst.supabase.co/",
    cname: null,
    expected: "abcdefghijklmnopqrst",
    fastPath: true,
  },
  {
    name: "custom domain CNAME fallback",
    url: "https://api.example.com",
    cname: ["abcdefghijklmnopqrst.supabase.co."],
    expected: "abcdefghijklmnopqrst",
    fastPath: false,
  },
  {
    name: "subdomain-bypass guard rejects <ref>.supabase.co.evil.com",
    url: "https://api.attacker.com",
    cname: ["abcdefghijklmnopqrst.supabase.co.evil.com."],
    expected: null,
    fastPath: false,
  },
  {
    name: "uppercase host rejected",
    url: "https://ABCDEFGHIJKLMNOPQRST.supabase.co",
    cname: null,
    expected: null,
    fastPath: false,
  },
  {
    name: "empty string rejected",
    url: "",
    cname: null,
    expected: null,
    fastPath: false,
  },
  // Length-anchor fixtures — both sides MUST require exactly 20 chars on
  // the fast path. Without these, a bash regex of `[a-z0-9]+` would silently
  // accept off-spec hosts the TS form rejects (subdomain-bypass guard
  // bypassed via short/long ref). The CNAME fallback also rejects them.
  {
    name: "sub-20-char host rejected (length anchor)",
    url: "https://abc.supabase.co",
    cname: null,
    expected: null,
    fastPath: false,
  },
  {
    name: "21-char host rejected (length anchor)",
    url: "https://abcdefghijklmnopqrstu.supabase.co",
    cname: null,
    expected: null,
    fastPath: false,
  },
];

// Write a fake `dig` to a tempdir that prints the fixture's CNAME line for
// any invocation. Returns the tempdir path; callers add it to PATH.
function makeFakeDig(cnameLine: string | null): string {
  const dir = mkdtempSync(join(tmpdir(), "resolve-ref-parity-"));
  const script = [
    "#!/usr/bin/env bash",
    cnameLine == null ? "exit 0" : `printf '%s\\n' '${cnameLine}'`,
    "",
  ].join("\n");
  const digPath = join(dir, "dig");
  writeFileSync(digPath, script);
  chmodSync(digPath, 0o755);
  return dir;
}

function callBash(url: string, fakeDigDir: string | null): {
  rc: number;
  stdout: string;
} {
  const pathPrefix = fakeDigDir == null ? "" : `${fakeDigDir}:`;
  const env = {
    ...process.env,
    PATH: `${pathPrefix}${process.env.PATH ?? ""}`,
  };
  // `--` separates bash options from positional args; `"$1"` is `url`.
  const result = spawnSync(
    "bash",
    [
      "-c",
      `source "${BASH_HELPER}"; resolve_supabase_ref "$1"`,
      "--",
      url,
    ],
    { env, encoding: "utf8" },
  );
  return { rc: result.status ?? 1, stdout: (result.stdout ?? "").trim() };
}

let tempDirs: string[] = [];

beforeEach(() => {
  resolveCnameSpy.mockReset();
  tempDirs = [];
});

afterEach(() => {
  for (const dir of tempDirs) {
    rmSync(dir, { recursive: true, force: true });
  }
});

describe("resolve-ref bash/TS parity", () => {
  // Sanity guard — confirm the bash helper exists at the resolved path. A
  // future repo restructure that moves the script would otherwise produce
  // confusing per-case failures.
  it("bash helper is locatable from the test's path", () => {
    const probe = spawnSync("test", ["-f", BASH_HELPER], { encoding: "utf8" });
    expect(probe.status).toBe(0);
  });

  for (const fx of FIXTURES) {
    it(`parity: ${fx.name}`, async () => {
      // TS side — mock `resolveCname` to mirror the fixture's CNAME shape.
      if (fx.cname == null) {
        // Either fast path (no CNAME call) or NXDOMAIN-on-call. Throwing
        // covers the empty-string case (early return) and the uppercase
        // case (regex match fails before any DNS call) without coupling
        // the test to those branches.
        resolveCnameSpy.mockRejectedValue(
          Object.assign(new Error("ENOTFOUND"), { code: "ENOTFOUND" }),
        );
      } else {
        resolveCnameSpy.mockResolvedValue(fx.cname);
      }
      const { resolveSupabaseRef } = await import("@/lib/supabase/resolve-ref");
      const tsResult = await resolveSupabaseRef(fx.url);

      // Bash side — write a fake `dig` to a tempdir per fixture (the line
      // printed mirrors the TS-side CNAME mock, since the bash form pipes
      // `dig +short CNAME ... | head -1` and reads one line).
      const fakeDigDir = makeFakeDig(fx.cname?.[0] ?? null);
      tempDirs.push(fakeDigDir);
      const bash = callBash(fx.url, fakeDigDir);
      const bashResult: string | null =
        bash.rc === 0 && bash.stdout !== "" ? bash.stdout : null;

      // Assert rc + stdout shape explicitly so a future refactor that
      // accidentally `return 0`s on a parse miss (or `return 1`s with
      // stdout-leaked output) fails this gate. data-integrity-guardian
      // F2 — without this, the parity contract collapses both axes
      // into `null` and silently passes regression rc drift.
      if (fx.expected === null) {
        expect(bash.rc, `bash rc for ${fx.name}`).toBe(1);
      } else {
        expect(bash.rc, `bash rc for ${fx.name}`).toBe(0);
        expect(bash.stdout, `bash stdout for ${fx.name}`).toBe(fx.expected);
      }
      expect(tsResult, `TS for ${fx.name}`).toBe(fx.expected);
      expect(bashResult, `bash for ${fx.name}`).toBe(fx.expected);
    });
  }
});
