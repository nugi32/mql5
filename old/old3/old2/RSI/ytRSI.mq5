//+------------------------------------------------------------------+
//| RSI MA Filter EA                                                 |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

CTrade trade;

// INPUT
input double InpLotSize = 0.01;
input int InpRSILevel = 30;
input int InpStopLoss = 200;
input int InpTakeProfit = 200;
input bool InpCloseSignal = true;
input long InpMagicNumber = 12345;

// INDICATOR HANDLES
int handleRSI;
int handleMA;

// BUFFERS
double bufferRSI[2];
double bufferMA[1];

datetime previousTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   handleRSI = iRSI(_Symbol,_Period,25,PRICE_CLOSE);
   handleMA  = iMA(_Symbol,_Period,25,0,MODE_SMA,PRICE_CLOSE);

   if(handleRSI == INVALID_HANDLE || handleMA == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   MqlTick currentTick;
   if(!SymbolInfoTick(_Symbol,currentTick))
   {
      Print("Failed to get current tick");
      return;
   }

   int values = CopyBuffer(handleRSI,0,0,2,bufferRSI);
   if(values != 2)
   {
      Print("Failed to get RSI values");
      return;
   }

   values = CopyBuffer(handleMA,0,0,1,bufferMA);
   if(values != 1)
   {
      Print("Failed to get MA value");
      return;
   }

   Comment(
      "bufferRSI[0]: ",bufferRSI[0],
      "\nbufferRSI[1]: ",bufferRSI[1],
      "\nbufferMA[0]: ",bufferMA[0]
   );

   int cntBuy, cntSell;
   if(!CountOpenPositions(cntBuy,cntSell)) return;

   // BUY
   if(cntBuy==0 && bufferRSI[1] >= (100-InpRSILevel) && bufferRSI[0] < (100-InpRSILevel) && currentTick.ask > bufferMA[0])
   {
      if(InpCloseSignal)
         if(!ClosePositions(2)) return;

      double sl = InpStopLoss==0 ? 0 : currentTick.bid - InpStopLoss * _Point;
      double tp = InpTakeProfit==0 ? 0 : currentTick.bid + InpTakeProfit * _Point;

      if(!NormalizePrice(sl)) return;
      if(!NormalizePrice(tp)) return;

      trade.PositionOpen(_Symbol,ORDER_TYPE_BUY,InpLotSize,currentTick.ask,sl,tp,"RSI MA filter EA");
   }

   // SELL
   if(cntSell==0 && bufferRSI[1] <= InpRSILevel && bufferRSI[0] > InpRSILevel && currentTick.bid < bufferMA[0])
   {
      if(InpCloseSignal)
         if(!ClosePositions(1)) return;

      double sl = InpStopLoss==0 ? 0 : currentTick.ask + InpStopLoss * _Point;
      double tp = InpTakeProfit==0 ? 0 : currentTick.ask - InpTakeProfit * _Point;

      if(!NormalizePrice(sl)) return;
      if(!NormalizePrice(tp)) return;

      trade.PositionOpen(_Symbol,ORDER_TYPE_SELL,InpLotSize,currentTick.bid,sl,tp,"RSI MA filter EA");
   }
}

//+------------------------------------------------------------------+
//| Check new bar                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentTime = iTime(_Symbol,_Period,0);

   if(previousTime != currentTime)
   {
      previousTime = currentTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
bool CountOpenPositions(int &cntBuy, int &cntSell)
{
   cntBuy = 0;
   cntSell = 0;

   int total = PositionsTotal();

   for(int i=total-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket<=0)
      {
         Print("Failed to get position ticket");
         return false;
      }

      if(!PositionSelectByTicket(ticket))
      {
         Print("Failed to select position");
         return false;
      }

      long magic;
      if(!PositionGetInteger(POSITION_MAGIC,magic))
      {
         Print("Failed to get magic number");
         return false;
      }

      if(magic == InpMagicNumber)
      {
         long type;

         if(!PositionGetInteger(POSITION_TYPE,type))
         {
            Print("Failed to get position type");
            return false;
         }

         if(type == POSITION_TYPE_BUY) cntBuy++;
         if(type == POSITION_TYPE_SELL) cntSell++;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Close positions                                                  |
//+------------------------------------------------------------------+
bool ClosePositions(int all_buy_sell)
{
   int total = PositionsTotal();

   for(int i=total-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket<=0)
      {
         Print("Failed to get position ticket");
         return false;
      }

      if(!PositionSelectByTicket(ticket))
      {
         Print("Failed to select position");
         return false;
      }

      long magic;

      if(!PositionGetInteger(POSITION_MAGIC,magic))
      {
         Print("Failed to get magic number");
         return false;
      }

      if(magic == InpMagicNumber)
      {
         long type;

         if(!PositionGetInteger(POSITION_TYPE,type))
         {
            Print("Failed to get position type");
            return false;
         }

         if(all_buy_sell==1 && type==POSITION_TYPE_SELL) continue;
         if(all_buy_sell==2 && type==POSITION_TYPE_BUY) continue;

         trade.PositionClose(ticket);

         if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
         {
            Print("Failed to close position: ",ticket,
            " result:",trade.ResultRetcode(),
            " ",trade.CheckResultRetcodeDescription());
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Normalize price                                                  |
//+------------------------------------------------------------------+
bool NormalizePrice(double &price)
{
   double tickSize = 0;

   if(!SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE,tickSize))
   {
      Print("Failed to get tick size");
      return false;
   }

   price = NormalizeDouble(MathRound(price/tickSize)*tickSize,_Digits);

   return true;
}