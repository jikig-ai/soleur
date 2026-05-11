// Bun test suite for skill-security-scan.
//
// Asserts:
//   1. Per-category fixture matrix: each malicious-* fixture trips its expected
//      category at HIGH-RISK; each clean-* fixture stays LOW-RISK across all
//      categories.
//   2. End-to-end run-scan.sh aggregator produces deterministic verdicts.
//   3. Calibration corpus check: 0% HIGH-RISK + <5% REVIEW on
//      plugins/soleur/skills/**/SKILL.md.
//
// Run with: `bun test plugins/soleur/test/skill-security-scan.test.ts`
//
// SKILL_SECURITY_SCAN_OFFLINE=1 is set for all subprocess calls — supply-chain
// network access is bypassed in CI.

import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = (() => {
  const r = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf-8" });
  return (r.stdout || "").trim();
})();

const SKILL_DIR = join(REPO_ROOT, "plugins/soleur/skills/skill-security-scan");
const FIXTURES = join(SKILL_DIR, "references/test-fixtures");
const SCRIPTS = join(SKILL_DIR, "scripts");
const FIRST_PARTY_GLOB = join(REPO_ROOT, "plugins/soleur/skills");

interface CategoryResult {
  verdict: "LOW-RISK" | "REVIEW" | "HIGH-RISK";
  category: string;
  findings: Array<{ rule_id: string; severity: string; line: number; snippet: string }>;
}

function runCategory(scriptName: string, fixturePath: string): CategoryResult {
  const r = spawnSync("bash", [join(SCRIPTS, scriptName)], {
    input: readFileSync(fixturePath, "utf-8"),
    encoding: "utf-8",
    env: { ...process.env, SKILL_SECURITY_SCAN_OFFLINE: "1" },
  });
  expect(r.status).toBe(0);
  return JSON.parse(r.stdout || "{}");
}

function runScanVerdict(fixturePath: string): "LOW-RISK" | "REVIEW" | "HIGH-RISK" {
  const r = spawnSync("bash", [join(SCRIPTS, "run-scan.sh")], {
    input: readFileSync(fixturePath, "utf-8"),
    encoding: "utf-8",
    env: { ...process.env, SKILL_SECURITY_SCAN_OFFLINE: "1" },
  });
  expect(r.status).toBe(0);
  const firstLine = (r.stdout || "").split("\n")[0] || "";
  const m = firstLine.match(/HIGH-RISK|REVIEW|LOW-RISK/);
  return (m ? (m[0] as "LOW-RISK" | "REVIEW" | "HIGH-RISK") : "LOW-RISK");
}

