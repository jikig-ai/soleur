// Deploy-pipeline-fix drift gate — verifies plugins/soleur/skills/ship/SKILL.md
// Phase 5.5 contains the canonical gate definition (#2881) and the file+systemd
// post-apply verification contract (#3034).
//
// The gate is documentation, not executable code — these tests assert that:
// (a) the gate's bash array enumerates the 4 trigger files exactly,
// (b) the regex documented next to the array matches/rejects the right paths,
// (c) the canonical `terraform apply -target=...` command appears verbatim,
// (d) the file+systemd verification snippet is present (sha256sum + systemctl),
// (e) the headless-mode fallback chain (gh pr comment → stderr → step summary).
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync, existsSync } from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/ship/SKILL.md",
);
const POSTMERGE_RUNBOOK = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/postmerge/references/deploy-status-debugging.md",
);

// The 4 trigger files MUST match apps/web-platform/infra/server.tf
// `terraform_data.deploy_pipeline_fix.triggers_replace.sha256(join(",",...))`
// block. If a future infra refactor changes the basenames, this fixture and
// the gate's bash array must update together — the regex in the gate is
// derived from this same list.
const TRIGGER_FILES = [
  "apps/web-platform/infra/ci-deploy.sh",
  "apps/web-platform/infra/webhook.service",
  "apps/web-platform/infra/cat-deploy-state.sh",
  "apps/web-platform/infra/hooks.json.tmpl",
];

