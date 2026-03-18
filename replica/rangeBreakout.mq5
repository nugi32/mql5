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

//--- GLOBAL VARIABLES
double sessionHigh, sessionLow;
datetime sessionStartTime, sessionEndTime;
bool isSessionActive;
double pointValue;
double pipValue;

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
   
   Print("EA Range Session Scalper initialized. Magic: ", MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Update session range
   UpdateSessionRange();
   
   //--- Cek apakah perlu close trades/orders berdasarkan jam
   CheckCloseByHour();
   
   //--- Jika session aktif, catat high/low
   if(isSessionActive)
   {
      double currentHigh = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentLow = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      if(currentHigh > sessionHigh) sessionHigh = currentHigh;
      if(currentLow < sessionLow || sessionLow == 0) sessionLow = currentLow;
   }
   
   //--- Setelah session berakhir, hitung SL dan pasang order
   static datetime lastSessionEnd = 0;
   if(TimeCurrent() >= sessionEndTime && lastSessionEnd != sessionEndTime)
   {
      if(sessionHigh > 0 && sessionLow > 0)
      {
         PlacePendingOrders();
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
                                    dt.year, dt.month, dt.day, StartHour, StartMinute));
   datetime todayEnd = StringToTime(StringFormat("%04d.%02d.%02d %02d:%02d:00", 
                                  dt.year, dt.month, dt.day, EndHour, EndMinute));
   
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
//| Hitung volume berdasarkan risk option                           |
//+------------------------------------------------------------------+
double CalculateVolume()
{
   double volume = FixedLot; // Default
   
   if(RiskOption == 1) // Percentage of Equity
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      // Rumus sederhana: Volume = (Equity * Percent/100) / (SL * TickValue/TickSize)
      // Ini perlu disesuaikan dengan risk management yang diinginkan
      double riskAmount = equity * (PercentEquity / 100.0);
      double slPoints = CalculateSL() / pointValue;
      double pointValuePerLot = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / 
                                SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * pointValue;
      
      if(slPoints > 0 && pointValuePerLot > 0)
         volume = riskAmount / (slPoints * pointValuePerLot);
      
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
//| Pasang pending orders                                           |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double volume = CalculateVolume();
   double slPoints = CalculateSL();
   
   //--- Hitung harga pending order
   double buyStopPrice = NormalizeDouble(ask + OrderPadding * pointValue, _Digits);
   double sellStopPrice = NormalizeDouble(bid - OrderPadding * pointValue, _Digits);
   
   //--- Hitung SL dan TP
   double buySL = NormalizeDouble(buyStopPrice - slPoints, _Digits);
   double sellSL = NormalizeDouble(sellStopPrice + slPoints, _Digits);
   
   double partialTPPrice = PartialTP * 10 * pointValue; // Konversi pips ke harga
   double finalTPPrice = FinalTP * 10 * pointValue;
   
   double buyPartialTP = NormalizeDouble(buyStopPrice + partialTPPrice, _Digits);
   double buyFinalTP = NormalizeDouble(buyStopPrice + finalTPPrice, _Digits);
   
   double sellPartialTP = NormalizeDouble(sellStopPrice - partialTPPrice, _Digits);
   double sellFinalTP = NormalizeDouble(sellStopPrice - finalTPPrice, _Digits);
   
   //--- Cek apakah sudah ada pending order
   bool buyExists = PendingOrderExists(ORDER_TYPE_BUY_STOP);
   bool sellExists = PendingOrderExists(ORDER_TYPE_SELL_STOP);
   
   //--- Buat request structure
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   //--- Pasang Buy Stop (jika belum ada)
   if(!buyExists && volume > 0)
   {
      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = volume;
      request.type = ORDER_TYPE_BUY_STOP;
      request.price = buyStopPrice;
      request.sl = buySL;
      request.tp = buyFinalTP; // TP awal adalah Final TP, nanti dimodifikasi saat partial
      request.deviation = 10;
      request.magic = MagicNumber;
      request.comment = "Range Buy Stop";
      request.type_filling = ORDER_FILLING_FOK;
      request.type_time = ORDER_TIME_GTC;
      
      ZeroMemory(result);
      if(OrderSend(request, result))
      {
         Print("Buy Stop placed: ", result.order, " at ", buyStopPrice);
      }
      else
      {
         Print("Buy Stop failed: ", result.retcode, " ", result.comment);
      }
   }
   
   //--- Pasang Sell Stop (jika belum ada dan AllowBothDirections = true)
   if(AllowBothDirections && !sellExists && volume > 0)
   {
      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = volume;
      request.type = ORDER_TYPE_SELL_STOP;
      request.price = sellStopPrice;
      request.sl = sellSL;
      request.tp = sellFinalTP;
      request.deviation = 10;
      request.magic = MagicNumber;
      request.comment = "Range Sell Stop";
      request.type_filling = ORDER_FILLING_FOK;
      request.type_time = ORDER_TIME_GTC;
      
      ZeroMemory(result);
      if(OrderSend(request, result))
      {
         Print("Sell Stop placed: ", result.order, " at ", sellStopPrice);
      }
      else
      {
         Print("Sell Stop failed: ", result.retcode, " ", result.comment);
      }
   }
}

//+------------------------------------------------------------------+
//| Cek apakah pending order sudah ada                              |
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
                  
                  // Modifikasi sisa posisi untuk trailing (jika diaktifkan)
                  if(UseTrailing)
                  {
                     ModifyPositionForTrailing(ticket);
                  }
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
//| Modifikasi posisi untuk trailing                                |
//+------------------------------------------------------------------+
void ModifyPositionForTrailing(ulong ticket)
{
   // Implementasi modifikasi SL untuk trailing
   // Akan dipanggil setelah partial close
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
      
      //--- Close trades pada jam tertentu
      if(CloseTradesHour > 0 && dt.hour == CloseTradesHour && dt.min == 0)
      {
         CloseAllPositions();
      }
      
      //--- Close orders pada jam tertentu
      if(CloseOrdersHour > 0 && dt.hour == CloseOrdersHour && dt.min == 0)
      {
         DeleteAllPendingOrders();
      }
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
            OrderSend(request, result);
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
            OrderSend(request, result);
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