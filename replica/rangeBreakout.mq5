//+------------------------------------------------------------------+
//|                                          RangeSessionScalper.mq5 |
//|                                      Replica by Analisis Pattern |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Replica by Analisis Pattern"
#property version   "1.00"
#property strict

//--- INPUT PARAMETERS (Sesuai dengan file input EA)
//--- RANGE SETTINGS
input string   RANGE_SETTINGS = "--- RANGE SETTINGS ---";
input int      StartHour = 3;           // Start (HH)
input int      StartMinute = 0;          // Start (MM)
input int      EndHour = 12;             // End (HH)
input int      EndMinute = 0;            // End (MM)
input color    RangeColor = C'52,101,164'; // Range Color (CadetBlue = 52,101,164)

//--- RISK MANAGEMENT
input string   RISK_MANAGEMENT = "--- RISK MANAGEMENT ---";
input int      RiskOption = 0;           // 0=Fixed, 1=Percentage
input double   FixedLot = 1.0;           // Lot Size (Fixed)
input double   PercentEquity = 1.0;      // Percentage of Equity

//--- ORDER SETTINGS
input string   ORDER_SETTINGS = "--- ORDER SETTINGS ---";
input int      MagicNumber = 4122;        // Magic Number
input int      OrderPadding = 5;          // Limit Order Padding (points)
input bool     AllowBothDirections = true; // Allow Both Directions
input int      CloseTradesHour = 0;       // Close Trades at certain hour (0=off)
input int      CloseOrdersHour = 0;        // Close Orders at certain hour (0=off)

//--- ENTRY/EXIT SETTINGS
input string   ENTRY_SETTINGS = "--- ENTRY/EXIT SETTINGS ---";
input int      RiskMode = 0;              // 0=Pips, 1=Session
input int      FixedSL = 1000;            // Stoploss (Pips)
input double   RangeSLPercent = 50.0;     // Stoploss Range % Off Session
input int      PartialTP = 2000;          // Partial TP (Pips)
input double   PartialClosePercent = 50.0; // Partial TP Close %
input int      FinalTP = 3000;            // Final TP (Pips)
input bool     UseTrailing = false;       // Activate Trailing Stoploss
input int      TrailingTrigger = 500;     // Trigger Distance (TSL)
input int      TrailingDistance = 700;    // Trailing Distance (TSL)

//--- ENTRY CHARACTERISTICS (berdasarkan pola dari data transaksi)
input string   ENTRY_CHARACTERISTICS = "--- ENTRY CHARACTERISTICS ---";
input int      EntryLevels = 3;           // Jumlah level entry (1-5)
input int      LevelDistance = 50;        // Jarak antar level (points)
input bool     UseFibonacci = true;       // Gunakan Fibonacci levels
input double   FibLevel1 = 0.236;         // Fibonacci level 1
input double   FibLevel2 = 0.382;         // Fibonacci level 2
input double   FibLevel3 = 0.618;         // Fibonacci level 3
input double   FibLevel4 = 0.786;         // Fibonacci level 4
input bool     UseBreakout = false;       // Gunakan breakout (false = pending order terus)

//--- GLOBAL VARIABLES
double sessionHigh, sessionLow;
datetime sessionStartTime, sessionEndTime;
bool isSessionActive;
double pointValue;
double pipValue;
long chartId;
string rectName = "RangeSessionRect";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Hitung nilai point dan pip
   pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   pipValue = pointValue * 10; // Untuk 5 digit broker, 1 pip = 10 point
   
   //--- Inisialisasi session
   sessionHigh = 0;
   sessionLow = 0;
   isSessionActive = false;
   chartId = ChartID();
   
   //--- Hapus rectangle lama jika ada
   ObjectDelete(chartId, rectName);
   
   Print("EA Range Session Scalper initialized. Magic: ", MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Hapus rectangle
   ObjectDelete(chartId, rectName);
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Update session range
   UpdateSessionRange();
   
   //--- Gambar kotak session
   DrawSessionRange();
   
   //--- Cek apakah perlu close trades/orders berdasarkan jam
   CheckCloseByHour();
   
   //--- Cek partial TP
   CheckPartialTP();
   
   //--- Jika session aktif, catat high/low
   if(isSessionActive)
   {
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      if(currentBid > sessionHigh) sessionHigh = currentBid;
      if(currentAsk < sessionLow || sessionLow == 0) sessionLow = currentAsk;
   }
   
   //--- Setelah session berakhir, pasang pending order di MULTIPLE LEVELS
   static datetime lastSessionEnd = 0;
   if(TimeCurrent() >= sessionEndTime && lastSessionEnd != sessionEndTime)
   {
      if(sessionHigh > 0 && sessionLow > 0)
      {
         PlaceMultipleLevelOrders();
         lastSessionEnd = sessionEndTime;
      }
   }
   
   //--- Trailing stop (jika diaktifkan)
   if(UseTrailing)
   {
      DoTrailingStop();
   }
}

