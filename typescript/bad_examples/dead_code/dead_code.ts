/**
 * Deliberate dead code: an exported helper nothing ever imports.
 *
 * Expected signal: knip reports the unused export "orphanedHelper" when
 * assert.sh copies this file into src/ for one run. See
 * bad_examples/README.md for the manifest of expected signals.
 */
export function orphanedHelper(units: number): number {
  return units * 2;
}
