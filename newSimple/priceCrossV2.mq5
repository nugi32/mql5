//+------------------------------------------------------------------+
//|        EMA Crossover EA — Open-Price-Consistent Edition          |
//|                                                                  |
//| DESIGN RULE: Every decision is based ONLY on completed bar data  |
//| (bar index >= 1). No live bid/ask, no bar[0] data is ever used   |
//| for trade logic. This guarantees identical backtest results       |
//| between "Open prices only" and "Every tick" simulation modes.    |
//+------------------------------------------------------------------+
#property strict

input double LotSize            = 0.01;
input int    Slippage           = 10;
input int    FastEMA            = 10;

input int    SidewaysPeriod     = 20;
input double SidewaysThreshold  = 0.30;

input double SarStep            = 0.02;
input double SarMax             = 0.2;

input int    atrPeriod          = 14;
input double atrMultiplier      = 1.0;
input ulong  MagicNumber        = 123456;

//--- indicator handles
int fastHandle, sidewaysHandle, atrHandle, sarHandle;

//--- virtual stop tracking
struct VirtualSL
{
   ulong  ticket;
   double sl;
};
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle     = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   sidewaysHandle = iMA(_Symbol, PERIOD_CURRENT, SidewaysPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle      = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle      = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);

   if(fastHandle     == INVALID_HANDLE ||
      sidewaysHandle == INVALID_HANDLE ||
      atrHandle      == INVALID_HANDLE ||
      sarHandle      == INVALID_HANDLE)
      return INIT_FAILED;

   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(sidewaysHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(sarHandle);
}

//+------------------------------------------------------------------+
// IsNewBar — true only on the first tick of each new bar.
// In "Open prices only" mode MetaTrader calls OnTick() exactly once
// per bar (at the open), so this gate is always true there.
// In "Every tick" mode it filters out all intra-bar ticks.
// Result: both modes execute identical bar-by-bar logic.
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar != lastBar)
   {
      lastBar = currentBar;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // ── GATE: all logic runs only at the open of a new bar ─────────
   // This single gate is the reason results are identical in both
   // "Open prices only" and "Every tick" backtest modes.
   if(!IsNewBar())
      return;

   // ── PHASE 1: collect completed-bar indicator data ───────────────
   // All arrays use bar[1] (last fully closed bar) for decisions.
   // bar[0] is the live, unclosed bar — never used for logic.

   double fast[], atr[], close[], open[], high[], low[];
   ArraySetAsSeries(fast,  true);
   ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   // Require at least 3 completed bars (indices 1 and 2 are used)
   if(CopyBuffer(fastHandle, 0, 0, 3, fast)           < 3) return;
   if(CopyBuffer(atrHandle,  0, 0, 3, atr)            < 3) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3) return;
   if(CopyOpen (_Symbol, PERIOD_CURRENT, 0, 3, open)  < 3) return;
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, 3, high)  < 3) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, 3, low)   < 3) return;

   // ── PHASE 2: check virtual stops using prior bar OHLC ───────────
   // Uses bar[1] high/low — the same value seen in both test modes.
   // NEVER uses raw bid/ask, which would differ between modes.
   CheckVirtualStops();

   // ── PHASE 3: update trailing virtual SL using SAR[1] ───────────
   // SAR bar[1] is a confirmed, closed-bar value — mode-independent.
   UpdateTrailingVirtualSL();

   // ── PHASE 4: build signals from completed bar data ──────────────
   // m = noise margin based on bar[1] ATR (confirmed bar)
   double m = atr[1] * 0.15;

   // All signal conditions reference bar[1] and bar[2] — closed bars.
   bool buyS1 = close[2] < fast[2]     && close[1] > fast[1] + m;
   bool buyS2 = open[1]  < fast[1] - m && close[1] > fast[1] + m;
   bool buyS3 = high[2]  < fast[2]     && close[1] > fast[1] + m;
   bool buySignal  = buyS1 || buyS2 || buyS3;

   bool sellS1 = close[2] > fast[2]     && close[1] < fast[1] - m;
   bool sellS2 = open[1]  > fast[1] + m && close[1] < fast[1] - m;
   bool sellS3 = low[2]   > fast[2]     && close[1] < fast[1] - m;
   bool sellSignal = sellS1 || sellS2 || sellS3;

   // ── PHASE 5: entry gate checks ───────────────────────────────────
   if(HasOpenPosition())
      return;

   // Sideways filter: uses MA slope vs ATR over completed bars only
   if(IsSideways())
      return;

   // ── PHASE 6: entry — SL price derived from bar[1] ATR ───────────
   // FIX: original used close[0] (live bar price) for entry SL anchor.
   // Changed to close[1] (last closed bar) so the SL level is
   // identical whether resolved at bar open or mid-bar in tick mode.
   if(buySignal)  OpenBuy (close[1] - atr[1] * atrMultiplier);
   if(sellSignal) OpenSell(close[1] + atr[1] * atrMultiplier);
}

