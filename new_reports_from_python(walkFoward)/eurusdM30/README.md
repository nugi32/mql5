# eurusdM30 - Walk-forward edge EAs (EURUSD M30)

21 EAs, one per window that has an accepted edge in the report.
Windows with 0 accepted edges (69 of 90) have no EA.

## Install
Copy the `MQL5` folder in this zip into your MT5 data folder
(File > Open Data Folder), merging with the existing MQL5 folder. Then compile in MetaEditor.

    MQL5/
      Include/eurusdM30/EdgeCore.mqh            <- shared engine
      Experts/eurusdM30/run_YYYY/EURUSD_M30_runYYYY_wNNNN.mq5

## Behaviour (all EAs)
- Chart: EURUSD, M30 only (init fails otherwise)
- Logic runs only on a new bar (IsNewBar, same pattern as DataExporter.mq5 OnTick)
- Signal is read from the last CLOSED bar (shift 1), same as DataExporter exports
- Entry: market SELL on first tick of the new bar. SL = 0, TP = 0 (no broker SL/TP)
- Exit: closed by the EA once the position is >= hold bars old (23 or 24, from report)
- One position at a time (InpAllowOverlap=false). Optional overlap on hedging accounts only
- Indicator parameters identical to DataExporter.mq5

## Inputs
InpLots, InpDeviation, InpMagic (unique per EA), InpHoldBars (default = report), InpAllowOverlap

## Unique strategies
| test year | edge | condition | hold | OOS exp_r | PF | trades |
|---|---|---|---|---|---|---|
| 2014 | EURUSD_M30_1  | rsi_14 > 70 | 23 | 0.8977 | 1.71 | 438 |
| 2015 | EURUSD_M30_71 | rsi_7 > 80 AND stoch_5_3_3_k > 80 AND mom_10 > 0 | 24 | 0.7101 | 1.72 | 272 |
| 2016 | EURUSD_M30_2  | rsi_7 > 75 | 24 | 0.2647 | 1.30 | 783 |
| 2024 | EURUSD_M30_95 | rsi_7 > 70 AND stoch_5_3_3_k > 80 AND ma_5_sma < close AND mom_10 > 0 | 24 | 0.3048 | 1.31 | 979 |

Windows with the same test year are identical (overlapping runs), so there are only 4 distinct
strategies. See manifest.csv for the full window -> EA mapping.

## Notes
- All short, mean-reversion on overbought. Test with the same broker/data as the exported CSV;
  spread/commission differences matter a lot for expectancy this small.
- mom_10 in MT5 (iMomentum) oscillates around 100, so `mom_10 > -5/0/5` is always true:
  that clause is effectively a no-op. It is kept to match the report exactly.
