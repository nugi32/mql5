//+------------------------------------------------------------------+
//| EURUSD_M5_run2010_window0005.mq5
//| Walk-forward window : run_2010 / window_0005
//| Edge id (per window): EURUSD_M5_6
//| Condition           : rsi_14 > 75.0 AND stoch_5_3_3_k > 80.0
//| Direction           : SHORT
//| Exit                : close after 114 bars (no SL, no TP)
//| Train period        : 2015-01-02 09:00 .. 2017-12-29 23:55
//| Test period (OOS)   : 2018-01-02 00:00 .. 2018-12-31 22:55
//| Report test stats   : expectancy_r=0.7807  PF=1.42  n_trades=630
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward EAs"
#property version     "1.00"
#property strict
#property description "EURUSD M5 | run_2010 / window_0005 | rsi_14 > 75.0 AND stoch_5_3_3_k > 80.0"

#include "..\Include\EdgeCore.mqh"

//--- Edge definition (taken from the walk-forward report)
#define EDGE_HOLD_BARS  114
#define EDGE_DIRECTION  EC_SHORT
#define EDGE_COMMENT    "r2010w0005_M5_6"

//--- Inputs
input group "Trading"
input double InpLots         = 0.10;        // Lot size
input long   InpMagic        = 520100005;   // Magic number (unique per window)
input int    InpSlippage     = 20;          // Max deviation (points)
input int    InpMaxPositions = 0;           // Max open positions (0 = unlimited, hedging account needed)

//--- Indicator handles
int h_rsi14  = INVALID_HANDLE;
int h_stoch5 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last closed bar                |
//+------------------------------------------------------------------+
bool EdgeSignal()
  {
   double rsi, k;
   if(!EC_Value(h_rsi14,  EC_SIGNAL_SHIFT, rsi)) return false;      // rsi_14
   if(!EC_Value(h_stoch5, EC_SIGNAL_SHIFT, k, 0)) return false;     // stoch_5_3_3_k (main)

   return (rsi > 75.0 && k > 80.0);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!EC_ValidateChart())
      return INIT_FAILED;

   h_rsi14  = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   h_stoch5 = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);

   if(h_rsi14 == INVALID_HANDLE || h_stoch5 == INVALID_HANDLE)
     {
      Print("ERROR: failed to create indicator handle(s)");
      return INIT_FAILED;
     }

   EC_Init((ulong)InpMagic, InpLots, InpSlippage, EDGE_COMMENT);

   PrintFormat("%s ready | hold=%d bars | condition: rsi_14 > 75.0 AND stoch_5_3_3_k > 80.0", EDGE_COMMENT, EDGE_HOLD_BARS);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EC_Release(h_rsi14);
   EC_Release(h_stoch5);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // Everything runs once per new bar
   if(!EC_IsNewBar())
      return;

   // 1) time-stop: close positions that reached the holding period
   EC_CloseExpired(EDGE_HOLD_BARS);

   // 2) entry
   if(InpMaxPositions > 0 && EC_CountPositions() >= InpMaxPositions)
      return;

   if(EdgeSignal())
      EC_Open(EDGE_DIRECTION);
  }
//+------------------------------------------------------------------+
