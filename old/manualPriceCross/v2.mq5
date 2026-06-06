//+------------------------------------------------------------------+
//|                                        PersistenceEA.mq5         |
//|                     Trend Persistence Framework                  |
//|                                                                  |
//|  REFACTORED FROM: EMA Cross → Immediate Trade                   |
//|  REFACTORED TO:   EMA Cross → Candidate → Score Gate → Trade    |
//|                                                                  |
//|  SIGNAL FLOW:                                                    |
//|  [New Bar] → [Candidate Detection]                               |
//|           → [Regime Filter (isSideways)]                         |
//|           → [Persistence Scoring A+B+C+D+E+F]                   |
//|           → [Score >= Threshold?] → [Order Execution]           |
//|                                                                  |
//|  SCORE COMPONENTS (max 10 points):                               |
//|    A — Volatility Expansion        (max 3)                       |
//|    B — Compression → Expansion     (max 1)                       |
//|    C — Persistence Metrics         (max 2)                       |
//|    D — Structure Acceptance        (max 1)                       |
//|    E — Fast EMA Trend Quality      (max 1)                       |
//|    F — Higher Timeframe            (max 2)                       |
//|                                                                  |
//|  PRESERVED UNCHANGED:                                            |
//|    Virtual SL management (CheckVirtualStops, AddVirtualSL, etc) |
//|    New bar detection (lastBarTime guard)                         |
//|    Order execution (OpenBuy, OpenSell, ClosePosition)            |
//|    SAR-based trailing stop (UpdateTrailingVirtualSL)             |
//+------------------------------------------------------------------+
#property strict

//=============================================================================
//  SECTION 1 — PRESERVED INPUTS
//  Identical names/defaults to original to avoid breaking existing sets.
//=============================================================================

input group "--- Visual ---"
input color  BuyDotColor   = clrLime;
input color  SellDotColor  = clrRed;
input int    DotDistance   = 100;

input group "--- EMA ---"
input int    FastEMA        = 10;
input int    EMAPeriod      = 50;
input int    SlopeLookback  = 5;
input double SlopeThreshold = 50.0;

input group "--- ATR / SAR / Trade ---"
input int    atrPeriod     = 14;
input double atrMultiplier = 1.0;
input double SarStep       = 0.02;
input double SarMax        = 0.2;
input double LotSize       = 0.01;
input int    Slippage      = 10;
input ulong  MagicNumber   = 123456;

//=============================================================================
//  SECTION 2 — PERSISTENCE FRAMEWORK INPUTS (NEW)
//
//  Design principle: every threshold is externally configurable.
//  Nothing is hardcoded. This allows walk-forward parameter sweeps
//  without recompiling the EA. Start with the defaults below and
//  validate via out-of-sample forward returns before modifying.
//=============================================================================

input group "--- [PERSIST] Gate: Minimum Score Required ---"
// Trades are only executed when PersistenceScore >= MinPersistenceScore.
// Scale: 0-10. Default 5 = balanced. Raise to 6-7 for stricter filtering.
// Lower to 4 only if forward-return analysis supports it.
input int MinPersistenceScore = 5;

//--- Component A: Volatility Expansion (max 3 points) ---
// Rationale: Trends with positive expectancy almost universally emerge from
// volatility expansion events. Three independent sub-signals reward:
//   A1 — ATR expanding above its baseline (energy is entering the market)
//   A2 — Signal candle is wide relative to recent history (range expansion)
//   A3 — Close is located strongly in the trend direction (conviction)
input group "--- [PERSIST] A: Volatility Expansion (max 3 pts) ---"
input int    AtrMAPeriod       = 20;   // ATR smoothing period for baseline
input double AtrExpansionRatio = 1.20; // ATR[1] > AtrMA * ratio → +1
input int    RangeLookback     = 20;   // Bars for range-percentile calculation
input double RangePercentile   = 60.0; // Signal range must beat X% of prior bars → +1
input double CloseLocationMin  = 0.60; // Close in top/bottom X% of candle range → +1

//--- Component B: Compression → Expansion (max 1 point) ---
// Rationale: Volatility is mean-reverting. Compression builds kinetic energy.
// When expansion follows a measurable compression window, the resulting move
// is more likely to be directional rather than random noise. This filter
// rewards the classic "squeeze → breakout" setup at an ATR level,
// without relying on any specific chart pattern or indicator.
input group "--- [PERSIST] B: Compression → Expansion (max 1 pt) ---"
input int    CompressionLookback = 8;    // Prior bars to measure ATR compression
input double CompressionRatio    = 0.85; // priorAvgATR < currentATR * ratio → +1

//--- Component C: Persistence Metrics (max 2 points) ---
// Rationale: A single high-expansion bar is necessary but not sufficient.
// If the preceding N bars have already been closing on the trend side of
// the fast EMA, it indicates the market has been accepting the move — not
// just spiking. A dominant candle body adds confirmation that the signal
// bar itself represents directional commitment, not indecision.
input group "--- [PERSIST] C: Persistence Metrics (max 2 pts) ---"
input int    ConsecutiveClosesBars = 2;    // N bars closing above/below fast EMA → +1
input double BodyRatioMin          = 0.50; // Body/Range of signal candle ≥ this → +1

