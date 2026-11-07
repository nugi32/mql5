//+------------------------------------------------------------------+
//| EA_Combo_7_8_10_20.mq5                                           |
//| Four research conditions in one EA (EURUSD M5).                  |
//| Indicator calls/buffers copied from DataExporter.mq5.            |
//| All values are read at shift 1 (last closed bar).                |
//| NOT COMPILED / NOT TESTED.                                       |
//+------------------------------------------------------------------+
#property copyright "EA_Combo"
#property version   "1.00"
#property strict
#property description "S7 : short | rsi_7>75 & stoch_5_3_3_k>70 & ps_dist_sess_h_atr<0.5 & volregime_atr_pctl<30"
#property description "S8 : short | rsi_7>75 & ps_dist_sess_h_atr<0.5 & volregime_atr_pctl<30"
#property description "S10: long  | cci_20<-100 & ma_20_lwma>close & ps_dist_sess_l_atr>-0.5 & volregime_atr_pctl<30"
#property description "S20: short | rsi_7>75 & stoch_5_3_3_k>80 & ps_dist_sess_h_atr<-2 & volregime_atr_pctl<30"

#property tester_indicator "VolRegime_ATR.ex5"
#property tester_indicator "PriceStructure.ex5"

#define CUSTOM_IND_VOLREGIME    "VolRegime_ATR"
#define CUSTOM_IND_PRICESTRUCT  "PriceStructure"

#include <Trade\Trade.mqh>

//--- General inputs
input group "=== General ==="
input double InpLots          = 0.1;          // Fixed lot size
input int    InpDeviation     = 20;           // Max deviation (points)
input long   InpMagicBase     = 770000;       // Magic base (strategy magic = base + strategy number)
input string InpComment       = "EA_Combo";   // Order comment prefix
input bool   InpOnePosPerStrat = true;        // true = max 1 open position per strategy; false = open on every new bar where signal is true

//--- Strategy 7
input group "=== Strategy 7 (short) ==="
input bool   InpUseS7         = true;         // Enable strategy 7
input int    InpHoldBarsS7    = 136;          // Hold bars S7

//--- Strategy 8
input group "=== Strategy 8 (short) ==="
input bool   InpUseS8         = true;         // Enable strategy 8
input int    InpHoldBarsS8    = 135;          // Hold bars S8

//--- Strategy 10
input group "=== Strategy 10 (long) ==="
input bool   InpUseS10        = true;         // Enable strategy 10
input int    InpHoldBarsS10   = 78;           // Hold bars S10

//--- Strategy 20
input group "=== Strategy 20 (short) ==="
input bool   InpUseS20        = true;         // Enable strategy 20
input int    InpHoldBarsS20   = 112;          // Hold bars S20

//--- Strategy table
#define NSTRAT 4
bool   g_enabled[NSTRAT];
bool   g_long[NSTRAT];
int    g_hold[NSTRAT];
long   g_magic[NSTRAT];
string g_name[NSTRAT];

//--- Indicator handles
int h_rsi7      = INVALID_HANDLE;
int h_stoch533  = INVALID_HANDLE;
int h_cci20     = INVALID_HANDLE;
int h_ma20lwma  = INVALID_HANDLE;
int h_volregime = INVALID_HANDLE;
int h_pricestruct = INVALID_HANDLE;

CTrade   g_trade;
datetime g_last_bar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if (_Symbol != "EURUSD" || _Period != PERIOD_M5)
      Print("WARNING: conditions were researched on EURUSD M5, current chart is ", _Symbol, " ", EnumToString(_Period));

   if (AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: not a hedging account. Several positions per strategy and per-magic separation will not work (positions are netted).");

   // strategy 7
   g_enabled[0] = InpUseS7;  g_long[0] = false; g_hold[0] = InpHoldBarsS7;  g_magic[0] = InpMagicBase + 7;  g_name[0] = "S7";
   // strategy 8
   g_enabled[1] = InpUseS8;  g_long[1] = false; g_hold[1] = InpHoldBarsS8;  g_magic[1] = InpMagicBase + 8;  g_name[1] = "S8";
   // strategy 10
   g_enabled[2] = InpUseS10; g_long[2] = true;  g_hold[2] = InpHoldBarsS10; g_magic[2] = InpMagicBase + 10; g_name[2] = "S10";
   // strategy 20
   g_enabled[3] = InpUseS20; g_long[3] = false; g_hold[3] = InpHoldBarsS20; g_magic[3] = InpMagicBase + 20; g_name[3] = "S20";

   // same calls as DataExporter.mq5
   h_rsi7      = iRSI(_Symbol, _Period, 7, PRICE_CLOSE);
   h_stoch533  = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_cci20     = iCCI(_Symbol, _Period, 20, PRICE_TYPICAL);
   h_ma20lwma  = iMA(_Symbol, _Period, 20, 0, MODE_LWMA, PRICE_CLOSE);
   h_volregime = iCustom(_Symbol, _Period, CUSTOM_IND_VOLREGIME);
   h_pricestruct = iCustom(_Symbol, _Period, CUSTOM_IND_PRICESTRUCT);

   if (h_rsi7 == INVALID_HANDLE || h_stoch533 == INVALID_HANDLE || h_cci20 == INVALID_HANDLE ||
       h_ma20lwma == INVALID_HANDLE || h_volregime == INVALID_HANDLE || h_pricestruct == INVALID_HANDLE) {
      Print("ERROR: failed to create one or more indicator handles, error ", GetLastError());
      return INIT_FAILED;
   }

   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (h_rsi7 != INVALID_HANDLE)        IndicatorRelease(h_rsi7);
   if (h_stoch533 != INVALID_HANDLE)    IndicatorRelease(h_stoch533);
   if (h_cci20 != INVALID_HANDLE)       IndicatorRelease(h_cci20);
   if (h_ma20lwma != INVALID_HANDLE)    IndicatorRelease(h_ma20lwma);
   if (h_volregime != INVALID_HANDLE)   IndicatorRelease(h_volregime);
   if (h_pricestruct != INVALID_HANDLE) IndicatorRelease(h_pricestruct);
}

