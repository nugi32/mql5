//+-----------------------------------------------------------------------------------+
//| QuantSystemEA.mq5                                                                 |
//| 5-Layer Systematic Trading Architecture                                           |
//| Built on Darwinex Single-Symbol Bar-Processing Framework                          |
//|                                                                                   |
//| Layers:                                                                           |
//|   1. Alpha Signal (compression/expansion/momentum)                                |
//|   2. Regime Detection (trend/meanrev/highvol/dead)                                |
//|   3. Risk Management (volatility-adjusted sizing)                                 |
//|   4. Portfolio / Strategy Architecture (expandable)                               |
//|   5. Risk Overlay / Circuit Breaker                                               |
//|   +  Research / CSV Logging Framework                                             |
//+-----------------------------------------------------------------------------------+
#property copyright "QuantSystem"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

CTrade         Trade;
CPositionInfo  PosInfo;
COrderInfo     OrdInfo;

//===================================================================================
// ENUMS
//===================================================================================

enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR
};

enum ENUM_REGIME
{
   REGIME_TREND        = 0,
   REGIME_MEAN_REVERT  = 1,
   REGIME_HIGH_VOL     = 2,
   REGIME_DEAD_MARKET  = 3,
   REGIME_UNDEFINED    = 4
};

enum ENUM_ALPHA_SIGNAL
{
   SIGNAL_BUY    =  1,
   SIGNAL_SELL   = -1,
   SIGNAL_NONE   =  0
};

enum ENUM_SESSION
{
   SESSION_SYDNEY    = 0,
   SESSION_TOKYO     = 1,
   SESSION_LONDON    = 2,
   SESSION_NEW_YORK  = 3,
   SESSION_OFF       = 4
};

//===================================================================================
// INPUT PARAMETERS — FRAMEWORK
//===================================================================================
input group "=== FRAMEWORK ==="
input ENUM_TIMEFRAMES          TradeTimeframe      = PERIOD_H1;
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR;
input string                   EA_Comment          = "QS_EA";
input ulong                    MagicNumber         = 202401;

//===================================================================================
// INPUT PARAMETERS — ALPHA
//===================================================================================
input group "=== ALPHA ==="
input int    ATR_Period              = 14;          // ATR period
input int    Lookback_Compression    = 10;          // Bars for compression check
input int    Lookback_Momentum       = 5;           // Bars for momentum persistence
input int    Lookback_Efficiency     = 20;          // Bars for directional efficiency
input double Alpha_MinConfidence     = 0.38;        // Min confidence to trade (0-1)

//===================================================================================
// INPUT PARAMETERS — REGIME
//===================================================================================
input group "=== REGIME ==="
input int    ATR_Percentile_Lookback = 100;         // Bars for ATR percentile
input double ATR_High_Threshold      = 0.88;        // ATR percentile → high vol
input double ATR_Low_Threshold       = 0.10;        // ATR percentile → dead market
input double Efficiency_Trend_Min    = 0.28;        // Efficiency ratio → trending
input double Autocorr_MR_Threshold  = 0.05;        // Autocorr below → mean revert

//===================================================================================
// INPUT PARAMETERS — RISK
//===================================================================================
input group "=== RISK ==="
input double Risk_Pct_Per_Trade      = 0.25;        // Risk % per trade (0.25 = 0.25%)
input double ATR_SL_Multiplier       = 1.5;         // ATR × N = stop distance
input double ATR_TP_Multiplier       = 2.5;         // ATR × N = TP distance
input double Max_Spread_Points       = 30.0;        // Max allowable spread (points)
input double Min_Lot                 = 0.01;
input double Max_Lot                 = 10.0;

//===================================================================================
// INPUT PARAMETERS — CIRCUIT BREAKER
//===================================================================================
input group "=== CIRCUIT BREAKER ==="
input bool   CircuitBreaker_Enabled  = true;
input int    CB_Lookback_Trades      = 20;          // Rolling window N trades
input double CB_MaxDrawdown_Pct      = 5.0;         // Equity DD% → disable
input int    CB_MaxConsecLosses      = 5;           // Consecutive losses → half size
input double CB_MinExpectancy        = -0.5;        // R-expectancy → disable

//===================================================================================
// INPUT PARAMETERS — LOGGING
//===================================================================================
input group "=== LOGGING ==="
input bool   Log_Enabled             = true;
input string Log_FileName            = "QuantSystem_TradeLog.csv";

//===================================================================================
// STRUCTS
//===================================================================================

struct SMarketFeatures
{
   double   atr;
   double   atr_percentile;        // 0-1
   double   realized_vol;          // 20-bar realized vol (normalized)
   double   efficiency_ratio;      // 0-1
   double   autocorrelation;       // -1 to 1
   double   hurst;                 // 0-1 estimate
   double   spread_points;
   double   compression_score;     // 0-1
   double   expansion_score;       // 0-1
   double   momentum_score;        // -1 to 1
   ENUM_SESSION session;
   int      day_of_week;
};

struct SAlphaResult
{
   ENUM_ALPHA_SIGNAL signal;
   double            alpha_score;     // -1 to 1
   double            confidence;      // 0-1
   double            trend_score;
   double            compression_score;
   double            expansion_score;
   double            efficiency_ratio;
};