//--- Component D: Structure Acceptance (max 1 point) ---
// Rationale: An EMA event inside a prior range may simply be the market
// revisiting known territory. A close that exceeds the prior N-bar structure
// high/low indicates the market has moved to genuinely new ground — a
// necessary condition for a structural trend move, not a range oscillation.
input group "--- [PERSIST] D: Structure Acceptance (max 1 pt) ---"
input int StructureLookback = 10; // Bars 2..N+1 define the prior structure range

//--- Component E: Fast EMA Trend Quality (max 1 point) ---
// Rationale: The slow EMA already acts as a binary regime gate (isSideways).
// This component additionally requires the fast EMA slope to agree — meaning
// short-term momentum is aligned with the signal. This dual-slope check
// is a proxy for "the short-term trend is consistent with the medium-term
// trend," reducing the probability of catching a temporary counter-swing.
input group "--- [PERSIST] E: Fast EMA Trend Quality (max 1 pt) ---"
input int    FastSlopeLookback  = 3;
input double FastSlopeThreshold = 20.0;

//--- Component F: Higher Timeframe Confirmation (max 2 points) ---
// Rationale: HTF context is the single most powerful class-level filter for
// trade quality. A trade with the HTF bias has a structurally higher prior
// probability of continuation because it is aligned with more capital and
// longer holding horizons. Two points reward: (1) directional agreement
// and (2) a sufficiently strong HTF slope (trend conviction, not a drift).
input group "--- [PERSIST] F: Higher Timeframe Confirmation (max 2 pts) ---"
input bool            UseHTF            = true;
input ENUM_TIMEFRAMES HTFPeriod         = PERIOD_H4;
input int             HTFEMAPeriod      = 50;
input int             HTFSlopeLookback  = 5;
input double          HTFSlopeThreshold = 30.0;

//=============================================================================
//  SECTION 3 — GLOBALS AND STRUCTS
//=============================================================================
datetime lastBarTime = 0;

int emaHandle  = INVALID_HANDLE; // Slow EMA  — regime gate
int fastHandle = INVALID_HANDLE; // Fast EMA  — signal detection + quality
int atrHandle  = INVALID_HANDLE; // ATR       — volatility measurement
int sarHandle  = INVALID_HANDLE; // SAR       — trailing stop
int htfHandle  = INVALID_HANDLE; // HTF EMA   — higher timeframe confirmation

// Virtual SL record — PRESERVED UNCHANGED
struct VirtualSL
{
    ulong  ticket;
    double sl;
};
VirtualSL vsl[];

// Score breakdown — populated for every candidate, logged for diagnostics.
// Logging every candidate (not just qualified trades) enables post-hoc
// analysis: you can measure how often each component fired and how strongly
// it correlates with forward returns.
struct PersistenceBreakdown
{
    int scoreA; // Volatility Expansion:    0-3
    int scoreB; // Compression→Expansion:   0-1
    int scoreC; // Persistence Metrics:     0-2
    int scoreD; // Structure Acceptance:    0-1
    int scoreE; // Fast EMA Trend Quality:  0-1
    int scoreF; // Higher Timeframe:        0-2
    int total;  // Aggregate:               0-10
};