//+------------------------------------------------------------------+
//| Update session range berdasarkan waktu                          |
//+------------------------------------------------------------------+
void UpdateSessionRange()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   //--- Tentukan waktu mulai dan selesai session untuk hari ini
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00", 
                                    dt.year, dt.mon, dt.day, StartHour, StartMinute));
   datetime todayEnd = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00", 
                                  dt.year, dt.mon, dt.day, EndHour, EndMinute));
   
   //--- Jika session melewati tengah malam, sesuaikan
   if(EndHour < StartHour || (EndHour == StartHour && EndMinute <= StartMinute))
   {
      if(currentTime < todayEnd)
         todayStart -= 24 * 3600; // Session kemarin
      else
         todayEnd += 24 * 3600;   // Session besok
   }
   
   //--- Cek apakah dalam session
   if(currentTime >= todayStart && currentTime < todayEnd)
   {
      if(!isSessionActive)
      {
         // Session baru dimulai
         isSessionActive = true;
         sessionHigh = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         sessionLow = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         sessionStartTime = todayStart;
         sessionEndTime = todayEnd;
         Print("Session started: High/Low reset");
      }
   }
   else
   {
      if(isSessionActive)
      {
         // Session berakhir
         isSessionActive = false;
         Print("Session ended. High: ", sessionHigh, " Low: ", sessionLow);
      }
   }
}

