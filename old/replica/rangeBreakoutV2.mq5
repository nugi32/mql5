//+------------------------------------------------------------------+
//| EA: Session Box + Pending Orders (03-12) Volatility SL           |
//+------------------------------------------------------------------+
#property strict

input color  BoxColor    = clrAqua;
input int    BoxWidth    = 2;
input double LotSize     = 0.1;
input int    Slippage    = 5;
input int    MagicNumber = 12345;

datetime startTime, endTime;
double sessionHigh = -DBL_MAX;
double sessionLow  = DBL_MAX;
bool boxDrawn = false;
int lastDay = -1;

//+------------------------------------------------------------------+
//| Hitung ATR (average true range) selama sesi                      |
//+------------------------------------------------------------------+
double CalcVolatility()
{
    int bars = iBars(_Symbol, PERIOD_M5);
    if(bars <= 1) return 0;

    double sumTR = 0;
    for(int i=0; i<bars; i++)
    {
        double high  = iHigh(_Symbol, PERIOD_M5, i);
        double low   = iLow(_Symbol, PERIOD_M5, i);
        double prevClose = (i < bars-1) ? iClose(_Symbol, PERIOD_M5, i+1) : iClose(_Symbol, PERIOD_M5, i);
        double tr = MathMax(high-low, MathMax(MathAbs(high-prevClose), MathAbs(low-prevClose)));
        sumTR += tr;
    }
    return sumTR / bars; // ATR rata-rata
}

//+------------------------------------------------------------------+
//| Fungsi kirim pending order (MQL5)                                |
//+------------------------------------------------------------------+
bool SendPendingOrder(ENUM_ORDER_TYPE type, double price, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_PENDING;
   request.symbol   = _Symbol;
   request.volume   = LotSize;
   request.type     = type;
   request.price    = NormalizeDouble(price, _Digits);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= Slippage;
   request.magic    = MagicNumber;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time    = ORDER_TIME_GTC;

   if(!OrderSend(request, result))
   {
      Print("OrderSend failed: ", result.retcode);
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("OrderSend not successful: ", result.retcode);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Cek apakah order sudah ada                                        |
//+------------------------------------------------------------------+
bool OrderExists(ENUM_ORDER_TYPE type)
{
   int total = OrdersTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            if(OrderGetInteger(ORDER_TYPE) == type)
               return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update Session & Pasang Pending Orders                            |
//+------------------------------------------------------------------+
void UpdateSession()
{
   datetime now = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now, dt);

   // Reset tiap hari
   if(dt.day != lastDay)
   {
      sessionHigh = -DBL_MAX;
      sessionLow  = DBL_MAX;
      boxDrawn = false;
      lastDay = dt.day;
   }

   // Set jam 03:00
   dt.hour = 3; dt.min = 0; dt.sec = 0;
   startTime = StructToTime(dt);

   // Set jam 12:00
   dt.hour = 12; dt.min = 0; dt.sec = 0;
   endTime = StructToTime(dt);

   // Ambil data M5 terbaru
   double high = iHigh(_Symbol, PERIOD_M5, 0);
   double low  = iLow(_Symbol, PERIOD_M5, 0);

   // Kumpulkan high-low selama sesi
   if(now >= startTime && now <= endTime)
   {
      if(high > sessionHigh) sessionHigh = high;
      if(low < sessionLow)   sessionLow  = low;
   }

   // Setelah sesi selesai
   if(now > endTime && !boxDrawn)
   {
      string name = "BOX_0312_" + TimeToString(startTime, TIME_DATE);

      ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                   startTime, sessionHigh,
                   endTime, sessionLow);

      ObjectSetInteger(0, name, OBJPROP_COLOR, BoxColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, BoxWidth);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);

      // ===============================
      // HITUNG VOLATILITAS (ATR)
      // ===============================
      double volatility = CalcVolatility();
      if(volatility <= 0)
      {
         Print("Volatilitas nol, order tidak dikirim");
         boxDrawn = true;
         return;
      }

      double slDistance = volatility * 0.5;  // 50% volatilitas
      double tpDistance = slDistance * 3;    // RR 1:3

      double buyPrice  = sessionHigh;
      double sellPrice = sessionLow;

      double buySL = buyPrice - slDistance;
      double buyTP = buyPrice + tpDistance;

      double sellSL = sellPrice + slDistance;
      double sellTP = sellPrice - tpDistance;

      // Stop level check
      double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(MathAbs(buyPrice - buySL) < stopLevel || MathAbs(sellSL - sellPrice) < stopLevel)
      {
         Print("SL terlalu dekat dengan harga (stop level)");
         boxDrawn = true;
         return;
      }

      // ===============================
      // Kirim Pending Orders
      // ===============================
      if(!OrderExists(ORDER_TYPE_BUY_STOP))
         SendPendingOrder(ORDER_TYPE_BUY_STOP, buyPrice, buySL, buyTP);

      if(!OrderExists(ORDER_TYPE_SELL_STOP))
         SendPendingOrder(ORDER_TYPE_SELL_STOP, sellPrice, sellSL, sellTP);

      boxDrawn = true;
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateSession();
}
//+------------------------------------------------------------------+