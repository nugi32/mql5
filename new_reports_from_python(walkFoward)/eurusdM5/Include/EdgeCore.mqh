//+------------------------------------------------------------------+
//| EdgeCore.mqh                                                     |
//| Shared helpers for the eurusdM5 walk-forward EAs:                |
//|   - new-bar detection (same logic as DataExporter OnTick)        |
//|   - safe indicator buffer read                                   |
//|   - market entry WITHOUT broker SL / TP                          |
//|   - time-stop: close position after N bars                       |
//+------------------------------------------------------------------+
#ifndef EDGE_CORE_MQH
#define EDGE_CORE_MQH

#include <Trade\Trade.mqh>

//--- Signals are evaluated on the last CLOSED bar (same as the CSV export,
//--- which writes bar index 1 on every new bar).
#define EC_SIGNAL_SHIFT 1

enum EC_DIRECTION
  {
   EC_LONG  = 0,
   EC_SHORT = 1
  };

//--- State
CTrade   g_ec_trade;
ulong    g_ec_magic    = 0;
double   g_ec_lots     = 0.10;
string   g_ec_comment  = "";
datetime g_ec_last_bar = 0;

//+------------------------------------------------------------------+
//| Make sure the EA is attached to EURUSD / M5                      |
//+------------------------------------------------------------------+
bool EC_ValidateChart()
  {
   if(StringFind(_Symbol, "EURUSD") < 0)
     {
      Print("ERROR: this EA is designed for EURUSD. Current symbol: ", _Symbol);
      return false;
     }
   if(_Period != PERIOD_M5)
     {
      Print("ERROR: this EA is designed for the M5 timeframe.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Initialise trade object and new-bar state                        |
//+------------------------------------------------------------------+
void EC_Init(const ulong magic, const double lots, const int slippage, const string comment)
  {
   g_ec_magic   = magic;
   g_ec_lots    = lots;
   g_ec_comment = comment;

   g_ec_trade.SetExpertMagicNumber(magic);
   g_ec_trade.SetDeviationInPoints(slippage);
   g_ec_trade.SetTypeFillingBySymbol(_Symbol);

   // Do not treat the very first tick after attach as a "new bar"
   g_ec_last_bar = iTime(_Symbol, _Period, 0);
  }

//+------------------------------------------------------------------+
//| True once per new bar (same idea as OnTick in DataExporter)      |
//+------------------------------------------------------------------+
bool EC_IsNewBar()
  {
   datetime current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time == 0 || current_bar_time == g_ec_last_bar)
      return false;
   g_ec_last_bar = current_bar_time;
   return true;
  }

//+------------------------------------------------------------------+
//| Read one indicator buffer value                                  |
//+------------------------------------------------------------------+
bool EC_Value(const int handle, const int shift, double &value, const int buffer = 0)
  {
   if(handle == INVALID_HANDLE)
      return false;

   double buf[1];
   if(CopyBuffer(handle, buffer, shift, 1, buf) != 1)
      return false;
   if(!MathIsValidNumber(buf[0]) || buf[0] == EMPTY_VALUE)
      return false;

   value = buf[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Release one indicator handle                                     |
//+------------------------------------------------------------------+
void EC_Release(int &handle)
  {
   if(handle != INVALID_HANDLE)
     {
      IndicatorRelease(handle);
      handle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| Number of open positions of this EA (symbol + magic)             |
//+------------------------------------------------------------------+
int EC_CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_ec_magic)
         continue;
      n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
//| Close every position that has lived for >= hold_bars bars.       |
//| Age is derived from POSITION_TIME, so it survives EA restarts.   |
//+------------------------------------------------------------------+
void EC_CloseExpired(const int hold_bars)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_ec_magic)
         continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int bars_alive  = iBarShift(_Symbol, _Period, opened, false);
      if(bars_alive < 0)
         continue;

      if(bars_alive >= hold_bars)
        {
         if(!g_ec_trade.PositionClose(ticket))
            PrintFormat("PositionClose failed. ticket=%I64u retcode=%u (%s)",
                        ticket, g_ec_trade.ResultRetcode(), g_ec_trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Normalise lot size to the symbol's volume rules                  |
//+------------------------------------------------------------------+
double EC_NormalizeLots(double lots)
  {
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(vstep > 0.0)
      lots = MathFloor(lots / vstep + 1e-8) * vstep;
   lots = MathMax(vmin, MathMin(vmax, lots));

   int digits = 2;
   if(vstep > 0.0)
      digits = (int)MathMax(0.0, MathRound(-MathLog10(vstep)));
   return NormalizeDouble(lots, digits);
  }

//+------------------------------------------------------------------+
//| Market order, NO SL and NO TP                                    |
//+------------------------------------------------------------------+
bool EC_Open(const EC_DIRECTION dir)
  {
   double lots = EC_NormalizeLots(g_ec_lots);
   bool   ok;

   if(dir == EC_LONG)
      ok = g_ec_trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, g_ec_comment);
   else
      ok = g_ec_trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, g_ec_comment);

   if(!ok)
      PrintFormat("Open failed. retcode=%u (%s)",
                  g_ec_trade.ResultRetcode(), g_ec_trade.ResultRetcodeDescription());
   return ok;
  }

#endif // EDGE_CORE_MQH
