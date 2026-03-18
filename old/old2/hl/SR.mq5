//+------------------------------------------------------------------+
//|     Adaptive Swing High Low Horizontal S/R (MTF) - Multi Lines   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//================ INPUT =================
input int Depth = 10;
input ENUM_TIMEFRAMES SourceTF = PERIOD_CURRENT;
input bool ShowHistorical = true;           // Tampilkan garis historis
input color ResistanceColor = clrLime;      // Warna resistance
input color SupportColor = clrRed;          // Warna support
input int LineWidth = 2;                    // Ketebalan garis
input ENUM_LINE_STYLE LineStyle = STYLE_SOLID; // Gaya garis

//================ STRUCTS ===============
struct SwingPoint
{
   datetime time;
   double   price;
   bool     isHigh;
   string   objName;
};

//================ VARIABLES =============
SwingPoint swings[];
int lastProcessedBar = -1;
long chartID = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   chartID = ChartID();
   ArrayResize(swings, 0);
   lastProcessedBar = -1;
   
   // Hapus semua objek lama dengan prefix kita
   ObjectsDeleteAll(chartID, "ASHL_");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Hapus semua objek kita saat indicator dihapus
   ObjectsDeleteAll(chartID, "ASHL_");
}

//+------------------------------------------------------------------+
void DetectSwings()
{
   int srcBars = iBars(_Symbol, SourceTF);
   if(srcBars < Depth * 3) return;
   
   // Array untuk swing points baru
   SwingPoint newSwings[];
   ArrayResize(newSwings, 0);
   
   int startBar = Depth;
   int endBar = srcBars - Depth - 1;
   
   // Jika tidak show historical, hanya cek bar terbaru
   if(!ShowHistorical)
   {
      startBar = srcBars - Depth * 3;
      if(startBar < Depth) startBar = Depth;
   }
   
   for(int i = startBar; i <= endBar; i++)
   {
      // Swing High detection
      bool isSwingHigh = true;
      double currentHigh = iHigh(_Symbol, SourceTF, i);
      
      // Check left side
      for(int j = 1; j <= Depth; j++)
      {
         if(iHigh(_Symbol, SourceTF, i - j) >= currentHigh)
         {
            isSwingHigh = false;
            break;
         }
      }
      
      // Check right side
      if(isSwingHigh)
      {
         for(int j = 1; j <= Depth; j++)
         {
            if(iHigh(_Symbol, SourceTF, i + j) >= currentHigh)
            {
               isSwingHigh = false;
               break;
            }
         }
      }
      
      if(isSwingHigh)
      {
         int size = ArraySize(newSwings);
         ArrayResize(newSwings, size + 1);
         newSwings[size].time = iTime(_Symbol, SourceTF, i);
         newSwings[size].price = currentHigh;
         newSwings[size].isHigh = true;
         newSwings[size].objName = "ASHL_R_" + IntegerToString(iTime(_Symbol, SourceTF, i));
      }
      
      // Swing Low detection
      bool isSwingLow = true;
      double currentLow = iLow(_Symbol, SourceTF, i);
      
      // Check left side
      for(int j = 1; j <= Depth; j++)
      {
         if(iLow(_Symbol, SourceTF, i - j) <= currentLow)
         {
            isSwingLow = false;
            break;
         }
      }
      
      // Check right side
      if(isSwingLow)
      {
         for(int j = 1; j <= Depth; j++)
         {
            if(iLow(_Symbol, SourceTF, i + j) <= currentLow)
            {
               isSwingLow = false;
               break;
            }
         }
      }
      
      if(isSwingLow)
      {
         int size = ArraySize(newSwings);
         ArrayResize(newSwings, size + 1);
         newSwings[size].time = iTime(_Symbol, SourceTF, i);
         newSwings[size].price = currentLow;
         newSwings[size].isHigh = false;
         newSwings[size].objName = "ASHL_S_" + IntegerToString(iTime(_Symbol, SourceTF, i));
      }
   }
   
   // Update swings array
   ArrayResize(swings, ArraySize(newSwings));
   for(int i = 0; i < ArraySize(newSwings); i++)
   {
      swings[i] = newSwings[i];
   }
}

//+------------------------------------------------------------------+
void DrawHorizontalLines()
{
   // Hapus semua objek garis kita yang ada
   ObjectsDeleteAll(chartID, "ASHL_");
   
   // Gambar semua garis resistance dan support
   for(int i = 0; i < ArraySize(swings); i++)
   {
      string objName = swings[i].objName;
      double price = swings[i].price;
      color lineColor = swings[i].isHigh ? ResistanceColor : SupportColor;
      
      // Buat objek horizontal line
      ObjectCreate(chartID, objName, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(chartID, objName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(chartID, objName, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(chartID, objName, OBJPROP_STYLE, LineStyle);
      ObjectSetInteger(chartID, objName, OBJPROP_BACK, true); // Tampilkan di background
      
      // Tambahkan label untuk swing point
      string labelName = objName + "_LABEL";
      ObjectCreate(chartID, labelName, OBJ_TEXT, 0, swings[i].time, price);
      ObjectSetString(chartID, labelName, OBJPROP_TEXT, DoubleToString(price, _Digits));
      ObjectSetInteger(chartID, labelName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(chartID, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(chartID, labelName, OBJPROP_BACK, true);
      ObjectSetInteger(chartID, labelName, OBJPROP_FONTSIZE, 8);
   }
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
   // Cek jika ada bar baru
   if(prev_calculated == 0 || rates_total - 1 > lastProcessedBar)
   {
      // Deteksi swing points
      DetectSwings();
      
      // Gambar garis horizontal
      DrawHorizontalLines();
      
      lastProcessedBar = rates_total - 1;
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Fungsi untuk mendapatkan shift bar berdasarkan timeframe         |
//+------------------------------------------------------------------+
int GetShiftOnChartTimeframe(datetime time)
{
   datetime chartTime[];
   ArraySetAsSeries(chartTime, true);
   
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, 100, chartTime) > 0)
   {
      for(int i = 0; i < ArraySize(chartTime); i++)
      {
         if(chartTime[i] <= time)
            return i;
      }
   }
   return 0;
}