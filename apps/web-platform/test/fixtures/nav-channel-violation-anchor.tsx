// SENTINEL FIXTURE — a literal internal anchor split across lines; the
// pre-widening line-based grep could not see this shape.
export function FixtureAnchor() {
  return (
    <a
      href={"/dashboard/chat"}
      className="fixture"
    >
      chat
    </a>
  );
}
