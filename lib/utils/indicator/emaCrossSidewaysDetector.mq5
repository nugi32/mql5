//+------------------------------------------------------------------+
//|        EMA Cross Sideways Detector (Arrow Version) MT5          |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "Sideways Dot"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrYellow
#property indicator_width1  2

//---- input
input int FastEMA = 10;
input int SlowEMA = 20;
input int LookbackCandles = 50;   // jumlah candle cek cross
input int CrossThreshold = 5;     // minimal cross = sideways
input int Dot_Code = 159;         // kode arrow

//---- buffer
double DotBuffer[];

//---- EMA handle
int fastHandle, slowHandle;

//---- EMA data
double fastEMA[], slowEMA[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, Dot_Code);

   fastHandle = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
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
   if(rates_total < LookbackCandles)
      return(0);

   if(CopyBuffer(fastHandle, 0, 0, rates_total, fastEMA) <= 0)
      return(0);

   if(CopyBuffer(slowHandle, 0, 0, rates_total, slowEMA) <= 0)
      return(0);

   int start = prev_calculated > 0 ? prev_calculated - 1 : LookbackCandles;

   for(int i = start; i < rates_total; i++)
   {
      DotBuffer[i] = EMPTY_VALUE;

      int crossCount = 0;

      for(int j = i - LookbackCandles + 1; j <= i; j++)
      {
         if(j <= 0) continue;

         bool prevAbove = fastEMA[j-1] > slowEMA[j-1];
         bool currAbove = fastEMA[j] > slowEMA[j];

         if(prevAbove != currAbove)
            crossCount++;
      }

      // kalau sideways → tampilkan dot
      if(crossCount >= CrossThreshold)
      {
         DotBuffer[i] = low[i] - (5 * _Point); // dot di bawah candle
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+