//+------------------------------------------------------------------+
//| EURUSD_H1_run2011_w0000.mq5
//|                                                                  |
//| Source        : Walk-forward meta-pipeline report (calendar mode)|
//| Window        : run_2011 / window_0000
//| Train period  : 2011-01-03 00:00:00 .. 2013-12-31 18:00:00
//| Test period   : 2014-01-01 23:00:00 .. 2014-12-31 19:00:00
//| Report edge   : EURUSD_H1_50 (plateau-centre pick)
//| Rule (SHORT)  : rsi_7 > 75.0 AND stoch_5_3_3_k > 70.0 AND mom_10 > 0.0
//| Exit          : close after 11 bars, no broker SL/TP
//| Test result   : expectancy_r=0.6403  PF=1.79  n_trades=281
//+------------------------------------------------------------------+
#property copyright   "eurusdH1"
#property version     "1.00"
#property description "EURUSD H1 | run_2011 / window_0000 | short only"
#property description "Rule: rsi_7 > 75.0 AND stoch_5_3_3_k > 70.0 AND mom_10 > 0.0"
#property description "Exit: close after 11 bars. No broker SL/TP."

#include "..\..\Include\EurH1Core.mqh"

//--- Inputs
input double InpLots      = 0.01;      // Lot size
input ulong  InpMagic     = 9001000; // Magic number (unique per window)
input int    InpDeviation = 30;        // Max slippage (points)

//--- Fixed by report
const int            HOLD_BARS  = 11;   // close after N bars
const ENUM_ORDER_TYPE TRADE_TYPE = ORDER_TYPE_SELL;
const string         TRADE_TAG  = "run2011_w0000";

//--- State
CBarHoldTrader g_trader;
int g_h_rsi_7 = INVALID_HANDLE;
int g_h_stoch_5_3_3_k = INVALID_HANDLE;
int g_h_mom_10 = INVALID_HANDLE;

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
   g_h_stoch_5_3_3_k = iStochastic(_Symbol, PERIOD_H1, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_h_mom_10 = iMomentum(_Symbol, PERIOD_H1, 10, PRICE_CLOSE);
   if(g_h_rsi_7 == INVALID_HANDLE ||
      g_h_stoch_5_3_3_k == INVALID_HANDLE ||
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
   if(g_h_rsi_7 != INVALID_HANDLE) IndicatorRelease(g_h_rsi_7);
   if(g_h_stoch_5_3_3_k != INVALID_HANDLE) IndicatorRelease(g_h_stoch_5_3_3_k);
   if(g_h_mom_10 != INVALID_HANDLE) IndicatorRelease(g_h_mom_10);
}

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last CLOSED bar (shift 1),      |
//| exactly like DataExporter.mq5 exports bar index 1 per new bar.    |
//+------------------------------------------------------------------+
bool EntrySignal()
{
   double rsi_7, stoch_5_3_3_k, mom_10;
   if(!ReadBuffer(g_h_rsi_7, 0, 1, rsi_7)) return false;
   if(!ReadBuffer(g_h_stoch_5_3_3_k, 0, 1, stoch_5_3_3_k)) return false;
   if(!ReadBuffer(g_h_mom_10, 0, 1, mom_10)) return false;

   return (rsi_7 > 75.0 && stoch_5_3_3_k > 70.0 && mom_10 > 0.0);
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
