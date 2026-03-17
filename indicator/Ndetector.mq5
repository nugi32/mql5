#property indicator_chart_window
#property indicator_plots 0
#property strict

input int SwingBars = 5;
input int Lookback  = 300;

//---------------------------------------

bool IsSwingHigh(int i,int swing,const double &high[])
{
   for(int j=1;j<=swing;j++)
   {
      if(high[i] <= high[i+j] || high[i] <= high[i-j])
         return false;
   }
   return true;
}

//---------------------------------------

bool IsSwingLow(int i,int swing,const double &low[])
{
   for(int j=1;j<=swing;j++)
   {
      if(low[i] >= low[i+j] || low[i] >= low[i-j])
         return false;
   }
   return true;
}

//---------------------------------------

void DrawLine(string name,double price,datetime t)
{
   if(ObjectFind(0,name)>=0)
      return;

   datetime t2 = t - PeriodSeconds()*300;

   ObjectCreate(0,name,OBJ_TREND,0,t,price,t2,price);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,true);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
}

//---------------------------------------

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
const int &spread[])
{

   int lastLow  = -1;
   int lastHigh = -1;

   int start = rates_total - Lookback;
   if(start < SwingBars+5)
      start = SwingBars+5;

   for(int i=start;i<rates_total-SwingBars;i++)
   {
      if(IsSwingLow(i,SwingBars,low))
      {
         if(lastLow!=-1 && lastHigh!=-1)
         {
            if(low[i] > low[lastLow])
            {
               string name="BullN_"+IntegerToString(i);
               DrawLine(name,high[lastHigh],time[lastHigh]);
            }
         }

         lastLow=i;
      }

      if(IsSwingHigh(i,SwingBars,high))
      {
         if(lastLow!=-1 && lastHigh!=-1)
         {
            if(high[i] < high[lastHigh])
            {
               string name="BearN_"+IntegerToString(i);
               DrawLine(name,low[lastLow],time[lastLow]);
            }
         }

         lastHigh=i;
      }
   }

   return rates_total;
}