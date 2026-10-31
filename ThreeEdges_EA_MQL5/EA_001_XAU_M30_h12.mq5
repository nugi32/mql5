//+------------------------------------------------------------------+
//| EA_001_XAU_M30_h12.mq5
//| Strategi 001 - LONG XAUUSD M30  (report edge: XAUUSD_M30_14)
//|
//| Entry (dicek pada bar yang baru close = shift 1, sama dgn DataExporter):
//|   rsi_7 < 20 AND stoch_14_3_3_k < 20 AND ps_dist_sess_l_atr > 2.0
//| Exit : close setelah 12 candle (tanpa SL/TP broker)
//| Semua diproses sekali per bar baru. Tanpa #include / custom library.
//+------------------------------------------------------------------+
#property copyright "ThreeEdges"
#property version   "1.00"
#property strict

input group "=== Strategi 001 ==="
input long   InpMagic     = 1001;
input double InpLot       = 0.01;
input int    InpHoldBars  = 12;   // close setelah X candle

input group "=== Threshold (sesuai report) ==="
input double InpRsiMax    = 20.0;   // rsi_7 < nilai ini
input double InpStochMax  = 20.0;   // stoch_14_3_3_k < nilai ini
input double InpPsMin     = 2.0;    // ps_dist_sess_l_atr > nilai ini

input group "=== Kalibrasi indikator custom (cocokkan dgn CSV export!) ==="
input int    InpAtrPeriod       = 14;   // periode ATR
input int    InpSessionLenHours = 8;    // panjang 1 sesi (jam server), pembagi 24
input int    InpSessionOffsetH  = 0;    // geser awal sesi (jam server)
input int    InpSessionScanBars = 400;  // max bar mundur utk cari sesi sebelumnya

input group "=== Eksekusi ==="
input int    InpDeviation = 30;      // slippage (points)
input bool   InpDebugLog  = false;   // print nilai indikator tiap bar baru
input string InpComment   = "EA_001";

int h_rsi7  = INVALID_HANDLE;
int h_stoch = INVALID_HANDLE;
int h_atr   = INVALID_HANDLE;

datetime g_last_bar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M30)
      Print("WARNING: report dibuat untuk M30, chart sekarang ", EnumToString((ENUM_TIMEFRAMES)Period()));

   h_rsi7  = iRSI(_Symbol, _Period, 7, PRICE_CLOSE);
   h_stoch = iStochastic(_Symbol, _Period, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_atr   = iATR(_Symbol, _Period, InpAtrPeriod);

   if(h_rsi7 == INVALID_HANDLE || h_stoch == INVALID_HANDLE || h_atr == INVALID_HANDLE)
   {
      Print("ERROR: gagal membuat handle indikator");
      return INIT_FAILED;
   }
   if(InpSessionLenHours < 1 || InpSessionLenHours > 24 || (24 % InpSessionLenHours) != 0)
   {
      Print("ERROR: InpSessionLenHours harus pembagi 24 (1,2,3,4,6,8,12,24)");
      return INIT_PARAMETERS_INCORRECT;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_rsi7  != INVALID_HANDLE) IndicatorRelease(h_rsi7);
   if(h_stoch != INVALID_HANDLE) IndicatorRelease(h_stoch);
   if(h_atr   != INVALID_HANDLE) IndicatorRelease(h_atr);
}

//+------------------------------------------------------------------+
bool GetBuf(int handle, int buffer, int shift, double &val)
{
   double b[1];
   if(CopyBuffer(handle, buffer, shift, 1, b) != 1) return false;
   if(b[0] != b[0] || b[0] == EMPTY_VALUE) return false;
   val = b[0];
   return true;
}

//+------------------------------------------------------------------+
//| ID sesi dari waktu                                               |
//+------------------------------------------------------------------+
long SessionId(datetime t)
{
   long ts  = (long)t - (long)InpSessionOffsetH * 3600;
   long day = ts / 86400;
   long sec = ts - day * 86400;
   long blk = sec / ((long)InpSessionLenHours * 3600);
   return day * (24 / InpSessionLenHours) + blk;
}

