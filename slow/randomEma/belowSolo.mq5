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

//================ TRAILING =================
input group "=== Trailing Settings ==="
input double SAR_Step=0.02;
input double SAR_Max=0.2;

//================ TRADING =================
input group "=== Trading Settings ==="
input int maxRangePoints=500;
input double lotSize=0.01;


//================ GLOBAL =================

int emaSignalHandle;
int emaSidewaysHandle;
int sarHandle;

double emaSignal[];
double emaSideways[];

datetime lastBarTime=0;

double lastCrossPrice=0;
bool lastCrossWasUp=false;


//+------------------------------------------------------------------+
int OnInit()
{

   emaSignalHandle=iMA(_Symbol,_Period,
      Signal_EMA_Period,
      Signal_EMA_Shift,
      Signal_EMA_Method,
      Signal_EMA_Applied);

   emaSidewaysHandle=iMA(_Symbol,_Period,
      Sideways_EMA_Period,
      0,
      MODE_EMA,
      PRICE_CLOSE);

   sarHandle=iSAR(_Symbol,_Period,SAR_Step,SAR_Max);

   if(emaSignalHandle==INVALID_HANDLE ||
      emaSidewaysHandle==INVALID_HANDLE ||
      sarHandle==INVALID_HANDLE)
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
   IndicatorRelease(sarHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   if(CopyBuffer(emaSignalHandle,0,0,3,emaSignal)<3) return;
   if(CopyBuffer(emaSidewaysHandle,0,0,3,emaSideways)<3) return;

   CheckForEntry();

   double newSL;
   TrailingParabolicSAR(_Symbol,newSL);
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

   bool crossUp=(price_prev<=ema_prev && price_now>ema_now);
   bool crossDown=(price_prev>=ema_prev && price_now<ema_now);

   if(crossUp)
   {
      lastCrossPrice=price_now;
      lastCrossWasUp=true;
   }

   if(crossDown)
   {
      lastCrossPrice=price_now;
      lastCrossWasUp=false;
   }

   bool stillAboveEMA=false;
   bool stillBelowEMA=false;

   if(lastCrossPrice>0)
   {

      stillAboveEMA=
      (
      price_now>ema_now &&
      lastCrossWasUp &&
      (price_now-lastCrossPrice)<=maxRangePoints*_Point
      );

      stillBelowEMA=
      (
      price_now<ema_now &&
      !lastCrossWasUp &&
      (lastCrossPrice-price_now)<=maxRangePoints*_Point
      );

   }

   bool sellSignal=(crossUp || stillAboveEMA);
   bool buySignal=(crossDown || stillBelowEMA);

   if(buySignal) OpenBuy();
   if(sellSignal) OpenSell();

}

//+------------------------------------------------------------------+

void SendOrder(ENUM_ORDER_TYPE type,double price)
{

   double sarBuffer[];
   ArraySetAsSeries(sarBuffer,true);

   if(CopyBuffer(sarHandle,0,1,1,sarBuffer)<1) return;

   double sarValue=sarBuffer[0];

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
   req.sl       = sarValue;

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

bool TrailingParabolicSAR(string symbol,double &newSL)
{

   if(PositionsTotal()==0) return false;

   double sarBuffer[];
   ArraySetAsSeries(sarBuffer,true);

   if(CopyBuffer(sarHandle,0,1,1,sarBuffer)<1) return false;

   double sarValue=sarBuffer[0];

   for(int i=0;i<PositionsTotal();i++)
   {

      ulong ticket=PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber) continue;

      if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;

      long type=PositionGetInteger(POSITION_TYPE);

      double currentSL=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);

      double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);

      if(type==POSITION_TYPE_BUY)
      {

         if(sarValue>currentSL && sarValue<bid)
            newSL=sarValue;
         else
            continue;

      }

      else if(type==POSITION_TYPE_SELL)
      {

         if((currentSL==0 || sarValue<currentSL) && sarValue>ask)
            newSL=sarValue;
         else
            continue;

      }

      MqlTradeRequest req={};
      MqlTradeResult res={};

      req.action=TRADE_ACTION_SLTP;
      req.position=ticket;
      req.symbol=symbol;
      req.sl=newSL;
      req.tp=tp;

      OrderSend(req,res);

   }

   return false;

}
//+------------------------------------------------------------------+