use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;

#[test]
fn test_sth() {
    let mut test_data = get_sth_test_data();
    loop {
        match test_data.pop_front() {
            Option::Some(x1) => {
                let _x = *x1;
                assert(_x == 1_u128, 'n');
            },
            Option::None(()) => {
                break ();
            },
        };
    };
}

fn get_sth_test_data() -> Span<u128> {
    let mut test_data = ArrayTrait::<u128>::new();
    test_data.append(1_u128);
    test_data.append(1_u128);
    test_data.append(1_u128);
    test_data.append(1_u128);
    test_data.append(1_u128);
    return test_data.span();
}
