//+--------------------------------------------------------------------------------+
//| RSI21_RSI7_Oversold_RuleEA.mq5                                                 |
//|                                                                                |
//| Rule ID: XAUUSD_M1_70                                                          |
//| Hypothesis: Price rally after rsi_21 < 20.0 AND rsi_7 < 20.0                   |
//| Entry Condition: rsi_21 < 20.0 AND rsi_7 < 20.0                                |
//| Optimal Horizon: 1 bar                                                         |
//| Baseline Prob (Bull): 49.20% -> Prob (Bull) at horizon: 56.65%                 |
//| Effect Size: 0.0878 | Net Expectancy: 1477.54 pips | Expectancy: 0.29R         |
//|                                                                                |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                             |
//| THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"    |
//| AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE      |
//| IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE |
//| DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE   |
//| FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL     |
//| DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR     |
//| SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER     |
//| CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,  |
//| OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  |
//| OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.           |
//+--------------------------------------------------------------------------------+

#property copyright     "Nugi"
#property link          ""
#property description   "Rule-based EA: RSI(21)<20 AND RSI(7)<20 oversold long entry, 1-bar horizon exit"
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

input string                     Section_General      = "==== General ====";      //---
input ENUM_TIMEFRAMES            TradeTimeframe        = PERIOD_M1;                //Trading Timeframe (rule mined on M1)
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod   = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR; //EA Bar Processing Method
input ulong                      MagicNumber           = 210070;                   //Magic Number (unique per EA)
input double                     LotSize               = 0.01;                     //Fixed Lot Size

input string                     Section_Rule          = "==== Rule Parameters (XAUUSD_M1_70) ===="; //---
input int                        RSI_Period_Slow        = 21;                      //RSI Period (Slow)
input int                        RSI_Period_Fast         = 7;                      //RSI Period (Fast)
input double                     RSI_Slow_Threshold      = 20.0;                   //RSI(21) Entry Threshold (< this)
input double                     RSI_Fast_Threshold      = 20.0;                   //RSI(7) Entry Threshold (< this)
input int                        HorizonBars              = 1;                     //Optimal Horizon (bars) - primary exit trigger

input string                     Section_Risk          = "==== Virtual Risk Management (no broker-side SL/TP) ===="; //---
input bool                       UseVirtualStop           = true;                  //Use Virtual ATR-based Stop (safety rail)
input int                        ATR_Period                = 14;                   //ATR Period for virtual stop
input double                     ATR_Multiplier_SL          = 2.5;                  //Virtual SL = entry - (ATR * this)
input bool                       AllowOnlyOnePositionAtATime = true;               //Block new entries while a position is open

input string                     Section_Log           = "==== Logging ====";      //---
input string                     CSV_FileName             = "RSI21_RSI7_Oversold_RuleEA_Trades.csv"; //CSV trade log filename (Files folder)

//################
//Global Variables
//################

CTrade   trade;

int      TicksReceivedCount      = 0;
int      TicksProcessedCount     = 0;
datetime TimeLastTickProcessed   = D'1971.01.01 00:00';

int      iBarToUseForProcessing;   //Set in OnInit() based on BarProcessingMethod

int      hRSI_Slow = INVALID_HANDLE;
int      hRSI_Fast = INVALID_HANDLE;
int      hATR      = INVALID_HANDLE;

//Open position bookkeeping (single position tracked; EA uses its own magic number so PositionSelect by magic is authoritative)
datetime g_EntryBarTime  = 0;
double   g_EntryPrice    = 0.0;
double   g_VirtualSL     = 0.0;
int      g_BarsHeld      = 0;

