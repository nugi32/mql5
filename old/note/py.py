import MetaTrader5 as mt5
import pandas as pd

# ===== INPUT PARAMETER (bisa dioptimasi) =====
SYMBOL = input("Symbol (contoh EURUSD): ") or "EURUSD"
TIMEFRAME_STR = input("Timeframe (M1/M5/M15/H1): ") or "M5"
FAST_EMA = int(input("Fast EMA: ") or 12)
SLOW_EMA = int(input("Slow EMA: ") or 26)
LOT = float(input("Lot size: ") or 0.1)
N_BARS = int(input("Jumlah bars: ") or 300)

# mapping timeframe
TF_MAP = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "H1": mt5.TIMEFRAME_H1,
}
TIMEFRAME = TF_MAP.get(TIMEFRAME_STR, mt5.TIMEFRAME_M5)

DEVIATION = 20
MAGIC = 123456

# ===== FUNCTIONS =====
def get_data():
    rates = mt5.copy_rates_from_pos(SYMBOL, TIMEFRAME, 0, N_BARS)
    df = pd.DataFrame(rates)
    return df

def add_ema(df):
    df['ema_fast'] = df['close'].ewm(span=FAST_EMA, adjust=False).mean()
    df['ema_slow'] = df['close'].ewm(span=SLOW_EMA, adjust=False).mean()
    return df

def get_signal(df):
    prev = df.iloc[-2]
    curr = df.iloc[-1]

    if prev.ema_fast <= prev.ema_slow and curr.ema_fast > curr.ema_slow:
        return "buy"
    if prev.ema_fast >= prev.ema_slow and curr.ema_fast < curr.ema_slow:
        return "sell"
    return None

def send_order(signal):
    tick = mt5.symbol_info_tick(SYMBOL)

    order_type = mt5.ORDER_TYPE_BUY if signal=="buy" else mt5.ORDER_TYPE_SELL
    price = tick.ask if signal=="buy" else tick.bid

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": SYMBOL,
        "volume": LOT,
        "type": order_type,
        "price": price,
        "deviation": DEVIATION,
        "magic": MAGIC,
        "comment": "EMA input strategy",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }

    result = mt5.order_send(request)
    print(result)

# ===== MAIN =====
if not mt5.initialize():
    print("MT5 gagal start")
    quit()

mt5.symbol_select(SYMBOL, True)

df = get_data()
df = add_ema(df)

signal = get_signal(df)
print("Signal:", signal)

if signal:
    send_order(signal)

mt5.shutdown()
