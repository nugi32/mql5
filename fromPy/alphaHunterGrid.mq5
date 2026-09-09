//+--------------------------------------------------------------------------------+
//| signal-pattern-01-ea-fixed.mq5                                                 |
//|                                                                                |
//| Built on the "control-bar-opening-single-symbol" framework.                    |
//| Trades the single confluence pattern from the report:                         |
//|   SMA21_above_EMA21 + squeeze_active + STO_K14_cross_below_D +                 |
//|   Close_below_BB_lower_20_2  ->  Historically BULLISH 62.2% of the time        |
//|   (avg move 1.50 ATR, STABLE across train/val/oos splits)                      |
//|                                                                                |
//| FIX NOTES vs the previous version:                                             |
//|  1) SMA21_above_EMA21 and Close_below_BB_lower_20_2 are "cross" conditions in  |
//|     the JSON spec (a crossover event), not a static state - fixed.            |
//|  2) squeeze_active's ATR term in the Python source is a SIMPLE rolling mean    |
//|     of True Range (tr.rolling(20).mean()), NOT Wilder-smoothed ATR             |
//|     (what MT5's iATR() returns) - now computed manually.                       |
//|  3) Keltner Channel basis is a Close-based EMA in Python                       |
//|     (df["Close"].ewm(span=20)), previously PRICE_TYPICAL - fixed.              |
//|  4) Python hardcodes the BB/KC multiplier to 2 in the squeeze function -       |
//|     default corrected from 1.5 to 2.0.                                        |
//|  5) Bollinger Bands: pandas .std() is sample std (ddof=1); MT5's iBands()      |
//|     uses population std (ddof=0) - now computed manually with ddof=1.          |
//|  6) Stochastic: iStochastic() does not reproduce the exact double-smoothing    |
//|     (raw %K -> 3-bar SMA -> 3-bar SMA of that) used in the Python source -     |
//|     now computed manually, bar-for-bar.                                       |
//|  7) EMA: MT5's built-in EMA seeding differs from pandas ewm(adjust=False) -    |
//|     replaced with a manual recursive EMA over a configurable lookback window   |
//|     so it converges to the same values.                                        |
//|                                                                                |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                             |
//| THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"    |
//| AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE      |
//| IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE |
//| DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE   |
//| FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL     |
//| DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE.                    |
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property link        ""
#property description "Trades SMA21>EMA21 cross + Squeeze + Stoch K/D cross below + Close<BB_lower(20,2) cross. Fixed lot. No broker SL/TP."
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//################
// Enums
//################
enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               //Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        //Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   //Only Process Ticks From New Bar in Trade TF
};

//################
// Input Variables
//################
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;                          //Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR;   //EA Bar Processing Method

input group "=== Signal Parameters (must match the Python definitions) ==="
input int    SMA_Period    = 21;      //SMA period (SMA_21)
input int    EMA_Period    = 21;      //EMA period (EMA_21)
input int    BB_Period     = 20;      //Bollinger Bands period (BB_20_2)
input double BB_Deviation  = 2.0;     //Bollinger Bands deviation (BB_20_2 factor)
input int    KC_Period     = 20;      //Keltner Channel EMA/ATR period (squeeze definition)
input double KC_ATR_Mult   = 2.0;     //Keltner Channel ATR multiplier - Python HARDCODES this to 2. Do not change unless you change the Python source too.
input int    Stoch_K       = 14;      //Stochastic %K lookback period (STO_K_14)
input int    HistoryBars   = 300;     //Bars of history used to converge the manually-computed EMA (bigger = closer to python's full-history EMA)

input group "=== Trade Settings ==="
input double FixedLotSize  = 0.10;                       //Fixed lot size (no risk-based sizing)
input int    MagicNumber   = 20260721;                    //Magic number
input string TradeComment  = "SMA21EMA21_Squeeze_StochBB"; //Order comment
input bool   OnlyOnePositionAtATime = true;                //Block new entries while a position from this EA is open
input int    CloseAfterXCandles     = 5;                   //Force-close the position after this many closed candles on TradeTimeframe (0 = disabled)

