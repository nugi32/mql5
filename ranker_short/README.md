# MQL5 EAs dari Python pipeline ranker reports

Satu EA mandiri per baris kombinasi di report, per pair dan timeframe. Hanya terjemahan: tidak ada filter, pemilihan, atau optimasi aturan. Total: **50 EA** (XAUUSD 25, EURUSD 25; 5 EA per folder timeframe).

Nama file: `<PAIR>_<TF>_R<n>.mq5`, dengan `n` = nomor baris (#) di report timeframe tersebut.

**Status kompilasi:** MetaEditor tidak tersedia saat file dibuat, jadi EA **belum dikompilasi maupun di-backtest**. Kode hanya diperiksa lewat review (keseimbangan kurung, signature disamakan dengan loader). Mohon kompilasi sekali dan laporkan pesan error jika ada.

```
MQL5_EAs/
|-- XAUUSD/ {M1,M5,M15,M30,H1}/XAUUSD_<TF>_R1..R5.mq5
|-- EURUSD/ {M1,M5,M15,M30,H1}/EURUSD_<TF>_R1..R5.mq5
`-- README.md
```

## Desain umum (sama di semua EA)

| Topik | Implementasi |
|---|---|
| Bar baru | `IsNewBar()` membandingkan `iTime(_Symbol, tf, 0)` dengan bar terakhir (sama seperti `OnTick` loader). Semua proses (exit, baca indikator, entry) jalan sekali per bar baru. |
| Shift candle | Semua indikator dan `close` dibaca di **shift 1** (bar yang baru close), sama dengan `WriteBarToCSVLive()` di loader. |
| Presisi nilai | Nilai dibulatkan seperti CSV loader: 6 desimal; `volregime_regime` 0 desimal. |
| Data kosong | Indikator belum siap / NaN / `EMPTY_VALUE` (custom) => kondisi false => tidak ada sinyal. |
| Arah | Tetap per EA sesuai kolom Dir report (`long` = buy di ask, `short` = sell di bid). |
| Exit | Hanya time exit: posisi ditutup setelah ditahan `Hold` bar. |
| Order | `OrderSend` native, tanpa include. Filling mode dipilih dari simbol. |
| Resource | Hanya handle yang dibutuhkan aturan EA itu yang dibuat; dilepas di `OnDeinit`. |

Input yang tidak ada di report: `InpLots` (0.10), `InpMagic` (unik per EA), `InpDeviation`, `InpAllowOverlap` (false), `InpComment`.

## Mapping indikator (disalin dari `DataExporter.mq5`)

| Kolom | Panggilan MQL5 | Buffer |
|---|---|---|
| `close` | `iClose(.., 1)` | - |
| `mom_10` | `iMomentum(10, PRICE_CLOSE)` | 0 |
| `rsi_7 / rsi_14 / rsi_21` | `iRSI(n, PRICE_CLOSE)` | 0 |
| `ma_N_sma/ema/smma/lwma` | `iMA(N, 0, MODE_x, PRICE_CLOSE)` | 0 |
| `stoch_5_3_3_k`, `stoch_14_3_3_k` | `iStochastic(5|14, 3, 3, MODE_SMA, STO_LOWHIGH)` | 0 |
| `cci_14` | `iCCI(14, PRICE_TYPICAL)` | 0 |
| `volregime_atr_pctl / atr_ratio / regime` | `iCustom("VolRegime_ATR")`, input default | 0 / 5 / 6 |
| `ps_dist_pdh / sess_h / sess_l / round_up _atr`, `ps_gap_atr` | `iCustom("PriceStructure")`, input default | 0 / 2 / 3 / 4 / 6 |

`VolRegime_ATR.ex5` dan `PriceStructure.ex5` harus ada di `MQL5\Indicators` (lokasi sama seperti saat loader dijalankan). Jika ada di sub-folder, ubah baris `#property tester_indicator` dan `#define CUSTOM_IND_*` di EA. Nomor buffer diambil dari komentar loader karena source indikator tidak diberikan. EA yang tidak memakai indikator custom (mis. XAUUSD M5) tidak membutuhkannya.

## XAUUSD

### XAUUSD M1 - long

| File | Aturan | Hold (bar) |
|---|---|---|
| `XAUUSD_M1_R1.mq5` | `ps_dist_round_up_atr < 0.5 AND volregime_atr_pctl < 30.0` | 210 |
| `XAUUSD_M1_R2.mq5` | `ps_dist_round_up_atr < 0.5 AND volregime_regime == 0.0` | 210 |
| `XAUUSD_M1_R3.mq5` | `ps_dist_round_up_atr < 0.5 AND volregime_atr_pctl < 30.0 AND mom_10 > -5.0` | 210 |
| `XAUUSD_M1_R4.mq5` | `ps_dist_round_up_atr < 0.5 AND volregime_atr_pctl < 30.0 AND mom_10 > 0.0` | 210 |
| `XAUUSD_M1_R5.mq5` | `ps_dist_round_up_atr < 0.5 AND volregime_regime == 0.0 AND mom_10 > -5.0` | 210 |

### XAUUSD M5 - long

| File | Aturan | Hold (bar) |
|---|---|---|
| `XAUUSD_M5_R1.mq5` | `rsi_21 < 25.0 AND ma_5_sma > close AND mom_10 > -5.0` | 116 |
| `XAUUSD_M5_R2.mq5` | `rsi_21 < 25.0 AND ma_5_sma > close AND mom_10 > 0.0` | 116 |
| `XAUUSD_M5_R3.mq5` | `rsi_21 < 25.0 AND mom_10 > -5.0` | 116 |
| `XAUUSD_M5_R4.mq5` | `rsi_21 < 25.0 AND mom_10 > 0.0` | 116 |
| `XAUUSD_M5_R5.mq5` | `rsi_14 < 25.0` | 54 |

### XAUUSD M15 - long

| File | Aturan | Hold (bar) |
|---|---|---|
| `XAUUSD_M15_R1.mq5` | `ma_5_lwma > close AND volregime_atr_pctl < 20.0` | 48 |
| `XAUUSD_M15_R2.mq5` | `ma_5_lwma > close AND volregime_atr_pctl < 20.0 AND mom_10 > -5.0` | 48 |
| `XAUUSD_M15_R3.mq5` | `ma_5_lwma > close AND volregime_atr_pctl < 20.0 AND mom_10 > 0.0` | 48 |
| `XAUUSD_M15_R4.mq5` | `stoch_5_3_3_k < 20.0 AND volregime_atr_pctl > 80.0 AND rsi_7 < 30.0` | 34 |
| `XAUUSD_M15_R5.mq5` | `stoch_5_3_3_k < 20.0 AND ma_5_ema > close AND volregime_atr_pctl > 80.0 AND rsi_7 < 30.0` | 34 |

### XAUUSD M30 - long

| File | Aturan | Hold (bar) |
|---|---|---|
| `XAUUSD_M30_R1.mq5` | `stoch_5_3_3_k < 20.0 AND volregime_atr_pctl > 70.0 AND rsi_7 < 20.0` | 15 |
| `XAUUSD_M30_R2.mq5` | `stoch_5_3_3_k < 20.0 AND volregime_atr_pctl > 70.0 AND mom_10 > -5.0 AND rsi_7 < 20.0` | 15 |
| `XAUUSD_M30_R3.mq5` | `stoch_5_3_3_k < 20.0 AND volregime_atr_pctl > 70.0 AND mom_10 > 0.0 AND rsi_7 < 20.0` | 15 |
| `XAUUSD_M30_R4.mq5` | `stoch_5_3_3_k < 20.0 AND volregime_atr_pctl > 80.0 AND rsi_7 < 20.0` | 23 |
| `XAUUSD_M30_R5.mq5` | `stoch_5_3_3_k < 20.0 AND volregime_atr_pctl > 80.0 AND mom_10 > -5.0 AND rsi_7 < 20.0` | 23 |

### XAUUSD H1 - long

| File | Aturan | Hold (bar) |
|---|---|---|
| `XAUUSD_H1_R1.mq5` | `rsi_14 < 25.0 AND stoch_14_3_3_k < 20.0 AND volregime_atr_pctl > 80.0` | 12 |
| `XAUUSD_H1_R2.mq5` | `rsi_14 < 25.0 AND stoch_14_3_3_k < 20.0 AND volregime_atr_pctl > 80.0 AND mom_10 > -5.0` | 12 |
| `XAUUSD_H1_R3.mq5` | `rsi_14 < 25.0 AND stoch_14_3_3_k < 20.0 AND volregime_atr_pctl > 80.0 AND mom_10 > 0.0` | 12 |
| `XAUUSD_H1_R4.mq5` | `rsi_14 < 25.0 AND stoch_14_3_3_k < 20.0 AND volregime_atr_pctl > 80.0 AND cci_14 < -50.0` | 12 |
| `XAUUSD_H1_R5.mq5` | `rsi_14 < 25.0 AND stoch_14_3_3_k < 20.0 AND volregime_atr_pctl > 80.0 AND ma_10_sma > close` | 12 |

## EURUSD

### EURUSD M1 - long

| File | Aturan | Hold (bar) |
|---|---|---|
| `EURUSD_M1_R1.mq5` | `rsi_21 < 20.0 AND cci_14 < -100.0 AND ps_dist_sess_l_atr > 0.5 AND volregime_atr_pctl > 70.0` | 665 |
| `EURUSD_M1_R2.mq5` | `rsi_21 < 20.0 AND cci_14 < -100.0 AND ps_dist_sess_l_atr > 0.5 AND volregime_atr_pctl > 70.0 AND ma_20_smma > close` | 665 |
| `EURUSD_M1_R3.mq5` | `rsi_21 < 20.0 AND cci_14 < -100.0 AND ps_dist_sess_l_atr > 0.5 AND volregime_atr_pctl > 70.0 AND ma_20_ema > close` | 665 |
| `EURUSD_M1_R4.mq5` | `rsi_21 < 20.0 AND cci_14 < -100.0 AND ps_dist_sess_l_atr > 0.5 AND volregime_atr_pctl > 70.0 AND mom_10 > -5.0` | 665 |
| `EURUSD_M1_R5.mq5` | `rsi_21 < 20.0 AND cci_14 < -100.0 AND ps_dist_sess_l_atr > 0.5 AND volregime_atr_pctl > 70.0 AND mom_10 > 0.0` | 665 |

### EURUSD M5 - short

| File | Aturan | Hold (bar) |
|---|---|---|
| `EURUSD_M5_R1.mq5` | `rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0` | 88 |
| `EURUSD_M5_R2.mq5` | `rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND ma_10_smma < close AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0` | 88 |
| `EURUSD_M5_R3.mq5` | `rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0 AND mom_10 > -5.0` | 88 |
| `EURUSD_M5_R4.mq5` | `rsi_14 > 75.0 AND stoch_14_3_3_k > 80.0 AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0 AND mom_10 > 0.0` | 88 |
| `EURUSD_M5_R5.mq5` | `rsi_14 > 75.0 AND ps_dist_sess_h_atr < -2.0 AND volregime_regime == 1.0 AND mom_10 > -5.0` | 89 |

### EURUSD M15 - short

| File | Aturan | Hold (bar) |
|---|---|---|
| `EURUSD_M15_R1.mq5` | `stoch_5_3_3_k > 80.0 AND volregime_atr_ratio < 0.8 AND rsi_7 > 75.0` | 48 |
| `EURUSD_M15_R2.mq5` | `stoch_5_3_3_k > 80.0 AND ma_5_ema < close AND volregime_atr_ratio < 0.8 AND rsi_7 > 75.0` | 48 |
| `EURUSD_M15_R3.mq5` | `rsi_7 > 80.0 AND volregime_atr_pctl < 20.0` | 47 |
| `EURUSD_M15_R4.mq5` | `rsi_7 > 80.0 AND ma_5_ema < close AND volregime_atr_pctl < 20.0` | 47 |
| `EURUSD_M15_R5.mq5` | `rsi_7 > 80.0 AND ma_5_smma < close AND volregime_atr_pctl < 20.0` | 47 |

### EURUSD M30 - short

| File | Aturan | Hold (bar) |
|---|---|---|
| `EURUSD_M30_R1.mq5` | `volregime_atr_ratio < 1.0 AND rsi_7 > 75.0` | 13 |
| `EURUSD_M30_R2.mq5` | `volregime_atr_ratio < 1.0 AND mom_10 > -5.0 AND rsi_7 > 75.0` | 13 |
| `EURUSD_M30_R3.mq5` | `volregime_atr_ratio < 1.0 AND mom_10 > 0.0 AND rsi_7 > 75.0` | 13 |
| `EURUSD_M30_R4.mq5` | `ps_dist_pdh_atr < -0.5 AND stoch_5_3_3_k > 80.0 AND cci_14 > 100.0` | 24 |
| `EURUSD_M30_R5.mq5` | `ps_dist_pdh_atr < -0.5 AND stoch_5_3_3_k > 80.0 AND cci_14 > 100.0 AND ma_10_smma < close` | 24 |

### EURUSD H1 - short

| File | Aturan | Hold (bar) |
|---|---|---|
| `EURUSD_H1_R1.mq5` | `volregime_atr_pctl < 20.0 AND stoch_14_3_3_k > 80.0 AND cci_14 > 100.0` | 8 |
| `EURUSD_H1_R2.mq5` | `volregime_atr_pctl < 20.0 AND stoch_14_3_3_k > 80.0 AND cci_14 > 100.0 AND mom_10 > -5.0` | 8 |
| `EURUSD_H1_R3.mq5` | `volregime_atr_pctl < 20.0 AND stoch_14_3_3_k > 80.0 AND cci_14 > 100.0 AND mom_10 > 0.0` | 8 |
| `EURUSD_H1_R4.mq5` | `ps_gap_atr > 1.0 AND cci_14 > 100.0` | 12 |
| `EURUSD_H1_R5.mq5` | `ps_gap_atr > 1.0 AND cci_14 > 100.0 AND mom_10 > -5.0` | 12 |

## Catatan dari report

- XAUUSD: semua baris M1/M5/M30/H1 `no_plateau`. M15 R1-R3: `low_pf, no_plateau, few_windows` (0/12 window). M30 R1-R5 stabilitas rendah (0.11-0.21).
- EURUSD: hanya M1 R1-R5 (plateau 1.00, 10/10 window) dan M30 R1-R3 (plateau 0.89, stab 0.94) tanpa warning. **EURUSD H1 R4-R5 hanya 12 trade, 0/2 window** (PF 10.00 tidak bermakna).
- Baris yang statistiknya identik dengan baris lain di report (mis. yang hanya menambah `mom_10 > -5.0` / `> 0.0`) tetap dibuat sebagai EA terpisah sesuai permintaan.

## Asumsi / hal yang belum jelas (tidak ditentukan report)

1. **Satuan Hold** - dianggap **bar** dari timeframe EA. Posisi ditutup pada bar baru pertama saat sudah ditahan >= Hold bar (hitungan dari series, akhir pekan/gap tidak dihitung).
2. **Waktu entry** - sinyal dievaluasi pada bar closed (shift 1), order market dikirim pada open bar berikutnya (~ close bar sinyal). Konvensi harga entry/exit pipeline tidak disebut report.
3. **Tanpa SL/TP** - "Exp R" mengimplikasikan definisi R, tetapi aturan stop/target tidak diberikan, jadi tidak diimplementasikan. Tambahkan manajemen risiko sendiri sebelum live.
4. **Sinyal overlap** - report tidak menyebut apakah sinyal saat posisi terbuka dihitung. Default: satu posisi sekali waktu. `InpAllowOverlap = true` membuka satu posisi per sinyal (masing-masing time exit sendiri), hanya untuk akun hedging; otomatis dimatikan dengan warning jika bukan hedging.
5. **Short** - jual di bid, tutup dengan buy di ask. Spread/swap/komisi tidak dimodelkan report.
6. **Lot / slippage / magic** - nilai default sembarang, bukan dari report.
7. **`mom_10`** - `iMomentum` MT5 berupa rasio sekitar 100, jadi `mom_10 > -5.0` dan `> 0.0` praktis selalu true; konsisten dengan statistik identik di report. Tetap diimplementasikan apa adanya.
8. **XAUUSD M1 R1 vs R2** - statistik identik, konsisten jika `volregime_atr_pctl < 30` ekuivalen dengan `volregime_regime == 0` di indikator (tidak bisa diverifikasi tanpa source indikator).
9. **Timeframe/simbol** - EA menolak jalan di timeframe yang berbeda; hanya memberi warning jika nama simbol tidak mengandung simbol report (akhiran broker boleh).

## Pemakaian
Salin `.mq5` ke `MQL5\Experts`, kompilasi, pasang di chart pair/timeframe yang sesuai atau jalankan di Strategy Tester.