//+------------------------------------------------------------------+
//| Read one indicator value at shift 1                              |
//+------------------------------------------------------------------+
bool ReadBuf(const int handle, const int buffer, double &value)
{
   if (handle == INVALID_HANDLE) return false;
   double a[1];
   if (CopyBuffer(handle, buffer, 1, 1, a) <= 0) return false;
   value = a[0];
   if (value != value || value == EMPTY_VALUE || MathAbs(value) >= 1.0e300) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Count open positions of one strategy                             |
//+------------------------------------------------------------------+
int CountPositions(const long magic)
{
   int n = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != magic) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Close positions of one strategy that reached the hold bars       |
//+------------------------------------------------------------------+
void CloseExpired(const int s)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != g_magic[s]) continue;

      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int held = iBarShift(_Symbol, _Period, open_time);
      if (held < 0) continue;

      if (held >= g_hold[s]) {
         if (!g_trade.PositionClose(ticket))
            Print(g_name[s], ": close failed, ticket ", ticket, ", retcode ", g_trade.ResultRetcode());
         else
            Print(g_name[s], ": closed ticket ", ticket, " after ", held, " bars");
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bar0 = iTime(_Symbol, _Period, 0);
   if (bar0 == g_last_bar) return;
   g_last_bar = bar0;

   // ---- step 1: close expired positions
   for (int s = 0; s < NSTRAT; s++)
      if (g_enabled[s]) CloseExpired(s);

   // ---- read all values at shift 1
   double rsi7, stochK, sessH, sessL, pctl, cci20, lwma20;
   bool ok_rsi   = ReadBuf(h_rsi7, 0, rsi7);
   bool ok_stoch = ReadBuf(h_stoch533, 0, stochK);        // K = buffer 0
   bool ok_sessH = ReadBuf(h_pricestruct, 2, sessH);      // ps_dist_sess_h_atr
   bool ok_sessL = ReadBuf(h_pricestruct, 3, sessL);      // ps_dist_sess_l_atr
   bool ok_pctl  = ReadBuf(h_volregime, 0, pctl);         // volregime_atr_pctl
   bool ok_cci   = ReadBuf(h_cci20, 0, cci20);
   bool ok_lwma  = ReadBuf(h_ma20lwma, 0, lwma20);
   double close1 = iClose(_Symbol, _Period, 1);

   bool sig[NSTRAT];
   // S7
   sig[0] = ok_rsi && ok_stoch && ok_sessH && ok_pctl &&
            rsi7 > 75.0 && stochK > 70.0 && sessH < 0.5 && pctl < 30.0;
   // S8
   sig[1] = ok_rsi && ok_sessH && ok_pctl &&
            rsi7 > 75.0 && sessH < 0.5 && pctl < 30.0;
   // S10
   sig[2] = ok_cci && ok_lwma && ok_sessL && ok_pctl &&
            cci20 < -100.0 && lwma20 > close1 && sessL > -0.5 && pctl < 30.0;
   // S20
   sig[3] = ok_rsi && ok_stoch && ok_sessH && ok_pctl &&
            rsi7 > 75.0 && stochK > 80.0 && sessH < -2.0 && pctl < 30.0;

   // ---- step 2: open new positions
   for (int s = 0; s < NSTRAT; s++) {
      if (!g_enabled[s] || !sig[s]) continue;
      if (InpOnePosPerStrat && CountPositions(g_magic[s]) > 0) continue;

      g_trade.SetExpertMagicNumber(g_magic[s]);
      string cmt = InpComment + "_" + g_name[s];
      bool res = g_long[s] ? g_trade.Buy(InpLots, _Symbol, 0.0, 0.0, 0.0, cmt)
                           : g_trade.Sell(InpLots, _Symbol, 0.0, 0.0, 0.0, cmt);
      if (!res)
         Print(g_name[s], ": open failed, retcode ", g_trade.ResultRetcode());
      else
         Print(g_name[s], ": opened ", (g_long[s] ? "BUY" : "SELL"));
   }
}
//+------------------------------------------------------------------+