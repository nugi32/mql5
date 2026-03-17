//+------------------------------------------------------------------+
//|           EMA Crossover EA + Sideways Filter + SAR Trailing     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.30"

input string Inp_Expert_Title="Expert_EMA_Crossover";
int Expert_MagicNumber=14598;

//================ EMA SETTINGS =================
input group "=== Fast EMA Settings ==="
input int FastEMA_Period = 13;
input int FastEMA_Shift  = 0;

input group "=== Slow EMA Settings ==="
input int SlowEMA_Period = 21;
input int SlowEMA_Shift  = 0;

input group "=== Trend EMA Settings ==="
input int TrendEMA_Period = 21;
input int TrendEMA_Shift  = 0;
//================ SIDEWAYS FILTER =================
input group "=== Sideways Detector Settings ==="
input int period = 34;
input double rangeBuffer = 100.0;

//================ TRADING =================
input group "=== Trading Settings ==="
input double lotSize = 0.01;

//================ GLOBAL =================
int fastEmaHandle;
int slowEmaHandle;
int sidewaysHandle;
int trendEmaHandle;

double fastEma[];
double slowEma[];
double sidewaysBuffer[];
double trendEma[];

MqlRates rates[];

datetime lastBarTime=0;

//+------------------------------------------------------------------+
int OnInit()
{

   fastEmaHandle=iMA(_Symbol,_Period,FastEMA_Period,FastEMA_Shift,MODE_EMA,PRICE_CLOSE);
   slowEmaHandle=iMA(_Symbol,_Period,SlowEMA_Period,SlowEMA_Shift,MODE_EMA,PRICE_CLOSE);
   trendEmaHandle=iMA(_Symbol,_Period,TrendEMA_Period,TrendEMA_Shift,MODE_EMA,PRICE_CLOSE);

   sidewaysHandle=iCustom(
      _Symbol,
      _Period,
      "EMA_Sideways_Detector",
      period,
      rangeBuffer,
      159
   );

   if(fastEmaHandle==INVALID_HANDLE ||
      slowEmaHandle==INVALID_HANDLE ||
      trendEmaHandle==INVALID_HANDLE ||
      sidewaysHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(fastEma,true);
   ArraySetAsSeries(slowEma,true);
   ArraySetAsSeries(trendEma,true);
   ArraySetAsSeries(rates,true);
   ArraySetAsSeries(sidewaysBuffer,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{

   IndicatorRelease(fastEmaHandle);
   IndicatorRelease(slowEmaHandle);
   IndicatorRelease(trendEmaHandle);
   IndicatorRelease(sidewaysHandle);

}
//+------------------------------------------------------------------+
void OnTick()
{

   if(!IsNewBar()) return;

   if(CopyBuffer(fastEmaHandle,0,0,3,fastEma)<3) return;
   if(CopyBuffer(slowEmaHandle,0,0,3,slowEma)<3) return;
   if(CopyBuffer(trendEmaHandle,0,0,3,trendEma)<3) return;
   if(CopyBuffer(sidewaysHandle,0,0,3,sidewaysBuffer)<3) return;
   if(CopyRates(_Symbol,_Period,0,3,rates)<3) return;

   CheckForEntry();

}
//+------------------------------------------------------------------+
bool IsNewBar()
{

   datetime current=iTime(_Symbol,_Period,0);

   if(current==lastBarTime)
      return false;

   lastBarTime=current;
   return true;

}
//+------------------------------------------------------------------+
bool isSideways()
{
   return (sidewaysBuffer[1]!=EMPTY_VALUE);
}

//+------------------------------------------------------------------+
bool isUpTrend()
{
   return rates[1].close > trendEma[1];
}

//+------------------------------------------------------------------+
bool isDownTrend()
{
   return rates[1].close < trendEma[1];
}

//+------------------------------------------------------------------+
void CheckForEntry()
{

   if(isSideways()) return;

   double fast_now=fastEma[1];
   double fast_prev=fastEma[2];

   double slow_now=slowEma[1];
   double slow_prev=slowEma[2];

   bool crossUp=(fast_prev<=slow_prev && fast_now>slow_now);
   bool crossDown=(fast_prev>=slow_prev && fast_now<slow_now);

   if(crossUp && isUpTrend())
   {
      Print("EMA Cross UP -> BUY");
      CloseSell();
      OpenBuy();
   }

   if(crossDown && isDownTrend())
   {
      Print("EMA Cross DOWN -> SELL");
        CloseBuy();
      OpenSell();
   }

}
//+------------------------------------------------------------------+
bool HasOpenPosition()
{

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC)==Expert_MagicNumber &&
            PositionGetString(POSITION_SYMBOL)==_Symbol)
            return true;
      }
   }

   return false;

}
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   SendOrder(ORDER_TYPE_BUY,entry);

}
//+------------------------------------------------------------------+
void OpenSell()
{

   double entry=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   SendOrder(ORDER_TYPE_SELL,entry);

}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price)
{

   if(HasOpenPosition()) return;

   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.symbol=_Symbol;
   req.volume=lotSize;
   req.type=type;
   req.price=price;
   req.magic=Expert_MagicNumber;
   req.deviation=10;
   req.comment=Inp_Expert_Title;

   OrderSend(req,res);

}
//+------------------------------------------------------------------+
//| Close all BUY positions                                          |
//+------------------------------------------------------------------+
void CloseBuy()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY)
         continue;

      double volume=PositionGetDouble(POSITION_VOLUME);
      double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

      MqlTradeRequest req={};
      MqlTradeResult res={};

      req.action=TRADE_ACTION_DEAL;
      req.position=ticket;
      req.symbol=_Symbol;
      req.volume=volume;
      req.type=ORDER_TYPE_SELL;
      req.price=price;
      req.magic=Expert_MagicNumber;
      req.deviation=10;

      OrderSend(req,res);
   }
}

//+------------------------------------------------------------------+
//| Close all SELL positions                                         |
//+------------------------------------------------------------------+
void CloseSell()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL)
         continue;

      double volume=PositionGetDouble(POSITION_VOLUME);
      double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      MqlTradeRequest req={};
      MqlTradeResult res={};

      req.action=TRADE_ACTION_DEAL;
      req.position=ticket;
      req.symbol=_Symbol;
      req.volume=volume;
      req.type=ORDER_TYPE_BUY;
      req.price=price;
      req.magic=Expert_MagicNumber;
      req.deviation=10;

      OrderSend(req,res);
   }
}