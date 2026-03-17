//+------------------------------------------------------------------+
//|                     Adaptive Swing EA v2.1                       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

//==================== INPUT ====================
input string   SETUP = "============= TRADING SETUP =============";
input double   RiskPercent = 2.0;            // Risk % dari equity per trade
input int      ATR_Period = 14;              // Periode ATR untuk SL
input double   ATR_Multiplier = 1.5;         // Multiplier ATR untuk SL
input bool     UseTrailingSL = false;        // Gunakan trailing stop loss
input double   TrailingStep = 0.5;           // Step trailing (dalam ATR)

input string   INDICATOR_SETUP = "============= INDICATOR SETUP =============";
input int      Depth = 10;                   // Depth swing detection
input ENUM_TIMEFRAMES IndicatorTF = PERIOD_H1; // Timeframe untuk indicator

input string   ORDER_SETUP = "============= ORDER SETUP =============";
input int      MagicNumber = 2024;           // Magic number
input int      Slippage = 10;                // Slippage dalam points
input string   OrderComment = "SwingTrade";  // Komentar order

//==================== GLOBAL ===================
int      HL_Handle = INVALID_HANDLE;
int      ATR_Handle = INVALID_HANDLE;
datetime lastBarTime = 0;
double   lastSwingPrice = 0;
bool     lastSwingWasHigh = false;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Load indicator h-l_indicator (sesuaikan parameter sesuai indikator)
   HL_Handle = iCustom(
      _Symbol,
      PERIOD_CURRENT,
      "h-l_indicator",
      Depth
   );

   if(HL_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot load indicator. Error code: ", GetLastError());
      return INIT_FAILED;
   }

   // Initialize ATR indicator
   ATR_Handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create ATR handle");
      return INIT_FAILED;
   }

   Print("EA initialized successfully. Indicator handle: ", HL_Handle);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(HL_Handle != INVALID_HANDLE)
      IndicatorRelease(HL_Handle);
      
   if(ATR_Handle != INVALID_HANDLE)
      IndicatorRelease(ATR_Handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

void OnTick()
{
   CheckForSwingPoints();
   
   // Trailing stop jika diaktifkan
   if(UseTrailingSL)
      ApplyTrailingStop();
}

//+------------------------------------------------------------------+
//| Cek swing points dari objek chart                               |
//+------------------------------------------------------------------+
void CheckForSwingPoints()
{
   string objPrefix = "ASHL_";
   int totalObjects = ObjectsTotal(0);

   double prevClose = iClose(_Symbol, _Period, 1);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double tolerance = spread * 2;

   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      if(StringFind(name, objPrefix) != 0)
         continue;

      double linePrice = ObjectGetDouble(0, name, OBJPROP_PRICE);

      // ==============================
      // SELL: harga dari bawah menyentuh garis
      // ==============================
      if(prevClose < linePrice &&
         MathAbs(bid - linePrice) <= tolerance)
      {
         if(MathAbs(linePrice - lastSwingPrice) > _Point)
         {
            Print("SELL touch line: ", linePrice);
            CloseBuyPositions();
            OpenSellOrder();
            lastSwingPrice = linePrice;
            lastSwingWasHigh = true;
            return;
         }
      }

      // ==============================
      // BUY: harga dari atas menyentuh garis
      // ==============================
      if(prevClose > linePrice &&
         MathAbs(ask - linePrice) <= tolerance)
      {
         if(MathAbs(linePrice - lastSwingPrice) > _Point)
         {
            Print("BUY touch line: ", linePrice);
            CloseSellPositions();
            OpenBuyOrder();
            lastSwingPrice = linePrice;
            lastSwingWasHigh = false;
            return;
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Cek jika ada posisi open dengan magic number                    |
//+------------------------------------------------------------------+

void CloseBuyPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol   = _Symbol;
      request.volume   = volume;
      request.type     = ORDER_TYPE_SELL;
      request.price    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      request.deviation= Slippage;
      request.magic    = MagicNumber;
      request.comment  = "Close BUY by EA";
      request.type_filling = ORDER_FILLING_FOK;

      if(OrderSend(request, result))
         Print("BUY closed: Ticket=", ticket, " Retcode=", result.retcode);
      else
         Print("Failed close BUY: Ticket=", ticket, " Error=", result.retcode);
   }
}

void CloseSellPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol   = _Symbol;
      request.volume   = volume;
      request.type     = ORDER_TYPE_BUY;
      request.price    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      request.deviation= Slippage;
      request.magic    = MagicNumber;
      request.comment  = "Close SELL by EA";
      request.type_filling = ORDER_FILLING_FOK;

      if(OrderSend(request, result))
         Print("SELL closed: Ticket=", ticket, " Retcode=", result.retcode);
      else
         Print("Failed close SELL: Ticket=", ticket, " Error=", result.retcode);
   }
}



bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            return true;
         }
      }
   }
   return false;
}
//+------------------------------------------------------------------+
//| Hitung lot size berdasarkan persentase equity                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * (RiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue * tickSize / _Point;
   
   if(slPoints <= 0 || pointValue <= 0) 
      return 0.01;
   
   double lotSize = riskAmount / (slPoints * pointValue);
   
   // Sesuaikan dengan lot step dan min/max lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Dapatkan ATR value                                               |
//+------------------------------------------------------------------+
double GetATRValue()
{
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   
   if(CopyBuffer(ATR_Handle, 0, 0, 1, atrBuffer) > 0)
      return atrBuffer[0];
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| Open BUY order dengan OrderSend                                 |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
if (HasOpenPosition()) return;
   double atrValue = GetATRValue();
   if(atrValue <= 0) 
   {
      Print("Cannot get ATR value for BUY order");
      return;
   }
   
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slPrice = entryPrice - (atrValue * ATR_Multiplier);
  // double tpPrice = CalculateTakeProfit(true, entryPrice, slPrice, 2.0);
   
   // Hitung lot size
   double slPoints = MathAbs(entryPrice - slPrice) / _Point;
   double lotSize = CalculateLotSize(slPoints);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Lot size too small: ", lotSize);
      return;
   }
   
   // Normalize prices
   entryPrice = NormalizeDouble(entryPrice, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Prepare order request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.magic = MagicNumber;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.price = entryPrice;
   request.sl = slPrice;
   request.tp = 0;
   request.deviation = Slippage;
   request.type = ORDER_TYPE_BUY;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment = OrderComment;
   
   // Send order
   if(OrderSend(request, result))
   {
      Print("BUY Order opened: Ticket=", result.order, 
            " Price=", entryPrice, " SL=", slPrice, " TP=", 0, 
            " Lot=", lotSize, " ATR=", atrValue);
   }
   else
   {
      Print("BUY Order failed: ", result.retcode, 
            " - ", GetRetcodeDescription(result.retcode));
   }
}

//+------------------------------------------------------------------+
//| Open SELL order dengan OrderSend                                |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
if (HasOpenPosition()) return;
   double atrValue = GetATRValue();
   if(atrValue <= 0) 
   {
      Print("Cannot get ATR value for SELL order");
      return;
   }
   
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = entryPrice + (atrValue * ATR_Multiplier);
   //double tpPrice = CalculateTakeProfit(false, entryPrice, slPrice, 2.0);
   
   // Hitung lot size
   double slPoints = MathAbs(slPrice - entryPrice) / _Point;
   double lotSize = CalculateLotSize(slPoints);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Lot size too small: ", lotSize);
      return;
   }
   
   // Normalize prices
   entryPrice = NormalizeDouble(entryPrice, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);
   //tpPrice = NormalizeDouble(tpPrice, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Prepare order request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.magic = MagicNumber;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.price = entryPrice;
   request.sl = slPrice;
   request.tp = 0;
   request.deviation = Slippage;
   request.type = ORDER_TYPE_SELL;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment = OrderComment;
   
   // Send order
   if(OrderSend(request, result))
   {
      Print("SELL Order opened: Ticket=", result.order, 
            " Price=", entryPrice, " SL=", slPrice, " TP=", 0, 
            " Lot=", lotSize, " ATR=", atrValue);
   }
   else
   {
      Print("SELL Order failed: ", result.retcode, 
            " - ", GetRetcodeDescription(result.retcode));
   }
}

