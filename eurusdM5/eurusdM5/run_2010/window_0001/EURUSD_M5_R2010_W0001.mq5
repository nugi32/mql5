//+------------------------------------------------------------------+
//| EURUSD_M5_R2010_W0001.mq5
//| Walk-Forward edge EA  |  EURUSD M5  |  run_2010 / window_0001
//+------------------------------------------------------------------+
//| Edge ID    : EURUSD_M5_20
//| Direction  : SHORT
//| Condition  : stoch_5_3_3_k > 80.0 AND volregime_atr_pctl < 20.0 AND rsi_7 > 70.0
//| Exit       : close after 123 bars (NO broker SL / TP)
//| Train      : 2011-01-03 00:00:00 .. 2013-12-31 18:55:00
//| Test (OOS) : 2014-01-01 23:00:00 .. 2014-12-31 19:55:00
//| OOS result : expectancy_r 0.4338 | PF 1.01 | trades 1011
//| Plateau    : score 0.3263 (only 1 neighbour: EURUSD_M5_5) - weak plateau evidence
//|
//| Signal is evaluated ONCE per new bar on the last CLOSED bar
//| (shift 1) - same convention as the DataExporter. Entry = market
//| order at the open of the new bar.
//+------------------------------------------------------------------+
#property copyright   "Walk-Forward Meta-Pipeline"
#property version     "1.00"
#property strict
#property description "EURUSD_M5_20 (run_2010 / window_0001) - SHORT only"
#property description "Exit by bar count, no broker SL/TP - use with care"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Trade ==="
input double InpLots            = 0.10;      // Lot size
input ulong  InpMagic           = 201001;    // Magic number (unique per window)
input int    InpMaxPositions    = 1;         // Max simultaneous positions (>1 needs HEDGING account)
input int    InpDeviation       = 20;        // Max slippage (points)
input int    InpMaxSpreadPoints = 0;         // Max spread in points (0 = no filter)
input string InpComment         = "R2010W0001 M5_20"; // Order comment

input group "=== Exit (from report) ==="
input int    InpHoldingBars     = 123;    // Close position after N bars

input group "=== Entry thresholds (from report) ==="
input double InpStoch533K_Above                = 80.0;  // stoch_5_3_3_k > 80.0
input double InpVolregimeAtrPctl_Below         = 20.0;  // volregime_atr_pctl < 20.0
input double InpRsi7_Above                     = 70.0;  // rsi_7 > 70.0

input group "=== VolRegime replica (calibrate to your VolRegime_ATR) ==="
input int    InpVolAtrPeriod  = 14;      // ATR period
input int    InpPctlLookback  = 500;     // Bars used for ATR percentile rank
input double InpRegimeLowPct  = 33.33;   // pctl < this  -> regime 0 (low vol)
input double InpRegimeHighPct = 66.67;   // pctl > this  -> regime 2 (high vol)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
bool     g_exitPending = false;
int h_stoch_5_3_3_k = INVALID_HANDLE;
int h_rsi_7 = INVALID_HANDLE;
int h_atr_vol = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_Symbol != "EURUSD")
      Print("WARNING: this EA was researched on EURUSD, attached to ", _Symbol);
   if(_Period != PERIOD_M5)
      Print("WARNING: this EA was researched on M5, attached to ", EnumToString(_Period));
   if(InpHoldingBars < 1 || InpMaxPositions < 1 || InpLots <= 0.0)
   {
      Print("ERROR: invalid inputs (HoldingBars / MaxPositions / Lots)");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxPositions > 1 && AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: InpMaxPositions > 1 requires a HEDGING account; on netting positions will merge.");
   if(InpPctlLookback < 50 || InpVolAtrPeriod < 2)
   {
      Print("ERROR: invalid VolRegime inputs");
      return INIT_PARAMETERS_INCORRECT;
   }
   h_stoch_5_3_3_k = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   if(h_stoch_5_3_3_k == INVALID_HANDLE)
   {
      Print("ERROR: cannot create indicator stoch_5_3_3_k");
      return INIT_FAILED;
   }
   h_rsi_7 = iRSI(_Symbol, _Period, 7, PRICE_CLOSE);
   if(h_rsi_7 == INVALID_HANDLE)
   {
      Print("ERROR: cannot create indicator rsi_7");
      return INIT_FAILED;
   }
   h_atr_vol = iATR(_Symbol, _Period, InpVolAtrPeriod);
   if(h_atr_vol == INVALID_HANDLE)
   {
      Print("ERROR: cannot create ATR (vol regime)");
      return INIT_FAILED;
   }
   PrintFormat("EURUSD_M5_20 ready | stoch_5_3_3_k > 80.0 AND volregime_atr_pctl < 20.0 AND rsi_7 > 70.0 | hold %d bars | magic %I64u", InpHoldingBars, InpMagic);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_stoch_5_3_3_k != INVALID_HANDLE)
      IndicatorRelease(h_stoch_5_3_3_k);
   if(h_rsi_7 != INVALID_HANDLE)
      IndicatorRelease(h_rsi_7);
   if(h_atr_vol != INVALID_HANDLE)
      IndicatorRelease(h_atr_vol);
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // retry exits that failed earlier (requote etc.) without waiting for the next bar
   if(g_exitPending)
      CloseExpiredPositions();

   if(!IsNewBar())
      return;

   // 1) time exit
   CloseExpiredPositions();

   // 2) entry
   if(CountMyPositions() >= InpMaxPositions)
      return;
   if(!SpreadAllowed())
      return;
   if(SignalShort())
      OpenShort();
}

