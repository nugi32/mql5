5 EA MQL5 (EURUSD M30, SHORT only, close after N candles, tanpa SL/TP, tanpa custom indicator/library)
Pasang di MQL5\Experts, compile, jalankan di Strategy Tester / chart M30.

01 : ps_dist_sess_h_atr<-1 AND volregime_atr_ratio<1                 hold 19  (EURUSD_M30_46)
02 : #01 + mom_10>-5                                                 hold 19  (EURUSD_M30_117)
03 : #01 + mom_10>0                                                  hold 19  (EURUSD_M30_118)
04 : rsi_7>75 AND ma_5_ema<close AND volregime_atr_ratio<1           hold 14  (EURUSD_M30_96)
05 : #04 + mom_10>-5                                                 hold 14  (EURUSD_M30_196)

CATATAN: volregime_atr_ratio & ps_dist_sess_h_atr dihitung ulang inline (source indikator
VolRegime_ATR / PriceStructure tidak ada), jadi parameter default adalah ASUMSI:
  ATR=14, SMA(ATR)=50, session=8 jam (offset 0, waktu server).
Sesuaikan input agar sama dengan indikator aslimu.
mom_10 (iMomentum) skala ~100, sehingga mom_10>-5 / >0 selalu true (sama seperti di report: hasil #1=#2=#3).

PERUBAHAN (v2): InpATRMAPeriod default 50 -> 20, sama dengan InpMAPeriod di mql5/volRegime.mq5
(yang dipakai dataExporter lewat iCustom dengan input default). Belum dikompilasi di MetaEditor.
Hold bars di nama file (19/14) berasal dari run lama; run EURUSD_M30_p83668 memilih 14 untuk kondisi SessH+Vol.
EA ini membuka posisi baru di tick yang sama dengan penutupan posisi lama (ManageExit lalu TryEntry),
jadi di config/MT5_TESTER/EURUSD/M30.yaml set reenter_on_exit_bar: true.
