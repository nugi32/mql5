//+--------------------------------------------------------------------------------+
//| control-bar-ohlc-virtual-fixed.mq5                                             |
//|                                                                                |
//| FIXES vs previous version:                                                     |
//|  BUG 1  tradeBuy/tradeSell: entry price → gCtx.Ask()/Bid()                    |
//|  BUG 2  ClosePosition:      close price → gCtx.Bid()/Ask()                    |
//|  BUG 3  isSideways:         copy 3 bars, compare [1] vs [2], use atr[1]       |
//|  BUG 4  checkEntry:         remove dead CopyClose(_Period) call               |
//|  BUG 5  UpdateVirtualBreakEven: copy 2 bars, use atr[1]                       |
//|  BUG 6  UpdateTrailingVirtualSL: guard SAR against crossing current price     |
//+--------------------------------------------------------------------------------+
#property strict

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_BAR_PROCESSING_METHOD
{
    PROCESS_ALL_DELIVERED_TICKS,
    ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,
    ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR
};

enum ENUM_OHLC_EVENT
{
    OHLC_NONE  = -1,
    OHLC_OPEN  =  0,
    OHLC_LOW   =  1,
    OHLC_HIGH  =  2,
    OHLC_CLOSE =  3
};

enum ENUM_ENTRY_SIGNAL
{
    SIGNAL_NONE = 0,
    SIGNAL_BUY,
    SIGNAL_SELL
};

//==================================================================
//  INPUTS
//==================================================================
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR;

input group "POSITION SETTINGS"
input double LotSize     = 0.01;
input int    Slippage    = 10;
input double RiskPercent = 1.0;
input int    MagicNumber = 123456;

input group "INDICATOR SETTINGS"
input int    ATR_Period      = 14;
input double ATR_Multiplier  = 1.5;
input int    Sideways_Period = 34;
input double Sideways_Buffer = 155;
input int    meanPeriod      = 50;

input group "STOP LOSS & TAKE PROFIT"
input double SL_Multiplier     = 1.5;
input double TP_Multiplier     = 1.0;
input double TP_Gap_Multiplier = 1.0;

input group "FEATURE TOGGLES"
input bool useBreakEven   = false;
input bool useATR         = true;
input bool useEma         = false;
input bool useTrailingStop= false;

input group "SAR TRAILING"
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

input group "BREAK EVEN"
input double BE_Trigger_ATR = 1.0;
input double BE_Lock_ATR    = 0.2;

//==================================================================
//  VIRTUAL FEED
//==================================================================
struct SVirtualTick
{
    datetime        time;
    double          bid;
    double          ask;
    double          last;
    ENUM_OHLC_EVENT event;
};

struct SBarDescriptor
{
    datetime barTime;
    double   O, H, L, C;
    long     tickVol;
    int      spread;
    bool     bullish;
};

class CVirtualFeed
{
private:
    string          m_sym;
    SBarDescriptor  m_bar, m_prevBar;
    bool            m_hasPrev;
    int             m_seqIdx, m_seqLen;
    ENUM_OHLC_EVENT m_seq[4];
    datetime        m_lastBarTime;

    bool ResolveBullish(bool raw)
    {
        if (m_bar.O != m_bar.C) return raw;
        if (!m_hasPrev)         return raw;
        return !(m_prevBar.C >= m_prevBar.O);
    }

    void BuildSequence()
    {
        m_seqIdx = 0;
        long tv  = m_bar.tickVol;
        if (tv <= 1) { m_seqLen=1; m_seq[0]=OHLC_CLOSE; return; }
        if (tv == 2) { m_seqLen=2; m_seq[0]=OHLC_OPEN; m_seq[1]=OHLC_CLOSE; return; }
        m_seqLen=4; m_seq[0]=OHLC_OPEN; m_seq[3]=OHLC_CLOSE;
        if (m_bar.bullish) { m_seq[1]=OHLC_LOW; m_seq[2]=OHLC_HIGH; }
        else               { m_seq[1]=OHLC_HIGH; m_seq[2]=OHLC_LOW; }
    }

    double PriceFor(ENUM_OHLC_EVENT ev) const
    {
        switch(ev)
        {
            case OHLC_OPEN:  return m_bar.O;
            case OHLC_HIGH:  return m_bar.H;
            case OHLC_LOW:   return m_bar.L;
            case OHLC_CLOSE: return m_bar.C;
            default:         return m_bar.C;
        }
    }

