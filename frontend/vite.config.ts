import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    // The largest file is web3.js (~540 kB), which is only downloaded when the activity feed is opened.
    chunkSizeWarningLimit: 600,
    rolldownOptions: {
      output: {
        codeSplitting: {
          // Put ethers (and its crypto libraries) in its own file. It changes rarely,
          // so browsers keep it cached when only our app code changes.
          groups: [{ name: "ethers", test: /node_modules[\\/](ethers|@noble|@adraffy)[\\/]/ }],
        },
      },
    },
  },
});