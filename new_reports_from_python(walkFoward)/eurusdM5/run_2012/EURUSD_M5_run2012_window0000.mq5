//+------------------------------------------------------------------+
//| EURUSD_M5_run2012_window0000.mq5
//| Walk-forward window : run_2012 / window_0000
//| Edge id (per window): EURUSD_M5_2
//| Condition           : stoch_14_3_3_k < 20.0 AND ma_10_ema < close
//| Direction           : SHORT
//| Exit                : close after 122 bars (no SL, no TP)
//| Train period        : 2012-01-02 00:00 .. 2014-12-31 19:55
//| Test period (OOS)   : 2015-01-02 09:00 .. 2015-12-31 20:00
//| Report test stats   : expectancy_r=1.4739  PF=1.19  n_trades=272
//+------------------------------------------------------------------+
#property copyright   "eurusdM5 walk-forward EAs"
#property version     "1.00"
#property strict
#property description "EURUSD M5 | run_2012 / window_0000 | stoch_14_3_3_k < 20.0 AND ma_10_ema < close"

#include "..\Include\EdgeCore.mqh"

//--- Edge definition (taken from the walk-forward report)
#define EDGE_HOLD_BARS  122
#define EDGE_DIRECTION  EC_SHORT
#define EDGE_COMMENT    "r2012w0000_M5_2"

//--- Inputs
input group "Trading"
input double InpLots         = 0.10;        // Lot size
input long   InpMagic        = 520120000;   // Magic number (unique per window)
input int    InpSlippage     = 20;          // Max deviation (points)
input int    InpMaxPositions = 0;           // Max open positions (0 = unlimited, hedging account needed)

//--- Indicator handles
int h_stoch14 = INVALID_HANDLE;
int h_ema10   = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last closed bar                |
//+------------------------------------------------------------------+
bool EdgeSignal()
  {
   double k, ema;
   if(!EC_Value(h_stoch14, EC_SIGNAL_SHIFT, k, 0)) return false;   // stoch_14_3_3_k (main)
   if(!EC_Value(h_ema10,   EC_SIGNAL_SHIFT, ema))  return false;   // ma_10_ema
   double close1 = iClose(_Symbol, _Period, EC_SIGNAL_SHIFT);

   return (k < 20.0 && ema < close1);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!EC_ValidateChart())
      return INIT_FAILED;

   h_stoch14 = iStochastic(_Symbol, _Period, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_ema10   = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE);

   if(h_stoch14 == INVALID_HANDLE || h_ema10 == INVALID_HANDLE)
     {
      Print("ERROR: failed to create indicator handle(s)");
      return INIT_FAILED;
     }

   EC_Init((ulong)InpMagic, InpLots, InpSlippage, EDGE_COMMENT);

   PrintFormat("%s ready | hold=%d bars | condition: stoch_14_3_3_k < 20.0 AND ma_10_ema < close", EDGE_COMMENT, EDGE_HOLD_BARS);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EC_Release(h_stoch14);
   EC_Release(h_ema10);
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
