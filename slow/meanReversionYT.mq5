#property strict

input double LotSize = 0.01;

input int BB_Period = 20;
input double BB_Deviation = 2.0;

input int RSI_Period = 14;

input int ADX_H1_Period = 30;
input int ADX_H4_Period = 17;

input int ATR_Period = 14;
input double ATR_Mult = 4.5;

datetime lastBar=0;

// indicator handles
int bbHandle;
int rsiHandle;
int adxH1Handle;
int adxH4Handle;
int atrHandle;

//------------------------------------------------

int OnInit()
{
   bbHandle = iBands(_Symbol,PERIOD_H1,BB_Period,0,BB_Deviation,PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol,PERIOD_H4,RSI_Period,PRICE_CLOSE);
   adxH1Handle = iADX(_Symbol,PERIOD_H1,ADX_H1_Period);
   adxH4Handle = iADX(_Symbol,PERIOD_H4,ADX_H4_Period);
   atrHandle = iATR(_Symbol,PERIOD_H1,ATR_Period);

   if(bbHandle==INVALID_HANDLE ||
      rsiHandle==INVALID_HANDLE ||
      adxH1Handle==INVALID_HANDLE ||
      adxH4Handle==INVALID_HANDLE ||
      atrHandle==INVALID_HANDLE)
   {
      Print("Indicator handle error");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//------------------------------------------------

bool PositionExists()
{
   if(PositionSelect(_Symbol))
      return true;

   return false;
}

//------------------------------------------------

void OpenTrade(ENUM_ORDER_TYPE type,double sl,double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   sl = NormalizeDouble(sl,_Digits);
   tp = NormalizeDouble(tp,_Digits);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = type;

   request.price = (type==ORDER_TYPE_BUY)?
                   SymbolInfoDouble(_Symbol,SYMBOL_ASK):
                   SymbolInfoDouble(_Symbol,SYMBOL_BID);

   request.sl = sl;
   request.tp = tp;

   request.deviation = 20;
   request.magic = 123456;
   request.type_filling = ORDER_FILLING_IOC;

   OrderSend(request,result);

   Print("ORDER SENT | type=",type,
         " sl=",sl,
         " tp=",tp,
         " digits=",_Digits,
         " ret=",result.retcode);
}

//------------------------------------------------

void OnTick()
{
   datetime time=iTime(_Symbol,PERIOD_H1,0);

   if(time==lastBar) return;
   lastBar=time;

   if(PositionExists())
   {
      Print("Position already exists");
      return;
   }

   double upper[],lower[];
   double rsi[];
   double adxH1[];
   double adxH4[];
   double atr[];

   ArraySetAsSeries(upper,true);
   ArraySetAsSeries(lower,true);
   ArraySetAsSeries(rsi,true);
   ArraySetAsSeries(adxH1,true);
   ArraySetAsSeries(adxH4,true);
   ArraySetAsSeries(atr,true);

   if(CopyBuffer(bbHandle,1,1,1,upper)<=0) return;
   if(CopyBuffer(bbHandle,2,1,1,lower)<=0) return;

   if(CopyBuffer(rsiHandle,0,0,1,rsi)<=0) return;

   if(CopyBuffer(adxH1Handle,0,1,1,adxH1)<=0) return;
   if(CopyBuffer(adxH4Handle,0,0,1,adxH4)<=0) return;

   if(CopyBuffer(atrHandle,0,1,1,atr)<=0) return;

   // Get previous candle OHLC
   MqlRates price[];
   ArraySetAsSeries(price,true);

   if(CopyRates(_Symbol,PERIOD_H1,1,1,price)<=0)
      return;

   double close = price[0].close;
   double low   = price[0].low;
   double high  = price[0].high;

   bool trend = (adxH1[0]>20 && adxH4[0]>25);

   bool bounceBuy  = (low<=lower[0] && close>lower[0]);
   bool bounceSell = (high>=upper[0] && close<upper[0]);

   Print("------ NEW H1 BAR ------");
   Print("UpperBB=",upper[0]," LowerBB=",lower[0]);
   Print("RSI H4=",rsi[0]);
   Print("ADX H1=",adxH1[0]," ADX H4=",adxH4[0]);
   Print("ATR=",atr[0]);
   Print("Close=",close," Low=",low," High=",high);
   Print("Trend=",trend);
   Print("BounceBuy=",bounceBuy," BounceSell=",bounceSell);

   // BUY
   if(trend && rsi[0]>55 && bounceBuy)
   {
      double sl=low-(atr[0] * ATR_Mult);
      double tp=upper[0];

      Print("BUY SIGNAL | SL=",sl," TP=",tp);

      OpenTrade(ORDER_TYPE_BUY,sl,tp);
   }

   // SELL
   if(trend && rsi[0]<45 && bounceSell)
   {
      double sl=high+(atr[0] * ATR_Mult);
      double tp=lower[0];

      Print("SELL SIGNAL | SL=",sl," TP=",tp);

      OpenTrade(ORDER_TYPE_SELL,sl,tp);
   }
}