//+------------------------------------------------------------------+
//|                                                ATR_HL_SET_TF.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Swing High"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGreen

#property indicator_label2  "Swing Low"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed

//--- input
input int Depth       = 10;            // Depth in M1 bars (minutes)
input int atrPeriod   = 14;
input double atrMult  = 0.5;
input ENUM_TIMEFRAMES TF = PERIOD_M1;  // ATR timeframe

//--- buffers
double HighBuf[], LowBuf[], ATRBuf[];

//--- state
int      lastDir = 0;     // 1 = high, -1 = low
datetime lastTime = 0;
int      atrHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, HighBuf, INDICATOR_DATA);
   SetIndexBuffer(1, LowBuf,  INDICATOR_DATA);

   ArraySetAsSeries(HighBuf, true);
   ArraySetAsSeries(LowBuf,  true);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  10);

   atrHandle = iATR(_Symbol, TF, atrPeriod);
   if(atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

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
   // --- Convert M1 depth to chart timeframe bars
   int m1_seconds     = PeriodSeconds(PERIOD_M1);   // 60
   int chart_seconds  = PeriodSeconds(_Period);

   if(chart_seconds <= 0)
      return 0;

   int DepthTF = MathMax(1, Depth * m1_seconds / chart_seconds);

   if(rates_total < DepthTF * 2 + atrPeriod)
      return 0;

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low,  true);
   ArraySetAsSeries(time, true);

   ArrayResize(ATRBuf, rates_total);
   ArraySetAsSeries(ATRBuf, true);

   if(CopyBuffer(atrHandle, 0, 0, rates_total, ATRBuf) <= 0)
      return prev_calculated;

   int limit = rates_total - DepthTF * 2 - 1;

   for(int i = limit; i > 0; i--)
   {
      HighBuf[i] = EMPTY_VALUE;
      LowBuf[i]  = EMPTY_VALUE;

      double atr = ATRBuf[i + DepthTF] * atrMult;

      // ---- Swing High ----
      if(i + DepthTF == ArrayMaximum(high, i, DepthTF * 2))
      {
         if(high[i + DepthTF] - low[i + DepthTF] >= atr)
         {
            HighBuf[i + DepthTF] = high[i + DepthTF];
            lastDir  = 1;
            lastTime = time[i + DepthTF];
         }
      }

      // ---- Swing Low ----
      if(i + DepthTF == ArrayMinimum(low, i, DepthTF * 2))
      {
         if(high[i + DepthTF] - low[i + DepthTF] >= atr)
         {
            LowBuf[i + DepthTF] = low[i + DepthTF];
            lastDir  = -1;
            lastTime = time[i + DepthTF];
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
