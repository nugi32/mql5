//+--------------------------------------------------------------------------------+
//| rsi20-orderblockbear-ea.mq5                                                    |
//|                                                                                |
//| Implements a single mined rule:                                                |
//|   RULE: RSI_below_20  AND  order_block_bear                                    |
//|   -> Historically BULLISH 58.2% of the time (report: mag_atr_mean 0.1556,      |
//|      persistence 0.83, lift 30.23, STABLE across train/val/OOS)                |
//|                                                                                |
//| Rule definitions (ported from the Python feature-engineering source):          |
//|                                                                                |
//|   RSI_below_20:                                                                |
//|     RSI_14 (Wilder-smoothed, standard iRSI) at the last CLOSED bar < 20        |
//|                                                                                |
//|   order_block_bear (from compute_market_structure()):                         |
//|     order_block_bear_raw[i] = (Close[i] < Open[i]) AND                         |
//|                               strong_move[i+1]                                 |
//|     strong_move[i] = |Close[i]-Open[i]| > ATR_14[i]                            |
//|     order_block_bear[i] = order_block_bear_raw[i-1]   (shifted +1 bar so it    |
//|         only appears once confirmable, i.e. once bar i+1 has actually closed)  |
//|                                                                                |
//|     In MT5 shift-indexing (0=forming bar, 1=last closed, 2=bar before that):   |
//|     order_block_bear confirmed AT shift 1  <=>                                 |
//|         Close[2] < Open[2]                         (bar at shift 2 is bearish)|
//|         AND  |Close[1]-Open[1]| > ATR_14[1]         (bar at shift 1 is a       |
//|                                                       strong move, confirmed   |
//|                                                       now that shift 1 closed) |
//|                                                                                |
//| Trading rule: on a new confirmed bar, if RSI_below_20 AND order_block_bear     |
//| both true at shift 1 -> open a BUY (dominant historical direction), fixed     |
//| lot size, NO broker SL/TP. Position closed after HoldBars closed bars.         |
//|                                                                                |
//| Bar-processing control block adapted from the user-supplied framework file    |
//| control-bar-opening-single-symbol.mq5.                                        |
//+--------------------------------------------------------------------------------+

#property strict
#include <Trade\Trade.mqh>

enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               //Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        //Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   //Only Process Ticks From New Bar in Trade TF
};

//################
// Input Variables
//################

input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;                          //Trading Timeframe (must match the TF the rule was mined on)
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR; //EA Bar Processing Method (recommended: only closed bars, since the rule needs confirmed data)

input int      RSI_Period     = 14;      //RSI period (matches RSI_14 in the rule)
input double   RSI_Threshold  = 20.0;    //RSI must be BELOW this value
input int      ATR_Period     = 14;      //ATR period used for the "strong move" test in order_block_bear

input int      HoldBars       = 5;       //Bars to hold the trade before closing (time-based exit -- ADJUST AS NEEDED)
input double   LotSize        = 0.01;    //Fixed lot size per trade -- ADJUST AS NEEDED

input ulong    MagicNumber    = 20260723;  //Magic number for this EA's trades
input string   TradeComment   = "RSI20_OrderBlockBear";

//################
//Global Variables
//################

CTrade   trade;

int      TicksReceivedCount      = 0;
int      TicksProcessedCount     = 0;
datetime TimeLastTickProcessed   = D'1971.01.01 00:00';

int      iBarToUseForProcessing;

int      RSI_Handle = INVALID_HANDLE;
int      ATR_Handle = INVALID_HANDLE;

int OnInit()
{
   //################################
   //Determine which bar we will used (0 or 1) to perform processing of data
   //################################

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;

   Print("EA USING " + EnumToString(BarProcessingMethod) + " PROCESSING METHOD AND INDICATORS WILL USE BAR " + IntegerToString(iBarToUseForProcessing));

   if(iBarToUseForProcessing == 0)
      Print("WARNING: this EA's rule (order_block_bear) is only confirmable on a CLOSED bar. Using bar 0 means the signal will be evaluated against a bar that can still repaint. ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR is recommended.");

   RSI_Handle = iRSI(Symbol(), TradeTimeframe, RSI_Period, PRICE_CLOSE);
   ATR_Handle = iATR(Symbol(), TradeTimeframe, ATR_Period);

   if(RSI_Handle == INVALID_HANDLE || ATR_Handle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);

   OutputStatusToScreen();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(RSI_Handle != INVALID_HANDLE) IndicatorRelease(RSI_Handle);
   if(ATR_Handle != INVALID_HANDLE) IndicatorRelease(ATR_Handle);
   Comment("");
}

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

   //#############################
   //Process Trades if appropriate
   //#############################

   if(ProcessThisIteration == true)
   {
      TicksProcessedCount++;

      ProcessTradeClosures();
      ProcessTradeOpens();
   }

   OutputStatusToScreen();
}

