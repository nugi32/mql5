//+--------------------------------------------------------------------------------+
//| signal-pattern-01-ea.mq5                                                       |
//|                                                                                |
//| Built on the "control-bar-opening-single-symbol" framework.                    |
//| Trades the single confluence pattern from the report:                         |
//|   SMA21_above_EMA21 + squeeze_active + STO_K14_cross_below_D +                 |
//|   Close_below_BB_lower_20_2  ->  Historically BULLISH 62.2% of the time        |
//|   (avg move 1.50 ATR, STABLE across train/val/oos splits)                      |
//|                                                                                |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                             |
//| THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"    |
//| AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE      |
//| IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE |
//| DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE   |
//| FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL     |
//| DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE.                    |
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property link        ""
#property description "Trades SMA21>EMA21 + Squeeze + Stoch K/D cross below + Close<BB_lower (20,2) bullish setup. Fixed lot. No broker SL/TP."
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

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
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;                          //Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR;   //EA Bar Processing Method

input group "=== Signal Parameters (per report pattern) ==="
input int    SMA_Period    = 21;      //SMA period
input int    EMA_Period    = 21;      //EMA period
input int    BB_Period     = 20;      //Bollinger Bands period
input double BB_Deviation  = 2.0;     //Bollinger Bands deviation
input int    KC_Period     = 20;      //Keltner Channel MA/ATR period (used to define squeeze_active)
input double KC_ATR_Mult   = 1.5;     //Keltner Channel ATR multiplier
input int    Stoch_K       = 14;      //Stochastic %K period
input int    Stoch_D       = 3;       //Stochastic %D period
input int    Stoch_Slowing = 3;       //Stochastic slowing

input group "=== Trade Settings ==="
input double FixedLotSize  = 0.10;                       //Fixed lot size (no risk-based sizing)
input int    MagicNumber   = 20260721;                    //Magic number
input string TradeComment  = "SMA21EMA21_Squeeze_StochBB"; //Order comment
input bool   OnlyOnePositionAtATime = true;                //Block new entries while a position from this EA is open
input int    CloseAfterXCandles     = 5;                   //Force-close the position after this many closed candles on TradeTimeframe (0 = disabled)

//################
// Global Variables
//################
int      TicksReceivedCount    = 0;                     //Number of ticks received by the EA
int      TicksProcessedCount   = 0;                     //Number of ticks processed by the EA
int      SignalsDetectedCount  = 0;                     //Number of times the full pattern fired
int      TradesOpenedCount     = 0;                     //Number of buy orders sent
datetime TimeLastTickProcessed = D'1971.01.01 00:00';   //Controls processing interval

int      iBarToUseForProcessing;   //Bar 0 or 1, set in OnInit(), same logic as the base framework

//--- indicator handles
int hSMA, hEMA, hBB, hStoch, hKC_MA, hATR;

