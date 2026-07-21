//+--------------------------------------------------------------------------------+
//| ATR21_Stoch_OB_Cross_EA.mq5                                                    |
//| Signal: ATR21_rising + stoch_overbought_cross -> BULLISH (57.0% dir, 0.33 ATR) |
//| No broker SL/TP. Purely time-based (candle-count) exit.                       |
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property link        ""
#property description ""
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

input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M15;                          //Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR; //EA Bar Processing Method

input group "=== Signal Params (must mirror python indicator matrix) ==="
input int    ATR_Period          = 21;      //ATR Period (Wilder smoothing, matches iATR default)
input int    Stoch_KPeriod       = 14;      //Stochastic %K Period (python compute_stochastic default)
input int    Stoch_DPeriod       = 3;       //Stochastic %D Period
input int    Stoch_Slowing       = 1;       //Stochastic Slowing (1 = raw %K, no smoothing, matches python)
input double Stoch_OverboughtLvl = 80.0;    //Stochastic Overbought Level

input group "=== Dynamic Lot Sizing ==="
input double RiskPercent         = 1.0;     //Risk % of Equity per Trade
input double ATR_RiskMultiplier  = 1.5;     //ATR multiple used as virtual sizing distance (never sent as broker SL)
input double MinLotCap           = 0.01;    //Absolute Min Lot Cap
input double MaxLotCap           = 5.0;     //Absolute Max Lot Cap

input group "=== Trade Management ==="
input int    ExitAfterBars       = 1;       //Exit Position After N Bars (Trade TF) - Timing from report = 1
input ulong  MagicNumber         = 210725;  //Magic Number

//################
//Global Variables
//################

int      TicksReceivedCount      = 0;                    //Number of ticks received by the EA
int      TicksProcessedCount     = 0;                    //Number of ticks processed by the EA
datetime TimeLastTickProcessed   = D'1971.01.01 00:00';  //Controls processing so live matches Strategy Tester timing

int      iBarToUseForProcessing;        //Either bar 0 or bar 1, set in OnInit()

int      handleATR;
int      handleStoch;

CTrade   trade;

//+--------------------------------------------------------------------------------+
//| IsNewBar - determines whether processing should occur this tick,              |
//| per the selected BarProcessingMethod. Called at the top of OnTick().          |
//+--------------------------------------------------------------------------------+
bool IsNewBar()
{
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      return true;

   if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
   {
      datetime t = iTime(Symbol(), PERIOD_M1, 0);
      if(TimeLastTickProcessed != t)
      {
         TimeLastTickProcessed = t;
         return true;
      }
      return false;
   }

   if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
   {
      datetime t = iTime(Symbol(), TradeTimeframe, 0);
      if(TimeLastTickProcessed != t)
      {
         TimeLastTickProcessed = t;
         return true;
      }
      return false;
   }

   return false;
}

int OnInit()
{
   //################################
   //Determine which bar we will use (0 or 1) to perform processing of data
   //################################

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;

   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;    //Use last completed bar so indicator values don't repaint

   handleATR = iATR(Symbol(), TradeTimeframe, ATR_Period);
   if(handleATR == INVALID_HANDLE)
   {
      Print("FAILED TO CREATE ATR HANDLE");
      return(INIT_FAILED);
   }

   handleStoch = iStochastic(Symbol(), TradeTimeframe, Stoch_KPeriod, Stoch_DPeriod, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   if(handleStoch == INVALID_HANDLE)
   {
      Print("FAILED TO CREATE STOCHASTIC HANDLE");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(Symbol());
   trade.SetDeviationInPoints(30);

   Print("EA USING " + EnumToString(BarProcessingMethod) + " PROCESSING METHOD AND INDICATORS WILL USE BAR " + IntegerToString(iBarToUseForProcessing));

   OutputStatusToScreen();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(handleATR   != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleStoch != INVALID_HANDLE) IndicatorRelease(handleStoch);
   Comment("");
}

void OnTick()
{
   TicksReceivedCount++;

   bool ProcessThisIteration = IsNewBar();

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;

      ProcessTradeClosures();
      ProcessTradeOpens();
   }

   OutputStatusToScreen();
}

//+--------------------------------------------------------------------------------+
//| Time-based exit only. No SL/TP is ever used - positions are closed purely on  |
//| candle count (ExitAfterBars measured in TradeTimeframe bars since open).      |
//+--------------------------------------------------------------------------------+
void ProcessTradeClosures()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int barsSinceOpen = iBarShift(Symbol(), TradeTimeframe, openTime, false);

      if(barsSinceOpen >= ExitAfterBars)
      {
         trade.PositionClose(ticket);
      }
   }
}

