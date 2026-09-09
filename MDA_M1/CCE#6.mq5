//+------------------------------------------------------------------------------------+
//| BB_PctB_RuleEA.mq5                                                                 |
//|                                                                                    |
//| Trades the rule discovered by the market-dependency mining pipeline:               |
//|    BB_pctb_above_0.75  ->  BEARISH bias                                            |
//|    (lift=2.12, direction%=50.9%, mag_atr_mean=-0.03, CV=91.3, STABLE across splits) |
//|                                                                                    |
//| NOTE ON EDGE QUALITY: this rule is only marginally better than a coin flip and     |
//| has very high move-magnitude variance. It is wired up here exactly as reported,    |
//| but is best used as ONE condition inside a multi-condition rule (your beam_search  |
//| output already supports combos up to 4 conditions) rather than traded alone.       |
//|                                                                                    |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                                 |
//| THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. TRADING FOREX/    |
//| CFDs CARRIES SUBSTANTIAL RISK OF LOSS. PAST STATISTICAL EDGE (INCLUDING OOS        |
//| VALIDATION) DOES NOT GUARANTEE FUTURE PERFORMANCE.                                 |
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property version     "1.00"
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
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;                          //Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR; //EA Bar Processing Method

input group "=== Rule: BB_pctb_above_0.75 (bearish) ==="
input int      BB_Period            = 20;       //Bollinger Bands period (matches BB_pctb_20 in mining lib)
input double   BB_Deviation         = 2.0;      //Bollinger Bands deviation
input double   BB_PctB_Threshold    = 0.75;     //%B threshold from the rule report
input bool     RequireFreshCross    = true;     //Only fire the bar %B first crosses above threshold, not every bar it stays above

input group "=== Risk / Virtual SL & TP (NO broker-side SL/TP is ever sent) ==="
input int      ATR_Period_Risk      = 14;
input double   SL_ATR_Multiple      = 1.5;      //Rule's own mag_atr_mean (~0.03 ATR) is noise-sized, not usable as a stop distance
input double   TP_ATR_Multiple      = 1.5;
input bool     UseTrailingStop      = true;
input double   TrailingStart_ATR    = 1.0;      //Start trailing once price has moved this many ATR in favor
input double   TrailingStep_ATR     = 0.5;      //Trail distance kept behind price once active

input group "=== Trade / Money Management ==="
input double   LotSize              = 0.10;
input int      MagicNumber          = 20260724;
input int      MaxSlippagePoints    = 20;
input bool     OnePositionAtATime   = true;

input group "=== Logging ==="
input bool     LogTradesToCSV       = true;
input string   CSVFileName          = "BB_PctB_RuleEA_trades.csv";

//################
// Globals
//################
CTrade   trade;
int      hBB, hATR;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;
bool     PrevBarWasAboveThreshold = false;   // for RequireFreshCross edge-detection
int      TicksReceivedCount = 0;
int      TicksProcessedCount = 0;

