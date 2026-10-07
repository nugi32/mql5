//+------------------------------------------------------------------+
//| EurH1Core.mqh                                                    |
//| Shared engine for all eurusdH1 window EAs.                       |
//|  - new-bar detection (same logic as DataExporter OnTick)         |
//|  - single position per magic number (long or short)              |
//|  - time-based exit: close after N bars                           |
//|  - NO broker-side SL / TP, ever                                  |
//+------------------------------------------------------------------+
#ifndef EUR_H1_CORE_MQH
#define EUR_H1_CORE_MQH

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Read one value from an indicator buffer at a given shift          |
//+------------------------------------------------------------------+
bool ReadBuffer(const int handle, const int buffer, const int shift, double &value)
{
   if(handle == INVALID_HANDLE)
      return false;

   double buf[1];
   if(CopyBuffer(handle, buffer, shift, 1, buf) != 1)
      return false;
   if(!MathIsValidNumber(buf[0]))
      return false;

   value = buf[0];
   return true;
}

//+------------------------------------------------------------------+
//| Bar-count based trader (market entry, close after N bars)         |
//+------------------------------------------------------------------+
class CBarHoldTrader
{
private:
   CTrade          m_trade;
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   ulong           m_magic;
   double          m_lots;
   int             m_hold_bars;
   datetime        m_last_bar_time;

   double NormalizeLots(const double lots) const
   {
      double vmin  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double vmax  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double vstep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(vstep <= 0.0)
         vstep = 0.01;

      double v = MathFloor(lots / vstep + 1e-9) * vstep;
      v = MathMax(vmin, MathMin(vmax, v));
      return NormalizeDouble(v, 2);
   }

public:
   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const ulong magic,
             const double lots, const int hold_bars, const int deviation_points)
   {
      m_symbol        = symbol;
      m_tf            = tf;
      m_magic         = magic;
      m_lots          = lots;
      m_hold_bars     = hold_bars;
      m_last_bar_time = 0;

      if(m_hold_bars <= 0)
         return false;

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(deviation_points);
      m_trade.SetTypeFillingBySymbol(symbol);
      return true;
   }

   // True once per new bar (same pattern as OnTick in DataExporter.mq5)
   bool IsNewBar()
   {
      datetime current_bar_time = iTime(m_symbol, m_tf, 0);
      if(current_bar_time == 0 || current_bar_time == m_last_bar_time)
         return false;

      m_last_bar_time = current_bar_time;
      return true;
   }

   bool FindPosition(ulong &ticket, datetime &open_time) const
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         ticket    = tk;
         open_time = (datetime)PositionGetInteger(POSITION_TIME);
         return true;
      }
      return false;
   }

   bool HasPosition() const
   {
      ulong    tk;
      datetime ot;
      return FindPosition(tk, ot);
   }

   // Close the position once it has lived for m_hold_bars bars.
   // Called on every new bar; if a close fails it is retried next bar.
   void ManageExit()
   {
      ulong    tk;
      datetime ot;
      if(!FindPosition(tk, ot))
         return;

      int bars_held = iBarShift(m_symbol, m_tf, ot, false);
      if(bars_held >= m_hold_bars)
      {
         if(!m_trade.PositionClose(tk))
            PrintFormat("Close failed (ticket %I64u): %d %s", tk,
                        m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      }
   }

   // Market order, no SL and no TP. type = ORDER_TYPE_BUY or ORDER_TYPE_SELL
   bool OpenPosition(const ENUM_ORDER_TYPE type, const string comment)
   {
      double lots = NormalizeLots(m_lots);
      bool   ok   = false;

      if(type == ORDER_TYPE_BUY)
         ok = m_trade.Buy(lots, m_symbol, 0.0, 0.0, 0.0, comment);
      else if(type == ORDER_TYPE_SELL)
         ok = m_trade.Sell(lots, m_symbol, 0.0, 0.0, 0.0, comment);

      if(!ok)
         PrintFormat("Order failed: %d %s", m_trade.ResultRetcode(),
                     m_trade.ResultRetcodeDescription());
      return ok;
   }
};

#endif // EUR_H1_CORE_MQH
