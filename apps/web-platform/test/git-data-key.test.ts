// The git-data SSH keys as the container receives them (#8211 PR-G). Doppler holds each key
// as a multi-line value; ci-deploy.sh's `--format docker` + `--env-file` path leaves ONE
// line with literal backslash-n pairs, which ssh cannot parse (`Load key ... invalid
// format`, then `Permission denied (publickey)`; rehearsal-2 run 40305860011).
import { afterEach, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  GIT_DATA_KEY_ENV_NAMES,
  gitDataKeyFileContents,
  normalizeGitDataKey,
  readGitDataKeyEnv,
} from "../server/git-data-key";
import { HAS_SSH_KEYGEN, keyParses, makeMultilineKey, PEM_BEGIN, PEM_END, toDockerForm } from "./helpers/git-data-key-fixture";

const KEY = makeMultilineKey(); // ends with "\n"
const KEY_BODY = KEY.trim();
const DOCKER = toDockerForm(KEY);

afterEach(() => vi.unstubAllEnvs());

describe("normalizeGitDataKey", () => {
  it("fixture shape: a multi-line key and its one-line docker form carrying literal backslash-n pairs", () => {
    expect(KEY_BODY.split("\n").length).toBeGreaterThanOrEqual(3);
    expect(DOCKER.includes("\n")).toBe(false);
    expect(DOCKER.split("\\n").length).toBe(KEY_BODY.split("\n").length);
  });

  it("a docker-format one-line key becomes the exact multi-line key (same line count, same bytes)", () => {
    const out = normalizeGitDataKey(DOCKER);
    expect(out).toBe(KEY_BODY);
    expect(out.split("\n").length).toBe(KEY_BODY.split("\n").length);
  });

  it("a trailing literal backslash-n pair (docker form that kept the final newline) yields no extra blank line", () => {
    expect(normalizeGitDataKey(`${DOCKER}\\n`)).toBe(KEY_BODY);
  });

  it("a real-newline key passes through byte-identical (apart from trimmed ends)", () => {
    expect(normalizeGitDataKey(KEY_BODY)).toBe(KEY_BODY);
    expect(normalizeGitDataKey(`\n  ${KEY}\n\n`)).toBe(KEY_BODY);
  });

  it("a single-line value with no literal pair is returned unchanged", () => {
    expect(normalizeGitDataKey("transport-key")).toBe("transport-key");
  });

  it("empty, whitespace-only, unset stay absent (empty string)", () => {
    for (const v of ["", " ", "\n\t \n", undefined, null]) expect(normalizeGitDataKey(v)).toBe("");
  });

  it("a value with real newlines AND a literal backslash-n inside (a comment) is NOT altered", () => {
    const withComment = `${PEM_BEGIN}\nQUJD\n${PEM_END}\n# note\\nkept`;
    expect(normalizeGitDataKey(withComment)).toBe(withComment);
    expect(normalizeGitDataKey(withComment)).toContain("note\\nkept");
  });

  it("is idempotent", () => {
    const once = normalizeGitDataKey(DOCKER);
    expect(normalizeGitDataKey(once)).toBe(once);
  });
});

describe("readGitDataKeyEnv", () => {
  it.each(GIT_DATA_KEY_ENV_NAMES)("%s: the docker-format env value reads back as the multi-line key", (name) => {
    vi.stubEnv(name, DOCKER);
    expect(readGitDataKeyEnv(name)).toBe(KEY_BODY);
  });
  it.each(GIT_DATA_KEY_ENV_NAMES)("%s: unset or blank reads as empty", (name) => {
    vi.stubEnv(name, "   ");
    expect(readGitDataKeyEnv(name)).toBe("");
    vi.stubEnv(name, "");
    expect(readGitDataKeyEnv(name)).toBe("");
  });
});

