//+------------------------------------------------------------------+
//| ATR Mean Reversion EA (Complete Version)                        |
//+------------------------------------------------------------------+
#property strict

input group "POSITION SETTINGS"
input int LotSize = 0.1;
input int Slippage = 10;
input double RiskPercent = 1.0;

input group "INDICATOR SETTINGS" input int ATR_Period = 14;
input double ATR_Multiplier = 1.5;

// Sideways detection
input int EMAPeriod = 14;
input int SlopeLookback = 14;
input double SlopeThreshold = 89;

input int meanPeriod = 50;

input group "STOP LOSS & TAKE PROFIT" input double SL_Multiplier = 1.5;
input double TP_Multiplier = 1.0;
input double TP_Gap_Multiplier = 1.0;

input group "FEATURE TOGGLES" input bool useBreakEven = false;

input group "TP SETTINGS" input bool useATR = true;
input bool useEma = false;
input bool useTrailingStop = false;

input group "SAR TRAILING" input double SAR_Step = 0.02;
input double SAR_Max = 0.2;

input group "BREAK EVEN" input double BE_Trigger_ATR = 1.0;
input double BE_Lock_ATR = 0.2;

//--- Handles
int atrHandle, maHandle, emaHandle, sarHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   maHandle = iMA(_Symbol, _Period, meanPeriod, 0, MODE_SMA, PRICE_CLOSE);
   emaHandle = iMA(_Symbol, _Period, EMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   sarHandle = iSAR(_Symbol, _Period, SAR_Step, SAR_Max);

   if (atrHandle == INVALID_HANDLE ||
       maHandle == INVALID_HANDLE ||
       emaHandle == INVALID_HANDLE ||
       sarHandle == INVALID_HANDLE)
   {
      Print("Init error: ", GetLastError());
      return (INIT_FAILED);
   }

   return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
   IndicatorRelease(maHandle);
   IndicatorRelease(emaHandle);
   IndicatorRelease(sarHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   managePosition();

   if (!isSideways())
      return;
   if (PositionsTotal() > 0)
      return;

   double atr[], ma[], close[];

   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(close, true);

   if (CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0)
      return;
   if (CopyBuffer(maHandle, 0, 0, 2, ma) <= 0)
      return;
   if (CopyClose(_Symbol, _Period, 0, 2, close) <= 0)
      return;

   double currentATR = atr[0];
   double currentMA = ma[0];
   double currentPrice = close[0];

   double deviation = MathAbs(currentPrice - currentMA);
   double threshold = currentATR * ATR_Multiplier;

   double sl, tp;

   if (useATR)
   {
      // SELL
      if (currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + (currentATR * SL_Multiplier);
         tp = currentPrice - (currentATR * TP_Multiplier);
         tradeSell(sl, tp, currentPrice);
      }

      // BUY
      if (currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - (currentATR * SL_Multiplier);
         tp = currentPrice + (currentATR * TP_Multiplier);
         tradeBuy(sl, tp, currentPrice);
      }
   }
   else if (useEma)
   {
      // SELL
      if (currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + (currentATR * SL_Multiplier);
         tp = currentMA + (currentATR * TP_Gap_Multiplier);
         tradeSell(sl, tp, currentPrice);
      }

      // BUY
      if (currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - (currentATR * SL_Multiplier);
         tp = currentMA - (currentATR * TP_Gap_Multiplier);
         tradeBuy(sl, tp, currentPrice);
      }
   }
   else if (useTrailingStop)
   {
      // SELL
      if (currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + (currentATR * SL_Multiplier);
         tp = currentMA + (currentATR * TP_Gap_Multiplier);
         tradeSell(sl, tp, currentPrice);
      }

      // BUY
      if (currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - (currentATR * SL_Multiplier);
         tp = currentMA - (currentATR * TP_Gap_Multiplier);
         tradeBuy(sl, tp, currentPrice);
      }
   }
}
//+------------------------------------------------------------------+
//| SIDEWAYS CHECK                                                   |
//+------------------------------------------------------------------+
bool isSideways()
{
    double buf[];
    ArraySetAsSeries(buf, true);

    if (CopyBuffer(emaHandle, 0, 0, SlopeLookback + 1, buf) <= 0)
    {
        Print("CopyBuffer failed: ", GetLastError());
        return true; // assume sideways on error
    }

    double slope = (buf[0] - buf[SlopeLookback]) / _Point;

    Print("EMA Slope = ", slope);

    if (slope >= SlopeThreshold)
    {
        Print("GREEN TREND UP");
        return false;
    }
    else if (slope <= -SlopeThreshold)
    {
        Print("RED TREND DOWN");
        return false;
    }

    Print("SIDEWAYS");
    return true;
}
//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                              |
//+------------------------------------------------------------------+
void managePosition()
{
   if (PositionsTotal() <= 0)
      return;

   double atr[], sar[];

   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(sar, true);

   if (CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
      return;
   if (CopyBuffer(sarHandle, 0, 0, 1, sar) <= 0)
      return;

   double currentATR = atr[0];
   double currentSAR = sar[0];

   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      int type = PositionGetInteger(POSITION_TYPE);

      double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //================ BREAK EVEN =================
      if (useBreakEven)
      {
         double trigger = currentATR * BE_Trigger_ATR;
         double lock = currentATR * BE_Lock_ATR;

         if (type == POSITION_TYPE_BUY)
         {
            if (price - openPrice >= trigger)
            {
               double newSL = openPrice + lock;
               if (newSL > sl)
                  modifySL(ticket, newSL, tp);
            }
         }
         else
         {
            if (openPrice - price >= trigger)
            {
               double newSL = openPrice - lock;
               if (newSL < sl || sl == 0)
                  modifySL(ticket, newSL, tp);
            }
         }
      }

      //================ TRAILING SAR ===============
      if (useTrailingStop)
      {
         if (type == POSITION_TYPE_BUY)
         {
            if (currentSAR > sl && currentSAR < price)
               modifySL(ticket, currentSAR, tp);
         }
         else
         {
            if (currentSAR < sl && currentSAR > price)
               modifySL(ticket, currentSAR, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MODIFY SL                                                        |
//+------------------------------------------------------------------+
void modifySL(ulong ticket, double newSL, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl = NormalizeDouble(newSL, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);

   OrderSend(request, result);
}
//+------------------------------------------------------------------+
//| BUY                                                              |
//+------------------------------------------------------------------+
void tradeBuy(double sl, double tp, double currentPrice)
{
   
double slDistance = MathAbs(currentPrice - sl);
double lot = calculateLot(slDistance);

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_BUY;
   request.symbol = _Symbol;
   request.volume = lot;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = Slippage;
   request.magic = 123456;

   OrderSend(request, result);
}
//+------------------------------------------------------------------+
//| SELL                                                             |
//+------------------------------------------------------------------+
void tradeSell(double sl, double tp, double currentPrice)
{

   double slDistance = MathAbs(currentPrice - sl);
double lot = calculateLot(slDistance);

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_SELL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = Slippage;
   request.magic = 123456;

   OrderSend(request, result);
}
//+------------------------------------------------------------------+
double calculateLot(double slPriceDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double valuePerPoint = tickValue / tickSize;

   double slPoints = slPriceDistance / _Point;

   if (slPoints <= 0)
      return LotSize;

   double lot = riskMoney / (slPoints * valuePerPoint);

   //================ NORMALISASI =================
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;

   //================ RULE KAMU =================
   if (lot < minLot)
      lot = minLot;

   // safety tambahan (biar ga over)
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (lot > maxLot)
      lot = maxLot;

   return NormalizeDouble(lot, 2);
}
//+------------------------------------------------------------------+
double OnTester()
{
   double profit      = TesterStatistics(STAT_PROFIT);
   double drawdown    = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades      = TesterStatistics(STAT_TRADES);
   double sharpe      = TesterStatistics(STAT_SHARPE_RATIO);

   //================ SAFETY =================
   if (trades < 50)        
      return -1000;

   if (drawdown <= 0)
      return -1000;

   //================ NORMALISASI =================
   double ddFactor     = 1.0 / drawdown;     
   double tradeFactor  = MathLog(trades);    
   double sharpeFactor = sharpe;

   //================ FINAL SCORE =================
   double score = (profit * ddFactor) * sharpeFactor * tradeFactor;

   return score;
}