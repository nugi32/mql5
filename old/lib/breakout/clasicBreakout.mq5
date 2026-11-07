//+------------------------------------------------------------------+
//|          Breakout EA v2 - Fixed                                   |
//|  Scenarios: Valid Breakout | False Breakout | Retest             |
//|                                                                  |
//|  KEY FIX: DetectZone scans bars 2..N+1 (bar[1] is excluded so   |
//|  it can act as the signal/breakout bar without polluting the     |
//|  zone range). DetectZone is skipped when a breakout is tracked   |
//|  so zone levels are preserved for retest entries.                |
//+------------------------------------------------------------------+
#property strict
#property description "Breakout EA: zone detection, 3 entry types, dynamic lot, virtual SL/TP"

//=== ================================================================
//    INPUTS
//=== ================================================================

input group "=== Risk Management ==="
input double InpRiskPct       = 1.0;      // Risk % of balance per trade
input double InpMinLot        = 0.01;     // Minimum lot size
input double InpMaxLot        = 10.0;     // Maximum lot size
input int    InpSlippage      = 10;       // Max slippage (points)
input ulong  InpMagic         = 789012;   // EA magic number

input group "=== ATR ==="
input int    InpATRPeriod     = 14;       // ATR period

input group "=== Zone / Sideways Detection ==="
input int    InpZonePeriod    = 40;       // Bars scanned: bars[2] to bars[N+1]
input int    InpMinZoneBars   = 8;        // Min bars with close inside zone
input double InpZoneATRMult   = 3.0;      // Zone height <= ATR x this = sideways

input group "=== Entry Scenarios ==="
input bool   InpValidBreak    = true;     // Enable: Valid Breakout
input bool   InpFalseBreak    = true;     // Enable: False Breakout (fade)
input bool   InpRetestBreak   = true;     // Enable: Retest after breakout
input double InpBreakBuf      = 0.3;      // Valid break buffer (ATR x)
input double InpFalseSpkMult  = 0.2;      // Min spike beyond zone (ATR x)
input double InpRetestMult    = 0.5;      // Retest proximity to zone edge (ATR x)
input int    InpRetestMaxBars = 30;       // Bars before retest timeout/reset

input group "=== Virtual SL / TP ==="
input double InpSLMult        = 2.0;      // Stop Loss = ATR x this
input double InpTPRR          = 2.0;      // TP = SL x this (Risk:Reward)
input bool   InpSARTrail      = true;     // Use Parabolic SAR trailing stop
input double InpSarStep       = 0.02;
input double InpSarMax        = 0.2;

input group "=== Display ==="
input bool   InpDrawZone      = true;
input color  InpClrHigh       = clrDodgerBlue;
input color  InpClrLow        = clrTomato;
input color  InpClrMid        = clrGold;
input color  InpClrRect       = clrLightSteelBlue;

//=== ================================================================
//    GLOBALS
//=== ================================================================

int g_atrHandle = INVALID_HANDLE;
int g_sarHandle = INVALID_HANDLE;

// Zone levels (set by DetectZone, preserved during breakout tracking)
double g_zHigh  = 0;
double g_zLow   = 0;
double g_zMid   = 0;
bool   g_zValid = false;

// Breakout state machine
// g_brkDir: 0 = in zone (no break yet)
//           1 = upward breakout detected
//          -1 = downward breakout detected
int    g_brkDir = 0;
int    g_brkAge = 0;   // bars elapsed since breakout (retest timeout counter)

// Virtual orders: SL and TP managed in software, not on broker
struct VOrder
{
   ulong  ticket;
   double sl;
   double tp;
};
VOrder g_vords[];

