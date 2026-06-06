//+------------------------------------------------------------------+
//|              EMA Crossover EA - Virtual Stop Loss               |
//+------------------------------------------------------------------+
#property strict

input double LotSize           = 0.10;
input int    Slippage          = 10;
input int    FastEMA           = 9;
input int    SlowEMA           = 21;
input int    SidewaysPeriod    = 20;
input double SidewaysThreshold = 120;   // points
input ulong  MagicNumber       = 123456;

//--- indicator handles
int fastHandle;
int slowHandle;

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
   fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ArrayResize(vsl,0);
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
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
void OnTick()
{
   if(!IsNewBar())
      return;

   // 1. manual virtual SL
   CheckVirtualStops();

   // 2. signal calculation
   double fast[3], slow[3];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast) <= 0) return;
   if(CopyBuffer(slowHandle, 0, 0, 3, slow) <= 0) return;

   bool buySignal  = (fast[2] < slow[2] && fast[1] > slow[1]);
   bool sellSignal = (fast[2] > slow[2] && fast[1] < slow[1]);

   // 3. reverse exit
   ManageReverseSignal(buySignal, sellSignal);

   // 4. only one position
   if(HasOpenPosition())
      return;

   // 5. sideways filter
   if(IsSideways())
      return;

   // 6. entry
   if(buySignal)
      OpenBuy(fast[1]);

   if(sellSignal)
      OpenSell(fast[1]);
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
bool IsSideways()
{
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

   return (rangePoints < SidewaysThreshold);
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