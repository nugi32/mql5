//+------------------------------------------------------------------+
//|                                                    EURUSD_M30_R5.mq5 |
//| Expert Advisor generated from the Python pipeline ranker report  |
//| "Ranker sort result - EURUSD M30" (row #5).            |
//|                                                                  |
//| - Short-only, time-exit (hold N bars). No SL/TP: the report does  |
//|   not define any (see README.md, "Open points").                 |
//| - All logic runs ONCE per newly opened bar (IsNewBar), reading   |
//|   the just-closed bar at shift 1 - exactly like the DataExporter |
//|   loader (WriteBarToCSVLive: iTime/iClose/CopyBuffer at shift 1).|
//| - Indicator parameters / buffers copied from DataExporter.mq5.   |
//| - Values are rounded as the loader writes them to the CSV        |
//|   (6 decimals; volregime_regime 0 decimals) before comparing.    |
//| - Any missing / invalid indicator value => no signal (the Python |
//|   side treats NaN comparisons as false).                         |
//+------------------------------------------------------------------+
#property copyright "Generated from pipeline report"
#property version   "1.00"
#property description "EURUSD M30 - rules from the Python pipeline ranker report"
#property description "Report row #5: ps_dist_pdh_atr < -0.5 AND stoch_5_3_3_k > 80.0 AND cci_14 > 100.0 AND ma_10_smma < close | short | hold 24 bars"
#property tester_indicator "PriceStructure.ex5"

#define EXPECTED_TF  PERIOD_M30
#define CUSTOM_IND_PRICESTRUCT  "PriceStructure"

enum ENUM_HANDLE_ID  { H_PRICESTRUCT, H_STOCH_5_3_3, H_CCI_14, H_MA_10_SMMA, H_COUNT };
enum ENUM_FEATURE_ID { F_PS_DIST_PDH_ATR, F_STOCH_5_3_3_K, F_CCI_14, F_MA_10_SMMA, F_CLOSE, F_COUNT };
enum ENUM_COMPARE_OP { OP_LT, OP_GT, OP_EQ };

//--- Inputs
const int STRATEGY_RANK = 5;   // row number in the ranker report

input group "=== Trade settings (not defined by the report) ==="
input double   InpLots         = 0.10;     // Fixed lot size
input long     InpMagic        = 72000305; // Magic number
input int      InpDeviation    = 20;       // Max slippage (points)
input bool     InpAllowOverlap = false;    // Allow a new entry while a position is open (hedging accounts only)
input string   InpComment      = "EURUSD_M30_R5"; // Order comment

//--- Rule model
struct Condition
  {
   int      lhs;            // feature id (left side)
   int      op;             // ENUM_COMPARE_OP
   bool     rhs_is_feature; // true: compare with another feature (e.g. close)
   int      rhs_feature;
   double   rhs_value;
  };

//--- Globals
ENUM_TIMEFRAMES g_tf = EXPECTED_TF;
int       g_handles[H_COUNT];
bool      g_handleNeeded[H_COUNT];
int       g_featHandle[F_COUNT];
int       g_featBuffer[F_COUNT];
bool      g_featCustom[F_COUNT];
int       g_featDigits[F_COUNT];
string    g_featName[F_COUNT];
bool      g_featNeeded[F_COUNT];

Condition g_rule[];
int       g_ruleSize    = 0;
int       g_hold        = 0;
string    g_ruleText    = "";
bool      g_overlap     = false;
datetime  g_lastBarTime = 0;

const bool g_isLong = false;   // direction from the report
const int SIGNAL_SHIFT = 1;   // closed bar, same as loader (WriteBarToCSVLive)

