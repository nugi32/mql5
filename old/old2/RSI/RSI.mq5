//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== RSI Settings (Entry TF) ==="
input int emaPeriod = 10;
input int overSold = 20;
input int overPrice = 80;

input group "=== Trading Settings ==="
input double lotSize = 0.01;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross-MTF";

//================ GLOBAL =================
int     rsiHandle;
double RSI[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   rsiHandle = iRSI(_Symbol, _Period, emaPeriod, PRICE_CLOSE);

   if(rsiHandle == INVALID_HANDLE)
      return INIT_FAILED;

ArraySetAsSeries(RSI,true);               


   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(rsiHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(rsiHandle,0,0,3,RSI) < 3 ) return;

   CheckForEntry();
   ManagePositions();
}
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(_Symbol,_Period,0);
   if(current == lastBarTime) return false;
   lastBarTime = current;
   return true;
}
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(HasOpenPosition()) return;


bool rsiBuy  = RSI[1] <= overSold;
bool rsiSell = RSI[1] >= overPrice;

   // ===== FINAL SIGNAL =====
   if(rsiSell)
      OpenBuy();

   if(rsiBuy)
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

   double sl,tp;

   if(type==ORDER_TYPE_BUY)
   {
      sl = price - 500 * _Point;
      tp = price + 200 * _Point;
   }
   else
   {
      sl = price + 500 * _Point;
      tp = price - 200 * _Point;
   }

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = lotSize;
   req.price    = price;
   req.sl       = NormalizeDouble(sl,_Digits);
   req.tp       = NormalizeDouble(tp,_Digits);
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

      //ManageReverseTP(ticket);
   }
}
//+------------------------------------------------------------------+
void ManageReverseTP(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);
   bool rsiBuy  = RSI[1] > overSold && RSI[1] < 50;
   bool rsiSell = RSI[1] < overPrice && RSI[1] > 50;

   if(type==POSITION_TYPE_BUY &&
      rsiSell)
      ClosePosition(ticket);

   if(type==POSITION_TYPE_SELL &&
      rsiBuy)
      ClosePosition(ticket);
}
//+------------------------------------------------------------------+
void ModifySL(ulong ticket,double newSL)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.sl       = newSL;
   req.tp       = PositionGetDouble(POSITION_TP);

   OrderSend(req,res);
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