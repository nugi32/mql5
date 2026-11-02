//+------------------------------------------------------------------+
//| EA_02_Short_SessH_Vol_Mom5_H19.mq5
//| Strategy : #2 Short - #1 + mom_10 > -5
//| Direction: SHORT only | Exit: close after 19 candles (no SL/TP)
//|
//| ---- Edge report (EURUSD M30, source: edge research report) ----
//| Edge ID            : EURUSD_M30_117
//| Condition          : ps_dist_sess_h_atr < -1.0 AND volregime_atr_ratio < 1.0 AND mom_10 > -5.0
//| Frequency          : 245.1 signals / year
//| Prob(bull) @h1     : 45.97% (baseline 49.95%) -> bearish edge
//| Effect size        : -0.0382   | p_adj: 1.8094e-05
//| Walk-forward       : consistent = True, positive mean R in 24/34 windows
//| Hold 19 bars        : mean R = +0.2709 (n=1046), std R = 4.0539
//| Net expectancy     : 1.27 pips / 0.11 R per trade
//|
//| ---- Backtest summary (user supplied) ----
//| Trades 1046 | Net profit 2,656.90 | PF 1.24 | Win % 53.5 | Max equity DD 800.00 (6.6%)
//| Signals skipped while busy: 2876 | Open at end: 0
//|
//| Logic (same as DataExporter): features read from the CLOSED bar
//| (shift 1) on every new bar; entry at open of the new bar.
//| One position at a time (signals while busy are skipped).
//| No custom indicators / no external includes: everything is computed
//| inline from built-in indicators and price data.
//+------------------------------------------------------------------+
#property copyright "Generated EA"
#property version   "1.00"
#property strict

//--- trade inputs
input double InpLots      = 0.10;     // Fixed lot size
input long   InpMagic     = 260102;   // Magic number
input int    InpHoldBars  = 19;       // Close after N candles
input int    InpDeviation = 20;       // Max slippage (points)
input string InpComment   = "EA02_SessH_Vol_Mom5_H19"; // Order comment

//--- signal thresholds (from report)
input double InpPsDistThr  = -1.0;  // ps_dist_sess_h_atr < thr
input double InpVolRatioThr = 1.0;  // volregime_atr_ratio < thr
input double InpMomThr     = -5.0;  // mom_10 > thr (iMomentum ~100 scale)
//--- feature calculation settings
input int    InpATRPeriod       = 14;   // ATR period (ATR used for distance / ratio)
input int    InpATRMAPeriod     = 50;   // SMA period applied on ATR for volregime_atr_ratio
input int    InpSessionHours    = 8;    // Session length in hours (server time)
input int    InpSessionOffsetHour = 0;  // Session grid offset (server hour)

//--- handles
int g_ma = INVALID_HANDLE, g_rsi = INVALID_HANDLE, g_mom = INVALID_HANDLE, g_atr = INVALID_HANDLE;
datetime g_last_bar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpHoldBars < 1) { Print("InpHoldBars must be >= 1"); return INIT_PARAMETERS_INCORRECT; }
   g_atr = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atr == INVALID_HANDLE) return INIT_FAILED;
   g_mom = iMomentum(_Symbol, _Period, 10, PRICE_CLOSE);
   if(g_mom == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_ma  != INVALID_HANDLE) IndicatorRelease(g_ma);
   if(g_rsi != INVALID_HANDLE) IndicatorRelease(g_rsi);
   if(g_mom != INVALID_HANDLE) IndicatorRelease(g_mom);
   if(g_atr != INVALID_HANDLE) IndicatorRelease(g_atr);
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool GetBuf(const int handle, const int buffer, const int shift, double &value)
{
   if(handle == INVALID_HANDLE) return false;
   double a[1];
   if(CopyBuffer(handle, buffer, shift, 1, a) != 1) return false;
   value = a[0];
   return (MathIsValidNumber(value) && value != EMPTY_VALUE);
}

//--- volregime_atr_ratio = ATR(shift1) / SMA(ATR, N) at shift 1
bool CalcAtrRatio(double &ratio)
{
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(g_atr, 0, 1, InpATRMAPeriod, a) != InpATRMAPeriod) return false;
   double sum = 0.0;
   for(int i = 0; i < InpATRMAPeriod; i++)
   {
      if(!MathIsValidNumber(a[i])) return false;
      sum += a[i];
   }
   double ma = sum / InpATRMAPeriod;
   if(ma <= 0.0) return false;
   ratio = a[0] / ma;
   return true;
}

//--- session id (fixed blocks of InpSessionHours, shifted by InpSessionOffsetHour, server time)
long SessId(const datetime t)
{
   return (long)MathFloor(((double)t - InpSessionOffsetHour * 3600.0) / (InpSessionHours * 3600.0));
}

