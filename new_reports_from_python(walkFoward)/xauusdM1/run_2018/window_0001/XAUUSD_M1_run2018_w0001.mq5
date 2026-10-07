//+------------------------------------------------------------------+
//| XAUUSD_M1_run2018_w0001.mq5
//|                                                                  |
//| Source        : Walk-forward meta-pipeline report (calendar mode)|
//| Window        : run_2018 / window_0001
//| Train period  : 2019-01-02 06:00:00 .. 2021-12-31 20:59:00
//| Test period   : 2022-01-03 01:05:00 .. 2022-12-30 23:57:00
//| Report edge   : XAUUSD_M1_6 (plateau-centre pick)
//| Rule (LONG)   : rsi_21 < 20.0 AND mom_10 > 0.0
//| Exit          : close after 714 bars, no broker SL/TP
//| Test result   : expectancy_r=2.6570  PF=1.17  n_trades=285
//| Test window complete (not truncated).
//+------------------------------------------------------------------+
#property copyright   "xauusdM1"
#property version     "1.00"
#property description "XAUUSD M1 | run_2018 / window_0001 | long only"
#property description "Rule: rsi_21 < 20.0 AND mom_10 > 0.0"
#property description "Exit: close after 714 bars. No broker SL/TP."

#include "..\..\Include\XauM1Core.mqh"

//--- Inputs
input double InpLots      = 0.01;      // Lot size
input ulong  InpMagic     = 8008001; // Magic number (unique per window)
input int    InpDeviation = 30;        // Max slippage (points)

//--- Fixed by report
const int    HOLD_BARS    = 714;  // close after N bars
const string TRADE_TAG    = "run2018_w0001";

//--- State
CBarHoldTrader g_trader;
int g_h_rsi = INVALID_HANDLE;
int g_h_mom = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M1)
   {
      Print("This EA is built for the M1 timeframe. Current: ", EnumToString(Period()));
      return INIT_FAILED;
   }

   if(!g_trader.Init(_Symbol, PERIOD_M1, InpMagic, InpLots, HOLD_BARS, InpDeviation))
   {
      Print("Trader init failed");
      return INIT_FAILED;
   }

   g_h_rsi = iRSI(_Symbol, PERIOD_M1, 21, PRICE_CLOSE);
   g_h_mom = iMomentum(_Symbol, PERIOD_M1, 10, PRICE_CLOSE);
   if(g_h_rsi == INVALID_HANDLE || g_h_mom == INVALID_HANDLE)
   {
      Print("Failed to create indicator handle");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_h_rsi != INVALID_HANDLE) IndicatorRelease(g_h_rsi);
   if(g_h_mom != INVALID_HANDLE) IndicatorRelease(g_h_mom);
}

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last CLOSED bar (shift 1),      |
//| exactly like DataExporter.mq5 exports bar index 1 per new bar.    |
//+------------------------------------------------------------------+
bool EntrySignal()
{
   double rsi_21, mom_10;
   if(!ReadBuffer(g_h_rsi, 0, 1, rsi_21)) return false;
   if(!ReadBuffer(g_h_mom, 0, 1, mom_10)) return false;

   return (rsi_21 < 20.0 && mom_10 > 0.0);
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
      g_trader.OpenLong(TRADE_TAG);
}
