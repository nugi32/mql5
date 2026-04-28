//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== EMA Settings (Entry TF) ==="
input int EMA_Fast_Period = 10;
input int EMA_Slow_Period = 20;

input group "=== ATR Settings ==="
input int ATRperiod = 14;
input int ATRmultiplier = 2;

input group "=== Positon Settings ==="
input int higherThanPreviousCandle = 3;
input int closeAfterCandles = 3;

input group "=== Trading Settings ==="
input double Risk_Percent = 1.0;
input double Auto_BE_Level  = 1.0;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross-MTF";

//================ GLOBAL =================
int    emaFastHandle, emaSlowHandle, ATRhandle;
double emaFast[], emaSlow[], ATR[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   emaFastHandle = iMA(_Symbol,_Period,EMA_Fast_Period,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol,_Period,EMA_Slow_Period,0,MODE_EMA,PRICE_CLOSE);
   ATRhandle = iATR(_Symbol,_Period, ATRperiod);

   if(emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE || ATRhandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(emaFast,true);
   ArraySetAsSeries(emaSlow,true);
   ArraySetAsSeries(ATR,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(ATRhandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(emaFastHandle,0,0,3,emaFast) < 3) return;
   if(CopyBuffer(emaSlowHandle,0,0,3,emaSlow) < 3) return;
   if(CopyBuffer(ATRhandle,0,0,3,ATR) < 3) return;

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
bool IsPriceHigherThanPrevious(int candles)
{
   double currentClose = iClose(_Symbol, _Period, 0);

   for(int i = 1; i <= candles; i++)
   {
      double prevClose = iClose(_Symbol, _Period, i);
      if(currentClose <= prevClose)
         return false;
   }
   return true;
}

bool IsPriceLowerThanPrevious(int candles)
{
   double currentClose = iClose(_Symbol, _Period, 0);

   for(int i = 1; i <= candles; i++)
   {
      double prevClose = iClose(_Symbol, _Period, i);
      if(currentClose >= prevClose)
         return false;
   }
   return true;
}


void CheckForEntry()
{
   //if(HasOpenPosition()) return;

   bool buyTrend  = emaFast[1] > emaSlow[1];
   bool sellTrend = emaFast[1] < emaSlow[1];
  

   if(buyTrend && IsPriceHigherThanPrevious(higherThanPreviousCandle)) {
      OpenBuy();
      }

   if(sellTrend && IsPriceLowerThanPrevious(higherThanPreviousCandle)){
      OpenSell();
      }
}
//+------------------------------------------------------------------+
bool IsPositionClosedAfterCandles(ulong ticket, int candles)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

   int openShift = iBarShift(_Symbol, _Period, openTime, false);
   if(openShift < 0)
      return false;

   // candle 0 masih berjalan, jadi yang sudah close = openShift
   if(openShift >= candles)
      return true;

   return false;
}

/*
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
}*/
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl    = 0;

   //double lot = CalculateLot(entry,sl);
   double lot =0.01;
   if(lot<=0) return;

   double tp = 0;

   SendOrder(ORDER_TYPE_BUY,lot,entry,sl,tp);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl    = 0;

   //double lot = CalculateLot(sl,entry);
   double lot =0.01;
   if(lot<=0) return;

   double tp = 0;

   SendOrder(ORDER_TYPE_SELL,lot,entry,sl,tp);
}
//+------------------------------------------------------------------+
/*
bool IsValidStop(double price,double sl)
{
   double stopLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   return MathAbs(price-sl) >= stopLevel;
}*/
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

     // ManageBreakeven(ticket);
      ManageReverseTP(ticket);
   }
}
//+------------------------------------------------------------------+
/*
void ManageBreakeven(ulong ticket)
{
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double price= PositionGetDouble(POSITION_PRICE_CURRENT);
   long   type = PositionGetInteger(POSITION_TYPE);

   double risk = MathAbs(open-sl);
   if(risk<=0) return;

   if(type==POSITION_TYPE_BUY && price>=open+risk*Auto_BE_Level && sl<open)
      ModifySL(ticket,open);

   if(type==POSITION_TYPE_SELL && price<=open-risk*Auto_BE_Level && sl>open)
      ModifySL(ticket,open);
}*/
//+------------------------------------------------------------------+
void ManageReverseTP(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);

   if(type==POSITION_TYPE_BUY &&
      IsPositionClosedAfterCandles(ticket, closeAfterCandles))
      ClosePosition(ticket);

   if(type==POSITION_TYPE_SELL &&
      IsPositionClosedAfterCandles(ticket, closeAfterCandles))
      ClosePosition(ticket);
}
//+------------------------------------------------------------------+
/*
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
}*/
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
