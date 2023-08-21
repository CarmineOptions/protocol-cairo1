mod OptionPricing {
    // Module that calculates Black-Scholes with Choudhury's approximation to std normal CDF
    // https://www.hrpub.org/download/20140305/MS7-13401470.pdf.

    use cubit::f128::types::fixed::{Fixed, FixedTrait};
    use cubit::f128::math::comp::max;

    use array::{ArrayTrait, SpanTrait};

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
        let one = FixedTrait::new_unscaled(1_u128, false);

        if x <= ten == true {
            return (one / x.exp());
        } else {
            let inv_exp_x_minus_ten = inv_exp_big_x(x - ten);
            let inv_exp_ten = one / ten.exp();

            return inv_exp_ten * inv_exp_x_minus_ten;
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
        let ONE = FixedTrait::from_unscaled_felt(1);
        let TWO = FixedTrait::from_unscaled_felt(2);
        let THREE = FixedTrait::from_unscaled_felt(3);

        if x.sign == true {
            let dist_symmetric_value = std_normal_cdf(x.abs());
            return (ONE - dist_symmetric_value);
        };

        assert(x <= (TWO.pow(THREE)), 'STD_NC - x > 8');

        let x_squared = x * x;
        let x_sq_half = x_squared / TWO;
        let numerator = inv_exp_big_x(x_sq_half);

        let denominator_b = x * FixedTrait::new(CONST_B, false);
        let denominator_a = denominator_b * FixedTrait::new(CONST_A, false);
        let sqrt_den_part = (x + THREE).sqrt();
        let denominator_c = sqrt_den_part * FixedTrait::new(CONST_C, false);
        let denominator = denominator_a + denominator_c;

        let res_a = numerator / denominator;
        let res_b = res_a * FixedTrait::new(INV_ROOT_OF_TWO_PI, false);

        return (ONE - res_b);
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
        if (is_pos_d1 == false) {
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
        // if is_for_trade != true { TODO: finish _premia_extreme
        //     if is_d_extreme == true {
        //         return _premia_extreme_d(strike_price, underlying_price);
        //     }
        // }

        // TODO: Err messages
        let normal_d_1 = adjusted_std_normal_cdf(d_1, is_pos_d_1);
        let normal_d_2 = adjusted_std_normal_cdf(d_2, is_pos_d_2);

        let normal_d_1_underlying_price = normal_d_1 * strike_price;
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

        let cent = FixedTrait::new_unscaled(184467440737095520_u128, false); // 0.01 

        let _call_premia = max(FixedTrait::new_unscaled(0, false), price_diff_call);
        let call_option_value = _call_premia + cent;

        let _put_premia = max(FixedTrait::new_unscaled(0, false), price_diff_put);
        let put_option_value = _put_premia + cent;

        return (call_option_value, put_option_value, false);
    }
}