struct STradeSetup
{
   double   lot_size;
   double   entry_price;
   double   stop_loss;
   double   take_profit;
   double   risk_pct;
   double   sl_distance;
};

struct STradeRecord
{
   datetime open_time;
   datetime close_time;
   string   symbol;
   int      ticket;
   double   entry;
   double   sl;
   double   tp;
   double   lot;
   double   risk_pct;
   double   profit;
   double   mfe;
   double   mae;
   int      holding_bars;
   double   r_multiple;
   double   sl_distance;
   // Market state at entry
   double   atr;
   double   atr_pct;
   double   spread;
   ENUM_SESSION session;
   int      dow;
   double   realized_vol;
   // Signal state at entry
   double   compression_score;
   double   expansion_score;
   double   trend_score;
   double   efficiency_ratio;
   ENUM_REGIME regime;
   double   alpha_score;
   double   confidence;
};

struct SCircuitBreakerState
{
   bool     trading_enabled;
   bool     half_size_mode;
   int      consec_losses;
   double   rolling_expectancy;
   double   peak_equity;
   double   current_drawdown_pct;
};

//===================================================================================
// GLOBALS — DARWINEX FRAMEWORK
//===================================================================================
int      TicksReceivedCount    = 0;
int      TicksProcessedCount   = 0;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;

//===================================================================================
// GLOBALS — EA STATE
//===================================================================================
int      ATR_Handle            = INVALID_HANDLE;

// Trade log buffer (ring buffer, last CB_Lookback_Trades)
STradeRecord TradeHistory[];
int          TradeHistoryCount = 0;

// Active trade tracking for MFE/MAE
struct SActiveTrade
{
   ulong    ticket;
   double   entry;
   double   sl_distance;
   double   mfe;
   double   mae;
   datetime open_time;
   int      open_bar;
   double   risk_pct;
   // Snapshot at entry for logging
   SMarketFeatures mkt;
   SAlphaResult    alpha;
   ENUM_REGIME     regime;
};
SActiveTrade ActiveTrades[];

SCircuitBreakerState CB;

// CSV log file handle
int      LogFileHandle = INVALID_HANDLE;

//===================================================================================
// OnInit
//===================================================================================
int OnInit()
{
   // --- Darwinex bar control ---
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;

   // --- ATR indicator ---
   ATR_Handle = iATR(Symbol(), TradeTimeframe, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR handle");
      return INIT_FAILED;
   }

   // --- Circuit breaker init ---
   CB.trading_enabled      = true;
   CB.half_size_mode       = false;
   CB.consec_losses        = 0;
   CB.rolling_expectancy   = 0;
   CB.peak_equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   CB.current_drawdown_pct = 0;

   // --- Arrays ---
   ArrayResize(TradeHistory, CB_Lookback_Trades);
   ArrayResize(ActiveTrades, 0);

   // --- Trade object ---
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(30);
   Trade.SetTypeFilling(ORDER_FILLING_FOK);

   // --- Logging ---
   if(Log_Enabled)
      InitLogFile();

   Print("QuantSystem EA initialized | Symbol: ", Symbol(), " TF: ", EnumToString(TradeTimeframe));
   return INIT_SUCCEEDED;
}

//===================================================================================
// OnDeinit
//===================================================================================
void OnDeinit(const int reason)
{
   if(ATR_Handle != INVALID_HANDLE)
      IndicatorRelease(ATR_Handle);

   if(LogFileHandle != INVALID_HANDLE)
      FileClose(LogFileHandle);

   Print("QuantSystem EA deinitialized");
}

//===================================================================================
// OnTick — Darwinex Framework (preserved exactly)
//===================================================================================
void OnTick()
{
   TicksReceivedCount++;
   bool ProcessThisIteration = false;

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      ProcessThisIteration = true;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), PERIOD_M1, 0))
      {
         ProcessThisIteration = true;
         TimeLastTickProcessed = iTime(Symbol(), PERIOD_M1, 0);
      }
   }

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), TradeTimeframe, 0))
      {
         ProcessThisIteration = true;
         TimeLastTickProcessed = iTime(Symbol(), TradeTimeframe, 0);
      }
   }

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      UpdateActiveTradeMFE_MAE();   // Always track excursion
      ProcessTradeClosures();
      ProcessTradeOpens();
   }
}

//===================================================================================
// PROCESS TRADE CLOSURES — detect closed trades, compute outcome, log
//===================================================================================
void ProcessTradeClosures()
{
   // Scan ActiveTrades array; if ticket no longer open → record closure
   int n = ArraySize(ActiveTrades);
   for(int i = n - 1; i >= 0; i--)
   {
      ulong ticket = ActiveTrades[i].ticket;
      if(!PositionSelectByTicket(ticket))
      {
         // Position closed — retrieve from history
         if(HistoryDealSelect(ticket) || FindLastDealForPosition(ticket))
         {
            STradeRecord rec;
            BuildTradeRecord(ActiveTrades[i], rec);
            StoreTradeRecord(rec);
            UpdateCircuitBreaker(rec);
            if(Log_Enabled) WriteTradeLog(rec);
         }
         // Remove from active
         RemoveActiveTrade(i);
      }
   }
}

