/**
 * Deliberately type-unsafe code: a wrong-type initializer and unannotated
 * parameters.
 *
 * The types gate must reject both patterns; assert.sh scopes `tsc -p` at
 * this directory via its own tsconfig.json and expects `error TS2322` among
 * the diagnostics. See bad_examples/README.md for the manifest.
 */

const unitsTotal: number = "3";

function combine(rawLeft, rawRight): number {
  const left = rawLeft;
  const right = rawRight;
  return left + right;
}

export const combineUnits = combine;
