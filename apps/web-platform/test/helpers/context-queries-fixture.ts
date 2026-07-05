// Shared git fixture for the context-queries hook tests (#6046, ADR-086).
//
// Both the behavioural unit test (`context-queries-hook.test.ts`) and the
// cross-language byte-parity test (`context-queries-shell-parity.test.ts`) build
// the SAME throwaway `git init` repo through this helper — the parity test reuses
// the unit test's fixture rather than standing up a second harness (deepen-plan
// simplicity finding). The hook's containment gate is `git ls-files` (committed
// files only), so behaviour must run against a real committed tree, not the
// ambient CWD (mirrors `.claude/hooks/skill-context-queries.test.sh`'s discipline
// + the CONTEXT_QUERIES_REPO_ROOT seam).
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

/** Toolchain probe — the fixture needs a working `git` binary. */
export function gitAvailable(): boolean {
  try {
    execFileSync("git", ["--version"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function git(root: string, args: string[]): void {
  execFileSync("git", ["-C", root, "-c", "user.email=t@t", "-c", "user.name=t", ...args], {
    stdio: "ignore",
  });
}

function writeSkill(root: string, name: string, frontmatterBody: string): void {
  const d = path.join(root, "plugins", "soleur", "skills", name);
  mkdirSync(d, { recursive: true });
  // Byte-for-byte the same SKILL.md shape the shell test's mk_skill() emits.
  const md = `---\nname: ${name}\ndescription: "test skill"\n${frontmatterBody}---\n\nBody.\n`;
  writeFileSync(path.join(d, "SKILL.md"), md);
}

/**
 * Build a committed git fixture and return its absolute root. Caller owns
 * teardown via {@link cleanupFixture}. The skill set mirrors the shell hook's
 * test fixture plus a >MAX_GLOB directory and a committed symlink for the
 * determinism + symlink-reject scenarios.
 */
export function buildFixture(): string {
  const root = mkdtempSync(path.join(tmpdir(), "ctxq-fix-"));

  mkdirSync(path.join(root, "knowledge-base", "marketing"), { recursive: true });
  mkdirSync(path.join(root, "knowledge-base", "deep"), { recursive: true });
  mkdirSync(path.join(root, "knowledge-base", "many"), { recursive: true });

  writeFileSync(path.join(root, "knowledge-base", "marketing", "brand-guide.md"), "# Brand\nBrand tokens here.\n");
  writeFileSync(path.join(root, "knowledge-base", "deep", "a.md"), "one\n");
  writeFileSync(path.join(root, "knowledge-base", "deep", "b.md"), "two\n");
  // >MAX_GLOB(20) committed matches for the cap/determinism scenario. Zero-padded
  // so lexical (byte) order is unambiguous: m00..m24.
  for (let i = 0; i < 25; i++) {
    const n = String(i).padStart(2, "0");
    writeFileSync(path.join(root, "knowledge-base", "many", `m${n}.md`), `many-${n}\n`);
  }
  // A committed symlink under knowledge-base/ → must be rejected by the per-match
  // symlink gate even though `git ls-files` lists it.
  symlinkSync("brand-guide.md", path.join(root, "knowledge-base", "marketing", "link.md"));

  writeSkill(root, "with-query", "context_queries:\n  - knowledge-base/marketing/brand-guide.md\n");
  writeSkill(root, "inline-query", "context_queries: [knowledge-base/marketing/brand-guide.md]\n");
  writeSkill(root, "glob-query", "context_queries:\n  - knowledge-base/deep/*.md\n");
  writeSkill(root, "many-query", "context_queries:\n  - knowledge-base/many/*.md\n");
  writeSkill(root, "no-query", "");
  writeSkill(root, "empty-query", "context_queries: []\n");
  writeSkill(root, "missing-art", "context_queries:\n  - knowledge-base/marketing/does-not-exist.md\n");
  writeSkill(root, "mixed-query", "context_queries:\n  - knowledge-base/marketing/brand-guide.md\n  - knowledge-base/marketing/does-not-exist.md\n");
  writeSkill(root, "traversal", "context_queries:\n  - knowledge-base/../../../etc/passwd\n");
  writeSkill(root, "absolute", "context_queries:\n  - /etc/passwd\n");
  writeSkill(root, "symlink-query", "context_queries:\n  - knowledge-base/marketing/link.md\n");
  // A skill literally named `plugin`, resolving a real artifact. Makes the
  // `other:plugin` adversarial test DISCRIMINATING: under the buggy
  // `lastIndexOf(":")` strip, `other:plugin` launders to `plugin` and would
  // resolve here; the correct anchored strip keeps the colon and fails the
  // charset gate → {}. Without this skill, both impls return {} vacuously.
  writeSkill(root, "plugin", "context_queries:\n  - knowledge-base/marketing/brand-guide.md\n");

  // A skill whose SKILL.md is a SYMLINK (target inside the skills dir, so realpath
  // containment passes) → gate #2's `lstatSync(...).isSymbolicLink()` reject fires.
  const symlinkSkillDir = path.join(root, "plugins", "soleur", "skills", "symlink-skillmd");
  mkdirSync(symlinkSkillDir, { recursive: true });
  symlinkSync(path.join("..", "with-query", "SKILL.md"), path.join(symlinkSkillDir, "SKILL.md"));

  // A skill whose BODY (not frontmatter) mentions context_queries: — the
  // frontmatter fast-path must treat this as a silent no-op.
  const bodyMentionDir = path.join(root, "plugins", "soleur", "skills", "body-mention");
  mkdirSync(bodyMentionDir, { recursive: true });
  writeFileSync(
    path.join(bodyMentionDir, "SKILL.md"),
    '---\nname: body-mention\ndescription: "d"\n---\n\nThis documents context_queries: the frontmatter field.\n',
  );

  git(root, ["init", "-q", "-b", "main"]);
  git(root, ["add", "-A"]);
  git(root, ["commit", "-q", "-m", "init"]);

  // A file present on disk but NOT committed (the untracked-artifact scenario).
  // Its SKILL.md IS committed so gate #2 passes; the artifact stays untracked so
  // `git ls-files` never lists it.
  writeFileSync(path.join(root, "knowledge-base", "marketing", "untracked.md"), "secret-ish\n");
  writeSkill(root, "untracked-art", "context_queries:\n  - knowledge-base/marketing/untracked.md\n");
  git(root, ["add", "plugins/soleur/skills/untracked-art"]);
  git(root, ["commit", "-q", "-m", "untracked-skill"]);

  return root;
}

export function cleanupFixture(root: string): void {
  rmSync(root, { recursive: true, force: true });
}