//===================================================================================
// PROCESS TRADE OPENS — system flow: features → regime → alpha → risk → execute
//===================================================================================
void ProcessTradeOpens()
{
   // Only one position at a time per magic (single-symbol)
   if(CountOpenPositions() > 0) return;

   // --- Check circuit breaker ---
   if(!CanTrade()) return;

   // --- 1. Feature Extraction ---
   SMarketFeatures mkt;
   if(!ExtractMarketFeatures(mkt)) return;

   // --- Spread guard ---
   if(mkt.spread_points > Max_Spread_Points) return;

   // --- 2. Regime Detection ---
   ENUM_REGIME regime = GetRegime(mkt);

   // Dead market → no trade
   if(regime == REGIME_DEAD_MARKET) return;

   // --- 3. Alpha Signal (Layer 1) —--
   // Architecture: multiple alpha modules; for now single active alpha
   SAlphaResult alpha;
   GetAlphaSignal(mkt, regime, alpha);

   if(alpha.signal == SIGNAL_NONE)           return;
   if(alpha.confidence < Alpha_MinConfidence) return;

   // --- 4. Risk Sizing (Layer 3) ---
   STradeSetup setup;
   if(!CalculateTradeSetup(alpha, mkt, setup)) return;

   // --- 5. Execute ---
   ExecuteTrade(alpha, setup, mkt, regime);
}

//===================================================================================
// =================== LAYER 1: FEATURE EXTRACTION =================================
//===================================================================================

bool ExtractMarketFeatures(SMarketFeatures &mkt)
{
   // --- ATR ---
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(ATR_Handle, 0, iBarToUseForProcessing, ATR_Percentile_Lookback + 5, atr_buf) <= 0)
      return false;

   mkt.atr           = atr_buf[0];
   if(mkt.atr <= 0) return false;

   // --- ATR Percentile ---
   mkt.atr_percentile = GetATRPercentile(atr_buf, ATR_Percentile_Lookback);

   // --- Realized Volatility (20-bar log returns std dev, normalized by ATR) ---
   mkt.realized_vol   = GetRealizedVol(20);

   // --- Directional Efficiency Ratio ---
   mkt.efficiency_ratio = GetDirectionalEfficiency(Lookback_Efficiency);

   // --- Autocorrelation (lag-1 of bar returns) ---
   mkt.autocorrelation  = GetAutocorrelation(20, 1);

   // --- Hurst estimate (simplified R/S) ---
   mkt.hurst            = GetHurstEstimate(32);

   // --- Spread ---
   mkt.spread_points    = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

   // --- Compression Score: bars where range < ATR fraction ---
   mkt.compression_score = GetCompressionScore(Lookback_Compression, mkt.atr);

   // --- Expansion Score: current bar range vs ATR ---
   double high_arr[], low_arr[];
   ArraySetAsSeries(high_arr, true);
   ArraySetAsSeries(low_arr,  true);
   // Use bar[1] = last COMPLETED bar (bar[0] is still forming when on M1 tick processing)
   CopyHigh(Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, 3, high_arr);
   CopyLow (Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, 3, low_arr);
   double current_range = high_arr[0] - low_arr[0];
   mkt.expansion_score  = (mkt.atr > 0) ? MathMin(current_range / mkt.atr, 2.0) / 2.0 : 0;

   // --- Momentum Score (directional persistence over N bars) ---
   mkt.momentum_score   = GetMomentumScore(Lookback_Momentum);

   // --- Session ---
   mkt.session          = GetCurrentSession();
   mkt.day_of_week      = (int)TimeDayOfWeek(TimeCurrent());

   return true;
}

//===================================================================================
// =================== LAYER 2: REGIME DETECTION ===================================
//===================================================================================

ENUM_REGIME GetRegime(const SMarketFeatures &mkt)
{
   // Dead Market: BOTH very low ATR percentile AND very low efficiency required
   // Requires BOTH conditions to avoid over-filtering
   if(mkt.atr_percentile < ATR_Low_Threshold && mkt.efficiency_ratio < 0.12)
      return REGIME_DEAD_MARKET;

   // Mean Reversion: autocorrelation above threshold (slightly positive = choppy/reverting)
   // Hurst soft check — not hard gate since 32-bar estimate is noisy
   if(mkt.autocorrelation > Autocorr_MR_Threshold && mkt.efficiency_ratio < 0.25)
      return REGIME_MEAN_REVERT;

   // Trending: efficiency ratio above minimum — Hurst used as soft confirmation only
   if(mkt.efficiency_ratio >= Efficiency_Trend_Min)
      return REGIME_TREND;

   // High Volatility: only extreme ATR percentile qualifies
   // We still trade here (breakout alpha), just flag it for logging
   if(mkt.atr_percentile > ATR_High_Threshold)
      return REGIME_HIGH_VOL;

   // Default: Trend
   return REGIME_TREND;
}

//===================================================================================
// =================== LAYER 1: ALPHA SIGNAL =======================================
//===================================================================================
// Architecture: alpha modules registered in a function table.
// Add Alpha_B, Alpha_C here later with weighting.

