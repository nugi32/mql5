//+------------------------------------------------------------------+
//|                    GridMartingale_EA.mq5                         |
//|         Grid Martingale EA — RSI Reversal + EMA Trend Edge       |
//|                        v2.1 — Fixed MTF + Virtual SL             |
//+------------------------------------------------------------------+
#property copyright   "GridMartingale EA"
#property link        "https://www.mql5.com"
#property version     "2.10"
#property description "Grid Martingale | RSI+EMA+ATR+BB | Fixed MTF | Virtual SL"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Groups
input group "════════ TIMEFRAME ════════"
input ENUM_TIMEFRAMES InpMainTF       = PERIOD_M15;  // Main Timeframe
input ENUM_TIMEFRAMES InpHTFTF        = PERIOD_H1;   // Higher Timeframe (trend bias)
input bool            InpUseHTF       = true;         // Use Higher TF Trend Filter

input group "════════ GRID SETTINGS ════════"
input double   InpInitialLot      = 0.01;   // Initial Lot Size
input double   InpLotMultiplier   = 1.8;    // Lot Multiplier (per grid level)
input int      InpMaxOrders       = 6;      // Max Grid Orders
input double   InpGridStep        = 30.0;   // Grid Step (pips)
input double   InpTakeProfit      = 20.0;   // Take Profit from avg price (pips)
input bool     InpATRGrid         = true;   // ATR-Adaptive Grid Step

input group "════════ RISK MANAGEMENT ════════"
input double   InpMaxDrawdownPct  = 20.0;   // Max Drawdown % (close all)
input bool     InpUseEquityStop   = true;   // Enable Equity Floor Stop
input double   InpEquityStopPct   = 30.0;   // Equity Stop % below initial balance
input double   InpVirtualSLPips   = 50.0;   // Virtual Stop Loss (pips)

input group "════════ SIGNAL SETTINGS ════════"
input int      InpRSIPeriod       = 14;     // RSI Period
input double   InpRSIOversold     = 32.0;   // RSI Oversold Level
input double   InpRSIOverbought   = 68.0;   // RSI Overbought Level
input int      InpFastEMA         = 21;     // Fast EMA Period
input int      InpSlowEMA         = 50;     // Slow EMA Period
input int      InpHTFEMAPeriod    = 200;    // HTF EMA Period
input int      InpATRPeriod       = 14;     // ATR Period
input double   InpATRMinPips      = 3.0;    // Min ATR (pips) to allow entry
input int      InpBBPeriod        = 20;     // Bollinger Band Period
input double   InpBBDeviation     = 2.0;    // BB Standard Deviation
input bool     InpBBFilter        = true;   // Bollinger Squeeze Filter

input group "════════ SESSION FILTER ════════"
input bool     InpSessionFilter   = false;  // Enable Session Filter
input int      InpSessionStart    = 7;      // Session Start Hour (server)
input int      InpSessionEnd      = 20;     // Session End Hour (server)

input group "════════ EA SETTINGS ════════"
input int      InpMagicNumber     = 20240101; // Magic Number
input int      InpSlippage        = 20;       // Max Slippage (points)
input bool     InpShowDashboard   = true;     // Show On-Chart Dashboard

//--- Objects
CTrade         trade;
CPositionInfo  posInfo;

//--- Indicator handles
int   hRSI, hFastEMA, hSlowEMA, hATR, hBB, hHTFEMA;

//--- Buffers
double bRSI[], bFastEMA[], bSlowEMA[], bATR[];
double bBBUp[], bBBLo[], bBBMid[];
double bHTFEMA[];

//--- State
datetime  lastBarTime    = 0;
double    initialBalance = 0;
int       totalTrades    = 0;
int       wonTrades      = 0;
double    totalProfit    = 0.0;
string    LBL            = "GM_";

//--- Virtual SL structure
struct VirtualSL {
   ulong ticket;
   double sl;
   double tp;
};
VirtualSL vsl[];