//+------------------------------------------------------------------+
//| Feature table (parameters/buffers copied from DataExporter.mq5)  |
//+------------------------------------------------------------------+
void InitFeatureTable()
  {
   g_featHandle[F_PS_DIST_PDH_ATR] = H_PRICESTRUCT; g_featBuffer[F_PS_DIST_PDH_ATR] = 0; g_featCustom[F_PS_DIST_PDH_ATR] = true; g_featDigits[F_PS_DIST_PDH_ATR] = 6; g_featName[F_PS_DIST_PDH_ATR] = "ps_dist_pdh_atr";
   g_featHandle[F_STOCH_5_3_3_K] = H_STOCH_5_3_3; g_featBuffer[F_STOCH_5_3_3_K] = 0; g_featCustom[F_STOCH_5_3_3_K] = false; g_featDigits[F_STOCH_5_3_3_K] = 6; g_featName[F_STOCH_5_3_3_K] = "stoch_5_3_3_k";
   g_featHandle[F_CCI_14] = H_CCI_14; g_featBuffer[F_CCI_14] = 0; g_featCustom[F_CCI_14] = false; g_featDigits[F_CCI_14] = 6; g_featName[F_CCI_14] = "cci_14";
   g_featHandle[F_MA_10_SMMA] = H_MA_10_SMMA; g_featBuffer[F_MA_10_SMMA] = 0; g_featCustom[F_MA_10_SMMA] = false; g_featDigits[F_MA_10_SMMA] = 6; g_featName[F_MA_10_SMMA] = "ma_10_smma";
   g_featHandle[F_CLOSE] = -1; g_featBuffer[F_CLOSE] = 0; g_featCustom[F_CLOSE] = false; g_featDigits[F_CLOSE] = 6; g_featName[F_CLOSE] = "close";
  }

//+------------------------------------------------------------------+
//| Rule helpers                                                     |
//+------------------------------------------------------------------+
void AddCondValue(const int lhs, const int op, const double value)
  {
   ArrayResize(g_rule, g_ruleSize + 1);
   g_rule[g_ruleSize].lhs            = lhs;
   g_rule[g_ruleSize].op             = op;
   g_rule[g_ruleSize].rhs_is_feature = false;
   g_rule[g_ruleSize].rhs_feature    = -1;
   g_rule[g_ruleSize].rhs_value      = value;
   g_featNeeded[lhs] = true;
   g_ruleSize++;
  }

void AddCondFeature(const int lhs, const int op, const int rhs_feature)
  {
   ArrayResize(g_rule, g_ruleSize + 1);
   g_rule[g_ruleSize].lhs            = lhs;
   g_rule[g_ruleSize].op             = op;
   g_rule[g_ruleSize].rhs_is_feature = true;
   g_rule[g_ruleSize].rhs_feature    = rhs_feature;
   g_rule[g_ruleSize].rhs_value      = 0.0;
   g_featNeeded[lhs]         = true;
   g_featNeeded[rhs_feature] = true;
   g_ruleSize++;
  }