//+------------------------------------------------------------------+
//| Apply trailing stop loss                                         |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   double atrValue = GetATRValue();
   double trailingDistance = atrValue * TrailingStep;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               double newSL = NormalizeDouble(currentPrice - trailingDistance, _Digits);
               if(newSL > currentSL && newSL > openPrice)
               {
                  request.action = TRADE_ACTION_SLTP;
                  request.position = ticket;
                  request.sl = newSL;
                  request.tp = PositionGetDouble(POSITION_TP);
                  request.magic = MagicNumber;
                  request.symbol = _Symbol;
                  
                  if(OrderSend(request, result))
                     Print("Trailing SL updated for BUY: ", newSL);
               }
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               double newSL = NormalizeDouble(currentPrice + trailingDistance, _Digits);
               if(newSL < currentSL && newSL < openPrice)
               {
                  request.action = TRADE_ACTION_SLTP;
                  request.position = ticket;
                  request.sl = newSL;
                  request.tp = PositionGetDouble(POSITION_TP);
                  request.magic = MagicNumber;
                  request.symbol = _Symbol;
                  
                  if(OrderSend(request, result))
                     Print("Trailing SL updated for SELL: ", newSL);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get retcode description                                          |
//+------------------------------------------------------------------+
string GetRetcodeDescription(int retcode)
{
   switch(retcode)
   {
      case 10004: return "TRADE_RETCODE_REQUOTE";
      case 10006: return "TRADE_RETCODE_REJECT";
      case 10007: return "TRADE_RETCODE_CANCEL";
      case 10008: return "TRADE_RETCODE_PLACED";
      case 10009: return "TRADE_RETCODE_DONE";
      case 10010: return "TRADE_RETCODE_DONE_PARTIAL";
      case 10011: return "TRADE_RETCODE_ERROR";
      case 10012: return "TRADE_RETCODE_TIMEOUT";
      case 10013: return "TRADE_RETCODE_INVALID";
      case 10014: return "TRADE_RETCODE_INVALID_VOLUME";
      case 10015: return "TRADE_RETCODE_INVALID_PRICE";
      case 10016: return "TRADE_RETCODE_INVALID_STOPS";
      case 10017: return "TRADE_RETCODE_TRADE_DISABLED";
      case 10018: return "TRADE_RETCODE_MARKET_CLOSED";
      case 10019: return "TRADE_RETCODE_NO_MONEY";
      case 10020: return "TRADE_RETCODE_PRICE_CHANGED";
      case 10021: return "TRADE_RETCODE_PRICE_OFF";
      case 10022: return "TRADE_RETCODE_INVALID_EXPIRATION";
      case 10023: return "TRADE_RETCODE_ORDER_CHANGED";
      case 10024: return "TRADE_RETCODE_TOO_MANY_REQUESTS";
      case 10025: return "TRADE_RETCODE_NO_CHANGES";
      case 10026: return "TRADE_RETCODE_SERVER_DISABLES_AT";
      case 10027: return "TRADE_RETCODE_CLIENT_DISABLES_AT";
      case 10028: return "TRADE_RETCODE_LOCKED";
      case 10029: return "TRADE_RETCODE_FROZEN";
      case 10030: return "TRADE_RETCODE_INVALID_FILL";
      case 10031: return "TRADE_RETCODE_CONNECTION";
      case 10032: return "TRADE_RETCODE_ONLY_REAL";
      case 10033: return "TRADE_RETCODE_LIMIT_ORDERS";
      case 10034: return "TRADE_RETCODE_LIMIT_VOLUME";
      case 10035: return "TRADE_RETCODE_INVALID_ORDER";
      case 10036: return "TRADE_RETCODE_POSITION_CLOSED";
      case 10038: return "TRADE_RETCODE_INVALID_CLOSE_VOLUME";
      case 10039: return "TRADE_RETCODE_CLOSE_ORDER_EXIST";
      case 10040: return "TRADE_RETCODE_LIMIT_POSITIONS";
      default: return "Unknown error: " + IntegerToString(retcode);
   }
}