def calculate_new_volatility(current_volatility, option_size, pool_volatility_adjustment_speed, is_long):
    relative_option_size = (option_size / pool_volatility_adjustment_speed) * 100
    if is_long:
        new_volatility = current_volatility + relative_option_size
    else:
        new_volatility = current_volatility - relative_option_size
    trade_volatility = (current_volatility + new_volatility) / 2
    return new_volatility, trade_volatility

def simulate_trade(pool_size, initial_volatility, adjustment_speed, is_call):
    current_volatility = initial_volatility
    total_traded = 0
    step = pool_size / 10  # We'll simulate the trade in 10 steps
    
    print(f"{'Call' if is_call else 'Put'} Pool Simulation:")
    print(f"Initial volatility: {current_volatility}")
    print(f"Adjustment speed: {adjustment_speed}")
    print(f"{'STRK' if is_call else 'USDC'} in pool: {pool_size}")
    print("\nTrading simulation:")
    
    for i in range(10):
        total_traded += step
        new_volatility, _ = calculate_new_volatility(current_volatility, step, adjustment_speed, True)
        current_volatility = new_volatility
        print(f"Traded {total_traded:.2f}: New volatility = {current_volatility:.2f}")
    
    print(f"\nFinal volatility after trading all {pool_size} {'STRK' if is_call else 'USDC'}: {current_volatility:.2f}")

# Simulate for call pool
simulate_trade(600000, 100, 400000, True)

print("\n" + "="*50 + "\n")

# Simulate for put pool
simulate_trade(100000, 100, 66666.67, False)
