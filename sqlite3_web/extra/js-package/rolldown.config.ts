import { defineConfig } from "rolldown";
import { minify } from "terser";

export default defineConfig({
  input: "src/index.ts",
  output: {
    file: "dist/index.mjs",
    // We use terser instead of oxc minifier so that we can mangle some property and method names.
    minify: false,
  },
  plugins: [
    {
      name: "terser",
      renderChunk: async (code) => {
        const result = await minify(code, {
          module: true,
          ecma: 2025,
          mangle: {
            properties: {
              regex: /_internal_/,
            },
          },
        });
        return result.code;
      },
    },
  ],
});
