//+------------------------------------------------------------------+
//|        Price Cross EA — Smart Sideways Filter                    |
//|                                                                  |
//|  Core idea:                                                      |
//|    BLOCK entry  → dead chop (sideways + no momentum)            |
//|    ALLOW entry  → sideways that's BREAKING OUT (expanding ATR,  |
//|                   big candle body, BB expanding, ADX rising)     |
//|                                                                  |
//|  This solves the "filter kills rally start" problem because      |
//|  big moves always begin with a volatility expansion that         |
//|  overrides the sideways block.                                   |
//+------------------------------------------------------------------+
#property strict

//==================================================================//
//                        INPUTS                                     //
//==================================================================//

input group "=== TRADE MANAGEMENT ==="
input double LotSize          = 0.01;
input int    Slippage         = 10;
input ulong  MagicNumber      = 123456;

input group "=== SIGNAL: EMA CROSS ==="
input int    FastEMA          = 10;    // Fast EMA period
input int    SlowEMA          = 34;    // Slow EMA — trend direction gate
// Cross confirmed when close crosses fast EMA by at least X * ATR
input double CrossATRMargin   = 0.10;  // Raise to reduce noise

input group "=== SIGNAL: SLOW EMA TREND GATE ==="
// Only buy when price is above slow EMA, sell when below
// Slope gate: slow EMA must be sloping in trade direction
input int    TrendSlopeBars   = 8;     // Bars to measure slow EMA slope
input double TrendSlopeMinATR = 0.04;  // Min slope (x ATR/bar) to confirm trend

input group "=== LAYER / HIGHER TF ==="
input int             layerPeriod      = 50;
input ENUM_TIMEFRAMES layerTimeframe   = PERIOD_H1;
input int             layerSlopePeriod = 5;
input double          layerSlopeMinATR = 0.03;

input group "=== ATR / TRAILING ==="
input int    atrPeriod        = 14;
input double atrSLMultiplier  = 1.5;
input double SarStep          = 0.02;
input double SarMax           = 0.2;

//------------------------------------------------------------------//
//   SIDEWAYS DETECTION — "DEAD CHOP" BLOCK                        //
//   Market is blocked ONLY when sideways AND no breakout signal    //
//------------------------------------------------------------------//

input group "=== SIDEWAYS: DEAD-CHOP DETECTION ==="
// A bar is considered sideways when enough of these are true:
input int    sw_MinVotes          = 2;   // Min votes to call it sideways

// ADX gate — low ADX = no trend
input bool   sw_Use_ADX           = true;
input int    sw_ADX_Period        = 14;
input double sw_ADX_Threshold     = 22.0; // Lower than default = stricter

// ATR compression — slow recent ATR vs long-term
input bool   sw_Use_ATR           = true;
input int    sw_ATR_Fast          = 5;
input int    sw_ATR_Slow          = 50;
input double sw_ATR_Ratio         = 0.70;

// BB width narrow
input bool   sw_Use_BB            = true;
input int    sw_BB_Period         = 20;
input double sw_BB_Dev            = 2.0;
input int    sw_BB_Lookback       = 40;
input double sw_BB_WidthPct       = 0.55;

// MA slope flat
input bool   sw_Use_MASlope       = true;
input int    sw_MA_Period         = 34;
input ENUM_MA_METHOD sw_MA_Method = MODE_EMA;
input int    sw_MA_SlopeLookback  = 5;
input double sw_MA_SlopeThresh    = 0.00015;

input group "=== BREAKOUT OVERRIDE ==="
// Even if sideways votes pass, a breakout signal ALLOWS the trade.
// This is the key fix — rallies/drops start from consolidation.

// Override 1: ATR expansion — current bar's ATR > average * multiplier
input bool   bo_Use_ATR_Expand    = true;
input int    bo_ATR_AvgPeriod     = 10;  // Average ATR over this many bars
input double bo_ATR_ExpandMult    = 1.30; // Current ATR > avg * this = breakout

// Override 2: Candle body expansion — big candle breaks the silence
input bool   bo_Use_BodyExpand    = true;
input int    bo_BodyAvgPeriod     = 10;  // Average body over N bars
input double bo_BodyExpandMult    = 1.50; // Body > avg * this = breakout candle