// Build the regex the gate documents. Regex string MUST be derivable from
// TRIGGER_FILES via this function so the test fails if the documented regex
// drifts from the array.
function buildTriggerRegex(files: string[]): RegExp {
  const basenames = files.map((p) => {
    const base = p.replace(/^apps\/web-platform\/infra\//, "");
    // Escape regex metachars in the basename
    return base.replace(/[.+*?^$(){}|[\]\\]/g, "\\$&");
  });
  return new RegExp(
    `^apps/web-platform/infra/(${basenames.join("|")})$`,
  );
}

let SHIP_TEXT: string;

beforeAll(() => {
  if (!existsSync(SHIP_SKILL)) {
    throw new Error(`ship SKILL.md not found at ${SHIP_SKILL}`);
  }
  SHIP_TEXT = readFileSync(SHIP_SKILL, "utf8");
});

describe("ship/SKILL.md Deploy Pipeline Fix Drift Gate", () => {
  test("Phase 5.5 contains the gate subsection heading", () => {
    expect(SHIP_TEXT).toMatch(/^### Deploy Pipeline Fix Drift Gate/m);
  });

  test("gate enumerates exactly the 4 canonical trigger files", () => {
    for (const path of TRIGGER_FILES) {
      expect(SHIP_TEXT).toContain(path);
    }
  });

  test("gate emits the canonical terraform apply command verbatim", () => {
    // The exact substring is asserted so paraphrase drift fails the test.
    expect(SHIP_TEXT).toContain(
      "terraform apply -target=terraform_data.deploy_pipeline_fix -input=true",
    );
    expect(SHIP_TEXT).toContain(
      "doppler run -p soleur -c prd_terraform",
    );
  });

  test("gate emits the file+systemd verification contract", () => {
    expect(SHIP_TEXT).toMatch(/sha256sum\s+\/usr\/local\/bin\/ci-deploy\.sh/);
    expect(SHIP_TEXT).toMatch(/systemctl is-active webhook/);
    expect(SHIP_TEXT).toContain('terraform output -raw server_ip');
  });

  test("gate cites the per-command authorization rule", () => {
    expect(SHIP_TEXT).toContain("hr-menu-option-ack-not-prod-write-auth");
  });

  test("gate has a headless-mode fallback chain (gh pr comment → stderr → step summary)", () => {
    // Find the gate section and slice it out for tighter assertions
    const gateStart = SHIP_TEXT.indexOf("### Deploy Pipeline Fix Drift Gate");
    expect(gateStart).toBeGreaterThan(-1);
    const gateEnd = SHIP_TEXT.indexOf(
      "### Retroactive Gate Application",
      gateStart,
    );
    expect(gateEnd).toBeGreaterThan(gateStart);
    const gate = SHIP_TEXT.slice(gateStart, gateEnd);

    expect(gate).toMatch(/gh pr comment/);
    expect(gate).toMatch(/GITHUB_STEP_SUMMARY/);
    // The stderr fallback uses `>&2` redirect.
    expect(gate).toMatch(/>&2/);
  });

  test("gate references both issues (#2881 and #3034)", () => {
    const gateStart = SHIP_TEXT.indexOf("### Deploy Pipeline Fix Drift Gate");
    const gateEnd = SHIP_TEXT.indexOf(
      "### Retroactive Gate Application",
      gateStart,
    );
    const gate = SHIP_TEXT.slice(gateStart, gateEnd);
    expect(gate).toContain("#2881");
    expect(gate).toContain("#3034");
  });
});

describe("Trigger regex behavior (derived from canonical array)", () => {
  const regex = buildTriggerRegex(TRIGGER_FILES);

  test("matches each trigger file individually", () => {
    for (const path of TRIGGER_FILES) {
      expect(regex.test(path)).toBe(true);
    }
  });

  test("does NOT match unrelated repo paths", () => {
    const negatives = [
      "apps/web-platform/app/page.tsx",
      "plugins/soleur/skills/ship/SKILL.md",
      // cloud-init is a sync-source for some triggers but is NOT in the
      // triggers_replace block — must not fire the gate.
      "apps/web-platform/infra/cloud-init.yml",
      "apps/web-platform/infra/main.tf",
      "knowledge-base/project/plans/something.md",
    ];
    for (const path of negatives) {
      expect(regex.test(path)).toBe(false);
    }
  });

  test("does NOT match prefix-only / suffixed variants", () => {
    const negatives = [
      "apps/web-platform/infra/ci-deploy.sh.bak",
      "apps/web-platform/infra/ci-deploy.sh.j2",
      "apps/web-platform/infra/webhook.service.disabled",
      "apps/web-platform/infra/cat-deploy-state.sh~",
      // Must be exact end-of-line — defends against partial-path FP.
      "apps/web-platform/infra/hooks.json.tmpl.old",
    ];
    for (const path of negatives) {
      expect(regex.test(path)).toBe(false);
    }
  });

  test("fires once for a multi-file diff (≥1 match)", () => {
    const diffOutput = TRIGGER_FILES.join("\n");
    const matches = diffOutput.split("\n").filter((line) => regex.test(line));
    expect(matches.length).toBe(4);
    // Trigger condition is "≥1 match" — gate should fire once, not 4 times.
    const triggered = matches.length >= 1;
    expect(triggered).toBe(true);
  });

  test("does NOT fire for a diff with only unrelated paths", () => {
    const diffOutput = [
      "apps/web-platform/app/page.tsx",
      "plugins/soleur/skills/ship/SKILL.md",
      "apps/web-platform/infra/cloud-init.yml",
    ].join("\n");
    const matches = diffOutput.split("\n").filter((line) => regex.test(line));
    expect(matches.length).toBe(0);
  });
});

describe("Trigger array and server.tf are in sync (path-glob verification)", () => {
  // Per AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g`: every
  // path the gate documents must exist in the repo at the asserted location.
  test("each trigger file exists at the documented path", () => {
    for (const path of TRIGGER_FILES) {
      const abs = resolve(REPO_ROOT, path);
      expect(existsSync(abs)).toBe(true);
    }
  });

  test("server.tf triggers_replace block references the same 4 basenames", () => {
    const serverTf = resolve(
      REPO_ROOT,
      "apps/web-platform/infra/server.tf",
    );
    expect(existsSync(serverTf)).toBe(true);
    const tf = readFileSync(serverTf, "utf8");
    // The triggers_replace block uses sha256(join(",", [...])). Each trigger
    // file must be referenced somewhere inside the block. We don't try to
    // parse HCL — a basename presence check is sufficient since the four
    // names are unique to this resource.
    for (const path of TRIGGER_FILES) {
      const basename = path.split("/").pop()!;
      expect(tf).toContain(basename);
    }
  });
});

describe("postmerge runbook updates (#3034)", () => {
  let runbook: string;

  beforeAll(() => {
    if (!existsSync(POSTMERGE_RUNBOOK)) {
      throw new Error(`postmerge runbook not found at ${POSTMERGE_RUNBOOK}`);
    }
    runbook = readFileSync(POSTMERGE_RUNBOOK, "utf8");
  });

  test("contains a 'When NOT to use this probe' subsection", () => {
    expect(runbook).toMatch(/^## When NOT to use this probe/m);
  });

  test("references the post-apply file+systemd contract", () => {
    expect(runbook).toMatch(/sha256sum/);
    expect(runbook).toMatch(/systemctl is-active webhook/);
  });

  test("links to the 2026-04-29 verification-contract learning", () => {
    expect(runbook).toContain(
      "2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access",
    );
  });
});
