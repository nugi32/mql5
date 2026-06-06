#property strict

input int FastEMA = 9;
input int SlowEMA = 21;
input int ATRPeriod = 14;
input int LookAhead = 10;

int fileHandle = INVALID_HANDLE;
datetime lastBarTime = 0;

//=====================
// statistics
//=====================

int totalSignals = 0;
int buySignals   = 0;
int sellSignals  = 0;

int trendCount   = 0;

double totalMove1 = 0;
double totalMove3 = 0;
double totalMove5 = 0;

double totalMFE   = 0;
double totalMAE   = 0;

//=====================
// helpers
//=====================

double EMAValue(int period,int shift)
{
   int handle=iMA(
      _Symbol,
      _Period,
      period,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   if(handle==INVALID_HANDLE)
      return 0;

   double buffer[];
   ArraySetAsSeries(buffer,true);

   if(CopyBuffer(handle,0,shift,1,buffer)<=0)
      return 0;

   IndicatorRelease(handle);

   return buffer[0];
}

double ATRValue(int shift)
{
   int handle=iATR(
      _Symbol,
      _Period,
      ATRPeriod
   );

   if(handle==INVALID_HANDLE)
      return 0;

   double buffer[];
   ArraySetAsSeries(buffer,true);

   if(CopyBuffer(handle,0,shift,1,buffer)<=0)
      return 0;

   IndicatorRelease(handle);

   return buffer[0];
}

bool IsNewBar()
{
   datetime current=iTime(_Symbol,_Period,0);

   if(current!=lastBarTime)
   {
      lastBarTime=current;
      return true;
   }

   return false;
}

//=====================
// logging
//=====================

void LogSignal(
   string type,
   datetime signalTime,
   double entry,
   double emaFast,
   double emaSlow,
   double atr
)
{
   double close1=iClose(_Symbol,_Period,0);
   double close3=iClose(_Symbol,_Period,0);
   double close5=iClose(_Symbol,_Period,0);

   if(Bars(_Symbol,_Period) < LookAhead+5)
      return;

   close1=iClose(_Symbol,_Period,1);
   close3=iClose(_Symbol,_Period,3);
   close5=iClose(_Symbol,_Period,5);

   double move1=0;
   double move3=0;
   double move5=0;

   if(type=="BUY")
   {
      move1=(close1-entry)/_Point;
      move3=(close3-entry)/_Point;
      move5=(close5-entry)/_Point;
   }
   else
   {
      move1=(entry-close1)/_Point;
      move3=(entry-close3)/_Point;
      move5=(entry-close5)/_Point;
   }

   double highest=entry;
   double lowest =entry;

   for(int i=1;i<=LookAhead;i++)
   {
      double h=iHigh(_Symbol,_Period,i);
      double l=iLow(_Symbol,_Period,i);

      if(h>highest)
         highest=h;

      if(l<lowest)
         lowest=l;
   }

   double mfe=0;
   double mae=0;

   if(type=="BUY")
   {
      mfe=(highest-entry)/_Point;
      mae=(entry-lowest)/_Point;
   }
   else
   {
      mfe=(entry-lowest)/_Point;
      mae=(highest-entry)/_Point;
   }

   bool trendFollow=(move5>0);

   // stats
   totalSignals++;

   if(type=="BUY")
      buySignals++;
   else
      sellSignals++;

   if(trendFollow)
      trendCount++;

   totalMove1+=move1;
   totalMove3+=move3;
   totalMove5+=move5;

   totalMFE+=mfe;
   totalMAE+=mae;

   // csv
   FileWrite(
      fileHandle,
      TimeToString(signalTime),
      type,
      entry,
      emaFast,
      emaSlow,
      atr,
      move1,
      move3,
      move5,
      mfe,
      mae,
      trendFollow
   );
}

//=====================
// init
//=====================

int OnInit()
{
   fileHandle=
      FileOpen(
         "ema_notes.csv",
         FILE_WRITE|
         FILE_CSV|
         FILE_COMMON
      );

   if(fileHandle==INVALID_HANDLE)
   {
      Print("Cannot open csv");
      return INIT_FAILED;
   }

   FileWrite(
      fileHandle,
      "time",
      "type",
      "entry",
      "emaFast",
      "emaSlow",
      "atr",
      "move1",
      "move3",
      "move5",
      "mfe",
      "mae",
      "trend"
   );

   return INIT_SUCCEEDED;
}

//=====================
// tick
//=====================

void OnTick()
{
   if(!IsNewBar())
      return;

   if(Bars(_Symbol,_Period)<SlowEMA+20)
      return;

   double fast1=EMAValue(FastEMA,1);
   double fast2=EMAValue(FastEMA,2);

   double slow1=EMAValue(SlowEMA,1);
   double slow2=EMAValue(SlowEMA,2);

   double atr=ATRValue(1);

   bool buyCross=
      fast2<slow2 &&
      fast1>slow1;

   bool sellCross=
      fast2>slow2 &&
      fast1<slow1;

   double entry=iClose(_Symbol,_Period,1);
   datetime t=iTime(_Symbol,_Period,1);

   if(buyCross)
   {
      LogSignal(
         "BUY",
         t,
         entry,
         fast1,
         slow1,
         atr
      );
   }

   if(sellCross)
   {
      LogSignal(
         "SELL",
         t,
         entry,
         fast1,
         slow1,
         atr
      );
   }
}

//=====================
// tester summary
//=====================

double OnTester()
{
   double avg1=0;
   double avg3=0;
   double avg5=0;

   double avgMFE=0;
   double avgMAE=0;

   double trendPct=0;

   if(totalSignals>0)
   {
      avg1=totalMove1/totalSignals;
      avg3=totalMove3/totalSignals;
      avg5=totalMove5/totalSignals;

      avgMFE=totalMFE/totalSignals;
      avgMAE=totalMAE/totalSignals;

      trendPct=
         (
            (double)trendCount/
            totalSignals
         )*100.0;
   }

   Print("===== EMA LOGGER =====");
   Print("Total signals: ",totalSignals);
   Print("BUY: ",buySignals);
   Print("SELL: ",sellSignals);

   Print("Avg move1: ",avg1);
   Print("Avg move3: ",avg3);
   Print("Avg move5: ",avg5);

   Print("Avg MFE: ",avgMFE);
   Print("Avg MAE: ",avgMAE);

   Print("Trend %: ",trendPct);

   return trendPct;
}

//=====================
// deinit
//=====================

void OnDeinit(const int reason)
{
   if(fileHandle!=INVALID_HANDLE)
      FileClose(fileHandle);
}