// Override 3: BB expansion — bands widening after squeeze
input bool   bo_Use_BB_Expand     = true;
// Uses same bb handle as sideways detection
input int    bo_BB_ExpLookback    = 3;   // Bars of consecutive width increase
input double bo_BB_ExpMinPct      = 0.10; // Each bar must widen by at least X%

// Override 4: ADX rising — even below threshold, if it's rising = trend starting
input bool   bo_Use_ADX_Rising    = true;
input int    bo_ADX_RiseBars      = 3;   // ADX must have risen for this many bars
// (uses same ADX handle)

//==================================================================//
//                    HANDLES                                        //
//==================================================================//

int fastHandle, slowHandle, atrHandle, sarHandle, layerHandle;
int sw_adxHandle  = INVALID_HANDLE;
int sw_atrFHandle = INVALID_HANDLE;
int sw_atrSHandle = INVALID_HANDLE;
int sw_bbHandle   = INVALID_HANDLE;
int sw_maHandle   = INVALID_HANDLE;

struct VirtualSL { ulong ticket; double sl; };
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle  = iMA (_Symbol, PERIOD_CURRENT, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   slowHandle  = iMA (_Symbol, PERIOD_CURRENT, SlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   atrHandle   = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle   = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);
   layerHandle = iMA (_Symbol, layerTimeframe, layerPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(sw_Use_ADX || bo_Use_ADX_Rising)
      sw_adxHandle  = iADX  (_Symbol, PERIOD_CURRENT, sw_ADX_Period);
   if(sw_Use_ATR)
     {
      sw_atrFHandle = iATR(_Symbol, PERIOD_CURRENT, sw_ATR_Fast);
      sw_atrSHandle = iATR(_Symbol, PERIOD_CURRENT, sw_ATR_Slow);
     }
   if(sw_Use_BB || bo_Use_BB_Expand)
      sw_bbHandle = iBands(_Symbol, PERIOD_CURRENT, sw_BB_Period, 0, sw_BB_Dev, PRICE_CLOSE);
   if(sw_Use_MASlope)
      sw_maHandle = iMA(_Symbol, PERIOD_CURRENT, sw_MA_Period, 0, sw_MA_Method, PRICE_CLOSE);

   bool ok = (fastHandle  != INVALID_HANDLE && slowHandle  != INVALID_HANDLE &&
              atrHandle   != INVALID_HANDLE && sarHandle   != INVALID_HANDLE &&
              layerHandle != INVALID_HANDLE);
   if((sw_Use_ADX||bo_Use_ADX_Rising) && sw_adxHandle==INVALID_HANDLE) ok=false;
   if(sw_Use_ATR && (sw_atrFHandle==INVALID_HANDLE || sw_atrSHandle==INVALID_HANDLE)) ok=false;
   if((sw_Use_BB||bo_Use_BB_Expand) && sw_bbHandle==INVALID_HANDLE) ok=false;
   if(sw_Use_MASlope && sw_maHandle==INVALID_HANDLE) ok=false;

   if(!ok) return INIT_FAILED;
   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle); IndicatorRelease(slowHandle);
   IndicatorRelease(atrHandle);  IndicatorRelease(sarHandle);
   IndicatorRelease(layerHandle);
   if(sw_adxHandle  != INVALID_HANDLE) IndicatorRelease(sw_adxHandle);
   if(sw_atrFHandle != INVALID_HANDLE) IndicatorRelease(sw_atrFHandle);
   if(sw_atrSHandle != INVALID_HANDLE) IndicatorRelease(sw_atrSHandle);
   if(sw_bbHandle   != INVALID_HANDLE) IndicatorRelease(sw_bbHandle);
   if(sw_maHandle   != INVALID_HANDLE) IndicatorRelease(sw_maHandle);
}

bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
}

//==================================================================//
//              SIDEWAYS DETECTION (DEAD CHOP)                      //
//==================================================================//

