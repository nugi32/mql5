# Seleksi Edge per Window

## Metode pemilihan (plateau, bukan spike)

Di setiap window, edge yang diterima membentuk beberapa **klaster** dengan metrik test identik
(variasi filter `mom_10` / `ma_*` tidak mengubah hasil sama sekali). Aturan pemilihan:

1. Klaster dengan **anggota paling banyak** = plateau paling lebar (hasil stabil terhadap variasi parameter).
2. Jika seri, pilih **expectancy_r test tertinggi**.
3. Dalam klaster terpilih, ambil edge dengan **kondisi paling sederhana** (jumlah kondisi paling sedikit).

Klaster sempit dengan angka lebih tinggi dianggap *spike* dan dibuang.

## Hasil

| Test year | Edge terpilih | Kondisi | Hold (bar) | Exp R | PF | Trades | Ukuran plateau |
|---|---|---|---:|---:|---:|---:|---:|
| 2015 | EURUSD_M5_2   | `stoch_14_3_3_k < 20 AND ma_10_ema < close` | 122 | 1.4739 | 1.19 | 272 | 4 (seluruh window) |
| 2016 | EURUSD_M5_121 | `rsi_14 > 75 AND stoch_14_3_3_k > 80 AND mom_10 > -5` | 138 | 0.8530 | 1.42 | 786 | 9 |
| 2018 | EURUSD_M5_6   | `rsi_14 > 75 AND stoch_5_3_3_k > 80` | 114 | 0.7807 | 1.42 | 630 | 8 |

## Yang ditolak

**2016**
- `rsi_14>75 & stoch_14>80 & cci_14>100` (M5_118/241): Exp 1.1084, PF 1.53, tapi hanya 2 anggota -> spike.
- `rsi_21>70 & stoch_14>80 & mom_10...` (M5_145 dst): Exp 0.8477, PF 1.44, 906 trades, 9 anggota -> plateau setara, kalah tipis di expectancy. Alternatif terdekat.

**2018**
- `rsi_14>75 & cci_14>100 & stoch_5>80` (M5_23 dst): 8 anggota tapi Exp 0.7443 < 0.7807.
- `rsi_21>70 & cci_20>100 & stoch_5>80` (M5_39 dst): Exp 0.8434, PF 1.48, hanya 4 anggota -> terlalu sempit.

## Window -> EA

Run berbeda memakai periode train/test yang sama, jadi 13 window hanya berisi **3 strategi unik**
(hasil di report identik). Lihat `windows_index.csv` untuk pemetaan lengkap.
