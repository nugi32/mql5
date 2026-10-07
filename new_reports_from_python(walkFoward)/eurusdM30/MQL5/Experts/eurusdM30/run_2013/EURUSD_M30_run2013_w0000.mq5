//+------------------------------------------------------------------+
//| EURUSD_M30_run2013_w0000.mq5
//| Source window : run_2013/window_0000
//| Train period  : 2013-01-01 .. 2015-12-31  (3y)
//| Test period   : 2016-01-04 .. 2016-12-30  (1y)  <- run the Strategy Tester here
//| Edge          : EURUSD_M30_2  (short, hold 24 bars)
//| Condition     : rsi_7 > 75.0
//| Report (OOS)  : expectancy_r=0.2647  PF=1.3  trades=783
//| Pick reason   : rsi_7>75 and rsi_7>80 both pass (0.26 exp); >75 is inside the plateau with 2x trades
//| Symbol/TF     : EURUSD M30 | no broker SL/TP | exit by bar count |
//+------------------------------------------------------------------+
#property copyright "eurusdM30"
#property version   "1.00"
#property description "run_2013/window_0000 | EURUSD_M30_2 | rsi_7 > 75.0"

#define EDGE_ID        "EURUSD_M30_2"
#define EDGE_IS_SHORT  true
#define EDGE_HOLD_BARS 24
#define EDGE_MAGIC     710012

#include <eurusdM30\EdgeCore.mqh>

//--- condition exactly as in the report
bool EdgeCondition(const EdgeSnapshot &s)
  {
   return(s.rsi_7 > 75.0);
  }
