//+------------------------------------------------------------------+
//|              RSI_ADX_EMA_MACD_GridMartingale_EA.mq5              |
//|                                                                  |
//|  Signal (level-1 trigger only) :                                |
//|            RSI14_deep_oversold + ADX_trending                   |
//|            + EMA21_below_EMA50 + EMA50_above_EMA100             |
//|            + MACD_bear_cross                                    |
//|  Direction: BULLISH (grid/martingale add-on version)            |
//|                                                                  |
//|  IMPORTANT — how this differs from the original EA:             |
//|  - No SL/TP is EVER sent to the broker (req.sl / req.tp are     |
//|    always 0.0). All risk control is done in EA code.             |
//|  - After the first entry, additional BUY orders ("grid levels") |
//|    are added automatically whenever price moves against the     |
//|    basket by InpGridStepPoints, with lot size multiplied by      |
//|    InpLotMultiplier each time (classic martingale grid).         |
//|  - The ENTIRE basket is closed together in only two cases:       |
//|      1) Normal exit  -> combined floating P/L of the basket      |
//|                          is >= InpMinBasketProfit (i.e. it only  |
//|                          closes in profit).                      |
//|      2) Emergency exit -> combined floating LOSS of the basket   |
//|                          reaches InpFloatingLossPercent of the   |
//|                          account balance. This is a manual,      |
//|                          code-side kill-switch, NOT a broker SL. |
//|                                                                  |
//|  BAR-PROCESSING FRAMEWORK (adapted from                          |
//|  control-bar-opening-single-symbol.mq5):                        |
//|  - TradeTimeframe is the timeframe indicators/logic run on       |
//|    (e.g. PERIOD_M5). All indicator handles are built on this TF, |
//|    NOT on the chart's own period.                                |
//|  - BarProcessingMethod controls WHEN OnTick actually evaluates    |
//|    the strategy:                                                  |
//|      PROCESS_ALL_DELIVERED_TICKS            -> every tick         |
//|      ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR     -> once per new M1    |
//|                                                 bar, but reading   |
//|                                                 the CURRENT        |
//|                                                 (forming) bar 0    |
//|                                                 of TradeTimeframe  |
//|      ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR -> once per new bar |
//|                                                 of TradeTimeframe, |
//|                                                 reading the last  |
//|                                                 CLOSED bar 1       |
//|  - Default here: TradeTimeframe = M5,                             |
//|    BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,       |
//|    i.e. "run everything on M5, but check for new bars every M1."  |
//+------------------------------------------------------------------+
#property copyright "Generated EA — Grid Martingale variant"
#property version   "3.00"
#property strict

enum ENUM_BAR_PROCESSING_METHOD
{
   PROCESS_ALL_DELIVERED_TICKS,               //Process All Delivered Ticks
   ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR,        //Only Process Ticks From New M1 Bar
   ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR   //Only Process Ticks From New Bar in Trade TF
};

//=== INPUT PARAMETERS ===============================================
input group            "── Bar Processing Framework ──"
input ENUM_TIMEFRAMES            TradeTimeframe      = PERIOD_M5;                          // Timeframe used for indicators/logic
input ENUM_BAR_PROCESSING_METHOD BarProcessingMethod = ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR;  // When OnTick actually processes

input group            "── Base Trade Settings ──"
input double           InpLotSize       = 0.1;    // Base Lot Size (grid level 1)
input ulong            InpMagicNumber   = 202401; // Magic Number

input group            "── Grid / Martingale Settings ──"
input int              InpGridStepPoints   = 300;  // Distance (points) before adding next grid level
input double           InpLotMultiplier    = 1.6;  // Lot multiplier applied on each new grid level
input int              InpMaxGridLevels    = 6;    // Maximum number of grid levels (including first entry)

input group            "── Basket Exit Settings (profit-only) ──"
input double           InpMinBasketProfit  = 0.0;  // Close ALL when basket floating P/L (in account currency) >= this. 0 = any profit

input group            "── Emergency Risk Control (no broker SL/TP) ──"
input double           InpFloatingLossPercent = 5.0; // Force-close ALL if floating loss >= this % of account balance

input group            "── RSI Settings ──"
input int              InpRSIPeriod     = 14;     // RSI Period
input double           InpRSIDeepLevel  = 25.0;   // RSI Deep Oversold Threshold (<)

input group            "── ADX Settings ──"
input int              InpADXPeriod     = 14;     // ADX Period
input double           InpADXLevel      = 25.0;   // ADX Trending Threshold (>)

