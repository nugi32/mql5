//+------------------------------------------------------------------+
//|              EMA Crossover EA - Virtual Stop Loss               |
//+------------------------------------------------------------------+
#property strict

input double LotSize       = 0.01;
input int    Slippage      = 10;

input int    FastEMA       = 10;

input int    SlowEMA       = 34;  
input int sidewaysPeriod       = 21;  
input bool useATRtreshold = true;
input double sidewaysATRtresholdMultiplier   = 1.0;
input double sidewaysFixedTreshold = 30.0;
input double layerSlopeThreshold = 0.05;
input double CrossMargin   = 0.15;


input int layerPeriod       = 20;     
input ENUM_TIMEFRAMES layerTimeframe = PERIOD_CURRENT;
input double layerSLopeTreshold = 0.10;

input double layerSlopeBuffer   = 0.10;  
input int layerSlopePeriod       = 5;    

input double SarStep       = 0.02;
input double SarMax        = 0.2;

input int    atrPeriod     = 14;
input double atrMultiplier = 1.0;
input ulong  MagicNumber   = 123456;

//--- handles
int fastHandle, slowHandle, atrHandle, sarHandle, layerHandle;

//--- virtual SL
struct VirtualSL { ulong ticket; double sl; };
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle  = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle  = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);
   layerHandle = iMA(_Symbol, layerTimeframe, layerPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE ||
      slowHandle == INVALID_HANDLE ||
      atrHandle  == INVALID_HANDLE ||
      sarHandle  == INVALID_HANDLE ||
      layerHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(sarHandle);
   IndicatorRelease(layerHandle);
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar != lastBar) { lastBar = currentBar; return true; }
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar())
      return;

   // 1. virtual SL check
   CheckVirtualStops();

   // 2. copy buffers
   double fast[], slow[], atr[], close[], open[], high[], low[];

   ArraySetAsSeries(fast,  true);
   ArraySetAsSeries(slow,  true);
   ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast)           < 3) return;
   if(CopyBuffer(slowHandle, 0, 0, 3, slow)           < 3) return;
   if(CopyBuffer(atrHandle,  0, 0, 3, atr)            < 3) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3) return;
   if(CopyOpen (_Symbol, PERIOD_CURRENT, 0, 3, open)  < 3) return;
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, 3, high)  < 3) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, 3, low)   < 3) return;

   double currentPrice = close[0];
   double m = atr[1] * CrossMargin;

   // 3. fast EMA cross signal (S1 only — most stable, no OR)
   bool buySignal  = close[2] < fast[2] && close[1] > fast[1] + m;
   bool sellSignal = close[2] > fast[2] && close[1] < fast[1] - m;

   // 4. slow EMA trend filter — replaces isSideways()
   //    buys only when price above slow EMA (uptrend)
   //    sells only when price below slow EMA (downtrend)
   //    in sideways markets price oscillates around slow EMA → most signals blocked naturally
   buySignal  = buySignal  && (close[1] > slow[1]);
   sellSignal = sellSignal && (close[1] < slow[1]);

   // 5. trailing SL update
   UpdateTrailingVirtualSL();

   if(IsSideways())
      return;

   // 6. one position at a time
   if(HasOpenPosition())
      return;

   // 7. entry
   if(buySignal && IsLayerBullish())  OpenBuy (currentPrice - atr[1] * atrMultiplier);
   if(sellSignal && IsLayerBearish()) OpenSell(currentPrice + atr[1] * atrMultiplier);
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// IsSideways: true when the slow MA slope is too flat relative to ATR.
// Measures total MA movement over SidewaysPeriod bars, divided by
// (ATR × period) — giving a 0..1+ ratio of "trend strength per bar".
// Below threshold = choppy/flat. Above = directional enough to trade.
//+------------------------------------------------------------------+
bool IsSideways()
{
   double slow[], atr[];
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(atr,  true);

   if(CopyBuffer(slowHandle, 0, 0, sidewaysPeriod + 1, slow) < sidewaysPeriod + 1)
      return false;  // fail safe: don't block trades on data error

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) < 2)
      return false;

   // Total MA displacement over the lookback period
   double totalSlope    = MathAbs(slow[0] - slow[sidewaysPeriod]);

   // ATR × period = expected range if market trended 1 ATR per bar
   double atrBenchmark  = atr[1] * sidewaysATRtresholdMultiplier;

   if(atrBenchmark <= 0)
      return false;

   // Ratio: 0 = completely flat, 1.0+ = strong trend
   //double slopeRatio = totalSlope / atrBenchmark;

   if(useATRtreshold)
      return (totalSlope < atrBenchmark);  // true = sideways, skip entry
   else
      return (totalSlope < sidewaysFixedTreshold);  // true = sideways, skip entry

   //return (slopeRatio < SidewaysThreshold);  // true = sideways, skip entry
}
bool IsLayerBullish()
{
    double layer[], atr[], close[];
    
    ArraySetAsSeries(layer, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);

    if(CopyBuffer(layerHandle, 0, 0, 3, layer) < 3)
        return false;

    if(CopyBuffer(atrHandle, 0, 0, 3, atr) < 3)
        return false;

    // Use Close prices directly instead of closeHandle
    if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3)
        return false;

    bool isAbove = close[1] > layer[1];

    double slope = (layer[0] - layer[1]) / layer[1] * 100.0;

    return isAbove && slope > layerSlopeThreshold;
}


