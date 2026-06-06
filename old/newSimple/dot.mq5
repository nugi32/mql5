//+------------------------------------------------------------------+
//|                                                   DotExampleEA   |
//|                       Example EA for drawing dots on chart       |
//+------------------------------------------------------------------+
#property strict

input color BuyDotColor  = clrLime;
input color SellDotColor = clrRed;
input int   DotDistance  = 100; // jarak dot dari candle (point)

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Fungsi membuat dot                                               |
//+------------------------------------------------------------------+
void CreateDot(string name, datetime t, double price, color clr)
{
   // kalau object sudah ada, hapus dulu
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   // buat object arrow
   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);

   // set bentuk jadi dot/bullet
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);

   // warna
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);

   // ukuran
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("DotExampleEA started");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ambil waktu candle sekarang
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

   // cek apakah candle baru
   if(currentBar != lastBarTime)
   {
      lastBarTime = currentBar;

      // data candle sebelumnya
      double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double low1   = iLow(_Symbol, PERIOD_CURRENT, 1);
      datetime t1   = iTime(_Symbol, PERIOD_CURRENT, 1);

      // =========================
      // Candle bullish
      // =========================
      if(close1 > open1)
      {
         double price = low1 - DotDistance * _Point;

         CreateDot(
            "BUY_DOT_" + IntegerToString((int)t1),
            t1,
            price,
            BuyDotColor
         );

         Print("Bullish dot created");
      }

      // =========================
      // Candle bearish
      // =========================
      if(close1 < open1)
      {
         double price = high1 + DotDistance * _Point;

         CreateDot(
            "SELL_DOT_" + IntegerToString((int)t1),
            t1,
            price,
            SellDotColor
         );

         Print("Bearish dot created");
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("DotExampleEA stopped");
}