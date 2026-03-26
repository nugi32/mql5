//+------------------------------------------------------------------+
//|                     MACD_MoneyMap_Debug.mq5                      |
//+------------------------------------------------------------------+
#property strict

input double LotSize = 0.1;
input int StopLoss = 200;     
input int TakeProfit = 400;   
input int FastEMA = 12;
input int SlowEMA = 26;
input int SignalSMA = 9;

input ENUM_TIMEFRAMES TF_Trend = PERIOD_D1;
input ENUM_TIMEFRAMES TF_Setup = PERIOD_H4;
input ENUM_TIMEFRAMES TF_Entry = PERIOD_H1;

input double DistanceThreshold = 0.0005;

//--- handles
int macdTrendHandle;
int macdSetupHandle;
int macdEntryHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   macdTrendHandle = iMACD(_Symbol, TF_Trend, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE);
   macdSetupHandle = iMACD(_Symbol, TF_Setup, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE);
   macdEntryHandle = iMACD(_Symbol, TF_Entry, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE);

   Print("INIT DONE");
   Print("Symbol: ", _Symbol);
   Print("Digits: ", _Digits);
   Print("Point: ", _Point);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
bool GetMACD(int handle, double &main[], double &signal[], double &hist[])
{
   ArraySetAsSeries(main, true);
   ArraySetAsSeries(signal, true);
   ArraySetAsSeries(hist, true);

   if(CopyBuffer(handle, 0, 0, 3, main) <= 0) return false;
   if(CopyBuffer(handle, 1, 0, 3, signal) <= 0) return false;
   if(CopyBuffer(handle, 2, 0, 3, hist) <= 0) return false;

   return true;
}

//+------------------------------------------------------------------+
int GetTrendBias()
{
   double main[], signal[], hist[];
   if(!GetMACD(macdTrendHandle, main, signal, hist)) return 0;

   if(main[0] > 0) return 1;
   if(main[0] < 0) return -1;

   return 0;
}

//+------------------------------------------------------------------+
bool BullishCrossover(double &main[], double &signal[])
{
   return (main[1] < signal[1] && main[0] > signal[0]);
}

bool BearishCrossover(double &main[], double &signal[])
{
   return (main[1] > signal[1] && main[0] < signal[0]);
}

bool HistogramBullishFlip(double &hist[])
{
   return (hist[1] < 0 && hist[0] > 0);
}

bool HistogramBearishFlip(double &hist[])
{
   return (hist[1] > 0 && hist[0] < 0);
}

bool ValidDistance(double value)
{
   return MathAbs(value) > DistanceThreshold;
}

//+------------------------------------------------------------------+
void CheckTrade()
{
   int bias = GetTrendBias();
   if(bias == 0) return;

   double mainS[], signalS[], histS[];
   double mainE[], signalE[], histE[];

   if(!GetMACD(macdSetupHandle, mainS, signalS, histS)) return;
   if(!GetMACD(macdEntryHandle, mainE, signalE, histE)) return;

   Print("Bias: ", bias);
   Print("MACD Setup Main: ", mainS[0]);

   if(bias == 1)
   {
      if(BullishCrossover(mainS, signalS) )//&& ValidDistance(mainS[0]))
      {
         if(HistogramBullishFlip(histE))
         {
            Print("BUY SIGNAL DETECTED");
            OpenBuy();
         }
      }
   }

   if(bias == -1)
   {
      if(BearishCrossover(mainS, signalS) && ValidDistance(mainS[0]))
      {
         if(HistogramBearishFlip(histE))
         {
            Print("SELL SIGNAL DETECTED");
            OpenSell();
         }
      }
   }
}

//+------------------------------------------------------------------+
double GetPip()
{
   if(_Digits == 3 || _Digits == 5)
      return 10 * _Point;
   return _Point;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   if(PositionSelect(_Symbol)) return;

   double pip = GetPip();

   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = price - StopLoss * pip;
   double tp = price + TakeProfit * pip;

   SendOrder(ORDER_TYPE_BUY, price, tp, sl);
}

//+------------------------------------------------------------------+
void OpenSell()
{
   if(PositionSelect(_Symbol)) return;

   double pip = GetPip();

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = price + StopLoss * pip;
   double tp = price - TakeProfit * pip;

   SendOrder(ORDER_TYPE_SELL, price, tp, sl);
}

//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double price, double tp, double sl)
{
   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   // volume fix
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double volume = MathMax(minLot, LotSize);
   volume = MathFloor(volume / lotStep) * lotStep;

   // normalize
   price = NormalizeDouble(price, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   Print("------ ORDER DEBUG ------");
   Print("Type: ", type);
   Print("Price: ", price);
   Print("SL: ", sl);
   Print("TP: ", tp);
   Print("StopLevel: ", stopLevel);
   Print("Volume: ", volume);

   // stop validation
   if(type == ORDER_TYPE_BUY)
   {
      if((price - sl) < stopLevel || (tp - price) < stopLevel)
      {
         Print("INVALID STOP BUY");
         return;
      }
   }
   else
   {
      if((sl - price) < stopLevel || (price - tp) < stopLevel)
      {
         Print("INVALID STOP SELL");
         return;
      }
   }

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = volume;
   req.type      = type;
   req.price     = price;
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = 20;
   req.magic     = 123;
   req.comment   = "MACD";
   req.type_filling = ORDER_FILLING_IOC;
   req.type_time    = ORDER_TIME_GTC;

   if(!OrderSend(req, res))
   {
      Print("OrderSend FAILED: ", GetLastError());
      return;
   }

   Print("Retcode: ", res.retcode);

   if(res.retcode != TRADE_RETCODE_DONE)
      Print("TRADE FAILED");
   else
      Print("TRADE SUCCESS");
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, TF_Entry, 0);

   if(currentTime != lastTime)
   {
      lastTime = currentTime;
      CheckTrade();
   }
}
//+------------------------------------------------------------------+