//################
// Global Variables
//################
int      TicksReceivedCount    = 0;                     //Number of ticks received by the EA
int      TicksProcessedCount   = 0;                     //Number of ticks processed by the EA
int      SignalsDetectedCount  = 0;                     //Number of times the full pattern fired
int      TradesOpenedCount     = 0;                     //Number of buy orders sent
datetime TimeLastTickProcessed = D'1971.01.01 00:00';   //Controls processing interval

int      iBarToUseForProcessing;   //Bar 0 or 1, set in OnInit(), same logic as the base framework

//--- last evaluated condition snapshot (for on-screen reporting only)
bool   Last_SMA_above_EMA_Cross  = false;
bool   Last_Squeeze_active       = false;
bool   Last_Stoch_cross_below    = false;
bool   Last_Close_below_BBLow_Cross = false;
bool   Last_Signal_fired         = false;
datetime Last_Eval_Time          = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   //################################
   //Determine which bar we will use (0 or 1) - identical logic to the base framework
   //################################
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;

   int minBarsNeeded = MathMax(MathMax(SMA_Period, EMA_Period), MathMax(BB_Period, KC_Period)) + Stoch_K + 10;
   if(HistoryBars < minBarsNeeded)
      Print("WARNING: HistoryBars (", HistoryBars, ") is small relative to your periods. Consider >= ", minBarsNeeded, " for stable EMA convergence.");

   trade.SetExpertMagicNumber(MagicNumber);

   Print("EA USING " + EnumToString(BarProcessingMethod) + " PROCESSING METHOD AND INDICATORS WILL USE BAR " + IntegerToString(iBarToUseForProcessing));

   OutputStatusToScreen();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

   //########################################################
   //Control EA so that we only process at required intervals - identical to base framework
   //########################################################
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

   //#############################
   //Process signal + trade if appropriate
   //#############################
   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      CheckTimedExit();
      ProcessSignalAndTrade();
   }

   OutputStatusToScreen();
}

//+------------------------------------------------------------------+
//| ---------------------- MANUAL INDICATOR MATH ----------------------
//| All arrays below are SERIES ORDER: index 0 = the bar at             |
//| "shift" 0 (i.e. iBarToUseForProcessing), index increases = further  |
//| back in time. This mirrors how we call CopyClose/High/Low with      |
//| start = iBarToUseForProcessing.                                     |
//+------------------------------------------------------------------+

double SMA_S(const double &arr[], int shift, int period)
{
   double sum = 0.0;
   for(int i = 0; i < period; i++) sum += arr[shift + i];
   return sum / period;
}

// Sample standard deviation (ddof=1), matching pandas .std() default
double STD_S(const double &arr[], int shift, int period, double mean)
{
   double s = 0.0;
   for(int i = 0; i < period; i++)
   {
      double d = arr[shift + i] - mean;
      s += d * d;
   }
   return MathSqrt(s / (period - 1));
}

double Highest_S(const double &arr[], int shift, int period)
{
   double m = arr[shift];
   for(int i = 1; i < period; i++) if(arr[shift + i] > m) m = arr[shift + i];
   return m;
}

double Lowest_S(const double &arr[], int shift, int period)
{
   double m = arr[shift];
   for(int i = 1; i < period; i++) if(arr[shift + i] < m) m = arr[shift + i];
   return m;
}

// Recursive EMA matching pandas ewm(span=period, adjust=False).mean()
// src is series-order (index0=latest); emaOut is filled the same way.
void BuildEMA_S(const double &src[], double &emaOut[], int period)
{
   int n = ArraySize(src);
   ArrayResize(emaOut, n);
   double alpha = 2.0 / (period + 1.0);
   emaOut[n - 1] = src[n - 1];              // oldest bar in the window = seed
   for(int i = n - 2; i >= 0; i--)
      emaOut[i] = alpha * src[i] + (1.0 - alpha) * emaOut[i + 1];
}

