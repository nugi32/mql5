//+------------------------------------------------------------------+
//| EMA Crossover EA + Sideways + ATR SL + SAR Trailing              |
//+------------------------------------------------------------------+
#property strict
#property version   "1.50"

input string Inp_Expert_Title = "Expert_EMA_Layer";
int Expert_MagicNumber = 14598;

//================ EMA =================
input int EMA_Period = 13;

//================ SIDEWAYS =================
input int    period = 34;
input double Sideways_Buffer = 89;
input double sideways_range_buffer = 50;
input int ema_sideways_fast = 50;
input int ema_sideways_slow = 100;

//================ RISK =================
input double lotSize = 0.01;
input double ATR_SL_Multiplier = 2.0;
input double ATR_TP_Multiplier = 1.5;

//================ GLOBAL =================
int EmaHandle, sidewaysHandle, sidewaysEmaFastHandle, sidewaysEmaSlowHandle, sarHandle, atrHandle;


double Ema[], sidewaysBuffer[], atrBuffer[], sidewaysEmaFast[], sidewaysEmaSlow[];
MqlRates rates[];

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   EmaHandle  = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   //sideways
      sidewaysHandle = iMA(_Symbol, _Period, period, 0, MODE_EMA, PRICE_CLOSE);
      sidewaysEmaFastHandle = iMA(_Symbol, _Period, ema_sideways_fast, 0, MODE_EMA, PRICE_CLOSE);
      sidewaysEmaSlowHandle = iMA(_Symbol, _Period, ema_sideways_slow, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, 14);

   // Validate all indicator handles
   if(EmaHandle == INVALID_HANDLE ||
      sidewaysHandle == INVALID_HANDLE ||
      atrHandle == INVALID_HANDLE || 
      sidewaysEmaFastHandle == INVALID_HANDLE ||
      sidewaysEmaSlowHandle == INVALID_HANDLE)
      return INIT_FAILED;

   // Set arrays as series (latest index = 0)
   ArraySetAsSeries(Ema, true);
   ArraySetAsSeries(sidewaysBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(sidewaysEmaFast, true);
   ArraySetAsSeries(sidewaysEmaSlow, true);

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
   if(CopyBuffer(EmaHandle, 0, 0, 3, Ema) < 3) return;
   if(CopyBuffer(sidewaysHandle, 0, 0, period, sidewaysBuffer) < period) return;
   if(CopyBuffer(atrHandle, 0, 0, period, atrBuffer) < period) return;
   if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3) return;
    if(CopyBuffer(sidewaysEmaFastHandle, 0, 0, 30, sidewaysEmaFast) < 30) return;
    if(CopyBuffer(sidewaysEmaSlowHandle, 0, 0, 30, sidewaysEmaSlow) < 30) return;

   // Entry logic if market is not sideways
   if(!isSideways(period))
      CheckForEntry();

}

//------------------------------------------------------------------+
bool isSiddewaysEma()
{
   double slopeFast = sidewaysEmaFast[1] - sidewaysEmaFast[20];
   double slopeSlow = sidewaysEmaSlow[1] - sidewaysEmaSlow[20];

   double atr = atrBuffer[0];
   double slopeThreshold = atr * 0.15;

   if(MathAbs(slopeFast) < slopeThreshold && MathAbs(slopeSlow) < slopeThreshold)
      return true;

   return false;
}

//------------------------------------------------------------------+
bool isTrendingEma()
{
    double fast = sidewaysEmaFast[0];
    double slow = sidewaysEmaSlow[0];
   return fast > slow && (fast - slow) > sideways_range_buffer * _Point ||
          slow > fast && (slow - fast) > sideways_range_buffer * _Point;
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
void CheckForEntry()
{
   if(isSiddewaysEma() || !isTrendingEma())
      return;

   double atr = atrBuffer[0];
   double ema = Ema[1];

   double close1 = rates[1].close;
   double open1  = rates[1].open;
   double high1  = rates[1].high;
   double low1   = rates[1].low;

   // --- Slope filter ---
   double slope = sidewaysBuffer[0] - sidewaysBuffer[20];
   if(MathAbs(slope) < atr * 0.1) // sedikit dilonggarkan
      return;

   // --- ATR expansion (lebih fleksibel) ---
   bool atrExpansion = atrBuffer[0] >= atrBuffer[5] * 0.9;

   // --- Wick calculation ---
   double body = MathAbs(close1 - open1);
   double lowerWick = MathMin(open1, close1) - low1;
   double upperWick = high1 - MathMax(open1, close1);

   // --- EMA tolerance zone ---
   double tolerance = atr * 0.15;

   // =========================
   // 🔥 WICK CATCH LOGIC
   // =========================

   bool bullishReject = 
      (low1 <= ema + tolerance) &&        // wick nyentuh EMA
      (lowerWick > body * 1.2) &&         // wick lebih panjang dari body
      (close1 > low1 + (high1 - low1) * 0.3); // close tidak di bawah banget

   bool bearishReject = 
      (high1 >= ema - tolerance) &&
      (upperWick > body * 1.2) &&
      (close1 < high1 - (high1 - low1) * 0.3);

   // --- Entry ---
   if(atrExpansion && bullishReject)
      OpenBuy(atr);

   if(atrExpansion && bearishReject)
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
void OpenBuy(double atrValue)
{
   if(HasOpenPosition())
      return;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tp = entry + atrValue * ATR_TP_Multiplier;
   double sl = entry - atrValue * ATR_SL_Multiplier;

   SendOrder(ORDER_TYPE_BUY, entry, tp, sl);
}

//+------------------------------------------------------------------+
//| Open Sell                                                        |
//+------------------------------------------------------------------+
void OpenSell(double atrValue)
{
   if(HasOpenPosition())
      return;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp = entry - atrValue * ATR_TP_Multiplier;
    double sl = entry + atrValue * ATR_SL_Multiplier;

   SendOrder(ORDER_TYPE_SELL, entry, tp, sl);
}

//+------------------------------------------------------------------+
//| Send Order                                                       |
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double price, double tp, double sl)
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
   req.comment   = Inp_Expert_Title;
   req.tp        = tp;
   req.sl        = sl;

   OrderSend(req, res);
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