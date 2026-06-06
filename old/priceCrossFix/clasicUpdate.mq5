//+------------------------------------------------------------------+
//|        EMA Price Cross EA — Smart Sideways + Dot Visual          |
//|                                                                  |
//|  Dot BELOW bar  = dead chop blocked  (red by default)           |
//|  Dot ABOVE bar  = trending / breaking out → trades allowed      |
//+------------------------------------------------------------------+
#property strict

//==================================================================//
//                        INPUTS                                     //
//==================================================================//

input group "=== TRADE ==="
input double LotSize          = 0.01;
input int    Slippage         = 10;
input ulong  MagicNumber      = 123456;

input group "=== EMA SIGNAL ==="
input int    FastEMA          = 10;
input double CrossATRMargin   = 0.15;   // original 0.15

input group "=== TRAILING STOP ==="
input double SarStep          = 0.02;
input double SarMax           = 0.2;
input int    atrPeriod        = 14;
input double atrMultiplier    = 1.0;

input group "=== DOT VISUAL ==="
input color  SidewaysColor    = clrRed;    // dot below bar = blocked
input color  TrendingColor    = clrLime;   // dot above bar = allowed
input int    DotDistance      = 100;       // distance from candle in points

//------------------------------------------------------------------//
//   SIDEWAYS DETECTION                                             //
//   Votes: how many of the 4 methods must agree to call it flat   //
//------------------------------------------------------------------//

input group "=== SIDEWAYS: VOTE THRESHOLD ==="
input int    sw_MinVotes          = 2;

input group "=== SIDEWAYS: ADX ==="
input bool   sw_Use_ADX           = true;
input int    sw_ADX_Period        = 14;
input double sw_ADX_Threshold     = 22.0;

input group "=== SIDEWAYS: ATR COMPRESSION ==="
input bool   sw_Use_ATR           = true;
input int    sw_ATR_Fast          = 5;
input int    sw_ATR_Slow          = 50;
input double sw_ATR_Ratio         = 0.70;

input group "=== SIDEWAYS: BOLLINGER WIDTH ==="
input bool   sw_Use_BB            = true;
input int    sw_BB_Period         = 20;
input double sw_BB_Dev            = 2.0;
input int    sw_BB_Lookback       = 40;
input double sw_BB_WidthPct       = 0.55;

input group "=== SIDEWAYS: MA SLOPE ==="
input bool   sw_Use_MASlope       = true;
input int    sw_MA_Period         = 34;
input ENUM_MA_METHOD sw_MA_Method = MODE_EMA;
input int    sw_MA_SlopeLookback  = 5;
input double sw_MA_SlopeThresh    = 0.00015;

//------------------------------------------------------------------//
//   BREAKOUT OVERRIDE                                              //
//   If ANY of these fire, the sideways block is lifted.           //
//   Catches the start of a rally / drop from consolidation.       //
//------------------------------------------------------------------//

input group "=== BREAKOUT: ATR EXPANSION ==="
input bool   bo_Use_ATR           = true;
input int    bo_ATR_AvgPeriod     = 10;
input double bo_ATR_ExpandMult    = 1.30;

input group "=== BREAKOUT: BIG CANDLE BODY ==="
input bool   bo_Use_Body          = true;
input int    bo_BodyAvgPeriod     = 10;
input double bo_BodyExpandMult    = 1.50;

input group "=== BREAKOUT: BB EXPANDING ==="
input bool   bo_Use_BB_Expand     = true;
input int    bo_BB_ExpBars        = 3;
input double bo_BB_ExpMinPct      = 0.10;

input group "=== BREAKOUT: ADX RISING ==="
input bool   bo_Use_ADX_Rising    = true;
input int    bo_ADX_RiseBars      = 3;

//==================================================================//
//                    HANDLES                                        //
//==================================================================//

