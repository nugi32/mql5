//+------------------------------------------------------------------+
//| EURUSD_M30_run2011_w0001.mq5
//| Source window : run_2011/window_0001
//| Train period  : 2012-01-02 .. 2014-12-31  (3y)
//| Test period   : 2015-01-02 .. 2015-12-31  (1y)  <- run the Strategy Tester here
//| Edge          : EURUSD_M30_71  (short, hold 24 bars)
//| Condition     : rsi_7 > 80.0 AND stoch_5_3_3_k > 80.0 AND mom_10 > 0.0
//| Report (OOS)  : expectancy_r=0.7101  PF=1.72  trades=272
//| Pick reason   : 6 variants (mom_10 -5/0/5, +ema) give identical results; middle value of plateau, simplest form
//| Symbol/TF     : EURUSD M30 | no broker SL/TP | exit by bar count |
//+------------------------------------------------------------------+
#property copyright "eurusdM30"
#property version   "1.00"
#property description "run_2011/window_0001 | EURUSD_M30_71 | rsi_7 > 80.0 AND stoch_5_3_3_k > 80.0 AND mom_10 > 0.0"

#define EDGE_ID        "EURUSD_M30_71"
#define EDGE_IS_SHORT  true
#define EDGE_HOLD_BARS 24
#define EDGE_MAGIC     710006

#include <eurusdM30\EdgeCore.mqh>

//--- condition exactly as in the report
bool EdgeCondition(const EdgeSnapshot &s)
  {
   return(s.rsi_7 > 80.0
          && s.stoch_5_3_3_k > 80.0
          && s.mom_10 > 0.0);
  }
