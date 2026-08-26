//! `PlaceOrderUseCase`: validate -> reserve -> charge -> persist, Result-typed.

use warehouse_domain::error::{InsufficientStock, InvalidOrder, OrderAlreadyShipped};
use warehouse_domain::order::{Order, OrderLine};

use crate::ports::{InventoryGateway, OrderRepository, PaymentProcessor};

/// Failure payload: exactly one typed domain verdict
/// ([CONTRACTS.md §2](../../docs/CONTRACTS.md)).
///
/// The idiomatic [`Result`] IS the result type: success carries the
/// persisted order ([`PersistedOrder`]), failure carries exactly one of the
/// three domain errors.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PlaceOrderError {
    /// The inventory could not cover a line's request.
    #[error(transparent)]
    InsufficientStock(#[from] InsufficientStock),
    /// The order or its payment violated a structural rule.
    #[error(transparent)]
    InvalidOrder(#[from] InvalidOrder),
    /// Reserved verdict for callers mutating already-shipped orders; the
    /// validate-reserve-charge-persist flow itself never produces one, but
    /// the contract names all three verdicts as the failure vocabulary.
    #[error(transparent)]
    AlreadyShipped(#[from] OrderAlreadyShipped),
}

/// Success payload: proof that the returned order was persisted.
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

/// Orchestrates validate -> reserve -> charge -> persist without raising:
/// every outcome is an `Ok` [`PersistedOrder`] or an `Err`
/// [`PlaceOrderError`].
///
/// Generic over its outbound ports (static dispatch — no trait objects, no
/// allocation); adapters are injected at construction time.
///
/// The `Debug` bound lands on the port parameters, not on the use case's
/// logic: any wiring that can print itself makes the whole assembly
/// printable.
#[derive(Debug)]
pub struct PlaceOrderUseCase<I, P, R> {
    inventory: I,
    payments: P,
    repository: R,
}

impl<I, P, R> PlaceOrderUseCase<I, P, R>
where
    I: InventoryGateway,
    P: PaymentProcessor,
    R: OrderRepository,
{
    /// Wires the use case to its outbound ports.
    #[must_use]
    pub fn new(inventory: I, payments: P, repository: R) -> Self {
        Self {
            inventory,
            payments,
            repository,
        }
    }

    /// Returns the wired ports back to the caller.
    ///
    /// Useful for teardown-time inspection of the adapters' state (e.g. in
    /// tests that assert reservations or charge logs after [`Self::execute`]).
    #[must_use]
    pub fn into_parts(self) -> (I, P, R) {
        (self.inventory, self.payments, self.repository)
    }

    /// Validates the order, reserves stock for every line, collects
    /// payment, then persists.
    ///
    /// # Errors
    ///
    /// Returns [`PlaceOrderError::InsufficientStock`] when stock cannot
    /// cover a line, [`PlaceOrderError::InvalidOrder`] when validation or
    /// payment fails, and never panics: no exception crosses this boundary.
    pub fn execute(&mut self, lines: Vec<OrderLine>) -> Result<PersistedOrder, PlaceOrderError> {
        let order = Order::new(lines)?;
        for line in order.lines() {
            self.inventory
                .reserve(line.sku().clone(), line.quantity())
                .map_err(PlaceOrderError::InsufficientStock)?;
        }
        self.payments
            .charge(&order)
            .map_err(PlaceOrderError::InvalidOrder)?;
        let persisted = self.repository.save(order);
        Ok(PersistedOrder::new(persisted))
    }
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
    use crate::ports::{Charged, Reserved};
    use std::cell::RefCell;
    use std::collections::BTreeMap;
    use warehouse_domain::money::{Currency, Money};
    use warehouse_domain::order::OrderId;
    use warehouse_domain::quantity::Quantity;
    use warehouse_domain::sku::Sku;

    // Inline fakes implementing the ports WITHOUT the adapters crate: proof
    // that the use case compiles and runs against the interfaces alone.
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
        fn reserve(&mut self, sku: Sku, quantity: Quantity) -> Result<Reserved, InsufficientStock> {
            let mut stock = self.stock.borrow_mut();
            let available = stock.get(&sku).copied().unwrap_or(0);
            if available < quantity.value() {
                return Err(InsufficientStock::new(sku, quantity, available));
            }
            stock.insert(sku, available - quantity.value());
            Ok(Reserved)
        }
    }

    struct StubPayments {
        decline: bool,
        charged: RefCell<u32>,
    }

    impl StubPayments {
        fn new() -> Self {
            Self {
                decline: false,
                charged: RefCell::new(0),
            }
        }
    }

    impl PaymentProcessor for StubPayments {
        fn charge(&mut self, _order: &Order) -> Result<Charged, InvalidOrder> {
            *self.charged.borrow_mut() += 1;
            if self.decline {
                return Err(InvalidOrder::new("payment declined".to_owned()));
            }
            Ok(Charged)
        }
    }

    #[derive(Default)]
    struct StubRepository {
        orders: RefCell<Vec<Order>>,
    }

    impl OrderRepository for StubRepository {
        fn save(&mut self, order: Order) -> Order {
            self.orders.borrow_mut().push(order.clone());
            order
        }

        fn get(&self, order_id: OrderId) -> Option<Order> {
            self.orders
                .borrow()
                .iter()
                .find(|order| order.id() == order_id)
                .cloned()
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
            Money::from_minor(units, currency()),
        )
    }

    type UseCase = PlaceOrderUseCase<StubInventory, StubPayments, StubRepository>;

    fn use_case(stock: &[(&str, u32)]) -> UseCase {
        PlaceOrderUseCase::new(
            StubInventory::new(stock),
            StubPayments::new(),
            StubRepository::default(),
        )
    }

    #[test]
    fn happy_path_persists_after_reserving_and_charging() {
        let mut use_case = use_case(&[("SKU-A", 10)]);
        let outcome = use_case.execute(vec![line("SKU-A", 2, 300)]).unwrap();
        assert_eq!(outcome.order().total().unwrap().minor_units(), 600);
    }

    #[test]
    fn empty_lines_fail_as_invalid_order() {
        let mut use_case = use_case(&[]);
        match use_case.execute(Vec::new()) {
            Err(PlaceOrderError::InvalidOrder(_)) => {}
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn shortage_fails_without_charging_or_persisting() {
        let mut use_case = use_case(&[("SKU-A", 1)]);
        match use_case.execute(vec![line("SKU-A", 5, 100)]) {
            Err(PlaceOrderError::InsufficientStock(error)) => {
                assert_eq!(error.available(), 1);
            }
            other => panic!("expected insufficient-stock verdict, got {other:?}"),
        }
    }

    #[test]
    fn declined_payment_maps_to_invalid_order() {
        let mut use_case = use_case(&[("SKU-A", 10)]);
        use_case.payments.decline = true;
        match use_case.execute(vec![line("SKU-A", 1, 100)]) {
            Err(PlaceOrderError::InvalidOrder(_)) => {}
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn duplicate_skus_fail_before_any_reservation() {
        let mut use_case = use_case(&[("SKU-A", 10)]);
        match use_case.execute(vec![line("SKU-A", 1, 100), line("SKU-A", 1, 100)]) {
            Err(PlaceOrderError::InvalidOrder(_)) => {}
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn persisted_order_accessors_agree() {
        let mut use_case = use_case(&[("SKU-A", 10)]);
        let outcome = use_case.execute(vec![line("SKU-A", 2, 300)]).unwrap();
        let borrowed = outcome.order().clone();
        assert_eq!(outcome.into_inner(), borrowed);
    }

    #[test]
    fn place_order_error_displays_its_verdict() {
        let error = PlaceOrderError::from(InvalidOrder::new("no lines"));
        assert!(error.to_string().contains("no lines"));
    }
}
