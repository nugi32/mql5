//+------------------------------------------------------------------+
//| EA_04_Short_RSI75_EMA5_Vol_H14.mq5
//| Strategy : #4 Short - RSI7>75 + close>EMA5 + low vol
//| Direction: SHORT only | Exit: close after 14 candles (no SL/TP)
//|
//| ---- Edge report (EURUSD M30, source: edge research report) ----
//| Edge ID            : EURUSD_M30_96
//| Condition          : rsi_7 > 75.0 AND ma_5_ema < close AND volregime_atr_ratio < 1.0
//| Frequency          : 257.1 signals / year
//| Prob(bull) @h1     : 42.72% (baseline 49.95%) -> bearish edge
//| Effect size        : -0.0707   | p_adj: 0.0000e+00
//| Walk-forward       : consistent = True, positive mean R in 24/34 windows
//| Hold 14 bars        : mean R = +0.2167 (n=1538), std R = 4.1493
//| Net expectancy     : 1.88 pips / 0.16 R per trade
//|
//| ---- Backtest summary (user supplied) ----
//| Trades 1538 | Net profit 2,746.20 | PF 1.16 | Win % 54.1 | Max equity DD 957.60 (9.2%)
//| Signals skipped while busy: 2575 | Open at end: 0
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
input long   InpMagic     = 260104;   // Magic number
input int    InpHoldBars  = 14;       // Close after N candles
input int    InpDeviation = 20;       // Max slippage (points)
input string InpComment   = "EA04_RSI75_EMA5_Vol_H14"; // Order comment

//--- signal thresholds (from report)
input double InpRsiThr     = 75.0;  // rsi_7 > thr
input double InpVolRatioThr = 1.0;  // volregime_atr_ratio < thr
//--- feature calculation settings
input int    InpATRPeriod       = 14;   // ATR period (ATR used for distance / ratio)
input int    InpATRMAPeriod     = 50;   // SMA period applied on ATR for volregime_atr_ratio

//--- handles
int g_ma = INVALID_HANDLE, g_rsi = INVALID_HANDLE, g_mom = INVALID_HANDLE, g_atr = INVALID_HANDLE;
datetime g_last_bar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpHoldBars < 1) { Print("InpHoldBars must be >= 1"); return INIT_PARAMETERS_INCORRECT; }
   g_atr = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atr == INVALID_HANDLE) return INIT_FAILED;
   g_ma = iMA(_Symbol, _Period, 5, 0, MODE_EMA, PRICE_CLOSE);
   if(g_ma == INVALID_HANDLE) return INIT_FAILED;
   g_rsi = iRSI(_Symbol, _Period, 7, PRICE_CLOSE);
   if(g_rsi == INVALID_HANDLE) return INIT_FAILED;
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


//+------------------------------------------------------------------+
//| Entry signal (all values from closed bar, shift 1)               |
//+------------------------------------------------------------------+
bool ShortSignal()
{
   double v = 0.0;
   double atr = 0.0;
   if(!GetBuf(g_atr, 0, 1, atr)) return false;
   if(!GetBuf(g_rsi, 0, 1, v)) return false;
   if(!(v > InpRsiThr)) return false;
   double ema5 = 0.0;
   if(!GetBuf(g_ma, 0, 1, ema5)) return false;
   double cl = iClose(_Symbol, _Period, 1);
   if(!(ema5 < cl)) return false;                     // ma_5_ema < close
   double ratio = 0.0;
   if(!CalcAtrRatio(ratio)) return false;
   if(!(ratio < InpVolRatioThr)) return false;
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
      Print("Opened SHORT (EURUSD_M30_96), hold=", InpHoldBars, " candles");
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
