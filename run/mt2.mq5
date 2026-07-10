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
//|  - ALL logic (emergency check, profit exit, grid adds, and new   |
//|    entries) evaluates only once per new completed bar — nothing  |
//|    is checked intra-bar / on every tick.                         |
//+------------------------------------------------------------------+
#property copyright "Generated EA — Grid Martingale variant"
#property version   "2.00"
#property strict

//=== INPUT PARAMETERS ===============================================
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
datetime g_lastBarTime  = 0;

//+------------------------------------------------------------------+
//|  IsNewBar                                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|  OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   hRSI    = iRSI (_Symbol, _Period, InpRSIPeriod,   PRICE_CLOSE);
   hADX    = iADX (_Symbol, _Period, InpADXPeriod);
   hEMA21  = iMA  (_Symbol, _Period, InpEMA21Period,  0, MODE_EMA, PRICE_CLOSE);
   hEMA50  = iMA  (_Symbol, _Period, InpEMA50Period,  0, MODE_EMA, PRICE_CLOSE);
   hEMA100 = iMA  (_Symbol, _Period, InpEMA100Period, 0, MODE_EMA, PRICE_CLOSE);
   hMACD   = iMACD(_Symbol, _Period, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

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

   int warmUp = MathMax(InpEMA100Period, InpMACDSlow + InpMACDSignal) + 10;
   Print("✅ Grid-Martingale EA initialized | Warm-up bars needed: ", warmUp);
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
   Print("🔴 EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//|  ReadIndicators                                                  |
//+------------------------------------------------------------------+
bool ReadIndicators(double &rsi,   double &adx,
                    double &ema21, double &ema50, double &ema100,
                    double &macd,  double &sig)
{
   double buf[1];

   if(CopyBuffer(hRSI,    0, 1, 1, buf) < 1) return false; rsi   = buf[0];
   if(CopyBuffer(hADX,    0, 1, 1, buf) < 1) return false; adx   = buf[0];
   if(CopyBuffer(hEMA21,  0, 1, 1, buf) < 1) return false; ema21  = buf[0];
   if(CopyBuffer(hEMA50,  0, 1, 1, buf) < 1) return false; ema50  = buf[0];
   if(CopyBuffer(hEMA100, 0, 1, 1, buf) < 1) return false; ema100 = buf[0];
   if(CopyBuffer(hMACD,   0, 1, 1, buf) < 1) return false; macd  = buf[0];
   if(CopyBuffer(hMACD,   1, 1, 1, buf) < 1) return false; sig   = buf[0];

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
//|  OnTick — main logic                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Everything below only evaluates once per new completed bar.
   if(!IsNewBar()) return;

   int    count;
   double totalVolume, floatingPL, lowestOpenPrice, lastLotSize;
   BasketSnapshot(count, totalVolume, floatingPL, lowestOpenPrice, lastLotSize);

   //=== 1) EMERGENCY EQUITY PROTECTION (checked once per new bar, highest priority) ===
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
            return; // basket flat, nothing else to do this tick
         }
      }
   }

   //=== 2) PROFIT-ONLY BASKET EXIT (checked once per new bar) ==================
   if(count > 0 && floatingPL >= InpMinBasketProfit)
   {
      PrintFormat("💰 BASKET PROFIT CLOSE | Levels=%d | Volume=%.2f | P&L=%.2f (target %.2f)",
                  count, totalVolume, floatingPL, InpMinBasketProfit);
      CloseBasket("BasketProfitClose");
      return;
   }

   //=== 3) GRID MARTINGALE ADD-ON (checked once per new bar) ===================
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
      return; // don't also evaluate a fresh level-1 entry while grid is active
   }

   //=== 4) FRESH GRID LEVEL 1 ENTRY (only if flat) ==============================
   if(count == 0)
   {
      if(CheckEntrySignal())
         SendMarketOrder(InpLotSize, "GridLevel_1");
   }
}
//+------------------------------------------------------------------+