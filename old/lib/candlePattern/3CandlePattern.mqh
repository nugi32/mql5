//+------------------------------------------------------------------+
//|                                                   Candle3Patterns.mqh |
//|        Pola 3 Candle Bullish & Bearish Reversal                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ENUM untuk tipe sinyal                                           |
//+------------------------------------------------------------------+
enum ENUM_CANDLE3_SIGNAL
{
   SIGNAL3_NONE = 0,
   SIGNAL3_BULLISH,
   SIGNAL3_BEARISH
};

//+------------------------------------------------------------------+
//| Fungsi bantu untuk mengecek apakah candle adalah Doji            |
//+------------------------------------------------------------------+
bool IsDoji(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   return (body <= range * 0.1);
}

//+------------------------------------------------------------------+
//| Fungsi bantu untuk mengecek apakah candle adalah Long            |
//+------------------------------------------------------------------+
bool IsLongCandle(const double &open[], const double &high[], const double &low[], const double &close[], int shift, double multiplier = 0.6)
{
   double body = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   
   if(range == 0) return false;
   return (body >= range * multiplier);
}

//+------------------------------------------------------------------+
//| Fungsi bantu untuk mengecek gap                                  |
//+------------------------------------------------------------------+
bool IsGapUp(const double &low[], const double &high[], int shift1, int shift2)
{
   return (low[shift1] > high[shift2]);
}

bool IsGapDown(const double &high[], const double &low[], int shift1, int shift2)
{
   return (high[shift1] < low[shift2]);
}

//+------------------------------------------------------------------+
//| ================ POLA 3 CANDLE BULLISH REVERSAL ================ |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Morning Star                                                     |
//| Candle 1: Long bearish candle                                    |
//| Candle 2: Small body (could be bullish or bearish)               |
//|          Gap down from Candle 1                                  |
//| Candle 3: Long bullish candle that closes into Candle 1's body   |
//+------------------------------------------------------------------+
bool IsMorningStar(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // shift = candle terbaru (candle 3), candle 2 = shift+1, candle 1 = shift+2
   
   // Candle 1: Long bearish
   if(!IsLongCandle(open, high, low, close, shift+2) || (close[shift+2] - open[shift+2]) >= 0)
      return false;
   
   // Candle 2: Small body (tidak harus doji, tapi kecil)
   double body2 = MathAbs(close[shift+1] - open[shift+1]);
   double range2 = high[shift+1] - low[shift+1];
   if(range2 == 0) return false;
   bool isSmallBody2 = (body2 <= range2 * 0.3);
   if(!isSmallBody2) return false;
   
   // Gap down dari Candle 1 ke Candle 2
   bool properGapDown = (high[shift+1] < low[shift+2]);
   if(!properGapDown) return false;
   
   // Candle 3: Long bullish
   if(!IsLongCandle(open, high, low, close, shift) || (close[shift] - open[shift]) <= 0)
      return false;
   
   // Candle 3 closes into Candle 1's body (minimal 50%)
   double body1Bottom = MathMin(open[shift+2], close[shift+2]);
   double body1Top = MathMax(open[shift+2], close[shift+2]);
   double body1Length = body1Top - body1Bottom;
   
   bool closeIntoBody1 = (close[shift] > body1Bottom + (body1Length * 0.5));
   
   return closeIntoBody1;
}

//+------------------------------------------------------------------+
//| Morning Doji Star                                                |
//| Sama seperti Morning Star, tapi Candle 2 adalah Doji             |
//+------------------------------------------------------------------+
bool IsMorningDojiStar(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // Candle 1: Long bearish
   if(!IsLongCandle(open, high, low, close, shift+2) || (close[shift+2] - open[shift+2]) >= 0)
      return false;
   
   // Candle 2: Doji
   if(!IsDoji(open, high, low, close, shift+1)) return false;
   
   // Gap down dari Candle 1 ke Candle 2
   bool properGapDown = (high[shift+1] < low[shift+2]);
   if(!properGapDown) return false;
   
   // Candle 3: Long bullish
   if(!IsLongCandle(open, high, low, close, shift) || (close[shift] - open[shift]) <= 0)
      return false;
   
   // Candle 3 closes into Candle 1's body
   double body1Bottom = MathMin(open[shift+2], close[shift+2]);
   double body1Length = MathAbs(close[shift+2] - open[shift+2]);
   
   bool closeIntoBody1 = (close[shift] > body1Bottom + (body1Length * 0.5));
   
   return closeIntoBody1;
}

