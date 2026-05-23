//+------------------------------------------------------------------+
//|          Trend Follow EA — Optimizer-Safe Parameter Handling     |
//|                                                                  |
//|  Key fix: NO parameter validation in OnInit.                    |
//|  Bad param combos → zero trades (low score) not INIT_FAILED.   |
//|  OnInit only fails if indicator handles can't be created.       |
//+------------------------------------------------------------------+
#property strict

//==================================================================//
//                        INPUTS                                     //
//==================================================================//

input group "=== TRADE ==="
input double LotSize          = 0.01;
input int    Slippage         = 10;
input ulong  MagicNumber      = 123456;

input group "=== DIRECTION CONTROL ==="
input bool   EnableBuys       = true;
input bool   EnableSells      = true;

input group "=== EMA ==="
input int    FastEMA          = 10;
input int    SlowEMA          = 50;

input group "=== SIGNAL QUALITY ==="
input double CrossATRMargin   = 0.36;
input double MinBodyRatio     = 0.56;

input group "=== TREND GATE ==="
input int    TrendSlopeBars   = 10;
input double TrendSlopeMin    = 0.050;

input group "=== RSI MOMENTUM GATE ==="
// Optimizer range MUST be set to 1–99 in the .set file.
// If BuyMin >= BuyMax the buy RSI gate is simply never true → no buys.
// This scores the pass poorly but does NOT crash the run.
input int    RSI_Period       = 14;
input double RSI_BuyMin       = 48.0;
input double RSI_BuyMax       = 72.0;
input double RSI_SellMin      = 39.2;
input double RSI_SellMax      = 52.0;

input group "=== STOPS ==="
input double SL_ATR_Multi     = 1.5;
input double TP_ATR_Multi     = 3.0;
input double SarStep          = 0.02;
input double SarMax           = 0.2;
input double SarActivateATR   = 0.8;

input group "=== ATR ==="
input int    atrPeriod        = 14;

input group "=== DOT VISUAL ==="
input color  SidewaysColor    = clrRed;
input color  TrendingColor    = clrLime;
input int    DotDistance      = 100;

//--- SIDEWAYS ---
input group "=== SIDEWAYS: VOTES ==="
input int    sw_MinVotes      = 2;

input group "=== SIDEWAYS: ADX ==="
input bool   sw_Use_ADX       = true;
input int    sw_ADX_Period    = 14;
input double sw_ADX_Threshold = 22.0;

input group "=== SIDEWAYS: ATR COMPRESSION ==="
input bool   sw_Use_ATR       = true;
input int    sw_ATR_Fast      = 5;
input int    sw_ATR_Slow      = 50;
input double sw_ATR_Ratio     = 0.70;

input group "=== SIDEWAYS: BOLLINGER WIDTH ==="
input bool   sw_Use_BB        = true;
input int    sw_BB_Period     = 20;
input double sw_BB_Dev        = 2.0;
input int    sw_BB_Lookback   = 40;
input double sw_BB_WidthPct   = 0.55;

input group "=== SIDEWAYS: MA SLOPE ==="
input bool   sw_Use_MASlope       = true;
input int    sw_MA_Period         = 34;
input ENUM_MA_METHOD sw_MA_Method = MODE_EMA;
input int    sw_MA_SlopeLookback  = 5;
input double sw_MA_SlopeThresh    = 0.00015;

input group "=== BREAKOUT OVERRIDE ==="
input bool   bo_Use_ATR         = true;
input int    bo_ATR_AvgPeriod   = 10;
input double bo_ATR_ExpandMult  = 1.30;
input bool   bo_Use_Body        = true;
input int    bo_BodyAvgPeriod   = 10;
input double bo_BodyExpandMult  = 1.50;
input bool   bo_Use_BB_Expand   = true;
input int    bo_BB_ExpBars      = 3;
input double bo_BB_ExpMinPct    = 0.10;
input bool   bo_Use_ADX_Rising  = true;
input int    bo_ADX_RiseBars    = 3;

//==================================================================//
//                 TRADE GUARD                                       //
//==================================================================//

struct TradeGuard
{
   ulong  ticket;
   double sl;
   double tp;
   double entryPrice;
   int    direction;
   bool   sarActive;
};
TradeGuard guards[];

//==================================================================//
//                    HANDLES                                        //
//==================================================================//

