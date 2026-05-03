#property strict

input double LotSize = 0.01;
input int    Slippage = 1;
input int    StopLoss = 200;
input int    TakeProfit = 300;

datetime lastBarTime = 0;

// --------------------------------------------------
bool IsNewBar(datetime currentBarTime)
{
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

// --------------------------------------------------
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }

   return false;
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
   request.volume       = LotSize;
   request.type         = ORDER_TYPE_BUY;
   request.price        = NormalizeDouble(tick.ask, _Digits);
   request.sl           = NormalizeDouble(tick.ask - StopLoss * _Point, _Digits);
   request.tp           = NormalizeDouble(tick.ask + TakeProfit * _Point, _Digits);
   request.deviation    = Slippage;
   request.type_filling = ORDER_FILLING_IOC;

   OrderSend(request, result);

   Print("BUY tick=", tick.ask,
         " fill=", result.price);
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
   request.volume       = LotSize;
   request.type         = ORDER_TYPE_SELL;
   request.price        = NormalizeDouble(tick.bid, _Digits);
   request.sl           = NormalizeDouble(tick.bid + StopLoss * _Point, _Digits);
   request.tp           = NormalizeDouble(tick.bid - TakeProfit * _Point, _Digits);
   request.deviation    = Slippage;
   request.type_filling = ORDER_FILLING_IOC;

   OrderSend(request, result);

   Print("SELL tick=", tick.bid,
         " fill=", result.price);
}

// --------------------------------------------------
void OnTick()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   datetime currentBar = iTime(_Symbol, PERIOD_M1, 0);

   if(!IsNewBar(currentBar))
      return;

   if(HasOpenPosition())
      return;

   // candle M1 yang baru selesai
   double prevOpen  = iOpen(_Symbol, PERIOD_M1, 1);
   double prevClose = iClose(_Symbol, PERIOD_M1, 1);

   // tick pertama candle baru dipakai sebagai harga entry
   if(prevClose > prevOpen)
      OpenBuy(tick);
   else if(prevClose < prevOpen)
      OpenSell(tick);
}