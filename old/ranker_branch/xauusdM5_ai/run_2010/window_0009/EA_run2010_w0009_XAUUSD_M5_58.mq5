//+------------------------------------------------------------------+
//| EA_run2010_w0009_XAUUSD_M5_58.mq5
//| Walk-forward window : run_2010 / window_0009
//| Train               : 2019-01-01 .. 2021-12-31 (nominal)
//| Test                : 2022-01-01 .. 2022-12-31 (nominal)
//| Edge                : XAUUSD_M5_58  (long only)
//| Condition           : cci_14 < -100.0 AND ps_dist_sess_l_atr > -1.0 AND volregime_atr_pctl < 30.0
//| Holding             : 139 bars (close after N candles)
//| Report (test)       : expectancy_r=1.4948  PF=1.21  n_trades=839
//| No broker SL / TP. Entry on new bar, signal from last closed bar.
//+------------------------------------------------------------------+
#property copyright "Walk-Forward EA"
#property version   "1.00"
#property strict
#property description "run_2010 / window_0009 - XAUUSD_M5_58"
#property description "Long only, exit after fixed number of bars, no SL/TP"
#property tester_indicator "VolRegime_ATR.ex5"
#property tester_indicator "PriceStructure.ex5"

#include <Trade\Trade.mqh>

//--- custom indicator names (add folder prefix if they live in a sub-folder)
#define IND_VOLREGIME   "VolRegime_ATR"
#define IND_PRICESTRUCT "PriceStructure"

//--- inputs
input group "=== Trade ==="
input double InpLots         = 0.01;       // Lot size (fixed)
input int    InpHoldingBars  = 139;   // Close after N bars (from report)
input int    InpMaxPositions = 150;        // Max concurrent positions (hedging only)
input int    InpDeviation    = 30;         // Max deviation (points)
input long   InpMagic        = 9000009;  // Magic number (unique per window)
input string InpComment      = "XAUUSD_M5_58"; // Order comment

//--- globals
CTrade   g_trade;
datetime g_last_bar = 0;
int      g_max_pos  = 1;
double   g_close    = 0.0;

//--- indicator handles / values (bar shift 1 = last closed bar)
int    h_cci_14 = INVALID_HANDLE;
double v_cci_14 = 0.0;
int    h_ps_dist_sess_l_atr = INVALID_HANDLE;
double v_ps_dist_sess_l_atr = 0.0;
int    h_volregime_atr_pctl = INVALID_HANDLE;
double v_volregime_atr_pctl = 0.0;

//+------------------------------------------------------------------+
//| Read one value from an indicator buffer at shift 1                |
//+------------------------------------------------------------------+
bool GetBuf(const int handle, const int buffer, double &value)
{
   if(handle == INVALID_HANDLE) return false;
   double a[1];
   if(CopyBuffer(handle, buffer, 1, 1, a) <= 0) return false;
   value = a[0];
   if(!MathIsValidNumber(value) || value == EMPTY_VALUE || MathAbs(value) >= 1.0e300) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Load every value needed by the condition                          |
//+------------------------------------------------------------------+
bool LoadValues()
{
   g_close = iClose(_Symbol, _Period, 1);
   if(g_close <= 0.0) return false;
   if(!GetBuf(h_cci_14, 0, v_cci_14)) return false;
   if(!GetBuf(h_ps_dist_sess_l_atr, 3, v_ps_dist_sess_l_atr)) return false;
   if(!GetBuf(h_volregime_atr_pctl, 0, v_volregime_atr_pctl)) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Entry condition (from report): cci_14 < -100.0 AND ps_dist_sess_l_atr > -1.0 AND volregime_atr_pctl < 30.0
//+------------------------------------------------------------------+
bool SignalLong()
{
   if(!LoadValues()) return false;
   return ( v_cci_14 < -100.0
      && v_ps_dist_sess_l_atr > -1.0
      && v_volregime_atr_pctl < 30.0 );
}

//+------------------------------------------------------------------+
//| Position helpers                                                  |
//+------------------------------------------------------------------+
int CountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      n++;
   }
   return n;
}

// Close every position that has been open for >= InpHoldingBars bars
void CloseExpiredPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int shift = iBarShift(_Symbol, _Period, opened, false);
      if(shift < 0) continue;
      if(shift >= InpHoldingBars)
      {
         if(!g_trade.PositionClose(ticket))
            PrintFormat("Close failed #%I64u retcode=%d (%s)", ticket,
                        g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   h_cci_14 = iCCI(_Symbol,_Period,14,PRICE_TYPICAL);
   if(h_cci_14 == INVALID_HANDLE) { Print("Failed to create indicator: cci_14"); return INIT_FAILED; }
   h_ps_dist_sess_l_atr = iCustom(_Symbol,_Period,IND_PRICESTRUCT);
   if(h_ps_dist_sess_l_atr == INVALID_HANDLE) { Print("Failed to create indicator: ps_dist_sess_l_atr"); return INIT_FAILED; }
   h_volregime_atr_pctl = iCustom(_Symbol,_Period,IND_VOLREGIME);
   if(h_volregime_atr_pctl == INVALID_HANDLE) { Print("Failed to create indicator: volregime_atr_pctl"); return INIT_FAILED; }

   ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_max_pos = InpMaxPositions;
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && g_max_pos > 1)
   {
      Print("WARNING: non-hedging account -> max concurrent positions forced to 1.");
      g_max_pos = 1;
   }
   if(g_max_pos < 1) g_max_pos = 1;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   PrintFormat("EA_run2010_w0009_XAUUSD_M5_58 ready | %s %s | hold=%d bars | max positions=%d",
               _Symbol, EnumToString(_Period), InpHoldingBars, g_max_pos);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_cci_14 != INVALID_HANDLE) IndicatorRelease(h_cci_14);
   if(h_ps_dist_sess_l_atr != INVALID_HANDLE) IndicatorRelease(h_ps_dist_sess_l_atr);
   if(h_volregime_atr_pctl != INVALID_HANDLE) IndicatorRelease(h_volregime_atr_pctl);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // --- new bar gate (same approach as DataExporter OnTick)
   datetime bar_time = iTime(_Symbol, _Period, 0);
   if(bar_time == 0 || bar_time == g_last_bar) return;
   g_last_bar = bar_time;

   // 1) exits first: close positions older than N bars
   CloseExpiredPositions();

   // 2) entry: signal evaluated on the last closed bar, enter at new bar open
   if(CountPositions() >= g_max_pos) return;
   if(!SignalLong()) return;

   // no SL, no TP (both 0)
   if(!g_trade.Buy(InpLots, _Symbol, 0.0, 0.0, 0.0, InpComment))
      PrintFormat("Buy failed retcode=%d (%s)", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
}
//+------------------------------------------------------------------+
