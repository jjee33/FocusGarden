/**
 * @vitest-environment jsdom
 *
 * The boundary is only ever exercised by a failure, so it is exactly the kind of
 * code that ships broken. These assert the two things it exists to guarantee: a
 * thrown render does not become a blank page, and the person is told their data
 * survived.
 */

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ErrorBoundary } from "../ErrorBoundary.js";

function Boom(): never {
  throw new Error("kaboom in render");
}

describe("ErrorBoundary", () => {
  beforeEach(() => {
    // React logs caught render errors to console.error by design. Silenced so a
    // passing run is not full of red that means nothing.
    vi.spyOn(console, "error").mockImplementation(() => {});
  });
  // Explicit, because auto-cleanup only runs when the globals setup is loaded
  // and this suite does not use it. Without it each render stacks onto the same
  // document and every getByText finds the previous test's copy too.
  afterEach(() => { cleanup(); vi.restoreAllMocks(); });

  it("renders its children when nothing throws", () => {
    render(<ErrorBoundary><p>the garden</p></ErrorBoundary>);
    expect(screen.getByText("the garden")).toBeTruthy();
  });

  it("catches a thrown render instead of blanking the page", () => {
    render(<ErrorBoundary><Boom /></ErrorBoundary>);
    expect(screen.getByText(/Something broke on this screen/i)).toBeTruthy();
  });

  it("says the garden is safe, which is the only thing worth saying", () => {
    render(<ErrorBoundary><Boom /></ErrorBoundary>);
    expect(screen.getByText(/Your garden is safe/i)).toBeTruthy();
  });

  it("offers a reload and an export, so there is always a way out", () => {
    render(<ErrorBoundary><Boom /></ErrorBoundary>);
    expect(screen.getByRole("button", { name: /reload/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /download a copy/i })).toBeTruthy();
  });

  it("does not put the raw error where it reads as the headline", () => {
    render(<ErrorBoundary><Boom /></ErrorBoundary>);
    const heading = screen.getByRole("heading", { level: 1 });
    expect(heading.textContent).not.toContain("kaboom");
  });
});
