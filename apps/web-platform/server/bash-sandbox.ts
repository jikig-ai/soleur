/**
 * Defense-in-depth checks for Bash commands executed by the Agent SDK.
 *
 * The primary security boundary is the SDK's bubblewrap sandbox (OS-level).
 * These checks catch sensitive env var access patterns that the filesystem/
 * network sandbox cannot prevent (process.env is inherited in-memory).
 */

const SENSITIVE_ENV_PATTERNS: RegExp[] = [
  /\benv\b/,
  /\bprintenv\b/,
  /\bset\b(?!\s+-)/,
  /\$SUPABASE_/,
  /\$ANTHROPIC_/,
  /\$\{SUPABASE_/,
  /\$\{ANTHROPIC_/,
  /\$BYOK_/,
  /\$\{BYOK_/,
  /\/proc\/self\/environ/,
];

export function containsSensitiveEnvAccess(command: string): boolean {
  return SENSITIVE_ENV_PATTERNS.some((pattern) => pattern.test(command));
}