int fastHandle, slowHandle, atrHandle, sarHandle, rsiHandle;
int sw_adxHandle  = INVALID_HANDLE;
int sw_atrFHandle = INVALID_HANDLE;
int sw_atrSHandle = INVALID_HANDLE;
int sw_bbHandle   = INVALID_HANDLE;
int sw_maHandle   = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   // ONLY fail if indicator handles can't be created.
   // Parameter validation is intentionally NOT here —
   // bad param combos just produce zero trades and score poorly.

   fastHandle = iMA (_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA (_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle  = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle  = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);
   rsiHandle  = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);

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

   bool ok = (fastHandle != INVALID_HANDLE && slowHandle != INVALID_HANDLE &&
              atrHandle  != INVALID_HANDLE && sarHandle  != INVALID_HANDLE &&
              rsiHandle  != INVALID_HANDLE);
   if((sw_Use_ADX||bo_Use_ADX_Rising) && sw_adxHandle==INVALID_HANDLE)             ok=false;
   if(sw_Use_ATR && (sw_atrFHandle==INVALID_HANDLE||sw_atrSHandle==INVALID_HANDLE)) ok=false;
   if((sw_Use_BB||bo_Use_BB_Expand) && sw_bbHandle==INVALID_HANDLE)                ok=false;
   if(sw_Use_MASlope && sw_maHandle==INVALID_HANDLE)                                ok=false;

   if(!ok) return INIT_FAILED;

   ArrayResize(guards, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle); IndicatorRelease(slowHandle);
   IndicatorRelease(atrHandle);  IndicatorRelease(sarHandle);
   IndicatorRelease(rsiHandle);
   if(sw_adxHandle  != INVALID_HANDLE) IndicatorRelease(sw_adxHandle);
   if(sw_atrFHandle != INVALID_HANDLE) IndicatorRelease(sw_atrFHandle);
   if(sw_atrSHandle != INVALID_HANDLE) IndicatorRelease(sw_atrSHandle);
   if(sw_bbHandle   != INVALID_HANDLE) IndicatorRelease(sw_bbHandle);
   if(sw_maHandle   != INVALID_HANDLE) IndicatorRelease(sw_maHandle);
   ObjectsDeleteAll(0, "SW_DOT_");
}

bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
}

//==================================================================//
//   VIRTUAL SL + TP                                                //
//==================================================================//

void CheckGuards()
{
   double pH = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double pL = iLow (_Symbol, PERIOD_CURRENT, 1);

   for(int i = ArraySize(guards)-1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(guards[i].ticket)) { ArrayRemove(guards,i,1); continue; }

      bool hitSL, hitTP;
      if(guards[i].direction == 1)
         { hitSL=(pL<=guards[i].sl); hitTP=(pH>=guards[i].tp); }
      else
         { hitSL=(pH>=guards[i].sl); hitTP=(pL<=guards[i].tp); }

      if(hitTP || hitSL)
         if(ClosePosition(guards[i].ticket)) ArrayRemove(guards,i,1);
     }
}

void UpdateTrailingSL()
{
   double sar[], atr[];
   ArraySetAsSeries(sar,true); ArraySetAsSeries(atr,true);
   if(CopyBuffer(sarHandle,0,0,3,sar)<3) return;
   if(CopyBuffer(atrHandle,0,0,3,atr)<3) return;

   for(int i=0; i<ArraySize(guards); i++)
     {
      if(!PositionSelectByTicket(guards[i].ticket)) continue;
      double price = (guards[i].direction==1)
                     ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double pnl = guards[i].direction * (price - guards[i].entryPrice);
      if(!guards[i].sarActive && pnl >= SarActivateATR * atr[1])
         guards[i].sarActive = true;
      if(!guards[i].sarActive) continue;
      if(guards[i].direction== 1 && sar[1]>guards[i].sl && sar[1]<guards[i].tp)
         guards[i].sl = NormalizeDouble(sar[1],_Digits);
      if(guards[i].direction==-1 && sar[1]<guards[i].sl && sar[1]>guards[i].tp)
         guards[i].sl = NormalizeDouble(sar[1],_Digits);
     }
}

//==================================================================//
//   SIDEWAYS                                                       //
//==================================================================//

