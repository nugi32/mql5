//+------------------------------------------------------------------+
//|                                                h-l indicator.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "High"
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_type1   DRAW_ARROW

#property indicator_label2  "Low"
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_type2   DRAW_ARROW

input int Depth = 10;

double highs[], lows[];

int      lastDirection = 0;   // 1 = high, -1 = low
datetime lastTime      = 0;

//+------------------------------------------------------------------+
//| Indicator initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   SetIndexBuffer(0, highs, INDICATOR_DATA);
   SetIndexBuffer(1, lows,  INDICATOR_DATA);

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  10);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Indicator calculation                                            |
//+------------------------------------------------------------------+
int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
)
{
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low,  true);
   ArraySetAsSeries(time, true);

   int limit = rates_total - prev_calculated;
   limit = MathMin(limit, rates_total - Depth * 2 - 1);

   for(int i = limit; i > 0; i--)
   {
      highs[i] = EMPTY_VALUE;
      lows[i]  = EMPTY_VALUE;

      // ---- Swing High ----
      if(i + Depth == ArrayMaximum(high, i, Depth * 2))
      {
         if(lastDirection == 1)
         {
            int index = iBarShift(_Symbol, PERIOD_CURRENT, lastTime);
            if(index >= 0 && high[index] >= high[i + Depth])
               continue;

            if(index >= 0)
               highs[index] = EMPTY_VALUE;
         }

         highs[i + Depth] = high[i + Depth];
         lastDirection = 1;
         lastTime      = time[i + Depth];
      }

      // ---- Swing Low ----
      if(i + Depth == ArrayMinimum(low, i, Depth * 2))
      {
         if(lastDirection == -1)
         {
            int index = iBarShift(_Symbol, PERIOD_CURRENT, lastTime);
            if(index >= 0 && low[index] <= low[i + Depth])
               continue;

            if(index >= 0)
               lows[index] = EMPTY_VALUE;
         }

         lows[i + Depth] = low[i + Depth];
         lastDirection = -1;
         lastTime      = time[i + Depth];
      }
   }

   return rates_total;
}
