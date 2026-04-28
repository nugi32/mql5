//+------------------------------------------------------------------+
//|                                                   Candle2Patterns.mqh |
//|        Pola 2 Candle Bullish & Bearish Reversal                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ENUM untuk tipe sinyal                                           |
//+------------------------------------------------------------------+
enum ENUM_CANDLE2_SIGNAL
{
   SIGNAL2_NONE = 0,
   SIGNAL2_BULLISH,
   SIGNAL2_BEARISH
};

//+------------------------------------------------------------------+
//| Fungsi bantu untuk mendapatkan point value                       |
//+------------------------------------------------------------------+
double GetPointValue()
{
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointValue == 0) pointValue = _Point;
   return pointValue;
}

//+------------------------------------------------------------------+
//| ================ POLA 2 CANDLE BULLISH REVERSAL ================ |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Bullish Pregnant (Bullish Harami)                                |
//| Candle 1: Long bearish candle                                    |
//| Candle 2: Small bullish candle completely inside Candle 1        |
//+------------------------------------------------------------------+
bool IsBullishPregnant(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // shift = index candle terbaru (candle 2), candle 1 = shift+1
   double body1 = close[shift+1] - open[shift+1];  // Candle 1
   double body2 = close[shift] - open[shift];      // Candle 2
   
   // Candle 1 harus bearish (body negatif)
   if(body1 >= 0) return false;
   // Candle 2 harus bullish (body positif)
   if(body2 <= 0) return false;
   
   double range1 = high[shift+1] - low[shift+1];
   if(range1 == 0) return false;
   
   // Candle 2 harus completely inside Candle 1
   bool inside = (high[shift] <= high[shift+1] && low[shift] >= low[shift+1]);
   
   // Body Candle 2 relatif kecil
   bool smallBody = (MathAbs(body2) <= MathAbs(body1) * 0.5);
   
   return (inside && smallBody);
}

//+------------------------------------------------------------------+
//| Bullish Pregnant Cross (Bullish Harami Cross)                    |
//| Candle 1: Long bearish candle                                    |
//| Candle 2: Doji completely inside Candle 1                        |
//+------------------------------------------------------------------+
bool IsBullishPregnantCross(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = MathAbs(close[shift] - open[shift]);
   double range2 = high[shift] - low[shift];
   
   // Candle 1 bearish
   if(body1 >= 0) return false;
   if(range2 == 0) return false;
   
   // Candle 2 adalah Doji (body sangat kecil)
   bool isDoji = (body2 <= range2 * 0.1);
   
   // Candle 2 completely inside Candle 1
   bool inside = (high[shift] <= high[shift+1] && low[shift] >= low[shift+1]);
   
   return (inside && isDoji);
}

//+------------------------------------------------------------------+
//| Bullish Homing Pigeon                                            |
//| Candle 1: Bearish candle                                         |
//| Candle 2: Bearish candle with body inside Candle 1's body        |
//|          and close near high                                     |
//+------------------------------------------------------------------+
bool IsBullishHomingPigeon(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = close[shift] - open[shift];
   
   // Kedua candle harus bearish
   if(body1 >= 0) return false;
   if(body2 >= 0) return false;
   
   // Body candle 2 harus di dalam body candle 1
   double body1Top = MathMax(open[shift+1], close[shift+1]);
   double body1Bottom = MathMin(open[shift+1], close[shift+1]);
   double body2Top = MathMax(open[shift], close[shift]);
   double body2Bottom = MathMin(open[shift], close[shift]);
   
   bool insideBody = (body2Top <= body1Top && body2Bottom >= body1Bottom);
   
   // Close candle 2 mendekati high (menunjukkan potensi reversal)
   double range2 = high[shift] - low[shift];
   double closeNearHigh = (range2 > 0) ? ((high[shift] - close[shift]) / range2) <= 0.3 : false;
   
   return (insideBody && closeNearHigh);
}

//+------------------------------------------------------------------+
//| Matching Low                                                     |
//| Dua candle dengan low yang sama atau hampir sama                 |
//| Setelah downtrend, ini menunjukkan support kuat                  |
//+------------------------------------------------------------------+
bool IsMatchingLow(const double &low[], const double &open[], const double &close[], int shift)
{
   double low1 = low[shift+1];
   double low2 = low[shift];
   
   if(low1 == 0 || low2 == 0) return false;
   
   double pointValue = GetPointValue();
   double diff = MathAbs(low1 - low2);
   double tolerance = pointValue * 5;  // 5 points tolerance
   
   // Candle 1 bearish, candle 2 bisa apa saja
   bool candle1Bearish = (close[shift+1] < open[shift+1]);
   
   return (diff <= tolerance && candle1Bearish);
}

