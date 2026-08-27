# Negative fixtures

One subdirectory per gated rule class. Each fixture is deliberately broken
code that its gate must reject; `assert.sh` proves every rejection still
happens. Fixtures are excluded from `Warehouse.sln` by construction — never
via inline suppressions.

| fixture      | gate    | expected signal                         |
| ------------ | ------- | --------------------------------------- |
| unformatted  | format  | `dotnet format --verify-no-changes`     |
| compile_fail | compile | `CS0029` (string assigned to `int`)     |
