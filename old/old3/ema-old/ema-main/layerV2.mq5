//+------------------------------------------------------------------+
//| EMA Crossover + Breakout + ATR Expansion EA                      |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"

input string Inp_Expert_Title = "Expert_EMA_EDGE";
int Expert_MagicNumber = 14598;

//================ EMA =================
input int FastEMA_Period = 13;
input int SlowEMA_Period = 21;

//================ RISK =================
input double lotSize = 0.01;
input double ATR_SL_Multiplier = 2.0;
input double ATR_TP_Multiplier = 1.5;

//================ FILTER =================
input double Min_ATR_Multiplier = 0.5;

//================ GLOBAL =================
int fastEmaHandle, slowEmaHandle, atrHandle;

double fastEma[], slowEma[], atrBuffer[];
MqlRates rates[];

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   fastEmaHandle = iMA(_Symbol, _Period, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(_Symbol, _Period, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle     = iATR(_Symbol, _Period, 14);

   if(fastEmaHandle == INVALID_HANDLE ||
      slowEmaHandle == INVALID_HANDLE ||
      atrHandle     == INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(fastEma, true);
   ArraySetAsSeries(slowEma, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(rates, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar())
      return;

   if(CopyBuffer(fastEmaHandle, 0, 0, 3, fastEma) < 3) return;
   if(CopyBuffer(slowEmaHandle, 0, 0, 3, slowEma) < 3) return;
   if(CopyBuffer(atrHandle, 0, 0, 10, atrBuffer) < 10) return;
   if(CopyRates(_Symbol, _Period, 0, 5, rates) < 5) return;

   CheckForEntry();
}

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
bool IsSideways(double atr)
{
   double range = rates[1].high - rates[1].low;

   if(range < atr * Min_ATR_Multiplier)
      return true;

   return false;
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(HasOpenPosition())
      return;

   double atr = atrBuffer[0];

   // ================= EMA CROSS =================
   bool bullishCross = fastEma[2] < slowEma[2] && fastEma[1] > slowEma[1];
   bool bearishCross = fastEma[2] > slowEma[2] && fastEma[1] < slowEma[1];

   // ================= ATR EXPANSION =================
   bool atrExpansion = atrBuffer[0] > atrBuffer[5];

   // ================= SIDEWAYS FILTER =================
   if(IsSideways(atr))
      return;

   // ================= BREAKOUT =================
   double close1 = rates[1].close;
   double high2  = rates[2].high;
   double low2   = rates[2].low;

   bool breakoutBuy  = close1 > high2;
   bool breakoutSell = close1 < low2;

   // ================= ENTRY =================
   if(bullishCross && atrExpansion && breakoutBuy)
      OpenBuy(atr);

   if(bearishCross && atrExpansion && breakoutSell)
      OpenSell(atr);
}

//+------------------------------------------------------------------+
void OpenBuy(double atr)
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = entry - atr * ATR_SL_Multiplier;
   double tp = entry + atr * ATR_TP_Multiplier;

   SendOrder(ORDER_TYPE_BUY, entry, sl, tp);
}

//+------------------------------------------------------------------+
void OpenSell(double atr)
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = entry + atr * ATR_SL_Multiplier;
   double tp = entry - atr * ATR_TP_Multiplier;

   SendOrder(ORDER_TYPE_SELL, entry, sl, tp);
}

//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double price, double sl, double tp)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lotSize;
   req.type      = type;
   req.price     = price;
   req.sl        = sl;
   req.tp        = tp;
   req.magic     = Expert_MagicNumber;
   req.deviation = 10;
   req.comment   = Inp_Expert_Title;

   OrderSend(req, res);
}

//+------------------------------------------------------------------+
double OnTester()
{
   double profit     = TesterStatistics(STAT_PROFIT);
   double drawdown   = TesterStatistics(STAT_EQUITY_DD);
   double trades     = TesterStatistics(STAT_TRADES);

   if(trades < 10)
      return 0;

   double recovery = (drawdown > 0) ? profit / drawdown : 0;
   double pf       = TesterStatistics(STAT_PROFIT_FACTOR);

   if(pf > 10) pf = 10;

   return (recovery * 0.6) + (pf * 0.4);
}