//+-----------------------------------------------------------------------------------+
//| rsi7_ema200_breakout_bull.mq5                                                     |
//|                                                                                   |
//| STRATEGY : RSI7_oversold + close_above_EMA200 + breakout_down => BULLISH ENTRY   |
//| EXITS    : Time-exit only — close after X M15 candles (no SL, no TP)             |
//|                                                                                   |
//| Signal Stats:                                                                     |
//|   Direction : BULLISH 55.0%                                                       |
//|   Magnitude : 2.21 ATR  |  Timing : ~3.5 M15 candles  |  Freq : 0.95%            |
//|                                                                                   |
//| Signal Definitions:                                                               |
//|   RSI7 oversold   : RSI(7) < OversoldLevel (default 30)                           |
//|   Close > EMA200  : Close above 200-period EMA                                    |
//|   Breakout down   : Close < Low.rolling(20).min().shift(1)                        |
//|                     => Close breaks below lowest low of prior 20 bars             |
//|                                                                                   |
//| DISCLAIMER: PROVIDED "AS IS". PAST STATISTICS DO NOT GUARANTEE FUTURE RESULTS.   |
//+-----------------------------------------------------------------------------------+

#property copyright "Nugi"
#property link      ""
#property description "RSI7 Oversold + EMA200 Filter + Breakout-Down Reversal — Time Exit Only"
#property strict

//===================================================================================
//  ENUMS
//===================================================================================

//===================================================================================
//  POSITION TRACKER
//  Stores only the open-bar-time for every trade opened by this EA.
//  Exits are time-based only (no SL, no TP).
//===================================================================================

struct STradeRecord
{
   ulong    ticket;       // MT5 position ticket
   datetime openBarTime; // iTime of M15 bar at entry (used for MaxBars count)
};

STradeRecord tradeRecords[];   // Dynamic array — one entry per open EA trade
int          tradeCount = 0;   // Number of entries currently tracked

//===================================================================================
//  INPUT PARAMETERS
//===================================================================================
input group "=== Signal Parameters ==="
input int    RSI_Period         = 7;    // RSI Period
input double RSI_OversoldLevel  = 30.0; // RSI Oversold Threshold
input int    EMA_Period         = 200;  // EMA Period
input int    Breakout_Lookback  = 20;   // Breakout Lookback Bars

input group "=== Trade Management ==="
input double LotSize            = 0.1;  // Lot Size
input int    MaxBarsInTrade     = 7;    // Max M15 Bars Before Force-Close
input int    MaxOpenTrades      = 1;    // Max concurrent EA trades
input ulong  MagicNumber        = 20250101;

input group "=== Risk Guard ==="
input double MaxSpreadPoints    = 20.0; // Max spread (points) to allow entry

//===================================================================================
//  CONSTANTS
//===================================================================================

input ENUM_TIMEFRAMES TradeTimeframe = PERIOD_M15;   // Fixed to M15

//===================================================================================
//  GLOBAL VARIABLES
//===================================================================================

int hRSI = INVALID_HANDLE;
int hEMA = INVALID_HANDLE;

//===================================================================================
//  OnInit
//===================================================================================

int OnInit()
{
   //--- Indicator handles (all on M15) — ATR no longer needed
   hRSI = iRSI(Symbol(), TradeTimeframe, RSI_Period, PRICE_CLOSE);
   hEMA = iMA (Symbol(), TradeTimeframe, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(hRSI == INVALID_HANDLE || hEMA == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles.");
      return INIT_FAILED;
   }

   //--- Initialise trade record array
   ArrayResize(tradeRecords, 0);
   tradeCount = 0;

   return INIT_SUCCEEDED;
}

//===================================================================================
//  OnDeinit
//===================================================================================

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   Comment("");
}

//===================================================================================
//  OnTick
//===================================================================================
bool IsNewBar()
{
   static datetime lastBarTime = 0;

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}
void OnTick()
{

   if(!IsNewBar()) return;

   //--- CRITICAL: Check time-exit on EVERY tick
   ProcessTradeClosures();

   ProcessTradeOpens();
}

//===================================================================================
//  TRADE RECORD MANAGEMENT
//===================================================================================

//--- Add a new trade record after a successful entry
void TradeRecord_Add(ulong ticket, datetime openBarTime)
{
   ArrayResize(tradeRecords, tradeCount + 1);
   tradeRecords[tradeCount].ticket      = ticket;
   tradeRecords[tradeCount].openBarTime = openBarTime;
   tradeCount++;
   Print(StringFormat("TRADE RECORD ADDED | Ticket=%I64u | OpenBarTime=%s",
         ticket, TimeToString(openBarTime)));
}

//--- Remove a trade record by index (swap-with-last)
void TradeRecord_Remove(int idx)
{
   tradeRecords[idx] = tradeRecords[tradeCount - 1];
   tradeCount--;
   ArrayResize(tradeRecords, tradeCount);
}

//--- Find the index of a ticket in tradeRecords[]; returns -1 if not found
int TradeRecord_Find(ulong ticket)
{
   for(int i = 0; i < tradeCount; i++)
      if(tradeRecords[i].ticket == ticket) return i;
   return -1;
}

//===================================================================================
//  CLOSE A POSITION (market order)
//===================================================================================

