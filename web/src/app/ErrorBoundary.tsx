/**
 * The last thing between a thrown render and a white screen.
 *
 * React unmounts the whole tree when a render throws and nothing catches it. For
 * this app that is the worst possible failure: the garden is safe in IndexedDB,
 * intact and one refresh away, but the person is looking at a blank page with no
 * way to know that and no reason to believe their months of work survived.
 *
 * So this says the one thing that actually matters - your data is fine - and
 * offers the two ways out that do not risk it. Exporting is offered FIRST and
 * deliberately, because someone who has just watched an app break wants their
 * data in their own hands before they try anything else, and the export path
 * reads IndexedDB directly rather than going through the component tree that
 * just failed.
 */

import { Component, type ErrorInfo, type ReactNode } from "react";

import { exportBundleFromStore } from "../storage/save-store.js";

interface Props {
  children: ReactNode;
}

interface State {
  failed: boolean;
  detail: string;
}

export class ErrorBoundary extends Component<Props, State> {
  override state: State = { failed: false, detail: "" };

  static getDerivedStateFromError(error: unknown): State {
    return {
      failed: true,
      detail: error instanceof Error ? error.message : String(error),
    };
  }

  override componentDidCatch(error: Error, info: ErrorInfo): void {
    // Logged, not displayed. A stack trace tells the person nothing they can act
    // on, and it makes a broken page look like a crashed one.
    console.error("Render failed:", error, info.componentStack);
  }

  private readonly download = async (): Promise<void> => {
    try {
      const json = await exportBundleFromStore();
      const url = URL.createObjectURL(new Blob([json], { type: "application/json" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = `focus-garden-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      this.setState({ detail: "The export could not be built on this device." });
    }
  };

  override render(): ReactNode {
    if (!this.state.failed) return this.props.children;

    return (
      <main className="auth">
        <div className="auth__panel">
          <div className="auth__brand">
            <b>Focus Garden</b>
            <span>grow what you give time to</span>
          </div>
          <h1>Something broke on this screen.</h1>
          <p>
            <b>Your garden is safe.</b> Everything you have grown is stored on this
            device and none of it was touched by this. Reloading almost always
            fixes it.
          </p>
          <div className="auth__actions">
            <button className="btn" type="button" onClick={() => window.location.reload()}>
              Reload
            </button>
            <button className="btn btn--ghost" type="button" onClick={() => void this.download()}>
              Download a copy of my garden first
            </button>
          </div>
          {this.state.detail !== "" && (
            <p className="hint">
              If it keeps happening, this is what went wrong: {this.state.detail}
            </p>
          )}
        </div>
      </main>
    );
  }
}
