//+------------------------------------------------------------------+
//|                                         TrailingParabolicSAR.mqh |
//|                                              Single Function Only |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Single function untuk trailing stop dengan Parabolic SAR         |
//| Parameters:                                                      |
//|   symbol     - simbol trading                                    |
//|   sarStep    - step parameter untuk Parabolic SAR                |
//|   sarMaximum - maximum parameter untuk Parabolic SAR             |
//|   &newSL     - reference untuk menyimpan nilai SL baru           |
//| Returns: true jika trailing stop dieksekusi, false jika tidak    |
//+------------------------------------------------------------------+
bool TrailingParabolicSAR(string symbol, double sarStep, double sarMaximum, double &newSL)
{
   //--- Inisialisasi variables
   newSL = 0;
   
   //--- Cek apakah ada posisi terbuka
   if(PositionsTotal() == 0)
      return false;
   
   //--- Dapatkan ticket posisi pertama (sesuai magic number)
   ulong ticket = PositionGetTicket(0);
   if(ticket == 0)
      return false;
   
   //--- Select position
   if(!PositionSelectByTicket(ticket))
      return false;
   
   //--- Get position info
   string positionSymbol = PositionGetString(POSITION_SYMBOL);
   if(positionSymbol != symbol)
      return false;
   
   long positionType = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double basePrice = (currentSL == 0) ? openPrice : currentSL;
   
   //--- Buat handle Parabolic SAR
   int sarHandle = iSAR(symbol, PERIOD_CURRENT, sarStep, sarMaximum);
   if(sarHandle == INVALID_HANDLE)
   {
      Print("Error creating Parabolic SAR handle");
      return false;
   }
   
   //--- Dapatkan nilai SAR
   double sarBuffer[];
   ArraySetAsSeries(sarBuffer, true);
   
   if(CopyBuffer(sarHandle, 0, 1, 1, sarBuffer) < 1)
   {
      Print("Error copying SAR buffer");
      IndicatorRelease(sarHandle);
      return false;
   }
   
   double sarValue = sarBuffer[0];
   
   //--- Release handle
   IndicatorRelease(sarHandle);
   
   //--- Get symbol info
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
   
   //--- Cek apakah WIN contract (Brazilian market)
   bool isWinContract = (StringSubstr(symbol, 0, 3) == "WIN");
   
   //--- Get current bid/ask
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   //--- Calculate new stop loss based on position type
   double level = 0;
   double calculatedSL = 0;
   bool executeTrailing = false;
   
   if(positionType == POSITION_TYPE_BUY)  // Long position
   {
      //--- Level minimal SL
      level = NormalizeDouble(bid - stopsLevel * point, digits);
      
      //--- Nilai SAR untuk long position
      calculatedSL = NormalizeDouble(sarValue, digits);
      
      //--- Adjust untuk WIN contract
      if(isWinContract && point != 5 * _Point)
      {
         double remainder = MathMod(calculatedSL, tickValue * tickSize);
         calculatedSL = calculatedSL - remainder + (tickValue * tickSize);
      }
      
      //--- Validasi untuk long
      if(calculatedSL > basePrice && calculatedSL < level)
         executeTrailing = true;
   }
   else if(positionType == POSITION_TYPE_SELL)  // Short position
   {
      //--- Level maksimal SL
      level = NormalizeDouble(ask + stopsLevel * point, digits);
      
      //--- Nilai SAR untuk short position (plus spread)
      calculatedSL = NormalizeDouble(sarValue + spread, digits);
      
      //--- Adjust untuk WIN contract
      if(isWinContract && point != 5 * _Point)
      {
         double remainder = MathMod(calculatedSL, tickValue * tickSize);
         calculatedSL = calculatedSL - remainder;
      }
      
      //--- Validasi untuk short
      if(calculatedSL < basePrice && calculatedSL > level)
         executeTrailing = true;
   }
   
   //--- Eksekusi trailing stop jika valid
   if(executeTrailing)
   {
      newSL = calculatedSL;
      
      //--- Modify position
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = symbol;
      request.sl = newSL;
      request.tp = PositionGetDouble(POSITION_TP);
      request.magic = PositionGetInteger(POSITION_MAGIC);
      
      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("Trailing stop executed - New SL: ", newSL);
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Contoh cara penggunaan dalam EA:                                 |
//+------------------------------------------------------------------+
/*
void OnTick()
{
   double newStopLoss;
   if(TrailingParabolicSAR(_Symbol, 0.02, 0.2, newStopLoss))
   {
      Print("Trailing stop updated to: ", newStopLoss);
   }
}
*/