//--- Virtual position state. No SL/TP is ever attached to the broker order;
//--- everything below is tracked and enforced entirely by this EA.
struct VirtualPosition
{
   bool     active;
   ulong    ticket;
   datetime entryTime;
   double   entryPrice;
   double   virtualSL;
   double   virtualTP;
   double   entryATR;
   double   entryPctB;
   bool     trailingActive;
};
VirtualPosition vpos;

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
      iBarToUseForProcessing = 1;   //Use the last COMPLETED bar so the %B value can never change after the fact

   hBB = iBands(Symbol(), TradeTimeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   if(hBB == INVALID_HANDLE)
   {
      Print("ERROR: failed to create iBands handle, error=", GetLastError());
      return(INIT_FAILED);
   }

   hATR = iATR(Symbol(), TradeTimeframe, ATR_Period_Risk);
   if(hATR == INVALID_HANDLE)
   {
      Print("ERROR: failed to create iATR handle, error=", GetLastError());
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   ZeroMemory(vpos);
   vpos.active = false;

   if(LogTradesToCSV)
   {
      bool fileExists = (FileIsExist(CSVFileName));
      fileHandle = FileOpen(CSVFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(fileHandle != INVALID_HANDLE)
      {
         FileSeek(fileHandle, 0, SEEK_END);
         if(!fileExists)
            FileWrite(fileHandle, "OpenTime", "CloseTime", "Type", "EntryPrice", "ExitPrice",
                      "VirtualSL", "VirtualTP", "ATRAtEntry", "PctB_AtEntry", "ExitReason", "ProfitPoints");
      }
      else
         Print("WARNING: could not open CSV log file, error=", GetLastError());
   }

   Print("EA initialised. BarProcessingMethod=", EnumToString(BarProcessingMethod),
         " | Reading signals from bar ", iBarToUseForProcessing,
         " | Rule: BB_pctb_above_", DoubleToString(BB_PctB_Threshold, 2), " -> SELL bias");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hBB != INVALID_HANDLE)  IndicatorRelease(hBB);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(fileHandle != INVALID_HANDLE) FileClose(fileHandle);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

   //--- Virtual SL/TP has to be checked on EVERY tick regardless of the bar-processing
   //--- throttle below, since price can cross a virtual level intra-bar.
   if(vpos.active)
      ManageVirtualStops();

   //########################################################
   //Control EA so signal evaluation only happens at the required interval
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

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      EvaluateSignal();
   }

   OutputStatusToScreen();
}

//+------------------------------------------------------------------+
//| Reads %B off the last completed bar and opens/holds the sell rule |
//+------------------------------------------------------------------+
void EvaluateSignal()
{
   double upperBuf[], lowerBuf[];
   ArraySetAsSeries(upperBuf, true);
   ArraySetAsSeries(lowerBuf, true);

   int need = iBarToUseForProcessing + 2;
   if(CopyBuffer(hBB, UPPER_BAND, 0, need, upperBuf) < need) return;
   if(CopyBuffer(hBB, LOWER_BAND, 0, need, lowerBuf) < need) return;

   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(Symbol(), TradeTimeframe, 0, need, closeArr) < need) return;

   double upper = upperBuf[iBarToUseForProcessing];
   double lower = lowerBuf[iBarToUseForProcessing];
   double close = closeArr[iBarToUseForProcessing];

   if(upper - lower <= 0) return; // guard against a flat/zero-width band

   double pctB = (close - lower) / (upper - lower);
   bool aboveThreshold = (pctB > BB_PctB_Threshold);

   bool signalFires = aboveThreshold;
   if(RequireFreshCross)
      signalFires = aboveThreshold && !PrevBarWasAboveThreshold;

   PrevBarWasAboveThreshold = aboveThreshold;

   if(!signalFires) return;

   if(OnePositionAtATime && vpos.active) return; // already in the rule's trade

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR, 0, 0, need, atrBuf) < need) return;
   double atrAtEntry = atrBuf[iBarToUseForProcessing];
   if(atrAtEntry <= 0) return;

   OpenVirtualSell(atrAtEntry, pctB);
}

//+------------------------------------------------------------------+
//| Opens a SELL with NO broker sl/tp, then tracks virtual levels     |
//+------------------------------------------------------------------+
void OpenVirtualSell(double atrAtEntry, double pctBAtEntry)
{
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   //--- sl/tp are intentionally passed as 0.0 -- everything is virtual, managed by this EA
   if(!trade.Sell(LotSize, Symbol(), bid, 0.0, 0.0, "BB_pctb_rule"))
   {
      Print("Sell failed, error=", GetLastError());
      return;
   }

   vpos.active         = true;
   vpos.ticket         = trade.ResultOrder();
   vpos.entryTime      = TimeCurrent();
   vpos.entryPrice     = bid;
   vpos.entryATR       = atrAtEntry;
   vpos.entryPctB      = pctBAtEntry;
   vpos.virtualSL      = bid + SL_ATR_Multiple * atrAtEntry;   // short: SL sits above entry
   vpos.virtualTP      = bid - TP_ATR_Multiple * atrAtEntry;   // short: TP sits below entry
   vpos.trailingActive = false;

   Print("VIRTUAL SELL opened @ ", DoubleToString(bid, _Digits),
         " | vSL=", DoubleToString(vpos.virtualSL, _Digits),
         " | vTP=", DoubleToString(vpos.virtualTP, _Digits),
         " | ATR=", DoubleToString(atrAtEntry, _Digits),
         " | %B=", DoubleToString(pctBAtEntry, 4));
}

