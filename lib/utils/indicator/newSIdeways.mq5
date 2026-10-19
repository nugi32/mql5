//+------------------------------------------------------------------+
//|                                           SidewaysDetector.mq5   |
//|               Multi-Method Sideways Market Detector               |
//|          Prints a dot on chart when sideways is detected          |
//+------------------------------------------------------------------+
#property copyright   "SidewaysDetector"
#property version     "2.00"
#property description "Multi-method sideways/ranging market detector."
#property description "Combines up to 6 detection methods with voting."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot: Sideways Dot (above bar)
#property indicator_label1  "Sideways"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot: Trend Dot (optional, below bar)
#property indicator_label2  "Trending"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//==================================================================//
//                    INPUT PARAMETERS                               //
//==================================================================//

//--- General
input group "=== GENERAL SETTINGS ==="
input int    MinVotesRequired   = 3;       // Min methods that must agree (1-6)
input bool   ShowTrendDot       = false;   // Show trending dot (opposite signal)
input int    DotSize            = 2;       // Dot size (1=small, 5=large)
input color  SidewaysColor      = clrDodgerBlue;   // Sideways dot color
input color  TrendingColor      = clrOrangeRed;    // Trending dot color
input int    DotOffsetBars      = 5;       // Vertical offset (in pips) from high/low

//--- Method 1: ADX
input group "=== METHOD 1: ADX (Trend Strength) ==="
input bool   Use_ADX            = true;    // Enable ADX method
input int    ADX_Period         = 14;      // ADX period
input double ADX_Threshold      = 25.0;    // Sideways if ADX < threshold

//--- Method 2: ATR Ratio
input group "=== METHOD 2: ATR Ratio (Volatility) ==="
input bool   Use_ATR            = true;    // Enable ATR method
input int    ATR_FastPeriod     = 5;       // ATR fast period
input int    ATR_SlowPeriod     = 50;      // ATR slow period
input double ATR_Ratio          = 0.75;    // Sideways if fast/slow ATR < ratio

//--- Method 3: Bollinger Band Width
input group "=== METHOD 3: Bollinger Band Width ==="
input bool   Use_BBWidth        = true;    // Enable BB Width method
input int    BB_Period          = 20;      // Bollinger Bands period
input double BB_Deviation       = 2.0;     // Bollinger Bands deviation
input int    BB_WidthLookback   = 50;      // Lookback to find average width
input double BB_WidthPercent    = 0.50;    // Sideways if width < X% of average

//--- Method 4: MA Slope
input group "=== METHOD 4: Moving Average Slope ==="
input bool   Use_MASlope        = true;    // Enable MA Slope method
input int    MA_Period          = 50;      // MA period
input ENUM_MA_METHOD MA_Method  = MODE_EMA; // MA smoothing method
input int    MA_SlopeLookback   = 5;       // Bars back to measure slope
input double MA_SlopeThreshold  = 0.0002;  // Max slope (normalized) for sideways

//--- Method 5: Linear Regression Channel
input group "=== METHOD 5: Linear Regression R² ==="
input bool   Use_LinReg        = true;     // Enable LinReg method
input int    LinReg_Period     = 20;       // LinReg lookback bars
input double LinReg_R2_Max     = 0.35;    // Sideways if R² < threshold (low fit = sideways)

//--- Method 6: Price Range / Channel
input group "=== METHOD 6: Price Channel Range ==="
input bool   Use_Channel        = true;    // Enable Price Channel method
input int    Channel_Period     = 20;      // Bars to define the channel
input double Channel_ATR_Multi  = 1.5;    // Sideways if range < X * ATR(14)

//==================================================================//
//                    BUFFERS & GLOBALS                              //
//==================================================================//

double SidewaysBuffer[];
double TrendBuffer[];

// Handles
int h_ADX, h_ATR_Fast, h_ATR_Slow, h_BB;
int h_MA;

