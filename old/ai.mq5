//+------------------------------------------------------------------+
//|                     StraddleBreakoutEA.mq5                       |
//|  Places buy-stop + sell-stop at a set time, manages risk,        |
//|  OCO, break-even and trailing stop. MQL5 only.                   |
//+------------------------------------------------------------------+
#property copyright "StraddleBreakout EA"
#property link      ""
#property version   "1.00"
#property description "Time-based straddle with ATR/percent distances, risk sizing, OCO, BE and trailing stop."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//===================================================================
//  INPUT PARAMETERS
//===================================================================

input group "══════════  General  ══════════"
input int             InpMagicNumber            = 12345;      // Magic Number
input string          InpEntryTime              = "06:00";    // Entry Time  (HH:MM, broker time)
input string          InpDeletionTime           = "22:00";    // Deletion Time (HH:MM, broker time)
input bool            InpCloseTradesAtDeletion  = false;      // Close Open Trades at Deletion Time
input bool            InpOCOEnabled             = true;       // OCO – cancel opposite order on fill

input group "══════════  Distance / SL / TP Mode  ══════════"
input bool            InpUseATR                 = false;      // Use ATR mode  (false = % of price)

input group "══════════  Percent Settings  ══════════"
input double          InpDistancePct            = 0.50;       // Entry Distance  (% of price)
input double          InpSLPct                  = 0.50;       // Stop Loss       (% of price)
input double          InpTPPct                  = 1.00;       // Take Profit     (% of price)

input group "══════════  ATR Settings  ══════════"
input ENUM_TIMEFRAMES InpATRTimeframe           = PERIOD_H1;  // ATR Timeframe
input int             InpATRPeriod              = 14;         // ATR Period
input double          InpATRMultEntry           = 1.00;       // ATR Multiplier – Entry Distance
input double          InpATRMultSL              = 1.00;       // ATR Multiplier – Stop Loss
input double          InpATRMultTP              = 2.00;       // ATR Multiplier – Take Profit

input group "══════════  Risk  ══════════"
input bool            InpRiskInMoney            = false;      // Risk mode: true = fixed money, false = % balance
input double          InpRiskValue              = 1.00;       // Risk amount (currency) or % of balance

input group "══════════  Break Even  ══════════"
input bool            InpUseBreakEven           = true;       // Enable Break Even
input double          InpBETrigger              = 1.00;       // BE Trigger  (% of open price  OR  ATR mult)

input group "══════════  Trailing Stop  ══════════"
input bool            InpUseTrailing            = false;      // Enable Trailing Stop
input double          InpTSTrigger              = 1.50;       // TS Trigger   (% OR ATR mult)
input double          InpTSDistance             = 1.00;       // TS Distance  (% OR ATR mult)
input double          InpTSStep                 = 0.10;       // TS Step      (% OR ATR mult)


//===================================================================
//  GLOBAL VARIABLES
//===================================================================
CTrade        g_trade;
CPositionInfo g_pos;

int           g_atrHandle          = INVALID_HANDLE;
bool          g_ordersPlacedToday  = false;   // prevents double-placement per day
bool          g_deletionDoneToday  = false;   // prevents double-deletion per day
bool          g_ocoFired           = false;   // OCO already executed today
datetime      g_lastDay            = 0;       // date of last processed day


//===================================================================
//  UTILITY HELPERS
//===================================================================

//--- Parse "HH:MM" string → integer hour & minute
bool ParseHHMM(const string s, int &h, int &m)
{
   string p[];
   if(StringSplit(s, ':', p) < 2) { h = 0; m = 0; return false; }
   h = (int)StringToInteger(p[0]);
   m = (int)StringToInteger(p[1]);
   return (h >= 0 && h < 24 && m >= 0 && m < 60);
}

//--- Current time as minutes-since-midnight (broker time)
int NowMinutes()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour * 60 + dt.min;
}

//--- Midnight of today (broker time)
datetime TodayMidnight()
{
   return StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
}

//--- Single ATR value from last closed bar
double GetATR()
{
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double buf[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) != 1) return 0.0;
   return buf[0];
}

//--- Minimum distance the broker requires (stops level + freeze, with small buffer)
double MinStopDist()
{
   long sl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long frz = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)MathMax(sl, frz) * _Point, _Point) * 1.05;
}

