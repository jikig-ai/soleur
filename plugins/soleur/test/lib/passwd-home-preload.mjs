// passwd-home-preload.mjs — `node --import <this>?home=<dir> adapter.mjs`: makes os.userInfo().homedir
// report <dir>. The adapter looks for the pen CLI under the passwd home first and $HOME second, and
// the passwd home cannot be redirected by an environment variable, so a test (or the live probe) that
// wants "this HOME, and no other" installs this in the adapter process. Test-lib only: the adapter
// itself has no such hook.
import os from "node:os";
import { syncBuiltinESMExports } from "node:module";

const home = new URL(import.meta.url).searchParams.get("home");
if (home) {
  const real = os.userInfo;
  os.userInfo = (options) => ({ ...real.call(os, options), homedir: home });
  syncBuiltinESMExports();
}