//+------------------------------------------------------------------+
int OnInit()
  {
   // Buffers
   SetIndexBuffer(0, SidewaysBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, TrendBuffer,    INDICATOR_DATA);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Arrow codes: 159 = filled circle (Wingdings), 108 = dot
   PlotIndexSetInteger(0, PLOT_ARROW, 159);
   PlotIndexSetInteger(1, PLOT_ARROW, 159);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, DotSize);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, DotSize);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, SidewaysColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, TrendingColor);

   // Create indicator handles
   if(Use_ADX)
      h_ADX = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);

   if(Use_ATR)
     {
      h_ATR_Fast = iATR(_Symbol, PERIOD_CURRENT, ATR_FastPeriod);
      h_ATR_Slow = iATR(_Symbol, PERIOD_CURRENT, ATR_SlowPeriod);
     }

   if(Use_BBWidth)
      h_BB = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);

   if(Use_MASlope)
      h_MA = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MA_Method, PRICE_CLOSE);

   // Validate vote threshold
   int maxMethods = (int)Use_ADX + (int)Use_ATR + (int)Use_BBWidth +
                    (int)Use_MASlope + (int)Use_LinReg + (int)Use_Channel;
   if(MinVotesRequired > maxMethods)
     {
      Alert("SidewaysDetector: MinVotesRequired (", MinVotesRequired,
            ") > enabled methods (", maxMethods, "). Adjust inputs.");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Sideways[%d/%d votes]",
                                   MinVotesRequired, maxMethods));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(Use_ADX)     { IndicatorRelease(h_ADX);      }
   if(Use_ATR)     { IndicatorRelease(h_ATR_Fast);
                     IndicatorRelease(h_ATR_Slow);  }
   if(Use_BBWidth) { IndicatorRelease(h_BB);        }
   if(Use_MASlope) { IndicatorRelease(h_MA);        }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
   // Minimum bars needed
   int minBars = MathMax(MathMax(ADX_Period, ATR_SlowPeriod),
                 MathMax(MathMax(BB_Period + BB_WidthLookback, MA_Period + MA_SlopeLookback),
                         MathMax(LinReg_Period, Channel_Period))) + 5;

   if(rates_total < minBars) return 0;

   int startBar = (prev_calculated <= 0) ? minBars : prev_calculated - 1;

   //--- Pull indicator data into local arrays
   double adxVal[];
   double atrFast[], atrSlow[];
   double bbUpper[], bbLower[], bbMiddle[];
   double maVal[];

   int needed = rates_total - startBar + 1;

   if(Use_ADX)
     {
      ArraySetAsSeries(adxVal, true);
      if(CopyBuffer(h_ADX, 0, 0, needed + 5, adxVal) <= 0) return prev_calculated;
     }
   if(Use_ATR)
     {
      ArraySetAsSeries(atrFast, true);
      ArraySetAsSeries(atrSlow, true);
      if(CopyBuffer(h_ATR_Fast, 0, 0, needed + 5, atrFast) <= 0) return prev_calculated;
      if(CopyBuffer(h_ATR_Slow, 0, 0, needed + 5, atrSlow) <= 0) return prev_calculated;
     }
   if(Use_BBWidth)
     {
      ArraySetAsSeries(bbUpper,  true);
      ArraySetAsSeries(bbLower,  true);
      ArraySetAsSeries(bbMiddle, true);
      if(CopyBuffer(h_BB, 1, 0, needed + BB_WidthLookback + 5, bbUpper)  <= 0) return prev_calculated;
      if(CopyBuffer(h_BB, 2, 0, needed + BB_WidthLookback + 5, bbLower)  <= 0) return prev_calculated;
      if(CopyBuffer(h_BB, 0, 0, needed + BB_WidthLookback + 5, bbMiddle) <= 0) return prev_calculated;
     }
   if(Use_MASlope)
     {
      ArraySetAsSeries(maVal, true);
      if(CopyBuffer(h_MA, 0, 0, needed + MA_SlopeLookback + 5, maVal) <= 0) return prev_calculated;
     }

   //--- Main loop
   for(int i = startBar; i < rates_total; i++)
     {
      SidewaysBuffer[i] = EMPTY_VALUE;
      TrendBuffer[i]    = EMPTY_VALUE;

      int shift = rates_total - 1 - i; // convert to series-style index

      int votes   = 0;
      int enabled = 0;

      //--------------------------------------------------------------
      // METHOD 1: ADX — low ADX = no trend = sideways
      //--------------------------------------------------------------
      if(Use_ADX && shift < (int)ArraySize(adxVal))
        {
         enabled++;
         if(adxVal[shift] < ADX_Threshold && adxVal[shift] > 0)
            votes++;
        }

      //--------------------------------------------------------------
      // METHOD 2: ATR Ratio — low recent volatility vs historical
      //--------------------------------------------------------------
      if(Use_ATR &&
         shift < (int)ArraySize(atrFast) &&
         shift < (int)ArraySize(atrSlow))
        {
         enabled++;
         if(atrSlow[shift] > 0 && (atrFast[shift] / atrSlow[shift]) < ATR_Ratio)
            votes++;
        }

      //--------------------------------------------------------------
      // METHOD 3: Bollinger Band Width vs its own average
      //--------------------------------------------------------------
      if(Use_BBWidth &&
         shift < (int)ArraySize(bbUpper) &&
         shift + BB_WidthLookback < (int)ArraySize(bbUpper))
        {
         enabled++;
         double curWidth = bbUpper[shift] - bbLower[shift];

         // Average BB width over lookback
         double sumWidth = 0;
         int    count    = 0;
         for(int k = shift; k < shift + BB_WidthLookback; k++)
           {
            if(k < (int)ArraySize(bbUpper) && bbMiddle[k] > 0)
              {
               sumWidth += (bbUpper[k] - bbLower[k]);
               count++;
              }
           }
         if(count > 0)
           {
            double avgWidth = sumWidth / count;
            if(avgWidth > 0 && (curWidth / avgWidth) < BB_WidthPercent)
               votes++;
           }
        }

      //--------------------------------------------------------------
      // METHOD 4: Moving Average Slope (normalized by price)
      //--------------------------------------------------------------
      if(Use_MASlope &&
         shift < (int)ArraySize(maVal) &&
         shift + MA_SlopeLookback < (int)ArraySize(maVal))
        {
         enabled++;
         double slope = MathAbs(maVal[shift] - maVal[shift + MA_SlopeLookback]);
         double normalizedSlope = (close[i] > 0) ? slope / close[i] : 1.0;
         if(normalizedSlope < MA_SlopeThreshold)
            votes++;
        }

      //--------------------------------------------------------------
      // METHOD 5: Linear Regression R² (goodness of fit)
      // Low R² = price is not fitting a line = ranging
      //--------------------------------------------------------------
      if(Use_LinReg && shift + LinReg_Period < rates_total)
        {
         enabled++;
         double r2 = CalcR2(close, i, LinReg_Period, rates_total);
         if(r2 >= 0 && r2 < LinReg_R2_Max)
            votes++;
        }

      //--------------------------------------------------------------
      // METHOD 6: Price Channel Range vs ATR
      // Tight channel relative to ATR = sideways
      //--------------------------------------------------------------
      if(Use_Channel && shift + Channel_Period < rates_total)
        {
         enabled++;
         int startIdx = i - Channel_Period + 1;
         if(startIdx >= 0)
           {
            double hiMax = high[startIdx];
            double loMin = low[startIdx];
            for(int k = startIdx + 1; k <= i; k++)
              {
               if(high[k] > hiMax) hiMax = high[k];
               if(low[k]  < loMin) loMin = low[k];
              }
            double channelRange = hiMax - loMin;

            // Use ATR from atrFast if available, else approximate
            double atr14 = 0;
            if(Use_ATR && shift < (int)ArraySize(atrSlow))
               atr14 = atrSlow[shift];
            else
               atr14 = ApproxATR(high, low, close, i, 14, rates_total);

            if(atr14 > 0 && channelRange < Channel_ATR_Multi * atr14)
               votes++;
           }
        }

      //--------------------------------------------------------------
      // DECISION: enough votes cast for sideways?
      //--------------------------------------------------------------
      if(enabled > 0 && votes >= MinVotesRequired)
        {
         // Draw dot ABOVE the high
         SidewaysBuffer[i] = high[i] + DotOffsetBars * _Point * 10;
        }
      else if(ShowTrendDot && enabled > 0)
        {
         // Draw dot BELOW the low
         TrendBuffer[i] = low[i] - DotOffsetBars * _Point * 10;
        }
     }

   return rates_total;
  }

