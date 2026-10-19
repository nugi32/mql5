//+------------------------------------------------------------------+
//|                                    EURUSD_M30_Rule74_EA.mq5      |
//|                                                                  |
//| EA berdasarkan hasil edge-search report:                         |
//|   Rule: EURUSD_M30_74                                            |
//|   Entry Condition: rsi_7 > 80.0 AND stoch_5_3_3_k > 80.0          |
//|                    AND ma_5_ema < close AND mom_10 > -5.0         |
//|   Holding Period : 23 bar (Phase 7c EXIT_BARS, walk-forward       |
//|                     stabil, score tertinggi di horizon 23)        |
//|                                                                  |
//| CATATAN PENTING SOAL ARAH TRADE:                                  |
//|   Hipotesis awal rule ini adalah "price rally" (bullish), TAPI    |
//|   hasil statistik di report menunjukkan Prob(Bull) turun dari     |
//|   baseline 49.78% -> 44.97% (Effect Size -0.0482, p-value sangat  |
//|   signifikan). Artinya kondisi ini justru edge BEARISH, bukan     |
//|   bullish seperti nama hipotesisnya.                              |
//|   Net Expectancy (pips) dan Expectancy (R) yang positif di        |
//|   horizon 23 dihitung berdasarkan arah edge yang sebenarnya       |
//|   (bearish), jadi EA ini didesain untuk SELL saat kondisi entry   |
//|   terpenuhi, BUKAN buy. Kalau ternyata expectancy di report itu   |
//|   dihitung untuk arah BUY, tinggal balik ORDER_TYPE_SELL jadi     |
//|   ORDER_TYPE_BUY di fungsi OpenPosition() -- saya tandai di sana. |
//|                                                                  |
//| Arsitektur:                                                       |
//|   - Semua logic (entry check & exit check) HANYA jalan saat bar   |
//|     baru terbentuk (is new bar), tidak di setiap tick.            |
//|   - TIDAK ada SL/TP broker sama sekali (sl=0, tp=0 di OrderSend). |
//|     Exit murni time-based: close setelah 23 bar closed sejak      |
//|     entry.                                                        |
//|   - Restart-safe: jumlah bar sejak entry dihitung ulang dari      |
//|     POSITION_TIME via iBarShift(), bukan dari variabel in-memory, |
//|     jadi kalau EA di-restart posisi tetap ke-track dengan benar.  |
//|   - Timeframe indikator di-hardcode ke PERIOD_M30 (timeframe di   |
//|     mana rule ini di-mining), TIDAK mengikuti Period() chart.     |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Rule74 EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs
input double InpLots               = 0.10;      // Lot size
input ulong  InpMagic               = 74074023;  // Magic number
input int    InpHoldingBars         = 23;        // Holding period (bar), sesuai report
input int    InpRSI_Period          = 7;         // RSI period
input double InpRSI_Threshold       = 80.0;      // RSI threshold
input int    InpStoch_K             = 5;         // Stochastic %K period
input int    InpStoch_D             = 3;         // Stochastic %D period
input int    InpStoch_Slowing       = 3;         // Stochastic slowing
input double InpStoch_Threshold     = 80.0;      // Stochastic %K threshold
input int    InpMA_Period           = 5;         // MA period (EMA)
input int    InpMom_Period          = 10;        // Momentum period
input double InpMom_Threshold       = -5.0;      // Momentum threshold (mom_10 > this)
input bool   InpEnableCSVLog        = true;      // Enable CSV trade logging

//--- Hardcoded to the timeframe/symbol the rule was mined on
#define RULE_TIMEFRAME PERIOD_M30

