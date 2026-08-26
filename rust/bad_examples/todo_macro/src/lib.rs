//! Negative fixture: unfinished work shipped as `todo!`. Expected trip:
//! clippy::todo (denied by workspace lints).

#[must_use]
pub fn discount_for(tier: &str) -> u32 {
    match tier {
        "gold" => 20,
        _ => todo!("price the remaining tiers"),
    }
}
