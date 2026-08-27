//! Integration tests: happy path plus each failure path, driven through
//! the REAL adapter doubles ([CONTRACTS.md §2](../../docs/CONTRACTS.md)).
//!
//! This test target is the one sanctioned place where the application layer
//! looks outward: dev-dependencies may wire `warehouse-adapters` into the
//! use case, production code may not.

// Documented test-side suppressions (see crates/domain/src/order.rs).
#![allow(
    clippy::unwrap_used,
    reason = "tests build known-valid values and read errors"
)]
#![allow(clippy::panic, reason = "a failed assertion IS the test failing")]

use std::collections::BTreeMap;
use std::thread;

use warehouse_adapters::ids::FixedOrderIdGenerator;
use warehouse_adapters::inventory::InMemoryInventoryGateway;
use warehouse_adapters::payments::FakePaymentProcessor;
use warehouse_adapters::repository::InMemoryOrderRepository;
use warehouse_application::place_order::{PersistedOrder, PlaceOrderError, PlaceOrderUseCase};
use warehouse_application::ports::OrderRepository;
use warehouse_domain::money::{Currency, Money};
use warehouse_domain::order::{Order, OrderId, OrderLine, OrderStatus};
use warehouse_domain::quantity::Quantity;
use warehouse_domain::sku::Sku;

type Pipeline = PlaceOrderUseCase<
    InMemoryInventoryGateway,
    FakePaymentProcessor,
    InMemoryOrderRepository,
    FixedOrderIdGenerator,
>;

fn currency() -> Currency {
    Currency::new("EUR").unwrap()
}

fn line(code: &str, quantity_value: u32, units: u64) -> OrderLine {
    OrderLine::new(
        Sku::new(code).unwrap(),
        Quantity::new(quantity_value).unwrap(),
        Money::from_minor(units, currency()).unwrap(),
    )
}

fn usd_line(code: &str, quantity_value: u32, units: u64) -> OrderLine {
    OrderLine::new(
        Sku::new(code).unwrap(),
        Quantity::new(quantity_value).unwrap(),
        Money::from_minor(units, Currency::new("USD").unwrap()).unwrap(),
    )
}

fn stock_map(pairs: &[(&str, u32)]) -> BTreeMap<Sku, u32> {
    pairs
        .iter()
        .map(|(code, units)| (Sku::new(*code).unwrap(), *units))
        .collect()
}

fn stock(pairs: &[(&str, u32)]) -> InMemoryInventoryGateway {
    InMemoryInventoryGateway::new(stock_map(pairs))
}

fn pipeline(pairs: &[(&str, u32)], decline: bool, order_id: &str) -> Pipeline {
    PlaceOrderUseCase::new(
        stock(pairs),
        FakePaymentProcessor::new(decline),
        InMemoryOrderRepository::new(),
        FixedOrderIdGenerator::new(OrderId::new(order_id).unwrap()),
    )
}

fn assert_paid(order: &Order, expected_id: &str, total: u64) {
    assert_eq!(order.id().value(), expected_id);
    assert_eq!(order.status(), OrderStatus::Paid);
    assert_eq!(order.version(), 1);
    assert_eq!(order.total().unwrap().minor_units(), total);
}

#[test]
fn happy_path_persists_paid() {
    let use_case = pipeline(&[("SKU-A", 10), ("SKU-B", 5)], false, "ord-1");
    let lines = vec![line("SKU-A", 2, 300), line("SKU-B", 1, 700)];
    let order = use_case.execute(lines, "idem-1").unwrap().into_inner();
    assert_paid(&order, "ord-1", 1_300);
    let (gateway, payments, repository, _) = use_case.into_parts();
    let stored = repository.get(order.id()).unwrap();
    assert_eq!(stored.status(), OrderStatus::Paid);
    assert_eq!(payments.charged_orders().len(), 1);
    assert_eq!(gateway.available(&Sku::new("SKU-A").unwrap()), 8);
}

