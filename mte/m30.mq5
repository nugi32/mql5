//+------------------------------------------------------------------+
//|                                       XAUUSD_M30_212_EA.mq5        |
//|                                                                    |
//| Mined edge: rsi_7 < 20.0 AND stoch_5_3_3_k < 20.0 AND              |
//|             ma_5_lwma > close   (long only)                        |
//|                                                                    |
//| Source: edge_research pipeline, XAUUSD M30 profile.                |
//| Phase 7c simulated stats (see STRATEGY_GATE_RESULTS.csv):          |
//|   n_trades=4185  expectancy_r=+0.0143  profit_factor=1.112         |
//|   win_rate=42.9%  robust_walk_forward=True  gate_passed=True       |
//|                                                                    |
//| Exit scheme (matches Phase 7c trade_simulator.py exactly):         |
//|   SL = entry - 3.0 * ATR(14) at entry bar                          |
//|   TP = entry + 6.0 * ATR(14) at entry bar   (risk:reward 1:2)      |
//|   Max holding = 60 bars, forced close at market if neither hit     |
//|                                                                    |
//| NO broker-side SL/TP is ever set on the position -- both are       |
//| tracked and enforced virtually by this EA, checked once per new    |
//| bar only (never intra-bar), per explicit request. This means a     |
//| terminal/VPS outage between bars leaves the position fully         |
//| unprotected by the broker until the EA resumes -- see the note     |
//| at the end of the chat response before running this live.         |
//+------------------------------------------------------------------+
#property copyright "edge_research"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Hardcoded to the timeframe this edge was mined on. Do NOT infer
//    from Period() -- this EA's indicator values must always be M30,
//    regardless of which chart it is attached to (see project convention:
//    an earlier bug in this project came from inferring the indicator
//    timeframe from the chart instead of hardcoding it).
#define EA_TIMEFRAME PERIOD_M30

//--- Inputs
input double InpLotSize          = 0.01;     // Fixed lot size
input int    InpRsiPeriod        = 7;        // RSI period
input double InpRsiThreshold     = 20.0;     // RSI entry threshold (< this)
input int    InpStochKPeriod     = 5;        // Stochastic %K period
input int    InpStochDPeriod     = 3;        // Stochastic %D period
input int    InpStochSlowing     = 3;        // Stochastic slowing
input double InpStochThreshold   = 20.0;     // Stochastic entry threshold (< this)
input int    InpMaPeriod         = 5;        // MA period (LWMA)
input int    InpAtrPeriod        = 14;       // ATR period
input double InpSlAtrMult        = 3.0;      // Stop-loss distance, in ATR multiples
input double InpTpAtrMult        = 6.0;      // Take-profit distance, in ATR multiples
input int    InpMaxHoldingBars   = 60;       // Force-close after this many bars if neither SL nor TP hit
input ulong  InpMagicNumber      = 30021200; // Unique magic number for this EA

//--- Global state
int      g_handle_rsi   = INVALID_HANDLE;
int      g_handle_stoch = INVALID_HANDLE;
int      g_handle_ma    = INVALID_HANDLE;
int      g_handle_atr   = INVALID_HANDLE;

CTrade   g_trade;
datetime g_last_bar_time   = 0;

//--- Virtual position state (no broker-side SL/TP -- these levels are
//    enforced entirely by this EA's own new-bar checks).
bool     g_in_position    = false;
double   g_virtual_sl     = 0.0;
double   g_virtual_tp     = 0.0;
datetime g_entry_time     = 0;
int      g_bars_held      = 0;
ulong    g_position_ticket = 0;