//+------------------------------------------------------------------+
//| Bullish Abandoned Baby                                           |
//| Candle 1: Long bearish                                           |
//| Candle 2: Doji with gaps on both sides                           |
//| Candle 3: Long bullish                                           |
//+------------------------------------------------------------------+
bool IsBullishAbandonedBaby(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // Candle 1: Long bearish
   if(!IsLongCandle(open, high, low, close, shift+2) || (close[shift+2] - open[shift+2]) >= 0)
      return false;
   
   // Candle 2: Doji
   if(!IsDoji(open, high, low, close, shift+1)) return false;
   
   // Gap down dari Candle 1 ke Candle 2
   bool gap1 = (high[shift+1] < low[shift+2]);
   
   // Gap up dari Candle 2 ke Candle 3 (gap ke atas)
   bool gap2 = (low[shift] > high[shift+1]);
   
   // Candle 3: Long bullish
   if(!IsLongCandle(open, high, low, close, shift) || (close[shift] - open[shift]) <= 0)
      return false;
   
   return (gap1 && gap2);
}

//+------------------------------------------------------------------+
//| Morning Tri Star                                                 |
//| Tiga candle: Bearish, Doji, Doji, Bullish (atau variasi)         |
//| Candle 2 dan 3 adalah doji, dengan gap                           |
//+------------------------------------------------------------------+
bool IsMorningTriStar(const double &open[], const double &high[], const double &low[], const double &close[], int shift, int barsCount)
{
   // shift = candle terbaru (candle 3), candle 2 = shift+1, candle 1 = shift+2
   
   // Candle 1: Bearish (bisa long atau tidak)
   if((close[shift+2] - open[shift+2]) >= 0)
      return false;
   
   // Candle 2: Doji
   if(!IsDoji(open, high, low, close, shift+1)) return false;
   
   // Candle 3: Doji (bukan bullish candle, tapi doji lagi untuk tri-star)
   if(!IsDoji(open, high, low, close, shift)) return false;
   
   // Candle 4 untuk konfirmasi (shift-1) harus bullish
   if(shift-1 < 0 || shift-1 >= barsCount) return false;
   
   bool confirmBullish = (close[shift-1] > open[shift-1]) && 
                         (close[shift-1] > high[shift+2] * 0.95);
   
   // Gap pattern
   bool gap1 = (high[shift+1] < low[shift+2]);
   bool gap2 = (low[shift] > high[shift+1]);
   
   return (gap1 && gap2 && confirmBullish);
}

//+------------------------------------------------------------------+
//| Three White Soldiers                                             |
//| Tiga candle bullish berturut-turut                               |
//| Setiap candle open di dalam body candle sebelumnya              |
//| Setiap candle close lebih tinggi dari sebelumnya                |
//+------------------------------------------------------------------+
bool IsThreeWhiteSoldiers(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // shift = candle terbaru (candle 3), candle 2 = shift+1, candle 1 = shift+2
   
   // Ketiga candle harus bullish
   for(int i = 0; i <= 2; i++)
   {
      if(close[shift+i] <= open[shift+i])
         return false;
   }
   
   // Setiap candle harus memiliki body yang signifikan
   if(!IsLongCandle(open, high, low, close, shift+2) || 
      !IsLongCandle(open, high, low, close, shift+1) || 
      !IsLongCandle(open, high, low, close, shift))
      return false;
   
   // Candle 2: Open harus di dalam body Candle 1
   bool open2Inside = (open[shift+1] > open[shift+2] && open[shift+1] < close[shift+2]);
   
   // Candle 3: Open harus di dalam body Candle 2
   bool open3Inside = (open[shift] > open[shift+1] && open[shift] < close[shift+1]);
   
   // Setiap candle close lebih tinggi dari sebelumnya
   bool higherCloses = (close[shift+1] > close[shift+2]) && (close[shift] > close[shift+1]);
   
   // Upper shadow tidak boleh terlalu panjang (opsional)
   double range3 = high[shift] - low[shift];
   double upperShadow3 = high[shift] - close[shift];
   bool noLongUpperShadow = (range3 > 0) ? (upperShadow3 <= range3 * 0.3) : true;
   
   return (open2Inside && open3Inside && higherCloses && noLongUpperShadow);
}

