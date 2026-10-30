//+------------------------------------------------------------------+
//|  EA_EURUSD_M5_r2010_w0006.mq5
//|  Walk-forward edge EA  |  run_2010 / window_0006
//+------------------------------------------------------------------+
//|  Edge id       : EURUSD_M5_37
//|  Direction     : SHORT
//|  Condition     : rsi_14 > 75.0 AND stoch_5_3_3_k > 80.0 AND ps_dist_sess_h_atr < -1.0
//|  Exit          : close after 88 M5 bars (time exit)
//|  SL / TP       : NONE (no broker SL, no broker TP)
//|  Train period  : 2016-01-04 00:00:00 .. 2018-12-31 22:55:00
//|  Test period   : 2019-01-02 06:00:00 .. 2019-12-31 22:55:00
//|  Report (test) : expectancy_r 1.6914 | PF 1.83 | trades 390
//|
//|  Signal is read from the LAST CLOSED bar (shift 1) when a new bar
//|  opens, exactly like DataExporter.mq5 writes its CSV rows.
//|  Entry = market order at the open of the new bar.
//|  Indicator parameters are identical to DataExporter.mq5.
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward"
#property version     "1.00"
#property description "EURUSD_M5_37 | SHORT | hold 88 bars | no SL / no TP"
#property description "run_2010 / window_0006 - test year 2019"
#property tester_indicator "PriceStructure.ex5"

//--- Edge definition
#define EDGE_ID          "EURUSD_M5_37"
#define EDGE_MAGIC       20100006
#define EDGE_DIRECTION   EDGE_SHORT
#define EDGE_HOLD_BARS   88
#define EDGE_TIMEFRAME   PERIOD_M5
#define EDGE_TEST_FROM   D'2019.01.01 00:00'
#define EDGE_TEST_TO     D'2020.01.01 00:00'
//--- Custom indicator names (add the sub-folder here if you keep them in one)
#define CUSTOM_IND_PRICESTRUCT "PriceStructure"

#include <eurusdM5\EdgeEngine.mqh>

//--- Indicator handles
int h_rsi_14 = INVALID_HANDLE;
int h_stoch_5_3_3 = INVALID_HANDLE;
int h_pricestruct = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Create indicator handles                                         |
//+------------------------------------------------------------------+
bool EdgeInitIndicators()
{
   h_rsi_14 = iRSI(_Symbol, EDGE_TIMEFRAME, 14, PRICE_CLOSE);
   h_stoch_5_3_3 = iStochastic(_Symbol, EDGE_TIMEFRAME, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_pricestruct = iCustom(_Symbol, EDGE_TIMEFRAME, CUSTOM_IND_PRICESTRUCT);
   if(h_rsi_14 == INVALID_HANDLE || h_stoch_5_3_3 == INVALID_HANDLE || h_pricestruct == INVALID_HANDLE)
   {
      Print("EURUSD_M5_37: failed to create indicator handle(s), error ", GetLastError());
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
   if(h_stoch_5_3_3 != INVALID_HANDLE) { IndicatorRelease(h_stoch_5_3_3); h_stoch_5_3_3 = INVALID_HANDLE; }
   if(h_pricestruct != INVALID_HANDLE) { IndicatorRelease(h_pricestruct); h_pricestruct = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Entry signal, evaluated once per new bar on the last closed bar  |
//+------------------------------------------------------------------+
bool EdgeSignal()
{
   const int shift = 1;
   double rsi_14 = 0.0;
   double stoch_5_3_3_k = 0.0;
   double ps_dist_sess_h_atr = 0.0;

   if(!EdgeReadBuffer(h_rsi_14, 0, shift, rsi_14)) return false;
   if(!EdgeReadBuffer(h_stoch_5_3_3, 0, shift, stoch_5_3_3_k)) return false;
   if(!EdgeReadBuffer(h_pricestruct, 2, shift, ps_dist_sess_h_atr)) return false;

   // rsi_14 > 75.0 AND stoch_5_3_3_k > 80.0 AND ps_dist_sess_h_atr < -1.0
   return (rsi_14 > 75.0 && stoch_5_3_3_k > 80.0 && ps_dist_sess_h_atr < -1.0);
}
//+------------------------------------------------------------------+
