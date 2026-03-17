//+------------------------------------------------------------------+
//|              EMA price EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"


input string             Inp_Expert_Title                 ="ExpertMAPSAR";
int                      Expert_MagicNumber               =14598;

//--- inputs for signal
input group "=== EMA Settings ==="
input int                Inp_Signal_MA_Period             =12;
input int                Inp_Signal_MA_Shift              =6;
input ENUM_MA_METHOD     Inp_Signal_MA_Method             =MODE_SMA;
input ENUM_APPLIED_PRICE Inp_Signal_MA_Applied            =PRICE_CLOSE;

//--- inputs for trailing
input group "=== Tailing Settings ==="
input double             Inp_Trailing_ParabolicSAR_Step   =0.02;
input double             Inp_Trailing_ParabolicSAR_Maximum=0.2;

input group "=== ADX Settings ==="
input int adxPeriod = 14;
input int adxThreshold = 25;

input group "=== Trading Settings ==="
input int maxRangePoints = 500; 
input double Risk_Percent = 1.0;

//================ GLOBAL =================
int    emaHandle;
double   ema[];
MqlRates rates[];
datetime lastBarTime = 0;

int adxHandle;
double ADX[];

int sarHandle;

double lastCrossPrice = 0;     // global variable
bool   lastCrossWasUp = false; // global variable

//+------------------------------------------------------------------+
int OnInit()
{
   emaHandle = iMA(_Symbol,_Period,Inp_Signal_MA_Period,Inp_Signal_MA_Shift,Inp_Signal_MA_Method,Inp_Signal_MA_Applied);
   sarHandle = iSAR(_Symbol,_Period,
                 Inp_Trailing_ParabolicSAR_Step,
                 Inp_Trailing_ParabolicSAR_Maximum);

    adxHandle = iADX(_Symbol, _Period, adxPeriod);

   if(emaHandle==INVALID_HANDLE || sarHandle==INVALID_HANDLE || adxHandle==INVALID_HANDLE)
      return INIT_FAILED;
      
ArraySetAsSeries(ema,true);
ArraySetAsSeries(rates,true);
ArraySetAsSeries(ADX,true);


   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaHandle);
   IndicatorRelease(sarHandle);
   IndicatorRelease(adxHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(emaHandle,0,0,3,ema) < 3) return;
   if(CopyRates(_Symbol,_Period,0,3,rates) < 3) return;
   if(CopyBuffer(adxHandle,0,0,3,ADX) < 3) return;

   CheckForEntry();
   double newSL;
TrailingParabolicSAR(_Symbol,newSL);
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(HasOpenPosition()) return;

   double price_now  = rates[1].close;
   double price_prev = rates[2].close;

   bool IsTrending = ADX[1] > adxThreshold;

   double ema_now  = ema[1];
   double ema_prev = ema[2];

   bool crossUp   = (price_prev <= ema_prev && price_now > ema_now);
   bool crossDown = (price_prev >= ema_prev && price_now < ema_now);

   // ===== SIMPAN CROSS PRICE =====
   if(crossUp)
   {
      lastCrossPrice = price_now;
      lastCrossWasUp = true;
      Print("Cross UP at: ", lastCrossPrice);
   }

   if(crossDown)
   {
      lastCrossPrice = price_now;
      lastCrossWasUp = false;
      Print("Cross DOWN at: ", lastCrossPrice);
   }

   // ===== CEK RANGE DARI CROSS =====
   bool stillAboveEMA = false;
   bool stillBelowEMA = false;

   if(lastCrossPrice > 0)
   {
      stillAboveEMA = (price_now > ema_now &&
                       lastCrossWasUp &&
                       (price_now - lastCrossPrice) <= maxRangePoints * _Point);

      stillBelowEMA = (price_now < ema_now &&
                       !lastCrossWasUp &&
                       (lastCrossPrice - price_now) <= maxRangePoints * _Point);
   }

   bool buySignal  = IsTrending && (crossUp   || stillAboveEMA);
   bool sellSignal = IsTrending && (crossDown || stillBelowEMA);

   if(buySignal)
      OpenBuy();

   if(sellSignal)
      OpenSell();
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
   req.magic    = Expert_MagicNumber;
   req.comment  = Inp_Expert_Title;
   req.deviation= 10;

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(_Symbol,_Period,0);
   if(current == lastBarTime) return false;
   lastBarTime = current;
   return true;
}
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC)==Expert_MagicNumber &&
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
   double sl    = 0;

   //if(!IsValidStop(entry,sl)) return;

   double lot = 0.01;
   //if(lot<=0) return;

   double tp = 0;

   SendOrder(ORDER_TYPE_BUY,lot,entry,sl,tp);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl    = 0;

   if(!IsValidStop(sl,entry)) return;

   double lot = 0.01;
   //if(lot<=0) return;

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
bool TrailingParabolicSAR(string symbol, double &newSL)
{
   if(PositionsTotal()==0)
      return false;

   double sarBuffer[];
   ArraySetAsSeries(sarBuffer,true);

   if(CopyBuffer(sarHandle,0,1,1,sarBuffer)<1)
      return false;

   double sarValue = sarBuffer[0];

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double bid = SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol,SYMBOL_ASK);

      if(type==POSITION_TYPE_BUY)
      {
         if(sarValue > currentSL && sarValue < bid)
         {
            newSL = sarValue;
         }
         else continue;
      }
      else if(type==POSITION_TYPE_SELL)
      {
         if((currentSL==0 || sarValue < currentSL) && sarValue > ask)
         {
            newSL = sarValue;
         }
         else continue;
      }

      MqlTradeRequest req={};
      MqlTradeResult  res={};

      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = symbol;
      req.sl       = newSL;
      req.tp       = tp;

      if(OrderSend(req,res))
      {
         if(res.retcode==TRADE_RETCODE_DONE)
         {
            Print("Trailing updated to: ",newSL);
            return true;
         }
      }
   }

   return false;
}