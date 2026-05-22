import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";

// Drift-class smoke test for apps/web-platform/scripts/check-tc-document-sha.sh
// (the all-9-legal-docs SHA-pin guard). Verifies the script catches the
// #4289-class drift pattern: a canonical edit that ships without the paired
// SHA-literal refresh.
//
// The script is invoked under a tempdir copy of just the four file trees it
// reads (docs/legal/, plugins/soleur/docs/pages/legal/, apps/web-platform/
// lib/legal/, apps/web-platform/scripts/) so each test case can mutate
// freely without touching the real working tree. spawnSync is invoked with
// an explicit args array — no shell, no string interpolation, per AC7.

const REPO_ROOT = resolve(__dirname, "../../..");
const SCRIPT_REL = "apps/web-platform/scripts/check-tc-document-sha.sh";

function makeTempCopy(): string {
  const tmp = mkdtempSync(join(tmpdir(), "legal-doc-shas-guard-"));
  for (const sub of [
    "docs/legal",
    "plugins/soleur/docs/pages/legal",
    "apps/web-platform/lib/legal",
    "apps/web-platform/scripts",
  ]) {
    cpSync(resolve(REPO_ROOT, sub), join(tmp, sub), { recursive: true });
  }
  return tmp;
}

function runGuard(cwd: string): { status: number | null; stderr: string; stdout: string } {
  const result = spawnSync("bash", [SCRIPT_REL], {
    cwd,
    encoding: "utf8",
    // Strip GITHUB_BASE_REF so the T&C bypass cannot fire in the test env;
    // the bypass requires a real git history we are not setting up.
    env: { ...process.env, GITHUB_BASE_REF: "" },
  });
  return {
    status: result.status,
    stderr: result.stderr ?? "",
    stdout: result.stdout ?? "",
  };
}

describe("check-tc-document-sha.sh: drift-class smoke", () => {
  let tmp: string;

  beforeAll(() => {
    tmp = makeTempCopy();
  });

  afterAll(() => {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
  });

  test("baseline: unmodified tree exits 0", () => {
    const r = runGuard(tmp);
    expect(r.status, `stderr:\n${r.stderr}`).toBe(0);
  });

  test("mirror prose drift on T&C is detected (body-equivalence step)", () => {
    // Restore baseline, then inject a sentinel paragraph into the T&C
    // Eleventy mirror's content section. The sentinel is plain prose so
    // the collapse + normalize_plugin pipeline preserves it; the canonical
    // does not contain it, so the body-SHA comparison must fail.
    rmSync(tmp, { recursive: true, force: true });
    tmp = makeTempCopy();
    const mirrorPath = join(tmp, "plugins/soleur/docs/pages/legal/terms-and-conditions.md");
    const original = readFileSync(mirrorPath, "utf8");
    const sentinel = "\n\nSENTINEL-MIRROR-DRIFT-FOR-TEST: this paragraph is only present in the test mutation.\n";
    // Inject before the closing </section> of the content block.
    const mutated = original.replace(
      /<\/section>\s*$/,
      `${sentinel}\n</section>\n`,
    );
    expect(mutated, "mutation must change the mirror").not.toBe(original);
    writeFileSync(mirrorPath, mutated);

    const r = runGuard(tmp);
    expect(r.status, `stdout:\n${r.stdout}\nstderr:\n${r.stderr}`).toBe(1);
    expect(r.stderr).toMatch(/T&C body drift/);
  });

  test("stale SHA literal on a non-T&C doc is detected", () => {
    rmSync(tmp, { recursive: true, force: true });
    tmp = makeTempCopy();
    const canonicalPath = join(tmp, "docs/legal/cookie-policy.md");
    const original = readFileSync(canonicalPath, "utf8");
    // Append a single newline byte — alters sha256 deterministically but
    // does not introduce a structurally meaningful diff. The script's
    // SHA-pin step still fires; the literal is now stale.
    writeFileSync(canonicalPath, original + "\n");

    const r = runGuard(tmp);
    expect(r.status, `stdout:\n${r.stdout}\nstderr:\n${r.stderr}`).toBe(1);
    expect(r.stderr).toMatch(/cookie-policy/);
    expect(r.stderr).toMatch(/LEGAL_DOC_SHAS/);
  });

  test("stale SHA literal on T&C without TC_VERSION bump is detected", () => {
    rmSync(tmp, { recursive: true, force: true });
    tmp = makeTempCopy();
    const canonicalPath = join(tmp, "docs/legal/terms-and-conditions.md");
    const mirrorPath = join(tmp, "plugins/soleur/docs/pages/legal/terms-and-conditions.md");
    // Mutate both canonical AND mirror in lockstep so body-equivalence
    // still passes (Step 1) — the failure must come from the SHA-stale
    // path (Step 3), not from body drift.
    const originalCanonical = readFileSync(canonicalPath, "utf8");
    const originalMirror = readFileSync(mirrorPath, "utf8");
    const sentinel = "\n\nSENTINEL-CANONICAL-EDIT-FOR-TEST.\n";
    writeFileSync(canonicalPath, originalCanonical + sentinel);
    // Insert the same sentinel inside the mirror's content section so
    // normalize_plugin + collapse produces an equivalent body.
    writeFileSync(
      mirrorPath,
      originalMirror.replace(/<\/section>\s*$/, `${sentinel}\n</section>\n`),
    );

    const r = runGuard(tmp);
    expect(r.status, `stdout:\n${r.stdout}\nstderr:\n${r.stderr}`).toBe(1);
    expect(r.stderr).toMatch(/TC_DOCUMENT_SHA literal is stale/);
  });

  test("missing LEGAL_DOC_SHAS literal for a doc is detected", () => {
    rmSync(tmp, { recursive: true, force: true });
    tmp = makeTempCopy();
    const literalPath = join(tmp, "apps/web-platform/lib/legal/legal-doc-shas.ts");
    const original = readFileSync(literalPath, "utf8");
    // Drop the disclaimer entry — comment out the key/value pair.
    const mutated = original.replace(
      /"disclaimer":\s*\n\s*"[0-9a-f]{64}",/,
      '// removed for test',
    );
    expect(mutated, "mutation must drop the disclaimer entry").not.toBe(original);
    writeFileSync(literalPath, mutated);

    const r = runGuard(tmp);
    expect(r.status, `stdout:\n${r.stdout}\nstderr:\n${r.stderr}`).toBe(1);
    expect(r.stderr).toMatch(/disclaimer/);
    expect(r.stderr).toMatch(/literal/i);
  });
});
