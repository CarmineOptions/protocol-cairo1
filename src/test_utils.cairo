
use cubit::f128::types::fixed::{Fixed, FixedTrait};

// Helper function for relative comparison of two numbers
// TODO: Is this correct?
fn is_close(a: Fixed, b: Fixed, rel_tol: Fixed) -> bool {
    let tmp = (a - b).abs() / b;

    if tmp <= rel_tol {
        true
    } else {
        false
    }
}