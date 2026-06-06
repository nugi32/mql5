//+------------------------------------------------------------------+
//|                                                   DotExampleEA   |
//|                 EMA Slope Trend / Sideways Detector             |
//+------------------------------------------------------------------+
#property strict

input group "Sideways Settings"
input color BuyDotColor = clrLime;
input color SellDotColor = clrRed;
input int DotDistance = 100;

// ===== EMA SETTINGS =====
input int EMAPeriod = 50;
input int SlopeLookback = 5;
input double SlopeThreshold = 50;

input group "Trading Settings"
input double LotSize = 0.01;
input int Slippage = 10;
input int FastEMA = 10;

input double SarStep = 0.02;
input double SarMax = 0.2;

input int atrPeriod = 14;
input double atrMultiplier = 1.0;
input ulong MagicNumber = 123456;

datetime lastBarTime = 0;
int emaHandle = INVALID_HANDLE;
int fastHandle, atrHandle, sarHandle;

//--- virtual stop
struct VirtualSL
{
    ulong ticket;
    double sl;
};
VirtualSL vsl[];

//+------------------------------------------------------------------+
//| Fungsi membuat dot                                               |
//+------------------------------------------------------------------+
void CreateDot(string name, datetime t, double price, color clr)
{
    if (ObjectFind(0, name) >= 0)
        ObjectDelete(0, name);

    ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Returns true if market is sideways, false if trending            |
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
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

    fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
    atrHandle = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
    sarHandle = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);

    if (fastHandle == INVALID_HANDLE ||
        emaHandle == INVALID_HANDLE || // ← now actually valid
        atrHandle == INVALID_HANDLE ||
        sarHandle == INVALID_HANDLE)
        return INIT_FAILED;

    ArrayResize(vsl, 0);
    return INIT_SUCCEEDED;

    Print("DotExampleEA started");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

    if (currentBar == lastBarTime)
        return;

    lastBarTime = currentBar;

    CheckVirtualStops();

    double fast[], atr[], close[], open[], high[], low[];
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);

    if (CopyBuffer(fastHandle, 0, 0, 3, fast) < 3) return;
    if (CopyBuffer(atrHandle,  0, 0, 3, atr)  < 3) return;
    if (CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3) return;
    if (CopyOpen (_Symbol, PERIOD_CURRENT, 0, 3, open)  < 3) return;
    if (CopyHigh (_Symbol, PERIOD_CURRENT, 0, 3, high)  < 3) return;
    if (CopyLow  (_Symbol, PERIOD_CURRENT, 0, 3, low)   < 3) return;

    double currentPrice = close[0];
    double m = atr[1] * 0.15;

    // =========================
    // ORIGINAL SIGNALS
    // =========================
    bool buyS1 = close[2] < fast[2] && close[1] > fast[1] + m;
    bool buyS2 = open[1]  < fast[1] - m && close[1] > fast[1] + m;
    bool buyS3 = high[2]  < fast[2] && close[1] > fast[1] + m;

    bool sellS1 = close[2] > fast[2] && close[1] < fast[1] - m;
    bool sellS2 = open[1]  > fast[1] + m && close[1] < fast[1] - m;
    bool sellS3 = low[2]   > fast[2] && close[1] < fast[1] - m;

    // =========================
    // NEW SCENARIO 1: EMA BOUNCE
    // Price is above EMA (uptrend), dips to touch EMA, 
    // then closes back above EMA — continuation buy
    // Vice versa for sell
    // =========================
    bool buyBounce  = close[2] > fast[2]           // was above EMA
                   && low[1]   <= fast[1] + m       // wick touched or near EMA
                   && close[1] > fast[1] + m;       // closed back above EMA

    bool sellBounce = close[2] < fast[2]            // was below EMA
                   && high[1]  >= fast[1] - m       // wick touched or near EMA
                   && close[1] < fast[1] - m;       // closed back below EMA

    // =========================
    // NEW SCENARIO 2: EMA REJECTION
    // Price spikes through EMA but fails — body stays on original side
    // Strong reversal/continuation signal
    // =========================
    bool buyRejection  = low[1]  < fast[1]          // wick pierced below EMA
                      && open[1] > fast[1]           // body stayed above
                      && close[1] > fast[1] + m;    // closed strong above EMA

    bool sellRejection = high[1] > fast[1]           // wick pierced above EMA
                      && open[1] < fast[1]           // body stayed below
                      && close[1] < fast[1] - m;    // closed strong below EMA

    // =========================
    // NEW SCENARIO 3: EMA RECLAIM
    // Price was below EMA for 2+ bars, then reclaims it — trend shift signal
    // =========================
    bool buyReclaim  = close[2] < fast[2]            // 2 bars ago below EMA
                    && close[1] > fast[1] + m;       // now reclaimed above

    bool sellReclaim = close[2] > fast[2]            // 2 bars ago above EMA
                    && close[1] < fast[1] - m;       // now reclaimed below

    // =========================
    // COMBINE ALL SIGNALS
    // =========================
    bool buySignal  = buyS1  || buyS2  || buyS3
                   || buyBounce || buyRejection || buyReclaim;

    bool sellSignal = sellS1 || sellS2 || sellS3
                   || sellBounce || sellRejection || sellReclaim;

    UpdateTrailingVirtualSL();
    //ManageReverseSignal(buySignal, sellSignal);

    if (HasOpenPosition()) return;
    if (isSideways())      return;

    if (buySignal)
        OpenBuy(currentPrice - atr[1] * atrMultiplier);

    if (sellSignal)
        OpenSell(currentPrice + atr[1] * atrMultiplier);

    // =========================
    // DOT LOGIC (trend only)
    // =========================
    double buf[];
    ArraySetAsSeries(buf, true);
    CopyBuffer(emaHandle, 0, 0, SlopeLookback + 1, buf);
    double slope = (buf[0] - buf[SlopeLookback]) / _Point;

    double   high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double   low1  = iLow (_Symbol, PERIOD_CURRENT, 1);
    datetime t1    = iTime(_Symbol, PERIOD_CURRENT, 1);

    if (slope >= SlopeThreshold)
    {
        double price = low1 - DotDistance * _Point;
        CreateDot("BUY_DOT_" + IntegerToString((int)t1), t1, price, BuyDotColor);
        Print("Buy dot | Signals: S1=", buyS1, " S2=", buyS2, " S3=", buyS3,
              " Bounce=", buyBounce, " Rejection=", buyRejection, " Reclaim=", buyReclaim);
    }
    else if (slope <= -SlopeThreshold)
    {
        double price = high1 + DotDistance * _Point;
        CreateDot("SELL_DOT_" + IntegerToString((int)t1), t1, price, SellDotColor);
        Print("Sell dot | Signals: S1=", sellS1, " S2=", sellS2, " S3=", sellS3,
              " Bounce=", sellBounce, " Rejection=", sellRejection, " Reclaim=", sellReclaim);
    }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(fastHandle);
    IndicatorRelease(emaHandle);
    IndicatorRelease(atrHandle);
    IndicatorRelease(sarHandle);
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
            if (prevLow <= vsl[i].sl)
                closeNow = true;
        }
        else
        {
            if (prevHigh >= vsl[i].sl)
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
bool HasOpenPosition()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);

        if (PositionSelectByTicket(ticket))
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
                PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
                return true;
        }
    }

    return false;
}
//+------------------------------------------------------------------+
void ManageReverseSignal(bool buySignal, bool sellSignal)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);

        if (!PositionSelectByTicket(ticket))
            continue;

        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

        if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
            continue;

        long type = PositionGetInteger(POSITION_TYPE);

        if (type == POSITION_TYPE_BUY && sellSignal)
            CloseAndRemove(ticket);

        if (type == POSITION_TYPE_SELL && buySignal)
            CloseAndRemove(ticket);
    }
}
//+------------------------------------------------------------------+
bool OpenBuy(double slPrice)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.type = ORDER_TYPE_BUY;
    request.volume = LotSize;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.sl = 0;
    request.tp = 0;
    request.deviation = Slippage;
    request.magic = MagicNumber;

    if (!OrderSend(request, result))
        return false;

    if (result.retcode == TRADE_RETCODE_DONE ||
        result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(result.order, slPrice);
        return true;
    }

    return false;
}
//+------------------------------------------------------------------+
bool OpenSell(double slPrice)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.type = ORDER_TYPE_SELL;
    request.volume = LotSize;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl = 0;
    request.tp = 0;
    request.deviation = Slippage;
    request.magic = MagicNumber;

    if (!OrderSend(request, result))
        return false;

    if (result.retcode == TRADE_RETCODE_DONE ||
        result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(result.order, slPrice);
        return true;
    }

    return false;
}
//+------------------------------------------------------------------+
void AddVirtualSL(ulong ticket, double sl)
{
    int size = ArraySize(vsl);
    ArrayResize(vsl, size + 1);

    vsl[size].ticket = ticket;
    vsl[size].sl = NormalizeDouble(sl, _Digits);
}
//+------------------------------------------------------------------+
void CloseAndRemove(ulong ticket)
{
    if (ClosePosition(ticket))
    {
        for (int i = ArraySize(vsl) - 1; i >= 0; i--)
        {
            if (vsl[i].ticket == ticket)
            {
                ArrayRemove(vsl, i, 1);
                break;
            }
        }
    }
}
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
    if (!PositionSelectByTicket(ticket))
        return false;

    long type = PositionGetInteger(POSITION_TYPE);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.deviation = Slippage;
    request.magic = MagicNumber;

    if (type == POSITION_TYPE_BUY)
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }
    else
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }

    if (!OrderSend(request, result))
        return false;

    return (result.retcode == TRADE_RETCODE_DONE ||
            result.retcode == TRADE_RETCODE_DONE_PARTIAL);
}
//+------------------------------------------------------------------+
void UpdateTrailingVirtualSL()
{
    double sar[];
    ArraySetAsSeries(sar, true);

    if (CopyBuffer(sarHandle, 0, 0, 3, sar) < 3)
        return;

    double sarValue = sar[1];

    for (int i = 0; i < ArraySize(vsl); i++)
    {
        ulong ticket = vsl[i].ticket;

        if (!PositionSelectByTicket(ticket))
            continue;

        long type = PositionGetInteger(POSITION_TYPE);

        // BUY POSITION
        if (type == POSITION_TYPE_BUY)
        {
            // trailing hanya naik
            if (sarValue > vsl[i].sl)
            {
                vsl[i].sl = NormalizeDouble(sarValue, _Digits);
            }
        }

        // SELL POSITION
        else if (type == POSITION_TYPE_SELL)
        {
            // trailing hanya turun
            if (sarValue < vsl[i].sl)
            {
                vsl[i].sl = NormalizeDouble(sarValue, _Digits);
            }
        }
    }
}