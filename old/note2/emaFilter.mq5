//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== EMA Settings (Entry TF) ==="
input int EMA_Fast_Period = 10;
input int EMA_Slow_Period = 20;

input group "=== ADX Settings ==="
input int ADX_Period = 14;
input int ADX_Filter = 20;

input group "=== VOL Settings ==="
input int Volume_Filter = 1;

input group "=== RSI CONFIRMATION ==="
input int RSI_Period = 14;
input int RSI_Overbought = 70;
input int RSI_Oversold = 30;

input group "=== Higher TF Confirmation ==="
input ENUM_TIMEFRAMES LAYER_TIMEFRAME = PERIOD_H1;
input int EMA_HIGH_TIMEFRAME_PERIOD = 30;

input group "=== Trading Settings ==="
input double Risk_Percent = 1.0;
input double Auto_BE_Level  = 1.0;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross-MTF";

//================ GLOBAL =================
int    emaFastHandle, emaSlowHandle, emaLayerHandle, rsiHandle, adxHandle, volHandle;
double emaFast[], emaSlow[], emaLayer[], ADX[], RSI[], VOL[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   emaFastHandle = iMA(_Symbol,_Period,EMA_Fast_Period,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol,_Period,EMA_Slow_Period,0,MODE_EMA,PRICE_CLOSE);
   emaLayerHandle = iMA(_Symbol,LAYER_TIMEFRAME,EMA_HIGH_TIMEFRAME_PERIOD,0,MODE_EMA,PRICE_CLOSE);

   rsiHandle = iRSI(_Symbol,_Period,RSI_Period,PRICE_CLOSE);
   adxHandle = iADX(_Symbol,_Period,ADX_Period);
   volHandle = iVolumes(_Symbol,_Period, VOLUME_TICK);

   if(emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE || emaLayerHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE || adxHandle==INVALID_HANDLE || volHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(emaFast,true);
   ArraySetAsSeries(emaSlow,true);
   ArraySetAsSeries(emaLayer,true);
   ArraySetAsSeries(ADX,true);
   ArraySetAsSeries(RSI,true);
   ArraySetAsSeries(VOL,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(emaLayerHandle);
   IndicatorRelease(adxHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(volHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(emaFastHandle,0,0,3,emaFast) < 3) return;
   if(CopyBuffer(emaSlowHandle,0,0,3,emaSlow) < 3) return;
   if(CopyBuffer(emaLayerHandle,0,0,3,emaLayer) < 3) return;
   if(CopyBuffer(adxHandle,0,0,3,ADX) < 3) return;
   if(CopyBuffer(rsiHandle,0,0,3,RSI) < 3) return;
   if(CopyBuffer(volHandle,0,0,3,VOL) < 3) return;

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
//================ MTF CONFIRMATION =================
bool HigherTF_Bullish()
{
   double priceHTF = iClose(_Symbol,LAYER_TIMEFRAME,0);
   return priceHTF > emaLayer[1];
}

bool HigherTF_Bearish()
{
   double priceHTF = iClose(_Symbol,LAYER_TIMEFRAME,0);
   return priceHTF < emaLayer[1];
}
//+------------------------------------------------------------------+
void CheckForEntry()
{
   //if(HasOpenPosition()) return;

   bool buySignal  = emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2];
   bool sellSignal = emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2];

   //RSI
bool rsiBuy  = RSI[1] <= RSI_Oversold;
bool rsiSell = RSI[1] >= RSI_Overbought;

   //ADX
   bool adxTrend = ADX[1] > ADX_Filter;

   //VOL
   bool strongVol = VOL[1] > Volume_Filter;

//&& rsiBuy && adxTrend && strongVol &&HigherTF_Bullish()
   if(buySignal && rsiBuy && adxTrend && strongVol && HigherTF_Bullish())
      OpenBuy();

   if(sellSignal && rsiSell && adxTrend && strongVol &&HigherTF_Bearish())
      OpenSell();
}
//+------------------------------------------------------------------+
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
   double sl    = emaFast[1];

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
   double sl    = emaFast[1];

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

      ManageBreakeven(ticket);
      ManageReverseTP(ticket);
   }
}
//+------------------------------------------------------------------+
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
}
//+------------------------------------------------------------------+
void ManageReverseTP(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);

   if(type==POSITION_TYPE_BUY &&
      emaFast[1]<emaSlow[1] && emaFast[2]>=emaSlow[2])
      ClosePosition(ticket);

   if(type==POSITION_TYPE_SELL &&
      emaFast[1]>emaSlow[1] && emaFast[2]<=emaSlow[2])
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