//=============================================================================
//  SECTION 4 — HELPER: DOT VISUALIZATION (PRESERVED UNCHANGED)
//=============================================================================
void CreateDot(string name, datetime t, double price, color clr)
{
    if (ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//=============================================================================
//  SECTION 5 — MARKET REGIME FILTER (PRESERVED UNCHANGED)
//
//  Role in new framework: hard binary pre-gate, NOT a score component.
//  Persistence scoring is never evaluated in sideways regimes — the slow EMA
//  slope must confirm a trending condition before candidates are scored.
//  This prevents the scoring system from evaluating low-quality candidates
//  that would fail the regime check regardless of other factors.
//=============================================================================
bool isSideways()
{
    double buf[];
    ArraySetAsSeries(buf, true);

    if (CopyBuffer(emaHandle, 0, 0, SlopeLookback + 1, buf) <= 0)
    {
        Print("isSideways: CopyBuffer failed: ", GetLastError());
        return true; // fail-safe: treat as sideways on error
    }

    double slope = (buf[0] - buf[SlopeLookback]) / _Point;
    Print("EMA Slope = ", slope);

    if (slope >=  SlopeThreshold) { Print("GREEN TREND UP");               return false; }
    if (slope <= -SlopeThreshold) { Print("RED TREND DOWN");               return false; }

    Print("SIDEWAYS — persistence scoring bypassed");
    return true;
}

//=============================================================================
//  SECTION 6 — CANDIDATE DETECTION
//
//  KEY ARCHITECTURAL CHANGE:
//  In the original EA, these conditions triggered trades directly.
//  In the refactored EA, they are "candidate events" only.
//
//  A candidate means: "something EMA-related happened."
//  It is necessary but NOT sufficient to enter a trade.
//  The persistence score determines sufficiency.
//
//  All original signal types are preserved so that no candidate class
//  is lost — they are simply reclassified as candidates, not triggers.
//=============================================================================
bool DetectBuyCandidate(const double &close[], const double &open[],
                         const double &high[],  const double &low[],
                         const double &fast[],  double m)
{
    // Original S1: closed below EMA, now closes above → trend cross
    bool crossAbove  = close[2] < fast[2] && close[1] > fast[1] + m;

    // Original S2: opened below EMA, engulfed, closed above → power candle
    bool engulfAbove = open[1] < fast[1] - m && close[1] > fast[1] + m;

    // Original S3: high was below EMA, now closes above → full range reclaim
    bool breakAbove  = high[2] < fast[2] && close[1] > fast[1] + m;

    // Bounce: was above EMA, dipped near it, closed back above → continuation
    bool bounce      = close[2] > fast[2]
                    && low[1]   <= fast[1] + m
                    && close[1] > fast[1] + m;

    // Rejection: wick pierced below EMA but body held above → failed breakdown
    bool rejection   = low[1]  < fast[1]
                    && open[1] > fast[1]
                    && close[1] > fast[1] + m;

    // Reclaim: was below EMA for 2 bars, reclaims above → trend shift
    bool reclaim     = close[2] < fast[2] && close[1] > fast[1] + m;

    return crossAbove || engulfAbove || breakAbove || bounce || rejection || reclaim;
}

bool DetectSellCandidate(const double &close[], const double &open[],
                          const double &high[],  const double &low[],
                          const double &fast[],  double m)
{
    bool crossBelow  = close[2] > fast[2] && close[1] < fast[1] - m;
    bool engulfBelow = open[1]  > fast[1] + m && close[1] < fast[1] - m;
    bool breakBelow  = low[2]   > fast[2] && close[1] < fast[1] - m;
    bool bounce      = close[2] < fast[2]
                    && high[1]  >= fast[1] - m
                    && close[1] < fast[1] - m;
    bool rejection   = high[1] > fast[1]
                    && open[1] < fast[1]
                    && close[1] < fast[1] - m;
    bool reclaim     = close[2] > fast[2] && close[1] < fast[1] - m;

    return crossBelow || engulfBelow || breakBelow || bounce || rejection || reclaim;
}

//=============================================================================
//  SECTION 7 — SCORE COMPONENT A: VOLATILITY EXPANSION (max 3)
//
//  Three independent sub-signals, each awarded +1 point:
//
//  A1 — ATR Expansion:
//       Current ATR exceeds a moving average of recent ATR values by a ratio.
//       This measures whether energy (volatility) is increasing — a necessary
//       precondition for a move that will carry far enough to generate profit.
//
//  A2 — Range Percentile:
//       The signal candle's high-low range ranked against the prior N bars.
//       A candle in the top 60th percentile is unusually wide — indicative of
//       institutional participation or genuine momentum, not noise.
//
//  A3 — Close Location:
//       How strongly did price close within the candle's range?
//       Bulls: top 60% of the candle. Bears: bottom 40%.
//       A strong close location implies the directional move sustained
//       through the entire bar — not a spike that reversed before close.
//=============================================================================
int ScoreA_VolatilityExpansion(int direction)
{
    int score = 0;

    // --- A1: ATR Expansion ---
    // Load (AtrMAPeriod + 2) bars of ATR from bar[0].
    // atrBuf[1] = signal bar ATR. atrBuf[2..AtrMAPeriod+1] = prior ATR values.
    int atrNeeded = AtrMAPeriod + 2;
    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if (CopyBuffer(atrHandle, 0, 0, atrNeeded, atrBuf) < atrNeeded)
        return score; // bail without penalizing if data unavailable

    double currentATR = atrBuf[1];
    double atrSum     = 0.0;
    for (int i = 2; i < atrNeeded; i++) atrSum += atrBuf[i];
    double atrMA = atrSum / AtrMAPeriod;

    if (atrMA > 0.0 && currentATR > atrMA * AtrExpansionRatio)
        score++; // A1 confirmed: volatility expanding above recent baseline

    // --- A2: Range Percentile ---
    // CopyHigh/Low with startShift=1, count=RangeLookback:
    // hi[0]/lo[0] = bar[1] (signal candle), hi[1..]/lo[1..] = prior bars.
    double hi[], lo[];
    ArraySetAsSeries(hi, true);
    ArraySetAsSeries(lo, true);
    if (CopyHigh(_Symbol, PERIOD_CURRENT, 1, RangeLookback, hi) < RangeLookback) return score;
    if (CopyLow (_Symbol, PERIOD_CURRENT, 1, RangeLookback, lo) < RangeLookback) return score;

    double signalRange = hi[0] - lo[0];
    int countBelow = 0;
    for (int i = 1; i < RangeLookback; i++)
        if ((hi[i] - lo[i]) <= signalRange) countBelow++;

    double rangePct = (double)countBelow / (RangeLookback - 1) * 100.0;
    if (rangePct >= RangePercentile)
        score++; // A2 confirmed: signal candle range is unusually wide

    // --- A3: Close Location ---
    double cl[];
    ArraySetAsSeries(cl, true);
    if (CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, cl) < 1) return score;

    double totalRange = hi[0] - lo[0];
    if (totalRange > 0.0)
    {
        double closeLoc = (cl[0] - lo[0]) / totalRange; // 0.0 = at low, 1.0 = at high
        if (direction ==  1 && closeLoc >= CloseLocationMin)        score++; // bull
        if (direction == -1 && closeLoc <= (1.0 - CloseLocationMin)) score++; // bear
    }

    return score; // max 3
}

//=============================================================================
//  SECTION 8 — SCORE COMPONENT B: COMPRESSION → EXPANSION (max 1)
//
//  Concept: Volatility is mean-reverting. When ATR has been declining over
//  the prior N bars (compression), the market is coiling. If the signal
//  bar's ATR is meaningfully higher than the compressed baseline, the
//  move is more likely to be a genuine breakout from compression than
//  a random fluctuation within a volatile environment.
//
//  Statistical basis: range expansion after contraction has a higher
//  autocorrelation of directional movement than expansion from already-high
//  volatility (Engle, ARCH literature; Mandelbrot volatility clustering).
//=============================================================================
int ScoreB_CompressionExpansion(int direction)
{
    // needed = CompressionLookback + 2 because:
    // atrBuf[0] = bar[0] (current, forming), atrBuf[1] = bar[1] (signal),
    // atrBuf[2..CompressionLookback+1] = the prior compression window.
    int needed = CompressionLookback + 2;
    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if (CopyBuffer(atrHandle, 0, 0, needed, atrBuf) < needed) return 0;

    double currentATR  = atrBuf[1];
    double priorSum    = 0.0;
    for (int i = 2; i < needed; i++) priorSum += atrBuf[i];
    double priorAvgATR = priorSum / CompressionLookback;

    // Prior average ATR was compressed (below currentATR * CompressionRatio)
    if (priorAvgATR > 0.0 && priorAvgATR < currentATR * CompressionRatio)
        return 1; // B confirmed: compression → expansion detected

    return 0;
}

//=============================================================================
//  SECTION 9 — SCORE COMPONENT C: PERSISTENCE METRICS (max 2)
//
//  C1 — Consecutive Closes:
//       The last N completed bars all closed on the correct side of the fast
//       EMA. This is direct evidence of market acceptance — not just a one-bar
//       event. If the prior bars were closing in the trend direction, the
//       probability that the next bar continues is conditionally higher.
//
//  C2 — Signal Candle Body Quality:
//       Body/Range ratio of the signal candle (bar[1]).
//       A body ≥ 50% of total range indicates a directional candle.
//       Doji candles and spinning tops fail this — they represent indecision
//       and are poor candidates for trend persistence, regardless of their
//       position relative to the EMA.
//=============================================================================
int ScoreC_PersistenceMetrics(int direction)
{
    int score = 0;

    // --- C1: Consecutive Closes ---
    // CopyClose with startShift=1, count=needed: cl[0]=bar[1], cl[1]=bar[2], ...
    // CopyBuffer fastHandle with startShift=1, count=needed: same alignment.
    int needed = ConsecutiveClosesBars + 1;
    double cl[], fema[];
    ArraySetAsSeries(cl,   true);
    ArraySetAsSeries(fema, true);
    if (CopyClose(_Symbol, PERIOD_CURRENT, 1, needed, cl)   < needed) return score;
    if (CopyBuffer(fastHandle, 0, 1, needed, fema)          < needed) return score;

    bool allConsecutive = true;
    for (int i = 0; i < ConsecutiveClosesBars; i++)
    {
        if (direction ==  1 && cl[i] <= fema[i]) { allConsecutive = false; break; }
        if (direction == -1 && cl[i] >= fema[i]) { allConsecutive = false; break; }
    }
    if (allConsecutive) score++; // C1 confirmed: market accepting the move

    // --- C2: Body Quality of Signal Candle (bar[1]) ---
    double op[], hi[], lo[];
    ArraySetAsSeries(op, true);
    ArraySetAsSeries(hi, true);
    ArraySetAsSeries(lo, true);
    if (CopyOpen (_Symbol, PERIOD_CURRENT, 1, 1, op) < 1) return score;
    if (CopyHigh (_Symbol, PERIOD_CURRENT, 1, 1, hi) < 1) return score;
    if (CopyLow  (_Symbol, PERIOD_CURRENT, 1, 1, lo) < 1) return score;

    double totalRange = hi[0] - lo[0];
    double body       = MathAbs(cl[0] - op[0]);
    if (totalRange > 0.0 && (body / totalRange) >= BodyRatioMin)
        score++; // C2 confirmed: conviction candle, not indecision

    return score; // max 2
}

//=============================================================================
//  SECTION 10 — SCORE COMPONENT D: STRUCTURE ACCEPTANCE (max 1)
//
//  Concept: The EMA is not a structural level — it moves with price and
//  can be crossed during ordinary range oscillation. A structural breakout
//  occurs when price closes beyond the prior N-bar high (bull) or low (bear).
//  This filters EMA events that occur within an established range from
//  those that represent genuine new territory.
//
//  "Prior structure" = bars 2..StructureLookback+1 (excluding signal bar[1]
//  and the forming bar[0]).
//=============================================================================
int ScoreD_StructureAcceptance(int direction)
{
    int needed = StructureLookback + 2;
    double hi[], lo[], cl[];
    ArraySetAsSeries(hi, true);
    ArraySetAsSeries(lo, true);
    ArraySetAsSeries(cl, true);

    // Fetch from bar[0] so hi[0]=bar[0], hi[1]=bar[1] (signal), hi[2..]=prior structure
    if (CopyHigh (_Symbol, PERIOD_CURRENT, 0, needed, hi) < needed) return 0;
    if (CopyLow  (_Symbol, PERIOD_CURRENT, 0, needed, lo) < needed) return 0;
    if (CopyClose(_Symbol, PERIOD_CURRENT, 1, 1,      cl) < 1)      return 0;

    // Build prior structure range from bars 2..needed-1
    double structHigh = hi[2];
    double structLow  = lo[2];
    for (int i = 3; i < needed; i++)
    {
        if (hi[i] > structHigh) structHigh = hi[i];
        if (lo[i] < structLow)  structLow  = lo[i];
    }

    double signalClose = cl[0]; // close of bar[1]

    if (direction ==  1 && signalClose > structHigh) return 1; // D confirmed: bull structure break
    if (direction == -1 && signalClose < structLow)  return 1; // D confirmed: bear structure break

    return 0;
}

//=============================================================================
//  SECTION 11 — SCORE COMPONENT E: FAST EMA TREND QUALITY (max 1)
//
//  The slow EMA (EMAPeriod) is already used as a binary regime gate.
//  This component checks the fast EMA (FastEMA) slope independently.
//  When both the slow EMA (regime gate) and fast EMA (quality score) agree
//  in direction AND magnitude, the signal has multi-horizon momentum support.
//
//  Note: FastSlopeThreshold will typically be lower than SlopeThreshold
//  because the fast EMA reacts more quickly and has a steeper raw slope.
//  Calibrate separately per instrument and timeframe.
//=============================================================================
int ScoreE_TrendQuality(int direction)
{
    int needed = FastSlopeLookback + 2;
    double fema[];
    ArraySetAsSeries(fema, true);
    if (CopyBuffer(fastHandle, 0, 0, needed, fema) < needed) return 0;

    // Slope of fast EMA measured from bar[1+FastSlopeLookback] to bar[1]
    double fastSlope = (fema[1] - fema[1 + FastSlopeLookback]) / _Point;

    if (direction ==  1 && fastSlope >=  FastSlopeThreshold) return 1; // E confirmed: bull momentum
    if (direction == -1 && fastSlope <= -FastSlopeThreshold) return 1; // E confirmed: bear momentum

    return 0;
}

//=============================================================================
//  SECTION 12 — SCORE COMPONENT F: HIGHER TIMEFRAME CONFIRMATION (max 2)
//
//  F1 (+1): HTF EMA is sloping in the same direction as the signal.
//           This is the minimum condition for "with-trend" classification.
//
//  F2 (+1): HTF EMA slope exceeds HTFSlopeThreshold — indicating the HTF
//           trend has genuine momentum, not merely a weak directional drift.
//           A strong HTF trend materially increases the prior probability
//           that the LTF move will be sustained (trend-following returns
//           are higher when the HTF trend is clear and strong).
//
//  If UseHTF = false, this component scores 0 and does not penalize.
//  The minimum score threshold should be adjusted accordingly (e.g. lower
//  MinPersistenceScore by 1-2 if HTF is disabled).
//=============================================================================
int ScoreF_HigherTimeframe(int direction)
{
    if (!UseHTF || htfHandle == INVALID_HANDLE) return 0;

    int score  = 0;
    int needed = HTFSlopeLookback + 2;
    double htfBuf[];
    ArraySetAsSeries(htfBuf, true);
    if (CopyBuffer(htfHandle, 0, 0, needed, htfBuf) < needed) return 0;

    // Slope of HTF EMA measured from bar[1+HTFSlopeLookback] to bar[1]
    double htfSlope = (htfBuf[1] - htfBuf[1 + HTFSlopeLookback]) / _Point;

    if (direction ==  1 && htfSlope > 0.0) score++; // F1: HTF directional agreement
    if (direction == -1 && htfSlope < 0.0) score++;

    if (direction ==  1 && htfSlope >=  HTFSlopeThreshold) score++; // F2: HTF trend strength
    if (direction == -1 && htfSlope <= -HTFSlopeThreshold) score++;

    return score; // max 2
}

//=============================================================================
//  SECTION 13 — MASTER PERSISTENCE SCORE AGGREGATOR
//
//  Combines all six component scores into a single persistence score.
//  Returns a fully populated PersistenceBreakdown for logging.
//
//  Total max = 3 + 1 + 2 + 1 + 1 + 2 = 10
//
//  The modular design allows individual components to be disabled
//  (by setting their threshold to an extreme value) without restructuring
//  the code. It also isolates each component for independent testing.
//=============================================================================
PersistenceBreakdown CalcPersistenceScore(int direction)
{
    PersistenceBreakdown bd;
    bd.scoreA = ScoreA_VolatilityExpansion(direction);  // max 3
    bd.scoreB = ScoreB_CompressionExpansion(direction); // max 1
    bd.scoreC = ScoreC_PersistenceMetrics(direction);   // max 2
    bd.scoreD = ScoreD_StructureAcceptance(direction);  // max 1
    bd.scoreE = ScoreE_TrendQuality(direction);         // max 1
    bd.scoreF = ScoreF_HigherTimeframe(direction);      // max 2
    bd.total  = bd.scoreA + bd.scoreB + bd.scoreC
              + bd.scoreD + bd.scoreE + bd.scoreF;      // max 10
    return bd;
}

//=============================================================================
//  SECTION 14 — EXPERT INITIALIZATION
//=============================================================================
int OnInit()
{
    emaHandle  = iMA(_Symbol, PERIOD_CURRENT, EMAPeriod,    0, MODE_EMA, PRICE_CLOSE);
    fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMA,      0, MODE_EMA, PRICE_CLOSE);
    atrHandle  = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
    sarHandle  = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);
    htfHandle  = UseHTF
                 ? iMA(_Symbol, HTFPeriod, HTFEMAPeriod, 0, MODE_EMA, PRICE_CLOSE)
                 : INVALID_HANDLE;

    // Validate required handles — fail hard if any are missing
    if (emaHandle  == INVALID_HANDLE ||
        fastHandle == INVALID_HANDLE ||
        atrHandle  == INVALID_HANDLE ||
        sarHandle  == INVALID_HANDLE)
    {
        Print("PersistenceEA OnInit: required indicator handle creation failed.");
        return INIT_FAILED;
    }

    // HTF handle is optional — warn but continue
    if (UseHTF && htfHandle == INVALID_HANDLE)
        Print("PersistenceEA OnInit: WARNING — HTF handle failed. ScoreF will return 0.");

    ArrayResize(vsl, 0);

    PrintFormat("PersistenceEA initialized | Min score = %d/10 | HTF = %s (%s EMA%d)",
                MinPersistenceScore,
                UseHTF ? "ON" : "OFF",
                UseHTF ? EnumToString(HTFPeriod) : "N/A",
                HTFEMAPeriod);

    return INIT_SUCCEEDED;
}