//+------------------------------------------------------------------+
//| Gambar kotak untuk area session                                 |
//+------------------------------------------------------------------+
void DrawSessionRange()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   //--- Tentukan waktu mulai dan selesai session untuk hari ini
   datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00", 
                                    dt.year, dt.mon, dt.day, StartHour, StartMinute));
   datetime todayEnd = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00", 
                                  dt.year, dt.mon, dt.day, EndHour, EndMinute));
   
   //--- Jika session melewati tengah malam, sesuaikan
   if(EndHour < StartHour || (EndHour == StartHour && EndMinute <= StartMinute))
   {
      if(currentTime < todayEnd)
         todayStart -= 24 * 3600; // Session kemarin
      else
         todayEnd += 24 * 3600;   // Session besok
   }
   
   //--- Cari high/low untuk periode session (gunakan fungsi Custom)
   double sessionHighPrice = GetHighForPeriod(todayStart, todayEnd);
   double sessionLowPrice = GetLowForPeriod(todayStart, todayEnd);
   
   //--- Gambar rectangle
   if(ObjectFind(chartId, rectName) < 0)
   {
      ObjectCreate(chartId, rectName, OBJ_RECTANGLE, 0, todayStart, sessionHighPrice, todayEnd, sessionLowPrice);
      ObjectSetInteger(chartId, rectName, OBJPROP_COLOR, RangeColor);
      ObjectSetInteger(chartId, rectName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(chartId, rectName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(chartId, rectName, OBJPROP_BACK, true); // Di belakang candlestick
      ObjectSetInteger(chartId, rectName, OBJPROP_FILL, true); // Diisi warna
      ObjectSetInteger(chartId, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chartId, rectName, OBJPROP_HIDDEN, true);
   }
   else
   {
      // Update rectangle
      ObjectMove(chartId, rectName, 0, todayStart, sessionHighPrice);
      ObjectMove(chartId, rectName, 1, todayEnd, sessionLowPrice);
   }
}

//+------------------------------------------------------------------+
//| Mendapatkan harga tertinggi untuk periode tertentu              |
//+------------------------------------------------------------------+
double GetHighForPeriod(datetime startTime, datetime endTime)
{
   double high = 0;
   int startShift = GetBarShift(_Symbol, PERIOD_CURRENT, startTime);
   int endShift = GetBarShift(_Symbol, PERIOD_CURRENT, endTime);
   
   if(startShift < 0 || endShift < 0) return SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   for(int i = startShift; i >= endShift; i--)
   {
      double barHigh = GetBarHigh(_Symbol, PERIOD_CURRENT, i);
      if(barHigh > high) high = barHigh;
   }
   
   return high;
}

//+------------------------------------------------------------------+
//| Mendapatkan harga terendah untuk periode tertentu               |
//+------------------------------------------------------------------+
double GetLowForPeriod(datetime startTime, datetime endTime)
{
   double low = DBL_MAX;
   int startShift = GetBarShift(_Symbol, PERIOD_CURRENT, startTime);
   int endShift = GetBarShift(_Symbol, PERIOD_CURRENT, endTime);
   
   if(startShift < 0 || endShift < 0) return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for(int i = startShift; i >= endShift; i--)
   {
      double barLow = GetBarLow(_Symbol, PERIOD_CURRENT, i);
      if(barLow < low) low = barLow;
   }
   
   return low;
}

//+------------------------------------------------------------------+
//| Custom iBarShift (tidak override built-in)                      |
//+------------------------------------------------------------------+
int GetBarShift(string symbol, ENUM_TIMEFRAMES tf, datetime time)
{
   datetime times[];
   ArraySetAsSeries(times, true);
   int bars = CopyTime(symbol, tf, 0, 1000, times);
   if(bars < 0) return -1;
   
   for(int i = 0; i < bars; i++)
   {
      if(time >= times[i])
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Custom iHigh (tidak override built-in)                          |
//+------------------------------------------------------------------+
double GetBarHigh(string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   double high[];
   ArraySetAsSeries(high, true);
   if(CopyHigh(symbol, tf, shift, 1, high) > 0)
      return high[0];
   return 0;
}

//+------------------------------------------------------------------+
//| Custom iLow (tidak override built-in)                           |
//+------------------------------------------------------------------+
double GetBarLow(string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   double low[];
   ArraySetAsSeries(low, true);
   if(CopyLow(symbol, tf, shift, 1, low) > 0)
      return low[0];
   return 0;
}

//+------------------------------------------------------------------+
//| Custom iClose (tidak override built-in)                         |
//+------------------------------------------------------------------+
double GetBarClose(string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(symbol, tf, shift, 1, close) > 0)
      return close[0];
   return 0;
}

//+------------------------------------------------------------------+
//| Pasang pending orders di MULTIPLE LEVELS                        |
//+------------------------------------------------------------------+
void PlaceMultipleLevelOrders()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double volume = CalculateVolume();
   double slPoints = CalculateSL();
   
   //--- Hitung range session
   double range = sessionHigh - sessionLow;
   
   //--- Hitung level-level entry berdasarkan karakteristik dari data
   double entryLevels[];
   ArrayResize(entryLevels, EntryLevels * 2); // Untuk buy dan sell
   
   //--- Level untuk BUY STOP (di atas harga)
   if(UseFibonacci)
   {
      // Fibonacci levels dari low ke high
      for(int i = 0; i < EntryLevels; i++)
      {
         double fibLevel;
         switch(i)
         {
            case 0: fibLevel = FibLevel1; break;
            case 1: fibLevel = FibLevel2; break;
            case 2: fibLevel = FibLevel3; break;
            case 3: fibLevel = FibLevel4; break;
            default: fibLevel = 0.5; break;
         }
         
         // Buy stop di atas session high + fib retracement
         entryLevels[i] = NormalizeDouble(sessionHigh + (range * fibLevel), _Digits);
      }
   }
   else
   {
      // Fixed distance levels
      for(int i = 0; i < EntryLevels; i++)
      {
         entryLevels[i] = NormalizeDouble(sessionHigh + (i + 1) * LevelDistance * pointValue, _Digits);
      }
   }
   
   //--- Level untuk SELL STOP (di bawah harga)
   if(UseFibonacci)
   {
      // Fibonacci levels dari high ke low
      for(int i = 0; i < EntryLevels; i++)
      {
         double fibLevel;
         switch(i)
         {
            case 0: fibLevel = FibLevel1; break;
            case 1: fibLevel = FibLevel2; break;
            case 2: fibLevel = FibLevel3; break;
            case 3: fibLevel = FibLevel4; break;
            default: fibLevel = 0.5; break;
         }
         
         // Sell stop di bawah session low - fib retracement
         entryLevels[EntryLevels + i] = NormalizeDouble(sessionLow - (range * fibLevel), _Digits);
      }
   }
   else
   {
      // Fixed distance levels
      for(int i = 0; i < EntryLevels; i++)
      {
         entryLevels[EntryLevels + i] = NormalizeDouble(sessionLow - (i + 1) * LevelDistance * pointValue, _Digits);
      }
   }
   
   //--- Hitung SL dan TP
   double partialTPPrice = PartialTP * 10 * pointValue; // Konversi pips ke harga
   double finalTPPrice = FinalTP * 10 * pointValue;
   
   //--- Pasang Buy Stop di setiap level
   for(int i = 0; i < EntryLevels; i++)
   {
      double buyStopPrice = entryLevels[i];
      
      // Validasi harga
      if(buyStopPrice <= ask) continue; // Buy stop harus di atas harga
      
      // Cek apakah sudah ada pending order di level ini
      if(PendingOrderExistsAtPrice(ORDER_TYPE_BUY_STOP, buyStopPrice)) continue;
      
      // Hitung SL untuk buy
      double buySL = NormalizeDouble(buyStopPrice - slPoints, _Digits);
      double buyTP = NormalizeDouble(buyStopPrice + finalTPPrice, _Digits);
      
      // Buat request
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = volume;
      request.type = ORDER_TYPE_BUY_STOP;
      request.price = buyStopPrice;
      request.sl = buySL;
      request.tp = buyTP;
      request.deviation = 10;
      request.magic = MagicNumber;
      request.comment = "Range Buy Stop L" + IntegerToString(i+1);
      request.type_filling = ORDER_FILLING_FOK;
      request.type_time = ORDER_TIME_GTC;
      
      ZeroMemory(result);
      if(OrderSend(request, result))
      {
         Print("Buy Stop Level ", i+1, " placed: ", result.order, " at ", buyStopPrice);
      }
      else
      {
         Print("Buy Stop Level ", i+1, " failed: ", result.retcode);
      }
   }
   
   //--- Pasang Sell Stop di setiap level (jika diizinkan)
   if(AllowBothDirections)
   {
      for(int i = 0; i < EntryLevels; i++)
      {
         double sellStopPrice = entryLevels[EntryLevels + i];
         
         // Validasi harga
         if(sellStopPrice >= bid) continue; // Sell stop harus di bawah harga
         
         // Cek apakah sudah ada pending order di level ini
         if(PendingOrderExistsAtPrice(ORDER_TYPE_SELL_STOP, sellStopPrice)) continue;
         
         // Hitung SL untuk sell
         double sellSL = NormalizeDouble(sellStopPrice + slPoints, _Digits);
         double sellTP = NormalizeDouble(sellStopPrice - finalTPPrice, _Digits);
         
         // Buat request
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_PENDING;
         request.symbol = _Symbol;
         request.volume = volume;
         request.type = ORDER_TYPE_SELL_STOP;
         request.price = sellStopPrice;
         request.sl = sellSL;
         request.tp = sellTP;
         request.deviation = 10;
         request.magic = MagicNumber;
         request.comment = "Range Sell Stop L" + IntegerToString(i+1);
         request.type_filling = ORDER_FILLING_FOK;
         request.type_time = ORDER_TIME_GTC;
         
         ZeroMemory(result);
         if(OrderSend(request, result))
         {
            Print("Sell Stop Level ", i+1, " placed: ", result.order, " at ", sellStopPrice);
         }
         else
         {
            Print("Sell Stop Level ", i+1, " failed: ", result.retcode);
         }
      }
   }
   
   //--- Tampilkan informasi level
   Print("--- Multiple Levels Placed ---");
   for(int i = 0; i < EntryLevels; i++)
   {
      Print("Buy Level ", i+1, ": ", entryLevels[i]);
   }
   for(int i = 0; i < EntryLevels; i++)
   {
      Print("Sell Level ", i+1, ": ", entryLevels[EntryLevels + i]);
   }
}

//+------------------------------------------------------------------+
//| Cek apakah pending order sudah ada di harga tertentu            |
//+------------------------------------------------------------------+
bool PendingOrderExistsAtPrice(ENUM_ORDER_TYPE type, double price)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == type)
         {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            // Bandingkan dengan toleransi kecil
            if(MathAbs(orderPrice - price) <= pointValue)
               return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cek apakah pending order sudah ada (by type)                    |
//+------------------------------------------------------------------+
bool PendingOrderExists(ENUM_ORDER_TYPE type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
            OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) == type)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Hitung volume berdasarkan risk option                           |
