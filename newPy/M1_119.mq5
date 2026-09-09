//+------------------------------------------------------------------+
//|                                        XAUUSD_M1_119_RuleEA.mq5   |
//|                                                                  |
//| Rule ID: XAUUSD_M1_119                                           |
//| Hypothesis: Price rally after rsi_21 < 20.0 AND cci_14 < -100.0  |
//| Entry: rsi_21 < 20.0 AND cci_14 < -100.0  -> LONG                |
//| Optimal Horizon: 1 bar (configurable via input)                  |
//| Stats: Prob(Bull) 57.18% vs baseline 49.20%, effect size 0.0931  |
//|        p-adj 0.0000, freq ~331.9/yr, expectancy 0.27R            |
//|                                                                  |
//| Architecture:                                                    |
//|  - MQL5-native indicator handles (same params as DataExporter)   |
//|  - Bar-gated: all logic recalculated exactly once per new bar    |
//|  - Signal read from bar index 1 (last CLOSED bar), never bar 0   |
//|  - No broker-side SL/TP - flat market entry only                 |
//|  - Time-based exit: close after N closed bars, checked every     |
//|    new bar (not tick-by-tick)                                    |
//|  - Virtual position tracking (independent of broker position     |
//|    ticket lifecycle) + CSV trade log                             |
//+------------------------------------------------------------------+
#property copyright "edge_research"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs -----------------------------------------------------------
input group "=== Rule Parameters (from mined edge report) ==="
input int    InpRSI_Period     = 21;      // RSI period
input int    InpCCI_Period     = 14;      // CCI period
input double InpRSI_Threshold  = 20.0;    // Entry: RSI21 < threshold
input double InpCCI_Threshold  = -100.0;  // Entry: CCI14 < threshold
input int    InpHoldBars       = 1;       // Close position after N closed bars (optimal horizon)

input group "=== Trade Management ==="
input double InpLotSize        = 0.01;    // Fixed lot size
input ulong  InpMagicNumber    = 119;     // Magic number (rule id XAUUSD_M1_119)
input int    InpMaxSlippage    = 20;      // Max slippage, points
input double InpMaxSpreadPts   = 300;     // Max allowed spread, points (0 = no filter)

input group "=== Logging ==="
input bool   InpLogTrades      = true;    // Write closed trades to CSV
input string InpLogFileName    = "XAUUSD_M1_119_trades.csv"; // CSV log filename

//--- Globals ------------------------------------------------------------
CTrade         trade;
string         g_symbol;
ENUM_TIMEFRAMES g_timeframe;

int            g_h_rsi   = INVALID_HANDLE;
int            g_h_cci   = INVALID_HANDLE;

datetime       g_last_bar_time   = 0;   // last processed CLOSED-bar time (bar index 1's time)

//--- Virtual position state (tracks OUR managed position, not just broker ticket)
bool           g_pos_open        = false;
ulong          g_pos_ticket      = 0;
datetime       g_pos_entry_time  = 0;   // time of the bar 1 that triggered entry
int            g_bars_held       = 0;   // number of CLOSED bars elapsed since entry
double         g_pos_entry_price = 0.0;

int            g_file_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol    = Symbol();
   g_timeframe = Period();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFillingBySymbol(g_symbol);

   // Same indicator construction as DataExporter.mq5 -> identical values to research pipeline
   g_h_rsi = iRSI(g_symbol, g_timeframe, InpRSI_Period, PRICE_CLOSE);
   g_h_cci = iCCI(g_symbol, g_timeframe, InpCCI_Period, PRICE_TYPICAL);

   if(g_h_rsi == INVALID_HANDLE || g_h_cci == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create indicator handles (RSI=", g_h_rsi, " CCI=", g_h_cci, ")");
      return INIT_FAILED;
     }

   if(InpLogTrades)
      InitializeLogFile();

   // Recover any open position from this EA on this symbol after recompile/restart
   RecoverVirtualPositionFromBroker();

   g_last_bar_time = 0; // force processing on first tick

   Print("===== XAUUSD_M1_119_RuleEA initialized =====");
   Print("Rule: RSI(", InpRSI_Period, ") < ", InpRSI_Threshold,
         " AND CCI(", InpCCI_Period, ") < ", InpCCI_Threshold,
         " -> LONG, close after ", InpHoldBars, " closed bar(s)");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_h_rsi   != INVALID_HANDLE) IndicatorRelease(g_h_rsi);
   if(g_h_cci   != INVALID_HANDLE) IndicatorRelease(g_h_cci);
   if(g_file_handle != INVALID_HANDLE) FileClose(g_file_handle);
  }

