//+------------------------------------------------------------------+
//|              EMA Crossover EA - Virtual Stop Loss               |
//+------------------------------------------------------------------+
#property strict

//--- Sideways Detector Inputs
input group "=== SIDEWAYS DETECTOR ==="

input int    SD_MinVotesRequired   = 3;
input bool   SD_ShowTrendDot       = false;
input int    SD_DotSize            = 2;
input color  SD_SidewaysColor      = clrDodgerBlue;
input color  SD_TrendingColor      = clrOrangeRed;
input int    SD_DotOffsetBars      = 5;

// METHOD 1 ADX
input bool   SD_Use_ADX            = true;
input int    SD_ADX_Period         = 14;
input double SD_ADX_Threshold      = 25.0;

// METHOD 2 ATR
input bool   SD_Use_ATR            = true;
input int    SD_ATR_FastPeriod     = 5;
input int    SD_ATR_SlowPeriod     = 50;
input double SD_ATR_Ratio          = 0.75;

// METHOD 3 BB Width
input bool   SD_Use_BBWidth        = true;
input int    SD_BB_Period          = 20;
input double SD_BB_Deviation       = 2.0;
input int    SD_BB_WidthLookback   = 50;
input double SD_BB_WidthPercent    = 0.50;

// METHOD 4 MA Slope
input bool   SD_Use_MASlope        = true;
input int    SD_MA_Period          = 50;
input ENUM_MA_METHOD SD_MA_Method  = MODE_EMA;
input int    SD_MA_SlopeLookback   = 5;
input double SD_MA_SlopeThreshold  = 0.0002;

// METHOD 5 LinReg
input bool   SD_Use_LinReg         = true;
input int    SD_LinReg_Period      = 20;
input double SD_LinReg_R2_Max      = 0.35;

// METHOD 6 Channel
input bool   SD_Use_Channel        = true;
input int    SD_Channel_Period     = 20;
input double SD_Channel_ATR_Multi  = 1.5;

input double LotSize           = 0.01;
input int    Slippage          = 10;
input int    FastEMA           = 10;
                                        
input double SarStep = 0.02;
input double SarMax  = 0.2;

input int atrPeriod           = 14;
input double atrMultiplier     = 1.0;
input ulong  MagicNumber       = 123456;


//--- indicator handles
int fastHandle, sidewaysHandle, atrHandle, sarHandle;

