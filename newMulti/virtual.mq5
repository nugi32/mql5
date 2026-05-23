//+------------------------------------------------------------------+
//| ATR Mean Reversion EA (Virtual SL + New Bar Version)            |
//+------------------------------------------------------------------+
#property strict

input group "POSITION SETTINGS"
input double LotSize = 0.1;
input int    Slippage = 10;
input double RiskPercent = 1.0;

input group "INDICATOR SETTINGS"
input int    ATR_Period = 14;
input double ATR_Multiplier = 1.5;

// Sideways detection
input int    Sideways_Period = 34;
input double Sideways_Buffer = 155;

input int    meanPeriod = 50;

input group "STOP LOSS & TAKE PROFIT"
input double SL_Multiplier = 1.5;
input double TP_Multiplier = 1.0;
input double TP_Gap_Multiplier = 1.0;

input group "FEATURE TOGGLES"
input bool   useBreakEven = false;

input group "TP SETTINGS"
input bool   useATR           = true;
input bool   useEma           = false;
input bool   useTrailingStop  = false;

input group "SAR TRAILING"
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

input group "BREAK EVEN"
input double BE_Trigger_ATR = 1.0;
input double BE_Lock_ATR    = 0.2;

//--- Handles
int atrHandle, maHandle, sidewayHandle, sarHandle;

//--- New-bar tracking (from EA1)
datetime lastBarTime = 0;

//--- Virtual stop-loss system (from EA1)
struct VirtualSL
{
    ulong  ticket;
    double sl;
};
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
    atrHandle    = iATR(_Symbol, _Period, ATR_Period);
    maHandle     = iMA(_Symbol, _Period, meanPeriod,      0, MODE_SMA, PRICE_CLOSE);
    sidewayHandle= iMA(_Symbol, _Period, Sideways_Period, 0, MODE_SMA, PRICE_CLOSE);
    sarHandle    = iSAR(_Symbol, _Period, SAR_Step, SAR_Max);

    if (atrHandle     == INVALID_HANDLE ||
        maHandle      == INVALID_HANDLE ||
        sidewayHandle == INVALID_HANDLE ||
        sarHandle     == INVALID_HANDLE)
    {
        Print("Init error: ", GetLastError());
        return INIT_FAILED;
    }

    ArrayResize(vsl, 0);
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
void OnTick()
{
    //--- NEW BAR CHECK (from EA1) — run virtual-SL check every tick,
    //    but run signal logic only on a new bar open

    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (currentBar == lastBarTime)
        return;
    lastBarTime = currentBar;

    CheckVirtualStops();
    managePosition();

    //--- From here: new-bar logic only ---

    if (!isSideways())
        return;
    if (PositionsTotal() > 0)
        return;

    double atr[], ma[], close[];

    ArraySetAsSeries(atr,   true);
    ArraySetAsSeries(ma,    true);
    ArraySetAsSeries(close, true);

    if (CopyBuffer(atrHandle, 0, 0, 2, atr)   <= 0) return;
    if (CopyBuffer(maHandle,  0, 0, 2, ma)    <= 0) return;
    if (CopyClose(_Symbol, _Period, 0, 2, close) <= 0) return;

    double currentATR   = atr[0];
    double currentMA    = ma[0];
    double currentPrice = close[0];

    double deviation  = MathAbs(currentPrice - currentMA);
    double threshold  = currentATR * ATR_Multiplier;

    double sl, tp;

    if (useATR)
    {
        // SELL
        if (currentPrice > currentMA && deviation > threshold)
        {
            sl = currentPrice + (currentATR * SL_Multiplier);
            tp = currentPrice - (currentATR * TP_Multiplier);
            tradeSell(sl, tp, currentPrice);
        }
        // BUY
        if (currentPrice < currentMA && deviation > threshold)
        {
            sl = currentPrice - (currentATR * SL_Multiplier);
            tp = currentPrice + (currentATR * TP_Multiplier);
            tradeBuy(sl, tp, currentPrice);
        }
    }
    else if (useEma)
    {
        // SELL
        if (currentPrice > currentMA && deviation > threshold)
        {
            sl = currentPrice + (currentATR * SL_Multiplier);
            tp = currentMA + (currentATR * TP_Gap_Multiplier);
            tradeSell(sl, tp, currentPrice);
        }
        // BUY
        if (currentPrice < currentMA && deviation > threshold)
        {
            sl = currentPrice - (currentATR * SL_Multiplier);
            tp = currentMA - (currentATR * TP_Gap_Multiplier);
            tradeBuy(sl, tp, currentPrice);
        }
    }
    else if (useTrailingStop)
    {
        // SELL
        if (currentPrice > currentMA && deviation > threshold)
        {
            sl = currentPrice + (currentATR * SL_Multiplier);
            tp = currentMA + (currentATR * TP_Gap_Multiplier);
            tradeSell(sl, tp, currentPrice);
        }
        // BUY
        if (currentPrice < currentMA && deviation > threshold)
        {
            sl = currentPrice - (currentATR * SL_Multiplier);
            tp = currentMA - (currentATR * TP_Gap_Multiplier);
            tradeBuy(sl, tp, currentPrice);
        }
    }
}