input group            "── EMA Settings ──"
input int              InpEMA21Period   = 21;     // EMA Fast Period
input int              InpEMA50Period   = 50;     // EMA Mid Period
input int              InpEMA100Period  = 100;    // EMA Slow Period

input group            "── MACD Settings ──"
input int              InpMACDFast      = 12;     // MACD Fast EMA
input int              InpMACDSlow      = 26;     // MACD Slow EMA
input int              InpMACDSignal    = 9;      // MACD Signal Period

//=== GLOBAL VARIABLES ===============================================
int      hRSI, hADX, hEMA21, hEMA50, hEMA100, hMACD;

int      iBarToUseForProcessing;                          // Set in OnInit() based on BarProcessingMethod
datetime TimeLastTickProcessed  = D'1971.01.01 00:00';     // Seeded in the past so the first real tick always processes
int      TicksReceivedCount     = 0;
int      TicksProcessedCount    = 0;

//+------------------------------------------------------------------+
//|  OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicators are built on TradeTimeframe, not on the chart's own _Period
   hRSI    = iRSI (_Symbol, TradeTimeframe, InpRSIPeriod,   PRICE_CLOSE);
   hADX    = iADX (_Symbol, TradeTimeframe, InpADXPeriod);
   hEMA21  = iMA  (_Symbol, TradeTimeframe, InpEMA21Period,  0, MODE_EMA, PRICE_CLOSE);
   hEMA50  = iMA  (_Symbol, TradeTimeframe, InpEMA50Period,  0, MODE_EMA, PRICE_CLOSE);
   hEMA100 = iMA  (_Symbol, TradeTimeframe, InpEMA100Period, 0, MODE_EMA, PRICE_CLOSE);
   hMACD   = iMACD(_Symbol, TradeTimeframe, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   if(hRSI    == INVALID_HANDLE ||
      hADX    == INVALID_HANDLE ||
      hEMA21  == INVALID_HANDLE ||
      hEMA50  == INVALID_HANDLE ||
      hEMA100 == INVALID_HANDLE ||
      hMACD   == INVALID_HANDLE)
   {
      Print("❌ Failed to create indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
   }

   if(InpMaxGridLevels < 1)
   {
      Print("❌ InpMaxGridLevels must be >= 1");
      return INIT_FAILED;
   }

   //--- Determine which bar (0 = forming, 1 = last closed) of TradeTimeframe to read indicators from
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      iBarToUseForProcessing = 0;              // every tick -> only bar 0's value is meaningful to re-check
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
      iBarToUseForProcessing = 0;              // gated by M1, but TradeTimeframe bar 0 is still forming -> use bar 0
   else if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
      iBarToUseForProcessing = 1;              // gated by TradeTimeframe itself -> use the last CLOSED bar

   PrintFormat("✅ Grid-Martingale EA initialized | TradeTimeframe=%s | BarProcessingMethod=%s | Bar used=%d",
               EnumToString(TradeTimeframe), EnumToString(BarProcessingMethod), iBarToUseForProcessing);

   int warmUp = MathMax(InpEMA100Period, InpMACDSlow + InpMACDSignal) + 10;
   Print("   Warm-up bars needed on TradeTimeframe: ", warmUp);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  OnDeinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   IndicatorRelease(hADX);
   IndicatorRelease(hEMA21);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hEMA100);
   IndicatorRelease(hMACD);
   Comment("");
   Print("🔴 EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//|  ShouldProcessThisTick                                           |
//|  Implements the same gating logic as                             |
//|  control-bar-opening-single-symbol.mq5, driven by                |
//|  BarProcessingMethod. Updates TimeLastTickProcessed as needed.    |
//+------------------------------------------------------------------+
bool ShouldProcessThisTick()
{
   if(BarProcessingMethod == PROCESS_ALL_DELIVERED_TICKS)
      return true;

   if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_M1_BAR)
   {
      datetime m1BarTime = iTime(_Symbol, PERIOD_M1, 0);
      if(TimeLastTickProcessed != m1BarTime)
      {
         TimeLastTickProcessed = m1BarTime;
         return true;
      }
      return false;
   }

   if(BarProcessingMethod == ONLY_PROCESS_TICKS_FROM_NEW_TRADE_TF_BAR)
   {
      datetime tfBarTime = iTime(_Symbol, TradeTimeframe, 0);
      if(TimeLastTickProcessed != tfBarTime)
      {
         TimeLastTickProcessed = tfBarTime;
         return true;
      }
      return false;
   }

   return false;
}

//+------------------------------------------------------------------+
//|  ReadIndicators                                                  |
//|  Reads from iBarToUseForProcessing on TradeTimeframe (0 = the     |
//|  currently forming bar, 1 = the last fully closed bar).          |
//+------------------------------------------------------------------+
bool ReadIndicators(double &rsi,   double &adx,
                    double &ema21, double &ema50, double &ema100,
                    double &macd,  double &sig)
{
   double buf[1];
   int    p = iBarToUseForProcessing;

   if(CopyBuffer(hRSI,    0, p, 1, buf) < 1) return false; rsi    = buf[0];
   if(CopyBuffer(hADX,    0, p, 1, buf) < 1) return false; adx    = buf[0];
   if(CopyBuffer(hEMA21,  0, p, 1, buf) < 1) return false; ema21  = buf[0];
   if(CopyBuffer(hEMA50,  0, p, 1, buf) < 1) return false; ema50  = buf[0];
   if(CopyBuffer(hEMA100, 0, p, 1, buf) < 1) return false; ema100 = buf[0];
   if(CopyBuffer(hMACD,   0, p, 1, buf) < 1) return false; macd   = buf[0];
   if(CopyBuffer(hMACD,   1, p, 1, buf) < 1) return false; sig    = buf[0];

   return true;
}

//+------------------------------------------------------------------+
//|  CheckEntrySignal — used ONLY to trigger grid level 1            |
//+------------------------------------------------------------------+
bool CheckEntrySignal()
{
   double rsi, adx, ema21, ema50, ema100, macd, sig;
   if(!ReadIndicators(rsi, adx, ema21, ema50, ema100, macd, sig))
   {
      Print("⚠️ ReadIndicators failed.");
      return false;
   }

   bool c1 = (rsi   < InpRSIDeepLevel);
   bool c2 = (adx   > InpADXLevel);
   bool c3 = (ema21 < ema50);
   bool c4 = (ema50 > ema100);
   bool c5 = (macd  < sig);

   if(c1 && c2 && c3 && c4 && c5)
   {
      PrintFormat("🟢 SIGNAL (grid level 1) | RSI=%.2f | ADX=%.2f | EMA21=%.5f < EMA50=%.5f | "
                  "EMA50=%.5f > EMA100=%.5f | MACD=%.5f < Sig=%.5f",
                  rsi, adx, ema21, ema50, ema50, ema100, macd, sig);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|  BasketSnapshot                                                  |
//|  Scans all open positions for this Symbol+Magic and returns      |
//|  aggregate stats used for grid/exit decisions.                   |
//+------------------------------------------------------------------+
void BasketSnapshot(int &count, double &totalVolume, double &floatingPL,
                     double &lowestOpenPrice, double &lastLotSize)
{
   count           = 0;
   totalVolume     = 0.0;
   floatingPL      = 0.0;
   lowestOpenPrice = DBL_MAX;
   lastLotSize     = 0.0;

   datetime lastOpenTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol)        continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      count++;
      double vol = PositionGetDouble(POSITION_VOLUME);
      totalVolume += vol;
      floatingPL  += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(openPrice < lowestOpenPrice) lowestOpenPrice = openPrice;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime >= lastOpenTime)
      {
         lastOpenTime = openTime;
         lastLotSize  = vol;
      }
   }

   if(count == 0) lowestOpenPrice = 0.0;
}

