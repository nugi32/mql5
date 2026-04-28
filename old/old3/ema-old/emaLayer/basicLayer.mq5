//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== EMA Signal Settings ==="
input int EMA_Fast_Period = 13;
input int EMA_Slow_Period = 21;

input group "=== Trend Filter ==="
input int fastTrendPeriod = 50;
input int slowTrendPeriod = 100;
input double emaTrendDiffRange = 50;
input bool Use_Trend_Filter = true;

//================ SIDEWAYS =================
input int    period = 34;
input double Sideways_Buffer = 144;
input int   emaSidewaysDiffRange = 50;

//================ SAR =================
input bool   UseSAR_Trailing = true;
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

//================ ATR =================
input int    ATR_Period = 14;

input group "=== Trading Settings ==="
input double Lot_Size = 0.01;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross";

//================ GLOBAL =================
int    emaFastHandle, emaSlowHandle, emaTrendFastHandle, emaTrendSlowHandle, sidewaysHandle, sarHandle, atrHandle;
double emaFast[], emaSlow[], emaTrendFast[], emaTrendSlow[], sidewaysBuffer[], atrBuffer[];
MqlRates rates[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   emaFastHandle = iMA(_Symbol,_Period,EMA_Fast_Period,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol,_Period,EMA_Slow_Period,0,MODE_EMA,PRICE_CLOSE);
   emaTrendFastHandle = iMA(_Symbol,_Period,fastTrendPeriod,0,MODE_EMA,PRICE_CLOSE);
   emaTrendSlowHandle = iMA(_Symbol,_Period,slowTrendPeriod,0,MODE_EMA,PRICE_CLOSE);
   sidewaysHandle = iMA(_Symbol, _Period, period, 0, MODE_EMA, PRICE_CLOSE);

      sarHandle = iSAR(_Symbol, _Period, SAR_Step, SAR_Max);
   atrHandle = iATR(_Symbol, _Period, ATR_Period);

   if(sidewaysHandle==INVALID_HANDLE || emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE || emaTrendFastHandle==INVALID_HANDLE || emaTrendSlowHandle==INVALID_HANDLE || sarHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(emaFast,true);
   ArraySetAsSeries(emaSlow,true);
   ArraySetAsSeries(emaTrendFast,true);
   ArraySetAsSeries(emaTrendSlow,true);
   ArraySetAsSeries(sidewaysBuffer,true);
   ArraySetAsSeries(atrBuffer,true);
   ArraySetAsSeries(rates, true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(emaTrendFastHandle);
   IndicatorRelease(emaTrendSlowHandle);
   IndicatorRelease(sidewaysHandle);
   IndicatorRelease(sarHandle);
   IndicatorRelease(atrHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(emaFastHandle,0,0,3,emaFast) < 3) return;
   if(CopyBuffer(emaSlowHandle,0,0,3,emaSlow) < 3) return;
   if(CopyBuffer(sidewaysHandle, 0, 0, period, sidewaysBuffer) < period) return;
   if(CopyBuffer(atrHandle,0,0,period,atrBuffer) < period) return; // ⚠️ ubah ini juga!
   if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3) return;

   if(Use_Trend_Filter)
   {
      if(CopyBuffer(emaTrendFastHandle,0,0,3,emaTrendFast) < 3) return;
      if(CopyBuffer(emaTrendSlowHandle,0,0,3,emaTrendSlow) < 3) return;
   }

   if(isSideways(period)) return;

   CheckForEntry();

   double newSL = 0;
   TrailingParabolicSAR(_Symbol, newSL);
}
//+------------------------------------------------------------------+
bool isSideways(int length)
{
   if(length < 2) return false;

   if(ArraySize(sidewaysBuffer) < length) return false;
   if(ArraySize(atrBuffer) < length) return false;

   for(int i = 1; i < length - 1; i++)
   {
      double diff = MathAbs(sidewaysBuffer[i] - sidewaysBuffer[i + 1]);
      double buffer_price = Sideways_Buffer * _Point;

      bool atr_down = atrBuffer[i] < atrBuffer[i - 1];

      if(diff > buffer_price)
         return false;

      if(diff <= buffer_price && atr_down)
         return true;
   }

   return false;
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
bool Trending() 
{
   if(!Use_Trend_Filter) return true;

   return emaTrendFast[1] > emaTrendSlow[1] && (emaTrendFast[1] - emaTrendSlow[1]) > (emaTrendDiffRange * _Point) ||
          emaTrendFast[1] < emaTrendSlow[1] && (emaTrendSlow[1] - emaTrendFast[1]) > (emaTrendDiffRange * _Point);
}
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(HasOpenPosition()) return;
   if(!Trending()) return;

   bool bullBounce = rates[1].low < emaFast[1] && rates[1].close > emaFast[1];
   bool bearBounce = rates[1].high > emaFast[1] && rates[1].close < emaFast[1];

   bool buySignal  = emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2];
   bool sellSignal = emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2];

   if(bullBounce)
      OpenBuy();

   if(bearBounce)
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

   SendOrder(ORDER_TYPE_BUY,entry,0,0);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   SendOrder(ORDER_TYPE_SELL,entry,0,0);
}

//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = Lot_Size;
   req.price    = price;
   req.sl       = sl;
   req.tp       = tp;
   req.magic    = Magic_Number;
   req.comment  = Trade_Comment;
   req.deviation= 10;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
//| Parabolic SAR Trailing                                           |
//+------------------------------------------------------------------+
bool TrailingParabolicSAR(string symbol, double &newSL)
{
   if(PositionsTotal() == 0)
      return false;

   double sar[];
   ArraySetAsSeries(sar, true);

   if(CopyBuffer(sarHandle, 0, 1, 1, sar) < 1)
      return false;

   double sarValue = sar[0];

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      long type       = PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         if(sarValue > currentSL && sarValue < bid)
            newSL = sarValue;
         else
            continue;
      }
      else
      {
         if((currentSL == 0 || sarValue < currentSL) && sarValue > ask)
            newSL = sarValue;
         else
            continue;
      }

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = symbol;
      req.sl       = newSL;
      req.tp       = tp;

      OrderSend(req, res);
   }

   return true;
}

//+------------------------------------------------------------------+
//| SAR Position Validation                                          |
//+------------------------------------------------------------------+
bool IsSARPositiveAgainstEntry()
{
   if(PositionsTotal() == 0)
      return false;

   double sar[];
   ArraySetAsSeries(sar, true);

   if(CopyBuffer(sarHandle, 0, 1, 1, sar) < 1)
      return false;

   double sarValue = sar[0];

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long type   = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);

      if(type == POSITION_TYPE_BUY)
      {
         if(sarValue > entry)
            return true;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(sarValue < entry)
            return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Custom Optimization Score                                        |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit     = TesterStatistics(STAT_PROFIT);
   double drawdown   = TesterStatistics(STAT_EQUITY_DD);
   double trades     = TesterStatistics(STAT_TRADES);
   double win_trades = TesterStatistics(STAT_PROFIT_TRADES);

   // Avoid low sample size bias
   if(trades < 10)
      return 0;

   // Recovery factor
   double recovery = 0;
   if(drawdown > 0)
      recovery = profit / drawdown;

   // Win rate
   double winrate = win_trades / trades;

   // Expected payoff
   double payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);

   // Profit factor
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);

   // Safety normalization
   if(recovery < 0) recovery = 0;
   if(pf > 10) pf = 10;

   // Final scoring formula
   double score =
      (recovery * 0.4) +
      (winrate  * 0.3) +
      (pf       * 0.2) +
      (payoff   * 0.1);

   return score;
}