//+------------------------------------------------------------------+
//| Expert tick function - strictly bar-gated                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Bar index 1 = last fully CLOSED bar. Its open time only changes once,
   // exactly when a new bar forms, giving us a clean once-per-bar gate.
   datetime closed_bar_time = iTime(g_symbol, g_timeframe, 1);
   if(closed_bar_time == 0 || closed_bar_time == g_last_bar_time)
      return; // still inside the same bar / no data yet - do nothing

   g_last_bar_time = closed_bar_time;

   ProcessNewClosedBar(closed_bar_time);
  }

//+------------------------------------------------------------------+
//| All per-bar logic lives here - called exactly once per new bar   |
//+------------------------------------------------------------------+
void ProcessNewClosedBar(datetime closed_bar_time)
  {
   // 1) Manage any existing position FIRST (time-based exit)
   if(g_pos_open)
     {
      g_bars_held++;

      if(g_bars_held >= InpHoldBars)
        {
         CloseVirtualPosition("time_exit");
        }
     }

   // 2) Only look for a new entry if we are flat
   if(!g_pos_open)
     {
      double rsi_val, cci_val;
      if(!GetIndicatorValue(g_h_rsi, 1, rsi_val)) return;
      if(!GetIndicatorValue(g_h_cci, 1, cci_val)) return;

      bool entry_signal = (rsi_val < InpRSI_Threshold) && (cci_val < InpCCI_Threshold);

      if(entry_signal)
        {
         if(!SpreadOk())
           {
            Print("Signal fired but spread filter blocked entry at ", TimeToString(closed_bar_time));
            return;
           }
         OpenVirtualLong(closed_bar_time, rsi_val, cci_val);
        }
     }
  }

//+------------------------------------------------------------------+
//| Spread filter                                                    |
//+------------------------------------------------------------------+
bool SpreadOk()
  {
   if(InpMaxSpreadPts <= 0) return true;
   double spread_pts = (double)SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   return (spread_pts <= InpMaxSpreadPts);
  }

//+------------------------------------------------------------------+
//| Open a long position - flat entry, no broker SL/TP               |
//+------------------------------------------------------------------+
void OpenVirtualLong(datetime signal_bar_time, double rsi_val, double cci_val)
  {
   double lots = NormalizeLots(InpLotSize);
   double ask  = SymbolInfoDouble(g_symbol, SYMBOL_ASK);

   string comment = StringFormat("XAUUSD_M1_119 rsi=%.2f cci=%.2f", rsi_val, cci_val);

   bool ok = trade.Buy(lots, g_symbol, 0.0, 0.0, 0.0, comment); // price=0 -> market, sl=0, tp=0 (no broker SL/TP)

   if(!ok)
     {
      Print("ERROR: Buy failed. retcode=", trade.ResultRetcode(), " desc=", trade.ResultRetcodeDescription());
      return;
     }

   g_pos_open        = true;
   g_pos_ticket       = trade.ResultOrder();
   g_pos_entry_time   = signal_bar_time;
   g_pos_entry_price  = trade.ResultPrice() > 0 ? trade.ResultPrice() : ask;
   g_bars_held        = 0;

   Print("LONG opened @ ", DoubleToString(g_pos_entry_price, _Digits),
         " | signal_bar=", TimeToString(signal_bar_time),
         " | ticket=", g_pos_ticket,
         " | rsi=", DoubleToString(rsi_val, 2), " cci=", DoubleToString(cci_val, 2));
  }

