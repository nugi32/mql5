//+------------------------------------------------------------------+
//|              EMA Crossover EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

//================ INPUT =================
input group "=== EMA Settings (Entry TF) ==="
input int EMA_period = 10;

input group "=== RR Step Trailing ==="
input double BE_At_R         = 1.0;  // BE saat profit >= X R
input double Move_Every_R    = 0.5;  // Update tiap Y R
input double Move_Distance_R = 0.5;  // Geser SL sejauh Z R tiap update

input group "=== ADX Settings ==="
input int adxPeriod = 14;
input int adxThreshold = 25;


input group "=== Trading Settings ==="
input double Risk_Percent = 1.0;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross-MTF";

//================ GLOBAL =================
int    emaHandle;
double   ema[];
MqlRates rates[];
datetime lastBarTime = 0;

int adxHandle;
double ADX[];

//+------------------------------------------------------------------+
int OnInit()
{
   emaHandle = iMA(_Symbol,_Period,EMA_period,0,MODE_EMA,PRICE_CLOSE);
   adxHandle = iADX(_Symbol, _Period, adxPeriod);

   if(emaHandle==INVALID_HANDLE)
      return INIT_FAILED;
      
ArraySetAsSeries(ema,true);
ArraySetAsSeries(ADX,true);
ArraySetAsSeries(rates,true);


   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(adxHandle);
    IndicatorRelease(emaHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{

   if(CopyBuffer(emaHandle,0,0,3,ema) < 3) return;
   if(CopyRates(_Symbol,_Period,0,3,rates) < 3) return;
    if(CopyBuffer(adxHandle,0,0,3,ADX) < 3) return;


   CheckForEntry();
   ManagePositions();
}
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(HasOpenPosition()) return;

   // candle yang SUDAH CLOSE
   double price_now  = rates[1].close;
   double price_prev = rates[2].close;

   double ema_now  = ema[1];
   double ema_prev = ema[2];

   bool crossUp  = (price_prev <= ema_prev) && (price_now > ema_now);
   bool crossDown = (price_prev >= ema_prev) && (price_now < ema_now);

   bool buySignal  = crossUp && (ADX[1] > adxThreshold);
   bool sellSignal = crossDown && (ADX[1] > adxThreshold);

   if(buySignal)
      OpenBuy();

   if(sellSignal)
      OpenSell();
}
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC)==Magic_Number &&
            PositionGetString(POSITION_SYMBOL)==_Symbol)
            return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl    = ema[1];

   if(!IsValidStop(entry,sl)) return;

   double lot = CalculateLot(entry,sl);
   if(lot<=0) return;

   double tp = 0;

   SendOrder(ORDER_TYPE_BUY,lot,entry,sl,tp);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl    = ema[1];

   if(!IsValidStop(sl,entry)) return;

   double lot = CalculateLot(sl,entry);
   if(lot<=0) return;

   double tp = 0;

   SendOrder(ORDER_TYPE_SELL,lot,entry,sl,tp);
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

   req.comment  = Trade_Comment + "|SL=" + DoubleToString(sl,_Digits);

   req.deviation= 10;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      manageTrailingStops(ticket);
   }
}
//+------------------------------------------------------------------+
void ModifySL(ulong ticket,double newSL)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.sl       = newSL;
   req.tp       = PositionGetDouble(POSITION_TP);

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);
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

   if(type==POSITION_TYPE_BUY)
   {
      req.type  = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   }
   else
   {
      req.type  = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
void manageTrailingStops(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;

    double current_sl    = PositionGetDouble(POSITION_SL);
    double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
    double open_price    = PositionGetDouble(POSITION_PRICE_OPEN);
    long   type          = PositionGetInteger(POSITION_TYPE);

    string comment = PositionGetString(POSITION_COMMENT);

    // Ambil initial SL dari comment
    int pos = StringFind(comment,"SL=");
    if(pos < 0) return;

    double initial_sl = StringToDouble(StringSubstr(comment,pos+3));
    if(initial_sl == 0) return;

    // Hitung 1R (risk awal)
    double risk;
    if(type == POSITION_TYPE_BUY)
        risk = open_price - initial_sl;
    else
        risk = initial_sl - open_price;

    if(risk <= 0) return;

    // Hitung profit dalam R
    double profit;
    if(type == POSITION_TYPE_BUY)
        profit = current_price - open_price;
    else
        profit = open_price - current_price;

    double profit_in_R = profit / risk;

    // ==========================
    // 1️⃣ BE LEVEL
    // ==========================
    if(profit_in_R < BE_At_R)
        return;

    // ==========================
    // 2️⃣ HITUNG STEP
    // ==========================
    double steps = MathFloor((profit_in_R - BE_At_R) / Move_Every_R);

    double total_locked_R = steps * Move_Distance_R;

    double new_sl;

    if(type == POSITION_TYPE_BUY)
    {
        new_sl = open_price + total_locked_R * risk;

        if(new_sl > current_sl)
            ModifySL(ticket, NormalizeDouble(new_sl,_Digits));
    }
    else
    {
        new_sl = open_price - total_locked_R * risk;

        if(new_sl < current_sl || current_sl==0)
            ModifySL(ticket, NormalizeDouble(new_sl,_Digits));
    }
}
