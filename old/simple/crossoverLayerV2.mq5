//+------------------------------------------------------------------+
//|              EMA Cross + Layer Slope EA                         |
//+------------------------------------------------------------------+
#property strict

input double LotSize         = 0.01;
input int    Slippage        = 10;

// --- Cross signal
input int    FastEMA         = 10;
input double CrossMargin     = 0.15;   // ATR fraction for cross buffer

// --- Layer (trend quality filter)
input int               layerPeriod        = 20;
input ENUM_TIMEFRAMES   layerTimeframe     = PERIOD_CURRENT;
input int               layerSlopePeriod   = 5;     // bars to measure slope over (was declared, never used)
input double            layerSlopeThreshold = 0.05; // min % slope to consider trending
input double            layerSlopeBuffer   = 0.10;  // ATR fraction buffer above/below layer (was declared, never used)

// --- Exit
input double SarStep         = 0.02;
input double SarMax          = 0.2;
input int    atrPeriod       = 14;
input double atrMultiplier   = 1.0;

input ulong  MagicNumber     = 123456;

//--- handles
int fastHandle, atrHandle, sarHandle, layerHandle;

//--- virtual SL
struct VirtualSL { ulong ticket; double sl; };
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle  = iMA(_Symbol, PERIOD_CURRENT, FastEMA,     0, MODE_EMA, PRICE_CLOSE);
   layerHandle = iMA(_Symbol, layerTimeframe, layerPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle   = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle   = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);

   if(fastHandle  == INVALID_HANDLE || layerHandle == INVALID_HANDLE ||
      atrHandle   == INVALID_HANDLE || sarHandle   == INVALID_HANDLE)
      return INIT_FAILED;

   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(layerHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(sarHandle);
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   // 1. virtual SL check first
   CheckVirtualStops();

   // 2. copy buffers
   double fast[], atr[], close[], high[], low[];

   ArraySetAsSeries(fast,  true); ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true); ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast)           < 3) return;
   if(CopyBuffer(atrHandle,  0, 0, 3, atr)            < 3) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3) return;
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, 3, high)  < 3) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, 3, low)   < 3) return;

   double currentPrice = close[0];
   double m = atr[1] * CrossMargin;

   // 3. cross signal
   bool buySignal  = close[2] < fast[2] && close[1] > fast[1] + m;
   bool sellSignal = close[2] > fast[2] && close[1] < fast[1] - m;

   // 4. trailing SL
   UpdateTrailingVirtualSL();

   if(HasOpenPosition()) return;

   // 5. layer is the ONLY filter — handles both trend AND sideways detection
   //    no IsSideways(), no slow EMA check — layer slope does it all
   if(buySignal  && IsLayerBullish()) OpenBuy (currentPrice - atr[1] * atrMultiplier);
   if(sellSignal && IsLayerBearish()) OpenSell(currentPrice + atr[1] * atrMultiplier);
}

//+------------------------------------------------------------------+
// Layer slope quality — the core edge
// Checks: (1) price clearly above/below layer by ATR buffer
//         (2) layer slope over layerSlopePeriod bars exceeds threshold
// This replaces both IsSideways() and slow EMA trend filter
//+------------------------------------------------------------------+
bool IsLayerBullish()
{
   int bars = layerSlopePeriod + 2;
   double layer[], atr[], close[];

   ArraySetAsSeries(layer, true);
   ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(layerHandle, 0, 0, bars, layer) < bars) return false;
   if(CopyBuffer(atrHandle,   0, 0, 2,    atr)   < 2)    return false;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 2, close) < 2) return false;

   // Price must be clearly above layer — ATR buffer prevents noise entries
   bool priceAbove = close[1] > layer[1] + atr[1] * layerSlopeBuffer;

   // Slope over layerSlopePeriod bars (% normalized, stable vs 1-bar noise)
   // layer[0] = most recent, layer[layerSlopePeriod] = N bars ago
   double slope = (layer[0] - layer[layerSlopePeriod]) / layer[layerSlopePeriod] * 100.0;

   return priceAbove && slope > layerSlopeThreshold;
}

//+------------------------------------------------------------------+
bool IsLayerBearish()
{
   int bars = layerSlopePeriod + 2;
   double layer[], atr[], close[];

   ArraySetAsSeries(layer, true);
   ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(layerHandle, 0, 0, bars, layer) < bars) return false;
   if(CopyBuffer(atrHandle,   0, 0, 2,    atr)   < 2)    return false;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 2, close) < 2) return false;

   // Price must be clearly below layer
   bool priceBelow = close[1] < layer[1] - atr[1] * layerSlopeBuffer;

   // Slope: for bearish we want layer going DOWN (old value > new value)
   double slope = (layer[layerSlopePeriod] - layer[0]) / layer[layerSlopePeriod] * 100.0;

   return priceBelow && slope > layerSlopeThreshold;
}

//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prevLow  = iLow (_Symbol, PERIOD_CURRENT, 1);

   for(int i = ArraySize(vsl)-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vsl[i].ticket))
         { ArrayRemove(vsl, i, 1); continue; }

      long type    = PositionGetInteger(POSITION_TYPE);
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
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool OpenBuy(double slPrice)
{
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL; req.symbol    = _Symbol;
   req.type   = ORDER_TYPE_BUY;   req.volume    = LotSize;
   req.price  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.sl = 0; req.tp = 0; req.deviation = Slippage; req.magic = MagicNumber;
   if(!OrderSend(req, res)) return false;
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
      { AddVirtualSL(res.order, slPrice); return true; }
   return false;
}

//+------------------------------------------------------------------+
bool OpenSell(double slPrice)
{
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL; req.symbol    = _Symbol;
   req.type   = ORDER_TYPE_SELL;  req.volume    = LotSize;
   req.price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl = 0; req.tp = 0; req.deviation = Slippage; req.magic = MagicNumber;
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
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   long type = PositionGetInteger(POSITION_TYPE);
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action   = TRADE_ACTION_DEAL; req.position = ticket;
   req.symbol   = _Symbol; req.volume   = PositionGetDouble(POSITION_VOLUME);
   req.deviation = Slippage; req.magic  = MagicNumber;
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
      if(!PositionSelectByTicket(vsl[i].ticket)) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY  && sarValue > vsl[i].sl)
         vsl[i].sl = NormalizeDouble(sarValue, _Digits);
      if(type == POSITION_TYPE_SELL && sarValue < vsl[i].sl)
         vsl[i].sl = NormalizeDouble(sarValue, _Digits);
   }
}