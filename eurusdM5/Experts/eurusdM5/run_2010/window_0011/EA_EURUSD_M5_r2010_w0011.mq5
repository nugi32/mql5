//+------------------------------------------------------------------+
//|  EA_EURUSD_M5_r2010_w0011.mq5
//|  Walk-forward edge EA  |  run_2010 / window_0011
//+------------------------------------------------------------------+
//|  Edge id       : EURUSD_M5_3
//|  Direction     : SHORT
//|  Condition     : cci_14 > 100.0 AND ps_dist_sess_h_atr < -0.5
//|  Exit          : close after 144 M5 bars (time exit)
//|  SL / TP       : NONE (no broker SL, no broker TP)
//|  Train period  : 2021-01-04 00:00:00 .. 2023-12-29 23:55:00
//|  Test period   : 2024-01-02 00:00:00 .. 2024-12-31 23:55:00
//|  Report (test) : expectancy_r 0.6043 | PF 1.23 | trades 3715
//|
//|  Signal is read from the LAST CLOSED bar (shift 1) when a new bar
//|  opens, exactly like DataExporter.mq5 writes its CSV rows.
//|  Entry = market order at the open of the new bar.
//|  Indicator parameters are identical to DataExporter.mq5.
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward"
#property version     "1.00"
#property description "EURUSD_M5_3 | SHORT | hold 144 bars | no SL / no TP"
#property description "run_2010 / window_0011 - test year 2024"
#property tester_indicator "PriceStructure.ex5"

//--- Edge definition
#define EDGE_ID          "EURUSD_M5_3"
#define EDGE_MAGIC       20100011
#define EDGE_DIRECTION   EDGE_SHORT
#define EDGE_HOLD_BARS   144
#define EDGE_TIMEFRAME   PERIOD_M5
#define EDGE_TEST_FROM   D'2024.01.01 00:00'
#define EDGE_TEST_TO     D'2025.01.01 00:00'
//--- Custom indicator names (add the sub-folder here if you keep them in one)
#define CUSTOM_IND_PRICESTRUCT "PriceStructure"

#include <eurusdM5\EdgeEngine.mqh>

//--- Indicator handles
int h_cci_14 = INVALID_HANDLE;
int h_pricestruct = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Create indicator handles                                         |
//+------------------------------------------------------------------+
bool EdgeInitIndicators()
{
   h_cci_14 = iCCI(_Symbol, EDGE_TIMEFRAME, 14, PRICE_TYPICAL);
   h_pricestruct = iCustom(_Symbol, EDGE_TIMEFRAME, CUSTOM_IND_PRICESTRUCT);
   if(h_cci_14 == INVALID_HANDLE || h_pricestruct == INVALID_HANDLE)
   {
      Print("EURUSD_M5_3: failed to create indicator handle(s), error ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Release indicator handles                                        |
//+------------------------------------------------------------------+
void EdgeReleaseIndicators()
{
   if(h_cci_14 != INVALID_HANDLE) { IndicatorRelease(h_cci_14); h_cci_14 = INVALID_HANDLE; }
   if(h_pricestruct != INVALID_HANDLE) { IndicatorRelease(h_pricestruct); h_pricestruct = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Entry signal, evaluated once per new bar on the last closed bar  |
//+------------------------------------------------------------------+
bool EdgeSignal()
{
   const int shift = 1;
   double cci_14 = 0.0;
   double ps_dist_sess_h_atr = 0.0;

   if(!EdgeReadBuffer(h_cci_14, 0, shift, cci_14)) return false;
   if(!EdgeReadBuffer(h_pricestruct, 2, shift, ps_dist_sess_h_atr)) return false;

   // cci_14 > 100.0 AND ps_dist_sess_h_atr < -0.5
   return (cci_14 > 100.0 && ps_dist_sess_h_atr < -0.5);
}
//+------------------------------------------------------------------+