void ProcessTradeOpens()
{
   //Only one position at a time for this signal
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol() && (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return;
   }

   double atrCurrent;
   if(!CheckSignal(atrCurrent))
      return;

   double price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double lot   = CalculateDynamicLot(atrCurrent);

   //No SL/TP passed - broker-side stop loss / take profit are never used
   trade.PositionOpen(Symbol(), ORDER_TYPE_BUY, lot, price, 0.0, 0.0, "ATR21_rising+stoch_ob_cross");
}

//+--------------------------------------------------------------------------------+
//| CheckSignal - ATR21_rising + stoch_overbought_cross, evaluated on              |
//| iBarToUseForProcessing (last completed bar for the trade TF method).          |
//| Definitions mirror the python indicator matrix exactly:                       |
//|   ATR_21_RISING           = ATR[t] > ATR[t-1]                                 |
//|   STOCH_OVERBOUGHT_CROSS  = K[t] < 80 AND K[t-1] >= 80  (cross DOWN through)  |
//| outATRCurrent returns the ATR value used, for dynamic lot sizing.             |
//+--------------------------------------------------------------------------------+
bool CheckSignal(double &outATRCurrent)
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(handleATR, 0, 0, iBarToUseForProcessing + 2, atrBuf) < iBarToUseForProcessing + 2)
      return false;

   double atrCurrent  = atrBuf[iBarToUseForProcessing];
   double atrPrevious = atrBuf[iBarToUseForProcessing + 1];
   bool   atrRising    = (atrCurrent > atrPrevious);
   outATRCurrent = atrCurrent;

   double stochMain[];
   ArraySetAsSeries(stochMain, true);
   if(CopyBuffer(handleStoch, MAIN_LINE, 0, iBarToUseForProcessing + 2, stochMain) < iBarToUseForProcessing + 2)
      return false;

   double kCurrent  = stochMain[iBarToUseForProcessing];
   double kPrevious = stochMain[iBarToUseForProcessing + 1];

   //Overbought cross = %K crosses DOWN through the overbought level (matches python STOCH_OVERBOUGHT_CROSS)
   bool overboughtCross = (kPrevious >= Stoch_OverboughtLvl && kCurrent < Stoch_OverboughtLvl);

   return(atrRising && overboughtCross);
}

//+--------------------------------------------------------------------------------+
//| CalculateDynamicLot - sizes the position as RiskPercent of equity, using       |
//| (ATR * ATR_RiskMultiplier) as a VIRTUAL risk distance. This distance is used  |
//| only for the sizing formula below - it is never sent to the broker as a       |
//| stop loss. No SL order is ever placed, per standing convention.               |
//+--------------------------------------------------------------------------------+
double CalculateDynamicLot(double atrValue)
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (RiskPercent / 100.0);

   double riskDistance = atrValue * ATR_RiskMultiplier;
   if(riskDistance <= 0.0)
      return NormalizeLot(MinLotCap);

   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      return NormalizeLot(MinLotCap);

   double valuePerPriceUnit = tickValue / tickSize;   //account currency value of a 1.0-price move, per 1.0 lot
   double lot = riskAmount / (riskDistance * valuePerPriceUnit);

   lot = MathMax(MinLotCap, MathMin(MaxLotCap, lot));

   return NormalizeLot(lot);
}

//+--------------------------------------------------------------------------------+
//| Normalizes lot size to the symbol's volume step/min/max                       |
//+--------------------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   lot = MathRound(lot / stepLot) * stepLot;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   return lot;
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
   OutputText += "SYMBOL BEING TRADED:   " + Symbol() + "\n\r";
   OutputText += "TRADING TIMEFRAME:   " + EnumToString(TradeTimeframe) + "\n\r\n\r";

   OutputText += "SIGNAL: ATR21_rising + stoch_overbought_cross (BULLISH ONLY)\n\r";
   OutputText += "ATR PERIOD:   " + IntegerToString(ATR_Period) + "\n\r";
   OutputText += "STOCH(" + IntegerToString(Stoch_KPeriod) + "," + IntegerToString(Stoch_DPeriod) + "," + IntegerToString(Stoch_Slowing) + ")  OB LEVEL: " + DoubleToString(Stoch_OverboughtLvl, 1) + " (cross DOWN through)\n\r";
   OutputText += "RISK % PER TRADE:   " + DoubleToString(RiskPercent, 2) + "%  |  ATR RISK MULT:   " + DoubleToString(ATR_RiskMultiplier, 2) + " (sizing only, no broker SL)\n\r";
   OutputText += "EXIT AFTER BARS:   " + IntegerToString(ExitAfterBars) + " (NO SL/TP USED)\n\r";
   OutputText += "OPEN POSITIONS (MAGIC " + IntegerToString((int)MagicNumber) + "):   " + IntegerToString(CountOwnPositions()) + "\n\r\n\r";

   Comment(OutputText);

   return;
}

int CountOwnPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol() && (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}