//=============================================================================
//  SECTION 15 — MAIN TICK HANDLER (REFACTORED)
//
//  Signal Flow:
//  1. [New Bar Guard]          — PRESERVED
//  2. [CheckVirtualStops]      — PRESERVED
//  3. [Data Load]              — PRESERVED
//  4. [Candidate Detection]    — NEW ROLE: candidates, not triggers
//  5. [UpdateTrailingVirtualSL] — PRESERVED
//  6. [HasOpenPosition]        — PRESERVED
//  7. [isSideways regime gate] — PRESERVED (hard binary pre-gate)
//  8. [CalcPersistenceScore]   — NEW: scores each candidate
//  9. [Score Gate]             — NEW: score >= threshold → trade
// 10. [OpenBuy / OpenSell]     — PRESERVED architecture
// 11. [Dot visualization]      — PRESERVED
//=============================================================================
void OnTick()
{
    // ----------------------------------------------------------------
    // STEP 1: NEW BAR DETECTION — PRESERVED UNCHANGED
    // ----------------------------------------------------------------
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (currentBar == lastBarTime) return;
    lastBarTime = currentBar;

    // ----------------------------------------------------------------
    // STEP 2: VIRTUAL STOP MANAGEMENT — PRESERVED UNCHANGED
    // ----------------------------------------------------------------
    CheckVirtualStops();

    // ----------------------------------------------------------------
    // STEP 3: DATA LOAD
    // ----------------------------------------------------------------
    double fast[], atr[], close[], open[], high[], low[];
    ArraySetAsSeries(fast,  true);
    ArraySetAsSeries(atr,   true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open,  true);
    ArraySetAsSeries(high,  true);
    ArraySetAsSeries(low,   true);

    if (CopyBuffer(fastHandle, 0, 0, 3, fast)           < 3) return;
    if (CopyBuffer(atrHandle,  0, 0, 3, atr)            < 3) return;
    if (CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3) return;
    if (CopyOpen (_Symbol, PERIOD_CURRENT, 0, 3, open)  < 3) return;
    if (CopyHigh (_Symbol, PERIOD_CURRENT, 0, 3, high)  < 3) return;
    if (CopyLow  (_Symbol, PERIOD_CURRENT, 0, 3, low)   < 3) return;

    double currentPrice = close[0];
    double m = atr[1] * 0.15; // EMA proximity margin (inherited from original)

    // ----------------------------------------------------------------
    // STEP 4: CANDIDATE DETECTION — NEW ROLE
    //
    // All EMA events are now "candidates." A candidate is a necessary
    // condition for a trade, but it is no longer sufficient by itself.
    // The persistence score provides the sufficiency condition.
    // ----------------------------------------------------------------
    bool buyCandidate  = DetectBuyCandidate (close, open, high, low, fast, m);
    bool sellCandidate = DetectSellCandidate(close, open, high, low, fast, m);

    // ----------------------------------------------------------------
    // STEP 5: TRAILING STOP UPDATE — PRESERVED UNCHANGED
    // ----------------------------------------------------------------
    UpdateTrailingVirtualSL();

    // ----------------------------------------------------------------
    // STEP 6: SKIP IF ALREADY IN POSITION — PRESERVED UNCHANGED
    // ----------------------------------------------------------------
    if (HasOpenPosition()) return;

    // ----------------------------------------------------------------
    // STEP 7: REGIME FILTER — PRESERVED AS HARD BINARY GATE
    //
    // This is not a score component. It is a hard pre-filter.
    // Persistence scoring is never evaluated in sideways regimes.
    // If the slow EMA does not confirm a trend, no candidates are
    // scored regardless of how high their other metrics might be.
    // ----------------------------------------------------------------
    if (isSideways()) return;

    // ----------------------------------------------------------------
    // STEP 8 + 9: PERSISTENCE SCORING AND QUALIFICATION
    //
    // Only candidates detected in a trending regime reach this stage.
    // Each candidate is scored independently. The score breakdown is
    // always logged — even for rejected candidates. This creates a
    // data record for post-hoc statistical validation (see Section 16).
    // ----------------------------------------------------------------
    bool buySignal  = false;
    bool sellSignal = false;

    if (buyCandidate)
    {
        PersistenceBreakdown bd = CalcPersistenceScore(1);

        PrintFormat("[BUY  CANDIDATE] Score %d/%d | A:%d B:%d C:%d D:%d E:%d F:%d",
                    bd.total, MinPersistenceScore,
                    bd.scoreA, bd.scoreB, bd.scoreC,
                    bd.scoreD, bd.scoreE, bd.scoreF);

        if (bd.total >= MinPersistenceScore)
        {
            buySignal = true;
            Print("[BUY  QUALIFIED] Persistence threshold passed.");
        }
        else
            Print("[BUY  REJECTED]  Score below threshold. Candidate skipped.");
    }

    if (sellCandidate)
    {
        PersistenceBreakdown bd = CalcPersistenceScore(-1);

        PrintFormat("[SELL CANDIDATE] Score %d/%d | A:%d B:%d C:%d D:%d E:%d F:%d",
                    bd.total, MinPersistenceScore,
                    bd.scoreA, bd.scoreB, bd.scoreC,
                    bd.scoreD, bd.scoreE, bd.scoreF);

        if (bd.total >= MinPersistenceScore)
        {
            sellSignal = true;
            Print("[SELL QUALIFIED] Persistence threshold passed.");
        }
        else
            Print("[SELL REJECTED]  Score below threshold. Candidate skipped.");
    }

    // ----------------------------------------------------------------
    // STEP 10: ORDER EXECUTION — PRESERVED ARCHITECTURE UNCHANGED
    // ----------------------------------------------------------------
    if (buySignal)
        OpenBuy(currentPrice - atr[1] * atrMultiplier);

    if (sellSignal)
        OpenSell(currentPrice + atr[1] * atrMultiplier);

    // ----------------------------------------------------------------
    // STEP 11: DOT VISUALIZATION — PRESERVED UNCHANGED
    // Dots indicate regime direction, independent of trade qualification.
    // ----------------------------------------------------------------
    double buf[];
    ArraySetAsSeries(buf, true);
    CopyBuffer(emaHandle, 0, 0, SlopeLookback + 1, buf);
    double slope = (buf[0] - buf[SlopeLookback]) / _Point;

    double   high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double   low1  = iLow (_Symbol, PERIOD_CURRENT, 1);
    datetime t1    = iTime(_Symbol, PERIOD_CURRENT, 1);

    if (slope >= SlopeThreshold)
        CreateDot("BUY_DOT_"  + IntegerToString((int)t1), t1,
                  low1  - DotDistance * _Point, BuyDotColor);
    else if (slope <= -SlopeThreshold)
        CreateDot("SELL_DOT_" + IntegerToString((int)t1), t1,
                  high1 + DotDistance * _Point, SellDotColor);
}