//+------------------------------------------------------------------+
//| Bullish Engulfing                                                |
//| Candle 1: Bearish candle                                         |
//| Candle 2: Bullish candle yang completely menutupi Candle 1       |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = close[shift] - open[shift];
   
   // Candle 1 bearish, Candle 2 bullish
   if(body1 >= 0) return false;
   if(body2 <= 0) return false;
   
   // Bullish engulfing: Candle 2 menutupi seluruh Candle 1
   bool engulf = (open[shift] <= close[shift+1] && close[shift] >= open[shift+1]);
   
   // Atau versi lebih ketat: mencakup seluruh range
   bool fullEngulf = (low[shift] <= low[shift+1] && high[shift] >= high[shift+1]);
   
   return (engulf || fullEngulf);
}

//+------------------------------------------------------------------+
//| Piercing Line                                                    |
//| Candle 1: Long bearish candle                                    |
//| Candle 2: Bullish candle yang open di bawah low Candle 1         |
//|          dan close di atas 50% body Candle 1                     |
//+------------------------------------------------------------------+
bool IsPiercingLine(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = close[shift] - open[shift];
   
   // Candle 1 bearish, Candle 2 bullish
   if(body1 >= 0) return false;
   if(body2 <= 0) return false;
   
   // Open candle 2 di bawah low candle 1
   bool openBelowLow = (open[shift] < low[shift+1]);
   
   // Close candle 2 di atas 50% body candle 1
   double body1Length = MathAbs(body1);
   double body1Mid = open[shift+1] - (body1Length / 2);  // Untuk bearish, mid = open - 50% body
   
   bool closeAboveMid = (close[shift] > body1Mid);
   
   // Candle 1 memiliki body yang signifikan
   bool significantBody = (body1Length >= (high[shift+1] - low[shift+1]) * 0.5);
   
   return (openBelowLow && closeAboveMid && significantBody);
}

//+------------------------------------------------------------------+
//| Tweezer Bottom                                                   |
//| Dua candle dengan low yang sama atau hampir sama                 |
//| Candle 1: Bearish, Candle 2: Bullish                             |
//+------------------------------------------------------------------+
bool IsTweezerBottom(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double low1 = low[shift+1];
   double low2 = low[shift];
   
   if(low1 == 0 || low2 == 0) return false;
   
   double pointValue = GetPointValue();
   double diff = MathAbs(low1 - low2);
   double tolerance = pointValue * 5;
   
   bool sameLow = (diff <= tolerance);
   bool candle1Bearish = (close[shift+1] < open[shift+1]);
   bool candle2Bullish = (close[shift] > open[shift]);
   
   // Lower shadow pada kedua candle (opsional, untuk konfirmasi)
   double range1 = high[shift+1] - low[shift+1];
   double range2 = high[shift] - low[shift];
   bool hasLowerShadow1 = (range1 > 0) ? ((close[shift+1] > low[shift+1]) || (open[shift+1] > low[shift+1])) : false;
   bool hasLowerShadow2 = (range2 > 0) ? ((close[shift] > low[shift]) || (open[shift] > low[shift])) : false;
   
   return (sameLow && candle1Bearish && candle2Bullish);
}

//+------------------------------------------------------------------+
//| ================ POLA 2 CANDLE BEARISH REVERSAL ================ |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Bearish Pregnant (Bearish Harami)                                |
//| Candle 1: Long bullish candle                                    |
//| Candle 2: Small bearish candle completely inside Candle 1        |
//+------------------------------------------------------------------+
bool IsBearishPregnant(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = close[shift] - open[shift];
   
   // Candle 1 bullish, Candle 2 bearish
   if(body1 <= 0) return false;
   if(body2 >= 0) return false;
   
   double range1 = high[shift+1] - low[shift+1];
   if(range1 == 0) return false;
   
   // Candle 2 completely inside Candle 1
   bool inside = (high[shift] <= high[shift+1] && low[shift] >= low[shift+1]);
   
   // Body Candle 2 relatif kecil
   bool smallBody = (MathAbs(body2) <= MathAbs(body1) * 0.5);
   
   return (inside && smallBody);
}

