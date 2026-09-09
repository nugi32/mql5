0//+--------------------------------------------------------------------------------+
//| BB_pctb_below_0v2_RuleEA.mq5                                                   |
//|                                                                                |
//| Trades the rule discovered by the market-dependency mining pipeline:          |
//|    BB_pctb_below_0.2  ->  BULLISH bias                                        |
//|    (lift=3.84, direction%=54.7%, mag_atr_mean@h10=0.0171, CV=156.17, STABLE)   |
//|                                                                                |
//| *** THIS RULE IS WEAKER THAN PRIOR ONES DEPLOYED -- READ BEFORE USE ***        |
//| 1) mag_cv = 156.17. The stdev of the move is ~156x the mean move. Compare to   |
//|    the order-block rule's CV of 21.55, itself already noise-dominated. This   |
//|    "edge" is almost entirely noise around a tiny average.                     |
//| 2) The mining report's own robustness check found the RECOMMENDED HOLDING     |
//|    PERIOD ITSELF unstable across splits: train=3 candles, val=2, oos=1. The   |
//|    report explicitly says: "Treat recommended_horizon as exploratory, not     |
//|    confirmed." There is no single validated exit timing to give this EA.      |
//| CandlesToHold below defaults to 1 (the OOS-preferred, most conservative of    |
//| the three disagreeing values) rather than the full-sample winner of 3, but    |
//| this is a judgment call, not a resolved number. OnInit() prints the full      |
//| disagreement every time this EA starts.                                       |
//|                                                                                |
//| EXIT MODEL: NO broker-side SL or TP is ever attached to the order (sl=0,      |
//| tp=0 always, per requirement). Primary exit is a timer (CandlesToHold         |
//| completed bars). An OPTIONAL virtual stop (UseVirtualStop) is monitored       |
//| entirely in EA code every tick and closes via market order if breached --     |
//| no price level is ever sent to the broker.                                    |
//|                                                                                |
//| Built on the control-bar-opening-single-symbol.mq5 framework (bar-processing  |
//| enum, iBarToUseForProcessing convention, tick counters, OutputStatusToScreen).|
//|                                                                                |
//| DISCLAIMER: PROVIDED "AS IS", NO WARRANTY. TRADING FOREX/CFDs CARRIES         |
//| SUBSTANTIAL RISK OF LOSS. PAST STATISTICAL EDGE (INCLUDING OOS VALIDATION)    |
//| DOES NOT GUARANTEE FUTURE PERFORMANCE. THIS SPECIFIC RULE'S OWN MINING        |
//| REPORT FLAGGED ITS EXIT TIMING AS UNSTABLE -- THAT IS NOT RESOLVED BY THIS EA.|
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property version     "1.00"
#property strict

#include <Trade\Trade.mqh>

//################
// Bar processing control (framework: control-bar-opening-single-symbol.mq5)
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
// This rule was mined exclusively on M15 data (data/raw/XAUUSD15.csv). BB_pctb_20
// computed on any other timeframe is a different quantity than what was measured.
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;                          //Trading Timeframe (MUST match mined data: M15)
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR; //EA Bar Processing Method

input group "=== Rule: BB_pctb_below_0.2 (bullish) ==="
input int      BB_Period            = 20;      //Matches Python compute_bollinger(period=20)
input double   BB_Deviation         = 2.0;     //Matches Python num_std=2.0
input double   BB_PctB_Threshold    = 0.2;     //BB_pctb_below_0.2 in the mining report

input group "=== Exit: pure time-based, NO broker SL/TP of any kind ==="
// UNRESOLVED (see header): train/val/oos recommended holding periods disagreed
// (3 / 2 / 1 candles). Defaulted here to 1 -- the OOS-preferred, most conservative
// value -- as a judgment call, NOT a validated number. Change only with a clear
// reason, and re-read the mining report's horizon_profile / split_validation
// before trusting any specific value.
input int      CandlesToHold          = 1;        //Close after this many completed candles (train=3/val=2/oos=1 disagreed -- see header)
input bool     AcknowledgedInstability = false;    //Set TRUE only after reading the horizon-instability warning above

