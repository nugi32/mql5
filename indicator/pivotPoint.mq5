//+------------------------------------------------------------------+
//|                                                PivotPoint_Daily  |
//|                         Classic Daily Pivot (Previous Day HLC)   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0

input ENUM_TIMEFRAMES PivotTF = PERIOD_D1;
input color   ColorPP = clrGold;
input color   ColorR  = clrRed;
input color   ColorS  = clrDeepSkyBlue;
input int     LineWidth = 1;
input bool    ShowLabels = true;

double pp, r1, r2, s1, s2;
datetime last_calculated_day = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Daily Pivot (Classic)");
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteLines();
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
   datetime current_day = iTime(_Symbol, PERIOD_D1, 0);
   if(current_day == last_calculated_day)
      return(rates_total);

   last_calculated_day = current_day;

   CalculatePivot();
   DrawLines();

   return(rates_total);
}
//+------------------------------------------------------------------+
void CalculatePivot()
{
   double prevHigh  = iHigh(_Symbol, PivotTF, 1);
   double prevLow   = iLow(_Symbol, PivotTF, 1);
   double prevClose = iClose(_Symbol, PivotTF, 1);

   pp = (prevHigh + prevLow + prevClose) / 3.0;
   r1 = (2.0 * pp) - prevLow;
   s1 = (2.0 * pp) - prevHigh;
   r2 = pp + (prevHigh - prevLow);
   s2 = pp - (prevHigh - prevLow);
}
//+------------------------------------------------------------------+
void DrawLine(string name, double price, color clr)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);

   if(ShowLabels)
      ObjectSetString(0, name, OBJPROP_TEXT, name);
}
//+------------------------------------------------------------------+
void DrawLines()
{
   DrawLine("PP", pp, ColorPP);
   DrawLine("R1", r1, ColorR);
   DrawLine("R2", r2, ColorR);
   DrawLine("S1", s1, ColorS);
   DrawLine("S2", s2, ColorS);
}
//+------------------------------------------------------------------+
void DeleteLines()
{
   ObjectDelete(0, "PP");
   ObjectDelete(0, "R1");
   ObjectDelete(0, "R2");
   ObjectDelete(0, "S1");
   ObjectDelete(0, "S2");
}
//+------------------------------------------------------------------+