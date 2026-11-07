//+------------------------------------------------------------------+
//| XAU_Edge1_RSI21_SMA5.mq5
//| Edge 1: rsi_21<25 AND ma_5_sma>close AND mom_10>-5 | hold 116
//| XAUUSD M5, long only. Tanpa library. Fixed lot.
//| Sinyal dibaca di bar close (shift 1), entry di open bar berikutnya,
//| posisi ditutup setelah 116 candle (sesuai report).
//+------------------------------------------------------------------+
#property copyright "XAU_Edge1_RSI21_SMA5"
#property version   "1.00"
#property strict

input group "=== Strategi ==="
input int       InpHoldBars      = 116;    // Tutup posisi setelah X candle (sesuai report)
input bool      InpUseMomFilter  = true;      // Filter mom_10 (di MT5 ~100, jadi selalu lolos)
input double    InpMomThreshold  = -5.0;      // mom_10 > nilai ini

input group "=== Order ==="
input double    InpLot           = 0.01;      // Fixed lot
input long      InpMagic         = 20260101;   // Magic number
input double    InpSLAtrMult     = 0.0;       // SL darurat ATR(14) x ini (0 = tanpa SL)
input int       InpMaxPositions  = 1;         // Maks posisi bersamaan
input int       InpMaxSpreadPts  = 0;         // Maks spread points (0 = off)
input int       InpSlippage      = 30;        // Deviasi (points)
input string    InpComment       = "XAU_Edge1_RSI21_SMA5";

int h_mom=INVALID_HANDLE, h_atr=INVALID_HANDLE;
int h_rsi21=INVALID_HANDLE, h_ma5=INVALID_HANDLE;
datetime g_lastBar = 0;

bool GetBuf(const int handle, const int buffer, const int shift, double &v)
{
   if(handle == INVALID_HANDLE) return false;
   double a[1];
   if(CopyBuffer(handle, buffer, shift, 1, a) <= 0) return false;
   v = a[0];
   if(v != v || v == EMPTY_VALUE || MathAbs(v) >= 1.0e300) return false;
   return true;
}

void ReleaseH(int &h) { if(h != INVALID_HANDLE) { IndicatorRelease(h); h = INVALID_HANDLE; } }

int OnInit()
{
   if(Symbol() != "XAUUSD" || Period() != PERIOD_M5)
      Print("PERINGATAN: EA ini diriset untuk XAUUSD M5. Chart sekarang: ", Symbol(), " ", EnumToString(Period()));
   h_mom = iMomentum(_Symbol, _Period, 10, PRICE_CLOSE);
   h_atr = iATR(_Symbol, _Period, 14);
   h_rsi21 = iRSI(_Symbol, _Period, 21, PRICE_CLOSE);
   h_ma5   = iMA(_Symbol, _Period, 5, 0, MODE_SMA, PRICE_CLOSE);
   if(h_mom == INVALID_HANDLE || h_atr == INVALID_HANDLE) { Print("ERROR: gagal membuat handle indikator"); return INIT_FAILED; }
   Print("XAU_Edge1_RSI21_SMA5 aktif | hold ", InpHoldBars, " candle | lot ", InpLot);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ReleaseH(h_mom); ReleaseH(h_atr);
   ReleaseH(h_rsi21); ReleaseH(h_ma5);
}

bool BuySignal()
{
   double v, cl = iClose(_Symbol, _Period, 1);
   if(cl <= 0) return false;
   if(InpUseMomFilter)
   {
      if(!GetBuf(h_mom, 0, 1, v)) return false;
      if(!(v > InpMomThreshold)) return false;
   }
   if(!GetBuf(h_rsi21, 0, 1, v) || !(v < 25.0)) return false;
   if(!GetBuf(h_ma5,   0, 1, v) || !(v > cl))   return false;
   return true;
}

int CountMyPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      n++;
   }
   return n;
}

ENUM_ORDER_TYPE_FILLING Filling()
{
   int fm = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

bool RetOK(const uint rc)
{
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
}

bool ClosePosition(const ulong ticket, const double volume)
{
   MqlTradeRequest rq; MqlTradeResult rs;
   ZeroMemory(rq); ZeroMemory(rs);
   rq.action       = TRADE_ACTION_DEAL;
   rq.position     = ticket;
   rq.symbol       = _Symbol;
   rq.volume       = volume;
   rq.type         = ORDER_TYPE_SELL;
   rq.price        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   rq.deviation    = InpSlippage;
   rq.magic        = InpMagic;
   rq.type_filling = Filling();
   rq.comment      = InpComment + " exit";
   if(!OrderSend(rq, rs) || !RetOK(rs.retcode))
   {
      Print("Close gagal ticket ", ticket, " retcode=", rs.retcode, " err=", GetLastError());
      return false;
   }
   return true;
}

void ManageTimeExit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int barsHeld = iBarShift(_Symbol, _Period, opened, false);
      if(barsHeld >= InpHoldBars)
         ClosePosition(tk, PositionGetDouble(POSITION_VOLUME));
   }
}

double NormLot()
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lots = InpLot;
   if(step > 0) lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < minV) lots = minV;
   if(lots > maxV) lots = maxV;
   return NormalizeDouble(lots, 2);
}

void OpenBuy()
{
   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts) return;
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = 0.0;
   if(InpSLAtrMult > 0)
   {
      double atr;
      if(GetBuf(h_atr, 0, 1, atr) && atr > 0)
      {
         double d = atr * InpSLAtrMult;
         double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
         if(d < minDist * 1.1) d = minDist * 1.1;
         sl = NormalizeDouble(ask - d, digits);
      }
   }
   MqlTradeRequest rq; MqlTradeResult rs;
   ZeroMemory(rq); ZeroMemory(rs);
   rq.action       = TRADE_ACTION_DEAL;
   rq.symbol       = _Symbol;
   rq.volume       = NormLot();
   rq.type         = ORDER_TYPE_BUY;
   rq.price        = ask;
   rq.sl           = sl;
   rq.deviation    = InpSlippage;
   rq.magic        = InpMagic;
   rq.type_filling = Filling();
   rq.comment      = InpComment;
   if(!OrderSend(rq, rs) || !RetOK(rs.retcode))
      Print("Buy gagal retcode=", rs.retcode, " err=", GetLastError());
}

void OnTick()
{
   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt == 0 || bt == g_lastBar) return;   // sekali per bar baru
   g_lastBar = bt;
   ManageTimeExit();
   if(CountMyPositions() >= InpMaxPositions) return;
   if(BuySignal()) OpenBuy();
}
