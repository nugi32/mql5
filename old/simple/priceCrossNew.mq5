//+------------------------------------------------------------------+
//|          EMA Pullback EA — Sideways Logic Fully Embedded         |
//|  No external indicator dependency — compiles and runs standalone  |
//+------------------------------------------------------------------+
#property strict

//==================================================================//
//                        INPUTS                                     //
//==================================================================//

input group "=== TRADE MANAGEMENT ==="
input double LotSize          = 0.01;
input int    Slippage         = 10;
input ulong  MagicNumber      = 123456;

input group "=== EMA SETTINGS ==="
input int    FastEMA          = 10;
input int    SlowEMA          = 34;

input group "=== SIGNAL: PULLBACK ZONE ==="
input double PullbackATRZone  = 0.6;
input int    PullbackLookback = 4;

input group "=== SIGNAL: ENTRY CANDLE ==="
input double MinBodyRatio     = 0.35;
input double ConfirmPips      = 0.5;

input group "=== SIGNAL: RSI MOMENTUM ==="
input int    RSI_Period       = 14;
input double RSI_BuyMin       = 45.0;
input double RSI_BuyMax       = 72.0;
input double RSI_SellMin      = 28.0;
input double RSI_SellMax      = 55.0;

input group "=== SIGNAL: SLOW EMA SLOPE ==="
input int    SlopeATRPeriod   = 5;
input double SlopeMinATR      = 0.08;

input group "=== SIGNAL: STRUCTURE ==="
input bool   UseStructure      = true;
input int    StructureLookback = 5;

input group "=== LAYER / HIGHER TF FILTER ==="
input int             layerPeriod      = 50;
input ENUM_TIMEFRAMES layerTimeframe   = PERIOD_H1;
input int             layerSlopePeriod = 5;
input double          layerSlopeMinATR = 0.05;

input group "=== ATR STOP LOSS ==="
input int    atrPeriod        = 14;
input double atrSLMultiplier  = 1.5;

input group "=== PARABOLIC SAR (TRAILING) ==="
input double SarStep          = 0.02;
input double SarMax           = 0.2;

input group "=== SIDEWAYS: VOTING ==="
input int    sw_MinVotes          = 3;

input group "=== SIDEWAYS: ADX ==="
input bool   sw_Use_ADX           = true;
input int    sw_ADX_Period        = 14;
input double sw_ADX_Threshold     = 25.0;

input group "=== SIDEWAYS: ATR RATIO ==="
input bool   sw_Use_ATR           = true;
input int    sw_ATR_Fast          = 5;
input int    sw_ATR_Slow          = 50;
input double sw_ATR_Ratio         = 0.75;

input group "=== SIDEWAYS: BOLLINGER WIDTH ==="
input bool   sw_Use_BB            = true;
input int    sw_BB_Period         = 20;
input double sw_BB_Dev            = 2.0;
input int    sw_BB_Lookback       = 50;
input double sw_BB_WidthPct       = 0.50;

input group "=== SIDEWAYS: MA SLOPE ==="
input bool   sw_Use_MASlope       = true;
input int    sw_MA_Period         = 50;
input ENUM_MA_METHOD sw_MA_Method = MODE_EMA;
input int    sw_MA_SlopeLookback  = 5;
input double sw_MA_SlopeThresh    = 0.0002;

input group "=== SIDEWAYS: LINEAR REGRESSION R2 ==="
input bool   sw_Use_LinReg        = true;
input int    sw_LinReg_Period     = 20;
input double sw_LinReg_R2_Max     = 0.35;

input group "=== SIDEWAYS: PRICE CHANNEL ==="
input bool   sw_Use_Channel       = true;
input int    sw_Channel_Period    = 20;
input double sw_Channel_ATRMult   = 1.5;

//==================================================================//
//                    HANDLES                                        //
//==================================================================//

int fastHandle, slowHandle, atrHandle, sarHandle, layerHandle, rsiHandle;
int sw_adxHandle   = INVALID_HANDLE;
int sw_atrFHandle  = INVALID_HANDLE;
int sw_atrSHandle  = INVALID_HANDLE;
int sw_bbHandle    = INVALID_HANDLE;
int sw_maHandle    = INVALID_HANDLE;

