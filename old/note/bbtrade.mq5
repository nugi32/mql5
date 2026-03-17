//+------------------------------------------------------------------+
//|                                               BollingerBands.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

 #include<Trade\Trade.mqh> // Include the trade library
 CTrade trade; // Create an instance of the CTrade class  

 // Input parameters for the Bollinger Bands strategy
 input int BandPeriod = 30;
 input double BandDeviation = 2.0;
 input double LotSize = 0.2;
 input int Slippage = 3;
 const double StopLoss = 70;
 const double TakeProfit = 140;
 
 int Bb_Handle; // Handle for the Bollinger Bands indicator 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Create the Bollinger Bands indicator handle
   Bb_Handle = iBands(_Symbol, _Period, BandPeriod, BandDeviation, 0, PRICE_CLOSE); 
    { 
    if(Bb_Handle == INVALID_HANDLE)
     {
      Print("Error creating Bollinger Bands indicator"); 
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }
 
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Release the Bollinger Bands indicator hande
   IndicatorRelease(Bb_Handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
    double upperBand[], lowerBand[], middleBand[];
   
    // Copy the Bollinger Bands values into arrays
    if(CopyBuffer(Bb_Handle, 0, 0, 1, upperBand) <= 0||
      (CopyBuffer(Bb_Handle, 1, 0, 1, middleBand) <= 0||
      (CopyBuffer(Bb_Handle, 2, 0, 1, lowerBand) <= 0||
   {
     Print("Error copying band values");
     return;
    
     double upper = upperBand[0];
     double lower = lowerBand[0];
     double middle = middleBand[0];
     double price = Close[0];
     double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
     double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
     
     // Buy signal: price is below the lower band and no open positions 
    if(price < lower && ! IsPositionOpen(_symbol))
      {
       double sl, tp;
       CalculateSLTP(sl, tp, price, true);
      if(trade.Buy(LotSize, _symbol, Ask, sl, tp, "Buy Order"))
        Print("Buy order opened at price: ", price);
      else
      { 
       Print("Error opening BUY order:", trade.ResultRetcode());
     }
      // Sell signal: price is above the upper band no open positions
      else if(price > upper && ! IsPositionOpen(_symbol))
       {
        double sl, tp;
        CalculateSLTP(sl, tp, price, false);
       if(trade.Sell(LotSize, _Symbol, Bid, sl, tp, "Sell Order"));
         Print("Sell order opened at price:", Price);
      else
         print("Error opening SELL order:", trade.ResultRetcode())
    }
  }

//+------------------------------------------------------------------+
//| Check if there's an open position for a symbol                   |
//+------------------------------------------------------------------+
   
   bool IsPositionOpen(string symbol)
   }
    for(int i = 0;  i< PositionsTotal(); i++)
    }
     if(PositionSelectByIndex(i) && PositionGetString(POSITION_SYMBOL) == symbol)
       return true;
     {
      return false;
    }
//+------------------------------------------------------------------+
//|Close all positions for a symbol                                  |
//+------------------------------------------------------------------+
   void CloseAllPositions(string symbol)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
    if(PositionSelectByIndex(i) && PositionGetString(POSITION_SYMBOL) == symbol)
     {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         trade.sell(LotSize, symbol, symbolInfoDouble(symbol, SYMBOL_BID), Slippage, 0, "Close Buy");
     {
     if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
          trade.Buy(LotSize, symbol, SymbolInfoDouble(symbol, SYMBOL_ASK), Slippage, 0, "Close Sell");
          // Wait for order to be processed before continuing
            Sleep(1000);
           }
          }
         }
        
//+------------------------------------------------------------------+
//| Calculate Stop Loss and Take Profit levels                       |
//+------------------------------------------------------------------+
   void CalculateSLTP(double &sl, double &tp, double price, bool isBuy)
   {
    if(isBuy)
     {
      sl = price - StopLoss *_Point;
      tp = price + TakeProfit *_Point;
     }
     else 
      {
       sl = price + StopLoss *_Point;
       tp = price - TakeProfit *_Point;
      }
     }