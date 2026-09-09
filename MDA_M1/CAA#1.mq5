//+------------------------------------------------------------------------------------+
//| RSI_FVG_OrderBlock_RuleEA.mq5                                                      |
//|                                                                                    |
//| Trades the rule discovered by the market-dependency mining pipeline:               |
//|    RSI_below_30 + bear_fvg + order_block_bear  ->  BULLISH bias                    |
//|    (lift=16.27, direction%=56.1%, mag_atr_mean=0.15, CV=21.55, STABLE)             |
//|                                                                                    |
//| Split behavior is the best of the three rules mined so far -- direction% actually  |
//| IMPROVES across splits (train 55.5% -> val 57.0% -> oos 57.4%), unlike the RSI+    |
//| Stoch rule's val dip. Still: mag_cv=21.55 means any single trade's outcome is      |
//| still dominated by noise even though the average is favorably biased, and match    |
//| count (3848) over the mined history implies this fires rarely live.               |
//|                                                                                    |
//| EXIT MODEL: no SL/TP of any kind (virtual or broker). Position is closed purely on |
//| a timer -- exactly CandlesToHold completed bars after entry.                       |
//|                                                                                    |
//| *** UNRESOLVED FROM CODE REVIEW -- READ BEFORE LIVE/DEMO USE ***                   |
//| "Timing (candles) = 1.0" in the mining report is a HARDCODED CONSTANT in the       |
//| Python reporting code, written identically for every rule ever produced. It is     |
//| NOT the measured holding period. The actual number of candles over which           |
//| mag_atr_mean = 0.1484 was measured is whatever --horizon value was passed to the   |
//| specific run_rule_discovery call that generated this rule's report -- and that     |
//| value does not appear anywhere in the report output. CandlesToHold below is left   |
//| at 1 as a placeholder only; it has NOT been confirmed to match the mined horizon.  |
//| OnInit() below prints a loud warning every time this EA starts until this is fixed |
//| in the input by whoever deploys it. Get the real --horizon value from whoever ran  |
//| Stage 3 for this rule and set CandlesToHold to it before trusting any results.      |
//|                                                                                    |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                                 |
//| THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. TRADING FOREX/     |
//| CFDs CARRIES SUBSTANTIAL RISK OF LOSS. PAST STATISTICAL EDGE (INCLUDING OOS         |
//| VALIDATION) DOES NOT GUARANTEE FUTURE PERFORMANCE. WITH NO SL, ADVERSE MOVES ARE    |
//| HELD FOR THE FULL HOLDING PERIOD REGARDLESS OF SIZE.                                |
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property version     "1.01"
#property strict

#include <Trade\Trade.mqh>

//################
// Bar processing control (same pattern as control-bar-opening-single-symbol.mq5)
//################
enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               //Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        //Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   //Only Process Ticks From New Bar in Trade TF
};

//################
// Inputs
//################
input group "=== Bar Processing ==="
// FIX (code review): every rule-mining run in this pipeline was on M1 data
// (data/raw/XAUUSD1.csv). RSI/bear_fvg/order_block_bear computed on any other
// timeframe are different quantities than what was actually measured and tested.
// This MUST be PERIOD_M1 to reproduce the mined edge. If you want to test M15,
// that is a separate experiment requiring its own Stage 3 mining run on M15 data --
// this rule's stats (56.1% direction, 0.15 ATR average move, etc.) do not transfer.
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M1;                           //Trading Timeframe (MUST match mined data: M1)
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR; //EA Bar Processing Method

input group "=== Rule: RSI_below_30 + bear_fvg + order_block_bear (bullish) ==="
input int      RSI_Period           = 14;
input double   RSI_Threshold        = 30.0;    //RSI_below_30 in the mining report
input int      ATR_Period_Structure = 14;      //Used only to detect the order-block "strong move" (body > ATR)

input group "=== Exit: pure time-based, NO SL or TP of any kind ==="
// UNRESOLVED (code review): this is NOT confirmed to match the mined horizon.
// The report's "Timing (candles) = 1.0" is a hardcoded constant, not a measurement.
// Set this to the actual --horizon value used for this rule's Stage 3 run before
// trusting results. Left at 1 as a placeholder; OnInit() will warn until this
// input is deliberately acknowledged via ConfirmedHorizonValue below.
input int      CandlesToHold          = 1;       //Close the position after exactly this many completed candles (UNCONFIRMED -- see warning)
input bool     ConfirmedHorizonValue  = false;    //Set TRUE only after you've verified CandlesToHold against the actual --horizon used