void GetAlphaSignal(const SMarketFeatures &mkt, const ENUM_REGIME regime, SAlphaResult &alpha)
{
   alpha.signal         = SIGNAL_NONE;
   alpha.alpha_score    = 0;
   alpha.confidence     = 0;
   alpha.trend_score    = mkt.momentum_score;
   alpha.compression_score = mkt.compression_score;
   alpha.expansion_score   = mkt.expansion_score;
   alpha.efficiency_ratio  = mkt.efficiency_ratio;

   // Dispatch by regime
   switch(regime)
   {
      case REGIME_TREND:
         Alpha_BreakoutMomentum(mkt, alpha);
         break;
      case REGIME_MEAN_REVERT:
         Alpha_MeanReversion(mkt, alpha);
         break;
      case REGIME_HIGH_VOL:
         // High vol → still allow breakout alpha; CB half-size handles risk
         Alpha_BreakoutMomentum(mkt, alpha);
         break;
      case REGIME_DEAD_MARKET:
         alpha.signal = SIGNAL_NONE;
         break;
      default:
         Alpha_BreakoutMomentum(mkt, alpha);
         break;
   }
}

//-----------------------------------------------------------------------------------
// Alpha A: Breakout + Momentum Persistence (for TREND regime)
// Edge: after compression, expansion with directional persistence → small edge
//-----------------------------------------------------------------------------------
void Alpha_BreakoutMomentum(const SMarketFeatures &mkt, SAlphaResult &alpha)
{
   // Need some prior compression (relaxed: 20% of recent bars compressed)
   if(mkt.compression_score < 0.20) { alpha.signal = SIGNAL_NONE; return; }

   // Need expansion on last completed bar (relaxed)
   if(mkt.expansion_score < 0.18)   { alpha.signal = SIGNAL_NONE; return; }

   // Soft efficiency gate — allow weak trends through
   if(mkt.efficiency_ratio < 0.15)  { alpha.signal = SIGNAL_NONE; return; }

   // Direction from bar[1] = last COMPLETED bar (avoids incomplete bar noise)
   double close_arr[], open_arr[];
   ArraySetAsSeries(close_arr, true);
   ArraySetAsSeries(open_arr,  true);
   CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, 3, close_arr);
   CopyOpen (Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, 3, open_arr);
   double bar_dir = (close_arr[0] > open_arr[0]) ? 1.0 : -1.0;

   // Confirm with momentum
   if(bar_dir > 0 && mkt.momentum_score > 0.0)
   {
      alpha.signal      = SIGNAL_BUY;
      alpha.alpha_score = MathMin(mkt.compression_score + mkt.expansion_score * 0.5 + mkt.efficiency_ratio * 0.5 - 1.0, 1.0);
      alpha.confidence  = CalcConfidence(mkt.compression_score, mkt.expansion_score,
                                         mkt.efficiency_ratio, mkt.momentum_score, 1.0);
   }
   else if(bar_dir < 0 && mkt.momentum_score < 0.0)
   {
      alpha.signal      = SIGNAL_SELL;
      alpha.alpha_score = -(MathMin(mkt.compression_score + mkt.expansion_score * 0.5 + mkt.efficiency_ratio * 0.5 - 1.0, 1.0));
      alpha.confidence  = CalcConfidence(mkt.compression_score, mkt.expansion_score,
                                         mkt.efficiency_ratio, MathAbs(mkt.momentum_score), -1.0);
   }
   else
   {
      alpha.signal = SIGNAL_NONE;
   }
}

//-----------------------------------------------------------------------------------
// Alpha B: Mean Reversion after expansion exhaustion (for MEAN_REVERT regime)
// Edge: after abnormal expansion, fade the move with tight stop
//-----------------------------------------------------------------------------------
void Alpha_MeanReversion(const SMarketFeatures &mkt, SAlphaResult &alpha)
{
   // Need moderate expansion to fade
   if(mkt.expansion_score < 0.35) { alpha.signal = SIGNAL_NONE; return; }

   // Regime already confirmed mean-revert (autocorr > threshold); no double-check needed

   // Direction from bar[1] = last COMPLETED bar
   double close_arr[], open_arr[];
   ArraySetAsSeries(close_arr, true);
   ArraySetAsSeries(open_arr,  true);
   CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, 3, close_arr);
   CopyOpen (Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, 3, open_arr);
   double bar_dir = (close_arr[0] > open_arr[0]) ? 1.0 : -1.0;

   // Fade the move
   if(bar_dir > 0)
   {
      alpha.signal      = SIGNAL_SELL;  // fade bull bar
      alpha.alpha_score = -(mkt.expansion_score * 0.7 + MathAbs(mkt.autocorrelation) * 0.3);
      alpha.confidence  = CalcConfidence(mkt.expansion_score, MathAbs(mkt.autocorrelation),
                                         1.0 - mkt.efficiency_ratio, MathAbs(mkt.momentum_score), -1.0);
   }
   else
   {
      alpha.signal      = SIGNAL_BUY;   // fade bear bar
      alpha.alpha_score = (mkt.expansion_score * 0.7 + MathAbs(mkt.autocorrelation) * 0.3);
      alpha.confidence  = CalcConfidence(mkt.expansion_score, MathAbs(mkt.autocorrelation),
                                         1.0 - mkt.efficiency_ratio, MathAbs(mkt.momentum_score), 1.0);
   }
}

// Placeholder for future alpha modules
// void Alpha_C(...) { }

