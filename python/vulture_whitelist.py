"""
Vulture whitelist: names reported dead but kept deliberately.

Each entry silences exactly one false positive, with the reason it exists.
The deadcode gate runs ``vulture src vulture_whitelist.py --min-confidence 80``;
add entries here only when vulture flags code that is genuinely used through a
mechanism it cannot see. Keep the list minimal — a growing whitelist is a
smell the negative fixtures cannot cover.
"""
