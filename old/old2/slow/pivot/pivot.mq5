//+------------------------------------------------------------------+
//|                                              PivotTouchTrader    |
//|                       Trade when price touches pivot levels      |
//+------------------------------------------------------------------+
#property strict

input double LotSize = 0.1;
input double StopLossPoints = 300;      // dalam points
input double TakeProfitPoints = 600;    // dalam points
input bool   TradePP = false;           // aktifkan trade di PP?
input int    Slippage = 10;

double pp, r1, r2, s1, s2;
datetime last_day = 0;

bool tradedPP=false, tradedR1=false, tradedR2=false, tradedS1=false, tradedS2=false;

//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnTick()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != last_day)
   {
      last_day = today;
      CalculatePivot();
      ResetFlags();
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   CheckTouch(bid, ask);
}
//+------------------------------------------------------------------+
void CalculatePivot()
{
   double H = iHigh(_Symbol, PERIOD_D1, 1);
   double L = iLow(_Symbol, PERIOD_D1, 1);
   double C = iClose(_Symbol, PERIOD_D1, 1);

   pp = (H + L + C) / 3.0;
   r1 = (2.0 * pp) - L;
   s1 = (2.0 * pp) - H;
   r2 = pp + (H - L);
   s2 = pp - (H - L);
}
//+------------------------------------------------------------------+
void ResetFlags()
{
   tradedPP=false;
   tradedR1=false;
   tradedR2=false;
   tradedS1=false;
   tradedS2=false;
}
//+------------------------------------------------------------------+
void CheckTouch(double bid,double ask)
{
   if(PositionSelect(_Symbol)) return; // hanya 1 posisi aktif

   double tolerance = _Point * 10;

   if(!tradedR1 && MathAbs(bid - r1) <= tolerance)
   {
      Sell();
      tradedR1=true;
   }

   if(!tradedR2 && MathAbs(bid - r2) <= tolerance)
   {
      Sell();
      tradedR2=true;
   }

   if(!tradedS1 && MathAbs(ask - s1) <= tolerance)
   {
      Buy();
      tradedS1=true;
   }

   if(!tradedS2 && MathAbs(ask - s2) <= tolerance)
   {
      Buy();
      tradedS2=true;
   }

   if(TradePP && !tradedPP && MathAbs(bid - pp) <= tolerance)
   {
      Sell(); // default: mean reversion
      tradedPP=true;
   }
}
//+------------------------------------------------------------------+
void Buy()
{
   double sl = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID) - StopLossPoints*_Point,_Digits);
   double tp = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID) + TakeProfitPoints*_Point,_Digits);

   SendOrder(ORDER_TYPE_BUY,LotSize,SymbolInfoDouble(_Symbol,SYMBOL_BID),sl,tp);
}
//+------------------------------------------------------------------+
void Sell()
{
   double sl = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK) + StopLossPoints*_Point,_Digits);
   double tp = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK) - TakeProfitPoints*_Point,_Digits);

   SendOrder(ORDER_TYPE_SELL,LotSize,SymbolInfoDouble(_Symbol,SYMBOL_ASK),sl,tp);
}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double lot,double price,double sl,double tp)
{
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

if(type == ORDER_TYPE_BUY)
{
   if((price - sl) < stopLevel || (tp - price) < stopLevel)
   {
      Print("SL/TP too close for BUY");
      return;
   }
}
else if(type == ORDER_TYPE_SELL)
{
   if((sl - price) < stopLevel || (price - tp) < stopLevel)
   {
      Print("SL/TP too close for SELL");
      return;
   }
}
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = lot;
   req.price    = price;
   req.sl       = sl;
   req.tp       = tp;
   req.magic    = 123;

   req.comment  = "|SL=" + DoubleToString(sl,_Digits);

   req.deviation= 10;

   OrderSend(req,res);
}