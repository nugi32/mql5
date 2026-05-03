//+------------------------------------------------------------------+
//|           ATR Mean Reversion EA – OHLC Emulation                 |
//+------------------------------------------------------------------+
#property strict

input group "POSITION SETTINGS"
input double LotSize      = 0.01;
input int    Slippage     = 10;
input double RiskPercent  = 1.0;

input group "INDICATOR SETTINGS"
input int    ATR_Period        = 14;
input double ATR_Multiplier    = 1.5;
input int    Sideways_Period   = 34;
input double Sideways_Buffer   = 155;
input int    meanPeriod        = 50;

input group "STOP LOSS & TAKE PROFIT"
input double SL_Multiplier     = 1.5;
input double TP_Multiplier     = 1.0;
input double TP_Gap_Multiplier = 1.0;

input group "FEATURE TOGGLES"
input bool useBreakEven    = false;
input bool useTrailingStop = false;
input bool useATR          = true;
input bool useEma          = false;

input group "SAR TRAILING"
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

input group "BREAK EVEN"
input double BE_Trigger_ATR = 1.0;
input double BE_Lock_ATR    = 0.2;

//--- Handles
int atrHandle, maHandle, sidewayHandle, sarHandle;

//--- Virtual stop storage
struct VirtualPos
{
   ulong  ticket;
   double sl;
   double tp;
};
VirtualPos vpos[];

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle     = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   maHandle      = iMA(_Symbol, PERIOD_CURRENT, meanPeriod, 0, MODE_SMA, PRICE_CLOSE);
   sidewayHandle = iMA(_Symbol, PERIOD_CURRENT, Sideways_Period, 0, MODE_SMA, PRICE_CLOSE);
   sarHandle     = iSAR(_Symbol, PERIOD_CURRENT, SAR_Step, SAR_Max);

   if(atrHandle == INVALID_HANDLE || maHandle == INVALID_HANDLE ||
      sidewayHandle == INVALID_HANDLE || sarHandle == INVALID_HANDLE)
   {
      Print("Init error: ", GetLastError());
      return INIT_FAILED;
   }

   ArrayResize(vpos, 0);
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
   IndicatorRelease(maHandle);
   IndicatorRelease(sidewayHandle);
   IndicatorRelease(sarHandle);
}
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastTime = 0;
   datetime curTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curTime != lastTime)
   {
      lastTime = curTime;
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar())
      return;

   // 1. Close positions that were stopped out by the previous candle
   CheckVirtualStops();

   // 2. Apply trailing / breakeven on remaining positions
   ManageVirtualPositions();

   // 3. Open new trades if conditions are met
   if(!IsSideways())
      return;
   if(PositionsTotal() > 0)
      return;

   double atr[], ma[], close[], open[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);

   if(CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0) return;
   if(CopyBuffer(maHandle, 0, 0, 3, ma) <= 0) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) <= 0) return;
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, 2, open) <= 0) return;

   double currentATR  = atr[1];
   double currentMA   = ma[1];
   double signalPrice = close[1];
   double entryPrice  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double deviation   = MathAbs(signalPrice - currentMA);
   double threshold   = currentATR * ATR_Multiplier;

   double sl, tp;
   //--- Core strategy entry logic (unchanged)
   if(useATR)
   {
      if(signalPrice > currentMA && deviation > threshold) // SELL
      {
         sl = entryPrice + (currentATR * SL_Multiplier);
         tp = entryPrice - (currentATR * TP_Multiplier);
         TradeSell(sl, tp);
      }
      if(signalPrice < currentMA && deviation > threshold) // BUY
      {
         sl = entryPrice - (currentATR * SL_Multiplier);
         tp = entryPrice + (currentATR * TP_Multiplier);
         TradeBuy(sl, tp);
      }
   }
   else if(useEma)
   {
      if(signalPrice > currentMA && deviation > threshold) // SELL
      {
         sl = entryPrice + (currentATR * SL_Multiplier);
         tp = entryPrice + (currentATR * TP_Gap_Multiplier);
         TradeSell(sl, tp);
      }
      if(signalPrice < currentMA && deviation > threshold) // BUY
      {
         sl = entryPrice - (currentATR * SL_Multiplier);
         tp = entryPrice - (currentATR * TP_Gap_Multiplier);
         TradeBuy(sl, tp);
      }
   }
   else if(useTrailingStop)
   {
      if(signalPrice > currentMA && deviation > threshold) // SELL
      {
         sl = entryPrice + (currentATR * SL_Multiplier);
         tp = entryPrice + (currentATR * TP_Gap_Multiplier);
         TradeSell(sl, tp);
      }
      if(signalPrice < currentMA && deviation > threshold) // BUY
      {
         sl = entryPrice - (currentATR * SL_Multiplier);
         tp = entryPrice - (currentATR * TP_Gap_Multiplier);
         TradeBuy(sl, tp);
      }
   }
}
//+------------------------------------------------------------------+
//| Check and close positions using previous candle OHLC            |
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   // Remove stale entries
   for(int i = ArraySize(vpos) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vpos[i].ticket))
         ArrayRemove(vpos, i, 1);
   }

   // Get previous candle OHLC
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool bullish = (c1 > o1);

   for(int i = ArraySize(vpos) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vpos[i].ticket))
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double vsl = vpos[i].sl;
      double vtp = vpos[i].tp;
      bool closeNow = false;

      // Determine if SL or TP is touched and in which order
      if(type == POSITION_TYPE_BUY)
      {
         bool slHit = (l1 <= vsl && vsl > 0);
         bool tpHit = (h1 >= vtp && vtp > 0);
         if(slHit && tpHit)
         {
            // Both hit: use the sequence Open->High->Low->Close for bullish,
            // Open->Low->High->Close for bearish
            if(bullish)
               closeNow = true; // TP hit first (High reached before Low)
            else
               closeNow = true; // SL hit first (Low reached before High)
         }
         else if(slHit) closeNow = true;
         else if(tpHit) closeNow = true;
      }
      else // SELL
      {
         bool slHit = (h1 >= vsl && vsl > 0);
         bool tpHit = (l1 <= vtp && vtp > 0);
         if(slHit && tpHit)
         {
            // Bullish: Open->High->Low => SL (High) hit first
            // Bearish: Open->Low->High => TP (Low) hit first
            closeNow = true;
         }
         else if(slHit) closeNow = true;
         else if(tpHit) closeNow = true;
      }

      if(closeNow)
      {
         ClosePosition(vpos[i].ticket);
         ArrayRemove(vpos, i, 1);
      }
   }
}
//+------------------------------------------------------------------+
//| Manage breakeven and trailing using previous candle's close     |
//+------------------------------------------------------------------+
void ManageVirtualPositions()
{
   // Sync array with currently open positions
   for(int i = ArraySize(vpos) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vpos[i].ticket))
         ArrayRemove(vpos, i, 1);
   }

   if(ArraySize(vpos) == 0) return;

   double atr[1], sar[1];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(sar, true);

   // Use values from the previous completed bar (index 1)
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0) return;
   if(CopyBuffer(sarHandle, 0, 1, 1, sar) <= 0) return;

   double currentATR = atr[0];
   double currentSAR = sar[0];
   double priceClose1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   for(int i = 0; i < ArraySize(vpos); i++)
   {
      if(!PositionSelectByTicket(vpos[i].ticket))
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      long   type      = PositionGetInteger(POSITION_TYPE);
      double vsl       = vpos[i].sl;
      double vtp       = vpos[i].tp;
      double newSL     = vsl;     // will be updated if needed

      //--- BREAKEVEN (using close of previous bar)
      if(useBreakEven)
      {
         double trigger = currentATR * BE_Trigger_ATR;
         double lock    = currentATR * BE_Lock_ATR;

         if(type == POSITION_TYPE_BUY)
         {
            if(priceClose1 - openPrice >= trigger)
            {
               double candidate = openPrice + lock;
               if(candidate > vsl)
                  newSL = candidate;
            }
         }
         else
         {
            if(openPrice - priceClose1 >= trigger)
            {
               double candidate = openPrice - lock;
               if(candidate < vsl || vsl == 0)
                  newSL = candidate;
            }
         }
      }

      //--- TRAILING SAR
      if(useTrailingStop)
      {
         if(type == POSITION_TYPE_BUY)
         {
            if(currentSAR > vsl && currentSAR < priceClose1)
               newSL = currentSAR;
         }
         else
         {
            if(currentSAR < vsl && currentSAR > priceClose1)
               newSL = currentSAR;
         }
      }

      // If virtual SL changed, store it (no broker modification)
      if(newSL != vsl)
      {
         vpos[i].sl = newSL;
         // Broker SL remains 0 – stops are purely virtual
      }
   }
}
//+------------------------------------------------------------------+
bool IsSideways()
{
   double sideway[], atr[];
   ArraySetAsSeries(sideway, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(sidewayHandle, 0, 0, 5, sideway) <= 0) return false;
   if(CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0) return false;

   double sideway_diff  = MathAbs(sideway[1] - sideway[2]);
   double buffer_fixed  = Sideways_Buffer * _Point;
   double buffer_atr    = atr[1] * 0.2;
   double buffer_total  = buffer_fixed + buffer_atr;

   return (sideway_diff <= buffer_total);
}
//+------------------------------------------------------------------+
//| Manual order sending functions                                   |
//+------------------------------------------------------------------+
bool TradeBuy(double sl, double tp)
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDistance = MathAbs(entryPrice - sl);
   double lot = CalculateLot(slDistance);

   MqlTradeRequest request = {};
   MqlTradeResult  result = {};

   request.action    = TRADE_ACTION_DEAL;
   request.type      = ORDER_TYPE_BUY;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = entryPrice;
   request.sl        = 0;  // No broker SL
   request.tp        = 0;  // No broker TP
   request.deviation = Slippage;
   request.magic     = 123456;

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         ulong ticket = result.order;
         AddVirtual(ticket, sl, tp);
         return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
