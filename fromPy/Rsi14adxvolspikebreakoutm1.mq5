//+-----------------------------------------------------------------------------------+
//| PatternEA_RSI_ADX_Vol_Breakout.mq5                                               |
//|                                                                                   |
//| Pattern  : RSI14_deep_oversold + ADX_strong_trend + vol_spike_1x5 + breakout_down|
//| Signal   : BULLISH  (Direction 55.3% | Avg Move 2.85 ATR | STABLE)               |
//| Exit     : Close position after X candles — no broker SL/TP                      |
//|                                                                                   |
//| DISCLAIMER: THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND.      |
//| THE AUTHOR SHALL NOT BE LIABLE FOR ANY DAMAGES ARISING FROM THE USE OF THIS CODE. |
//+-----------------------------------------------------------------------------------+

#property copyright "Nugi"
#property link      ""
#property description "Pattern: RSI14_deep_oversold + ADX_strong_trend + vol_spike_1x5 + breakout_down => BULLISH"
#property strict

//===================================================================================
// ENUMS
//===================================================================================

enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               // Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        // Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   // Only Process Ticks From New Bar in Trade TF
};

//===================================================================================
// INPUT PARAMETERS
//===================================================================================

input group "=== Framework Settings ==="
input ENUM_TIMEFRAMES            TradeTimeframe       = PERIOD_M15;                              // Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod  = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR;// EA Bar Processing Method

input group "=== Trade Management ==="
input double   LotSize            = 0.10;    // Lot Size
input int      ExitAfterCandles   = 4;       // Exit After X Candles (pattern timing ~3.6)
input int      MagicNumber        = 20250101;// Magic Number

input group "=== Condition Thresholds ==="
input double   RSIDeepOversoldLevel   = 25.0; // RSI14_deep_oversold  : RSI(14) < this value
input double   ADXStrongTrendLevel    = 35.0; // ADX_strong_trend     : ADX(14) > this value
input double   VolSpikeMultiplier     = 1.5;  // vol_spike_1x5        : Volume > VolSMA * this
input int      VolSMAPeriod           = 20;   // Volume SMA period for vol_spike check
input int      BreakoutPeriod         = 20;   // breakout_down        : Close < Lowest(Low, N)

//===================================================================================
// GLOBAL VARIABLES
//===================================================================================

int      TicksReceivedCount    = 0;
int      TicksProcessedCount   = 0;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;

// Indicator handles
int hRSI = INVALID_HANDLE;
int hADX = INVALID_HANDLE;

//===================================================================================
// OnInit
//===================================================================================

int OnInit()
{
   //--- Determine bar index used for processing (0 = forming bar, 1 = last completed bar)
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;  // Use last completed bar — values won't change mid-bar

   //--- Create indicator handles
   hRSI = iRSI(Symbol(), TradeTimeframe, 14, PRICE_CLOSE);
   hADX = iADX(Symbol(), TradeTimeframe, 14);

   if(hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles. EA cannot run.");
      return INIT_FAILED;
   }

   //--- Validate inputs
   if(ExitAfterCandles < 1)
   {
      Print("ERROR: ExitAfterCandles must be >= 1.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(LotSize <= 0.0)
   {
      Print("ERROR: LotSize must be > 0.");
      return INIT_PARAMETERS_INCORRECT;
   }

   Print("===========================================================");
   Print("EA INIT — Pattern: RSI14_deep_oversold + ADX_strong_trend + vol_spike_1x5 + breakout_down");
   Print("Bar processing method : ", EnumToString(BarProcessingMethod));
   Print("Indicator bar index   : ", iBarToUseForProcessing);
   Print("Exit after candles    : ", ExitAfterCandles);
   Print("Lot size              : ", LotSize);
   Print("===========================================================");

   OutputStatusToScreen();
   return INIT_SUCCEEDED;
}

//===================================================================================
// OnDeinit
//===================================================================================

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   Comment("");
}

//===================================================================================
// OnTick
//===================================================================================

void OnTick()
{
   TicksReceivedCount++;

   //--- Gate: only process at the desired interval
   bool ProcessThisIteration = false;

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
   {
      ProcessThisIteration = true;
   }
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
   {
      datetime m1Time = iTime(Symbol(), PERIOD_M1, 0);
      if(TimeLastTickProcessed != m1Time)
      {
         ProcessThisIteration  = true;
         TimeLastTickProcessed = m1Time;
      }
   }
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
   {
      datetime tfTime = iTime(Symbol(), TradeTimeframe, 0);
      if(TimeLastTickProcessed != tfTime)
      {
         ProcessThisIteration  = true;
         TimeLastTickProcessed = tfTime;
      }
   }

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      ProcessTradeClosures();  // Check exits first
      ProcessTradeOpens();     // Then check entries
   }

   OutputStatusToScreen();
}

