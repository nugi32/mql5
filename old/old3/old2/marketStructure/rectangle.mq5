//+------------------------------------------------------------------+
//|                                                h-l indicator.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "High"
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_type1   DRAW_ARROW

#property indicator_label2  "Low"
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_type2   DRAW_ARROW

input int Depth = 10;
//--- Input untuk fitur rectangle area
input int ExtendIgnoreCandles = 5;   // Jika kotak ditabrak setelah X candle sejak dot muncul, tabrakan diabaikan

double highs[], lows[];

int      lastDirection = 0;   // 1 = high, -1 = low
datetime lastTime      = 0;

//+------------------------------------------------------------------+
//| Fungsi untuk mendapatkan nama unik rectangle                    |
//+------------------------------------------------------------------+
string GetRectangleName(int index, string type)
{
   return "HL_RECTANGLE_" + type + "_" + IntegerToString(index) + "_" + IntegerToString(TimeCurrent());
}

//+------------------------------------------------------------------+
//| Fungsi untuk membuat rectangle area                             |
//+------------------------------------------------------------------+
void CreateRectangleArea(int dotIndex, 
                         double dotPrice, 
                         bool isSupply, 
                         const datetime &time[],
                         const double &high[],
                         const double &low[])
{
   // Dapatkan harga candle yang mencetak dot
   double candleHigh = high[dotIndex];
   double candleLow = low[dotIndex];
   datetime dotTime = time[dotIndex];
   
   // Hitung ukuran candle (tinggi candle)
   double candleSize = candleHigh - candleLow;
   
   // Hitung lebar kotak = 1/4 ukuran candle
   double boxHeight = candleSize * 0.25;
   
   // Tentukan harga awal dan arah kotak
   double priceTop, priceBottom;
   
   if(isSupply) // Supply (dot di atas) - kotak dari atas ke bawah
   {
      priceTop = candleHigh;      // Batas atas = high
      priceBottom = candleHigh - boxHeight; // Batas bawah = high - 1/4 ukuran
   }
   else // Demand (dot di bawah) - kotak dari bawah ke atas
   {
      priceTop = candleLow + boxHeight; // Batas atas = low + 1/4 ukuran
      priceBottom = candleLow;    // Batas bawah = low
   }
   
   // Cari batas kiri extend (candle pertama yang tidak menabrak)
   int extendStopIndex = 0;
   bool stopExtend = false;
   
   // Loop ke kiri untuk mencari tabrakan (dari dotIndex - 1 ke 0)
   for(int i = dotIndex - 1; i >= 0; i--)
   {
      double testHigh = high[i];
      double testLow = low[i];
      
      // Cek apakah candle menabrak area rectangle
      // Tabrak jika ada overlap antara range harga candle dengan range harga rectangle
      bool isTouching = false;
      
      if(isSupply)
      {
         // Untuk Supply: area dari priceBottom ke priceTop
         // Cek apakah candle menyentuh area ini
         if(testHigh >= priceBottom && testLow <= priceTop)
            isTouching = true;
      }
      else // Demand
      {
         // Untuk Demand: area dari priceBottom ke priceTop
         // Cek apakah candle menyentuh area ini
         if(testHigh >= priceBottom && testLow <= priceTop)
            isTouching = true;
      }
      
      if(isTouching)
      {
         // Cek apakah tabrakan terjadi setelah ExtendIgnoreCandles candle sejak dot
         int candlesFromDot = dotIndex - i;
         if(candlesFromDot > ExtendIgnoreCandles)
         {
            // Abaikan (false break), lanjutkan extend
            continue;
         }
         else
         {
            // Tabrakan valid, berhenti di sini
            stopExtend = true;
            // Berhenti di candle setelah yang menabrak (agar candle yang menabrak tidak masuk area)
            extendStopIndex = i + 1;
            break;
         }
      }
   }
   
   // Tentukan waktu untuk EXTEND KE KIRI
   // timeRight = waktu dot (kanan)
   // timeLeft = waktu batas kiri extend
   datetime timeRight = time[dotIndex];  // Kanan (dot)
   datetime timeLeft;                     // Kiri (batas extend)
   
   if(stopExtend && extendStopIndex < ArraySize(time))
      timeLeft = time[extendStopIndex];   // Batas kiri adalah candle setelah yang menabrak
   else
      timeLeft = time[ArraySize(time) - 1]; // Sampai candle paling kiri
   
   // Pastikan timeLeft lebih kecil dari timeRight (kiri < kanan)
   if(timeLeft > timeRight)
   {
      datetime temp = timeLeft;
      timeLeft = timeRight;
      timeRight = temp;
   }
   
   // Buat nama unik untuk rectangle
   string rectName = GetRectangleName(dotIndex, isSupply ? "SUPPLY" : "DEMAND");
   
   // Hapus rectangle dengan nama yang sama jika sudah ada
   if(ObjectFind(0, rectName) >= 0)
      ObjectDelete(0, rectName);
   
   // Buat rectangle object
   // OBJ_RECTANGLE menggunakan TIME1, PRICE1 (pojok kiri atas) dan TIME2, PRICE2 (pojok kanan bawah)
   if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, timeLeft, priceTop, timeRight, priceBottom))
   {
      Print("Gagal membuat rectangle: ", GetLastError());
      return;
   }
   
   // Set properties rectangle
   ObjectSetInteger(0, rectName, OBJPROP_COLOR, isSupply ? clrRed : clrGreen);
   ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, rectName, OBJPROP_BACK, true);  // Gambar di belakang candlestick
   ObjectSetInteger(0, rectName, OBJPROP_FILL, true);  // Isi dengan warna
   ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Update rectangle untuk memeriksa tabrakan baru                   |
