//+--------------------------------------------------------------------------------+
//| squeeze-bullish-pattern-ea.mq5                                                  |
//|                                                                                  |
//| Implements the pattern from the report:                                        |
//|   SMA21_above_EMA21 + squeeze_active + Close_below_BB_lower_20_2                |
//|   -> Historically BULLISH 61.5% of the time, avg move ~1.51 ATR                 |
//|                                                                                  |
//| Bar-processing framework reused/adapted from control-bar-opening-single-symbol  |
//|                                                                                  |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                             |
//| THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. TRADING       |
//| INVOLVES RISK OF LOSS. BACKTEST AND FORWARD-TEST THOROUGHLY BEFORE USE ON A    |
//| LIVE ACCOUNT. THE AUTHOR ACCEPTS NO LIABILITY FOR ANY LOSSES INCURRED.         |
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property link        ""
#property description "Bollinger/Keltner squeeze + SMA21>EMA21 + Close<BB_lower bullish pattern EA"
#property strict

#include <Trade\Trade.mqh>

//################
// Enums
//################

enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               //Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        //Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   //Only Process Ticks From New Bar in Trade TF
};

//################
// Input Variables
//################

input ENUM_TIMEFRAMES            TradeTimeframe        = PERIOD_M15;                          //Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod   = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR; //EA Bar Processing Method

input group "=== Pattern Parameters ==="
input int    SMA_Period            = 21;      //SMA Period (SMA21_above_EMA21)
input int    EMA_Period             = 21;      //EMA Period (SMA21_above_EMA21)
input int    BB_Period              = 20;      //Bollinger Bands Period
input double BB_Deviation           = 2.0;     //Bollinger Bands Std Dev Multiplier
input int    KC_EMA_Period          = 20;      //Keltner Channel EMA (basis) Period
input int    ATR_Period             = 20;      //ATR Period (used for Keltner width + SL/TP)
input double KC_ATR_Multiplier      = 2.0;     //Keltner Channel ATR Multiplier

input group "=== Trade Management (VIRTUAL SL/TP ONLY - no broker-side stops sent) ==="
input double LotSize                = 0.10;    //Fixed Lot Size
input double SL_ATR_Multiplier      = 1.5;     //Virtual Stop Loss, in multiples of ATR
input double TP_ATR_Multiplier      = 1.51;    //Virtual Take Profit, in multiples of ATR (per report: avg move ~1.51 ATR)
input int    MagicNumber            = 20260724; //Magic Number
input int    ExitAfterXCandles      = 2;        //Force-close after X candles (report: Timing~1.39, Persistence~1.26 candles -> rounded up)

//################
// Global Variables
//################

int      TicksReceivedCount    = 0;
int      TicksProcessedCount   = 0;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';

int      iBarToUseForProcessing;   // 0 = current forming bar, 1 = last completed bar

int      handleSMA;
int      handleEMA;
int      handleKcEma;
int      handleBB;
int      handleATR;

CTrade   trade;

//################
// Virtual SL / TP tracking (NO broker-side stops are ever sent)
//################

bool     gPositionActive  = false; //True while we are virtually managing an open position
ulong    gManagedTicket   = 0;     //Ticket of the position we are virtually managing
double   gVirtualSL       = 0.0;   //Virtual stop-loss price (checked in code, NEVER sent to the broker)
double   gVirtualTP       = 0.0;   //Virtual take-profit price (checked in code, NEVER sent to the broker)
datetime gEntryBarTime    = 0;     //Time of the bar on which the position was opened (used for the X-candle timeout)

