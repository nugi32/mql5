//+------------------------------------------------------------------+
//|                 Range Sideways Detector (MT5)                    |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "Sideways Dot"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrYellow
#property indicator_width1  2

//--- input
input int      SidewaysPeriod    = 20;
input double   SidewaysThreshold = 300; // points
input int      Dot_Code          = 159;

//--- buffer
double DotBuffer[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, Dot_Code);

   ArraySetAsSeries(DotBuffer, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
bool IsSideways(const double &high[],
                const double &low[],
                int shift)
{
   double highest = high[shift];
   double lowest  = low[shift];

   for(int i = shift; i < shift + SidewaysPeriod; i++)
   {
      if(high[i] > highest)
         highest = high[i];

      if(low[i] < lowest)
         lowest = low[i];
   }

   double rangePoints = (highest - lowest) / _Point;

   return(rangePoints <= SidewaysThreshold);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < SidewaysPeriod)
      return(0);

   // penting
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int limit = rates_total - SidewaysPeriod;

   for(int i = 0; i < limit; i++)
   {
      DotBuffer[i] = EMPTY_VALUE;

      if(IsSideways(high, low, i))
      {
         // tampilkan dot sedikit di bawah candle
         DotBuffer[i] = low[i] - (10 * _Point);
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+