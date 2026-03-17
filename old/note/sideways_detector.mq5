//+------------------------------------------------------------------+
//|                         bb.mq5                                   |
//|        Sideways Market Start Detector (Dot Indicator)            |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property strict

#property indicator_label1  "SidewaysStart"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrOrange
#property indicator_width1  2

// ================= INPUT =================
input int    SW_SlopePeriod   = 20;
input int    SW_ATRPeriod     = 14;
input int    SW_ERPeriod      = 20;
input int    SW_VolMedian     = 100;

input double SW_SlopeThresh  = 0.15;
input double SW_VolThresh    = 0.80;
input double SW_ERThresh     = 0.30;

input double DotOffsetATR    = 0.5;   // jarak dot dari candle (ATR)

// ================= GLOBAL =================
double   DotBuffer[];
MqlRates rates[];

// ================= INIT ===================
int OnInit()
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 159); // ● dot
   ArraySetAsSeries(DotBuffer, true);
   ArraySetAsSeries(rates, true);

   return(INIT_SUCCEEDED);
}

// ================= LOAD DATA ==============
void LoadRates(int bars)
{
   CopyRates(_Symbol, _Period, 0, bars, rates);
}

// ==============================
// ===== HELPER FUNCTIONS =======
// ==============================

double CalcATR(int period, int shift)
{
   double trSum = 0.0;

   for(int i = shift; i < shift + period; i++)
   {
      double high = rates[i].high;
      double low  = rates[i].low;
      double prevClose = rates[i+1].close;

      double tr = MathMax(high - low,
                 MathMax(MathAbs(high - prevClose),
                         MathAbs(low - prevClose)));

      trSum += tr;
   }

   return trSum / period;
}

double CalcSlopeNorm(int period, int shift)
{
   double sumX=0, sumY=0, sumXY=0, sumX2=0;

   for(int i=0;i<period;i++)
   {
      double x = i + 1;
      double y = MathLog(rates[shift + i].close);

      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
   }

   double denom = period * sumX2 - sumX * sumX;
   if(denom == 0) return 0;

   double slope = (period * sumXY - sumX * sumY) / denom;
   double atr   = CalcATR(SW_ATRPeriod, shift);

   if(atr == 0) return 0;
   return MathAbs(slope) / atr;
}

double CalcVolRatio(int shift)
{
   double atrNow = CalcATR(SW_ATRPeriod, shift);
   double atrNormNow = atrNow / rates[shift].close;

   double atrArray[];
   ArrayResize(atrArray, SW_VolMedian);

   for(int i=0;i<SW_VolMedian;i++)
   {
      double atr = CalcATR(SW_ATRPeriod, shift + i);
      atrArray[i] = atr / rates[shift + i].close;
   }

   ArraySort(atrArray);
   double median = atrArray[SW_VolMedian/2];

   if(median == 0) return 1.0;
   return atrNormNow / median;
}

double CalcEfficiencyRatio(int period, int shift)
{
   double netMove = MathAbs(rates[shift].close - rates[shift + period].close);

   double totalMove = 0;
   for(int i=shift;i<shift+period;i++)
      totalMove += MathAbs(rates[i].close - rates[i+1].close);

   if(totalMove == 0) return 0;
   return netMove / totalMove;
}

bool IsSideways(int shift)
{
   if(CalcSlopeNorm(SW_SlopePeriod, shift) < SW_SlopeThresh &&
      CalcVolRatio(shift)                < SW_VolThresh   &&
      CalcEfficiencyRatio(SW_ERPeriod, shift) < SW_ERThresh)
      return true;

   return false;
}

// ================= CALCULATE ==============
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
   if(rates_total < 300) return 0;

   LoadRates(600);

   int start = (prev_calculated == 0) ? 300 : rates_total - 1;

   for(int i = start; i >= 1; i--)
   {
      DotBuffer[i] = EMPTY_VALUE;

      bool nowSideways  = IsSideways(i);
      bool prevSideways = IsSideways(i+1);

      // === DETECT SIDEWAYS START ===
      if(nowSideways && !prevSideways)
      {
         double atr = CalcATR(SW_ATRPeriod, i);
         DotBuffer[i] = rates[i].high + atr * DotOffsetATR;
      }
   }

   return rates_total;
}
