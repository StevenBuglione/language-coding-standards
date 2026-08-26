import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      // index.ts is a pure re-export surface with no executable statements;
      // measuring it only adds a misleading 0% row.
      include: ["src/**/*.ts"],
      exclude: ["src/index.ts"],
      reporter: ["text", "text-summary"],
      thresholds: {
        lines: 93,
        statements: 93,
        functions: 96,
        branches: 89,
      },
    },
  },
});
