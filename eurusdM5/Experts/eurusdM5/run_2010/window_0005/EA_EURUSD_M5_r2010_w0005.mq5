//+------------------------------------------------------------------+
//|  EA_EURUSD_M5_r2010_w0005.mq5
//|  Walk-forward edge EA  |  run_2010 / window_0005
//+------------------------------------------------------------------+
//|  Edge id       : EURUSD_M5_181
//|  Direction     : SHORT
//|  Condition     : rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0
//|  Exit          : close after 88 M5 bars (time exit)
//|  SL / TP       : NONE (no broker SL, no broker TP)
//|  Train period  : 2015-01-02 09:00:00 .. 2017-12-29 23:55:00
//|  Test period   : 2018-01-02 00:00:00 .. 2018-12-31 22:55:00
//|  Report (test) : expectancy_r 3.1629 | PF 3.07 | trades 81
//|
//|  Signal is read from the LAST CLOSED bar (shift 1) when a new bar
//|  opens, exactly like DataExporter.mq5 writes its CSV rows.
//|  Entry = market order at the open of the new bar.
//|  Indicator parameters are identical to DataExporter.mq5.
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward"
#property version     "1.00"
#property description "EURUSD_M5_181 | SHORT | hold 88 bars | no SL / no TP"
#property description "run_2010 / window_0005 - test year 2018"
#property tester_indicator "VolRegime_ATR.ex5"
#property tester_indicator "PriceStructure.ex5"

//--- Edge definition
#define EDGE_ID          "EURUSD_M5_181"
#define EDGE_MAGIC       20100005
#define EDGE_DIRECTION   EDGE_SHORT
#define EDGE_HOLD_BARS   88
#define EDGE_TIMEFRAME   PERIOD_M5
#define EDGE_TEST_FROM   D'2018.01.01 00:00'
#define EDGE_TEST_TO     D'2019.01.01 00:00'
//--- Custom indicator names (add the sub-folder here if you keep them in one)
#define CUSTOM_IND_VOLREGIME   "VolRegime_ATR"
#define CUSTOM_IND_PRICESTRUCT "PriceStructure"

#include <eurusdM5\EdgeEngine.mqh>

//--- Indicator handles
int h_rsi_14 = INVALID_HANDLE;
int h_stoch_14_3_3 = INVALID_HANDLE;
int h_pricestruct = INVALID_HANDLE;
int h_volregime = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Create indicator handles                                         |
//+------------------------------------------------------------------+
bool EdgeInitIndicators()
{
   h_rsi_14 = iRSI(_Symbol, EDGE_TIMEFRAME, 14, PRICE_CLOSE);
   h_stoch_14_3_3 = iStochastic(_Symbol, EDGE_TIMEFRAME, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_pricestruct = iCustom(_Symbol, EDGE_TIMEFRAME, CUSTOM_IND_PRICESTRUCT);
   h_volregime = iCustom(_Symbol, EDGE_TIMEFRAME, CUSTOM_IND_VOLREGIME);
   if(h_rsi_14 == INVALID_HANDLE || h_stoch_14_3_3 == INVALID_HANDLE || h_pricestruct == INVALID_HANDLE || h_volregime == INVALID_HANDLE)
   {
      Print("EURUSD_M5_181: failed to create indicator handle(s), error ", GetLastError());
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
   if(h_pricestruct != INVALID_HANDLE) { IndicatorRelease(h_pricestruct); h_pricestruct = INVALID_HANDLE; }
   if(h_volregime != INVALID_HANDLE) { IndicatorRelease(h_volregime); h_volregime = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Entry signal, evaluated once per new bar on the last closed bar  |
//+------------------------------------------------------------------+
bool EdgeSignal()
{
   const int shift = 1;
   double rsi_14 = 0.0;
   double stoch_14_3_3_k = 0.0;
   double ps_dist_sess_h_atr = 0.0;
   double volregime_regime = 0.0;

   if(!EdgeReadBuffer(h_rsi_14, 0, shift, rsi_14)) return false;
   if(!EdgeReadBuffer(h_stoch_14_3_3, 0, shift, stoch_14_3_3_k)) return false;
   if(!EdgeReadBuffer(h_pricestruct, 2, shift, ps_dist_sess_h_atr)) return false;
   if(!EdgeReadBuffer(h_volregime, 6, shift, volregime_regime)) return false;

   // rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0
   return (rsi_14 > 75.0 && stoch_14_3_3_k > 80.0 && ps_dist_sess_h_atr < -2.0 && MathAbs(volregime_regime - 1.0) < 0.5);
}
//+------------------------------------------------------------------+
