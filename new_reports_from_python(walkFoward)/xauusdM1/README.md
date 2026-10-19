# xauusdM1

31 Expert Advisors (MT5), satu per window walk-forward yang punya accepted edge.
Semua LONG, XAUUSD, timeframe M1.

## Struktur

    xauusdM1/
    |-- Include/
    |   `-- XauM1Core.mqh          engine bersama (new bar, 1 posisi, exit N bar)
    |-- run_2010/
    |   |-- window_0008/XAUUSD_M1_run2010_w0008.mq5
    |   |-- window_0009/XAUUSD_M1_run2010_w0009.mq5
    |   `-- window_0012/XAUUSD_M1_run2010_w0012.mq5
    |-- ... (run_2011 .. run_2021)
    |-- manifest.csv               ringkasan semua EA
    `-- README.md

## Instalasi

Copy seluruh folder `xauusdM1` ke `<MT5 Data Folder>/MQL5/Experts/`.
Struktur harus utuh karena EA meng-include `..\..\Include\XauM1Core.mqh`.
Compile lewat MetaEditor (F7), lalu pasang di chart XAUUSD M1.

## Perilaku EA

- Pakai `IsNewBar` (iTime shift 0), sama seperti OnTick di DataExporter.mq5.
- Sinyal dibaca dari bar yang sudah close (shift 1), sama seperti export CSV.
- Entry market buy tanpa SL dan tanpa TP.
- Exit: posisi ditutup saat sudah berumur `holding_bars` bar (cek tiap bar baru).
- Maksimal 1 posisi per EA (per magic number). Magic unik per window.
- Input: `InpLots` (0.01), `InpMagic`, `InpDeviation`.

## Edge yang dipilih

| Test year | Edge report | Rule | Hold |
|---|---|---|---:|
| 2021 | XAUUSD_M1_10 | rsi_21 < 20 AND mom_10 > 0 | 362 |
| 2022 | XAUUSD_M1_6 | rsi_21 < 20 AND mom_10 > 0 | 714 |
| 2025 | XAUUSD_M1_8 | rsi_21 < 30 AND cci_20 < -100 AND ma_5_lwma < close AND mom_10 > 0 | 228 |

Pemilihan: grup dengan test expectancy dan PF tertinggi di window itu, lalu
varian tengah dari plateau (threshold mom_10 -5 / 0 / 5 memberi hasil identik,
diambil 0). Detail ada di pesan penjelasan.

## Catatan

- Window 2025 truncated (data OOS berhenti 2025-12-31).
- EA belum di-compile di MetaEditor oleh pembuatnya; compile dulu dan cek log.
