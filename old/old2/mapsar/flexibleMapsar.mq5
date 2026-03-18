//+------------------------------------------------------------------+
//|                                                 ExpertMAPSAR.mq5 |
//|                        Modified Version - Fixed Lot + SL/TP     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"

//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Expert\Expert.mqh>
#include <Expert\Signal\SignalMA.mqh>
#include <Expert\Trailing\TrailingParabolicSAR.mqh>
#include <Expert\Money\MoneyFixedLot.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string             Inp_Expert_Title="ExpertMAPSAR";

//--- expert settings
int                      Expert_MagicNumber=14598;
bool                     Expert_EveryTick=false;

//--- signal (MA)
input int                Inp_Signal_MA_Period=12;
input int                Inp_Signal_MA_Shift=6;
input ENUM_MA_METHOD     Inp_Signal_MA_Method=MODE_SMA;
input ENUM_APPLIED_PRICE Inp_Signal_MA_Applied=PRICE_CLOSE;

//--- initial SL/TP (in points)
input int                Inp_StopLoss_Points=300;
input int                Inp_TakeProfit_Points=600;

//--- trailing (Parabolic SAR)
input double             Inp_Trailing_ParabolicSAR_Step=0.02;
input double             Inp_Trailing_ParabolicSAR_Maximum=0.2;

//--- money management
input double             Inp_Lot_Size=0.1;

//+------------------------------------------------------------------+
//| Global expert object                                             |
//+------------------------------------------------------------------+
CExpert ExtExpert;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit(void)
{
   if(!ExtExpert.Init(Symbol(),Period(),Expert_EveryTick,Expert_MagicNumber))
   {
      Print(__FUNCTION__," : error initializing expert");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   //--- SIGNAL (MA)
   CSignalMA *signal=new CSignalMA;
   if(signal==NULL)
   {
      Print(__FUNCTION__," : error creating signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   if(!ExtExpert.InitSignal(signal))
   {
      Print(__FUNCTION__," : error initializing signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   signal.PeriodMA(Inp_Signal_MA_Period);
   signal.Shift(Inp_Signal_MA_Shift);
   signal.Method(Inp_Signal_MA_Method);
   signal.Applied(Inp_Signal_MA_Applied);

   //--- initial SL/TP
   signal.StopLevel(Inp_StopLoss_Points);
   signal.TakeLevel(Inp_TakeProfit_Points);

   if(!signal.ValidationSettings())
   {
      Print(__FUNCTION__," : error signal parameters");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   //--- TRAILING (PSAR)
   CTrailingPSAR *trailing=new CTrailingPSAR;
   if(trailing==NULL)
   {
      Print(__FUNCTION__," : error creating trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   if(!ExtExpert.InitTrailing(trailing))
   {
      Print(__FUNCTION__," : error initializing trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   trailing.Step(Inp_Trailing_ParabolicSAR_Step);
   trailing.Maximum(Inp_Trailing_ParabolicSAR_Maximum);

   if(!trailing.ValidationSettings())
   {
      Print(__FUNCTION__," : error trailing parameters");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   //--- MONEY (Fixed Lot)
   CMoneyFixedLot *money=new CMoneyFixedLot;
   if(money==NULL)
   {
      Print(__FUNCTION__," : error creating money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   if(!ExtExpert.InitMoney(money))
   {
      Print(__FUNCTION__," : error initializing money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   money.Lots(Inp_Lot_Size);

   if(!money.ValidationSettings())
   {
      Print(__FUNCTION__," : error money parameters");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   //--- initialize indicators
   if(!ExtExpert.InitIndicators())
   {
      Print(__FUNCTION__," : error initializing indicators");
      ExtExpert.Deinit();
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ExtExpert.Deinit();
}

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick(void)
{
   ExtExpert.OnTick();
}

//+------------------------------------------------------------------+
//| Trade event                                                      |
//+------------------------------------------------------------------+
void OnTrade(void)
{
   ExtExpert.OnTrade();
}

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer(void)
{
   ExtExpert.OnTimer();
}
//+------------------------------------------------------------------+
