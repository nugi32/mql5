//+------------------------------------------------------------------+
//|                     Adaptive Swing EA v2.1                       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

input string   INDICATOR_SETUP = "============= INDICATOR SETUP =============";
input int      Depth = 10;                   // Depth swing detection
input int     ConfirmBars = 3;            // Jumlah candle untuk konfirmasi swing
input ENUM_TIMEFRAMES IndicatorTF = PERIOD_H1; // Timeframe untuk indicator

input group "=== Tailing Settings ==="
input double             Inp_Trailing_ParabolicSAR_Step   =0.02;
input double             Inp_Trailing_ParabolicSAR_Maximum=0.2;

input string   ORDER_SETUP = "============= ORDER SETUP =============";
input double lotSize = 0.01;                // Ukuran lot
input int slBuffer = 10;
input int      MagicNumber = 2024;           // Magic number
input int      Slippage = 10;                // Slippage dalam points
input string   OrderComment = "Market-Structure";  // Komentar order

//==================== GLOBAL ===================
int      ms_handle = INVALID_HANDLE;
datetime lastBarTime = 0;

int sarHandle;

int lastTradedHighIndex = -1;
int lastTradedLowIndex  = -1;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   ms_handle = iCustom(_Symbol,IndicatorTF,"basicDot",Depth,ConfirmBars);

   sarHandle = iSAR(_Symbol,_Period,
                    Inp_Trailing_ParabolicSAR_Step,
                    Inp_Trailing_ParabolicSAR_Maximum);

   if(ms_handle == INVALID_HANDLE)
   {
      Print("Failed to load basicDot indicator");
      return INIT_FAILED;
   }

   if(sarHandle == INVALID_HANDLE)
   {
      Print("Failed to load SAR indicator");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
      IndicatorRelease(ms_handle);

      IndicatorRelease(sarHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

void OnTick()
{
   datetime currentBar = iTime(_Symbol,_Period,0);

   if(currentBar == lastBarTime)
      return;

   lastBarTime = currentBar;

   CheckForEntry();

      double newSL;
TrailingParabolicSAR(_Symbol,newSL);
}






















//+------------------------------------------------------------------+
//| Cek swing points dari objek chart                               |
//+------------------------------------------------------------------+
bool GetSwingBuffers(double &lastHigh, int &highIndex,
                     double &lastLow,  int &lowIndex)
{
   double highBuffer[50];
   double lowBuffer[50];
   double highBroken[50];
   double lowBroken[50];

   ArraySetAsSeries(highBuffer,true);
   ArraySetAsSeries(lowBuffer,true);
   ArraySetAsSeries(highBroken,true);
   ArraySetAsSeries(lowBroken,true);

   if(CopyBuffer(ms_handle,0,0,50,highBuffer)<=0) return false;
   if(CopyBuffer(ms_handle,1,0,50,lowBuffer)<=0) return false;
   if(CopyBuffer(ms_handle,2,0,50,highBroken)<=0) return false;
   if(CopyBuffer(ms_handle,3,0,50,lowBroken)<=0) return false;

   lastHigh = 0;
   lastLow  = 0;
   highIndex = -1;
   lowIndex  = -1;

   //====================
   // SWING HIGH VALID
   //====================
   for(int i=1;i<50;i++)
   {
      bool swingStillValid = (highBroken[i] == EMPTY_VALUE);

      if(highBuffer[i] != EMPTY_VALUE && swingStillValid)
      {
         lastHigh = highBuffer[i];
         highIndex = i;
         break;
      }
   }

   //====================
   // SWING LOW VALID
   //====================
   for(int i=1;i<50;i++)
   {
      bool swingStillValid = (lowBroken[i] == EMPTY_VALUE);

      if(lowBuffer[i] != EMPTY_VALUE && swingStillValid)
      {
         lastLow = lowBuffer[i];
         lowIndex = i;
         break;
      }
   }

   return true;
}
//+------------------------------------------------------------------+
bool GetHighZone(double swingHigh,int index,double &zoneStart,double &zoneEnd,double &sl)
{
   double lows[];
   ArraySetAsSeries(lows,true);

   if(CopyLow(_Symbol,IndicatorTF,0,100,lows)<=0)
      return false;

   double candleLow = lows[index];

   double range = swingHigh - candleLow;
   double zone  = range / 4.0;

   zoneStart = swingHigh;
   zoneEnd   = swingHigh - zone;

   sl = swingHigh + (slBuffer*_Point);

   return true;
}

bool GetLowZone(double swingLow,int index,double &zoneStart,double &zoneEnd,double &sl)
{
   double highs[];
   ArraySetAsSeries(highs,true);

   if(CopyHigh(_Symbol,IndicatorTF,0,100,highs)<=0)
      return false;

   double candleHigh = highs[index];

   double range = candleHigh - swingLow;
   double zone  = range / 4.0;

   zoneStart = swingLow;
   zoneEnd   = swingLow + zone;

   sl = swingLow - (slBuffer*_Point);

   return true;
}

//+------------------------------------------------------------------+

void CheckForEntry()
{
    if (HasOpenPosition()) return;
  
   double swingHigh, swingLow;
   int highIndex, lowIndex;

   if(!GetSwingBuffers(swingHigh,highIndex,swingLow,lowIndex))
      return;

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   // =========================
   // SELL ZONE
   // =========================

   if(swingHigh > 0)
   {
      double zoneStart,zoneEnd,sl;

      GetHighZone(swingHigh,highIndex,zoneStart,zoneEnd,sl);

if(bid <= zoneStart && bid >= zoneEnd)
{
   if(highIndex == lastTradedHighIndex)
      return;

   Print("SELL zone hit");

   CloseBuyPositions();
   OpenSellOrder(sl);

   lastTradedHighIndex = highIndex;
}
   }

   // =========================
   // BUY ZONE
   // =========================

   if(swingLow > 0)
   {
      double zoneStart,zoneEnd,sl;

      GetLowZone(swingLow,lowIndex,zoneStart,zoneEnd,sl);

if(ask >= zoneStart && ask <= zoneEnd)
{
   if(lowIndex == lastTradedLowIndex)
      return;

   Print("BUY zone hit");

   CloseSellPositions();
   OpenBuyOrder(sl);

   lastTradedLowIndex = lowIndex;
}
   }
}
//+------------------------------------------------------------------+
bool TrailingParabolicSAR(string symbol, double &newSL)
{
   if(PositionsTotal()==0)
      return false;

   double sarBuffer[];
   ArraySetAsSeries(sarBuffer,true);

   if(CopyBuffer(sarHandle,0,1,1,sarBuffer)<1)
      return false;

   double sarValue = sarBuffer[0];

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double bid = SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol,SYMBOL_ASK);

      if(type==POSITION_TYPE_BUY)
      {
         if(sarValue > currentSL && sarValue < bid)
         {
            newSL = sarValue;
         }
         else continue;
      }
      else if(type==POSITION_TYPE_SELL)
      {
         if((currentSL==0 || sarValue < currentSL) && sarValue > ask)
         {
            newSL = sarValue;
         }
         else continue;
      }

      MqlTradeRequest req={};
      MqlTradeResult  res={};

      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = symbol;
      req.sl       = newSL;
      req.tp       = tp;

      if(OrderSend(req,res))
      {
         if(res.retcode==TRADE_RETCODE_DONE)
         {
            Print("Trailing updated to: ",newSL);
            return true;
         }
      }
   }

   return false;
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

//+------------------------------------------------------------------+

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
//| Open BUY order dengan OrderSend                                 |
//+------------------------------------------------------------------+
void OpenBuyOrder(double slPrice)
{
   if (HasOpenPosition()) return;

   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double slPoints = MathAbs(entryPrice - slPrice) / _Point;

   entryPrice = NormalizeDouble(entryPrice,_Digits);
   slPrice = NormalizeDouble(slPrice,_Digits);

   MqlTradeRequest request={};
   MqlTradeResult result={};

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

   OrderSend(request,result);
}
//+------------------------------------------------------------------+
//| Open SELL order dengan OrderSend                                |
//+------------------------------------------------------------------+
void OpenSellOrder(double slPrice)
{
   if (HasOpenPosition()) return;

   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slPoints = MathAbs(slPrice - entryPrice) / _Point;

   entryPrice = NormalizeDouble(entryPrice,_Digits);
   slPrice = NormalizeDouble(slPrice,_Digits);

   MqlTradeRequest request={};
   MqlTradeResult result={};

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

   OrderSend(request,result);
}