bool TradeSell(double sl, double tp)
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDistance = MathAbs(entryPrice - sl);
   double lot = CalculateLot(slDistance);

   MqlTradeRequest request = {};
   MqlTradeResult  result = {};

   request.action    = TRADE_ACTION_DEAL;
   request.type      = ORDER_TYPE_SELL;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = entryPrice;
   request.sl        = 0;  // No broker SL
   request.tp        = 0;  // No broker TP
   request.deviation = Slippage;
   request.magic     = 123456;

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         ulong ticket = result.order;
         AddVirtual(ticket, sl, tp);
         return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   MqlTradeRequest request = {};
   MqlTradeResult  result = {};

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = _Symbol;
   request.volume    = PositionGetDouble(POSITION_VOLUME);
   request.deviation = Slippage;
   request.magic     = 123456;

   long type = PositionGetInteger(POSITION_TYPE);
   if(type == POSITION_TYPE_BUY)
   {
      request.type   = ORDER_TYPE_SELL;
      request.price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      request.type   = ORDER_TYPE_BUY;
      request.price  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   return OrderSend(request, result);
}
//+------------------------------------------------------------------+
void AddVirtual(ulong ticket, double sl, double tp)
{
   int size = ArraySize(vpos);
   ArrayResize(vpos, size + 1);
   vpos[size].ticket = ticket;
   vpos[size].sl     = sl;
   vpos[size].tp     = tp;
}
//+------------------------------------------------------------------+
double CalculateLot(double slPriceDistance)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney  = balance * (RiskPercent / 100.0);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPoint = tickValue / tickSize;
   double slPoints = slPriceDistance / _Point;
   if(slPoints <= 0) return LotSize;

   double lot = riskMoney / (slPoints * valuePerPoint);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}
//+------------------------------------------------------------------+
double OnTester()
{
   double profit   = TesterStatistics(STAT_PROFIT);
   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades   = TesterStatistics(STAT_TRADES);
   double sharpe   = TesterStatistics(STAT_SHARPE_RATIO);
   if(trades < 50)        return -1000;
   if(drawdown <= 0)      return -1000;
   double ddFactor     = 1.0 / drawdown;
   double tradeFactor  = MathLog(trades);
   double sharpeFactor = sharpe;
   double score = (profit * ddFactor) * sharpeFactor * tradeFactor;
   return score;
}
//+------------------------------------------------------------------+