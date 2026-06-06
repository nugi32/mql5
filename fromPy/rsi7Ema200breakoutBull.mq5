//+-----------------------------------------------------------------------------------+
//| rsi7_ema200_breakout_bull.mq5                                                     |
//|                                                                                   |
//| STRATEGY: RSI7_oversold + close_above_EMA200 + breakout_down => BULLISH ENTRY     |
//|                                                                                   |
//| Signal Stats (from backtested pattern mining):                                    |
//|   Direction : BULLISH 55.0%                                                       |
//|   Magnitude : 2.21 ATR (high variance, cv=0.64)                                   |
//|   Frequency : 0.95% of bars                                                       |
//|   Timing    : ~3.5 candles to resolution                                          |
//|                                                                                   |
//| Signal Definitions:                                                               |
//|   RSI7 oversold      : RSI(7) < OversoldLevel (default 30)                        |
//|   Close above EMA200 : Close > EMA(200)                                           |
//|   Breakout down      : Close < min(Low, 20 bars back from prev bar)               |
//|     (Python equiv)   : Close < Low.rolling(20).min().shift(1)                     |
//|                                                                                   |
//| DISCLAIMER: THIS SOFTWARE IS PROVIDED "AS IS". THE AUTHOR ACCEPTS NO LIABILITY   |
//| FOR TRADING LOSSES. PAST PATTERN STATISTICS DO NOT GUARANTEE FUTURE PERFORMANCE.  |
//+-----------------------------------------------------------------------------------+

#property copyright "Nugi"
#property link      ""
#property description "RSI7 Oversold + EMA200 Filter + Breakout-Down Reversal"
#property strict

//===================================================================================
//  ENUMS
//===================================================================================

enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               // Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        // Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   // Only Process Ticks From New Bar in Trade TF
};

//===================================================================================
//  INPUT PARAMETERS
//===================================================================================

input group "=== Framework Settings ==="
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR;

input group "=== Signal Parameters ==="
input int    RSI_Period          = 7;      // RSI Period
input double RSI_OversoldLevel   = 30.0;  // RSI Oversold Threshold
input int    EMA_Period          = 200;   // EMA Period
input int    Breakout_Lookback   = 20;    // Breakout Lookback (bars)

input group "=== Trade Management ==="
input double LotSize             = 0.1;   // Lot Size
input double SL_ATR_Multiplier   = 1.2;  // Stop Loss (x ATR)
input double TP_ATR_Multiplier   = 2.2;  // Take Profit (x ATR) [matches signal magnitude]
input int    ATR_Period          = 14;    // ATR Period for SL/TP
input int    MaxBarsInTrade      = 7;     // Max Bars Before Force-Close (2x signal timing)
input int    MaxOpenTrades       = 1;     // Max concurrent trades from this EA
input ulong  MagicNumber         = 20250101;

input group "=== Risk Guard ==="
input double MaxSpreadPoints     = 20.0; // Max allowed spread (points) to enter

//===================================================================================
//  GLOBAL VARIABLES
//===================================================================================

int      TicksReceivedCount    = 0;
int      TicksProcessedCount   = 0;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;

// Indicator handles
int hRSI   = INVALID_HANDLE;
int hEMA   = INVALID_HANDLE;
int hATR   = INVALID_HANDLE;

//===================================================================================
//  OnInit
//===================================================================================

int OnInit()
{
   //--- Determine processing bar (0 = current forming bar, 1 = last closed bar)
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;

   //--- Create indicator handles
   hRSI = iRSI(Symbol(), TradeTimeframe, RSI_Period, PRICE_CLOSE);
   hEMA = iMA(Symbol(), TradeTimeframe, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR = iATR(Symbol(), TradeTimeframe, ATR_Period);

   if(hRSI == INVALID_HANDLE || hEMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create one or more indicator handles.");
      return INIT_FAILED;
   }

   Print("EA INIT OK | Method=" + EnumToString(BarProcessingMethod) +
         " | Bar=" + IntegerToString(iBarToUseForProcessing));

   OutputStatusToScreen();
   return INIT_SUCCEEDED;
}

//===================================================================================
//  OnDeinit
//===================================================================================

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
}

//===================================================================================
//  OnTick
//===================================================================================

