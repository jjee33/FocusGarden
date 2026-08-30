/**
 * What is on screen while the garden is being fetched.
 *
 * This used to be an empty div with a background colour and a visually-hidden
 * label, which turned out to be the reason the page appeared blank for over a
 * second. index.html paints the brand and the pitch before any JavaScript runs -
 * and then React mounted, replaced #root with a coloured rectangle, and threw
 * that first paint away. A Lighthouse filmstrip showed it exactly: background
 * present at 375ms, no text until 1500ms.
 *
 * So the loading state now says the same words the static shell does. Nothing
 * flashes, nothing is thrown away, and the transition into the real screen is a
 * refinement of what was already on screen rather than a replacement for a blank.
 *
 * KEEP THIS IN STEP WITH THE #boot MARKUP IN index.html. They are deliberately
 * the same words; if they diverge, the swap becomes visible again.
 */

interface Props {
  /** Announced to screen readers. The visible text is identical in both states. */
  label: string;
}

export function BootScreen({ label }: Props) {
  return (
    <div className="boot" role="status" aria-live="polite">
      <span className="visually-hidden">{label}</span>
      <div className="boot__words" aria-hidden="true">
        <b>Focus Garden</b>
        <span className="boot__tag">grow what you give time to</span>
        <h1>Every plant here grew out of time you spent focusing.</h1>
        <p>
          A focus timer that grows a garden from the hours you actually spend
          concentrating. Free, no ads, no tracking, and it works offline. An
          account is optional and only keeps your garden on more than one device.
        </p>
      </div>
    </div>
  );
}