//-----------------------------------------------------------------------------------
// Confidence scoring: weighted combination of feature strengths
//-----------------------------------------------------------------------------------
double CalcConfidence(double f1, double f2, double f3, double f4, double dir)
{
   // Weighted sum — features are 0-1 scaled; scale output so moderate signals reach ~0.4-0.6
   // f1=compression, f2=expansion, f3=efficiency, f4=momentum persistence
   double raw = (f1 * 0.30 + f2 * 0.35 + f3 * 0.20 + MathAbs(f4) * 0.15);
   // Normalize: a "typical good setup" (all features ~0.5) should score ~0.5
   return MathMax(0.0, MathMin(1.0, raw * 1.80));
}

//===================================================================================
// =================== LAYER 3: RISK MANAGEMENT ====================================
//===================================================================================

bool CalculateTradeSetup(const SAlphaResult &alpha, const SMarketFeatures &mkt, STradeSetup &setup)
{
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amt    = equity * (Risk_Pct_Per_Trade / 100.0);

   // Circuit breaker: half size
   if(CB.half_size_mode) risk_amt *= 0.5;

   double atr         = mkt.atr;
   double sl_dist     = atr * ATR_SL_Multiplier;
   double tp_dist     = atr * ATR_TP_Multiplier;

   // Tick value & point
   double tick_val    = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tick_size   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double point       = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   if(tick_val <= 0 || tick_size <= 0 || point <= 0) return false;

   // Convert sl_dist (price) to money per lot
   double sl_pips_money = (sl_dist / tick_size) * tick_val;
   if(sl_pips_money <= 0) return false;

   double raw_lot = risk_amt / sl_pips_money;
   raw_lot = MathFloor(raw_lot / SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP))
             * SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   raw_lot = MathMax(Min_Lot, MathMin(Max_Lot, raw_lot));

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   setup.lot_size   = raw_lot;
   setup.risk_pct   = Risk_Pct_Per_Trade * (CB.half_size_mode ? 0.5 : 1.0);
   setup.sl_distance = sl_dist;

   if(alpha.signal == SIGNAL_BUY)
   {
      setup.entry_price = ask;
      setup.stop_loss   = ask - sl_dist;
      setup.take_profit = ask + tp_dist;
   }
   else
   {
      setup.entry_price = bid;
      setup.stop_loss   = bid + sl_dist;
      setup.take_profit = bid - tp_dist;
   }

   // Sanity
   if(setup.lot_size < Min_Lot) return false;
   return true;
}

//===================================================================================
// =================== LAYER 4: PORTFOLIO / STRATEGY ARCHITECTURE ==================
//===================================================================================
// Single symbol now. Ready to expand:
// - Add strategy weight table: StrategyWeights[]
// - Each alpha returns SAlphaResult; aggregate via WeightedVote()
// - Allocate capital proportionally

void ExecuteTrade(const SAlphaResult &alpha, const STradeSetup &setup,
                  const SMarketFeatures &mkt, const ENUM_REGIME regime)
{
   bool res = false;
   if(alpha.signal == SIGNAL_BUY)
      res = Trade.Buy(setup.lot_size, Symbol(), setup.entry_price, setup.stop_loss, setup.take_profit, EA_Comment);
   else if(alpha.signal == SIGNAL_SELL)
      res = Trade.Sell(setup.lot_size, Symbol(), setup.entry_price, setup.stop_loss, setup.take_profit, EA_Comment);

   if(res && Trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      ulong ticket = Trade.ResultOrder();
      RegisterActiveTrade(ticket, setup, mkt, alpha, regime);
      Print("Trade opened | Ticket:", ticket, " Lot:", setup.lot_size,
            " SL:", setup.stop_loss, " TP:", setup.take_profit,
            " Regime:", EnumToString(regime), " Conf:", DoubleToString(alpha.confidence, 3));
   }
   else
   {
      Print("Trade failed | Retcode:", Trade.ResultRetcode(), " Comment:", Trade.ResultComment());
   }
}

//===================================================================================
// =================== LAYER 5: CIRCUIT BREAKER ====================================
//===================================================================================

bool CanTrade()
{
   if(!CircuitBreaker_Enabled) return true;

   // Check equity drawdown
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > CB.peak_equity) CB.peak_equity = equity;
   CB.current_drawdown_pct = (CB.peak_equity > 0)
      ? ((CB.peak_equity - equity) / CB.peak_equity) * 100.0
      : 0.0;

   if(CB.current_drawdown_pct >= CB_MaxDrawdown_Pct)
   {
      if(CB.trading_enabled)
         Print("CIRCUIT BREAKER: Equity DD ", DoubleToString(CB.current_drawdown_pct, 2),
               "% >= threshold. Trading DISABLED.");
      CB.trading_enabled = false;
      return false;
   }

   if(!CB.trading_enabled) return false;

   // Consecutive losses → half size
   CB.half_size_mode = (CB.consec_losses >= CB_MaxConsecLosses);

   // Rolling expectancy check
   if(TradeHistoryCount >= CB_Lookback_Trades)
   {
      CB.rolling_expectancy = ComputeRollingExpectancy();
      if(CB.rolling_expectancy < CB_MinExpectancy)
      {
         Print("CIRCUIT BREAKER: Rolling expectancy ", DoubleToString(CB.rolling_expectancy, 3),
               " < threshold. Trading DISABLED.");
         CB.trading_enabled = false;
         return false;
      }
   }

   return true;
}

