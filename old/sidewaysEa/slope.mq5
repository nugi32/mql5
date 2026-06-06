//+------------------------------------------------------------------+
//|                                                   DotExampleEA   |
//|                 EMA Slope Trend / Sideways Detector             |
//+------------------------------------------------------------------+
#property strict

input color  BuyDotColor    = clrLime;
input color  SellDotColor   = clrRed;
input int    DotDistance    = 100;

// ===== EMA SETTINGS =====
input int    EMAPeriod      = 50;
input int    SlopeLookback  = 5;
input double SlopeThreshold = 50; // in points

datetime lastBarTime = 0;
int      emaHandle   = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Fungsi membuat dot                                               |
//+------------------------------------------------------------------+
void CreateDot(string name, datetime t, double price, color clr)
{
    if (ObjectFind(0, name) >= 0)
        ObjectDelete(0, name);

    ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
}

//+------------------------------------------------------------------+
//| Hitung slope EMA                                                 |
//+------------------------------------------------------------------+
double GetEMASlope()
{
    // MQL5: CopyBuffer reads from newest→oldest, index 0 = most recent bar
    double buf[];
    ArraySetAsSeries(buf, true);

    // We need SlopeLookback+1 bars: index 0 (now) and index SlopeLookback (past)
    if (CopyBuffer(emaHandle, 0, 0, SlopeLookback + 1, buf) <= 0)
    {
        Print("CopyBuffer failed: ", GetLastError());
        return 0.0;
    }

    double emaNow  = buf[0];
    double emaPast = buf[SlopeLookback];

    return (emaNow - emaPast) / _Point;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    // MQL5: create handle once on init — 6 params, no shift param
    emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

    if (emaHandle == INVALID_HANDLE)
    {
        Print("Failed to create EMA handle: ", GetLastError());
        return INIT_FAILED;
    }

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

    // =========================
    // EMA SLOPE DETECTION
    // =========================
    double slope = GetEMASlope();

    double   high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double   low1  = iLow (_Symbol, PERIOD_CURRENT, 1);
    datetime t1    = iTime(_Symbol, PERIOD_CURRENT, 1);

    // BULLISH SLOPE → buy dot below previous candle
    if (slope >= SlopeThreshold)
    {
        double price = low1 - DotDistance * _Point;
        CreateDot("BUY_DOT_" + IntegerToString((int)t1), t1, price, BuyDotColor);
        Print("GREEN TREND UP  | EMA Slope = ", slope, " → Buy dot created");
    }
    // BEARISH SLOPE → sell dot above previous candle
    else if (slope <= -SlopeThreshold)
    {
        double price = high1 + DotDistance * _Point;
        CreateDot("SELL_DOT_" + IntegerToString((int)t1), t1, price, SellDotColor);
        Print("RED TREND DOWN  | EMA Slope = ", slope, " → Sell dot created");
    }
    // SIDEWAYS → no dot
    else
    {
        Print("SIDEWAYS        | EMA Slope = ", slope, " → No dot");
    }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if (emaHandle != INVALID_HANDLE)
        IndicatorRelease(emaHandle);

    Print("DotExampleEA stopped");
}