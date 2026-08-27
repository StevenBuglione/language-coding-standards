# Contract v2 conformance vectors

Language-independent behavior contract for the warehouse-order sample.

| File | Role |
| --- | --- |
| `schema.json` | JSON Schema for suite documents |
| `catalog.json` | Required case ids and shared numeric limits |
| `gaps.json` | Vectors the audited baseline still fails |
| `suites/*.json` | Inputs and expected outcomes every language must load |
| `validate.py` | Stdlib-only structural validator |
| `tests/test_validate.py` | Validator and on-disk suite tests |

## Validate

From the repository root:

```bash
python conformance/v2/validate.py
python -m unittest discover -s conformance/v2/tests
```

`PASS` means the vectors are well-formed. It does **not** mean any language
pack implements them. Language adapters are WP4. Until then,
`gaps.json` is the expected failure list, including successful placement
persisting `PAID`.

## Integer encoding

Amounts, quantities, versions, and call counts are decimal strings so
values such as `9007199254740992` stay lossless in JSON. Booleans appear
only in the quantity cases that prove booleans are not integers.

## Currency

ISO-style `[A-Z]{3}`. `ZZZ` is valid. This is not ISO-4217 membership.
