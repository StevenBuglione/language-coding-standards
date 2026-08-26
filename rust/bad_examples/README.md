# Negative fixtures

One subdirectory per gated rule class. Each fixture is deliberately broken
code that its gate must reject; `assert.sh` proves every rejection still
happens (the `negative` phase of `verify.sh`). Fixtures are excluded from
main tooling by construction: the root `[workspace]` excludes this directory
AND every fixture manifest declares its own empty `[workspace]` table — no
inline suppressions anywhere.

| fixture          | gate     | expected signal                                   |
| ---------------- | -------- | ------------------------------------------------- |
| too_complex      | lint     | `clippy::too_many_lines` (>30 lines)              |
| unwrap_used      | lint     | `clippy::unwrap_used`                             |
| indexing_slicing | lint     | `clippy::indexing_slicing`                        |
| print_stdout     | lint     | `clippy::print_stdout`                            |
| todo_macro       | lint     | `clippy::todo`                                    |
| dead_code        | deadcode | compiler `dead_code`: "never used"                |
| pub_api_leak     | arch     | `unreachable_pub` under `-D warnings`             |
| unsafe_block     | types    | compile error (`unsafe_code = "forbid"`)          |
| unformatted      | format   | rustfmt diff (`Diff in`)                          |

Notes:

- The brief's cross-crate arch_violation idea was replaced by
  `pub_api_leak`: workspace lints cannot see into a foreign crate, so a
  dependency-direction fixture would prove nothing real. The layering rule
  itself is enforced by the arch phase over the REAL workspace via
  `cargo tree`; `pub_api_leak` is the negative proof of the
  pub-by-default backstop that supports it. Mapping change documented in
  LANG_SPEC.md.
- The complexity ceiling uses `too_many_lines` because clippy's
  `cognitive_complexity` no longer emits on current clippy; the swap is
  documented in LANG_SPEC.md (Deliberate non-enforcements).
- Clippy fixtures are probed through `--message-format=json` because human
  output renders lint names unstably; JSON carries the machine-readable
  code.