//+------------------------------------------------------------------+
double CalculateVolume()
{
   double volume = FixedLot; // Default
   
   if(RiskOption == 1) // Percentage of Equity
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      // Untuk MQL5, perhitungan sederhana: Volume = (Equity * Percent/100) / 1000 (asumsi)
      volume = equity * (PercentEquity / 100.0) / 1000.0;
      
      // Batasi volume minimum dan maksimum
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      volume = MathFloor(volume / lotStep) * lotStep;
      volume = MathMax(minLot, MathMin(maxLot, volume));
   }
   
   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| Hitung Stop Loss berdasarkan setting                            |
//+------------------------------------------------------------------+
double CalculateSL()
{
   double slPoints = 0;
   
   if(RiskMode == 0) // Pips mode
   {
      slPoints = FixedSL * 10 * pointValue; // Konversi pips ke harga
   }
   else // Session mode
   {
      if(sessionHigh > 0 && sessionLow > 0)
      {
         double range = (sessionHigh - sessionLow) / pointValue; // Range dalam points
         slPoints = (range * (RangeSLPercent / 100.0)) * pointValue;
         
         // Batasi jika melebihi FixedSL (optional)
         double maxSL = FixedSL * 10 * pointValue;
         if(slPoints > maxSL && maxSL > 0)
            slPoints = maxSL;
      }
      else
      {
         // Fallback ke FixedSL jika session tidak tersedia
         slPoints = FixedSL * 10 * pointValue;
      }
   }
   
   return NormalizeDouble(slPoints, _Digits);
}

