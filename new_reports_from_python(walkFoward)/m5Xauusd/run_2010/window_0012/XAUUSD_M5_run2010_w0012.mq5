//+------------------------------------------------------------------+
//| XAUUSD_M5_run2010_w0012.mq5
//|                                                                  |
//| Source        : Walk-forward meta-pipeline report (calendar mode)|
//| Window        : run_2010 / window_0012
//| Train period  : 2022-01-03 01:05:00 .. 2024-12-31 23:55:00
//| Test period   : 2025-01-02 01:00:00 .. 2025-12-31 23:50:00
//| Report edge   : XAUUSD_M5_40 (plateau-centre pick, 3 edges identical)
//| Rule (LONG)   : rsi_21 < 25.0 AND ma_5_sma > close AND mom_10 > 0.0
//| Exit          : close after 116 bars, no broker SL/TP
//| Test result   : expectancy_r=1.3110  PF=1.63  n_trades=317
//| TRUNCATED test window: OOS data ends 2025-12-31, treat stats with care.
//+------------------------------------------------------------------+
#property copyright   "m5Xauusd"
#property version     "1.00"
#property description "XAUUSD M5 | run_2010 / window_0012 | long only"
#property description "Rule: rsi_21 < 25.0 AND ma_5_sma > close AND mom_10 > 0.0"
#property description "Exit: close after 116 bars. No broker SL/TP."

#include "..\..\Include\XauM5Core.mqh"

//--- Inputs
input double InpLots      = 0.01;      // Lot size
input ulong  InpMagic     = 7000012; // Magic number (unique per window)
input int    InpDeviation = 30;        // Max slippage (points)

//--- Fixed by report
const int             HOLD_BARS  = 116;   // close after N bars
const ENUM_ORDER_TYPE TRADE_TYPE = ORDER_TYPE_BUY;
const string          TRADE_TAG  = "run2010_w0012";

//--- State
CBarHoldTrader g_trader;
int g_h_rsi_21 = INVALID_HANDLE;
int g_h_ma_5_sma = INVALID_HANDLE;
int g_h_mom_10 = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   // Timeframe is hardcoded to the one the edge was mined on.
   if(Period() != PERIOD_M5)
   {
      Print("This EA is built for the M5 timeframe. Current: ", EnumToString(Period()));
      return INIT_FAILED;
   }

   if(!g_trader.Init(_Symbol, PERIOD_M5, InpMagic, InpLots, HOLD_BARS, InpDeviation))
   {
      Print("Trader init failed");
      return INIT_FAILED;
   }

   g_h_rsi_21 = iRSI(_Symbol, PERIOD_M5, 21, PRICE_CLOSE);
   g_h_ma_5_sma = iMA(_Symbol, PERIOD_M5, 5, 0, MODE_SMA, PRICE_CLOSE);
   g_h_mom_10 = iMomentum(_Symbol, PERIOD_M5, 10, PRICE_CLOSE);
   if(g_h_rsi_21 == INVALID_HANDLE ||
      g_h_ma_5_sma == INVALID_HANDLE ||
      g_h_mom_10 == INVALID_HANDLE)
   {
      Print("Failed to create indicator handle");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_h_rsi_21 != INVALID_HANDLE) IndicatorRelease(g_h_rsi_21);
   if(g_h_ma_5_sma != INVALID_HANDLE) IndicatorRelease(g_h_ma_5_sma);
   if(g_h_mom_10 != INVALID_HANDLE) IndicatorRelease(g_h_mom_10);
}

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last CLOSED bar (shift 1),      |
//| exactly like DataExporter.mq5 exports bar index 1 per new bar.    |
//+------------------------------------------------------------------+
bool EntrySignal()
{
   double rsi_21, ma_5_sma, mom_10;
   if(!ReadBuffer(g_h_rsi_21, 0, 1, rsi_21)) return false;
   if(!ReadBuffer(g_h_ma_5_sma, 0, 1, ma_5_sma)) return false;
   if(!ReadBuffer(g_h_mom_10, 0, 1, mom_10)) return false;

   double close_1 = iClose(_Symbol, PERIOD_M5, 1);
   if(close_1 <= 0.0) return false;

   return (rsi_21 < 25.0 && ma_5_sma > close_1 && mom_10 > 0.0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_trader.IsNewBar())
      return;

   // 1) time exit first
   g_trader.ManageExit();

   // 2) one position at a time
   if(g_trader.HasPosition())
      return;

   // 3) entry
   if(EntrySignal())
      g_trader.OpenPosition(TRADE_TYPE, TRADE_TAG);
}
