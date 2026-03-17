//+------------------------------------------------------------------+
//|         Mean Reversion EA (Multi Position + SL Only)            |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"

input string Inp_Expert_Title="Expert_Mean_Reversion";
int Expert_MagicNumber=14598;

//================ TRADING =================
input group "=== Trading Settings ==="
input double lotSize = 0.01;
input int StopLossPoints = 300;
input int MaxPositions = 5;
input int MinDistancePoints = 100;

//================ GLOBAL =================
MqlRates rates[];
datetime lastBarTime=0;

//================ INDICATORS =================
int env1, env2, env3, env4;
int dem1, dem2, dem3, dem4;

// buffers envelopes
double env1_upper[], env1_lower[];
double env2_upper[], env2_lower[];
double env3_upper[], env3_lower[];
double env4_upper[], env4_lower[];

// buffers demarker
double deM1[], deM2[], deM3[], deM4[];

//+------------------------------------------------------------------+
int OnInit()
{
   ArraySetAsSeries(rates,true);

   // ENVELOPES
   env1 = iEnvelopes(Symbol(), PERIOD_CURRENT, 4, 0, MODE_SMA, PRICE_CLOSE, 0.270);
   env2 = iEnvelopes(Symbol(), PERIOD_CURRENT, 4, 0, MODE_SMA, PRICE_CLOSE, 0.290);
   env3 = iEnvelopes(Symbol(), PERIOD_CURRENT, 6, 0, MODE_SMA, PRICE_CLOSE, 0.370);
   env4 = iEnvelopes(Symbol(), PERIOD_CURRENT, 6, 0, MODE_SMA, PRICE_CLOSE, 0.310);

   // DEMARKER
   dem1 = iDeMarker(Symbol(), PERIOD_CURRENT, 35);
   dem2 = iDeMarker(Symbol(), PERIOD_CURRENT, 20);
   dem3 = iDeMarker(Symbol(), PERIOD_CURRENT, 31);
   dem4 = iDeMarker(Symbol(), PERIOD_CURRENT, 30);

   // array series
   ArraySetAsSeries(env1_upper,true); ArraySetAsSeries(env1_lower,true);
   ArraySetAsSeries(env2_upper,true); ArraySetAsSeries(env2_lower,true);
   ArraySetAsSeries(env3_upper,true); ArraySetAsSeries(env3_lower,true);
   ArraySetAsSeries(env4_upper,true); ArraySetAsSeries(env4_lower,true);

   ArraySetAsSeries(deM1,true);
   ArraySetAsSeries(deM2,true);
   ArraySetAsSeries(deM3,true);
   ArraySetAsSeries(deM4,true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   CopyRates(Symbol(), PERIOD_CURRENT, 0, 3, rates);

   // 1 candle filter
   datetime currentBar = rates[0].time;
   if(currentBar == lastBarTime)
      return;
   lastBarTime = currentBar;

   // COPY ENVELOPES
   CopyBuffer(env1, 0, 0, 3, env1_upper);
   CopyBuffer(env1, 1, 0, 3, env1_lower);

   CopyBuffer(env2, 0, 0, 3, env2_upper);
   CopyBuffer(env2, 1, 0, 3, env2_lower);

   CopyBuffer(env3, 0, 0, 3, env3_upper);
   CopyBuffer(env3, 1, 0, 3, env3_lower);

   CopyBuffer(env4, 0, 0, 3, env4_upper);
   CopyBuffer(env4, 1, 0, 3, env4_lower);

   // COPY DEMARKER
   CopyBuffer(dem1, 0, 0, 3, deM1);
   CopyBuffer(dem2, 0, 0, 3, deM2);
   CopyBuffer(dem3, 0, 0, 3, deM3);
   CopyBuffer(dem4, 0, 0, 3, deM4);

   CheckForEntry();
}

//+------------------------------------------------------------------+
int CountMyPositions()
{
   int total = 0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      total++;
   }
   return total;
}

//+------------------------------------------------------------------+
bool CanOpenNewPosition(double price)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      if(MathAbs(price - openPrice) < MinDistancePoints * _Point)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
   double price = rates[0].close;

   int totalPos = CountMyPositions();
   if(totalPos >= MaxPositions)
      return;

   // BUY scaling
   if(price < env1_lower[0] && deM1[0] < 0.3 && CanOpenNewPosition(price))
      OpenBuy();

   if(price < env2_lower[0] && deM2[0] < 0.3 && CanOpenNewPosition(price))
      OpenBuy();

   if(price < env3_lower[0] && deM3[0] < 0.3 && CanOpenNewPosition(price))
      OpenBuy();

   if(price < env4_lower[0] && deM4[0] < 0.3 && CanOpenNewPosition(price))
      OpenBuy();

   // SELL scaling
   if(price > env1_upper[0] && deM1[0] > 0.7 && CanOpenNewPosition(price))
      OpenSell();

   if(price > env2_upper[0] && deM2[0] > 0.7 && CanOpenNewPosition(price))
      OpenSell();

   if(price > env3_upper[0] && deM3[0] > 0.7 && CanOpenNewPosition(price))
      OpenSell();

   if(price > env4_upper[0] && deM4[0] > 0.7 && CanOpenNewPosition(price))
      OpenSell();

   CheckForExit();
}

//+------------------------------------------------------------------+
void CheckForExit()
{
   double price = rates[0].close;
   double mean = (env1_upper[0] + env1_lower[0]) / 2.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      int type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY && price >= mean)
         CloseBuy();

      if(type == POSITION_TYPE_SELL && price <= mean)
         CloseSell();
   }
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl = price - StopLossPoints * _Point;

   SendOrder(ORDER_TYPE_BUY,price,sl);
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = price + StopLossPoints * _Point;

   SendOrder(ORDER_TYPE_SELL,price,sl);
}

//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price,double sl)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lotSize;
   req.type      = type;
   req.price     = price;
   req.sl        = sl;
   req.tp        = 0;
   req.magic     = Expert_MagicNumber;
   req.deviation = 10;
   req.comment   = Inp_Expert_Title;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
void CloseBuy()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) continue;

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

      OrderSend(req,res);
   }
}

//+------------------------------------------------------------------+
void CloseSell()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL) continue;

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

      OrderSend(req,res);
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(env1);
   IndicatorRelease(env2);
   IndicatorRelease(env3);
   IndicatorRelease(env4);

   IndicatorRelease(dem1);
   IndicatorRelease(dem2);
   IndicatorRelease(dem3);
   IndicatorRelease(dem4);
}
//+------------------------------------------------------------------+