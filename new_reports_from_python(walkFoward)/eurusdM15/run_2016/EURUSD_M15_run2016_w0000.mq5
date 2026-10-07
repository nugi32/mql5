//+------------------------------------------------------------------+
//| EURUSD_M15_run2016_w0000.mq5
//| Walk-forward edge EA | EURUSD M15 | SHORT only
//|
//| Run / Window : run_2016 / window_0000
//| Train period : 2016-01-01 .. 2018-12-31
//| Test  (OOS)  : 2019-01-01 .. 2019-12-31   <- jalankan Strategy Tester di periode ini
//| Source edge  : EURUSD_M15_16
//| Condition    : rsi_14 > 80.0 AND mom_10 > 0.0
//| Exit         : close after 18 bars (NO broker SL/TP)
//| Test stats   : expectancy_r=0.2909  PF=1.30  trades=105
//+------------------------------------------------------------------+
#property copyright "eurusdM15"
#property version   "1.00"
#property description "EURUSD_M15_run2016_w0000 - rsi_14 > 80.0 AND mom_10 > 0.0 -> SELL, close after 18 bars"

#include "..\\Include\\EdgeCore.mqh"

//--- inputs
input double InpLots          = 0.10;      // Lot per trade
input long   InpMagic         = 71016000;   // Magic number (unik per window)
input int    InpDeviation     = 20;        // Max slippage (points)
input bool   InpAllowOverlap  = true;      // Boleh posisi bertumpuk (butuh HEDGING account)
input int    InpMaxPositions  = 0;         // Batas posisi bersamaan (0 = tanpa batas)

//--- edge definition
const int    HOLD_BARS = 18;           // close after N bars
const string EA_NAME   = "EURUSD_M15_run2016_w0000";

//--- state
CTrade g_trade;
bool   g_overlap = false;
int    h_rsi_14 = INVALID_HANDLE;
int    h_mom_10 = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   if(_Period != PERIOD_M15)
   {
      Print(EA_NAME, ": EA ini hanya untuk timeframe M15.");
      return INIT_FAILED;
   }
   if(StringFind(_Symbol, "EURUSD") < 0)
      Print(EA_NAME, ": WARNING - dirancang untuk EURUSD, symbol sekarang ", _Symbol);

   g_overlap = InpAllowOverlap &&
               (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(InpAllowOverlap && !g_overlap)
      Print(EA_NAME, ": akun bukan HEDGING -> overlap dimatikan (maks 1 posisi).");

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   h_rsi_14 = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   h_mom_10 = iMomentum(_Symbol, _Period, 10, PRICE_CLOSE);
   if(h_rsi_14 == INVALID_HANDLE || h_mom_10 == INVALID_HANDLE)
   {
      Print(EA_NAME, ": gagal membuat indicator handle");
      return INIT_FAILED;
   }

   PrintFormat("%s ready | hold=%d bars | overlap=%s", EA_NAME, HOLD_BARS, g_overlap ? "yes" : "no");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_rsi_14 != INVALID_HANDLE) IndicatorRelease(h_rsi_14);
   if(h_mom_10 != INVALID_HANDLE) IndicatorRelease(h_mom_10);
}

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last CLOSED bar (shift 1)      |
//+------------------------------------------------------------------+
bool Signal()
{
   double rsi_14, mom_10;
   if(!GetBuf(h_rsi_14, 0, 1, rsi_14)) return false;
   if(!GetBuf(h_mom_10, 0, 1, mom_10)) return false;

   return (rsi_14 > 80.0 && mom_10 > 0.0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   // 1) time-based exit first
   CloseExpiredPositions(g_trade, InpMagic, HOLD_BARS);

   // 2) position limits
   int open_cnt = CountPositions(InpMagic);
   if(!g_overlap && open_cnt > 0) return;
   if(InpMaxPositions > 0 && open_cnt >= InpMaxPositions) return;

   // 3) entry (SHORT) - no SL, no TP
   if(Signal())
   {
      if(!g_trade.Sell(InpLots, _Symbol, 0.0, 0.0, 0.0, EA_NAME))
         PrintFormat("%s Sell failed err=%d", EA_NAME, GetLastError());
   }
}
//+------------------------------------------------------------------+
