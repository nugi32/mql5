//+------------------------------------------------------------------+
//|                                              PriceCrossEA.mq5    |
//|           Price × EMA Cross EA + Sideways Market Filter          |
//|    Integrates all 6 SidewaysDetector methods (voting system)     |
//|    Virtual SL/TP — stops never sent to broker                    |
//+------------------------------------------------------------------+
#property copyright   "PriceCrossEA"
#property version     "1.00"
#property description "Price × EMA cross EA with integrated sideways filter."
#property description "Virtual SL/TP. Multiple cross-confirmation scenarios."

#include <Trade\Trade.mqh>
CTrade Trade;

//==================================================================//
//                    INPUT PARAMETERS                               //
//==================================================================//

input group "=== GENERAL ==="
input double LotSize            = 0.01;    // Lot size
input int    MagicNumber        = 202400;  // Magic number
input bool   CloseOnOpposite    = true;    // Close trade on opposite cross signal

input group "=== EMA SETTINGS ==="
input int    EMA_Period         = 21;      // EMA period
input ENUM_APPLIED_PRICE EMA_Price = PRICE_CLOSE; // EMA applied price

input group "=== CROSS DETECTION SCENARIOS ==="
// Each scenario is an independent way to confirm a valid cross.
// A signal fires when ANY enabled scenario triggers — but ONLY if
// the sideways filter permits (not in sideways market).
input bool   Scenario_CloseCross       = true;  // S1: Close crosses EMA (simple 1-bar)
input bool   Scenario_BodyCross        = true;  // S2: Full candle body clears EMA
input bool   Scenario_Confirmed2Bar    = true;  // S3: 2 consecutive closes confirm side
input bool   Scenario_MomentumCross    = true;  // S4: Cross + strong closing momentum
input bool   Scenario_RejectionFilter  = true;  // S5: Reject if wick-only (false cross guard)
input double Momentum_MinBodyRatio     = 0.40;  // S4: Min body/range ratio (0-1)

input group "=== VIRTUAL SL / TP ==="
input bool   UseVirtualSLTP     = true;    // Use virtual (hidden) SL & TP
input int    SL_Points          = 300;     // Stop loss in points (0 = disabled)
input int    TP_Points          = 600;     // Take profit in points (0 = disabled)
input bool   UseBreakEven       = true;    // Move SL to break-even
input int    BreakEvenTrigger   = 200;     // Points in profit to trigger BE
input int    BreakEvenBuffer    = 10;      // Extra points above entry for BE SL
input bool   UseTrailingStop    = false;   // Enable trailing stop
input int    TrailDistance      = 150;     // Trail distance in points
input int    TrailStep          = 30;      // Min points to move trail

input group "=== SIDEWAYS FILTER (Voting System) ==="
input bool   UseSidewaysFilter  = true;    // Enable sideways filter
input int    MinVotesRequired   = 3;       // Min methods that must agree sideways (1-6)
input bool   AllowExitInSideways = true;   // Allow close of existing trade in sideways

//--- Method 1: ADX
input group "--- Method 1: ADX ---"
input bool   Use_ADX            = true;
input int    ADX_Period         = 14;
input double ADX_Threshold      = 25.0;    // Sideways if ADX < threshold

//--- Method 2: ATR Ratio
input group "--- Method 2: ATR Ratio ---"
input bool   Use_ATR            = true;
input int    ATR_FastPeriod     = 5;
input int    ATR_SlowPeriod     = 50;
input double ATR_Ratio          = 0.75;    // Sideways if fast/slow < ratio

//--- Method 3: Bollinger Band Width
input group "--- Method 3: BB Width ---"
input bool   Use_BBWidth        = true;
input int    BB_Period          = 20;
input double BB_Deviation       = 2.0;
input int    BB_WidthLookback   = 50;
input double BB_WidthPercent    = 0.50;