bool IsDeadChop()
{
   int votes = 0, enabled = 0;

   // METHOD 1: ADX low
   if(sw_Use_ADX)
     {
      enabled++;
      double adx[]; ArraySetAsSeries(adx,true);
      if(CopyBuffer(sw_adxHandle,0,0,3,adx)==3 && adx[1]>0 && adx[1]<sw_ADX_Threshold)
         votes++;
     }

   // METHOD 2: ATR compressed
   if(sw_Use_ATR)
     {
      enabled++;
      double af[],as_[]; ArraySetAsSeries(af,true); ArraySetAsSeries(as_,true);
      if(CopyBuffer(sw_atrFHandle,0,0,3,af)==3 &&
         CopyBuffer(sw_atrSHandle,0,0,3,as_)==3 && as_[1]>0 && (af[1]/as_[1])<sw_ATR_Ratio)
         votes++;
     }

   // METHOD 3: BB width narrow
   if(sw_Use_BB)
     {
      enabled++;
      int need=sw_BB_Lookback+3;
      double upper[],lower[],mid[];
      ArraySetAsSeries(upper,true); ArraySetAsSeries(lower,true); ArraySetAsSeries(mid,true);
      if(CopyBuffer(sw_bbHandle,1,0,need,upper)==need &&
         CopyBuffer(sw_bbHandle,2,0,need,lower)==need &&
         CopyBuffer(sw_bbHandle,0,0,need,mid)  ==need)
        {
         double curW=upper[1]-lower[1], sumW=0; int cnt=0;
         for(int k=1;k<need;k++) if(mid[k]>0){sumW+=upper[k]-lower[k];cnt++;}
         if(cnt>0 && (sumW/cnt)>0 && curW/(sumW/cnt) < sw_BB_WidthPct) votes++;
        }
     }

   // METHOD 4: MA slope flat
   if(sw_Use_MASlope)
     {
      enabled++;
      int need=sw_MA_SlopeLookback+3;
      double ma[]; ArraySetAsSeries(ma,true);
      if(CopyBuffer(sw_maHandle,0,0,need,ma)==need)
        {
         double price=iClose(_Symbol,PERIOD_CURRENT,1);
         if(price>0 && MathAbs(ma[1]-ma[1+sw_MA_SlopeLookback])/price < sw_MA_SlopeThresh)
            votes++;
        }
     }

   return (enabled > 0 && votes >= sw_MinVotes);
}

//==================================================================//
//         BREAKOUT OVERRIDE — allow trade even if sideways         //
//==================================================================//

bool IsBreakingOut()
{
   // OVERRIDE 1: ATR expansion
   if(bo_Use_ATR_Expand)
     {
      int need = bo_ATR_AvgPeriod + 3;
      double atr[]; ArraySetAsSeries(atr,true);
      if(CopyBuffer(atrHandle,0,0,need,atr)==need)
        {
         double sum=0;
         for(int k=2;k<need;k++) sum+=atr[k]; // exclude bar[1]
         double avg=sum/(need-2);
         if(avg>0 && atr[1] > avg * bo_ATR_ExpandMult)
            return true;
        }
     }

   // OVERRIDE 2: Big candle body
   if(bo_Use_BodyExpand)
     {
      int need = bo_BodyAvgPeriod + 3;
      double cls[],opn[];
      ArraySetAsSeries(cls,true); ArraySetAsSeries(opn,true);
      if(CopyClose(_Symbol,PERIOD_CURRENT,0,need,cls)==need &&
         CopyOpen (_Symbol,PERIOD_CURRENT,0,need,opn)==need)
        {
         double curBody = MathAbs(cls[1]-opn[1]);
         double sum=0;
         for(int k=2;k<need;k++) sum+=MathAbs(cls[k]-opn[k]);
         double avg=sum/(need-2);
         if(avg>0 && curBody > avg * bo_BodyExpandMult)
            return true;
        }
     }

   // OVERRIDE 3: BB bands expanding (widening for N consecutive bars)
   if(bo_Use_BB_Expand && sw_bbHandle != INVALID_HANDLE)
     {
      int need = bo_BB_ExpLookback + 3;
      double upper[],lower[];
      ArraySetAsSeries(upper,true); ArraySetAsSeries(lower,true);
      if(CopyBuffer(sw_bbHandle,1,0,need,upper)==need &&
         CopyBuffer(sw_bbHandle,2,0,need,lower)==need)
        {
         bool expanding = true;
         for(int k=1; k<=bo_BB_ExpLookback; k++)
           {
            double wNow  = upper[k]   - lower[k];
            double wPrev = upper[k+1] - lower[k+1];
            if(wPrev<=0 || (wNow-wPrev)/wPrev < bo_BB_ExpMinPct)
              { expanding=false; break; }
           }
         if(expanding) return true;
        }
     }

   // OVERRIDE 4: ADX rising for N bars (trend awakening)
   if(bo_Use_ADX_Rising && sw_adxHandle != INVALID_HANDLE)
     {
      int need = bo_ADX_RiseBars + 2;
      double adx[]; ArraySetAsSeries(adx,true);
      if(CopyBuffer(sw_adxHandle,0,0,need,adx)==need)
        {
         bool rising = true;
         for(int k=1; k<=bo_ADX_RiseBars; k++)
           { if(adx[k] <= adx[k+1]) { rising=false; break; } }
         if(rising) return true;
        }
     }

   return false;
}

