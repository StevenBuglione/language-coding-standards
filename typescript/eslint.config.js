// ESLint 10 flat config. Plain .js (not .ts) on purpose: a TypeScript config
// would need jiti or --experimental-strip-types just to parse, adding a
// dependency the toolchain does not need. See LANG_SPEC.md.
//
// Rule budget: typescript-eslint strictTypeChecked + stylisticTypeChecked for
// type-aware maximalism, unicorn + sonarjs for opinionated structural rules,
// and core complexity caps. Every warning-class setting below is "error"
// (PHILOSOPHY.md principle 1); zero inline suppressions ship in src/tests.
//
// @ts-check
import js from "@eslint/js";
import sonarjs from "eslint-plugin-sonarjs";
import unicorn from "eslint-plugin-unicorn";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    // bad_examples is exercised only by the negative phase with explicit
    // paths (--no-ignore), never by the main gates (CONTRACTS.md §3).
    ignores: [
      "**/node_modules/**",
      "**/coverage/**",
      "**/.cache/**",
      "**/.pnpm-store/**",
      "**/dist/**",
      "**/.stryker-tmp/**",
      "bad_examples/**",
    ],
  },
  js.configs.recommended,
  unicorn.configs.recommended,
  sonarjs.configs.recommended,
  {
    files: ["**/*.ts"],
    extends: [tseslint.configs.strictTypeChecked, tseslint.configs.stylisticTypeChecked],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // The type-aware bundle brings @typescript-eslint/no-unused-vars;
      // the core rule would double-report every finding.
      "no-unused-vars": "off",
      // Exhaustive switches over discriminated unions are compiler work;
      // forgetting a variant must fail the build, not production.
      "@typescript-eslint/switch-exhaustiveness-check": "error",
      // Type-only imports stay syntactically erasable (verbatimModuleSyntax).
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports", fixStyle: "inline-type-imports" },
      ],
    },
  },
  {
    files: ["tests/**/*.test.ts"],
    rules: {
      // Repeated literals in assertions ("USD", sku codes) are test data,
      // not duplication debt; extracting them hides the expected values.
      "sonarjs/no-duplicate-string": "off",
    },
  },
  {
    rules: {
      // Structural caps (toolchain brief): agents refactor toward tables
      // and small functions instead of negotiating with review comments.
      complexity: ["error", 15],
      "max-depth": ["error", 4],
      "max-lines-per-function": ["error", { max: 120, skipBlankLines: true, skipComments: true }],
      "max-statements": ["error", 25, { ignoreTopLevelFunctions: true }],
      "max-params": ["error", 4],
      "sonarjs/cognitive-complexity": ["error", 15],

      // Debugging output goes through injected loggers, never console.
      "no-console": "error",

      // Untracked work notes rot silently; items belong in the tracker,
      // so any such marker in comments fails lint (see bad_examples).
      "no-warning-comments": ["error", { terms: ["todo", "fixme", "xxx"], location: "anywhere" }],
      // Deliberate non-enforcement (documented in LANG_SPEC.md): this rule
      // rewrites ubiquitous-language names ("repository" -> "repo",
      // "inventory" -> "stock"), but CONTRACTS.md §2 canonically names
      // OrderRepository and the adapters layer; domain vocabulary wins.
      "unicorn/name-replacements": "off",

      // Custom security bans (there is no maintained free TS SAST today):
      // eval executes ambient strings; the no-arg Date constructor reads
      // the ambient clock. Both messages carry a stable "forbidden:" prefix
      // that the negative fixtures assert against.
      "no-restricted-syntax": [
        "error",
        {
          selector: "CallExpression[callee.name='eval']",
          message: "forbidden: eval() executes ambient strings.",
        },
        {
          selector: "NewExpression[callee.name='Date'][arguments.length=0]",
          message: "forbidden: new Date() reads the ambient clock; inject time explicitly.",
        },
      ],
    },
  },
);