// True Range, series-order. trOut[i] uses close[i+1] as "previous close",
// matching pandas' Close.shift(1) behaviour.
void BuildTR_S(const double &high[], const double &low[], const double &close[], double &trOut[])
{
   int n = ArraySize(high);
   ArrayResize(trOut, n);
   for(int i = 0; i < n - 1; i++)
   {
      double hl = high[i] - low[i];
      double hc = MathAbs(high[i] - close[i + 1]);
      double lc = MathAbs(low[i]  - close[i + 1]);
      trOut[i] = MathMax(hl, MathMax(hc, lc));
   }
   trOut[n - 1] = high[n - 1] - low[n - 1]; // oldest bar, no earlier close available in our window
}

// Raw %K = (Close - LowestLow(period)) / (HighestHigh(period) - LowestLow(period)) * 100
double RawK_S(const double &close[], const double &high[], const double &low[], int shift, int period)
{
   double hi = Highest_S(high, shift, period);
   double lo = Lowest_S(low, shift, period);
   if(hi - lo == 0.0) return 50.0;
   return ((close[shift] - lo) / (hi - lo)) * 100.0;
}

// Slow %K = 3-bar SMA of raw %K
double SlowK_S(const double &close[], const double &high[], const double &low[], int shift, int period)
{
   double sum = 0.0;
   for(int i = 0; i < 3; i++) sum += RawK_S(close, high, low, shift + i, period);
   return sum / 3.0;
}

// %D = 3-bar SMA of slow %K
double SlowD_S(const double &close[], const double &high[], const double &low[], int shift, int period)
{
   double sum = 0.0;
   for(int i = 0; i < 3; i++) sum += SlowK_S(close, high, low, shift + i, period);
   return sum / 3.0;
}

//+------------------------------------------------------------------+
//| Reads price history and evaluates all 4 pattern conditions,       |
//| matching the Python "type": "cross" / "threshold" semantics       |
//| exactly (cross = event on this bar, threshold/state = holds now). |
//+------------------------------------------------------------------+
bool GetSignalConditions(bool &sma_above_ema_cross, bool &squeeze_active,
                          bool &stoch_cross_below, bool &close_below_bb_lower_cross)
{
   int shift0 = 0;   // the signal bar (iBarToUseForProcessing)
   int shift1 = 1;   // one bar before the signal bar

   double close[], high[], low[];
   if(CopyClose(Symbol(), TradeTimeframe, iBarToUseForProcessing, HistoryBars, close) < HistoryBars) return false;
   if(CopyHigh (Symbol(), TradeTimeframe, iBarToUseForProcessing, HistoryBars, high)  < HistoryBars) return false;
   if(CopyLow  (Symbol(), TradeTimeframe, iBarToUseForProcessing, HistoryBars, low)   < HistoryBars) return false;
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   // Bounds safety: need shift1 + max(period) + a few extra bars for the stochastic's double-smoothing
   int maxPeriod = MathMax(MathMax(SMA_Period, EMA_Period), MathMax(BB_Period, KC_Period));
   if(HistoryBars < shift1 + maxPeriod + Stoch_K + 6)
   {
      Print("Not enough HistoryBars to safely evaluate the pattern - increase the HistoryBars input.");
      return false;
   }

   double emaMain[], emaKC[];
   BuildEMA_S(close, emaMain, EMA_Period);   // EMA_21 (used vs SMA_21)
   BuildEMA_S(close, emaKC,   KC_Period);    // Keltner Channel basis EMA (Close-based, per python)

   double trArr[];
   BuildTR_S(high, low, close, trArr);

   //--- Condition 1: SMA21_above_EMA21 -> CROSS (sma>ema now, sma<=ema previous bar)
   double sma_now  = SMA_S(close, shift0, SMA_Period);
   double sma_prev = SMA_S(close, shift1, SMA_Period);
   sma_above_ema_cross = (sma_now > emaMain[shift0]) && (sma_prev <= emaMain[shift1]);

   //--- Condition 2: squeeze_active -> STATE (BB(20,2) inside Keltner(20, Close-EMA, 2*ATR_SMA20))
   double bbMean_now  = SMA_S(close, shift0, BB_Period);
   double bbStd_now   = STD_S(close, shift0, BB_Period, bbMean_now);
   double bbUpper_now = bbMean_now + BB_Deviation * bbStd_now;
   double bbLower_now = bbMean_now - BB_Deviation * bbStd_now;

   double atr_now      = SMA_S(trArr, shift0, KC_Period);   // simple mean of TR, NOT Wilder ATR
   double kcUpper_now  = emaKC[shift0] + KC_ATR_Mult * atr_now;
   double kcLower_now  = emaKC[shift0] - KC_ATR_Mult * atr_now;

   squeeze_active = (bbUpper_now < kcUpper_now) && (bbLower_now > kcLower_now);

   //--- Condition 3: STO_K14_cross_below_D -> CROSS (K<D now, K>=D previous bar)
   double k_now  = SlowK_S(close, high, low, shift0, Stoch_K);
   double d_now  = SlowD_S(close, high, low, shift0, Stoch_K);
   double k_prev = SlowK_S(close, high, low, shift1, Stoch_K);
   double d_prev = SlowD_S(close, high, low, shift1, Stoch_K);
   stoch_cross_below = (k_now < d_now) && (k_prev >= d_prev);

   //--- Condition 4: Close_below_BB_lower_20_2 -> CROSS (close<lower now, close>=lower previous bar)
   double bbMean_prev  = SMA_S(close, shift1, BB_Period);
   double bbStd_prev   = STD_S(close, shift1, BB_Period, bbMean_prev);
   double bbLower_prev = bbMean_prev - BB_Deviation * bbStd_prev;

   close_below_bb_lower_cross = (close[shift0] < bbLower_now) && (close[shift1] >= bbLower_prev);

   return true;
}