//--- CSV trade log
int      g_log_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);

   g_handle_rsi   = iRSI(_Symbol, EA_TIMEFRAME, InpRsiPeriod, PRICE_CLOSE);
   g_handle_stoch = iStochastic(_Symbol, EA_TIMEFRAME, InpStochKPeriod, InpStochDPeriod,
                                 InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   g_handle_ma    = iMA(_Symbol, EA_TIMEFRAME, InpMaPeriod, 0, MODE_LWMA, PRICE_CLOSE);
   g_handle_atr   = iATR(_Symbol, EA_TIMEFRAME, InpAtrPeriod);

   if(g_handle_rsi == INVALID_HANDLE || g_handle_stoch == INVALID_HANDLE ||
      g_handle_ma == INVALID_HANDLE || g_handle_atr == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create one or more indicator handles");
      return INIT_FAILED;
   }

   if(!InitializeCsvLog())
   {
      Print("ERROR: Failed to initialize CSV trade log");
      return INIT_FAILED;
   }

   RecoverPositionState();

   Print("XAUUSD_M30_212_EA initialized. Magic=", InpMagicNumber,
         " Timeframe=", EnumToString(EA_TIMEFRAME),
         g_in_position ? " (recovered open position)" : " (no open position)");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Restart-safe recovery: if this EA (or the terminal) restarts     |
//| while a position is open, reconstruct the virtual SL/TP/entry    |
//| state from the position comment rather than losing it.           |
//+------------------------------------------------------------------+
void RecoverPositionState()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      // Comment format: "vsl=<sl>;vtp=<tp>;entry=<time>;bars=<n>"
      string comment = PositionGetString(POSITION_COMMENT);
      double sl = 0.0, tp = 0.0;
      long   entry_time = 0;
      int    bars = 0;

      string parts[];
      int n = StringSplit(comment, ';', parts);
      for(int p = 0; p < n; p++)
      {
         string kv[];
         if(StringSplit(parts[p], '=', kv) != 2) continue;
         if(kv[0] == "vsl")   sl = StringToDouble(kv[1]);
         if(kv[0] == "vtp")   tp = StringToDouble(kv[1]);
         if(kv[0] == "entry") entry_time = StringToInteger(kv[1]);
         if(kv[0] == "bars")  bars = (int)StringToInteger(kv[1]);
      }

      if(sl > 0.0 && tp > 0.0)
      {
         g_in_position     = true;
         g_virtual_sl      = sl;
         g_virtual_tp      = tp;
         g_entry_time      = (datetime)entry_time;
         g_bars_held       = bars;
         g_position_ticket = ticket;
      }
      else
      {
         Print("WARNING: open position found with this magic number but comment ",
               "could not be parsed -- virtual SL/TP unknown. Manual review recommended. ",
               "Ticket=", ticket);
      }
      break; // only one position expected per magic number
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_handle_rsi   != INVALID_HANDLE) IndicatorRelease(g_handle_rsi);
   if(g_handle_stoch != INVALID_HANDLE) IndicatorRelease(g_handle_stoch);
   if(g_handle_ma    != INVALID_HANDLE) IndicatorRelease(g_handle_ma);
   if(g_handle_atr   != INVALID_HANDLE) IndicatorRelease(g_handle_atr);

   if(g_log_handle != INVALID_HANDLE) FileClose(g_log_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function -- everything gated on a new completed bar. |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_bar_time = iTime(_Symbol, EA_TIMEFRAME, 0);
   if(current_bar_time == g_last_bar_time) return; // not a new bar yet
   g_last_bar_time = current_bar_time;

   // All decisions use bar shift 1 -- the last fully completed bar --
   // never shift 0 (still forming), matching the no-lookahead convention
   // used throughout the edge_research pipeline that mined this edge.

   if(g_in_position)
   {
      g_bars_held++;
      CheckVirtualExit();
   }
   else
   {
      CheckEntry();
   }
}