//=============================================================================
//  SECTION 16 — EXPERT DEINITIALIZATION
//=============================================================================
void OnDeinit(const int reason)
{
    IndicatorRelease(fastHandle);
    IndicatorRelease(emaHandle);
    IndicatorRelease(atrHandle);
    IndicatorRelease(sarHandle);
    if (htfHandle != INVALID_HANDLE) IndicatorRelease(htfHandle);
}

//=============================================================================
//  SECTIONS 17-END — VIRTUAL POSITION MANAGEMENT + ORDER EXECUTION
//  PRESERVED UNCHANGED PER DESIGN CONSTRAINTS.
//  No modifications of any kind below this line.
//=============================================================================

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

        long type     = PositionGetInteger(POSITION_TYPE);
        bool closeNow = false;

        if (type == POSITION_TYPE_BUY  && prevLow  <= vsl[i].sl) closeNow = true;
        if (type == POSITION_TYPE_SELL && prevHigh >= vsl[i].sl) closeNow = true;

        if (closeNow)
            if (ClosePosition(vsl[i].ticket))
                ArrayRemove(vsl, i, 1);
    }
}

bool HasOpenPosition()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
            if (PositionGetString(POSITION_SYMBOL)   == _Symbol &&
                PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
                return true;
    }
    return false;
}