input group "=== Trade / Money Management ==="
input double   LotSize              = 0.10;
input int      MagicNumber          = 20260727;
input int      MaxSlippagePoints    = 20;
input bool     OnePositionAtATime   = true;

input group "=== Optional VIRTUAL stop (no broker order sent) ==="
// Given mag_cv=156.17, an unprotected position could see a large adverse move
// before the timed exit fires. This is a purely EA-side monitored level -- NO
// price is ever attached to the broker order (sl stays 0 always). If breached,
// the EA closes at market itself.
input bool     UseVirtualStop       = false;    //Monitor a virtual stop in-code and close at market if breached (no broker-side SL)
input double   VirtualStop_ATRMult  = 5.0;      //ATR multiple for the virtual stop level, if enabled
input int      ATR_Period_ForStop   = 14;       //ATR period used only for the virtual stop distance

input group "=== Logging ==="
input bool     LogTradesToCSV       = true;
input string   CSVFileName          = "BB_pctb_below_0v2_RuleEA_trades.csv";

//################
// Global Variables (framework convention)
//################
CTrade   trade;
int      hBB_Base, hATR;
int      TicksReceivedCount    = 0;
int      TicksProcessedCount   = 0;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;

struct TimedPosition
{
   bool     active;
   ulong    ticket;
   datetime entryTime;
   double   entryPrice;
   int      barsHeld;
   double   entryPctB;
   double   virtualStopPrice;   //0.0 if UseVirtualStop is false
};
TimedPosition tpos;

int fileHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   //--- Determine which bar to use, exactly per the framework's convention:
   //--- use the last COMPLETED bar when processing on new-trade-TF-bar events,
   //--- so structure/indicator reads can never change after the fact.
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;
   else //ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR
      iBarToUseForProcessing = 1;

   if(TradeTimeframe != PERIOD_M15)
   {
      Print("ERROR: TradeTimeframe is ", EnumToString(TradeTimeframe),
            " but this rule was mined exclusively on M15 data. BB_pctb_20 on any ",
            "other timeframe is an untested quantity. Set TradeTimeframe = PERIOD_M15, ",
            "or mine a fresh rule on your target timeframe first.");
      return(INIT_FAILED);
   }

   Print("*** HORIZON INSTABILITY WARNING (from mining report, not resolved by this EA) ***");
   Print("Recommended holding period disagreed across splits: train=3, val=2, oos=1 candles.");
   Print("CandlesToHold is currently ", CandlesToHold, " (a judgment call -- the OOS-preferred, ",
         "most conservative of the three disagreeing values, NOT a validated number).");
   Print("mag_cv=156.17 -- the stdev of the historical move is ~156x its mean. This edge is ",
         "almost entirely noise around a tiny average.");
   if(!AcknowledgedInstability)
      Print("WARNING: AcknowledgedInstability is false. Trading will proceed, but re-read the ",
            "mining report's horizon_profile and split_validation before trusting any result from this EA.");

   hBB_Base = iBands(Symbol(), TradeTimeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   if(hBB_Base == INVALID_HANDLE)
   {
      Print("ERROR: failed to create iBands handle, error=", GetLastError());
      return(INIT_FAILED);
   }

   if(UseVirtualStop)
   {
      hATR = iATR(Symbol(), TradeTimeframe, ATR_Period_ForStop);
      if(hATR == INVALID_HANDLE)
      {
         Print("ERROR: failed to create iATR handle (needed for virtual stop), error=", GetLastError());
         return(INIT_FAILED);
      }
   }
   else
      hATR = INVALID_HANDLE;

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
                      "PctB_AtEntry", "CandlesHeld", "ExitReason", "ProfitPoints");
      }
      else
         Print("WARNING: could not open CSV log file, error=", GetLastError());
   }

   Print("EA initialised. BarProcessingMethod=", EnumToString(BarProcessingMethod),
         " | Reading signals from bar ", iBarToUseForProcessing,
         " | TradeTimeframe=", EnumToString(TradeTimeframe),
         " | Rule: BB_pctb_20 < ", DoubleToString(BB_PctB_Threshold, 2), " -> BUY",
         " | Holding period: ", CandlesToHold, " candle(s) [UNVALIDATED, see warnings above]",
         " | Virtual stop: ", (UseVirtualStop ? (DoubleToString(VirtualStop_ATRMult,1) + "x ATR, EA-monitored only") : "disabled"),
         " | Broker SL/TP: never used (sl=0, tp=0 always)");

   OutputStatusToScreen();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hBB_Base != INVALID_HANDLE) IndicatorRelease(hBB_Base);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(fileHandle != INVALID_HANDLE) FileClose(fileHandle);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

   //--- Virtual stop must be checked every tick (it's price-based, not bar-based),
   //--- regardless of BarProcessingMethod -- matches "use virtual if really needed"
   //--- with NO broker-side order ever involved.
   if(tpos.active && UseVirtualStop)
      CheckVirtualStop();

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

      ProcessTradeClosures();  //Timed exit -- only meaningful once per new bar
      ProcessTradeOpens();     //Signal check -- only meaningful once per new bar
   }

   OutputStatusToScreen();
}

