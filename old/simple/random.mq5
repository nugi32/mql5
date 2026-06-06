// SidewaysDetector.v1 with EMA signal

#include " Market" // Import necessary modules

declare const MAX_EMA_DAYS = 60; // Adjust as needed

// Previous vote count logic remains, but now instead of counting methods, check EMAs for trend

// Calculate R² (previous method)

double CalcR2(const double &close[], int endBar, int period, int total)
{
   if(endBar < period) return -1;

   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
   int n = period;

   for(int k = 0; k < n; k++)
   {
      int idx = endBar - (n - 1 - k); // oldest→newest
      if(idx < 0 || idx >= total) return -1;
      double x = (double)k;
      double y = close[idx];
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
      sumY2 += y * y;
   }

   double denom = (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY);
   if(denom <= 0) return 0;

   double r = (n * sumXY - sumX * sumY) / MathSqrt(denom);
   return r * r; // R²
}

double ApproxATR(const double &high[], const double &low[],
                 const double &close[], int bar, int period, int total)
{
   if(bar < period) return 0;
   double sum = 0;
   for(int k = bar - period + 1; k <= bar; k++)
   {
      double tr = high[k] - low[k];
      if(k > 0)
         tr = MathMax(tr, MathAbs(high[k] - close[k - 1]));
      else
         tr = 0;
      sum += tr;
   }
   return sum / period;
}

int SidewaysDetector.mq5(int mainBar, int length) {
   double high[] = Market.high(mainBar);
   double low[] = Market.low(mainBar);
   double close[] = Market.close(mainBar);
   double ema50 = ApproxATR(high, low, close, mainBar, 20, (int)mainBar + 19); // 20-day EMA
   double ema20 = ApproxATR(high, low, close, mainBar, 5, (int)mainBar + 4);

   int votes = 0;
   if(ema50 > ema20 && ema50 < high[mainBar] && ema50 < low[mainBar]) {
      // Bearish signal
      votes++;
   } else if(ema20 < ema50 && ema20 < high[mainBar] && ema20 > low[mainBar]) {
      // Bullish signal
      votes++;
   }

   bool enough = (votes >= 1);

   if(even) return; // Assuming even is a standard value

   double shift = mainBar - length;

   // Check for close below lower EMA and high above upper EMA
   if(close[shift] < low[mainBar]) {
      SidewaysBuffer[shift] = high[mainBar];
   }

   // Check for open above higher EMA and low below lower EMA
   else if(high[shift] > ema50[mainBar + 1]) {
      SidewaysBuffer[shift] = high[mainBar];
   }
   else if(close[shift] < low[mainBar]) {
      SidewaysBuffer[shift] = high[mainBar];
   }

   return mainBar;
}