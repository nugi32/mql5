//+------------------------------------------------------------------+
//|              EMA Crossover EA - Virtual Stop Loss               |
//+------------------------------------------------------------------+
#property strict

input double LotSize           = 0.01;
input int    Slippage          = 10;
input int    FastEMA           = 10;

input int    SidewaysPeriod    = 20;
input double SidewaysThreshold = 0.30;
                                        
input double SarStep = 0.02;
input double SarMax  = 0.2;

input int atrPeriod           = 14;
input double atrMultiplier     = 1.0;
input ulong  MagicNumber       = 123456;

//--- indicator handles
int fastHandle, sidewaysHandle, atrHandle, sarHandle;

//--- virtual stop
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
   sidewaysHandle = iMA(_Symbol, PERIOD_CURRENT, SidewaysPeriod, 0, MODE_EMA, PRICE_CLOSE); // ← uncommented
   atrHandle      = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle      = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);

   if(fastHandle     == INVALID_HANDLE ||
      sidewaysHandle == INVALID_HANDLE ||  // ← now actually valid
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
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar())
      return;

   CheckVirtualStops();

   double fast[], atr[], close[], open[], high[], low[];
   ArraySetAsSeries(fast,  true);
   ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast)           < 3) return;
   if(CopyBuffer(atrHandle,  0, 0, 3, atr)            < 3) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3) return;
   if(CopyOpen (_Symbol, PERIOD_CURRENT, 0, 3, open)  < 3) return;
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, 3, high)  < 3) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, 3, low)   < 3) return;

   double currentPrice = close[0];
   double m = atr[1] * 0.15;

   bool buyS1 = close[2] < fast[2]     && close[1] > fast[1] + m;
   bool buyS2 = open[1]  < fast[1] - m && close[1] > fast[1] + m;
   bool buyS3 = high[2]  < fast[2]     && close[1] > fast[1] + m;
   bool buySignal = buyS1 || buyS2 || buyS3;

   bool sellS1 = close[2] > fast[2]     && close[1] < fast[1] - m;
   bool sellS2 = open[1]  > fast[1] + m && close[1] < fast[1] - m;
   bool sellS3 = low[2]   > fast[2]     && close[1] < fast[1] - m;
   bool sellSignal = sellS1 || sellS2 || sellS3;

   UpdateTrailingVirtualSL();

   if(HasOpenPosition())
      return;

   // ← sideways filter only blocks new entries, not trailing/stops
   if(IsSideways())
      return;

   if(buySignal)  OpenBuy (currentPrice - atr[1] * atrMultiplier);
   if(sellSignal) OpenSell(currentPrice + atr[1] * atrMultiplier);
}
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prevLow  = iLow(_Symbol, PERIOD_CURRENT, 1);

   for(int i = ArraySize(vsl)-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vsl[i].ticket))
      {
         ArrayRemove(vsl, i, 1);
         continue;
      }

      long type = PositionGetInteger(POSITION_TYPE);
      bool closeNow = false;

      if(type == POSITION_TYPE_BUY)
      {
         if(prevLow <= vsl[i].sl)
            closeNow = true;
      }
      else
      {
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
/*
bool IsSideways()
{
    double sideways[];
    ArraySetAsSeries(sideways, true);
    if(CopyBuffer(sidewaysHandle, 0, 0, SidewaysPeriod + 1, sideways) < SidewaysPeriod + 1)
       return false;

       double slope = (sideways[0] - sideways[SidewaysPeriod]);
       /*

   double highest = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double lowest  = iLow(_Symbol, PERIOD_CURRENT, 1);

   for(int i=2; i<=SidewaysPeriod; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);

      if(h > highest) highest = h;
      if(l < lowest)  lowest  = l;
   }

   double rangePoints = (highest - lowest) / _Point;

   return (slope <= (SidewaysThreshold * _Point));
}*/
/*
bool isSideways()
{
   double sideways[], fast[];

   ArraySetAsSeries(sideways, true);
   ArraySetAsSeries(fast, true);

   if(CopyBuffer(sidewaysHandle, 0, 0, 2, sideways) <= 0)
      return false;

   if(CopyBuffer(fastHandle, 0, 0, 2, fast) <= 0)
      return false;

   double sideway_diff = MathAbs(sideways[0] - sideways[1]);
   double buffer_price = SidewaysThreshold * _Point;

   return (sideway_diff >= buffer_price);
}*/
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

   if(CopyBuffer(sidewaysHandle, 0, 0, SidewaysPeriod + 1, slow) < SidewaysPeriod + 1)
      return false;  // fail safe: don't block trades on data error

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) < 2)
      return false;

   // Total MA displacement over the lookback period
   double totalSlope    = MathAbs(slow[0] - slow[SidewaysPeriod]);

   // ATR × period = expected range if market trended 1 ATR per bar
   double atrBenchmark  = atr[1] * SidewaysPeriod;

   if(atrBenchmark <= 0)
      return false;

   // Ratio: 0 = completely flat, 1.0+ = strong trend
   double slopeRatio = totalSlope / atrBenchmark;

   return (slopeRatio < SidewaysThreshold);  // true = sideways, skip entry
}
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
            return true;
      }
   }

   return false;
}
//+------------------------------------------------------------------+
void ManageReverseSignal(bool buySignal, bool sellSignal)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY && sellSignal)
         CloseAndRemove(ticket);

      if(type == POSITION_TYPE_SELL && buySignal)
         CloseAndRemove(ticket);
   }
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
      for(int i = ArraySize(vsl)-1; i >= 0; i--)
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
void UpdateTrailingVirtualSL()
{
   double sar[];
   ArraySetAsSeries(sar, true);

   if(CopyBuffer(sarHandle, 0, 0, 3, sar) < 3)
      return;

   double sarValue = sar[1];

   for(int i = 0; i < ArraySize(vsl); i++)
   {
      ulong ticket = vsl[i].ticket;

      if(!PositionSelectByTicket(ticket))
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      // BUY POSITION
      if(type == POSITION_TYPE_BUY)
      {
         // trailing hanya naik
         if(sarValue > vsl[i].sl)
         {
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);
         }
      }

      // SELL POSITION
      else if(type == POSITION_TYPE_SELL)
      {
         // trailing hanya turun
         if(sarValue < vsl[i].sl)
         {
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);
         }
      }
   }
}