//==================================================================//
//   MASTER GATE: block entry only on dead chop with no breakout    //
//==================================================================//
bool ShouldBlockEntry()
{
   if(!IsDeadChop())   return false;  // not sideways at all → allow
   if(IsBreakingOut()) return false;  // sideways but breaking out → allow
   return true;                       // dead chop, no breakout → block
}

//==================================================================//
//                         MAIN TICK                                //
//==================================================================//
void OnTick()
{
   if(!IsNewBar()) return;

   CheckVirtualStops();
   UpdateTrailingVirtualSL();

   int need = MathMax(TrendSlopeBars, bo_ATR_AvgPeriod) + 5;

   double fast[], slow[], atr[];
   double close[], open[];

   ArraySetAsSeries(fast, true); ArraySetAsSeries(slow, true);
   ArraySetAsSeries(atr,  true); ArraySetAsSeries(close,true);
   ArraySetAsSeries(open, true);

   if(CopyBuffer(fastHandle,0,0,need,fast)            < need) return;
   if(CopyBuffer(slowHandle,0,0,need,slow)            < need) return;
   if(CopyBuffer(atrHandle, 0,0,need,atr)             < need) return;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,need,close)  < need) return;
   if(CopyOpen (_Symbol,PERIOD_CURRENT,0,need,open)   < need) return;

   // GATE 1: dead chop without breakout → skip
   if(ShouldBlockEntry()) return;

   // GATE 2: one position at a time
   if(HasOpenPosition()) return;

   double atrNow = atr[1];
   if(atrNow <= 0) return;

   //--- PRICE × FAST EMA CROSS SIGNAL
   // Buy:  bar[2] was below fast EMA, bar[1] closed above it (+ margin)
   // Sell: bar[2] was above fast EMA, bar[1] closed below it (- margin)
   double margin = atrNow * CrossATRMargin;

   bool buySignal  = (close[2] < fast[2]) && (close[1] > fast[1] + margin);
   bool sellSignal = (close[2] > fast[2]) && (close[1] < fast[1] - margin);

   //--- SLOW EMA TREND GATE (direction + slope)
   // Buys only above slow EMA with rising slow EMA
   // Sells only below slow EMA with falling slow EMA
   double slowSlope = 0;
   if(1 + TrendSlopeBars < ArraySize(slow))
      slowSlope = (slow[1] - slow[1 + TrendSlopeBars]) / (TrendSlopeBars * atrNow);

   bool upTrend   = (close[1] > slow[1]) && (slowSlope >  TrendSlopeMinATR);
   bool downTrend = (close[1] < slow[1]) && (slowSlope < -TrendSlopeMinATR);

   buySignal  = buySignal  && upTrend;
   sellSignal = sellSignal && downTrend;

   //--- LAYER (HTF) GATE
   if(buySignal  && !IsLayerBullish()) buySignal  = false;
   if(sellSignal && !IsLayerBearish()) sellSignal = false;

   double slDist = atrNow * atrSLMultiplier;
   if(buySignal)  OpenBuy (SymbolInfoDouble(_Symbol,SYMBOL_ASK) - slDist);
   if(sellSignal) OpenSell(SymbolInfoDouble(_Symbol,SYMBOL_BID) + slDist);
}

//==================================================================//
//                   HELPER FUNCTIONS                               //
//==================================================================//