input group "=== Trade / Money Management ==="
input double   LotSize              = 0.10;
input int      MagicNumber          = 20260726;
input int      MaxSlippagePoints    = 20;
input bool     OnePositionAtATime   = true;

input group "=== Risk safeguard (recommended given mag_cv=21.55) ==="
// The mining report's mag_cv = 21.5496 means the stdev of the move is ~21x the mean
// move. With no SL/TP of any kind, a single outlier adverse excursion is held for the
// full timed period regardless of size. This EA still defaults to no SL, matching the
// stated intent -- but if that was a simplification rather than a deliberate, sized
// decision, set UseEmergencySL true and pick a multiple of ATR you can live with.
// This does NOT change the mined statistics; it only caps tail risk on individual trades.
input bool     UseEmergencySL       = false;    //Optional: attach a wide ATR-multiple SL purely as a risk backstop (does not reflect the mined rule)
input double   EmergencySL_ATRMult  = 5.0;      //ATR multiple for the emergency SL, if enabled

input group "=== Logging ==="
input bool     LogTradesToCSV       = true;
input string   CSVFileName          = "RSI_FVG_OrderBlock_RuleEA_trades.csv";

//################
// Globals
//################
CTrade   trade;
int      hRSI, hATR;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;
int      TicksReceivedCount = 0;
int      TicksProcessedCount = 0;

//--- Position state. No SL/TP is ever attached to the broker order by default (see
//--- UseEmergencySL above for an optional risk backstop), and no virtual price-based
//--- exit is tracked either -- the primary exit condition is elapsed completed bars.
struct TimedPosition
{
   bool     active;
   ulong    ticket;
   datetime entryTime;
   double   entryPrice;
   int      barsHeld;
   double   entryRSI;
};
TimedPosition tpos;

int fileHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   //--- Determine which bar to read signals/indicators from (0 = still forming, 1 = last completed)
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;
   else //ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR
      iBarToUseForProcessing = 1;   //Use the last COMPLETED bar so structure detection can never change after the fact

   //--- Guard: this rule was only ever mined and validated on M1. Refuse to run on
   //--- anything else, since the boolean logic would then be evaluating a signal
   //--- that was never tested (per code review).
   if(TradeTimeframe != PERIOD_M1)
   {
      Print("ERROR: TradeTimeframe is ", EnumToString(TradeTimeframe),
            " but this rule was mined exclusively on M1 data. RSI/bear_fvg/order_block_bear ",
            "on any other timeframe are untested quantities. Set TradeTimeframe = PERIOD_M1, ",
            "or mine a fresh rule on your target timeframe first.");
      return(INIT_FAILED);
   }

   //--- Warn (does not block) on the unresolved holding-period question from the review.
   if(!ConfirmedHorizonValue)
   {
      Print("WARNING: CandlesToHold=", CandlesToHold, " has NOT been confirmed against the actual ",
            "--horizon value used when this rule was mined. The report's 'Timing (candles)=1.0' is a ",
            "hardcoded constant, not a measurement -- do not assume 1 is correct. Find the real horizon ",
            "used for this rule's Stage 3 run, set CandlesToHold accordingly, then set ",
            "ConfirmedHorizonValue=true to silence this warning. Trading will proceed, but the reported ",
            "stats (56.1% direction, 0.15 ATR average move) do not apply until this is fixed.");
   }

   hRSI = iRSI(Symbol(), TradeTimeframe, RSI_Period, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE)
   {
      Print("ERROR: failed to create iRSI handle, error=", GetLastError());
      return(INIT_FAILED);
   }

   hATR = iATR(Symbol(), TradeTimeframe, ATR_Period_Structure);
   if(hATR == INVALID_HANDLE)
   {
      Print("ERROR: failed to create iATR handle, error=", GetLastError());
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   ZeroMemory(tpos);
   tpos.active = false;

   if(LogTradesToCSV)
   {
      bool fileExists = (FileIsExist(CSVFileName));
      fileHandle = FileOpen(CSVFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(fileHandle != INVALID_HANDLE)
      {
         FileSeek(fileHandle, 0, SEEK_END);
         if(!fileExists)
            FileWrite(fileHandle, "OpenTime", "CloseTime", "Type", "EntryPrice", "ExitPrice",
                      "RSI_AtEntry", "CandlesHeld", "ProfitPoints");
      }
      else
         Print("WARNING: could not open CSV log file, error=", GetLastError());
   }

   Print("EA initialised. BarProcessingMethod=", EnumToString(BarProcessingMethod),
         " | Reading signals from bar ", iBarToUseForProcessing,
         " | TradeTimeframe=", EnumToString(TradeTimeframe),
         " | Rule: RSI_below_", DoubleToString(RSI_Threshold,0), " + bear_fvg + order_block_bear -> BUY",
         " | Holding period: ", CandlesToHold, " candle(s) [",
         (ConfirmedHorizonValue ? "confirmed against mined horizon" : "UNCONFIRMED -- see warning above"),
         "]",
         " | Emergency SL: ", (UseEmergencySL ? (DoubleToString(EmergencySL_ATRMult,1) + "x ATR") : "disabled (matches mined rule)"));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(fileHandle != INVALID_HANDLE) FileClose(fileHandle);
   Comment("");
}

//+------------------------------------------------------------------+
//| No tick-level monitoring needed for the timed exit. If UseEmergencySL |
//| is enabled, the broker-side SL handles that intra-bar, so no polling  |
//| is required here either.                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

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

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;

      //--- Timed exit is checked once per new bar, since it counts completed bars,
      //--- not price -- there is nothing to watch for intra-bar (the emergency SL,
      //--- if enabled, is handled by the broker/terminal directly).
      if(tpos.active)
         ManageTimedExit();

      EvaluateSignal();
   }

   OutputStatusToScreen();
}

