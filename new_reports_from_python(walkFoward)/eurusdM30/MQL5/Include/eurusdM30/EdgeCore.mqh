//+------------------------------------------------------------------+
//|                                                    EdgeCore.mqh   |
//| Shared engine for all eurusdM30 walk-forward edge EAs.            |
//|                                                                   |
//| Each EA file only defines (before including this header):         |
//|   EDGE_ID, EDGE_IS_SHORT, EDGE_HOLD_BARS, EDGE_MAGIC              |
//| and implements:  bool EdgeCondition(const EdgeSnapshot &s)        |
//|                                                                   |
//| Rules:                                                            |
//|  - Runs only once per new M30 bar (IsNewBar, same as DataExporter)|
//|  - Signal is evaluated on the last CLOSED bar (shift 1), matching |
//|    DataExporter.mq5 (WriteBarToCSVLive uses shift 1)              |
//|  - Entry at market on the first tick of the new bar               |
//|  - NO broker SL / TP. Exit = close after EDGE_HOLD_BARS bars      |
//+------------------------------------------------------------------+
#property copyright "eurusdM30"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Inputs
input double InpLots         = 0.10;            // Lot size
input int    InpDeviation    = 20;              // Max slippage (points)
input int    InpMagic        = EDGE_MAGIC;      // Magic number
input int    InpHoldBars     = EDGE_HOLD_BARS;  // Close after N bars
input bool   InpAllowOverlap = false;           // Allow multiple positions (hedging account only)

#define EDGE_TF PERIOD_M30

//--- Indicator values at the last closed bar (names match report/CSV columns)
struct EdgeSnapshot
  {
   double close;
   double rsi_7, rsi_14, rsi_21;
   double stoch_5_3_3_k;
   double cci_14;
   double mom_10;
   double ma_5_sma, ma_5_ema, ma_5_lwma;
  };

//--- Implemented by each EA file
bool EdgeCondition(const EdgeSnapshot &s);

//--- State
CTrade   g_trade;
datetime g_last_bar_time = 0;
bool     g_allow_overlap = false;

int h_rsi_7 = INVALID_HANDLE, h_rsi_14 = INVALID_HANDLE, h_rsi_21 = INVALID_HANDLE;
int h_stoch_5_3_3 = INVALID_HANDLE;
int h_cci_14 = INVALID_HANDLE;
int h_mom_10 = INVALID_HANDLE;
int h_ma_5_sma = INVALID_HANDLE, h_ma_5_ema = INVALID_HANDLE, h_ma_5_lwma = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool ReadBuffer(const int handle, const int buffer, double &value)
  {
   if(handle == INVALID_HANDLE) return false;
   double b[1];
   if(CopyBuffer(handle, buffer, 1, 1, b) != 1) return false;
   if(b[0] == EMPTY_VALUE || b[0] != b[0]) return false;
   value = b[0];
   return true;
  }

bool BuildSnapshot(EdgeSnapshot &s)
  {
   double c[1];
   if(CopyClose(_Symbol, EDGE_TF, 1, 1, c) != 1) return false;
   s.close = c[0];

   if(!ReadBuffer(h_rsi_7,        0, s.rsi_7))         return false;
   if(!ReadBuffer(h_rsi_14,       0, s.rsi_14))        return false;
   if(!ReadBuffer(h_rsi_21,       0, s.rsi_21))        return false;
   if(!ReadBuffer(h_stoch_5_3_3,  0, s.stoch_5_3_3_k)) return false; // buffer 0 = %K
   if(!ReadBuffer(h_cci_14,       0, s.cci_14))        return false;
   if(!ReadBuffer(h_mom_10,       0, s.mom_10))        return false;
   if(!ReadBuffer(h_ma_5_sma,     0, s.ma_5_sma))      return false;
   if(!ReadBuffer(h_ma_5_ema,     0, s.ma_5_ema))      return false;
   if(!ReadBuffer(h_ma_5_lwma,    0, s.ma_5_lwma))     return false;
   return true;
  }

bool IsNewBar()
  {
   datetime t = iTime(_Symbol, EDGE_TF, 0);
   if(t == 0 || t == g_last_bar_time) return false;
   g_last_bar_time = t;
   return true;
  }

int CountMyPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      n++;
     }
   return n;
  }

