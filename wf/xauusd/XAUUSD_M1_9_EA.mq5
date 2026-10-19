//+------------------------------------------------------------------+
//| XAUUSD_M1_9_EA.mq5                                                |
//| Edge  : XAUUSD_M1_9                                               |
//| Rule  : rsi_21 < 20.0 AND mom_10 > -5.0        (BUY / long)       |
//| Hold  : 362 bars M1, exit murni time-based, tanpa SL/TP broker    |
//|                                                                   |
//| CARA HITUNG INDIKATOR = IDENTIK DataExporter.mq5:                 |
//|   rsi_21 = iRSI(sym, tf, 21, PRICE_CLOSE)         buffer 0        |
//|   mom_10 = iMomentum(sym, tf, 10, PRICE_CLOSE)    buffer 0        |
//|   Nilai dibaca pada shift 1 (bar terakhir yg sudah close),        |
//|   sama seperti WriteBarToCSVLive() yang memakai bar index 1.      |
//|                                                                   |
//| CATATAN PENTING (mom_10):                                         |
//|   iMomentum MQL5 mengembalikan rasio close/close[n]*100 (~100),   |
//|   BUKAN selisih harga. Jadi mom_10 > -5.0 praktis SELALU true     |
//|   (di report: correlation 1.0 saat threshold digeser). Kondisi    |
//|   dipertahankan persis agar sama dengan data riset, tapi efek     |
//|   nyatanya hanya rsi_21 < 20.                                     |
//|                                                                   |
//| Report: expectancy_r 0.75 (net), net 32.5 pips, holding stable,   |
//|   12/16 window positif, std_r besar -> hasil per trade volatil.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "XAUUSD M1 rule9: RSI21<20 & Mom10>-5, BUY, hold 362 bars"

#include <Trade\Trade.mqh>

//--- fixed rule parameters (hardcoded sesuai report)
#define TF            PERIOD_M1
#define RSI_PERIOD    21
#define RSI_LEVEL     20.0
#define MOM_PERIOD    10
#define MOM_LEVEL     (-5.0)
#define EXIT_BARS     362

input double InpLots     = 0.01;      // Lot
input int    InpMaxPos   = 1;         // Max posisi bersamaan (magic ini)
input int    InpSlippage = 30;        // Deviation (points)
input long   InpMagic    = 1009362;   // Magic number unik
input bool   InpLogCsv   = true;      // Tulis CSV log

CTrade   trade;
int      hRSI = INVALID_HANDLE;
int      hMOM = INVALID_HANDLE;
datetime lastBar = 0;

string CsvName() { return "XAUUSD_M1_9_Trades_" + _Symbol + ".csv"; }

//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("WARNING: EA ini di-riset untuk XAUUSD, chart sekarang: ", _Symbol);
   if(_Period != TF)
      Print("INFO: EA memakai PERIOD_M1 hardcoded, chart period diabaikan.");

   // sama persis dengan CreateIndicatorHandles() di DataExporter
   hRSI = iRSI(_Symbol, TF, RSI_PERIOD, PRICE_CLOSE);
   hMOM = iMomentum(_Symbol, TF, MOM_PERIOD, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE || hMOM == INVALID_HANDLE)
   {
      Print("Gagal membuat handle indikator");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hMOM != INVALID_HANDLE) IndicatorRelease(hMOM);
}

//+------------------------------------------------------------------+
int CountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic) n++;
   }
   return n;
}

// Exit time-based, restart-safe: umur posisi dihitung dari POSITION_TIME
void CheckExits()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int openShift = iBarShift(_Symbol, TF, opened, false);
      if(openShift >= EXIT_BARS)
      {
         if(!trade.PositionClose(t))
            Print("Close gagal ticket ", t, " err=", GetLastError());
      }
   }
}

// Sama dengan GetIndicatorValue() DataExporter: CopyBuffer(handle,0,shift,1)
bool GetVal(int handle, int shift, double &value)
{
   double b[1];
   if(CopyBuffer(handle, 0, shift, 1, b) != 1) return false;
   if(b[0] != b[0]) return false;           // NaN check
   value = b[0];
   return true;
}

bool SignalBuy()
{
   double rsi, mom;
   if(!GetVal(hRSI, 1, rsi)) return false;  // shift 1 = bar closed terakhir
   if(!GetVal(hMOM, 1, mom)) return false;
   return (rsi < RSI_LEVEL && mom > MOM_LEVEL);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bar0 = iTime(_Symbol, TF, 0);
   if(bar0 == 0 || bar0 == lastBar) return;   // bar-gated
   lastBar = bar0;

   CheckExits();

   if(CountPositions() >= InpMaxPos) return;
   if(SignalBuy())
   {
      if(!trade.Buy(InpLots, _Symbol, 0.0, 0.0, 0.0, "XAUUSD_M1_9"))
         Print("Buy gagal err=", GetLastError(), " ret=", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!InpLogCsv) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   string kind = (entry == DEAL_ENTRY_IN) ? "OPEN" : "CLOSE";

   int h = FileOpen(CsvName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0)
      FileWrite(h, "time", "event", "symbol", "type", "volume", "price", "profit", "position_id");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h,
             TimeToString((datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME), TIME_DATE | TIME_SECONDS),
             kind, _Symbol,
             (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? "BUY" : "SELL"),
             DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 2),
             DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits),
             DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PROFIT), 2),
             (string)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
   FileClose(h);
}
//+------------------------------------------------------------------+
