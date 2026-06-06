//+------------------------------------------------------------------+
//|   EMA Crossover EA (Clean Version)                              |
//+------------------------------------------------------------------+
#property strict
#property version   "2.10"

#include "..\lib\candlePattern\1CandlePattern.mqh"
#include "..\lib\candlePattern\2CandlePattern.mqh"
#include "..\lib\candlePattern\3CandlePattern.mqh"

//================ BASIC =================
input string ExpertTitle = "EMA_Crossover_Clean";
int MagicNumber = 14598;

//================ EMA SETTINGS =================
input group "=== EMA Settings ==="
input int FastEMA_Period = 13;
input int SlowEMA_Period = 21;

input group "=== ATR SL Settings ==="
input int ATR_Period = 14;
input double ATR_Multiplier = 2.0;

//================ TRADING SETTINGS =================
input group "=== Trading Settings ==="
input double LotSize  = 0.01;
input int TP_Points   = 500;
input int SL_Points   = 500;

//================ GLOBAL VARIABLES =================
int fastEmaHandle, slowEmaHandle, atrHandle;
double fastEma[], slowEma[], atr[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   fastEmaHandle = iMA(_Symbol, _Period, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(_Symbol, _Period, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, ATR_Period);

   if(fastEmaHandle == INVALID_HANDLE || slowEmaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Indicator handle creation failed");
      return INIT_FAILED;
   }

   ArraySetAsSeries(fastEma, true);
   ArraySetAsSeries(slowEma, true);
   ArraySetAsSeries(atr, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastEmaHandle);
   IndicatorRelease(slowEmaHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Tick Function                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   if(HasOpenPosition())
      return;

   if(!UpdateEMA())
      return;

    if(!UpdateATR())
      return;

   CheckForEntry();
}

//+------------------------------------------------------------------+
//| Update EMA Data                                                  |
//+------------------------------------------------------------------+
bool UpdateEMA()
{
   if(CopyBuffer(fastEmaHandle, 0, 0, 3, fastEma) <= 0)
      return false;

   if(CopyBuffer(slowEmaHandle, 0, 0, 3, slowEma) <= 0)
      return false;

   return true;
}

bool UpdateATR()
{
   if(CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0)
      return false;

   return true;
}

ENUM_CANDLE_SIGNAL GetCombinedSignal()
{
   int barsCount = 10; // Sufficient bars
   double open[], close[], high[], low[];
   ArrayResize(open, barsCount);
   ArrayResize(close, barsCount);
   ArrayResize(high, barsCount);
   ArrayResize(low, barsCount);
   
   for(int i = 0; i < barsCount; i++)
   {
      open[i]  = iOpen(_Symbol, _Period, i);
      close[i] = iClose(_Symbol, _Period, i);
      high[i]  = iHigh(_Symbol, _Period, i);
      low[i]   = iLow(_Symbol, _Period, i);
   }
   // Check 1 candle patterns
   ENUM_CANDLE_SIGNAL signal1 = GetCandleReversalSignal(open, close, high, low, 1, true);
   if(signal1 != SIGNAL_NONE) return signal1;
   
   // Check 2 candle patterns
   ENUM_CANDLE2_SIGNAL signal2 = GetCandle2ReversalSignal(open, high, low, close, 1, barsCount, true);
   if(signal2 == SIGNAL2_BULLISH) return SIGNAL_BULLISH;
   if(signal2 == SIGNAL2_BEARISH) return SIGNAL_BEARISH;
   
   // Check 3 candle patterns
   ENUM_CANDLE3_SIGNAL signal3 = GetCandle3ReversalSignal(open, high, low, close, 1, barsCount, true);
   if(signal3 == SIGNAL3_BULLISH) return SIGNAL_BULLISH;
   if(signal3 == SIGNAL3_BEARISH) return SIGNAL_BEARISH;
   
   return SIGNAL_NONE;
}
//+------------------------------------------------------------------+
//| Entry Logic                                                      |
//+------------------------------------------------------------------+
void CheckForEntry()
{

   ENUM_CANDLE_SIGNAL signal = GetCombinedSignal();

   double fastCurrent = fastEma[1];
   double slowCurrent = slowEma[1];

   double fastPrev = fastEma[2];
   double slowPrev = slowEma[2];

   bool bullCross = (fastPrev < slowPrev) && (fastCurrent > slowCurrent);
   bool bearCross = (fastPrev > slowPrev) && (fastCurrent < slowCurrent);

   // Debug
   Print("Fast[0]=", fastCurrent, " Slow[0]=", slowCurrent,
         " | Fast[1]=", fastPrev, " Slow[1]=", slowPrev);

   if(bullCross && signal == SIGNAL_BULLISH)
   {
      Print("BUY SIGNAL");
      OpenPosition(ORDER_TYPE_BUY);
   }
   else if(bearCross && signal == SIGNAL_BEARISH)
   {
      Print("SELL SIGNAL");
      OpenPosition(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Check Open Positions                                             |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Open Position Wrapper                                            |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type)
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, _Period, 0);

    if(currentBarTime == lastBarTime)
    return;

    lastBarTime = currentBarTime;

   double price, tp, sl;

   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      tp = price + TP_Points * _Point;
      sl = price - (atr[0] * ATR_Multiplier);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      tp = price - TP_Points * _Point;
      sl = price + (atr[0] * ATR_Multiplier);
   }

   SendOrder(type, price, tp, sl);
}

//+------------------------------------------------------------------+
//| Send Order                                                       |
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double price, double tp, double sl)
{
   if(HasOpenPosition())
      return;

   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = LotSize;
   req.type      = type;
   req.price     = price;
   req.tp        = tp;
   req.sl        = sl;
   req.magic     = MagicNumber;
   req.deviation = 10;
   req.comment   = ExpertTitle;

   if(!OrderSend(req, res))
      Print("Order FAILED: ", res.retcode);
   else
      Print("Order SUCCESS: ", res.order);
}
//+------------------------------------------------------------------+