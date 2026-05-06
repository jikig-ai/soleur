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
            <p className="text-sm text-soleur-text-secondary">
              Something went wrong loading this content.
            </p>
            <button
              onClick={() => this.setState({ hasError: false })}
              className="mt-2 text-sm text-soleur-accent-gold-fg underline hover:text-soleur-accent-gold-text"
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