//+------------------------------------------------------------------+
//| Pre-load history to avoid Error 4805 in tester                  |
//+------------------------------------------------------------------+
void PreloadHistory(ENUM_TIMEFRAMES tf)
{
   datetime t[];
   int attempts = 0;
   while(!IsStopped() && attempts < 200)
   {
      if(CopyTime(_Symbol, tf, 0, 10, t) > 0) break;
      Sleep(10);
      attempts++;
   }
   if(attempts >= 200)
      PrintFormat("⚠️  History preload timeout for %s", EnumToString(tf));
   else
      PrintFormat("✔  History loaded: %s %s", _Symbol, EnumToString(tf));
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- Force history load BEFORE creating handles
   PreloadHistory(InpMainTF);
   if(InpUseHTF) PreloadHistory(InpHTFTF);

   //--- Create handles on the chosen main timeframe
   hRSI     = iRSI  (_Symbol, InpMainTF, InpRSIPeriod,   PRICE_CLOSE);
   hFastEMA = iMA   (_Symbol, InpMainTF, InpFastEMA, 0,  MODE_EMA, PRICE_CLOSE);
   hSlowEMA = iMA   (_Symbol, InpMainTF, InpSlowEMA, 0,  MODE_EMA, PRICE_CLOSE);
   hATR     = iATR  (_Symbol, InpMainTF, InpATRPeriod);
   hBB      = iBands(_Symbol, InpMainTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);

   if(hRSI     == INVALID_HANDLE || hFastEMA == INVALID_HANDLE ||
      hSlowEMA == INVALID_HANDLE || hATR     == INVALID_HANDLE || hBB == INVALID_HANDLE)
   {
      PrintFormat("❌ Main indicator creation failed. Error: %d", GetLastError());
      return INIT_FAILED;
   }

   //--- HTF EMA — optional, non-fatal if unavailable
   hHTFEMA = INVALID_HANDLE;
   if(InpUseHTF)
   {
      hHTFEMA = iMA(_Symbol, InpHTFTF, InpHTFEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hHTFEMA == INVALID_HANDLE)
         PrintFormat("⚠️  HTF EMA unavailable (Err:%d) — HTF filter disabled.", GetLastError());
   }

   //--- Set all buffers as time-series
   ArraySetAsSeries(bRSI,     true);
   ArraySetAsSeries(bFastEMA, true);
   ArraySetAsSeries(bSlowEMA, true);
   ArraySetAsSeries(bATR,     true);
   ArraySetAsSeries(bBBUp,    true);
   ArraySetAsSeries(bBBLo,    true);
   ArraySetAsSeries(bBBMid,   true);
   ArraySetAsSeries(bHTFEMA,  true);

   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   ArrayResize(vsl, 0);

   if(InpShowDashboard) CreateDashboard();

   PrintFormat("✅ GridMartingale EA v2.1 | %s %s | Magic:%d | HTF:%s",
               _Symbol, EnumToString(InpMainTF), InpMagicNumber,
               (hHTFEMA != INVALID_HANDLE ? EnumToString(InpHTFTF) : "OFF"));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hRSI     != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hFastEMA != INVALID_HANDLE) IndicatorRelease(hFastEMA);
   if(hSlowEMA != INVALID_HANDLE) IndicatorRelease(hSlowEMA);
   if(hATR     != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hBB      != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hHTFEMA  != INVALID_HANDLE) IndicatorRelease(hHTFEMA);
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!LoadBuffers()) return;

   //--- Equity floor stop
   if(InpUseEquityStop &&
      AccountInfoDouble(ACCOUNT_EQUITY) < initialBalance * (1.0 - InpEquityStopPct / 100.0))
   {
      CloseAll("EQUITY STOP");
      if(InpShowDashboard) UpdateDashboard();
      return;
   }

   //--- Drawdown stop
   if(GetDrawdown() >= InpMaxDrawdownPct)
   {
      CloseAll("MAX DD STOP");
      if(InpShowDashboard) UpdateDashboard();
      return;
   }

   //--- Check virtual stops every tick
   CheckVirtualStops();

   //--- Grid management every tick
   ManageGrid();

   //--- New bar logic
   datetime barTime = iTime(_Symbol, InpMainTF, 0);
   if(barTime == lastBarTime)
   {
      if(InpShowDashboard) UpdateDashboard();
      return;
   }
   lastBarTime = barTime;

   if(InpSessionFilter && !IsInSession()) return;

   int b = 0, s = 0;
   CountPos(b, s);
   if(b == 0 && s == 0) CheckSignal();

   if(InpShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Load indicator buffers safely                                    |
//+------------------------------------------------------------------+
bool LoadBuffers()
{
   if(CopyBuffer(hRSI,     0, 0, 4, bRSI)     < 4) return false;
   if(CopyBuffer(hFastEMA, 0, 0, 4, bFastEMA) < 4) return false;
   if(CopyBuffer(hSlowEMA, 0, 0, 4, bSlowEMA) < 4) return false;
   if(CopyBuffer(hATR,     0, 0, 4, bATR)     < 4) return false;
   if(CopyBuffer(hBB,      1, 0, 4, bBBUp)    < 4) return false;
   if(CopyBuffer(hBB,      2, 0, 4, bBBLo)    < 4) return false;
   if(CopyBuffer(hBB,      0, 0, 4, bBBMid)   < 4) return false;

   if(hHTFEMA != INVALID_HANDLE)
   {
      if(CopyBuffer(hHTFEMA, 0, 0, 2, bHTFEMA) < 2)
      {
         // Soft failure — fill with zeros so HTF check is bypassed
         ArrayResize(bHTFEMA, 2);
         bHTFEMA[0] = 0;
         bHTFEMA[1] = 0;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Entry signal — 5-layer confirmation                              |
//|                                                                  |
//|  BUY : HTF bias bull + EMA uptrend + RSI cross from oversold     |
//|        + ATR > min + BB not squeezing                            |
//|  SELL: mirror                                                    |
//+------------------------------------------------------------------+
void CheckSignal()
{
   double pip     = PipSize();
   double atrPips = bATR[1] / pip;

   // [1] Volatility gate
   if(atrPips < InpATRMinPips) return;

   // [2] Bollinger Squeeze guard
   if(InpBBFilter && (bBBUp[1] - bBBLo[1]) < bATR[1] * 1.2) return;

   // [3] H1 macro trend (skip when HTF handle unavailable or zeroed)
   bool htfBull = true, htfBear = true;
   if(hHTFEMA != INVALID_HANDLE && bHTFEMA[1] > 0)
   {
      double htfClose = iClose(_Symbol, InpHTFTF, 1);
      htfBull = htfClose > bHTFEMA[1];
      htfBear = htfClose < bHTFEMA[1];
   }

   // [4] M-TF EMA trend + slope
   bool emaBull    = bFastEMA[1] > bSlowEMA[1];
   bool emaBear    = bFastEMA[1] < bSlowEMA[1];
   bool emaRising  = bFastEMA[1] > bFastEMA[2];
   bool emaFalling = bFastEMA[1] < bFastEMA[2];

   // [5] RSI confirmed crossover from extreme (uses bar[2] → bar[1])
   bool rsiBull = bRSI[2] < InpRSIOversold   && bRSI[1] >= InpRSIOversold;
   bool rsiBear = bRSI[2] > InpRSIOverbought && bRSI[1] <= InpRSIOverbought;

   // [6] Price side of BB midline
   double c1    = iClose(_Symbol, InpMainTF, 1);
   bool   below = c1 < bBBMid[1];
   bool   above = c1 > bBBMid[1];

   if(htfBull && emaBull && emaRising  && rsiBull && below)
      OpenGridOrder(ORDER_TYPE_BUY,  InpInitialLot, 1);
   else if(htfBear && emaBear && emaFalling && rsiBear && above)
      OpenGridOrder(ORDER_TYPE_SELL, InpInitialLot, 1);
}

//+------------------------------------------------------------------+
//| Grid management — runs every tick                                |
//+------------------------------------------------------------------+
void ManageGrid()
{
   int b = 0, s = 0;
   CountPos(b, s);
   if(b + s == 0) return;

   double pip  = PipSize();
   double step = (InpATRGrid
                  ? MathMax(InpGridStep, bATR[1] / pip * 0.8)
                  : InpGridStep) * pip;
   double tp   = InpTakeProfit * pip;

   ENUM_POSITION_TYPE dir = (b > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   int    cnt  = (b > 0) ? b : s;
   double avg  = AvgPrice(dir);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(dir == POSITION_TYPE_BUY)
   {
      // Check for TP hit (virtual)
      if(bid >= avg + tp)               { CloseAll("TP HIT"); wonTrades++; return; }
      double lo = ExtremePrice(dir, false);
      if(cnt < InpMaxOrders && bid <= lo - step)
         OpenGridOrder(ORDER_TYPE_BUY, NormLot(InpInitialLot * MathPow(InpLotMultiplier, cnt)), cnt + 1);
   }
   else
   {
      // Check for TP hit (virtual)
      if(ask <= avg - tp)               { CloseAll("TP HIT"); wonTrades++; return; }
      double hi = ExtremePrice(dir, true);
      if(cnt < InpMaxOrders && ask >= hi + step)
         OpenGridOrder(ORDER_TYPE_SELL, NormLot(InpInitialLot * MathPow(InpLotMultiplier, cnt)), cnt + 1);
   }
}

//+------------------------------------------------------------------+
//| Open a grid position                                             |
//+------------------------------------------------------------------+
bool OpenGridOrder(ENUM_ORDER_TYPE type, double lots, int level)
{
   double price = (type == ORDER_TYPE_BUY)
                ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool ok = trade.PositionOpen(_Symbol, type, lots, price, 0, 0,
             StringFormat("GM|%s|L%d", (type == ORDER_TYPE_BUY ? "B" : "S"), level));
   if(ok)
   {
      totalTrades++;
      PrintFormat("📊 %s L%d | %.2f lots @ %.*f",
                  (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), level, lots, _Digits, price);

      // Add virtual SL/TP
      ulong ticket = trade.ResultRetcode() == TRADE_RETCODE_DONE ? trade.ResultOrder() : 0;
      if(ticket > 0)
      {
         double pip = PipSize();
         double vsl_price = (type == ORDER_TYPE_BUY)
                           ? price - InpVirtualSLPips * pip
                           : price + InpVirtualSLPips * pip;
         double vtp_price = (type == ORDER_TYPE_BUY)
                           ? price + InpTakeProfit * pip
                           : price - InpTakeProfit * pip;
         AddVirtualSL(ticket, vsl_price, vtp_price);
      }
   }
   else
      PrintFormat("❌ OpenOrder Err:%d lots:%.2f", GetLastError(), lots);
   return ok;
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAll(string reason)
{
   double pnl = FloatPnL();
   totalProfit += pnl;
   PrintFormat("🔒 %s | PnL: %+.2f", reason, pnl);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
            trade.PositionClose(posInfo.Ticket(), InpSlippage);

   // Clear virtual SL array
   ArrayResize(vsl, 0);
}

//+------------------------------------------------------------------+
//| Virtual SL Functions                                             |
//+------------------------------------------------------------------+
void AddVirtualSL(ulong ticket, double sl, double tp)
{
   int size = ArraySize(vsl);
   ArrayResize(vsl, size + 1);
   vsl[size].ticket = ticket;
   vsl[size].sl = NormalizeDouble(sl, _Digits);
   vsl[size].tp = NormalizeDouble(tp, _Digits);
}

void CheckVirtualStops()
{
   for(int i = ArraySize(vsl) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vsl[i].ticket))
      {
         ArrayRemove(vsl, i, 1);
         continue;
      }

      long type = PositionGetInteger(POSITION_TYPE);
      double price = (type == POSITION_TYPE_BUY)
                    ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                    : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool closeNow = false;
      string reason = "";

      // Check SL
      if((type == POSITION_TYPE_BUY && price <= vsl[i].sl) ||
         (type == POSITION_TYPE_SELL && price >= vsl[i].sl))
      {
         closeNow = true;
         reason = "VIRTUAL SL";
      }
      // Check TP
      else if((type == POSITION_TYPE_BUY && price >= vsl[i].tp) ||
              (type == POSITION_TYPE_SELL && price <= vsl[i].tp))
      {
         closeNow = true;
         reason = "VIRTUAL TP";
         wonTrades++;
      }

      if(closeNow)
      {
         trade.PositionClose(vsl[i].ticket, InpSlippage);
         PrintFormat("🔒 %s HIT | Ticket: %d", reason, vsl[i].ticket);
         ArrayRemove(vsl, i, 1);
      }
   }
}

//--- Helpers -----------------------------------------------------------
void CountPos(int &b, int &s)
{
   b = 0; s = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            if(posInfo.PositionType() == POSITION_TYPE_BUY)  b++;
            if(posInfo.PositionType() == POSITION_TYPE_SELL) s++;
         }
}

double AvgPrice(ENUM_POSITION_TYPE t)
{
   double v = 0, c = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber
            && posInfo.PositionType() == t)
         { v += posInfo.Volume(); c += posInfo.PriceOpen() * posInfo.Volume(); }
   return (v > 0) ? c / v : 0;
}

double ExtremePrice(ENUM_POSITION_TYPE t, bool highest)
{
   double e = highest ? 0.0 : DBL_MAX;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber
            && posInfo.PositionType() == t)
         {
            double p = posInfo.PriceOpen();
            if(highest && p > e)  e = p;
            if(!highest && p < e) e = p;
         }
   return (e == DBL_MAX || e == 0.0) ? 0 : e;
}

double TotalLots(ENUM_POSITION_TYPE t)
{
   double v = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber
            && posInfo.PositionType() == t) v += posInfo.Volume();
   return v;
}