//+------------------------------------------------------------------+
//| ps_dist_sess_l_atr = (low sesi sebelumnya - close) / ATR (bar 1) |
//+------------------------------------------------------------------+
bool CalcPsDistSessL(double &out)
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, _Period, 1, InpSessionScanBars, r); // r[0] = bar 1
   if(n < 10) return false;

   double atr;
   if(!GetBuf(h_atr, 0, 1, atr) || atr <= 0.0) return false;

   long cur_sid = SessionId(r[0].time);
   int i = 0;
   while(i < n && SessionId(r[i].time) == cur_sid) i++;   // lewati sesi berjalan
   if(i >= n) return false;

   long prev_sid = SessionId(r[i].time);
   double lo = r[i].low;
   while(i < n && SessionId(r[i].time) == prev_sid)
   {
      if(r[i].low < lo) lo = r[i].low;
      i++;
   }
   out = (lo - r[0].close) / atr;
   return true;
}

//+------------------------------------------------------------------+
bool FindPosition(ulong &ticket, datetime &open_time)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = tk;
      open_time = (datetime)PositionGetInteger(POSITION_TIME);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFilling()
{
   long f = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((f & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((f & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step > 0) lot = MathFloor(lot / step + 1e-8) * step;
   if(lot < mn) lot = mn;
   if(lot > mx) lot = mx;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
bool OpenBuy()
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = NormalizeLot(InpLot);
   req.type         = ORDER_TYPE_BUY;
   req.price        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.sl           = 0.0;      // tanpa SL broker
   req.tp           = 0.0;      // tanpa TP broker
   req.deviation    = InpDeviation;
   req.magic        = InpMagic;
   req.comment      = InpComment;
   req.type_filling = GetFilling();

   if(!OrderSend(req, res) ||
      (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      Print("BUY gagal. retcode=", res.retcode, " ", res.comment);
      return false;
   }
   Print("BUY dibuka. deal=", res.deal, " price=", DoubleToString(res.price, _Digits));
   return true;
}

//+------------------------------------------------------------------+
bool ClosePos(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = PositionGetDouble(POSITION_VOLUME);
   req.type         = ORDER_TYPE_SELL;
   req.price        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.position     = ticket;
   req.deviation    = InpDeviation;
   req.magic        = InpMagic;
   req.comment      = InpComment + "_exit";
   req.type_filling = GetFilling();

   if(!OrderSend(req, res) ||
      (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      Print("Close gagal. retcode=", res.retcode, " ", res.comment);
      return false;
   }
   Print("Posisi ditutup (exit setelah ", InpHoldBars, " candle). ticket=", ticket);
   return true;
}

//+------------------------------------------------------------------+
//| Tutup bila sudah >= InpHoldBars candle sejak bar entry           |
//+------------------------------------------------------------------+
void ManageExit()
{
   ulong tk; datetime ot;
   if(!FindPosition(tk, ot)) return;

   int shift = iBarShift(_Symbol, _Period, ot, false);   // 0 = bar tempat entry
   if(shift < 0) return;
   if(shift >= InpHoldBars)
      ClosePos(tk);
}

//+------------------------------------------------------------------+
//| Satu-satunya titik proses: dipanggil sekali per bar baru         |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   // 1) EXIT dulu
   ManageExit();

   // 2) Nilai indikator pada bar 1 (bar yang baru close)
   double rsi7, stoch_k;
   if(!GetBuf(h_rsi7,  0, 1, rsi7))    return;
   if(!GetBuf(h_stoch, 0, 1, stoch_k)) return;   // buffer 0 = %K (sama dgn exporter)
   double ps;
   if(!CalcPsDistSessL(ps)) return;

   if(InpDebugLog)
      Print("BAR ", TimeToString(iTime(_Symbol, _Period, 1), TIME_DATE | TIME_MINUTES),
            " rsi_7=", DoubleToString(rsi7, 2),
            " stoch_14_3_3_k=", DoubleToString(stoch_k, 2),
            " ps_dist_sess_l_atr=", DoubleToString(ps, 3));

   // 3) Sinyal entry
   bool signal = (rsi7 < InpRsiMax) && (stoch_k < InpStochMax) && (ps > InpPsMin);
   if(!signal) return;

   ulong tk; datetime ot;
   if(!FindPosition(tk, ot))     // maks 1 posisi per strategi
      OpenBuy();
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt == 0 || bt == g_last_bar) return;
   g_last_bar = bt;

   ProcessNewBar();
}
//+------------------------------------------------------------------+
