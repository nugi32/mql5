//+------------------------------------------------------------------+
//| EURUSD_H1_run2013_w0000.mq5
//|                                                                  |
//| Source        : Walk-forward meta-pipeline report (calendar mode)|
//| Window        : run_2013 / window_0000
//| Train period  : 2013-01-01 23:00:00 .. 2015-12-31 20:00:00
//| Test period   : 2016-01-04 00:00:00 .. 2016-12-30 23:00:00
//| Report edge   : EURUSD_H1_53 (plateau-centre pick)
//| Rule (SHORT)  : rsi_7 > 80.0 AND stoch_14_3_3_k > 80.0
//| Exit          : close after 12 bars, no broker SL/TP
//| Test result   : expectancy_r=0.0326  PF=1.26  n_trades=200
//+------------------------------------------------------------------+
#property copyright   "eurusdH1"
#property version     "1.00"
#property description "EURUSD H1 | run_2013 / window_0000 | short only"
#property description "Rule: rsi_7 > 80.0 AND stoch_14_3_3_k > 80.0"
#property description "Exit: close after 12 bars. No broker SL/TP."

#include "..\..\Include\EurH1Core.mqh"

//--- Inputs
input double InpLots      = 0.01;      // Lot size
input ulong  InpMagic     = 9003000; // Magic number (unique per window)
input int    InpDeviation = 30;        // Max slippage (points)

//--- Fixed by report
const int            HOLD_BARS  = 12;   // close after N bars
const ENUM_ORDER_TYPE TRADE_TYPE = ORDER_TYPE_SELL;
const string         TRADE_TAG  = "run2013_w0000";

//--- State
CBarHoldTrader g_trader;
int g_h_rsi_7 = INVALID_HANDLE;
int g_h_stoch_14_3_3_k = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   // Timeframe is hardcoded to the one the edge was mined on.
   if(Period() != PERIOD_H1)
   {
      Print("This EA is built for the H1 timeframe. Current: ", EnumToString(Period()));
      return INIT_FAILED;
   }

   if(!g_trader.Init(_Symbol, PERIOD_H1, InpMagic, InpLots, HOLD_BARS, InpDeviation))
   {
      Print("Trader init failed");
      return INIT_FAILED;
   }

   g_h_rsi_7 = iRSI(_Symbol, PERIOD_H1, 7, PRICE_CLOSE);
   g_h_stoch_14_3_3_k = iStochastic(_Symbol, PERIOD_H1, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   if(g_h_rsi_7 == INVALID_HANDLE ||
      g_h_stoch_14_3_3_k == INVALID_HANDLE)
   {
      Print("Failed to create indicator handle");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_h_rsi_7 != INVALID_HANDLE) IndicatorRelease(g_h_rsi_7);
   if(g_h_stoch_14_3_3_k != INVALID_HANDLE) IndicatorRelease(g_h_stoch_14_3_3_k);
}

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last CLOSED bar (shift 1),      |
//| exactly like DataExporter.mq5 exports bar index 1 per new bar.    |
//+------------------------------------------------------------------+
bool EntrySignal()
{
   double rsi_7, stoch_14_3_3_k;
   if(!ReadBuffer(g_h_rsi_7, 0, 1, rsi_7)) return false;
   if(!ReadBuffer(g_h_stoch_14_3_3_k, 0, 1, stoch_14_3_3_k)) return false;

   return (rsi_7 > 80.0 && stoch_14_3_3_k > 80.0);
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
