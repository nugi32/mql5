//+------------------------------------------------------------------+
//|                                                  EdgeEngine.mqh  |
//| Shared engine for the eurusdM5 walk-forward edge EAs.            |
//|                                                                  |
//| - New-bar gate (same pattern as DataExporter.mq5 OnTick)         |
//| - Signal evaluated on the LAST CLOSED bar (shift 1), exactly as  |
//|   DataExporter writes its CSV rows                               |
//| - Entry at market on the open of the new bar                     |
//| - Exit by TIME ONLY: close after EDGE_HOLD_BARS bars             |
//| - NO broker SL, NO broker TP                                     |
//|                                                                  |
//| The EA file must define BEFORE including this file:              |
//|   EDGE_ID, EDGE_MAGIC, EDGE_DIRECTION, EDGE_HOLD_BARS,           |
//|   EDGE_TIMEFRAME, EDGE_TEST_FROM, EDGE_TEST_TO                   |
//| and must implement:                                              |
//|   bool EdgeInitIndicators();                                     |
//|   void EdgeReleaseIndicators();                                  |
//|   bool EdgeSignal();                                             |
//+------------------------------------------------------------------+
#ifndef EURUSDM5_EDGE_ENGINE_MQH
#define EURUSDM5_EDGE_ENGINE_MQH

#include <Trade\Trade.mqh>

#define EDGE_LONG    1
#define EDGE_SHORT  -1

#ifndef EDGE_ID
   #error "EDGE_ID must be defined before including EdgeEngine.mqh"
#endif
#ifndef EDGE_MAGIC
   #error "EDGE_MAGIC must be defined before including EdgeEngine.mqh"
#endif
#ifndef EDGE_DIRECTION
   #error "EDGE_DIRECTION must be defined before including EdgeEngine.mqh"
#endif
#ifndef EDGE_HOLD_BARS
   #error "EDGE_HOLD_BARS must be defined before including EdgeEngine.mqh"
#endif
#ifndef EDGE_TIMEFRAME
   #error "EDGE_TIMEFRAME must be defined before including EdgeEngine.mqh"
#endif

//--- Inputs
input group "=== Trade ==="
input double   InpLots              = 0.01;            // Lot size per position
input ulong    InpMagic             = EDGE_MAGIC;      // Magic number
input int      InpMaxPositions      = 0;               // Max open positions (0 = unlimited, mirrors report)
input int      InpDeviationPoints   = 20;              // Max slippage (points)
input group "=== Optional date filter ==="
input bool     InpRestrictToWindow  = false;           // Only OPEN trades inside the window below
input datetime InpTradeFrom         = EDGE_TEST_FROM;  // Window start (report test period)
input datetime InpTradeTo           = EDGE_TEST_TO;    // Window end (exclusive)
input group "=== Misc ==="
input bool     InpVerbose           = false;           // Print every entry / exit

//--- Forward declarations (implemented in the EA file)
bool EdgeInitIndicators();
void EdgeReleaseIndicators();
bool EdgeSignal();

//--- State
CTrade   g_trade;
datetime g_last_bar_time = 0;
int      g_max_positions = 0;
bool     g_exit_pending  = false;

//+------------------------------------------------------------------+
//| Read one indicator buffer value (false if missing / NaN / EMPTY) |
//+------------------------------------------------------------------+
bool EdgeReadBuffer(const int handle, const int buffer, const int shift, double &value)
{
   if(handle == INVALID_HANDLE) return false;

   double tmp[1];
   if(CopyBuffer(handle, buffer, shift, 1, tmp) <= 0) return false;

   value = tmp[0];
   if(!MathIsValidNumber(value)) return false;
   if(value == EMPTY_VALUE || MathAbs(value) >= 1.0e300) return false;
   return true;
}

//+------------------------------------------------------------------+
//| New bar gate (same logic as DataExporter OnTick)                 |
//+------------------------------------------------------------------+
bool EdgeIsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0) return false;
   if(t == g_last_bar_time) return false;
   g_last_bar_time = t;
   return true;
}

//+------------------------------------------------------------------+
//| Position helpers                                                 |
//+------------------------------------------------------------------+
bool EdgeIsMine(const ulong ticket)
{
   if(ticket == 0) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   return true;
}

int EdgeCountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(EdgeIsMine(ticket)) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Close every position that has been held >= EDGE_HOLD_BARS bars   |
//| (bars counted from the bar in which the position was opened)     |
//+------------------------------------------------------------------+
void EdgeManageExits()
{
   g_exit_pending = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!EdgeIsMine(ticket)) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int held = iBarShift(_Symbol, _Period, opened, false);
      if(held < 0) continue;

      if(held >= EDGE_HOLD_BARS)
      {
         if(g_trade.PositionClose(ticket))
         {
            if(InpVerbose) Print(EDGE_ID, " closed #", ticket, " after ", held, " bars");
         }
         else
         {
            g_exit_pending = true; // retry on next tick
            Print(EDGE_ID, " close failed #", ticket, " retcode=", g_trade.ResultRetcode(),
                  " (", g_trade.ResultRetcodeDescription(), ")");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Lot normalisation                                                |
//+------------------------------------------------------------------+
double EdgeNormalizeLots(double lots)
{
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = vmin;

   lots = MathFloor(lots / step + 1.0e-9) * step;
   lots = MathMax(vmin, MathMin(vmax, lots));

   int digits = 0;
   double s = step;
   while(digits < 8 && MathAbs(s - MathRound(s)) > 1.0e-8) { s *= 10.0; digits++; }
   return NormalizeDouble(lots, digits);
}

bool EdgeInTradeWindow()
{
   if(!InpRestrictToWindow) return true;
   datetime now = TimeCurrent();
   return (now >= InpTradeFrom && now < InpTradeTo);
}

//+------------------------------------------------------------------+
//| Open one market position, NO SL / NO TP                          |
//+------------------------------------------------------------------+
void EdgeOpen()
{
   double lots = EdgeNormalizeLots(InpLots);
   string cmt  = EDGE_ID;
   bool ok;

   if(EDGE_DIRECTION == EDGE_LONG)
      ok = g_trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, cmt);
   else
      ok = g_trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, cmt);

   if(!ok)
      Print(EDGE_ID, " open failed retcode=", g_trade.ResultRetcode(),
            " (", g_trade.ResultRetcodeDescription(), ")");
   else if(InpVerbose)
      Print(EDGE_ID, " opened ", (EDGE_DIRECTION == EDGE_LONG ? "BUY " : "SELL "), lots, " lots");
}

//+------------------------------------------------------------------+
//| Expert initialisation                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if((ENUM_TIMEFRAMES)_Period != EDGE_TIMEFRAME)
   {
      Print(EDGE_ID, ": this EA was built for ", EnumToString(EDGE_TIMEFRAME),
            " but the chart is ", EnumToString((ENUM_TIMEFRAMES)_Period));
      return INIT_FAILED;
   }
   if(StringFind(_Symbol, "EURUSD") < 0)
      Print("WARNING: ", EDGE_ID, " was researched on EURUSD, current symbol is ", _Symbol);

   g_max_positions = InpMaxPositions;
   ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && g_max_positions != 1)
   {
      Print("WARNING: account is not HEDGING - overlapping positions would be netted. ",
            "Forcing max positions = 1.");
      g_max_positions = 1;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!EdgeInitIndicators())
   {
      Print(EDGE_ID, ": indicator initialisation failed");
      return INIT_FAILED;
   }

   Print(EDGE_ID, " ready | ", (EDGE_DIRECTION == EDGE_LONG ? "LONG" : "SHORT"),
         " | hold ", EDGE_HOLD_BARS, " bars | magic ", InpMagic, " | no SL / no TP");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EdgeReleaseIndicators();
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!EdgeIsNewBar())
   {
      if(g_exit_pending) EdgeManageExits();
      return;
   }

   // 1) time exits first
   EdgeManageExits();

   // 2) entry on the new bar, signal read from the last closed bar
   if(!EdgeInTradeWindow()) return;
   if(g_max_positions > 0 && EdgeCountPositions() >= g_max_positions) return;
   if(!EdgeSignal()) return;

   EdgeOpen();
}

#endif // EURUSDM5_EDGE_ENGINE_MQH
