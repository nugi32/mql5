//+------------------------------------------------------------------+
//|            Candle Volatility Library (MQL5)                      |
//+------------------------------------------------------------------+
#ifndef __CANDLE_VOLATILITY_MQH__
#define __CANDLE_VOLATILITY_MQH__

// Hitung range candle
double GetCandleRange(string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   double high = iHigh(symbol, tf, shift);
   double low  = iLow(symbol, tf, shift);
   return (high - low);
}

//--------------------------------------------------------------
// DETEKSI FALLING (range makin kecil)
//--------------------------------------------------------------
bool IsFallingVolatility(string symbol, ENUM_TIMEFRAMES tf, int bars = 3)
{
   for(int i = 0; i < bars - 1; i++)
   {
      double current = GetCandleRange(symbol, tf, i);
      double next    = GetCandleRange(symbol, tf, i + 1);

      if(current >= next)
         return false;
   }
   return true;
}

//--------------------------------------------------------------
// DETEKSI RISING (range makin besar)
//--------------------------------------------------------------
bool IsRisingVolatility(string symbol, ENUM_TIMEFRAMES tf, int bars = 3)
{
   for(int i = 0; i < bars - 1; i++)
   {
      double current = GetCandleRange(symbol, tf, i);
      double next    = GetCandleRange(symbol, tf, i + 1);

      if(current <= next)
         return false;
   }
   return true;
}

//--------------------------------------------------------------
// VERSI SMOOTH (pakai rata-rata)
//--------------------------------------------------------------
double GetAverageRange(string symbol, ENUM_TIMEFRAMES tf, int bars, int shift = 0)
{
   double total = 0;

   for(int i = shift; i < shift + bars; i++)
      total += GetCandleRange(symbol, tf, i);

   return total / bars;
}

// contraction (avg sekarang < avg sebelumnya)
bool IsContracting(string symbol, ENUM_TIMEFRAMES tf, int bars = 5)
{
   double recent = GetAverageRange(symbol, tf, bars, 0);
   double prev   = GetAverageRange(symbol, tf, bars, bars);

   return (recent < prev);
}

// expansion (avg sekarang > avg sebelumnya)
bool IsExpanding(string symbol, ENUM_TIMEFRAMES tf, int bars = 5)
{
   double recent = GetAverageRange(symbol, tf, bars, 0);
   double prev   = GetAverageRange(symbol, tf, bars, bars);

   return (recent > prev);
}

#endif