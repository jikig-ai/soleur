import { describe, test, expect, beforeEach, afterEach } from "vitest";
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
import { LEGAL_DOC_SHAS } from "../lib/legal/legal-doc-shas";

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
//
// Each test gets its own fresh tempdir via beforeEach so cases stay
// order-independent and safe under concurrent execution.

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

  beforeEach(() => {
    tmp = makeTempCopy();
  });

  afterEach(() => {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
  });

  test("EXPECTED_COUNT in the bash script matches the TS const-only file", () => {
    // The bash sentinel `EXPECTED_COUNT=9` and the TS-side glob meta-
    // assertion (legal-doc-consistency.test.ts) must stay in lockstep with
    // the TS const file. There are 8 entries in LEGAL_DOC_SHAS plus T&C
    // (whose SHA lives in tc-version.ts) → 9 total docs. If a future
    // operator adds a doc to LEGAL_DOC_SHAS but forgets the bash sentinel,
    // this assertion fails loudly.
    const script = readFileSync(
      resolve(REPO_ROOT, SCRIPT_REL),
      "utf8",
    );
    const m = script.match(/^EXPECTED_COUNT=(\d+)\b/m);
    expect(m, "EXPECTED_COUNT declaration not found in script").not.toBeNull();
    const expectedFromScript = Number(m![1]);
    expect(expectedFromScript).toBe(Object.keys(LEGAL_DOC_SHAS).length + 1);
  });

  test("baseline: unmodified tree exits 0 with no glob-empty warning", () => {
    const r = runGuard(tmp);
    expect(r.status, `stderr:\n${r.stderr}`).toBe(0);
    // Positive control against a vacuous-pass shape where the glob silently
    // returned zero entries (e.g. cpSync path typo): the script would print
    // a "::warning::...glob returned 0..." line and still exit 0. Pinning
    // this assertion makes the baseline gating-non-primitive.
    expect(r.stderr).not.toMatch(/glob returned 0\b/);
  });

  test("mirror prose drift on T&C is detected (body-equivalence step)", () => {
    // Inject a sentinel paragraph into the T&C Eleventy mirror's content
    // section. The sentinel is plain prose so the collapse +
    // normalize_plugin pipeline preserves it; the canonical does not
    // contain it, so the body-SHA comparison must fail.
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
    expect(r.stderr).toMatch(/terms-and-conditions body drift/);
  });

  test("stale SHA literal on a non-T&C doc is detected", () => {
    const canonicalPath = join(tmp, "docs/legal/cookie-policy.md");
    const original = readFileSync(canonicalPath, "utf8");
    // Append a single newline byte — alters sha256 deterministically but
    // does not introduce a structurally meaningful diff. The script's
    // SHA-pin step still fires; the literal is now stale.
    writeFileSync(canonicalPath, original + "\n");

    const r = runGuard(tmp);
    expect(r.status, `stdout:\n${r.stdout}\nstderr:\n${r.stderr}`).toBe(1);
    // Pin to the full stale-literal message to distinguish from the
    // "literal missing" failure (different drift class with the same
    // doc name in the output).
    expect(r.stderr).toMatch(
      /content changed but LEGAL_DOC_SHAS\["cookie-policy"\] is stale/,
    );
  });

  test("stale SHA literal on T&C without TC_VERSION bump is detected", () => {
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
    // Guard against a future regression where the lockstep sentinel
    // accidentally trips body-equivalence (e.g., if a new `collapse` sed
    // rule matches the sentinel literal) — the failure should be SHA-
    // stale, not body drift.
    expect(r.stderr).not.toMatch(/terms-and-conditions body drift/);
  });

  test("missing LEGAL_DOC_SHAS literal for a doc is detected", () => {
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
    expect(r.stderr).toMatch(/LEGAL_DOC_SHAS literal for "disclaimer" not found/);
  });
});
