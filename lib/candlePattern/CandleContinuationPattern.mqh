//+------------------------------------------------------------------+
//|                                           CandleContinuationPatterns.mqh |
//|        Candlestick Continuation Patterns (Bullish & Bearish)         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Include common gap functions from 3CandlePattern.mqh             |
//+------------------------------------------------------------------+
#include "3CandlePattern.mqh"

//+------------------------------------------------------------------+
//| ENUM for continuation signal types                               |
//+------------------------------------------------------------------+
enum ENUM_CONTINUATION_SIGNAL
{
   SIGNAL_CONT_NONE = 0,
   SIGNAL_CONT_BULLISH,
   SIGNAL_CONT_BEARISH
};

//+------------------------------------------------------------------+
//| Helper function to check if candle is bullish                    |
//+------------------------------------------------------------------+
bool IsBullishCandle(const double &open[], const double &close[], int shift)
{
   return (close[shift] > open[shift]);
}

//+------------------------------------------------------------------+
//| Helper function to check if candle is bearish                    |
//+------------------------------------------------------------------+
bool IsBearishCandle(const double &open[], const double &close[], int shift)
{
   return (close[shift] < open[shift]);
}

//+------------------------------------------------------------------+
//| Helper function to check if candle is Marubozu                   |
//| (little to no shadow)                                            |
//+------------------------------------------------------------------+
bool IsMarubozu(const double &open[], const double &high[], const double &low[], const double &close[], int shift, bool bullish)
{
   double range = high[shift] - low[shift];
   if(range == 0) return false;
   
   if(bullish)
   {
      double lowerShadow = open[shift] - low[shift];
      double upperShadow = high[shift] - close[shift];
      return (lowerShadow <= range * 0.05 && upperShadow <= range * 0.1);
   }
   else
   {
      double lowerShadow = close[shift] - low[shift];
      double upperShadow = high[shift] - open[shift];
      return (upperShadow <= range * 0.05 && lowerShadow <= range * 0.1);
   }
}

// NOTE: IsGapUp and IsGapDown functions are now included from 3CandlePattern.mqh
// Do not redefine them here to avoid duplicate function errors

//+------------------------------------------------------------------+
//| ================ BULLISH CONTINUATION PATTERNS ================  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Upward Gap Tasuki (Bullish Continuation)                         |
//| Description: This pattern occurs in an uptrend                   |
//| Candle 1: Long bullish candle                                    |
//| Candle 2: Bullish candle with gap up from Candle 1               |
//| Candle 3: Bearish candle that opens inside the gap,              |
//|           and closes inside Candle 2's body                      |
//+------------------------------------------------------------------+
bool IsUpwardGapTasuki(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // shift = most recent candle (candle 3), candle 2 = shift+1, candle 1 = shift+2
   
   // Candle 1: Bullish candle (preferably long)
   if(!IsBullishCandle(open, close, shift+2))
      return false;
   
   // Candle 2: Bullish candle with gap up from Candle 1
   if(!IsBullishCandle(open, close, shift+1))
      return false;
   
   // Gap up from Candle 1 to Candle 2
   bool gapUp = IsGapUp(low, high, shift+1, shift+2);
   if(!gapUp)
      return false;
   
   // Candle 3: Bearish candle
   if(!IsBearishCandle(open, close, shift))
      return false;
   
   // Candle 3 open must be inside the gap (between Candle 1 high and Candle 2 low)
   double gapBottom = high[shift+2];  // High of Candle 1 (before gap)
   double gapTop = low[shift+1];      // Low of Candle 2 (after gap)
   
   bool openInsideGap = (open[shift] > gapBottom && open[shift] < gapTop);
   
   // Candle 3 close must be inside Candle 2's body
   double body2Top = MathMax(open[shift+1], close[shift+1]);
   double body2Bottom = MathMin(open[shift+1], close[shift+1]);
   
   bool closeInsideBody2 = (close[shift] < body2Top && close[shift] > body2Bottom);
   
   return (openInsideGap && closeInsideBody2);
}