bool IsLayerBearish()
{
    double layer[], atr[], close[];

    ArraySetAsSeries(layer, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);

    if(CopyBuffer(layerHandle, 0, 0, 3, layer) < 3)
        return false;

    if(CopyBuffer(atrHandle, 0, 0, 3, atr) < 3)
        return false;

    // Use Close prices directly instead of closeHandle
    if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3)
        return false;

    bool isBelow = close[1] < layer[1];

    double slope = (layer[1] - layer[0]) / layer[1] * 100.0;

    return isBelow && slope > layerSlopeThreshold;
}
//+------------------------------------------------------------------+
//   ALL FUNCTIONS BELOW UNCHANGED
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prevLow  = iLow (_Symbol, PERIOD_CURRENT, 1);

   for(int i = ArraySize(vsl)-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vsl[i].ticket))
         { ArrayRemove(vsl, i, 1); continue; }

      long type = PositionGetInteger(POSITION_TYPE);
      bool closeNow = false;

      if(type == POSITION_TYPE_BUY)  closeNow = (prevLow  <= vsl[i].sl);
      else                           closeNow = (prevHigh >= vsl[i].sl);

      if(closeNow && ClosePosition(vsl[i].ticket))
         ArrayRemove(vsl, i, 1);
   }
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
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.type      = ORDER_TYPE_BUY;
   req.volume    = LotSize;
   req.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.sl        = 0; req.tp = 0;
   req.deviation = Slippage;
   req.magic     = MagicNumber;

   if(!OrderSend(req, res)) return false;

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
      { AddVirtualSL(res.order, slPrice); return true; }
   return false;
}

//+------------------------------------------------------------------+
bool OpenSell(double slPrice)
{
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.type      = ORDER_TYPE_SELL;
   req.volume    = LotSize;
   req.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl        = 0; req.tp = 0;
   req.deviation = Slippage;
   req.magic     = MagicNumber;

   if(!OrderSend(req, res)) return false;

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
      { AddVirtualSL(res.order, slPrice); return true; }
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
      for(int i = ArraySize(vsl)-1; i >= 0; i--)
         if(vsl[i].ticket == ticket) { ArrayRemove(vsl, i, 1); break; }
}

//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;

   long type = PositionGetInteger(POSITION_TYPE);
   MqlTradeRequest req = {}; MqlTradeResult res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.position  = ticket;
   req.symbol    = _Symbol;
   req.volume    = PositionGetDouble(POSITION_VOLUME);
   req.deviation = Slippage;
   req.magic     = MagicNumber;

   if(type == POSITION_TYPE_BUY)
      { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
   else
      { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

   if(!OrderSend(req, res)) return false;
   return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL);
}

//+------------------------------------------------------------------+
void UpdateTrailingVirtualSL()
{
   double sar[];
   ArraySetAsSeries(sar, true);
   if(CopyBuffer(sarHandle, 0, 0, 3, sar) < 3) return;
   double sarValue = sar[1];

   for(int i = 0; i < ArraySize(vsl); i++)
   {
      ulong ticket = vsl[i].ticket;
      if(!PositionSelectByTicket(ticket)) continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY  && sarValue > vsl[i].sl)
         vsl[i].sl = NormalizeDouble(sarValue, _Digits);

      if(type == POSITION_TYPE_SELL && sarValue < vsl[i].sl)
         vsl[i].sl = NormalizeDouble(sarValue, _Digits);
   }
}