//--- Method 4: MA Slope
input group "--- Method 4: MA Slope ---"
input bool   Use_MASlope        = true;
input int    MA_Period          = 50;
input ENUM_MA_METHOD MA_Method  = MODE_EMA;
input int    MA_SlopeLookback   = 5;
input double MA_SlopeThreshold  = 0.0002;

//--- Method 5: Linear Regression R²
input group "--- Method 5: LinReg R² ---"
input bool   Use_LinReg         = true;
input int    LinReg_Period      = 20;
input double LinReg_R2_Max      = 0.35;    // Sideways if R² < threshold

//--- Method 6: Price Channel Range
input group "--- Method 6: Price Channel ---"
input bool   Use_Channel        = true;
input int    Channel_Period     = 20;
input double Channel_ATR_Multi  = 1.5;

//==================================================================//
//                    GLOBALS                                        //
//==================================================================//

// Indicator handles
int h_EMA;
int h_ADX, h_ATR_Fast, h_ATR_Slow, h_BB, h_MA_Slope;

// Virtual SL/TP tracking
struct VirtualPosition
  {
   ulong  ticket;
   int    type;          // ORDER_TYPE_BUY or ORDER_TYPE_SELL
   double entryPrice;
   double virtualSL;
   double virtualTP;
   bool   breakEvenDone;
   double trailLevel;    // current trailing SL level
  };

VirtualPosition vPos;
bool            hasVirtualPos = false;

// For cross detection (store previous bar state)
double prevClose1 = 0;   // close[1] from last OnTick cycle
double prevClose2 = 0;   // close[2] from last OnTick cycle
double prevEMA1   = 0;
double prevEMA2   = 0;

datetime lastBarTime = 0; // track new bar

//+------------------------------------------------------------------+
int OnInit()
  {
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(20);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);

   // EMA handle
   h_EMA = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, EMA_Price);
   if(h_EMA == INVALID_HANDLE) { Alert("Failed to create EMA handle"); return INIT_FAILED; }

   // Sideways method handles
   if(Use_ADX)
     {
      h_ADX = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
      if(h_ADX == INVALID_HANDLE) { Alert("Failed to create ADX handle"); return INIT_FAILED; }
     }
   if(Use_ATR)
     {
      h_ATR_Fast = iATR(_Symbol, PERIOD_CURRENT, ATR_FastPeriod);
      h_ATR_Slow = iATR(_Symbol, PERIOD_CURRENT, ATR_SlowPeriod);
      if(h_ATR_Fast == INVALID_HANDLE || h_ATR_Slow == INVALID_HANDLE)
        { Alert("Failed to create ATR handles"); return INIT_FAILED; }
     }
   if(Use_BBWidth)
     {
      h_BB = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
      if(h_BB == INVALID_HANDLE) { Alert("Failed to create BB handle"); return INIT_FAILED; }
     }
   if(Use_MASlope)
     {
      h_MA_Slope = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MA_Method, PRICE_CLOSE);
      if(h_MA_Slope == INVALID_HANDLE) { Alert("Failed to create MA handle"); return INIT_FAILED; }
     }

   // Validate vote threshold
   int maxMethods = (int)Use_ADX + (int)Use_ATR + (int)Use_BBWidth +
                    (int)Use_MASlope + (int)Use_LinReg + (int)Use_Channel;
   if(UseSidewaysFilter && MinVotesRequired > maxMethods)
     {
      Alert("MinVotesRequired (", MinVotesRequired, ") > enabled methods (", maxMethods, ")");
      return INIT_FAILED;
     }

   hasVirtualPos = false;
   Print("PriceCrossEA initialized. EMA(", EMA_Period, ") | Sideways Filter: ",
         UseSidewaysFilter ? "ON" : "OFF");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(h_EMA);
   if(Use_ADX)     IndicatorRelease(h_ADX);
   if(Use_ATR)   { IndicatorRelease(h_ATR_Fast); IndicatorRelease(h_ATR_Slow); }
   if(Use_BBWidth) IndicatorRelease(h_BB);
   if(Use_MASlope) IndicatorRelease(h_MA_Slope);
  }

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
}


