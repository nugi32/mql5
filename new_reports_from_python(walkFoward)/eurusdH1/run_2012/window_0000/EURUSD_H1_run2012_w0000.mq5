//+------------------------------------------------------------------+
//| EURUSD_H1_run2012_w0000.mq5
//|                                                                  |
//| Source        : Walk-forward meta-pipeline report (calendar mode)|
//| Window        : run_2012 / window_0000
//| Train period  : 2012-01-02 00:00:00 .. 2014-12-31 19:00:00
//| Test period   : 2015-01-02 09:00:00 .. 2015-12-31 20:00:00
//| Report edge   : EURUSD_H1_174 (plateau-centre pick)
//| Rule (SHORT)  : stoch_14_3_3_k > 70.0 AND cci_20 > 100.0 AND ma_5_ema < close AND mom_10 > 0.0
//| Exit          : close after 12 bars, no broker SL/TP
//| Test result   : expectancy_r=0.0317  PF=1.01  n_trades=902
//+------------------------------------------------------------------+
#property copyright   "eurusdH1"
#property version     "1.00"
#property description "EURUSD H1 | run_2012 / window_0000 | short only"
#property description "Rule: stoch_14_3_3_k > 70.0 AND cci_20 > 100.0 AND ma_5_ema < close AND mom_10 > 0.0"
#property description "Exit: close after 12 bars. No broker SL/TP."

#include "..\..\Include\EurH1Core.mqh"

//--- Inputs
input double InpLots      = 0.01;      // Lot size
input ulong  InpMagic     = 9002000; // Magic number (unique per window)
input int    InpDeviation = 30;        // Max slippage (points)

//--- Fixed by report
const int            HOLD_BARS  = 12;   // close after N bars
const ENUM_ORDER_TYPE TRADE_TYPE = ORDER_TYPE_SELL;
const string         TRADE_TAG  = "run2012_w0000";

//--- State
CBarHoldTrader g_trader;
int g_h_stoch_14_3_3_k = INVALID_HANDLE;
int g_h_cci_20 = INVALID_HANDLE;
int g_h_ma_5_ema = INVALID_HANDLE;
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

   g_h_stoch_14_3_3_k = iStochastic(_Symbol, PERIOD_H1, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_h_cci_20 = iCCI(_Symbol, PERIOD_H1, 20, PRICE_TYPICAL);
   g_h_ma_5_ema = iMA(_Symbol, PERIOD_H1, 5, 0, MODE_EMA, PRICE_CLOSE);
   g_h_mom_10 = iMomentum(_Symbol, PERIOD_H1, 10, PRICE_CLOSE);
   if(g_h_stoch_14_3_3_k == INVALID_HANDLE ||
      g_h_cci_20 == INVALID_HANDLE ||
      g_h_ma_5_ema == INVALID_HANDLE ||
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
   if(g_h_stoch_14_3_3_k != INVALID_HANDLE) IndicatorRelease(g_h_stoch_14_3_3_k);
   if(g_h_cci_20 != INVALID_HANDLE) IndicatorRelease(g_h_cci_20);
   if(g_h_ma_5_ema != INVALID_HANDLE) IndicatorRelease(g_h_ma_5_ema);
   if(g_h_mom_10 != INVALID_HANDLE) IndicatorRelease(g_h_mom_10);
}

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last CLOSED bar (shift 1),      |
//| exactly like DataExporter.mq5 exports bar index 1 per new bar.    |
//+------------------------------------------------------------------+
bool EntrySignal()
{
   double stoch_14_3_3_k, cci_20, ma_5_ema, mom_10;
   if(!ReadBuffer(g_h_stoch_14_3_3_k, 0, 1, stoch_14_3_3_k)) return false;
   if(!ReadBuffer(g_h_cci_20, 0, 1, cci_20)) return false;
   if(!ReadBuffer(g_h_ma_5_ema, 0, 1, ma_5_ema)) return false;
   if(!ReadBuffer(g_h_mom_10, 0, 1, mom_10)) return false;

   double close_1 = iClose(_Symbol, PERIOD_H1, 1);
   if(close_1 <= 0.0) return false;

   return (stoch_14_3_3_k > 70.0 && cci_20 > 100.0 && ma_5_ema < close_1 && mom_10 > 0.0);
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
