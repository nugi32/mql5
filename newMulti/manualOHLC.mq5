//+--------------------------------------------------------------------------------+
//| control-bar-ohlc-virtual.mq5                                                   |
//|                                                                                |
//| Original framework: Darwinex / Martyn Tinsley                                  |
//| OHLC virtual feed integration: replaces the single-fire M1 bar gate            |
//| with a 4-point OHLC pump so that checkEntry / ProcessTradeClosures /            |
//| ProcessTradeOpens are called at each O/L/H/C price level of every M1 bar.      |
//+--------------------------------------------------------------------------------+
#property strict

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_BAR_PROCESSING_METHOD
{
    PROCESS_ALL_DELIVERED_TICKS,              // Process All Delivered Ticks
    ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,       // M1 OHLC Virtual Feed (4 events/bar)
    ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR  // Only Process Ticks From New Bar in Trade TF
};

//--- Which OHLC event fired (for logging and context)
enum ENUM_OHLC_EVENT
{
    OHLC_NONE  = -1,
    OHLC_OPEN  =  0,
    OHLC_LOW   =  1,   // Bull: Low comes before High (per MT5 docs)
    OHLC_HIGH  =  2,
    OHLC_CLOSE =  3
};

//==================================================================
//  INPUTS
//==================================================================
input ENUM_TIMEFRAMES              TradeTimeframe     = PERIOD_M15;
input ENUM_BAR_PROCESSING_METHOD   BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR;

//==================================================================
//  ── VIRTUAL FEED LAYER ──────────────────────────────────────────
//  Implements the MT5 "1-Minute OHLC" tick generation table:
//
//   TickVol = 1  →  [ Close ]
//   TickVol = 2  →  [ Open, Close ]
//   TickVol ≥ 3,
//     Bull (C≥O) →  [ Open, Low, High, Close ]
//     Bear (C<O) →  [ Open, High, Low, Close ]
//   Doji (C==O) → direction = opposite of previous bar
//==================================================================

struct SVirtualTick
{
    datetime      time;
    double        bid;          // OHLC prices are Bid in MT5 history
    double        ask;          // bid + spread * _Point
    double        last;         // = bid
    ENUM_OHLC_EVENT event;      // which OHLC point this tick represents
};

struct SBarDescriptor
{
    datetime barTime;
    double   O, H, L, C;
    long     tickVol;
    int      spread;
    bool     bullish;
};

enum ENUM_ENTRY_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY,
   SIGNAL_SELL
};

ENUM_ENTRY_SIGNAL gPendingSignal = SIGNAL_NONE;
double gPendingSL = 0;
double gPendingTP = 0;
double gPendingPrice = 0;

datetime gLastTradeBar = 0;

datetime gSignalBarTime = 0;
bool     gSignalLocked  = false;
//------------------------------------------------------------------
class CVirtualFeed
{
private:
    string          m_sym;
    SBarDescriptor  m_bar;
    SBarDescriptor  m_prevBar;
    bool            m_hasPrev;

    int             m_seqIdx;
    int             m_seqLen;
    ENUM_OHLC_EVENT m_seq[4];

    datetime        m_lastBarTime;

    //--- Doji resolution: opposite of previous bar direction
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

        if (tv <= 1)
        {
            m_seqLen    = 1;
            m_seq[0]    = OHLC_CLOSE;
            return;
        }
        if (tv == 2)
        {
            m_seqLen    = 2;
            m_seq[0]    = OHLC_OPEN;
            m_seq[1]    = OHLC_CLOSE;
            return;
        }
        // tv >= 3 → full 4-event sequence
        m_seqLen = 4;
        m_seq[0] = OHLC_OPEN;
        m_seq[3] = OHLC_CLOSE;
        if (m_bar.bullish)
        {
            m_seq[1] = OHLC_LOW;   // opening shadow hits Low first
            m_seq[2] = OHLC_HIGH;
        }
        else
        {
            m_seq[1] = OHLC_HIGH;  // opening shadow hits High first
            m_seq[2] = OHLC_LOW;
        }
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
        if (m_seqLen == 1)          return m_bar.barTime + 59;
        if (step == 0)              return m_bar.barTime;
        if (step == m_seqLen - 1)   return m_bar.barTime + 59;
        return m_bar.barTime + (datetime)(step * 59 / (m_seqLen - 1));
    }

    SVirtualTick MakeTick(datetime t, double bidPx, ENUM_OHLC_EVENT ev) const
    {
        double sp = m_bar.spread * _Point;
        SVirtualTick tk;
        tk.time  = t;
        tk.bid   = NormalizeDouble(bidPx, _Digits);
        tk.ask   = NormalizeDouble(bidPx + sp, _Digits);
        tk.last  = tk.bid;
        tk.event = ev;
        return tk;
    }

