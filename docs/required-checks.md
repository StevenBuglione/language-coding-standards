# Required status checks

Until a GitHub ruleset is applied, this is the intended protection set for
`main`. Administrators must not routinely bypass it.

## Always required

- `meta / Lint GitHub workflows + enforce LF`
- `meta / Lint Dockerfiles`
- `meta / Secret scan`
- `meta / Enforce action pinning policy`
- `meta / Manifest + conformance schema`

## Required for implemented languages

Each language workflow exposes reusable jobs:

- `<lang> / verify / static gates`
- `<lang> / verify / tests and coverage`
- `<lang> / verify / supply chain`

Languages: `go`, `java`, `python`, `rust`, `typescript`.

A ruleset must require this **stable aggregate set**, not dynamically
disappearing names. After the jobs are observed green on `main`, enable:

- target: `main`
- require the checks above
- block force pushes and deletion
- require pull requests and one review once the repository leaves the
  bootstrap window
- dismiss stale approvals
- limit bypass to a documented emergency role

`full` is scheduled and is not a pull-request required check.

This file is the source for ruleset configuration (WP7). Applying it in
GitHub requires repository admin access and is not completed by a code
commit alone.