//+------------------------------------------------------------------+
//| Close the currently tracked virtual position                     |
//+------------------------------------------------------------------+
void CloseVirtualPosition(string reason)
  {
   double exit_price = 0.0;
   bool closed = false;

   if(PositionSelectByTicket(g_pos_ticket))
     {
      exit_price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      closed = trade.PositionClose(g_pos_ticket, InpMaxSlippage);
      if(!closed)
         Print("ERROR: PositionClose failed. retcode=", trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());
     }
   else
     {
      // Ticket no longer exists on broker side (e.g. closed externally) - just reset state
      Print("WARNING: position ticket ", g_pos_ticket, " not found on broker, resetting virtual state");
      closed = true;
      exit_price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
     }

   if(closed)
     {
      double pips = (exit_price - g_pos_entry_price);
      LogClosedTrade(g_pos_entry_time, g_pos_entry_price, exit_price, g_bars_held, reason);

      Print("Position closed (", reason, ") @ ", DoubleToString(exit_price, _Digits),
            " | held_bars=", g_bars_held,
            " | pnl_price=", DoubleToString(pips, _Digits));

      g_pos_open        = false;
      g_pos_ticket       = 0;
      g_pos_entry_time   = 0;
      g_pos_entry_price  = 0.0;
      g_bars_held        = 0;
     }
  }

//+------------------------------------------------------------------+
//| On restart/recompile, reattach to any open position from this EA |
//+------------------------------------------------------------------+
void RecoverVirtualPositionFromBroker()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;

      g_pos_open        = true;
      g_pos_ticket       = ticket;
      g_pos_entry_price  = PositionGetDouble(POSITION_PRICE_OPEN);
      g_pos_entry_time   = (datetime)PositionGetInteger(POSITION_TIME);
      g_bars_held        = 0; // conservative: restart the hold-bar counter

      Print("Recovered existing position on init. ticket=", ticket,
            " entry=", DoubleToString(g_pos_entry_price, _Digits));
      break;
     }
  }

//+------------------------------------------------------------------+
//| Indicator value helper (mirrors DataExporter.mq5 pattern)        |
//+------------------------------------------------------------------+
bool GetIndicatorValue(int handle, int bar_index, double &value, int buffer = 0)
  {
   if(handle == INVALID_HANDLE) return false;

   double buf[1];
   int copied = CopyBuffer(handle, buffer, bar_index, 1, buf);
   if(copied <= 0) return false;

   value = buf[0];
   return (value == value); // reject NaN
  }

//+------------------------------------------------------------------+
//| Lot size normalization to broker constraints                     |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double min_lot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   double norm = MathRound(lots / lot_step) * lot_step;
   norm = MathMax(min_lot, MathMin(max_lot, norm));
   return norm;
  }

//+------------------------------------------------------------------+
//| CSV trade log                                                    |
//+------------------------------------------------------------------+
void InitializeLogFile()
  {
   bool file_exists = FileIsExist(InpLogFileName);
   g_file_handle = FileOpen(InpLogFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ);
   if(g_file_handle == INVALID_HANDLE)
     {
      Print("ERROR: Cannot open log file ", InpLogFileName);
      return;
     }
   FileSeek(g_file_handle, 0, SEEK_END);
   if(!file_exists)
      FileWrite(g_file_handle, "entry_time,entry_price,exit_time,exit_price,bars_held,pnl_price,exit_reason");
  }

void LogClosedTrade(datetime entry_time, double entry_price, double exit_price, int bars_held, string reason)
  {
   if(!InpLogTrades || g_file_handle == INVALID_HANDLE) return;

   datetime exit_time = TimeCurrent();
   double pnl = exit_price - entry_price;

   FileWrite(g_file_handle,
             TimeToString(entry_time, TIME_DATE|TIME_SECONDS),
             DoubleToString(entry_price, _Digits),
             TimeToString(exit_time, TIME_DATE|TIME_SECONDS),
             DoubleToString(exit_price, _Digits),
             bars_held,
             DoubleToString(pnl, _Digits),
             reason);
   FileFlush(g_file_handle);
  }
//+------------------------------------------------------------------+