//--- Clamp any distance so it meets broker requirements
double Clamp(double dist)
{
   return MathMax(dist, MinStopDist());
}

//--- Derive lot size from SL distance in price
double CalcLotSize(double slPrice)
{
   if(slPrice <= 0.0) return 0.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = InpRiskInMoney ? InpRiskValue : balance * InpRiskValue * 0.01;
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0.0 || tickVal <= 0.0) return 0.0;
   double slPerLot = (slPrice / tickSz) * tickVal;
   if(slPerLot <= 0.0) return 0.0;
   double lots = riskAmt / slPerLot;
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / step) * step;
   return NormalizeDouble(MathMax(minL, MathMin(maxL, lots)), 2);
}


//===================================================================
//  ORDER / POSITION MANAGEMENT
//===================================================================

//--- Delete all pending orders belonging to this EA on this symbol
void DeletePendingOrders(const string reason = "")
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)  != InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)        != _Symbol)        continue;
      if(!g_trade.OrderDelete(ticket))
         PrintFormat("[EA] OrderDelete #%I64u failed (%d): %s",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      else if(reason != "")
         PrintFormat("[EA] Pending order #%I64u deleted (%s)", ticket, reason);
   }
}

//--- Close all positions belonging to this EA on this symbol
void CloseAllPositions(const string reason = "")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol)        continue;
      if(!g_trade.PositionClose(ticket))
         PrintFormat("[EA] PositionClose #%I64u failed (%d): %s",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      else if(reason != "")
         PrintFormat("[EA] Position #%I64u closed (%s)", ticket, reason);
   }
}

//--- Place fresh straddle orders
void PlaceStraddleOrders()
{
   // Clean up any leftover pending orders first (delete-and-place-fresh)
   DeletePendingOrders("replace-fresh");

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = (ask + bid) * 0.5;

   // Distances
   double entDist, slDist, tpDist;
   if(InpUseATR)
   {
      double atr = GetATR();
      if(atr <= 0.0) { Print("[EA] ATR = 0; orders not placed."); return; }
      entDist = atr * InpATRMultEntry;
      slDist  = atr * InpATRMultSL;
      tpDist  = atr * InpATRMultTP;
   }
   else
   {
      entDist = mid * InpDistancePct * 0.01;
      slDist  = mid * InpSLPct      * 0.01;
      tpDist  = mid * InpTPPct      * 0.01;
   }

   // Enforce broker minimums
   entDist = Clamp(entDist);
   slDist  = Clamp(slDist);
   tpDist  = Clamp(tpDist);

   // Buy Stop
   double buyEntry = NormalizeDouble(ask + entDist, _Digits);
   double buySL    = NormalizeDouble(buyEntry - slDist, _Digits);
   double buyTP    = NormalizeDouble(buyEntry + tpDist, _Digits);

   // Sell Stop
   double sellEntry = NormalizeDouble(bid - entDist, _Digits);
   double sellSL    = NormalizeDouble(sellEntry + slDist, _Digits);
   double sellTP    = NormalizeDouble(sellEntry - tpDist, _Digits);

   // Lot sizes (each sized independently on their own SL)
   double buyLot  = CalcLotSize(slDist);
   double sellLot = CalcLotSize(slDist);

   if(buyLot <= 0.0 || sellLot <= 0.0)
   { Print("[EA] Lot size = 0. Check risk settings."); return; }

   // Place
   if(g_trade.BuyStop(buyLot, buyEntry, _Symbol, buySL, buyTP, ORDER_TIME_GTC, 0, "SB_BUY"))
      PrintFormat("[EA] BuyStop  placed  | Entry=%.5f  SL=%.5f  TP=%.5f  Lots=%.2f",
                  buyEntry, buySL, buyTP, buyLot);
   else
      PrintFormat("[EA] BuyStop  FAILED  (%d): %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());

   if(g_trade.SellStop(sellLot, sellEntry, _Symbol, sellSL, sellTP, ORDER_TIME_GTC, 0, "SB_SELL"))
      PrintFormat("[EA] SellStop placed  | Entry=%.5f  SL=%.5f  TP=%.5f  Lots=%.2f",
                  sellEntry, sellSL, sellTP, sellLot);
   else
      PrintFormat("[EA] SellStop FAILED  (%d): %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());

   g_ocoFired = false; // fresh OCO state for the new day
}


//===================================================================
//  OCO LOGIC
//===================================================================
void CheckOCO()
{
   if(g_ocoFired) return;

   bool hasBuy = false, hasSell = false;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol)        continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(pt == POSITION_TYPE_BUY)  hasBuy  = true;
      if(pt == POSITION_TYPE_SELL) hasSell = true;
   }
   if(!hasBuy && !hasSell) return;

   bool acted = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if((long)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)       != _Symbol)        continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if((hasBuy  && ot == ORDER_TYPE_SELL_STOP) ||
         (hasSell && ot == ORDER_TYPE_BUY_STOP))
      {
         if(g_trade.OrderDelete(ticket))
            { PrintFormat("[EA] OCO: deleted opposite pending #%I64u", ticket); acted = true; }
      }
   }
   if(acted) g_ocoFired = true;
}