//+------------------------------------------------------------------+
void OnTick()
  {
    if(!IsNewBar()) return;
   // ── 1. Sync virtual position with real broker positions ──────────
   SyncVirtualPosition();

   // ── 2. Manage open virtual SL/TP on every tick ───────────────────
   if(hasVirtualPos)
      ManageVirtualSLTP();

   // ── 3. Only evaluate signals on a new closed bar ─────────────────
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == lastBarTime) return;
   lastBarTime = barTime;

   // ── 4. Collect price & indicator data ────────────────────────────
   double closeArr[4], emaArr[4], openArr[4], highArr[4], lowArr[4];
   if(CopyClose (_Symbol, PERIOD_CURRENT, 0, 4, closeArr) < 4) return;
   if(CopyOpen  (_Symbol, PERIOD_CURRENT, 0, 4, openArr)  < 4) return;
   if(CopyHigh  (_Symbol, PERIOD_CURRENT, 0, 4, highArr)  < 4) return;
   if(CopyLow   (_Symbol, PERIOD_CURRENT, 0, 4, lowArr)   < 4) return;
   if(CopyBuffer(h_EMA, 0, 0, 4, emaArr) < 4) return;

   // Series: index 0 = current forming bar, 1 = last closed, 2 = two bars ago
   double c1 = closeArr[1], c2 = closeArr[2];
   double o1 = openArr[1];
   double h1 = highArr[1], l1 = lowArr[1];
   double e1 = emaArr[1],  e2 = emaArr[2];

   // ── 5. Sideways detection ─────────────────────────────────────────
   bool isSideways = false;
   if(UseSidewaysFilter)
      isSideways = DetectSideways(1); // analyse bar index shift=1

   // ── 6. Cross signal detection ─────────────────────────────────────
   int signal = 0; // +1 = BUY cross, -1 = SELL cross

   // Raw cross direction (what actually happened on bar[1])
   bool crossedAbove = (c2 < e2) && (c1 > e1); // price crossed EMA upward
   bool crossedBelow = (c2 > e2) && (c1 < e1); // price crossed EMA downward

   if(crossedAbove || crossedBelow)
     {
      int rawDir = crossedAbove ? 1 : -1;
      int confirmCount = 0;
      int scenariosEnabled = 0;

      //------------------------------------------------------------
      // SCENARIO 1 — Simple close cross
      // Last closed bar's close is on the new side of EMA
      //------------------------------------------------------------
      if(Scenario_CloseCross)
        {
         scenariosEnabled++;
         // Already confirmed by crossedAbove/crossedBelow logic
         confirmCount++;
        }

      //------------------------------------------------------------
      // SCENARIO 2 — Full candle body clears EMA
      // Both open AND close of bar[1] are on the new side
      //------------------------------------------------------------
      if(Scenario_BodyCross)
        {
         scenariosEnabled++;
         bool bodyAbove = (o1 > e1) && (c1 > e1);
         bool bodyBelow = (o1 < e1) && (c1 < e1);
         if((rawDir == 1 && bodyAbove) || (rawDir == -1 && bodyBelow))
            confirmCount++;
        }

      //------------------------------------------------------------
      // SCENARIO 3 — Two-bar confirmation
      // Bar[1] AND bar[2] both close on the new side (momentum check)
      // For this scenario the cross actually happened at bar[2] or
      // before; we want two confirmed bars after the cross.
      // We redefine: bar[1] closes new side AND bar[2] already does too
      // (i.e. the cross happened before bar[2]).
      // Separate check: was bar[2] already on the new side?
      //------------------------------------------------------------
      if(Scenario_Confirmed2Bar)
        {
         scenariosEnabled++;
         // Need bar[2] and bar[3] close data
         if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 4, closeArr) >= 4)
           {
            double c3 = closeArr[3];
            double e3_arr[4];
            if(CopyBuffer(h_EMA, 0, 0, 4, e3_arr) >= 4)
              {
               double e3 = e3_arr[3];
               // c2 already on new side AND c1 continues
               bool twoBarBull = (c2 > e2) && (c1 > e1);
               bool twoBarBear = (c2 < e2) && (c1 < e1);
               // Cross must have occurred at bar 2 (c3 was on old side)
               bool origCrossBull = (c3 < e3) && twoBarBull;
               bool origCrossBear = (c3 > e3) && twoBarBear;
               if((rawDir == 1 && origCrossBull) || (rawDir == -1 && origCrossBear))
                  confirmCount++;
              }
           }
        }

      //------------------------------------------------------------
      // SCENARIO 4 — Momentum / strong candle cross
      // Body of bar[1] must be >= Momentum_MinBodyRatio of its range
      // Ensures the cross was driven by conviction, not a small close
      //------------------------------------------------------------
      if(Scenario_MomentumCross)
        {
         scenariosEnabled++;
         double range = h1 - l1;
         double body  = MathAbs(c1 - o1);
         bool strongCandle = (range > 0) && ((body / range) >= Momentum_MinBodyRatio);
         // Close must be on the new side (already true via crossedAbove/Below)
         // AND candle must close in the direction of the cross
         bool bullClose = (c1 > o1); // bullish candle
         bool bearClose = (c1 < o1); // bearish candle
         if(strongCandle &&
            ((rawDir == 1 && bullClose) || (rawDir == -1 && bearClose)))
            confirmCount++;
        }

      //------------------------------------------------------------
      // SCENARIO 5 — Rejection / false-cross guard
      // Passes only when the candle's WICK did NOT go deeply through
      // the EMA in the opposite direction (no false spike cross)
      // If this scenario is enabled and rejects, it REMOVES a vote
      //------------------------------------------------------------
      if(Scenario_RejectionFilter)
        {
         scenariosEnabled++;
         bool wickCross = false;
         if(rawDir == 1) // upward cross — check lower wick didn't spike far below EMA
           {
            double lowerWick = MathMin(o1, c1) - l1;
            double totalRange = h1 - l1;
            // If lower wick is >50% of range AND it dipped below EMA, suspect false
            wickCross = (totalRange > 0) && (lowerWick / totalRange > 0.50) && (l1 < e1);
           }
         else // downward cross — check upper wick
           {
            double upperWick = h1 - MathMax(o1, c1);
            double totalRange = h1 - l1;
            wickCross = (totalRange > 0) && (upperWick / totalRange > 0.50) && (h1 > e1);
           }
         if(!wickCross)
            confirmCount++; // valid — no deceptive wick
         // If wickCross = true we simply don't add a vote
        }

      // ── Signal decision ─────────────────────────────────────────
      // Require at least half the enabled scenarios to confirm
      int threshold = (int)MathCeil(scenariosEnabled / 2.0);
      if(confirmCount >= threshold)
         signal = rawDir;
     }

   // ── 7. Apply sideways filter ──────────────────────────────────────
   if(isSideways && signal != 0)
     {
      Comment("PriceCrossEA | Sideways detected — signal suppressed");
      signal = 0;
     }

   // ── 8. Execute or close trades ────────────────────────────────────
   if(signal != 0)
     {
      bool hasBuy  = PositionExistsByMagic(ORDER_TYPE_BUY);
      bool hasSell = PositionExistsByMagic(ORDER_TYPE_SELL);

      if(signal == 1) // BUY signal
        {
         if(hasSell && CloseOnOpposite)
            CloseAllByMagic();
         if(!hasBuy && !hasVirtualPos)
            OpenTrade(ORDER_TYPE_BUY);
        }
      else if(signal == -1) // SELL signal
        {
         if(hasBuy && CloseOnOpposite)
            CloseAllByMagic();
         if(!hasSell && !hasVirtualPos)
            OpenTrade(ORDER_TYPE_SELL);
        }
     }

   // ── 9. Dashboard comment ──────────────────────────────────────────
   string info = StringFormat(
      "PriceCrossEA  |  EMA(%d)  |  Sideways: %s\n"
      "Last bar: C=%.5f  EMA=%.5f  Signal=%s\n"
      "Virtual SL/TP: %s  |  Pos: %s",
      EMA_Period,
      isSideways ? "YES" : "NO",
      closeArr[1], emaArr[1],
      signal == 1 ? "BUY" : signal == -1 ? "SELL" : "—",
      UseVirtualSLTP ? "ON" : "OFF",
      hasVirtualPos ? StringFormat("%.5f | SL %.5f | TP %.5f",
                       vPos.entryPrice, vPos.virtualSL, vPos.virtualTP) : "None"
   );
   Comment(info);
  }