double FloatPnL()
{
   double p = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
            p += posInfo.Profit() + posInfo.Swap();
   return p;
}

double GetDrawdown()
{
   double b = AccountInfoDouble(ACCOUNT_BALANCE);
   double e = AccountInfoDouble(ACCOUNT_EQUITY);
   return (b > 0) ? MathMax(0.0, (b - e) / b * 100.0) : 0;
}

double PipSize()
{
   double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    dig = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (dig == 3 || dig == 5) ? pt * 10.0 : pt;
}

double NormLot(double lot)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathMax(mn, MathMin(mx, MathRound(lot / st) * st));
}

bool IsInSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   ObjectCreate(0, LBL+"bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_XDISTANCE,   8);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_YDISTANCE,   8);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_XSIZE,       232);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_YSIZE,       305);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_BGCOLOR,     C'12,18,28');
   ObjectSetInteger(0, LBL+"bg", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_COLOR,       C'35,55,80');
   ObjectSetInteger(0, LBL+"bg", OBJPROP_BACK,        false);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, LBL+"bg", OBJPROP_ZORDER,      0);

   for(int i = 0; i <= 16; i++) MkLabel(LBL+"r"+IntegerToString(i), 16, 16+i*18, clrSilver);
   UpdateDashboard();
}

void MkLabel(string n, int x, int y, color c)
{
   ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   8);
   ObjectSetString (0, n, OBJPROP_FONT,       "Consolas");
   ObjectSetInteger(0, n, OBJPROP_COLOR,      c);
   ObjectSetString (0, n, OBJPROP_TEXT,       "");
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     1);
}

