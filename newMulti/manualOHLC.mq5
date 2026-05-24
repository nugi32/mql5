
//+--------------------------------------------------------------------------------+
//| control-bar-opening-single-symbol.mq5                                          |
//|                                                                                |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                             |
//| THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"    |
//| AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE      |
//| IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE |
//| DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE   |
//| FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL     |
//| DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR     |
//| SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER     |
//| CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,  |
//| OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  |
//| OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.           |
//+--------------------------------------------------------------------------------+

#property copyright "Darwinex"
#property link "http://www.darwinex.com"
#property description "Bar Controlling Code (Single Symbol) - Darwinex Advanced MQL Coding Video Series. Author: Martyn Tinsley, Trade Like A Machine Ltd"

#property strict

enum ENUM_BAR_PROCESSING_METHOD
{
    PROCESS_ALL_DELIVERED_TICKS,             // Process All Delivered Ticks
    ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,      // Only Process Ticks From New M1 Bar
    ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR // Only Process Ticks From New Bar in Trade TF
};

// ################
//  Input Variables
// ################

input ENUM_TIMEFRAMES TradeTimeframe = PERIOD_M15;                                         // Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR; // EA Bar Processing Method

// ################
// Global Variables
// ################

int TicksReceivedCount = 0;                            // Number of ticks received by the EA
int TicksProcessedCount = 0;                           // Number of ticks processed by the EA (will depend on the BarProcessingMethod being used)
datetime TimeLastTickProcessed = D'1971.01.01 00:00'; // Used to control the processing of trades so that processing only happens at the desired intervals (to allow like-for-like back testing between the Strategy Tester and Live Trading) - Seeded with a past date before any backtesting will ever be run

int iBarToUseForProcessing; // This will either be bar 0 or bar 1, and depends on the BarProcessingMethod - Set in OnInit()

int OnInit()
{

    atrHandle = iATR(_Symbol, _Period, ATR_Period);
    maHandle = iMA(_Symbol, _Period, meanPeriod, 0, MODE_SMA, PRICE_CLOSE);
    sidewayHandle = iMA(_Symbol, _Period, Sideways_Period, 0, MODE_SMA, PRICE_CLOSE);
    sarHandle = iSAR(_Symbol, _Period, SAR_Step, SAR_Max);
    // ################################
    // Determine which bar we will used (0 or 1) to perform processing of data
    // ################################

    if (BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS) // Process data every tick that is 'delivered' to the EA
        iBarToUseForProcessing = 0;                         // The rationale here is that it is only worth processing every tick if you are actually going to use bar 0 from the trade TF, the value of which changes throughout the bar in the Trade TF                                          //The rationale here is that we want to use values that are right up to date - otherwise it is pointless doing this every 10 seconds

    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR) // Process trades based on 'any' TF, every minute.
        iBarToUseForProcessing = 0;                                     // The rationale here is that it is only worth processing every minute if you are actually going to use bar 0 from the trade TF, the value of which changes throughout the bar in the Trade TF

    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR) // Process when a new bar appears in the TF being used. So the M15 TF is processed once every 15 minutes, the TF60 is processed once every hour etc...
        iBarToUseForProcessing = 1;                                           // The rationale here is that if you only process data when a new bar in the trade TF appears, then it is better to use the indicator data etc from the last 'completed' bar, which will not subsequently change. (If using indicator values from bar 0 these will change throughout the evolution of bar 0)

    Print("EA USING " + EnumToString(BarProcessingMethod) + " PROCESSING METHOD AND INDICATORS WILL USE BAR " + IntegerToString(iBarToUseForProcessing));

    // Perform immediate update to screen so that if out of hours (e.g. at the weekend), the screen will still update (this is also run in OnTick())
    // if(!MQLInfoInteger(MQL_TESTER))
    OutputStatusToScreen();

    if (atrHandle == INVALID_HANDLE ||
        maHandle == INVALID_HANDLE ||
        sidewayHandle == INVALID_HANDLE ||
        sarHandle == INVALID_HANDLE)
    {
        Print("Init error: ", GetLastError());
        return (INIT_FAILED);
    }
    ArrayResize(vsl, 0);
    return (INIT_SUCCEEDED);
}

