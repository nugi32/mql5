//+------------------------------------------------------------------+
//| ATR Mean Reversion EA (Complete Version)                        |
//+------------------------------------------------------------------+
#property strict

//--- Input
input double LotSize = 0.1;

input int ATR_Period = 14;
input int MA_Period  = 50;

//--- Sideways
input int EMA_Period = 34;
input double Sideways_Buffer = 155;

//--- ATR Logic
input double ATR_Multiplier = 1.5;
input double SL_Multiplier  = 1.5;
input double TP_Multiplier  = 1.0;

//--- Fixed SL/TP
input double Fixed_SL = 300;
input double Fixed_TP = 300;

//--- Trade Settings
input int Slippage = 10;

//--- Features
input bool useTrailingStop = false;
input bool useBreakEven    = false;
input bool useATR          = true;

//--- SAR Trailing
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

//--- Break Even
input double BE_Trigger_ATR = 1.0;
input double BE_Lock_ATR    = 0.2;

//--- Handles
int atrHandle, maHandle, emaHandle, sarHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   maHandle  = iMA(_Symbol, _Period, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   sarHandle = iSAR(_Symbol, _Period, SAR_Step, SAR_Max);

   if(atrHandle == INVALID_HANDLE ||
      maHandle  == INVALID_HANDLE ||
      emaHandle == INVALID_HANDLE ||
      sarHandle == INVALID_HANDLE)
   {
      Print("Init error: ", GetLastError());
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
   IndicatorRelease(maHandle);
   IndicatorRelease(emaHandle);
   IndicatorRelease(sarHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   managePosition();

   if(!isSideways()) return;
   if(PositionsTotal() > 0) return;

   double atr[], ma[], close[];

   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(close, true);

   if(CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0) return;
   if(CopyBuffer(maHandle, 0, 0, 2, ma) <= 0) return;
   if(CopyClose(_Symbol, _Period, 0, 2, close) <= 0) return;

   double currentATR   = atr[0];
   double currentMA    = ma[0];
   double currentPrice = close[0];

   double deviation = MathAbs(currentPrice - currentMA);
   double threshold = currentATR * ATR_Multiplier;

   double sl, tp;

   if(useATR)
   {
      // SELL
      if(currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + (currentATR * SL_Multiplier);
         tp = currentPrice - (currentATR * TP_Multiplier);
         tradeSell(sl, tp);
      }

      // BUY
      if(currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - (currentATR * SL_Multiplier);
         tp = currentPrice + (currentATR * TP_Multiplier);
         tradeBuy(sl, tp);
      }
   }
   else
   {
      double sl_points = Fixed_SL * _Point;
      double tp_points = Fixed_TP * _Point;

      // SELL
      if(currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + sl_points;
         tp = currentPrice - tp_points;
         tradeSell(sl, tp);
      }

      // BUY
      if(currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - sl_points;
         tp = currentPrice + tp_points;
         tradeBuy(sl, tp);
      }
   }
}
//+------------------------------------------------------------------+
//| SIDEWAYS CHECK                                                   |
//+------------------------------------------------------------------+
bool isSideways()
{
   double ema[];
   ArraySetAsSeries(ema, true);

   if(CopyBuffer(emaHandle, 0, 0, 2, ema) <= 0)
      return false;

   double ema_diff = MathAbs(ema[0] - ema[1]);
   double buffer_price = Sideways_Buffer * _Point;

   return (ema_diff <= buffer_price);
}
//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                              |
//+------------------------------------------------------------------+
void managePosition()
{
   if(PositionsTotal() <= 0) return;

   double atr[], sar[];

   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(sar, true);

   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return;
   if(CopyBuffer(sarHandle, 0, 0, 1, sar) <= 0) return;

   double currentATR = atr[0];
   double currentSAR = sar[0];

   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      int type         = PositionGetInteger(POSITION_TYPE);

      double price = (type == POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //================ BREAK EVEN =================
      if(useBreakEven)
      {
         double trigger = currentATR * BE_Trigger_ATR;
         double lock    = currentATR * BE_Lock_ATR;

         if(type == POSITION_TYPE_BUY)
         {
            if(price - openPrice >= trigger)
            {
               double newSL = openPrice + lock;
               if(newSL > sl)
                  modifySL(ticket, newSL, tp);
            }
         }
         else
         {
            if(openPrice - price >= trigger)
            {
               double newSL = openPrice - lock;
               if(newSL < sl || sl == 0)
                  modifySL(ticket, newSL, tp);
            }
         }
      }

      //================ TRAILING SAR ===============
      if(useTrailingStop)
      {
         if(type == POSITION_TYPE_BUY)
         {
            if(currentSAR > sl && currentSAR < price)
               modifySL(ticket, currentSAR, tp);
         }
         else
         {
            if(currentSAR < sl && currentSAR > price)
               modifySL(ticket, currentSAR, tp);
         }
      }
   }
}
//+------------------------------------------------------------------+
//| MODIFY SL                                                        |
//+------------------------------------------------------------------+
void modifySL(ulong ticket, double newSL, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl       = NormalizeDouble(newSL, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);

   OrderSend(request, result);
}
//+------------------------------------------------------------------+
//| BUY                                                              |
//+------------------------------------------------------------------+
void tradeBuy(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.type     = ORDER_TYPE_BUY;
   request.symbol   = _Symbol;
   request.volume   = LotSize;
   request.price    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= Slippage;
   request.magic    = 123456;

   OrderSend(request, result);
}
//+------------------------------------------------------------------+
//| SELL                                                             |
//+------------------------------------------------------------------+
void tradeSell(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.type     = ORDER_TYPE_SELL;
   request.symbol   = _Symbol;
   request.volume   = LotSize;
   request.price    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = NormalizeDouble(tp, _Digits);
   request.deviation= Slippage;
   request.magic    = 123456;

   OrderSend(request, result);
}
//+------------------------------------------------------------------+