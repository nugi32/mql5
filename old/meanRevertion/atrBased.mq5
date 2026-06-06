//+-----------------------------------------------------------------------------------+
//| MeanReversion_XAUUSD_M15.mq5                                                     |
//|                                                                                   |
//| Mean Reversion Strategy for XAUUSD M15                                           |
//| Logic : Price deviates X*ATR from a Moving Average → expect reversion to mean    |
//| Entry : BUY  when Ask < MA - (EntryATRMultiplier * ATR)  (price too far below)   |
//|         SELL when Bid > MA + (EntryATRMultiplier * ATR)  (price too far above)   |
//| SL    : Entry ± SL_ATRMultiplier * ATR                                           |
//| TP    : Moving Average (the mean we revert to)                                   |
//| Lots  : Derived from RiskPercent and SL distance in pips/points                  |
//| Bar   : Processed on every NEW M1 bar (ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)      |
//|                                                                                   |
//| DISCLAIMER: FOR EDUCATIONAL / ILLUSTRATIVE PURPOSES ONLY.                        |
//| Trading involves risk. Past performance does not guarantee future results.        |
//+-----------------------------------------------------------------------------------+

#property copyright  "Custom"
#property strict

//============================
// ENUMS (from base framework)
//============================
enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               // Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        // Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   // Only Process Ticks From New Bar in Trade TF
};

//==============
// INPUT PARAMS
//==============
input group                        "=== Core Settings ==="
input ENUM_TIMEFRAMES              TradeTimeframe       = PERIOD_M15;                         // Trading Timeframe
input ENUM_BAR_PROCESSING_METHOD   BarProcessingMethod  = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR; // Bar Processing Method (fixed to M1)

input group                        "=== Moving Average (Mean) ==="
input int                          MA_Period            = 50;                  // MA Period
input ENUM_MA_METHOD               MA_Method            = MODE_EMA;           // MA Method
input ENUM_APPLIED_PRICE           MA_AppliedPrice      = PRICE_CLOSE;        // MA Applied Price

input group                        "=== ATR Settings ==="
input int                          ATR_Period           = 14;                  // ATR Period
input double                       EntryATRMultiplier   = 1.5;                 // Entry Distance (X * ATR from MA)
input double                       SL_ATRMultiplier     = 2.0;                 // Stop Loss Distance (X * ATR from entry)

input group                        "=== Risk Management ==="
input double                       RiskPercent          = 1.0;                 // Risk Per Trade (% of balance)
input double                       MaxSpreadPoints      = 30.0;                // Max allowed spread in points (skip trade if wider)

input group                        "=== Trade Settings ==="
input ulong                        MagicNumber          = 20240101;            // EA Magic Number
input string                       TradeComment         = "MR_XAUUSD_M15";    // Trade Comment
input int                          MaxOpenTrades        = 1;                   // Max open positions at once

//=================
// GLOBAL VARIABLES
//=================
int      TicksReceivedCount     = 0;
int      TicksProcessedCount    = 0;
datetime TimeLastTickProcessed  = D'1971.01.01 00:00';
int      iBarToUseForProcessing = 0;

// Indicator handles
int      hMA  = INVALID_HANDLE;
int      hATR = INVALID_HANDLE;

//========
// OnInit
//========
int OnInit()
{
   // Validate symbol
   if(Symbol() != "XAUUSD")
      Print("WARNING: This EA is designed for XAUUSD. Current symbol: ", Symbol());

   // Fix bar processing to M1 as per requirement
   iBarToUseForProcessing = 0;  // Always bar 0 for M1-based processing

   // Create indicator handles
   hMA  = iMA(Symbol(), TradeTimeframe, MA_Period, 0, MA_Method, MA_AppliedPrice);
   hATR = iATR(Symbol(), TradeTimeframe, ATR_Period);

   if(hMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles. EA will not run.");
      return INIT_FAILED;
   }

   Print("EA INITIALIZED | Symbol: ", Symbol(),
         " | TF: ", EnumToString(TradeTimeframe),
         " | Processing: ", EnumToString(BarProcessingMethod),
         " | Bar Used: ", iBarToUseForProcessing);

   OutputStatusToScreen();
   return INIT_SUCCEEDED;
}