//+------------------------------------------------------------------+
//| Open a trade and register virtual SL/TP                          |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
  {
   double price  = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point  = _Point;

   double sl = 0, tp = 0;

   if(!UseVirtualSLTP)
     {
      // Real broker SL/TP
      if(SL_Points > 0)
         sl = (type == ORDER_TYPE_BUY) ? price - SL_Points * point
                                       : price + SL_Points * point;
      if(TP_Points > 0)
         tp = (type == ORDER_TYPE_BUY) ? price + TP_Points * point
                                       : price - TP_Points * point;
      if(type == ORDER_TYPE_BUY)
         Trade.Buy(LotSize, _Symbol, price, sl, tp, "PriceCrossEA");
      else
         Trade.Sell(LotSize, _Symbol, price, sl, tp, "PriceCrossEA");
     }
   else
     {
      // Virtual — send to broker with NO stops
      bool result = false;
      if(type == ORDER_TYPE_BUY)
         result = Trade.Buy(LotSize, _Symbol, price, 0, 0, "PriceCrossEA");
      else
         result = Trade.Sell(LotSize, _Symbol, price, 0, 0, "PriceCrossEA");

      if(result)
        {
         // Register virtual levels
         vPos.ticket      = Trade.ResultDeal();
         vPos.type        = (int)type;
         vPos.entryPrice  = price;
         vPos.breakEvenDone = false;

         if(SL_Points > 0)
            vPos.virtualSL = (type == ORDER_TYPE_BUY) ? price - SL_Points * point
                                                       : price + SL_Points * point;
         else
            vPos.virtualSL = 0;

         if(TP_Points > 0)
            vPos.virtualTP = (type == ORDER_TYPE_BUY) ? price + TP_Points * point
                                                       : price - TP_Points * point;
         else
            vPos.virtualTP = 0;

         vPos.trailLevel = vPos.virtualSL;
         hasVirtualPos   = true;

         PrintFormat("Trade opened: %s @ %.5f | vSL=%.5f | vTP=%.5f",
                     EnumToString(type), price, vPos.virtualSL, vPos.virtualTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| Check & act on virtual SL/TP on every tick                       |
//+------------------------------------------------------------------+
void ManageVirtualSLTP()
  {
   if(!UseVirtualSLTP || !hasVirtualPos) return;

   // Make sure real position still exists
   if(!PositionSelectByTicket(vPos.ticket))
     {
      // Position may have been closed manually — resync
      SyncVirtualPosition();
      return;
     }

   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = _Point;
   double curPrice = (vPos.type == ORDER_TYPE_BUY) ? bid : ask;

   // ── Virtual TP hit ───────────────────────────────────────────────
   if(vPos.virtualTP > 0)
     {
      bool tpHit = (vPos.type == ORDER_TYPE_BUY && bid >= vPos.virtualTP) ||
                   (vPos.type == ORDER_TYPE_SELL && ask <= vPos.virtualTP);
      if(tpHit)
        {
         PrintFormat("Virtual TP hit @ %.5f", curPrice);
         CloseVirtualPosition();
         return;
        }
     }

   // ── Virtual SL hit ───────────────────────────────────────────────
   if(vPos.virtualSL > 0)
     {
      bool slHit = (vPos.type == ORDER_TYPE_BUY && bid <= vPos.virtualSL) ||
                   (vPos.type == ORDER_TYPE_SELL && ask >= vPos.virtualSL);
      if(slHit)
        {
         PrintFormat("Virtual SL hit @ %.5f", curPrice);
         CloseVirtualPosition();
         return;
        }
     }

   // ── Break-even ───────────────────────────────────────────────────
   if(UseBreakEven && !vPos.breakEvenDone && BreakEvenTrigger > 0)
     {
      double profitPoints = (vPos.type == ORDER_TYPE_BUY)
                            ? (bid - vPos.entryPrice) / point
                            : (vPos.entryPrice - ask) / point;

      if(profitPoints >= BreakEvenTrigger)
        {
         double newSL = (vPos.type == ORDER_TYPE_BUY)
                        ? vPos.entryPrice + BreakEvenBuffer * point
                        : vPos.entryPrice - BreakEvenBuffer * point;

         // Only move in profit direction
         bool improved = (vPos.type == ORDER_TYPE_BUY && newSL > vPos.virtualSL) ||
                         (vPos.type == ORDER_TYPE_SELL && (vPos.virtualSL == 0 || newSL < vPos.virtualSL));
         if(improved)
           {
            vPos.virtualSL     = newSL;
            vPos.trailLevel    = newSL;
            vPos.breakEvenDone = true;
            PrintFormat("Break-even set: vSL moved to %.5f", newSL);
           }
        }
     }

   // ── Trailing stop ────────────────────────────────────────────────
   if(UseTrailingStop && TrailDistance > 0)
     {
      double newTrail = (vPos.type == ORDER_TYPE_BUY)
                        ? bid - TrailDistance * point
                        : ask + TrailDistance * point;

      bool trailMoved = false;
      if(vPos.type == ORDER_TYPE_BUY &&
         newTrail > vPos.trailLevel + TrailStep * point)
        {
         vPos.trailLevel = newTrail;
         trailMoved = true;
        }
      else if(vPos.type == ORDER_TYPE_SELL &&
              newTrail < vPos.trailLevel - TrailStep * point)
        {
         vPos.trailLevel = newTrail;
         trailMoved = true;
        }

      if(trailMoved)
        {
         vPos.virtualSL = vPos.trailLevel;
         // PrintFormat("Trail moved: vSL = %.5f", vPos.virtualSL); // uncomment if needed
        }
     }
  }

//+------------------------------------------------------------------+
//| Close the virtual position by market                             |
//+------------------------------------------------------------------+
void CloseVirtualPosition()
  {
   if(PositionSelectByTicket(vPos.ticket))
     {
      ENUM_ORDER_TYPE closeType = (vPos.type == ORDER_TYPE_BUY)
                                  ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double closePrice = (closeType == ORDER_TYPE_SELL)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      Trade.PositionClose(vPos.ticket);
     }
   hasVirtualPos = false;
   Print("Virtual position closed.");
  }

//+------------------------------------------------------------------+
//| Sync virtual pos struct to real broker positions                 |
//+------------------------------------------------------------------+
void SyncVirtualPosition()
  {
   if(!hasVirtualPos) return;

   if(!PositionSelectByTicket(vPos.ticket))
     {
      // Position no longer exists on broker
      hasVirtualPos = false;
      return;
     }
  }

//+------------------------------------------------------------------+
//| Close all positions for this EA's magic                          |
//+------------------------------------------------------------------+
void CloseAllByMagic()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            Trade.PositionClose(ticket);
            if(hasVirtualPos && vPos.ticket == ticket)
               hasVirtualPos = false;
           }
     }
  }

//+------------------------------------------------------------------+
//| Check if position of type exists for this magic                  |
//+------------------------------------------------------------------+
bool PositionExistsByMagic(ENUM_ORDER_TYPE type)
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            (int)PositionGetInteger(POSITION_TYPE) == (int)type)
            return true;
     }
   return false;
  }