void Lbl(string n, string txt, color c = CLR_NONE)
{
   if(ObjectFind(0, n) < 0) return;
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   if(c != CLR_NONE) ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}

void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   int b = 0, s = 0;
   CountPos(b, s);
   int    cnt  = b + s;
   double pnl  = FloatPnL();
   double dd   = GetDrawdown();
   double atrP = (ArraySize(bATR) > 1) ? bATR[1] / PipSize() : 0;
   double rsi  = (ArraySize(bRSI) > 1) ? bRSI[1] : 0;

   string dirTxt = "   —  FLAT"; color dirC = clrSilver;
   ENUM_POSITION_TYPE atype = POSITION_TYPE_BUY;
   if(b > 0) { dirTxt = "▲  LONG  GRID"; dirC = clrLimeGreen;  atype = POSITION_TYPE_BUY;  }
   if(s > 0) { dirTxt = "▼  SHORT GRID"; dirC = clrTomato;     atype = POSITION_TYPE_SELL; }

   double avg  = (cnt > 0) ? AvgPrice(atype) : 0;
   double lots = (cnt > 0) ? TotalLots(atype) : 0;

   string trendTxt = "—"; color trendC = clrSilver;
   if(ArraySize(bFastEMA) > 1 && ArraySize(bSlowEMA) > 1)
   {
      if(bFastEMA[1] > bSlowEMA[1]) { trendTxt = "▲ Bullish"; trendC = clrLimeGreen; }
      else                           { trendTxt = "▼ Bearish"; trendC = clrTomato; }
   }

   double win  = (totalTrades > 0) ? 100.0 * wonTrades / totalTrades : 0;
   color  pnlC = pnl >= 0 ? clrLimeGreen : clrTomato;
   color  ddC  = dd < 5 ? clrLimeGreen : (dd < 12 ? clrGold : clrTomato);

   Lbl(LBL+"r0",  "⬡  GRID MARTINGALE v2.1",        clrDodgerBlue);
   Lbl(LBL+"r1",  "──────────────────────────",      C'35,55,80');
   Lbl(LBL+"r2",  "Symbol : "+_Symbol+" "+EnumToString(InpMainTF));
   Lbl(LBL+"r3",  "Grid   : "+dirTxt,                dirC);
   Lbl(LBL+"r4",  StringFormat("Orders : %d/%d  lots:%.2f", cnt, InpMaxOrders, lots));
   Lbl(LBL+"r5",  avg > 0 ? StringFormat("Avg Px : %.*f", _Digits, avg) : "Avg Px : —");
   Lbl(LBL+"r6",  StringFormat("Float  : %+.2f %s", pnl, AccountInfoString(ACCOUNT_CURRENCY)), pnlC);
   Lbl(LBL+"r7",  StringFormat("Drawdn : %.2f%%  (lim %.0f%%)", dd, InpMaxDrawdownPct), ddC);
   Lbl(LBL+"r8",  "──────────────────────────",      C'35,55,80');
   Lbl(LBL+"r9",  StringFormat("RSI 14 : %.1f  [%.0f / %.0f]", rsi, InpRSIOversold, InpRSIOverbought));
   Lbl(LBL+"r10", StringFormat("ATR    : %.1f pips  (min %.0f)", atrP, InpATRMinPips));
   Lbl(LBL+"r11", "Trend  : "+trendTxt+(hHTFEMA!=INVALID_HANDLE?" + HTF":""), trendC);
   Lbl(LBL+"r12", "──────────────────────────",      C'35,55,80');
   Lbl(LBL+"r13", StringFormat("Cycles : %d  (W:%d  L:%d)", totalTrades, wonTrades, totalTrades-wonTrades));
   Lbl(LBL+"r14", StringFormat("Win %%  : %.1f%%   PnL:%+.2f", win, totalProfit),
                  win >= 50 ? clrLimeGreen : clrTomato);
   Lbl(LBL+"r15", "──────────────────────────",      C'35,55,80');
   Lbl(LBL+"r16", "Time   : "+TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), clrGray);
   ChartRedraw(0);
}

void DeleteDashboard()
{
   ObjectDelete(0, LBL+"bg");
   for(int i = 0; i <= 16; i++) ObjectDelete(0, LBL+"r"+IntegerToString(i));
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC)  == InpMagicNumber &&
         HistoryDealGetString (trans.deal, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(trans.deal, DEAL_ENTRY)  == DEAL_ENTRY_OUT)
         PrintFormat("💰 Deal | %+.2f", HistoryDealGetDouble(trans.deal, DEAL_PROFIT));
}
//+------------------------------------------------------------------+
