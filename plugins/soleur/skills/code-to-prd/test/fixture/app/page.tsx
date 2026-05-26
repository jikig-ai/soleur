/**
 * Landing page for the synthetic code-to-prd fixture.
 */
import { useState } from "react";

export default function HomePage() {
  const [count, setCount] = useState(0);
  return (
    <main>
      <h1>code-to-prd fixture</h1>
      <button onClick={() => setCount(count + 1)}>Count: {count}</button>
    </main>
  );
}
