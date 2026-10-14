// SENTINEL FIXTURE — raw useRouter nav call bypasses usePendingRouter.
import { useRouter } from "next/navigation";
export function FixtureRouterNav() {
  const nav = useRouter();
  return <button type="button" onClick={() => nav.push("/inbox")}>go</button>;
}