public:
    void Init(string sym)
    {
        m_sym         = sym;
        m_lastBarTime = 0;
        m_seqIdx      = 4;
        m_seqLen      = 0;
        m_hasPrev     = false;
        ZeroMemory(m_bar);
        ZeroMemory(m_prevBar);
    }

    //--- Returns true + fills 'tick' when a new virtual event is ready.
    bool Next(SVirtualTick &tick)
    {
        if (m_seqIdx >= m_seqLen)
        {
            // Try loading the most-recently completed M1 bar (index 1)
            datetime barTimes[];
            if (CopyTime(m_sym, PERIOD_M1, 1, 1, barTimes) <= 0) return false;
            if (barTimes[0] == m_lastBarTime)                     return false;

            MqlRates rates[];
            if (CopyRates(m_sym, PERIOD_M1, 1, 1, rates) <= 0)   return false;

            m_lastBarTime = barTimes[0];
            m_prevBar     = m_bar;
            m_hasPrev     = true;

            m_bar.barTime = rates[0].time;
            m_bar.O       = rates[0].open;
            m_bar.H       = rates[0].high;
            m_bar.L       = rates[0].low;
            m_bar.C       = rates[0].close;
            m_bar.tickVol = rates[0].tick_volume;
            m_bar.spread  = (int)rates[0].spread;
            if (m_bar.spread <= 0)
                m_bar.spread = (int)SymbolInfoInteger(m_sym, SYMBOL_SPREAD);

            m_bar.bullish = ResolveBullish(m_bar.C >= m_bar.O);
            BuildSequence();
        }

        if (m_seqIdx >= m_seqLen) return false;

        ENUM_OHLC_EVENT ev = m_seq[m_seqIdx];
        double          px = PriceFor(ev);
        datetime        t  = TimeFor(m_seqIdx);

        tick = MakeTick(t, px, ev);
        m_seqIdx++;
        return true;
    }

    bool     HasData()    const { return m_lastBarTime > 0; }
    SBarDescriptor Bar()  const { return m_bar; }
};

//------------------------------------------------------------------
class CVirtualMarketContext
{
private:
    SVirtualTick    m_tick;
    bool            m_valid;

public:
    void Init()  { m_valid = false; ZeroMemory(m_tick); }