//+------------------------------------------------------------------+
//| New bar detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0 || t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
}

//+------------------------------------------------------------------+
//| SIGNAL (all values taken from the last closed bar, shift = 1)    |
//+------------------------------------------------------------------+
bool SignalShort()
{
   double v = 0.0;
   double pctl = 0.0;
   int    regime = 0;
   if(!CalcVolRegime(pctl, regime))
      return false;

   // stoch_5_3_3_k > 80.0
   if(!ReadBuffer(h_stoch_5_3_3_k, 0, 1, v) || !(v > InpStoch533K_Above))
      return false;

   // volregime_atr_pctl < 20.0
   if(!(pctl < InpVolregimeAtrPctl_Below))
      return false;

   // rsi_7 > 70.0
   if(!ReadBuffer(h_rsi_7, 0, 1, v) || !(v > InpRsi7_Above))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Indicator helper                                                 |
//+------------------------------------------------------------------+
bool ReadBuffer(const int handle, const int buffer, const int shift, double &value)
{
   if(handle == INVALID_HANDLE)
      return false;
   double tmp[1];
   if(CopyBuffer(handle, buffer, shift, 1, tmp) != 1)
      return false;
   if(!MathIsValidNumber(tmp[0]) || tmp[0] == EMPTY_VALUE)
      return false;
   value = tmp[0];
   return true;
}

//+------------------------------------------------------------------+
//| VolRegime replica (no custom indicator needed)                   |
//|  pctl   = percent rank of ATR[1] inside the last N ATR values    |
//|  regime = 0 low vol / 1 mid / 2 high vol (split by pctl)         |
//+------------------------------------------------------------------+
bool CalcVolRegime(double &pctl, int &regime)
{
   if(h_atr_vol == INVALID_HANDLE)
      return false;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h_atr_vol, 0, 1, InpPctlLookback, buf) != InpPctlLookback)
      return false;
   double cur = buf[0];
   if(!MathIsValidNumber(cur) || cur <= 0.0)
      return false;
   int below = 0;
   for(int i = 1; i < InpPctlLookback; i++)
      if(buf[i] < cur)
         below++;
   pctl   = 100.0 * below / (InpPctlLookback - 1);
   regime = (pctl < InpRegimeLowPct) ? 0 : ((pctl > InpRegimeHighPct) ? 2 : 1);
   return true;
}

//+------------------------------------------------------------------+
//| Trading                                                          |
//+------------------------------------------------------------------+
bool SpreadAllowed()
{
   if(InpMaxSpreadPoints <= 0)
      return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints);
}

ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   long modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

double NormalizeLots(const double lots)
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double v = MathFloor(lots / step + 1e-8) * step;
   v = MathMax(minV, MathMin(maxV, v));
   int digits = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   return NormalizeDouble(v, digits);
}

bool OpenShort()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;

   double vol = NormalizeLots(InpLots);
   if(vol <= 0.0)
      return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = vol;
   req.type         = ORDER_TYPE_SELL;
   req.price        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl           = 0.0;                 // no broker SL
   req.tp           = 0.0;                 // no broker TP
   req.deviation    = InpDeviation;
   req.magic        = InpMagic;
   req.comment      = InpComment;
   req.type_filling = GetFillingMode();

   if(!OrderSend(req, res) ||
      (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("OpenShort failed: retcode=%u (%s) err=%d", res.retcode, res.comment, GetLastError());
      return false;
   }
   return true;
}

bool ClosePosition(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.position     = ticket;
   req.volume       = PositionGetDouble(POSITION_VOLUME);
   req.type         = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price        = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.deviation    = InpDeviation;
   req.magic        = InpMagic;
   req.comment      = InpComment;
   req.type_filling = GetFillingMode();

   if(!OrderSend(req, res) ||
      (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("ClosePosition #%I64u failed: retcode=%u (%s)", ticket, res.retcode, res.comment);
      return false;
   }
   return true;
}

bool IsMyPosition(const ulong ticket)
{
   if(ticket == 0)
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   return ((ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

int CountMyPositions()
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsMyPosition(ticket))
         cnt++;
   }
   return cnt;
}

//--- close every position that has been open for >= InpHoldingBars bars
void CloseExpiredPositions()
{
   g_exitPending = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsMyPosition(ticket))
         continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int held = iBarShift(_Symbol, _Period, opened, false);
      if(held < 0)
         held = (int)((TimeCurrent() - opened) / PeriodSeconds(_Period));

      if(held >= InpHoldingBars)
      {
         if(!ClosePosition(ticket))
            g_exitPending = true;
      }
   }
}
//+------------------------------------------------------------------+