void UpdateCircuitBreaker(const STradeRecord &rec)
{
   if(rec.profit < 0)
      CB.consec_losses++;
   else
      CB.consec_losses = 0;
}

double ComputeRollingExpectancy()
{
   int n = MathMin(TradeHistoryCount, CB_Lookback_Trades);
   if(n <= 0) return 0;
   double sum = 0;
   int start  = TradeHistoryCount - n;
   for(int i = start; i < TradeHistoryCount; i++)
      sum += TradeHistory[i % CB_Lookback_Trades].r_multiple;
   return sum / n;
}

//===================================================================================
// =================== HELPER FUNCTIONS ============================================
//===================================================================================

//-----------------------------------------------------------------------------------
// ATR Percentile: rank current ATR in historical window
//-----------------------------------------------------------------------------------
double GetATRPercentile(const double &atr_buf[], int lookback)
{
   double cur = atr_buf[0];
   int below  = 0;
   int total  = MathMin(lookback, ArraySize(atr_buf) - 1);
   for(int i = 1; i <= total; i++)
      if(atr_buf[i] < cur) below++;
   return (total > 0) ? (double)below / (double)total : 0.5;
}

//-----------------------------------------------------------------------------------
// Directional Efficiency Ratio: |net move| / sum(|bar moves|)
//-----------------------------------------------------------------------------------
double GetDirectionalEfficiency(int period)
{
   double close_arr[];
   ArraySetAsSeries(close_arr, true);
   if(CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing, period + 1, close_arr) <= 0)
      return 0.5;

   double net_move  = MathAbs(close_arr[0] - close_arr[period]);
   double path_len  = 0;
   for(int i = 0; i < period; i++)
      path_len += MathAbs(close_arr[i] - close_arr[i+1]);

   return (path_len > 0) ? MathMin(net_move / path_len, 1.0) : 0.0;
}

//-----------------------------------------------------------------------------------
// Realized Volatility: std dev of log returns, normalized by ATR
//-----------------------------------------------------------------------------------
double GetRealizedVol(int period)
{
   double close_arr[];
   ArraySetAsSeries(close_arr, true);
   if(CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing, period + 2, close_arr) <= 0)
      return 0;

   double sum = 0, sum2 = 0;
   int    n   = period;
   double returns[];
   ArrayResize(returns, n);
   for(int i = 0; i < n; i++)
   {
      if(close_arr[i+1] <= 0) { returns[i] = 0; continue; }
      returns[i] = MathLog(close_arr[i] / close_arr[i+1]);
      sum  += returns[i];
   }
   double mean = sum / n;
   for(int i = 0; i < n; i++)
      sum2 += (returns[i] - mean) * (returns[i] - mean);
   return MathSqrt(sum2 / (n - 1));
}

//-----------------------------------------------------------------------------------
// Autocorrelation at lag k
//-----------------------------------------------------------------------------------
double GetAutocorrelation(int period, int lag)
{
   double close_arr[];
   ArraySetAsSeries(close_arr, true);
   int needed = period + lag + 2;
   if(CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing, needed, close_arr) <= 0)
      return 0;

   double ret[];
   ArrayResize(ret, period + lag);
   for(int i = 0; i < period + lag; i++)
   {
      if(close_arr[i+1] <= 0) { ret[i] = 0; continue; }
      ret[i] = close_arr[i] - close_arr[i+1];
   }

   // Pearson correlation between ret[0..n-1] and ret[lag..n+lag-1]
   int n   = period;
   double sx = 0, sy = 0, sxy = 0, sx2 = 0, sy2 = 0;
   for(int i = 0; i < n; i++)
   {
      double x = ret[i];
      double y = ret[i + lag];
      sx  += x; sy  += y;
      sxy += x * y;
      sx2 += x * x;
      sy2 += y * y;
   }
   double num   = n * sxy - sx * sy;
   double den   = MathSqrt((n * sx2 - sx * sx) * (n * sy2 - sy * sy));
   return (den > 0) ? num / den : 0;
}

//-----------------------------------------------------------------------------------
// Hurst Exponent Estimate (simplified R/S analysis)
//-----------------------------------------------------------------------------------
double GetHurstEstimate(int period)
{
   double close_arr[];
   ArraySetAsSeries(close_arr, true);
   if(CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing, period + 2, close_arr) <= 0)
      return 0.5;

   double ret[];
   ArrayResize(ret, period);
   for(int i = 0; i < period; i++)
   {
      if(close_arr[i+1] <= 0) { ret[i] = 0; continue; }
      ret[i] = close_arr[i] - close_arr[i+1];
   }

   // Mean and deviation
   double mean = 0;
   for(int i = 0; i < period; i++) mean += ret[i];
   mean /= period;

   // Cumulative deviations
   double cum = 0, mn = 1e18, mx = -1e18;
   double var_sum = 0;
   for(int i = 0; i < period; i++)
   {
      cum += ret[i] - mean;
      if(cum > mx) mx = cum;
      if(cum < mn) mn = cum;
      var_sum += (ret[i] - mean) * (ret[i] - mean);
   }
   double R   = mx - mn;
   double S   = MathSqrt(var_sum / period);
   double RS  = (S > 0) ? R / S : 1.0;
   double H   = (period > 1 && RS > 0) ? MathLog(RS) / MathLog((double)period) : 0.5;
   return MathMax(0.0, MathMin(1.0, H));
}