bool ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return false;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = Symbol();
   req.volume       = PositionGetDouble(POSITION_VOLUME);
   req.type         = ORDER_TYPE_SELL;   // Always BUY positions in this EA
   req.price        = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   req.deviation    = 10;
   req.magic        = MagicNumber;
   req.position     = ticket;
   req.comment      = reason;
   req.type_filling = ORDER_FILLING_IOC;

   bool ok = OrderSend(req, res);
   if(ok)
      Print(StringFormat("CLOSED [%s] | Ticket=%I64u | Bid=%.5f", reason, ticket, req.price));
   else
      Print(StringFormat("CLOSE FAILED [%s] | Ticket=%I64u | Retcode=%d", reason, ticket, res.retcode));

   return ok;
}

//===================================================================================
//  ProcessTradeClosures — called on EVERY tick
//  Only exit condition: MaxBarsInTrade M15 candles elapsed since entry bar
//===================================================================================

void ProcessTradeClosures()
{
   //--- Purge stale records whose broker position no longer exists
   //    (e.g. manually closed by user)
   for(int i = tradeCount - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(tradeRecords[i].ticket))
      {
         Print("TRADE RECORD ORPHANED (position gone) | Ticket=" +
               IntegerToString((int)tradeRecords[i].ticket) + " — removing");
         TradeRecord_Remove(i);
      }
   }

   //--- Check each tracked trade for time-exit
   for(int i = tradeCount - 1; i >= 0; i--)
   {
      ulong    ticket      = tradeRecords[i].ticket;
      datetime openBarTime = tradeRecords[i].openBarTime;

      //--- Safety: confirm position still belongs to this EA
      if(!PositionSelectByTicket(ticket))               { TradeRecord_Remove(i); continue; }
      if(PositionGetString (POSITION_SYMBOL) != Symbol()) { TradeRecord_Remove(i); continue; }
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) { TradeRecord_Remove(i); continue; }

      //--- Count M15 bars elapsed since the entry bar
      int barsPassed = Bars(Symbol(), TradeTimeframe, openBarTime,
                            iTime(Symbol(), TradeTimeframe, 0)) - 1;

      if(barsPassed >= MaxBarsInTrade)
      {
         string closeReason = StringFormat("TimeExit | BarsPassed=%d >= MaxBars=%d",
                                            barsPassed, MaxBarsInTrade);
         if(ClosePosition(ticket, closeReason))
            TradeRecord_Remove(i);
      }
   }
}

//===================================================================================
//  SIGNAL EVALUATION
//===================================================================================

bool IsSignalActive(int iBar)
{
   //--- RSI buffer
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   if(CopyBuffer(hRSI, 0, 0, iBar + 2, rsiBuffer) < iBar + 2) return false;

   //--- EMA buffer
   double emaBuffer[];
   ArraySetAsSeries(emaBuffer, true);
   if(CopyBuffer(hEMA, 0, 0, iBar + 2, emaBuffer) < iBar + 2) return false;

   //--- Close prices
   int barsNeeded = iBar + 1 + Breakout_Lookback + 1;
   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(Symbol(), TradeTimeframe, 0, barsNeeded, closeArr) < barsNeeded) return false;

   double closeVal = closeArr[iBar];

   //--- Condition A: RSI(7) < OversoldLevel
   bool rsiOversold = (rsiBuffer[iBar] < RSI_OversoldLevel);

   //--- Condition B: Close > EMA(200)
   bool aboveEMA = (closeVal > emaBuffer[iBar]);

   //--- Condition C: Breakout Down
   //    close[iBar] < lowest Low in [iBar+1 .. iBar+Breakout_Lookback]
   int lowestIdx = iLowest(Symbol(), TradeTimeframe, MODE_LOW, Breakout_Lookback, iBar + 1);
   if(lowestIdx < 0) return false;
   double rollingMinLow = iLow(Symbol(), TradeTimeframe, lowestIdx);
   bool breakoutDown    = (closeVal < rollingMinLow);

   return (rsiOversold && aboveEMA && breakoutDown);
}

//===================================================================================
//  ProcessTradeOpens
//===================================================================================

void ProcessTradeOpens()
{
   //--- Guard: max trades
   if(CountOpenTrades() >= MaxOpenTrades) return;

   //--- Guard: spread
   double spreadPts = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   if(spreadPts > MaxSpreadPoints)
   {
      Print("ENTRY SKIPPED: Spread=" + DoubleToString(spreadPts, 1) + " pts > max");
      return;
   }


   double askPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   int    digits   = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   //--- Send market order — NO broker SL, NO broker TP
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = Symbol();
   req.volume       = LotSize;
   req.type         = ORDER_TYPE_BUY;
   req.price        = askPrice;
   req.sl           = 0;   // No SL
   req.tp           = 0;   // No TP
   req.deviation    = 10;
   req.magic        = MagicNumber;
   req.comment      = "RSI7+EMA200+BrkDn";
   req.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(req, res))
   {
      Print("OrderSend FAILED: retcode=" + IntegerToString(res.retcode) + " | " + res.comment);
      return;
   }

   //--- Record entry bar time for time-exit tracking
   datetime openBarTime = iTime(Symbol(), TradeTimeframe, 0);
   TradeRecord_Add(res.order, openBarTime);

   Print(StringFormat("BUY OPENED | Ticket=%I64u | Ask=%.5f | ExitAfter=%d bars",
         res.order, askPrice, MaxBarsInTrade));
}

//===================================================================================
//  HELPERS
//===================================================================================

int CountOpenTrades()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString (POSITION_SYMBOL) == Symbol() &&
         PositionGetInteger(POSITION_MAGIC)  == (long)MagicNumber)
         count++;
   }
   return count;
}