    void Update(const SVirtualTick &tk) { m_tick = tk; m_valid = true; }

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
//  GLOBAL INSTANCES
//==================================================================
CVirtualFeed          gFeed;
CVirtualMarketContext gCtx;

//==================================================================
//  EA GLOBALS (from original framework)
//==================================================================
int TicksReceivedCount   = 0;
int TicksProcessedCount  = 0;

// For TRADE_TF mode only — OHLC mode uses gFeed, not this timestamp
datetime TimeLastTickProcessed = D'1971.01.01 00:00';

int iBarToUseForProcessing;

//==================================================================
//  OHLC PROCESSING LOG  (ring buffer of last 40 events)
//==================================================================
struct SOHLCLogEntry
{
    datetime barTime;
    string   eventName;
    double   price;
    double   bid;
    double   ask;
};
SOHLCLogEntry gOHLCLog[40];
int           gOHLCLogCount = 0;

void LogOHLCEvent(const SVirtualTick &tk)
{
    int idx = gOHLCLogCount % 40;
    gOHLCLog[idx].barTime   = tk.time;
    gOHLCLog[idx].eventName = gCtx.EventName();
    gOHLCLog[idx].price     = tk.last;
    gOHLCLog[idx].bid       = tk.bid;
    gOHLCLog[idx].ask       = tk.ask;
    gOHLCLogCount++;

    PrintFormat("OHLC EVENT | %s | %-5s | Bid=%.5f  Ask=%.5f",
                TimeToString(tk.time, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                gCtx.EventName(),
                tk.bid,
                tk.ask);
}

//==================================================================
//  OnInit
//==================================================================
int OnInit()
{
    //--- Indicator handles (use PERIOD_M1 to align with virtual feed)
    atrHandle     = iATR (_Symbol, PERIOD_M1, 14);
    maHandle      = iMA  (_Symbol, PERIOD_M1, 50,  0, MODE_SMA, PRICE_CLOSE);
    sidewayHandle = iMA  (_Symbol, PERIOD_M1, 34,  0, MODE_SMA, PRICE_CLOSE);
    sarHandle     = iSAR (_Symbol, PERIOD_M1, 0.02, 0.2);

    if (atrHandle     == INVALID_HANDLE ||
        maHandle      == INVALID_HANDLE ||
        sidewayHandle == INVALID_HANDLE ||
        sarHandle     == INVALID_HANDLE)
    {
        Print("Init error: ", GetLastError());
        return INIT_FAILED;
    }

    //--- Bar index logic (unchanged from original)
    if (BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
        iBarToUseForProcessing = 0;
    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
        iBarToUseForProcessing = 1;  // use CLOSED bar indicators (see fix #6)
    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
        iBarToUseForProcessing = 1;

    PrintFormat("EA USING %s | INDICATOR BAR INDEX = %d",
                EnumToString(BarProcessingMethod),
                iBarToUseForProcessing);

    //--- Init virtual feed
    gFeed.Init(_Symbol);
    gCtx .Init();

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

    // ─────────────────────────────────────────────────────────────
    //  MODE A: OHLC virtual feed
    //  Each real broker tick pumps the feed.
    //  For every pending OHLC event we update context, log,
    //  then run the full processing block — up to 4× per M1 bar.
    // ─────────────────────────────────────────────────────────────
    if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
    {
        SVirtualTick vTick;
        while (gFeed.Next(vTick))
        {
            gCtx.Update(vTick);
            LogOHLCEvent(vTick);          // ← prints event + prices

            TicksProcessedCount++;

            checkEntry();
            ProcessTradeClosures();
            ProcessTradeOpens();

            AlertFormat("OHLC %s | %s | Bid=%.5f  Ask=%.5f",
                        gCtx.EventName(),
                        Symbol(),
                        gCtx.Bid(),
                        gCtx.Ask());
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  MODE B: Every tick — unchanged
    // ─────────────────────────────────────────────────────────────
    else if (BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
    {
        TicksProcessedCount++;
        checkEntry();
        ProcessTradeClosures();
        ProcessTradeOpens();
        Alert("PROCESSING " + Symbol() + " ON " + EnumToString(TradeTimeframe) + " CHART");
    }

    // ─────────────────────────────────────────────────────────────
    //  MODE C: New Trade-TF bar — unchanged
    // ─────────────────────────────────────────────────────────────
    else if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
    {
        if (TimeLastTickProcessed != iTime(Symbol(), TradeTimeframe, 0))
        {
            TimeLastTickProcessed = iTime(Symbol(), TradeTimeframe, 0);
            TicksProcessedCount++;
            checkEntry();
            ProcessTradeClosures();
            ProcessTradeOpens();
            Alert("PROCESSING " + Symbol() + " ON " + EnumToString(TradeTimeframe) + " CHART");
        }
    }

    OutputStatusToScreen();
}

//==================================================================
//  STRATEGY STUBS
//  Replace with your real logic.
//  Use gCtx.Bid() / gCtx.Ask() / gCtx.Last() for the current price.
//  Use gCtx.Event() or gCtx.EventName() to know which OHLC point fired.
//==================================================================
/*
void checkEntry()
{
    if (!gCtx.IsValid()) return;

    // ── Example: only act on Open and Close events ──────────────
    // ENUM_OHLC_EVENT ev = gCtx.Event();
    // if (ev != OHLC_OPEN && ev != OHLC_CLOSE) return;

    // Read indicators at the CLOSED bar (index 1 = the bar whose
    // OHLC events we are currently processing)
    double atr[], ma[];
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(ma,  true);
    if (CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0) return;
    if (CopyBuffer(maHandle,  0, 0, 3, ma)  <= 0) return;

    double currentATR   = atr[iBarToUseForProcessing];
    double currentMA    = ma [iBarToUseForProcessing];
    double currentPrice = gCtx.Last();   // virtual OHLC price

    // ... your entry logic here ...
}*/

void ProcessTradeClosures()
{
    if (!gCtx.IsValid())
        return;

    // virtual TP / SL
    CheckVirtualStops();

    // break even + trailing
    managePosition();
}

void ProcessTradeOpens()
{
    if (!gCtx.IsValid())
        return;

    if (gPendingSignal == SIGNAL_NONE)
        return;

    if (PositionsTotal() > 0)
    {
        gPendingSignal = SIGNAL_NONE;
        return;
    }

    // optional:
    // buka cuma di OPEN / CLOSE
    ENUM_OHLC_EVENT ev = gCtx.Event();

    if (ev != OHLC_OPEN &&
        ev != OHLC_CLOSE)
        return;

    bool opened = false;

    if (gPendingSignal == SIGNAL_BUY)
    {
        opened = tradeBuy(
            gPendingSL,
            gPendingTP,
            gPendingPrice
        );
    }
    else if (gPendingSignal == SIGNAL_SELL)
    {
        opened = tradeSell(
            gPendingSL,
            gPendingTP,
            gPendingPrice
        );
    }

    if (opened)
{
    Print("OPENED: ", EnumToString(gPendingSignal));
    gPendingSignal = SIGNAL_NONE;
}
}

//==================================================================
//  OutputStatusToScreen — extended with OHLC log
//==================================================================
void OutputStatusToScreen()
{
    double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

    string out = "\n\r";
    out += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
        + " (UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

    out += Symbol() + " TICKS RECEIVED:    " + IntegerToString(TicksReceivedCount)  + "\n\r";
    out += Symbol() + " TICKS PROCESSED:   " + IntegerToString(TicksProcessedCount) + "\n\r";
    out += "PROCESSING METHOD:  " + EnumToString(BarProcessingMethod) + "\n\r";
    out += "INDICATOR BAR IDX:  " + IntegerToString(iBarToUseForProcessing)          + "\n\r";
    out += "TRADING TIMEFRAME:  " + EnumToString(TradeTimeframe)                     + "\n\r\n\r";

    // ── Last 10 OHLC events ──────────────────────────────────────
    if (BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR && gOHLCLogCount > 0)
    {
        out += "─── LAST OHLC EVENTS ────────────────────────────\n\r";
        int start = MathMax(0, gOHLCLogCount - 10);
        for (int i = start; i < gOHLCLogCount; i++)
        {
            int idx = i % 40;
            out += StringFormat("  %s | %-5s | %.5f  (bid=%.5f  ask=%.5f)\n\r",
                                TimeToString(gOHLCLog[idx].barTime,
                                             TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                                gOHLCLog[idx].eventName,
                                gOHLCLog[idx].price,
                                gOHLCLog[idx].bid,
                                gOHLCLog[idx].ask);
        }
    }

    // ── Current virtual context ──────────────────────────────────
    if (gCtx.IsValid())
    {
        out += "\n\r── CURRENT VIRTUAL TICK ─────────────────────────\n\r";
        out += "  Event : " + gCtx.EventName()                              + "\n\r";
        out += "  Bid   : " + DoubleToString(gCtx.Bid(), _Digits)           + "\n\r";
        out += "  Ask   : " + DoubleToString(gCtx.Ask(), _Digits)           + "\n\r";
        out += "  Time  : " + TimeToString(gCtx.Time(), TIME_DATE | TIME_SECONDS) + "\n\r";
    }

    Comment(out);
}

//==================================================================
//  AlertFormat helper (Alert() doesn't support printf-style directly)
//==================================================================
void AlertFormat(string fmt, string a, string b, double c, double d)
{
    Alert(StringFormat(fmt, a, b, c, d));
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
void checkEntry()
{
 if (!gCtx.IsValid())
        return;

    datetime currentTradeBar =
        iTime(_Symbol, TradeTimeframe, 0);

    // reset lock tiap bar M15 baru
    if (currentTradeBar != gLastTradeBar)
    {
        gLastTradeBar = currentTradeBar;
        gSignalLocked = false;
    }

    // sudah ada signal di M15 ini
    if (gSignalLocked)
        return;

    if (!isSideways())
        return;

    if (PositionsTotal() > 0)
        return;

    double atr[], ma[], close[];

    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(ma, true);
    ArraySetAsSeries(close, true);

    if (CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0)
        return;
    if (CopyBuffer(maHandle, 0, 0, 3, ma) <= 0)
        return;
    if (CopyClose(_Symbol, _Period, 0, 3, close) <= 0)
        return;

    double currentATR   = atr[iBarToUseForProcessing];
    double currentMA    = ma [iBarToUseForProcessing];
    double currentPrice = gCtx.Last();   // virtual OHLC price

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

    gPendingSignal = SIGNAL_SELL;
    gPendingSL     = sl;
    gPendingTP     = tp;
    gPendingPrice  = currentPrice;

    gSignalLocked  = true;

    return;
        }

        // BUY
        if (currentPrice < currentMA && deviation > threshold)
        {
    sl = currentPrice - (currentATR * SL_Multiplier);
    tp = currentPrice + (currentATR * TP_Multiplier);

    gPendingSignal = SIGNAL_BUY;
    gPendingSL     = sl;
    gPendingTP     = tp;
    gPendingPrice  = currentPrice;

    gSignalLocked  = true;

    return;
        }
    }
    else if (useEma)
    {
        // SELL
        if (currentPrice > currentMA && deviation > threshold)
        {
 sl = currentPrice + (currentATR * SL_Multiplier);
    tp = currentPrice - (currentATR * TP_Multiplier);

    gPendingSignal = SIGNAL_SELL;
    gPendingSL     = sl;
    gPendingTP     = tp;
    gPendingPrice  = currentPrice;

    gSignalLocked  = true;

    return;
        }

        // BUY
        if (currentPrice < currentMA && deviation > threshold)
        {
    sl = currentPrice - (currentATR * SL_Multiplier);
    tp = currentPrice + (currentATR * TP_Multiplier);

    gPendingSignal = SIGNAL_BUY;
    gPendingSL     = sl;
    gPendingTP     = tp;
    gPendingPrice  = currentPrice;

    gSignalLocked  = true;

    return;
        }
    }
    else if (useTrailingStop)
    {
        // SELL
        if (currentPrice > currentMA && deviation > threshold)
        {
 sl = currentPrice + (currentATR * SL_Multiplier);
    tp = currentPrice - (currentATR * TP_Multiplier);

    gPendingSignal = SIGNAL_SELL;
    gPendingSL     = sl;
    gPendingTP     = tp;
    gPendingPrice  = currentPrice;

    gSignalLocked  = true;

    return;
        }

        // BUY
        if (currentPrice < currentMA && deviation > threshold)
        {
    sl = currentPrice - (currentATR * SL_Multiplier);
    tp = currentPrice + (currentATR * TP_Multiplier);

    gPendingSignal = SIGNAL_BUY;
    gPendingSL     = sl;
    gPendingTP     = tp;
    gPendingPrice  = currentPrice;

    gSignalLocked  = true;

    return;
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
? gCtx.Bid()
: gCtx.Ask();

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