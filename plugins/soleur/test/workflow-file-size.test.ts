// #8361 — workflow byte-size gate.
//
// GitHub refuses to START a run for a workflow file above its per-file limit, and it does so
// silently: the run has ZERO jobs (conclusion `startup_failure` on a workflow_dispatch, plain
// `failure` on a push), `gh run view` prints only "This run likely failed because of a workflow
// file issue", and the API exposes no message. Measured 2026-09-19 on
// apply-web-platform-infra.yml: 510,313 bytes ran (run 35431644262, 21 jobs), 513,306 bytes did
// not (runs 35431689935 / 35431766054, 0 jobs) — a bracket consistent with 512,000 and not with
// 500,000. https://docs.github.com/en/actions/reference/limits says "500 KB" and does not define
// KB; the bracket does.
//
// The gate must keep at least GATE_HEADROOM_BYTES under the limit (22,000 today) so a
// comment-only PR cannot cross it unnoticed: the file grew ~1.5 KB/commit on average over the
// 12 commits before #8361.
import { afterAll, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import {
  mkdirSync,
  readFileSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const WORKFLOWS_DIR = join(REPO_ROOT, ".github", "workflows");

// https://docs.github.com/en/actions/reference/limits — "A workflow file larger than 500 KB
// will not start runs." Pinned to the measured bracket above, not to a reading of "KB".
const GITHUB_WORKFLOW_FILE_LIMIT_BYTES = 512_000;
const WORKFLOW_FILE_GATE_BYTES = 490_000;
// Headroom the gate must keep under the GitHub limit. Weakening the gate past this requires
// editing BOTH constants — a two-line change a reviewer sees, not a one-number edit.
const GATE_HEADROOM_BYTES = 20_000;
// GitHub reads only top-level .github/workflows/; the live tree holds 80 .yml today. A walk
// that finds fewer than this is mis-resolved, and a passing gate over zero files is vacuous.
// The floor detects a WRONG directory; the conservation check against `git ls-files` in the
// live describe is what detects a walk that silently drops members of the RIGHT one.
const LIVE_MIN_FILES = 20;
const LIVE_SENTINEL = "apply-web-platform-infra.yml";
// The sentinel is by far the largest workflow (477 KB; the next is 162 KB). Pinning a size
// band turns the sentinel test from a name check into a proof that the walk saw the real
// directory — a decoy dir holding a 10-byte file of that name would pass a bare `toContain`.
// 200,000 stays decoy-proof and survives the planned per-target split (ADR-231 §3) taking the
// file well below its current size; retune if the split ever halves it again.
const LIVE_SENTINEL_MIN_BYTES = 200_000;

type Overage = { file: string; size: number; over: number };

/** The workflow files GitHub would read from `dir`: regular files named *.yml / *.yaml, sorted. */
function workflowFiles(dir: string, minFiles = 1): string[] {
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
function oversizedWorkflows(dir: string, gateBytes: number, minFiles = 1): Overage[] {
  return workflowFiles(dir, minFiles)
    .map((file) => ({ file, size: statSync(join(dir, file)).size }))
    .filter(({ size }) => size > gateBytes)
    .map(({ file, size }) => ({ file, size, over: size - gateBytes }));
}

const describeOverage = ({ file, size, over }: Overage) =>
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

  test("row 1: names the file, its size and the overage; the message is operator-readable", () => {
    const hit = oversizedWorkflows(fixture({ "a.yml": 100, [LIVE_SENTINEL]: G + 1 }), G);
    expect(hit).toEqual([{ file: LIVE_SENTINEL, size: G + 1, over: 1 }]);
    expect(describeOverage(hit[0])).toMatch(
      /^apply-web-platform-infra\.yml is 490001 bytes, 1 bytes over the 490000-byte gate \(GitHub refuses workflow files above 512000 bytes: https:\/\/docs\.github\.com\/en\/actions\/reference\/limits\)\. Relocate comment prose to a runbook \(precedent: knowledge-base\/engineering\/operations\/runbooks\/apply-web-platform-infra-job-rationale\.md\)\.$/,
    );
  });

  test("row 2: an empty dir throws rather than passing (guard's own dispatch)", () => {
    expect(() => oversizedWorkflows(fixture({}), G)).toThrow(
      "0 workflow files found, expected ≥ 1",
    );
  });

  test("row 3: the walk does not stop at the first member, and .yaml counts", () => {
    expect(oversizedWorkflows(fixture({ "a.yml": 100, "zz-mutant.yaml": G + 10_000 }), G)).toEqual(
      [{ file: "zz-mutant.yaml", size: G + 10_000, over: 10_000 }],
    );
  });

  test("row 4 (harness): the gate keeps its headroom under the GitHub limit", () => {
    expect(WORKFLOW_FILE_GATE_BYTES).toBeLessThanOrEqual(
      GITHUB_WORKFLOW_FILE_LIMIT_BYTES - GATE_HEADROOM_BYTES,
    );
  });

  test("row 5 (must-PASS): boundary inclusive; non-YAML, directories and symlinks are neither flagged nor counted", () => {
    const dir = fixture({ "edge.yml": G, "tiny.yaml": 1, "README.md": 600_000, "old.yaml.bak": 600_000 });
    // A directory named like a workflow must not contribute its inode size; a symlink is not a
    // regular file (Dirent.isFile() is false for it), so it is excluded from count and overage —
    // GitHub does not run symlinked workflow files either.
    mkdirSync(join(dir, "sub.yml"));
    writeFileSync(join(dir, "sub.yml", "inner"), "x".repeat(600_000));
    symlinkSync(join(dir, "edge.yml"), join(dir, "link.yml"));
    expect(oversizedWorkflows(dir, G, 2)).toEqual([]);
    // The second call proves README.md, old.yaml.bak, sub.yml/ and link.yml were excluded from
    // the COUNT, not merely from the overage list: exactly edge.yml and tiny.yaml remain.
    expect(() => oversizedWorkflows(dir, G, 3)).toThrow("2 workflow files found, expected ≥ 3");
  });
});

describe("live .github/workflows", () => {
  test("the walk resolves the real directory and finds the sentinel at its real size", () => {
    const files = workflowFiles(WORKFLOWS_DIR, LIVE_MIN_FILES);
    expect(files).toContain(LIVE_SENTINEL);
    expect(statSync(join(WORKFLOWS_DIR, LIVE_SENTINEL)).size).toBeGreaterThan(LIVE_SENTINEL_MIN_BYTES);
  });

  test("the walk sees every tracked top-level workflow file (conservation against git ls-files)", () => {
    // An independent enumerator: a walk that silently dropped members (a narrowed regex, a
    // truncated list) would still clear the floor and the sentinel; it cannot match git's view.
    // Locally, an UNTRACKED scratch *.yml in .github/workflows/ reds this as a name-list diff —
    // that is the walk seeing a file git does not, not a size failure.
    const tracked = execFileSync("git", ["-C", REPO_ROOT, "ls-files", "--", ".github/workflows"], {
      encoding: "utf8",
    })
      .split("\n")
      .filter((p) => p && dirname(p) === ".github/workflows" && /\.ya?ml$/.test(p))
      .map((p) => basename(p))
      .sort();
    expect(tracked.length).toBeGreaterThanOrEqual(LIVE_MIN_FILES);
    expect(workflowFiles(WORKFLOWS_DIR, LIVE_MIN_FILES)).toEqual(tracked);
  });

  test("every `# Rationale: <runbook> §<id>` pointer resolves to a `## <id>` heading in that runbook, and vice versa", () => {
    // The relocation convention (ADR-231 §2): a pointer's §<id> is an exact heading anchor.
    // A job rename or a runbook heading edit would otherwise dangle one side silently.
    const RUNBOOK = "knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md";
    const workflow = readFileSync(join(WORKFLOWS_DIR, LIVE_SENTINEL), "utf8");
    const pointerRe = new RegExp(`^\\s*# Rationale: ${RUNBOOK.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")} §(.+?)(?: \\(test-anchored lines kept below\\))?$`, "gm");
    const pointers = [...workflow.matchAll(pointerRe)].map((m) => m[1]).sort();
    const headings = [...readFileSync(join(REPO_ROOT, RUNBOOK), "utf8").matchAll(/^## (.+)$/gm)]
      .map((m) => m[1])
      .sort();
    expect(pointers.length).toBeGreaterThanOrEqual(10);
    expect(pointers).toEqual(headings);
  });

  test("no workflow file exceeds the gate", () => {
    expect(
      oversizedWorkflows(WORKFLOWS_DIR, WORKFLOW_FILE_GATE_BYTES, LIVE_MIN_FILES).map(describeOverage),
    ).toEqual([]);
  });
});
