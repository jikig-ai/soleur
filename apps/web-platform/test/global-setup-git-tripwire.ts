// Guard 3, vitest arm — the git-location tripwire, registered as `globalSetup`.
//
// WHY globalSetup AND NOT setupFiles. All three vitest projects pin `isolate: true`, so a
// `setupFiles` entry re-executes per TEST FILE: measured 1114 executions at ~20 ms each, ~22 CPU-s
// and ~1.7 s of wall clock on this suite, growing linearly with the corpus.
//
// The property is unharmed by the move, and is arguably better expressed here. The hazard is an
// environment INHERITED AT PROCESS START, and `globalSetup` runs in vitest's main process — the
// one that actually inherited it, and the one every worker is forked from. Checking it 1114 times
// in the children answers the same question 1113 more times than necessary.
//
// It also removes a wart: `process.exit(97)` inside a worker is swallowed, and vitest reports its
// own aggregate exit code (1), which is why the Guard 3 driver had to assert "non-zero" rather
// than 97. From globalSetup the real code propagates.
import { assertNoInheritedGitLocation } from "../../../plugins/soleur/test/lib/git-tripwire";

export default function setup(): void {
  assertNoInheritedGitLocation("vitest");
}