void ManageReverseSignal(bool buySignal, bool sellSignal)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL)   != _Symbol)          continue;
        if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

        long type = PositionGetInteger(POSITION_TYPE);
        if (type == POSITION_TYPE_BUY  && sellSignal) CloseAndRemove(ticket);
        if (type == POSITION_TYPE_SELL && buySignal)  CloseAndRemove(ticket);
    }
}

bool OpenBuy(double slPrice)
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

    if (!OrderSend(request, result)) return false;

    if (result.retcode == TRADE_RETCODE_DONE ||
        result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(result.order, slPrice);
        return true;
    }
    return false;
}

bool OpenSell(double slPrice)
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

    if (!OrderSend(request, result)) return false;

    if (result.retcode == TRADE_RETCODE_DONE ||
        result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        AddVirtualSL(result.order, slPrice);
        return true;
    }
    return false;
}

void AddVirtualSL(ulong ticket, double sl)
{
    int size = ArraySize(vsl);
    ArrayResize(vsl, size + 1);
    vsl[size].ticket = ticket;
    vsl[size].sl     = NormalizeDouble(sl, _Digits);
}

void CloseAndRemove(ulong ticket)
{
    if (ClosePosition(ticket))
        for (int i = ArraySize(vsl) - 1; i >= 0; i--)
            if (vsl[i].ticket == ticket) { ArrayRemove(vsl, i, 1); break; }
}