//==================================================================//
//             SIDEWAYS DETECTOR — All 6 Methods                    //
//   (Ported directly from SidewaysDetector.mq5, bar-shift based)   //
//==================================================================//

//+------------------------------------------------------------------+
//| Master sideways detection at bar shift 'shift'                   //
//| Returns true if MinVotesRequired agree on sideways               |
//+------------------------------------------------------------------+
bool DetectSideways(int shift)
  {
   int votes   = 0;
   int enabled = 0;
   int needed  = shift + 10; // enough buffer

   //----------------------------------------------------------------
   // METHOD 1: ADX
   //----------------------------------------------------------------
   if(Use_ADX)
     {
      enabled++;
      double adxBuf[5];
      ArraySetAsSeries(adxBuf, true);
      if(CopyBuffer(h_ADX, 0, 0, needed + 5, adxBuf) > shift)
         if(adxBuf[shift] < ADX_Threshold && adxBuf[shift] > 0)
            votes++;
     }

   //----------------------------------------------------------------
   // METHOD 2: ATR Ratio
   //----------------------------------------------------------------
   if(Use_ATR)
     {
      enabled++;
      double atrFBuf[5], atrSBuf[5];
      ArraySetAsSeries(atrFBuf, true);
      ArraySetAsSeries(atrSBuf, true);
      if(CopyBuffer(h_ATR_Fast, 0, 0, needed + 5, atrFBuf) > shift &&
         CopyBuffer(h_ATR_Slow, 0, 0, needed + 5, atrSBuf) > shift)
         if(atrSBuf[shift] > 0 && (atrFBuf[shift] / atrSBuf[shift]) < ATR_Ratio)
            votes++;
     }

   //----------------------------------------------------------------
   // METHOD 3: BB Width
   //----------------------------------------------------------------
   if(Use_BBWidth)
     {
      enabled++;
      int bbn = needed + BB_WidthLookback + 5;
      double bbU[], bbL[], bbM[];
      ArraySetAsSeries(bbU, true);
      ArraySetAsSeries(bbL, true);
      ArraySetAsSeries(bbM, true);
      if(CopyBuffer(h_BB, 1, 0, bbn, bbU) > shift + BB_WidthLookback &&
         CopyBuffer(h_BB, 2, 0, bbn, bbL) > shift + BB_WidthLookback &&
         CopyBuffer(h_BB, 0, 0, bbn, bbM) > shift + BB_WidthLookback)
        {
         double curW = bbU[shift] - bbL[shift];
         double sumW = 0; int cnt = 0;
         for(int k = shift; k < shift + BB_WidthLookback; k++)
           {
            if(k < (int)ArraySize(bbU) && bbM[k] > 0)
              { sumW += (bbU[k] - bbL[k]); cnt++; }
           }
         if(cnt > 0)
           {
            double avgW = sumW / cnt;
            if(avgW > 0 && (curW / avgW) < BB_WidthPercent) votes++;
           }
        }
     }

   //----------------------------------------------------------------
   // METHOD 4: MA Slope
   //----------------------------------------------------------------
   if(Use_MASlope)
     {
      enabled++;
      int man = needed + MA_SlopeLookback + 5;
      double maB[];
      ArraySetAsSeries(maB, true);
      if(CopyBuffer(h_MA_Slope, 0, 0, man, maB) > shift + MA_SlopeLookback)
        {
         double slope = MathAbs(maB[shift] - maB[shift + MA_SlopeLookback]);
         double cl1[2]; ArraySetAsSeries(cl1, true);
         if(CopyClose(_Symbol, PERIOD_CURRENT, 0, shift + 3, cl1) > shift)
           {
            double normSlope = (cl1[shift] > 0) ? slope / cl1[shift] : 1.0;
            if(normSlope < MA_SlopeThreshold) votes++;
           }
        }
     }

   //----------------------------------------------------------------
   // METHOD 5: Linear Regression R²
   //----------------------------------------------------------------
   if(Use_LinReg)
     {
      enabled++;
      double cl[];
      ArraySetAsSeries(cl, true);
      int lrn = shift + LinReg_Period + 5;
      if(CopyClose(_Symbol, PERIOD_CURRENT, 0, lrn, cl) >= shift + LinReg_Period)
        {
         double r2 = CalcR2Series(cl, shift, LinReg_Period);
         if(r2 >= 0 && r2 < LinReg_R2_Max) votes++;
        }
     }

   //----------------------------------------------------------------
   // METHOD 6: Price Channel
   //----------------------------------------------------------------
   if(Use_Channel)
     {
      enabled++;
      double hi[], lo[];
      ArraySetAsSeries(hi, true);
      ArraySetAsSeries(lo, true);
      int chn = shift + Channel_Period + 5;
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, chn, hi) >= shift + Channel_Period &&
         CopyLow (_Symbol, PERIOD_CURRENT, 0, chn, lo) >= shift + Channel_Period)
        {
         double hiMax = hi[shift], loMin = lo[shift];
         for(int k = shift; k < shift + Channel_Period; k++)
           {
            if(hi[k] > hiMax) hiMax = hi[k];
            if(lo[k] < loMin) loMin = lo[k];
           }
         double chanRange = hiMax - loMin;

         double atrV[5]; ArraySetAsSeries(atrV, true);
         double atr14 = 0;
         if(Use_ATR && CopyBuffer(h_ATR_Slow, 0, 0, shift + 5, atrV) > shift)
            atr14 = atrV[shift];
         else
           {
            double cl2[], h2[], l2[];
            ArraySetAsSeries(cl2, true); ArraySetAsSeries(h2, true); ArraySetAsSeries(l2, true);
            int need14 = shift + 18;
            CopyClose(_Symbol, PERIOD_CURRENT, 0, need14, cl2);
            CopyHigh (_Symbol, PERIOD_CURRENT, 0, need14, h2);
            CopyLow  (_Symbol, PERIOD_CURRENT, 0, need14, l2);
            double sum14 = 0;
            for(int k = shift; k < shift + 14; k++)
              {
               double tr = h2[k] - l2[k];
               if(k + 1 < (int)ArraySize(cl2))
                 {
                  tr = MathMax(tr, MathAbs(h2[k] - cl2[k + 1]));
                  tr = MathMax(tr, MathAbs(l2[k] - cl2[k + 1]));
                 }
               sum14 += tr;
              }
            atr14 = sum14 / 14.0;
           }

         if(atr14 > 0 && chanRange < Channel_ATR_Multi * atr14)
            votes++;
        }
     }

   return (enabled > 0 && votes >= MinVotesRequired);
  }

//+------------------------------------------------------------------+
//| R² on series-style (index 0 = most recent) arrays               |
//+------------------------------------------------------------------+
double CalcR2Series(const double &cl[], int startShift, int period)
  {
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
   int n = period;

   for(int k = 0; k < n; k++)
     {
      int idx = startShift + (n - 1 - k); // oldest at k=0, newest at k=n-1
      if(idx >= (int)ArraySize(cl)) return -1;
      double x = (double)k;
      double y = cl[idx];
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
      sumY2 += y * y;
     }

   double denom = (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY);
   if(denom <= 0) return 0;
   double r = (n * sumXY - sumX * sumY) / MathSqrt(denom);
   return r * r;
  }
//+------------------------------------------------------------------+