//+------------------------------------------------------------------+
//| Cek posisi terbuka untuk partial TP                             |
//+------------------------------------------------------------------+
void CheckPartialTP()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                 SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double profitPoints = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                                 (currentPrice - openPrice) / pointValue :
                                 (openPrice - currentPrice) / pointValue;
            
            double partialTPPoints = PartialTP * 10; // Konversi pips ke points
            
            // Cek apakah sudah mencapai Partial TP
            if(profitPoints >= partialTPPoints)
            {
               double volume = PositionGetDouble(POSITION_VOLUME);
               double closeVolume = volume * (PartialClosePercent / 100.0);
               
               // Bulatkan sesuai lot step
               double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
               
               if(closeVolume > 0)
               {
                  ClosePartialPosition(ticket, closeVolume);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tutup sebagian posisi                                           |
//+------------------------------------------------------------------+
void ClosePartialPosition(ulong ticket, double volume)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = volume;
   request.deviation = 10;
   request.magic = MagicNumber;
   
   // Tentukan arah close
   if(PositionSelectByTicket(ticket))
   {
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         request.type = ORDER_TYPE_SELL;
      else
         request.type = ORDER_TYPE_BUY;
         
      request.price = (request.type == ORDER_TYPE_SELL) ? 
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      request.position = ticket;
      
      ZeroMemory(result);
      if(OrderSend(request, result))
      {
         Print("Partial close success: ", result.order, " Volume: ", volume);
      }
      else
      {
         Print("Partial close failed: ", result.retcode);
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing stop                                                   |
//+------------------------------------------------------------------+
void DoTrailingStop()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                 SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            double triggerPoints = TrailingTrigger * 10 * pointValue;
            double trailPoints = TrailingDistance * 10 * pointValue;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               // Untuk posisi Buy
               double newSL = currentPrice - trailPoints;
               
               // Cek apakah sudah mencapai trigger dan newSL lebih tinggi dari SL sebelumnya
               if(currentPrice - openPrice >= triggerPoints && 
                  (currentSL == 0 || newSL > currentSL))
               {
                  ModifyStopLoss(ticket, newSL);
               }
            }
            else
            {
               // Untuk posisi Sell
               double newSL = currentPrice + trailPoints;
               
               // Cek apakah sudah mencapai trigger dan newSL lebih rendah dari SL sebelumnya
               if(openPrice - currentPrice >= triggerPoints && 
                  (currentSL == 0 || newSL < currentSL))
               {
                  ModifyStopLoss(ticket, newSL);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modifikasi Stop Loss                                            |
//+------------------------------------------------------------------+
void ModifyStopLoss(ulong ticket, double newSL)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.symbol = _Symbol;
   request.sl = newSL;
   request.tp = PositionGetDouble(POSITION_TP);
   request.position = ticket;
   request.magic = MagicNumber;
   
   ZeroMemory(result);
   if(!OrderSend(request, result))
   {
      Print("Trailing modify failed: ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| Cek dan close berdasarkan jam                                   |
//+------------------------------------------------------------------+
void CheckCloseByHour()
{
   if(CloseTradesHour > 0 || CloseOrdersHour > 0)
   {
      datetime currentTime = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(currentTime, dt);
      
      static int lastCloseTradeHour = -1;
      static int lastCloseOrderHour = -1;
      
      //--- Close trades pada jam tertentu (hanya sekali per jam)
      if(CloseTradesHour > 0 && dt.hour == CloseTradesHour && dt.min < 5 && lastCloseTradeHour != dt.hour)
      {
         CloseAllPositions();
         lastCloseTradeHour = dt.hour;
      }
      
      //--- Close orders pada jam tertentu (hanya sekali per jam)
      if(CloseOrdersHour > 0 && dt.hour == CloseOrdersHour && dt.min < 5 && lastCloseOrderHour != dt.hour)
      {
         DeleteAllPendingOrders();
         lastCloseOrderHour = dt.hour;
      }
      
      // Reset counter jika jam berubah
      if(dt.hour != lastCloseTradeHour) lastCloseTradeHour = -1;
      if(dt.hour != lastCloseOrderHour) lastCloseOrderHour = -1;
   }
}

//+------------------------------------------------------------------+
//| Tutup semua posisi                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.deviation = 10;
            request.magic = MagicNumber;
            request.position = ticket;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               request.type = ORDER_TYPE_SELL;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            }
            else
            {
               request.type = ORDER_TYPE_BUY;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            }
            
            ZeroMemory(result);
            if(!OrderSend(request, result))
            {
               Print("Close position failed: ", result.retcode);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Hapus semua pending order                                       |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
            OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_REMOVE;
            request.order = ticket;
            
            ZeroMemory(result);
            if(!OrderSend(request, result))
            {
               Print("Delete order failed: ", result.retcode);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction handler untuk deteksi posisi baru            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // Deal added - cek apakah ini posisi baru dari pending order kita
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == MagicNumber)
         {
            // Ini adalah posisi baru dari EA kita
            // Bisa ditambahkan logika tambahan di sini jika diperlukan
         }
      }
   }
}
//+------------------------------------------------------------------+