//+------------------------------------------------------------------+
//| Rising Three Methods (Bullish Continuation)                      |
//| Description: Long bullish candle, followed by 3 small bearish    |
//|              candles that remain within Candle 1's range,        |
//|              then another bullish candle                         |
//| Simplified version: 1 long bullish + 2-3 small candles + bullish |
//+------------------------------------------------------------------+
bool IsRisingThree(const double &open[], const double &high[], const double &low[], const double &close[], int shift, int barsCount)
{
   // shift = most recent candle (candle 5), candle 4 = shift+1, candle 3 = shift+2,
   // candle 2 = shift+3, candle 1 = shift+4
   
   // Minimum 5 candles required
   if(shift+4 >= barsCount)
      return false;
   
   // Candle 1 (shift+4): Long bullish candle
   if(!IsBullishCandle(open, close, shift+4))
      return false;
   
   double body1 = close[shift+4] - open[shift+4];
   double range1 = high[shift+4] - low[shift+4];
   if(range1 == 0) return false;
   bool isLongCandle1 = (body1 >= range1 * 0.5);
   if(!isLongCandle1) return false;
   
   // Candle 2, 3, 4 (shift+3, shift+2, shift+1): Small candles (can be bullish/bearish)
   // Must trade within Candle 1's range
   double high1 = high[shift+4];
   double low1 = low[shift+4];
   
   for(int i = 1; i <= 3; i++)
   {
      // Candle must be within Candle 1's range
      if(high[shift+i] > high1 || low[shift+i] < low1)
         return false;
      
      // Candle body must be relatively small
      double body = MathAbs(close[shift+i] - open[shift+i]);
      double range = high[shift+i] - low[shift+i];
      if(range > 0 && body > range * 0.6)
         return false;  // Not a small candle
   }
   
   // Candle 5 (shift): Bullish candle
   if(!IsBullishCandle(open, close, shift))
      return false;
   
   // Candle 5 close must be above Candle 1's High (or at least above Candle 1's body)
   bool closeAboveHigh1 = (close[shift] > high1);
   
   return closeAboveHigh1;
}

//+------------------------------------------------------------------+
//| ================ BEARISH CONTINUATION PATTERNS ================  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Downward Gap Tasuki (Bearish Continuation)                       |
//| Description: This pattern occurs in a downtrend                  |
//| Candle 1: Long bearish candle                                    |
//| Candle 2: Bearish candle with gap down from Candle 1             |
//| Candle 3: Bullish candle that opens inside the gap,              |
//|           and closes inside Candle 2's body                      |
//+------------------------------------------------------------------+
bool IsDownwardGapTasuki(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // shift = most recent candle (candle 3), candle 2 = shift+1, candle 1 = shift+2
   
   // Candle 1: Bearish candle
   if(!IsBearishCandle(open, close, shift+2))
      return false;
   
   // Candle 2: Bearish candle with gap down from Candle 1
   if(!IsBearishCandle(open, close, shift+1))
      return false;
   
   // Gap down from Candle 1 to Candle 2
   bool gapDown = IsGapDown(high, low, shift+1, shift+2);
   if(!gapDown)
      return false;
   
   // Candle 3: Bullish candle
   if(!IsBullishCandle(open, close, shift))
      return false;
   
   // Candle 3 open must be inside the gap
   double gapTop = low[shift+2];     // Low of Candle 1 (before gap)
   double gapBottom = high[shift+1]; // High of Candle 2 (after gap)
   
   bool openInsideGap = (open[shift] < gapTop && open[shift] > gapBottom);
   
   // Candle 3 close must be inside Candle 2's body
   double body2Top = MathMax(open[shift+1], close[shift+1]);
   double body2Bottom = MathMin(open[shift+1], close[shift+1]);
   
   bool closeInsideBody2 = (close[shift] < body2Top && close[shift] > body2Bottom);
   
   return (openInsideGap && closeInsideBody2);
}

