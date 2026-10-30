//+------------------------------------------------------------------+
//|  EA_EURUSD_M5_r2010_w0001.mq5
//|  Walk-forward edge EA  |  run_2010 / window_0001
//+------------------------------------------------------------------+
//|  Edge id       : EURUSD_M5_20
//|  Direction     : SHORT
//|  Condition     : stoch_5_3_3_k > 80.0 AND volregime_atr_pctl < 20.0 AND rsi_7 > 70.0
//|  Exit          : close after 123 M5 bars (time exit)
//|  SL / TP       : NONE (no broker SL, no broker TP)
//|  Train period  : 2011-01-03 00:00:00 .. 2013-12-31 18:55:00
//|  Test period   : 2014-01-01 23:00:00 .. 2014-12-31 19:55:00
//|  Report (test) : expectancy_r 0.4338 | PF 1.01 | trades 1011
//|
//|  Signal is read from the LAST CLOSED bar (shift 1) when a new bar
//|  opens, exactly like DataExporter.mq5 writes its CSV rows.
//|  Entry = market order at the open of the new bar.
//|  Indicator parameters are identical to DataExporter.mq5.
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward"
#property version     "1.00"
#property description "EURUSD_M5_20 | SHORT | hold 123 bars | no SL / no TP"
#property description "run_2010 / window_0001 - test year 2014"
#property tester_indicator "VolRegime_ATR.ex5"

//--- Edge definition
#define EDGE_ID          "EURUSD_M5_20"
#define EDGE_MAGIC       20100001
#define EDGE_DIRECTION   EDGE_SHORT
#define EDGE_HOLD_BARS   123
#define EDGE_TIMEFRAME   PERIOD_M5
#define EDGE_TEST_FROM   D'2014.01.01 00:00'
#define EDGE_TEST_TO     D'2015.01.01 00:00'
//--- Custom indicator names (add the sub-folder here if you keep them in one)
#define CUSTOM_IND_VOLREGIME   "VolRegime_ATR"

#include <eurusdM5\EdgeEngine.mqh>

//--- Indicator handles
int h_stoch_5_3_3 = INVALID_HANDLE;
int h_volregime = INVALID_HANDLE;
int h_rsi_7 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Create indicator handles                                         |
//+------------------------------------------------------------------+
bool EdgeInitIndicators()
{
   h_stoch_5_3_3 = iStochastic(_Symbol, EDGE_TIMEFRAME, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_volregime = iCustom(_Symbol, EDGE_TIMEFRAME, CUSTOM_IND_VOLREGIME);
   h_rsi_7 = iRSI(_Symbol, EDGE_TIMEFRAME, 7, PRICE_CLOSE);
   if(h_stoch_5_3_3 == INVALID_HANDLE || h_volregime == INVALID_HANDLE || h_rsi_7 == INVALID_HANDLE)
   {
      Print("EURUSD_M5_20: failed to create indicator handle(s), error ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Release indicator handles                                        |
//+------------------------------------------------------------------+
void EdgeReleaseIndicators()
{
   if(h_stoch_5_3_3 != INVALID_HANDLE) { IndicatorRelease(h_stoch_5_3_3); h_stoch_5_3_3 = INVALID_HANDLE; }
   if(h_volregime != INVALID_HANDLE) { IndicatorRelease(h_volregime); h_volregime = INVALID_HANDLE; }
   if(h_rsi_7 != INVALID_HANDLE) { IndicatorRelease(h_rsi_7); h_rsi_7 = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Entry signal, evaluated once per new bar on the last closed bar  |
//+------------------------------------------------------------------+
bool EdgeSignal()
{
   const int shift = 1;
   double stoch_5_3_3_k = 0.0;
   double volregime_atr_pctl = 0.0;
   double rsi_7 = 0.0;

   if(!EdgeReadBuffer(h_stoch_5_3_3, 0, shift, stoch_5_3_3_k)) return false;
   if(!EdgeReadBuffer(h_volregime, 0, shift, volregime_atr_pctl)) return false;
   if(!EdgeReadBuffer(h_rsi_7, 0, shift, rsi_7)) return false;

   // stoch_5_3_3_k > 80.0 AND volregime_atr_pctl < 20.0 AND rsi_7 > 70.0
   return (stoch_5_3_3_k > 80.0 && volregime_atr_pctl < 20.0 && rsi_7 > 70.0);
}
//+------------------------------------------------------------------+
