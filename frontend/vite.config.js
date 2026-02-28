import { fileURLToPath } from "url";
import path from "path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(path.dirname(fileURLToPath(import.meta.url)), "src"),
    },
  },
  server: {
    allowedHosts: true, // allow ngrok and other tunnel hosts when testing on phone
    hmr: true, // ensure hot module replacement is on so code changes apply without full refresh
    watch: {
      // Poll so code changes are always picked up (helps if HMR or fs events miss updates)
      usePolling: true,
      interval: 1000,
    },
    proxy: {
      "/chat": { target: "http://127.0.0.1:8000", changeOrigin: true },
      "/resy": { target: "http://127.0.0.1:8000", changeOrigin: true },
    },
  },
});
