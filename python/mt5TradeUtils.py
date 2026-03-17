import MetaTrader5 as mt5


# ==========================================================
#   CONNECTION CHECK
# ==========================================================
def check_connection():
    if not mt5.terminal_info():
        raise RuntimeError("MT5 not initialized. Call initialize() first.")
    if not mt5.account_info():
        raise RuntimeError("MT5 not logged in.")
    return True


# ==========================================================
#   SAFE SYMBOL INFO
# ==========================================================
def get_symbol_info(symbol: str):
    info = mt5.symbol_info(symbol)
    if info is None:
        raise ValueError(f"Symbol {symbol} not found")

    if not info.visible:
        if not mt5.symbol_select(symbol, True):
            raise RuntimeError(f"Failed to select symbol {symbol}")

    return mt5.symbol_info(symbol)


# ==========================================================
#   LOT CALCULATION (Risk % of Balance)
# ==========================================================
def calculate_lot(symbol: str, risk_percent: float = 1.0):
    check_connection()

    account = mt5.account_info()
    symbol_info = get_symbol_info(symbol)

    balance = account.balance
    risk_amount = balance * (risk_percent / 100)

    tick_value = symbol_info.trade_tick_value
    lot_step = symbol_info.volume_step
    min_lot = symbol_info.volume_min
    max_lot = symbol_info.volume_max

    if tick_value <= 0:
        raise ValueError("Invalid tick value")

    raw_lot = risk_amount / tick_value
    lot = min(raw_lot, max_lot)

    lot = round(lot / lot_step) * lot_step

    if lot < min_lot:
        lot = min_lot

    return float(lot)


# ==========================================================
#   VALIDATE SL / TP DIRECTION AND DISTANCE
# ==========================================================
def validate_sl_tp(order_type, price, sl, tp, symbol_info=None):
    """
    Validate SL/TP:
    - Direction (SL below entry for BUY, above for SELL)
    - Minimum distance from entry (usually 1-2 pips minimum)
    """
    # Minimum distance in points (price units)
    # Default to 10 units (0.10) but allow symbol-specific override
    min_distance = 10.0
    try:
        if symbol_info is not None and hasattr(symbol_info, 'point'):
            # Use a sensible multiplier for point (e.g., 10 * point)
            min_distance = max(min_distance, symbol_info.point * 10)
    except Exception:
        pass

    # Debug log for diagnostics
    print(f"validate_sl_tp called - order_type={order_type}, price={price}, sl={sl}, tp={tp}, min_distance={min_distance}")

    if order_type == "BUY":
        if sl is not None and sl >= price:
            print("SL direction invalid for BUY, removing SL")
            sl = None
        elif sl is not None and (price - sl) < min_distance:
            print(f"SL too close to entry: {price - sl} < {min_distance}, removing SL")
            sl = None

        if tp is not None and tp <= price:
            print("TP direction invalid for BUY, removing TP")
            tp = None
        elif tp is not None and (tp - price) < min_distance:
            print(f"TP too close to entry: {tp - price} < {min_distance}, removing TP")
            tp = None

    elif order_type == "SELL":
        if sl is not None and sl <= price:
            print("SL direction invalid for SELL, removing SL")
            sl = None
        elif sl is not None and (sl - price) < min_distance:
            print(f"SL too close to entry: {sl - price} < {min_distance}, removing SL")
            sl = None

        if tp is not None and tp >= price:
            print("TP direction invalid for SELL, removing TP")
            tp = None
        elif tp is not None and (price - tp) < min_distance:
            print(f"TP too close to entry: {price - tp} < {min_distance}, removing TP")
            tp = None

    print(f"validate_sl_tp result - sl={sl}, tp={tp}")
    return sl, tp