//+------------------------------------------------------------------------------+
//| OnInit                                                                        |
//+------------------------------------------------------------------------------+
int OnInit()
{
   //################################
   //Determine which bar to use for processing (0 or 1), mirrors the base framework
   //################################

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;   //Use last completed bar so indicator values don't repaint

   Print("EA USING " + EnumToString(BarProcessingMethod) + " PROCESSING METHOD AND INDICATORS WILL USE BAR " + IntegerToString(iBarToUseForProcessing));

   //################################
   //Create indicator handles
   //################################

   handleSMA   = iMA(Symbol(), TradeTimeframe, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   handleEMA   = iMA(Symbol(), TradeTimeframe, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleKcEma = iMA(Symbol(), TradeTimeframe, KC_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleBB    = iBands(Symbol(), TradeTimeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   handleATR   = iATR(Symbol(), TradeTimeframe, ATR_Period);

   if(handleSMA == INVALID_HANDLE || handleEMA == INVALID_HANDLE || handleKcEma == INVALID_HANDLE ||
      handleBB == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("FAILED TO CREATE ONE OR MORE INDICATOR HANDLES");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);

   OutputStatusToScreen();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------------------+
//| OnDeinit                                                                      |
//+------------------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleSMA);
   IndicatorRelease(handleEMA);
   IndicatorRelease(handleKcEma);
   IndicatorRelease(handleBB);
   IndicatorRelease(handleATR);

   Comment("");
}

//+------------------------------------------------------------------------------+
//| OnTick                                                                        |
//+------------------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

   //########################################################
   //Control EA so that we only process at required intervals
   //########################################################

   bool ProcessThisIteration = false;

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      ProcessThisIteration = true;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), PERIOD_M1, 0))
      {
         ProcessThisIteration = true;
         TimeLastTickProcessed = iTime(Symbol(), PERIOD_M1, 0);
      }
   }

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), TradeTimeframe, 0))
      {
         ProcessThisIteration = true;
         TimeLastTickProcessed = iTime(Symbol(), TradeTimeframe, 0);
      }
   }

   //#############################################################
   //Virtual SL/TP and candle-timeout are checked on EVERY tick,
   //because price can hit a virtual level intra-bar - no broker
   //SL/TP is ever attached to the order, so nothing but this code
   //will ever close the position for those reasons.
   //#############################################################

   ManageVirtualExits();

   //#############################
   //Process Trades if appropriate
   //#############################

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;

      ProcessTradeOpens();
   }

   OutputStatusToScreen();
}

//+------------------------------------------------------------------------------+
//| Pull all indicator values needed for one bar into a small struct             |
//+------------------------------------------------------------------------------+
struct PatternValues
{
   double sma;
   double ema;
   double bbUpper;
   double bbLower;
   double kcUpper;
   double kcLower;
   double atr;
   double close;
   bool   squeeze;
   bool   valid;
};

bool GetPatternValues(int shift, PatternValues &v)
{
   double bufSMA[1], bufEMA[1], bufKcEma[1], bufBBUpper[1], bufBBLower[1], bufATR[1];

   if(CopyBuffer(handleSMA, 0, shift, 1, bufSMA) != 1)      return(false);
   if(CopyBuffer(handleEMA, 0, shift, 1, bufEMA) != 1)      return(false);
   if(CopyBuffer(handleKcEma, 0, shift, 1, bufKcEma) != 1)  return(false);
   if(CopyBuffer(handleBB, 1, shift, 1, bufBBUpper) != 1)   return(false); //upper band buffer
   if(CopyBuffer(handleBB, 2, shift, 1, bufBBLower) != 1)   return(false); //lower band buffer
   if(CopyBuffer(handleATR, 0, shift, 1, bufATR) != 1)      return(false);

   double closeArr[1];
   if(CopyClose(Symbol(), TradeTimeframe, shift, 1, closeArr) != 1) return(false);

   v.sma     = bufSMA[0];
   v.ema     = bufEMA[0];
   v.atr     = bufATR[0];
   v.bbUpper = bufBBUpper[0];
   v.bbLower = bufBBLower[0];
   v.kcUpper = bufKcEma[0] + KC_ATR_Multiplier * v.atr;
   v.kcLower = bufKcEma[0] - KC_ATR_Multiplier * v.atr;
   v.close   = closeArr[0];
   v.squeeze = (v.bbUpper < v.kcUpper) && (v.bbLower > v.kcLower);
   v.valid   = true;

   return(true);
}

//+------------------------------------------------------------------------------+
//| Check for an existing open position on this symbol with our magic number     |
//+------------------------------------------------------------------------------+
bool HasOpenPosition()
{
   return(FindManagedPositionTicket() != 0);
}

//+------------------------------------------------------------------------------+
//| Find the ticket of our own open position on this symbol/magic (if any)       |
//+------------------------------------------------------------------------------+
ulong FindManagedPositionTicket()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return(ticket);
   }
   return(0);
}