//=========
// OnDeinit
//=========
void OnDeinit(const int reason)
{
   if(hMA  != INVALID_HANDLE) IndicatorRelease(hMA);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
}

//========
// OnTick
//========
void OnTick()
{
   TicksReceivedCount++;

   //--- Control: only process at desired intervals
   bool ProcessThisIteration = false;

   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
   {
      ProcessThisIteration = true;
   }
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), PERIOD_M1, 0))
      {
         ProcessThisIteration    = true;
         TimeLastTickProcessed   = iTime(Symbol(), PERIOD_M1, 0);
      }
   }
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
   {
      if(TimeLastTickProcessed != iTime(Symbol(), TradeTimeframe, 0))
      {
         ProcessThisIteration    = true;
         TimeLastTickProcessed   = iTime(Symbol(), TradeTimeframe, 0);
      }
   }

   //--- Main processing block
   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      ProcessTradeClosures();
      ProcessTradeOpens();
   }

   OutputStatusToScreen();
}

//========================
// INDICATOR DATA HELPERS
//========================

// Returns MA value at bar index, or 0.0 on failure
double GetMA(int barIndex)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hMA, 0, 0, barIndex + 2, buf) < barIndex + 2)
   {
      Print("ERROR: CopyBuffer MA failed");
      return 0.0;
   }
   return buf[barIndex];
}

// Returns ATR value at bar index, or 0.0 on failure
double GetATR(int barIndex)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hATR, 0, 0, barIndex + 2, buf) < barIndex + 2)
   {
      Print("ERROR: CopyBuffer ATR failed");
      return 0.0;
   }
   return buf[barIndex];
}

//======================
// POSITION COUNT HELPER
//======================
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != Symbol())    continue;
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;
      count++;
   }
   return count;
}

//===================
// LOT SIZE CALCULATOR
//===================
// Calculates lot size based on account balance, risk %, and SL in points
double CalculateLotSize(double slPoints)
{
   if(slPoints <= 0) return 0.0;

   double accountBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount      = accountBalance * (RiskPercent / 100.0);  // $ at risk
   double tickValue       = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize        = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double point           = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   // Value per point per lot
   double valuePerPointPerLot = (tickValue / tickSize) * point;
   if(valuePerPointPerLot <= 0) return 0.0;

   double lots = riskAmount / (slPoints * valuePerPointPerLot);

   // Clamp to broker limits
   double minLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;  // Round down to lot step
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
}

//======================
// PROCESS TRADE CLOSURES
//======================
// Mean reversion: close if price has crossed back to MA
void ProcessTradeClosures()
{
   double maValue = GetMA(iBarToUseForProcessing);
   if(maValue == 0.0) return;

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != Symbol())         continue;
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;

      long posType = PositionGetInteger(POSITION_TYPE);

      // BUY: close when price rises back to or above MA
      if(posType == POSITION_TYPE_BUY && bid >= maValue)
      {
         if(!ClosePosition(ticket))
            Print("WARNING: Failed to close BUY position #", ticket);
         else
            Print("CLOSED BUY #", ticket, " | Bid: ", bid, " | MA: ", maValue);
      }
      // SELL: close when price falls back to or below MA
      else if(posType == POSITION_TYPE_SELL && ask <= maValue)
      {
         if(!ClosePosition(ticket))
            Print("WARNING: Failed to close SELL position #", ticket);
         else
            Print("CLOSED SELL #", ticket, " | Ask: ", ask, " | MA: ", maValue);
      }
   }
}

