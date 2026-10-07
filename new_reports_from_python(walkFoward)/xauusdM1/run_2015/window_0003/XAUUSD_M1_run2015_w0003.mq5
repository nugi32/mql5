//+------------------------------------------------------------------+
//| XAUUSD_M1_run2015_w0003.mq5
//|                                                                  |
//| Source        : Walk-forward meta-pipeline report (calendar mode)|
//| Window        : run_2015 / window_0003
//| Train period  : 2018-01-02 09:00:00 .. 2020-12-31 20:59:00
//| Test period   : 2021-01-04 01:05:00 .. 2021-12-31 20:59:00
//| Report edge   : XAUUSD_M1_10 (plateau-centre pick)
//| Rule (LONG)   : rsi_21 < 20.0 AND mom_10 > 0.0
//| Exit          : close after 362 bars, no broker SL/TP
//| Test result   : expectancy_r=0.6881  PF=1.88  n_trades=337
//| Test window complete (not truncated).
//+------------------------------------------------------------------+
#property copyright   "xauusdM1"
#property version     "1.00"
#property description "XAUUSD M1 | run_2015 / window_0003 | long only"
#property description "Rule: rsi_21 < 20.0 AND mom_10 > 0.0"
#property description "Exit: close after 362 bars. No broker SL/TP."

#include "..\..\Include\XauM1Core.mqh"

//--- Inputs
input double InpLots      = 0.01;      // Lot size
input ulong  InpMagic     = 8005003; // Magic number (unique per window)
input int    InpDeviation = 30;        // Max slippage (points)

//--- Fixed by report
const int    HOLD_BARS    = 362;  // close after N bars
const string TRADE_TAG    = "run2015_w0003";

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