//===================================================================================
// CONDITION CHECKS
//===================================================================================

//--- Condition 1: RSI14_deep_oversold — RSI(14) < 25
bool IsRSIDeepOversold(int bar)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hRSI, 0, 0, bar + 2, buf) <= 0)
   {
      Print("CopyBuffer RSI failed. Error: ", GetLastError());
      return false;
   }
   return (buf[bar] < RSIDeepOversoldLevel);
}

//--- Condition 2: ADX_strong_trend — ADX(14) > 35
bool IsADXStrongTrend(int bar)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   // Buffer 0 of iADX is the main ADX line
   if(CopyBuffer(hADX, 0, 0, bar + 2, buf) <= 0)
   {
      Print("CopyBuffer ADX failed. Error: ", GetLastError());
      return false;
   }
   return (buf[bar] > ADXStrongTrendLevel);
}

//--- Condition 3: vol_spike_1x5 — Volume > VolSMA(20) * 1.5
bool IsVolSpike(int bar)
{
   int copyNeeded = bar + VolSMAPeriod + 1;

   long volBuf[];
   ArraySetAsSeries(volBuf, true);

   if(CopyTickVolume(Symbol(), TradeTimeframe, 0, copyNeeded, volBuf) < copyNeeded)
      return false;

   double sum = 0.0;

   // include current candle like pandas rolling(20)
   for(int i = bar; i < bar + VolSMAPeriod; i++)
      sum += (double)volBuf[i];

   double volSMA = sum / VolSMAPeriod;

   return ((double)volBuf[bar] > volSMA * VolSpikeMultiplier);
}

//--- Condition 4: breakout_down — Close breaks below the Lowest Low of the last N bars
//    This is the contrarian trigger: price made a downward breakout — pattern says BULLISH reversal
bool IsBreakoutDown(int bar)
{
   int   copyNeeded = bar + BreakoutPeriod + 2;
   double closeBuf[], lowBuf[];
   ArraySetAsSeries(closeBuf, true);
   ArraySetAsSeries(lowBuf,   true);

   if(CopyClose(Symbol(), TradeTimeframe, 0, copyNeeded, closeBuf) < copyNeeded)
   {
      Print("CopyClose failed. Error: ", GetLastError());
      return false;
   }
   if(CopyLow(Symbol(), TradeTimeframe, 0, copyNeeded, lowBuf) < copyNeeded)
   {
      Print("CopyLow failed. Error: ", GetLastError());
      return false;
   }

   // Find the lowest low of the previous BreakoutPeriod bars (bars bar+1 … bar+BreakoutPeriod)
   double lowestLow = lowBuf[bar + 1];
   for(int i = bar + 2; i <= bar + BreakoutPeriod; i++)
   {
      if(lowBuf[i] < lowestLow)
         lowestLow = lowBuf[i];
   }

   // Breakout down = current close pierces below that lowest prior low
   return (closeBuf[bar] < lowestLow);
}

//--- Master pattern check: ALL four conditions must be true simultaneously
bool IsPatternActive(int bar)
{
   if(!IsRSIDeepOversold(bar)) return false;
   if(!IsADXStrongTrend(bar))  return false;
   if(!IsVolSpike(bar))        return false;
   if(!IsBreakoutDown(bar))    return false;
   return true;
}

//===================================================================================
// POSITION HELPERS
//===================================================================================

bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  == Symbol() &&
         PositionGetInteger(POSITION_MAGIC)  == MagicNumber)
         return true;
   }
   return false;
}

//--- Count how many closed candles have formed since a given datetime
int CandlesSinceOpen(datetime openTime)
{
   // iBarShift returns bar index (0 = current bar).
   // For a position opened at 'openTime', the shift tells us how far back that bar is.
   int shift = iBarShift(Symbol(), TradeTimeframe, openTime, false);
   return shift;
}

//===================================================================================
// PROCESS TRADE CLOSURES — Exit after ExitAfterCandles candles, no SL/TP
//===================================================================================

