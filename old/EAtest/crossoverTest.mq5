//+------------------------------------------------------------------+
//|   EMA Crossover EA (Fixed) + Sideways Filter                    |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"

input string Inp_Expert_Title="Expert_EMA_Crossover_Test";
int Expert_MagicNumber=14598;

//================ EMA SETTINGS =================
input group "=== EMA Settings ==="
input int FastEMA_Period = 13;
input int SlowEMA_Period = 21;

//================ TRADING =================
input group "=== Trading Settings ==="
input double lotSize = 0.01;
input int TP_Points = 500;
input int SL_Points = 500;

//================ GLOBAL =================
int fastEmaHandle;
int slowEmaHandle;

double fastEma[];
double slowEma[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastEmaHandle=iMA(_Symbol,_Period,FastEMA_Period,0,MODE_EMA,PRICE_CLOSE);
   slowEmaHandle=iMA(_Symbol,_Period,SlowEMA_Period,0,MODE_EMA,PRICE_CLOSE);

   if(fastEmaHandle==INVALID_HANDLE || slowEmaHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(fastEma,true);
   ArraySetAsSeries(slowEma,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastEmaHandle);
   IndicatorRelease(slowEmaHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;
datetime currentBarTime = iTime(_Symbol, _Period, 0);

if(currentBarTime == lastBarTime)
   return;

lastBarTime = currentBarTime;

   if(HasOpenPosition()) return;

    if(CopyBuffer(fastEmaHandle,0,0,3,fastEma) <= 0) return;
    if(CopyBuffer(slowEmaHandle,0,0,3,slowEma) <= 0) return;

   CheckForEntry();
}
//+------------------------------------------------------------------+
void CheckForEntry()
{
   double fast1 = fastEma[0]; // last closed candle
   double slow1 = slowEma[0];

   double fast2 = fastEma[1]; // previous candle
   double slow2 = slowEma[1];

   // ====== CROSS DETECTION ======
   bool bullCross = (fast2 < slow2) && (fast1 > slow1);
   bool bearCross = (fast2 > slow2) && (fast1 < slow1);

   // ====== DEBUG ======
   Print("fast1=",fast1," slow1=",slow1,
         " fast2=",fast2," slow2=",slow2);

   // ====== ENTRY ======
   if(bullCross)
   {
      Print("BUY SIGNAL");
      OpenBuy();
      return;
   }

   if(bearCross)
   {
      Print("SELL SIGNAL");
      OpenSell();
      return;
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

   double tp = entry + TP_Points * _Point;
   double sl = entry - SL_Points * _Point;

   SendOrder(ORDER_TYPE_BUY,entry,tp,sl);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   // FIXED (IMPORTANT!)
   double tp = entry - TP_Points * _Point;
   double sl = entry + SL_Points * _Point;

   SendOrder(ORDER_TYPE_SELL,entry,tp,sl);
}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price,double tp,double sl)
{
   if(HasOpenPosition()) return;

   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.volume   = lotSize;
   req.type     = type;
   req.price    = price;
   req.magic    = Expert_MagicNumber;
   req.deviation= 10;
   req.tp       = tp;
   req.sl       = sl;
   req.comment  = Inp_Expert_Title;

   if(!OrderSend(req,res))
   {
      Print("OrderSend FAILED: ",res.retcode);
   }
   else
   {
      Print("Order SUCCESS: ",res.order);
   }
}
//+------------------------------------------------------------------+
