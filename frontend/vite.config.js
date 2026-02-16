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
    proxy: {
      "/chat": { target: "http://127.0.0.1:8000", changeOrigin: true },
      "/resy": { target: "http://127.0.0.1:8000", changeOrigin: true },
    },
  },
});