void ProcessTradeClosures()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != Symbol())       continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      datetime posOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
      int      barsElapsed = CandlesSinceOpen(posOpenTime);

      if(barsElapsed >= ExitAfterCandles)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double             volume  = PositionGetDouble(POSITION_VOLUME);

         MqlTradeRequest request = {};
         MqlTradeResult  result  = {};

         request.action   = TRADE_ACTION_DEAL;
         request.symbol   = Symbol();
         request.volume   = volume;
         request.position = ticket;
         request.magic    = MagicNumber;
         request.deviation = 20;
         request.comment  = "Exit after " + IntegerToString(barsElapsed) + " candles";

         // Close BUY with a SELL, close SELL with a BUY
         if(posType == POSITION_TYPE_BUY)
         {
            request.type  = ORDER_TYPE_SELL;
            request.price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         }
         else
         {
            request.type  = ORDER_TYPE_BUY;
            request.price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         }

         if(!OrderSend(request, result))
            Print("CLOSE FAILED  | Ticket: ", ticket,
                  " | RetCode: ", result.retcode,
                  " | Comment: ", result.comment);
         else
            Print("CLOSED        | Ticket: ", ticket,
                  " | Bars held: ", barsElapsed,
                  " | Price: ", request.price);
      }
   }
}

//===================================================================================
// PROCESS TRADE OPENS — Enter BUY when pattern fires
//===================================================================================

void ProcessTradeOpens()
{
   //--- Only one position at a time on this symbol / magic
   if(HasOpenPosition()) return;

   //--- Check all four conditions on the designated bar
   if(!IsPatternActive(iBarToUseForProcessing)) return;

   double askPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = Symbol();
   request.volume    = LotSize;
   request.type      = ORDER_TYPE_BUY;      // Pattern is BULLISH
   request.price     = askPrice;
   request.sl        = 0;                   // No broker SL — exit managed by candle count
   request.tp        = 0;                   // No broker TP
   request.deviation = 20;
   request.magic     = MagicNumber;
   request.comment   = "RSI_deep+ADX_strong+VolSpike+BrkDn";

   if(!OrderSend(request, result))
      Print("OPEN FAILED   | RetCode: ", result.retcode,
            " | Comment: ", result.comment);
   else
      Print("OPENED BUY    | Ticket: ", result.order,
            " | Price: ", askPrice,
            " | RSI<25 | ADX>35 | VolSpike | BreakoutDown");
}

//===================================================================================
// SCREEN OUTPUT
//===================================================================================

void OutputStatusToScreen()
{
   double offsetHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   // Gather live condition values for display (bar 0 for readability)
   double rsiVal  = 0, adxVal  = 0;
   double rsiB[], adxB[];
   ArraySetAsSeries(rsiB, true);
   ArraySetAsSeries(adxB, true);
   if(CopyBuffer(hRSI, 0, 0, 2, rsiB) > 0) rsiVal = rsiB[0];
   if(CopyBuffer(hADX, 0, 0, 2, adxB) > 0) adxVal = adxB[0];

   string out = "\n\r";
   out += "MT5 SERVER TIME : " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)
        + " (UTC/GMT" + StringFormat("%+.1f", offsetHours) + ")\n\r\n\r";

   out += "╔══════════════════════════════════════════════════════╗\n\r";
   out += "║  PATTERN EA — RSI14_deep_oversold + ADX_strong_trend  ║\n\r";
   out += "║              + vol_spike_1x5 + breakout_down          ║\n\r";
   out += "║  Signal: BULLISH 55.3% | Avg: 2.85 ATR | STABLE       ║\n\r";
   out += "╚══════════════════════════════════════════════════════╝\n\r\n\r";

   out += "Symbol           : " + Symbol() + "\n\r";
   out += "Timeframe        : " + EnumToString(TradeTimeframe) + "\n\r";
   out += "Process method   : " + EnumToString(BarProcessingMethod) + "\n\r";
   out += "Bar index used   : " + IntegerToString(iBarToUseForProcessing) + "\n\r\n\r";

   out += "--- Live Indicator Values (Bar 0) ---\n\r";
   out += "RSI(14)          : " + DoubleToString(rsiVal, 2)
        + "  (need < " + DoubleToString(RSIDeepOversoldLevel, 1) + ")\n\r";
   out += "ADX(14)          : " + DoubleToString(adxVal, 2)
        + "  (need > " + DoubleToString(ADXStrongTrendLevel, 1) + ")\n\r\n\r";

   out += "--- Session Stats ---\n\r";
   out += "Ticks received   : " + IntegerToString(TicksReceivedCount)   + "\n\r";
   out += "Ticks processed  : " + IntegerToString(TicksProcessedCount)  + "\n\r";
   out += "Open positions   : " + IntegerToString(PositionsTotal())     + "\n\r\n\r";

   out += "--- Trade Settings ---\n\r";
   out += "Lot size         : " + DoubleToString(LotSize, 2)            + "\n\r";
   out += "Exit after       : " + IntegerToString(ExitAfterCandles) + " candles\n\r";
   out += "Magic number     : " + IntegerToString(MagicNumber)          + "\n\r";

   Comment(out);
}