//+------------------------------------------------------------------+
//| Checks/enforces virtual SL, virtual TP, and virtual trailing stop |
//+------------------------------------------------------------------+
void ManageVirtualStops()
{
   if(!PositionSelectByTicket(vpos.ticket))
   {
      // Position no longer exists (closed some other way) -- clear local state
      ZeroMemory(vpos);
      vpos.active = false;
      return;
   }

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   //--- Trailing stop logic (short position: trail SL down as price falls)
   if(UseTrailingStop)
   {
      double favorableMove = vpos.entryPrice - ask; // positive when price has fallen (good for a short)
      if(!vpos.trailingActive && favorableMove >= TrailingStart_ATR * vpos.entryATR)
         vpos.trailingActive = true;

      if(vpos.trailingActive)
      {
         double candidateSL = ask + TrailingStep_ATR * vpos.entryATR;
         if(candidateSL < vpos.virtualSL)
            vpos.virtualSL = candidateSL; // only ever tighten, never loosen
      }
   }

   //--- Virtual TP hit (price traded down through it)
   if(bid <= vpos.virtualTP)
   {
      CloseVirtualPosition("TP");
      return;
   }

   //--- Virtual SL hit (price traded up through it)
   if(ask >= vpos.virtualSL)
   {
      CloseVirtualPosition("SL");
      return;
   }
}

//+------------------------------------------------------------------+
void CloseVirtualPosition(string reason)
{
   double exitPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK); // buying back to close a short

   if(!trade.PositionClose(vpos.ticket))
   {
      Print("Failed to close virtual position, error=", GetLastError());
      return;
   }

   double profitPoints = (vpos.entryPrice - exitPrice) / _Point;

   Print("VIRTUAL POSITION CLOSED (", reason, ") @ ", DoubleToString(exitPrice, _Digits),
         " | Points=", DoubleToString(profitPoints, 1));

   if(LogTradesToCSV && fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle,
                TimeToString(vpos.entryTime, TIME_DATE|TIME_SECONDS),
                TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                "SELL",
                DoubleToString(vpos.entryPrice, _Digits),
                DoubleToString(exitPrice, _Digits),
                DoubleToString(vpos.virtualSL, _Digits),
                DoubleToString(vpos.virtualTP, _Digits),
                DoubleToString(vpos.entryATR, _Digits),
                DoubleToString(vpos.entryPctB, 4),
                reason,
                DoubleToString(profitPoints, 1));
      FileFlush(fileHandle);
   }

   ZeroMemory(vpos);
   vpos.active = false;
}

//+------------------------------------------------------------------+
void OutputStatusToScreen()
{
   string txt = "\n\r";
   txt += Symbol() + " " + EnumToString(TradeTimeframe) + " | BB_pctb_above_" + DoubleToString(BB_PctB_Threshold,2) + " rule EA\n\r";
   txt += "Ticks received/processed: " + IntegerToString(TicksReceivedCount) + " / " + IntegerToString(TicksProcessedCount) + "\n\r";
   txt += "Virtual position active: " + (vpos.active ? "YES" : "no") + "\n\r";
   if(vpos.active)
   {
      txt += "  Entry=" + DoubleToString(vpos.entryPrice, _Digits) +
             "  vSL=" + DoubleToString(vpos.virtualSL, _Digits) +
             "  vTP=" + DoubleToString(vpos.virtualTP, _Digits) +
             "  Trailing=" + (vpos.trailingActive ? "active" : "not yet") + "\n\r";
   }
   Comment(txt);
}