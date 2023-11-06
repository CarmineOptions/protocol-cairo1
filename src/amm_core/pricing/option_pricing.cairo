mod OptionPricing {
    // Module that calculates Black-Scholes with Choudhury's approximation to std normal CDF
    // https://www.hrpub.org/download/20140305/MS7-13401470.pdf.

    use cubit::f128::types::fixed::Fixed;
    use cubit::f128::types::fixed::FixedTrait;
    use cubit::f128::math::comp::max;
    use debug::PrintTrait;

    use array::ArrayTrait;
    use array::SpanTrait;

    const CONST_A: u128 = 4168964160658358665; // 0.226 * 2**64
    const CONST_B: u128 = 11805916207174113034; // 0.64  * 2**64
    const CONST_C: u128 = 6087425544324152033; // 0.33  * 2**64
    const INV_ROOT_OF_TWO_PI: u128 = 7359186143223876056; // (1 / sqrt(pi * 2)) * 2**64

    // @notice Calculates 1/exp(x) for big x
    // @dev Leverages the fact that 1/exp(x+a) = 1/(exp(x)*exp(a))
    // @param x: number in Cubit form
    // @return Returns 1/exp(x) in Cubit form
    fn inv_exp_big_x(x: Fixed) -> Fixed {
        let ten = FixedTrait::new_unscaled(10_u128, false);

        if x <= ten == true {
            let res = (FixedTrait::ONE() / x.exp());
            return res;
        } else {
            let inv_exp_x_minus_ten = inv_exp_big_x(x - ten);
            let inv_exp_ten = FixedTrait::ONE() / ten.exp();
            let res = inv_exp_ten * inv_exp_x_minus_ten;
            return res;
        }
    }

    /// @notice Calculates approximate value of standard normal CDF
    // @dev The approximation works well between -8 and 8. Its not the best approximation out there,
    //      but its not iterative, its simple to compute and works well on a wide range of values.
    //      There is no need for perfect approximation since this is part of the Black-Scholes model
    //      and that is used for updating prices.
    // @param x: number in Math64x61 form
    // @return Returns std normal cdf value in Math64x61 form/ @notice Calculates approximate value of standard normal CDF
    // @dev The approximation works well between -8 and 8. Its not the best approximation out there,
    //      but its not iterative, its simple to compute and works well on a wide range of values.
    //      There is no need for perfect approximation since this is part of the Black-Scholes model
    //      and that is used for updating prices.
    // @param x: number in Math64x61 form
    // @return Returns std normal cdf value in Math64x61 form
    fn std_normal_cdf(x: Fixed) -> Fixed {
        let TWO = FixedTrait::from_unscaled_felt(2);
        let THREE = FixedTrait::from_unscaled_felt(3);

        if x.sign {
            let dist_symmetric_value = std_normal_cdf(x.abs());
            return (FixedTrait::ONE() - dist_symmetric_value);
        };

        assert(x <= (TWO.pow(THREE)), 'STD_NC - x > 8');

        let x_squared = x * x;
        let x_sq_half = x_squared / TWO;
        let numerator = inv_exp_big_x(x_sq_half);

        let denominator_b = x * FixedTrait::new(CONST_B, false);
        let denominator_a = denominator_b + FixedTrait::new(CONST_A, false);
        let sqrt_den_part = (x_squared + THREE).sqrt();

        let denominator_c = sqrt_den_part * FixedTrait::new(CONST_C, false);
        let denominator = denominator_a + denominator_c;

        let res_a = numerator / denominator;
        let res_b = res_a * FixedTrait::new(INV_ROOT_OF_TWO_PI, false);

        let res = (FixedTrait::ONE() - res_b);
        return res;
    }

    // @notice Helper function
    // @dev This is just "extracted" code from the main function so that it wouldn't be really long
    //      "noodle".
    // @param is_frac: bool that determines whether the price to strike is actually price to strike
    //      or strike to price
    // @param ln_price_to_strike: ln(price/strike) or ln(strike/price) depending on "is_frac"
    // @param risk_plus_sigma_squared_half_time: "aggregated number" that is used inside
    //      of the Black-Scholes model.
    // @return Returns values that are needed for further computation.
    fn _get_d1_d2_numerator(
        is_frac: bool, ln_price_to_strike: Fixed, risk_plus_sigma_squared_half_time: Fixed
    ) -> (Fixed, bool) {
        if (is_frac == true) {
            // ln_price_to_strike < 0 (not stored as negative), but above the "let (div) = Math6..." had to be used
            // to not overflow
            // risk_plus_sigma_squared_half_time > 0

            if ln_price_to_strike <= (risk_plus_sigma_squared_half_time
                - FixedTrait::new(1_u128, false)) {
                let numerator = risk_plus_sigma_squared_half_time - ln_price_to_strike;
                let is_pos_d_1 = true;

                return (numerator, is_pos_d_1);
            } else {
                let numerator = ln_price_to_strike - risk_plus_sigma_squared_half_time;
                let is_pos_d_1 = false;

                return (numerator, is_pos_d_1);
            }
        } else {
            // both ln_price_to_strike, risk_plus_sigma_squared_half_time are positive
            let numerator = ln_price_to_strike + risk_plus_sigma_squared_half_time;
            let is_pos_d_1 = true;
            return (numerator, is_pos_d_1);
        }
    }

    // @notice Helper function
    // @dev This is just "extracted" code from the main function so that it wouldn't be really long
    //      "noodle".
    // @param is_pos_d1: "intermeidary" value needed inside of the Black-Scholes
    // @param d_1: "intermeidary" value needed inside of the Black-Scholes
    // @param denominator: "intermeidary" value needed inside of the Black-Scholes
    // @return Returns values that are needed for further computation.
    fn _get_d1_d2_d_2(is_pos_d1: bool, d_1: Fixed, denominator: Fixed) -> (Fixed, bool) {
        if (!is_pos_d1) {
            let d_2 = d_1 + denominator;
            let is_pos_d2 = false;
            return (d_2, is_pos_d2);
        } else {
            let is_pos_d_2 = denominator <= (d_1 - FixedTrait::new(1_u128, false));

            if is_pos_d_2 == true {
                let d_2 = d_1 - denominator;
                return (d_2, is_pos_d_2);
            } else {
                let d_2 = denominator - d_1;
                return (d_2, is_pos_d_2);
            }
        }
    }

    // @notice Calculates D_1 and D_2 for the Black-Scholes model
    // @param sigma: sigma, used as volatility... 80% volatility is represented as 0.8*2**61
    // @param time_till_maturity_annualized: Annualized time till maturity represented as Math64x61
    // @param strike_price: strike in Math64x61
    // @param underlying_price: price of underlying asset in Math64x61
    // @param risk_free_rate_annualized: risk free rate that is annualized
    // @return Returns D1 and D2 needed in the Black Scholes model and their sign
    fn d1_d2(
        sigma: Fixed,
        time_till_maturity_annualized: Fixed,
        strike_price: Fixed,
        underlying_price: Fixed,
        risk_free_rate_annualized: Fixed
    ) -> (Fixed, bool, Fixed, bool) {
        let ONE = FixedTrait::new_unscaled(1, false);

        let sqrt_time_till_maturity_annualized = time_till_maturity_annualized.sqrt();
        let sigma_squared = sigma * sigma;

        let sigma_squared_half = sigma_squared / FixedTrait::new_unscaled(2, false);
        let risk_plus_sigma_squared_half = risk_free_rate_annualized + sigma_squared_half;

        let price_to_strike = underlying_price / strike_price;

        let risk_plus_sigma_squared_half_time = risk_plus_sigma_squared_half
            * time_till_maturity_annualized;
        let denominator = sigma * sqrt_time_till_maturity_annualized;

        let is_frac = price_to_strike <= (ONE - FixedTrait::new(1_u128, false));
        if is_frac == true {
            let div = ONE / price_to_strike;
            let ln_price_to_strike = div.ln();
            let (numerator, is_pos_d1) = _get_d1_d2_numerator(
                is_frac, ln_price_to_strike, risk_plus_sigma_squared_half_time
            );
            let d_1 = numerator / denominator;

            let (d_2, is_pos_d_2) = _get_d1_d2_d_2(is_pos_d1, d_1, denominator);

            return (d_1, is_pos_d1, d_2, is_pos_d_2);
        } else {
            let ln_price_to_strike = price_to_strike.ln();
            let (numerator, is_pos_d1) = _get_d1_d2_numerator(
                is_frac, ln_price_to_strike, risk_plus_sigma_squared_half_time
            );
            let d_1 = numerator / denominator;

            let (d_2, is_pos_d_2) = _get_d1_d2_d_2(is_pos_d1, d_1, denominator);

            return (d_1, is_pos_d1, d_2, is_pos_d_2);
        }
    }

    // @notice Calculates STD normal CDF
    // @param d: d value (either d_1 or d_2) in the BS model
    // @param is_pos: sign of d
    // @return Returns the std normal CDF value of D
    fn adjusted_std_normal_cdf(d: Fixed, is_pos: bool) -> Fixed {
        let ONE = FixedTrait::new_unscaled(1, false);
        if is_pos == false {
            let d_ = std_normal_cdf(d);
            let normal_d = ONE - d_;
            return normal_d;
        } else {
            let normal_d = std_normal_cdf(d);
            return normal_d;
        }
    }


    // @notice Calculates value for Black Scholes
    // @param sigma: sigma, used as volatility... 80% volatility is represented as 0.8*2**61
    // @param time_till_maturity_annualized: Annualized time till maturity represented as Math64x61
    // @param strike_price: strike in Math64x61
    // @param underlying_price: price of underlying asset in Math64x61
    // @param risk_free_rate_annualized: risk free rate that is annualized
    // @param is_for_trade: whether pricing is for trading or other(withdraw/deposit etc.)
    // @return Returns call and put option premium, bool whether it's usable
    fn black_scholes(
        sigma: Fixed,
        time_till_maturity_annualized: Fixed,
        strike_price: Fixed,
        underlying_price: Fixed,
        risk_free_rate_annualized: Fixed,
        is_for_trade: bool // We want it to work for anything but trading
    ) -> (Fixed, Fixed, bool) {
        let ONE = FixedTrait::new_unscaled(1, false);
        let EIGHT = FixedTrait::new_unscaled(8, false);

        let risk_time_till_maturity = risk_free_rate_annualized * time_till_maturity_annualized;
        let e_risk_time_till_maturity = risk_time_till_maturity.exp();
        let e_neg_risk_time_till_maturity = ONE / e_risk_time_till_maturity;
        let strike_e_neg_risk_time_till_maturity = strike_price * e_neg_risk_time_till_maturity;

        let (d_1, is_pos_d_1, d_2, is_pos_d_2) = d1_d2(
            sigma,
            time_till_maturity_annualized,
            strike_price,
            underlying_price,
            risk_free_rate_annualized,
        );

        let abs_d = d_1.abs();
        let is_d_extreme = EIGHT <= abs_d;
        // If the pricing is for trade, let it fail in case of extreme ds
        if is_for_trade != true {
            if is_d_extreme == true {
                return _premia_extreme_d(strike_price, underlying_price);
            }
        }

        let normal_d_1 = adjusted_std_normal_cdf(d_1, is_pos_d_1);
        let normal_d_2 = adjusted_std_normal_cdf(d_2, is_pos_d_2);

        let normal_d_1_underlying_price = normal_d_1 * underlying_price;
        let normal_d_2_strike_e_neg_risk_time_till_maturity = normal_d_2
            * strike_e_neg_risk_time_till_maturity;

        let call_option_value = normal_d_1_underlying_price
            - normal_d_2_strike_e_neg_risk_time_till_maturity;

        let neg_underlying_price_call_value = call_option_value - underlying_price;
        let put_option_value = strike_e_neg_risk_time_till_maturity
            + neg_underlying_price_call_value;

        return (call_option_value, put_option_value, true);
    }

    // @notice Calculates premia for ds in BS that are outside of usability of our standard normal CDF approximation
    // @dev Returns either zero or diff of strike and underlying, both  plus cent
    // @param strike_price: Strike price of the option
    // @param underlying_price: Current price of the underlying
    // @returns Call and Put premia, plus variable indicating whether it was calculated by BS or not
    fn _premia_extreme_d(strike_price: Fixed, underlying_price: Fixed) -> (Fixed, Fixed, bool) {
        let price_diff_call = underlying_price - strike_price;
        let price_diff_put = strike_price - underlying_price;

        let cent = FixedTrait::from_felt(184467440737095520); // 0.01 

        let _call_premia = max(FixedTrait::ZERO(), price_diff_call);
        let call_option_value = _call_premia + cent;

        let _put_premia = max(FixedTrait::ZERO(), price_diff_put);
        let put_option_value = _put_premia + cent;

        return (call_option_value, put_option_value, false);
    }
}
// Tests --------------------------------------------------------------------------------------------------------------
use cubit::f128::types::fixed::{Fixed, FixedTrait};
use debug::PrintTrait;
use array::ArrayTrait;
use option::OptionTrait;
use traits::Into;

