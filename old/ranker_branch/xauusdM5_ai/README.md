# xauusdM5 - Walk-Forward EA Pack

Satu EA per sinyal unik. Dari 51 EA lintas window, hanya ada 5 sinyal berbeda; 46 EA dengan sinyal duplikat sudah dihapus. Tersisa 5 EA, satu untuk setiap sinyal. Window tanpa edge: 39 (dilewati).

## Struktur
```
xauusdM5/
  README.md
  SUMMARY.csv
  run_YYYY/
    window_XXXX/
      EA_runYYYY_wXXXX_<edge_id>.mq5
```

## Aturan EA
- Hanya LONG, tanpa SL & TP broker sama sekali (sl=0, tp=0).
- Eksekusi di bar baru (IsNewBar via iTime(0), sama seperti OnTick di DataExporter). Sinyal dibaca dari bar yang baru close (shift 1).
- Exit: posisi ditutup setelah `holding_bars` bar (dihitung dengan iBarShift dari waktu open posisi).
- Report menunjukkan trade saling overlap (mis. 839 trade x 139 bar > jumlah bar setahun), maka EA membuka posisi baru tiap sinyal. Butuh akun HEDGING; di akun NETTING otomatis dibatasi 1 posisi. Batas via `InpMaxPositions`.
- Lot fixed `InpLots` (default 0.01). Magic number unik per window.
- Indikator custom `VolRegime_ATR` dan `PriceStructure` (.ex5) harus ada di MQL5\Indicators (buffer: pctl=0, ratio=5, sess_low=3).

## Cara memilih EA yang dipertahankan
EA dikelompokkan berdasarkan sinyal/edge. Jika sinyal sama muncul di beberapa window, hanya satu EA dengan hasil terbaik yang dipertahankan. Pada data ini, metrik untuk setiap sinyal identik di semua window yang mengulanginya, jadi file dari run paling awal dipilih sebagai wakil.

| Test year | Edge | File yang dipertahankan | Hold | Exp R | PF | n | Catatan |
|---|---|---|---:|---:|---:|---:|---|
| 2018 | XAUUSD_M5_97 | `run_2010/window_0005/EA_run2010_w0005_XAUUSD_M5_97.mq5` | 144 | 0.6593 | 1.28 | 232 | Sinyal ini muncul 6 kali; hasilnya identik. |
| 2022 | XAUUSD_M5_58 | `run_2010/window_0009/EA_run2010_w0009_XAUUSD_M5_58.mq5` | 139 | 1.4948 | 1.21 | 839 | Sinyal ini muncul 10 kali; hasilnya identik. |
| 2023 | XAUUSD_M5_1 | `run_2010/window_0010/EA_run2010_w0010_XAUUSD_M5_1.mq5` | 144 | 1.6948 | 1.31 | 71 | Sinyal ini muncul 11 kali; hasilnya identik. Low confidence karena n_trades kecil. |
| 2024 | XAUUSD_M5_9 | `run_2010/window_0011/EA_run2010_w0011_XAUUSD_M5_9.mq5` | 59 | 0.8218 | 1.29 | 336 | Sinyal ini muncul 12 kali; hasilnya identik. |
| 2025 | XAUUSD_M5_11 | `run_2010/window_0012/EA_run2010_w0012_XAUUSD_M5_11.mq5` | 116 | 1.2958 | 1.65 | 328 | Sinyal ini muncul 12 kali; hasilnya identik. Window TRUNCATED di data (OOS 2025). |

## Catatan penting
1. Report berisi 12 run yang train-nya saling tumpang tindih. Dari 51 EA, terdapat 5 sinyal unik; tiap sinyal yang berulang memiliki hasil identik. Satu file per sinyal dipertahankan dan 46 duplikat dihapus.
2. `mom_10 > -5.0` / `> 0.0`: di MT5 iMomentum bernilai sekitar 100, jadi filter ini selalu true (terbukti dari hasil varian dengan/tanpa mom identik). Tetap diimplementasi apa adanya.
3. Data report adalah XAUUSD M5 (edge_id XAUUSD_M5_*). EA memakai _Symbol, pasang di chart XAUUSD M5.
4. Edge dipilih dari hasil test (OOS) di report, jadi bukan OOS murni. Window 2023 hanya 1 edge dengan 71 trade.
5. EA belum dikompilasi di MetaEditor; compile dulu dan cek di Strategy Tester (Every tick / real ticks).

## Window tanpa edge (tidak dibuat EA)
run_2010/window_0000, run_2010/window_0001, run_2010/window_0002, run_2010/window_0003, run_2010/window_0004, run_2010/window_0006, run_2010/window_0007, run_2010/window_0008, run_2011/window_0000, run_2011/window_0001, run_2011/window_0002, run_2011/window_0003, run_2011/window_0005, run_2011/window_0006, run_2011/window_0007, run_2012/window_0000, run_2012/window_0001, run_2012/window_0002, run_2012/window_0004, run_2012/window_0005, run_2012/window_0006, run_2013/window_0000, run_2013/window_0001, run_2013/window_0003, run_2013/window_0004, run_2013/window_0005, run_2014/window_0000, run_2014/window_0002, run_2014/window_0003, run_2014/window_0004, run_2015/window_0001, run_2015/window_0002, run_2015/window_0003, run_2016/window_0000, run_2016/window_0001, run_2016/window_0002, run_2017/window_0000, run_2017/window_0001, run_2018/window_0000
