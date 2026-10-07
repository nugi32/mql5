//+------------------------------------------------------------------+
//| EURUSD_M15_run2010_w0011.mq5
//| Walk-forward edge EA | EURUSD M15 | SHORT only
//|
//| Run / Window : run_2010 / window_0011
//| Train period : 2010-01-01 .. 2012-12-31
//| Test  (OOS)  : 2024-01-01 .. 2024-12-31   <- jalankan Strategy Tester di periode ini
//| Source edge  : EURUSD_M15_36
//| Condition    : rsi_7 > 75.0 AND stoch_5_3_3_k > 80.0
//| Exit         : close after 48 bars (NO broker SL/TP)
//| Test stats   : expectancy_r=0.3459  PF=1.29  trades=1209
//+------------------------------------------------------------------+
#property copyright "eurusdM15"
#property version   "1.00"
#property description "EURUSD_M15_run2010_w0011 - rsi_7 > 75.0 AND stoch_5_3_3_k > 80.0 -> SELL, close after 48 bars"

#include "..\\Include\\EdgeCore.mqh"

//--- inputs
input double InpLots          = 0.10;      // Lot per trade
input long   InpMagic         = 71010011;   // Magic number (unik per window)
input int    InpDeviation     = 20;        // Max slippage (points)
input bool   InpAllowOverlap  = true;      // Boleh posisi bertumpuk (butuh HEDGING account)
input int    InpMaxPositions  = 0;         // Batas posisi bersamaan (0 = tanpa batas)

//--- edge definition
const int    HOLD_BARS = 48;           // close after N bars
const string EA_NAME   = "EURUSD_M15_run2010_w0011";

//--- state
CTrade g_trade;
bool   g_overlap = false;
int    h_rsi_7 = INVALID_HANDLE;
int    h_stoch_5_3_3_k = INVALID_HANDLE;

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

   h_rsi_7 = iRSI(_Symbol, _Period, 7, PRICE_CLOSE);
   h_stoch_5_3_3_k = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   if(h_rsi_7 == INVALID_HANDLE || h_stoch_5_3_3_k == INVALID_HANDLE)
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
   if(h_rsi_7 != INVALID_HANDLE) IndicatorRelease(h_rsi_7);
   if(h_stoch_5_3_3_k != INVALID_HANDLE) IndicatorRelease(h_stoch_5_3_3_k);
}

//+------------------------------------------------------------------+
//| Entry condition, evaluated on the last CLOSED bar (shift 1)      |
//+------------------------------------------------------------------+
bool Signal()
{
   double rsi_7, stoch_5_3_3_k;
   if(!GetBuf(h_rsi_7, 0, 1, rsi_7)) return false;
   if(!GetBuf(h_stoch_5_3_3_k, 0, 1, stoch_5_3_3_k)) return false;

   return (rsi_7 > 75.0 && stoch_5_3_3_k > 80.0);
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
