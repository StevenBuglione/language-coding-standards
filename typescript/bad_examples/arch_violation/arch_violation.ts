/**
 * Deliberate boundary breach: the domain reaching out to adapters.
 *
 * The layered contract must reject this module when assert.sh copies it into
 * src/domain/ for one depcruise run. NOTE: the import path is written
 * relative to that destination ("../adapters/inventory" from src/domain/),
 * because this file is only ever analyzed from there — never from its
 * fixture location, where every tooling glob excludes it.
 */

import { InMemoryInventoryGateway } from "../adapters/inventory";

export const forbiddenDomainToAdapterEdge = new InMemoryInventoryGateway();