//+------------------------------------------------------------------+
int OnInit()
{
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   g_sarHandle = iSAR(_Symbol, PERIOD_CURRENT, InpSarStep, InpSarMax);

   if (g_atrHandle == INVALID_HANDLE || g_sarHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   ArrayResize(g_vords, 0);
   Print("Breakout EA ready | ", _Symbol, " | Magic: ", InpMagic);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(g_atrHandle);
   IndicatorRelease(g_sarHandle);
   ObjectsDeleteAll(0, "BK_");
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime s_last = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (cur != s_last) { s_last = cur; return true; }
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if (!IsNewBar()) return;

   // ---- 1. Manage virtual SL / TP / trailing ----
   CheckVirtualStops();
   if (InpSARTrail) UpdateTrailingSAR();

   // ---- 2. ATR ----
   double atr[];
   ArraySetAsSeries(atr, true);
   if (CopyBuffer(g_atrHandle, 0, 0, 3, atr) < 3) return;
   double atv = atr[1];
   if (atv <= 0) return;

   // ---- 3. Zone detection ----
   // CRITICAL: only called when g_brkDir == 0.
   // While tracking a breakout, zone levels must stay frozen for retest.
   if (g_brkDir == 0)
      DetectZone(atv);

   if (InpDrawZone && g_zValid) DrawZone();

   // ---- 4. Retest timeout ----
   if (g_brkDir != 0)
   {
      g_brkAge++;
      if (g_brkAge > InpRetestMaxBars)
      {
         Print("Retest timeout (", g_brkAge, " bars) — resetting zone state");
         ResetZoneState();
      }
   }

   // ---- 5. Skip entries if occupied or no zone ----
   if (HasOpenPosition()) return;
   if (!g_zValid)         return;

   // ---- 6. Price arrays — 3 bars (0 = forming, 1 = signal, 2 = prev) ----
   double cl[], op[], hi[], lo[];
   ArraySetAsSeries(cl, true); ArraySetAsSeries(op, true);
   ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true);
   if (CopyClose (_Symbol, PERIOD_CURRENT, 0, 3, cl) < 3) return;
   if (CopyOpen  (_Symbol, PERIOD_CURRENT, 0, 3, op) < 3) return;
   if (CopyHigh  (_Symbol, PERIOD_CURRENT, 0, 3, hi) < 3) return;
   if (CopyLow   (_Symbol, PERIOD_CURRENT, 0, 3, lo) < 3) return;

   // ---- 7. Entry scenarios — stops at first successful entry ----
   if (InpValidBreak  && EntryValidBreakout (cl, op, hi, lo, atv)) return;
   if (InpFalseBreak  && EntryFalseBreakout (cl, op, hi, lo, atv)) return;
   if (InpRetestBreak)   EntryRetestBreakout(cl, op, hi, lo, atv);
}

//+------------------------------------------------------------------+
//--- ZONE DETECTION
//---
//--- Scans bars[2] to bars[InpZonePeriod+1] — deliberately excludes
//--- bar[1] so bar[1] can serve as a clean signal/breakout bar
//--- without its wick polluting the zone's HH/LL.
//---
//--- Zone is valid when:
//---  (a) range (HH - LL) <= ATR * InpZoneATRMult  (tight consolidation)
//---  (b) at least InpMinZoneBars closed inside the range
//+------------------------------------------------------------------+
void DetectZone(double atv)
{
   double highest = -DBL_MAX;
   double lowest  =  DBL_MAX;
   int    barsIn  = 0;

   int startBar = 2;                     // exclude bar[1] (signal bar)
   int endBar   = InpZonePeriod + 1;     // look back N bars before bar[1]

   for (int i = startBar; i <= endBar; i++)
   {
      double h = iHigh (_Symbol, PERIOD_CURRENT, i);
      double l = iLow  (_Symbol, PERIOD_CURRENT, i);
      if (h > highest) highest = h;
      if (l < lowest)  lowest  = l;
   }

   if (highest <= -DBL_MAX || lowest >= DBL_MAX) { g_zValid = false; return; }

   double range = highest - lowest;
   double buf   = atv * 0.15;  // small buffer for "inside zone" count

   for (int i = startBar; i <= endBar; i++)
   {
      double c = iClose(_Symbol, PERIOD_CURRENT, i);
      if (c >= lowest - buf && c <= highest + buf) barsIn++;
   }

   bool sideways = (range <= atv * InpZoneATRMult) && (barsIn >= InpMinZoneBars);

   if (sideways)
   {
      g_zHigh  = highest;
      g_zLow   = lowest;
      g_zMid   = (highest + lowest) / 2.0;
      g_zValid = true;
   }
   else
   {
      g_zValid = false;
   }
}

