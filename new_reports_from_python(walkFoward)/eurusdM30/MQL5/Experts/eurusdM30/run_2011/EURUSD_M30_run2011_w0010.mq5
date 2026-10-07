//+------------------------------------------------------------------+
//| EURUSD_M30_run2011_w0010.mq5
//| Source window : run_2011/window_0010
//| Train period  : 2021-01-04 .. 2023-12-29  (3y)
//| Test period   : 2024-01-02 .. 2024-12-31  (1y)  <- run the Strategy Tester here
//| Edge          : EURUSD_M30_95  (short, hold 24 bars)
//| Condition     : rsi_7 > 70.0 AND stoch_5_3_3_k > 80.0 AND ma_5_sma < close AND mom_10 > 0.0
//| Report (OOS)  : expectancy_r=0.3048  PF=1.31  trades=979
//| Pick reason   : 12-edge cluster at exp 0.30/PF 1.30-1.31 (mom_10 -5/0/5 x sma/lwma/none); center of the best (sma) sub-plateau
//| Symbol/TF     : EURUSD M30 | no broker SL/TP | exit by bar count |
//+------------------------------------------------------------------+
#property copyright "eurusdM30"
#property version   "1.00"
#property description "run_2011/window_0010 | EURUSD_M30_95 | rsi_7 > 70.0 AND stoch_5_3_3_k > 80.0 AND ma_5_sma < close AND mom_10 > 0.0"

#define EDGE_ID        "EURUSD_M30_95"
#define EDGE_IS_SHORT  true
#define EDGE_HOLD_BARS 24
#define EDGE_MAGIC     710008

#include <eurusdM30\EdgeCore.mqh>

//--- condition exactly as in the report
bool EdgeCondition(const EdgeSnapshot &s)
  {
   return(s.rsi_7 > 70.0
          && s.stoch_5_3_3_k > 80.0
          && s.ma_5_sma < s.close
          && s.mom_10 > 0.0);
  }
