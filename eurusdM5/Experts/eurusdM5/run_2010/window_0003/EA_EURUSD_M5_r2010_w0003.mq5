//+------------------------------------------------------------------+
//|  EA_EURUSD_M5_r2010_w0003.mq5
//|  Walk-forward edge EA  |  run_2010 / window_0003
//+------------------------------------------------------------------+
//|  Edge id       : EURUSD_M5_142
//|  Direction     : SHORT
//|  Condition     : rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND mom_10 > -5.0
//|  Exit          : close after 138 M5 bars (time exit)
//|  SL / TP       : NONE (no broker SL, no broker TP)
//|  Train period  : 2013-01-01 23:00:00 .. 2015-12-31 20:00:00
//|  Test period   : 2016-01-04 00:00:00 .. 2016-12-30 23:55:00
//|  Report (test) : expectancy_r 0.8530 | PF 1.42 | trades 786
//|
//|  Signal is read from the LAST CLOSED bar (shift 1) when a new bar
//|  opens, exactly like DataExporter.mq5 writes its CSV rows.
//|  Entry = market order at the open of the new bar.
//|  Indicator parameters are identical to DataExporter.mq5.
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward"
#property version     "1.00"
#property description "EURUSD_M5_142 | SHORT | hold 138 bars | no SL / no TP"
#property description "run_2010 / window_0003 - test year 2016"

//--- Edge definition
#define EDGE_ID          "EURUSD_M5_142"
#define EDGE_MAGIC       20100003
#define EDGE_DIRECTION   EDGE_SHORT
#define EDGE_HOLD_BARS   138
#define EDGE_TIMEFRAME   PERIOD_M5
#define EDGE_TEST_FROM   D'2016.01.01 00:00'
#define EDGE_TEST_TO     D'2017.01.01 00:00'

#include <eurusdM5\EdgeEngine.mqh>

//--- Indicator handles
int h_rsi_14 = INVALID_HANDLE;
int h_stoch_14_3_3 = INVALID_HANDLE;
int h_mom_10 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Create indicator handles                                         |
//+------------------------------------------------------------------+
bool EdgeInitIndicators()
{
   h_rsi_14 = iRSI(_Symbol, EDGE_TIMEFRAME, 14, PRICE_CLOSE);
   h_stoch_14_3_3 = iStochastic(_Symbol, EDGE_TIMEFRAME, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_mom_10 = iMomentum(_Symbol, EDGE_TIMEFRAME, 10, PRICE_CLOSE);
   if(h_rsi_14 == INVALID_HANDLE || h_stoch_14_3_3 == INVALID_HANDLE || h_mom_10 == INVALID_HANDLE)
   {
      Print("EURUSD_M5_142: failed to create indicator handle(s), error ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Release indicator handles                                        |
//+------------------------------------------------------------------+
void EdgeReleaseIndicators()
{
   if(h_rsi_14 != INVALID_HANDLE) { IndicatorRelease(h_rsi_14); h_rsi_14 = INVALID_HANDLE; }
   if(h_stoch_14_3_3 != INVALID_HANDLE) { IndicatorRelease(h_stoch_14_3_3); h_stoch_14_3_3 = INVALID_HANDLE; }
   if(h_mom_10 != INVALID_HANDLE) { IndicatorRelease(h_mom_10); h_mom_10 = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Entry signal, evaluated once per new bar on the last closed bar  |
//+------------------------------------------------------------------+
bool EdgeSignal()
{
   const int shift = 1;
   double rsi_14 = 0.0;
   double stoch_14_3_3_k = 0.0;
   double mom_10 = 0.0;

   if(!EdgeReadBuffer(h_rsi_14, 0, shift, rsi_14)) return false;
   if(!EdgeReadBuffer(h_stoch_14_3_3, 0, shift, stoch_14_3_3_k)) return false;
   if(!EdgeReadBuffer(h_mom_10, 0, shift, mom_10)) return false;

   // rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND mom_10 > -5.0
   return (rsi_14 > 75.0 && stoch_14_3_3_k > 80.0 && mom_10 > -5.0);
}
//+------------------------------------------------------------------+
