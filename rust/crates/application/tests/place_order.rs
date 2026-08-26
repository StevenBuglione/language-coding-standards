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

use warehouse_adapters::inventory::InMemoryInventoryGateway;
use warehouse_adapters::payments::FakePaymentProcessor;
use warehouse_adapters::repository::InMemoryOrderRepository;
use warehouse_application::place_order::{PlaceOrderError, PlaceOrderUseCase};
use warehouse_application::ports::OrderRepository;
use warehouse_domain::money::{Currency, Money};
use warehouse_domain::order::OrderLine;
use warehouse_domain::quantity::Quantity;
use warehouse_domain::sku::Sku;

fn currency() -> Currency {
    Currency::new("EUR").unwrap()
}

fn line(code: &str, quantity_value: u32, units: u64) -> OrderLine {
    OrderLine::new(
        Sku::new(code).unwrap(),
        Quantity::new(quantity_value).unwrap(),
        Money::from_minor(units, currency()),
    )
}

#[test]
fn happy_path_reserves_charges_and_persists() {
    let sku = Sku::new("SKU-A").unwrap();
    let sku_b = Sku::new("SKU-B").unwrap();
    let mut use_case = PlaceOrderUseCase::new(
        InMemoryInventoryGateway::new(BTreeMap::from([(sku.clone(), 10), (sku_b, 5)])),
        FakePaymentProcessor::new(false),
        InMemoryOrderRepository::new(),
    );

    let outcome = use_case
        .execute(vec![line("SKU-A", 2, 300), line("SKU-B", 1, 700)])
        .unwrap();

    // The persisted order is retrievable and totals correctly.
    let order = outcome.into_inner();
    let (_, _, repository) = use_case.into_parts();
    assert_eq!(
        repository
            .get(order.id())
            .unwrap()
            .total()
            .unwrap()
            .minor_units(),
        1_300
    );
}

#[test]
fn happy_path_decrements_stock_and_logs_the_charge() {
    let sku = Sku::new("SKU-A").unwrap();
    let mut use_case = PlaceOrderUseCase::new(
        InMemoryInventoryGateway::new(BTreeMap::from([(sku.clone(), 10)])),
        FakePaymentProcessor::new(false),
        InMemoryOrderRepository::new(),
    );
    use_case.execute(vec![line("SKU-A", 2, 300)]).unwrap();

    let (gateway, payments, _) = use_case.into_parts();
    assert_eq!(gateway.available(&sku), 8);
    assert_eq!(payments.charged_orders().len(), 1);
}

#[test]
fn insufficient_stock_fails_without_charging() {
    let mut use_case = PlaceOrderUseCase::new(
        InMemoryInventoryGateway::new(BTreeMap::from([
            (Sku::new("SKU-A").unwrap(), 1),
            (Sku::new("SKU-B").unwrap(), 0),
        ])),
        FakePaymentProcessor::new(false),
        InMemoryOrderRepository::new(),
    );

    match use_case.execute(vec![line("SKU-A", 1, 300), line("SKU-B", 2, 100)]) {
        Err(PlaceOrderError::InsufficientStock(error)) => {
            assert_eq!(error.available(), 0);
            assert_eq!(error.sku().code(), "SKU-B");
        }
        other => panic!("expected insufficient-stock verdict, got {other:?}"),
    }
    let (_, payments, repository) = use_case.into_parts();
    assert!(payments.charged_orders().is_empty());
    assert_eq!(
        repository.get(warehouse_domain::order::OrderId::next()),
        None
    );
}

#[test]
fn empty_lines_fail_as_invalid_order() {
    let mut use_case = PlaceOrderUseCase::new(
        InMemoryInventoryGateway::default(),
        FakePaymentProcessor::new(false),
        InMemoryOrderRepository::new(),
    );

    match use_case.execute(Vec::new()) {
        Err(PlaceOrderError::InvalidOrder(error)) => {
            assert!(error.reason().contains("at least one line"));
        }
        other => panic!("expected invalid-order verdict, got {other:?}"),
    }
}

#[test]
fn duplicate_skus_fail_as_invalid_order() {
    let mut use_case = PlaceOrderUseCase::new(
        InMemoryInventoryGateway::new(BTreeMap::from([(Sku::new("SKU-A").unwrap(), 5)])),
        FakePaymentProcessor::new(false),
        InMemoryOrderRepository::new(),
    );

    match use_case.execute(vec![line("SKU-A", 1, 300), line("SKU-A", 2, 700)]) {
        Err(PlaceOrderError::InvalidOrder(error)) => {
            assert!(error.reason().contains("duplicate SKU"));
        }
        other => panic!("expected invalid-order verdict, got {other:?}"),
    }
}

#[test]
fn declined_payment_maps_to_invalid_order_after_reserving() {
    let sku = Sku::new("SKU-A").unwrap();
    let mut use_case = PlaceOrderUseCase::new(
        InMemoryInventoryGateway::new(BTreeMap::from([(sku.clone(), 5)])),
        FakePaymentProcessor::new(true),
        InMemoryOrderRepository::new(),
    );

    match use_case.execute(vec![line("SKU-A", 1, 300)]) {
        Err(PlaceOrderError::InvalidOrder(error)) => {
            assert!(error.reason().contains("declined"));
        }
        other => panic!("expected invalid-order verdict, got {other:?}"),
    }

    // Reservation happened before the decline; nothing was persisted.
    let (gateway, payments, _) = use_case.into_parts();
    assert_eq!(gateway.available(&sku), 4);
    assert_eq!(payments.charged_orders().len(), 1);
}