//+------------------------------------------------------------------+
//| Checks all open positions belonging to this EA/symbol/magic and  |
//| closes any that have been open for >= HoldBars closed bars.      |
//+------------------------------------------------------------------+
void ProcessTradeClosures()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      int barsSinceOpen = iBarShift(Symbol(), TradeTimeframe, openTime, false);
      // barsSinceOpen counts how many closed bars separate 'now' from the bar the
      // position was opened on. Once it reaches HoldBars, close the position.

      if(barsSinceOpen >= HoldBars)
      {
         trade.PositionClose(ticket);
         if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
            Print("Failed to close position #", ticket, " retcode=", trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
//| Evaluates the rule on the last CLOSED bar and opens a BUY (no    |
//| SL/TP) if it fires and there is no existing position for this EA.|
//+------------------------------------------------------------------+
void ProcessTradeOpens()
{
   if(HasOpenPosition())
      return; // one rule, one trade at a time

   if(!CheckRule())
      return;

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double sl = 0.0;   // no broker SL, per requirement
   double tp = 0.0;   // no broker TP, per requirement

   bool ok = trade.Buy(LotSize, Symbol(), ask, sl, tp, TradeComment);
   if(!ok)
      Print("Buy order failed. retcode=", trade.ResultRetcode(), " error=", GetLastError());
   else
      Print("Rule fired -> BUY opened. Lots=", LotSize, " HoldBars=", HoldBars);
}

//+------------------------------------------------------------------+
//| True if this EA already has an open position on this symbol.     |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
         (long)PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| RULE: RSI_below_20 AND order_block_bear, both evaluated on the   |
//| last fully closed bar (shift 1), using shift 2 for the prior bar |
//| that order_block_bear needs.                                     |
//+------------------------------------------------------------------+
bool CheckRule()
{
   // Need bars at shift 1 and shift 2 to exist.
   if(Bars(Symbol(), TradeTimeframe) < 5)
      return false;

   double rsiBuf[];
   double atrBuf[];
   ArraySetAsSeries(rsiBuf, true);
   ArraySetAsSeries(atrBuf, true);

   if(CopyBuffer(RSI_Handle, 0, 0, 3, rsiBuf) < 3) return false;
   if(CopyBuffer(ATR_Handle, 0, 0, 3, atrBuf) < 3) return false;

   double open1  = iOpen(Symbol(), TradeTimeframe, 1);
   double close1 = iClose(Symbol(), TradeTimeframe, 1);
   double open2  = iOpen(Symbol(), TradeTimeframe, 2);
   double close2 = iClose(Symbol(), TradeTimeframe, 2);

   // --- RSI_below_20 ---
   bool rsiBelowThreshold = (rsiBuf[1] < RSI_Threshold);

   // --- order_block_bear ---
   // bar at shift 2 must be bearish
   bool priorBarBearish = (close2 < open2);
   // bar at shift 1 must be a "strong move": body size > ATR14 at shift 1
   double bodySize1 = MathAbs(close1 - open1);
   bool strongMove = (bodySize1 > atrBuf[1]);

   bool orderBlockBear = priorBarBearish && strongMove;

   return (rsiBelowThreshold && orderBlockBear);
}

void OutputStatusToScreen()
{
   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   string OutputText = "\n\r";

   OutputText += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " (OPERATING AT UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   OutputText += Symbol() + " TICKS RECEIVED:   " + IntegerToString(TicksReceivedCount) + "\n\r";
   OutputText += Symbol() + " TICKS PROCESSED:   " + IntegerToString(TicksProcessedCount) + "\n\r";
   OutputText += "PROCESSING METHOD:   " + EnumToString(BarProcessingMethod) + "\n\r";
   OutputText += EnumToString(TradeTimeframe) + " BAR USED FOR PROCESSING INDICATORS / PRICE:   " + IntegerToString(iBarToUseForProcessing) + "\n\r";
   OutputText += "RULE: RSI_" + IntegerToString(RSI_Period) + "_below_" + DoubleToString(RSI_Threshold,1) + " + order_block_bear (ATR_" + IntegerToString(ATR_Period) + ")\n\r";
   OutputText += "HOLD BARS: " + IntegerToString(HoldBars) + "   LOT SIZE: " + DoubleToString(LotSize,2) + "   NO BROKER SL/TP\n\r";
   OutputText += "HAS OPEN POSITION: " + (HasOpenPosition() ? "YES" : "NO") + "\n\r\n\r";

   Comment(OutputText);

   return;
}