struct VirtualSL { ulong ticket; double sl; };
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle  = iMA (_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle  = iMA (_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle   = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle   = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);
   rsiHandle   = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   layerHandle = iMA (_Symbol, layerTimeframe,  layerPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(sw_Use_ADX)     sw_adxHandle  = iADX(_Symbol, PERIOD_CURRENT, sw_ADX_Period);
   if(sw_Use_ATR)   { sw_atrFHandle = iATR(_Symbol, PERIOD_CURRENT, sw_ATR_Fast);
                      sw_atrSHandle = iATR(_Symbol, PERIOD_CURRENT, sw_ATR_Slow); }
   if(sw_Use_BB)      sw_bbHandle   = iBands(_Symbol, PERIOD_CURRENT, sw_BB_Period, 0, sw_BB_Dev, PRICE_CLOSE);
   if(sw_Use_MASlope) sw_maHandle   = iMA  (_Symbol, PERIOD_CURRENT, sw_MA_Period, 0, sw_MA_Method, PRICE_CLOSE);

   bool ok = (fastHandle  != INVALID_HANDLE && slowHandle  != INVALID_HANDLE &&
              atrHandle   != INVALID_HANDLE && sarHandle   != INVALID_HANDLE &&
              rsiHandle   != INVALID_HANDLE && layerHandle != INVALID_HANDLE);

   if(sw_Use_ADX     && sw_adxHandle  == INVALID_HANDLE) ok = false;
   if(sw_Use_ATR     && (sw_atrFHandle == INVALID_HANDLE ||
                         sw_atrSHandle == INVALID_HANDLE)) ok = false;
   if(sw_Use_BB      && sw_bbHandle   == INVALID_HANDLE) ok = false;
   if(sw_Use_MASlope && sw_maHandle   == INVALID_HANDLE) ok = false;

   if(!ok) return INIT_FAILED;
   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle); IndicatorRelease(slowHandle);
   IndicatorRelease(atrHandle);  IndicatorRelease(sarHandle);
   IndicatorRelease(rsiHandle);  IndicatorRelease(layerHandle);
   if(sw_adxHandle  != INVALID_HANDLE) IndicatorRelease(sw_adxHandle);
   if(sw_atrFHandle != INVALID_HANDLE) IndicatorRelease(sw_atrFHandle);
   if(sw_atrSHandle != INVALID_HANDLE) IndicatorRelease(sw_atrSHandle);
   if(sw_bbHandle   != INVALID_HANDLE) IndicatorRelease(sw_bbHandle);
   if(sw_maHandle   != INVALID_HANDLE) IndicatorRelease(sw_maHandle);
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime current = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current != lastBar) { lastBar = current; return true; }
   return false;
}

//==================================================================//
//           SIDEWAYS DETECTION — FULLY INLINE                      //
//==================================================================//

double BufVal(int handle, int bufIndex, int shift)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, bufIndex, 0, shift + 1, arr) < shift + 1) return EMPTY_VALUE;
   return arr[shift];
}

double CalcR2_EA(const double &cls[], int period)
{
   if(period < 2 || ArraySize(cls) < period) return -1;
   double sumX=0,sumY=0,sumXY=0,sumX2=0,sumY2=0;
   for(int k=0;k<period;k++)
     {
      double x=(double)k, y=cls[k];
      sumX+=x; sumY+=y; sumXY+=x*y; sumX2+=x*x; sumY2+=y*y;
     }
   double denom=(period*sumX2-sumX*sumX)*(period*sumY2-sumY*sumY);
   if(denom<=0) return 0;
   double r=(period*sumXY-sumX*sumY)/MathSqrt(denom);
   return r*r;
}