int fastHandle, atrHandle, sarHandle;
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
   fastHandle = iMA (_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle  = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
   sarHandle  = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);

   if(sw_Use_ADX || bo_Use_ADX_Rising)
      sw_adxHandle  = iADX  (_Symbol, PERIOD_CURRENT, sw_ADX_Period);
   if(sw_Use_ATR)
     {
      sw_atrFHandle = iATR(_Symbol, PERIOD_CURRENT, sw_ATR_Fast);
      sw_atrSHandle = iATR(_Symbol, PERIOD_CURRENT, sw_ATR_Slow);
     }
   if(sw_Use_BB || bo_Use_BB_Expand)
      sw_bbHandle   = iBands(_Symbol, PERIOD_CURRENT, sw_BB_Period, 0, sw_BB_Dev, PRICE_CLOSE);
   if(sw_Use_MASlope)
      sw_maHandle   = iMA(_Symbol, PERIOD_CURRENT, sw_MA_Period, 0, sw_MA_Method, PRICE_CLOSE);

   bool ok = (fastHandle != INVALID_HANDLE &&
              atrHandle  != INVALID_HANDLE &&
              sarHandle  != INVALID_HANDLE);
   if((sw_Use_ADX||bo_Use_ADX_Rising) && sw_adxHandle==INVALID_HANDLE)          ok=false;
   if(sw_Use_ATR && (sw_atrFHandle==INVALID_HANDLE||sw_atrSHandle==INVALID_HANDLE)) ok=false;
   if((sw_Use_BB||bo_Use_BB_Expand) && sw_bbHandle==INVALID_HANDLE)              ok=false;
   if(sw_Use_MASlope && sw_maHandle==INVALID_HANDLE)                              ok=false;

   if(!ok) return INIT_FAILED;
   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(sarHandle);
   if(sw_adxHandle  != INVALID_HANDLE) IndicatorRelease(sw_adxHandle);
   if(sw_atrFHandle != INVALID_HANDLE) IndicatorRelease(sw_atrFHandle);
   if(sw_atrSHandle != INVALID_HANDLE) IndicatorRelease(sw_atrSHandle);
   if(sw_bbHandle   != INVALID_HANDLE) IndicatorRelease(sw_bbHandle);
   if(sw_maHandle   != INVALID_HANDLE) IndicatorRelease(sw_maHandle);
   ObjectsDeleteAll(0, "SW_DOT_");
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
}

//==================================================================//
//   SIDEWAYS: is the market in dead chop?                          //
//==================================================================//
bool IsDeadChop()
{
   int votes=0, enabled=0;

   if(sw_Use_ADX)
     {
      enabled++;
      double adx[]; ArraySetAsSeries(adx,true);
      if(CopyBuffer(sw_adxHandle,0,0,3,adx)==3 && adx[1]>0 && adx[1]<sw_ADX_Threshold)
         votes++;
     }

   if(sw_Use_ATR)
     {
      enabled++;
      double af[],as_[]; ArraySetAsSeries(af,true); ArraySetAsSeries(as_,true);
      if(CopyBuffer(sw_atrFHandle,0,0,3,af)==3 &&
         CopyBuffer(sw_atrSHandle,0,0,3,as_)==3 && as_[1]>0 && (af[1]/as_[1])<sw_ATR_Ratio)
         votes++;
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
         if(price>0 && MathAbs(ma[1]-ma[1+sw_MA_SlopeLookback])/price<sw_MA_SlopeThresh)
            votes++;
        }
     }

   return (enabled>0 && votes>=sw_MinVotes);
}