//+------------------------------------------------------------------+
//| Timed exit: counts one more completed bar elapsed, closes at       |
//| market once CandlesToHold is reached. No price levels checked here |
//| (the optional virtual stop is handled separately, every tick, in   |
//| CheckVirtualStop()).                                               |
//+------------------------------------------------------------------+
void ProcessTradeClosures()
{
   if(!tpos.active) return;

   if(!PositionSelectByTicket(tpos.ticket))
   {
      ZeroMemory(tpos);
      tpos.active = false;
      return;
   }

   tpos.barsHeld++;

   if(tpos.barsHeld >= CandlesToHold)
      CloseTimedPosition("timed_exit");
}

//+------------------------------------------------------------------+
//| Signal check: BB_pctb_below_0.2 on the completed processing bar,    |
//| matching how the miner evaluated the condition.                    |
//+------------------------------------------------------------------+
void ProcessTradeOpens()
{
   if(OnePositionAtATime && tpos.active) return;

   int bar = iBarToUseForProcessing;

   double upperBuf[], lowerBuf[], closeBuf[];
   ArraySetAsSeries(upperBuf, true);
   ArraySetAsSeries(lowerBuf, true);
   ArraySetAsSeries(closeBuf, true);

   int need = bar + 1;
   //--- iBands buffer indices: 0 = base/middle, 1 = upper, 2 = lower
   if(CopyBuffer(hBB_Base, 1, 0, need, upperBuf) < need) return;
   if(CopyBuffer(hBB_Base, 2, 0, need, lowerBuf) < need) return;
   if(CopyClose(Symbol(), TradeTimeframe, 0, need, closeBuf) < need) return;

   double upper = upperBuf[bar];
   double lower = lowerBuf[bar];
   double close_ = closeBuf[bar];
   double range = upper - lower;
   if(range <= 0.0) return; //degenerate band, cannot evaluate %B

   double pctB = (close_ - lower) / range;

   if(!(pctB < BB_PctB_Threshold)) return;

   OpenTimedBuy(pctB);
}

