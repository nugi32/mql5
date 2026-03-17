//+------------------------------------------------------------------+
//|                                                MeanRevertion.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
double g_mean = 0.0;
double g_std  = 0.0;

input double Risk_Percent = 1.0;
input ulong  Magic_Number = 123456;
input string Trade_Comment = "MeanReversion";

input int    Window      = 50;    // jumlah candle untuk mean
input double Z_Entry     = 2.0;   // threshold entry
input double Z_Stop      = 3.5;   // threshold stop
input int    MaxHolding  = 30;    // max candle holding

datetime entry_time = 0;
int      entry_bar  = -1;
MqlRates rates[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   EventSetTimer(60);
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   return PositionSelect(_Symbol);
}


void OnTick()
{
    if(!LoadRates(Window + 2))
      return;

   if(!CalcMeanStd())
      return;

   if(IsTrending())
      return;

   double z = (rates[0].close - g_mean) / g_std;

   // =========================
   // ENTRY
   // =========================
   if(!HasOpenPosition())
   {
      if(z <= -Z_Entry)
      {
         OpenBuy();
         entry_bar = Bars(_Symbol, _Period);
      }
      else if(z >= Z_Entry)
      {
         OpenSell();
         entry_bar = Bars(_Symbol, _Period);
      }
      return;
   }

   // =========================
   // EXIT
   // =========================
   int bars_held = Bars(_Symbol, _Period) - entry_bar;
   long pos_type = PositionGetInteger(POSITION_TYPE);

   if(pos_type == POSITION_TYPE_BUY && z >= 0.0)
   {
      ClosePosition();
      return;
   }

   if(pos_type == POSITION_TYPE_SELL && z <= 0.0)
   {
      ClosePosition();
      return;
   }

   if(pos_type == POSITION_TYPE_BUY && z <= -Z_Stop)
   {
      ClosePosition();
      return;
   }

   if(pos_type == POSITION_TYPE_SELL && z >= Z_Stop)
   {
      ClosePosition();
      return;
   }

   if(bars_held >= MaxHolding)
   {
      ClosePosition();
      return;
   }
}


//*********************************************************

bool LoadRates(int count)
{
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, count, rates) < count)
      return false;
   return true;
}

//*********************************************************

bool CalcMeanStd()
{
   double sum = 0.0;

   for(int i = 1; i <= Window; i++)
      sum += rates[i].close;

   g_mean = sum / Window;

   double var = 0.0;
   for(int i = 1; i <= Window; i++)
      var += MathPow(rates[i].close - g_mean, 2);

   g_std = MathSqrt(var / Window);

   return (g_std > 0.0);
}


//*********************************************************

bool IsTrending()
{
   double slope = rates[0].close - rates[Window].close;
   double slope_threshold = 2.5 * _Point * Window;

   return (MathAbs(slope) > slope_threshold);
}

//*********************************************************

void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = g_mean - Z_Stop * g_std;

   if(!IsValidStop(entry, sl)) return;

   double lot = CalculateLot(entry, sl);
   if(lot <= 0) return;

   SendOrder(ORDER_TYPE_BUY, lot, entry, sl, 0);
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = g_mean + Z_Stop * g_std;

   if(!IsValidStop(sl, entry)) return;

   double lot = CalculateLot(sl, entry);
   if(lot <= 0) return;

   SendOrder(ORDER_TYPE_SELL, lot, entry, sl, 0);
}

//+------------------------------------------------------------------+
bool IsValidStop(double price,double sl)
{
   double stopLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   return MathAbs(price-sl) >= stopLevel;
}
//+------------------------------------------------------------------+
double CalculateLot(double entry,double sl)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * Risk_Percent / 100.0;
   double points    = MathAbs(entry-sl)/_Point;
   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   if(points<=0 || tickValue<=0) return 0;

   double rawLot = riskMoney / (points * tickValue);

   double minLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(rawLot < minLot) return 0;

   double lot = MathFloor(rawLot / stepLot) * stepLot;
   lot = MathMin(lot, maxLot);

   return lot;
}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double lot,double price,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = lot;
   req.price    = price;
   req.sl       = sl;
   req.tp       = tp;
   req.magic    = Magic_Number;
   req.comment  = Trade_Comment;
   req.deviation= 10;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
void ClosePosition()
{
   if(!PositionSelect(_Symbol))
      return;

   ulong ticket = PositionGetInteger(POSITION_TICKET);
   long  type   = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.volume   = volume;
   req.magic    = Magic_Number;
   req.deviation= 10;

   if(type == POSITION_TYPE_BUY)
   {
      req.type  = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      req.type  = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   OrderSend(req, res);
}