void OnTick()
{
   TicksReceivedCount++;

   //--- Bar-processing gate (framework logic)
   bool ProcessThisIteration = false;

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
   {
      ProcessThisIteration = true;
   }
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), PERIOD_M1, 0))
      {
         ProcessThisIteration  = true;
         TimeLastTickProcessed = iTime(Symbol(), PERIOD_M1, 0);
      }
   }
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), TradeTimeframe, 0))
      {
         ProcessThisIteration  = true;
         TimeLastTickProcessed = iTime(Symbol(), TradeTimeframe, 0);
      }
   }

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      ProcessTradeClosures();
      ProcessTradeOpens();
   }

   OutputStatusToScreen();
}

//===================================================================================
//  SIGNAL LOGIC
//===================================================================================

//--- Returns true when ALL three conditions of the pattern are active on bar [iBar]
bool IsSignalActive(int iBar)
{
   //--- 1. Read RSI buffer
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   if(CopyBuffer(hRSI, 0, 0, iBar + 2, rsiBuffer) < iBar + 2) return false;

   //--- 2. Read EMA buffer
   double emaBuffer[];
   ArraySetAsSeries(emaBuffer, true);
   if(CopyBuffer(hEMA, 0, 0, iBar + 2, emaBuffer) < iBar + 2) return false;

   //--- 3. Read ATR buffer (needed later but validate handle here)
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(hATR, 0, 0, iBar + 2, atrBuffer) < iBar + 2) return false;

   //--- 4. Read OHLC from Trade TF
   //       We need enough bars for the 20-bar rolling min (plus the shift of 1)
   //       So: iBar + 1 (shift) + 20 (window) = iBar + 21 bars minimum
   int barsNeeded = iBar + 1 + Breakout_Lookback + 1;
   double closeArr[], lowArr[];
   ArraySetAsSeries(closeArr, true);
   ArraySetAsSeries(lowArr,   true);
   if(CopyClose(Symbol(), TradeTimeframe, 0, barsNeeded, closeArr) < barsNeeded) return false;
   if(CopyLow  (Symbol(), TradeTimeframe, 0, barsNeeded, lowArr  ) < barsNeeded) return false;

   //--- Condition A: RSI(7) < OversoldLevel
   double rsiVal = rsiBuffer[iBar];
   bool rsiOversold = (rsiVal < RSI_OversoldLevel);

   //--- Condition B: Close > EMA(200)
   double closeVal = closeArr[iBar];
   double emaVal   = emaBuffer[iBar];
   bool aboveEMA   = (closeVal > emaVal);

   //--- Condition C: Breakout Down
   //    Python: Close < Low.rolling(20).min().shift(1)
   //    MQL5  : closeArr[iBar] < min(lowArr[iBar+1 .. iBar+20])
   //    ArraySetAsSeries=true  => index 0 = newest bar
   //    => shift(1) means starting from iBar+1 in series-indexed array
   int lowestIdx = iLowest(Symbol(), TradeTimeframe, MODE_LOW,
                           Breakout_Lookback, iBar + 1);
   if(lowestIdx < 0) return false;
   double rollingMinLow = iLow(Symbol(), TradeTimeframe, lowestIdx);
   bool breakoutDown    = (closeVal < rollingMinLow);

   //--- DEBUG (comment out in production)
   if(ProcessThisIterationDbg())
      Print(StringFormat("SIGNAL CHECK | Bar=%d | RSI=%.2f(<%.1f:%s) | Close=%.5f EMA=%.5f (AboveEMA:%s) | RollMinLow=%.5f (BrkDn:%s)",
            iBar, rsiVal, RSI_OversoldLevel, rsiOversold?"YES":"NO",
            closeVal, emaVal, aboveEMA?"YES":"NO",
            rollingMinLow, breakoutDown?"YES":"NO"));

   return (rsiOversold && aboveEMA && breakoutDown);
}

bool ProcessThisIterationDbg() { return false; } // set true for verbose debug

//===================================================================================
//  ProcessTradeOpens
//===================================================================================

