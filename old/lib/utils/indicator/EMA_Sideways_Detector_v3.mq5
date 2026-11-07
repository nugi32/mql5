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
input int      first_EMA_Period = 34;
input int      second_EMA_Period = 55;
input double   Sideways_Buffer = 89;
input int atr = 14;
input double ATR_Multiplier = 1.5;
input int adxPeriod = 14;
input double ADX_Threshold = 25.0;
input int      Dot_Code = 159;

//---- buffers
double DotBuffer[];
double firstEMABuffer[];
double secondEMABuffer[];

//---- handle
int firstEmaHandle;
int secondEmaHandle;
int atrHandle;
int adxHandle;

double sidewaysBuffer[];
double atrBuffer[];
double adxBuffer[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, firstEMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(2, secondEMABuffer, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, Dot_Code);

   firstEmaHandle = iMA(_Symbol, _Period, first_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   secondEmaHandle = iMA(_Symbol, _Period, second_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, atr);
   adxHandle = iADX(_Symbol, _Period, adxPeriod);

   if(firstEmaHandle == INVALID_HANDLE || secondEmaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
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
   // Validasi jumlah data minimum
   if(rates_total <= first_EMA_Period)
      return 0;

   // Ambil data indikator
   if(CopyBuffer(firstEmaHandle, 0, 0, rates_total, firstEMABuffer) <= 0)
      return 0;

   if(CopyBuffer(secondEmaHandle, 0, 0, rates_total, secondEMABuffer) <= 0)
      return 0;

   if(CopyBuffer(atrHandle, 0, 0, rates_total, atrBuffer) <= 0)
      return 0;

   if(CopyBuffer(adxHandle, 0, 0, rates_total, adxBuffer) <= 0)
      return 0;

   // Tentukan titik mulai perhitungan
   int start = (prev_calculated > 0) ? prev_calculated - 1 : first_EMA_Period;

   // Loop utama
   for(int i = start; i < rates_total; i++)
   {
      DotBuffer[i] = EMPTY_VALUE;

      if(i <= 0)
         continue;

      // Hitung selisih EMA
      double ema_diff = MathAbs(firstEMABuffer[i] - secondEMABuffer[i]);

      // Threshold sideways
      double buffer_price = Sideways_Buffer * _Point;

      // Kondisi ATR menurun
      bool atr_down = (atrBuffer[i] < atrBuffer[i - 1]);

      // Sinyal sideways
      if(ema_diff <= buffer_price && atr_down)
      {
         DotBuffer[i] = close[i];
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+