    datetime TimeFor(int step) const
    {
        if (m_seqLen == 1)         return m_bar.barTime + 59;
        if (step == 0)             return m_bar.barTime;
        if (step == m_seqLen - 1)  return m_bar.barTime + 59;
        return m_bar.barTime + (datetime)(step * 59 / (m_seqLen - 1));
    }

    SVirtualTick MakeTick(datetime t, double bidPx, ENUM_OHLC_EVENT ev) const
    {
        SVirtualTick tk;
        tk.time  = t;
        tk.bid   = NormalizeDouble(bidPx, _Digits);
        tk.ask   = NormalizeDouble(bidPx + m_bar.spread * _Point, _Digits);
        tk.last  = tk.bid;
        tk.event = ev;
        return tk;
    }

public:
    void Init(string sym)
    {
        m_sym=sym; m_lastBarTime=0; m_seqIdx=4; m_seqLen=0; m_hasPrev=false;
        ZeroMemory(m_bar); ZeroMemory(m_prevBar);
    }

    bool Next(SVirtualTick &tick)
    {
        if (m_seqIdx >= m_seqLen)
        {
            datetime bt[];
            if (CopyTime(m_sym,PERIOD_M1,1,1,bt)<=0)    return false;
            if (bt[0]==m_lastBarTime)                    return false;
            MqlRates r[];
            if (CopyRates(m_sym,PERIOD_M1,1,1,r)<=0)    return false;
            m_lastBarTime=bt[0]; m_prevBar=m_bar; m_hasPrev=true;
            m_bar.barTime=r[0].time; m_bar.O=r[0].open; m_bar.H=r[0].high;
            m_bar.L=r[0].low; m_bar.C=r[0].close; m_bar.tickVol=r[0].tick_volume;
            m_bar.spread=(int)r[0].spread;
            if (m_bar.spread<=0) m_bar.spread=(int)SymbolInfoInteger(m_sym,SYMBOL_SPREAD);
            m_bar.bullish=ResolveBullish(m_bar.C>=m_bar.O);
            BuildSequence();
        }
        if (m_seqIdx>=m_seqLen) return false;
        ENUM_OHLC_EVENT ev=m_seq[m_seqIdx];
        tick=MakeTick(TimeFor(m_seqIdx),PriceFor(ev),ev);
        m_seqIdx++;
        return true;
    }
};

class CVirtualMarketContext
{
private:
    SVirtualTick m_tick;
    bool         m_valid;
public:
    void Init()  { m_valid=false; ZeroMemory(m_tick); }
    void Update(const SVirtualTick &tk) { m_tick=tk; m_valid=true; }
    bool            IsValid()   const { return m_valid; }
    double          Bid()       const { return m_tick.bid; }
    double          Ask()       const { return m_tick.ask; }
    double          Last()      const { return m_tick.last; }
    datetime        Time()      const { return m_tick.time; }
    ENUM_OHLC_EVENT Event()     const { return m_tick.event; }
    string EventName() const
    {
        switch(m_tick.event)
        {
            case OHLC_OPEN:  return "OPEN";
            case OHLC_HIGH:  return "HIGH";
            case OHLC_LOW:   return "LOW";
            case OHLC_CLOSE: return "CLOSE";
            default:         return "NONE";
        }
    }
};

//==================================================================
//  VIRTUAL SL/TP RECORD
//==================================================================
struct VirtualSL
{
    ulong  ticket;
    double sl;
    double tp;
};

//==================================================================
//  GLOBALS
//==================================================================
CVirtualFeed          gFeed;
CVirtualMarketContext gCtx;

int atrHandle, maHandle, sidewayHandle, sarHandle;

int      TicksReceivedCount  = 0;
int      TicksProcessedCount = 0;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;

VirtualSL vsl[];

ENUM_ENTRY_SIGNAL gPendingSignal = SIGNAL_NONE;
double            gPendingSL     = 0;
double            gPendingTP     = 0;
double            gPendingPrice  = 0;

datetime gLastTradeBar = 0;
bool     gSignalLocked = false;

//==================================================================
//  OHLC LOG
//==================================================================
struct SOHLCLogEntry { datetime barTime; string eventName; double bid,ask; };
SOHLCLogEntry gOHLCLog[40];
int           gOHLCLogCount = 0;

