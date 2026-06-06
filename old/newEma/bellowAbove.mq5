//+------------------------------------------------------------------+
//|        ATR Mean Reversion EA (EMA Sideways Inline)              |
//+------------------------------------------------------------------+
#property strict

input double LotSize = 0.01;
input int Slippage = 10;
input double RiskPercent = 1.0;

input int period = 50;

// --- sideways params
input int EMA_Period = 34;
input double Sideways_Buffer = 155;

input double ATR_Multiplier = 1.5;

//--- handles
int atrHandle;
int maHandle;
int sidewayHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle     = iATR(_Symbol, _Period, period);
   maHandle      = iMA(_Symbol, _Period, period, 0, MODE_SMA, PRICE_CLOSE);
   sidewayHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(atrHandle == INVALID_HANDLE ||
      maHandle == INVALID_HANDLE ||
      sidewayHandle == INVALID_HANDLE)
   {
      Print("Init error: ", GetLastError());
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
   IndicatorRelease(maHandle);
   IndicatorRelease(sidewayHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if (!isNewBar())
      return;
   if(isSideways())
      return;

   double atr[], ma[], close[];

   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0)
      return;

   if(CopyBuffer(maHandle, 0, 0, 2, ma) <= 0)
      return;

   if(CopyClose(_Symbol, _Period, 0, 2, close) <= 0)
      return;

   double currentATR   = atr[0];
   double currentMA    = ma[0];
   double currentPrice = close[0];

   double range     = MathAbs(currentPrice - currentMA);
   double threshold = currentATR * ATR_Multiplier;

   double sl;

   // SELL
   if(currentPrice < currentMA && range > threshold)
   {
      if(hasPosition(POSITION_TYPE_SELL))
         return;

      if(hasPosition(POSITION_TYPE_BUY))
         closePositions();

      sl = currentPrice + threshold;

      double slDistance = MathAbs(currentPrice - sl);
      double lot = calculateLot(slDistance);

      tradeSell(0, 0.01);
      return;
   }

   // BUY
   if(currentPrice > currentMA && range > threshold)
   {
      if(hasPosition(POSITION_TYPE_BUY))
         return;

      if(hasPosition(POSITION_TYPE_SELL))
         closePositions();

      sl = currentPrice - threshold;

      double slDistance = MathAbs(currentPrice - sl);
      double lot = calculateLot(slDistance);

      tradeBuy(0, 0.01);
      return;
   }
}
//+------------------------------------------------------------------+
//| SIDEWAYS FUNCTION (EMA SLOPE)                                   |
//+------------------------------------------------------------------+
bool isSideways()
{
   double sideway[];

   ArraySetAsSeries(sideway, true);

   if(CopyBuffer(sidewayHandle, 0, 0, 2, sideway) <= 0)
      return false;

   double sideway_diff = MathAbs(sideway[0] - sideway[1]);
   double buffer_price = Sideways_Buffer * _Point;

   return (sideway_diff <= buffer_price);
}
//+------------------------------------------------------------------+
//| CHECK POSITION TYPE                                              |
//+------------------------------------------------------------------+
bool hasPosition(ENUM_POSITION_TYPE type)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         return true;
   }

   return false;
}
//+------------------------------------------------------------------+
void tradeBuy(double sl, double lot)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.type      = ORDER_TYPE_BUY;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl        = NormalizeDouble(sl, _Digits);
   request.deviation = Slippage;
   request.magic     = 123456;

   if(!OrderSend(request, result))
      Print("BUY failed: ", result.retcode);
}
//+------------------------------------------------------------------+
void tradeSell(double sl, double lot)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action    = TRADE_ACTION_DEAL;
   request.type      = ORDER_TYPE_SELL;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl        = NormalizeDouble(sl, _Digits);
   request.deviation = Slippage;
   request.magic     = 123456;

   if(!OrderSend(request, result))
      Print("SELL failed: ", result.retcode);
}
//+------------------------------------------------------------------+
double calculateLot(double slPriceDistance)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double valuePerPoint = tickValue / tickSize;

   double slPoints = slPriceDistance / _Point;

   if(slPoints <= 0)
      return LotSize;

   double lot = riskMoney / (slPoints * valuePerPoint);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lotStep) * lotStep;

   if(lot < minLot)
      lot = minLot;

   if(lot > maxLot)
      lot = maxLot;

   return NormalizeDouble(lot, 2);
}
//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS ON CURRENT SYMBOL                           |
//+------------------------------------------------------------------+
void closePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double volume = PositionGetDouble(POSITION_VOLUME);

      MqlTradeRequest request;
      MqlTradeResult result;

      ZeroMemory(request);
      ZeroMemory(result);

      request.action    = TRADE_ACTION_DEAL;
      request.position  = ticket;
      request.symbol    = _Symbol;
      request.volume    = volume;
      request.deviation = Slippage;
      request.magic     = 123456;

      if(type == POSITION_TYPE_BUY)
      {
         request.type  = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         request.type  = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }

      if(!OrderSend(request, result))
         Print("Close failed ticket ", ticket, " retcode=", result.retcode);
   }
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| NEW BAR DETECTOR                                                 |
//+------------------------------------------------------------------+
bool isNewBar()
{
   static datetime lastBarTime = 0;

   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}