//--- ps_dist_sess_h_atr = (previous session HIGH - close[1]) / ATR[1]
//--- negative value = price is ABOVE the previous session high
bool CalcDistSessH(const double atr, double &dist)
{
   int per = PeriodSeconds(_Period);
   if(per <= 0 || atr <= 0.0) return false;
   int need = (InpSessionHours * 3600 / per) * 4 + 20;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, _Period, 1, need, r);   // r[0] = closed bar (shift 1)
   if(n < 3) return false;

   long   cur  = SessId(r[0].time);
   bool   have = false;
   long   prev = 0;
   double hh   = -DBL_MAX;

   for(int i = 0; i < n; i++)
   {
      long s = SessId(r[i].time);
      if(s == cur) continue;
      if(!have) { prev = s; have = true; }
      if(s != prev) break;
      if(r[i].high > hh) hh = r[i].high;
   }
   if(!have) return false;

   dist = (hh - r[0].close) / atr;
   return true;
}


//+------------------------------------------------------------------+
//| Entry signal (all values from closed bar, shift 1)               |
//+------------------------------------------------------------------+
bool ShortSignal()
{
   double v = 0.0;
   double atr = 0.0;
   if(!GetBuf(g_atr, 0, 1, atr)) return false;
   double dist = 0.0;
   if(!CalcDistSessH(atr, dist)) return false;
   if(!(dist < InpPsDistThr)) return false;
   double ratio = 0.0;
   if(!CalcAtrRatio(ratio)) return false;
   if(!(ratio < InpVolRatioThr)) return false;
   if(!GetBuf(g_mom, 0, 1, v)) return false;
   if(!(v > InpMomThr)) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Position handling                                                |
//+------------------------------------------------------------------+
bool FindPosition(ulong &ticket, datetime &open_time, double &volume)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket    = t;
      open_time = (datetime)PositionGetInteger(POSITION_TIME);
      volume    = PositionGetDouble(POSITION_VOLUME);
      return true;
   }
   return false;
}

ENUM_ORDER_TYPE_FILLING GetFilling()
{
   int f = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((f & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((f & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

double NormalizeLots(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step > 0) lots = MathFloor(lots / step + 1e-9) * step;
   lots = MathMax(vmin, MathMin(vmax, lots));
   return NormalizeDouble(lots, 2);
}

bool SendDeal(const ENUM_ORDER_TYPE type, const double volume, const ulong position_ticket)
{
   MqlTradeRequest rq;
   MqlTradeResult  rs;
   ZeroMemory(rq);
   ZeroMemory(rs);

   rq.action       = TRADE_ACTION_DEAL;
   rq.symbol       = _Symbol;
   rq.volume       = volume;
   rq.type         = type;
   rq.price        = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   rq.deviation    = InpDeviation;
   rq.magic        = InpMagic;
   rq.comment      = InpComment;
   rq.type_filling = GetFilling();
   if(position_ticket != 0) rq.position = position_ticket;

   if(!OrderSend(rq, rs))
   {
      Print("OrderSend failed. retcode=", rs.retcode, " err=", GetLastError());
      return false;
   }
   if(rs.retcode != TRADE_RETCODE_DONE && rs.retcode != TRADE_RETCODE_PLACED)
   {
      Print("Deal rejected. retcode=", rs.retcode, " ", rs.comment);
      return false;
   }
   return true;
}

//--- close after InpHoldBars candles
void ManageExit()
{
   ulong ticket; datetime opened; double vol;
   if(!FindPosition(ticket, opened, vol)) return;

   int held = iBarShift(_Symbol, _Period, opened, false);   // 0 = entry bar
   if(held >= InpHoldBars)
   {
      if(SendDeal(ORDER_TYPE_BUY, vol, ticket))   // BUY closes the SHORT
         Print("Closed SHORT after ", held, " candles. ticket=", ticket);
   }
}

void TryEntry()
{
   ulong ticket; datetime opened; double vol;
   if(FindPosition(ticket, opened, vol)) return;   // busy -> skip signal

   if(!ShortSignal()) return;

   if(SendDeal(ORDER_TYPE_SELL, NormalizeLots(InpLots), 0))
      Print("Opened SHORT (EURUSD_M30_117), hold=", InpHoldBars, " candles");
}

//+------------------------------------------------------------------+
//| Everything is processed once per new bar                         |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt == 0 || bt == g_last_bar) return;
   g_last_bar = bt;

   ManageExit();   // 1) close if hold reached
   TryEntry();     // 2) then look for a new signal (if flat)
}
//+------------------------------------------------------------------+
