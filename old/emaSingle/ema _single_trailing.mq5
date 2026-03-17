//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== EMA Settings (Entry TF) ==="
input int EMA_period = 10;

input group "=== Trailing Stops Settings ==="
input double Trailing_RR_Distance = 1.0; // SL distance = 1R
input double Trailing_RR_Step     = 0.5; // Move SL every 0.5R


input group "=== Trading Settings ==="
input double Risk_Percent = 1.0;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross-MTF";

//================ GLOBAL =================
int    emaHandle;
double   ema[];
MqlRates rates[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   emaHandle = iMA(_Symbol,_Period,EMA_period,0,MODE_EMA,PRICE_CLOSE);

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
   if(!IsNewBar()) return;

   if(CopyBuffer(emaHandle,0,0,3,ema) < 3) return;
   if(CopyRates(_Symbol,_Period,0,3,rates) < 3) return;


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
   // if(HasOpenPosition()) return;

   double emaSingle = ema[1];

   bool buySignal =
      rates[1].low   <= emaSingle &&
      rates[1].close >  emaSingle;

   bool sellSignal =
      rates[1].high  >= emaSingle &&
      rates[1].close <  emaSingle;

   if(buySignal)
      OpenBuy();

   if(sellSignal)
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
   double sl    = ema[1];

   if(!IsValidStop(entry,sl)) return;

   double lot = CalculateLot(entry,sl);
   if(lot<=0) return;

   double tp = 0;

   SendOrder(ORDER_TYPE_BUY,lot,entry,sl,tp);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl    = ema[1];

   if(!IsValidStop(sl,entry)) return;

   double lot = CalculateLot(sl,entry);
   if(lot<=0) return;

   double tp = 0;

   SendOrder(ORDER_TYPE_SELL,lot,entry,sl,tp);
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

   double lot = MathFloor(rawLot / stepLot) * stepLot;
   lot = MathMin(lot, maxLot);

   return lot;
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

      manageTrailingStops(ticket);
   }
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
void manageTrailingStops(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;

    double current_sl    = PositionGetDouble(POSITION_SL);
    double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
    double open_price    = PositionGetDouble(POSITION_PRICE_OPEN);
    long   type          = PositionGetInteger(POSITION_TYPE);

    string comment = PositionGetString(POSITION_COMMENT);

    // Ambil initial SL dari comment
    int pos = StringFind(comment,"SL=");
    if(pos < 0) return;

    double initial_sl = StringToDouble(StringSubstr(comment,pos+3));
    if(initial_sl == 0) return;

    // Hitung initial R
    double risk;
    if(type == POSITION_TYPE_BUY)
        risk = open_price - initial_sl;
    else
        risk = initial_sl - open_price;

    if(risk <= 0) return;

    // RR trailing
    double trailing_distance = risk * Trailing_RR_Distance;
    double trailing_step     = risk * Trailing_RR_Step;

    if(type == POSITION_TYPE_BUY)
    {
        double new_sl = current_price - trailing_distance;

        if(new_sl > current_sl && new_sl > open_price &&
           current_price - open_price >= trailing_distance)
        {
            ModifySL(ticket, NormalizeDouble(new_sl,_Digits));
        }
    }
    else if(type == POSITION_TYPE_SELL)
    {
        double new_sl = current_price + trailing_distance;

        if(new_sl < current_sl && new_sl < open_price &&
           open_price - current_price >= trailing_distance)
        {
            ModifySL(ticket, NormalizeDouble(new_sl,_Digits));
        }
    }
}