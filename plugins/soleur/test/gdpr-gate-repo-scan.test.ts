import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";

// Test suite for `/soleur:gdpr-gate --repo-scan` defenses D1-D5.
//
// The script under test resolves SKILL.md and path-denylist.txt as siblings
// of itself, so tests run the *real* script binary while pointing `cwd` at a
// sandbox git repo populated with mock files. `git ls-files` then reports
// the sandbox's contents; the deny-list and canonical regex still come from
// the real Soleur tree.

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SKILL_DIR = resolve(REPO_ROOT, "plugins/soleur/skills/gdpr-gate");
const SKILL_MD = resolve(SKILL_DIR, "SKILL.md");
const REPO_SCAN_SH = resolve(SKILL_DIR, "scripts/repo-scan.sh");
const PATH_DENYLIST = resolve(SKILL_DIR, "scripts/path-denylist.txt");

const CANONICAL_REGEX_LITERAL =
  "apps/web-platform/supabase/migrations/";

function gitCleanEnv(
  overrides: Record<string, string> = {},
): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (!k.startsWith("GIT_") && v !== undefined) env[k] = v;
  }
  // Always start without CI; tests opt-in by passing CI in `overrides`.
  delete env.CI;
  delete env.GDPR_GATE_REPO_SCAN_ALLOW_PATHS;
  for (const [k, v] of Object.entries(overrides)) env[k] = v;
  return env;
}

function createSandboxRepo(files: string[]): string {
  const dir = mkdtempSync(join(tmpdir(), "gdpr-repo-scan-"));
  const env = gitCleanEnv();
  Bun.spawnSync(["git", "init", "-q", dir], {
    env,
    stdout: "ignore",
    stderr: "ignore",
  });
  for (const rel of files) {
    const abs = join(dir, rel);
    mkdirSync(dirname(abs), { recursive: true });
    writeFileSync(abs, "// synthesized fixture\n");
  }
  // Add to index so ls-files -c picks them up.
  Bun.spawnSync(["git", "-C", dir, "add", "."], {
    env,
    stdout: "ignore",
    stderr: "ignore",
  });
  return dir;
}

