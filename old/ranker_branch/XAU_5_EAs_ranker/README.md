# 5 EA terpisah (MQL5, tanpa library, fixed lot)

Taruh semua `.mq5` di `MQL5\Experts`, compile (F7), pasang di chart **XAUUSD M5**. Satu EA = satu edge, magic number berbeda, jadi bisa jalan bersamaan.

| File | Kondisi (long) | Tutup setelah | Magic |
|---|---|---|---|
| XAU_Edge1_RSI21_SMA5 | rsi_21<25 AND ma_5_sma>close AND mom_10>-5 | 116 candle | 20260101 |
| XAU_Edge2_RSI21 | rsi_21<25 AND mom_10>-5 | 116 candle | 20260102 |
| XAU_Edge3_RSI14 | rsi_14<25 | 54 candle | 20260103 |
| XAU_Edge4_Stoch_SMMA5 | stoch_5_3_3_k<20 AND ma_5_smma>close AND ps_dist_sess_l_atr>0.5 AND volregime_atr_ratio<0.8 | 144 candle | 20260104 |
| XAU_Edge5_Stoch_EMA10 | stoch_5_3_3_k<20 AND ma_10_ema>close AND ps_dist_sess_l_atr>0.5 AND volregime_atr_ratio<0.8 | 144 candle | 20260105 |

- Exit: tutup posisi setelah X candle (`InpHoldBars`). Fixed lot `InpLot` (default 0.01).
- SL tidak ada di report; `InpSLAtrMult` default 0 (tanpa SL). Isi jika mau SL darurat.
- Edge 4 & 5 butuh `VolRegime_ATR.ex5` dan `PriceStructure.ex5`; di tester hapus `//` pada 2 baris `#property tester_indicator`.
- Filter mom_10 di MT5 (~100) selalu lolos; dibiarkan agar sama dengan report.