bool ClosePosition(ulong ticket)
{
    if (!PositionSelectByTicket(ticket)) return false;

    long type = PositionGetInteger(POSITION_TYPE);
    MqlTradeRequest request = {};
    MqlTradeResult  result  = {};

    request.action    = TRADE_ACTION_DEAL;
    request.position  = ticket;
    request.symbol    = _Symbol;
    request.volume    = PositionGetDouble(POSITION_VOLUME);
    request.deviation = Slippage;
    request.magic     = MagicNumber;

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

    if (!OrderSend(request, result)) return false;

    return (result.retcode == TRADE_RETCODE_DONE ||
            result.retcode == TRADE_RETCODE_DONE_PARTIAL);
}

void UpdateTrailingVirtualSL()
{
    double sar[];
    ArraySetAsSeries(sar, true);
    if (CopyBuffer(sarHandle, 0, 0, 3, sar) < 3) return;

    double sarValue = sar[1];

    for (int i = 0; i < ArraySize(vsl); i++)
    {
        ulong ticket = vsl[i].ticket;
        if (!PositionSelectByTicket(ticket)) continue;

        long type = PositionGetInteger(POSITION_TYPE);

        if (type == POSITION_TYPE_BUY  && sarValue > vsl[i].sl)
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);

        if (type == POSITION_TYPE_SELL && sarValue < vsl[i].sl)
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);
    }
}