int      g_CsvHandle     = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   //################################
   //Determine which bar we will use (0 or 1) to perform processing of data
   //Consistent with prior conventions: signals are read from the LAST COMPLETED bar (bar 1)
   //################################

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;

   Print("EA USING " + EnumToString(BarProcessingMethod) + " PROCESSING METHOD AND INDICATORS WILL USE BAR " + IntegerToString(iBarToUseForProcessing));

   //################################
   //Create indicator handles
   //################################

   hRSI_Slow = iRSI(Symbol(), TradeTimeframe, RSI_Period_Slow, PRICE_CLOSE);
   hRSI_Fast = iRSI(Symbol(), TradeTimeframe, RSI_Period_Fast, PRICE_CLOSE);
   hATR      = iATR(Symbol(), TradeTimeframe, ATR_Period);

   if(hRSI_Slow == INVALID_HANDLE || hRSI_Fast == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create one or more indicator handles. RSI_Slow=", hRSI_Slow,
            " RSI_Fast=", hRSI_Fast, " ATR=", hATR);
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(Symbol());

   //################################
   //Open CSV log file (append mode)
   //################################

   g_CsvHandle = FileOpen(CSV_FileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   if(g_CsvHandle == INVALID_HANDLE)
   {
      Print("ERROR: Could not open CSV log file: ", CSV_FileName, " Error: ", GetLastError());
   }
   else
   {
      FileSeek(g_CsvHandle, 0, SEEK_END);
      if(FileSize(g_CsvHandle) == 0)
      {
         FileWrite(g_CsvHandle, "EventTime", "EventType", "Symbol", "Direction", "Ticket",
                   "EntryTime", "EntryPrice", "ExitTime", "ExitPrice", "VirtualSL",
                   "BarsHeld", "RSI_Slow", "RSI_Fast", "ExitReason", "ProfitPips");
      }
   }

   //Restore state if a matching position already exists (EA restart mid-trade)
   RestoreOpenPositionState();

   OutputStatusToScreen();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hRSI_Slow != INVALID_HANDLE) IndicatorRelease(hRSI_Slow);
   if(hRSI_Fast != INVALID_HANDLE) IndicatorRelease(hRSI_Fast);
   if(hATR      != INVALID_HANDLE) IndicatorRelease(hATR);
   if(g_CsvHandle != INVALID_HANDLE) FileClose(g_CsvHandle);

   Comment("");
}

//+------------------------------------------------------------------+
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
   //Process on new bar close only (rule requires completed-bar RSI values)
   //#############################

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;

      ManageOpenPosition();   //Check horizon-based / virtual-stop exit first
      ProcessTradeOpens();    //Then evaluate new entries
   }

   //Virtual stop can still be checked intrabar for safety, independent of bar gating
   if(UseVirtualStop)
      CheckVirtualStopIntrabar();

   OutputStatusToScreen();
}