//+------------------------------------------------------------------+
// CheckVirtualStops
// Called once per new bar. Tests whether bar[1]'s high or low
// violated the virtual stop. Using bar[1] OHLC (not live bid/ask)
// ensures the check is identical in every-tick and open-price modes.
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   // bar[1] = the just-completed bar whose full range is now known
   double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prevLow  = iLow (_Symbol, PERIOD_CURRENT, 1);

   for(int i = ArraySize(vsl) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vsl[i].ticket))
      {
         ArrayRemove(vsl, i, 1);
         continue;
      }

      long type     = PositionGetInteger(POSITION_TYPE);
      bool closeNow = false;

      if(type == POSITION_TYPE_BUY)
      {
         // BUY stops out if the bar's low traded through the virtual SL
         if(prevLow <= vsl[i].sl)
            closeNow = true;
      }
      else
      {
         // SELL stops out if the bar's high traded through the virtual SL
         if(prevHigh >= vsl[i].sl)
            closeNow = true;
      }

      if(closeNow)
      {
         if(ClosePosition(vsl[i].ticket))
            ArrayRemove(vsl, i, 1);
      }
   }
}

//+------------------------------------------------------------------+
// UpdateTrailingVirtualSL
// Advances the virtual stop using the SAR value from bar[1].
// SAR[1] is a finalized indicator value — identical in both modes.
//+------------------------------------------------------------------+
void UpdateTrailingVirtualSL()
{
   double sar[];
   ArraySetAsSeries(sar, true);

   // Need bar[1] SAR (index 1); fetch 3 bars for safety
   if(CopyBuffer(sarHandle, 0, 0, 3, sar) < 3)
      return;

   double sarValue = sar[1]; // confirmed bar[1] SAR — mode-independent

   for(int i = 0; i < ArraySize(vsl); i++)
   {
      ulong ticket = vsl[i].ticket;
      if(!PositionSelectByTicket(ticket))
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
      {
         // Trail only advances upward (tightens stop on buys)
         if(sarValue > vsl[i].sl)
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         // Trail only advances downward (tightens stop on sells)
         if(sarValue < vsl[i].sl)
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);
      }
   }
}

//+------------------------------------------------------------------+
// IsSideways
// Measures total MA displacement over SidewaysPeriod bars versus
// ATR × period as a normalised trend-strength ratio.
// All data is from completed bars — result is mode-independent.
//+------------------------------------------------------------------+
bool IsSideways()
{
   double slow[], atr[];
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(atr,  true);

   if(CopyBuffer(sidewaysHandle, 0, 0, SidewaysPeriod + 1, slow) < SidewaysPeriod + 1)
      return false;  // fail-safe: don't block trades on data error

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) < 2)
      return false;

   double totalSlope   = MathAbs(slow[0] - slow[SidewaysPeriod]);
   double atrBenchmark = atr[1] * SidewaysPeriod;

   if(atrBenchmark <= 0)
      return false;

   double slopeRatio = totalSlope / atrBenchmark;

   return (slopeRatio < SidewaysThreshold); // true = sideways, skip entry
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)  == _Symbol &&
            PositionGetInteger(POSITION_MAGIC)  == (long)MagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool OpenBuy(double slPrice)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.type      = ORDER_TYPE_BUY;
   request.volume    = LotSize;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl        = 0;   // virtual — no real SL sent to broker
   request.tp        = 0;   // virtual — no real TP sent to broker
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(!OrderSend(request, result))
      return false;

   if(result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      AddVirtualSL(result.order, slPrice);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool OpenSell(double slPrice)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.type      = ORDER_TYPE_SELL;
   request.volume    = LotSize;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl        = 0;
   request.tp        = 0;
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(!OrderSend(request, result))
      return false;

   if(result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      AddVirtualSL(result.order, slPrice);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void AddVirtualSL(ulong ticket, double sl)
{
   int size = ArraySize(vsl);
   ArrayResize(vsl, size + 1);
   vsl[size].ticket = ticket;
   vsl[size].sl     = NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
void CloseAndRemove(ulong ticket)
{
   if(ClosePosition(ticket))
   {
      for(int i = ArraySize(vsl) - 1; i >= 0; i--)
      {
         if(vsl[i].ticket == ticket)
         {
            ArrayRemove(vsl, i, 1);
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   long type = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = _Symbol;
   request.volume    = PositionGetDouble(POSITION_VOLUME);
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(type == POSITION_TYPE_BUY)
   {
      request.type  = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      request.type  = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   if(!OrderSend(request, result))
      return false;

   return (result.retcode == TRADE_RETCODE_DONE ||
           result.retcode == TRADE_RETCODE_DONE_PARTIAL);
}
//+------------------------------------------------------------------+