//+------------------------------------------------------------------+
//| Bearish Pregnant Cross (Bearish Harami Cross)                    |
//| Candle 1: Long bullish candle                                    |
//| Candle 2: Doji completely inside Candle 1                        |
//+------------------------------------------------------------------+
bool IsBearishPregnantCross(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = MathAbs(close[shift] - open[shift]);
   double range2 = high[shift] - low[shift];
   
   // Candle 1 bullish
   if(body1 <= 0) return false;
   if(range2 == 0) return false;
   
   // Candle 2 adalah Doji
   bool isDoji = (body2 <= range2 * 0.1);
   
   // Candle 2 completely inside Candle 1
   bool inside = (high[shift] <= high[shift+1] && low[shift] >= low[shift+1]);
   
   return (inside && isDoji);
}

//+------------------------------------------------------------------+
//| Bearish Homing Pigeon                                            |
//| Candle 1: Bullish candle                                         |
//| Candle 2: Bullish candle dengan body inside Candle 1's body      |
//|          dan close near low                                      |
//+------------------------------------------------------------------+
bool IsBearishHomingPigeon(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = close[shift] - open[shift];
   
   // Kedua candle harus bullish
   if(body1 <= 0) return false;
   if(body2 <= 0) return false;
   
   // Body candle 2 harus di dalam body candle 1
   double body1Top = MathMax(open[shift+1], close[shift+1]);
   double body1Bottom = MathMin(open[shift+1], close[shift+1]);
   double body2Top = MathMax(open[shift], close[shift]);
   double body2Bottom = MathMin(open[shift], close[shift]);
   
   bool insideBody = (body2Top <= body1Top && body2Bottom >= body1Bottom);
   
   // Close candle 2 mendekati low
   double range2 = high[shift] - low[shift];
   double closeNearLow = (range2 > 0) ? ((close[shift] - low[shift]) / range2) <= 0.3 : false;
   
   return (insideBody && closeNearLow);
}

//+------------------------------------------------------------------+
//| Matching High                                                    |
//| Dua candle dengan high yang sama atau hampir sama                |
//| Setelah uptrend, ini menunjukkan resistance kuat                 |
//+------------------------------------------------------------------+
bool IsMatchingHigh(const double &high[], const double &open[], const double &close[], int shift)
{
   double high1 = high[shift+1];
   double high2 = high[shift];
   
   if(high1 == 0 || high2 == 0) return false;
   
   double pointValue = GetPointValue();
   double diff = MathAbs(high1 - high2);
   double tolerance = pointValue * 5;
   
   // Candle 1 bullish
   bool candle1Bullish = (close[shift+1] > open[shift+1]);
   
   return (diff <= tolerance && candle1Bullish);
}

//+------------------------------------------------------------------+
//| Bearish Engulfing                                                |
//| Candle 1: Bullish candle                                         |
//| Candle 2: Bearish candle yang completely menutupi Candle 1       |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = close[shift] - open[shift];
   
   // Candle 1 bullish, Candle 2 bearish
   if(body1 <= 0) return false;
   if(body2 >= 0) return false;
   
   // Bearish engulfing: Candle 2 menutupi seluruh Candle 1
   bool engulf = (open[shift] >= close[shift+1] && close[shift] <= open[shift+1]);
   
   bool fullEngulf = (high[shift] >= high[shift+1] && low[shift] <= low[shift+1]);
   
   return (engulf || fullEngulf);
}

//+------------------------------------------------------------------+
//| Dark Cloud Cover                                                 |
//| Candle 1: Long bullish candle                                    |
//| Candle 2: Bearish candle yang open di atas high Candle 1         |
//|          dan close di bawah 50% body Candle 1                    |
//+------------------------------------------------------------------+
bool IsDarkCloudCover(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body1 = close[shift+1] - open[shift+1];
   double body2 = close[shift] - open[shift];
   
   // Candle 1 bullish, Candle 2 bearish
   if(body1 <= 0) return false;
   if(body2 >= 0) return false;
   
   // Open candle 2 di atas high candle 1
   bool openAboveHigh = (open[shift] > high[shift+1]);
   
   // Close candle 2 di bawah 50% body candle 1
   double body1Length = MathAbs(body1);
   double body1Mid = open[shift+1] + (body1Length / 2);  // Untuk bullish, mid = open + 50% body
   
   bool closeBelowMid = (close[shift] < body1Mid);
   
   // Candle 1 memiliki body yang signifikan
   bool significantBody = (body1Length >= (high[shift+1] - low[shift+1]) * 0.5);
   
   return (openAboveHigh && closeBelowMid && significantBody);
}

