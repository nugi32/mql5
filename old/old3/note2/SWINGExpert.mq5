//+------------------------------------------------------------------+
//|                     HL_Swing_EA.mq5                               |
//|        Uses ATR_HL_SET_TF.mq5 indicator                           |
//|        Buy  : Swing Low                                           |
//|        Sell : Swing High                                          |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

//==================== INPUT ====================
input double LotSize     = 0.10;
input int    StopLoss    = 300; 
input int    TakeProfit  = 600;

input int    Depth       = 10;             // SAME as indicator
input int    atrPeriod   = 14;
input double atrMult     = 0.5;
input ENUM_TIMEFRAMES ATR_TF = PERIOD_M1;

input ENUM_TIMEFRAMES SignalTF = PERIOD_CURRENT;
input int    MagicNumber = 777;

//==================== GLOBAL ===================
int      HL_Handle      = INVALID_HANDLE;
datetime lastBarTime    = 0;
datetime lastSwingTime  = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   HL_Handle = iCustom(
      _Symbol,
      SignalTF,
      "ATR_HL_SET_TF",
      Depth,
      atrPeriod,
      atrMult,
      ATR_TF
   );

   if(HL_Handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot load ATR_HL_SET_TF indicator");
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

   // ===== CHECK BUY (SWING LOW) =====
   for(int i = 1; i <= Depth + 2; i++)
   {
      if(swingLow[i] != EMPTY_VALUE)
      {
         datetime swingTime = iTime(_Symbol, SignalTF, i);

         if(swingTime > lastSwingTime)
         {
            lastSwingTime = swingTime;
            Print("BUY at Swing LOW | ", TimeToString(swingTime));
            OpenBuy();
            return;
         }
         break;
      }
   }

   // ===== CHECK SELL (SWING HIGH) =====
   for(int i = 1; i <= Depth + 2; i++)
   {
      if(swingHigh[i] != EMPTY_VALUE)
      {
         datetime swingTime = iTime(_Symbol, SignalTF, i);

         if(swingTime > lastSwingTime)
         {
            lastSwingTime = swingTime;
            Print("SELL at Swing HIGH | ", TimeToString(swingTime));
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

   request.action        = TRADE_ACTION_DEAL;
   request.symbol        = _Symbol;
   request.volume        = LotSize;
   request.type          = type;
   request.price         = price;
   request.sl            = sl;
   request.tp            = tp;
   request.magic         = MagicNumber;
   request.deviation     = 20;
   request.type_filling  = ORDER_FILLING_IOC;

   if(!OrderSend(request, result))
      Print("OrderSend failed: ", result.retcode);
}
