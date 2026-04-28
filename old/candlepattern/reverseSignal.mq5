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
input int emaPeriod = 50;

int atrHandle, emaHandle;
double ATR[], EMA[];

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
    emaHandle = iMA(_Symbol, _Period, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
     if(atrHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE) return INIT_FAILED;
    ArraySetAsSeries(ATR, true);
    ArraySetAsSeries(EMA, true);
   //---
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
    IndicatorRelease(emaHandle);
}

bool isBulliishTrend()
{
   if(CopyBuffer(emaHandle, 0, 0, 2, EMA) < 0) return false;
   return EMA[0] > (EMA[1] + 50 * _Point);
}

bool isBearishTrend()
{
   if(CopyBuffer(emaHandle, 0, 0, 2, EMA) < 0) return false;
   return EMA[0] < (EMA[1] - 50 * _Point);
}
//+------------------------------------------------------------------+
void OnTick()
{
   // === Ambil data candle SEKALI saja ===
   int bars = 10;
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

   ENUM_CANDLE_SIGNAL signal = GetCombinedSignal(open, close, high, low, bars);

   // === HANDLE OPEN POSITION ===
   if(PositionSelect(_Symbol))
   {
      long type = PositionGetInteger(POSITION_TYPE);

      // Close BUY jika reverse ke bearish
      if(type == POSITION_TYPE_BUY && signal == SIGNAL_BEARISH)
      {
         trade.PositionClose(_Symbol);
         return;
      }

      // Close SELL jika reverse ke bullish
      if(type == POSITION_TYPE_SELL && signal == SIGNAL_BULLISH)
      {
         trade.PositionClose(_Symbol);
         return;
      }

      return;
   }

         if(CopyBuffer(atrHandle, 0, 0, 3, ATR) < 0) return;

   // === ENTRY ===
   if(signal == SIGNAL_BULLISH && isBulliishTrend())
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = price - (ATR[0] * 1);
      double tp = 0;

      trade.Buy(LotSize, _Symbol, price, sl, tp, "Candle Buy");
   }
   else if(signal == SIGNAL_BEARISH && isBearishTrend())
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = price + (ATR[0] * 1);
      double tp = 0;

      trade.Sell(LotSize, _Symbol, price, sl, tp, "Candle Sell");
   }
}
//+------------------------------------------------------------------+