// Helper function for testing
fn is_close(a: Fixed, b: Fixed, rel_tol: Fixed) -> bool {
    let tmp = (a - b).abs() / b;

    if tmp <= rel_tol {
        true
    } else {
        false
    }
}

#[test]
fn test_black_scholes() {
    let (call_premia, put_premia, _) = OptionPricing::black_scholes(
        FixedTrait::from_felt(184467440737095520),
        FixedTrait::from_felt(1844674407370955264),
        FixedTrait::from_felt(1844674407370955161600),
        FixedTrait::from_felt(1844674407370955161600),
        FixedTrait::from_felt(553402322211286528),
        true
    );
    assert(call_premia == FixedTrait::new(6062350487240555138, false), 'Call Premia 1 wrong');
    assert(put_premia == FixedTrait::new(536620027070393438, false), 'Put Premia 1 wrong');

    let (call_premia, put_premia, _) = OptionPricing::black_scholes(
        FixedTrait::from_felt(18446134590149408768),
        FixedTrait::from_felt(2303276866828757248),
        FixedTrait::from_felt(27670116110564327424000),
        FixedTrait::from_felt(23767079668293617104936),
        FixedTrait::from_felt(0),
        true
    );
    assert(call_premia == FixedTrait::new(1979598933257199867170, false), 'Call Premia 2 wrong');
    assert(put_premia == FixedTrait::new(5882635375527910186234, false), 'Put Premia 2 wrong');
}