double NormalizeLots(double lots)
  {
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep > 0) lots = MathFloor(lots / vstep + 1e-9) * vstep;
   return MathMax(vmin, MathMin(vmax, lots));
  }

//--- Close positions that have been open for >= InpHoldBars bars
void CloseExpiredPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int bars_held = iBarShift(_Symbol, EDGE_TF, opened, false);
      if(bars_held < 0) continue;

      if(bars_held >= InpHoldBars)
        {
         if(!g_trade.PositionClose(ticket))
            PrintFormat("[%s] close failed #%I64u, retcode=%u", EDGE_ID, ticket, g_trade.ResultRetcode());
        }
     }
  }

void TryEnter()
  {
   if(!g_allow_overlap && CountMyPositions() > 0) return;

   EdgeSnapshot s;
   if(!BuildSnapshot(s)) return;
   if(!EdgeCondition(s)) return;

   double lots = NormalizeLots(InpLots);
   bool ok;
   if(EDGE_IS_SHORT) ok = g_trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, EDGE_ID); // sl=0, tp=0
   else              ok = g_trade.Buy (lots, _Symbol, 0.0, 0.0, 0.0, EDGE_ID);

   if(!ok)
      PrintFormat("[%s] open failed, retcode=%u", EDGE_ID, g_trade.ResultRetcode());
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(_Period != EDGE_TF)
     {
      Print("ERROR: this EA must be attached to an M30 chart.");
      return INIT_FAILED;
     }
   if(StringFind(_Symbol, "EURUSD") < 0)
      Print("WARNING: edges were researched on EURUSD, current symbol is ", _Symbol);

   g_allow_overlap = InpAllowOverlap;
   if(g_allow_overlap &&
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("WARNING: not a hedging account, InpAllowOverlap forced to false.");
      g_allow_overlap = false;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   // Same parameters as DataExporter.mq5
   h_rsi_7       = iRSI(_Symbol, EDGE_TF, 7,  PRICE_CLOSE);
   h_rsi_14      = iRSI(_Symbol, EDGE_TF, 14, PRICE_CLOSE);
   h_rsi_21      = iRSI(_Symbol, EDGE_TF, 21, PRICE_CLOSE);
   h_stoch_5_3_3 = iStochastic(_Symbol, EDGE_TF, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_cci_14      = iCCI(_Symbol, EDGE_TF, 14, PRICE_TYPICAL);
   h_mom_10      = iMomentum(_Symbol, EDGE_TF, 10, PRICE_CLOSE);
   h_ma_5_sma    = iMA(_Symbol, EDGE_TF, 5, 0, MODE_SMA,  PRICE_CLOSE);
   h_ma_5_ema    = iMA(_Symbol, EDGE_TF, 5, 0, MODE_EMA,  PRICE_CLOSE);
   h_ma_5_lwma   = iMA(_Symbol, EDGE_TF, 5, 0, MODE_LWMA, PRICE_CLOSE);

   if(h_rsi_7 == INVALID_HANDLE || h_rsi_14 == INVALID_HANDLE || h_rsi_21 == INVALID_HANDLE ||
      h_stoch_5_3_3 == INVALID_HANDLE || h_cci_14 == INVALID_HANDLE || h_mom_10 == INVALID_HANDLE ||
      h_ma_5_sma == INVALID_HANDLE || h_ma_5_ema == INVALID_HANDLE || h_ma_5_lwma == INVALID_HANDLE)
     {
      Print("ERROR: failed to create indicator handles");
      return INIT_FAILED;
     }

   PrintFormat("[%s] started | %s %s | hold=%d bars | magic=%d | no SL/TP",
               EDGE_ID, _Symbol, EnumToString(EDGE_TF), InpHoldBars, InpMagic);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   int hs[] = {h_rsi_7, h_rsi_14, h_rsi_21, h_stoch_5_3_3, h_cci_14, h_mom_10,
               h_ma_5_sma, h_ma_5_ema, h_ma_5_lwma};
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] != INVALID_HANDLE) IndicatorRelease(hs[i]);
  }

//+------------------------------------------------------------------+
//| Expert tick: everything runs once per new bar                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar()) return;

   CloseExpiredPositions();   // 1) exit by time
   TryEnter();                // 2) entry on closed-bar signal
  }