void OnTick()
{
    TicksReceivedCount++;

    // ########################################################
    // Control EA so that we only process at required intervals (Either 'Every Tick', 'Open Prices' or 'M1 Open Prices')
    // ########################################################

    bool ProcessThisIteration = false; // Set to false by default and then set to true below if required

    if (BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
        ProcessThisIteration = true;

    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR) // Process trades from any TF, every minute.
    {
        if (TimeLastTickProcessed != iTime(Symbol(), PERIOD_M1, 0))
        {
            ProcessThisIteration = true;
            TimeLastTickProcessed = iTime(Symbol(), PERIOD_M1, 0);
        }
    }

    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR) // Process when a new bar appears in the TF being used. So the M15 TF is processed once every 15 minutes, the TF60 is processed once every hour etc...
    {
        if (TimeLastTickProcessed != iTime(Symbol(), TradeTimeframe, 0)) // TimeLastTickProcessed contains the last Time[0] we processed for this TF. If it's not the same as the current value, we know that we have a new bar in this TF, so need to process
        {
            ProcessThisIteration = true;
            TimeLastTickProcessed = iTime(Symbol(), TradeTimeframe, 0);
        }
    }

    // #############################
    // Process Trades if appropriate
    // #############################

    if (ProcessThisIteration == true)
    {
        TicksProcessedCount++;

        checkEntry();

        ProcessTradeClosures();
        ProcessTradeOpens();

        Alert("PROCESSING " + Symbol() + " ON " + EnumToString(TradeTimeframe) + " CHART");
    }

    // ############################################
    // OUTPUT INFORMATION AND METRICS TO THE SCREEN (DO NOT OUTPUT ON EVERY TICK IN PRODUCTION, FOR PERFORMANCE REASONS - DONE HERE FOR ILLUSTRATIVE PURPOSES ONLY)
    // ############################################

    // if(!MQLInfoInteger(MQL_TESTER))
    OutputStatusToScreen();
}

void ProcessTradeClosures()
{
    double localBuffer[];
    ArrayResize(localBuffer, 3);

    // Use CopyBuffer here to copy indicator buffer to local buffer...

    ArraySetAsSeries(localBuffer, true);

    double currentIndValue = localBuffer[iBarToUseForProcessing];
    double previousIndValue = localBuffer[iBarToUseForProcessing + 1];
}

void ProcessTradeOpens()
{
    double localBuffer[];
    ArrayResize(localBuffer, 3);

    // Use CopyBuffer here to copy indicator buffer to local buffer...

    ArraySetAsSeries(localBuffer, true);

    double currentIndValue = localBuffer[iBarToUseForProcessing];
    double previousIndValue = localBuffer[iBarToUseForProcessing + 1];
}

void OutputStatusToScreen()
{
    double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

    string OutputText = "\n\r";

    OutputText += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " (OPERATING AT UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

    OutputText += Symbol() + " TICKS RECEIVED:   " + IntegerToString(TicksReceivedCount) + "\n\r";
    OutputText += Symbol() + " TICKS PROCESSED:   " + IntegerToString(TicksProcessedCount) + "\n\r";
    OutputText += "PROCESSING METHOD:   " + EnumToString(BarProcessingMethod) + "\n\r";
    OutputText += EnumToString(TradeTimeframe) + " BAR USED FOR PROCESSING INDICATORS / PRICE:   " + IntegerToString(iBarToUseForProcessing) + "\n\r";
    OutputText += "SYMBOL BEING TRADED:   " + Symbol() + "\n\r";
    OutputText += "TRADING TIMEFRAME:   " + EnumToString(TradeTimeframe) + "\n\r\n\r";

    Comment(OutputText);

    return;
}

//+------------------------------------------------------------------+
//| ATR Mean Reversion EA (Complete Version)                        |
//+------------------------------------------------------------------+

input group "POSITION SETTINGS" input double LotSize = 0.01;
input int Slippage = 10;
input double RiskPercent = 1.0;
input int MagicNumber = 123456;

input group "INDICATOR SETTINGS" input int ATR_Period = 14;
input double ATR_Multiplier = 1.5;

// Sideways detection
input int Sideways_Period = 34;
input double Sideways_Buffer = 155;

input int meanPeriod = 50;

input group "STOP LOSS & TAKE PROFIT" input double SL_Multiplier = 1.5;
input double TP_Multiplier = 1.0;
input double TP_Gap_Multiplier = 1.0;

input group "FEATURE TOGGLES" input bool useBreakEven = false;

input group "TP SETTINGS" input bool useATR = true;
input bool useEma = false;
input bool useTrailingStop = false;

input group "SAR TRAILING" input double SAR_Step = 0.02;
input double SAR_Max = 0.2;

input group "BREAK EVEN" input double BE_Trigger_ATR = 1.0;
input double BE_Lock_ATR = 0.2;

//--- Handles
int atrHandle, maHandle, sidewayHandle, sarHandle;

