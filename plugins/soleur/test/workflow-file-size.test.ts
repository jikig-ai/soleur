// GitHub refuses to parse a workflow file larger than "500 KB" — the run is created with ZERO jobs,
// concludes `failure`, and the only diagnostic is the run page's banner ("Workflow file exceeds the
// maximum allowed size of 500 KB"); the API exposes no validation message. Measured 2026-09-19 on
// `apply-web-platform-infra.yml`: 510,313 bytes parsed (run 35394758942, 21 jobs), 513,306 bytes
// did not (run 35431689935, 0 jobs — every push to main after #8312 ran nothing). The ceiling is
// therefore in (510,313, 513,306]; 500 × 1024 = 512,000 is the value consistent with GitHub's
// wording and is what this test pins. Nothing else in CI reads the file size — actionlint, the
// YAML parsers and every content pin were green while the file could not run.
//
// A HARD limit, not a ratchet: the point is that the merge-time push cannot silently disable the
// production apply route. The structural remedy (the file is 48% comment prose and has grown
// 3–5 KB per infra PR since #8216) is tracked by #8363; when this test fires, reclaim bytes
// before merging rather than raising the number — the number is GitHub's, not ours.
import { test, expect, describe } from "bun:test";
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dir, "..", "..", "..");
const WORKFLOWS = join(REPO_ROOT, ".github", "workflows");
// GitHub's ceiling, bracketed by the two measured runs above.
export const GITHUB_WORKFLOW_FILE_LIMIT = 512_000;

describe("every workflow file is small enough for GitHub to parse", () => {
  const files = readdirSync(WORKFLOWS).filter((f) => /\.ya?ml$/.test(f));
  test("the workflow directory is populated", () => {
    expect(files.length).toBeGreaterThan(0);
  });
  for (const f of files) {
    test(`${f} is at most ${GITHUB_WORKFLOW_FILE_LIMIT} bytes`, () => {
      const size = statSync(join(WORKFLOWS, f)).size;
      const headroom = GITHUB_WORKFLOW_FILE_LIMIT - size;
      expect(
        size,
        `${f} is ${size} bytes, ${-headroom} over GitHub's ${GITHUB_WORKFLOW_FILE_LIMIT}-byte workflow-file ceiling. ` +
          `GitHub creates the run with zero jobs and no API-visible error (run 35431689935). ` +
          `Reclaim bytes (relocate prose, dedupe, or split the file) — do not raise the limit.`,
      ).toBeLessThanOrEqual(GITHUB_WORKFLOW_FILE_LIMIT);
    });
  }
});