#[test]
#[should_panic(expected: ('STD_NC - x > 8',))]
fn test_black_scholes_extreme() {
    let (call_premia_1, put_premia_1, is_usable_1) = OptionPricing::black_scholes(
        FixedTrait::from_felt(184467440737095520), // 0.01
        FixedTrait::from_felt(1844674407370955264),
        FixedTrait::from_unscaled_felt(1500),
        FixedTrait::from_unscaled_felt(1000),
        FixedTrait::from_felt(553402322211286528),
        false
    );

    assert(call_premia_1 == FixedTrait::from_felt(184467440737095520), 'Should be a cent'); // cent
    assert(
        put_premia_1 == FixedTrait::from_felt(9223556504295512903520), 'Should be 500 + cent'
    ); // 500 + cent
    assert(!is_usable_1, 'Should not be usable');

    let (call_premia_2, put_premia_2, is_usable_2) = OptionPricing::black_scholes(
        FixedTrait::from_felt(184467440737095520), // 0.01
        FixedTrait::from_felt(1844674407370955264),
        FixedTrait::from_unscaled_felt(1000),
        FixedTrait::from_unscaled_felt(1500),
        FixedTrait::from_felt(553402322211286528),
        false
    );

    assert(
        call_premia_2 == FixedTrait::from_felt(9223556504295512903520), 'Should be 500 + cent'
    ); // 500 + cent
    assert(put_premia_2 == FixedTrait::from_felt(184467440737095520), 'Should be a cent'); // cent
    assert(!is_usable_2, 'Should not be usable');

    let (call_premia, put_premia, _) = OptionPricing::black_scholes(
        FixedTrait::from_felt(184467440737095520), // 0.01
        FixedTrait::from_felt(1844674407370955264),
        FixedTrait::from_unscaled_felt(1500),
        FixedTrait::from_unscaled_felt(1000),
        FixedTrait::from_felt(553402322211286528),
        true
    );
}