//+------------------------------------------------------------------+
//| Calculate R² (coefficient of determination) for linear fit       |
//| over 'period' bars ending at bar index 'endBar'                  |
//+------------------------------------------------------------------+
double CalcR2(const double &close[], int endBar, int period, int total)
  {
   if(endBar - period + 1 < 0) return -1;

   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
   int n = period;

   for(int k = 0; k < n; k++)
     {
      int idx = endBar - (n - 1 - k); // oldest→newest
      if(idx < 0 || idx >= total) return -1;
      double x = (double)k;
      double y = close[idx];
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
      sumY2 += y * y;
     }

   double denom = (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY);
   if(denom <= 0) return 0;

   double r = (n * sumXY - sumX * sumY) / MathSqrt(denom);
   return r * r; // R²
  }

//+------------------------------------------------------------------+
//| Approximate ATR when external handle not yet ready               |
//+------------------------------------------------------------------+
double ApproxATR(const double &high[], const double &low[],
                 const double &close[], int bar, int period, int total)
  {
   if(bar < period) return 0;
   double sum = 0;
   for(int k = bar - period + 1; k <= bar; k++)
     {
      double tr = high[k] - low[k];
      if(k > 0)
        {
         tr = MathMax(tr, MathAbs(high[k] - close[k - 1]));
         tr = MathMax(tr, MathAbs(low[k]  - close[k - 1]));
        }
      sum += tr;
     }
   return sum / period;
  }
//+------------------------------------------------------------------+