function runScan(
  cwd: string,
  envOverrides: Record<string, string> = {},
): { exitCode: number; stdout: string; stderr: string } {
  const result = Bun.spawnSync(["bash", REPO_SCAN_SH], {
    cwd,
    env: gitCleanEnv(envOverrides),
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    exitCode: result.exitCode ?? -1,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

describe("gdpr-gate --repo-scan: file scaffold", () => {
  test("scripts/repo-scan.sh exists", () => {
    expect(existsSync(REPO_SCAN_SH)).toBe(true);
  });

  test("scripts/path-denylist.txt exists", () => {
    expect(existsSync(PATH_DENYLIST)).toBe(true);
  });
});

describe("D1 — deny-list blocks .env* and secrets/", () => {
  let sandbox: string;

  beforeEach(() => {
    sandbox = createSandboxRepo([
      // Canonical-regex matches that should NOT be denied
      "apps/web-platform/lib/auth/dev-mode.ts",
      "regular.sql",
      // Canonical-regex matches that SHOULD be denied
      "apps/web-platform/lib/auth/secrets/api.ts",
      "apps/web-platform/supabase/migrations/.env",
    ]);
  });

  afterEach(() => {
    rmSync(sandbox, { recursive: true, force: true });
  });

  test("non-denied paths appear on stdout", () => {
    const { exitCode, stdout } = runScan(sandbox);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("apps/web-platform/lib/auth/dev-mode.ts");
    expect(stdout).toContain("regular.sql");
  });

  test("deny-listed paths are excluded from stdout", () => {
    const { stdout } = runScan(sandbox);
    expect(stdout).not.toContain(
      "apps/web-platform/lib/auth/secrets/api.ts",
    );
    expect(stdout).not.toContain(
      "apps/web-platform/supabase/migrations/.env",
    );
  });

  test("blocked paths emit `# blocked: <path>` audit line on stderr", () => {
    const { stderr } = runScan(sandbox);
    expect(stderr).toContain(
      "# blocked: apps/web-platform/lib/auth/secrets/api.ts",
    );
    expect(stderr).toContain(
      "# blocked: apps/web-platform/supabase/migrations/.env",
    );
  });
});

describe("D3.bypass-typo — non-blocked path in allow-list exits 1", () => {
  let sandbox: string;

  beforeEach(() => {
    sandbox = createSandboxRepo([
      "apps/web-platform/lib/auth/dev-mode.ts",
      "README.md",
    ]);
  });

  afterEach(() => {
    rmSync(sandbox, { recursive: true, force: true });
  });

  test("README.md (real file, not deny-listed) → exit 1 with non-blocked message", () => {
    const { exitCode, stderr } = runScan(sandbox, {
      GDPR_GATE_REPO_SCAN_ALLOW_PATHS: "README.md",
    });
    expect(exitCode).toBe(1);
    expect(stderr).toContain("bypass references non-blocked path: README.md");
  });
});

describe("D3.bypass-coincidental-match — deny-pattern match but file missing exits 1", () => {
  let sandbox: string;

  beforeEach(() => {
    sandbox = createSandboxRepo([
      "apps/web-platform/lib/auth/dev-mode.ts",
    ]);
  });

  afterEach(() => {
    rmSync(sandbox, { recursive: true, force: true });
  });

  test("matches secrets/ pattern but does not exist → exit 1 with nonexistent message", () => {
    const { exitCode, stderr } = runScan(sandbox, {
      GDPR_GATE_REPO_SCAN_ALLOW_PATHS:
        "apps/web-platform/secrets/typo.json",
    });
    expect(exitCode).toBe(1);
    expect(stderr).toContain(
      "bypass references nonexistent path: apps/web-platform/secrets/typo.json",
    );
  });
});

describe("D3.ci-refusal — CI + ALLOW_PATHS exits 1 unconditionally", () => {
  let sandbox: string;

  beforeEach(() => {
    sandbox = createSandboxRepo(["apps/web-platform/lib/auth/dev-mode.ts"]);
  });

  afterEach(() => {
    rmSync(sandbox, { recursive: true, force: true });
  });

  test("CI=true + any ALLOW_PATHS → exit 1, refusal message on stderr", () => {
    const { exitCode, stderr } = runScan(sandbox, {
      CI: "true",
      GDPR_GATE_REPO_SCAN_ALLOW_PATHS:
        "apps/web-platform/supabase/migrations/.env",
    });
    expect(exitCode).toBe(1);
    expect(stderr).toContain(
      "allow-list bypass refused in CI environment",
    );
  });

  test("CI alone (no ALLOW_PATHS) does NOT trigger refusal", () => {
    // Sanity: the refusal must be conditional on BOTH being set.
    const { exitCode } = runScan(sandbox, { CI: "true" });
    expect(exitCode).toBe(0);
  });
});

describe("D4 — repo-scan.sh source contains no persistence write operators", () => {
  test("source has no write redirection to compliance-posture.md, fixtures, or __goldens__/", () => {
    const src = readFileSync(REPO_SCAN_SH, "utf8");
    // Forbidden destinations for D4 inline-only contract.
    const forbidden = [
      /(>>?|tee).*compliance-posture\.md/,
      /(>>?|tee).*__goldens__/,
      /(>>?|tee).*test\/fixtures/,
    ];
    for (const pat of forbidden) {
      expect(src).not.toMatch(pat);
    }
  });
});

describe("Sentinel — SKILL.md `## --repo-scan mode` section", () => {
  test("SKILL.md contains the literal sole-arg sentinel sentence", () => {
    const content = readFileSync(SKILL_MD, "utf8");
    expect(content).toContain("## --repo-scan mode");
    expect(content).toContain(
      "trimmed value equals **exactly** `--repo-scan`",
    );
  });

  test("SKILL.md repo-scan section names the load-bearing pieces", () => {
    const content = readFileSync(SKILL_MD, "utf8");
    expect(content).toContain("git ls-files -c -o --exclude-standard");
    expect(content).toContain("path-denylist.txt");
    expect(content).toContain("GDPR_GATE_REPO_SCAN_ALLOW_PATHS");
    expect(content).toContain("25 files per Haiku call");
  });
});

describe("Canonical-regex source-of-truth — repo-scan.sh extracts, never redefines", () => {
  test("script extracts regex from SKILL.md via awk (AC-PARITY-1, AC-SCRIPT-4)", () => {
    const src = readFileSync(REPO_SCAN_SH, "utf8");
    expect(src).toMatch(/awk[\s\S]{0,200}Path globs/);
  });

  test("script does NOT contain a second hardcoded copy of the canonical regex", () => {
    const src = readFileSync(REPO_SCAN_SH, "utf8");
    // The regex's `apps/web-platform/supabase/migrations/` literal appears
    // exactly once in SKILL.md and once in gdpr-gate.sh; if it shows up in
    // repo-scan.sh, the canonical-regex parity invariant is broken.
    expect(src).not.toContain(CANONICAL_REGEX_LITERAL);
  });
});

describe("Path deny-list file structure", () => {
  test("path-denylist.txt has the 7 patterns from the plan", () => {
    const content = readFileSync(PATH_DENYLIST, "utf8");
    const patterns = content
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0 && !l.startsWith("#"));
    // Plan §"Path deny-list" enumerates exactly 7 patterns.
    expect(patterns.length).toBe(7);
    // Spot-check the load-bearing pattern fragments.
    expect(content).toMatch(/\\\.env/);
    expect(content).toMatch(/secrets\//);
    expect(content).toMatch(/pem/);
    expect(content).toMatch(/__synthesized__|__goldens__|__snapshots__/);
  });
});
