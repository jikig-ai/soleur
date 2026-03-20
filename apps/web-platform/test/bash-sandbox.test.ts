import { describe, test, expect } from "vitest";
import { containsSensitiveEnvAccess } from "../server/bash-sandbox";

describe("containsSensitiveEnvAccess", () => {
  describe("blocked commands", () => {
    test.each([
      ["env", "bare env command"],
      ["printenv", "printenv command"],
      ["set", "bare set (lists all vars)"],
      ["declare -p", "declare -p dumps vars"],
      ["export -p", "export -p dumps vars"],
      ["compgen -v", "compgen -v lists var names"],
      ["echo $SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ var reference"],
      ["echo ${ANTHROPIC_API_KEY}", "ANTHROPIC_ var reference (braces)"],
      ["echo $BYOK_ENCRYPTION_KEY", "BYOK_ var reference"],
      ["echo ${BYOK_ENCRYPTION_KEY}", "BYOK_ var reference (braces)"],
      ["cat /proc/self/environ", "/proc/self/environ"],
      ["cat /proc/1/environ", "/proc/<pid>/environ"],
      ["dd if=/proc/$$/environ", "/proc/$$/environ"],
      ["ls | env", "env in pipeline"],
      ["echo ok && set", "set after &&"],
      ["python3 -c 'import os; print(os.environ)'", "python os.environ"],
      ["node -e 'console.log(process.env)'", "node process.env"],
      ["ruby -e 'puts ENV.to_a'", "ruby ENV access"],
    ])("blocks: %s (%s)", (cmd) => {
      expect(containsSensitiveEnvAccess(cmd)).toBe(true);
    });
  });

  describe("allowed commands (no false positives)", () => {
    test.each([
      ["ls -la", "basic file listing"],
      ["git status", "git command"],
      ["set -euo pipefail", "set with flags"],
      ["set -e", "set -e"],
      ["echo hello", "simple echo"],
      ["npm install", "npm install"],
      ["python -m venv .venv", "venv is not env"],
      ["source .env.local", ".env file is not env command"],
      ["cat environment.txt", "environment is not env"],
      ["NODE_ENV=test npm test", "env var assignment is not env command"],
      ["export FOO=bar", "export with assignment is not export -p"],
    ])("allows: %s (%s)", (cmd) => {
      expect(containsSensitiveEnvAccess(cmd)).toBe(false);
    });
  });
});
