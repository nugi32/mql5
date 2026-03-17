//+------------------------------------------------------------------+
//|              EMA price EA + MTF Confirmation                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"


input string             Inp_Expert_Title                 ="ExpertMAPSAR";
int                      Expert_MagicNumber               =14598;

//--- inputs for signal
input group "=== SAR Settings ==="
input double sarStep = 0.02;
input double sarMax = 0.2;

input group "=== Ema Settings ==="
input int                Inp_Signal_MA_Period             =12;
input int                Inp_Signal_MA_Shift              =6;
input ENUM_MA_METHOD     Inp_Signal_MA_Method             =MODE_SMA;
input ENUM_APPLIED_PRICE Inp_Signal_MA_Applied            =PRICE_CLOSE;

input group "=== ADX Settings ==="
input int adxPeriod = 14;
input int adxThreshold = 25;

input group "=== Trading Settings ==="
input double lotSize = 0.01;
input bool useSecondDot = false;

//================ GLOBAL =================
double   SAR[];
MqlRates rates[];
datetime lastBarTime = 0;
int sarHandle;

int emaHandle;
double EMA[];

int adxHandle;
double ADX[];


bool bullish = false;
bool bearish = false;
//+------------------------------------------------------------------+
int OnInit()
{
   sarHandle = iSAR(_Symbol,_Period,sarStep,sarMax);
   adxHandle = iADX(_Symbol, _Period, adxPeriod);
   emaHandle = iMA(_Symbol,_Period,Inp_Signal_MA_Period,Inp_Signal_MA_Shift,Inp_Signal_MA_Method,Inp_Signal_MA_Applied);

   if(sarHandle==INVALID_HANDLE || adxHandle==INVALID_HANDLE || emaHandle==INVALID_HANDLE)
      return INIT_FAILED;
      
ArraySetAsSeries(SAR,true);
ArraySetAsSeries(rates,true);
ArraySetAsSeries(ADX,true);
ArraySetAsSeries(EMA,true);


   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(sarHandle);
   IndicatorRelease(adxHandle);
   IndicatorRelease(emaHandle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

if(CopyBuffer(sarHandle,0,0,3,SAR) < 3) return;
if(CopyRates(_Symbol,_Period,0,3,rates) < 3) return;
if(CopyBuffer(adxHandle,0,0,3,ADX) < 3) return;
if(CopyBuffer(emaHandle,0,0,3,EMA) < 3) return;


   CheckForEntry();
   manageReverseSignal();
   checkTrend();
}
//+------------------------------------------------------------------+

void checkTrend() {
    double price_now  = rates[1].close;
    double price_prev = rates[2].close;

    bool isBullish = price_now > EMA[1];
    bool isBearish = price_now < EMA[1];

    if (isBullish) bullish = true;
    if (isBearish) bearish = true;
}

bool checkBuy() {
    double close0 = iClose(_Symbol, _Period, 0);
    double close1 = iClose(_Symbol, _Period, 1);
    double close2 = iClose(_Symbol, _Period, 2);

    bool firstDotBuy = (SAR[2] > close2) &&   // SAR above price before flip
                   (SAR[1] < close1);     // SAR below price after flip 

   //--- SECOND DOT BUY SIGNAL
    bool secondDotBuy = (SAR[2] > close2) &&
                       (SAR[1] < close1) &&  
                       (SAR[0] < close0);  

    if (useSecondDot) {
        return secondDotBuy;
    }
        else {
        return firstDotBuy;
        }
}

bool checkSell() {
    double close0 = iClose(_Symbol, _Period, 0);
    double close1 = iClose(_Symbol, _Period, 1);
    double close2 = iClose(_Symbol, _Period, 2);

    bool firstDotSell = (SAR[2] < close2) &&  // SAR below before flip
                    (SAR[1] > close1);    // SAR above after flip  

   //--- SECOND DOT BUY SIGNAL
    bool secondDotSell = (SAR[2] < close2) &&
                       (SAR[1] > close1) &&  
                       (SAR[0] > close0);  

    if (useSecondDot) {
        return secondDotSell;
    }
        else {
        return firstDotSell;
    }
                     
}

bool checkReverseBuy() {
    double close0 = iClose(_Symbol, _Period, 0);
    double close1 = iClose(_Symbol, _Period, 1);
    double close2 = iClose(_Symbol, _Period, 2);

    return (SAR[2] < close2) &&  // SAR below before flip
                    (SAR[1] > close1);  
}

bool checkReverseSell() {
    double close0 = iClose(_Symbol, _Period, 0);
    double close1 = iClose(_Symbol, _Period, 1);
    double close2 = iClose(_Symbol, _Period, 2);

    return (SAR[2] > close2) && (SAR[1] < close1); 
}
void CheckForEntry()
{
    bool IsTrending = ADX[1] > adxThreshold;
    if(checkBuy() && IsTrending && bullish) {
        OpenBuy();
    }
    else if(checkSell() && IsTrending && bearish) {
        OpenSell();
    }
}

void manageReverseSignal()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

    long type = PositionGetInteger(POSITION_TYPE);

    if(type==POSITION_TYPE_BUY &&
      checkReverseBuy())
      ClosePosition(ticket);

    if(type==POSITION_TYPE_SELL &&
      checkReverseSell())
      ClosePosition(ticket);
   }

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
   double tp = 0;

   SendOrder(ORDER_TYPE_BUY,lotSize,entry,sl,tp);
}
//+------------------------------------------------------------------+
void OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl    = 0;
   double tp = 0;

   SendOrder(ORDER_TYPE_SELL,lotSize,entry,sl,tp);
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
//+------------------------------------------------------------------+