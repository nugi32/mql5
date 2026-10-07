# eurusdM15 – Walk-Forward Edge EAs

43 EA (1 EA per window yang punya accepted edge), semuanya **EURUSD M15, SHORT only**.

## Struktur

```
eurusdM15/
├── Include/EdgeCore.mqh     # helper bersama (IsNewBar, GetBuf, close-after-N-bars)
├── run_2010/ ... run_2021/  # 1 file .mq5 per window
├── summary.csv              # daftar semua EA + kondisi + statistik test
└── README.md
```

## Instalasi

1. Copy folder `eurusdM15` ke `MQL5/Experts/`.
2. Compile file `.mq5` yang dipakai di MetaEditor (`Include/EdgeCore.mqh` ter-include otomatis lewat path relatif, jadi struktur folder jangan diubah).
3. Strategy Tester: EURUSD, M15, jalankan di **periode test (OOS)** yang tertulis di header tiap file.

## Logika EA

- Cek `IsNewBar()` di `OnTick` (sama dengan exporter).
- Indikator dibaca di **bar yang sudah close (shift 1)**, sama seperti `WriteBarToCSVLive` di exporter. Definisi indikator mengikuti kode MQL5 exporter (RSI/Mom `PRICE_CLOSE`, CCI `PRICE_TYPICAL`, Stochastic `SMA, STO_LOWHIGH` buffer 0 = %K).
- Kondisi terpenuhi → **SELL** market di open bar baru.
- Exit: **tutup setelah `holding_bars` bar** sesuai report. **Tidak ada SL/TP** yang dikirim ke broker.
- Posisi bertumpuk (overlap) diizinkan secara default karena jumlah trade di report (mis. 1080 trade × 47 bar) tidak mungkin tanpa overlap. Ini butuh akun **HEDGING**; di akun netting EA otomatis jadi maks 1 posisi. Atur lewat `InpAllowOverlap` / `InpMaxPositions`.

## Cara memilih 1 edge per window (plateau, bukan spike)

1. Edge dengan statistik identik dikelompokkan jadi satu cluster (varian filter tambahan yang tidak mengubah hasil = plateau yang lebar).
2. Cluster difilter: `n_trades >= 100` dan `PF >= 1.15`.
3. Ranking pakai `expectancy_r × √n_trades` – ini menghukum hasil runcing (PF tinggi tapi trade sedikit, contoh `rsi_14>80 AND cci_20>100` dengan 89 trade / PF 3.52 sengaja tidak dipilih).
4. Dari cluster terbaik dipilih kondisi **paling sederhana**; untuk filter `mom_10` dipilih nilai tengah (`> 0.0`).

| Test year | Condition | Hold | E(R) | PF | n |
|---|---|---:|---:|---:|---:|
| 2013 | `rsi_14 > 70` | 47 | 0.0135 | 1.04 | 1080 |
| 2015 | `rsi_14 > 70 AND stoch_14_3_3_k > 80` | 48 | 0.6144 | 1.33 | 830 |
| 2016 | `rsi_14 > 75 AND stoch_14_3_3_k > 80 AND cci_14 > 100` | 48 | 0.4726 | 1.27 | 301 |
| 2018 | `rsi_7 > 80` | 37 | 0.6798 | 1.49 | 730 |
| 2019 | `rsi_14 > 80 AND mom_10 > 0` | 18 | 0.2909 | 1.30 | 105 |
| 2022 | `rsi_14 > 70 AND cci_20 > 100 AND stoch_5_3_3_k > 80 AND mom_10 > 0` | 39 | 0.5335 | 1.44 | 681 |
| 2024 | `rsi_7 > 75 AND stoch_5_3_3_k > 80` | 48 | 0.3459 | 1.29 | 1209 |

## Catatan penting

- **`mom_10` tidak berfungsi sebagai filter.** Di report, `mom_10 > -5`, `> 0`, dan `> 5` menghasilkan jumlah trade identik. `iMomentum` di MT5 bernilai sekitar 100 (rasio), jadi kondisi itu selalu benar. Tetap dipertahankan agar sama persis dengan report; efektifnya kondisi = bagian lainnya.
- **Window test 2013 (n=1080, PF 1.04) dan 2019 (n=105)** lemah/tipis; hanya satu-satunya opsi di window tersebut.
- Banyak window dari run berbeda memakai edge yang **sama persis** (karena periode test sama). File tetap dibuat per window sesuai permintaan; magic number unik per file.
- Window tanpa accepted edge (tidak dibuat EA):
- run_2010 / window_0001 (test 2014)
- run_2010 / window_0004 (test 2017)
- run_2010 / window_0007 (test 2020)
- run_2010 / window_0008 (test 2021)
- run_2010 / window_0010 (test 2023)
- run_2010 / window_0012 (test 2025)
- run_2011 / window_0000 (test 2014)
- run_2011 / window_0003 (test 2017)
- run_2011 / window_0006 (test 2020)
- run_2011 / window_0007 (test 2021)
- run_2011 / window_0009 (test 2023)
- run_2011 / window_0011 (test 2025)
- run_2012 / window_0002 (test 2017)
- run_2012 / window_0005 (test 2020)
- run_2012 / window_0006 (test 2021)
- run_2012 / window_0008 (test 2023)
- run_2012 / window_0010 (test 2025)
- run_2013 / window_0001 (test 2017)
- run_2013 / window_0004 (test 2020)
- run_2013 / window_0005 (test 2021)
- run_2013 / window_0007 (test 2023)
- run_2013 / window_0009 (test 2025)
- run_2014 / window_0000 (test 2017)
- run_2014 / window_0003 (test 2020)
- run_2014 / window_0004 (test 2021)
- run_2014 / window_0006 (test 2023)
- run_2014 / window_0008 (test 2025)
- run_2015 / window_0002 (test 2020)
- run_2015 / window_0003 (test 2021)
- run_2015 / window_0005 (test 2023)
- run_2015 / window_0007 (test 2025)
- run_2016 / window_0001 (test 2020)
- run_2016 / window_0002 (test 2021)
- run_2016 / window_0004 (test 2023)
- run_2016 / window_0006 (test 2025)
- run_2017 / window_0000 (test 2020)
- run_2017 / window_0001 (test 2021)
- run_2017 / window_0003 (test 2023)
- run_2017 / window_0005 (test 2025)
- run_2018 / window_0000 (test 2021)
- run_2018 / window_0002 (test 2023)
- run_2018 / window_0004 (test 2025)
- run_2019 / window_0001 (test 2023)
- run_2019 / window_0003 (test 2025)
- run_2020 / window_0000 (test 2023)
- run_2020 / window_0002 (test 2025)
- run_2021 / window_0001 (test 2025)
- EA belum saya compile di MetaEditor (tidak ada MT5 di environment ini). Jika ada error compile, kirim pesan errornya.