struct VirtualSL
{
    ulong ticket;
    double sl;
    double tp;
};
VirtualSL vsl[];

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(atrHandle);
    IndicatorRelease(maHandle);
    IndicatorRelease(sidewayHandle);
    IndicatorRelease(sarHandle);
}
//+------------------------------------------------------------------+
void checkEntry()
{
    managePosition();
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
    ArraySetAsSeries(atr, true);

    if (CopyBuffer(sidewayHandle, 0, 0, 2, sideway) <= 0)
        return false;
    if (CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
        return false;

    double sideway_diff = MathAbs(sideway[0] - sideway[1]);

    double buffer_fixed = Sideways_Buffer * _Point;
    double buffer_atr = atr[0] * 0.2; // bisa kamu jadikan input

    double buffer_total = buffer_fixed + buffer_atr;

    return (sideway_diff <= buffer_total);
}
//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                              |
//+------------------------------------------------------------------+
void managePosition()
{
    if (PositionsTotal() <= 0)
        return;

    // BREAK EVEN virtual
    UpdateVirtualBreakEven();

    // TRAILING SAR virtual
    if (useTrailingStop)
        UpdateTrailingVirtualSL();
}

//+------------------------------------------------------------------+
//| BUY                                                              |
//+------------------------------------------------------------------+
bool tradeBuy(double sl, double tp, double currentPrice)
{

    double slDistance = MathAbs(currentPrice - sl);
    double lot = calculateLot(slDistance);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.type = ORDER_TYPE_BUY;
    request.volume = lot;
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
        AddVirtualSL(result.order, sl, tp);
        return true;
    }

    return false;
}
//+------------------------------------------------------------------+
//| SELL                                                             |
//+------------------------------------------------------------------+
bool tradeSell(double sl, double tp, double currentPrice)
{

    double slDistance = MathAbs(currentPrice - sl);
    double lot = calculateLot(slDistance);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.type = ORDER_TYPE_SELL;
    request.volume = lot;
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
        AddVirtualSL(result.order, sl, tp);
        return true;
    }

    return false;
}
//+------------------------------------------------------------------+
double calculateLot(double slPriceDistance)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (RiskPercent / 100.0);

    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    double valuePerPoint = tickValue / tickSize;

    double slPoints = slPriceDistance / _Point;

    if (slPoints <= 0)
        return LotSize;

    double lot = riskMoney / (slPoints * valuePerPoint);

    //================ NORMALISASI =================
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lot = MathFloor(lot / lotStep) * lotStep;

    //================ RULE KAMU =================
    if (lot < minLot)
        lot = minLot;

    // safety tambahan (biar ga over)
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if (lot > maxLot)
        lot = maxLot;

    return NormalizeDouble(lot, 2);
}
//+------------------------------------------------------------------+
double OnTester()
{
    double profit = TesterStatistics(STAT_PROFIT);
    double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
    double trades = TesterStatistics(STAT_TRADES);
    double sharpe = TesterStatistics(STAT_SHARPE_RATIO);

    //================ SAFETY =================
    if (trades < 50)
        return -1000;

    if (drawdown <= 0)
        return -1000;

    //================ NORMALISASI =================
    double ddFactor = 1.0 / drawdown;
    double tradeFactor = MathLog(trades);
    double sharpeFactor = sharpe;

    //================ FINAL SCORE =================
    double score = (profit * ddFactor) * sharpeFactor * tradeFactor;

    return score;
}

//+------------------------------------------------------------------+
//    VIRTUAL SECTION
//+------------------------------------------------------------------+

void CheckVirtualStops()
{
    double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double prevLow = iLow(_Symbol, PERIOD_CURRENT, 1);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    for (int i = ArraySize(vsl) - 1; i >= 0; i--)
    {
        if (!PositionSelectByTicket(vsl[i].ticket))
        {
            ArrayRemove(vsl, i, 1);
            continue;
        }

        long type = PositionGetInteger(POSITION_TYPE);

        bool hitSL = false;
        bool hitTP = false;

        //================ BUY =================
        if (type == POSITION_TYPE_BUY)
        {
            // SL kena kalau candle sebelumnya low tembus
            if (vsl[i].sl > 0 && bid <= vsl[i].sl)
                hitSL = true;

            // TP kena kalau candle sebelumnya high tembus
            if (vsl[i].tp > 0 && bid >= vsl[i].tp)
                hitTP = true;
        }

        //================ SELL ================
        else if (type == POSITION_TYPE_SELL)
        {
            // SL kena kalau high tembus
            if (vsl[i].sl > 0 && ask >= vsl[i].sl)
                hitSL = true;

            // TP kena kalau low tembus
            if (vsl[i].tp > 0 && ask <= vsl[i].tp)
                hitTP = true;
        }

        // close kalau salah satu kena
        if (hitSL || hitTP)
        {
            CloseAndRemove(vsl[i].ticket);
        }
    }
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
//+------------------------------------------------------------------+
void UpdateVirtualBreakEven()
{
    if (!useBreakEven)
        return;

    double atr[];
    ArraySetAsSeries(atr, true);

    if (CopyBuffer(atrHandle, 0, 0, 1, atr) < 1)
        return;

    double currentATR = atr[0];

    double trigger = currentATR * BE_Trigger_ATR;
    double lock = currentATR * BE_Lock_ATR;

    for (int i = 0; i < ArraySize(vsl); i++)
    {
        ulong ticket = vsl[i].ticket;

        if (!PositionSelectByTicket(ticket))
            continue;

        long type = PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

        double price =
            (type == POSITION_TYPE_BUY)
                ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        //================ BUY =================
        if (type == POSITION_TYPE_BUY)
        {
            if (price - openPrice >= trigger)
            {
                double newSL = NormalizeDouble(openPrice + lock, _Digits);

                // hanya naik
                if (newSL > vsl[i].sl)
                    vsl[i].sl = newSL;
            }
        }

        //================ SELL ================
        else if (type == POSITION_TYPE_SELL)
        {
            if (openPrice - price >= trigger)
            {
                double newSL = NormalizeDouble(openPrice - lock, _Digits);

                // hanya turun
                if (newSL < vsl[i].sl || vsl[i].sl == 0)
                    vsl[i].sl = newSL;
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