void ResetZoneState()
{
   g_brkDir = 0;
   g_brkAge = 0;
   g_zValid = false;  // force fresh zone scan next bar
}

//+------------------------------------------------------------------+
//--- SCENARIO 1: VALID BREAKOUT
//---
//--- bar[1] closed convincingly beyond the zone boundary.
//--- Because the zone was built from bars[2..N+1] (excluding bar[1]),
//--- a close above g_zHigh is a genuine breakout of the prior range.
//---
//--- BUY  when: close[1] > g_zHigh + ATR * buffer
//--- SELL when: close[1] < g_zLow  - ATR * buffer
//---
//--- SL: far side of zone ± ATR mult
//--- TP: SL distance * RR ratio
//+------------------------------------------------------------------+
bool EntryValidBreakout(const double &cl[], const double &op[],
                         const double &hi[], const double &lo[], double atv)
{
   if (g_brkDir != 0) return false;   // only fresh zones, no active breakout

   double buf = atv * InpBreakBuf;

   // ---- BUY breakout ----
   if (cl[1] > g_zHigh + buf)
   {
      double sl  = g_zLow - atv * InpSLMult;
      double rng = cl[1] - sl;
      if (rng <= 0) return false;
      double tp  = cl[1] + rng * InpTPRR;
      double lot = CalcLot(rng);

      LogEntry("VALID BREAKOUT BUY", cl[1], sl, tp, lot);
      if (OpenBuy(lot, sl, tp))
      {
         g_brkDir = 1;
         g_brkAge = 0;
         DrawLabel("BK_L_" + IntegerToString(GetTickCount()),
                   iTime(_Symbol, PERIOD_CURRENT, 1), hi[1], "VB↑", clrLime);
         return true;
      }
   }

   // ---- SELL breakout ----
   if (cl[1] < g_zLow - buf)
   {
      double sl  = g_zHigh + atv * InpSLMult;
      double rng = sl - cl[1];
      if (rng <= 0) return false;
      double tp  = cl[1] - rng * InpTPRR;
      double lot = CalcLot(rng);

      LogEntry("VALID BREAKOUT SELL", cl[1], sl, tp, lot);
      if (OpenSell(lot, sl, tp))
      {
         g_brkDir = -1;
         g_brkAge = 0;
         DrawLabel("BK_L_" + IntegerToString(GetTickCount()),
                   iTime(_Symbol, PERIOD_CURRENT, 1), lo[1], "VB↓", clrRed);
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//--- SCENARIO 2: FALSE BREAKOUT (FADE)
//---
//--- bar[1] WICKED outside the zone but CLOSED back inside — the market
//--- tested the boundary and rejected it. Fade the failed move.
//---
//--- Because g_zHigh / g_zLow come from bars[2..N+1], bar[1]'s wick
//--- being above g_zHigh truly means it pierced outside the zone.
//---
//--- FALSE BULL SPIKE → SELL: hi[1] > g_zHigh + spike, cl[1] < g_zHigh
//--- FALSE BEAR SPIKE → BUY:  lo[1] < g_zLow  - spike, cl[1] > g_zLow
//---
//--- SL: beyond the wick extreme
//--- TP: SL distance * RR ratio
//+------------------------------------------------------------------+
bool EntryFalseBreakout(const double &cl[], const double &op[],
                         const double &hi[], const double &lo[], double atv)
{
   if (g_brkDir != 0) return false;   // only valid inside the zone

   double spk = atv * InpFalseSpkMult;

   // ---- False bull spike → SELL ----
   if (hi[1] > g_zHigh + spk && cl[1] < g_zHigh)
   {
      double sl  = hi[1] + atv * 0.3;   // SL above the fake spike wick
      double rng = sl - cl[1];
      if (rng <= 0) return false;
      double tp  = cl[1] - rng * InpTPRR;
      double lot = CalcLot(rng);

      LogEntry("FALSE BREAKOUT SELL (fade bull spike)", cl[1], sl, tp, lot);
      if (OpenSell(lot, sl, tp))
      {
         DrawLabel("BK_L_" + IntegerToString(GetTickCount()),
                   iTime(_Symbol, PERIOD_CURRENT, 1), hi[1], "FB↓", clrOrange);
         return true;
      }
   }

   // ---- False bear spike → BUY ----
   if (lo[1] < g_zLow - spk && cl[1] > g_zLow)
   {
      double sl  = lo[1] - atv * 0.3;   // SL below the fake spike wick
      double rng = cl[1] - sl;
      if (rng <= 0) return false;
      double tp  = cl[1] + rng * InpTPRR;
      double lot = CalcLot(rng);

      LogEntry("FALSE BREAKOUT BUY (fade bear spike)", cl[1], sl, tp, lot);
      if (OpenBuy(lot, sl, tp))
      {
         DrawLabel("BK_L_" + IntegerToString(GetTickCount()),
                   iTime(_Symbol, PERIOD_CURRENT, 1), lo[1], "FB↑", clrAqua);
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//--- SCENARIO 3: RETEST BREAKOUT
//---
//--- After a valid breakout (g_brkDir set), price pulls back to the
//--- broken zone boundary and shows a confirming candle → ride the
//--- continuation. Zone levels stay frozen (DetectZone skipped when
//--- g_brkDir != 0) so the retest levels are exactly the original zone.
//---
//--- After upward break:   bar[1] wick touches g_zHigh from above, bullish close → BUY
//--- After downward break: bar[1] wick touches g_zLow  from below, bearish close → SELL
//+------------------------------------------------------------------+
bool EntryRetestBreakout(const double &cl[], const double &op[],
                          const double &hi[], const double &lo[], double atv)
{
   if (g_brkDir == 0) return false;   // need an active breakout to retest

   double prox = atv * InpRetestMult;

   // ---- Retest BUY (upward breakout retests g_zHigh) ----
   if (g_brkDir == 1)
   {
      bool hit = (lo[1] <= g_zHigh + prox)     // wick dipped into zone high area
              && (cl[1] >= g_zHigh - prox)       // closed above or near zone high
              && (cl[1] > op[1]);                // bullish candle body

      if (hit)
      {
         double sl  = g_zLow - atv * InpSLMult;
         double rng = cl[1] - sl;
         if (rng <= 0) return false;
         double tp  = cl[1] + rng * InpTPRR;
         double lot = CalcLot(rng);

         LogEntry("RETEST BUY", cl[1], sl, tp, lot);
         if (OpenBuy(lot, sl, tp))
         {
            DrawLabel("BK_L_" + IntegerToString(GetTickCount()),
                      iTime(_Symbol, PERIOD_CURRENT, 1), lo[1], "RT↑", clrSpringGreen);
            g_brkDir = 0;
            g_brkAge = 0;
            return true;
         }
      }
   }

   // ---- Retest SELL (downward breakout retests g_zLow) ----
   if (g_brkDir == -1)
   {
      bool hit = (hi[1] >= g_zLow - prox)      // wick rose into zone low area
              && (cl[1] <= g_zLow + prox)        // closed below or near zone low
              && (cl[1] < op[1]);                // bearish candle body

      if (hit)
      {
         double sl  = g_zHigh + atv * InpSLMult;
         double rng = sl - cl[1];
         if (rng <= 0) return false;
         double tp  = cl[1] - rng * InpTPRR;
         double lot = CalcLot(rng);

         LogEntry("RETEST SELL", cl[1], sl, tp, lot);
         if (OpenSell(lot, sl, tp))
         {
            DrawLabel("BK_L_" + IntegerToString(GetTickCount()),
                      iTime(_Symbol, PERIOD_CURRENT, 1), hi[1], "RT↓", clrOrangeRed);
            g_brkDir = 0;
            g_brkAge = 0;
            return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//--- DYNAMIC LOT
//--- RiskAmount = Balance * RiskPct%
//--- Lot = RiskAmount / (SL ticks * tick value)
//+------------------------------------------------------------------+
double CalcLot(double slDist)
{
   if (slDist <= 0) return InpMinLot;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance * InpRiskPct / 100.0;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if (tickVal <= 0 || tickSz <= 0) return InpMinLot;

   double slTicks = slDist / tickSz;
   double lot     = riskAmt / (slTicks * tickVal);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (step > 0) lot = MathFloor(lot / step) * step;

   return NormalizeDouble(MathMax(InpMinLot, MathMin(InpMaxLot, lot)), 2);
}

//+------------------------------------------------------------------+
//--- VIRTUAL STOP / TP CHECK
//--- Tests prev bar's high/low against each virtual SL and TP.
//--- Closes position if either level is hit.
//--- After close: g_brkDir is kept so retest can still fire.
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   double prevHi = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prevLo = iLow (_Symbol, PERIOD_CURRENT, 1);

   for (int i = ArraySize(g_vords) - 1; i >= 0; i--)
   {
      if (!PositionSelectByTicket(g_vords[i].ticket))
      {
         ArrayRemove(g_vords, i, 1);
         continue;
      }

      long   pType   = PositionGetInteger(POSITION_TYPE);
      bool   doClose = false;
      string reason  = "";

      if (pType == POSITION_TYPE_BUY)
      {
         if (prevLo <= g_vords[i].sl) { doClose = true; reason = "vSL BUY"; }
         if (prevHi >= g_vords[i].tp) { doClose = true; reason = "vTP BUY"; }
      }
      else
      {
         if (prevHi >= g_vords[i].sl) { doClose = true; reason = "vSL SELL"; }
         if (prevLo <= g_vords[i].tp) { doClose = true; reason = "vTP SELL"; }
      }

      if (doClose)
      {
         Print(reason, " | ticket:", g_vords[i].ticket,
               " SL:", DoubleToString(g_vords[i].sl, _Digits),
               " TP:", DoubleToString(g_vords[i].tp, _Digits));

         if (ClosePosition(g_vords[i].ticket))
         {
            ArrayRemove(g_vords, i, 1);
            // Deliberately keep g_brkDir intact after close:
            // if a trade hit SL/TP, a retest entry may still be valid
            // within InpRetestMaxBars before timeout resets state.
         }
      }
   }
}

//+------------------------------------------------------------------+
//--- SAR TRAILING
//--- BUY:  SAR trails upward only (never lowers the stop)
//--- SELL: SAR trails downward only (never raises the stop)
//+------------------------------------------------------------------+
void UpdateTrailingSAR()
{
   double sar[];
   ArraySetAsSeries(sar, true);
   if (CopyBuffer(g_sarHandle, 0, 0, 3, sar) < 3) return;
   double sarVal = sar[1];

   for (int i = 0; i < ArraySize(g_vords); i++)
   {
      if (!PositionSelectByTicket(g_vords[i].ticket)) continue;
      long pType = PositionGetInteger(POSITION_TYPE);

      if (pType == POSITION_TYPE_BUY)
      {
         if (sarVal > g_vords[i].sl)
            g_vords[i].sl = NormalizeDouble(sarVal, _Digits);
      }
      else
      {
         if (sarVal < g_vords[i].sl)
            g_vords[i].sl = NormalizeDouble(sarVal, _Digits);
      }
   }
}

//+------------------------------------------------------------------+
//--- OPEN BUY / SELL (no broker SL/TP — all virtual)
//+------------------------------------------------------------------+
bool OpenBuy(double lot, double sl, double tp)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.type      = ORDER_TYPE_BUY;
   req.volume    = lot;
   req.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.sl        = 0;
   req.tp        = 0;
   req.deviation = InpSlippage;
   req.magic     = InpMagic;

   if (!OrderSend(req, res))
   { Print("OpenBuy error:", GetLastError(), " retcode:", res.retcode); return false; }

   if (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
   { AddVirtualOrder(res.order, sl, tp); return true; }

   Print("OpenBuy failed retcode:", res.retcode);
   return false;
}

bool OpenSell(double lot, double sl, double tp)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.type      = ORDER_TYPE_SELL;
   req.volume    = lot;
   req.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl        = 0;
   req.tp        = 0;
   req.deviation = InpSlippage;
   req.magic     = InpMagic;

   if (!OrderSend(req, res))
   { Print("OpenSell error:", GetLastError(), " retcode:", res.retcode); return false; }

   if (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
   { AddVirtualOrder(res.order, sl, tp); return true; }

   Print("OpenSell failed retcode:", res.retcode);
   return false;
}

void AddVirtualOrder(ulong ticket, double sl, double tp)
{
   int sz = ArraySize(g_vords);
   ArrayResize(g_vords, sz + 1);
   g_vords[sz].ticket = ticket;
   g_vords[sz].sl     = NormalizeDouble(sl, _Digits);
   g_vords[sz].tp     = NormalizeDouble(tp, _Digits);
   Print("vOrder | ticket:", ticket,
         " SL:", DoubleToString(sl, _Digits),
         " TP:", DoubleToString(tp, _Digits));
}

bool ClosePosition(ulong ticket)
{
   if (!PositionSelectByTicket(ticket)) return false;
   long pType = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.position  = ticket;
   req.symbol    = _Symbol;
   req.volume    = PositionGetDouble(POSITION_VOLUME);
   req.deviation = InpSlippage;
   req.magic     = InpMagic;

   if (pType == POSITION_TYPE_BUY)
   { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
   else
   { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

   if (!OrderSend(req, res)) return false;
   return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL);
}

bool HasOpenPosition()
{
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == (long)InpMagic)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//--- DRAWING
//+------------------------------------------------------------------+
void DrawZone()
{
   DrawHLine("BK_HIGH", g_zHigh, InpClrHigh, STYLE_SOLID, 2);
   DrawHLine("BK_LOW",  g_zLow,  InpClrLow,  STYLE_SOLID, 2);
   DrawHLine("BK_MID",  g_zMid,  InpClrMid,  STYLE_DOT,   1);

   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, InpZonePeriod + 1);
   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 0) + (long)PeriodSeconds(PERIOD_CURRENT) * 10;

   string rn = "BK_RECT";
   if (ObjectFind(0, rn) < 0)
      ObjectCreate(0, rn, OBJ_RECTANGLE, 0, t0, g_zHigh, t1, g_zLow);

   ObjectSetInteger(0, rn, OBJPROP_TIME,  0, t0);
   ObjectSetDouble (0, rn, OBJPROP_PRICE, 0, g_zHigh);
   ObjectSetInteger(0, rn, OBJPROP_TIME,  1, t1);
   ObjectSetDouble (0, rn, OBJPROP_PRICE, 1, g_zLow);
   ObjectSetInteger(0, rn, OBJPROP_COLOR, InpClrRect);
   ObjectSetInteger(0, rn, OBJPROP_FILL,  true);
   ObjectSetInteger(0, rn, OBJPROP_BACK,  true);
   ObjectSetInteger(0, rn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rn, OBJPROP_HIDDEN, true);
}

void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width)
{
   if (ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble (0, name, OBJPROP_PRICE,      price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void DrawLabel(string name, datetime t, double price, string txt, color clr)
{
   if (ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString (0, name, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void LogEntry(string tag, double price, double sl, double tp, double lot)
{
   Print(">>> ", tag,
         " | Entry:", DoubleToString(price, _Digits),
         " SL:", DoubleToString(sl, _Digits),
         " TP:", DoubleToString(tp, _Digits),
         " Lot:", DoubleToString(lot, 2),
         " Zone:", DoubleToString(g_zLow, _Digits),
         "-", DoubleToString(g_zHigh, _Digits));
}
//+------------------------------------------------------------------+
//  END
//+------------------------------------------------------------------+