import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  plugins: [
    react(),
    /**
     * Installable, and genuinely usable offline.
     *
     * The app is already offline-first - every rule runs in the browser and
     * every record lives in IndexedDB - so the service worker only has to cache
     * the shell. It is NOT caching data: a stale copy of somebody's garden would
     * be worse than no copy.
     *
     * Precaching is left to Workbox rather than hand-rolled, because asset names
     * are content-hashed and a hand-written list goes stale silently.
     */
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["icon.svg"],
      manifest: {
        name: "Focus Garden",
        short_name: "Focus Garden",
        description: "A cosy garden grown from the time you invest in yourself.",
        start_url: "/",
        scope: "/",
        display: "standalone",
        orientation: "portrait",
        background_color: "#E9DFC9",
        theme_color: "#365A4D",
        categories: ["productivity", "lifestyle"],
        icons: [
          { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
          { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "maskable" },
        ],
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,svg,woff2}"],
        // Fonts come from Google's CDN; cache them so a second launch offline
        // does not fall back to a system serif and reflow the whole page.
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/fonts\.(googleapis|gstatic)\.com\/.*/,
            handler: "CacheFirst",
            options: {
              cacheName: "google-fonts",
              expiration: { maxEntries: 20, maxAgeSeconds: 60 * 60 * 24 * 365 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
        ],
      },
    }),
  ],
  server: { port: 5173 },
  test: {
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
    // node by default: the domain and renderer suites are pure and run faster
    // without a DOM. App-layer files opt in with an @vitest-environment docblock.
    environment: "node",
  },
});
