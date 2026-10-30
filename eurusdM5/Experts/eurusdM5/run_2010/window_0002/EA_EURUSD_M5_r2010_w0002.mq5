//+------------------------------------------------------------------+
//|  EA_EURUSD_M5_r2010_w0002.mq5
//|  Walk-forward edge EA  |  run_2010 / window_0002
//+------------------------------------------------------------------+
//|  Edge id       : EURUSD_M5_16
//|  Direction     : SHORT
//|  Condition     : stoch_5_3_3_k > 80.0 AND ps_dist_sess_h_atr < -0.5 AND volregime_atr_pctl < 20.0
//|  Exit          : close after 41 M5 bars (time exit)
//|  SL / TP       : NONE (no broker SL, no broker TP)
//|  Train period  : 2012-01-02 00:00:00 .. 2014-12-31 19:55:00
//|  Test period   : 2015-01-02 09:00:00 .. 2015-12-31 20:00:00
//|  Report (test) : expectancy_r 1.1272 | PF 1.79 | trades 205
//|
//|  Signal is read from the LAST CLOSED bar (shift 1) when a new bar
//|  opens, exactly like DataExporter.mq5 writes its CSV rows.
//|  Entry = market order at the open of the new bar.
//|  Indicator parameters are identical to DataExporter.mq5.
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward"
#property version     "1.00"
#property description "EURUSD_M5_16 | SHORT | hold 41 bars | no SL / no TP"
#property description "run_2010 / window_0002 - test year 2015"
#property tester_indicator "VolRegime_ATR.ex5"
#property tester_indicator "PriceStructure.ex5"

//--- Edge definition
#define EDGE_ID          "EURUSD_M5_16"
#define EDGE_MAGIC       20100002
#define EDGE_DIRECTION   EDGE_SHORT
#define EDGE_HOLD_BARS   41
#define EDGE_TIMEFRAME   PERIOD_M5
#define EDGE_TEST_FROM   D'2015.01.01 00:00'
#define EDGE_TEST_TO     D'2016.01.01 00:00'
//--- Custom indicator names (add the sub-folder here if you keep them in one)
#define CUSTOM_IND_VOLREGIME   "VolRegime_ATR"
#define CUSTOM_IND_PRICESTRUCT "PriceStructure"

#include <eurusdM5\EdgeEngine.mqh>

//--- Indicator handles
int h_stoch_5_3_3 = INVALID_HANDLE;
int h_pricestruct = INVALID_HANDLE;
int h_volregime = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Create indicator handles                                         |
//+------------------------------------------------------------------+
bool EdgeInitIndicators()
{
   h_stoch_5_3_3 = iStochastic(_Symbol, EDGE_TIMEFRAME, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_pricestruct = iCustom(_Symbol, EDGE_TIMEFRAME, CUSTOM_IND_PRICESTRUCT);
   h_volregime = iCustom(_Symbol, EDGE_TIMEFRAME, CUSTOM_IND_VOLREGIME);
   if(h_stoch_5_3_3 == INVALID_HANDLE || h_pricestruct == INVALID_HANDLE || h_volregime == INVALID_HANDLE)
   {
      Print("EURUSD_M5_16: failed to create indicator handle(s), error ", GetLastError());
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
   if(h_pricestruct != INVALID_HANDLE) { IndicatorRelease(h_pricestruct); h_pricestruct = INVALID_HANDLE; }
   if(h_volregime != INVALID_HANDLE) { IndicatorRelease(h_volregime); h_volregime = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Entry signal, evaluated once per new bar on the last closed bar  |
//+------------------------------------------------------------------+
bool EdgeSignal()
{
   const int shift = 1;
   double stoch_5_3_3_k = 0.0;
   double ps_dist_sess_h_atr = 0.0;
   double volregime_atr_pctl = 0.0;

   if(!EdgeReadBuffer(h_stoch_5_3_3, 0, shift, stoch_5_3_3_k)) return false;
   if(!EdgeReadBuffer(h_pricestruct, 2, shift, ps_dist_sess_h_atr)) return false;
   if(!EdgeReadBuffer(h_volregime, 0, shift, volregime_atr_pctl)) return false;

   // stoch_5_3_3_k > 80.0 AND ps_dist_sess_h_atr < -0.5 AND volregime_atr_pctl < 20.0
   return (stoch_5_3_3_k > 80.0 && ps_dist_sess_h_atr < -0.5 && volregime_atr_pctl < 20.0);
}
//+------------------------------------------------------------------+
