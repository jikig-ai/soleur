// #8361 — workflow byte-size gate.
//
// GitHub refuses to START a run for a workflow file above its per-file limit, and it does so
// silently: the run is `startup_failure` with zero jobs, `gh run view` prints only "This run
// likely failed because of a workflow file issue", and the API exposes no message. Measured
// 2026-09-19 on apply-web-platform-infra.yml: 510,313 bytes ran (run 35431644262), 513,306
// bytes did not (runs 35431689935 / 35431766054) — a bracket consistent with 512,000 and not
// with 500,000. https://docs.github.com/en/actions/reference/limits says "500 KB" and does not
// define KB; the bracket does.
//
// The gate sits 22,000 bytes under the limit so a comment-only PR cannot cross it unnoticed:
// the file grew ~1.5 KB/commit on average (~3 KB on the last three) before #8361.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const WORKFLOWS_DIR = join(REPO_ROOT, ".github", "workflows");

// https://docs.github.com/en/actions/reference/limits — "A workflow file larger than 500 KB
// will not start runs." Pinned to the measured bracket above, not to a reading of "KB".
export const GITHUB_WORKFLOW_FILE_LIMIT_BYTES = 512_000;
export const WORKFLOW_FILE_GATE_BYTES = 490_000;
// Headroom the gate must keep under the GitHub limit. Weakening the gate past this requires
// editing BOTH constants — a two-line change a reviewer sees, not a one-number edit.
const GATE_HEADROOM_BYTES = 20_000;
// GitHub reads only top-level .github/workflows/; the live tree holds 80 .yml today. A walk
// that finds fewer than this is mis-resolved, and a passing gate over zero files is vacuous.
const LIVE_MIN_FILES = 20;
const LIVE_SENTINEL = "apply-web-platform-infra.yml";

/** The workflow files GitHub would read from `dir`: regular files named *.yml / *.yaml, sorted. */
export function workflowFiles(dir: string, minFiles = 1): string[] {
  const files = readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isFile() && /\.ya?ml$/.test(d.name))
    .map((d) => d.name)
    .sort();
  if (files.length < minFiles) {
    throw new Error(`${files.length} workflow files found, expected ≥ ${minFiles}`);
  }
  return files;
}

/** Every workflow file in `dir` strictly larger than `gateBytes`, with its overage. */
export function oversizedWorkflows(
  dir: string,
  gateBytes: number,
  minFiles = 1,
): Array<{ file: string; size: number; over: number }> {
  return workflowFiles(dir, minFiles)
    .map((file) => ({ file, size: statSync(join(dir, file)).size }))
    .filter(({ size }) => size > gateBytes)
    .map(({ file, size }) => ({ file, size, over: size - gateBytes }));
}

const describeOverage = ({ file, size, over }: { file: string; size: number; over: number }) =>
  `${file} is ${size} bytes, ${over} bytes over the ${WORKFLOW_FILE_GATE_BYTES}-byte gate ` +
  `(GitHub refuses workflow files above ${GITHUB_WORKFLOW_FILE_LIMIT_BYTES} bytes: ` +
  `https://docs.github.com/en/actions/reference/limits). Relocate comment prose to a runbook ` +
  `(precedent: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md).`;

const dirs: string[] = [];
function fixture(files: Record<string, number>): string {
  const dir = mkdtempSync(join(tmpdir(), "wf-size-"));
  dirs.push(dir);
  for (const [name, bytes] of Object.entries(files)) {
    writeFileSync(join(dir, name), "x".repeat(bytes));
  }
  return dir;
}
afterAll(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

describe("oversizedWorkflows (fixtures — one temp dir per row)", () => {
  const G = WORKFLOW_FILE_GATE_BYTES;

  test("row 1: names the file, its size and the overage", () => {
    expect(oversizedWorkflows(fixture({ "a.yml": 100, [LIVE_SENTINEL]: G + 1 }), G)).toEqual([
      { file: LIVE_SENTINEL, size: G + 1, over: 1 },
    ]);
  });

  test("row 2: an empty dir throws rather than passing (guard's own dispatch)", () => {
    expect(() => oversizedWorkflows(fixture({}), G)).toThrow(
      "0 workflow files found, expected ≥ 1",
    );
  });

  test("row 2b: 19 files under a floor of 20 throws naming the count", () => {
    const nineteen = Object.fromEntries([...Array(19)].map((_, i) => [`f${i}.yml`, 10]));
    expect(() => oversizedWorkflows(fixture(nineteen), G, 20)).toThrow(
      "19 workflow files found, expected ≥ 20",
    );
  });

  test("row 3: the walk does not stop at the first member, and .yaml counts", () => {
    expect(oversizedWorkflows(fixture({ "a.yml": 100, "zz-mutant.yaml": 500_000 }), G)).toEqual([
      { file: "zz-mutant.yaml", size: 500_000, over: 10_000 },
    ]);
  });

  test("row 4 (harness): the gate keeps its headroom under the GitHub limit", () => {
    expect(WORKFLOW_FILE_GATE_BYTES).toBeLessThanOrEqual(
      GITHUB_WORKFLOW_FILE_LIMIT_BYTES - GATE_HEADROOM_BYTES,
    );
  });

  test("row 5 (must-PASS): boundary inclusive; non-YAML neither flagged nor counted", () => {
    const dir = fixture({ "edge.yml": G, "tiny.yaml": 1, "README.md": 600_000 });
    expect(oversizedWorkflows(dir, G, 2)).toEqual([]);
    // The second call proves README.md was excluded from the COUNT, not merely from the overage list.
    expect(() => oversizedWorkflows(dir, G, 3)).toThrow("2 workflow files found, expected ≥ 3");
  });
});

describe("live .github/workflows", () => {
  test("the walk resolves the real directory and finds the sentinel", () => {
    expect(workflowFiles(WORKFLOWS_DIR, LIVE_MIN_FILES)).toContain(LIVE_SENTINEL);
  });

  test("no workflow file exceeds the gate", () => {
    expect(
      oversizedWorkflows(WORKFLOWS_DIR, WORKFLOW_FILE_GATE_BYTES, LIVE_MIN_FILES).map(describeOverage),
    ).toEqual([]);
  });
});
