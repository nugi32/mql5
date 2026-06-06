#property strict

input ENUM_TIMEFRAMES TF = PERIOD_H1; // Timeframe target
input color BoxColor = clrRed;         // Warna kotak
input int BoxWidth = 1;                // Ketebalan garis

datetime lastCandleTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   lastCandleTime = iTime(_Symbol, TF, 0);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fungsi buat rectangle candle                                      |
//| return true jika berhasil dibuat                                   |
//+------------------------------------------------------------------+
bool DrawCandleBox(datetime candleTime, double highPrice, double lowPrice)
{
   datetime time1 = candleTime;
   datetime time2 = candleTime + PeriodSeconds(TF); // durasi candle
   string boxName = "CandleBox_" + IntegerToString(candleTime);

   if(!ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, time1, highPrice, time2, lowPrice))
   {
      Print("Gagal membuat rectangle: ", GetLastError());
      return false;
   }

   ObjectSetInteger(0, boxName, OBJPROP_COLOR, BoxColor);
   ObjectSetInteger(0, boxName, OBJPROP_WIDTH, BoxWidth);
   ObjectSetInteger(0, boxName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, boxName, OBJPROP_RAY_RIGHT, true); // extend kotak ke kanan

   return true; // rectangle berhasil dibuat
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentCandleTime = iTime(_Symbol, TF, 0);

   // cek candle baru
   if(currentCandleTime != lastCandleTime)
   {
      lastCandleTime = currentCandleTime;

      double highPrice = iHigh(_Symbol, TF, 1);
      double lowPrice  = iLow(_Symbol, TF, 1);
      datetime candleTime = iTime(_Symbol, TF, 1); // candle sebelumnya

      // panggil fungsi DrawCandleBox
      if(DrawCandleBox(candleTime, highPrice, lowPrice))
      {
         // Logic tambahan jika berhasil digambar
         Print("Rectangle candle berhasil dibuat untuk candle: ", TimeToString(candleTime, TIME_DATE|TIME_MINUTES));

         // Contoh logic tambahan: bisa hitung ukuran candle, warnai lain, dll.
         double candleRange = highPrice - lowPrice;
         if(candleRange > (0.005 * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)))
            Print("Candle besar detected: ", DoubleToString(candleRange, _Digits));
      }
   }
}