#[test]
fn happy_path_decrements_stock_and_logs_the_charge() {
    let use_case = pipeline(&[("SKU-A", 10)], false, "ord-1");
    let order = use_case
        .execute(vec![line("SKU-A", 2, 300)], "idem-1")
        .unwrap();
    assert_eq!(order.order().status(), OrderStatus::Paid);
    let (gateway, payments, _, _) = use_case.into_parts();
    assert_eq!(gateway.available(&Sku::new("SKU-A").unwrap()), 8);
    assert_eq!(payments.charged_orders().len(), 1);
}

#[test]
fn insufficient_stock_fails_without_charging() {
    let use_case = pipeline(&[("SKU-A", 1), ("SKU-B", 0)], false, "ord-3");
    let lines = vec![line("SKU-A", 1, 300), line("SKU-B", 2, 100)];
    match use_case.execute(lines, "idem-3") {
        Err(PlaceOrderError::InsufficientStock(error)) => {
            assert_eq!(error.available(), 0);
            assert_eq!(error.sku().code(), "SKU-B");
        }
        other => panic!("expected insufficient-stock verdict, got {other:?}"),
    }
    let (_, payments, repository, _) = use_case.into_parts();
    assert!(payments.charged_orders().is_empty());
    assert_eq!(repository.get(&OrderId::new("ord-3").unwrap()), None);
}

#[test]
fn empty_lines_fail_as_invalid_order() {
    let use_case = pipeline(&[("SKU-A", 10)], false, "ord-2");
    match use_case.execute(Vec::new(), "idem-2") {
        Err(PlaceOrderError::InvalidOrder(error)) => {
            assert!(error.reason().contains("at least one line"));
        }
        other => panic!("expected invalid-order verdict, got {other:?}"),
    }
}

#[test]
fn duplicate_skus_fail_as_invalid_order() {
    let use_case = pipeline(&[("SKU-A", 5)], false, "ord-1");
    let lines = vec![line("SKU-A", 1, 300), line("SKU-A", 2, 700)];
    match use_case.execute(lines, "idem-dup") {
        Err(PlaceOrderError::InvalidOrder(error)) => {
            assert!(error.reason().contains("duplicate SKU"));
        }
        other => panic!("expected invalid-order verdict, got {other:?}"),
    }
}

#[test]
fn declined_payment_releases_reservation() {
    let use_case = pipeline(&[("SKU-A", 5)], true, "ord-4");
    match use_case.execute(vec![line("SKU-A", 1, 300)], "idem-4") {
        Err(PlaceOrderError::PaymentDeclined(error)) => {
            assert!(error.reason().contains("declined"));
        }
        other => panic!("expected payment-declined verdict, got {other:?}"),
    }
    let (gateway, payments, repository, _) = use_case.into_parts();
    assert_eq!(gateway.available(&Sku::new("SKU-A").unwrap()), 5);
    assert_eq!(payments.charged_orders().len(), 1);
    assert!(repository.saved().is_empty());
}

#[test]
fn save_failure_refunds_and_releases() {
    let inventory = stock(&[("SKU-A", 10)]);
    let payments = FakePaymentProcessor::new(false);
    let repository = InMemoryOrderRepository::new();
    repository.set_fail_save(true);
    let use_case = wired(inventory.clone(), payments.clone(), repository, "ord-5");
    match use_case.execute(vec![usd_line("SKU-A", 1, 500)], "idem-5") {
        Err(PlaceOrderError::PersistenceConflict(_)) => {}
        other => panic!("expected persistence conflict, got {other:?}"),
    }
    assert_eq!(payments.refunded().len(), 1);
    assert_eq!(inventory.available(&Sku::new("SKU-A").unwrap()), 10);
}

fn wired(
    inventory: InMemoryInventoryGateway,
    payments: FakePaymentProcessor,
    repository: InMemoryOrderRepository,
    order_id: &str,
) -> Pipeline {
    PlaceOrderUseCase::new(
        inventory,
        payments,
        repository,
        FixedOrderIdGenerator::new(OrderId::new(order_id).unwrap()),
    )
}

#[test]
fn compensation_failure_after_save_failure() {
    let payments = FakePaymentProcessor::new(false);
    let repository = InMemoryOrderRepository::new();
    repository.set_fail_save(true);
    payments.set_fail_refund(true);
    let use_case = wired(stock(&[("SKU-A", 10)]), payments, repository, "ord-6");
    match use_case.execute(vec![usd_line("SKU-A", 1, 500)], "idem-6") {
        Err(PlaceOrderError::CompensationFailure(error)) => {
            assert_eq!(error.stage(), "refund");
        }
        other => panic!("expected compensation failure, got {other:?}"),
    }
}