//--- Globals
CTrade   g_trade;
int      g_hRSI    = INVALID_HANDLE;
int      g_hStoch  = INVALID_HANDLE;
int      g_hMA     = INVALID_HANDLE;
int      g_hMom    = INVALID_HANDLE;
datetime g_last_bar_time = 0;
string   g_csv_filename  = "";
int      g_csv_handle    = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if (StringFind(_Symbol, "EURUSD") < 0)
      Print("WARNING: EA ini dibangun dari rule EURUSD_M30_74. Chart sekarang symbol-nya ", _Symbol,
            " -- pastikan ini memang broker-suffixed EURUSD, kalau bukan hasil trading tidak valid.");

   g_hRSI = iRSI(_Symbol, RULE_TIMEFRAME, InpRSI_Period, PRICE_CLOSE);
   if (g_hRSI == INVALID_HANDLE) { Print("ERROR: gagal buat handle RSI"); return INIT_FAILED; }

   g_hStoch = iStochastic(_Symbol, RULE_TIMEFRAME, InpStoch_K, InpStoch_D, InpStoch_Slowing, MODE_SMA, STO_LOWHIGH);
   if (g_hStoch == INVALID_HANDLE) { Print("ERROR: gagal buat handle Stochastic"); return INIT_FAILED; }

   g_hMA = iMA(_Symbol, RULE_TIMEFRAME, InpMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if (g_hMA == INVALID_HANDLE) { Print("ERROR: gagal buat handle MA EMA"); return INIT_FAILED; }

   g_hMom = iMomentum(_Symbol, RULE_TIMEFRAME, InpMom_Period, PRICE_CLOSE);
   if (g_hMom == INVALID_HANDLE) { Print("ERROR: gagal buat handle Momentum"); return INIT_FAILED; }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if (InpEnableCSVLog)
   {
      g_csv_filename = "Rule74_Trades_" + _Symbol + ".csv";
      bool exists = FileIsExist(g_csv_filename);
      g_csv_handle = FileOpen(g_csv_filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (g_csv_handle != INVALID_HANDLE)
      {
         FileSeek(g_csv_handle, 0, SEEK_END);
         if (!exists)
            FileWrite(g_csv_handle, "time", "action", "type", "price", "lots", "bars_held", "comment");
      }
      else
      {
         Print("WARNING: gagal buka file CSV log, logging dinonaktifkan");
      }
   }

   // Inisialisasi supaya OnTick langsung bisa deteksi "bar baru" pertama kali dengan benar
   g_last_bar_time = iTime(_Symbol, RULE_TIMEFRAME, 0);

   Print("Rule74 EA initialized. Symbol=", _Symbol, " Timeframe=M30 (hardcoded) HoldingBars=", InpHoldingBars);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (g_hRSI   != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if (g_hStoch != INVALID_HANDLE) IndicatorRelease(g_hStoch);
   if (g_hMA    != INVALID_HANDLE) IndicatorRelease(g_hMA);
   if (g_hMom   != INVALID_HANDLE) IndicatorRelease(g_hMom);
   if (g_csv_handle != INVALID_HANDLE) FileClose(g_csv_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function -- hanya proses saat bar baru               |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_bar_time = iTime(_Symbol, RULE_TIMEFRAME, 0);
   if (current_bar_time == g_last_bar_time)
      return; // masih di bar yang sama, tidak melakukan apa-apa (tidak ada broker SL/TP jadi memang tidak perlu diproses per-tick)

   g_last_bar_time = current_bar_time;
   ProcessNewBar();
}

//+------------------------------------------------------------------+
//| Semua logic entry & exit ada di sini, dipanggil sekali per bar   |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   if (PositionSelectBySymbolMagic())
   {
      int barsHeld = GetBarsSinceEntry();
      if (barsHeld >= InpHoldingBars)
      {
         ClosePosition("holding_period_reached");
      }
      // Kalau posisi masih terbuka dan belum kena holding period, tidak melakukan apa-apa lagi
      // (tidak ada SL/TP, tidak ada exit lain selain waktu).
      return;
   }

   // Tidak ada posisi terbuka -> cek entry condition di bar terakhir yang sudah closed (shift 1)
   if (CheckEntryCondition())
   {
      OpenPosition();
   }
}

//+------------------------------------------------------------------+
//| Cek apakah posisi EA ini (symbol + magic) sedang terbuka         |
//+------------------------------------------------------------------+
bool PositionSelectBySymbolMagic()
{
   if (!PositionSelect(_Symbol)) return false;
   if (PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Hitung berapa bar closed sejak posisi entry -- restart-safe,      |
//| dihitung ulang dari POSITION_TIME, bukan dari variabel in-memory  |
//+------------------------------------------------------------------+
int GetBarsSinceEntry()
{
   datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
   int shift = iBarShift(_Symbol, RULE_TIMEFRAME, entryTime, false);
   if (shift < 0) shift = 0;
   return shift;
}

//+------------------------------------------------------------------+
//| Cek entry condition di bar closed terakhir (shift = 1)           |
//+------------------------------------------------------------------+
bool CheckEntryCondition()
{
   double rsiBuf[1], stochKBuf[1], maBuf[1], momBuf[1];

   if (CopyBuffer(g_hRSI, 0, 1, 1, rsiBuf) <= 0)      { Print("ERROR: gagal ambil buffer RSI"); return false; }
   if (CopyBuffer(g_hStoch, 0, 1, 1, stochKBuf) <= 0) { Print("ERROR: gagal ambil buffer Stoch %K"); return false; }
   if (CopyBuffer(g_hMA, 0, 1, 1, maBuf) <= 0)        { Print("ERROR: gagal ambil buffer MA"); return false; }
   if (CopyBuffer(g_hMom, 0, 1, 1, momBuf) <= 0)      { Print("ERROR: gagal ambil buffer Momentum"); return false; }

   double close1 = iClose(_Symbol, RULE_TIMEFRAME, 1);

   double rsi7    = rsiBuf[0];
   double stochK  = stochKBuf[0];
   double ma5ema  = maBuf[0];
   double mom10   = momBuf[0];

   bool cond = (rsi7 > InpRSI_Threshold) &&
               (stochK > InpStoch_Threshold) &&
               (ma5ema < close1) &&
               (mom10 > InpMom_Threshold);

   return cond;
}

//+------------------------------------------------------------------+
//| Buka posisi -- TANPA SL/TP broker sama sekali                    |
//+------------------------------------------------------------------+
void OpenPosition()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Edge di report ini BEARISH (Prob Bull turun signifikan setelah kondisi terpenuhi),
   // jadi default-nya SELL. Kalau expectancy report ternyata dihitung untuk arah BUY,
   // ganti baris di bawah ini jadi g_trade.Buy(...) + SYMBOL_ASK.
   bool ok = g_trade.Sell(InpLots, _Symbol, price, 0.0, 0.0, "Rule74_Sell");

   if (ok)
   {
      Print("ENTRY: SELL ", InpLots, " lot @ ", price, " (Rule74 condition terpenuhi)");
      LogTrade("OPEN", "SELL", price, InpLots, 0, "entry_condition_met");
   }
   else
   {
      Print("ERROR: gagal buka posisi SELL. RetCode=", g_trade.ResultRetcode(),
            " Desc=", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Tutup posisi (market close, tidak ada SL/TP yang dihapus karena  |
//| memang tidak pernah di-set di broker)                            |
//+------------------------------------------------------------------+
void ClosePosition(string reason)
{
   int barsHeld = GetBarsSinceEntry();
   double lots  = PositionGetDouble(POSITION_VOLUME);

   bool ok = g_trade.PositionClose(_Symbol);

   if (ok)
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      Print("EXIT: close posisi setelah ", barsHeld, " bar (reason=", reason, ")");
      LogTrade("CLOSE", "SELL", price, lots, barsHeld, reason);
   }
   else
   {
      Print("ERROR: gagal close posisi. RetCode=", g_trade.ResultRetcode(),
            " Desc=", g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| CSV trade logging                                                |
//+------------------------------------------------------------------+
void LogTrade(string action, string type, double price, double lots, int barsHeld, string comment)
{
   if (!InpEnableCSVLog || g_csv_handle == INVALID_HANDLE) return;

   FileWrite(g_csv_handle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             action,
             type,
             DoubleToString(price, _Digits),
             DoubleToString(lots, 2),
             barsHeld,
             comment);
   FileFlush(g_csv_handle);
}
//+------------------------------------------------------------------+
