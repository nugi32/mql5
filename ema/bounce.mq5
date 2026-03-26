//+------------------------------------------------------------------+
//| EMA Crossover EA + Sideways + ATR SL + SAR Trailing              |
//+------------------------------------------------------------------+
#property strict
#property version   "1.50"

input string Inp_Expert_Title = "Expert_EMA_Crossover";
int Expert_MagicNumber = 14598;

//================ EMA =================
input int FastEMA_Period = 13;
input int SlowEMA_Period = 34;

//================ SAR =================
input bool   UseSAR_Trailing = true;
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

//================ SIDEWAYS =================
input int    period = 34;
input double Sideways_Buffer = 144;

//================ RISK =================
input double lotSize = 0.01;


//================ GLOBAL =================
int fastEmaHandle, slowEmaHandle, sidewaysHandle;
int sarHandle, atrHandle;

double atrBuffer[];
double fastEma[], slowEma[], sidewaysBuffer[];
MqlRates rates[];

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   fastEmaHandle  = iMA(_Symbol, _Period, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle  = iMA(_Symbol, _Period, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   sidewaysHandle = iMA(_Symbol, _Period, period, 0, MODE_EMA, PRICE_CLOSE);

   sarHandle = iSAR(_Symbol, _Period, SAR_Step, SAR_Max);
   atrHandle = iATR(_Symbol, _Period, 14);

   // Validate all indicator handles
   if(fastEmaHandle == INVALID_HANDLE ||
      slowEmaHandle == INVALID_HANDLE ||
      sidewaysHandle == INVALID_HANDLE ||
      sarHandle == INVALID_HANDLE ||
      atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   // Set arrays as series (latest index = 0)
   ArraySetAsSeries(fastEma, true);
   ArraySetAsSeries(slowEma, true);
   ArraySetAsSeries(sidewaysBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(rates, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Main Tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Execute logic only on new bar
   if(!IsNewBar())
      return;

   // Copy indicator buffers
   if(CopyBuffer(fastEmaHandle, 0, 0, 3, fastEma) < 3) return;
   if(CopyBuffer(slowEmaHandle, 0, 0, 3, slowEma) < 3) return;
   if(CopyBuffer(sidewaysHandle, 0, 0, period, sidewaysBuffer) < period) return;
   if(CopyBuffer(atrHandle, 0, 0, period, atrBuffer) < period) return;
   if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3) return;

   // Entry logic if market is not sideways
   if(!isSideways(period))
      CheckForEntry();
/*
   // Apply SAR trailing stop
   if(IsSARPositiveAgainstEntry())
   {
      double newSL = 0;
      TrailingParabolicSAR(_Symbol, newSL);
   }*/

         double newSL = 0;
      TrailingParabolicSAR(_Symbol, newSL);
}

//+------------------------------------------------------------------+
//| Detect New Bar                                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(_Symbol, _Period, 0);

   if(current == lastBarTime)
      return false;

   lastBarTime = current;
   return true;
}

//+------------------------------------------------------------------+
//| Sideways Market Detection                                        |
//+------------------------------------------------------------------+
bool isSideways(int length)
{
   if(length < 2)
      return false;

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
//| Entry Logic                                                      |
//+------------------------------------------------------------------+
void checkReverseCross() {
    double fast_prev2 = fastEma[2];
double slow_prev2 = slowEma[2];

double fast_prev1 = fastEma[1];
double slow_prev1 = slowEma[1];

//--- crossover conditions
bool crossUp   = (fast_prev2 <= slow_prev2 && fast_prev1 > slow_prev1);
bool crossDown = (fast_prev2 >= slow_prev2 && fast_prev1 < slow_prev1);

   // --- Entry execution ---
   if(crossUp || crossDown)
      CloseAllPositions();
}

//+------------------------------------------------------------------+
//| Entry Logic                                                      |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   // ATR value for volatility filtering
   double atr = atrBuffer[0];

   // --- Sideways filter using slope ---
   double slope = sidewaysBuffer[0] - sidewaysBuffer[20];

   if(MathAbs(slope) < atr * 0.15)
      return;

double fast_prev2 = fastEma[2];
double slow_prev2 = slowEma[2];

double fast_prev1 = fastEma[1];
double slow_prev1 = slowEma[1];

//--- crossover conditions
bool crossUp   = (fast_prev2 <= slow_prev2 && fast_prev1 > slow_prev1);
bool crossDown = (fast_prev2 >= slow_prev2 && fast_prev1 < slow_prev1);

   // --- Entry execution ---
   if(crossUp)
      OpenBuy(atr);

   if(crossDown)
      OpenSell(atr);
}

//+------------------------------------------------------------------+
//| Check Existing Positions                                         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == Expert_MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Open Buy                                                         |
//+------------------------------------------------------------------+
void OpenBuy(double sl)
{
   if(HasOpenPosition())
      return;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = entry - sl;
   double takeProfit = entry + sl;

   SendOrder(ORDER_TYPE_BUY, entry, stopLoss, takeProfit);
}

//+------------------------------------------------------------------+
//| Open Sell                                                        |
//+------------------------------------------------------------------+
void OpenSell(double sl)
{
   if(HasOpenPosition())
      return;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = entry + sl;
   double takeProfit = entry - sl;

   SendOrder(ORDER_TYPE_SELL, entry, stopLoss, takeProfit);
}

//+------------------------------------------------------------------+
//| Send Order                                                       |
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double price, double stopLoss, double takeProfit)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lotSize;
   req.type      = type;
   req.price     = price;
   req.magic     = Expert_MagicNumber;
   req.deviation = 10;
   req.sl = 0;
   req.comment   = Inp_Expert_Title;
   req.tp = takeProfit;

   OrderSend(req, res);
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

      if(PositionGetInteger(POSITION_MAGIC) != Expert_MagicNumber)
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

      if(PositionGetInteger(POSITION_MAGIC) != Expert_MagicNumber)
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

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == Expert_MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.deviation = 10;
            request.magic = Expert_MagicNumber;
            request.position = ticket;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               request.type = ORDER_TYPE_SELL;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            }
            else
            {
               request.type = ORDER_TYPE_BUY;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            }
            
            ZeroMemory(result);
            if(!OrderSend(request, result))
            {
               Print("Close position failed: ", result.retcode);
            }
         }
      }
   }
}