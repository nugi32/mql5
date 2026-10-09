# m5Xauusd

35 Expert Advisors (MT5), satu per window walk-forward yang punya accepted edge.
Semua LONG, XAUUSD, timeframe M5. Window tanpa accepted edge (test 2013-2022) tidak dibuat.

## Struktur

    m5Xauusd/
    |-- Include/
    |   `-- XauM5Core.mqh          engine bersama (new bar, 1 posisi, exit N bar)
    |-- run_2010/
    |   |-- window_0010/XAUUSD_M5_run2010_w0010.mq5   (test 2023)
    |   |-- window_0011/XAUUSD_M5_run2010_w0011.mq5   (test 2024)
    |   `-- window_0012/XAUUSD_M5_run2010_w0012.mq5   (test 2025, truncated)
    |-- ... (run_2011 .. run_2021)
    |-- manifest.csv               ringkasan semua EA
    `-- README.md

## Instalasi

Copy seluruh folder `m5Xauusd` ke `<MT5 Data Folder>/MQL5/Experts/`.
Struktur harus utuh karena EA meng-include `..\..\Include\XauM5Core.mqh`.
Compile lewat MetaEditor (F7), lalu pasang di chart XAUUSD M5.

## Perilaku EA

- Pakai `IsNewBar` (iTime shift 0), sama seperti OnTick di DataExporter.mq5.
- Sinyal dibaca dari bar yang sudah close (shift 1), sama seperti export CSV.
- Entry market buy tanpa SL dan tanpa TP.
- Exit: posisi ditutup saat sudah berumur `holding_bars` bar (cek tiap bar baru).
- Maksimal 1 posisi per EA (per magic number). Magic unik per window.
- Timeframe di-hardcode PERIOD_M5 (EA menolak jalan di timeframe lain).
- Input: `InpLots` (0.01), `InpMagic`, `InpDeviation`.

## Edge yang dipilih (per test year)

| Test year | Edge report | Rule (long) | Hold | Exp R | PF | Trades |
|---|---|---|---:|---:|---:|---:|
| 2023 | XAUUSD_M5_1 | rsi_21 < 20 | 144 | 1.6948 | 1.31 | 71 |
| 2024 | XAUUSD_M5_45 | rsi_21 < 25 AND cci_14 < -100 AND mom_10 > 0 | 59 | 0.8218 | 1.29 | 336 |
| 2025 | XAUUSD_M5_40 | rsi_21 < 25 AND ma_5_sma > close AND mom_10 > 0 | 116 | 1.3110 | 1.63 | 317 |

Window dengan test year yang sama memakai edge yang sama (statistik report identik),
yang beda hanya nama window dan magic number.

## Catatan

- Test 2023 hanya punya 1 edge (71 trade), jadi tidak ada plateau untuk dipilih.
- Test 2025 truncated (data OOS berhenti 2025-12-31).
- `mom_10` memakai iMomentum (nilai sekitar 100), jadi threshold -5 / 0 / 5 selalu true.
  Filter ini praktis tidak menyaring apa pun; dipertahankan karena itu definisi di report.
- EA belum di-compile di MetaEditor oleh pembuatnya; compile dulu dan cek log.