//+------------------------------------------------------------------------------+
//| ProcessTradeOpens - fires the pattern from the report                        |
//+------------------------------------------------------------------------------+
void ProcessTradeOpens()
{
   if(HasOpenPosition())
      return; //One position at a time for this pattern/magic

   PatternValues v;
   if(!GetPatternValues(iBarToUseForProcessing, v))
   {
      Print("COULD NOT RETRIEVE INDICATOR VALUES FOR PATTERN CHECK");
      return;
   }

   //################################################################
   // Pattern: SMA21_above_EMA21 + squeeze_active + Close_below_BB_lower_20_2
   // -> Historically bullish 61.5% of the time, avg move ~1.51 ATR (report #2)
   //################################################################

   bool smaAboveEma      = v.sma > v.ema;
   bool squeezeActive    = v.squeeze;
   bool closeBelowBBLow  = v.close < v.bbLower;

   bool patternTriggered = smaAboveEma && squeezeActive && closeBelowBBLow;

   if(patternTriggered)
   {
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

      //Virtual levels only - computed here but NEVER passed to trade.Buy(), so the
      //broker sees a plain market order with no stops attached at all.
      double virtualSL = NormalizeDouble(ask - SL_ATR_Multiplier * v.atr, _Digits);
      double virtualTP = NormalizeDouble(ask + TP_ATR_Multiplier * v.atr, _Digits);

      string comment = "SMA21>EMA21+Squeeze+CloseBelowBBLower";

      if(trade.Buy(LotSize, Symbol(), ask, 0.0, 0.0, comment))   //sl=0, tp=0 -> no broker-side stops
      {
         gManagedTicket  = FindManagedPositionTicket();
         gPositionActive = (gManagedTicket != 0);
         gVirtualSL      = virtualSL;
         gVirtualTP      = virtualTP;
         gEntryBarTime   = iTime(Symbol(), TradeTimeframe, 0);   //bar on which the trade was opened

         Print("BUY OPENED ON PATTERN MATCH (VIRTUAL SL=" + DoubleToString(virtualSL, _Digits) +
               " VIRTUAL TP=" + DoubleToString(virtualTP, _Digits) +
               ", MAX HOLD=" + IntegerToString(ExitAfterXCandles) + " CANDLES) | Close=" +
               DoubleToString(v.close, _Digits) + " BB_Lower=" + DoubleToString(v.bbLower, _Digits) +
               " ATR=" + DoubleToString(v.atr, _Digits));
      }
      else
         Print("BUY ORDER FAILED: " + IntegerToString(trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------------------+
//| ManageVirtualExits - the ONLY place a position gets closed.                  |
//| Runs every tick. No broker SL/TP exists on the order at all, so every exit   |
//| (stop, target, or timeout) is decided and executed here, in code.            |
//+------------------------------------------------------------------------------+
void ManageVirtualExits()
{
   //Resync in case the position was closed manually / by margin call / etc.
   if(gPositionActive && !PositionSelectByTicket(gManagedTicket))
   {
      gPositionActive = false;
      gManagedTicket  = 0;
      return;
   }

   if(!gPositionActive)
      return;

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   //1) Virtual Take Profit
   if(bid >= gVirtualTP)
   {
      trade.PositionClose(gManagedTicket);
      Print("VIRTUAL TP HIT - CLOSED TICKET " + IntegerToString(gManagedTicket) +
            " | Bid=" + DoubleToString(bid, _Digits) + " VirtualTP=" + DoubleToString(gVirtualTP, _Digits));
      ResetManagedState();
      return;
   }

   //2) Virtual Stop Loss
   if(bid <= gVirtualSL)
   {
      trade.PositionClose(gManagedTicket);
      Print("VIRTUAL SL HIT - CLOSED TICKET " + IntegerToString(gManagedTicket) +
            " | Bid=" + DoubleToString(bid, _Digits) + " VirtualSL=" + DoubleToString(gVirtualSL, _Digits));
      ResetManagedState();
      return;
   }

   //3) Candle-count timeout, per the report's Timing (~1.39 candles) and
   //   Persistence (~1.26 candles) stats - the edge is short-lived, so the
   //   position is force-closed after ExitAfterXCandles completed candles
   //   regardless of where price is, win or lose.
   int barsSinceEntry = iBarShift(Symbol(), TradeTimeframe, gEntryBarTime, false);
   if(barsSinceEntry >= ExitAfterXCandles)
   {
      trade.PositionClose(gManagedTicket);
      Print("CANDLE TIMEOUT (" + IntegerToString(barsSinceEntry) + "/" + IntegerToString(ExitAfterXCandles) +
            ") - CLOSED TICKET " + IntegerToString(gManagedTicket));
      ResetManagedState();
      return;
   }
}

//+------------------------------------------------------------------------------+
//| ResetManagedState                                                             |
//+------------------------------------------------------------------------------+
void ResetManagedState()
{
   gPositionActive = false;
   gManagedTicket  = 0;
   gVirtualSL      = 0.0;
   gVirtualTP      = 0.0;
   gEntryBarTime   = 0;
}

//+------------------------------------------------------------------------------+
//| OutputStatusToScreen                                                          |
//+------------------------------------------------------------------------------+
void OutputStatusToScreen()
{
   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   PatternValues v;
   bool haveVals = GetPatternValues(iBarToUseForProcessing, v);

   string OutputText = "\n\r";

   OutputText += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
                 " (OPERATING AT UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   OutputText += Symbol() + " TICKS RECEIVED:   " + IntegerToString(TicksReceivedCount) + "\n\r";
   OutputText += Symbol() + " TICKS PROCESSED:  " + IntegerToString(TicksProcessedCount) + "\n\r";
   OutputText += "PROCESSING METHOD:            " + EnumToString(BarProcessingMethod) + "\n\r";
   OutputText += EnumToString(TradeTimeframe) + " BAR USED FOR PROCESSING:  " + IntegerToString(iBarToUseForProcessing) + "\n\r";
   OutputText += "SYMBOL BEING TRADED:          " + Symbol() + "\n\r";
   OutputText += "TRADING TIMEFRAME:            " + EnumToString(TradeTimeframe) + "\n\r\n\r";

   if(haveVals)
   {
      OutputText += "--- PATTERN STATE (report #2) ---\n\r";
      OutputText += "SMA" + IntegerToString(SMA_Period) + ": " + DoubleToString(v.sma, _Digits) +
                    "   EMA" + IntegerToString(EMA_Period) + ": " + DoubleToString(v.ema, _Digits) +
                    "   SMA>EMA: " + (v.sma > v.ema ? "YES" : "no") + "\n\r";
      OutputText += "BB_UPPER: " + DoubleToString(v.bbUpper, _Digits) +
                    "   BB_LOWER: " + DoubleToString(v.bbLower, _Digits) + "\n\r";
      OutputText += "KC_UPPER: " + DoubleToString(v.kcUpper, _Digits) +
                    "   KC_LOWER: " + DoubleToString(v.kcLower, _Digits) + "\n\r";
      OutputText += "SQUEEZE ACTIVE: " + (v.squeeze ? "YES" : "no") + "\n\r";
      OutputText += "CLOSE: " + DoubleToString(v.close, _Digits) +
                    "   CLOSE<BB_LOWER: " + (v.close < v.bbLower ? "YES" : "no") + "\n\r";
      OutputText += "PATTERN TRIGGERED THIS BAR: " +
                    ((v.sma > v.ema && v.squeeze && v.close < v.bbLower) ? "YES" : "no") + "\n\r\n\r";
   }

   OutputText += "--- VIRTUAL POSITION MANAGEMENT (no broker SL/TP sent) ---\n\r";
   if(gPositionActive)
   {
      int barsSinceEntry = iBarShift(Symbol(), TradeTimeframe, gEntryBarTime, false);
      OutputText += "MANAGED TICKET:   " + IntegerToString(gManagedTicket) + "\n\r";
      OutputText += "VIRTUAL SL:       " + DoubleToString(gVirtualSL, _Digits) + "\n\r";
      OutputText += "VIRTUAL TP:       " + DoubleToString(gVirtualTP, _Digits) + "\n\r";
      OutputText += "CANDLES HELD:     " + IntegerToString(barsSinceEntry) + " / " + IntegerToString(ExitAfterXCandles) + "\n\r\n\r";
   }
   else
      OutputText += "NO POSITION CURRENTLY MANAGED\n\r\n\r";

   Comment(OutputText);

   return;
}