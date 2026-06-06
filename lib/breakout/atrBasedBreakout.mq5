//+------------------------------------------------------------------+
//|        ATR Breakout EA - IMPROVED & STABLE VERSION (MQL5)        |
//+------------------------------------------------------------------+
#property strict

input double LotSize = 0.1;
input int ATR_Period = 14;
input double ATR_Multiplier = 1.2;
input double SL_Multiplier = 1.5;
input double TP_Multiplier = 3.5;
input int Slippage = 10;
input int MagicNumber = 222222;

// Filter tambahan
input int MaxSpread = 20;        // dalam points
input int StartHour = 7;
input int EndHour   = 20;
input int CooldownSeconds = 300;

int atrHandle, emaHandle;
double ema[];

datetime lastBarTime = 0;
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   emaHandle = iMA(_Symbol, _Period, 34, 0, MODE_EMA, PRICE_CLOSE);

   ArraySetAsSeries(ema, true);

   if(atrHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
   {
      Print("Indicator init failed");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
bool isBullish()
{
   if(CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0)
      return false;

   return ema[0] > ema[1];
}
//+------------------------------------------------------------------+
bool isBearish()
{
   if(CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0)
      return false;

   return ema[0] < ema[1];
}
//+------------------------------------------------------------------+
bool isSideways()
{
   if(CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0)
      return false;

   double diff = MathAbs(ema[0] - ema[1]);
   return (diff < 50 * _Point);
}
//+------------------------------------------------------------------+
bool isValidTime()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);

   int hour = timeStruct.hour;

   return (hour >= StartHour && hour <= EndHour);
}
//+------------------------------------------------------------------+
void OnTick()
{
/*
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;

   if(Bars(_Symbol, _Period) < 50)
      return;

   if(!isValidTime())
      return;

   if(isSideways())
      return;

   if(PositionSelect(_Symbol))
      return;

   if(TimeCurrent() - lastTradeTime < CooldownSeconds)
      return;
*/
   double atr[], high[], low[];

   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0)
      return;

   if(CopyHigh(_Symbol, _Period, 0, 2, high) <= 0)
      return;

   if(CopyLow(_Symbol, _Period, 0, 2, low) <= 0)
      return;

   double currentATR = atr[0];

   double prevHigh = high[1];
   double prevLow  = low[1];

   double buyLevel  = prevHigh + (currentATR * ATR_Multiplier);
   double sellLevel = prevLow  - (currentATR * ATR_Multiplier);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp;

   // BUY
   if(ask > buyLevel && isBullish())
   {
      sl = ask - (currentATR * SL_Multiplier);
      tp = ask + (currentATR * TP_Multiplier);

      if(tradeBuy(sl, tp))
         lastTradeTime = TimeCurrent();
   }

   // SELL
   if(bid < sellLevel && isBearish())
   {
      sl = bid + (currentATR * SL_Multiplier);
      tp = bid - (currentATR * TP_Multiplier);

      if(tradeSell(sl, tp))
         lastTradeTime = TimeCurrent();
   }
}
//+------------------------------------------------------------------+
bool tradeBuy(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_BUY;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request, result))
   {
      Print("BUY FAILED: ", result.retcode);
      return false;
   }

   Print("BUY OPENED");
   return true;
}
//+------------------------------------------------------------------+
bool tradeSell(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_SELL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request, result))
   {
      Print("SELL FAILED: ", result.retcode);
      return false;
   }

   Print("SELL OPENED");
   return true;
}
//+------------------------------------------------------------------+