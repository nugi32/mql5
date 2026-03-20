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

//---- input (default for M1 XAU)
input int      EMA_Period = 34;
input double   Sideways_Buffer = 89;
input int atr = 14;
input double ATR_Multiplier = 1.5;
input int adxPeriod = 14;
input double ADX_Threshold = 25.0;
input int      Dot_Code = 159;

//---- buffers
double DotBuffer[];
double EMABuffer[];

//---- handle
int emaHandle;
int atrHandle;
int adxHandle;

int sidewaysHandle;
double sidewaysBuffer[];
double atrBuffer[];
double adxBuffer[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, EMABuffer, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, Dot_Code);

   emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, atr);
   adxHandle = iADX(_Symbol, _Period, adxPeriod);

   if(emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
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

   if(CopyBuffer(emaHandle, 0, 0, rates_total, EMABuffer) <= 0)
      return(0);
    if(CopyBuffer(atrHandle, 0, 0, rates_total, atrBuffer) <= 0)
      return(0);
   if(CopyBuffer(adxHandle, 0, 0, rates_total, adxBuffer) <= 0)
      return(0);

   int start = prev_calculated > 0 ? prev_calculated - 1 : EMA_Period;

   for(int i = start; i < rates_total; i++)
   {
      DotBuffer[i] = EMPTY_VALUE;

      if(i > 0)
      {
         double ema_diff = MathAbs(EMABuffer[i] - EMABuffer[i-1]);

         double buffer_price =Sideways_Buffer * _Point;

         double atr_down = atrBuffer[i] < atrBuffer[i-1];

         if(ema_diff <= buffer_price && atr_down)
         {
            DotBuffer[i] = close[i];
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+