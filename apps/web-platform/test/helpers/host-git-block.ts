// The shared host-git hardening block precedes the caller's args on every host-side `git` exec. Sibling suites whose
// `execFileSync` fakes branch on the subcommand slice it off through this helper, so the block is taken from the
// helper itself (never a copied literal list) and a change to it moves the fakes and production together.
import { hostGitInvocation } from "../../server/host-git";

const BLOCK_LEN = (): number => hostGitInvocation([], { allowProtocol: "none" }).args.length;

export function stripHostGitBlock(argv: readonly string[]): string[] {
  return argv.slice(BLOCK_LEN());
}