//--- last evaluated condition snapshot (for on-screen reporting only)
bool   Last_SMA_above_EMA      = false;
bool   Last_Squeeze_active     = false;
bool   Last_Stoch_cross_below  = false;
bool   Last_Close_below_BBLow  = false;
bool   Last_Signal_fired       = false;
datetime Last_Eval_Time        = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   //################################
   //Determine which bar we will use (0 or 1) - identical logic to the base framework
   //################################
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;

   //--- create indicator handles on the trading timeframe
   hSMA   = iMA(Symbol(), TradeTimeframe, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   hEMA   = iMA(Symbol(), TradeTimeframe, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hBB    = iBands(Symbol(), TradeTimeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   hStoch = iStochastic(Symbol(), TradeTimeframe, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   hKC_MA = iMA(Symbol(), TradeTimeframe, KC_Period, 0, MODE_EMA, PRICE_TYPICAL); //Keltner midline
   hATR   = iATR(Symbol(), TradeTimeframe, KC_Period);                           //Keltner width

   if(hSMA==INVALID_HANDLE || hEMA==INVALID_HANDLE || hBB==INVALID_HANDLE ||
      hStoch==INVALID_HANDLE || hKC_MA==INVALID_HANDLE || hATR==INVALID_HANDLE)
   {
      Print("ERROR: Failed to create one or more indicator handles");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);

   Print("EA USING " + EnumToString(BarProcessingMethod) + " PROCESSING METHOD AND INDICATORS WILL USE BAR " + IntegerToString(iBarToUseForProcessing));

   OutputStatusToScreen();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hSMA   != INVALID_HANDLE) IndicatorRelease(hSMA);
   if(hEMA   != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hBB    != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hStoch != INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hKC_MA != INVALID_HANDLE) IndicatorRelease(hKC_MA);
   if(hATR   != INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

   //########################################################
   //Control EA so that we only process at required intervals - identical to base framework
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
   //Process signal + trade if appropriate
   //#############################
   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      CheckTimedExit();
      ProcessSignalAndTrade();
   }

   OutputStatusToScreen();
}

//+------------------------------------------------------------------+
//| Reads all indicator buffers needed to evaluate the pattern        |
//+------------------------------------------------------------------+
bool GetSignalConditions(bool &sma_above_ema, bool &squeeze_active,
                          bool &stoch_cross_below, bool &close_below_bb_lower)
{
   int barsNeeded = iBarToUseForProcessing + 2;   //need current + previous bar for the cross check

   double smaBuf[], emaBuf[], bbUpperBuf[], bbLowerBuf[];
   double stochKBuf[], stochDBuf[], kcMaBuf[], atrBuf[];

   if(CopyBuffer(hSMA,   0, 0, barsNeeded, smaBuf)     < barsNeeded) return false;
   if(CopyBuffer(hEMA,   0, 0, barsNeeded, emaBuf)     < barsNeeded) return false;
   if(CopyBuffer(hBB,    1, 0, barsNeeded, bbUpperBuf) < barsNeeded) return false; //upper band
   if(CopyBuffer(hBB,    2, 0, barsNeeded, bbLowerBuf) < barsNeeded) return false; //lower band
   if(CopyBuffer(hStoch, 0, 0, barsNeeded, stochKBuf)  < barsNeeded) return false; //%K
   if(CopyBuffer(hStoch, 1, 0, barsNeeded, stochDBuf)  < barsNeeded) return false; //%D
   if(CopyBuffer(hKC_MA, 0, 0, barsNeeded, kcMaBuf)    < barsNeeded) return false;
   if(CopyBuffer(hATR,   0, 0, barsNeeded, atrBuf)     < barsNeeded) return false;

   ArraySetAsSeries(smaBuf,     true);
   ArraySetAsSeries(emaBuf,     true);
   ArraySetAsSeries(bbUpperBuf, true);
   ArraySetAsSeries(bbLowerBuf, true);
   ArraySetAsSeries(stochKBuf,  true);
   ArraySetAsSeries(stochDBuf,  true);
   ArraySetAsSeries(kcMaBuf,    true);
   ArraySetAsSeries(atrBuf,     true);

   int bar     = iBarToUseForProcessing;
   int barPrev = bar + 1;

   double closeCur = iClose(Symbol(), TradeTimeframe, bar);

   //--- SMA21_above_EMA21
   sma_above_ema = (smaBuf[bar] > emaBuf[bar]);

   //--- squeeze_active : classic TTM-style squeeze, Bollinger Bands inside Keltner Channel
   double kcUpperCur = kcMaBuf[bar] + KC_ATR_Mult * atrBuf[bar];
   double kcLowerCur = kcMaBuf[bar] - KC_ATR_Mult * atrBuf[bar];
   squeeze_active = (bbUpperBuf[bar] < kcUpperCur) && (bbLowerBuf[bar] > kcLowerCur);

   //--- STO_K14_cross_below_D : %K was above %D on the previous bar, at/below %D on the current bar
   stoch_cross_below = (stochKBuf[barPrev] > stochDBuf[barPrev]) && (stochKBuf[bar] <= stochDBuf[bar]);

   //--- Close_below_BB_lower_20_2
   close_below_bb_lower = (closeCur < bbLowerBuf[bar]);

   return true;
}

//+------------------------------------------------------------------+
//| Evaluates the pattern and opens a fixed-lot buy with no SL/TP     |
//+------------------------------------------------------------------+
void ProcessSignalAndTrade()
{
   bool sma_above_ema=false, squeeze_active=false, stoch_cross_below=false, close_below_bb_lower=false;

   if(!GetSignalConditions(sma_above_ema, squeeze_active, stoch_cross_below, close_below_bb_lower))
   {
      Print("Not enough bar/indicator history yet to evaluate the pattern.");
      return;
   }

   Last_SMA_above_EMA     = sma_above_ema;
   Last_Squeeze_active    = squeeze_active;
   Last_Stoch_cross_below = stoch_cross_below;
   Last_Close_below_BBLow = close_below_bb_lower;
   Last_Eval_Time         = iTime(Symbol(), TradeTimeframe, iBarToUseForProcessing);

   bool signalFired = sma_above_ema && squeeze_active && stoch_cross_below && close_below_bb_lower;
   Last_Signal_fired = signalFired;

   if(!signalFired)
      return;

   SignalsDetectedCount++;

   if(OnlyOnePositionAtATime && HasOpenPosition())
   {
      Print("Signal fired but an EA position is already open on " + Symbol() + " - skipping.");
      return;
   }

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   //--- Fixed lot, NO stop loss / take profit sent to the broker (sl=0, tp=0)
   if(trade.Buy(FixedLotSize, Symbol(), ask, 0.0, 0.0, TradeComment))
   {
      TradesOpenedCount++;
      Print("BUY opened: ", Symbol(), " lot=", DoubleToString(FixedLotSize,2),
            " @ ", DoubleToString(ask, _Digits), " (no SL/TP set)");
   }
   else
   {
      Print("BUY order failed. Error code: ", GetLastError(), " retcode: ", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Force-closes any EA position once it has lived through            |
//| CloseAfterXCandles closed bars on TradeTimeframe                  |
//+------------------------------------------------------------------+
void CheckTimedExit()
{
   if(CloseAfterXCandles <= 0)
      return;   //feature disabled

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != Symbol() ||
         PositionGetInteger(POSITION_MAGIC)  != MagicNumber)
         continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      //--- how many completed bars have passed since the bar the position opened on
      int openBarShift = iBarShift(Symbol(), TradeTimeframe, openTime, false);
      if(openBarShift < 0)
         continue; //couldn't resolve, skip this check for now

      int candlesElapsed = openBarShift;   //bar 0 = current forming bar, so this = fully-closed candles since entry

      if(candlesElapsed >= CloseAfterXCandles)
      {
         if(trade.PositionClose(ticket))
            Print("Position #", ticket, " closed after ", candlesElapsed, " candles (limit ", CloseAfterXCandles, ")");
         else
            Print("Failed to close position #", ticket, ". Error: ", GetLastError(), " retcode: ", trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void OutputStatusToScreen()
{
   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   string OutputText = "\n\r";

   OutputText += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
                 " (UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   OutputText += Symbol() + " TICKS RECEIVED:    " + IntegerToString(TicksReceivedCount) + "\n\r";
   OutputText += Symbol() + " TICKS PROCESSED:   " + IntegerToString(TicksProcessedCount) + "\n\r";
   OutputText += "PROCESSING METHOD:   " + EnumToString(BarProcessingMethod) + "\n\r";
   OutputText += EnumToString(TradeTimeframe) + " BAR USED FOR SIGNAL:   " + IntegerToString(iBarToUseForProcessing) + "\n\r";
   OutputText += "TRADING TIMEFRAME:   " + EnumToString(TradeTimeframe) + "\n\r";
   OutputText += "FIXED LOT SIZE:   " + DoubleToString(FixedLotSize,2) + "  |  SL/TP SENT TO BROKER: NONE\n\r";
   OutputText += "TIMED EXIT:   " + (CloseAfterXCandles > 0 ? ("close after " + IntegerToString(CloseAfterXCandles) + " candles") : "disabled") + "\n\r\n\r";

   OutputText += "--- PATTERN: SMA21>EMA21 + Squeeze + Stoch K-cross-below-D + Close<BB_lower(20,2) ---\n\r";
   OutputText += "Last evaluated bar time:   " + (Last_Eval_Time>0 ? TimeToString(Last_Eval_Time, TIME_DATE|TIME_MINUTES) : "n/a") + "\n\r";
   OutputText += "  SMA21_above_EMA21:        " + (Last_SMA_above_EMA     ? "TRUE" : "false") + "\n\r";
   OutputText += "  squeeze_active:           " + (Last_Squeeze_active    ? "TRUE" : "false") + "\n\r";
   OutputText += "  STO_K14_cross_below_D:    " + (Last_Stoch_cross_below ? "TRUE" : "false") + "\n\r";
   OutputText += "  Close_below_BB_lower:     " + (Last_Close_below_BBLow ? "TRUE" : "false") + "\n\r";
   OutputText += "  >>> FULL PATTERN FIRED:   " + (Last_Signal_fired      ? "YES"  : "no")   + "\n\r\n\r";

   OutputText += "Signals detected (this session):   " + IntegerToString(SignalsDetectedCount) + "\n\r";
   OutputText += "Trades opened (this session):      " + IntegerToString(TradesOpenedCount) + "\n\r\n\r";

   OutputText += "--- REPORT REFERENCE STATS (historical, from prior analysis) ---\n\r";
   OutputText += "Consistency Score: 0.6410   Match Count: 1348   Dominant Dir: BULLISH 62.2%\n\r";
   OutputText += "Mag ATR mean/std: 1.5022 / 0.7656 (CV 0.5097)   Timing: 1.39 candles   Persistence: 1.27\n\r";
   OutputText += "Frequency: 0.674%   Overfit Status: STABLE (train 60.6% / val 70.5% / oos 50.0%)\n\r";

   Comment(OutputText);
}
//+------------------------------------------------------------------+