# ==========================================================
#   OPEN ORDER (MARKET + PENDING)
# ==========================================================
def open_order(
    symbol: str,
    order_type: str,
    lot: float,
    price: float = None,
    sl: float = None,
    tp: float = None,
    deviation: int = 20,
    magic: int = 10001
):

    check_connection()

    symbol_info = get_symbol_info(symbol)
    tick = mt5.symbol_info_tick(symbol)

    if tick is None:
        print("Tick error:", mt5.last_error())
        return None

    type_map = {
        "BUY": mt5.ORDER_TYPE_BUY,
        "SELL": mt5.ORDER_TYPE_SELL,
        "BUY_LIMIT": mt5.ORDER_TYPE_BUY_LIMIT,
        "SELL_LIMIT": mt5.ORDER_TYPE_SELL_LIMIT,
        "BUY_STOP": mt5.ORDER_TYPE_BUY_STOP,
        "SELL_STOP": mt5.ORDER_TYPE_SELL_STOP
    }

    if order_type not in type_map:
        raise ValueError("Invalid order type")

    # Determine action and price
    if order_type == "BUY":
        price = tick.ask
        action = mt5.TRADE_ACTION_DEAL

    elif order_type == "SELL":
        price = tick.bid
        action = mt5.TRADE_ACTION_DEAL

    else:
        action = mt5.TRADE_ACTION_PENDING
        if price is None:
            raise ValueError("Pending order requires price")

    # Validate SL/TP
    sl, tp = validate_sl_tp(order_type, price, sl, tp, symbol_info)

    # Round lot correctly
    lot_step = symbol_info.volume_step
    lot = round(lot / lot_step) * lot_step

    # Determine filling mode based on symbol support
    filling_mode = mt5.ORDER_FILLING_IOC  # Default to IOC (Immediate Or Cancel)
    if symbol_info.filling_mode == 0:  # FOK (Fill Or Kill) supported
        filling_mode = mt5.ORDER_FILLING_FOK
    elif symbol_info.filling_mode == 2:  # Return supported
        filling_mode = mt5.ORDER_FILLING_RETURN
    
    request = {
        "action": action,
        "symbol": symbol,
        "volume": float(lot),
        "type": type_map[order_type],
        "price": price,
        "deviation": deviation,
        "magic": magic,
        "comment": "trade_utils",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": filling_mode,
    }

    if sl:
        request["sl"] = sl
    if tp:
        request["tp"] = tp

    print("Sending order:", request)

    result = mt5.order_send(request)

    if result is None:
        print("order_send returned None")
        print("MT5 error:", mt5.last_error())
        return None

    print("Retcode:", result.retcode)

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print("Order failed:", result)
        return None

    return result


# ==========================================================
#   MODIFY POSITION
# ==========================================================
def modify_position(ticket: int, new_sl: float = None, new_tp: float = None):

    check_connection()

    position = mt5.positions_get(ticket=ticket)
    if not position:
        raise ValueError("Position not found")

    pos = position[0]

    request = {
        "action": mt5.TRADE_ACTION_SLTP,
        "position": pos.ticket,
        "symbol": pos.symbol,
        "sl": new_sl if new_sl else pos.sl,
        "tp": new_tp if new_tp else pos.tp,
    }

    result = mt5.order_send(request)

    if result is None:
        print("Modify returned None:", mt5.last_error())
        return None

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        raise RuntimeError(f"Modify failed: {result.retcode}")

    return result


# ==========================================================
#   CLOSE POSITION
# ==========================================================
def close_position(ticket: int):

    check_connection()

    position = mt5.positions_get(ticket=ticket)
    if not position:
        raise ValueError("Position not found")

    pos = position[0]
    symbol = pos.symbol
    volume = pos.volume

    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        print("Tick error:", mt5.last_error())
        return None

    if pos.type == mt5.POSITION_TYPE_BUY:
        order_type = mt5.ORDER_TYPE_SELL
        price = tick.bid
    else:
        order_type = mt5.ORDER_TYPE_BUY
        price = tick.ask

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": symbol,
        "volume": volume,
        "type": order_type,
        "position": ticket,
        "price": price,
        "deviation": 20,
        "magic": 10001,
        "comment": "close_position",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_RETURN,
    }

    result = mt5.order_send(request)

    if result is None:
        print("Close returned None:", mt5.last_error())
        return None

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        raise RuntimeError(f"Close failed: {result.retcode}")

    return result