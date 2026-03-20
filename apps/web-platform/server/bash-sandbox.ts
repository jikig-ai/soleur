/**
 * Defense-in-depth checks for Bash commands executed by the Agent SDK.
 *
 * The primary security boundary is the SDK's bubblewrap sandbox (OS-level)
 * combined with the minimal env allowlist (only 6 vars passed to child).
 * These checks catch common env-dump patterns as an additional layer.
 *
 * Known limitation: regex-based command analysis is fundamentally bypassable
 * (eval tricks, string concatenation, interpreter-level access). The env
 * allowlist and bubblewrap sandbox are the actual trust boundaries.
 */

const SENSITIVE_ENV_PATTERNS: RegExp[] = [
  // Command-position env-dump tools (anchored to pipeline segment start)
  /(?:^|[|;&])\s*env\b/,
  /(?:^|[|;&])\s*printenv\b/,
  /(?:^|[|;&])\s*set\b(?!\s+-)/,
  /(?:^|[|;&])\s*declare\s+-p\b/,
  /(?:^|[|;&])\s*export\s+-p\b/,
  /(?:^|[|;&])\s*compgen\s+-v\b/,
  // Direct variable references
  /\$SUPABASE_/,
  /\$ANTHROPIC_/,
  /\$\{SUPABASE_/,
  /\$\{ANTHROPIC_/,
  /\$BYOK_/,
  /\$\{BYOK_/,
  // /proc environ access (any PID, not just /proc/self)
  /\/proc\/.*\/environ/,
  // Interpreter-level env dumps
  /\bpython[23]?\b.*\bos\.environ\b/,
  /\bnode\b.*\bprocess\.env\b/,
  /\bruby\b.*\bENV\b/,
];

export function containsSensitiveEnvAccess(command: string): boolean {
  return SENSITIVE_ENV_PATTERNS.some((pattern) => pattern.test(command));
}
