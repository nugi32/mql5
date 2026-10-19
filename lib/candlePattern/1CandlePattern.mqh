//+------------------------------------------------------------------+
//|                                               CandlePatterns.mqh |
//|                       Pola 1 Candle Bullish & Bearish Reversal   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ENUM untuk tipe sinyal                                           |
//+------------------------------------------------------------------+
enum ENUM_CANDLE_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BULLISH,
   SIGNAL_BEARISH
};

//+------------------------------------------------------------------+
//| Fungsi mendeteksi Southern Doji (Bullish)                        |
//+------------------------------------------------------------------+
bool IsSouthernDoji(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   // Doji criteria: body < 10% of range
   if(body > range * 0.1) return false;
   
   // Southern: close near low, open near low
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Lower shadow must be small, price near low
   return (lowerShadow <= range * 0.1 && upperShadow >= range * 0.7);
}

//+------------------------------------------------------------------+
//| Southern Long-Leg Doji (Bullish)                                 |
//+------------------------------------------------------------------+
bool IsSouthernLongLegDoji(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   // Long leg doji: body very small
   if(body > range * 0.05) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Long lower shadow and small upper shadow, but price near low for southern
   return (lowerShadow >= range * 0.4 && upperShadow <= range * 0.3);
}

//+------------------------------------------------------------------+
//| Dragonfly Doji / Dragonfly (Bullish)                             |
//+------------------------------------------------------------------+
bool IsDragonfly(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Dragonfly: long lower shadow, very short or no upper shadow, small body
   bool condition = (upperShadow <= range * 0.1) && 
                    (lowerShadow >= range * 0.6) &&
                    (body <= range * 0.3);
   
   return condition;
}

//+------------------------------------------------------------------+
//| Hammer (Bullish reversal after downtrend)                        |
//+------------------------------------------------------------------+
bool IsHammer(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Hammer criteria: lower shadow >= 2x body, upper shadow small
   bool condition = (lowerShadow >= body * 2) && 
                    (upperShadow <= body * 0.5) &&
                    (body <= range * 0.4);
   
   return condition;
}

//+------------------------------------------------------------------+
//| Inverted Hammer (Bullish reversal)                               |
//+------------------------------------------------------------------+
bool IsInvertedHammer(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Inverted hammer: upper shadow >= 2x body, lower shadow small
   bool condition = (upperShadow >= body * 2) && 
                    (lowerShadow <= body * 0.5) &&
                    (body <= range * 0.4);
   
   return condition;
}

//+------------------------------------------------------------------+
//| Bullish Belt Hold (Long white candle with no lower shadow)      |
//+------------------------------------------------------------------+
bool IsBullishBeltHold(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = close[shift] - open[shift];
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   // Bullish candle
   if(body <= 0) return false;
   
   double lowerShadow = open[shift] - low[shift];
   double upperShadow = high[shift] - close[shift];
   
   // No lower shadow or very tiny, upper shadow allowed
   return (lowerShadow <= range * 0.05) && (body >= range * 0.6);
}

//+------------------------------------------------------------------+
//| Northern Doji (Bearish)                                          |
//+------------------------------------------------------------------+
bool IsNorthernDoji(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   if(body > range * 0.1) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Northern: price near high
   return (upperShadow <= range * 0.1 && lowerShadow >= range * 0.7);
}

//+------------------------------------------------------------------+
//| Northern Long-Leg Doji (Bearish)                                 |
//+------------------------------------------------------------------+
bool IsNorthernLongLegDoji(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   if(body > range * 0.05) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Long upper shadow, price near high
   return (upperShadow >= range * 0.4 && lowerShadow <= range * 0.3);
}

//+------------------------------------------------------------------+
//| Gravestone Doji (Bearish)                                        |
//+------------------------------------------------------------------+
bool IsGravestone(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Gravestone: long upper shadow, very short lower shadow, small body
   return (lowerShadow <= range * 0.1) && 
          (upperShadow >= range * 0.6) &&
          (body <= range * 0.3);
}

//+------------------------------------------------------------------+
//| Shooting Star (Bearish reversal after uptrend)                  |
//+------------------------------------------------------------------+
bool IsShootingStar(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Shooting star: upper shadow >= 2x body, lower shadow small
   return (upperShadow >= body * 2) && 
          (lowerShadow <= body * 0.5) &&
          (body <= range * 0.4);
}

//+------------------------------------------------------------------+
//| Hanging Man (Bearish reversal after uptrend)                    |
//+------------------------------------------------------------------+
bool IsHangingMan(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   double lowerShadow = (close[shift] < open[shift]) ? close[shift] - low[shift] : open[shift] - low[shift];
   double upperShadow = high[shift] - (close[shift] > open[shift] ? close[shift] : open[shift]);
   
   // Hanging man: lower shadow >= 2x body, upper shadow small
   return (lowerShadow >= body * 2) && 
          (upperShadow <= body * 0.5) &&
          (body <= range * 0.4);
}

//+------------------------------------------------------------------+
//| Bearish Belt Hold (Long black candle with no upper shadow)      |
//+------------------------------------------------------------------+
bool IsBearishBeltHold(const double &open[], const double &close[], const double &high[], const double &low[], int shift)
{
   double body = close[shift] - open[shift];
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   
   // Bearish candle
   if(body >= 0) return false;
   
   double lowerShadow = close[shift] - low[shift];
   double upperShadow = high[shift] - open[shift];
   
   // No upper shadow, lower shadow allowed
   return (upperShadow <= range * 0.05) && (MathAbs(body) >= range * 0.6);
}

//+------------------------------------------------------------------+
//| Fungsi utama deteksi sinyal reversal                             |
//+------------------------------------------------------------------+
ENUM_CANDLE_SIGNAL GetCandleReversalSignal(const double &open[], const double &close[], const double &high[], const double &low[], int shift, bool requireTrendFilter = true)
{
   // Bullish patterns
   if(IsSouthernDoji(open, close, high, low, shift) ||
      IsSouthernLongLegDoji(open, close, high, low, shift) ||
      IsDragonfly(open, close, high, low, shift) ||
      IsHammer(open, close, high, low, shift) ||
      IsInvertedHammer(open, close, high, low, shift) ||
      IsBullishBeltHold(open, close, high, low, shift))
   {
      if(requireTrendFilter)
      {
         // Require downtrend for bullish reversal
         if(close[shift+1] < close[shift+2] && close[shift+2] < close[shift+3])
            return SIGNAL_BULLISH;
         else
            return SIGNAL_NONE;
      }
      return SIGNAL_BULLISH;
   }
   
   // Bearish patterns
   if(IsNorthernDoji(open, close, high, low, shift) ||
      IsNorthernLongLegDoji(open, close, high, low, shift) ||
      IsGravestone(open, close, high, low, shift) ||
      IsShootingStar(open, close, high, low, shift) ||
      IsHangingMan(open, close, high, low, shift) ||
      IsBearishBeltHold(open, close, high, low, shift))
   {
      if(requireTrendFilter)
      {
         // Require uptrend for bearish reversal
         if(close[shift+1] > close[shift+2] && close[shift+2] > close[shift+3])
            return SIGNAL_BEARISH;
         else
            return SIGNAL_NONE;
      }
      return SIGNAL_BEARISH;
   }
   
   return SIGNAL_NONE;
}