//+------------------------------------------------------------------+
void UpdateRectangles(const datetime &time[], const double &high[], const double &low[])
{
   // Loop melalui semua rectangle
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if(StringFind(objName, "HL_RECTANGLE_") == 0)
      {
         // Dapatkan informasi rectangle
         datetime timeLeft = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
         datetime timeRight = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 1);
         double priceTop = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
         double priceBottom = ObjectGetDouble(0, objName, OBJPROP_PRICE, 1);
         
         // Cari index waktu
         int leftIndex = -1;
         int rightIndex = -1;
         int timeSize = ArraySize(time);
         
         for(int j = 0; j < timeSize; j++)
         {
            if(time[j] == timeLeft)
               leftIndex = j;
            if(time[j] == timeRight)
               rightIndex = j;
         }
         
         if(leftIndex < 0 || rightIndex < 0)
            continue;
         
         // Pastikan leftIndex lebih besar (lebih tua) dari rightIndex
         if(leftIndex < rightIndex)
         {
            int temp = leftIndex;
            leftIndex = rightIndex;
            rightIndex = temp;
         }
         
         // Dapatkan dot index dari nama rectangle
         string parts[];
         StringSplit(objName, '_', parts);
         if(ArraySize(parts) < 4)
            continue;
            
         int dotIndex = (int)StringToInteger(parts[3]);
         
         // Periksa candle dari kiri ke kanan (dari leftIndex ke rightIndex)
         for(int j = leftIndex; j > rightIndex; j--)
         {
            // Lewati candle dot
            if(j == dotIndex)
               continue;
               
            double testHigh = high[j];
            double testLow = low[j];
            
            // Cek tabrakan
            if(testHigh >= priceBottom && testLow <= priceTop)
            {
               int candlesFromDot = dotIndex - j;
               
               // Jika tabrakan terjadi dalam batas ExtendIgnoreCandles, update rectangle
               if(candlesFromDot <= ExtendIgnoreCandles)
               {
                  // Update batas kiri ke candle setelah yang menabrak
                  datetime newTimeLeft = time[j + 1];
                  if(newTimeLeft < timeRight)
                  {
                     ObjectSetInteger(0, objName, OBJPROP_TIME, 0, newTimeLeft);
                  }
                  break;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Indicator initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   SetIndexBuffer(0, highs, INDICATOR_DATA);
   SetIndexBuffer(1, lows,  INDICATOR_DATA);

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  10);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Indicator deinitialization                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Hapus semua rectangle yang dibuat indikator ini
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if(StringFind(objName, "HL_RECTANGLE_") == 0)
         ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
//| Indicator calculation                                            |
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
   // Set array sebagai series
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low,  true);
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   int limit = rates_total - prev_calculated;
   if(limit > 1)
   {
      limit = rates_total - Depth * 2 - 1;
      if(limit < 1)
         limit = 1;
   }

   for(int i = limit; i >= 0; i--)
   {
      highs[i] = EMPTY_VALUE;
      lows[i]  = EMPTY_VALUE;

      // ---- Swing High ----
      if(i + Depth < rates_total)
      {
         int maxIndex = ArrayMaximum(high, i, Depth * 2);
         if(maxIndex >= 0 && i + Depth == maxIndex)
         {
            if(lastDirection == 1)
            {
               int index = -1;
               for(int j = 0; j < rates_total; j++)
               {
                  if(time[j] == lastTime)
                  {
                     index = j;
                     break;
                  }
               }
               if(index >= 0 && high[index] >= high[i + Depth])
                  continue;

               if(index >= 0)
                  highs[index] = EMPTY_VALUE;
            }

            highs[i + Depth] = high[i + Depth];
            lastDirection = 1;
            lastTime      = time[i + Depth];
            
            // --- Buat rectangle untuk Supply (dot di atas) ---
            CreateRectangleArea(i + Depth, high[i + Depth], true, time, high, low);
         }
      }

      // ---- Swing Low ----
      if(i + Depth < rates_total)
      {
         int minIndex = ArrayMinimum(low, i, Depth * 2);
         if(minIndex >= 0 && i + Depth == minIndex)
         {
            if(lastDirection == -1)
            {
               int index = -1;
               for(int j = 0; j < rates_total; j++)
               {
                  if(time[j] == lastTime)
                  {
                     index = j;
                     break;
                  }
               }
               if(index >= 0 && low[index] <= low[i + Depth])
                  continue;

               if(index >= 0)
                  lows[index] = EMPTY_VALUE;
            }

            lows[i + Depth] = low[i + Depth];
            lastDirection = -1;
            lastTime      = time[i + Depth];
            
            // --- Buat rectangle untuk Demand (dot di bawah) ---
            CreateRectangleArea(i + Depth, low[i + Depth], false, time, high, low);
         }
      }
   }
   
   // Update rectangle untuk memeriksa tabrakan baru
   if(prev_calculated > 0)
      UpdateRectangles(time, high, low);

   return rates_total;
}
//+------------------------------------------------------------------+