//+------------------------------------------------------------------+
//| Checks all three structural conditions on the same completed bar,  |
//| matching how the miner evaluated the combined boolean mask.        |
//+------------------------------------------------------------------+
void EvaluateSignal()
{
   if(OnePositionAtATime && tpos.active) return; // already holding this rule's trade

   int bar  = iBarToUseForProcessing;
   int need = bar + 3; // bear_fvg needs bar+2, order_block_bear needs bar+1

   double highArr[], lowArr[], openArr[], closeArr[];
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);
   ArraySetAsSeries(openArr, true);
   ArraySetAsSeries(closeArr, true);

   if(CopyHigh(Symbol(), TradeTimeframe, 0, need, highArr) < need) return;
   if(CopyLow(Symbol(), TradeTimeframe, 0, need, lowArr) < need) return;
   if(CopyOpen(Symbol(), TradeTimeframe, 0, need, openArr) < need) return;
   if(CopyClose(Symbol(), TradeTimeframe, 0, need, closeArr) < need) return;

   double rsiBuf[], atrBuf[];
   ArraySetAsSeries(rsiBuf, true);
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hRSI, 0, 0, need, rsiBuf) < need) return;
   if(CopyBuffer(hATR, 0, 0, need, atrBuf) < need) return;

   //--- Condition 1: RSI_below_30
   bool rsiBelow30 = (rsiBuf[bar] < RSI_Threshold);

   //--- Condition 2: bear_fvg -- current bar's high fails to reach the low from 2 bars back
   bool bearFVG = (highArr[bar] < lowArr[bar + 2]);

   //--- Condition 3: order_block_bear -- the PRIOR bar closed bearish, and the CURRENT
   //--- bar's body size exceeds ATR (the "strong move" that confirms the prior bar as
   //--- the order block), exactly matching the shift(1) confirmation logic in the miner.
   bool priorBarBearish  = (closeArr[bar + 1] < openArr[bar + 1]);
   double currentBodySize = MathAbs(closeArr[bar] - openArr[bar]);
   bool currentStrongMove = (currentBodySize > atrBuf[bar]);
   bool orderBlockBear = priorBarBearish && currentStrongMove;

   if(!(rsiBelow30 && bearFVG && orderBlockBear)) return;

   OpenTimedBuy(rsiBuf[bar], atrBuf[bar]);
}