//+------------------------------------------------------------------+
//  END OF FILE
//
//  STATISTICAL VALIDATION CHECKLIST (post-deployment):
//
//  1. FORWARD RETURN ANALYSIS
//     For every logged [CANDIDATE] event (taken and rejected):
//     - Record 5-bar, 10-bar, 20-bar forward returns
//     - Stratify by total score and each component score
//     - Target: higher score → higher avg forward return
//     - Red flag: components that don't improve expected return
//
//  2. COMPONENT CONTRIBUTION STUDY
//     Run 6 stripped variants, each with one component removed.
//     Measure Sharpe, win rate, avg trade duration per variant.
//     This identifies which components carry genuine predictive weight
//     vs which may be overfitted.
//
//  3. SCORE THRESHOLD CALIBRATION
//     Plot [score → forward return distribution] for all scores 1-10.
//     Find the inflection point where E[return | score=N] turns positive.
//     Use that as MinPersistenceScore. Validate on out-of-sample data.
//
//  4. REGIME CLASSIFICATION TESTING
//     Measure EA performance segmented by detected regime (isSideways output).
//     Validate that the regime filter is genuinely improving in-trend performance,
//     not simply removing a random subset of trades.
//
//  5. WALK-FORWARD ROBUSTNESS
//     Standard 70/30 in-sample / out-of-sample split, rolling forward.
//     Parameters should degrade gracefully out-of-sample (not cliff-edge).
//     A 20-30% Sharpe degradation out-of-sample is acceptable; 50%+ suggests overfitting.
//
//  6. MONTE CARLO DRAWDOWN SIMULATION
//     Shuffle trade sequence 10,000x. Plot 5th percentile drawdown curve.
//     Ensure actual drawdown does not significantly exceed the median simulated path.
//
//+------------------------------------------------------------------+