//==================================================================//
//   BREAKOUT: is the chop about to end?                            //
//==================================================================//
bool IsBreakingOut()
{
   // 1. ATR expanding
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

   // 2. Big candle body
   if(bo_Use_Body)
     {
      int need=bo_BodyAvgPeriod+3;
      double cls[],opn[];
      ArraySetAsSeries(cls,true); ArraySetAsSeries(opn,true);
      if(CopyClose(_Symbol,PERIOD_CURRENT,0,need,cls)==need &&
         CopyOpen (_Symbol,PERIOD_CURRENT,0,need,opn)==need)
        {
         double curBody=MathAbs(cls[1]-opn[1]),sum=0;
         for(int k=2;k<need;k++) sum+=MathAbs(cls[k]-opn[k]);
         double avg=sum/(need-2);
         if(avg>0 && curBody>avg*bo_BodyExpandMult) return true;
        }
     }

   // 3. BB bands widening N bars in a row
   if(bo_Use_BB_Expand && sw_bbHandle!=INVALID_HANDLE)
     {
      int need=bo_BB_ExpBars+3;
      double upper[],lower[];
      ArraySetAsSeries(upper,true); ArraySetAsSeries(lower,true);
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

   // 4. ADX rising N bars straight
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

//+------------------------------------------------------------------+
// MASTER GATE
//   true  = block entry (draw red dot below bar)
//   false = allow entry (draw green dot above bar)
//+------------------------------------------------------------------+
bool ShouldBlock()
{
   if(!IsDeadChop())   return false;  // clearly moving → allow
   if(IsBreakingOut()) return false;  // waking up from chop → allow
   return true;                       // flat + silent → block
}

//==================================================================//
//                         MAIN TICK                                //
//==================================================================//
void OnTick()
{
   if(!IsNewBar()) return;

   CheckVirtualStops();
   UpdateTrailingVirtualSL();

   double fast[], atr[], close[], open[], high[], low[];
   ArraySetAsSeries(fast, true); ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close,true); ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high, true); ArraySetAsSeries(low,   true);

   if(CopyBuffer(fastHandle,0,0,3,fast)           < 3) return;
   if(CopyBuffer(atrHandle, 0,0,3,atr)            < 3) return;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,3,close) < 3) return;
   if(CopyOpen (_Symbol,PERIOD_CURRENT,0,3,open)  < 3) return;
   if(CopyHigh (_Symbol,PERIOD_CURRENT,0,3,high)  < 3) return;
   if(CopyLow  (_Symbol,PERIOD_CURRENT,0,3,low)   < 3) return;

   double currentPrice = close[0];
   double m = atr[1] * CrossATRMargin;

   // Original S1 / S2 / S3 signals — unchanged
   bool buyS1 = close[2] < fast[2] && close[1] > fast[1] + m;
   bool buyS2 = open[1]  < fast[1] - m && close[1] > fast[1] + m;
   bool buyS3 = high[2]  < fast[2] && close[1] > fast[1] + m;
   bool buySignal  = buyS1 || buyS2 || buyS3;

   bool sellS1 = close[2] > fast[2] && close[1] < fast[1] - m;
   bool sellS2 = open[1]  > fast[1] + m && close[1] < fast[1] - m;
   bool sellS3 = low[2]   > fast[2] && close[1] < fast[1] - m;
   bool sellSignal = sellS1 || sellS2 || sellS3;

   if(HasOpenPosition()) return;

   datetime t1     = iTime(_Symbol, PERIOD_CURRENT, 1);
   string   dotKey = "SW_DOT_" + IntegerToString((int)t1);

   if(ShouldBlock())
     {
      // Red dot BELOW bar = dead chop, entry blocked
      CreateDot(dotKey, t1, low[1] - (DotDistance * _Point), SidewaysColor);
      return;
     }

   // Green dot ABOVE bar = trending or breaking out, trades allowed
   CreateDot(dotKey, t1, high[1] + (DotDistance * _Point), TrendingColor);

   if(buySignal)  OpenBuy (currentPrice - atr[1] * atrMultiplier);
   if(sellSignal) OpenSell(currentPrice + atr[1] * atrMultiplier);
}

//==================================================================//
//             STOP / ORDER MANAGEMENT (UNCHANGED)                  //
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

void UpdateTrailingVirtualSL()
{
   double sar[]; ArraySetAsSeries(sar,true);
   if(CopyBuffer(sarHandle,0,0,3,sar)<3) return;
   double sarV=sar[1];
   for(int i=0;i<ArraySize(vsl);i++)
     {
      if(!PositionSelectByTicket(vsl[i].ticket)) continue;
      long t=PositionGetInteger(POSITION_TYPE);
      if(t==POSITION_TYPE_BUY  && sarV>vsl[i].sl) vsl[i].sl=NormalizeDouble(sarV,_Digits);
      if(t==POSITION_TYPE_SELL && sarV<vsl[i].sl) vsl[i].sl=NormalizeDouble(sarV,_Digits);
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

void CloseAndRemove(ulong ticket)
{
   if(ClosePosition(ticket))
      for(int i=ArraySize(vsl)-1;i>=0;i--)
         if(vsl[i].ticket==ticket){ArrayRemove(vsl,i,1);break;}
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

//+------------------------------------------------------------------+
//   CreateDot — identical to original implementation               //
//+------------------------------------------------------------------+
void CreateDot(string name, datetime t, double price, color clr)
{
   if(ObjectFind(0,name) >= 0) ObjectDelete(0,name);
   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}
//+------------------------------------------------------------------+