//+------------------------------------------------------------------+
//| Opens a BUY. No SL/TP of any kind by default, matching the mined   |
//| rule; an optional wide ATR-multiple SL can be attached purely as a |
//| tail-risk backstop via UseEmergencySL (see review note above).     |
//+------------------------------------------------------------------+
void OpenTimedBuy(double rsiAtEntry, double atrAtEntry)
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   double slPrice = 0.0;
   if(UseEmergencySL && atrAtEntry > 0.0)
      slPrice = ask - (atrAtEntry * EmergencySL_ATRMult);

   if(!trade.Buy(LotSize, Symbol(), ask, slPrice, 0.0, "RSI_FVG_OrderBlock_rule"))
   {
      Print("Buy failed, error=", GetLastError());
      return;
   }

   tpos.active     = true;
   tpos.ticket     = trade.ResultOrder();
   tpos.entryTime  = TimeCurrent();
   tpos.entryPrice = ask;
   tpos.barsHeld   = 0;
   tpos.entryRSI   = rsiAtEntry;

   Print("BUY opened @ ", DoubleToString(ask, _Digits),
         " | RSI=", DoubleToString(rsiAtEntry, 2),
         " | will close after ", CandlesToHold, " completed candle(s)",
         (UseEmergencySL ? (" | emergency SL @ " + DoubleToString(slPrice, _Digits)) : " | no SL/TP"));
}

//+------------------------------------------------------------------+
//| Counts one more completed bar elapsed; closes at market once the   |
//| holding period is reached. No price levels are checked here (the   |
//| optional emergency SL, if any, is enforced by the broker directly).|
//+------------------------------------------------------------------+
void ManageTimedExit()
{
   if(!PositionSelectByTicket(tpos.ticket))
   {
      // Position no longer exists (closed some other way, e.g. emergency SL hit) --
      // clear local state.
      ZeroMemory(tpos);
      tpos.active = false;
      return;
   }

   tpos.barsHeld++;

   if(tpos.barsHeld >= CandlesToHold)
      CloseTimedPosition();
}

//+------------------------------------------------------------------+
void CloseTimedPosition()
{
   double exitPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID); // selling to close a long

   if(!trade.PositionClose(tpos.ticket))
   {
      Print("Failed to close position, error=", GetLastError());
      return;
   }

   double profitPoints = (exitPrice - tpos.entryPrice) / _Point;

   Print("POSITION CLOSED (timed exit after ", tpos.barsHeld, " candle(s)) @ ", DoubleToString(exitPrice, _Digits),
         " | Points=", DoubleToString(profitPoints, 1));

   if(LogTradesToCSV && fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle,
                TimeToString(tpos.entryTime, TIME_DATE|TIME_SECONDS),
                TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                "BUY",
                DoubleToString(tpos.entryPrice, _Digits),
                DoubleToString(exitPrice, _Digits),
                DoubleToString(tpos.entryRSI, 2),
                IntegerToString(tpos.barsHeld),
                DoubleToString(profitPoints, 1));
      FileFlush(fileHandle);
   }

   ZeroMemory(tpos);
   tpos.active = false;
}

//+------------------------------------------------------------------+
void OutputStatusToScreen()
{
   string txt = "\n\r";
   txt += Symbol() + " " + EnumToString(TradeTimeframe) + " | RSI_below_30 + bear_fvg + order_block_bear rule EA\n\r";
   txt += "Ticks received/processed: " + IntegerToString(TicksReceivedCount) + " / " + IntegerToString(TicksProcessedCount) + "\n\r";
   txt += "Holding period: " + IntegerToString(CandlesToHold) + " candle(s) [" +
          (ConfirmedHorizonValue ? "confirmed" : "UNCONFIRMED") + "] | " +
          (UseEmergencySL ? ("Emergency SL " + DoubleToString(EmergencySL_ATRMult,1) + "x ATR") : "No SL/TP") + "\n\r";
   txt += "Position active: " + (tpos.active ? "YES" : "no") + "\n\r";
   if(tpos.active)
   {
      txt += "  Entry=" + DoubleToString(tpos.entryPrice, _Digits) +
             "  BarsHeld=" + IntegerToString(tpos.barsHeld) + "/" + IntegerToString(CandlesToHold) +
             "  RSI@Entry=" + DoubleToString(tpos.entryRSI, 2) + "\n\r";
   }
   Comment(txt);
}