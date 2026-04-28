//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== ATR SL Settings (Entry TF) ==="
input int ATRperiod = 10;

input group "=== RSI Settings (Entry TF) ==="
input int emaPeriod = 10;
input int overSold = 20;
input int overPrice = 80;

input group "=== ADX Settings (Entry TF) ==="
input int adxPeriod = 14;
input int ADX_trending = 25;

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
int    atrHandle, emaLayerHandle, rsiHandle, adxHandle;
double ATR[], emaLayer[], RSI[], ADX[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol,_Period,ATRperiod);
   emaLayerHandle = iMA(_Symbol,LAYER_TIMEFRAME,EMA_HIGH_TIMEFRAME_PERIOD,0,MODE_EMA,PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, _Period, emaPeriod, PRICE_CLOSE);
   adxHandle = iADX(_Symbol, _Period, adxPeriod);

   if(atrHandle==INVALID_HANDLE || emaLayerHandle==INVALID_HANDLE || rsiHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
      return INIT_FAILED;

ArraySetAsSeries(ATR,true);         
ArraySetAsSeries(emaLayer,true);    
ArraySetAsSeries(RSI,true); 
ArraySetAsSeries(ADX, true);        


   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
   IndicatorRelease(emaLayerHandle);
   IndicatorRelease(rsiHandle);
      IndicatorRelease(adxHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(atrHandle,0,0,3,ATR) < 3) return;
   if(CopyBuffer(emaLayerHandle,0,0,3,emaLayer) < 3) return;
   if(CopyBuffer(rsiHandle,0,0,3,RSI) < 3 ) return;
    if(CopyBuffer(adxHandle,0,0,3,ADX) < 3 ) return;

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
   if(HasOpenPosition()) return;


bool rsiBuy  = RSI[1] <= overSold;
bool rsiSell = RSI[1] >= overPrice;

  bool ADXtrending = ADX[1] >=ADX_trending;

   // ===== FINAL SIGNAL =====
   if(rsiBuy && HigherTF_Bullish() && ADXtrending)
      OpenBuy();

   if(rsiSell && HigherTF_Bearish() && ADXtrending)
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
   double sl = entry - ATR[1];

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
   double sl = entry + ATR[1];

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