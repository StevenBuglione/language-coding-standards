/**
 * Deliberate read of the ambient clock, which the lint gate forbids.
 *
 * `new Date()` without arguments hides a non-deterministic dependency;
 * time must be injected explicitly. The ban is a custom no-restricted-syntax
 * selector documented in eslint.config.js and LANG_SPEC.md. See
 * bad_examples/README.md for the manifest of expected signals.
 */
export function auditStamp(): Date {
  return new Date();
}
