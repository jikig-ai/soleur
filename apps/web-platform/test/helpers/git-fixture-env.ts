// App-local re-export of the repo's fixture git environment (#12600, rulings D24(10) and D25(5)).
//
// The real-git suites of the KB sync import `gitFixtureEnv` from here instead of spelling the repo-root path
// themselves, so the one escape from the app lives in ONE helper. `test/repo-wide-containment.test.ts` sees this file
// escape and requires every suite that imports it to be listed in `test/repo-wide-suites.ts` (they run on every diff,
// which is what a suite reading a repo-root helper must do).
export { gitFixtureEnv } from "../../../../plugins/soleur/test/lib/git-fixture-env";
