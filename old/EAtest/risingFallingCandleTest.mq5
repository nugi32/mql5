//+------------------------------------------------------------------+
//|      Test EA - Candle Volatility Expansion Trading               |
//+------------------------------------------------------------------+
#property strict

#include "..\lib\candlePattern\risingFallingCandle.mqh"

input double LotSize = 0.01;
input double SL_Points = 300;
input double TP_Points = 600;
input int Slippage = 10;

bool wasContracting = false;

//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(PositionsTotal() > 0) return;

   bool contracting = IsContracting(_Symbol, _Period, 5);
   bool expanding   = IsExpanding(_Symbol, _Period, 5);

   // simpan fase contraction
   if(contracting)
   {
      wasContracting = true;
      return;
   }

   // entry saat expansion setelah contraction
   if(wasContracting && expanding)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double highPrev = iHigh(_Symbol, _Period, 1);
      double lowPrev  = iLow(_Symbol, _Period, 1);

      // breakout direction
      if(ask > highPrev)
      {
         double sl = ask - SL_Points * _Point;
         double tp = ask + TP_Points * _Point;

         tradeBuy(sl, tp);
         wasContracting = false;
      }
      else if(bid < lowPrev)
      {
         double sl = bid + SL_Points * _Point;
         double tp = bid - TP_Points * _Point;

         tradeSell(sl, tp);
         wasContracting = false;
      }
   }
}
//+------------------------------------------------------------------+
void tradeBuy(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_BUY;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = Slippage;
   request.magic = 999001;

   OrderSend(request, result);
}
//+------------------------------------------------------------------+
void tradeSell(double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_SELL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = Slippage;
   request.magic = 999001;

   OrderSend(request, result);
}
//+------------------------------------------------------------------+