bool IsLayerBullish()
{
   double layer[],atr[],close[];
   ArraySetAsSeries(layer,true); ArraySetAsSeries(atr,true); ArraySetAsSeries(close,true);
   if(CopyBuffer(layerHandle,0,0,layerSlopePeriod+2,layer)<layerSlopePeriod+2) return false;
   if(CopyBuffer(atrHandle,  0,0,3,atr)<3) return false;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,3,close)<3) return false;
   double slope=(layer[1]-layer[1+layerSlopePeriod])/(layerSlopePeriod*atr[1]+1e-10);
   return (close[1]>layer[1] && slope>layerSlopeMinATR);
}

bool IsLayerBearish()
{
   double layer[],atr[],close[];
   ArraySetAsSeries(layer,true); ArraySetAsSeries(atr,true); ArraySetAsSeries(close,true);
   if(CopyBuffer(layerHandle,0,0,layerSlopePeriod+2,layer)<layerSlopePeriod+2) return false;
   if(CopyBuffer(atrHandle,  0,0,3,atr)<3) return false;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,3,close)<3) return false;
   double slope=(layer[1]-layer[1+layerSlopePeriod])/(layerSlopePeriod*atr[1]+1e-10);
   return (close[1]<layer[1] && slope<-layerSlopeMinATR);
}

//==================================================================//
//             POSITION / ORDER MANAGEMENT                          //
//==================================================================//

void CheckVirtualStops()
{
   double pH=iHigh(_Symbol,PERIOD_CURRENT,1);
   double pL=iLow (_Symbol,PERIOD_CURRENT,1);
   for(int i=ArraySize(vsl)-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(vsl[i].ticket)){ArrayRemove(vsl,i,1);continue;}
      long t=PositionGetInteger(POSITION_TYPE);
      bool hit=(t==POSITION_TYPE_BUY)?(pL<=vsl[i].sl):(pH>=vsl[i].sl);
      if(hit && ClosePosition(vsl[i].ticket)) ArrayRemove(vsl,i,1);
     }
}

bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t))
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber) return true;
     }
   return false;
}

bool OpenBuy(double slPrice)
{
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.type=ORDER_TYPE_BUY;
   req.volume=LotSize; req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   req.sl=0; req.tp=0; req.deviation=Slippage; req.magic=MagicNumber;
   if(!OrderSend(req,res)) return false;
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_DONE_PARTIAL)
      {AddVirtualSL(res.order,slPrice);return true;}
   return false;
}

bool OpenSell(double slPrice)
{
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.type=ORDER_TYPE_SELL;
   req.volume=LotSize; req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.sl=0; req.tp=0; req.deviation=Slippage; req.magic=MagicNumber;
   if(!OrderSend(req,res)) return false;
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_DONE_PARTIAL)
      {AddVirtualSL(res.order,slPrice);return true;}
   return false;
}

void AddVirtualSL(ulong ticket, double sl)
{
   int sz=ArraySize(vsl); ArrayResize(vsl,sz+1);
   vsl[sz].ticket=ticket; vsl[sz].sl=NormalizeDouble(sl,_Digits);
}

bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   long type=PositionGetInteger(POSITION_TYPE);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.position=ticket; req.symbol=_Symbol;
   req.volume=PositionGetDouble(POSITION_VOLUME); req.deviation=Slippage; req.magic=MagicNumber;
   if(type==POSITION_TYPE_BUY){req.type=ORDER_TYPE_SELL;req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);}
   else                       {req.type=ORDER_TYPE_BUY; req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);}
   if(!OrderSend(req,res)) return false;
   return (res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_DONE_PARTIAL);
}

void UpdateTrailingVirtualSL()
{
   double sar[]; ArraySetAsSeries(sar,true);
   if(CopyBuffer(sarHandle,0,0,3,sar)<3) return;
   for(int i=0;i<ArraySize(vsl);i++)
     {
      if(!PositionSelectByTicket(vsl[i].ticket)) continue;
      long t=PositionGetInteger(POSITION_TYPE);
      if(t==POSITION_TYPE_BUY  && sar[1]>vsl[i].sl) vsl[i].sl=NormalizeDouble(sar[1],_Digits);
      if(t==POSITION_TYPE_SELL && sar[1]<vsl[i].sl) vsl[i].sl=NormalizeDouble(sar[1],_Digits);
     }
}
//+------------------------------------------------------------------+