//+------------------------------------------------------------------+
//| SIDEWAYS CHECK                                                   |
//+------------------------------------------------------------------+
bool isSideways()
{
    double sideway[], atr[];
    ArraySetAsSeries(sideway, true);
    ArraySetAsSeries(atr,     true);

    if (CopyBuffer(sidewayHandle, 0, 0, 2, sideway) <= 0) return false;
    if (CopyBuffer(atrHandle,     0, 0, 1, atr)     <= 0) return false;

    double sideway_diff = MathAbs(sideway[0] - sideway[1]);
    double buffer_fixed = Sideways_Buffer * _Point;
    double buffer_atr   = atr[0] * 0.2;
    double buffer_total = buffer_fixed + buffer_atr;

    return (sideway_diff <= buffer_total);
}

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT (original break-even + SAR trailing)        |
//+------------------------------------------------------------------+
void managePosition()
{
    if (PositionsTotal() <= 0)
        return;

    double atr[], sar[];
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(sar, true);

    if (CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return;
    if (CopyBuffer(sarHandle, 0, 0, 1, sar) <= 0) return;

    double currentATR = atr[0];
    double currentSAR = sar[0];

    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl        = PositionGetDouble(POSITION_SL);
        double tp        = PositionGetDouble(POSITION_TP);
        int    type      = (int)PositionGetInteger(POSITION_TYPE);

        double price = (type == POSITION_TYPE_BUY)
                       ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        //--- BREAK EVEN (unchanged)
        if (useBreakEven)
        {
            double trigger = currentATR * BE_Trigger_ATR;
            double lock    = currentATR * BE_Lock_ATR;

            if (type == POSITION_TYPE_BUY)
            {
                if (price - openPrice >= trigger)
                {
                    double newSL = openPrice + lock;
                    if (newSL > sl)
                        modifySL(ticket, newSL, tp);
                }
            }
            else
            {
                if (openPrice - price >= trigger)
                {
                    double newSL = openPrice - lock;
                    if (newSL < sl || sl == 0)
                        modifySL(ticket, newSL, tp);
                }
            }
        }

        //--- TRAILING SAR (unchanged)
        if (useTrailingStop)
        {
            if (type == POSITION_TYPE_BUY)
            {
                if (currentSAR > sl && currentSAR < price)
                    modifySL(ticket, currentSAR, tp);
            }
            else
            {
                if (currentSAR < sl && currentSAR > price)
                    modifySL(ticket, currentSAR, tp);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| MODIFY SL (unchanged)                                            |
//+------------------------------------------------------------------+
void modifySL(ulong ticket, double newSL, double tp)
{
    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action   = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl       = NormalizeDouble(newSL, _Digits);
    request.tp       = NormalizeDouble(tp,    _Digits);

    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| BUY — sends with sl=0/tp=0, stores SL in virtual array          |
//+------------------------------------------------------------------+
void tradeBuy(double sl, double tp, double currentPrice)
{
    double slDistance = MathAbs(currentPrice - sl);
    double lot        = calculateLot(slDistance);

    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action    = TRADE_ACTION_DEAL;
    request.type      = ORDER_TYPE_BUY;
    request.symbol    = _Symbol;
    request.volume    = lot;
    request.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.sl        = 0;   // virtual — not sent to broker
    request.tp        = NormalizeDouble(tp, _Digits);
    request.deviation = Slippage;
    request.magic     = 123456;

    if (!OrderSend(request, result)) return;

    if (result.retcode == TRADE_RETCODE_DONE ||
        result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(result.order, sl);
    }
}

//+------------------------------------------------------------------+
//| SELL — sends with sl=0/tp=0, stores SL in virtual array         |
//+------------------------------------------------------------------+
void tradeSell(double sl, double tp, double currentPrice)
{
    double slDistance = MathAbs(currentPrice - sl);
    double lot        = calculateLot(slDistance);

    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action    = TRADE_ACTION_DEAL;
    request.type      = ORDER_TYPE_SELL;
    request.symbol    = _Symbol;
    request.volume    = lot;
    request.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl        = 0;   // virtual — not sent to broker
    request.tp        = NormalizeDouble(tp, _Digits);
    request.deviation = Slippage;
    request.magic     = 123456;

    if (!OrderSend(request, result)) return;

    if (result.retcode == TRADE_RETCODE_DONE ||
        result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(result.order, sl);
    }
}

//+------------------------------------------------------------------+
//| LOT CALCULATION (unchanged)                                      |
//+------------------------------------------------------------------+
double calculateLot(double slPriceDistance)
{
    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney    = balance * (RiskPercent / 100.0);
    double tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double valuePerPoint= tickValue / tickSize;
    double slPoints     = slPriceDistance / _Point;

    if (slPoints <= 0)
        return LotSize;

    double lot     = riskMoney / (slPoints * valuePerPoint);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    lot = MathFloor(lot / lotStep) * lotStep;
    if (lot < minLot) lot = minLot;
    if (lot > maxLot) lot = maxLot;

    return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| VIRTUAL SL — add entry                                           |
//+------------------------------------------------------------------+
void AddVirtualSL(ulong ticket, double sl)
{
    int size = ArraySize(vsl);
    ArrayResize(vsl, size + 1);
    vsl[size].ticket = ticket;
    vsl[size].sl     = NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| VIRTUAL SL — check & close on breach (runs every tick)          |
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
    double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double prevLow  = iLow (_Symbol, PERIOD_CURRENT, 1);

    for (int i = ArraySize(vsl) - 1; i >= 0; i--)
    {
        if (!PositionSelectByTicket(vsl[i].ticket))
        {
            ArrayRemove(vsl, i, 1);
            continue;
        }

        long type      = PositionGetInteger(POSITION_TYPE);
        bool closeNow  = false;

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
//| VIRTUAL SL — close position at market                           |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
    if (!PositionSelectByTicket(ticket))
        return false;

    long type = PositionGetInteger(POSITION_TYPE);

    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action   = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol   = _Symbol;
    request.volume   = PositionGetDouble(POSITION_VOLUME);
    request.deviation= Slippage;
    request.magic    = 123456;

    if (type == POSITION_TYPE_BUY)
    {
        request.type  = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }
    else
    {
        request.type  = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }

    if (!OrderSend(request, result))
        return false;

    return (result.retcode == TRADE_RETCODE_DONE ||
            result.retcode == TRADE_RETCODE_DONE_PARTIAL);
}

//+------------------------------------------------------------------+
//| OPTIMIZER SCORE (unchanged)                                      |
//+------------------------------------------------------------------+
double OnTester()
{
    double profit   = TesterStatistics(STAT_PROFIT);
    double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
    double trades   = TesterStatistics(STAT_TRADES);
    double sharpe   = TesterStatistics(STAT_SHARPE_RATIO);

    if (trades   < 50) return -1000;
    if (drawdown <= 0) return -1000;

    double ddFactor    = 1.0 / drawdown;
    double tradeFactor = MathLog(trades);
    double score       = (profit * ddFactor) * sharpe * tradeFactor;

    return score;
}
//+------------------------------------------------------------------+