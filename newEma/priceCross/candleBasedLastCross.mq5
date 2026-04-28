//+------------------------------------------------------------------+
//|              EMA Crossover EA + Management                       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.30"

//================ INPUT =================
input group "=== EMA Settings ==="
input int EMA_period = 10;

input group "=== Filter Settings ==="
input int MinBarsBetweenCross = 5;
input int emaTrendFilterPeriod = 50;

input group "=== Trading Settings ==="
input double lotSize = 0.01;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross";

//================ GLOBAL =================
int emaHandle, atrHandle, emaTrendHandle;
double ema[], ATR[], emaTrend[];
MqlRates rates[];

datetime lastCrossTime = 0;
datetime lastSignalBarTime = 0;
datetime lastEntryTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   emaHandle = iMA(_Symbol,_Period,EMA_period,0,MODE_EMA,PRICE_CLOSE);
   atrHandle = iATR(_Symbol,_Period,14);
   emaTrendHandle = iMA(_Symbol,_Period,emaTrendFilterPeriod,0,MODE_EMA,PRICE_CLOSE);
   atrHandle = iATR(_Symbol,_Period,14);

   if(emaHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE || emaTrendHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(ema,true);
   ArraySetAsSeries(ATR,true);
   ArraySetAsSeries(rates,true);
   ArraySetAsSeries(emaTrend,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(CopyBuffer(emaHandle,0,0,3,ema) < 3) return;
   if(CopyBuffer(atrHandle,0,0,3,ATR) < 3) return;
   if(CopyBuffer(emaTrendHandle,0,0,3,emaTrend) < 3) return;
   if(CopyRates(_Symbol,_Period,0,3,rates) < 3) return;

   //ManagePosition();
   CheckForEntry();
}
//+------------------------------------------------------------------+

bool IsUptrend()
{
   return emaTrend[1] > emaTrend[2] &&

          emaTrend[1] < rates[1].close && 

          emaTrend[1] - rates[1].close > 50 * _Point;
}


bool IsDowntrend()
{
   return emaTrend[1] < emaTrend[2] &&

          emaTrend[1] > rates[1].close && 

          emaTrend[1] - rates[1].close > 50 * _Point;
}

//================ SIGNAL FILTER =================
bool IsValidCrossDistance(datetime t)
{
   if(lastCrossTime == 0) return true;

   int sec = PeriodSeconds(_Period);
   int bars = (int)((t - lastCrossTime)/sec);

   return (bars >= MinBarsBetweenCross);
}

bool IsNewSignal(datetime t)
{
   if(t == lastSignalBarTime) return false;

   lastSignalBarTime = t;
   return true;
}

//================ ENTRY =================
void CheckForEntry()
{
   if(HasOpenPosition()) return;

   bool crossUp   = rates[1].open < ema[1] && rates[1].close > ema[1];
   bool crossDown = rates[1].open > ema[1] && rates[1].close < ema[1];

   datetime t = rates[1].time;

   if(!IsNewSignal(t)) return;

   if(crossUp && IsValidCrossDistance(t) && IsDowntrend())
   {
      if(OpenBuy())
         lastCrossTime = t;
   }

   if(crossDown && IsValidCrossDistance(t) && IsUptrend())
   {
      if(OpenSell())
         lastCrossTime = t;
   }
}

//================ POSITION CHECK =================
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

//================ ORDER =================
bool SendOrder(ENUM_ORDER_TYPE type,double price,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = lotSize;
   req.price    = price;
   req.sl       = sl;
   req.tp       = tp;
   req.magic    = Magic_Number;
   req.comment  = Trade_Comment;
   req.deviation= 10;

   if(!OrderSend(req,res))
   {
      Print("OrderSend FAILED: ", res.retcode);
      return false;
   }

   if(res.retcode != TRADE_RETCODE_DONE)
   {
      Print("OrderSend ERROR: ", res.retcode);
      return false;
   }

   return true;
}

//================ OPEN =================
bool OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl    = entry - ATR[1] * 2;
   double tp    = entry + ATR[1];

   if(SendOrder(ORDER_TYPE_BUY,entry,sl,tp))
   {
      lastEntryTime = TimeCurrent();
      return true;
   }
   return false;
}

bool OpenSell()
{
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl    = entry + ATR[1] * 2;
   double tp    = entry - ATR[1];

   if(SendOrder(ORDER_TYPE_SELL,entry,sl,tp))
   {
      lastEntryTime = TimeCurrent();
      return true;
   }
   return false;
}


































































/*

//================ MODIFY SL =================
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

//================ PARTIAL CLOSE =================
void ClosePartial(ulong ticket,double volume)
{
   if(!PositionSelectByTicket(ticket)) return;

   long type = PositionGetInteger(POSITION_TYPE);

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
      req.type=ORDER_TYPE_SELL;
      req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   }
   else
   {
      req.type=ORDER_TYPE_BUY;
      req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   OrderSend(req,res);
}

//================ CLOSE FULL =================
void ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;

   long type = PositionGetInteger(POSITION_TYPE);
   double vol = PositionGetDouble(POSITION_VOLUME);

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.position=ticket;
   req.symbol=_Symbol;
   req.volume=vol;
   req.magic=Magic_Number;
   req.deviation=10;

   if(type==POSITION_TYPE_BUY)
   {
      req.type=ORDER_TYPE_SELL;
      req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   }
   else
   {
      req.type=ORDER_TYPE_BUY;
      req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   OrderSend(req,res);
}

//================ MANAGEMENT =================
void ManagePosition()
{
   // ❌ jangan manage di tick yg sama dengan entry
   if(TimeCurrent() == lastEntryTime)
      return;

   bool reverseSell = rates[1].open > ema[1] && rates[1].close < ema[1];
   bool reverseBuy  = rates[1].open < ema[1] && rates[1].close > ema[1];

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);

      double price = (type==POSITION_TYPE_BUY) ?
         SymbolInfoDouble(_Symbol,SYMBOL_BID) :
         SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double risk = MathAbs(entry - sl);
      double reward = MathAbs(price - entry);

      bool hitRR = reward >= risk;

      // BE + partial
      if(hitRR && sl != entry)
      {
         ModifySL(ticket,entry);

         if(vol > 0.01)
         {
            double closeLot = NormalizeDouble(vol/2.0,2);

            int digit = (int)(vol*100)%10;
            if(digit % 2 != 0)
               closeLot += 0.01;

            ClosePartial(ticket,closeLot);
         }
      }

      // reverse close
      if(type==POSITION_TYPE_BUY && reverseSell)
         ClosePosition(ticket);

      if(type==POSITION_TYPE_SELL && reverseBuy)
         ClosePosition(ticket);
   }
}
//+------------------------------------------------------------------+
*/