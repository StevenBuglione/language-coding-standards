# Negative fixtures

Deliberately violating code that every implemented gate must reject on demand
(CONTRACTS.md §4). `assert.sh` invokes ktlint scoped to each fixture file,
asserts a nonzero exit plus the expected stable signal from the manifest table
at the top of the script.

| Fixture class | Directory | Trips gate | Signal |
| --- | --- | --- | --- |
| `Unformatted` | `unformatted/` | format (`ktlintCheck`) | `standard:indent` |
| `WildcardImport` | `lint/` | lint (`ktlint` style) | `no-wildcard-imports` |

Fixtures live outside production source sets so the main `ktlintCheck` never
sees them. Deleting this directory without deleting the `negative-fixtures`
phase removes the proof that the gates bite.
