//+------------------------------------------------------------------+
//|           EMA Cross EA + EMA Sideways Detector (Internal)       |
//+------------------------------------------------------------------+
#property strict
#property version "2.10"

input string Inp_Expert_Title="ExpertMAPSAR";
int Expert_MagicNumber=14598;

//================ EMA SIGNAL =================
input group "=== EMA Signal Settings ==="
input int Signal_EMA_Period=12;
input int Signal_EMA_Shift=0;
input ENUM_MA_METHOD Signal_EMA_Method=MODE_SMA;
input ENUM_APPLIED_PRICE Signal_EMA_Applied=PRICE_CLOSE;

//================ EMA SIDEWAYS =================
input group "=== Sideways EMA Settings ==="
input int Sideways_EMA_Period=34;
input double rangeBuffer=100.0;

//================ TRADING =================
input group "=== Trading Settings ==="
input double lotSize=0.01;

//================ TRADING =================
input group "=== Trading Settings ==="
input ENUM_TIMEFRAMES TimeframeForSideways = PERIOD_H1;
input ENUM_TIMEFRAMES TimeframeForSignal = PERIOD_M15;


//================ GLOBAL =================

int emaSignalHandle;
int emaSidewaysHandle;

double emaSignal[];
double emaSideways[];

datetime lastBarTime=0;

//+------------------------------------------------------------------+
int OnInit()
{

   emaSignalHandle=iMA(_Symbol,TimeframeForSignal,
      Signal_EMA_Period,
      Signal_EMA_Shift,
      Signal_EMA_Method,
      Signal_EMA_Applied);

   emaSidewaysHandle=iMA(_Symbol,TimeframeForSideways,
      Sideways_EMA_Period,
      0,
      MODE_EMA,
      PRICE_CLOSE);

   if(emaSignalHandle==INVALID_HANDLE || emaSidewaysHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(emaSignal,true);
   ArraySetAsSeries(emaSideways,true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaSignalHandle);
   IndicatorRelease(emaSidewaysHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(emaSignalHandle,0,0,3,emaSignal)<3) return;
   if(CopyBuffer(emaSidewaysHandle,0,0,3,emaSideways)<3) return;

   CheckForEntry();
   ManagePositions();
}

//+------------------------------------------------------------------+
bool IsSideways()
{
   double diff=MathAbs(emaSideways[1]-emaSideways[2]);

   return diff <= rangeBuffer*_Point;
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(HasOpenPosition()) return;
   if(IsSideways()) return;

   double price_now=iClose(_Symbol,_Period,1);
   double price_prev=iClose(_Symbol,_Period,2);

   double ema_now=emaSignal[1];
   double ema_prev=emaSignal[2];

   bool below=(price_now<ema_now);
   bool above=(price_now>ema_now);

   bool sellSignal=(above);
   bool buySignal=(below);

   if(buySignal) OpenBuy();
   if(sellSignal) OpenSell();

}

//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.symbol=_Symbol;
   req.volume=lotSize;
   req.type=type;
   req.price=price;
   req.magic=Expert_MagicNumber;
   req.deviation=10;
   req.comment=Inp_Expert_Title;

   OrderSend(req,res);

}

//+------------------------------------------------------------------+
bool IsNewBar()
{

   datetime current=iTime(_Symbol,_Period,0);

   if(current==lastBarTime) return false;

   lastBarTime=current;

   return true;

}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{

   for(int i=0;i<PositionsTotal();i++)
   {

      ulong ticket=PositionGetTicket(i);

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

   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   SendOrder(ORDER_TYPE_BUY,price);

}

//+------------------------------------------------------------------+
void OpenSell()
{

   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   SendOrder(ORDER_TYPE_SELL,price);

}
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      
      if(IsSideways()) {
      ClosePosition(ticket);
      }
   }
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
   req.magic    = Expert_MagicNumber;
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