//+------------------------------------------------------------------+
//| Tweezer Top                                                      |
//| Dua candle dengan high yang sama atau hampir sama                |
//| Candle 1: Bullish, Candle 2: Bearish                             |
//+------------------------------------------------------------------+
bool IsTweezerTop(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double high1 = high[shift+1];
   double high2 = high[shift];
   
   if(high1 == 0 || high2 == 0) return false;
   
   double pointValue = GetPointValue();
   double diff = MathAbs(high1 - high2);
   double tolerance = pointValue * 5;
   
   bool sameHigh = (diff <= tolerance);
   bool candle1Bullish = (close[shift+1] > open[shift+1]);
   bool candle2Bearish = (close[shift] < open[shift]);
   
   // Upper shadow pada kedua candle
   double range1 = high[shift+1] - low[shift+1];
   double range2 = high[shift] - low[shift];
   bool hasUpperShadow1 = (range1 > 0) ? ((high[shift+1] > close[shift+1]) || (high[shift+1] > open[shift+1])) : false;
   bool hasUpperShadow2 = (range2 > 0) ? ((high[shift] > close[shift]) || (high[shift] > open[shift])) : false;
   
   return (sameHigh && candle1Bullish && candle2Bearish);
}

//+------------------------------------------------------------------+
//| ================ FUNGSI UTAMA ================                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Deteksi semua pola 2 candle reversal                             |
//+------------------------------------------------------------------+
ENUM_CANDLE2_SIGNAL GetCandle2ReversalSignal(const double &open[], const double &high[], const double &low[], const double &close[], 
                                               int shift, int barsCount, bool requireTrendFilter = true)
{
   // Bullish patterns
   if(IsBullishPregnant(open, high, low, close, shift) ||
      IsBullishPregnantCross(open, high, low, close, shift) ||
      IsBullishHomingPigeon(open, high, low, close, shift) ||
      IsMatchingLow(low, open, close, shift) ||
      IsBullishEngulfing(open, high, low, close, shift) ||
      IsPiercingLine(open, high, low, close, shift) ||
      IsTweezerBottom(open, high, low, close, shift))
   {
      if(requireTrendFilter && shift+4 < barsCount)
      {
         // Require downtrend untuk bullish reversal (2 candle terakhir sebelum pola)
         if(close[shift+2] < close[shift+3] && close[shift+3] < close[shift+4])
            return SIGNAL2_BULLISH;
         else
            return SIGNAL2_NONE;
      }
      return SIGNAL2_BULLISH;
   }
   
   // Bearish patterns
   if(IsBearishPregnant(open, high, low, close, shift) ||
      IsBearishPregnantCross(open, high, low, close, shift) ||
      IsBearishHomingPigeon(open, high, low, close, shift) ||
      IsMatchingHigh(high, open, close, shift) ||
      IsBearishEngulfing(open, high, low, close, shift) ||
      IsDarkCloudCover(open, high, low, close, shift) ||
      IsTweezerTop(open, high, low, close, shift))
   {
      if(requireTrendFilter && shift+4 < barsCount)
      {
         // Require uptrend untuk bearish reversal
         if(close[shift+2] > close[shift+3] && close[shift+3] > close[shift+4])
            return SIGNAL2_BEARISH;
         else
            return SIGNAL2_NONE;
      }
      return SIGNAL2_BEARISH;
   }
   
   return SIGNAL2_NONE;
}

//+------------------------------------------------------------------+
//| Deteksi spesifik pola berdasarkan nama                           |
//+------------------------------------------------------------------+
string GetDetectedPatternName2(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   if(IsBullishPregnant(open, high, low, close, shift)) return "Bullish Pregnant";
   if(IsBullishPregnantCross(open, high, low, close, shift)) return "Bullish Pregnant Cross";
   if(IsBullishHomingPigeon(open, high, low, close, shift)) return "Bullish Homing Pigeon";
   if(IsMatchingLow(low, open, close, shift)) return "Matching Low";
   if(IsBullishEngulfing(open, high, low, close, shift)) return "Bullish Engulfing";
   if(IsPiercingLine(open, high, low, close, shift)) return "Piercing Line";
   if(IsTweezerBottom(open, high, low, close, shift)) return "Tweezer Bottom";
   
   if(IsBearishPregnant(open, high, low, close, shift)) return "Bearish Pregnant";
   if(IsBearishPregnantCross(open, high, low, close, shift)) return "Bearish Pregnant Cross";
   if(IsBearishHomingPigeon(open, high, low, close, shift)) return "Bearish Homing Pigeon";
   if(IsMatchingHigh(high, open, close, shift)) return "Matching High";
   if(IsBearishEngulfing(open, high, low, close, shift)) return "Bearish Engulfing";
   if(IsDarkCloudCover(open, high, low, close, shift)) return "Dark Cloud Cover";
   if(IsTweezerTop(open, high, low, close, shift)) return "Tweezer Top";
   
   return "None";
}