//+------------------------------------------------------------------+
//| EURUSD_M30_run2010_w0001.mq5
//| Source window : run_2010/window_0001
//| Train period  : 2011-01-03 .. 2013-12-31  (3y)
//| Test period   : 2014-01-01 .. 2014-12-31  (1y)  <- run the Strategy Tester here
//| Edge          : EURUSD_M30_1  (short, hold 23 bars)
//| Condition     : rsi_14 > 70.0
//| Report (OOS)  : expectancy_r=0.8977  PF=1.71  trades=438
//| Pick reason   : rsi_14>70 and rsi_21>70 both pass with same hold (23); rsi_14 chosen: same plateau, 2x trades
//| Symbol/TF     : EURUSD M30 | no broker SL/TP | exit by bar count |
//+------------------------------------------------------------------+
#property copyright "eurusdM30"
#property version   "1.00"
#property description "run_2010/window_0001 | EURUSD_M30_1 | rsi_14 > 70.0"

#define EDGE_ID        "EURUSD_M30_1"
#define EDGE_IS_SHORT  true
#define EDGE_HOLD_BARS 23
#define EDGE_MAGIC     710001

#include <eurusdM30\EdgeCore.mqh>

//--- condition exactly as in the report
bool EdgeCondition(const EdgeSnapshot &s)
  {
   return(s.rsi_14 > 70.0);
  }
