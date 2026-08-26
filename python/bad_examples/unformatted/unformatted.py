"""Deliberately misformatted source that the format gate must reject.

See bad_examples/README.md for the manifest of expected signals.
"""


def badly_spaced( amount:int ):
    totals={ 'units':   amount }
    return  totals['units']+1