bool IsSideways()
{
   int votes=0, enabled=0;
   double atrRef = BufVal(atrHandle, 0, 1);
   if(atrRef <= 0) return false;

   // METHOD 1: ADX
   if(sw_Use_ADX)
     {
      enabled++;
      double v = BufVal(sw_adxHandle, 0, 1);
      if(v != EMPTY_VALUE && v > 0 && v < sw_ADX_Threshold) votes++;
     }

   // METHOD 2: ATR Ratio
   if(sw_Use_ATR)
     {
      enabled++;
      double af = BufVal(sw_atrFHandle, 0, 1);
      double as = BufVal(sw_atrSHandle, 0, 1);
      if(af != EMPTY_VALUE && as > 0 && (af/as) < sw_ATR_Ratio) votes++;
     }

   // METHOD 3: BB Width
   if(sw_Use_BB)
     {
      enabled++;
      int need = sw_BB_Lookback + 3;
      double upper[], lower[], mid[];
      ArraySetAsSeries(upper,true); ArraySetAsSeries(lower,true); ArraySetAsSeries(mid,true);
      if(CopyBuffer(sw_bbHandle,1,0,need,upper)==need &&
         CopyBuffer(sw_bbHandle,2,0,need,lower)==need &&
         CopyBuffer(sw_bbHandle,0,0,need,mid)  ==need)
        {
         double curW=upper[1]-lower[1], sumW=0; int cnt=0;
         for(int k=1;k<need;k++) if(mid[k]>0){sumW+=upper[k]-lower[k];cnt++;}
         if(cnt>0 && (sumW/cnt)>0 && curW/(sumW/cnt)<sw_BB_WidthPct) votes++;
        }
     }

   // METHOD 4: MA Slope
   if(sw_Use_MASlope)
     {
      enabled++;
      int need = sw_MA_SlopeLookback + 3;
      double ma[];
      ArraySetAsSeries(ma, true);
      if(CopyBuffer(sw_maHandle, 0, 0, need, ma) == need)
        {
         double price = iClose(_Symbol, PERIOD_CURRENT, 1);
         if(price > 0 && MathAbs(ma[1]-ma[1+sw_MA_SlopeLookback])/price < sw_MA_SlopeThresh)
            votes++;
        }
     }

   // METHOD 5: Linear Regression R2
   if(sw_Use_LinReg)
     {
      enabled++;
      int need = sw_LinReg_Period + 2;
      double cls[];
      // oldest-first for R2 calc: shift=1 means skip current bar
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, need, cls) == need)
        {
         // Reverse so index 0 = oldest
         double tmp[]; ArrayResize(tmp, sw_LinReg_Period);
         for(int k=0;k<sw_LinReg_Period;k++) tmp[k] = cls[need-1-k];
         double r2 = CalcR2_EA(tmp, sw_LinReg_Period);
         if(r2 >= 0 && r2 < sw_LinReg_R2_Max) votes++;
        }
     }

   // METHOD 6: Price Channel
   if(sw_Use_Channel)
     {
      enabled++;
      int need = sw_Channel_Period + 2;
      double hi[], lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(_Symbol,PERIOD_CURRENT,1,need,hi)==need &&
         CopyLow (_Symbol,PERIOD_CURRENT,1,need,lo)==need)
        {
         double hMax=hi[0],lMin=lo[0];
         for(int k=1;k<need;k++){if(hi[k]>hMax)hMax=hi[k];if(lo[k]<lMin)lMin=lo[k];}
         if(atrRef>0 && (hMax-lMin)<sw_Channel_ATRMult*atrRef) votes++;
        }
     }

   return (enabled > 0 && votes >= sw_MinVotes);
}

//==================================================================//
//                         MAIN TICK                                //
//==================================================================//
void OnTick()
{
   if(!IsNewBar()) return;

   CheckVirtualStops();
   UpdateTrailingVirtualSL();

   int need = MathMax(PullbackLookback, StructureLookback) + 5;

   double fast[], slow[], atr[], rsi[];
   double close[], open[], high[], low[];

   ArraySetAsSeries(fast,  true); ArraySetAsSeries(slow,  true);
   ArraySetAsSeries(atr,   true); ArraySetAsSeries(rsi,   true);
   ArraySetAsSeries(close, true); ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true); ArraySetAsSeries(low,   true);

   if(CopyBuffer(fastHandle,0,0,need,fast)            < need) return;
   if(CopyBuffer(slowHandle,0,0,need,slow)            < need) return;
   if(CopyBuffer(atrHandle, 0,0,need,atr)             < need) return;
   if(CopyBuffer(rsiHandle, 0,0,need,rsi)             < need) return;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,need,close)  < need) return;
   if(CopyOpen (_Symbol,PERIOD_CURRENT,0,need,open)   < need) return;
   if(CopyHigh (_Symbol,PERIOD_CURRENT,0,need,high)   < need) return;
   if(CopyLow  (_Symbol,PERIOD_CURRENT,0,need,low)    < need) return;

   if(IsSideways())       return;
   if(HasOpenPosition())  return;

   bool layerBull = IsLayerBullish();
   bool layerBear = IsLayerBearish();

   double atrNow = atr[1];
   if(atrNow <= 0) return;

   bool upSlope   = SlowEMASlope(slow, atrNow) >  SlopeMinATR;
   bool downSlope = SlowEMASlope(slow, atrNow) < -SlopeMinATR;

   double zone = atrNow * PullbackATRZone;
   bool hadBullPullback = false, hadBearPullback = false;
   for(int k=2; k<=PullbackLookback+1; k++)
     {
      if(low[k]  <= fast[k]+zone && low[k]  >= fast[k]-zone*1.5 && close[k] > fast[k]-zone) hadBullPullback = true;
      if(high[k] >= fast[k]-zone && high[k] <= fast[k]+zone*1.5 && close[k] < fast[k]+zone) hadBearPullback = true;
     }

   double body    = MathAbs(close[1] - open[1]);
   double confirm = ConfirmPips * _Point * 10;
   bool   realC   = (body >= atrNow * MinBodyRatio);
   bool bullCandle = (close[1]>open[1]) && realC && (close[1]>fast[1]+confirm);
   bool bearCandle = (close[1]<open[1]) && realC && (close[1]<fast[1]-confirm);

   bool rsiBull = (rsi[1]>=RSI_BuyMin  && rsi[1]<=RSI_BuyMax);
   bool rsiBear = (rsi[1]>=RSI_SellMin && rsi[1]<=RSI_SellMax);

   bool aboveSlow = (close[1] > slow[1]);
   bool belowSlow = (close[1] < slow[1]);

   bool structureBull = true, structureBear = true;
   if(UseStructure)
     {
      double swH=high[2], swL=low[2];
      for(int k=2;k<StructureLookback+2;k++){if(high[k]>swH)swH=high[k];if(low[k]<swL)swL=low[k];}
      structureBull = (close[1] > swH - atrNow*0.3);
      structureBear = (close[1] < swL + atrNow*0.3);
     }

   bool buySignal  = upSlope   && aboveSlow && hadBullPullback && bullCandle && rsiBull  && structureBull && layerBull;
   bool sellSignal = downSlope && belowSlow && hadBearPullback && bearCandle && rsiBear  && structureBear && layerBear;

   double slDist = atrNow * atrSLMultiplier;
   if(buySignal)  OpenBuy (SymbolInfoDouble(_Symbol,SYMBOL_ASK) - slDist);
   if(sellSignal) OpenSell(SymbolInfoDouble(_Symbol,SYMBOL_BID) + slDist);
}

