"""Deliberate untracked work note that the lint gate must reject.

The comment below carries no author tag and no issue link, which the TODO
rules forbid. See bad_examples/README.md for the manifest of signals.
"""


def unfinished() -> None:
    """Stub whose comment violates the TODO rules."""
    # TODO: wire this to the real pipeline
