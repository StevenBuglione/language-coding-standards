/**
 * Deliberate eval() usage that the custom no-restricted-syntax ban must
 * reject (there is no maintained free TypeScript SAST; the eval and ambient-
 * clock bans are configured explicitly in eslint.config.js — LANG_SPEC.md
 * documents this choice). See bad_examples/README.md for the manifest.
 */
export function evaluateExpression(raw: string): unknown {
  return eval(raw);
}
