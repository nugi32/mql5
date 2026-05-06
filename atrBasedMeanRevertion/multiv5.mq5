//+------------------------------------------------------------------+
//|           ATR Mean Reversion EA – True OHLC Emulation            |
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

   // Replay the previous completed candle as a sequence of synthetic ticks
   SimulatePreviousBar();
}
//+------------------------------------------------------------------+
void SimulatePreviousBar()
{
   double o = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool bullish = (c >= o);

   if(bullish)
   {
      ProcessSyntheticPrice(o, 1);
      ProcessSyntheticPrice(l, 1);
      ProcessSyntheticPrice(h, 1);
      ProcessSyntheticPrice(c, 1);
   }
   else
   {
      ProcessSyntheticPrice(o, 1);
      ProcessSyntheticPrice(h, 1);
      ProcessSyntheticPrice(l, 1);
      ProcessSyntheticPrice(c, 1);
   }
}
//+------------------------------------------------------------------+
void ProcessSyntheticPrice(double price, int shift)
{
   // 1. Close positions that hit SL/TP at this synthetic price
   CheckVirtualStopsAtPrice(price);

   // 2. Update trailing / breakeven for remaining positions
   ManageVirtualPositionsAtPrice(price, shift);

   // 3. If no open broker position, check for new entry
   if(PositionsTotal() == 0)
      CheckEntryAtPrice(price, shift);
}
//+------------------------------------------------------------------+
void CheckVirtualStopsAtPrice(double price)
{
   for(int i = ArraySize(vpos) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vpos[i].ticket))
      {
         ArrayRemove(vpos, i, 1);
         continue;
      }

      long type = PositionGetInteger(POSITION_TYPE);
      bool closeNow = false;

      if(type == POSITION_TYPE_BUY)
      {
         if(vpos[i].sl > 0 && price <= vpos[i].sl) closeNow = true;
         if(vpos[i].tp > 0 && price >= vpos[i].tp) closeNow = true;
      }
      else // SELL
      {
         if(vpos[i].sl > 0 && price >= vpos[i].sl) closeNow = true;
         if(vpos[i].tp > 0 && price <= vpos[i].tp) closeNow = true;
      }

      if(closeNow)
      {
         Print("Virtual stop hit for ticket ", vpos[i].ticket, " at price ", price);
         if(ClosePosition(vpos[i].ticket))
         {
            Print("Successfully closed ticket ", vpos[i].ticket);
            ArrayRemove(vpos, i, 1);
         }
         else
         {
            Print("Failed to close ticket ", vpos[i].ticket);
         }
      }
   }
}
//+------------------------------------------------------------------+
void ManageVirtualPositionsAtPrice(double price, int shift)
{
   // Sync array with currently open broker positions
   for(int i = ArraySize(vpos) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vpos[i].ticket))
         ArrayRemove(vpos, i, 1);
   }

   if(ArraySize(vpos) == 0) return;

   // Use dynamic arrays to avoid warning 63
   double atr[];
   double sar[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(sar, true);

   if(CopyBuffer(atrHandle, 0, shift, 1, atr) <= 0) return;
   if(CopyBuffer(sarHandle, 0, shift, 1, sar) <= 0) return;

   double currentATR = atr[0];
   double currentSAR = sar[0];

   for(int i = 0; i < ArraySize(vpos); i++)
   {
      if(!PositionSelectByTicket(vpos[i].ticket)) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      long   type      = PositionGetInteger(POSITION_TYPE);
      double vsl       = vpos[i].sl;
      double vtp       = vpos[i].tp;
      double newSL     = vsl;

      //--- Breakeven (using current synthetic price as reference)
      if(useBreakEven)
      {
         double trigger = currentATR * BE_Trigger_ATR;
         double lock    = currentATR * BE_Lock_ATR;

         if(type == POSITION_TYPE_BUY)
         {
            if(price - openPrice >= trigger)
            {
               double candidate = openPrice + lock;
               if(candidate > vsl) newSL = candidate;
            }
         }
         else // SELL
         {
            if(openPrice - price >= trigger)
            {
               double candidate = openPrice - lock;
               if(candidate < vsl || vsl == 0) newSL = candidate;
            }
         }
      }

      //--- SAR Trailing
      if(useTrailingStop)
      {
         if(type == POSITION_TYPE_BUY)
         {
            if(currentSAR > vsl && currentSAR < price)
               newSL = currentSAR;
         }
         else
         {
            if(currentSAR < vsl && currentSAR > price)
               newSL = currentSAR;
         }
      }

      if(newSL != vsl)
      {
         Print("Virtual SL updated for ticket ", vpos[i].ticket, " from ", vsl, " to ", newSL);
         vpos[i].sl = newSL;
      }
   }
}
//+------------------------------------------------------------------+
void CheckEntryAtPrice(double price, int shift)
{
   if(!IsSideways(shift))
      return;

   // Use dynamic arrays to avoid warning 63
   double atr[];
   double ma[];
   double close[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(atrHandle, 0, shift, 1, atr) <= 0) return;
   if(CopyBuffer(maHandle,  0, shift, 1, ma) <= 0) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, shift, 1, close) <= 0) return;

   double currentATR  = atr[0];
   double currentMA   = ma[0];
   double signalPrice = close[0];

   double deviation = MathAbs(signalPrice - currentMA);
   double threshold = currentATR * ATR_Multiplier;

   double sl, tp;

   if(useATR)
   {
      // SELL signal
      if(signalPrice > currentMA && deviation > threshold)
      {
         sl = price + (currentATR * SL_Multiplier);
         tp = price - (currentATR * TP_Multiplier);
         TradeSell(price, sl, tp);
      }

      // BUY signal
      if(signalPrice < currentMA && deviation > threshold)
      {
         sl = price - (currentATR * SL_Multiplier);
         tp = price + (currentATR * TP_Multiplier);
         TradeBuy(price, sl, tp);
      }
   }
   else if(useEma)
   {
      if(signalPrice > currentMA && deviation > threshold)
      {
         sl = price + (currentATR * SL_Multiplier);
         tp = price + (currentATR * TP_Gap_Multiplier);
         TradeSell(price, sl, tp);
      }

      if(signalPrice < currentMA && deviation > threshold)
      {
         sl = price - (currentATR * SL_Multiplier);
         tp = price - (currentATR * TP_Gap_Multiplier);
         TradeBuy(price, sl, tp);
      }
   }
   else if(useTrailingStop)
   {
      if(signalPrice > currentMA && deviation > threshold)
      {
         sl = price + (currentATR * SL_Multiplier);
         tp = price + (currentATR * TP_Gap_Multiplier);
         TradeSell(price, sl, tp);
      }

      if(signalPrice < currentMA && deviation > threshold)
      {
         sl = price - (currentATR * SL_Multiplier);
         tp = price - (currentATR * TP_Gap_Multiplier);
         TradeBuy(price, sl, tp);
      }
   }
}
//+------------------------------------------------------------------+
bool IsSideways(int shift)
{
   // Use dynamic arrays to avoid warning 63
   double sideway[];
   double atr[];
   ArraySetAsSeries(sideway, true);
   ArraySetAsSeries(atr, true);

   // Use shift and shift+1 for two completed bars
   if(CopyBuffer(sidewayHandle, 0, shift, 2, sideway) <= 0) return false;
   if(CopyBuffer(atrHandle, 0, shift, 1, atr) <= 0) return false;

   double sideway_diff = MathAbs(sideway[0] - sideway[1]);
   double buffer_fixed = Sideways_Buffer * _Point;
   double buffer_atr   = atr[0] * 0.2;
   double buffer_total = buffer_fixed + buffer_atr;

   return (sideway_diff <= buffer_total);
}
//+------------------------------------------------------------------+
bool TradeBuy(double entryPrice, double sl, double tp)
{
   double slDistance = MathAbs(entryPrice - sl);
   double lot = CalculateLot(slDistance);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.type      = ORDER_TYPE_BUY;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = entryPrice;
   request.sl        = 0;
   request.tp        = 0;
   request.deviation = Slippage;
   request.magic     = 123456;

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         ulong ticket = result.order;
         // Get the actual position ticket from the deal
         if(HistoryDealSelect(ticket))
         {
            ticket = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         }
         AddVirtual(ticket, sl, tp);
         Print("Buy order opened, ticket = ", ticket);
         return true;
      }
   }
   Print("Buy order failed, retcode = ", result.retcode);
   return false;
}
//+------------------------------------------------------------------+
bool TradeSell(double entryPrice, double sl, double tp)
{
   double slDistance = MathAbs(entryPrice - sl);
   double lot = CalculateLot(slDistance);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.type      = ORDER_TYPE_SELL;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = entryPrice;
   request.sl        = 0;
   request.tp        = 0;
   request.deviation = Slippage;
   request.magic     = 123456;

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         ulong ticket = result.order;
         // Get the actual position ticket from the deal
         if(HistoryDealSelect(ticket))
         {
            ticket = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         }
         AddVirtual(ticket, sl, tp);
         Print("Sell order opened, ticket = ", ticket);
         return true;
      }
   }
   Print("Sell order failed, retcode = ", result.retcode);
   return false;
}
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("ClosePosition: cannot select ticket ", ticket);
      return false;
   }

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = _Symbol;
   request.volume    = PositionGetDouble(POSITION_VOLUME);
   request.deviation = Slippage;
   request.magic     = 123456;

   long type = PositionGetInteger(POSITION_TYPE);
   if(type == POSITION_TYPE_BUY)
   {
      request.type  = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      request.type  = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         Print("ClosePosition succeeded for ticket ", ticket);
         return true;
      }
   }
   Print("ClosePosition failed for ticket ", ticket, " retcode = ", result.retcode);
   return false;
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