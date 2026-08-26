"""
Shared pytest configuration: hypothesis profile registration.

The ``ci`` profile activates only when ``CI=true`` (as the coverage gate does):
200 examples, no deadline, derandomization off so exploration stays broad
while failures still reproduce through the example database.
"""

import os

from hypothesis import settings

settings.register_profile("ci", max_examples=200, deadline=None, derandomize=False)
settings.register_profile(
    "default",
    max_examples=50,
    deadline=None,
    derandomize=False,
)

if os.getenv("CI", "").strip().lower() == "true":
    settings.load_profile("ci")