//+------------------------------------------------------------------+
//| Rules exactly as listed in the report (long, hold in bars)       |
//+------------------------------------------------------------------+
bool BuildRule(const int rank)
  {
   ArrayResize(g_rule, 0);
   g_ruleSize = 0;
   switch(rank)
     {
      case 5:
         AddCondValue(F_PS_DIST_PDH_ATR, OP_LT, -0.5);
         AddCondValue(F_STOCH_5_3_3_K, OP_GT, 80.0);
         AddCondValue(F_CCI_14, OP_GT, 100.0);
         AddCondFeature(F_MA_10_SMMA, OP_LT, F_CLOSE);
         g_hold = 24;
         g_ruleText = "ps_dist_pdh_atr < -0.5 AND stoch_5_3_3_k > 80.0 AND cci_14 > 100.0 AND ma_10_smma < close | short | hold 24 bars";
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Create the indicator handles required by the selected rule       |
//+------------------------------------------------------------------+
bool CreateHandles()
  {
   for(int i = 0; i < H_COUNT; i++)
      g_handles[i] = INVALID_HANDLE;
   if(g_handleNeeded[H_PRICESTRUCT])
     {
      g_handles[H_PRICESTRUCT] = iCustom(_Symbol, g_tf, CUSTOM_IND_PRICESTRUCT);
      if(g_handles[H_PRICESTRUCT] == INVALID_HANDLE)
        {
         Print("ERROR: failed to create indicator handle H_PRICESTRUCT (error ", GetLastError(), ")");
         return false;
        }
     }
   if(g_handleNeeded[H_STOCH_5_3_3])
     {
      g_handles[H_STOCH_5_3_3] = iStochastic(_Symbol, g_tf, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
      if(g_handles[H_STOCH_5_3_3] == INVALID_HANDLE)
        {
         Print("ERROR: failed to create indicator handle H_STOCH_5_3_3 (error ", GetLastError(), ")");
         return false;
        }
     }
   if(g_handleNeeded[H_CCI_14])
     {
      g_handles[H_CCI_14] = iCCI(_Symbol, g_tf, 14, PRICE_TYPICAL);
      if(g_handles[H_CCI_14] == INVALID_HANDLE)
        {
         Print("ERROR: failed to create indicator handle H_CCI_14 (error ", GetLastError(), ")");
         return false;
        }
     }
   if(g_handleNeeded[H_MA_10_SMMA])
     {
      g_handles[H_MA_10_SMMA] = iMA(_Symbol, g_tf, 10, 0, MODE_SMMA, PRICE_CLOSE);
      if(g_handles[H_MA_10_SMMA] == INVALID_HANDLE)
        {
         Print("ERROR: failed to create indicator handle H_MA_10_SMMA (error ", GetLastError(), ")");
         return false;
        }
     }
   return true;
  }

void ReleaseHandles()
  {
   for(int i = 0; i < H_COUNT; i++)
      if(g_handles[i] != INVALID_HANDLE)
        {
         IndicatorRelease(g_handles[i]);
         g_handles[i] = INVALID_HANDLE;
        }
  }

//+------------------------------------------------------------------+
//| Read one feature at SIGNAL_SHIFT; false => missing/invalid       |
//+------------------------------------------------------------------+
bool ReadFeature(const int f, double &value)
  {
   if(g_featHandle[f] < 0)   // price feature: close
     {
      value = iClose(_Symbol, g_tf, SIGNAL_SHIFT);
      if(value <= 0.0 || !MathIsValidNumber(value))
         return false;
      value = NormalizeDouble(value, g_featDigits[f]);
      return true;
     }

   int h = g_handles[g_featHandle[f]];
   if(h == INVALID_HANDLE)
      return false;
   if(BarsCalculated(h) <= SIGNAL_SHIFT)
      return false;

   double buf[1];
   ResetLastError();
   if(CopyBuffer(h, g_featBuffer[f], SIGNAL_SHIFT, 1, buf) <= 0)
      return false;

   double v = buf[0];
   if(!MathIsValidNumber(v))
      return false;
   if(g_featCustom[f] && (v == EMPTY_VALUE || MathAbs(v) >= 1.0e300))
      return false;

   // same textual precision as the loader's CSV output
   if(g_featDigits[f] == 0)
      v = MathRound(v);
   else
      v = NormalizeDouble(v, g_featDigits[f]);

   value = v;
   return true;
  }

//+------------------------------------------------------------------+
//| Evaluate the selected rule (AND of all conditions)               |
//+------------------------------------------------------------------+
bool EvaluateRule()
  {
   for(int i = 0; i < g_ruleSize; i++)
     {
      double a, b;
      if(!ReadFeature(g_rule[i].lhs, a))
         return false;
      if(g_rule[i].rhs_is_feature)
        {
         if(!ReadFeature(g_rule[i].rhs_feature, b))
            return false;
        }
      else
         b = g_rule[i].rhs_value;

      bool ok = false;
      switch(g_rule[i].op)
        {
         case OP_LT: ok = (a < b);                   break;
         case OP_GT: ok = (a > b);                   break;
         case OP_EQ: ok = (MathAbs(a - b) < 1.0e-9); break;
        }
      if(!ok)
         return false;
     }
   return (g_ruleSize > 0);
  }

//+------------------------------------------------------------------+
//| New-bar detection (same approach as the loader's OnTick)         |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, g_tf, 0);
   if(t <= 0)
      return false;            // series not ready yet
   if(t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
  }

//+------------------------------------------------------------------+
//| Trading helpers                                                  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFilling()
  {
   int fm = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

double NormalizeLots(const double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   double v = MathFloor(lots / step + 1.0e-9) * step;
   v = MathMax(vmin, MathMin(vmax, v));
   int dg = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   return NormalizeDouble(v, dg);
  }

bool TradeOk(const MqlTradeResult &res)
  {
   return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL);
  }

int CountOurPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      n++;
     }
   return n;
  }

bool OpenPosition()
  {
   double vol = NormalizeLots(InpLots);
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = vol;
   req.type         = g_isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price        = SymbolInfoDouble(_Symbol, g_isLong ? SYMBOL_ASK : SYMBOL_BID);
   req.deviation    = (ulong)InpDeviation;
   req.magic        = (ulong)InpMagic;
   req.type_filling = GetFilling();
   req.comment      = InpComment;
   if(!OrderSend(req, res) || !TradeOk(res))
     {
      Print("ENTRY order failed: retcode=", res.retcode, " (", res.comment, ") error=", GetLastError());
      return false;
     }
   return true;
  }

bool ClosePosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = PositionGetDouble(POSITION_VOLUME);
   bool pos_is_buy  = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   req.type         = pos_is_buy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;   // opposite deal
   req.price        = SymbolInfoDouble(_Symbol, pos_is_buy ? SYMBOL_BID : SYMBOL_ASK);
   req.position     = ticket;
   req.deviation    = (ulong)InpDeviation;
   req.magic        = (ulong)InpMagic;
   req.type_filling = GetFilling();
   req.comment      = InpComment;
   if(!OrderSend(req, res) || !TradeOk(res))
     {
      Print("CLOSE failed (ticket ", ticket, "): retcode=", res.retcode, " (", res.comment,
            "). Will retry on the next bar.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Time exit: close positions held for >= g_hold bars               |
//| bars held = bar index (from bar 0) of the bar containing the     |
//| position open time; entry happens on the first tick of the bar   |
//| after the signal bar, so this counts completed bars since entry. |
//+------------------------------------------------------------------+
void ManageExits()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int bars_held = iBarShift(_Symbol, g_tf, open_time, false);
      if(bars_held < 0) continue;

      if(bars_held >= g_hold)
        {
         if(ClosePosition(ticket))
            PrintFormat("EXIT: ticket %I64u closed after %d bars (hold=%d)", ticket, bars_held, g_hold);
        }
     }
  }

//+------------------------------------------------------------------+
//| Everything that happens once per new bar                         |
//+------------------------------------------------------------------+
void ProcessBar()
  {
   // 1) exits
   ManageExits();

   // 2) entry
   if(!g_overlap && CountOurPositions() > 0)
      return;

   if(EvaluateRule())
     {
      if(OpenPosition())
         PrintFormat("ENTRY: %s @ bar %s | rank %d | %s", g_isLong ? "long" : "short", TimeToString(g_lastBarTime), STRATEGY_RANK, g_ruleText);
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(Period() != EXPECTED_TF)
     {
      Print("ERROR: this EA was built for M30 but the chart/tester timeframe is ", EnumToString(Period()));
      return INIT_FAILED;
     }
   if(StringFind(_Symbol, "EURUSD") < 0)
      Print("WARNING: the report is for EURUSD; current symbol is ", _Symbol);
   if(InpLots <= 0.0)
     {
      Print("ERROR: InpLots must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   ArrayInitialize(g_featNeeded, false);
   ArrayInitialize(g_handleNeeded, false);
   InitFeatureTable();

   if(!BuildRule(STRATEGY_RANK))
     {
      Print("ERROR: rule for this report row is not defined");
      return INIT_PARAMETERS_INCORRECT;
     }

   for(int f = 0; f < F_COUNT; f++)
      if(g_featNeeded[f] && g_featHandle[f] >= 0)
         g_handleNeeded[g_featHandle[f]] = true;

   // overlapping entries need per-position exits => hedging accounts only
   g_overlap = InpAllowOverlap;
   if(g_overlap)
     {
      ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
        {
         Print("WARNING: InpAllowOverlap requires a hedging account; overlap disabled.");
         g_overlap = false;
        }
     }

   if(!CreateHandles())
     {
      ReleaseHandles();
      return INIT_FAILED;
     }

   PrintFormat("EA ready | %s %s | rank %d | %s | hold %d bars | overlap=%s",
               _Symbol, EnumToString(g_tf), STRATEGY_RANK, g_isLong ? "long" : "short", g_hold, g_overlap ? "true" : "false");
   PrintFormat("Rule: %s", g_ruleText);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ReleaseHandles();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar())
      return;
   ProcessBar();
  }
//+------------------------------------------------------------------+