bool IsDeadChop()
{
   int votes=0, enabled=0;
   if(sw_Use_ADX)
     {
      enabled++;
      double adx[]; ArraySetAsSeries(adx,true);
      if(CopyBuffer(sw_adxHandle,0,0,3,adx)==3 && adx[1]>0 && adx[1]<sw_ADX_Threshold) votes++;
     }
   if(sw_Use_ATR)
     {
      enabled++;
      double af[],as_[]; ArraySetAsSeries(af,true); ArraySetAsSeries(as_,true);
      if(CopyBuffer(sw_atrFHandle,0,0,3,af)==3 &&
         CopyBuffer(sw_atrSHandle,0,0,3,as_)==3 && as_[1]>0 && (af[1]/as_[1])<sw_ATR_Ratio) votes++;
     }
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
         double curW=upper[1]-lower[1],sumW=0; int cnt=0;
         for(int k=1;k<need;k++) if(mid[k]>0){sumW+=upper[k]-lower[k];cnt++;}
         if(cnt>0 && (sumW/cnt)>0 && curW/(sumW/cnt)<sw_BB_WidthPct) votes++;
        }
     }
   if(sw_Use_MASlope)
     {
      enabled++;
      int need=sw_MA_SlopeLookback+3;
      double ma[]; ArraySetAsSeries(ma,true);
      if(CopyBuffer(sw_maHandle,0,0,need,ma)==need)
        {
         double price=iClose(_Symbol,PERIOD_CURRENT,1);
         if(price>0 && MathAbs(ma[1]-ma[1+sw_MA_SlopeLookback])/price<sw_MA_SlopeThresh) votes++;
        }
     }
   return (enabled>0 && votes>=sw_MinVotes);
}

bool IsBreakingOut()
{
   if(bo_Use_ATR)
     {
      int need=bo_ATR_AvgPeriod+3;
      double atr[]; ArraySetAsSeries(atr,true);
      if(CopyBuffer(atrHandle,0,0,need,atr)==need)
        {
         double sum=0; for(int k=2;k<need;k++) sum+=atr[k];
         double avg=sum/(need-2);
         if(avg>0 && atr[1]>avg*bo_ATR_ExpandMult) return true;
        }
     }
   if(bo_Use_Body)
     {
      int need=bo_BodyAvgPeriod+3;
      double cls[],opn[]; ArraySetAsSeries(cls,true); ArraySetAsSeries(opn,true);
      if(CopyClose(_Symbol,PERIOD_CURRENT,0,need,cls)==need &&
         CopyOpen (_Symbol,PERIOD_CURRENT,0,need,opn)==need)
        {
         double curB=MathAbs(cls[1]-opn[1]),sum=0;
         for(int k=2;k<need;k++) sum+=MathAbs(cls[k]-opn[k]);
         double avg=sum/(need-2);
         if(avg>0 && curB>avg*bo_BodyExpandMult) return true;
        }
     }
   if(bo_Use_BB_Expand && sw_bbHandle!=INVALID_HANDLE)
     {
      int need=bo_BB_ExpBars+3;
      double upper[],lower[]; ArraySetAsSeries(upper,true); ArraySetAsSeries(lower,true);
      if(CopyBuffer(sw_bbHandle,1,0,need,upper)==need &&
         CopyBuffer(sw_bbHandle,2,0,need,lower)==need)
        {
         bool exp=true;
         for(int k=1;k<=bo_BB_ExpBars;k++)
           {
            double wN=upper[k]-lower[k],wP=upper[k+1]-lower[k+1];
            if(wP<=0||(wN-wP)/wP<bo_BB_ExpMinPct){exp=false;break;}
           }
         if(exp) return true;
        }
     }
   if(bo_Use_ADX_Rising && sw_adxHandle!=INVALID_HANDLE)
     {
      int need=bo_ADX_RiseBars+2;
      double adx[]; ArraySetAsSeries(adx,true);
      if(CopyBuffer(sw_adxHandle,0,0,need,adx)==need)
        {
         bool rising=true;
         for(int k=1;k<=bo_ADX_RiseBars;k++)
            if(adx[k]<=adx[k+1]){rising=false;break;}
         if(rising) return true;
        }
     }
   return false;
}

bool ShouldBlock() { return IsDeadChop() && !IsBreakingOut(); }

//==================================================================//
//                         MAIN TICK                                //
//==================================================================//

