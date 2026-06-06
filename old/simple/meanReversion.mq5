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
input int MagicNumber = 123456;

//--- handles
int atrHandle;
int maHandle;
int emaHandle;

struct VirtualSL
{
    ulong ticket;
    double sl;
    double tp;
};
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
    atrHandle = iATR(_Symbol, _Period, ATR_Period);
    maHandle = iMA(_Symbol, _Period, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
    emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

    if (atrHandle == INVALID_HANDLE || maHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE)
    {
        Print("Init error: ", GetLastError());
        return (INIT_FAILED);
    }

    ArrayResize(vsl, 0);

    return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(atrHandle);
    IndicatorRelease(maHandle);
    IndicatorRelease(emaHandle);
}
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

    if (currentBar != lastBar)
    {
        lastBar = currentBar;
        return true;
    }

    return false;
}
//+------------------------------------------------------------------+
void OnTick()
{
    if (!IsNewBar())
        return;

    CheckVirtualStops();

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

    // SELL
    if (currentPrice > currentMA && deviation > threshold)
    {
        sl = currentPrice + (currentATR * SL_Multiplier);
        tp = currentPrice - (currentATR * TP_Multiplier);
        tradeSell(sl, tp);
    }

    // BUY
    if (currentPrice < currentMA && deviation > threshold)
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

    if (CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0)
        return false;

    double ema_diff = MathAbs(ema[0] - ema[1]);
    double buffer_price = Sideways_Buffer * _Point;

    return (ema_diff <= buffer_price);
}
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
    double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double prevLow = iLow(_Symbol, PERIOD_CURRENT, 1);

    for (int i = ArraySize(vsl) - 1; i >= 0; i--)
    {
        if (!PositionSelectByTicket(vsl[i].ticket))
        {
            ArrayRemove(vsl, i, 1);
            continue;
        }

        long type = PositionGetInteger(POSITION_TYPE);
        bool closeNow = false;

        if (type == POSITION_TYPE_BUY)
        {
            if (prevLow <= vsl[i].sl || prevLow >= vsl[i].tp)
                closeNow = true;
        }
        else
        {
            if (prevHigh >= vsl[i].sl || prevHigh <= vsl[i].tp)
                closeNow = true;
        }
        if (closeNow)
        {
            if (ClosePosition(vsl[i].ticket))
                ArrayRemove(vsl, i, 1);
        }
    }
}
//+------------------------------------------------------------------+
bool tradeBuy(double slPrice, double tpPrice)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.type      = ORDER_TYPE_BUY;
   request.volume    = LotSize;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl        = 0;
   request.tp        = 0;
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(!OrderSend(request, result))
      return false;

   if(result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      AddVirtualSL(result.order, slPrice, tpPrice);
      return true;
   }

   return false;
}
//+------------------------------------------------------------------+
bool tradeSell(double slPrice, double tpPrice)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.type      = ORDER_TYPE_SELL;
   request.volume    = LotSize;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl        = 0;
   request.tp        = 0;
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(!OrderSend(request, result))
      return false;

   if(result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      AddVirtualSL(result.order, slPrice, tpPrice);
      return true;
   }

   return false;
}
//+------------------------------------------------------------------+
void AddVirtualSL(ulong ticket, double sl, double tp)
{
    int size = ArraySize(vsl);
    ArrayResize(vsl, size + 1);

    vsl[size].ticket = ticket;
    vsl[size].sl = NormalizeDouble(sl, _Digits);
    vsl[size].tp = NormalizeDouble(tp, _Digits);
}
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   long type = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = _Symbol;
   request.volume    = PositionGetDouble(POSITION_VOLUME);
   request.deviation = Slippage;
   request.magic     = MagicNumber;

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

   if(!OrderSend(request, result))
      return false;

   return (result.retcode == TRADE_RETCODE_DONE ||
           result.retcode == TRADE_RETCODE_DONE_PARTIAL);
}