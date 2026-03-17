//+------------------------------------------------------------------+
//|                ADX Debug Dot Indicator                          |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property strict
--
#property indicator_label1  "ADXDot"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrOrange
#property indicator_width1  2

// ===== INPUT =====
input int adxPeriod = 14;
input int adxThreshold = 20;   // turunkan dulu supaya pasti muncul

// ===== GLOBAL =====
double DotBuffer[];
double adxBuffer[];
int    adxHandle;

// ===== INIT =====
int OnInit()
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 159);
   ArraySetAsSeries(DotBuffer, true);
   ArraySetAsSeries(adxBuffer, true);

   adxHandle = iADX(_Symbol, _Period, adxPeriod);

   if(adxHandle == INVALID_HANDLE)
   {
      Print("ADX handle failed");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

// ===== DEINIT =====
void OnDeinit(const int reason)
{
   if(adxHandle != INVALID_HANDLE)
      IndicatorRelease(adxHandle);
}

// ===== CALCULATE =====
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
   if(rates_total < 50)
      return 0;

   ArrayResize(adxBuffer, rates_total);

   if(CopyBuffer(adxHandle, 0, 0, rates_total, adxBuffer) <= 0)
   {
      Print("CopyBuffer failed");
      return 0;
   }

   for(int i = rates_total - 2; i >= 1; i--)
   {
      DotBuffer[i] = EMPTY_VALUE;

      double adxValue = adxBuffer[i];

      if(adxValue > adxThreshold)
      {
         DotBuffer[i] = high[i] + 30 * _Point;

         // debug
         if(i == 10)
            Print("ADX at bar 10 = ", adxValue);
      }
   }

   return rates_total;
}