//+------------------------------------------------------------------+
//|  SendMarketOrder — BUY only, NEVER sets sl/tp                    |
//+------------------------------------------------------------------+
bool SendMarketOrder(double lots, const string comment)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = NormalizeDouble(lots, 2);
   req.type         = ORDER_TYPE_BUY;
   req.price        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.deviation    = 20;
   req.magic        = InpMagicNumber;
   req.sl           = 0.0;   // explicitly NO broker stop loss
   req.tp           = 0.0;   // explicitly NO broker take profit
   req.comment      = comment;

   if(!OrderSend(req, res))
   {
      PrintFormat("❌ OrderSend BUY failed | retcode=%d | %s", res.retcode, res.comment);
      return false;
   }

   PrintFormat("✅ BUY opened | Lots=%.2f | Price=%.5f | Comment=%s",
               req.volume, req.price, comment);
   return true;
}

//+------------------------------------------------------------------+
//|  CloseBasket                                                     |
//|  Market-closes every position belonging to this EA (all grid     |
//|  levels), used for both the profit exit and the emergency exit.  |
//+------------------------------------------------------------------+
void CloseBasket(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol)        continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = _Symbol;
      req.volume       = PositionGetDouble(POSITION_VOLUME);
      req.type         = ORDER_TYPE_SELL;
      req.price        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      req.deviation    = 20;
      req.magic        = InpMagicNumber;
      req.position     = ticket;
      req.comment      = reason;

      if(!OrderSend(req, res))
         PrintFormat("❌ Close failed for ticket %I64u | retcode=%d | %s", ticket, res.retcode, res.comment);
      else
         PrintFormat("🔴 Closed ticket %I64u | Reason=%s | P&L=%.2f",
                     ticket, reason, PositionGetDouble(POSITION_PROFIT));
   }
}

