/**
 * Deliberate dead code: an exported helper nothing ever imports.
 *
 * assert.sh uses this fixture to prove both layers of knip's dead-code
 * detection: copying the file into src/ must surface as an unused FILE
 * ("_tmp_dead_code_fixture.ts"), and appending a dead export to a reachable
 * module (src/domain/sku.ts) must surface as an unused EXPORT
 * ("_tmpDeadExportProbe"). The export-level proof holds only while
 * src/index.ts forwards symbols by explicit name rather than through an
 * `export *` barrel. See bad_examples/README.md for the manifest of
 * expected signals.
 */
export function orphanedHelper(units: number): number {
  return units * 2;
}
