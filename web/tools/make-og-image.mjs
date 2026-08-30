/**
 * Renders the Open Graph image from the live site.
 *
 * Sharing thefocusgarden.com anywhere - Slack, Discord, iMessage, a search
 * result - showed a bare URL, which for a product whose entire pitch is "time
 * becomes something worth looking at" is the worst possible first impression.
 *
 * WHY A SCREENSHOT OF THE REAL SITE rather than a drawing. The plants are
 * procedural: there is no asset to export, and hand-building a second renderer
 * for this would be a copy that drifts the moment anything about the real one
 * changes. Pointing a headless browser at the deployed page means the preview is
 * always what the app actually draws, and regenerating after an art change is
 * one command.
 *
 *   node tools/make-og-image.mjs [url] [outfile]
 */

import { writeFileSync } from "node:fs";
import { launch } from "chrome-launcher";

const URL_TO_SHOOT = process.argv[2] ?? "https://thefocusgarden.com";
const OUT = process.argv[3] ?? "public/og.png";

/** The size every platform crops from. 1.91:1 is the shared denominator. */
const WIDTH = 1200;
const HEIGHT = 630;

/**
 * Reshapes the sign-in page into a poster.
 *
 * The page is a two-column layout with a form on the right; a preview wants the
 * garden and the promise, not a password field. This hides the panel, scales the
 * plants up, and writes the headline in - all in the page's own tokens, so the
 * result cannot drift from the app's palette.
 */
const POSTER_CSS = `
  .auth__panel { display: none !important; }

  /* The page is a centred two-column layout; a poster is a stack with a clear
     top and bottom. Laying it out explicitly rather than scaling the showcase in
     place - the first attempt did that and dropped the headline straight onto
     the bed line and through the middle plant's stem. */
  .auth {
    display: flex !important;
    flex-direction: column !important;
    justify-content: flex-start !important;
    align-items: center !important;
    padding: 0 !important;
    height: 630px !important;
    min-height: 0 !important;
    overflow: hidden !important;
  }
  .showcase {
    max-width: none !important;
    margin-top: 58px !important;
    transform: scale(1.35);
    transform-origin: top center;
  }
  .showcase__caption { display: none !important; }

  /* Below everything, with room. Not fixed to the viewport bottom: that is what
     put it on top of the plants when the scaled showcase grew past it. */
  #og-words {
    margin-top: auto;
    padding-bottom: 46px;
    text-align: center;
    font-family: "Fraunces","Iowan Old Style",Georgia,serif;
    color: #2b2519;
  }
  #og-words b { display:block; font-size: 52px; font-weight: 600; letter-spacing: -0.01em; }
  #og-words span {
    display:block; margin-top: 12px; font-size: 21px; color: #675c4a;
    font-family: "Public Sans","Segoe UI",system-ui,sans-serif;
  }
`;

async function cdp(port, method, params = {}, sessionId) {
  // Talking to the DevTools protocol directly rather than adding Puppeteer: this
  // needs four commands, and a browser automation framework to take one
  // screenshot is a dependency that will outlive its reason for being here.
  const res = await fetch(`http://127.0.0.1:${port}/json/list`);
  const targets = await res.json();
  void targets;
  void method; void params; void sessionId;
}
void cdp;

const chrome = await launch({
  chromeFlags: [
    "--headless=new",
    `--window-size=${WIDTH},${HEIGHT}`,
    "--hide-scrollbars",
    "--force-device-scale-factor=2",
    "--no-sandbox",
  ],
});

try {
  const list = await (await fetch(`http://127.0.0.1:${chrome.port}/json/list`)).json();
  const page = list.find((t) => t.type === "page");
  if (page === undefined) throw new Error("Chrome started but exposed no page target.");

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; });

  let id = 0;
  const pending = new Map();
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    const waiter = pending.get(msg.id);
    if (waiter !== undefined) { pending.delete(msg.id); waiter(msg); }
  };
  const send = (method, params = {}) => new Promise((resolve) => {
    const n = ++id;
    pending.set(n, resolve);
    ws.send(JSON.stringify({ id: n, method, params }));
  });

  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", {
    width: WIDTH, height: HEIGHT, deviceScaleFactor: 2, mobile: false,
  });
  // Light theme always. The preview appears on other people's surfaces, and a
  // dark card on a light timeline reads as a broken image.
  await send("Emulation.setEmulatedMedia", {
    features: [{ name: "prefers-color-scheme", value: "light" }],
  });

  await send("Page.navigate", { url: URL_TO_SHOOT });
  // Fonts and the SVG both need to settle; the plants are drawn on mount.
  await new Promise((r) => setTimeout(r, 6000));

  const applied = await send("Runtime.evaluate", {
    expression: `(() => {
      const s = document.createElement('style');
      s.textContent = ${JSON.stringify(POSTER_CSS)};
      document.head.appendChild(s);
      const w = document.createElement('div');
      w.id = 'og-words';
      w.innerHTML = '<b>Grow what you give time to</b><span>thefocusgarden.com</span>';
      // Inside .auth, not on body: .auth is the flex column that positions this
      // and it clips its overflow, so a sibling is simply never seen.
      (document.querySelector('.auth') ?? document.body).appendChild(w);
      return document.querySelectorAll('.showcase svg').length;
    })()`,
    returnByValue: true,
  });

  const plants = applied.result?.result?.value ?? 0;
  if (plants === 0) {
    throw new Error(
      "No plants rendered. The showcase only mounts above 900px, so this needs a "
      + "viewport at least that wide and a page that finished loading.",
    );
  }

  await new Promise((r) => setTimeout(r, 1200));
  const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
  const data = shot.result?.data;
  if (data === undefined) throw new Error("Chrome returned no image data.");

  writeFileSync(OUT, Buffer.from(data, "base64"));
  console.log(`Wrote ${OUT} - ${WIDTH}x${HEIGHT} at 2x, ${plants} plants.`);
  ws.close();
} finally {
  await chrome.kill();
}