void LogOHLCEvent(const SVirtualTick &tk)
{
    int idx = gOHLCLogCount % 40;
    gOHLCLog[idx].barTime   = tk.time;
    gOHLCLog[idx].eventName = gCtx.EventName();
    gOHLCLog[idx].bid       = tk.bid;
    gOHLCLog[idx].ask       = tk.ask;
    gOHLCLogCount++;
    PrintFormat("OHLC | %s | %-5s | Bid=%.5f  Ask=%.5f",
                TimeToString(tk.time,TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                gCtx.EventName(), tk.bid, tk.ask);
}

//==================================================================
//  FORWARD DECLARATIONS
//==================================================================
void  checkEntry();
void  ProcessTradeClosures();
void  ProcessTradeOpens();
void  CheckVirtualStops();
void  managePosition();
bool  isSideways();
bool  tradeBuy (double sl, double tp, double price);
bool  tradeSell(double sl, double tp, double price);
void  AddVirtualSL(ulong ticket, double sl, double tp);
void  CloseAndRemove(ulong ticket);
bool  ClosePosition(ulong ticket);
void  UpdateVirtualBreakEven();
void  UpdateTrailingVirtualSL();
double calculateLot(double slDist);
void  OutputStatusToScreen();

//==================================================================
//  OnInit
//==================================================================
int OnInit()
{
    atrHandle     = iATR (_Symbol, PERIOD_M1, ATR_Period);
    maHandle      = iMA  (_Symbol, PERIOD_M1, meanPeriod,      0, MODE_SMA, PRICE_CLOSE);
    sidewayHandle = iMA  (_Symbol, PERIOD_M1, Sideways_Period, 0, MODE_SMA, PRICE_CLOSE);
    sarHandle     = iSAR (_Symbol, PERIOD_M1, SAR_Step, SAR_Max);

    if (atrHandle==INVALID_HANDLE || maHandle==INVALID_HANDLE ||
        sidewayHandle==INVALID_HANDLE || sarHandle==INVALID_HANDLE)
    {
        Print("Init error: ", GetLastError());
        return INIT_FAILED;
    }

    if (BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
        iBarToUseForProcessing = 0;
    else
        iBarToUseForProcessing = 1; // always use CLOSED bar for OHLC and TradeTF modes

    gFeed.Init(_Symbol);
    gCtx .Init();
    ArrayResize(vsl, 0);

    PrintFormat("EA USING %s | BAR IDX = %d",
                EnumToString(BarProcessingMethod), iBarToUseForProcessing);
    OutputStatusToScreen();
    return INIT_SUCCEEDED;
}

//==================================================================
//  OnDeinit
//==================================================================
void OnDeinit(const int reason)
{
    IndicatorRelease(atrHandle);
    IndicatorRelease(maHandle);
    IndicatorRelease(sidewayHandle);
    IndicatorRelease(sarHandle);
}

//==================================================================
//  OnTick
//==================================================================
void OnTick()
{
    TicksReceivedCount++;

    if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
    {
        SVirtualTick vTick;
        while (gFeed.Next(vTick))
        {
            gCtx.Update(vTick);
            LogOHLCEvent(vTick);
            TicksProcessedCount++;
            ProcessTradeClosures();   // exits BEFORE entries (same as tester)
            checkEntry();
            ProcessTradeOpens();
        }
    }
    else if (BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
    {
        TicksProcessedCount++;
        ProcessTradeClosures();
        checkEntry();
        ProcessTradeOpens();
    }
    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
    {
        if (TimeLastTickProcessed != iTime(Symbol(), TradeTimeframe, 0))
        {
            TimeLastTickProcessed = iTime(Symbol(), TradeTimeframe, 0);
            TicksProcessedCount++;
            ProcessTradeClosures();
            checkEntry();
            ProcessTradeOpens();
        }
    }

    OutputStatusToScreen();
}

//==================================================================
//  ProcessTradeClosures
//==================================================================
void ProcessTradeClosures()
{
    if (!gCtx.IsValid()) return;
    CheckVirtualStops();
    managePosition();
}

//==================================================================
//  ProcessTradeOpens
//==================================================================
void ProcessTradeOpens()
{
    if (!gCtx.IsValid())           return;
    if (gPendingSignal == SIGNAL_NONE) return;
    if (PositionsTotal() > 0)     { gPendingSignal = SIGNAL_NONE; return; }

    // Only open on OPEN or CLOSE events
    ENUM_OHLC_EVENT ev = gCtx.Event();
    if (ev != OHLC_OPEN && ev != OHLC_CLOSE) return;

    bool opened = false;
    if (gPendingSignal == SIGNAL_BUY)
        opened = tradeBuy (gPendingSL, gPendingTP, gPendingPrice);
    else if (gPendingSignal == SIGNAL_SELL)
        opened = tradeSell(gPendingSL, gPendingTP, gPendingPrice);

    if (opened)
    {
        PrintFormat("OPENED %s | Event=%s | Price=%.5f",
                    EnumToString(gPendingSignal), gCtx.EventName(), gPendingPrice);
        gPendingSignal = SIGNAL_NONE;
    }
}

//==================================================================
//  checkEntry
//==================================================================
void checkEntry()
{
    if (!gCtx.IsValid()) return;

    datetime currentTradeBar = iTime(_Symbol, TradeTimeframe, 0);
    if (currentTradeBar != gLastTradeBar)
    {
        gLastTradeBar = currentTradeBar;
        gSignalLocked = false;
    }
    if (gSignalLocked)    return;
    if (!isSideways())    return;
    if (PositionsTotal() > 0) return;

    double atr[], ma[];
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(ma,  true);

    if (CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0) return;
    if (CopyBuffer(maHandle,  0, 0, 3, ma)  <= 0) return;

    // BUG 4 FIX: removed dead CopyClose(_Symbol, _Period, ...) — never used,
    //            used wrong timeframe (_Period instead of PERIOD_M1)

    double currentATR   = atr[iBarToUseForProcessing]; // closed bar
    double currentMA    = ma [iBarToUseForProcessing]; // closed bar
    double currentPrice = gCtx.Last();                 // virtual OHLC price

    double deviation = MathAbs(currentPrice - currentMA);
    double threshold = currentATR * ATR_Multiplier;

    if (deviation <= threshold) return; // no signal — exit early

    double sl, tp;

    if (useATR)
    {
        if (currentPrice > currentMA) // SELL
        {
            sl = currentPrice + (currentATR * SL_Multiplier);
            tp = currentPrice - (currentATR * TP_Multiplier);
            gPendingSignal = SIGNAL_SELL;
        }
        else // BUY
        {
            sl = currentPrice - (currentATR * SL_Multiplier);
            tp = currentPrice + (currentATR * TP_Multiplier);
            gPendingSignal = SIGNAL_BUY;
        }
    }
    else if (useEma)
    {
        if (currentPrice > currentMA) // SELL
        {
            sl = currentPrice + (currentATR * SL_Multiplier);
            tp = currentMA    + (currentATR * TP_Gap_Multiplier);
            gPendingSignal = SIGNAL_SELL;
        }
        else // BUY
        {
            sl = currentPrice - (currentATR * SL_Multiplier);
            tp = currentMA    - (currentATR * TP_Gap_Multiplier);
            gPendingSignal = SIGNAL_BUY;
        }
    }
    else if (useTrailingStop)
    {
        if (currentPrice > currentMA) // SELL
        {
            sl = currentPrice + (currentATR * SL_Multiplier);
            tp = currentMA    + (currentATR * TP_Gap_Multiplier);
            gPendingSignal = SIGNAL_SELL;
        }
        else // BUY
        {
            sl = currentPrice - (currentATR * SL_Multiplier);
            tp = currentMA    - (currentATR * TP_Gap_Multiplier);
            gPendingSignal = SIGNAL_BUY;
        }
    }
    else
    {
        return; // no mode selected
    }

    gPendingSL    = sl;
    gPendingTP    = tp;
    gPendingPrice = currentPrice;
    gSignalLocked = true;
}

//==================================================================
//  isSideways
//  BUG 3 FIX: copy 3 bars, compare sideway[1] vs sideway[2] (both
//             closed bars), use atr[1] (closed bar ATR)
//==================================================================
bool isSideways()
{
    double sideway[], atr[];
    ArraySetAsSeries(sideway, true);
    ArraySetAsSeries(atr,     true);

    // FIX: was CopyBuffer(..., 0, 0, 2, sideway) → compared [0] vs [1]
    //      [0] is the FORMING bar — wrong for OHLC mode
    //      Need 3 bars so we can safely compare [1] and [2]
    if (CopyBuffer(sidewayHandle, 0, 0, 3, sideway) <= 0) return false;
    if (CopyBuffer(atrHandle,     0, 0, 2, atr)     <= 0) return false;

    double sideway_diff = MathAbs(sideway[1] - sideway[2]); // both closed bars
    double buffer_fixed = Sideways_Buffer * _Point;
    double buffer_atr   = atr[1] * 0.2;                     // closed bar ATR

    return (sideway_diff <= buffer_fixed + buffer_atr);
}

//==================================================================
//  managePosition
//==================================================================
void managePosition()
{
    if (PositionsTotal() <= 0) return;
    if (useBreakEven)          UpdateVirtualBreakEven();
    if (useTrailingStop)       UpdateTrailingVirtualSL();
}

//==================================================================
//  tradeBuy
//  BUG 1 FIX: entry price → gCtx.Ask() (virtual OHLC ask)
//             was: SymbolInfoDouble(_Symbol, SYMBOL_ASK)  [real price]
//==================================================================
bool tradeBuy(double sl, double tp, double currentPrice)
{
    double slDist = MathAbs(currentPrice - sl);
    double lot    = calculateLot(slDist);

    MqlTradeRequest req = {};
    MqlTradeResult  res = {};
    req.action    = TRADE_ACTION_DEAL;
    req.symbol    = _Symbol;
    req.type      = ORDER_TYPE_BUY;
    req.volume    = lot;
    req.price     = gCtx.Ask();   // BUG 1 FIX: virtual price, not live ASK
    req.sl        = 0;
    req.tp        = 0;
    req.deviation = Slippage;
    req.magic     = MagicNumber;

    if (!OrderSend(req, res)) return false;

    if (res.retcode == TRADE_RETCODE_DONE ||
        res.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(res.order,
                     NormalizeDouble(sl, _Digits),
                     NormalizeDouble(tp, _Digits));
        return true;
    }
    return false;
}

//==================================================================
//  tradeSell
//  BUG 1 FIX: entry price → gCtx.Bid() (virtual OHLC bid)
//             was: SymbolInfoDouble(_Symbol, SYMBOL_BID)  [real price]
//==================================================================
bool tradeSell(double sl, double tp, double currentPrice)
{
    double slDist = MathAbs(currentPrice - sl);
    double lot    = calculateLot(slDist);

    MqlTradeRequest req = {};
    MqlTradeResult  res = {};
    req.action    = TRADE_ACTION_DEAL;
    req.symbol    = _Symbol;
    req.type      = ORDER_TYPE_SELL;
    req.volume    = lot;
    req.price     = gCtx.Bid();   // BUG 1 FIX: virtual price, not live BID
    req.sl        = 0;
    req.tp        = 0;
    req.deviation = Slippage;
    req.magic     = MagicNumber;

    if (!OrderSend(req, res)) return false;

    if (res.retcode == TRADE_RETCODE_DONE ||
        res.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(res.order,
                     NormalizeDouble(sl, _Digits),
                     NormalizeDouble(tp, _Digits));
        return true;
    }
    return false;
}

//==================================================================
//  CheckVirtualStops — uses virtual bid/ask (correct)
//==================================================================
void CheckVirtualStops()
{
    double bid = gCtx.Bid();
    double ask = gCtx.Ask();

    for (int i = ArraySize(vsl) - 1; i >= 0; i--)
    {
        if (!PositionSelectByTicket(vsl[i].ticket))
        {
            ArrayRemove(vsl, i, 1);
            continue;
        }

        long type = PositionGetInteger(POSITION_TYPE);
        bool hitSL = false, hitTP = false;

        if (type == POSITION_TYPE_BUY)
        {
            if (vsl[i].sl > 0 && bid <= vsl[i].sl) hitSL = true;
            if (vsl[i].tp > 0 && bid >= vsl[i].tp) hitTP = true;
        }
        else if (type == POSITION_TYPE_SELL)
        {
            if (vsl[i].sl > 0 && ask >= vsl[i].sl) hitSL = true;
            if (vsl[i].tp > 0 && ask <= vsl[i].tp) hitTP = true;
        }

        if (hitSL || hitTP)
            CloseAndRemove(vsl[i].ticket);
    }
}

//==================================================================
//  AddVirtualSL
//==================================================================
void AddVirtualSL(ulong ticket, double sl, double tp)
{
    int n = ArraySize(vsl);
    ArrayResize(vsl, n + 1);
    vsl[n].ticket = ticket;
    vsl[n].sl     = sl;
    vsl[n].tp     = tp;
}

//==================================================================
//  CloseAndRemove
//==================================================================
void CloseAndRemove(ulong ticket)
{
    if (ClosePosition(ticket))
    {
        for (int i = ArraySize(vsl) - 1; i >= 0; i--)
        {
            if (vsl[i].ticket == ticket)
            { ArrayRemove(vsl, i, 1); break; }
        }
    }
}

//==================================================================
//  ClosePosition
//  BUG 2 FIX: close price → gCtx.Bid()/Ask() (virtual OHLC price)
//             was: SymbolInfoDouble(_Symbol, SYMBOL_BID/ASK) [real price]
//==================================================================
bool ClosePosition(ulong ticket)
{
    if (!PositionSelectByTicket(ticket)) return false;

    long type = PositionGetInteger(POSITION_TYPE);

    MqlTradeRequest req = {};
    MqlTradeResult  res = {};
    req.action    = TRADE_ACTION_DEAL;
    req.position  = ticket;
    req.symbol    = _Symbol;
    req.volume    = PositionGetDouble(POSITION_VOLUME);
    req.deviation = Slippage;
    req.magic     = MagicNumber;

    if (type == POSITION_TYPE_BUY)
    {
        req.type  = ORDER_TYPE_SELL;
        req.price = gCtx.Bid();   // BUG 2 FIX: virtual OHLC bid, not live price
    }
    else
    {
        req.type  = ORDER_TYPE_BUY;
        req.price = gCtx.Ask();   // BUG 2 FIX: virtual OHLC ask, not live price
    }

    if (!OrderSend(req, res)) return false;
    return (res.retcode == TRADE_RETCODE_DONE ||
            res.retcode == TRADE_RETCODE_DONE_PARTIAL);
}

//==================================================================
//  UpdateVirtualBreakEven
//  BUG 5 FIX: use atr[1] (closed bar), was atr[0] (forming bar)
//==================================================================
void UpdateVirtualBreakEven()
{
    if (!useBreakEven) return;

    double atr[];
    ArraySetAsSeries(atr, true);

    // FIX: copy 2 bars, use index 1 (last closed bar)
    // was: CopyBuffer(..., 0, 0, 1, atr) → atr[0] = forming bar
    if (CopyBuffer(atrHandle, 0, 0, 2, atr) < 2) return;

    double currentATR = atr[1]; // BUG 5 FIX: closed bar
    double trigger    = currentATR * BE_Trigger_ATR;
    double lock       = currentATR * BE_Lock_ATR;

    for (int i = 0; i < ArraySize(vsl); i++)
    {
        if (!PositionSelectByTicket(vsl[i].ticket)) continue;

        long   type      = PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double price     = (type == POSITION_TYPE_BUY) ? gCtx.Bid() : gCtx.Ask();

        if (type == POSITION_TYPE_BUY)
        {
            if (price - openPrice >= trigger)
            {
                double newSL = NormalizeDouble(openPrice + lock, _Digits);
                if (newSL > vsl[i].sl) vsl[i].sl = newSL;
            }
        }
        else
        {
            if (openPrice - price >= trigger)
            {
                double newSL = NormalizeDouble(openPrice - lock, _Digits);
                if (newSL < vsl[i].sl || vsl[i].sl == 0) vsl[i].sl = newSL;
            }
        }
    }
}

//==================================================================
//  UpdateTrailingVirtualSL
//  BUG 6 FIX: guard SAR against crossing the current price.
//             Without the guard, a flipped SAR (above Bid for BUY,
//             below Ask for SELL) would set SL on the wrong side,
//             triggering an instant close at a wrong price.
//==================================================================
void UpdateTrailingVirtualSL()
{
    double sar[];
    ArraySetAsSeries(sar, true);
    if (CopyBuffer(sarHandle, 0, 0, 3, sar) < 3) return;

    double sarValue = sar[1]; // closed bar SAR

    for (int i = 0; i < ArraySize(vsl); i++)
    {
        if (!PositionSelectByTicket(vsl[i].ticket)) continue;

        long   type  = PositionGetInteger(POSITION_TYPE);
        double price = (type == POSITION_TYPE_BUY) ? gCtx.Bid() : gCtx.Ask();

        if (type == POSITION_TYPE_BUY)
        {
            // BUG 6 FIX: SAR must be BELOW current price and ABOVE old SL
            // was: if (sarValue > vsl[i].sl)  — no price ceiling check
            if (sarValue > vsl[i].sl && sarValue < price)
                vsl[i].sl = NormalizeDouble(sarValue, _Digits);
        }
        else
        {
            // BUG 6 FIX: SAR must be ABOVE current price and BELOW old SL
            // was: if (sarValue < vsl[i].sl)  — no price floor check
            if (sarValue < vsl[i].sl && sarValue > price)
                vsl[i].sl = NormalizeDouble(sarValue, _Digits);
        }
    }
}

//==================================================================
//  calculateLot — unchanged
//==================================================================
double calculateLot(double slPriceDistance)
{
    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (RiskPercent / 100.0);
    double tv        = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double ts        = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double vpp       = tv / ts;
    double slPoints  = slPriceDistance / _Point;

    if (slPoints <= 0) return LotSize;

    double lot     = riskMoney / (slPoints * vpp);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    lot = MathFloor(lot / lotStep) * lotStep;
    if (lot < minLot) lot = minLot;
    if (lot > maxLot) lot = maxLot;
    return NormalizeDouble(lot, 2);
}

//==================================================================
//  OnTester — unchanged
//==================================================================
double OnTester()
{
    double profit   = TesterStatistics(STAT_PROFIT);
    double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
    double trades   = TesterStatistics(STAT_TRADES);
    double sharpe   = TesterStatistics(STAT_SHARPE_RATIO);
    if (trades < 50 || drawdown <= 0) return -1000;
    return (profit * (1.0/drawdown)) * sharpe * MathLog(trades);
}

//==================================================================
//  OutputStatusToScreen
//==================================================================
void OutputStatusToScreen()
{
    double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

    string out = "\n\r";
    out += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)
        + " (UTC/GMT" + StringFormat("%+.1f",offsetInHours) + ")\n\r\n\r";
    out += Symbol() + " TICKS RECEIVED:   "  + IntegerToString(TicksReceivedCount)  + "\n\r";
    out += Symbol() + " TICKS PROCESSED:  "  + IntegerToString(TicksProcessedCount) + "\n\r";
    out += "PROCESSING METHOD: " + EnumToString(BarProcessingMethod) + "\n\r";
    out += "INDICATOR BAR IDX: " + IntegerToString(iBarToUseForProcessing) + "\n\r";
    out += "TRADING TIMEFRAME: " + EnumToString(TradeTimeframe) + "\n\r\n\r";

    if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR && gOHLCLogCount > 0)
    {
        out += "─── LAST OHLC EVENTS ────────────────────────────\n\r";
        int start = MathMax(0, gOHLCLogCount - 10);
        for (int i = start; i < gOHLCLogCount; i++)
        {
            int idx = i % 40;
            out += StringFormat("  %s | %-5s | bid=%.5f  ask=%.5f\n\r",
                                TimeToString(gOHLCLog[idx].barTime,
                                             TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                gOHLCLog[idx].eventName,
                                gOHLCLog[idx].bid,
                                gOHLCLog[idx].ask);
        }
    }

    if (gCtx.IsValid())
    {
        out += "\n\r── CURRENT VIRTUAL TICK ─────────────────────────\n\r";
        out += "  Event : " + gCtx.EventName()                              + "\n\r";
        out += "  Bid   : " + DoubleToString(gCtx.Bid(), _Digits)           + "\n\r";
        out += "  Ask   : " + DoubleToString(gCtx.Ask(), _Digits)           + "\n\r";
        out += "  Time  : " + TimeToString(gCtx.Time(), TIME_DATE|TIME_SECONDS) + "\n\r";
    }

    if (gPendingSignal != SIGNAL_NONE)
    {
        out += "\n\r── PENDING SIGNAL ───────────────────────────────\n\r";
        out += "  Signal : " + EnumToString(gPendingSignal)        + "\n\r";
        out += "  Price  : " + DoubleToString(gPendingPrice,_Digits)+ "\n\r";
        out += "  SL     : " + DoubleToString(gPendingSL,   _Digits)+ "\n\r";
        out += "  TP     : " + DoubleToString(gPendingTP,   _Digits)+ "\n\r";
    }

    Comment(out);
}