void OnTick()
{
   if(!IsNewBar()) return;

   CheckGuards();
   UpdateTrailingSL();

   int need = TrendSlopeBars + 5;
   double fast[],slow[],atr[],rsi[],close[],open[],high[],low[];
   ArraySetAsSeries(fast,true); ArraySetAsSeries(slow,true);
   ArraySetAsSeries(atr,true);  ArraySetAsSeries(rsi,true);
   ArraySetAsSeries(close,true);ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true); ArraySetAsSeries(low,true);

   if(CopyBuffer(fastHandle,0,0,need,fast)           <need) return;
   if(CopyBuffer(slowHandle,0,0,need,slow)           <need) return;
   if(CopyBuffer(atrHandle, 0,0,need,atr)            <need) return;
   if(CopyBuffer(rsiHandle, 0,0,need,rsi)            <need) return;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,need,close) <need) return;
   if(CopyOpen (_Symbol,PERIOD_CURRENT,0,need,open)  <need) return;
   if(CopyHigh (_Symbol,PERIOD_CURRENT,0,need,high)  <need) return;
   if(CopyLow  (_Symbol,PERIOD_CURRENT,0,need,low)   <need) return;

   double atrNow = atr[1];
   if(atrNow <= 0) return;

   // Dot
   datetime t1     = iTime(_Symbol,PERIOD_CURRENT,1);
   string   dotKey = "SW_DOT_" + IntegerToString((int)t1);
   if(ShouldBlock())
     { CreateDot(dotKey,t1,low[1]-(DotDistance*_Point),SidewaysColor); return; }
   CreateDot(dotKey,t1,high[1]+(DotDistance*_Point),TrendingColor);

   if(HasOpenPosition()) return;

   // Slow EMA slope
   double slowSlope = 0;
   if(1+TrendSlopeBars < ArraySize(slow))
      slowSlope = (slow[1]-slow[1+TrendSlopeBars]) / (TrendSlopeBars*atrNow);

   bool upTrend   = (slowSlope >  TrendSlopeMin) && (close[1] > slow[1]);
   bool downTrend = (slowSlope < -TrendSlopeMin) && (close[1] < slow[1]);

   // Cross
   double margin  = atrNow * CrossATRMargin;
   bool crossUp   = (close[2]<fast[2]) && (close[1]>fast[1]+margin);
   bool crossDown = (close[2]>fast[2]) && (close[1]<fast[1]-margin);

   // Candle body
   bool goodBody = (MathAbs(close[1]-open[1]) >= atrNow * MinBodyRatio);

   // RSI gate — if Min >= Max the condition is always false → no trades
   // This is intentional: bad RSI ranges score 0 trades, not a crash
   bool rsiBuy  = (RSI_BuyMin  < RSI_BuyMax)  && (rsi[1]>=RSI_BuyMin  && rsi[1]<=RSI_BuyMax);
   bool rsiSell = (RSI_SellMin < RSI_SellMax) && (rsi[1]>=RSI_SellMin && rsi[1]<=RSI_SellMax);

   // TP must give better R:R than SL — if not, skip silently
   bool goodRR = (TP_ATR_Multi > SL_ATR_Multi);

   bool buySignal  = goodRR && EnableBuys  && upTrend   && crossUp   && goodBody && rsiBuy;
   bool sellSignal = goodRR && EnableSells && downTrend && crossDown && goodBody && rsiSell;

   double slDist = atrNow * SL_ATR_Multi;
   double tpDist = atrNow * TP_ATR_Multi;

   if(buySignal)
     {
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      OpenBuy(ask-slDist, ask+tpDist, ask);
     }
   if(sellSignal)
     {
      double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      OpenSell(bid+slDist, bid-tpDist, bid);
     }
}

//==================================================================//
//   ORDER MANAGEMENT                                               //
//==================================================================//

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

bool OpenBuy(double sl, double tp, double entry)
{
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.type=ORDER_TYPE_BUY;
   req.volume=LotSize; req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   req.sl=0; req.tp=0; req.deviation=Slippage; req.magic=MagicNumber;
   if(!OrderSend(req,res)) return false;
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_DONE_PARTIAL)
      { AddGuard(res.order,sl,tp,entry,1); return true; }
   return false;
}

bool OpenSell(double sl, double tp, double entry)
{
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.type=ORDER_TYPE_SELL;
   req.volume=LotSize; req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.sl=0; req.tp=0; req.deviation=Slippage; req.magic=MagicNumber;
   if(!OrderSend(req,res)) return false;
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_DONE_PARTIAL)
      { AddGuard(res.order,sl,tp,entry,-1); return true; }
   return false;
}

void AddGuard(ulong ticket, double sl, double tp, double entry, int dir)
{
   int sz=ArraySize(guards); ArrayResize(guards,sz+1);
   guards[sz].ticket     = ticket;
   guards[sz].sl         = NormalizeDouble(sl,_Digits);
   guards[sz].tp         = NormalizeDouble(tp,_Digits);
   guards[sz].entryPrice = entry;
   guards[sz].direction  = dir;
   guards[sz].sarActive  = false;
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

void CreateDot(string name, datetime t, double price, color clr)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,159);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
}
//+------------------------------------------------------------------+