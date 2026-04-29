// Deploy-pipeline-fix drift gate — verifies plugins/soleur/skills/ship/SKILL.md
// Phase 5.5 contains the canonical gate definition (#2881) and the file+systemd
// post-apply verification contract (#3034). The gate is documentation that an
// LLM agent reads at /ship time; the only safety net against drift between the
// gate's bash array, its regex, and apps/web-platform/infra/server.tf's
// triggers_replace block is this test file.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync, existsSync } from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const POSTMERGE_RUNBOOK = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/postmerge/references/deploy-status-debugging.md",
);
const SERVER_TF = resolve(REPO_ROOT, "apps/web-platform/infra/server.tf");

const GATE_HEADING = "### Deploy Pipeline Fix Drift Gate";
const NEXT_HEADING = "### Retroactive Gate Application";

// The 4 trigger files MUST match apps/web-platform/infra/server.tf
// `terraform_data.deploy_pipeline_fix.triggers_replace.sha256(join(",",...))`.
// If a future infra refactor changes the basenames, this fixture, the gate's
// bash array, and the gate's regex must update together.
const TRIGGER_FILES = [
  "apps/web-platform/infra/ci-deploy.sh",
  "apps/web-platform/infra/webhook.service",
  "apps/web-platform/infra/cat-deploy-state.sh",
  "apps/web-platform/infra/hooks.json.tmpl",
];

function buildTriggerRegex(files: string[]): RegExp {
  const basenames = files.map((p) => {
    const base = p.replace(/^apps\/web-platform\/infra\//, "");
    return base.replace(/[.+*?^$(){}|[\]\\]/g, "\\$&");
  });
  return new RegExp(`^apps/web-platform/infra/(${basenames.join("|")})$`);
}

let SHIP_TEXT: string;
let GATE_SECTION: string;

function getGateSection(text: string): string {
  const start = text.indexOf(GATE_HEADING);
  const end = text.indexOf(NEXT_HEADING, start);
  if (start === -1 || end === -1 || end <= start) {
    throw new Error(
      `Gate section boundary not found: start=${start} end=${end}. ` +
        `The "${GATE_HEADING}" or "${NEXT_HEADING}" heading was renamed/removed.`,
    );
  }
  return text.slice(start, end);
}

beforeAll(() => {
  if (!existsSync(SHIP_SKILL)) {
    throw new Error(`ship SKILL.md not found at ${SHIP_SKILL}`);
  }
  SHIP_TEXT = readFileSync(SHIP_SKILL, "utf8");
  GATE_SECTION = getGateSection(SHIP_TEXT);
});

describe("ship/SKILL.md Deploy Pipeline Fix Drift Gate — structure", () => {
  test("Phase 5.5 contains the gate subsection heading", () => {
    expect(SHIP_TEXT).toMatch(/^### Deploy Pipeline Fix Drift Gate/m);
  });

  test("gate cites the per-command authorization rule", () => {
    expect(GATE_SECTION).toContain("hr-menu-option-ack-not-prod-write-auth");
  });

  test("gate references both issues (#2881 and #3034)", () => {
    expect(GATE_SECTION).toContain("#2881");
    expect(GATE_SECTION).toContain("#3034");
  });
});

describe("ship/SKILL.md gate — verbatim canonical command + verification", () => {
  test("emits the canonical terraform apply command verbatim", () => {
    expect(GATE_SECTION).toContain(
      "terraform apply -target=terraform_data.deploy_pipeline_fix -input=true",
    );
    expect(GATE_SECTION).toContain("doppler run -p soleur -c prd_terraform");
  });

  test("emits the file+systemd verification contract", () => {
    expect(GATE_SECTION).toMatch(/sha256sum\s+\/usr\/local\/bin\/ci-deploy\.sh/);
    expect(GATE_SECTION).toMatch(/systemctl is-active webhook/);
    expect(GATE_SECTION).toContain("terraform output -raw server_ip");
  });

  test("has a headless-mode fallback chain (gh pr comment → stderr → step summary)", () => {
    expect(GATE_SECTION).toMatch(/gh pr comment/);
    expect(GATE_SECTION).toMatch(/GITHUB_STEP_SUMMARY/);
    expect(GATE_SECTION).toMatch(/>&2/);
  });
});

describe("ship/SKILL.md gate — bash-array + regex match canonical fixture", () => {
  // P2-1 from code-quality review: a typo in the gate's array or regex must
  // fail the suite, not pass silently. Parse the gate's actual bash literal
  // from SKILL.md and compare to TRIGGER_FILES + buildTriggerRegex.

  test("gate's DEPLOY_PIPELINE_FIX_TRIGGERS bash array matches TRIGGER_FILES token-for-token", () => {
    const arrayMatch = GATE_SECTION.match(
      /DEPLOY_PIPELINE_FIX_TRIGGERS=\(\s*\n([\s\S]*?)\n\s*\)/,
    );
    expect(arrayMatch).not.toBeNull();
    const lines = arrayMatch![1]
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0);
    const parsed = lines.map((l) => {
      const m = l.match(/^"([^"]+)"$/);
      if (!m) {
        throw new Error(`bash array entry not double-quoted: ${l}`);
      }
      return m[1];
    });
    expect(parsed).toEqual(TRIGGER_FILES);
  });

  test("gate's DPF_REGEX literal equals buildTriggerRegex(TRIGGER_FILES).source", () => {
    const regexMatch = GATE_SECTION.match(/DPF_REGEX='([^']+)'/);
    expect(regexMatch).not.toBeNull();
    // Bash regex literals don't escape forward slashes; JS's RegExp.source does.
    // Normalize the JS source for the comparison.
    const expected = buildTriggerRegex(TRIGGER_FILES).source.replace(/\\\//g, "/");
    expect(regexMatch![1]).toBe(expected);
  });
});

