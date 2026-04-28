//+------------------------------------------------------------------+
//|        ATR Mean Reversion EA (EMA Sideways Inline)              |
//+------------------------------------------------------------------+
#property strict

input double LotSize = 0.01;
input int ATR_Period = 14;
input int MA_Period = 50;

// --- sideways params (dari indikator)
input int EMA_Period = 34;
input double Sideways_Buffer = 155;

input double ATR_Multiplier = 1.5;
input double SL_Multiplier = 1.5;
input double TP_Multiplier = 1.0;
input int Slippage = 10;

//--- handles
int atrHandle;
int maHandle;
int emaHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   maHandle  = iMA(_Symbol, _Period, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
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
   if(!isSideways()) return;

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

   double deviation = MathAbs(currentPrice - currentMA);
   double threshold = currentATR * ATR_Multiplier;

   double sl, tp;

   // SELL
   if(currentPrice > currentMA && deviation > threshold)
   {
      sl = currentPrice + (currentATR * SL_Multiplier);
      tp = currentPrice - (currentATR * TP_Multiplier);
      tradeSell(sl, tp);
   }

   // BUY
   if(currentPrice < currentMA && deviation > threshold)
   {
      sl = currentPrice - (currentATR * SL_Multiplier);
      tp = currentPrice + (currentATR * TP_Multiplier);
      tradeBuy(sl, tp);
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

   if(CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0)
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