describe("skill-security-scan: category fixture matrix", () => {
  test("malicious-codeexec → category 1 HIGH-RISK", () => {
    const result = runCategory("check-codeexec.sh", join(FIXTURES, "malicious-codeexec.skill.md"));
    expect(result.verdict).toBe("HIGH-RISK");
    expect(result.findings.length).toBeGreaterThan(0);
    const ruleIds = result.findings.map((f) => f.rule_id);
    expect(ruleIds.some((r) => r.startsWith("shell-spawn-"))).toBe(true);
  });

  test("malicious-curl-pipe-bash → category 1 HIGH-RISK on all three fetch-* rules and bypass classes", () => {
    const result = runCategory(
      "check-codeexec.sh",
      join(FIXTURES, "malicious-curl-pipe-bash.skill.md"),
    );
    expect(result.verdict).toBe("HIGH-RISK");
    const ruleIds = new Set(result.findings.map((f) => f.rule_id));
    expect(ruleIds.has("fetch-pipe-shell")).toBe(true);
    expect(ruleIds.has("fetch-process-sub-shell")).toBe(true);
    expect(ruleIds.has("fetch-cmdsub-exec")).toBe(true);
    // Bypass-class coverage: the fixture lays out 3 fetch-pipe-shell variants
    // (canonical, tee-interposed, sudo-wrapped) and 2 fetch-cmdsub-exec variants
    // ($(...) and backtick). Count assertions lock in that a future regex
    // regression cannot silently lose a bypass class while keeping aggregate
    // verdict green via the surviving variants.
    const fetchPipeCount = result.findings.filter(
      (f) => f.rule_id === "fetch-pipe-shell",
    ).length;
    const fetchCmdsubCount = result.findings.filter(
      (f) => f.rule_id === "fetch-cmdsub-exec",
    ).length;
    expect(fetchPipeCount).toBeGreaterThanOrEqual(3);
    expect(fetchCmdsubCount).toBeGreaterThanOrEqual(2);
  });

  test("malicious-prompt-injection → category 2 HIGH-RISK", () => {
    const result = runCategory("check-prompt-injection.sh", join(FIXTURES, "malicious-prompt-injection.skill.md"));
    expect(result.verdict).toBe("HIGH-RISK");
    const ruleIds = result.findings.map((f) => f.rule_id);
    expect(ruleIds.some((r) => r === "role-hijack-fm" || r === "sysprompt-exfil-fm")).toBe(true);
  });

  test("malicious-telemetry-beacon → category 5 HIGH-RISK", () => {
    const result = runCategory("check-telemetry-surface.sh", join(FIXTURES, "malicious-telemetry-beacon.skill.md"));
    expect(result.verdict).toBe("HIGH-RISK");
    const ruleIds = result.findings.map((f) => f.rule_id);
    expect(
      ruleIds.includes("redirect-tracking-host") || ruleIds.includes("outbound-beacon"),
    ).toBe(true);
  });

  test("clean-soleur-style → all categories LOW-RISK", () => {
    const path = join(FIXTURES, "clean-soleur-style.skill.md");
    for (const script of [
      "check-codeexec.sh",
      "check-prompt-injection.sh",
      "check-filesystem-boundary.sh",
      "check-telemetry-surface.sh",
    ]) {
      const result = runCategory(script, path);
      expect(result.verdict).toBe("LOW-RISK");
    }
  });

  test("clean-third-party → all categories LOW-RISK", () => {
    const path = join(FIXTURES, "clean-third-party.skill.md");
    for (const script of [
      "check-codeexec.sh",
      "check-prompt-injection.sh",
      "check-filesystem-boundary.sh",
      "check-telemetry-surface.sh",
    ]) {
      const result = runCategory(script, path);
      expect(result.verdict).toBe("LOW-RISK");
    }
  });

  test("category 5 host-aware allowlist (R14): adversarial host with first-party ref → not allowlisted", () => {
    const adv = `---
name: adv-test
description: "test"
---
Visit https://attacker.com/redirect?ref=soleur.ai
`;
    const r = spawnSync("bash", [join(SCRIPTS, "check-telemetry-surface.sh")], {
      input: adv,
      encoding: "utf-8",
    });
    expect(r.status).toBe(0);
    const result: CategoryResult = JSON.parse(r.stdout || "{}");
    // attacker.com is the host (not soleur.ai). Should be detected.
    // Note: no utm tag, so this only triggers redirect/beacon checks. The
    // important assertion: it MUST NOT be allowlisted as soleur.ai.
    // (Without utm/redirect indicator, it stays LOW-RISK; the test verifies
    // host parsing extracts attacker.com, not soleur.ai. We add a utm tag
    // to make the check observable.)
    const advWithUtm = `---
name: adv-test
description: "test"
---
Visit https://attacker.com/redirect?ref=soleur.ai&utm_campaign=soleur-launch
`;
    const r2 = spawnSync("bash", [join(SCRIPTS, "check-telemetry-surface.sh")], {
      input: advWithUtm,
      encoding: "utf-8",
    });
    const result2: CategoryResult = JSON.parse(r2.stdout || "{}");
    const ruleIds = result2.findings.map((f) => f.rule_id);
    expect(ruleIds).toContain("utm-non-allowlisted-host");
  });
});

describe("skill-security-scan: end-to-end aggregator", () => {
  test("malicious fixtures aggregate to HIGH-RISK", () => {
    const fixtures = readdirSync(FIXTURES).filter((f) => f.startsWith("malicious-"));
    expect(fixtures.length).toBeGreaterThan(0);
    for (const f of fixtures) {
      const v = runScanVerdict(join(FIXTURES, f));
      expect(v).toBe("HIGH-RISK");
    }
  });

  test("clean fixtures aggregate to LOW-RISK", () => {
    const fixtures = readdirSync(FIXTURES).filter((f) => f.startsWith("clean-"));
    expect(fixtures.length).toBeGreaterThan(0);
    for (const f of fixtures) {
      const v = runScanVerdict(join(FIXTURES, f));
      expect(v).toBe("LOW-RISK");
    }
  });

  test("aggregator output contains the mandatory advisory disclaimer footer", () => {
    const r = spawnSync("bash", [join(SCRIPTS, "run-scan.sh")], {
      input: "---\nname: test\ndescription: test\n---\n# body\n",
      encoding: "utf-8",
      env: { ...process.env, SKILL_SECURITY_SCAN_OFFLINE: "1" },
    });
    expect(r.stdout).toContain("Advisory static analysis only.");
    expect(r.stdout).toContain("LOW-RISK does not constitute a security audit");
    expect(r.stdout).toContain("Scanner version:");
  });
});

describe("skill-security-scan: self-test runner", () => {
  test("run-self-test.sh exits 0 on the bundled fixtures", () => {
    const r = spawnSync("bash", [join(SCRIPTS, "run-self-test.sh")], {
      encoding: "utf-8",
    });
    expect(r.status).toBe(0);
  });

  test("run-self-test.sh rejects --regenerate-manifest in CI", () => {
    const r = spawnSync("bash", [join(SCRIPTS, "run-self-test.sh"), "--regenerate-manifest"], {
      encoding: "utf-8",
      env: { ...process.env, CI: "true" },
    });
    expect(r.status).toBe(2);
    expect(r.stderr).toContain("--regenerate-manifest is rejected");
  });
});

