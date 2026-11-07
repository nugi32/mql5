//+------------------------------------------------------------------+
//| EURUSD_M5_R2010_W0011.mq5
//| Walk-Forward edge EA  |  EURUSD M5  |  run_2010 / window_0011
//+------------------------------------------------------------------+
//| Edge ID    : EURUSD_M5_3
//| Direction  : SHORT
//| Condition  : cci_14 > 100.0 AND ps_dist_sess_h_atr < -0.5
//| Exit       : close after 144 bars (NO broker SL / TP)
//| Train      : 2021-01-04 00:00:00 .. 2023-12-29 23:55:00
//| Test (OOS) : 2024-01-02 00:00:00 .. 2024-12-31 23:55:00
//| OOS result : expectancy_r 0.6043 | PF 1.23 | trades 3715
//| Plateau    : only edge accepted in this window - no neighbours to verify plateau
//|
//| Signal is evaluated ONCE per new bar on the last CLOSED bar
//| (shift 1) - same convention as the DataExporter. Entry = market
//| order at the open of the new bar.
//+------------------------------------------------------------------+
#property copyright   "Walk-Forward Meta-Pipeline"
#property version     "1.00"
#property strict
#property description "EURUSD_M5_3 (run_2010 / window_0011) - SHORT only"
#property description "Exit by bar count, no broker SL/TP - use with care"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Trade ==="
input double InpLots            = 0.10;      // Lot size
input ulong  InpMagic           = 201011;    // Magic number (unique per window)
input int    InpMaxPositions    = 1;         // Max simultaneous positions (>1 needs HEDGING account)
input int    InpDeviation       = 20;        // Max slippage (points)
input int    InpMaxSpreadPoints = 0;         // Max spread in points (0 = no filter)
input string InpComment         = "R2010W0011 M5_3"; // Order comment

input group "=== Exit (from report) ==="
input int    InpHoldingBars     = 144;    // Close position after N bars

input group "=== Entry thresholds (from report) ==="
input double InpCci14_Above                    = 100.0;  // cci_14 > 100.0
input double InpPsDistSessHAtr_Below           = -0.5;  // ps_dist_sess_h_atr < -0.5

input group "=== PriceStructure replica (calibrate to your PriceStructure) ==="
input int    InpPsAtrPeriod   = 14;      // ATR period used to normalise the distance
input int    InpSessionHours  = 8;       // Session length in hours (server time, from 00:00)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
bool     g_exitPending = false;
int h_cci_14 = INVALID_HANDLE;
int h_atr_ps = INVALID_HANDLE;
double g_sessHigh = 0.0;   // cache: previous-session high
long   g_sessKey  = -1;    // cache: start of the current session

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
   if(InpSessionHours < 1 || InpSessionHours > 24 || (24 % InpSessionHours) != 0 || InpPsAtrPeriod < 2)
   {
      Print("ERROR: invalid PriceStructure inputs (session hours must divide 24)");
      return INIT_PARAMETERS_INCORRECT;
   }
   h_cci_14 = iCCI(_Symbol, _Period, 14, PRICE_TYPICAL);
   if(h_cci_14 == INVALID_HANDLE)
   {
      Print("ERROR: cannot create indicator cci_14");
      return INIT_FAILED;
   }
   h_atr_ps = iATR(_Symbol, _Period, InpPsAtrPeriod);
   if(h_atr_ps == INVALID_HANDLE)
   {
      Print("ERROR: cannot create ATR (price structure)");
      return INIT_FAILED;
   }
   PrintFormat("EURUSD_M5_3 ready | cci_14 > 100.0 AND ps_dist_sess_h_atr < -0.5 | hold %d bars | magic %I64u", InpHoldingBars, InpMagic);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_cci_14 != INVALID_HANDLE)
      IndicatorRelease(h_cci_14);
   if(h_atr_ps != INVALID_HANDLE)
      IndicatorRelease(h_atr_ps);
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
   const double close1 = iClose(_Symbol, _Period, 1);
   if(close1 <= 0.0)
      return false;
   double psDist = 0.0;
   if(!CalcPsDistSessH(close1, psDist))
      return false;

   // cci_14 > 100.0
   if(!ReadBuffer(h_cci_14, 0, 1, v) || !(v > InpCci14_Above))
      return false;

   // ps_dist_sess_h_atr < -0.5
   if(!(psDist < InpPsDistSessHAtr_Below))
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
//| PriceStructure replica (no custom indicator needed)              |
//|  Sessions = consecutive blocks of InpSessionHours (server time,  |
//|  anchored at 00:00). Level = high of the PREVIOUS session.       |
//|  dist = (level - price) / ATR   (negative = price above level)   |
//+------------------------------------------------------------------+
bool GetPrevSessionHigh(const datetime barTime, double &level)
{
   const long secs     = (long)InpSessionHours * 3600;
   const long curStart = ((long)barTime / secs) * secs;

   if(curStart == g_sessKey && g_sessHigh > 0.0)
   {
      level = g_sessHigh;
      return true;
   }

   // walk back (skips empty blocks such as weekends)
   for(int k = 1; k <= 10; k++)
   {
      datetime from = (datetime)(curStart - k * secs);
      datetime to   = (datetime)(curStart - (k - 1) * secs - 1);
      double highs[];
      int n = CopyHigh(_Symbol, _Period, from, to, highs);
      if(n > 0)
      {
         double mx = highs[0];
         for(int i = 1; i < n; i++)
            if(highs[i] > mx)
               mx = highs[i];
         g_sessHigh = mx;
         g_sessKey  = curStart;
         level      = mx;
         return true;
      }
   }
   return false;
}

bool CalcPsDistSessH(const double price, double &dist)
{
   double atr = 0.0;
   if(!ReadBuffer(h_atr_ps, 0, 1, atr) || atr <= 0.0)
      return false;
   double level = 0.0;
   if(!GetPrevSessionHigh(iTime(_Symbol, _Period, 1), level))
      return false;
   dist = (level - price) / atr;
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
