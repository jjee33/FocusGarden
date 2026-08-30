/**
 * Turning a garden into an image someone can post.
 *
 * The one feature here that can bring people who have never heard of the app,
 * and it is nearly free: the plants are already SVG, so this composes them into
 * a poster and rasterises it in the browser. No server, no upload, nothing
 * leaves the device unless the person chooses to share the file.
 *
 * IDS ARE REWRITTEN PER PLANT. Each rendered plant carries its own <defs> with
 * generated ids, and nesting several into one document puts them all in the same
 * id space. Two plants of the same species with the same seed would collide, and
 * the second would silently draw the first one's leaf. Prefixing every id makes
 * that impossible rather than unlikely.
 */

import { renderPlantSvg } from "../render/plant-svg.js";
import type { PlantMorphology } from "../domain/species.js";

/** 1.91:1, the ratio every social platform crops to. */
const WIDTH = 1200;
const HEIGHT = 630;

/** Beyond this a garden becomes a smudge; the rest are summarised in the caption. */
const MAX_PLANTS = 7;

export interface SharePlant {
  morphology: PlantMorphology;
  growth: number;
  seed: string;
}

export interface ShareOptions {
  plants: SharePlant[];
  /** "14 hours of focus", already formatted by the caller. */
  subtitle: string;
  /** Light-theme values, because a preview lands on other people's surfaces. */
  background?: string;
  ink?: string;
  inkMuted?: string;
}

function rewriteIds(svg: string, prefix: string): string {
  const ids = [...svg.matchAll(/id="([^"]+)"/g)].map((m) => m[1] ?? "");
  let out = svg;
  for (const id of ids) {
    // Word-boundary anchored on the id itself: a naive replace would also hit an
    // id that merely contains this one as a substring.
    out = out.split(`id="${id}"`).join(`id="${prefix}${id}"`);
    out = out.split(`#${id}`).join(`#${prefix}${id}`);
  }
  return out;
}

/** Strips the outer <svg> wrapper so the body can be placed inside a group. */
function innerOf(svg: string): { body: string; width: number; height: number } {
  const width = Number(/width="(\d+(?:\.\d+)?)"/.exec(svg)?.[1] ?? 0);
  const height = Number(/height="(\d+(?:\.\d+)?)"/.exec(svg)?.[1] ?? 0);
  const body = svg.replace(/^<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "");
  return { body, width, height };
}

function escapeText(text: string): string {
  return text
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Composes the poster as one SVG document.
 *
 * Plants are laid along a ground line and scaled by growth, so a garden that has
 * had time in it looks like one. Text is drawn as SVG text rather than HTML,
 * because this has to survive being rasterised with no stylesheet.
 */
export function buildShareSvg(options: ShareOptions): string {
  const bg = options.background ?? "#e9dfc9";
  const ink = options.ink ?? "#2b2519";
  const muted = options.inkMuted ?? "#675c4a";

  const chosen = options.plants.slice(0, MAX_PLANTS);
  const groundY = 430;
  const slot = chosen.length === 0 ? WIDTH : WIDTH / (chosen.length + 1);

  const drawn = chosen.map((p, i) => {
    // Bigger for more grown, so the picture reads as progress at a glance.
    const scale = 0.55 + 0.45 * Math.max(0, Math.min(1, p.growth));
    const w = Math.round(180 * scale);
    const h = Math.round(240 * scale);
    const svg = renderPlantSvg({
      morphology: p.morphology, growth: p.growth, width: w, height: h,
      seed: p.seed, lod: 1, bloom: p.growth >= 1,
    });
    const { body } = innerOf(rewriteIds(svg, `s${i}_`));
    const x = Math.round(slot * (i + 1) - w / 2);
    const y = groundY - h;
    return `<g transform="translate(${x} ${y})">${body}</g>`;
  }).join("");

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}">`
    + `<rect width="${WIDTH}" height="${HEIGHT}" fill="${bg}"/>`
    + drawn
    + `<line x1="120" y1="${groundY}" x2="${WIDTH - 120}" y2="${groundY}" stroke="${muted}" stroke-opacity="0.35" stroke-width="2" stroke-linecap="round"/>`
    + `<text x="${WIDTH / 2}" y="518" text-anchor="middle" fill="${ink}"`
    + ` font-family="Fraunces, Georgia, serif" font-size="46" font-weight="600">`
    + `${escapeText(options.subtitle)}</text>`
    + `<text x="${WIDTH / 2}" y="562" text-anchor="middle" fill="${muted}"`
    + ` font-family="Public Sans, Segoe UI, system-ui, sans-serif" font-size="21">`
    + `thefocusgarden.com</text>`
    + `</svg>`;
}

/**
 * Rasterises the poster.
 *
 * Through an Image and a canvas rather than a library. The SVG the renderer
 * emits is entirely self-contained - no CSS variables, no classes, no external
 * references - which is what makes this possible at all; a stylesheet-dependent
 * SVG draws blank in a canvas.
 */
export async function renderShareImage(options: ShareOptions): Promise<Blob> {
  const svg = buildShareSvg(options);
  const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
  try {
    const image = new Image();
    await new Promise<void>((resolve, reject) => {
      image.onload = () => { resolve(); };
      image.onerror = () => { reject(new Error("The garden image could not be drawn.")); };
      image.src = url;
    });

    // 2x, so it stays sharp when a platform shows it on a dense screen.
    const canvas = document.createElement("canvas");
    canvas.width = WIDTH * 2;
    canvas.height = HEIGHT * 2;
    const ctx = canvas.getContext("2d");
    if (ctx === null) throw new Error("This browser would not provide a canvas.");
    ctx.scale(2, 2);
    ctx.drawImage(image, 0, 0, WIDTH, HEIGHT);

    return await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob(
        (blob) => { blob === null ? reject(new Error("The image could not be saved.")) : resolve(blob); },
        "image/png",
      );
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}

/**
 * Hands the image to the person, by whichever route their device offers.
 *
 * Web Share with a file is the good path on a phone - it opens the same sheet
 * every other app uses. Everything else gets a download, which is what a desktop
 * wanted anyway. `canShare` is checked with the actual file because Safari
 * advertises `share` while refusing files.
 */
export async function shareGardenImage(options: ShareOptions, fileName: string): Promise<"shared" | "downloaded"> {
  const blob = await renderShareImage(options);
  const file = new File([blob], fileName, { type: "image/png" });

  const nav = navigator as Navigator & {
    canShare?: (data: ShareData) => boolean;
    share?: (data: ShareData) => Promise<void>;
  };
  if (nav.share !== undefined && nav.canShare?.({ files: [file] }) === true) {
    try {
      await nav.share({ files: [file], title: "My Focus Garden" });
      return "shared";
    } catch (caught) {
      // A cancelled share sheet rejects. That is a choice, not a failure, so it
      // must not fall through to silently downloading a file nobody asked for.
      if (caught instanceof Error && caught.name === "AbortError") return "shared";
    }
  }

  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  URL.revokeObjectURL(url);
  return "downloaded";
}
