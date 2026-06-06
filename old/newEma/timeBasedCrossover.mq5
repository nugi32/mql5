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

input group "=== Filter Settings ==="
input int MinBarsBetweenCross = 5;

//================ TRADING =================
input group "=== Trading Settings ==="
input double lotSize = 0.01;
input bool useSLBE = true;

//================ GLOBAL =================
int fastEmaHandle;
int slowEmaHandle;
int atrHandle;
double fastEma[];
double slowEma[];
double atr[];

MqlRates rates[];

datetime lastCrossTime = 0;
datetime lastSignalBarTime = 0;
datetime lastEntryTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   fastEmaHandle=iMA(_Symbol,_Period,FastEMA_Period,0,MODE_EMA,PRICE_CLOSE);
   slowEmaHandle=iMA(_Symbol,_Period,SlowEMA_Period,0,MODE_EMA,PRICE_CLOSE);
   atrHandle=iATR(_Symbol,_Period,14);

   if(fastEmaHandle==INVALID_HANDLE || slowEmaHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(fastEma,true);
   ArraySetAsSeries(slowEma,true);
   ArraySetAsSeries(rates,true);
   ArraySetAsSeries(atr,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastEmaHandle);
   IndicatorRelease(slowEmaHandle);
   IndicatorRelease(atrHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;
datetime currentBarTime = iTime(_Symbol, _Period, 0);

if(currentBarTime == lastBarTime)
   return;

lastBarTime = currentBarTime;

    if(CopyBuffer(fastEmaHandle,0,0,3,fastEma) <= 0) return;
    if(CopyBuffer(slowEmaHandle,0,0,3,slowEma) <= 0) return;
    if(CopyBuffer(atrHandle,0,0,3,atr) <= 0) return;
    if(CopyRates(_Symbol,_Period,0,3,rates) < 3) return;

   CheckForEntry();
   CheckBreakEven();
}
//+------------------------------------------------------------------+
void CheckForEntry()
{
   double fast1 = fastEma[0]; // last closed candle
   double slow1 = slowEma[0];

   double fast2 = fastEma[1]; // previous candle
   double slow2 = slowEma[1];

    datetime t = rates[1].time;

   if(!IsNewSignal(t)) return;

   // ====== CROSS DETECTION ======
   bool bullCross = (fast2 < slow2) && (fast1 > slow1);
   bool bearCross = (fast2 > slow2) && (fast1 < slow1);

   // ====== DEBUG ======
   Print("fast1=",fast1," slow1=",slow1,
         " fast2=",fast2," slow2=",slow2);

   // ====== ENTRY ======
   if(bullCross && IsValidCrossDistance(t))
   {
      Print("BUY SIGNAL");
      CloseAllPositions();
      OpenBuy();
      return;
   }

   if(bearCross && IsValidCrossDistance(t))
   {
      Print("SELL SIGNAL");
      CloseAllPositions();
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

   double tp = entry + atr[1];
   double sl = entry - atr[1];

   SendOrder(ORDER_TYPE_BUY,entry,tp,sl);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   // FIXED (IMPORTANT!)
   double tp = entry - atr[1];
   double sl = entry + atr[1];

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
   req.tp       = 0;
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

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == Expert_MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.deviation = 10;
            request.magic = Expert_MagicNumber;
            request.position = ticket;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               request.type = ORDER_TYPE_SELL;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            }
            else
            {
               request.type = ORDER_TYPE_BUY;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            }
            
            ZeroMemory(result);
            if(!OrderSend(request, result))
            {
               Print("Close position failed: ", result.retcode);
            }
         }
      }
   }
}

//================ CHECK BREAK-EVEN =================
void CheckBreakEven()
{
   if (!useSLBE) return;

   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != Expert_MagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double price;
      double risk;

      // ================= BUY =================
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         risk = entry - sl;

         // Sudah BE atau SL invalid
         if(sl >= entry) continue;

         // RR 1:1 tercapai
         if(price >= entry + risk)
         {
            ModifySL(ticket, entry);
         }
      }

      // ================= SELL =================
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         risk = sl - entry;

         if(sl <= entry) continue;

         if(price <= entry - risk)
         {
            ModifySL(ticket, entry);
         }
      }
   }
}

//================ MODIFY SL =================
void ModifySL(ulong ticket, double newSL)
{
   MqlTradeRequest req = {};
   MqlTradeResult res = {};

   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.sl       = newSL;
   req.tp       = PositionGetDouble(POSITION_TP);

   if(!OrderSend(req, res))
   {
      Print("Modify SL FAILED: ", res.retcode);
   }
   else
   {
      Print("SL moved to BE for ticket: ", ticket);
   }
}