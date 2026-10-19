# eurusdM5 - Walk-Forward EAs (MQL5)

EA per window dari walk-forward report. Hanya window yang punya accepted edge yang dibuatkan EA (13 window).

## Struktur

```
eurusdM5/
  README.md
  SELECTION.md            <- alasan pemilihan edge (plateau)
  windows_index.csv       <- peta window -> EA -> kondisi -> hold -> magic
  Include/
    EdgeCore.mqh          <- logic bersama (new bar, baca indikator, buka/tutup posisi)
  run_2010/ ... run_2015/
    EURUSD_M5_run<YYYY>_window<NNNN>.mq5
```

## Instalasi

1. Copy seluruh folder `eurusdM5` ke `<MT5 data folder>\MQL5\Experts\`
   (File > Open Data Folder). Folder `Include` HARUS tetap di dalam `eurusdM5`,
   karena EA memakai `#include "..\Include\EdgeCore.mqh"`.
2. Buka salah satu `.mq5` di MetaEditor, tekan F7 untuk compile.
3. Strategy Tester: symbol EURUSD, timeframe M5. Set tanggal ke **test period** yang tertulis di header EA.

## Perilaku EA

- Eksekusi hanya sekali per bar baru (`EC_IsNewBar`, logika sama seperti OnTick di DataExporter).
- Sinyal dihitung dari **bar tertutup terakhir (shift 1)**, sama seperti CSV export (`WriteBarToCSVLive` menulis bar index 1).
- Entry market short di open bar berjalan. **Tanpa SL dan TP.**
- Exit: posisi ditutup setelah `holding_bars` bar (umur dihitung dari `POSITION_TIME` via `iBarShift`, jadi aman saat EA restart dan melewati weekend).
- Definisi indikator identik dengan DataExporter: `iRSI`, `iStochastic(...,MODE_SMA,STO_LOWHIGH)` buffer 0 (K), `iMA` EMA/SMMA, `iMomentum` (nilai sekitar 100), dll.
- Magic number unik per window: `5` + `YYYY` + `NNNN` (mis. run_2010/window_0002 -> 520100002).

## Input

| Input | Default | Keterangan |
|---|---|---|
| InpLots | 0.10 | Lot tetap |
| InpMagic | unik per window | |
| InpSlippage | 20 | Deviation (points) |
| InpMaxPositions | 0 | 0 = tanpa batas (meniru report) |

## Catatan penting

- **Overlap posisi**: jumlah trade di report (mis. 786 trade x 138 bar) melebihi jumlah bar M5 setahun,
  artinya report mengizinkan trade tumpang tindih. Karena itu default `InpMaxPositions = 0`.
  Ini butuh akun **hedging**. Di akun netting, posisi akan digabung dan time-stop per trade tidak akurat.
  Set `InpMaxPositions = 1` kalau mau satu posisi sekaligus (hasil akan berbeda dari report).
- `mom_10 > -5.0` pada edge 2016 selalu benar (iMomentum bernilai sekitar 100), jadi filter itu tidak berpengaruh.
  Tetap disertakan agar sesuai report.
- Kode belum dikompilasi di MetaEditor. Compile dulu (F7) dan cek hasil backtest terhadap report.