//+------------------------------------------------------------------+
//| Evaluates the pattern and opens a fixed-lot buy with no SL/TP     |
//+------------------------------------------------------------------+
void ProcessSignalAndTrade()
{
   bool sma_above_ema_cross=false, squeeze_active=false, stoch_cross_below=false, close_below_bb_lower_cross=false;

   if(!GetSignalConditions(sma_above_ema_cross, squeeze_active, stoch_cross_below, close_below_bb_lower_cross))
   {
      Print("Not enough bar/price history yet to evaluate the pattern.");
      return;
   }

   Last_SMA_above_EMA_Cross     = sma_above_ema_cross;
   Last_Squeeze_active          = squeeze_active;
   Last_Stoch_cross_below       = stoch_cross_below;
   Last_Close_below_BBLow_Cross = close_below_bb_lower_cross;
   Last_Eval_Time                = iTime(Symbol(), TradeTimeframe, iBarToUseForProcessing);

   bool signalFired = sma_above_ema_cross && squeeze_active && stoch_cross_below && close_below_bb_lower_cross;
   Last_Signal_fired = signalFired;

   if(!signalFired)
      return;

   SignalsDetectedCount++;

   if(OnlyOnePositionAtATime && HasOpenPosition())
   {
      Print("Signal fired but an EA position is already open on " + Symbol() + " - skipping.");
      return;
   }

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   //--- Fixed lot, NO stop loss / take profit sent to the broker (sl=0, tp=0)
   if(trade.Buy(FixedLotSize, Symbol(), ask, 0.0, 0.0, TradeComment))
   {
      TradesOpenedCount++;
      Print("BUY opened: ", Symbol(), " lot=", DoubleToString(FixedLotSize,2),
            " @ ", DoubleToString(ask, _Digits), " (no SL/TP set)");
   }
   else
   {
      Print("BUY order failed. Error code: ", GetLastError(), " retcode: ", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Force-closes any EA position once it has lived through            |
//| CloseAfterXCandles closed bars on TradeTimeframe                  |
//+------------------------------------------------------------------+
void CheckTimedExit()
{
   if(CloseAfterXCandles <= 0)
      return;   //feature disabled

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != Symbol() ||
         PositionGetInteger(POSITION_MAGIC)  != MagicNumber)
         continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      //--- how many completed bars have passed since the bar the position opened on
      int openBarShift = iBarShift(Symbol(), TradeTimeframe, openTime, false);
      if(openBarShift < 0)
         continue; //couldn't resolve, skip this check for now

      int candlesElapsed = openBarShift;   //bar 0 = current forming bar, so this = fully-closed candles since entry

      if(candlesElapsed >= CloseAfterXCandles)
      {
         if(trade.PositionClose(ticket))
            Print("Position #", ticket, " closed after ", candlesElapsed, " candles (limit ", CloseAfterXCandles, ")");
         else
            Print("Failed to close position #", ticket, ". Error: ", GetLastError(), " retcode: ", trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void OutputStatusToScreen()
{
   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   string OutputText = "\n\r";

   OutputText += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
                 " (UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   OutputText += Symbol() + " TICKS RECEIVED:    " + IntegerToString(TicksReceivedCount) + "\n\r";
   OutputText += Symbol() + " TICKS PROCESSED:   " + IntegerToString(TicksProcessedCount) + "\n\r";
   OutputText += "PROCESSING METHOD:   " + EnumToString(BarProcessingMethod) + "\n\r";
   OutputText += EnumToString(TradeTimeframe) + " BAR USED FOR SIGNAL:   " + IntegerToString(iBarToUseForProcessing) + "\n\r";
   OutputText += "TRADING TIMEFRAME:   " + EnumToString(TradeTimeframe) + "\n\r";
   OutputText += "FIXED LOT SIZE:   " + DoubleToString(FixedLotSize,2) + "  |  SL/TP SENT TO BROKER: NONE\n\r";
   OutputText += "TIMED EXIT:   " + (CloseAfterXCandles > 0 ? ("close after " + IntegerToString(CloseAfterXCandles) + " candles") : "disabled") + "\n\r\n\r";

   OutputText += "--- PATTERN: SMA21>EMA21 cross + Squeeze + Stoch K-cross-below-D + Close<BB_lower(20,2) cross ---\n\r";
   OutputText += "Last evaluated bar time:   " + (Last_Eval_Time>0 ? TimeToString(Last_Eval_Time, TIME_DATE|TIME_MINUTES) : "n/a") + "\n\r";
   OutputText += "  SMA21_above_EMA21 (cross):     " + (Last_SMA_above_EMA_Cross     ? "TRUE" : "false") + "\n\r";
   OutputText += "  squeeze_active (state):        " + (Last_Squeeze_active          ? "TRUE" : "false") + "\n\r";
   OutputText += "  STO_K14_cross_below_D (cross): " + (Last_Stoch_cross_below       ? "TRUE" : "false") + "\n\r";
   OutputText += "  Close_below_BB_lower (cross):  " + (Last_Close_below_BBLow_Cross ? "TRUE" : "false") + "\n\r";
   OutputText += "  >>> FULL PATTERN FIRED:        " + (Last_Signal_fired            ? "YES"  : "no")   + "\n\r\n\r";

   OutputText += "Signals detected (this session):   " + IntegerToString(SignalsDetectedCount) + "\n\r";
   OutputText += "Trades opened (this session):      " + IntegerToString(TradesOpenedCount) + "\n\r\n\r";

   OutputText += "--- REPORT REFERENCE STATS (historical, from prior analysis) ---\n\r";
   OutputText += "Consistency Score: 0.6410   Match Count: 1348   Dominant Dir: BULLISH 62.2%\n\r";
   OutputText += "Mag ATR mean/std: 1.5022 / 0.7656 (CV 0.5097)   Timing: 1.39 candles   Persistence: 1.27\n\r";
   OutputText += "Frequency: 0.674%   Overfit Status: STABLE (train 60.6% / val 70.5% / oos 50.0%)\n\r";

   Comment(OutputText);
}
//+------------------------------------------------------------------+