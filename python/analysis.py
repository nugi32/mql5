import MetaTrader5 as mt5
import pandas as pd
import requests
import json
import re
from datetime import datetime
from dotenv import load_dotenv
import os
import indicator as ind
import inspect
import numpy as np
import mt5TradeUtils as trade_utils
import mt5TradeUtils
import time
print("Using file:", mt5TradeUtils.__file__)

load_dotenv()

OLLAMA_URL = os.getenv("OLLAMA_URL")  # contoh: http://localhost:11434/api/generate
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL")  # contoh: tinyllama

SYMBOL = "BTCUSDm"
TIMEFRAME = mt5.TIMEFRAME_M5

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


# ============================================
# ACCOUNT & POSITION INFO
# ============================================

def get_account_info():
    account = mt5.account_info()
    if account is None:
        return None
    return {
        "balance": account.balance,
        "equity": account.equity,
        "profit": account.profit,
        "free_margin": account.margin_free,
        "used_margin": account.margin,
        "margin_level": account.margin_level,
    }

def get_open_positions(symbol=None):
    if symbol:
        positions = mt5.positions_get(symbol=symbol)
    else:
        positions = mt5.positions_get()
    
    if positions is None:
        return []
    
    pos_list = []
    for pos in positions:
        pos_list.append({
            "ticket": pos.ticket,
            "symbol": pos.symbol,
            "type": "BUY" if pos.type == mt5.POSITION_TYPE_BUY else "SELL",
            "volume": pos.volume,
            "open_price": pos.price_open,
            "current_price": pos.price_current,
            "SL": pos.sl,
            "TP": pos.tp,
            "profit": pos.profit,
        })
    return pos_list

# ============================================
# CONNECTION
# ============================================

def connect_mt5():
    if not mt5.initialize(path=MT5_PATH, login=LOGIN, password=PASSWORD, server=SERVER):
        raise Exception(f"Initialize failed: {mt5.last_error()}")
    print("Connected to MT5:", mt5.terminal_info().connected)


# ============================================
# GET TICK
# ============================================

def get_tick(symbol):
    if not mt5.symbol_select(symbol, True):
        raise Exception(f"Failed to select symbol {symbol}")

    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        raise Exception(f"No tick data for {symbol}")

    tick_dict = tick._asdict()
    df = pd.DataFrame([tick_dict])

    df["time"] = df["time"].apply(lambda x: datetime.fromtimestamp(x))
    df["time_msc"] = df["time_msc"].apply(lambda x: datetime.fromtimestamp(x / 1000))

    return df

# ============================================
# AI ANALYSIS
# ============================================

def analyze_with_ai(tick_df, rsi_value):

    row = tick_df.iloc[0]
    prompt = f"""
Analyze this short-term XAUUSD data.

Bid: {row['bid']}
Ask: {row['ask']}
Spread: {row['ask'] - row['bid']}
IndicatorValue: {rsi_value}

Return ONLY valid JSON:

{{
    "bias": "BUY or SELL or WAIT",
    "confidence": 0.0,
    "risk_level": "LOW/MEDIUM/HIGH",
    "reason": "short technical reason"
}}
"""

    payload = {
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {
            "temperature": 0.2,
            "num_predict": 200
        }
    }

    response = requests.post(OLLAMA_URL, json=payload, timeout=60)

    if response.status_code != 200:
        raise Exception(f"AI request failed: {response.text}")

    result = response.json()

    # Untuk endpoint /api/generate, output ada di field "response"
    content = result.get("response", "")

    # Attempt 1: direct load
    try:
        return json.loads(content)
    except:
        # Attempt 2: regex extract JSON
        match = re.search(r'\{.*\}', content, re.DOTALL)
        if match:
            try:
                return json.loads(match.group())
            except:
                pass

        print("AI returned non-JSON response:")
        print(content)
        return None


# ============================================
# MAIN
# ============================================