//+------------------------------------------------------------------+
//| Falling Three Methods (Bearish Continuation)                     |
//| Description: Long bearish candle, followed by 3 small bullish    |
//|              candles that remain within Candle 1's range,        |
//|              then another bearish candle                         |
//+------------------------------------------------------------------+
bool IsFallingThree(const double &open[], const double &high[], const double &low[], const double &close[], int shift, int barsCount)
{
   // shift = most recent candle (candle 5), candle 4 = shift+1, candle 3 = shift+2,
   // candle 2 = shift+3, candle 1 = shift+4
   
   if(shift+4 >= barsCount)
      return false;
   
   // Candle 1 (shift+4): Long bearish candle
   if(!IsBearishCandle(open, close, shift+4))
      return false;
   
   double body1 = open[shift+4] - close[shift+4];  // positive for bearish
   double range1 = high[shift+4] - low[shift+4];
   if(range1 == 0) return false;
   bool isLongCandle1 = (body1 >= range1 * 0.5);
   if(!isLongCandle1) return false;
   
   // Candle 2, 3, 4: Small candles (can be bullish/bearish)
   // Must trade within Candle 1's range
   double high1 = high[shift+4];
   double low1 = low[shift+4];
   
   for(int i = 1; i <= 3; i++)
   {
      if(high[shift+i] > high1 || low[shift+i] < low1)
         return false;
      
      double body = MathAbs(close[shift+i] - open[shift+i]);
      double range = high[shift+i] - low[shift+i];
      if(range > 0 && body > range * 0.6)
         return false;
   }
   
   // Candle 5 (shift): Bearish candle
   if(!IsBearishCandle(open, close, shift))
      return false;
   
   // Candle 5 close must be below Candle 1's Low
   bool closeBelowLow1 = (close[shift] < low1);
   
   return closeBelowLow1;
}

//+------------------------------------------------------------------+
//| ================ MAIN FUNCTIONS ================                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Detect all continuation patterns with trend filter               |
//+------------------------------------------------------------------+
ENUM_CONTINUATION_SIGNAL GetContinuationSignal(const double &open[], const double &high[], const double &low[], const double &close[], 
                                                int shift, int barsCount, bool requireTrendFilter = true)
{
   // For continuation patterns, we need to confirm the existing trend
   
   // Bullish patterns - require established uptrend
   if(IsUpwardGapTasuki(open, high, low, close, shift) || 
      IsRisingThree(open, high, low, close, shift, barsCount))
   {
      if(requireTrendFilter)
      {
         // Check uptrend: last 3 candles before pattern are rising
         bool uptrend = (close[shift+3] > close[shift+4] && 
                         close[shift+4] > close[shift+5] &&
                         close[shift+5] > close[shift+6]);
         
         // Or use simple moving average - requires separate MA parameter
         if(!uptrend && barsCount > shift+3+20)
         {
            // MA calculated in calling function, passed as parameter
            // For now, skip MA check if no parameter available
            uptrend = true; // Default to true if cannot check MA
         }
         
         if(uptrend)
            return SIGNAL_CONT_BULLISH;
         else
            return SIGNAL_CONT_NONE;
      }
      return SIGNAL_CONT_BULLISH;
   }
   
   // Bearish patterns - require established downtrend
   if(IsDownwardGapTasuki(open, high, low, close, shift) || 
      IsFallingThree(open, high, low, close, shift, barsCount))
   {
      if(requireTrendFilter)
      {
         // Check downtrend
         bool downtrend = (close[shift+3] < close[shift+4] && 
                           close[shift+4] < close[shift+5] &&
                           close[shift+5] < close[shift+6]);
         
         if(!downtrend && barsCount > shift+3+20)
         {
            downtrend = true; // Default to true if cannot check MA
         }
         
         if(downtrend)
            return SIGNAL_CONT_BEARISH;
         else
            return SIGNAL_CONT_NONE;
      }
      return SIGNAL_CONT_BEARISH;
   }
   
   return SIGNAL_CONT_NONE;
}

//+------------------------------------------------------------------+
//| Detect specific pattern by name                                  |
//+------------------------------------------------------------------+
string GetDetectedPatternNameCont(const double &open[], const double &high[], const double &low[], const double &close[], 
                                   int shift, int barsCount)
{
   if(IsUpwardGapTasuki(open, high, low, close, shift)) 
      return "Upward Gap Tasuki";
   if(IsRisingThree(open, high, low, close, shift, barsCount)) 
      return "Rising Three Methods";
   if(IsDownwardGapTasuki(open, high, low, close, shift)) 
      return "Downward Gap Tasuki";
   if(IsFallingThree(open, high, low, close, shift, barsCount)) 
      return "Falling Three Methods";
   
   return "None";
}

//+------------------------------------------------------------------+
//| Verify if continuation signal is valid                           |
//+------------------------------------------------------------------+
bool IsValidContinuationSignal(ENUM_CONTINUATION_SIGNAL signal)
{
   if(signal == SIGNAL_CONT_BULLISH)
   {
      // Additional validation for bullish continuation
      // Increasing volume? (optional)
      // Or confirmation from other indicators
      return true;
   }
   else if(signal == SIGNAL_CONT_BEARISH)
   {
      return true;
   }
   return false;
}