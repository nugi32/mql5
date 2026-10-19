# eurusdH1

29 Expert Advisors (MT5), satu per window walk-forward yang punya accepted edge.
Semua SHORT, EURUSD, timeframe H1. Tidak ada window 2025 yang punya accepted edge.

## Struktur

    eurusdH1/
    |-- Include/
    |   `-- EurH1Core.mqh          engine bersama (new bar, 1 posisi, exit N bar)
    |-- run_2010/
    |   |-- window_0000/EURUSD_H1_run2010_w0000.mq5
    |   |-- window_0001/EURUSD_H1_run2010_w0001.mq5
    |   `-- ...
    |-- ... (run_2011 .. run_2021)
    |-- manifest.csv               ringkasan semua EA
    `-- README.md

## Instalasi

Copy seluruh folder `eurusdH1` ke `<MT5 Data Folder>/MQL5/Experts/`.
Struktur harus utuh karena EA meng-include `..\..\Include\EurH1Core.mqh`.
Compile lewat MetaEditor (F7), lalu pasang di chart EURUSD H1.

## Perilaku EA

- Pakai `IsNewBar` (iTime shift 0), sama seperti OnTick di DataExporter.mq5.
- Sinyal dibaca dari bar yang sudah close (shift 1), sama seperti export CSV.
- Entry market sell tanpa SL dan tanpa TP.
- Exit: posisi ditutup saat sudah berumur `holding_bars` bar (cek tiap bar baru).
- Maksimal 1 posisi per EA (per magic number). Magic unik per window.
- Timeframe di-hardcode PERIOD_H1 (EA menolak jalan di timeframe lain).
- Input: `InpLots` (0.01), `InpMagic`, `InpDeviation`.

## Edge yang dipilih (per test year)

| Test year | Edge report | Rule (short) | Hold | Exp R | PF | Trades |
|---|---|---|---:|---:|---:|---:|
| 2013 | EURUSD_H1_1 | rsi_7 > 70 | 12 | 0.1165 | 1.20 | 850 |
| 2014 | EURUSD_H1_50 | rsi_7 > 75 AND stoch_5_3_3_k > 70 AND mom_10 > 0 | 11 | 0.6403 | 1.79 | 281 |
| 2015 | EURUSD_H1_174 | stoch_14_3_3_k > 70 AND cci_20 > 100 AND ma_5_ema < close AND mom_10 > 0 | 12 | 0.0317 | 1.01 | 902 |
| 2016 | EURUSD_H1_53 | rsi_7 > 80 AND stoch_14_3_3_k > 80 | 12 | 0.0326 | 1.26 | 200 |
| 2019 | EURUSD_H1_97 | stoch_14_3_3_k > 80 AND cci_14 > 50 AND ma_5_lwma < close AND mom_10 > 0 | 11 | 0.0268 | 1.01 | 819 |
| 2024 | EURUSD_H1_29 | cci_14 > 100 AND mom_10 > 0 | 12 | 0.0345 | 1.14 | 1211 |

Window dengan test year yang sama memakai edge yang sama (statistik report identik),
yang beda hanya periode train, nama window, dan magic number.

## Catatan

- `mom_10` memakai iMomentum (nilai sekitar 100), jadi threshold -5 / 0 / 5 selalu true.
  Filter ini praktis tidak menyaring apa pun; dipertahankan karena itu definisi di report.
- EA belum di-compile di MetaEditor oleh pembuatnya; compile dulu dan cek log.
