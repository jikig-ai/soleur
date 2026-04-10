import { Component } from "react";
import type { ReactNode } from "react";

export class KbErrorBoundary extends Component<
  { children: ReactNode },
  { hasError: boolean }
> {
  constructor(props: { children: ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex h-full items-center justify-center">
          <div className="text-center">
            <p className="text-sm text-neutral-400">
              Something went wrong loading this content.
            </p>
            <button
              onClick={() => this.setState({ hasError: false })}
              className="mt-2 text-sm text-amber-400 underline hover:text-amber-300"
            >
              Try again
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
