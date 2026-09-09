//+------------------------------------------------------------------------------------+
//| RSI_Stoch_RuleEA.mq5                                                               |
//|                                                                                    |
//| Trades the rule discovered by the market-dependency mining pipeline:               |
//|    RSI_cross_below_50 + stoch_overbought_cross  ->  BULLISH bias                   |
//|    (lift=8.26, direction%=52.0%, mag_atr_mean=0.31, CV=8.64, STABLE across splits)  |
//|                                                                                    |
//| NOTE ON EDGE QUALITY: train (52.3% bullish) and OOS (52.9% bullish) agree, but the  |
//| VAL split actually flips negative (48.6% direction, mag_atr=-0.05). "STABLE" here   |
//| means the rule cleared the permutation test overall, not that every split agreed    |
//| on direction. Worth watching closely on a demo account before sizing this up.       |
//|                                                                                    |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                                 |
//| THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. TRADING FOREX/     |
//| CFDs CARRIES SUBSTANTIAL RISK OF LOSS. PAST STATISTICAL EDGE (INCLUDING OOS         |
//| VALIDATION) DOES NOT GUARANTEE FUTURE PERFORMANCE.                                  |
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

input group "=== Rule: RSI_cross_below_50 + stoch_overbought_cross (bullish) ==="
input int      RSI_Period           = 14;
input int      Stoch_KPeriod        = 14;
input int      Stoch_DPeriod        = 3;
input int      Stoch_Slowing        = 3;
input double   Stoch_OverboughtLvl  = 80.0;    //Fires when %K crosses back below this level

input group "=== Risk / Virtual SL & TP (NO broker-side SL/TP is ever sent) ==="
input int      ATR_Period_Risk      = 14;
input double   SL_ATR_Multiple      = 1.5;
input double   TP_ATR_Multiple      = 2.5;      //Rule's own mag_atr_mean is ~0.31 ATR -- a real tradable magnitude, so give it room
input bool     UseTrailingStop      = true;
input double   TrailingStart_ATR    = 1.0;      //Start trailing once price has moved this many ATR in favor
input double   TrailingStep_ATR     = 0.5;      //Trail distance kept behind price once active

input group "=== Trade / Money Management ==="
input double   LotSize              = 0.10;
input int      MagicNumber          = 20260725;
input int      MaxSlippagePoints    = 20;
input bool     OnePositionAtATime   = true;

input group "=== Logging ==="
input bool     LogTradesToCSV       = true;
input string   CSVFileName          = "RSI_Stoch_RuleEA_trades.csv";

//################
// Globals
//################
CTrade   trade;
int      hRSI, hStoch, hATR;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';
int      iBarToUseForProcessing;
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
   double   entryRSI;
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
      iBarToUseForProcessing = 1;   //Use the last COMPLETED bar so cross detection can never change after the fact

   hRSI = iRSI(Symbol(), TradeTimeframe, RSI_Period, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE)
   {
      Print("ERROR: failed to create iRSI handle, error=", GetLastError());
      return(INIT_FAILED);
   }

   hStoch = iStochastic(Symbol(), TradeTimeframe, Stoch_KPeriod, Stoch_DPeriod, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   if(hStoch == INVALID_HANDLE)
   {
      Print("ERROR: failed to create iStochastic handle, error=", GetLastError());
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
                      "VirtualSL", "VirtualTP", "ATRAtEntry", "RSI_AtEntry", "ExitReason", "ProfitPoints");
      }
      else
         Print("WARNING: could not open CSV log file, error=", GetLastError());
   }

   Print("EA initialised. BarProcessingMethod=", EnumToString(BarProcessingMethod),
         " | Reading signals from bar ", iBarToUseForProcessing,
         " | Rule: RSI_cross_below_50 + stoch_overbought_cross -> BUY bias");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE)   IndicatorRelease(hRSI);
   if(hStoch != INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hATR != INVALID_HANDLE)   IndicatorRelease(hATR);
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
//| Both conditions must fire on the SAME completed bar, matching the  |
//| rule as it was measured (a combined boolean-mask AND in the miner) |
//+------------------------------------------------------------------+
void EvaluateSignal()
{
   int need = iBarToUseForProcessing + 2;

   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);
   if(CopyBuffer(hRSI, 0, 0, need, rsiBuf) < need) return;

   double stochKBuf[];
   ArraySetAsSeries(stochKBuf, true);
   if(CopyBuffer(hStoch, 0, 0, need, stochKBuf) < need) return; // buffer 0 = %K (MAIN_LINE)

   double rsiNow  = rsiBuf[iBarToUseForProcessing];
   double rsiPrev = rsiBuf[iBarToUseForProcessing + 1];
   double kNow    = stochKBuf[iBarToUseForProcessing];
   double kPrev   = stochKBuf[iBarToUseForProcessing + 1];

   bool rsiCrossBelow50   = (rsiNow < 50.0) && (rsiPrev >= 50.0);
   bool stochOverboughtCr = (kNow < Stoch_OverboughtLvl) && (kPrev >= Stoch_OverboughtLvl);

   if(!(rsiCrossBelow50 && stochOverboughtCr)) return;

   if(OnePositionAtATime && vpos.active) return; // already in the rule's trade

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR, 0, 0, need, atrBuf) < need) return;
   double atrAtEntry = atrBuf[iBarToUseForProcessing];
   if(atrAtEntry <= 0) return;

   OpenVirtualBuy(atrAtEntry, rsiNow);
}