//+------------------------------------------------------------------+
//| ================ POLA 3 CANDLE BEARISH REVERSAL ================ |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Evening Star                                                     |
//| Candle 1: Long bullish candle                                    |
//| Candle 2: Small body (gap up from Candle 1)                      |
//| Candle 3: Long bearish candle that closes into Candle 1's body   |
//+------------------------------------------------------------------+
bool IsEveningStar(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // Candle 1: Long bullish
   if(!IsLongCandle(open, high, low, close, shift+2) || (close[shift+2] - open[shift+2]) <= 0)
      return false;
   
   // Candle 2: Small body
   double body2 = MathAbs(close[shift+1] - open[shift+1]);
   double range2 = high[shift+1] - low[shift+1];
   if(range2 == 0) return false;
   bool isSmallBody2 = (body2 <= range2 * 0.3);
   if(!isSmallBody2) return false;
   
   // Gap up dari Candle 1 ke Candle 2
   bool properGapUp = (low[shift+1] > high[shift+2]);
   if(!properGapUp) return false;
   
   // Candle 3: Long bearish
   if(!IsLongCandle(open, high, low, close, shift) || (close[shift] - open[shift]) >= 0)
      return false;
   
   // Candle 3 closes into Candle 1's body (minimal 50%)
   double body1Top = MathMax(open[shift+2], close[shift+2]);
   double body1Length = MathAbs(close[shift+2] - open[shift+2]);
   
   bool closeIntoBody1 = (close[shift] < body1Top - (body1Length * 0.5));
   
   return closeIntoBody1;
}

//+------------------------------------------------------------------+
//| Evening Doji Star                                                |
//| Sama seperti Evening Star, tapi Candle 2 adalah Doji             |
//+------------------------------------------------------------------+
bool IsEveningDojiStar(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // Candle 1: Long bullish
   if(!IsLongCandle(open, high, low, close, shift+2) || (close[shift+2] - open[shift+2]) <= 0)
      return false;
   
   // Candle 2: Doji
   if(!IsDoji(open, high, low, close, shift+1)) return false;
   
   // Gap up dari Candle 1 ke Candle 2
   bool properGapUp = (low[shift+1] > high[shift+2]);
   if(!properGapUp) return false;
   
   // Candle 3: Long bearish
   if(!IsLongCandle(open, high, low, close, shift) || (close[shift] - open[shift]) >= 0)
      return false;
   
   // Candle 3 closes into Candle 1's body
   double body1Top = MathMax(open[shift+2], close[shift+2]);
   double body1Length = MathAbs(close[shift+2] - open[shift+2]);
   
   bool closeIntoBody1 = (close[shift] < body1Top - (body1Length * 0.5));
   
   return closeIntoBody1;
}

//+------------------------------------------------------------------+
//| Bearish Abandoned Baby                                           |
//| Candle 1: Long bullish                                           |
//| Candle 2: Doji with gaps on both sides                           |
//| Candle 3: Long bearish                                           |
//+------------------------------------------------------------------+
bool IsBearishAbandonedBaby(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // Candle 1: Long bullish
   if(!IsLongCandle(open, high, low, close, shift+2) || (close[shift+2] - open[shift+2]) <= 0)
      return false;
   
   // Candle 2: Doji
   if(!IsDoji(open, high, low, close, shift+1)) return false;
   
   // Gap up dari Candle 1 ke Candle 2
   bool gap1 = (low[shift+1] > high[shift+2]);
   
   // Gap down dari Candle 2 ke Candle 3
   bool gap2 = (high[shift] < low[shift+1]);
   
   // Candle 3: Long bearish
   if(!IsLongCandle(open, high, low, close, shift) || (close[shift] - open[shift]) >= 0)
      return false;
   
   return (gap1 && gap2);
}

//+------------------------------------------------------------------+
//| Evening Tri Star                                                 |
//| Tiga candle: Bullish, Doji, Doji, Bearish                        |
//+------------------------------------------------------------------+
bool IsEveningTriStar(const double &open[], const double &high[], const double &low[], const double &close[], int shift, int barsCount)
{
   // Candle 1: Bullish
   if((close[shift+2] - open[shift+2]) <= 0)
      return false;
   
   // Candle 2: Doji
   if(!IsDoji(open, high, low, close, shift+1)) return false;
   
   // Candle 3: Doji
   if(!IsDoji(open, high, low, close, shift)) return false;
   
   // Candle 4 untuk konfirmasi (shift-1) harus bearish
   if(shift-1 < 0 || shift-1 >= barsCount) return false;
   
   bool confirmBearish = (close[shift-1] < open[shift-1]) && 
                         (close[shift-1] < low[shift+2] * 1.05);
   
   // Gap pattern
   bool gap1 = (low[shift+1] > high[shift+2]);
   bool gap2 = (high[shift] < low[shift+1]);
   
   return (gap1 && gap2 && confirmBearish);
}