//--- virtual stop
struct VirtualSL
{
   ulong  ticket;
   double sl;
};
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle     = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
     sidewaysHandle = iCustom(
   _Symbol,
   PERIOD_CURRENT,
   "newSIdeways",

   SD_MinVotesRequired,
   SD_ShowTrendDot,
   SD_DotSize,
   SD_SidewaysColor,
   SD_TrendingColor,
   SD_DotOffsetBars,

   // ADX
   SD_Use_ADX,
   SD_ADX_Period,
   SD_ADX_Threshold,

   // ATR
   SD_Use_ATR,
   SD_ATR_FastPeriod,
   SD_ATR_SlowPeriod,
   SD_ATR_Ratio,

   // BB Width
   SD_Use_BBWidth,
   SD_BB_Period,
   SD_BB_Deviation,
   SD_BB_WidthLookback,
   SD_BB_WidthPercent,

   // MA Slope
   SD_Use_MASlope,
   SD_MA_Period,
   SD_MA_Method,
   SD_MA_SlopeLookback,
   SD_MA_SlopeThreshold,

   // LinReg
   SD_Use_LinReg,
   SD_LinReg_Period,
   SD_LinReg_R2_Max,

   // Channel
   SD_Use_Channel,
   SD_Channel_Period,
   SD_Channel_ATR_Multi
);

   atrHandle      = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle      = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);

   if(fastHandle     == INVALID_HANDLE ||
      sidewaysHandle == INVALID_HANDLE ||  // ← now actually valid
      atrHandle      == INVALID_HANDLE ||
      sarHandle      == INVALID_HANDLE)
      return INIT_FAILED;

   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(sidewaysHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(sarHandle);
}
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(currentBar != lastBar)
   {
      lastBar = currentBar;
      return true;
   }

   return false;
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar())
      return;

   CheckVirtualStops();

   double fast[], atr[], close[], open[], high[], low[];
   ArraySetAsSeries(fast,  true);
   ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   if(CopyBuffer(fastHandle, 0, 0, 3, fast)           < 3) return;
   if(CopyBuffer(atrHandle,  0, 0, 3, atr)            < 3) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3) return;
   if(CopyOpen (_Symbol, PERIOD_CURRENT, 0, 3, open)  < 3) return;
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, 3, high)  < 3) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, 3, low)   < 3) return;

   double currentPrice = close[0];
   double m = atr[1] * 0.15;

   bool buyS1 = close[2] < fast[2]     && close[1] > fast[1] + m;
   bool buyS2 = open[1]  < fast[1] - m && close[1] > fast[1] + m;
   bool buyS3 = high[2]  < fast[2]     && close[1] > fast[1] + m;
   bool buySignal = buyS1 || buyS2 || buyS3;

   bool sellS1 = close[2] > fast[2]     && close[1] < fast[1] - m;
   bool sellS2 = open[1]  > fast[1] + m && close[1] < fast[1] - m;
   bool sellS3 = low[2]   > fast[2]     && close[1] < fast[1] - m;
   bool sellSignal = sellS1 || sellS2 || sellS3;

   UpdateTrailingVirtualSL();

   if(HasOpenPosition())
      return;

   bool sideways = IsSideways();
   if(sideways)
      Print("SIDEWAYS DETECTED");
   else
      Print("TRENDING MARKET");

   // ← sideways filter only blocks new entries, not trailing/stops
   if(sideways)
      return;

   if(buySignal)  OpenBuy (currentPrice - atr[1] * atrMultiplier);
   if(sellSignal) OpenSell(currentPrice + atr[1] * atrMultiplier);
}
//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prevLow  = iLow(_Symbol, PERIOD_CURRENT, 1);

   for(int i = ArraySize(vsl)-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vsl[i].ticket))
      {
         ArrayRemove(vsl, i, 1);
         continue;
      }

      long type = PositionGetInteger(POSITION_TYPE);
      bool closeNow = false;

      if(type == POSITION_TYPE_BUY)
      {
         if(prevLow <= vsl[i].sl)
            closeNow = true;
      }
      else
      {
         if(prevHigh >= vsl[i].sl)
            closeNow = true;
      }

      if(closeNow)
      {
         if(ClosePosition(vsl[i].ticket))
            ArrayRemove(vsl, i, 1);
      }
   }
}
//+------------------------------------------------------------------+
bool IsSideways()
{
   if(sidewaysHandle == INVALID_HANDLE)
      return false;

   double sideways[2];
   ArraySetAsSeries(sideways, true);

   int copied = CopyBuffer(sidewaysHandle, 0, 0, 2, sideways);
   if(copied <= 0)
      return false;

   // debug
   PrintFormat("Sideways Buffer: copied=%d, bar0=%.5f, bar1=%.5f",
               copied,
               (copied > 0 ? sideways[0] : EMPTY_VALUE),
               (copied > 1 ? sideways[1] : EMPTY_VALUE));

   bool bar0 = (copied > 0 && sideways[0] != EMPTY_VALUE && sideways[0] != 0.0);
   bool bar1 = (copied > 1 && sideways[1] != EMPTY_VALUE && sideways[1] != 0.0);

   return (bar0 || bar1);
}
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
            return true;
      }
   }

   return false;
}
//+------------------------------------------------------------------+
void ManageReverseSignal(bool buySignal, bool sellSignal)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY && sellSignal)
         CloseAndRemove(ticket);

      if(type == POSITION_TYPE_SELL && buySignal)
         CloseAndRemove(ticket);
   }
}
//+------------------------------------------------------------------+
bool OpenBuy(double slPrice)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.type      = ORDER_TYPE_BUY;
   request.volume    = LotSize;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl        = 0;
   request.tp        = 0;
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(!OrderSend(request, result))
      return false;

   if(result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      AddVirtualSL(result.order, slPrice);
      return true;
   }

   return false;
}
//+------------------------------------------------------------------+
bool OpenSell(double slPrice)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.type      = ORDER_TYPE_SELL;
   request.volume    = LotSize;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl        = 0;
   request.tp        = 0;
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(!OrderSend(request, result))
      return false;

   if(result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL)
   {
      AddVirtualSL(result.order, slPrice);
      return true;
   }

   return false;
}
//+------------------------------------------------------------------+
void AddVirtualSL(ulong ticket, double sl)
{
   int size = ArraySize(vsl);
   ArrayResize(vsl, size + 1);

   vsl[size].ticket = ticket;
   vsl[size].sl     = NormalizeDouble(sl, _Digits);
}
//+------------------------------------------------------------------+
void CloseAndRemove(ulong ticket)
{
   if(ClosePosition(ticket))
   {
      for(int i = ArraySize(vsl)-1; i >= 0; i--)
      {
         if(vsl[i].ticket == ticket)
         {
            ArrayRemove(vsl, i, 1);
            break;
         }
      }
   }
}
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   long type = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = _Symbol;
   request.volume    = PositionGetDouble(POSITION_VOLUME);
   request.deviation = Slippage;
   request.magic     = MagicNumber;

   if(type == POSITION_TYPE_BUY)
   {
      request.type  = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      request.type  = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   if(!OrderSend(request, result))
      return false;

   return (result.retcode == TRADE_RETCODE_DONE ||
           result.retcode == TRADE_RETCODE_DONE_PARTIAL);
}
//+------------------------------------------------------------------+
void UpdateTrailingVirtualSL()
{
   double sar[];
   ArraySetAsSeries(sar, true);

   if(CopyBuffer(sarHandle, 0, 0, 3, sar) < 3)
      return;

   double sarValue = sar[1];

   for(int i = 0; i < ArraySize(vsl); i++)
   {
      ulong ticket = vsl[i].ticket;

      if(!PositionSelectByTicket(ticket))
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      // BUY POSITION
      if(type == POSITION_TYPE_BUY)
      {
         // trailing hanya naik
         if(sarValue > vsl[i].sl)
         {
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);
         }
      }

      // SELL POSITION
      else if(type == POSITION_TYPE_SELL)
      {
         // trailing hanya turun
         if(sarValue < vsl[i].sl)
         {
            vsl[i].sl = NormalizeDouble(sarValue, _Digits);
         }
      }
   }
}