#[test]
fn test_std_normal_cdf() {
    let rel_tol = FixedTrait::from_felt(184467440737095520); // 0.01
    let mut test_cases = get_test_std_normal_cdf_cases();

    loop {
        match test_cases.pop_front() {
            Option::Some((
                x, res
            )) => {
                let res_our = OptionPricing::std_normal_cdf(x);
                assert(is_close(res_our, res, rel_tol), x.mag.into());
            },
            Option::None(()) => {
                break;
            }
        };
    }
}

#[test]
fn test_d1_d2() {
    let rel_tol = FixedTrait::from_felt(18446744073709552); // 0.01
    let (cases, results) = get_test_d1_d2_cases();
    let mut i = 0;

    assert(cases.len() == results.len(), 'Cases != results');

    loop {
        if i >= cases.len() {
            break;
        };

        let (sigma, ttm, strike, underlying) = *(cases.at(i));
        let (d1_res, d2_res) = *(results.at(i));

        let (d1, _, d2, _) = OptionPricing::d1_d2(
            sigma, ttm, strike, underlying, FixedTrait::ZERO()
        );

        assert(is_close(d1, d1_res, rel_tol), 'D1 Fail');
        assert(is_close(d2, d2_res, rel_tol), 'D2 Fail');

        i += 1;
    }
}

