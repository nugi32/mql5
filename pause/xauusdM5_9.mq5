//+------------------------------------------------------------------+
//| EA_XAUUSD_M5_S9.mq5                                              |
//| One research condition (XAUUSD M5), long.                        |
//| Indicator calls/buffers copied from DataExporter.mq5.            |
//| All values are read at shift 1 (last closed bar).                |
//| NOT COMPILED / NOT TESTED.                                       |
//+------------------------------------------------------------------+
#property copyright "EA_XAUUSD"
#property version   "1.00"
#property strict
#property description "S9 : long | rsi_7<20 & stoch_14_3_3_k<20 & ps_dist_sess_l_atr>2 & volregime_atr_ratio<1"

#property tester_indicator "VolRegime_ATR.ex5"
#property tester_indicator "PriceStructure.ex5"

#define CUSTOM_IND_VOLREGIME    "VolRegime_ATR"
#define CUSTOM_IND_PRICESTRUCT  "PriceStructure"

#include <Trade\Trade.mqh>

//--- Inputs
input group "=== General ==="
input double InpLots           = 0.1;           // Fixed lot size
input int    InpDeviation      = 20;            // Max deviation (points)
input long   InpMagicBase      = 990000;        // Magic base (strategy magic = base + strategy number)
input string InpComment        = "EA_XAU_M5";   // Order comment prefix
input bool   InpOnePosPerStrat = true;          // true = max 1 open position per strategy; false = open on every new bar where signal is true

input group "=== Strategy 9 (long) ==="
input bool   InpUseS9          = true;          // Enable strategy 9
input int    InpHoldBarsS9     = 73;            // Hold bars S9

//--- Strategy table
#define NSTRAT 1
bool   g_enabled[NSTRAT];
bool   g_long[NSTRAT];
int    g_hold[NSTRAT];
long   g_magic[NSTRAT];
string g_name[NSTRAT];

//--- Indicator handles
int h_rsi7        = INVALID_HANDLE;
int h_stoch1433   = INVALID_HANDLE;
int h_volregime   = INVALID_HANDLE;
int h_pricestruct = INVALID_HANDLE;

CTrade   g_trade;
datetime g_last_bar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if (StringFind(_Symbol, "XAUUSD") != 0 || _Period != PERIOD_M5)
      Print("WARNING: condition was researched on XAUUSD M5, current chart is ", _Symbol, " ", EnumToString(_Period));

   if (AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: not a hedging account. Several positions per strategy and per-magic separation will not work (positions are netted).");

   g_enabled[0] = InpUseS9; g_long[0] = true; g_hold[0] = InpHoldBarsS9; g_magic[0] = InpMagicBase + 9; g_name[0] = "S9";

   // same calls as DataExporter.mq5
   h_rsi7        = iRSI(_Symbol, _Period, 7, PRICE_CLOSE);
   h_stoch1433   = iStochastic(_Symbol, _Period, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_volregime   = iCustom(_Symbol, _Period, CUSTOM_IND_VOLREGIME);
   h_pricestruct = iCustom(_Symbol, _Period, CUSTOM_IND_PRICESTRUCT);

   if (h_rsi7 == INVALID_HANDLE || h_stoch1433 == INVALID_HANDLE ||
       h_volregime == INVALID_HANDLE || h_pricestruct == INVALID_HANDLE) {
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
   if (h_stoch1433 != INVALID_HANDLE)   IndicatorRelease(h_stoch1433);
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
   double rsi7, stochK, sessL, ratio;
   bool ok_rsi   = ReadBuf(h_rsi7, 0, rsi7);
   bool ok_stoch = ReadBuf(h_stoch1433, 0, stochK);     // K = buffer 0
   bool ok_sessL = ReadBuf(h_pricestruct, 3, sessL);    // ps_dist_sess_l_atr
   bool ok_ratio = ReadBuf(h_volregime, 5, ratio);      // volregime_atr_ratio

   bool sig[NSTRAT];
   // S9
   sig[0] = ok_rsi && ok_stoch && ok_sessL && ok_ratio &&
            rsi7 < 20.0 && stochK < 20.0 && sessL > 2.0 && ratio < 1.0;

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