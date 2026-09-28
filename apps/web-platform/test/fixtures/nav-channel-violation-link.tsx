// SENTINEL FIXTURE — deliberately violates the nav-channel contract so the
// sweep tests can assert the sentinel FAILS on a bypass (positive-mutation
// coverage). Lives under test/fixtures/ which is outside every sweep's
// default pathspec; only env-overridden runs see it.
import Link from "next/link";
export function FixtureLink() {
  return <Link href="/dashboard">dash</Link>;
}