fn get_test_std_normal_cdf_cases() -> Array<(Fixed, Fixed)> {
    let mut arr = ArrayTrait::<(Fixed, Fixed)>::new();
    arr
        .append(
            (
                FixedTrait::from_felt(64800229984264355840),
                FixedTrait::from_felt(18442654751404615680)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(58312136748854312960),
                FixedTrait::from_felt(18432247643905175552)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-48184060197361451008), FixedTrait::from_felt(83008164005589360))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-40539702722723512320),
                FixedTrait::from_felt(258007448778362336)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(101923126309447892992),
                FixedTrait::from_felt(18446743770268907520)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-63083991958638624768), FixedTrait::from_felt(5780239419541288))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(28162466146725199872),
                FixedTrait::from_felt(17276869749314291712)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-88192507920352870400), FixedTrait::from_felt(16093869139577))
        );
    arr
        .append(
            (FixedTrait::from_felt(-78468888490706239488), FixedTrait::from_felt(193844374173112))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(28060374979069247488),
                FixedTrait::from_felt(17264116852247371776)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(94552108071591936000),
                FixedTrait::from_felt(18446741339296153600)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(126995597826164457472),
                FixedTrait::from_felt(18446744073656043520)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-62372937558596583424), FixedTrait::from_felt(6655447769788865))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(122848937580332089344),
                FixedTrait::from_felt(18446744073456396288)
            )
        );
    arr.append((FixedTrait::from_felt(-141281801947675754496), FixedTrait::from_felt(172965)));
    arr
        .append(
            (
                FixedTrait::from_felt(62755858162703237120),
                FixedTrait::from_felt(18440574175010328576)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(102069095219063259136),
                FixedTrait::from_felt(18446743783650828288)
            )
        );
    arr.append((FixedTrait::from_felt(-116572351975961001984), FixedTrait::from_felt(2421882545)));
    arr
        .append(
            (
                FixedTrait::from_felt(76011819007279857664),
                FixedTrait::from_felt(18446395548030355456)
            )
        );
    arr.append((FixedTrait::from_felt(-142753852756396310528), FixedTrait::from_felt(92636)));
    arr
        .append(
            (
                FixedTrait::from_felt(54281970277190926336),
                FixedTrait::from_felt(18416727943673896960)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-28758192813155647488),
                FixedTrait::from_felt(1097581163086414976)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(131903204858025443328),
                FixedTrait::from_felt(18446744073701576704)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(7620224593559715840),
                FixedTrait::from_felt(12179109250831343616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(35733331703604969472),
                FixedTrait::from_felt(17960375668118048768)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(76960895424288522240),
                FixedTrait::from_felt(18446465656903213056)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-9764929877766799360),
                FixedTrait::from_felt(5502268911090464768)
            )
        );
    arr.append((FixedTrait::from_felt(-119286720412122939392), FixedTrait::from_felt(924811531)));
    arr.append((FixedTrait::from_felt(-144946379936525058048), FixedTrait::from_felt(36127)));
    arr
        .append(
            (
                FixedTrait::from_felt(42666205868167397376),
                FixedTrait::from_felt(18255580859719563264)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-69939943924746911744), FixedTrait::from_felt(1381376337987086))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(5897761236622802944),
                FixedTrait::from_felt(11536760657208780800)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(57476019185036492800),
                FixedTrait::from_felt(18429823030984329216)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(85025547206671859712),
                FixedTrait::from_felt(18446706798786672640)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(59635370397632888832),
                FixedTrait::from_felt(18435439334488442880)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(145814538742669410304),
                FixedTrait::from_felt(18446744073709527040)
            )
        );
    arr.append((FixedTrait::from_felt(-145203862804605140992), FixedTrait::from_felt(32315)));
    arr
        .append(
            (
                FixedTrait::from_felt(37745173177238487040),
                FixedTrait::from_felt(18070987088780298240)
            )
        );
    arr.append((FixedTrait::from_felt(-109187138174932615168), FixedTrait::from_felt(29866493772)));
    arr
        .append(
            (
                FixedTrait::from_felt(51528775649317715968),
                FixedTrait::from_felt(18398634694787383296)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(28511272757997010944),
                FixedTrait::from_felt(17319635133324185600)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(66224525511740358656),
                FixedTrait::from_felt(18443694560887629824)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-82090144194716205056), FixedTrait::from_felt(79158729738176))
        );
    arr
        .append(
            (FixedTrait::from_felt(-67283806607978299392), FixedTrait::from_felt(2442745391761175))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(30759886744565809152),
                FixedTrait::from_felt(17566689944762902528)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(106201558586106576896),
                FixedTrait::from_felt(18446743994829830144)
            )
        );
    arr.append((FixedTrait::from_felt(-123177416101368102912), FixedTrait::from_felt(224235946)));
    arr
        .append(
            (
                FixedTrait::from_felt(43338696574693900288),
                FixedTrait::from_felt(18273308485610815488)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-101583844709702696960), FixedTrait::from_felt(336899512454))
        );
    arr
        .append(
            (FixedTrait::from_felt(-82300887755675107328), FixedTrait::from_felt(75053094784167))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-9748667062113009664),
                FixedTrait::from_felt(5507909937548864512)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(83116157601266073600),
                FixedTrait::from_felt(18446683067281709056)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(19106981540821303296),
                FixedTrait::from_felt(15676970957441302528)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-73554699430984318976), FixedTrait::from_felt(616112261109368))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-19812908245079228416),
                FixedTrait::from_felt(2608331168612691968)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-54538667119184510976), FixedTrait::from_felt(28694347940898116))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(41991179732368687104),
                FixedTrait::from_felt(18236217986054639616)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-74168657830972653568), FixedTrait::from_felt(535210877145306))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-16391176946104401920),
                FixedTrait::from_felt(3451713922802126848)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(92903169780826439680),
                FixedTrait::from_felt(18446739695937429504)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(52553608135926808576),
                FixedTrait::from_felt(18406285205838954496)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-88621271341219479552), FixedTrait::from_felt(14332726720611))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-1394979431439794176),
                FixedTrait::from_felt(8667385730205541376)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-85170498709129953280), FixedTrait::from_felt(35891466119948))
        );
    arr
        .append(
            (FixedTrait::from_felt(-70940007271893762048), FixedTrait::from_felt(1108886206865101))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(143051195303529250816),
                FixedTrait::from_felt(18446744073709469696)
            )
        );
    arr.append((FixedTrait::from_felt(-147002255679679627264), FixedTrait::from_felt(14753)));
    arr.append((FixedTrait::from_felt(-112194865682493538304), FixedTrait::from_felt(10940912510)));
    arr.append((FixedTrait::from_felt(-136090849467228160000), FixedTrait::from_felt(1487634)));
    arr.append((FixedTrait::from_felt(-142125378469688475648), FixedTrait::from_felt(121029)));
    arr.append((FixedTrait::from_felt(-118512179115981996032), FixedTrait::from_felt(1219819908)));
    arr
        .append(
            (
                FixedTrait::from_felt(-40477586112671940608),
                FixedTrait::from_felt(260230580704680672)
            )
        );
    arr.append((FixedTrait::from_felt(-126212382742498312192), FixedTrait::from_felt(72036555)));
    arr
        .append(
            (
                FixedTrait::from_felt(126233164890105839616),
                FixedTrait::from_felt(18446744073638080512)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-3826201323985993728),
                FixedTrait::from_felt(7707813460083302400)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(102849911943925104640),
                FixedTrait::from_felt(18446743846064775168)
            )
        );
    arr.append((FixedTrait::from_felt(-116320858887964426240), FixedTrait::from_felt(2644998313)));
    arr
        .append(
            (FixedTrait::from_felt(-81236826171553710080), FixedTrait::from_felt(98084078694961))
        );
    arr.append((FixedTrait::from_felt(-127114391232700252160), FixedTrait::from_felt(51140246)));
    arr.append((FixedTrait::from_felt(-116248040182797598720), FixedTrait::from_felt(2713265177)));
    arr
        .append(
            (
                FixedTrait::from_felt(96539218442379591680),
                FixedTrait::from_felt(18446742538768048128)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-21344647042975694848),
                FixedTrait::from_felt(2280324613129593856)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(62338658876034482176),
                FixedTrait::from_felt(18440043471955200000)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-71250753459369213952), FixedTrait::from_felt(1035115721417319))
        );
    arr.append((FixedTrait::from_felt(-107074528678609387520), FixedTrait::from_felt(59536820837)));
    arr
        .append(
            (
                FixedTrait::from_felt(106303691018135273472),
                FixedTrait::from_felt(18446743997375203328)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-59271559794651824128), FixedTrait::from_felt(12110515485909394))
        );
    arr
        .append(
            (FixedTrait::from_felt(-56802152671586189312), FixedTrait::from_felt(19140512788039108))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(43885956525637795840),
                FixedTrait::from_felt(18286656456710088704)
            )
        );
    arr.append((FixedTrait::from_felt(-123881970537218867200), FixedTrait::from_felt(172682911)));
    arr
        .append(
            (FixedTrait::from_felt(-49952225762593144832), FixedTrait::from_felt(62448907905773512))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(128324286661529534464),
                FixedTrait::from_felt(18446744073677371392)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-8805306682425376768),
                FixedTrait::from_felt(5839523716517879808)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(45087762431150063616),
                FixedTrait::from_felt(18312849551109718016)
            )
        );
    arr
        .append(
            (FixedTrait::from_felt(-60765693305346424832), FixedTrait::from_felt(9106433841723674))
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-27786928184967200768),
                FixedTrait::from_felt(1217317851643367680)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(-32109509061986680832),
                FixedTrait::from_felt(753947928578102912)
            )
        );
    arr.append((FixedTrait::from_felt(-112559089078395502592), FixedTrait::from_felt(9671076244)));
    arr.append((FixedTrait::from_felt(-134363697784829313024), FixedTrait::from_felt(2991840)));
    arr
        .append(
            (
                FixedTrait::from_felt(5412521098755178496),
                FixedTrait::from_felt(11352068958134509568)
            )
        );
    arr
}

