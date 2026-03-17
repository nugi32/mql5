import MetaTrader5 as mt5
import os
from dotenv import load_dotenv
from datetime import datetime

# =========================
# CONFIG
# =========================
SYMBOL = "BTCUSDm"
TIMEFRAME = mt5.TIMEFRAME_M5

load_dotenv()

MT5_PATH = os.getenv("MT5_PATH")
LOGIN = os.getenv("LOGIN")
PASSWORD = os.getenv("PASSWORD")
SERVER = os.getenv("SERVER")

if not LOGIN:
    raise Exception("LOGIN not found in .env")

LOGIN = int(LOGIN)

print("MT5_PATH:", MT5_PATH)
print("LOGIN:", LOGIN)
print("SERVER:", SERVER)

# =========================
# INITIALIZE MT5
# =========================
if not mt5.initialize(path=MT5_PATH):
    raise Exception(f"Initialize failed: {mt5.last_error()}")

# Login
if not mt5.login(LOGIN, password=PASSWORD, server=SERVER):
    raise Exception(f"Login failed: {mt5.last_error()}")

print("MT5 connected")

# =========================
# CHECK SYMBOL
# =========================
symbol_info = mt5.symbol_info(SYMBOL)
if symbol_info is None:
    raise Exception(f"{SYMBOL} not found")

if not symbol_info.visible:
    mt5.symbol_select(SYMBOL, True)

tick = mt5.symbol_info_tick(SYMBOL)
if tick is None:
    raise Exception("Failed to get tick")

price = tick.ask

# =========================
# PREPARE ORDER
# =========================
lot = 0.01

request = {
    "action": mt5.TRADE_ACTION_DEAL,
    "symbol": SYMBOL,
    "volume": lot,
    "type": mt5.ORDER_TYPE_BUY,
    "price": price,
    "deviation": 20,
    "magic": 123456,
    "comment": "python test order",
    "type_time": mt5.ORDER_TIME_GTC,
    "type_filling": mt5.ORDER_FILLING_IOC,
}

# =========================
# SEND ORDER
# =========================
result = mt5.order_send(request)

if result is None:
    raise Exception("order_send returned None")

print("Result:")
print("retcode:", result.retcode)

if result.retcode != mt5.TRADE_RETCODE_DONE:
    print("Order failed:", result)
else:
    print("Order success!")
    print("Order ticket:", result.order)
    print("Deal ticket:", result.deal)

# =========================
# SHUTDOWN
# =========================
mt5.shutdown()
print("MT5 disconnected")