//===================================================================
//  TRAILING STOP MANAGEMENT
//===================================================================
void ManageTrailingStops()
{
   if(!InpUseBreakEven && !InpUseTrailing) return;

   double atr    = InpUseATR ? GetATR() : 0.0;
   double minDst = MinStopDist();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!g_pos.SelectByTicket(ticket)) continue;
      if(g_pos.Magic()  != InpMagicNumber) continue;
      if(g_pos.Symbol() != _Symbol)        continue;

      ENUM_POSITION_TYPE posType = g_pos.PositionType();
      double openPx  = g_pos.PriceOpen();
      double curSL   = g_pos.StopLoss();
      double curTP   = g_pos.TakeProfit();
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double mktPx   = (posType == POSITION_TYPE_BUY) ? bid : ask;

      double newSL = curSL;  // candidate new SL; only modified when better

      // ── Break Even ──────────────────────────────────────────────
      if(InpUseBreakEven)
      {
         double beTrig = InpUseATR ? atr * InpBETrigger
                                   : openPx * InpBETrigger * 0.01;
         double beSL   = NormalizeDouble(openPx, _Digits);

         if(posType == POSITION_TYPE_BUY)
         {
            if(mktPx >= openPx + beTrig && beSL > curSL)
               newSL = beSL;
         }
         else // SELL
         {
            if(mktPx <= openPx - beTrig && (curSL == 0.0 || beSL < curSL))
               newSL = beSL;
         }
      }

      // ── Traditional Trailing Stop ────────────────────────────────
      if(InpUseTrailing)
      {
         double tsTrig, tsDist, tsStep;
         if(InpUseATR)
         {
            tsTrig = atr * InpTSTrigger;
            tsDist = atr * InpTSDistance;
            tsStep = atr * InpTSStep;
         }
         else
         {
            tsTrig = openPx * InpTSTrigger  * 0.01;
            tsDist = openPx * InpTSDistance * 0.01;
            tsStep = openPx * InpTSStep     * 0.01;
         }
         tsDist = Clamp(tsDist);
         tsStep = MathMax(tsStep, _Point);

         if(posType == POSITION_TYPE_BUY)
         {
            if(mktPx >= openPx + tsTrig)
            {
               double trail = NormalizeDouble(mktPx - tsDist, _Digits);
               if(trail > newSL + tsStep)
                  newSL = trail;
            }
         }
         else // SELL
         {
            if(mktPx <= openPx - tsTrig)
            {
               double trail = NormalizeDouble(mktPx + tsDist, _Digits);
               if(newSL == 0.0 || trail < newSL - tsStep)
                  newSL = trail;
            }
         }
      }

      // ── Apply modification (only if SL actually improved) ────────
      if(NormalizeDouble(newSL - curSL, _Digits) == 0.0) continue;

      // Validate distance to market price
      bool valid = false;
      if(posType == POSITION_TYPE_BUY  && newSL > 0.0 && newSL < bid - minDst) valid = true;
      if(posType == POSITION_TYPE_SELL && newSL > ask + minDst)                 valid = true;

      if(valid)
      {
         if(!g_trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("[EA] PositionModify #%I64u failed (%d): %s",
                        ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }
}


//===================================================================
//  STATE RESTORE  (called once on OnInit to rebuild daily flags)
//===================================================================
void RestoreState()
{
   datetime today = TodayMidnight();
   g_lastDay = today;

   int entH, entM, delH, delM;
   ParseHHMM(InpEntryTime,    entH, entM);
   ParseHHMM(InpDeletionTime, delH, delM);
   int nowMins = NowMinutes();
   int entMins = entH * 60 + entM;
   int delMins = delH * 60 + delM;

   // Any pending orders still alive? → entry was done, deletion not yet
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if((long)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
          OrderGetString(ORDER_SYMBOL)      == _Symbol)
      {
         g_ordersPlacedToday = true;
         g_deletionDoneToday = false;
         Print("[EA] State restored: pending orders found.");
         return;
      }
   }

   // Any positions opened today? → entry done; OCO may have fired
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if((long)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
          PositionGetString(POSITION_SYMBOL)      == _Symbol)
      {
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(openTime >= today)
         {
            g_ordersPlacedToday = true;
            g_ocoFired          = true;
            g_deletionDoneToday = (nowMins >= delMins);
            Print("[EA] State restored: open position from today found.");
            return;
         }
      }
   }

   // No orders/positions → decide from current time
   if(nowMins >= entMins) g_ordersPlacedToday = true;
   if(nowMins >= delMins) g_deletionDoneToday = true;
   PrintFormat("[EA] State restored: ordersPlaced=%s  deletionDone=%s",
               g_ordersPlacedToday ? "true" : "false",
               g_deletionDoneToday ? "true" : "false");
}