//====================
// CLOSE SINGLE POSITION (no CTrade - raw MQL5 trade request)
//====================
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;

   long   posType  = PositionGetInteger(POSITION_TYPE);
   double posVol   = PositionGetDouble(POSITION_VOLUME);
   string posSym   = PositionGetString(POSITION_SYMBOL);

   MqlTradeRequest  request = {};
   MqlTradeResult   result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = posSym;
   request.volume    = posVol;
   request.type      = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price     = (posType == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(posSym, SYMBOL_BID)
                          : SymbolInfoDouble(posSym, SYMBOL_ASK);
   request.deviation = 10;
   request.magic     = MagicNumber;
   request.comment   = TradeComment + "_CLOSE";
   request.position  = ticket;

   if(!OrderSend(request, result))
   {
      Print("ClosePosition OrderSend error: ", GetLastError(), " | Retcode: ", result.retcode);
      return false;
   }
   return (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED);
}

//====================
// PROCESS TRADE OPENS
//====================
void ProcessTradeOpens()
{
   // Skip if already at max trades
   if(CountOpenPositions() >= MaxOpenTrades) return;

   double maValue  = GetMA(iBarToUseForProcessing);
   double atrValue = GetATR(iBarToUseForProcessing);

   if(maValue == 0.0 || atrValue == 0.0) return;

   double ask    = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spread = ask - bid;
   double point  = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   // Check spread guard
   if(spread / point > MaxSpreadPoints)
   {
      Print("SPREAD TOO WIDE: ", spread / point, " points. Skipping.");
      return;
   }

   double entryZone = EntryATRMultiplier * atrValue;  // Distance from MA to trigger entry
   double slDist    = SL_ATRMultiplier   * atrValue;  // SL distance from entry price

   //--- BUY signal: Ask is sufficiently below MA (price too cheap → expect rise)
   bool buySignal  = (ask < maValue - entryZone);

   //--- SELL signal: Bid is sufficiently above MA (price too expensive → expect fall)
   bool sellSignal = (bid > maValue + entryZone);

   if(buySignal)
   {
      double entryPrice = ask;
      double slPrice    = entryPrice - slDist;
      double tpPrice    = maValue;  // TP = the mean

      // Normalise prices
      int    digits    = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
      slPrice          = NormalizeDouble(slPrice,    digits);
      tpPrice          = NormalizeDouble(tpPrice,    digits);

      double slPoints  = (entryPrice - slPrice) / point;
      double lots      = CalculateLotSize(slPoints);

      if(lots <= 0)
      {
         Print("BUY: Lot size calculation returned 0. Skipping.");
         return;
      }

      Print("BUY SIGNAL | Entry: ", entryPrice,
            " | MA: ", maValue, " | ATR: ", atrValue,
            " | SL: ", slPrice, " | TP: ", tpPrice,
            " | Lots: ", lots);

      SendMarketOrder(ORDER_TYPE_BUY, lots, entryPrice, slPrice, tpPrice);
   }
   else if(sellSignal)
   {
      double entryPrice = bid;
      double slPrice    = entryPrice + slDist;
      double tpPrice    = maValue;  // TP = the mean

      int    digits    = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
      slPrice          = NormalizeDouble(slPrice,    digits);
      tpPrice          = NormalizeDouble(tpPrice,    digits);

      double slPoints  = (slPrice - entryPrice) / point;
      double lots      = CalculateLotSize(slPoints);

      if(lots <= 0)
      {
         Print("SELL: Lot size calculation returned 0. Skipping.");
         return;
      }

      Print("SELL SIGNAL | Entry: ", entryPrice,
            " | MA: ", maValue, " | ATR: ", atrValue,
            " | SL: ", slPrice, " | TP: ", tpPrice,
            " | Lots: ", lots);

      SendMarketOrder(ORDER_TYPE_SELL, lots, entryPrice, slPrice, tpPrice);
   }
}

