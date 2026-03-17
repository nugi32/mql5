//+------------------------------------------------------------------+
//| Wick SR Bounce EA                                               |
//| Trade bounce dari high/low candle TF besar di M1                |
//+------------------------------------------------------------------+
#property strict

input ENUM_TIMEFRAMES SR_Timeframe = PERIOD_H1;
input double Lots = 0.01;
input int TP_Points = 200;
input int Touch_Distance = 20;
input int Magic = 20260312;

double SR_High;
double SR_Low;
datetime lastbar=0;

//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+

void GetSR()
{
   SR_High = iHigh(_Symbol,SR_Timeframe,1);
   SR_Low  = iLow(_Symbol,SR_Timeframe,1);
}

//+------------------------------------------------------------------+
bool BuyCondition()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double low1 = iLow(_Symbol,PERIOD_M1,1);
   double close1 = iClose(_Symbol,PERIOD_M1,1);

   if(MathAbs(low1 - SR_Low) <= Touch_Distance*_Point && close1 > low1)
      return true;

   return false;
}

//+------------------------------------------------------------------+
bool SellCondition()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double high1 = iHigh(_Symbol,PERIOD_M1,1);
   double close1 = iClose(_Symbol,PERIOD_M1,1);

   if(MathAbs(high1 - SR_High) <= Touch_Distance*_Point && close1 < high1)
      return true;

   return false;
}

//+------------------------------------------------------------------+
bool PositionOpen()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC)==Magic)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl = iLow(_Symbol,PERIOD_M1,1);
   double tp = ask + TP_Points*_Point;

   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = Lots;
   req.type = ORDER_TYPE_BUY;
   req.price = ask;
   req.sl = sl;
   req.tp = tp;
   req.magic = Magic;
   req.deviation = 20;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = iHigh(_Symbol,PERIOD_M1,1);
   double tp = bid - TP_Points*_Point;

   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = Lots;
   req.type = ORDER_TYPE_SELL;
   req.price = bid;
   req.sl = sl;
   req.tp = tp;
   req.magic = Magic;
   req.deviation = 20;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentbar=iTime(_Symbol,PERIOD_M1,0);

   if(currentbar==lastbar)
      return;

   lastbar=currentbar;

   GetSR();

   if(PositionOpen())
      return;

   if(BuyCondition())
      OpenBuy();

   if(SellCondition())
      OpenSell();
}
//+------------------------------------------------------------------+