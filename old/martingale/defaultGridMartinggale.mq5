//+------------------------------------------------------------------+
//|                                           GridMartingaleEA.mq5   |
//|                     Grid + Martingale Expert Advisor v2.0        |
//|                                                                  |
//|  ENTRY SIGNAL: Multi-Layer Trend-Pullback System                 |
//|  ─────────────────────────────────────────────────────────────── |
//|  Layer 1 (H4): Dominant trend — H4 close vs H4 EMA200           |
//|                H4 EMA50 slope must confirm direction             |
//|  Layer 2 (H1): Local trend alignment — H1 EMA21 vs H1 EMA55     |
//|  Layer 3 (H1): Trend strength — ADX(14) > threshold             |
//|                Rejects choppy/ranging markets entirely           |
//|  Layer 4 (H1): Pullback exhaustion — RSI(14) crosses back        |
//|                through 50 in the direction of the trend          |
//|                (price completed a pullback, momentum resumed)    |
//|  ─────────────────────────────────────────────────────────────── |
//|  WHY THIS HAS REAL EDGE:                                         |
//|  - H4 EMA200 + EMA50 slope prevents trading against the          |
//|    macro structure. You only trade in the dominant direction.     |
//|  - ADX > 22 ensures you are in a TRENDING regime. In ranging     |
//|    markets the grid would accumulate losers indefinitely —        |
//|    ADX blocks those scenarios.                                   |
//|  - RSI-50 cross after a pullback is a proven momentum trigger:   |
//|    you are entering AFTER short-term counter-move exhaustion,    |
//|    not at an arbitrary point. Combined with H4 bias, the         |
//|    probability of trend continuation is significantly elevated.  |
//|  - Net result: fewer entries (maybe 2-4 per week on majors),     |
//|    each with multi-layer confirmation. Grid fills on deeper       |
//|    pullbacks become averaging-in events inside a trend, not      |
//|    traps. This directly supports martingale recovery.            |
//|  ─────────────────────────────────────────────────────────────── |
//|  GRID   : Additional positions when price moves against cycle    |
//|  TP     : Basket take profit (money or points)                   |
//|  SL     : Floating drawdown % of account balance (not price SL)  |
//+------------------------------------------------------------------+
#property copyright "GridMartingaleEA v2.0"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Money Management ==="
input double   InpFixedLot         = 0.01;   // Fixed lot for first trade
input double   InpMartingaleMult   = 1.5;    // Martingale multiplier per grid level
input int      InpMaxGridOrders    = 6;      // Maximum grid positions per cycle
input double   InpGridDistPoints   = 300.0;  // Grid step distance in points
input double   InpBasketTPMoney    = 15.0;   // Basket TP in money  (0 = use points mode)
input double   InpBasketTPPoints   = 0.0;    // Basket TP in points (0 = use money mode)
input double   InpMaxDrawdownPct   = 15.0;   // Max drawdown % of balance → close all

input group "=== Signal Parameters ==="
input int      InpH4EMA200Period   = 200;    // H4 slow EMA period  (dominant trend)
input int      InpH4EMA50Period    = 50;     // H4 fast EMA period  (trend slope check)
input int      InpH1EMAFastPeriod  = 21;     // H1 fast EMA period  (local trend fast)
input int      InpH1EMASlowPeriod  = 55;     // H1 slow EMA period  (local trend slow)
input int      InpADXPeriod        = 14;     // ADX period          (trend strength filter)
input double   InpADXMinLevel      = 22.0;   // Min ADX — below this skip entries (choppy)
input int      InpRSIPeriod        = 14;     // RSI period          (pullback timing)
input int      InpCooldownBars     = 3;      // H1 bars to wait after each cycle closes

input group "=== EA Settings ==="
input int      InpMagicNumber      = 20240101; // EA magic number
input int      InpSlippage         = 30;       // Max slippage in points

