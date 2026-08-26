//! Negative fixture: stdout printing in library code. Expected trip:
//! clippy::print_stdout (denied by workspace lints).

pub fn announce(message: &str) {
    println!("{message}");
}