//+------------------------------------------------------------------+
//| Evaluate entry condition on the last COMPLETED bar (bar 1)       |
//+------------------------------------------------------------------+
void ProcessTradeOpens()
{
   if(AllowOnlyOnePositionAtATime && HasOpenPosition())
      return;

   double rsiSlow[], rsiFast[];
   ArraySetAsSeries(rsiSlow, true);
   ArraySetAsSeries(rsiFast, true);

   if(CopyBuffer(hRSI_Slow, 0, 0, 3, rsiSlow) < 3) return;
   if(CopyBuffer(hRSI_Fast, 0, 0, 3, rsiFast) < 3) return;

   double rsiSlowVal = rsiSlow[iBarToUseForProcessing];   //bar 1 = last completed bar
   double rsiFastVal = rsiFast[iBarToUseForProcessing];

   bool signal = (rsiSlowVal < RSI_Slow_Threshold) && (rsiFastVal < RSI_Fast_Threshold);

   if(!signal)
      return;

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   double atrVal = 0.0;
   if(CopyBuffer(hATR, 0, 0, 3, atrBuf) >= 3)
      atrVal = atrBuf[iBarToUseForProcessing];

   double virtualSL = 0.0;
   if(UseVirtualStop && atrVal > 0.0)
      virtualSL = ask - (atrVal * ATR_Multiplier_SL);

   //No broker-side SL/TP ever sent - managed virtually in ManageOpenPosition() / CheckVirtualStopIntrabar()
   if(trade.Buy(LotSize, Symbol(), ask, 0.0, 0.0, "RuleEA_XAUUSD_M1_70"))
   {
      g_EntryBarTime = iTime(Symbol(), TradeTimeframe, iBarToUseForProcessing);
      g_EntryPrice   = ask;
      g_VirtualSL    = virtualSL;
      g_BarsHeld     = 0;

      LogTrade("OPEN", "BUY", trade.ResultOrder(), g_EntryBarTime, g_EntryPrice,
                0, 0, g_VirtualSL, 0, rsiSlowVal, rsiFastVal, "ENTRY_SIGNAL", 0.0);

      Print("ENTRY: BUY ", Symbol(), " @ ", ask, " RSI21=", rsiSlowVal, " RSI7=", rsiFastVal,
            " VirtualSL=", g_VirtualSL);
   }
   else
   {
      Print("ERROR: Buy order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Manage the open position: horizon-based exit + virtual stop      |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(!HasOpenPosition())
      return;

   //Count completed bars since entry
   datetime currentCompletedBarTime = iTime(Symbol(), TradeTimeframe, 1);
   g_BarsHeld = iBarShift(Symbol(), TradeTimeframe, g_EntryBarTime, false);

   //Primary exit: rule's optimal horizon reached
   if(g_BarsHeld >= HorizonBars)
   {
      ClosePositionAndLog("HORIZON_REACHED");
      return;
   }

   //Secondary exit: virtual stop breached on the completed bar's low
   if(UseVirtualStop && g_VirtualSL > 0.0)
   {
      double low1 = iLow(Symbol(), TradeTimeframe, 1);
      if(low1 <= g_VirtualSL)
      {
         ClosePositionAndLog("VIRTUAL_SL_BAR_CLOSE");
      }
   }
}

//+------------------------------------------------------------------+
//| Intrabar check so the virtual stop isn't only evaluated on bar   |
//| close (protects against large adverse moves mid-bar)             |
//+------------------------------------------------------------------+
void CheckVirtualStopIntrabar()
{
   if(!HasOpenPosition() || g_VirtualSL <= 0.0)
      return;

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(bid <= g_VirtualSL)
   {
      ClosePositionAndLog("VIRTUAL_SL_INTRABAR");
   }
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ClosePositionAndLog(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double exitPrice  = SymbolInfoDouble(Symbol(), SYMBOL_BID);

      if(trade.PositionClose(ticket))
      {
         double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
         double profitPips = (exitPrice - entryPrice) / point / 10.0; //approx pips for 5-digit FX-style quoting; adjust for XAUUSD point size if needed

         LogTrade("CLOSE", "BUY", ticket, g_EntryBarTime, entryPrice,
                   TimeCurrent(), exitPrice, g_VirtualSL, g_BarsHeld,
                   0, 0, reason, profitPips);

         Print("EXIT [", reason, "]: ", Symbol(), " Entry=", entryPrice, " Exit=", exitPrice,
               " BarsHeld=", g_BarsHeld);

         g_EntryBarTime = 0;
         g_EntryPrice   = 0.0;
         g_VirtualSL    = 0.0;
         g_BarsHeld     = 0;
      }
      else
      {
         Print("ERROR: PositionClose failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Recover in-memory state if the EA is reloaded while a position   |
//| opened by this magic number is still live                       |
//+------------------------------------------------------------------+
void RestoreOpenPositionState()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
         PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber)
      {
         g_EntryPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
         g_EntryBarTime = (datetime)PositionGetInteger(POSITION_TIME);
         g_VirtualSL    = 0.0; //cannot be recovered exactly; virtual SL will be inactive until next entry
         g_BarsHeld     = iBarShift(Symbol(), TradeTimeframe, g_EntryBarTime, false);
         Print("RESTORED open position state on EA reload. EntryPrice=", g_EntryPrice,
               " EntryBarTime=", TimeToString(g_EntryBarTime));
         return;
      }
   }
}

//+------------------------------------------------------------------+
void LogTrade(string eventType, string direction, ulong ticket, datetime entryTime, double entryPrice,
              datetime exitTime, double exitPrice, double virtualSL, int barsHeld,
              double rsiSlow, double rsiFast, string exitReason, double profitPips)
{
   if(g_CsvHandle == INVALID_HANDLE)
      return;

   FileWrite(g_CsvHandle,
             TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
             eventType,
             Symbol(),
             direction,
             (long)ticket,
             TimeToString(entryTime, TIME_DATE|TIME_SECONDS),
             DoubleToString(entryPrice, _Digits),
             (exitTime > 0 ? TimeToString(exitTime, TIME_DATE|TIME_SECONDS) : ""),
             (exitPrice > 0 ? DoubleToString(exitPrice, _Digits) : ""),
             DoubleToString(virtualSL, _Digits),
             barsHeld,
             DoubleToString(rsiSlow, 2),
             DoubleToString(rsiFast, 2),
             exitReason,
             DoubleToString(profitPips, 2));

   FileFlush(g_CsvHandle);
}

//+------------------------------------------------------------------+
void OutputStatusToScreen()
{
   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   string OutputText = "\n\r";

   OutputText += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " (OPERATING AT UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   OutputText += "RULE: XAUUSD_M1_70 (RSI21<" + DoubleToString(RSI_Slow_Threshold,1) + " AND RSI7<" + DoubleToString(RSI_Fast_Threshold,1) + ")\n\r";
   OutputText += Symbol() + " TICKS RECEIVED:   " + IntegerToString(TicksReceivedCount) + "\n\r";
   OutputText += Symbol() + " TICKS PROCESSED:   " + IntegerToString(TicksProcessedCount) + "\n\r";
   OutputText += "PROCESSING METHOD:   " + EnumToString(BarProcessingMethod) + "\n\r";
   OutputText += EnumToString(TradeTimeframe) + " BAR USED FOR PROCESSING:   " + IntegerToString(iBarToUseForProcessing) + "\n\r";
   OutputText += "OPEN POSITION:   " + (HasOpenPosition() ? "YES (BarsHeld=" + IntegerToString(g_BarsHeld) + "/" + IntegerToString(HorizonBars) + ")" : "NO") + "\n\r";
   OutputText += "MAGIC NUMBER:   " + IntegerToString((long)MagicNumber) + "\n\r";

   Comment(OutputText);

   return;
}