//+------------------------------------------------------------------+
//| Global State                                                     |
//+------------------------------------------------------------------+
int      g_cycleDir       = 0;    // Active cycle: 0=none, 1=buy, -1=sell
double   g_lastGridPrice  = 0.0;  // Open price of the most recent grid order
int      g_gridCount      = 0;    // Number of open positions in current cycle
datetime g_lastCycleClose = 0;    // H1 bar time when last cycle ended (for cooldown)
datetime g_lastBarTime    = 0;    // H1 bar time of last signal evaluation

//+------------------------------------------------------------------+
//| Indicator Handles (all native MQL5 — no external includes)      |
//+------------------------------------------------------------------+
int g_hH4EMA200   = INVALID_HANDLE; // H4 EMA200 — macro trend direction
int g_hH4EMA50    = INVALID_HANDLE; // H4 EMA50  — slope confirmation
int g_hH1EMAFast  = INVALID_HANDLE; // H1 EMA21  — local trend fast line
int g_hH1EMASlow  = INVALID_HANDLE; // H1 EMA55  — local trend slow line
int g_hH1ADX      = INVALID_HANDLE; // H1 ADX14  — trend strength / chop filter
int g_hH1RSI      = INVALID_HANDLE; // H1 RSI14  — pullback exhaustion trigger

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Validate critical inputs
   if(InpFixedLot <= 0.0)
     { Print("ERROR: FixedLot must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMartingaleMult < 1.0)
     { Print("ERROR: MartingaleMult must be >= 1.0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxGridOrders < 1)
     { Print("ERROR: MaxGridOrders must be >= 1"); return INIT_PARAMETERS_INCORRECT; }
   if(InpBasketTPMoney <= 0.0 && InpBasketTPPoints <= 0.0)
     { Print("ERROR: Set BasketTPMoney > 0 or BasketTPPoints > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxDrawdownPct <= 0.0 || InpMaxDrawdownPct >= 100.0)
     { Print("ERROR: MaxDrawdownPct must be between 0 and 100"); return INIT_PARAMETERS_INCORRECT; }

   //--- Create all indicator handles
   g_hH4EMA200  = iMA(_Symbol, PERIOD_H4, InpH4EMA200Period,  0, MODE_EMA, PRICE_CLOSE);
   g_hH4EMA50   = iMA(_Symbol, PERIOD_H4, InpH4EMA50Period,   0, MODE_EMA, PRICE_CLOSE);
   g_hH1EMAFast = iMA(_Symbol, PERIOD_H1, InpH1EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hH1EMASlow = iMA(_Symbol, PERIOD_H1, InpH1EMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hH1ADX     = iADX(_Symbol, PERIOD_H1, InpADXPeriod);
   g_hH1RSI     = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);

   if(g_hH4EMA200  == INVALID_HANDLE || g_hH4EMA50   == INVALID_HANDLE ||
      g_hH1EMAFast == INVALID_HANDLE || g_hH1EMASlow == INVALID_HANDLE ||
      g_hH1ADX     == INVALID_HANDLE || g_hH1RSI     == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create one or more indicator handles");
      return INIT_FAILED;
     }

   PrintFormat("GridMartingaleEA v2.0 | %s | Magic:%d | MaxDD:%.1f%% | GridDist:%.0f pts | MaxGrid:%d",
               _Symbol, InpMagicNumber, InpMaxDrawdownPct, InpGridDistPoints, InpMaxGridOrders);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hH4EMA200  != INVALID_HANDLE) IndicatorRelease(g_hH4EMA200);
   if(g_hH4EMA50   != INVALID_HANDLE) IndicatorRelease(g_hH4EMA50);
   if(g_hH1EMAFast != INVALID_HANDLE) IndicatorRelease(g_hH1EMAFast);
   if(g_hH1EMASlow != INVALID_HANDLE) IndicatorRelease(g_hH1EMASlow);
   if(g_hH1ADX     != INVALID_HANDLE) IndicatorRelease(g_hH1ADX);
   if(g_hH1RSI     != INVALID_HANDLE) IndicatorRelease(g_hH1RSI);
  }

//+------------------------------------------------------------------+
//| Main OnTick Handler                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1. Re-sync internal counters with actual broker positions each tick
   SyncCycleState();

   //--- 2. Drawdown SL: highest priority, checked every tick
   if(g_cycleDir != 0)
     {
      if(CheckDrawdownSL()) return;
     }

   //--- 3. Basket TP check
   if(g_cycleDir != 0)
     {
      if(CheckBasketTP()) return;
     }

   //--- 4. Grid step: if cycle active, open next grid order if price moved far enough
   if(g_cycleDir != 0)
     {
      CheckAndOpenGridOrder();
      return; // Do not evaluate fresh entry while cycle is running
     }

   //--- 5. Entry signal: evaluate only once per new H1 bar
   datetime currentBar = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBar == g_lastBarTime)
      return;
   g_lastBarTime = currentBar;

   //--- 6. Cooldown: wait N bars after a cycle closes to avoid re-entering too fast
   if(InpCooldownBars > 0 && g_lastCycleClose != 0)
     {
      int barsSince = (int)((currentBar - g_lastCycleClose) / PeriodSeconds(PERIOD_H1));
      if(barsSince < InpCooldownBars) return;
     }

   //--- 7. Evaluate multi-layer signal and open first position
   int sig = GetEntrySignal();
   if(sig ==  1) OpenPosition(ORDER_TYPE_BUY,  InpFixedLot, "GMGrid_Buy_0");
   if(sig == -1) OpenPosition(ORDER_TYPE_SELL, InpFixedLot, "GMGrid_Sell_0");
  }

//+------------------------------------------------------------------+
//| ENTRY SIGNAL — Four-Layer Trend-Pullback System                  |
//|                                                                  |
//|  All four layers must be satisfied simultaneously.               |
//|  Signal fires on the bar AFTER trigger (confirmed close).        |
//|                                                                  |
//|  LAYER 1 — H4 Dominant Trend                                     |
//|   BUY  req: H4 close[1] > H4 EMA200[1]   (above macro trend)   |
//|             H4 EMA50[1] > H4 EMA50[4]    (slope rising)         |
//|   SELL req: H4 close[1] < H4 EMA200[1]   (below macro trend)   |
//|             H4 EMA50[1] < H4 EMA50[4]    (slope falling)        |
//|                                                                  |
//|  LAYER 2 — H1 Local Alignment                                    |
//|   BUY  req: H1 EMA21[1] > H1 EMA55[1]                          |
//|   SELL req: H1 EMA21[1] < H1 EMA55[1]                          |
//|                                                                  |
//|  LAYER 3 — ADX Trend Strength                                    |
//|   BOTH req: ADX[1] > InpADXMinLevel (default 22)                |
//|             Skips entries in flat/choppy/ranging conditions      |
//|                                                                  |
//|  LAYER 4 — RSI-50 Pullback Exhaustion (entry trigger)           |
//|   BUY  req: RSI[2] < 50 AND RSI[1] >= 50                        |
//|             → price dipped (pullback), momentum just turned up   |
//|   SELL req: RSI[2] > 50 AND RSI[1] <= 50                        |
//|             → price bounced (pullback), momentum just turned dn  |
//|                                                                  |
//|  Returns: 1 = buy, -1 = sell, 0 = no signal                     |
//+------------------------------------------------------------------+
int GetEntrySignal()
  {
   //--- Ensure all indicators have enough calculated bars
   if(BarsCalculated(g_hH4EMA200)  < InpH4EMA200Period  + 10) return 0;
   if(BarsCalculated(g_hH4EMA50)   < InpH4EMA50Period   + 10) return 0;
   if(BarsCalculated(g_hH1EMAFast) < InpH1EMAFastPeriod + 5)  return 0;
   if(BarsCalculated(g_hH1EMASlow) < InpH1EMASlowPeriod + 5)  return 0;
   if(BarsCalculated(g_hH1ADX)     < InpADXPeriod        + 5)  return 0;
   if(BarsCalculated(g_hH1RSI)     < InpRSIPeriod         + 5)  return 0;

   //--- H4 buffers: need 5 bars for slope check ([1] vs [4])
   double h4ema200[5], h4ema50[5];
   ArraySetAsSeries(h4ema200, true);
   ArraySetAsSeries(h4ema50,  true);
   if(CopyBuffer(g_hH4EMA200, 0, 0, 5, h4ema200) < 5) return 0;
   if(CopyBuffer(g_hH4EMA50,  0, 0, 5, h4ema50)  < 5) return 0;

   //--- H4 close prices: need last 2 bars
   double h4close[2];
   ArraySetAsSeries(h4close, true);
   if(CopyClose(_Symbol, PERIOD_H4, 0, 2, h4close) < 2) return 0;

   //--- H1 buffers: need 3 bars ([0]=forming, [1]=last closed, [2]=prior closed)
   double h1emaFast[3], h1emaSlow[3], h1rsi[3], h1adx[3];
   ArraySetAsSeries(h1emaFast, true);
   ArraySetAsSeries(h1emaSlow, true);
   ArraySetAsSeries(h1rsi,     true);
   ArraySetAsSeries(h1adx,     true);

   if(CopyBuffer(g_hH1EMAFast, 0, 0, 3, h1emaFast) < 3) return 0;
   if(CopyBuffer(g_hH1EMASlow, 0, 0, 3, h1emaSlow) < 3) return 0;
   if(CopyBuffer(g_hH1RSI,     0, 0, 3, h1rsi)     < 3) return 0;
   // iADX buffer 0 = ADX main line
   if(CopyBuffer(g_hH1ADX,     0, 0, 3, h1adx)     < 3) return 0;

   //=========================================================
   // LAYER 1: H4 Dominant Trend
   // h4close[1] = last fully closed H4 bar
   // h4ema50[1] vs h4ema50[4] = slope over last 3 H4 bars
   //=========================================================
   bool h4Bull = (h4close[1] > h4ema200[1]) && (h4ema50[1] > h4ema50[4]);
   bool h4Bear = (h4close[1] < h4ema200[1]) && (h4ema50[1] < h4ema50[4]);
   // If neither clear — macro structure is transitioning, skip
   if(!h4Bull && !h4Bear) return 0;

   //=========================================================
   // LAYER 2: H1 Local Trend Alignment
   // EMA21 vs EMA55 on last closed H1 bar
   //=========================================================
   bool h1Bull = (h1emaFast[1] > h1emaSlow[1]);
   bool h1Bear = (h1emaFast[1] < h1emaSlow[1]);

   //=========================================================
   // LAYER 3: ADX Trend Strength — reject choppy/ranging
   // ADX on last closed H1 bar must exceed threshold
   //=========================================================
   if(h1adx[1] <= InpADXMinLevel) return 0; // Market is ranging — skip

   //=========================================================
   // LAYER 4: RSI-50 Pullback Exhaustion (actual entry trigger)
   // RSI[2] = two bars ago (before pullback), RSI[1] = last closed bar
   // Buy:  RSI was <50 (bearish pullback), now crossed back >=50 (momentum up)
   // Sell: RSI was >50 (bullish bounce),   now crossed back <=50 (momentum dn)
   //=========================================================
   bool rsiPullbackBull = (h1rsi[2] < 50.0) && (h1rsi[1] >= 50.0);
   bool rsiPullbackBear = (h1rsi[2] > 50.0) && (h1rsi[1] <= 50.0);

   //=========================================================
   // COMBINE: all layers must agree
   //=========================================================
   if(h4Bull && h1Bull && rsiPullbackBull)
     {
      PrintFormat("=== BUY SIGNAL === H4Close=%.5f H4EMA200=%.5f | H4EMA50 slope %.5f->%.5f | H1EMA21=%.5f H1EMA55=%.5f | ADX=%.1f | RSI[2]=%.1f RSI[1]=%.1f",
                  h4close[1], h4ema200[1], h4ema50[4], h4ema50[1],
                  h1emaFast[1], h1emaSlow[1], h1adx[1], h1rsi[2], h1rsi[1]);
      return 1;
     }

   if(h4Bear && h1Bear && rsiPullbackBear)
     {
      PrintFormat("=== SELL SIGNAL === H4Close=%.5f H4EMA200=%.5f | H4EMA50 slope %.5f->%.5f | H1EMA21=%.5f H1EMA55=%.5f | ADX=%.1f | RSI[2]=%.1f RSI[1]=%.1f",
                  h4close[1], h4ema200[1], h4ema50[4], h4ema50[1],
                  h1emaFast[1], h1emaSlow[1], h1adx[1], h1rsi[2], h1rsi[1]);
      return -1;
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| Sync internal counters with actual open positions                |
//| Called every tick. Handles restarts and manual interventions.    |
//+------------------------------------------------------------------+
void SyncCycleState()
  {
   int    buyCount    = 0;
   int    sellCount   = 0;
   double lowestBuy   = DBL_MAX; // Lowest buy open price = last grid step placed (downward)
   double highestSell = 0.0;     // Highest sell open price = last grid step placed (upward)

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE pType  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             oprice = PositionGetDouble(POSITION_PRICE_OPEN);

      if(pType == POSITION_TYPE_BUY)
        {
         buyCount++;
         // Buy grid opens lower as price falls — lowest open = most recent grid step
         if(oprice < lowestBuy) lowestBuy = oprice;
        }
      else
        {
         sellCount++;
         // Sell grid opens higher as price rises — highest open = most recent grid step
         if(oprice > highestSell) highestSell = oprice;
        }
     }

   if(buyCount > 0 && sellCount == 0)
     {
      g_cycleDir      = 1;
      g_gridCount     = buyCount;
      g_lastGridPrice = (lowestBuy < DBL_MAX) ? lowestBuy : 0.0;
     }
   else if(sellCount > 0 && buyCount == 0)
     {
      g_cycleDir      = -1;
      g_gridCount     = sellCount;
      g_lastGridPrice = highestSell;
     }
   else if(buyCount == 0 && sellCount == 0)
     {
      // No positions — if we had a cycle, record close time for cooldown
      if(g_cycleDir != 0)
         g_lastCycleClose = iTime(_Symbol, PERIOD_H1, 0);
      g_cycleDir      = 0;
      g_gridCount     = 0;
      g_lastGridPrice = 0.0;
     }
   // Mixed positions (buy + sell) should not happen in this EA.
   // If they do, drawdown SL will close everything on next tick.
  }

//+------------------------------------------------------------------+
//| Drawdown Stop Loss Check                                         |
//| drawdown% = |floating basket loss| / accountBalance * 100        |
//| If drawdown% >= threshold → close all positions immediately      |
//| Returns true if positions were closed                            |
//+------------------------------------------------------------------+
bool CheckDrawdownSL()
  {
   double floatingPnL = GetBasketFloatingProfit();
   if(floatingPnL >= 0.0) return false; // Not in drawdown

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0) return false;

   double ddPct = (MathAbs(floatingPnL) / balance) * 100.0;

   if(ddPct >= InpMaxDrawdownPct)
     {
      PrintFormat(">>> DD SL TRIGGERED: %.2f%% >= %.2f%% | Loss=%.2f | Balance=%.2f",
                  ddPct, InpMaxDrawdownPct, floatingPnL, balance);
      CloseAllBasketPositions("DD_SL");
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Basket Take Profit Check                                         |
//| Supports both money-based and points-based targets               |
//| Returns true if positions were closed                            |
//+------------------------------------------------------------------+
bool CheckBasketTP()
  {
   double floatingProfit = GetBasketFloatingProfit();
   bool   tpHit          = false;

   // Money-based TP (priority if both are configured)
   if(InpBasketTPMoney > 0.0 && floatingProfit >= InpBasketTPMoney)
      tpHit = true;

   // Points-based TP using volume-weighted average entry
   if(!tpHit && InpBasketTPPoints > 0.0)
     {
      if(GetBasketPointsProfit() >= InpBasketTPPoints)
         tpHit = true;
     }

   if(tpHit)
     {
      PrintFormat(">>> BASKET TP HIT: Profit=%.2f | Closing all positions", floatingProfit);
      CloseAllBasketPositions("BASKET_TP");
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Grid Order Logic                                                 |
//| Opens next grid order when price moves InpGridDistPoints         |
//| against the active cycle direction from last grid open price     |
//+------------------------------------------------------------------+
void CheckAndOpenGridOrder()
  {
   if(g_gridCount >= InpMaxGridOrders) return; // At max depth

   double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointSize <= 0.0) return;

   double gridStep     = InpGridDistPoints * pointSize;
   double currentPrice = (g_cycleDir == 1)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)  // Buy grid checks BID
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK); // Sell grid checks ASK

   bool shouldOpen = false;
   if(g_cycleDir ==  1 && (g_lastGridPrice - currentPrice) >= gridStep)
      shouldOpen = true; // Price dropped far enough below last buy
   if(g_cycleDir == -1 && (currentPrice - g_lastGridPrice) >= gridStep)
      shouldOpen = true; // Price rose far enough above last sell

   if(shouldOpen)
     {
      double newLot = CalculateGridLot(g_gridCount);
      string label  = StringFormat("GMGrid_%s_%d",
                                   (g_cycleDir == 1 ? "Buy" : "Sell"),
                                   g_gridCount);
      ENUM_ORDER_TYPE otype = (g_cycleDir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      OpenPosition(otype, newLot, label);
     }
  }

//+------------------------------------------------------------------+
//| Calculate Martingale Lot for Grid Level N                        |
//| gridIndex 0 = first position (uses FixedLot directly)           |
//| gridIndex N = FixedLot * Multiplier^N                            |
//| Result is normalized to broker's lot step and clamped to limits  |
//+------------------------------------------------------------------+
double CalculateGridLot(int gridIndex)
  {
   double lot     = InpFixedLot * MathPow(InpMartingaleMult, (double)gridIndex);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lotStep > 0.0) lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Open a Market Position                                           |
//| Tries IOC → FOK → RETURN fill modes for broad broker support     |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE orderType, double lot, string comment)
  {
   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(price <= 0.0) { Print("OpenPosition: Bad price"); return false; }

   // Margin check with 10% safety buffer
   double marginNeeded = 0.0;
   if(OrderCalcMargin(orderType, _Symbol, lot, price, marginNeeded))
     {
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < marginNeeded * 1.1)
        { Print("OpenPosition: Insufficient free margin"); return false; }
     }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = orderType;
   req.price     = price;
   req.deviation = InpSlippage;
   req.magic     = InpMagicNumber;
   req.comment   = comment;

   // Try fill modes in order: IOC → FOK → RETURN
   ENUM_ORDER_TYPE_FILLING fills[3] = {ORDER_FILLING_IOC, ORDER_FILLING_FOK, ORDER_FILLING_RETURN};
   bool sent = false;
   for(int f = 0; f < 3; f++)
     {
      req.type_filling = fills[f];
      sent = OrderSend(req, res);
      if(sent && res.retcode == TRADE_RETCODE_DONE)    break; // Success
      if(res.retcode != TRADE_RETCODE_INVALID_FILL)    break; // Non-fill error, stop trying
     }

   if(!sent || res.retcode != TRADE_RETCODE_DONE)
     {
      PrintFormat("OpenPosition FAILED: %s | lot=%.2f | retcode=%d", comment, lot, res.retcode);
      return false;
     }

   PrintFormat("OpenPosition OK: %s | lot=%.2f | ticket=%I64u | price=%.5f",
               comment, lot, res.order, res.price);

   // Immediately update state without waiting for next tick
   g_cycleDir      = (orderType == ORDER_TYPE_BUY) ? 1 : -1;
   g_lastGridPrice = res.price;
   g_gridCount++;
   return true;
  }

//+------------------------------------------------------------------+
//| Close All Active Basket Positions                                |
//+------------------------------------------------------------------+
void CloseAllBasketPositions(string reason)
  {
   PrintFormat("CloseAllBasketPositions | Reason:%s | Count:%d", reason, g_gridCount);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      ClosePosition(ticket);
     }

   g_cycleDir       = 0;
   g_gridCount      = 0;
   g_lastGridPrice  = 0.0;
   g_lastCycleClose = iTime(_Symbol, PERIOD_H1, 0);
  }

//+------------------------------------------------------------------+
//| Close a Single Position by Ticket                                |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
     { PrintFormat("ClosePosition: Cannot select %I64u", ticket); return false; }

   ENUM_POSITION_TYPE pType  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double             volume = PositionGetDouble(POSITION_VOLUME);
   string             symbol = PositionGetString(POSITION_SYMBOL);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = symbol;
   req.volume    = volume;
   req.type      = (pType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price     = (pType == POSITION_TYPE_BUY)
                   ? SymbolInfoDouble(symbol, SYMBOL_BID)
                   : SymbolInfoDouble(symbol, SYMBOL_ASK);
   req.deviation = InpSlippage;
   req.magic     = InpMagicNumber;
   req.position  = ticket;
   req.comment   = "Close_" + IntegerToString(InpMagicNumber);

   ENUM_ORDER_TYPE_FILLING fills[3] = {ORDER_FILLING_IOC, ORDER_FILLING_FOK, ORDER_FILLING_RETURN};
   bool sent = false;
   for(int f = 0; f < 3; f++)
     {
      req.type_filling = fills[f];
      sent = OrderSend(req, res);
      if(sent && res.retcode == TRADE_RETCODE_DONE)    break;
      if(res.retcode != TRADE_RETCODE_INVALID_FILL)    break;
     }

   if(!sent || res.retcode != TRADE_RETCODE_DONE)
     { PrintFormat("ClosePosition FAILED: %I64u retcode=%d", ticket, res.retcode); return false; }

   return true;
  }

//+------------------------------------------------------------------+
//| Total Floating Profit of All Basket Positions                    |
//| Includes swap (reflects true cost for drawdown calculation)      |
//+------------------------------------------------------------------+
double GetBasketFloatingProfit()
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return total;
  }

//+------------------------------------------------------------------+
//| Basket Profit in Points (volume-weighted average)                |
//| Used for points-based basket TP calculation                      |
//+------------------------------------------------------------------+
double GetBasketPointsProfit()
  {
   double totalVol    = 0.0;
   double weightedSum = 0.0;
   int    posType     = -1;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double vol    = PositionGetDouble(POSITION_VOLUME);
      double oprice = PositionGetDouble(POSITION_PRICE_OPEN);
      posType       = (int)PositionGetInteger(POSITION_TYPE);
      totalVol     += vol;
      weightedSum  += oprice * vol;
     }

   if(totalVol <= 0.0 || posType < 0) return 0.0;

   double avgOpen   = weightedSum / totalVol;
   double curPrice  = (posType == POSITION_TYPE_BUY)
                      ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                      : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pointDiff = (posType == POSITION_TYPE_BUY)
                      ? (curPrice - avgOpen)
                      : (avgOpen  - curPrice);

   double ptSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(ptSize <= 0.0) return 0.0;
   return pointDiff / ptSize;
  }

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+