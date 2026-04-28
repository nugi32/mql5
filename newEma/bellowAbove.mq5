//+------------------------------------------------------------------+
//|        ATR Mean Reversion EA (EMA Sideways Inline)              |
//+------------------------------------------------------------------+
#property strict

input double LotSize = 0.01;
input int period = 50;

// --- sideways params (dari indikator)
input int EMA_Period = 34;
input double Sideways_Buffer = 155;

input double ATR_Multiplier = 1.5;
input int Slippage = 10;

//--- handles
int atrHandle;
int maHandle;
int emaHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, _Period, period);
   maHandle  = iMA(_Symbol, _Period, period, 0, MODE_SMA, PRICE_CLOSE);
   emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(atrHandle == INVALID_HANDLE || maHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
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
   IndicatorRelease(emaHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   applyTrailingStop();
   
   if(isSideways()) return;

   if(PositionsTotal() > 0) return;

   double atr[], ma[], close[];

   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0) return;
   if(CopyBuffer(maHandle, 0, 0, 2, ma) <= 0) return;
   if(CopyClose(_Symbol, _Period, 0, 2, close) <= 0) return;

   double currentATR   = atr[0];
   double currentMA    = ma[0];
   double currentPrice = close[0];

   double range = MathAbs(currentPrice - currentMA);
   double threshold = currentATR * ATR_Multiplier;

   double sl, tp;

   // SELL
   if(currentPrice < currentMA && range > threshold)
   {
      sl = currentMA;
      tradeSell(sl, 0);
   }

   // BUY
   if(currentPrice > currentMA && range > threshold)
   {
      sl = currentMA;
      tradeBuy(sl, 0);
   }
}
//+------------------------------------------------------------------+
//| SIDEWAYS FUNCTION (EMA SLOPE)                                   |
//+------------------------------------------------------------------+
bool isSideways()
{
   double ema[];

   ArraySetAsSeries(ema, true);
   ArrayResize(ema, 2);

   if(CopyBuffer(emaHandle, 0, 0, 20, ema) <= 0)
      return false;

   double ema_diff = MathAbs(ema[0] - ema[1]);
   double buffer_price = Sideways_Buffer * _Point;

   return (ema_diff <= buffer_price);
}
//+------------------------------------------------------------------+
void tradeBuy(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.type     = ORDER_TYPE_BUY;
   request.symbol   = _Symbol;
   request.volume   = LotSize;
   request.price    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= Slippage;
   request.magic    = 123456;

   if(!OrderSend(request, result))
      Print("BUY failed: ", result.retcode);
}
//+------------------------------------------------------------------+
void tradeSell(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.type     = ORDER_TYPE_SELL;
   request.symbol   = _Symbol;
   request.volume   = LotSize;
   request.price    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= Slippage;
   request.magic    = 123456;

   if(!OrderSend(request, result))
      Print("SELL failed: ", result.retcode);
}
//+------------------------------------------------------------------+
void applyTrailingStop()
{
   if(PositionsTotal() == 0) return;

   double ema[];
   ArraySetAsSeries(ema, true);

   if(CopyBuffer(emaHandle, 0, 0, 1, ema) <= 0)
      return;

   double currentEMA = ema[0];

   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double currentSL = PositionGetDouble(POSITION_SL);
      double priceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      int type = (int)PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest request;
      MqlTradeResult result;

      ZeroMemory(request);
      ZeroMemory(result);

      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = _Symbol;

      // BUY → SL naik mengikuti EMA
      if(type == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(currentEMA, _Digits);

         if(newSL > currentSL && newSL < SymbolInfoDouble(_Symbol, SYMBOL_BID))
         {
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);

            OrderSend(request, result);
         }
      }

      // SELL → SL turun mengikuti EMA
      if(type == POSITION_TYPE_SELL)
      {
         double newSL = NormalizeDouble(currentEMA, _Digits);

         if((currentSL == 0 || newSL < currentSL) && newSL > SymbolInfoDouble(_Symbol, SYMBOL_ASK))
         {
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);

            OrderSend(request, result);
         }
      }
   }
}