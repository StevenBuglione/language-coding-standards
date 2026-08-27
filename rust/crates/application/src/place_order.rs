//! `PlaceOrderUseCase`: validate, reserveAll, charge, pay, persist, compensate.

use warehouse_domain::error::{
    CompensationFailure, DomainError, InsufficientStock, InvalidOrder, PaymentDeclined,
    PersistenceConflict,
};
use warehouse_domain::order::{Order, OrderLine};

use crate::ports::{
    ChargeReceipt, InventoryGateway, OrderIdGenerator, OrderRepository, PaymentProcessor,
    ReservationToken,
};

/// Failure payload: exactly one typed domain verdict
/// ([CONTRACTS.md §2](../../docs/CONTRACTS.md)).
///
/// Decline is [`PlaceOrderError::PaymentDeclined`], never
/// [`PlaceOrderError::InvalidOrder`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PlaceOrderError {
    /// The inventory could not cover a line's request.
    #[error(transparent)]
    InsufficientStock(#[from] InsufficientStock),
    /// The order violated a structural rule (including idempotency reuse).
    #[error(transparent)]
    InvalidOrder(#[from] InvalidOrder),
    /// The payment processor refused the charge.
    #[error(transparent)]
    PaymentDeclined(#[from] PaymentDeclined),
    /// Optimistic save lost a compare-and-set race.
    #[error(transparent)]
    PersistenceConflict(#[from] PersistenceConflict),
    /// Refund or release failed after a partial success.
    #[error(transparent)]
    CompensationFailure(#[from] CompensationFailure),
}

/// Success payload: proof that the returned order was persisted as `PAID`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PersistedOrder {
    order: Order,
}

impl PersistedOrder {
    /// Wraps an order that has already been saved.
    #[must_use]
    pub fn new(order: Order) -> Self {
        Self { order }
    }

    /// Consumes the wrapper and returns the persisted order.
    #[must_use]
    pub fn into_inner(self) -> Order {
        self.order
    }

    /// Borrows the persisted order.
    #[must_use]
    pub fn order(&self) -> &Order {
        &self.order
    }
}

/// Orchestrates the v2 place-order policy without panicking.
///
/// Generic over its outbound ports (static dispatch — no trait objects);
/// adapters are injected at construction time.
#[derive(Debug)]
pub struct PlaceOrderUseCase<I, P, R, G> {
    inventory: I,
    payments: P,
    repository: R,
    ids: G,
}

impl<I, P, R, G> PlaceOrderUseCase<I, P, R, G>
where
    I: InventoryGateway,
    P: PaymentProcessor,
    R: OrderRepository,
    G: OrderIdGenerator,
{
    /// Wires the use case to its outbound ports.
    #[must_use]
    pub fn new(inventory: I, payments: P, repository: R, ids: G) -> Self {
        Self {
            inventory,
            payments,
            repository,
            ids,
        }
    }

    /// Returns the wired ports back to the caller.
    #[must_use]
    pub fn into_parts(self) -> (I, P, R, G) {
        (self.inventory, self.payments, self.repository, self.ids)
    }

    /// Validates, reserves, charges, marks `PAID`, persists; compensates
    /// on failure. Retrying the same key and payload does not double-charge.
    ///
    /// # Errors
    ///
    /// Returns a typed [`PlaceOrderError`] for validation, shortage,
    /// decline, conflict, or compensation failure. Never panics.
    pub fn execute(
        &self,
        lines: Vec<OrderLine>,
        idempotency_key: &str,
    ) -> Result<PersistedOrder, PlaceOrderError> {
        if let Some(replayed) = self.replay(idempotency_key, &lines)? {
            return Ok(replayed);
        }
        let mut order = Order::new(self.ids.next(), lines)?;
        let reserved = self.reserve(&order, idempotency_key)?;
        let receipt = self.charge(&order, &reserved, idempotency_key)?;
        self.pay_or_compensate(&mut order, &reserved, &receipt)?;
        self.persist(&order, &reserved, &receipt, idempotency_key)
    }

    fn replay(
        &self,
        key: &str,
        lines: &[OrderLine],
    ) -> Result<Option<PersistedOrder>, PlaceOrderError> {
        let Some((prior, snapshot)) = self.repository.get_by_idempotency_key(key) else {
            return Ok(None);
        };
        if prior == fingerprint(lines) {
            return Ok(Some(PersistedOrder::new(snapshot)));
        }
        Err(PlaceOrderError::InvalidOrder(InvalidOrder::new(
            "idempotency key reused with different payload",
        )))
    }

    fn reserve(
        &self,
        order: &Order,
        idempotency_key: &str,
    ) -> Result<ReservationToken, PlaceOrderError> {
        self.inventory
            .reserve_all(order.id(), order.lines(), idempotency_key)
            .map_err(PlaceOrderError::InsufficientStock)
    }

    fn charge(
        &self,
        order: &Order,
        reserved: &ReservationToken,
        idempotency_key: &str,
    ) -> Result<ChargeReceipt, PlaceOrderError> {
        match self.payments.charge(order, idempotency_key) {
            Ok(receipt) => Ok(receipt),
            Err(declined) => Err(self.release_or_fail(reserved, declined)),
        }
    }

    fn pay_or_compensate(
        &self,
        order: &mut Order,
        reserved: &ReservationToken,
        receipt: &ChargeReceipt,
    ) -> Result<(), PlaceOrderError> {
        match order.pay() {
            Ok(()) => Ok(()),
            Err(error) => Err(self.compensate_then(reserved, receipt, from_pay(error))),
        }
    }

    fn persist(
        &self,
        order: &Order,
        reserved: &ReservationToken,
        receipt: &ChargeReceipt,
        idempotency_key: &str,
    ) -> Result<PersistedOrder, PlaceOrderError> {
        match self.repository.save(order, order.version()) {
            Ok(saved) => {
                self.remember(idempotency_key, order.lines(), &saved);
                Ok(PersistedOrder::new(saved))
            }
            Err(conflict) => Err(self.compensate_then(
                reserved,
                receipt,
                PlaceOrderError::PersistenceConflict(conflict),
            )),
        }
    }

    fn remember(&self, key: &str, lines: &[OrderLine], saved: &Order) {
        self.repository
            .remember_idempotency(key, &fingerprint(lines), saved);
    }

    fn release_or_fail(
        &self,
        token: &ReservationToken,
        declined: PaymentDeclined,
    ) -> PlaceOrderError {
        match self.inventory.release(token) {
            Ok(()) => PlaceOrderError::PaymentDeclined(declined),
            Err(failure) => PlaceOrderError::CompensationFailure(failure),
        }
    }

    fn compensate_then(
        &self,
        token: &ReservationToken,
        receipt: &ChargeReceipt,
        fallback: PlaceOrderError,
    ) -> PlaceOrderError {
        let refunded = self.payments.refund(receipt);
        let released = self.inventory.release(token);
        if let Err(failure) = refunded {
            return PlaceOrderError::CompensationFailure(failure);
        }
        if let Err(failure) = released {
            return PlaceOrderError::CompensationFailure(failure);
        }
        fallback
    }
}

fn from_pay(error: DomainError) -> PlaceOrderError {
    match error {
        DomainError::InvalidOrder(error) => PlaceOrderError::InvalidOrder(error),
        DomainError::AlreadyShipped(error) => {
            PlaceOrderError::InvalidOrder(InvalidOrder::new(error.to_string()))
        }
        DomainError::InsufficientStock(_) => {
            PlaceOrderError::InvalidOrder(InvalidOrder::new("unexpected stock error during pay"))
        }
    }
}

fn fingerprint(lines: &[OrderLine]) -> String {
    let parts: Vec<String> = lines
        .iter()
        .map(|line| {
            format!(
                "{}:{}:{}:{}",
                line.sku().code(),
                line.quantity().value(),
                line.unit_price().currency(),
                line.unit_price().minor_units(),
            )
        })
        .collect();
    parts.join("|")
}

#[cfg(test)]
mod tests {
    // Documented test-side suppressions (see domain/src/order.rs).
    #![allow(
        clippy::unwrap_used,
        reason = "tests build known-valid values and read errors"
    )]
    #![allow(clippy::panic, reason = "a failed assertion IS the test failing")]

    use super::*;
    use crate::ports::{ChargeReceipt, OrderIdGenerator, ReservationToken};
    use std::cell::RefCell;
    use std::collections::BTreeMap;
    use warehouse_domain::money::{Currency, Money};
    use warehouse_domain::order::{OrderId, OrderStatus};
    use warehouse_domain::quantity::Quantity;
    use warehouse_domain::sku::Sku;

    struct StubInventory {
        stock: RefCell<BTreeMap<Sku, u32>>,
    }

    impl StubInventory {
        fn new(stock: &[(&str, u32)]) -> Self {
            let map = stock
                .iter()
                .map(|(code, amount)| (Sku::new(*code).unwrap(), *amount))
                .collect();
            Self {
                stock: RefCell::new(map),
            }
        }
    }

    impl InventoryGateway for StubInventory {
        fn reserve_all(
            &self,
            order_id: &OrderId,
            lines: &[OrderLine],
            key: &str,
        ) -> Result<ReservationToken, InsufficientStock> {
            debit(&mut self.stock.borrow_mut(), lines)?;
            Ok(ReservationToken::new(order_id.clone(), key))
        }

        fn release(&self, _token: &ReservationToken) -> Result<(), CompensationFailure> {
            Ok(())
        }
    }

    fn debit(stock: &mut BTreeMap<Sku, u32>, lines: &[OrderLine]) -> Result<(), InsufficientStock> {
        for line in lines {
            let available = stock.get(line.sku()).copied().unwrap_or(0);
            if available < line.quantity().value() {
                return Err(InsufficientStock::new(
                    line.sku().clone(),
                    line.quantity(),
                    available,
                ));
            }
        }
        for line in lines {
            if let Some(available) = stock.get_mut(line.sku()) {
                *available -= line.quantity().value();
            }
        }
        Ok(())
    }

    struct StubPayments {
        decline: bool,
        charged: RefCell<u32>,
    }

    impl StubPayments {
        fn new(decline: bool) -> Self {
            Self {
                decline,
                charged: RefCell::new(0),
            }
        }
    }

    impl PaymentProcessor for StubPayments {
        fn charge(&self, order: &Order, key: &str) -> Result<ChargeReceipt, PaymentDeclined> {
            *self.charged.borrow_mut() += 1;
            if self.decline {
                return Err(PaymentDeclined::new("payment declined".to_owned()));
            }
            Ok(ChargeReceipt::new(order.id().clone(), key))
        }

        fn refund(&self, _receipt: &ChargeReceipt) -> Result<(), CompensationFailure> {
            Ok(())
        }
    }

    #[derive(Default)]
    struct StubRepository {
        orders: RefCell<Vec<Order>>,
    }

    impl OrderRepository for StubRepository {
        fn save(
            &self,
            order: &Order,
            _expected_version: u32,
        ) -> Result<Order, PersistenceConflict> {
            let saved = order.snapshot();
            self.orders.borrow_mut().push(saved.clone());
            Ok(saved)
        }

        fn get(&self, order_id: &OrderId) -> Option<Order> {
            self.orders
                .borrow()
                .iter()
                .find(|order| order.id() == order_id)
                .cloned()
        }

        fn get_by_idempotency_key(&self, _key: &str) -> Option<(String, Order)> {
            None
        }

        fn remember_idempotency(&self, _key: &str, _fingerprint: &str, _order: &Order) {}
    }

    struct StubIds;

    impl OrderIdGenerator for StubIds {
        fn next(&self) -> OrderId {
            OrderId::from_sequence(1)
        }
    }

    fn currency() -> Currency {
        Currency::new("EUR").unwrap()
    }

    fn sku(code: &str) -> Sku {
        Sku::new(code).unwrap()
    }

    fn line(code: &str, amount: u32, units: u64) -> OrderLine {
        OrderLine::new(
            sku(code),
            Quantity::new(amount).unwrap(),
            Money::from_minor(units, currency()).unwrap(),
        )
    }

    type UseCase = PlaceOrderUseCase<StubInventory, StubPayments, StubRepository, StubIds>;

    fn use_case(stock: &[(&str, u32)]) -> UseCase {
        wired(stock, false)
    }

    fn wired(stock: &[(&str, u32)], decline: bool) -> UseCase {
        PlaceOrderUseCase::new(
            StubInventory::new(stock),
            StubPayments::new(decline),
            StubRepository::default(),
            StubIds,
        )
    }

    #[test]
    fn happy_path_persists_paid_after_reserving_and_charging() {
        let use_case = use_case(&[("SKU-A", 10)]);
        let outcome = use_case
            .execute(vec![line("SKU-A", 2, 300)], "idem-1")
            .unwrap();
        assert_eq!(outcome.order().status(), OrderStatus::Paid);
        assert_eq!(outcome.order().total().unwrap().minor_units(), 600);
    }

    #[test]
    fn empty_lines_fail_as_invalid_order() {
        let use_case = use_case(&[]);
        match use_case.execute(Vec::new(), "idem-empty") {
            Err(PlaceOrderError::InvalidOrder(_)) => {}
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn shortage_fails_without_charging_or_persisting() {
        let use_case = use_case(&[("SKU-A", 1)]);
        match use_case.execute(vec![line("SKU-A", 5, 100)], "idem-short") {
            Err(PlaceOrderError::InsufficientStock(error)) => {
                assert_eq!(error.available(), 1);
            }
            other => panic!("expected insufficient-stock verdict, got {other:?}"),
        }
    }

    #[test]
    fn declined_payment_is_not_invalid_order() {
        let use_case = wired(&[("SKU-A", 10)], true);
        match use_case.execute(vec![line("SKU-A", 1, 100)], "idem-declined") {
            Err(PlaceOrderError::PaymentDeclined(_)) => {}
            other => panic!("expected payment-declined verdict, got {other:?}"),
        }
    }

    #[test]
    fn duplicate_skus_fail_before_any_reservation() {
        let use_case = use_case(&[("SKU-A", 10)]);
        let lines = vec![line("SKU-A", 1, 100), line("SKU-A", 1, 100)];
        match use_case.execute(lines, "idem-dup") {
            Err(PlaceOrderError::InvalidOrder(_)) => {}
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn persisted_order_accessors_agree() {
        let use_case = use_case(&[("SKU-A", 10)]);
        let outcome = use_case
            .execute(vec![line("SKU-A", 2, 300)], "idem-acc")
            .unwrap();
        let borrowed = outcome.order().clone();
        assert_eq!(outcome.into_inner(), borrowed);
    }

    #[test]
    fn place_order_error_displays_its_verdict() {
        let error = PlaceOrderError::from(InvalidOrder::new("no lines"));
        assert!(error.to_string().contains("no lines"));
    }

    #[test]
    fn reservation_token_exposes_its_parts() {
        let token = ReservationToken::new(OrderId::from_sequence(1), "idem");
        assert_eq!(token.order_id().value(), "ord-1");
        assert_eq!(token.idempotency_key(), "idem");
    }
}
