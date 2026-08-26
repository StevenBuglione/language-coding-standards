/**
 * Deliberate console output that the lint gate must reject.
 *
 * See bad_examples/README.md for the manifest of expected signals.
 */
export function debugPipeline(): void {
  console.log("debug: entering order pipeline");
}