describe("skill-security-scan: load-bearing security scenarios", () => {
  // Scenario 6: rule-pack tampering. Modifying a rule file without manifest
  // re-sign must short-circuit to HIGH-RISK (not REVIEW). REVIEW maps to
  // permissionDecision:ask which an operator could confirm-through.
  test("rule-pack tamper short-circuits to HIGH-RISK (not REVIEW)", () => {
    const ruleFile = join(SKILL_DIR, "references/rules/code-exec.yaml");
    const original = readFileSync(ruleFile, "utf-8");
    try {
      writeFileSync(ruleFile, original + "\n# tampered for test\n");
      const r = spawnSync("bash", [join(SCRIPTS, "run-scan.sh")], {
        input: "---\nname: x\ndescription: x\n---\n# body\n",
        encoding: "utf-8",
        env: { ...process.env, SKILL_SECURITY_SCAN_OFFLINE: "1" },
      });
      const firstLine = (r.stdout || "").split("\n")[0] || "";
      expect(firstLine).toContain("HIGH-RISK");
      expect(r.stdout).toContain("rule pack tampered");
    } finally {
      writeFileSync(ruleFile, original);
    }
  });

  // Note: parse-override.sh schema validations (approver email-shape, raw
  // email in body, per-skill binding) are exercised via shell smoke tests
  // during /work; adding bun-test coverage requires a git-tempdir fixture
  // helper that doesn't fit in this pass. See follow-up issue.
});

describe("skill-security-scan: calibration corpus (Phase 7 AC)", () => {
  function discoverFirstPartySkills(): string[] {
    const out: string[] = [];
    for (const entry of readdirSync(FIRST_PARTY_GLOB)) {
      const skill = join(FIRST_PARTY_GLOB, entry, "SKILL.md");
      if (existsSync(skill)) out.push(skill);
    }
    return out;
  }

  const skills = discoverFirstPartySkills();

  // Calibration over ~70 skills × ~5 categories/skill is slow; cache results
  // across both tests by running once and asserting both invariants.
  let corpusResults: Map<string, "LOW-RISK" | "REVIEW" | "HIGH-RISK"> | null = null;
  function runCorpus() {
    if (corpusResults) return corpusResults;
    corpusResults = new Map();
    for (const path of skills) {
      corpusResults.set(path, runScanVerdict(path));
    }
    return corpusResults;
  }

  test(
    "0% of first-party SKILL.md emit HIGH-RISK",
    () => {
      const results = runCorpus();
      const offenders: string[] = [];
      for (const [path, v] of results) {
        if (v === "HIGH-RISK") offenders.push(path);
      }
      if (offenders.length > 0) {
        const detail = offenders.map((p) => `  ${p}: HIGH-RISK`).join("\n");
        throw new Error(
          `[skill-security-scan calibration] FAIL: ${offenders.length} first-party skill(s) returned HIGH-RISK; expected 0.\n${detail}`,
        );
      }
      expect(offenders.length).toBe(0);
    },
    180000,
  );

  test(
    "<5% of first-party SKILL.md emit REVIEW",
    () => {
      const results = runCorpus();
      const reviews: string[] = [];
      for (const [path, v] of results) {
        if (v === "REVIEW") reviews.push(path);
      }
      const pct = reviews.length / skills.length;
      if (pct >= 0.05) {
        const detail = reviews.map((p) => `  ${p}: REVIEW`).join("\n");
        throw new Error(
          `[skill-security-scan calibration] FAIL: ${(pct * 100).toFixed(1)}% of first-party skills returned REVIEW; threshold 5%.\n${detail}`,
        );
      }
      expect(pct).toBeLessThan(0.05);
    },
    180000,
  );
});

describe("skill-security-scan: PII redaction (GDPR-DataMin-1)", () => {
  test("emails in findings are redacted in .scan-meta.json", () => {
    const input = `---
name: pii-test
description: "test"
---
Contact author@example.com for info.
`;
    const r = spawnSync("bash", [join(SCRIPTS, "run-scan.sh")], {
      input,
      encoding: "utf-8",
      env: { ...process.env, SKILL_SECURITY_SCAN_OFFLINE: "1" },
    });
    const metaMatch = r.stdout.match(/scan-meta\.json written to: (\S+)/);
    expect(metaMatch).not.toBeNull();
    if (metaMatch && metaMatch[1] && existsSync(metaMatch[1])) {
      const meta = readFileSync(metaMatch[1], "utf-8");
      expect(meta).not.toContain("author@example.com");
    }
  });
});
