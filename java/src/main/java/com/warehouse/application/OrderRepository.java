package com.warehouse.application;

import com.warehouse.domain.DomainError.PersistenceConflictError;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;
import java.util.Optional;

/**
 * Outbound port that persists and retrieves immutable snapshots.
 *
 * <p>Reads and writes never expose a mutable alias to stored state.
 */
public interface OrderRepository {

  /**
   * Fingerprint and snapshot of a previous successful command, used for idempotent replay.
   *
   * @param fingerprint stable identity of the original payload
   * @param order detached snapshot of the persisted paid order
   */
  record IdempotencyRecord(String fingerprint, Order order) {}

  /**
   * Persists {@code order} under compare-and-set version rules and returns a snapshot.
   *
   * @param order the order to store under its identifier
   * @param expectedVersion the version the caller believes is currently stored ({@code 0} for a new
   *     aggregate)
   * @return the persisted snapshot, or a typed conflict when the expected version does not match
   */
  SaveOutcome save(Order order, int expectedVersion);

  /**
   * Looks up an order by identifier; absence never raises.
   *
   * @param orderId the identifier to look up
   * @return a stored snapshot, or empty for an unknown identifier
   */
  Optional<Order> get(OrderId orderId);

  /**
   * Looks up a previous successful command by idempotency key.
   *
   * @param key the command idempotency key
   * @return fingerprint and snapshot, or empty when this key has not succeeded
   */
  Optional<IdempotencyRecord> getByIdempotencyKey(String key);

  /**
   * Records a successful command so retries can replay the snapshot.
   *
   * @param key the command idempotency key
   * @param fingerprint stable identity of the payload
   * @param order the persisted paid snapshot
   */
  void rememberIdempotency(String key, String fingerprint, Order order);

  /** Outcome vocabulary of an optimistic save. */
  sealed interface SaveOutcome permits SaveOutcome.Saved, SaveOutcome.Conflict {

    /**
     * Success payload: the stored snapshot after the version bump.
     *
     * @param snapshot detached copy of what is now stored
     */
    record Saved(Order snapshot) implements SaveOutcome {}

    /** Failure payload: the compare-and-set lost a race. */
    record Conflict(PersistenceConflictError error) implements SaveOutcome {}
  }
}