//-----------------------------------------------------------------------------------
// Compression Score: fraction of last N bars with range < ATR * threshold
//-----------------------------------------------------------------------------------
double GetCompressionScore(int period, double atr)
{
   double high_arr[], low_arr[];
   ArraySetAsSeries(high_arr, true);
   ArraySetAsSeries(low_arr,  true);
   if(CopyHigh(Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, period, high_arr) <= 0) return 0;
   if(CopyLow (Symbol(), TradeTimeframe, iBarToUseForProcessing + 1, period, low_arr)  <= 0) return 0;

   int compressed = 0;
   double threshold = atr * 0.70;  // bar range < 70% ATR = compressed
   for(int i = 0; i < period; i++)
   {
      double rng = high_arr[i] - low_arr[i];
      if(rng < threshold) compressed++;
   }
   return (period > 0) ? (double)compressed / (double)period : 0;
}

//-----------------------------------------------------------------------------------
// Momentum Score: directional persistence (fraction of bars moving same way)
//-----------------------------------------------------------------------------------
double GetMomentumScore(int period)
{
   double close_arr[];
   ArraySetAsSeries(close_arr, true);
   if(CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing, period + 2, close_arr) <= 0)
      return 0;

   int up = 0, dn = 0;
   for(int i = 0; i < period; i++)
   {
      if(close_arr[i] > close_arr[i+1]) up++;
      else if(close_arr[i] < close_arr[i+1]) dn++;
   }
   // Returns -1 to +1
   return (period > 0) ? (double)(up - dn) / (double)period : 0;
}

//-----------------------------------------------------------------------------------
// Session Classification (UTC+0 times)
//-----------------------------------------------------------------------------------
ENUM_SESSION GetCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;

   if(h >= 22 || h < 8)  return SESSION_SYDNEY;
   if(h >= 0  && h < 3)  return SESSION_TOKYO;
   if(h >= 7  && h < 12) return SESSION_LONDON;
   if(h >= 12 && h < 21) return SESSION_NEW_YORK;
   return SESSION_OFF;
}

//-----------------------------------------------------------------------------------
// Day of week helper
//-----------------------------------------------------------------------------------
int TimeDayOfWeek(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.day_of_week;
}

//===================================================================================
// ACTIVE TRADE MANAGEMENT
//===================================================================================

void RegisterActiveTrade(ulong ticket, const STradeSetup &setup,
                          const SMarketFeatures &mkt, const SAlphaResult &alpha,
                          ENUM_REGIME regime)
{
   int n = ArraySize(ActiveTrades);
   ArrayResize(ActiveTrades, n + 1);
   ActiveTrades[n].ticket      = ticket;
   ActiveTrades[n].entry       = setup.entry_price;
   ActiveTrades[n].sl_distance = setup.sl_distance;
   ActiveTrades[n].mfe         = 0;
   ActiveTrades[n].mae         = 0;
   ActiveTrades[n].open_time   = TimeCurrent();
   ActiveTrades[n].open_bar    = (int)iBarShift(Symbol(), TradeTimeframe, TimeCurrent(), false);
   ActiveTrades[n].risk_pct    = setup.risk_pct;
   ActiveTrades[n].mkt         = mkt;
   ActiveTrades[n].alpha       = alpha;
   ActiveTrades[n].regime      = regime;
}

void RemoveActiveTrade(int idx)
{
   int n = ArraySize(ActiveTrades);
   for(int i = idx; i < n - 1; i++)
      ActiveTrades[i] = ActiveTrades[i + 1];
   ArrayResize(ActiveTrades, n - 1);
}

void UpdateActiveTradeMFE_MAE()
{
   int n = ArraySize(ActiveTrades);
   for(int i = 0; i < n; i++)
   {
      ulong ticket = ActiveTrades[i].ticket;
      if(!PositionSelectByTicket(ticket)) continue;

      double bid   = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      double ask   = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      double entry = ActiveTrades[i].entry;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double pnl_dist;
      if(pt == POSITION_TYPE_BUY)
         pnl_dist = bid - entry;
      else
         pnl_dist = entry - ask;

      if(pnl_dist > ActiveTrades[i].mfe) ActiveTrades[i].mfe = pnl_dist;
      if(pnl_dist < ActiveTrades[i].mae) ActiveTrades[i].mae = pnl_dist;
   }
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == Symbol() &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
         count++;
   }
   return count;
}

//===================================================================================
// TRADE RECORD BUILDING
//===================================================================================

bool FindLastDealForPosition(ulong position_ticket)
{
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID) == (long)position_ticket)
         return true;
   }
   return false;
}