#[test]
fn idempotent_replay_does_not_double_charge() {
    let inventory = stock(&[("SKU-A", 10)]);
    let payments = FakePaymentProcessor::new(false);
    let use_case = wired(
        inventory.clone(),
        payments.clone(),
        InMemoryOrderRepository::new(),
        "ord-7",
    );
    let first = use_case.execute(vec![line("SKU-A", 2, 300)], "idem-7");
    let second = use_case.execute(vec![line("SKU-A", 2, 300)], "idem-7");
    assert_replay(first, second, &payments, &inventory);
}

fn assert_replay(
    first: Result<PersistedOrder, PlaceOrderError>,
    second: Result<PersistedOrder, PlaceOrderError>,
    payments: &FakePaymentProcessor,
    inventory: &InMemoryInventoryGateway,
) {
    let first = first.unwrap();
    let second = second.unwrap();
    assert_eq!(first.order().status(), OrderStatus::Paid);
    assert_eq!(second.order().id(), first.order().id());
    assert_eq!(payments.charged_orders().len(), 1);
    assert_eq!(inventory.available(&Sku::new("SKU-A").unwrap()), 8);
}

#[test]
fn reused_key_with_different_payload_is_invalid_order() {
    let use_case = pipeline(&[("SKU-A", 10)], false, "ord-8");
    use_case
        .execute(vec![usd_line("SKU-A", 1, 100)], "idem-8")
        .unwrap();
    match use_case.execute(vec![usd_line("SKU-A", 2, 100)], "idem-8") {
        Err(PlaceOrderError::InvalidOrder(error)) => {
            assert!(error.reason().contains("idempotency key reused"));
        }
        other => panic!("expected invalid-order verdict, got {other:?}"),
    }
}

#[test]
fn concurrent_reservations_do_not_oversell() {
    let inventory = stock(&[("SKU-A", 5)]);
    let left = concurrent_case(inventory.clone(), "ord-9");
    let right = concurrent_case(inventory.clone(), "ord-10");
    let (left_result, right_result) = run_both(&left, &right);
    assert_one_success(&left_result, &right_result);
    assert_eq!(inventory.available(&Sku::new("SKU-A").unwrap()), 0);
}

fn concurrent_case(inventory: InMemoryInventoryGateway, order_id: &str) -> Pipeline {
    wired(
        inventory,
        FakePaymentProcessor::new(false),
        InMemoryOrderRepository::new(),
        order_id,
    )
}

fn run_both(
    left: &Pipeline,
    right: &Pipeline,
) -> (
    Result<PersistedOrder, PlaceOrderError>,
    Result<PersistedOrder, PlaceOrderError>,
) {
    thread::scope(|scope| {
        let left_handle = scope.spawn(|| left.execute(vec![usd_line("SKU-A", 5, 100)], "idem-9a"));
        let right_handle =
            scope.spawn(|| right.execute(vec![usd_line("SKU-A", 5, 100)], "idem-9b"));
        (
            left_handle
                .join()
                .unwrap_or_else(|_| panic!("left panicked")),
            right_handle
                .join()
                .unwrap_or_else(|_| panic!("right panicked")),
        )
    })
}

fn assert_one_success(
    left: &Result<PersistedOrder, PlaceOrderError>,
    right: &Result<PersistedOrder, PlaceOrderError>,
) {
    let successes = [left.is_ok(), right.is_ok()]
        .into_iter()
        .filter(|ok| *ok)
        .count();
    let shortages = [left, right]
        .into_iter()
        .filter(|result| matches!(result, Err(PlaceOrderError::InsufficientStock(_))))
        .count();
    assert_eq!(successes, 1);
    assert_eq!(shortages, 1);
}

#[test]
fn get_returns_none_for_unknown_id() {
    let use_case = pipeline(&[("SKU-A", 10)], false, "ord-1");
    let (_, _, repository, _) = use_case.into_parts();
    assert_eq!(
        repository.get(&OrderId::new("missing-order").unwrap()),
        None
    );
}