void ProcessTradeOpens()
{
   //--- Guard: already at max trades
   if(CountOpenTrades() >= MaxOpenTrades) return;

   //--- Guard: spread too wide
   double spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double spreadPts = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   if(spreadPts > MaxSpreadPoints)
   {
      Print("ENTRY SKIPPED: Spread too wide (" + DoubleToString(spreadPts, 1) + " pts)");
      return;
   }

   //--- Check signal
   if(!IsSignalActive(iBarToUseForProcessing)) return;

   //--- Read ATR for SL/TP sizing
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(hATR, 0, 0, iBarToUseForProcessing + 2, atrBuffer) < 2) return;
   double atrVal = atrBuffer[iBarToUseForProcessing];
   if(atrVal <= 0) return;

   double askPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double slPrice  = NormalizeDouble(askPrice - SL_ATR_Multiplier * atrVal,
                                     (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
   double tpPrice  = NormalizeDouble(askPrice + TP_ATR_Multiplier * atrVal,
                                     (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = Symbol();
   req.volume    = LotSize;
   req.type      = ORDER_TYPE_BUY;
   req.price     = askPrice;
   req.sl        = slPrice;
   req.tp        = tpPrice;
   req.deviation = 10;
   req.magic     = MagicNumber;
   req.comment   = "RSI7+EMA200+BrkDn";
   req.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(req, res))
      Print("OrderSend FAILED: " + IntegerToString(res.retcode) + " | " + res.comment);
   else
      Print(StringFormat("BUY OPENED | Ticket=%I64u | Ask=%.5f | SL=%.5f | TP=%.5f | ATR=%.5f",
            res.order, askPrice, slPrice, tpPrice, atrVal));
}

//===================================================================================
//  ProcessTradeClosures  — time-based exit (MaxBarsInTrade)
//===================================================================================

void ProcessTradeClosures()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != Symbol())      continue;
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE)   != POSITION_TYPE_BUY) continue;

      //--- Count how many Trade-TF bars have passed since entry
      datetime openTime   = (datetime)PositionGetInteger(POSITION_TIME);
      datetime currentBar = iTime(Symbol(), TradeTimeframe, 0);
      int barsPassed      = Bars(Symbol(), TradeTimeframe, openTime, currentBar) - 1;

      if(barsPassed >= MaxBarsInTrade)
      {
         MqlTradeRequest req = {};
         MqlTradeResult  res = {};
         req.action   = TRADE_ACTION_DEAL;
         req.symbol   = Symbol();
         req.volume   = PositionGetDouble(POSITION_VOLUME);
         req.type     = ORDER_TYPE_SELL;
         req.price    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         req.deviation = 10;
         req.magic    = MagicNumber;
         req.position = ticket;
         req.comment  = "TimeExit";
         req.type_filling = ORDER_FILLING_IOC;

         if(!OrderSend(req, res))
            Print("Close FAILED: " + IntegerToString(res.retcode));
         else
            Print("TIME-EXIT | Ticket=" + IntegerToString((int)ticket) +
                  " | BarsPassed=" + IntegerToString(barsPassed));
      }
   }
}

//===================================================================================
//  HELPERS
//===================================================================================

int CountOpenTrades()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
         count++;
   }
   return count;
}

//===================================================================================
//  OutputStatusToScreen
//===================================================================================

void OutputStatusToScreen()
{
   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   string txt = "\n\r";
   txt += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
          " (UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   txt += "═══ STRATEGY: RSI7 Oversold + EMA200 + Breakout-Down Reversal ═══\n\r\n\r";

   txt += Symbol() + " TICKS RECEIVED:    " + IntegerToString(TicksReceivedCount)  + "\n\r";
   txt += Symbol() + " TICKS PROCESSED:   " + IntegerToString(TicksProcessedCount) + "\n\r";
   txt += "PROCESSING METHOD:  " + EnumToString(BarProcessingMethod) + "\n\r";
   txt += "BAR USED:           " + IntegerToString(iBarToUseForProcessing) + "\n\r";
   txt += "SYMBOL:             " + Symbol() + "\n\r";
   txt += "TRADING TF:         " + EnumToString(TradeTimeframe) + "\n\r\n\r";

   txt += "═══ SIGNAL PARAMETERS ═══\n\r";
   txt += "RSI Period:         " + IntegerToString(RSI_Period)         + "\n\r";
   txt += "RSI Oversold Level: " + DoubleToString(RSI_OversoldLevel,1) + "\n\r";
   txt += "EMA Period:         " + IntegerToString(EMA_Period)         + "\n\r";
   txt += "Breakout Lookback:  " + IntegerToString(Breakout_Lookback)  + " bars\n\r\n\r";

   txt += "═══ TRADE MANAGEMENT ═══\n\r";
   txt += "Lot Size:           " + DoubleToString(LotSize, 2)               + "\n\r";
   txt += "SL Multiplier:      " + DoubleToString(SL_ATR_Multiplier, 2)     + "x ATR\n\r";
   txt += "TP Multiplier:      " + DoubleToString(TP_ATR_Multiplier, 2)     + "x ATR (signal mag)\n\r";
   txt += "Max Bars in Trade:  " + IntegerToString(MaxBarsInTrade)           + "\n\r";
   txt += "Open Trades Now:    " + IntegerToString(CountOpenTrades())         + " / " + IntegerToString(MaxOpenTrades) + "\n\r";

   Comment(txt);
}