fn get_test_d1_d2_cases() -> (Array<(Fixed, Fixed, Fixed, Fixed)>, Array<(Fixed, Fixed)>) {
    let mut arr = ArrayTrait::<(Fixed, Fixed, Fixed, Fixed)>::new();
    let mut target = ArrayTrait::<(Fixed, Fixed)>::new();

    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(18446744073709551616),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(18446744073709551616),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(5091301364343836672),
                FixedTrait::from_felt(55340232221128656),
                FixedTrait::from_felt(46116860184273879040000),
                FixedTrait::from_felt(169119749667769169215488)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(18446744073709551616),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(21324436149208240128),
                FixedTrait::from_felt(1199038364791120896),
                FixedTrait::from_felt(154380801152875237474304),
                FixedTrait::from_felt(112709606290365360373760)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(18446744073709551616),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(1973801615886921984),
                FixedTrait::from_felt(36893488147419104),
                FixedTrait::from_felt(36395426057428945338368),
                FixedTrait::from_felt(95904622439215958851584)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(18446744073709551616),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(36893488147419103232),
                FixedTrait::from_felt(977677435906606208),
                FixedTrait::from_felt(28979834939797705588736),
                FixedTrait::from_felt(118077608815814839894016)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(18446744073709551616),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(22800175675105005568),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(127190300388227358392320),
                FixedTrait::from_felt(96734725922532888674304)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(22800175675105005568),
                FixedTrait::from_felt(3910709743626424832),
                FixedTrait::from_felt(127190300388227358392320),
                FixedTrait::from_felt(96734725922532888674304)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(25825441703193370624),
                FixedTrait::from_felt(1014570924054025344),
                FixedTrait::from_felt(96734725922532888674304),
                FixedTrait::from_felt(3910709743626424942592)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(25825441703193370624),
                FixedTrait::from_felt(1014570924054025344),
                FixedTrait::from_felt(1014570924054025338880),
                FixedTrait::from_felt(3910709743626424942592)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(25825441703193370624),
                FixedTrait::from_felt(1014570924054025344),
                FixedTrait::from_felt(1014570924054025338880),
                FixedTrait::from_felt(3910709743626424942592)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(25825441703193370624),
                FixedTrait::from_felt(1014570924054025344),
                FixedTrait::from_felt(1014570924054025338880),
                FixedTrait::from_felt(3910709743626424942592)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(3910709743626424832),
                FixedTrait::from_felt(1014570924054025344),
                FixedTrait::from_felt(1014570924054025338880),
                FixedTrait::from_felt(3910709743626424942592)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(18446744073709551616),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(2969925795867237888),
                FixedTrait::from_felt(3283520445120300032),
                FixedTrait::from_felt(124072800639770444169216),
                FixedTrait::from_felt(180298476576437157494784)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(2969925795867237888),
                FixedTrait::from_felt(848550227390639360),
                FixedTrait::from_felt(124072800639770444169216),
                FixedTrait::from_felt(180298476576437157494784)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(2969925795867237888),
                FixedTrait::from_felt(848550227390639360),
                FixedTrait::from_felt(124072800639770444169216),
                FixedTrait::from_felt(180298476576437157494784)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(2969925795867237888),
                FixedTrait::from_felt(848550227390639360),
                FixedTrait::from_felt(2969925795867237810176),
                FixedTrait::from_felt(180298476576437157494784)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(2969925795867237888),
                FixedTrait::from_felt(848550227390639360),
                FixedTrait::from_felt(180298476576437157494784),
                FixedTrait::from_felt(180298476576437157494784)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(2969925795867237888),
                FixedTrait::from_felt(848550227390639360),
                FixedTrait::from_felt(2969925795867237810176),
                FixedTrait::from_felt(2969925795867237810176)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(21988518935861784576),
                FixedTrait::from_felt(6124319032471571456),
                FixedTrait::from_felt(124349501800876087443456),
                FixedTrait::from_felt(128518465961534446108672)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(21988518935861784576),
                FixedTrait::from_felt(6124319032471571456),
                FixedTrait::from_felt(124349501800876087443456),
                FixedTrait::from_felt(128518465961534446108672)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(21988518935861784576),
                FixedTrait::from_felt(6124319032471571456),
                FixedTrait::from_felt(21988518935861785526272),
                FixedTrait::from_felt(128518465961534446108672)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(21988518935861784576),
                FixedTrait::from_felt(3099053004383204864),
                FixedTrait::from_felt(21988518935861785526272),
                FixedTrait::from_felt(128518465961534446108672)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(21988518935861784576),
                FixedTrait::from_felt(3099053004383204864),
                FixedTrait::from_felt(21988518935861785526272),
                FixedTrait::from_felt(128518465961534446108672)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(11971936903837499392),
                FixedTrait::from_felt(516508834063867456),
                FixedTrait::from_felt(94465776401466613825536),
                FixedTrait::from_felt(94539563377761452032000)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18981699651847127040),
                FixedTrait::from_felt(516508834063867456),
                FixedTrait::from_felt(516508834063867445248),
                FixedTrait::from_felt(94465776401466613825536)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(516508834063867456),
                FixedTrait::from_felt(92233720368547760),
                FixedTrait::from_felt(94465776401466613825536),
                FixedTrait::from_felt(516508834063867445248)
            )
        );
    arr
        .append(
            (
                FixedTrait::from_felt(18446744073709560),
                FixedTrait::from_felt(18446744073709552),
                FixedTrait::from_felt(94465776401466613825536),
                FixedTrait::from_felt(18446744073709551616)
            )
        );
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(36893488147419103232)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(18981699651847128612864)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(2969925795867237810176)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(92233720368547758080)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(47279005060917580791808)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(18944806163699709509632)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(55340232221128654848)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(47260558316843871240192)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(94465776401466613825536)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(5109748108417545797632)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(18926359419625999958016)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(47242111572770161688576)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(94115288264066132344832)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(94225968728508389654528)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(94262862216655808757760)));
    // arr.append((FixedTrait::from_felt(18446744073709560), FixedTrait::from_felt(18446744073709552), FixedTrait::from_felt(94465776401466613825536), FixedTrait::from_felt(18723445234815194890240)));

    target
        .append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    target
        .append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    target
        .append(
            (
                FixedTrait::from_felt(1585771339775843237888),
                FixedTrait::from_felt(1585492477715412418560)
            )
        );
    target
        .append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    target
        .append(
            (
                FixedTrait::from_felt(-16972960374592655360),
                FixedTrait::from_felt(-22409646176651464704)
            )
        );
    target
        .append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    target
        .append(
            (
                FixedTrait::from_felt(3735166773356690669568),
                FixedTrait::from_felt(3735078502264946032640)
            )
        );
    target
        .append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    target
        .append(
            (
                FixedTrait::from_felt(60526011704982298624),
                FixedTrait::from_felt(52032492894310309888)
            )
        );
    target
        .append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    target
        .append(
            (
                FixedTrait::from_felt(-128819415131290238976),
                FixedTrait::from_felt(-129540419993143230464)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(-3623118538600333312),
                FixedTrait::from_felt(-14121107788590913536)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(-177223256978321539072),
                FixedTrait::from_felt(-183279859916774506496)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(78834333252308828160),
                FixedTrait::from_felt(72777730313855860736)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(78834333252308828160),
                FixedTrait::from_felt(72777730313855860736)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(78834333252308828160),
                FixedTrait::from_felt(72777730313855860736)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(501064441630978146304),
                FixedTrait::from_felt(500147298900298104832)
            )
        );
    target
        .append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    target
        .append(
            (
                FixedTrait::from_felt(102124966375437303808),
                FixedTrait::from_felt(100871953309477306368)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(199978245753020907520),
                FixedTrait::from_felt(199341267633525391360)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(199978245753020907520),
                FixedTrait::from_felt(199341267633525391360)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(2193840463900333047808),
                FixedTrait::from_felt(2193203485780837400576)
            )
        );
    target
        .append(
            (FixedTrait::from_felt(318489059747761088), FixedTrait::from_felt(-318489059747761088))
        );
    target
        .append(
            (FixedTrait::from_felt(318489059747761088), FixedTrait::from_felt(-318489059747761088))
        );
    target
        .append(
            (
                FixedTrait::from_felt(7220513475850757120),
                FixedTrait::from_felt(-5449148255134555136)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(7220513475850757120),
                FixedTrait::from_felt(-5449148255134555136)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(53754112958238507008),
                FixedTrait::from_felt(41084451227253194752)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(71166929563872649216),
                FixedTrait::from_felt(62154318725786804224)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(71166929563872649216),
                FixedTrait::from_felt(62154318725786804224)
            )
        );
    target
        .append(
            (FixedTrait::from_felt(1134271019703585408), FixedTrait::from_felt(-869017189822206592))
        );
    target
        .append(
            (
                FixedTrait::from_felt(559635914547718062080),
                FixedTrait::from_felt(556459668680842805248)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(-48531374030852731174912),
                FixedTrait::from_felt(-48531410553542644072448)
            )
        );
    target
        .append(
            (
                FixedTrait::from_felt(-4982344853156098614493184),
                FixedTrait::from_felt(-4982344853739435703926784)
            )
        );
    // target.append((FixedTrait::from_felt(-4578006271308677089591296), FixedTrait::from_felt(-4578006271892014179024896)));
    // target.append((FixedTrait::from_felt(-936117639551711413534720), FixedTrait::from_felt(-936117640135048637186048)));
    // target.append((FixedTrait::from_felt(-2018172319017906728861696), FixedTrait::from_felt(-2018172319601244086730752)));
    // target.append((FixedTrait::from_felt(-4043499740117657968443392), FixedTrait::from_felt(-4043499740700995057876992)));
    // target.append((FixedTrait::from_felt(-403769305364509281484800), FixedTrait::from_felt(-403769305947846572244992)));
    // target.append((FixedTrait::from_felt(-937252537316048214425600), FixedTrait::from_felt(-937252537899385438076928)));
    // target.append((FixedTrait::from_felt(-4341483363333163729289216), FixedTrait::from_felt(-4341483363916500818722816)));
    // target.append((FixedTrait::from_felt(-403996949178860175360000), FixedTrait::from_felt(-403996949762197466120192)));
    // target.append((FixedTrait::from_felt(291668633435675), FixedTrait::from_felt(-291668633435675)));
    // target.append((FixedTrait::from_felt(-1701645852260142667530240), FixedTrait::from_felt(-1701645852843480025399296)));
    // target.append((FixedTrait::from_felt(-937820815263447390355456), FixedTrait::from_felt(-937820815846784614006784)));
    // target.append((FixedTrait::from_felt(-404224681864505445056512), FixedTrait::from_felt(-404224682447842735816704)));
    // target.append((FixedTrait::from_felt(-2168330106865334878208), FixedTrait::from_felt(-2168330690202601783296)));
    // target.append((FixedTrait::from_felt(-1482723054146160427008), FixedTrait::from_felt(-1482723637483427332096)));
    // target.append((FixedTrait::from_felt(-1254366321196091834368), FixedTrait::from_felt(-1254366904533358739456)));
    // target.append((FixedTrait::from_felt(-944108685978897615945728), FixedTrait::from_felt(-944108686562234839597056)));

    (arr, target)
}
