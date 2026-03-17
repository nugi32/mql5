 #property strict

//================ INPUT =================//
input group "=== ATR Settings ==="
input int ATRperiod = 10;
input int MinVolatility = 2;

input group "=== RSI Settings ==="
input int rsiPeriod = 10;
input int overSold = 20;
input int overPrice = 80;

input group "=== EMA Settings ==="
input int EMA_Fast_Period = 10;
input int EMA_Slow_Period = 20;

input group "=== ADX Settings ==="
input int ADX_Period = 10;
input int ADX_trending = 25;

input group "=== Vol Settings ==="
input int VolMin = 10;

input group "=== SL Settings ==="
input bool use_ATR = false;
input bool use_EMA = false;
input bool use_RSI = false;


input group "=== TP Settings ==="
input bool UseATR = false;
input bool UseEMA = false;
input bool UseRSI = false;

input group "=== Signal Settings ==="
input bool useATR = false;
input bool useEMA = false;
input bool useRSI = false;
input bool useADX = false;
input bool useVOL = false;

input group "=== Trading Settings ==="
input bool UseBreakeEvent = false;
input double Risk_Percent = 1.0;
input double Auto_BE_Level  = 1.0;

input group "=== Other Settings ==="
input int    Magic_Number = 12345;
input string Trade_Comment = "EMA-Cross-MTF";

//================ GLOBAL =================//
int    atrHandle, rsiHandle, emaFastHandle, emaSlowHandle, adxHandle, volHandle;
double ATR[], RSI[], EmaFast[], EmaSlow[], ADX[], VOL[];
datetime lastBarTime = 0;

//================ INIT =================//
int OnInit()
{
   atrHandle = iATR(_Symbol,_Period,ATRperiod);
   rsiHandle = iRSI(_Symbol, _Period, rsiPeriod, PRICE_CLOSE);
   emaFastHandle = iMA(_Symbol,_Period,EMA_Fast_Period,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol,_Period,EMA_Slow_Period,0,MODE_EMA,PRICE_CLOSE);
   adxHandle = iADX(_Symbol, _Period, ADX_Period);
   volHandle = iVolumes(_Symbol, _Period, VOLUME_TICK);

   if(atrHandle==INVALID_HANDLE || rsiHandle == INVALID_HANDLE || emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE || adxHandle==INVALID_HANDLE || volHandle==INVALID_HANDLE)
      return INIT_FAILED;

ArraySetAsSeries(ATR,true);         
ArraySetAsSeries(RSI,true);    
ArraySetAsSeries(EmaFast,true); 
ArraySetAsSeries(EmaSlow,true);         
ArraySetAsSeries(ADX,true);    
ArraySetAsSeries(VOL,true);         


   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(adxHandle);
   IndicatorRelease(volHandle);
}
//================ ON TICK =================//

void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(atrHandle,0,0,3,ATR) < 3) return;
   if(CopyBuffer(rsiHandle,0,0,3,RSI) < 3) return;
   if(CopyBuffer(emaFastHandle,0,0,3,EmaFast) < 3 ) return;
   if(CopyBuffer(emaSlowHandle,0,0,3,EmaSlow) < 3) return;
   if(CopyBuffer(adxHandle,0,0,3,ADX) < 3) return;
   if(CopyBuffer(volHandle,0,0,3,VOL) < 3 ) return;

   CheckForEntry();
   ManagePositions();
}
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(_Symbol,_Period,0);
   if(current == lastBarTime) return false;
   lastBarTime = current;
   return true;
}

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
void OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   
   double sl = 0;
   double tp = 0;

   
   //SL
if(use_ATR)
   sl = entry - ATR[1];

if(use_EMA)
   sl = EmaFast[1];
   
   
//TP
if(UseATR)
   tp = entry + ATR[1];
  
   double lot = CalculateLot(entry,sl);
   if(lot<=0) return;

   SendOrder(ORDER_TYPE_BUY,lot,entry,sl,tp);
}
//+------------------------------------------------------------------+
void ManageReverseTP(ulong ticket)
{
   if(!UseEMA)
   return;
   
   long type = PositionGetInteger(POSITION_TYPE);

   if(type==POSITION_TYPE_BUY &&
      EmaFast[1]<EmaSlow[1] && EmaFast[2]>=EmaSlow[2])
      ClosePosition(ticket);

   if(type==POSITION_TYPE_SELL &&
      EmaFast[1]>EmaSlow[1] && EmaFast[2]<=EmaSlow[2])
      ClosePosition(ticket);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = 0;
   double tp = 0;

   // --- SL ---
   if(use_ATR)
      sl = entry + ATR[1];

   if(use_EMA)
      sl = EmaFast[1];

   // --- TP ---
   if(UseATR)
      tp = entry - ATR[1];

   double lot = CalculateLot(sl, entry);
   if(lot <= 0)
      return;

   SendOrder(ORDER_TYPE_SELL, lot, entry, sl, tp);
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

      ManageBreakeven(ticket);
      ManageReverseTP(ticket);
   }
}
//+------------------------------------------------------------------+
void ManageBreakeven(ulong ticket)
{
   if(!UseBreakeEvent)
   return;
   
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double price= PositionGetDouble(POSITION_PRICE_CURRENT);
   long   type = PositionGetInteger(POSITION_TYPE);

   double risk = MathAbs(open-sl);
   if(risk<=0) return;

   if(type==POSITION_TYPE_BUY && price>=open+risk*Auto_BE_Level && sl<open)
      ModifySL(ticket,open);

   if(type==POSITION_TYPE_SELL && price<=open-risk*Auto_BE_Level && sl>open)
      ModifySL(ticket,open);
}

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





bool isVolatile() {
   if(!useATR) return true;
   return ATR[1] > MinVolatility;
   }

bool rsiBuy() {
   if(!useRSI) return true;
   return RSI[1] <= overSold;
   }
bool rsiSell() {
   if(!useRSI) return true;
   return RSI[1] >= overPrice;
   }
   
bool emaBuy() {
   if (!useEMA) return true;
   return EmaFast[1] > EmaSlow[1] && EmaFast[2] <= EmaSlow[2];
}
bool emaSell() {
   if (!useEMA) return true;
   return EmaFast[1] < EmaSlow[1] && EmaFast[2] >= EmaSlow[2];
}

bool isTrending() {
   if (!useADX) return true;
   return ADX[1] > ADX_trending;
}
bool isHighVolume() {
   if (!useVOL) return true;
   return VOL[1] > VolMin;
}

void CheckForEntry() { 
   if(isVolatile() && rsiBuy() && emaBuy() && isTrending() && isHighVolume())
      OpenBuy();

   if(isVolatile() && rsiSell() && emaSell() && isTrending() && isHighVolume())
      OpenSell();
}