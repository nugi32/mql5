//+------------------------------------------------------------------+
//|           EMA Crossover EA + Sideways Filter + SAR Trailing     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.30"

input string Inp_Expert_Title="Expert_EMA_Crossover";
int Expert_MagicNumber=14598;

//================ EMA SETTINGS =================
input group "=== Fast EMA Settings ==="
input int FastEMA_Period = 13;
input int FastEMA_Shift  = 0;

input group "=== Slow EMA Settings ==="
input int SlowEMA_Period = 21;
input int SlowEMA_Shift  = 0;

input group "=== SAR Trailing Settings ==="
input bool UseSAR_Trailing = true;
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

//================ SIDEWAYS FILTER =================
input group "=== Sideways Detector Settings ==="
input int period = 34;
input double rangeBuffer = 100.0;

//================ TRADING =================
input group "=== Trading Settings ==="
input double lotSize = 0.01;

//================ GLOBAL =================
int fastEmaHandle;
int slowEmaHandle;
int sidewaysHandle;
int sarHandle;
int atrHandle;

double atrBuffer[];
double fastEma[];
double slowEma[];
double sidewaysBuffer[];

MqlRates rates[];

datetime lastBarTime=0;

//+------------------------------------------------------------------+
int OnInit()
{

   fastEmaHandle=iMA(_Symbol,_Period,FastEMA_Period,FastEMA_Shift,MODE_EMA,PRICE_CLOSE);
   slowEmaHandle=iMA(_Symbol,_Period,SlowEMA_Period,SlowEMA_Shift,MODE_EMA,PRICE_CLOSE);

   sidewaysHandle=iMA(_Symbol,_Period,period,0,MODE_EMA,PRICE_CLOSE);

   sarHandle = iSAR(_Symbol,_Period,SAR_Step,SAR_Max);
   atrHandle = iATR(_Symbol,_Period,14);

   if(fastEmaHandle==INVALID_HANDLE ||
      slowEmaHandle==INVALID_HANDLE ||
      sidewaysHandle==INVALID_HANDLE ||
      sarHandle==INVALID_HANDLE ||
      atrHandle==INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(fastEma,true);
   ArraySetAsSeries(slowEma,true);
   ArraySetAsSeries(rates,true);
   ArraySetAsSeries(sidewaysBuffer,true);
   ArraySetAsSeries(atrBuffer,true);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{

   IndicatorRelease(fastEmaHandle);
   IndicatorRelease(slowEmaHandle);
   IndicatorRelease(sidewaysHandle);
   IndicatorRelease(sarHandle);
    IndicatorRelease(atrHandle);

}
//+------------------------------------------------------------------+
void OnTick()
{
    if(!IsNewBar()) return;

    if(CopyBuffer(fastEmaHandle,0,0,3,fastEma)<3) return;
    if(CopyBuffer(slowEmaHandle,0,0,3,slowEma)<3) return;
    if(CopyBuffer(sidewaysHandle,0,0,period,sidewaysBuffer)<period) return;
    if(CopyBuffer(atrHandle,0,0,1,atrBuffer)<1) return;
    if(CopyRates(_Symbol,_Period,0,3,rates)<3) return;

    bool sideways = isSideways(period);

    if(!sideways)
    CheckForEntry();

    if(UseSAR_Trailing)
    {
    double newSL=0;
    TrailingParabolicSAR(_Symbol,newSL);
    }
}
//+------------------------------------------------------------------+
bool IsNewBar()
{

   datetime current=iTime(_Symbol,_Period,0);

   if(current==lastBarTime)
      return false;

   lastBarTime=current;
   return true;

}

//+------------------------------------------------------------------+
bool isSideways(int length) {
    double atr = atrBuffer[0];
    double buffer_price = atr * 0.1;

    int flatCount = 0;
    int directionChanges = 0;

    for(int i = 0; i < length - 1; i++) {
        double diff = MathAbs(sidewaysBuffer[i] - sidewaysBuffer[i+1]);

        if(diff <= buffer_price)
            flatCount++;

        if(i < length - 2) {
            double diff1 = sidewaysBuffer[i] - sidewaysBuffer[i+1];
            double diff2 = sidewaysBuffer[i+1] - sidewaysBuffer[i+2];

            if(diff1 * diff2 < 0)
                directionChanges++;
        }
    }

    double slope = sidewaysBuffer[0] - sidewaysBuffer[length-1];

    bool flat = flatCount >= (length * 0.8);
    bool choppy = directionChanges > length / 3;
    bool lowSlope = MathAbs(slope) < (atr * 0.2);

    return flat && choppy && lowSlope;
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
   //================ BASIC FILTER =================
   double atr = atrBuffer[0];

   // slope lebih panjang (lebih stabil)
   double slope = sidewaysBuffer[0] - sidewaysBuffer[10];
   if(MathAbs(slope) < atr * 0.2)
      return;

   //================ TREND DETECTION =================
   double fast = fastEma[1];
   double slow = slowEma[1];

   bool uptrend   = fast > slow;
   bool downtrend = fast < slow;

   // trend strength (hindari trend lemah)
   double trendStrength = MathAbs(fast - slow);
   if(trendStrength < atr * 0.3)
      return;

   //================ PRICE DATA =================
   double close1 = rates[1].close;
   double open1  = rates[1].open;
   double high1  = rates[1].high;
   double low1   = rates[1].low;

   //================ PULLBACK DETECTION =================
   double distance = MathAbs(close1 - fast);

   bool nearEMA = distance < atr * 0.5;

   if(!nearEMA)
      return;

   //================ REJECTION CANDLE =================
   bool bullishReject = (close1 > open1) && (low1 < fast);
   bool bearishReject = (close1 < open1) && (high1 > fast);

   //================ FINAL ENTRY =================
   if(uptrend && bullishReject)
   {
      Print("BUY: Trend + Pullback + Rejection");
      OpenBuy();
      return;
   }

   if(downtrend && bearishReject)
   {
      Print("SELL: Trend + Pullback + Rejection");
      OpenSell();
      return;
   }
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
   double entry=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   SendOrder(ORDER_TYPE_BUY,entry);

}
//+------------------------------------------------------------------+
void OpenSell()
{

   double entry=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   SendOrder(ORDER_TYPE_SELL,entry);

}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price)
{

   if(HasOpenPosition()) return;

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