//+------------------------------------------------------------------+
//|  OutputStatusToScreen — informational only                       |
//+------------------------------------------------------------------+
void OutputStatusToScreen(int count, double floatingPL)
{
   string txt = "\n\r";
   txt += Symbol() + " | TradeTimeframe: " + EnumToString(TradeTimeframe) + "\n\r";
   txt += "Bar Processing Method: " + EnumToString(BarProcessingMethod) + " (bar " + IntegerToString(iBarToUseForProcessing) + ")\n\r";
   txt += "Ticks Received: " + IntegerToString(TicksReceivedCount) + "   Ticks Processed: " + IntegerToString(TicksProcessedCount) + "\n\r";
   txt += "Open Grid Levels: " + IntegerToString(count) + "   Floating P/L: " + DoubleToString(floatingPL, 2) + "\n\r";
   Comment(txt);
}

//+------------------------------------------------------------------+
//|  OnTick — main logic                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

   //--- Gate everything below using the bar-processing framework
   if(!ShouldProcessThisTick())
      return;

   TicksProcessedCount++;

   int    count;
   double totalVolume, floatingPL, lowestOpenPrice, lastLotSize;
   BasketSnapshot(count, totalVolume, floatingPL, lowestOpenPrice, lastLotSize);

   //=== 1) EMERGENCY EQUITY PROTECTION (highest priority) ===
   if(count > 0)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance > 0.0 && floatingPL < 0.0)
      {
         double lossPercent = (-floatingPL / balance) * 100.0;
         if(lossPercent >= InpFloatingLossPercent)
         {
            PrintFormat("🛑 EMERGENCY CLOSE | Floating loss %.2f%% >= threshold %.2f%% | P&L=%.2f",
                        lossPercent, InpFloatingLossPercent, floatingPL);
            CloseBasket("EmergencyLossClose");
            OutputStatusToScreen(0, 0.0);
            return;
         }
      }
   }

   //=== 2) PROFIT-ONLY BASKET EXIT ===
   if(count > 0 && floatingPL >= InpMinBasketProfit)
   {
      PrintFormat("💰 BASKET PROFIT CLOSE | Levels=%d | Volume=%.2f | P&L=%.2f (target %.2f)",
                  count, totalVolume, floatingPL, InpMinBasketProfit);
      CloseBasket("BasketProfitClose");
      OutputStatusToScreen(0, 0.0);
      return;
   }

   //=== 3) GRID MARTINGALE ADD-ON ===
   if(count > 0 && count < InpMaxGridLevels)
   {
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double gridDist = InpGridStepPoints * _Point;

      if(ask <= lowestOpenPrice - gridDist)
      {
         double nextLot = NormalizeDouble(lastLotSize * InpLotMultiplier, 2);
         PrintFormat("➕ GRID ADD | Level=%d | New Lot=%.2f | Ask=%.5f <= Lowest %.5f - %.5f",
                     count + 1, nextLot, ask, lowestOpenPrice, gridDist);
         SendMarketOrder(nextLot, StringFormat("GridLevel_%d", count + 1));
      }
      OutputStatusToScreen(count, floatingPL);
      return;
   }

   //=== 4) FRESH GRID LEVEL 1 ENTRY (only if flat) ===
   if(count == 0)
   {
      if(CheckEntrySignal())
         SendMarketOrder(InpLotSize, "GridLevel_1");
   }

   OutputStatusToScreen(count, floatingPL);
}
//+------------------------------------------------------------------+