//===================================================================
//  EXPERT ADVISOR LIFECYCLE
//===================================================================

int OnInit()
{
   // Validate time strings
   int h, m;
   if(!ParseHHMM(InpEntryTime, h, m))
   { Alert("[EA] Invalid Entry Time – use HH:MM"); return INIT_PARAMETERS_INCORRECT; }
   if(!ParseHHMM(InpDeletionTime, h, m))
   { Alert("[EA] Invalid Deletion Time – use HH:MM"); return INIT_PARAMETERS_INCORRECT; }

   // Validate risk
   if(InpRiskValue <= 0.0)
   { Alert("[EA] Risk value must be > 0"); return INIT_PARAMETERS_INCORRECT; }

   // ATR handle
   if(InpUseATR)
   {
      g_atrHandle = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
      { Alert("[EA] Failed to create ATR indicator."); return INIT_FAILED; }
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetAsyncMode(false);

   RestoreState();

   PrintFormat("[EA] Initialized on %s | Magic=%d | Entry=%s | Delete=%s | Mode=%s",
               _Symbol, InpMagicNumber, InpEntryTime, InpDeletionTime,
               InpUseATR ? "ATR" : "Percent");
   return INIT_SUCCEEDED;
}

//---
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
   }
}

//---
void OnTick()
{
   // ── New day? Reset daily flags ───────────────────────────────
   datetime today = TodayMidnight();
   if(today != g_lastDay)
   {
      g_lastDay           = today;
      g_ordersPlacedToday = false;
      g_deletionDoneToday = false;
      g_ocoFired          = false;
   }

   int entH, entM, delH, delM;
   ParseHHMM(InpEntryTime,    entH, entM);
   ParseHHMM(InpDeletionTime, delH, delM);
   int nowMins = NowMinutes();
   int entMins = entH * 60 + entM;
   int delMins = delH * 60 + delM;

   // ── Deletion time ────────────────────────────────────────────
   if(nowMins >= delMins && !g_deletionDoneToday)
   {
      DeletePendingOrders("deletion time reached");
      if(InpCloseTradesAtDeletion)
         CloseAllPositions("deletion time reached");
      g_deletionDoneToday = true;
   }

   // ── Entry time (only before deletion, only once per day) ────
   if(nowMins >= entMins && !g_ordersPlacedToday && !g_deletionDoneToday)
   {
      PlaceStraddleOrders();
      g_ordersPlacedToday = true;
   }

   // ── OCO ──────────────────────────────────────────────────────
   if(InpOCOEnabled)
      CheckOCO();

   // ── Trailing stops ───────────────────────────────────────────
   ManageTrailingStops();
}

//--- Trade transaction handler – faster OCO response on order fill
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   // When a pending order belonging to this EA gets filled → trigger OCO immediately
   if(InpOCOEnabled && !g_ocoFired)
   {
      if(trans.type == TRADE_TRANSACTION_ORDER_DELETE &&
         trans.order_state == ORDER_STATE_FILLED)
      {
         // Confirm it is ours (quick heuristic via symbol; magic check via position below)
         if(trans.symbol == _Symbol)
            CheckOCO();
      }
   }
}
//+------------------------------------------------------------------+