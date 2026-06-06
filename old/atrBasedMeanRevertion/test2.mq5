#property strict

input ENUM_TIMEFRAMES SignalTF = PERIOD_M1;

input double LotSize           = 0.01;
input int    FastMAPeriod      = 8;
input int    SlowMAPeriod      = 21;

input int    StopLoss          = 150;   // points
input int    TakeProfit        = 250;   // points
input int    TrailingStop      = 0;     // 0 = off

input int    EntryBuffer       = 5;     // breakout buffer (points)
input int    MaxSpread         = 30;    // points
input int    Slippage          = 1;

input ulong  MagicNumber       = 20260502;

datetime lastBarTime = 0;

// --------------------------------------------------
bool IsNewBar()
{
   datetime t = iTime(_Symbol, SignalTF, 0);

   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }

   return false;
}

// --------------------------------------------------
bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }

   return false;
}

// --------------------------------------------------
double GetEMA(int period,int shift)
{
   return iMA(_Symbol, SignalTF, period, 0, MODE_EMA, PRICE_CLOSE);
}

// --------------------------------------------------
bool SpreadOK(const MqlTick &tick)
{
   double spread = (tick.ask - tick.bid) / _Point;
   return (spread <= MaxSpread);
}

// --------------------------------------------------
void OpenBuy(const MqlTick &tick)
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.magic        = MagicNumber;
   request.volume       = LotSize;
   request.type         = ORDER_TYPE_BUY;
   request.price        = NormalizeDouble(tick.ask,_Digits);
   request.sl           = NormalizeDouble(tick.ask - StopLoss * _Point,_Digits);
   request.tp           = NormalizeDouble(tick.ask + TakeProfit * _Point,_Digits);
   request.deviation    = Slippage;
   request.type_filling = ORDER_FILLING_IOC;

   OrderSend(request,result);
}

// --------------------------------------------------
void OpenSell(const MqlTick &tick)
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.magic        = MagicNumber;
   request.volume       = LotSize;
   request.type         = ORDER_TYPE_SELL;
   request.price        = NormalizeDouble(tick.bid,_Digits);
   request.sl           = NormalizeDouble(tick.bid + StopLoss * _Point,_Digits);
   request.tp           = NormalizeDouble(tick.bid - TakeProfit * _Point,_Digits);
   request.deviation    = Slippage;
   request.type_filling = ORDER_FILLING_IOC;

   OrderSend(request,result);
}

// --------------------------------------------------
void ManageTrailing()
{
   if(TrailingStop <= 0)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket <= 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      MqlTradeRequest request;
      MqlTradeResult  result;

      ZeroMemory(request);
      ZeroMemory(result);

      request.action   = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol   = _Symbol;

      if(type == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(tick.bid - TrailingStop * _Point,_Digits);

         if(newSL > sl)
         {
            request.sl = newSL;
            request.tp = tp;
            OrderSend(request,result);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double newSL = NormalizeDouble(tick.ask + TrailingStop * _Point,_Digits);

         if(sl == 0 || newSL < sl)
         {
            request.sl = newSL;
            request.tp = tp;
            OrderSend(request,result);
         }
      }
   }
}

// --------------------------------------------------
void OnTick()
{
   ManageTrailing();

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   if(!IsNewBar())
      return;

   if(!SpreadOK(tick))
      return;

   if(HasOpenPosition())
      return;

   double fast1 = GetEMA(FastMAPeriod,1);
   double slow1 = GetEMA(SlowMAPeriod,1);

   double prevHigh = iHigh(_Symbol,SignalTF,1);
   double prevLow  = iLow(_Symbol,SignalTF,1);

   double buyTrigger  = prevHigh + EntryBuffer * _Point;
   double sellTrigger = prevLow  - EntryBuffer * _Point;

   if(fast1 > slow1 && tick.ask > buyTrigger)
      OpenBuy(tick);

   if(fast1 < slow1 && tick.bid < sellTrigger)
      OpenSell(tick);
}