//+------------------------------------------------------------------+
//| EdgeCore.mqh                                                     |
//| Shared helpers for all eurusdM15 walk-forward edge EAs.          |
//|  - IsNewBar()            : new-bar gate (same logic as exporter) |
//|  - GetBuf()              : safe CopyBuffer wrapper               |
//|  - CloseExpiredPositions : time-based exit (close after N bars)  |
//|  - CountPositions        : open positions of this EA             |
//| No SL / TP is ever sent to the broker.                           |
//+------------------------------------------------------------------+
#ifndef EDGE_CORE_MQH
#define EDGE_CORE_MQH

#include <Trade\Trade.mqh>

datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0 || t == g_last_bar_time) return false;
   g_last_bar_time = t;
   return true;
}

//+------------------------------------------------------------------+
//| Read one indicator value (shift 1 = last closed bar)             |
//+------------------------------------------------------------------+
bool GetBuf(const int handle, const int buffer, const int shift, double &value)
{
   if(handle == INVALID_HANDLE) return false;
   double arr[1];
   if(CopyBuffer(handle, buffer, shift, 1, arr) <= 0) return false;
   if(arr[0] != arr[0] || arr[0] == EMPTY_VALUE) return false;   // NaN / empty
   value = arr[0];
   return true;
}

//+------------------------------------------------------------------+
int CountPositions(const long magic)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| Close every position of this EA that is >= hold_bars old         |
//+------------------------------------------------------------------+
void CloseExpiredPositions(CTrade &trade, const long magic, const int hold_bars)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int age = iBarShift(_Symbol, _Period, opened, false);   // bars since entry bar
      if(age >= hold_bars)
      {
         if(!trade.PositionClose(ticket))
            PrintFormat("PositionClose failed #%I64u err=%d", ticket, GetLastError());
      }
   }
}

#endif