//=====================
// SEND MARKET ORDER (raw MQL5 - no CTrade)
//=====================
bool SendMarketOrder(ENUM_ORDER_TYPE orderType, double lots,
                     double price, double sl, double tp)
{
   MqlTradeRequest  request = {};
   MqlTradeResult   result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = Symbol();
   request.volume    = lots;
   request.type      = orderType;
   request.price     = price;
   request.sl        = sl;
   request.tp        = tp;
   request.deviation = 10;
   request.magic     = MagicNumber;
   request.comment   = TradeComment;
   request.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
   {
      Print("SendMarketOrder error: ", GetLastError(),
            " | Retcode: ", result.retcode,
            " | Type: ", EnumToString(orderType));
      return false;
   }

   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("ORDER SENT SUCCESSFULLY | Ticket: ", result.order,
            " | Type: ", EnumToString(orderType),
            " | Lots: ", lots,
            " | Price: ", result.price);
      return true;
   }

   Print("ORDER NOT ACCEPTED | Retcode: ", result.retcode);
   return false;
}

//=======================
// OUTPUT STATUS TO SCREEN
//=======================
void OutputStatusToScreen()
{
   double maValue  = GetMA(iBarToUseForProcessing);
   double atrValue = GetATR(iBarToUseForProcessing);
   double bid      = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask      = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double point    = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double spread   = (ask - bid) / point;

   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   string txt = "\n\r";
   txt += "=== MEAN REVERSION EA | " + Symbol() + " " + EnumToString(TradeTimeframe) + " ===\n\r\n\r";
   txt += "MT5 SERVER TIME : " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)
        + " (UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   txt += "--- Bar Control ---\n\r";
   txt += "Processing Method  : " + EnumToString(BarProcessingMethod) + "\n\r";
   txt += "Ticks Received     : " + IntegerToString(TicksReceivedCount)   + "\n\r";
   txt += "Ticks Processed    : " + IntegerToString(TicksProcessedCount)  + "\n\r";
   txt += "Bar Used           : " + IntegerToString(iBarToUseForProcessing) + "\n\r\n\r";

   txt += "--- Market ---\n\r";
   txt += "Bid / Ask          : " + DoubleToString(bid, _Digits) + " / " + DoubleToString(ask, _Digits) + "\n\r";
   txt += "Spread             : " + StringFormat("%.1f", spread) + " pts"
        + (spread > MaxSpreadPoints ? "  !! WIDE !!" : "") + "\n\r\n\r";

   txt += "--- Indicators ---\n\r";
   txt += "MA(" + IntegerToString(MA_Period) + ")          : " + DoubleToString(maValue, _Digits) + "\n\r";
   txt += "ATR(" + IntegerToString(ATR_Period) + ")         : " + DoubleToString(atrValue, _Digits) + "\n\r";
   txt += "Entry Zone         : MA ± " + DoubleToString(EntryATRMultiplier * atrValue, _Digits)
        + "  (" + StringFormat("%.1f", EntryATRMultiplier) + " × ATR)\n\r";

   double entryBuyLevel  = maValue - (EntryATRMultiplier * atrValue);
   double entrySellLevel = maValue + (EntryATRMultiplier * atrValue);
   txt += "BUY  if Ask < " + DoubleToString(entryBuyLevel,  _Digits) + "\n\r";
   txt += "SELL if Bid > " + DoubleToString(entrySellLevel, _Digits) + "\n\r\n\r";

   txt += "--- Risk ---\n\r";
   txt += "Risk Per Trade     : " + StringFormat("%.2f", RiskPercent) + "%\n\r";
   txt += "Open Positions     : " + IntegerToString(CountOpenPositions())
        + " / " + IntegerToString(MaxOpenTrades) + "\n\r";
   txt += "Account Balance    : " + StringFormat("%.2f", AccountInfoDouble(ACCOUNT_BALANCE))
        + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n\r";

   Comment(txt);
}