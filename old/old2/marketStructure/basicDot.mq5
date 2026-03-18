//+------------------------------------------------------------------+
//|                                                h-l indicator.mq5 |
//|                Swing Hit Zone + Confirm Candle Filter            |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "High"
#property indicator_color1  clrGreen
#property indicator_type1   DRAW_ARROW

#property indicator_label2  "Low"
#property indicator_color2  clrRed
#property indicator_type2   DRAW_ARROW

#property indicator_label3  "High Broken"
#property indicator_color3  clrGray
#property indicator_type3   DRAW_ARROW

#property indicator_label4  "Low Broken"
#property indicator_color4  clrYellow
#property indicator_type4   DRAW_ARROW

input int Depth = 10;
input int ConfirmBars = 3;

double highs[];
double lows[];
double highsBroken[];
double lowsBroken[];

int      lastDirection = 0;
datetime lastTime      = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   SetIndexBuffer(0,highs,INDICATOR_DATA);
   SetIndexBuffer(1,lows,INDICATOR_DATA);
   SetIndexBuffer(2,highsBroken,INDICATOR_DATA);
   SetIndexBuffer(3,lowsBroken,INDICATOR_DATA);

   ArraySetAsSeries(highs,true);
   ArraySetAsSeries(lows,true);
   ArraySetAsSeries(highsBroken,true);
   ArraySetAsSeries(lowsBroken,true);

   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,-10);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,10);
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,-10);
   PlotIndexSetInteger(3,PLOT_ARROW_SHIFT,10);

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
   if(rates_total < Depth*2+5)
      return 0;

   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(time,true);

   int start;

   if(prev_calculated==0)
      start = rates_total - Depth*2 - 2;
   else
      start = rates_total - prev_calculated;

   if(start < 1)
      start = 1;

   for(int i=start;i>0;i--)
   {
      highs[i]=EMPTY_VALUE;
      lows[i]=EMPTY_VALUE;
      highsBroken[i]=EMPTY_VALUE;
      lowsBroken[i]=EMPTY_VALUE;

      //=====================
      // SWING HIGH
      //=====================

      int maxIndex = ArrayMaximum(high,i,Depth*2);

      if(maxIndex == i+Depth)
      {
         int swingIndex = i+Depth;

         double swingHigh = high[swingIndex];
         double swingLow  = low[swingIndex];

         double range = swingHigh - swingLow;
         double zone  = range/4.0;

         double hitLevel = swingHigh - zone;

         bool broken=false;

         int startCheck = swingIndex - ConfirmBars;

         if(startCheck < 0)
            startCheck = 0;

         for(int j=startCheck;j>=0;j--)
         {
            if(high[j] >= hitLevel)
            {
               broken=true;
               break;
            }
         }

         if(broken)
            highsBroken[swingIndex]=swingHigh;
         else
            highs[swingIndex]=swingHigh;

         lastDirection=1;
         lastTime=time[swingIndex];
      }

      //=====================
      // SWING LOW
      //=====================

      int minIndex = ArrayMinimum(low,i,Depth*2);

      if(minIndex == i+Depth)
      {
         int swingIndex = i+Depth;

         double swingHigh = high[swingIndex];
         double swingLow  = low[swingIndex];

         double range = swingHigh - swingLow;
         double zone  = range/4.0;

         double hitLevel = swingLow + zone;

         bool broken=false;

         int startCheck = swingIndex - ConfirmBars;

         if(startCheck < 0)
            startCheck = 0;

         for(int j=startCheck;j>=0;j--)
         {
            if(low[j] <= hitLevel)
            {
               broken=true;
               break;
            }
         }

         if(broken)
            lowsBroken[swingIndex]=swingLow;
         else
            lows[swingIndex]=swingLow;

         lastDirection=-1;
         lastTime=time[swingIndex];
      }
   }

   return rates_total;
}