//+------------------------------------------------------------------+
//| Three Black Crows                                                |
//| Tiga candle bearish berturut-turut                               |
//| Setiap candle open di dalam body candle sebelumnya              |
//| Setiap candle close lebih rendah dari sebelumnya                |
//+------------------------------------------------------------------+
bool IsThreeBlackCrows(const double &open[], const double &high[], const double &low[], const double &close[], int shift)
{
   // Ketiga candle harus bearish
   for(int i = 0; i <= 2; i++)
   {
      if(close[shift+i] >= open[shift+i])
         return false;
   }
   
   // Setiap candle harus memiliki body yang signifikan
   if(!IsLongCandle(open, high, low, close, shift+2) || 
      !IsLongCandle(open, high, low, close, shift+1) || 
      !IsLongCandle(open, high, low, close, shift))
      return false;
   
   // Candle 2: Open harus di dalam body Candle 1
   bool open2Inside = (open[shift+1] < open[shift+2] && open[shift+1] > close[shift+2]);
   
   // Candle 3: Open harus di dalam body Candle 2
   bool open3Inside = (open[shift] < open[shift+1] && open[shift] > close[shift+1]);
   
   // Setiap candle close lebih rendah dari sebelumnya
   bool lowerCloses = (close[shift+1] < close[shift+2]) && (close[shift] < close[shift+1]);
   
   // Lower shadow tidak boleh terlalu panjang (opsional)
   double range3 = high[shift] - low[shift];
   double lowerShadow3 = close[shift] - low[shift];
   bool noLongLowerShadow = (range3 > 0) ? (lowerShadow3 <= range3 * 0.3) : true;
   
   return (open2Inside && open3Inside && lowerCloses && noLongLowerShadow);
}

//+------------------------------------------------------------------+
//| ================ FUNGSI UTAMA ================                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Deteksi semua pola 3 candle reversal                             |
//+------------------------------------------------------------------+
ENUM_CANDLE3_SIGNAL GetCandle3ReversalSignal(const double &open[], const double &high[], const double &low[], const double &close[], 
                                               int shift, int barsCount, bool requireTrendFilter = true)
{
   // Bullish patterns
   if(IsMorningStar(open, high, low, close, shift) ||
      IsMorningDojiStar(open, high, low, close, shift) ||
      IsBullishAbandonedBaby(open, high, low, close, shift) ||
      IsMorningTriStar(open, high, low, close, shift, barsCount) ||
      IsThreeWhiteSoldiers(open, high, low, close, shift))
   {
      if(requireTrendFilter && shift+5 < barsCount)
      {
         // Require downtrend untuk bullish reversal
         if(close[shift+3] < close[shift+4] && close[shift+4] < close[shift+5])
            return SIGNAL3_BULLISH;
         else
            return SIGNAL3_NONE;
      }
      return SIGNAL3_BULLISH;
   }
   
   // Bearish patterns
   if(IsEveningStar(open, high, low, close, shift) ||
      IsEveningDojiStar(open, high, low, close, shift) ||
      IsBearishAbandonedBaby(open, high, low, close, shift) ||
      IsEveningTriStar(open, high, low, close, shift, barsCount) ||
      IsThreeBlackCrows(open, high, low, close, shift))
   {
      if(requireTrendFilter && shift+5 < barsCount)
      {
         // Require uptrend untuk bearish reversal
         if(close[shift+3] > close[shift+4] && close[shift+4] > close[shift+5])
            return SIGNAL3_BEARISH;
         else
            return SIGNAL3_NONE;
      }
      return SIGNAL3_BEARISH;
   }
   
   return SIGNAL3_NONE;
}

//+------------------------------------------------------------------+
//| Deteksi spesifik pola berdasarkan nama                           |
//+------------------------------------------------------------------+
string GetDetectedPatternName3(const double &open[], const double &high[], const double &low[], const double &close[], 
                                int shift, int barsCount)
{
   if(IsMorningStar(open, high, low, close, shift)) return "Morning Star";
   if(IsMorningDojiStar(open, high, low, close, shift)) return "Morning Doji Star";
   if(IsBullishAbandonedBaby(open, high, low, close, shift)) return "Bullish Abandoned Baby";
   if(IsMorningTriStar(open, high, low, close, shift, barsCount)) return "Morning Tri Star";
   if(IsThreeWhiteSoldiers(open, high, low, close, shift)) return "Three White Soldiers";
   
   if(IsEveningStar(open, high, low, close, shift)) return "Evening Star";
   if(IsEveningDojiStar(open, high, low, close, shift)) return "Evening Doji Star";
   if(IsBearishAbandonedBaby(open, high, low, close, shift)) return "Bearish Abandoned Baby";
   if(IsEveningTriStar(open, high, low, close, shift, barsCount)) return "Evening Tri Star";
   if(IsThreeBlackCrows(open, high, low, close, shift)) return "Three Black Crows";
   
   return "None";
}