# eurusdM5 - Walk-Forward Edge EAs (EURUSD M5)

Satu EA per window (hasil seleksi 1 edge "plateau" per window), dibuat dari
`Walk-Forward Meta-Pipeline Summary` dan indikator dari `DataExporter.mq5`.

## Struktur

```
eurusdM5/
|-- README.md
|-- Include/
|   `-- eurusdM5/
|       `-- EdgeEngine.mqh            <- engine bersama (new-bar, entry, exit by bars)
`-- Experts/
    `-- eurusdM5/
        `-- run_2010/
            |-- window_0001/EA_EURUSD_M5_r2010_w0001.mq5
            |-- window_0002/EA_EURUSD_M5_r2010_w0002.mq5
            |-- window_0003/EA_EURUSD_M5_r2010_w0003.mq5
            |-- window_0005/EA_EURUSD_M5_r2010_w0005.mq5
            |-- window_0006/EA_EURUSD_M5_r2010_w0006.mq5
            `-- window_0011/EA_EURUSD_M5_r2010_w0011.mq5
```

## Instalasi

1. Buka MT5 > File > Open Data Folder > `MQL5`.
2. Copy `Include/eurusdM5`  ->  `MQL5/Include/eurusdM5`
3. Copy `Experts/eurusdM5`  ->  `MQL5/Experts/eurusdM5`
4. Pastikan `VolRegime_ATR.ex5` dan `PriceStructure.ex5` ada di `MQL5/Indicators`
   (kalau di sub-folder, ubah `#define CUSTOM_IND_...` dan `#property tester_indicator` di EA).
5. Compile EA di MetaEditor, lalu jalankan di Strategy Tester: EURUSD, M5,
   tanggal tester = test period window (lihat tabel).
   Wajib akun **hedging** supaya posisi overlap seperti di report bisa jalan.

## Edge terpilih

| EA | Edge | Kondisi (SHORT) | Hold (bar M5) | Test year | Exp R | PF | Trades |
|---|---|---|---:|---|---:|---:|---:|
| r2010_w0001 | EURUSD_M5_20  | stoch_5_3_3_k > 80 AND volregime_atr_pctl < 20 AND rsi_7 > 70 | 123 | 2014 | 0.4338 | 1.01 | 1011 |
| r2010_w0002 | EURUSD_M5_16  | stoch_5_3_3_k > 80 AND ps_dist_sess_h_atr < -0.5 AND volregime_atr_pctl < 20 | 41 | 2015 | 1.1272 | 1.79 | 205 |
| r2010_w0003 | EURUSD_M5_142 | rsi_14 > 75 AND stoch_14_3_3_k > 80 AND mom_10 > -5 | 138 | 2016 | 0.8530 | 1.42 | 786 |
| r2010_w0005 | EURUSD_M5_181 | rsi_14 > 75 AND stoch_14_3_3_k > 80 AND ps_dist_sess_h_atr < -2 AND volregime_regime == 1 | 88 | 2018 | 3.1629 | 3.07 | 81 |
| r2010_w0006 | EURUSD_M5_37  | rsi_14 > 75 AND stoch_5_3_3_k > 80 AND ps_dist_sess_h_atr < -1 | 88 | 2019 | 1.6914 | 1.83 | 390 |
| r2010_w0011 | EURUSD_M5_3   | cci_14 > 100 AND ps_dist_sess_h_atr < -0.5 | 144 | 2024 | 0.6043 | 1.23 | 3715 |

Window tanpa edge (`accepted = 0`): 0000, 0004, 0007, 0008, 0009, 0010, 0012 -> tidak dibuat EA.

## Aturan seleksi "plateau"

Per window, edge dikelompokkan dengan tetangganya (kondisi mirip / threshold bergeser).
Dipilih cluster yang: n_trades >= ~80, PF > 1, dan tetangganya punya hasil hampir sama
(bukan satu angka tinggi yang sendirian). Dari cluster itu diambil edge yang paling dekat
dengan nilai tengah cluster dan jumlah kondisi paling sedikit. Edge dengan n_trades kecil
(contoh w0001: 19 trades, exp 5.34) dibuang karena "runcing".

## Perilaku EA

- Is-new-bar sama seperti `OnTick` di DataExporter; sinyal dibaca dari bar terakhir yang sudah close (shift 1),
  sama seperti baris CSV yang ditulis exporter.
- Entry market SELL di open bar baru. **Tanpa SL dan TP broker.**
- Exit: posisi ditutup saat sudah `holding_bars` bar M5 berlalu sejak bar entry.
- Report memuat jumlah trade yang jauh melebihi kapasitas bar per tahun (mis. 3715 trade x 144 bar),
  artinya posisi overlap. Default `InpMaxPositions = 0` (tanpa batas) meniru itu.
  Set ke 1 kalau mau satu posisi saja. Di akun netting otomatis dipaksa 1.
- `InpRestrictToWindow` (default off) membatasi pembukaan posisi ke tahun test window.
- `mom_10` dari `iMomentum` bernilai sekitar 100, jadi filter `mom_10 > -5` selalu true.
  Tetap dimasukkan di w0003 agar sama persis dengan kondisi di report.
