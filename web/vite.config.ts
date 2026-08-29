import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: { port: 5173 },
  test: {
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
    // node by default: the domain and renderer suites are pure and run faster
    // without a DOM. App-layer files opt in with an @vitest-environment docblock.
    environment: "node",
  },
});