//+------------------------------------------------------------------+
//| Opens a BUY with NO broker sl/tp, then tracks virtual levels      |
//+------------------------------------------------------------------+
void OpenVirtualBuy(double atrAtEntry, double rsiAtEntry)
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   //--- sl/tp are intentionally passed as 0.0 -- everything is virtual, managed by this EA
   if(!trade.Buy(LotSize, Symbol(), ask, 0.0, 0.0, "RSI_stoch_rule"))
   {
      Print("Buy failed, error=", GetLastError());
      return;
   }

   vpos.active         = true;
   vpos.ticket         = trade.ResultOrder();
   vpos.entryTime      = TimeCurrent();
   vpos.entryPrice     = ask;
   vpos.entryATR       = atrAtEntry;
   vpos.entryRSI       = rsiAtEntry;
   vpos.virtualSL      = ask - SL_ATR_Multiple * atrAtEntry;   // long: SL sits below entry
   vpos.virtualTP      = ask + TP_ATR_Multiple * atrAtEntry;   // long: TP sits above entry
   vpos.trailingActive = false;

   Print("VIRTUAL BUY opened @ ", DoubleToString(ask, _Digits),
         " | vSL=", DoubleToString(vpos.virtualSL, _Digits),
         " | vTP=", DoubleToString(vpos.virtualTP, _Digits),
         " | ATR=", DoubleToString(atrAtEntry, _Digits),
         " | RSI=", DoubleToString(rsiAtEntry, 2));
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

   //--- Trailing stop logic (long position: trail SL up as price rises)
   if(UseTrailingStop)
   {
      double favorableMove = bid - vpos.entryPrice; // positive when price has risen (good for a long)
      if(!vpos.trailingActive && favorableMove >= TrailingStart_ATR * vpos.entryATR)
         vpos.trailingActive = true;

      if(vpos.trailingActive)
      {
         double candidateSL = bid - TrailingStep_ATR * vpos.entryATR;
         if(candidateSL > vpos.virtualSL)
            vpos.virtualSL = candidateSL; // only ever tighten, never loosen
      }
   }

   //--- Virtual TP hit (price traded up through it)
   if(ask >= vpos.virtualTP)
   {
      CloseVirtualPosition("TP");
      return;
   }

   //--- Virtual SL hit (price traded down through it)
   if(bid <= vpos.virtualSL)
   {
      CloseVirtualPosition("SL");
      return;
   }
}

//+------------------------------------------------------------------+
void CloseVirtualPosition(string reason)
{
   double exitPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID); // selling to close a long

   if(!trade.PositionClose(vpos.ticket))
   {
      Print("Failed to close virtual position, error=", GetLastError());
      return;
   }

   double profitPoints = (exitPrice - vpos.entryPrice) / _Point;

   Print("VIRTUAL POSITION CLOSED (", reason, ") @ ", DoubleToString(exitPrice, _Digits),
         " | Points=", DoubleToString(profitPoints, 1));

   if(LogTradesToCSV && fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle,
                TimeToString(vpos.entryTime, TIME_DATE|TIME_SECONDS),
                TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                "BUY",
                DoubleToString(vpos.entryPrice, _Digits),
                DoubleToString(exitPrice, _Digits),
                DoubleToString(vpos.virtualSL, _Digits),
                DoubleToString(vpos.virtualTP, _Digits),
                DoubleToString(vpos.entryATR, _Digits),
                DoubleToString(vpos.entryRSI, 2),
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
   txt += Symbol() + " " + EnumToString(TradeTimeframe) + " | RSI_cross_below_50 + stoch_overbought_cross rule EA\n\r";
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