// Architecture contracts for the canonical warehouse layout (CONTRACTS.md §2):
// domain ← application ← adapters, plus cycle and dependency-hygiene bans.
// Every rule is severity "error": a violation fails the arch gate.
module.exports = {
  forbidden: [
    {
      // The domain layer is pure: no imports from application or adapters.
      name: "domain-no-outbound",
      severity: "error",
      comment: "domain must not import application or adapters (layered, inward only)",
      from: { path: "^src/domain" },
      to: { path: "^src/(application|adapters)" },
    },
    {
      // The application layer may reach domain but never adapters.
      name: "application-no-adapters",
      severity: "error",
      comment: "application must not import adapters; ports belong to it",
      from: { path: "^src/application" },
      to: { path: "^src/adapters" },
    },
    {
      name: "no-circular",
      severity: "error",
      from: {},
      to: { circular: true },
    },
    {
      // Production code depends on nothing outside runtime dependencies;
      // every dev-only tool stays in build/test land.
      name: "not-to-dev-dep",
      severity: "error",
      from: { path: "^src" },
      to: { dependencyTypes: ["npm-dev"] },
    },
    {
      name: "no-orphans",
      severity: "error",
      // ports.ts is excluded deliberately: it is a pure type-only contract
      // module, and dependency-cruiser does not record `import type` edges,
      // so it can never show incoming dependencies. Extend this list only
      // for other genuinely type-only files (see LANG_SPEC.md).
      comment: "every src module is reachable from the public entry or used by tests",
      from: {
        orphan: true,
        pathNot: [String.raw`\.d\.ts$`, String.raw`^src/application/ports\.ts$`],
      },
      to: {},
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsConfig: { fileName: "tsconfig.json" },
  },
};