describe("gitDataKeyFileContents", () => {
  it("ends with exactly one LF and is parseable by ssh-keygen when the input was the docker form", () => {
    const out = gitDataKeyFileContents(DOCKER);
    expect(out.endsWith("\n")).toBe(true);
    expect(out.endsWith("\n\n")).toBe(false);
    expect(out).toBe(`${KEY_BODY}\n`);
    expect(out.split("\n").length - 1).toBe(KEY_BODY.split("\n").length); // line count, LF-terminated
    if (HAS_SSH_KEYGEN) {
      expect(keyParses(out)).toBe(true);
      // The failure the fix removes: the raw docker form is NOT a parseable key.
      expect(keyParses(`${DOCKER}\n`)).toBe(false);
    }
  });
});

describe.skipIf(!HAS_SSH_KEYGEN)("probe and app agree on the key bytes (infra/git-data-container-probe.sh)", () => {
  const PROBE = path.resolve(__dirname, "../infra/git-data-container-probe.sh");

  // Run the REAL probe body to the point where it has written the key file, with an inner
  // ssh stub that copies the file it was handed to a path we read back. The stub answers with
  // the wrapper prefix so the body exits 0.
  function runProbeWithKey(envKey: string): { rc: number; written: string | null; out: string } {
    const dir = mkdtempSync(path.join(tmpdir(), "gdk-probe-"));
    try {
      const wt = path.join(dir, "wt");
      const tmp = path.join(dir, "tmp");
      const copy = path.join(dir, "copy");
      spawnSync("mkdir", ["-p", wt, tmp]);
      const stub = path.join(dir, "ssh-stub");
      writeFileSync(
        stub,
        '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -i ] && cp "$2" "$GDK_COPY"; shift; done\n' +
          "echo 'remote: git-data transport: repo does not exist' >&2\nexit 1\n",
        { mode: 0o755 },
      );
      const r = spawnSync("sh", [PROBE], {
        env: {
          PATH: "/usr/bin:/bin",
          TMPDIR: tmp,
          WORKTREE_ROOT: wt,
          GIT_TRANSPORT_SSH_PRIVATE_KEY: envKey,
          GIT_DATA_SSH_HOST_KEY: "ssh-ed25519 AAAA",
          GIT_DATA_SSH_HOST: "10.0.1.20",
          GDCP_SSH: stub,
          GDK_COPY: copy,
        } as unknown as NodeJS.ProcessEnv,
        input: "",
        encoding: "utf8",
      });
      return {
        rc: r.status ?? -1,
        written: existsSync(copy) ? readFileSync(copy, "utf8") : null,
        out: `${r.stdout}${r.stderr}`,
      };
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }

  it("same docker-format fixture: the probe writes the same bytes the app writes, and it parses", () => {
    const probe = runProbeWithKey(DOCKER);
    expect(probe.rc).toBe(0);
    expect(probe.written).toBe(gitDataKeyFileContents(DOCKER));
    expect(probe.written).toBe(`${KEY_BODY}\n`);
  });

  it("same real-newline fixture: both write the key unchanged", () => {
    const probe = runProbeWithKey(KEY_BODY);
    expect(probe.rc).toBe(0);
    expect(probe.written).toBe(gitDataKeyFileContents(KEY_BODY));
    expect(probe.written).toBe(`${KEY_BODY}\n`);
  });

  it("a real-newline value carrying a literal backslash-n in a trailing line is left alone by both", () => {
    const odd = `${KEY_BODY}\n# c\\nd`;
    expect(normalizeGitDataKey(odd)).toBe(odd);
    const probe = runProbeWithKey(odd);
    // Whether ssh-keygen tolerates the trailing line decides 0 vs 31; either way the probe
    // never rewrote the backslash-n into a newline.
    if (probe.written === null) expect(probe.rc).toBe(31);
    else expect(probe.written).toBe(`${odd}\n`);
    expect(probe.out).not.toContain(KEY_BODY.split("\n")[1]);
  });
});
