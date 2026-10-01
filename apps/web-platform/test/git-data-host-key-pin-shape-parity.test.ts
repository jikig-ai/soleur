import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { GIT_DATA_HOST_KEY_PIN_RE } from "../server/git-data-host-key-pin-shape";

// #5914 review: the pin shape lives in FOUR places — the TypeScript module (the resolver
// AND git-auth's runtime guard), the CI known_hosts writer, the cutover flag precheck and
// the git-data userdata variable validation. They must stay byte-identical, and until this
// test nothing compared them. The three non-TS files are governed by the rung-2 rehearsal
// and birth-readiness gates, so this test reads them rather than editing their pointers.
const REPO = path.resolve(__dirname, "..", "..", "..");
const TWINS: Array<[string, RegExp]> = [
  [".github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh", /^\s*RE='(\^ssh-ed25519 [^']+)'\s*$/m],
  ["apps/web-platform/infra/git-data-flag-precheck.sh", /^PIN_RE='(\^ssh-ed25519 [^']+)'\s*$/m],
  [
    "apps/web-platform/infra/modules/git-data-userdata/variables.tf",
    /condition\s*=\s*can\(regex\("(\^ssh-ed25519 [^"]+)",\s*var\.host_ssh_ed25519_public_key\)\)/,
  ],
];

describe("git-data host-key pin shape: every copy is byte-identical", () => {
  it.each(TWINS)("%s carries the same regex as git-data-host-key-pin-shape.ts", (rel, extract) => {
    const src = readFileSync(path.join(REPO, rel), "utf8");
    const m = src.match(extract);
    expect(m, `could not find the pin regex in ${rel}`).not.toBeNull();
    expect(m![1]).toBe(GIT_DATA_HOST_KEY_PIN_RE.source);
  });

  it("the TS regex has no flags (an `m` flag would let a second line half-match)", () => {
    expect(GIT_DATA_HOST_KEY_PIN_RE.flags).toBe("");
  });
});