if __name__ == "__main__":

    try:
        connect_mt5()
        
        # Track last candle time
        last_candle_time = None
        
        print(f"[{datetime.now()}] Starting AI analysis loop for {SYMBOL} ({TIMEFRAME} minutes)")
        print("Waiting for new candles...\n")
        
        while True:
            try:
                # Get the latest candle time
                rates = mt5.copy_rates_from_pos(SYMBOL, TIMEFRAME, 0, 1)
                if rates is None or len(rates) == 0:
                    print("Failed to get rates, retrying...")
                    time.sleep(5)
                    continue
                
                current_time = rates[0]['time']
                
                # Run analysis only on new candle
                if last_candle_time is None or current_time > last_candle_time:
                    last_candle_time = current_time
                    candle_time_str = datetime.fromtimestamp(current_time).strftime("%Y-%m-%d %H:%M:%S")
                    print(f"\n{'='*60}")
                    print(f"[{datetime.now()}] NEW CANDLE at {candle_time_str}")
                    print(f"{'='*60}\n")

                    try:
                        tick_df = get_tick(SYMBOL)

        # Ambil data historis untuk menghitung indikator
        def get_ohlcv(symbol, timeframe, count=200):
            if not mt5.symbol_select(symbol, True):
                raise Exception(f"Failed to select symbol for rates: {symbol}")
            # correct call: copy_rates_from_pos(symbol, timeframe, start_pos, count)
            rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, count)
            if rates is None or len(rates) == 0:
                # try a smaller count as a fallback
                rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, min(count, 100))
                if rates is None or len(rates) == 0:
                    raise Exception("Failed to get rates")
            df = pd.DataFrame(rates)
            df['time'] = pd.to_datetime(df['time'], unit='s')
            return df

        ohlcv = get_ohlcv(SYMBOL, TIMEFRAME, 500)

        # Daftar indikator yang tersedia beserta parameter non-series
        def list_indicators():
            funcs = {}
            for name, func in inspect.getmembers(ind.Indicators, predicate=inspect.isfunction):
                if name.startswith('_'):
                    continue
                sig = inspect.signature(func)
                # parameter names except the price series (close/high/low/volume)
                params = {k: v.default for k, v in sig.parameters.items() if k not in ('close', 'high', 'low', 'volume')}
                funcs[name] = params
            return funcs

        # Minta AI memilih indikator + parameter (mengembalikan dict)
        def ai_choose_indicator(indicators):
            prompt = {
                "model": OLLAMA_MODEL,
                "prompt": (
                    "You are given a list of technical indicators and their default parameters. "
                    "Choose ONE indicator that is appropriate for short-term XAUUSD M5 and return ONLY JSON with the format:\n"
                    "{\n  \"indicator\": \"name\",\n  \"params\": { \"param1\": value, ... }\n}\n"
                    "Available indicators and defaults:\n" + json.dumps(indicators)
                ),
                "stream": False,
                "format": "json",
                "options": {"temperature": 0.2, "num_predict": 200}
            }

            resp = requests.post(OLLAMA_URL, json=prompt, timeout=30)
            if resp.status_code != 200:
                raise Exception(f"AI request failed: {resp.text}")
            res = resp.json()
            content = res.get('response', '')
            try:
                return json.loads(content)
            except:
                m = re.search(r'\{.*\}', content, re.DOTALL)
                if m:
                    return json.loads(m.group())
                raise Exception('AI did not return JSON for indicator selection')

        indicators = list_indicators()
        try:
            choice = ai_choose_indicator(indicators)
        except Exception:
            # fallback default
            choice = {"indicator": "rsi", "params": {"period": 14}}

        # Normalize and validate AI choice
        def normalize_choice(choice_obj, available):
            if isinstance(choice_obj, str):
                try:
                    choice_obj = json.loads(choice_obj)
                except Exception:
                    choice_obj = {"indicator": choice_obj}
            if not isinstance(choice_obj, dict):
                return {"indicator": "rsi", "params": {"period": 14}}

            name = str(choice_obj.get("indicator", "")).strip()
            params = choice_obj.get("params", {}) if isinstance(choice_obj.get("params", {}), dict) else {}
            if not name:
                return {"indicator": "rsi", "params": {"period": 14}}

            # try exact or partial match against available indicators
            match = None
            for k in available.keys():
                if k.lower() == name.lower() or name.lower() in k.lower():
                    match = k
                    break
            if match is None:
                name_clean = re.sub(r'[^a-zA-Z0-9_]', '', name).lower()
                for k in available.keys():
                    if k.lower() == name_clean:
                        match = k
                        break
            if match is None:
                return {"indicator": "rsi", "params": {"period": 14}}
            return {"indicator": match, "params": params}

        choice = normalize_choice(choice, indicators)

        def compute_indicator(choice, ohlcv_df):
            name = choice.get('indicator')
            params = choice.get('params', {})
            func = getattr(ind.Indicators, name, None)
            if func is None:
                raise Exception(f"Unknown indicator: {name}")

            # prepare series args
            kwargs = {}
            sig = inspect.signature(func)
            if 'close' in sig.parameters:
                kwargs['close'] = ohlcv_df['close'].values
            if 'high' in sig.parameters:
                kwargs['high'] = ohlcv_df['high'].values
            if 'low' in sig.parameters:
                kwargs['low'] = ohlcv_df['low'].values
            if 'volume' in sig.parameters:
                kwargs['volume'] = ohlcv_df['tick_volume'].values if 'tick_volume' in ohlcv_df.columns else ohlcv_df['volume'].values

            # merge params but only those accepted by the function signature
            allowed = [p for p in sig.parameters.keys() if p not in ('close', 'high', 'low', 'volume')]
            params_filtered = {}
            if isinstance(params, dict):
                for k, v in params.items():
                    if k in allowed:
                        # try to coerce numeric-like strings to numbers
                        if isinstance(v, str):
                            try:
                                if '.' in v:
                                    v = float(v)
                                else:
                                    v = int(v)
                            except Exception:
                                pass
                        params_filtered[k] = v
            kwargs.update(params_filtered)

            try:
                out = func(**kwargs)
            except TypeError as e:
                raise Exception(f"Error calling indicator '{name}' with params {params_filtered}: {e}")
            # Normalize output to simple value(s)
            if isinstance(out, tuple):
                vals = []
                for arr in out:
                    try:
                        vals.append(float(np.nan_to_num(arr)[-1]))
                    except Exception:
                        vals.append(None)
                return {f'v{i}': vals[i] for i in range(len(vals))}
            else:
                try:
                    return float(np.nan_to_num(out)[-1])
                except Exception:
                    return None

        indicator_result = compute_indicator(choice, ohlcv)

        print("========== MARKET DATA ==========")
        print("Bid:", tick_df.iloc[0]["bid"])
        print("Ask:", tick_df.iloc[0]["ask"])
        print("Indicator choice:", choice)
        print("Indicator result:", indicator_result)
        print("=================================")

        # Sertakan nilai indikator (atau summary) dalam prompt analisis AI
        ai_result = analyze_with_ai(tick_df, indicator_result)

        # Provide defaults if ai_result is None or incomplete
        if not ai_result or not isinstance(ai_result, dict):
            ai_result = {}
        ai_result.setdefault("bias", "WAIT")
        ai_result.setdefault("confidence", 0.5)
        ai_result.setdefault("risk_level", "MEDIUM")
        ai_result.setdefault("reason", "Unable to determine")

        print("\n========== AI ANALYSIS ==========")
        print("Bias       :", ai_result.get("bias"))
        print("Confidence :", ai_result.get("confidence"))
        print("Risk Level :", ai_result.get("risk_level"))
        print("Reason     :", ai_result.get("reason"))
        print("=================================")

        # Request AI untuk membuat keputusan trade
        def ai_make_trade_decision(account_info, market_data, indicator_info, ai_analysis):
            prompt = f"""
Based on the following market and account context, make a TRADING DECISION.

Account Info:
- Balance: ${account_info['balance']}
- Equity: ${account_info['equity']}
- Free Margin: ${account_info['free_margin']}
- Margin Level: {account_info['margin_level']}%

Market Data:
- Symbol: {market_data['symbol']}
- Bid: {market_data['bid']}
- Ask: {market_data['ask']}
- Spread: {market_data['spread']}

Indicator: {indicator_info['name']} = {indicator_info['value']}

AI Analysis:
- Bias: {ai_analysis['bias']}
- Confidence: {ai_analysis['confidence']}
- Risk Level: {ai_analysis['risk_level']}
- Reason: {ai_analysis['reason']}

Return ONLY valid JSON in this format:
{{
  "action": "BUY or SELL or WAIT",
  "volume": 0.01,
  "stop_loss": price_value,
  "take_profit": price_value,
  "comment": "brief reason for this trade"
}}
"""
            payload = {
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False,
                "format": "json",
                "options": {"temperature": 0.3, "num_predict": 300}
            }

            resp = requests.post(OLLAMA_URL, json=payload, timeout=60)
            if resp.status_code != 200:
                return {"action": "WAIT", "comment": "AI request failed"}

            res = resp.json()
            content = res.get('response', '')
            try:
                return json.loads(content)
            except:
                m = re.search(r'\{.*\}', content, re.DOTALL)
                if m:
                    try:
                        return json.loads(m.group())
                    except:
                        pass
            return {"action": "WAIT", "comment": "Could not parse AI trade decision"}

        account_info = get_account_info()
        open_positions = get_open_positions(SYMBOL)
        
        print("\n========== ACCOUNT INFO ==========")
        print(f"Balance:       ${account_info['balance']:.2f}")
        print(f"Equity:        ${account_info['equity']:.2f}")
        print(f"Profit:        ${account_info['profit']:.2f}")
        print(f"Free Margin:   ${account_info['free_margin']:.2f}")
        print(f"Margin Level:  {account_info['margin_level']:.2f}%")
        print("=================================")

        if open_positions:
            print("\n========== OPEN POSITIONS ==========")
            for pos in open_positions:
                print(f"Ticket: {pos['ticket']}")
                print(f"  Type:     {pos['type']}")
                print(f"  Volume:   {pos['volume']}")
                print(f"  Open:     {pos['open_price']:.5f}")
                print(f"  Current:  {pos['current_price']:.5f}")
                print(f"  SL/TP:    {pos['SL']:.5f} / {pos['TP']:.5f}")
                print(f"  P&L:      ${pos['profit']:.2f}")
            print("=================================")
        else:
            print("\n(No open positions)")

        # Minta AI membuat keputusan trade
        try:
            trade_decision = ai_make_trade_decision(
                account_info,
                {
                    "symbol": SYMBOL,
                    "bid": tick_df.iloc[0]["bid"],
                    "ask": tick_df.iloc[0]["ask"],
                    "spread": tick_df.iloc[0]["ask"] - tick_df.iloc[0]["bid"]
                },
                {
                    "name": choice['indicator'],
                    "value": indicator_result
                },
                ai_result
            )
        except Exception as e:
            print(f"Warning: Trade decision failed: {e}")
            trade_decision = {"action": "WAIT", "comment": f"Decision error: {str(e)}"}

        # Provide defaults for trade_decision if missing
        trade_decision.setdefault("action", "WAIT")
        trade_decision.setdefault("volume", 0.01)
        trade_decision.setdefault("stop_loss", None)
        trade_decision.setdefault("take_profit", None)
        trade_decision.setdefault("comment", "No comment")

        print("\n========== TRADE DECISION ==========")
        print("Action:      ", trade_decision.get("action"))
        print("Volume:      ", trade_decision.get("volume"))
        print("Stop Loss:   ", trade_decision.get("stop_loss"))
        print("Take Profit: ", trade_decision.get("take_profit"))
        print("Comment:     ", trade_decision.get("comment"))
        print("=================================")

        # Eksekusi trade jika AI memberikan signal BUY atau SELL
        if trade_decision.get("action") in ["BUY", "SELL"]:
            try:
                print("\n>>> Executing trade...")
                
                # Validate account has sufficient margin
                if account_info['free_margin'] <= 10:
                    raise Exception(f"Insufficient margin: ${account_info['free_margin']:.2f} (need >$10)")
                
                # Smart lot sizing: calculate what account can afford
                final_lot = 0.01
                sl = None
                tp = None
                
                try:
                    symbol_info = mt5.symbol_info(SYMBOL)
                    if symbol_info is None:
                        raise Exception(f"Symbol {SYMBOL} not found")
                    
                    min_lot = symbol_info.volume_min
                    max_lot = symbol_info.volume_max
                    lot_step = symbol_info.volume_step
                    price = tick_df.iloc[0]["ask"]
                    
                    print(f"Symbol limits: min={min_lot}, max={max_lot}, step={lot_step}")
                    print(f"Current price: {price}, Free margin: ${account_info['free_margin']:.2f}")
                    
                    # Try to find affordable lot size
                    # Start from small and work up
                    for trial_lot in [0.001, 0.005, 0.01, 0.05, 0.1]:
                        if trial_lot > max_lot or trial_lot < min_lot:
                            continue
                        
                        # Rough margin check: at typical leverage 1:100, margin = (lot * price) / 100
                        # But we'll just try to execute and catch error if margin insufficient
                        final_lot = trial_lot
                        break
                    
                    # Round to lot_step
                    final_lot = round(final_lot / lot_step) * lot_step
                    
                    # Cap to balance for safety
                    max_affordable = account_info['balance'] / 100  # Very conservative
                    final_lot = min(final_lot, max_affordable)
                    
                    print(f"Trying lot size: {final_lot:.6f}")
                    
                except Exception as e:
                    final_lot = 0.001
                    print(f"Warning: Lot calculation issue ({str(e)}), using minimal: {final_lot}")
                    
                # Validate and fix SL/TP
                sl = trade_decision.get("stop_loss")
                tp = trade_decision.get("take_profit")
                
                # Remove SL/TP if None/invalid
                if sl is None or (isinstance(sl, (int, float)) and sl <= 0):
                    sl = None
                if tp is None or (isinstance(tp, (int, float)) and tp <= 0):
                    tp = None
                
                print(f"Final decision - Lot: {final_lot:.6f} | SL: {sl} | TP: {tp}")
                print("Symbol trade mode:", symbol_info.trade_mode)
                print("Filling mode:", symbol_info.filling_mode)
                result = trade_utils.open_order(
                    symbol=SYMBOL,
                    order_type=trade_decision.get("action"),
                    lot=final_lot,
                    sl=sl,
                    tp=tp,
                    magic=10001
                )
                
                if result is None:
                    raise Exception("order_send returned None - MT5 error")
                print("\n========== TRADE RESULT ==========")
                print("Order Status: SUCCESS")
                print(f"Ticket:       {result.order}")
                print(f"Action:       {trade_decision.get('action')}")
                print(f"Volume:       {final_lot:.6f}")
                print(f"Price:        {result.price:.5f}")
                print(f"SL:           {sl}")
                print(f"TP:           {tp}")
                print("=================================")
            except Exception as e:
                print("\n========== TRADE RESULT ==========")
                print("Order Status: FAILED")
                print(f"Error:        {str(e)}")
                print("=================================")
        else:
            print("\n>>> No trade executed (WAIT signal)")

    finally:
        mt5.shutdown()