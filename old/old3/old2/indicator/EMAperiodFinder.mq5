//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== EMA Settings (Entry TF) ==="
input int EMA_period = 10;
input int shift = 0;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "Period-finder";

//================ GLOBAL =================
int    emaHandle;
double   ema[];
MqlRates rates[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   emaHandle = iMA(_Symbol,_Period,EMA_period,shift,MODE_EMA,PRICE_CLOSE);

   if(emaHandle==INVALID_HANDLE)
      return INIT_FAILED;
      
ArraySetAsSeries(ema,true);
ArraySetAsSeries(rates,true);


   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{

   if(CopyBuffer(emaHandle,0,0,3,ema) < 3) return;
   if(CopyRates(_Symbol,_Period,0,3,rates) < 3) return;


   CheckForEntry();
   ManagePositions();
}
//+------------------------------------------------------------------+
bool crossUp()
{
   double price_now  = rates[1].close;
   double price_prev = rates[2].close;

   double ema_now  = ema[1];
   double ema_prev = ema[2];

   return (price_prev <= ema_prev && price_now > ema_now);
}
bool crossDown()
{
   double price_now  = rates[1].close;
   double price_prev = rates[2].close;

   double ema_now  = ema[1];
   double ema_prev = ema[2];

   return (price_prev >= ema_prev && price_now < ema_now);
}
void CheckForEntry()
{
   if(HasOpenPosition()) return;

   if(crossUp())
      OpenBuy();

   if(crossDown())
      OpenSell();
}
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC)==Magic_Number &&
            PositionGetString(POSITION_SYMBOL)==_Symbol)
            return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   SendOrder(ORDER_TYPE_BUY,entry);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   SendOrder(ORDER_TYPE_SELL,entry);
}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = 0.01;
   req.price    = price;
   req.magic    = Magic_Number;

   req.comment  = Trade_Comment;

   req.deviation= 10;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      manageReverseSignal(ticket);
   }
}
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.volume   = volume;
   req.magic    = Magic_Number;
   req.deviation= 10;

   if(type==POSITION_TYPE_BUY)
   {
      req.type  = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   }
   else
   {
      req.type  = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
void manageReverseSignal(ulong ticket)
{
  if (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && crossDown())
  {
      ClosePosition(ticket);
  }
  else if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && crossUp())
  {
      ClosePosition(ticket);
  }
}