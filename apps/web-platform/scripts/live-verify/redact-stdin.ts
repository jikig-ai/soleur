// scripts/live-verify/redact-stdin.ts
//
// Tiny CLI shim (#5487): read stdin, apply redact(), write stdout. Used by the
// live-verify GitHub Actions job to scrub the harness's raw stdout/stderr tail
// before embedding it in a `CANT-RUN:no-result-line` Sentry event — the
// no-RESULT-line case means the harness crashed BEFORE emitting its own
// already-redacted RESULT line, so the raw tail may carry the synthetic
// principal's live tokens/cookies/email. Runner: bun (`bun run …`), NOT node.
//
// Reads stdin via node's `process.stdin` (works under bun) rather than the `Bun`
// global, so it typechecks under the app's tsconfig (no `@types/bun`), matching
// run.ts's avoidance of Bun-typed globals.
import { redact } from "./redact";

async function main(): Promise<void> {
  process.stdin.setEncoding("utf8");
  let input = "";
  for await (const chunk of process.stdin) {
    input += String(chunk);
  }
  process.stdout.write(redact(input));
}

void main();