describe("Trigger regex behavior (derived from canonical array)", () => {
  const regex = buildTriggerRegex(TRIGGER_FILES);

  test.each(TRIGGER_FILES)("matches trigger file: %s", (path) => {
    expect(regex.test(path)).toBe(true);
  });

  test.each([
    "apps/web-platform/app/page.tsx",
    "plugins/soleur/skills/ship/SKILL.md",
    "apps/web-platform/infra/cloud-init.yml",
    "apps/web-platform/infra/main.tf",
    "knowledge-base/project/plans/something.md",
  ])("does NOT match unrelated path: %s", (path) => {
    expect(regex.test(path)).toBe(false);
  });

  test.each([
    "apps/web-platform/infra/ci-deploy.sh.bak",
    "apps/web-platform/infra/ci-deploy.sh.j2",
    "apps/web-platform/infra/webhook.service.disabled",
    "apps/web-platform/infra/cat-deploy-state.sh~",
    "apps/web-platform/infra/hooks.json.tmpl.old",
  ])("does NOT match suffixed variant: %s", (path) => {
    expect(regex.test(path)).toBe(false);
  });

  test("rejects paths with leading/trailing whitespace (anchored end-of-line)", () => {
    expect(regex.test(" apps/web-platform/infra/ci-deploy.sh")).toBe(false);
    expect(regex.test("apps/web-platform/infra/ci-deploy.sh ")).toBe(false);
  });

  test("rejects paths with carriage-return (defensive against \\r\\n diff output)", () => {
    expect(regex.test("apps/web-platform/infra/ci-deploy.sh\r")).toBe(false);
  });
});

describe("Trigger array and server.tf are in sync (path-glob verification)", () => {
  let serverTf: string;

  beforeAll(() => {
    expect(existsSync(SERVER_TF)).toBe(true);
    serverTf = readFileSync(SERVER_TF, "utf8");
  });

  test.each(TRIGGER_FILES)("trigger file exists at documented path: %s", (path) => {
    expect(existsSync(resolve(REPO_ROOT, path))).toBe(true);
  });

  test.each(TRIGGER_FILES)(
    "server.tf references basename via file()/templatefile(): %s",
    (path) => {
      const basename = path.split("/").pop()!;
      // Three direct triggers are referenced via file("${path.module}/<basename>")
      // inside the triggers_replace block. The fourth (hooks.json.tmpl) is rendered
      // by templatefile("${path.module}/hooks.json.tmpl", ...) in a locals block
      // and folded into triggers_replace via local.hooks_json. Either form proves
      // terraform tracks the file's contents.
      const escaped = basename.replace(/[.+*?^$(){}|[\]\\]/g, "\\$&");
      const referenced = new RegExp(
        `(file|templatefile)\\(\\s*"\\$\\{path\\.module\\}/${escaped}"`,
      ).test(serverTf);
      expect(referenced).toBe(true);
    },
  );
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