void BuildTradeRecord(const SActiveTrade &at, STradeRecord &rec)
{
   HistorySelect(0, TimeCurrent());

   rec.open_time   = at.open_time;
   rec.close_time  = TimeCurrent();
   rec.symbol      = Symbol();
   rec.ticket      = (int)at.ticket;
   rec.entry       = at.entry;
   rec.lot         = 0;
   rec.profit      = 0;
   rec.sl          = 0;
   rec.tp          = 0;

   // Sum up deals for this position
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(deal, DEAL_POSITION_ID) == (long)at.ticket)
      {
         rec.profit += HistoryDealGetDouble(deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(deal, DEAL_SWAP)
                     + HistoryDealGetDouble(deal, DEAL_COMMISSION);
         rec.lot     = HistoryDealGetDouble(deal, DEAL_VOLUME);
      }
   }

   rec.mfe          = at.mfe;
   rec.mae          = at.mae;
   rec.risk_pct     = at.risk_pct;
   rec.sl_distance  = at.sl_distance;

   // R-multiple
   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (at.risk_pct / 100.0);
   rec.r_multiple    = (risk_money > 0) ? rec.profit / risk_money : 0;

   // Holding time in bars
   int cur_bar     = (int)iBarShift(Symbol(), TradeTimeframe, TimeCurrent(), false);
   rec.holding_bars = MathAbs(at.open_bar - cur_bar);

   // Market snapshot
   rec.atr         = at.mkt.atr;
   rec.atr_pct     = at.mkt.atr_percentile;
   rec.spread      = at.mkt.spread_points;
   rec.session     = at.mkt.session;
   rec.dow         = at.mkt.day_of_week;
   rec.realized_vol = at.mkt.realized_vol;

   // Signal snapshot
   rec.compression_score = at.alpha.compression_score;
   rec.expansion_score   = at.alpha.expansion_score;
   rec.trend_score       = at.alpha.trend_score;
   rec.efficiency_ratio  = at.alpha.efficiency_ratio;
   rec.regime            = at.regime;
   rec.alpha_score       = at.alpha.alpha_score;
   rec.confidence        = at.alpha.confidence;
}

void StoreTradeRecord(const STradeRecord &rec)
{
   int idx = TradeHistoryCount % CB_Lookback_Trades;
   TradeHistory[idx] = rec;
   TradeHistoryCount++;
}

//===================================================================================
// =================== LOGGING FRAMEWORK ===========================================
//===================================================================================

void InitLogFile()
{
   LogFileHandle = FileOpen(Log_FileName, FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(LogFileHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open log file: ", Log_FileName);
      return;
   }

   // Write CSV header
   FileWrite(LogFileHandle,
      // Market State
      "OpenTime", "CloseTime", "Symbol", "Ticket",
      "Spread_Points", "ATR", "ATR_Percentile", "RealizedVol",
      "Session", "DayOfWeek",
      // Signal State
      "CompressionScore", "ExpansionScore", "TrendScore",
      "EfficiencyRatio", "Regime", "AlphaScore", "Confidence",
      // Trade State
      "Entry", "StopLoss_Dist", "Lot", "Risk_Pct",
      // Outcome
      "MFE", "MAE", "HoldingBars", "Profit", "R_Multiple"
   );
   Print("Log file initialized: ", Log_FileName);
}

string SessionToString(ENUM_SESSION s)
{
   switch(s)
   {
      case SESSION_SYDNEY:   return "Sydney";
      case SESSION_TOKYO:    return "Tokyo";
      case SESSION_LONDON:   return "London";
      case SESSION_NEW_YORK: return "NewYork";
      default:               return "Off";
   }
}

string RegimeToString(ENUM_REGIME r)
{
   switch(r)
   {
      case REGIME_TREND:       return "Trend";
      case REGIME_MEAN_REVERT: return "MeanRevert";
      case REGIME_HIGH_VOL:    return "HighVol";
      case REGIME_DEAD_MARKET: return "DeadMarket";
      default:                 return "Undefined";
   }
}

string DowToString(int dow)
{
   string days[] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
   if(dow >= 0 && dow <= 6) return days[dow];
   return "?";
}

void WriteTradeLog(const STradeRecord &rec)
{
   if(LogFileHandle == INVALID_HANDLE) return;

   FileWrite(LogFileHandle,
      // Market State
      TimeToString(rec.open_time,  TIME_DATE|TIME_MINUTES),
      TimeToString(rec.close_time, TIME_DATE|TIME_MINUTES),
      rec.symbol,
      IntegerToString(rec.ticket),
      DoubleToString(rec.spread,          1),
      DoubleToString(rec.atr,             5),
      DoubleToString(rec.atr_pct,         3),
      DoubleToString(rec.realized_vol,    6),
      SessionToString(rec.session),
      DowToString(rec.dow),
      // Signal State
      DoubleToString(rec.compression_score, 3),
      DoubleToString(rec.expansion_score,   3),
      DoubleToString(rec.trend_score,       3),
      DoubleToString(rec.efficiency_ratio,  3),
      RegimeToString(rec.regime),
      DoubleToString(rec.alpha_score,       3),
      DoubleToString(rec.confidence,        3),
      // Trade State
      DoubleToString(rec.entry,        5),
      DoubleToString(rec.sl_distance,  5),
      DoubleToString(rec.lot,          2),
      DoubleToString(rec.risk_pct,     3),
      // Outcome
      DoubleToString(rec.mfe,          5),
      DoubleToString(rec.mae,          5),
      IntegerToString(rec.holding_bars),
      DoubleToString(rec.profit,       2),
      DoubleToString(rec.r_multiple,   3)
   );

   FileFlush(LogFileHandle);
}

//+-----------------------------------------------------------------------------------+
//| END OF FILE                                                                        |
//+-----------------------------------------------------------------------------------+