# eurusdM5 – Walk-Forward Edge EAs (MQL5)

34 EA, satu per window yang punya accepted edge di report. Tiap window = **1 edge** (hasil seleksi plateau),
arah **SHORT**, keluar **setelah N candle** (`holding_bars` dari report), **tanpa SL/TP broker**.
Setiap file `.mq5` berdiri sendiri: tanpa `#include`, tanpa custom indicator (`iCustom`), tanpa library.

## Struktur folder

```
eurusdM5/
├── README.md
├── selection_summary.csv      <- 34 EA: window, edge, kondisi, hold, hasil test, magic, file
├── plateau_ranking.csv        <- semua kandidat per test-year + skor plateau
├── run_2010/
│   ├── window_0001/EURUSD_M5_R2010_W0001.mq5
│   ├── window_0002/EURUSD_M5_R2010_W0002.mq5
│   └── ...
├── run_2011/ ... run_2021/
```

Nama file: `EURUSD_M5_R<run>_W<window>.mq5`. Magic number = `run*100 + window` (unik per EA, mis. run_2010/window_0001 = 201001).
Window yang di report `accepted = 0` (56 window) tidak dibuatkan EA.

## Cara pakai

1. Copy folder `eurusdM5` ke `<MT5 data folder>\MQL5\Experts\`.
2. Compile (F7 di MetaEditor) EA yang diperlukan.
3. Strategy Tester: symbol **EURUSD**, period **M5**, atur tanggal test = "Test (OOS)" yang tertulis di header file `.mq5`.
4. Live/demo: attach ke chart EURUSD M5.

## Cara kerja EA

- `OnTick` memakai `IsNewBar()` (sama seperti `OnTick` di DataExporter). Sinyal dievaluasi **sekali per bar baru**
  dari bar terakhir yang sudah **close (shift 1)**, lalu entry market SELL di open bar baru.
- Exit: posisi ditutup saat umurnya sudah `>= InpHoldingBars` bar (dicek tiap bar baru; kalau close gagal, di-retry tiap tick).
- `sl = 0`, `tp = 0` – tidak ada SL/TP broker sama sekali.
- Indikator memakai definisi yang sama dengan `DataExporter.mq5` (RSI/CCI/Momentum/MA/Stochastic memakai parameter & price yang sama).
- Semua threshold dari report ada di bagian `input` (bisa diubah di tab Inputs).

## Cara memilih 1 edge per window (plateau, bukan runcing)

Isi report sangat berulang: window yang sama muncul di banyak run dengan hasil identik, sehingga ke-34 EA ini
sebenarnya hanya **6 logika unik** (per test-year). Seleksi dilakukan per test-year, lalu dipakai ke semua window yang kembar:

1. Edge dengan hasil identik (varian yang cuma menambah filter tidak berpengaruh) dilebur jadi satu; dipakai versi dengan kondisi paling sedikit.
   Catatan: `mom_10 > -5.0` / `> 0.0` selalu true (iMomentum MT5 berpusat di ~100), jadi bukan filter sungguhan.
2. "Tetangga" = edge lain di window yang sama dengan selisih satu kondisi (tambah/kurang kondisi, atau ganti threshold/periode).
3. Skor plateau = `mean(exp edge + tetangga) – 0.5 × std`. Skor tinggi berarti tinggi **dan** rata di sekitarnya; edge yang menonjol sendirian dihukum.
4. Syarat: trades ≥ 30, PF ≥ 1.0, minimal 2 tetangga (fallback: 1 tetangga, lalu tanpa tetangga). Edge tanpa tetangga di daftar accepted
   (mis. `M5_378` 2018 dengan 68 trades, atau `M5_29` 2014 dengan 19 trades) dianggap puncak runcing dan tidak dipilih.
5. Tie-break: expectancy lebih tinggi, lalu trades lebih banyak.

| Test year | Edge | Kondisi (SHORT) | Hold | Exp R | PF | Trades | Jumlah EA |
|---|---|---|---:|---:|---:|---:|---:|
| 2014 | `M5_20` | `stoch_5_3_3_k > 80.0 AND volregime_atr_pctl < 20.0 AND rsi_7 > 70.0` | 123 | 0.4338 | 1.01 | 1011 | 2 |
| 2015 | `M5_16` | `stoch_5_3_3_k > 80.0 AND ps_dist_sess_h_atr < -0.5 AND volregime_atr_pctl < 20.0` | 41 | 1.1272 | 1.79 | 205 | 3 |
| 2016 | `M5_452` | `stoch_5_3_3_k > 80.0 AND volregime_regime == 1.0 AND mom_10 > -5.0 AND rsi_21 > 70.0` | 103 | 0.3213 | 1.78 | 125 | 4 |
| 2018 | `M5_161` | `rsi_14 > 75.0 AND cci_14 > 100.0 AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0` | 89 | 3.4681 | 3.47 | 76 | 6 |
| 2019 | `M5_99` | `rsi_14 > 75.0 AND cci_14 > 100.0 AND stoch_5_3_3_k > 80.0 AND ps_dist_sess_h_atr < -1.0` | 88 | 1.7691 | 1.85 | 357 | 7 |
| 2024 | `M5_3` | `cci_14 > 100.0 AND ps_dist_sess_h_atr < -0.5` | 144 | 0.6043 | 1.23 | 3715 | 12 |

Window → logika:

- **2014**: 2010/w0001, 2011/w0000
- **2015**: 2010/w0002, 2011/w0001, 2012/w0000
- **2016**: 2010/w0003, 2011/w0002, 2012/w0001, 2013/w0000
- **2018**: 2010/w0005, 2011/w0004, 2012/w0003, 2013/w0002, 2014/w0001, 2015/w0000
- **2019**: 2010/w0006, 2011/w0005, 2012/w0004, 2013/w0003, 2014/w0002, 2015/w0001, 2016/w0000
- **2024**: 2010/w0011, 2011/w0010, 2012/w0009, 2013/w0008, 2014/w0007, 2015/w0006, 2016/w0005, 2017/w0004, 2018/w0003, 2019/w0002, 2020/w0001, 2021/w0000

## ⚠ Hal yang perlu Anda cek sebelum percaya hasilnya

1. **VolRegime_ATR dan PriceStructure direplikasi ulang** (karena tanpa custom indicator) dan saya tidak punya source aslinya,
   jadi ada asumsi: ATR percentile = percent-rank ATR(14)[1] terhadap 500 bar terakhir; regime 0/1/2 dibagi di persentil 33.33/66.67;
   "session" = blok 8 jam server time dari 00:00, level = high blok sebelumnya, jarak = (level − close[1]) / ATR(14)[1].
   Kalau definisi di indikator Anda berbeda, ubah di input group `VolRegime replica` / `PriceStructure replica`
   (atau beri tahu definisi aslinya dan saya sesuaikan). **Ini penentu utama apakah hasil EA cocok dengan report.**
2. **Overlap trade.** Di report mis. 3715 trade × 144 bar jauh lebih besar dari jumlah bar M5 setahun, artinya sinyal berurutan
   saling tumpang tindih. Default EA `InpMaxPositions = 1` (aman). Untuk meniru report, naikkan nilainya (butuh akun **hedging**) –
   tapi tanpa SL risikonya menumpuk.
3. **Tanpa SL** = kerugian per posisi tidak dibatasi sampai bar ke-N. Jalankan lot kecil dulu.
4. **Edge lemah di beberapa window.** 2014: PF hanya 1.01 (praktis tanpa edge setelah spread). 2019: tetangga edge terpilih
   jauh lebih lemah (exp 0.06–0.15 vs 1.77), jadi plateau-nya tidak benar-benar rata; pasangan `M5_99`/`M5_37` yang hampir kembar.
   2018 hanya 76 trades; 2024 hanya satu edge sehingga tidak ada bukti plateau.
5. Unit `expectancy_r` di report tidak konsisten dengan PF (mis. exp 0.43 dengan PF 1.01). Jangan menganggap "R" itu risiko riil karena EA ini tanpa SL.
6. Biaya (spread/slippage/swap) tidak ada di report – cek di tester dengan tick sebenarnya.
7. File belum saya kompilasi di MetaEditor (tidak ada MT5 di environment ini). Struktur kode sudah dicek (brace/placeholder/magic unik);
   kalau ada error compile, kirim pesannya.
