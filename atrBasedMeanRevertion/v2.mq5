//+------------------------------------------------------------------+
//| ATR Mean Reversion PRO (No Library - Fixed Version)             |
//+------------------------------------------------------------------+
#property strict

//--- INPUT
input double RiskPercent = 1.0;
input double FixedLot = 0.1;
input bool UseRisk = false;

input int ATR_Period = 14;
input int MA_Period = 50;
input int EMA_Period = 34;

input double ATR_Multiplier = 1.5;
input double SL_Multiplier = 1.5;
input double TP_Multiplier = 1.0;

input int RSI_Period = 14;
input double RSI_OB = 70;
input double RSI_OS = 30;

input ENUM_TIMEFRAMES HTF = PERIOD_H1;

input double Sideways_Buffer = 155;
input double ATR_Contraction = 0.8;

input int CooldownSeconds = 300;
input int MaxSpread = 200;
input int Slippage = 10;

input bool UseBreakEven = true;
input double BE_ATR = 1.0;

//--- HANDLES
int atrHandle, maHandle, emaHandle, rsiHandle;

//--- GLOBAL
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    atrHandle = iATR(_Symbol, _Period, ATR_Period);
    maHandle = iMA(_Symbol, _Period, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
    emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);

    if (atrHandle == INVALID_HANDLE || maHandle == INVALID_HANDLE ||
        emaHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
    {
        Print("Init error: ", GetLastError());
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnTick()
{
    if (!isSpreadOK())
        return;
    if (!isCooldown())
        return;
    if (!isSideways())
        return;

    if (PositionsTotal() > 0)
    {
        managePosition();
        return;
    }

    double atr[], ma[], close[], rsi[];

    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(ma, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(rsi, true);

    if (CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0)
        return;
    if (CopyBuffer(maHandle, 0, 0, 2, ma) <= 0)
        return;
    if (CopyClose(_Symbol, _Period, 0, 2, close) <= 0)
        return;
    if (CopyBuffer(rsiHandle, 0, 0, 2, rsi) <= 0)
        return;

    double currentATR = atr[0];
    double currentMA = ma[0];
    double price = close[0];
    double currentRSI = rsi[0];

    double deviation = MathAbs(price - currentMA);
    double threshold = currentATR * ATR_Multiplier;

    double sl, tp;
    double lot = calculateLot(currentATR);

    int htfHandle = iMA(_Symbol, HTF, MA_Period, 0, MODE_SMA, PRICE_CLOSE);

    double htfMA_arr[];
    ArraySetAsSeries(htfMA_arr, true);

    if (CopyBuffer(htfHandle, 0, 0, 1, htfMA_arr) <= 0)
        return;

    double htfMA = htfMA_arr[0];

    // SELL
    if (price > currentMA && deviation > threshold && currentRSI > RSI_OB && price < htfMA)
    {
        sl = price + currentATR * SL_Multiplier;
        tp = price - currentATR * TP_Multiplier;
        tradeSell(lot, sl, tp);
    }
    // BUY
    else if (price < currentMA && deviation > threshold && currentRSI < RSI_OS && price > htfMA)
    {
        sl = price - currentATR * SL_Multiplier;
        tp = price + currentATR * TP_Multiplier;
        tradeBuy(lot, sl, tp);
    }
}
//+------------------------------------------------------------------+
bool isSideways()
{
    double ema[2], atr[20];

    ArraySetAsSeries(ema, true);
    ArraySetAsSeries(atr, true);

    if (CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0)
        return false;
    if (CopyBuffer(atrHandle, 0, 0, 20, atr) <= 0)
        return false;

    double ema_diff = MathAbs(ema[0] - ema[1]);
    double buffer_price = Sideways_Buffer * _Point;

    double atr_avg = 0;
    for (int i = 0; i < 20; i++)
        atr_avg += atr[i];
    atr_avg /= 20;

    return (ema_diff <= buffer_price && atr[0] < atr_avg * ATR_Contraction);
}
//+------------------------------------------------------------------+
double calculateLot(double atr)
{
    if (!UseRisk)
        return FixedLot;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = balance * RiskPercent / 100.0;

    double sl_distance = atr * SL_Multiplier;
    double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

    if (sl_distance == 0 || tickvalue == 0)
        return FixedLot;

    double lot = risk / (sl_distance / _Point * tickvalue);

    return NormalizeDouble(lot, 2);
}
//+------------------------------------------------------------------+
void managePosition()
{
    if (!UseBreakEven)
        return;

    double atr[];
    ArraySetAsSeries(atr, true);
    if (CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
        return;

    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket))
            continue;

        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);

        int type = (int)PositionGetInteger(POSITION_TYPE);

        double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        double profit_distance = MathAbs(price - open);

        if (profit_distance > atr[0] * BE_ATR)
        {
            MqlTradeRequest req;
            MqlTradeResult res;

            ZeroMemory(req);
            ZeroMemory(res);

            req.action = TRADE_ACTION_SLTP;
            req.position = ticket;
            req.symbol = _Symbol;
            req.sl = open;
            req.tp = tp;

            OrderSend(req, res);
        }
    }
}
//+------------------------------------------------------------------+
bool isSpreadOK()
{
    int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    return (spread <= MaxSpread);
}
//+------------------------------------------------------------------+
bool isCooldown()
{
    return (TimeCurrent() - lastTradeTime > CooldownSeconds);
}
//+------------------------------------------------------------------+
void tradeBuy(double lot, double sl, double tp)
{
    MqlTradeRequest request;
    MqlTradeResult result;

    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.type = ORDER_TYPE_BUY;
    request.symbol = _Symbol;
    request.volume = lot;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = NormalizeDouble(tp, _Digits);
    request.deviation = Slippage;

    if (OrderSend(request, result))
        lastTradeTime = TimeCurrent();
    else
        Print("BUY failed: ", result.retcode);
}
//+------------------------------------------------------------------+
void tradeSell(double lot, double sl, double tp)
{
    MqlTradeRequest request;
    MqlTradeResult result;

    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.type = ORDER_TYPE_SELL;
    request.symbol = _Symbol;
    request.volume = lot;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = NormalizeDouble(tp, _Digits);
    request.deviation = Slippage;

    if (OrderSend(request, result))
        lastTradeTime = TimeCurrent();
    else
        Print("SELL failed: ", result.retcode);
}
//+------------------------------------------------------------------+