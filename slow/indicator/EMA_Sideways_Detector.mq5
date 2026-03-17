//+------------------------------------------------------------------+
//|                     EMA Sideways Detector (MT5)                  |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   1

#property indicator_label1  "Sideways Dot"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrYellow
#property indicator_width1  2

//---- input
input int      EMA_Period = 50;
input double   Sideways_Buffer = 10;   // dalam points
input int      Dot_Code = 159;

//---- buffers
double DotBuffer[];
double EMABuffer[];

//---- handle
int emaHandle;

int sidewaysHandle;
double sidewaysBuffer[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, EMABuffer, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, Dot_Code);

   emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(emaHandle == INVALID_HANDLE)
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
   if(rates_total <= EMA_Period)
      return(0);

   // Copy EMA data
   if(CopyBuffer(emaHandle, 0, 0, rates_total, EMABuffer) <= 0)
      return(0);

   int start = prev_calculated > 0 ? prev_calculated - 1 : EMA_Period;

   for(int i = start; i < rates_total; i++)
   {
      DotBuffer[i] = EMPTY_VALUE;

      if(i > 0)
      {
         double ema_diff = MathAbs(EMABuffer[i] - EMABuffer[i-1]);

         // convert buffer dari points ke harga
         double buffer_price = Sideways_Buffer * _Point;

         if(ema_diff <= buffer_price)
         {
            DotBuffer[i] = close[i];
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+