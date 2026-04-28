//+------------------------------------------------------------------+
//|                                                    EAtest.mq5    |
//|                        Expert Advisor using Candle Patterns     |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "..\lib\candlePattern\1CandlePattern.mqh"
#include "..\lib\candlePattern\2CandlePattern.mqh"
#include "..\lib\candlePattern\3CandlePattern.mqh"

//--- Input parameters
input int      TakeProfitPoints = 100;  // Take Profit in points
input int      StopLossPoints   = 50;   // Stop Loss in points
input double   LotSize          = 0.01; // Lot size

int atrHandle;
double ATR[];

CTrade         trade;
CPositionInfo  posInfo;

//+------------------------------------------------------------------+
//| Get combined signal from all candle patterns                     |
//+------------------------------------------------------------------+
ENUM_CANDLE_SIGNAL GetCombinedSignal(const double &open[], const double &close[], const double &high[], const double &low[], int barsCount)
{
   // Check 1 candle patterns
   ENUM_CANDLE_SIGNAL signal1 = GetCandleReversalSignal(open, close, high, low, 1, true);
   if(signal1 != SIGNAL_NONE) return signal1;
   
   // Check 2 candle patterns
   ENUM_CANDLE2_SIGNAL signal2 = GetCandle2ReversalSignal(open, high, low, close, 1, barsCount, true);
   if(signal2 == SIGNAL2_BULLISH) return SIGNAL_BULLISH;
   if(signal2 == SIGNAL2_BEARISH) return SIGNAL_BEARISH;
   
   // Check 3 candle patterns
   ENUM_CANDLE3_SIGNAL signal3 = GetCandle3ReversalSignal(open, high, low, close, 1, barsCount, true);
   if(signal3 == SIGNAL3_BULLISH) return SIGNAL_BULLISH;
   if(signal3 == SIGNAL3_BEARISH) return SIGNAL_BEARISH;
   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    atrHandle = iATR(_Symbol, _Period, 14);
       if(atrHandle == INVALID_HANDLE) return INIT_FAILED;
    ArraySetAsSeries(ATR, true);
   //---
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //---
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have open positions
   if(PositionSelect(_Symbol))
   {
      // If we have a position, do nothing (wait for TP/SL)
      return;
   }

      if(CopyBuffer(atrHandle, 0, 0, 3, ATR) < 0) return;

   // Get candle data (need enough for 3 candle patterns)
   int bars = 10; // Sufficient bars
   double open[], close[], high[], low[];
   ArrayResize(open, bars);
   ArrayResize(close, bars);
   ArrayResize(high, bars);
   ArrayResize(low, bars);
   
   for(int i = 0; i < bars; i++)
   {
      open[i]  = iOpen(_Symbol, _Period, i);
      close[i] = iClose(_Symbol, _Period, i);
      high[i]  = iHigh(_Symbol, _Period, i);
      low[i]   = iLow(_Symbol, _Period, i);
   }

   // Get combined signal from all candle patterns
   ENUM_CANDLE_SIGNAL signal = GetCombinedSignal(open, close, high, low, bars);

   if(signal == SIGNAL_BULLISH)
   {
      // Open Buy position
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = price - (ATR[0] * 1);
      double tp = price + (ATR[0] * 2);

      trade.Buy(LotSize, _Symbol, price, sl, tp, "Candle Pattern Buy");
   }
   else if(signal == SIGNAL_BEARISH)
   {
      // Open Sell position
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = price + (ATR[0] * 1);
      double tp = price - (ATR[0] * 2);

      trade.Sell(LotSize, _Symbol, price, sl, tp, "Candle Pattern Sell");
   }
}

//+------------------------------------------------------------------+