"""Deliberate boundary breach: the domain reaching out to adapters.

The layered contract must reject this module when assert.sh copies it into
``src/warehouse/domain/`` for the arch phase to inspect.
"""

from warehouse.adapters.inventory import InMemoryInventoryGateway
from warehouse.domain.quantity import Quantity
from warehouse.domain.sku import Sku

_GATEWAY = InMemoryInventoryGateway()


def reserve_directly(code: str, amount: int) -> object:
    """Domain logic must never touch adapter implementations."""
    return _GATEWAY.reserve(Sku(code), Quantity(amount))
