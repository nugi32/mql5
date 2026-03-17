//+------------------------------------------------------------------+
//|                     HL_Swing_EA.mq5                               |
//|              Uses h-l_indicator.mq5                               |
//|              Buy  : Swing Low                                     |
//|              Sell : Swing High                                    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

//==================== INPUT ====================
input double LotSize     = 0.10;
input int    StopLoss    = 300; 
input int    TakeProfit  = 600;
input int    Depth       = 10; 
input int    MagicNumber = 777;

//==================== GLOBAL ===================
int      HL_Handle = INVALID_HANDLE;
datetime lastBarTime = 0;
datetime lastSwingTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   HL_Handle = iCustom(
      _Symbol,
      PERIOD_CURRENT,
      "h-l_indicator",
      Depth
   );

   if(HL_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot load h-l_indicator");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(HL_Handle != INVALID_HANDLE)
      IndicatorRelease(HL_Handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;
   if(PositionSelect(_Symbol)) return;

   double swingHigh[];
   double swingLow[];

   ArraySetAsSeries(swingHigh, true);
   ArraySetAsSeries(swingLow,  true);

   if(CopyBuffer(HL_Handle, 0, 0, Depth + 5, swingHigh) <= 0) return;
   if(CopyBuffer(HL_Handle, 1, 0, Depth + 5, swingLow)  <= 0) return;

   // ===== CHECK SWING LOW (BUY) =====
   for(int i = 1; i <= Depth + 2; i++)
   {
      if(swingLow[i] != EMPTY_VALUE)
      {
         datetime swingTime = iTime(_Symbol, PERIOD_CURRENT, i);

         if(swingTime > lastSwingTime)
         {
            lastSwingTime = swingTime;
            Print("BUY at new swing LOW, time: ", TimeToString(swingTime));
            OpenBuy();
            return;
         }
         break;
      }
   }

   // ===== CHECK SWING HIGH (SELL) =====
   for(int i = 1; i <= Depth + 2; i++)
   {
      if(swingHigh[i] != EMPTY_VALUE)
      {
         datetime swingTime = iTime(_Symbol, PERIOD_CURRENT, i);

         if(swingTime > lastSwingTime)
         {
            lastSwingTime = swingTime;
            Print("SELL at new swing HIGH, time: ", TimeToString(swingTime));
            OpenSell();
            return;
         }
         break;
      }
   }
}




//+------------------------------------------------------------------+
//| Check New Candle                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current != lastBarTime)
   {
      lastBarTime = current;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| BUY ORDER                                                         |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = price - StopLoss * _Point;
   double tp    = price + TakeProfit * _Point;

   SendOrder(ORDER_TYPE_BUY, price, sl, tp);
}

//+------------------------------------------------------------------+
//| SELL ORDER                                                        |
//+------------------------------------------------------------------+
void OpenSell()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = price + StopLoss * _Point;
   double tp    = price - TakeProfit * _Point;

   SendOrder(ORDER_TYPE_SELL, price, sl, tp);
}

//+------------------------------------------------------------------+
//| Order Send                                                        |
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double price, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.volume   = LotSize;
   request.type     = type;
   request.price    = price;
   request.sl       = sl;
   request.tp       = tp;
   request.magic    = MagicNumber;
   request.deviation= 20;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request, result))
   {
      Print("OrderSend failed: ", result.retcode);
   }
}