//+------------------------------------------------------------------+
//| Evaluate the entry condition on the last completed bar           |
//+------------------------------------------------------------------+
void CheckEntry()
{
   double rsi_buf[1], stoch_buf[1], ma_buf[1], atr_buf[1];

   if(CopyBuffer(g_handle_rsi,   0, 1, 1, rsi_buf)   <= 0) return;
   if(CopyBuffer(g_handle_stoch, 0, 1, 1, stoch_buf) <= 0) return; // main line = %K
   if(CopyBuffer(g_handle_ma,    0, 1, 1, ma_buf)    <= 0) return;
   if(CopyBuffer(g_handle_atr,   0, 1, 1, atr_buf)   <= 0) return;

   double rsi_7          = rsi_buf[0];
   double stoch_5_3_3_k  = stoch_buf[0];
   double ma_5_lwma      = ma_buf[0];
   double atr_14         = atr_buf[0];
   double close_1        = iClose(_Symbol, EA_TIMEFRAME, 1);

   if(!MathIsValidNumber(rsi_7) || !MathIsValidNumber(stoch_5_3_3_k) ||
      !MathIsValidNumber(ma_5_lwma) || !MathIsValidNumber(atr_14) || atr_14 <= 0.0)
      return;

   bool condition = (rsi_7 < InpRsiThreshold) &&
                     (stoch_5_3_3_k < InpStochThreshold) &&
                     (ma_5_lwma > close_1);

   if(!condition) return;

   double sl_dist = InpSlAtrMult * atr_14;
   double tp_dist = InpTpAtrMult * atr_14;
   if(sl_dist <= 0.0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double virtual_sl = ask - sl_dist;
   double virtual_tp = ask + tp_dist;

   string comment = StringFormat("vsl=%.5f;vtp=%.5f;entry=%d;bars=0",
                                  virtual_sl, virtual_tp, (int)TimeCurrent());

   // No broker-side SL/TP is passed here (both left at 0) -- exits are
   // enforced entirely by CheckVirtualExit() on subsequent new bars.
   if(g_trade.Buy(InpLotSize, _Symbol, 0.0, 0.0, 0.0, comment))
   {
      g_in_position     = true;
      g_virtual_sl      = virtual_sl;
      g_virtual_tp      = virtual_tp;
      g_entry_time      = TimeCurrent();
      g_bars_held       = 0;
      g_position_ticket = g_trade.ResultOrder();

      Print("ENTRY long @ ", ask, " SL=", virtual_sl, " TP=", virtual_tp,
            " ATR=", atr_14, " RSI7=", rsi_7, " Stoch=", stoch_5_3_3_k);
   }
   else
   {
      Print("ERROR: Buy order failed, retcode=", g_trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Check virtual SL/TP/max-holding exit conditions on the last      |
//| completed bar. Checked once per new bar only, never intra-bar,   |
//| using that bar's high/low against the virtual levels.            |
//+------------------------------------------------------------------+
void CheckVirtualExit()
{
   if(!PositionSelectByTicket(g_position_ticket))
   {
      // Position no longer exists (closed manually / by broker) -- reset state.
      Print("WARNING: tracked position ticket not found, resetting virtual state");
      ResetPositionState();
      return;
   }

   double bar_high = iHigh(_Symbol, EA_TIMEFRAME, 1);
   double bar_low  = iLow(_Symbol, EA_TIMEFRAME, 1);

   bool hit_sl = (bar_low  <= g_virtual_sl);
   bool hit_tp = (bar_high >= g_virtual_tp);
   bool timed_out = (g_bars_held >= InpMaxHoldingBars);

   // Conservative assumption when both levels fall inside the same bar's
   // range (true intrabar order unknown from OHLC alone), matching the
   // pipeline's trade_simulator.py "stop_first" default.
   if(hit_sl && hit_tp)
   {
      ClosePosition("SL_AND_TP_SAME_BAR_STOP_FIRST");
   }
   else if(hit_sl)
   {
      ClosePosition("SL_HIT");
   }
   else if(hit_tp)
   {
      ClosePosition("TP_HIT");
   }
   else if(timed_out)
   {
      ClosePosition("MAX_HOLDING_BARS");
   }
   // else: still open, nothing to do until next new bar
}

//+------------------------------------------------------------------+
//| Close the tracked position at market and log the trade           |
//+------------------------------------------------------------------+
void ClosePosition(string reason)
{
   double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume      = PositionGetDouble(POSITION_VOLUME);

   if(!g_trade.PositionClose(g_position_ticket))
   {
      Print("ERROR: failed to close position ", g_position_ticket,
            " retcode=", g_trade.ResultRetcode());
      return;
   }

   double exit_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pips = exit_price - entry_price;
   double sl_dist = entry_price - g_virtual_sl;
   double r_multiple = (sl_dist > 0.0) ? (pips / sl_dist) : 0.0;

   LogTrade(entry_price, exit_price, pips, r_multiple, reason, volume);

   Print("EXIT (", reason, ") @ ", exit_price, " pips=", pips,
         " R=", r_multiple, " bars_held=", g_bars_held);

   ResetPositionState();
}

void ResetPositionState()
{
   g_in_position     = false;
   g_virtual_sl      = 0.0;
   g_virtual_tp      = 0.0;
   g_entry_time      = 0;
   g_bars_held       = 0;
   g_position_ticket = 0;
}

//+------------------------------------------------------------------+
//| CSV trade log                                                    |
//+------------------------------------------------------------------+
bool InitializeCsvLog()
{
   string filename = StringFormat("XAUUSD_M30_212_trades_%d.csv", (int)TimeCurrent());
   g_log_handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(g_log_handle == INVALID_HANDLE) return false;

   FileWrite(g_log_handle, "entry_price", "exit_price", "pips", "r_multiple",
             "exit_reason", "volume", "bars_held", "close_time");
   return true;
}

void LogTrade(double entry_price, double exit_price, double pips, double r_multiple,
              string reason, double volume)
{
   if(g_log_handle == INVALID_HANDLE) return;
   FileWrite(g_log_handle, entry_price, exit_price, pips, r_multiple,
             reason, volume, g_bars_held, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   FileFlush(g_log_handle);
}
//+------------------------------------------------------------------+