//==================================================================//
//                   HELPER FUNCTIONS                               //
//==================================================================//

double SlowEMASlope(const double &slow[], double atrNow)
{
   if(SlopeATRPeriod<=0 || atrNow<=0 || 1+SlopeATRPeriod>=ArraySize(slow)) return 0;
   return (slow[1]-slow[1+SlopeATRPeriod])/(SlopeATRPeriod*atrNow);
}

bool IsLayerBullish()
{
   double layer[], atr[], close[];
   ArraySetAsSeries(layer,true); ArraySetAsSeries(atr,true); ArraySetAsSeries(close,true);
   if(CopyBuffer(layerHandle,0,0,layerSlopePeriod+2,layer) < layerSlopePeriod+2) return false;
   if(CopyBuffer(atrHandle,  0,0,3,atr)   < 3) return false;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,3,close) < 3) return false;
   double slope=(layer[1]-layer[1+layerSlopePeriod])/(layerSlopePeriod*atr[1]+1e-10);
   return (close[1]>layer[1] && slope>layerSlopeMinATR);
}

bool IsLayerBearish()
{
   double layer[], atr[], close[];
   ArraySetAsSeries(layer,true); ArraySetAsSeries(atr,true); ArraySetAsSeries(close,true);
   if(CopyBuffer(layerHandle,0,0,layerSlopePeriod+2,layer) < layerSlopePeriod+2) return false;
   if(CopyBuffer(atrHandle,  0,0,3,atr)   < 3) return false;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,3,close) < 3) return false;
   double slope=(layer[1]-layer[1+layerSlopePeriod])/(layerSlopePeriod*atr[1]+1e-10);
   return (close[1]<layer[1] && slope<-layerSlopeMinATR);
}

//==================================================================//
//             POSITION / ORDER MANAGEMENT                          //
//==================================================================//

void CheckVirtualStops()
{
   double prevHigh=iHigh(_Symbol,PERIOD_CURRENT,1);
   double prevLow =iLow (_Symbol,PERIOD_CURRENT,1);
   for(int i=ArraySize(vsl)-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(vsl[i].ticket)){ArrayRemove(vsl,i,1);continue;}
      long type=PositionGetInteger(POSITION_TYPE);
      bool hit=(type==POSITION_TYPE_BUY)?(prevLow<=vsl[i].sl):(prevHigh>=vsl[i].sl);
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
   double sar[];
   ArraySetAsSeries(sar,true);
   if(CopyBuffer(sarHandle,0,0,3,sar)<3) return;
   double sarV=sar[1];
   for(int i=0;i<ArraySize(vsl);i++)
     {
      if(!PositionSelectByTicket(vsl[i].ticket)) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(type==POSITION_TYPE_BUY  && sarV>vsl[i].sl) vsl[i].sl=NormalizeDouble(sarV,_Digits);
      if(type==POSITION_TYPE_SELL && sarV<vsl[i].sl) vsl[i].sl=NormalizeDouble(sarV,_Digits);
     }
}
//+------------------------------------------------------------------+