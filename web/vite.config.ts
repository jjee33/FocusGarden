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
        /*
         * The legal pages are NOT the app, and the service worker must stop
         * pretending they are.
         *
         * navigateFallback sends any unmatched navigation to index.html, which is
         * right for SPA routes and wrong for these: the precache holds them under
         * `privacy.html`, the URL people visit is `/privacy`, those do not match,
         * and so a returning visitor with the worker installed would click
         * "Privacy Policy" and be shown the focus timer. It would work perfectly
         * in a fresh browser and fail only for people who had used the app -
         * which is everybody who might click it.
         *
         * Google's OAuth review fetches these URLs too, and it does not run our
         * JavaScript.
         */
        navigateFallbackDenylist: [
          /*
           * /api/ FIRST, because getting this wrong breaks sign-up for everyone.
           *
           * The email verification link is a TOP-LEVEL NAVIGATION to
           * /api/auth/verify-email. Without this entry the service worker treats
           * it as an app route, answers it from the precache with index.html, and
           * the request never reaches the server: the account stays unverified,
           * the person is bounced to the sign-in screen, and clicking the link
           * again does the same thing forever.
           *
           * It passes every test that does not involve a service worker - curl
           * verifies correctly, and so does a browser that has never visited the
           * site. It fails for exactly the people who WILL hit it: anyone who
           * loaded the app before opening their email, which is everyone who just
           * signed up. Caught by driving the real flow on production.
           *
           * OAuth callbacks live under /api/auth/ too and are also navigations.
           */
          /^\/api\//,
          /^\/privacy$/, /^\/terms$/, /^\/robots\.txt$/, /^\/sitemap\.xml$/,
        ],
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