//+------------------------------------------------------------------+
//| Opens a BUY. sl and tp are ALWAYS 0 -- no broker-side protection    |
//| is ever attached, per requirement. Virtual stop level (if enabled) |
//| is computed and stored locally only.                               |
//+------------------------------------------------------------------+
void OpenTimedBuy(double pctBAtEntry)
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   if(!trade.Buy(LotSize, Symbol(), ask, 0.0, 0.0, "BB_pctb_below_0.2_rule"))
   {
      Print("Buy failed, error=", GetLastError());
      return;
   }

   tpos.active           = true;
   tpos.ticket            = trade.ResultOrder();
   tpos.entryTime          = TimeCurrent();
   tpos.entryPrice         = ask;
   tpos.barsHeld           = 0;
   tpos.entryPctB          = pctBAtEntry;
   tpos.virtualStopPrice   = 0.0;

   if(UseVirtualStop)
   {
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(hATR, 0, 0, 2, atrBuf) >= 2)
         tpos.virtualStopPrice = ask - (atrBuf[iBarToUseForProcessing] * VirtualStop_ATRMult);
   }

   Print("BUY opened @ ", DoubleToString(ask, _Digits),
         " | %B=", DoubleToString(pctBAtEntry, 4),
         " | will close after ", CandlesToHold, " completed candle(s) [UNVALIDATED holding period]",
         (UseVirtualStop ? (" | virtual stop @ " + DoubleToString(tpos.virtualStopPrice, _Digits) + " (EA-monitored, not broker-side)") : " | no SL/TP of any kind"));
}

//+------------------------------------------------------------------+
//| Checked every tick. Purely EA-side -- no price level is ever sent  |
//| to the broker. Closes at market if the virtual level is breached.  |
//+------------------------------------------------------------------+
void CheckVirtualStop()
{
   if(!tpos.active || tpos.virtualStopPrice <= 0.0) return;
   if(!PositionSelectByTicket(tpos.ticket))
   {
      ZeroMemory(tpos);
      tpos.active = false;
      return;
   }

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(bid <= tpos.virtualStopPrice)
      CloseTimedPosition("virtual_stop");
}

//+------------------------------------------------------------------+
void CloseTimedPosition(string exitReason)
{
   double exitPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   if(!trade.PositionClose(tpos.ticket))
   {
      Print("Failed to close position, error=", GetLastError());
      return;
   }

   double profitPoints = (exitPrice - tpos.entryPrice) / _Point;

   Print("POSITION CLOSED (", exitReason, ", ", tpos.barsHeld, " candle(s) held) @ ",
         DoubleToString(exitPrice, _Digits), " | Points=", DoubleToString(profitPoints, 1));

   if(LogTradesToCSV && fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle,
                TimeToString(tpos.entryTime, TIME_DATE|TIME_SECONDS),
                TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                "BUY",
                DoubleToString(tpos.entryPrice, _Digits),
                DoubleToString(exitPrice, _Digits),
                DoubleToString(tpos.entryPctB, 4),
                IntegerToString(tpos.barsHeld),
                exitReason,
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
   txt += Symbol() + " " + EnumToString(TradeTimeframe) + " | BB_pctb_below_0.2 rule EA\n\r";
   txt += "Ticks received/processed: " + IntegerToString(TicksReceivedCount) + " / " + IntegerToString(TicksProcessedCount) + "\n\r";
   txt += "Holding: " + IntegerToString(CandlesToHold) + " candle(s) [UNVALIDATED -- train=3/val=2/oos=1 disagreed] | " +
          "Virtual stop: " + (UseVirtualStop ? (DoubleToString(VirtualStop_ATRMult,1) + "x ATR") : "off") +
          " | Broker SL/TP: never used\n\r";
   txt += "Position active: " + (tpos.active ? "YES" : "no") + "\n\r";
   if(tpos.active)
   {
      txt += "  Entry=" + DoubleToString(tpos.entryPrice, _Digits) +
             "  BarsHeld=" + IntegerToString(tpos.barsHeld) + "/" + IntegerToString(CandlesToHold) +
             "  %B@Entry=" + DoubleToString(tpos.entryPctB, 4) +
             (UseVirtualStop ? ("  VirtualStop=" + DoubleToString(tpos.virtualStopPrice, _Digits)) : "") + "\n\r";
   }
   Comment(txt);
}