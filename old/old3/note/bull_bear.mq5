//+------------------------------------------------------------------+
//|        Bulls & Bears Power EA (Risk Based + BE + Reverse Exit)   |
//+------------------------------------------------------------------+
#property strict
#property version "1.30"

//================ INPUT =================
input group "=== Indicator Settings ==="
input int EMA_period = 10;

input group "=== Trading Settings ==="
input double Risk_Percent   = 1.0;
input double Auto_BE_Level  = 1.0;
                                  
input group "=== Other Settings ==="
input int    Magic_Number   = 12345;
input string Trade_Comment  = "BullBear-EA";

//================ GLOBAL =================
int BullHandle, BearHandle;
double Bull[], Bear[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   BullHandle = iBullsPower(_Symbol,_Period,EMA_period);
   BearHandle = iBearsPower(_Symbol,_Period,EMA_period);

   if(BullHandle==INVALID_HANDLE || BearHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(Bull,true);
   ArraySetAsSeries(Bear,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(BullHandle);
   IndicatorRelease(BearHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(BullHandle,0,0,3,Bull) < 3) return;
   if(CopyBuffer(BearHandle,0,0,3,Bear) < 3) return;

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

   double bull1 = Bull[1];
   double bull2 = Bull[2];
   double bear1 = Bear[1];
   double bear2 = Bear[2];

   bool buySignal =
      bear1 < 0 &&
      bull2 < 0 &&
      bull1 > 0;

   bool sellSignal =
      bull1 > 0 &&
      bear2 > 0 &&
      bear1 < 0;

   if(buySignal)  OpenBuy();
   if(sellSignal) OpenSell();
}
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC)==Magic_Number &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl    = iLow(_Symbol,_Period,1);

   if(!IsValidStop(entry,sl)) return;

   double lot = CalculateLot(entry,sl);
   if(lot<=0) return;

   SendOrder(ORDER_TYPE_BUY,lot,entry,sl,0);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl    = iHigh(_Symbol,_Period,1);

   if(!IsValidStop(entry,sl)) return;

   double lot = CalculateLot(entry,sl);
   if(lot<=0) return;

   SendOrder(ORDER_TYPE_SELL,lot,entry,sl,0);
}
//+------------------------------------------------------------------+
bool IsValidStop(double price,double sl)
{
   double stopLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   return MathAbs(price-sl) >= stopLevel;
}
//+------------------------------------------------------------------+
double CalculateLot(double entry,double sl)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * Risk_Percent / 100.0;
   double points    = MathAbs(entry-sl)/_Point;
   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   if(points<=0 || tickValue<=0) return 0;

   double rawLot = riskMoney / (points * tickValue);

   double minLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(rawLot < minLot) return 0;

   double lot = MathFloor(rawLot/stepLot)*stepLot;
   return MathMin(lot,maxLot);
}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double lot,double price,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = lot;
   req.price    = price;
   req.sl       = sl;
   req.tp       = tp;
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

      ManageBreakeven(ticket);
      ManageReverseExit(ticket);
   }
}
//+------------------------------------------------------------------+
void ManageBreakeven(ulong ticket)
{
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   long type    = PositionGetInteger(POSITION_TYPE);

   double risk = MathAbs(open-sl);
   if(risk<=0) return;

   if(type==POSITION_TYPE_BUY && price>=open+risk*Auto_BE_Level && sl<open)
      ModifySL(ticket,open);

   if(type==POSITION_TYPE_SELL && price<=open-risk*Auto_BE_Level && sl>open)
      ModifySL(ticket,open);
}
//+------------------------------------------------------------------+
void ManageReverseExit(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);

   if(type==POSITION_TYPE_BUY && Bull[1] < 0)
      ClosePosition(ticket);

   if(type==POSITION_TYPE_SELL && Bear[1] > 0)
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
