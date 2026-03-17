//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Expert\Expert.mqh>
#include <Expert\Signal\SignalCCI.mqh>
#include <Expert\Trailing\TrailingParabolicSAR.mqh>
#include <Expert\Money\MoneyFixedLot.mqh>
//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string Expert_Title="ExpertCCI_PSAR";
int   Expert_MagicNumber = 20260222;
bool  Expert_EveryTick   = false;

//--- Signal CCI
input int    Inp_CCI_Period = 14;
input ENUM_APPLIED_PRICE Inp_CCI_Price = PRICE_TYPICAL;

//--- Trailing PSAR
input double Inp_PSAR_Step  = 0.02;
input double Inp_PSAR_Max   = 0.2;

//--- Fixed Lot
input double Inp_FixedLot   = 0.10;
//+------------------------------------------------------------------+
//| Global expert object                                             |
//+------------------------------------------------------------------+
CExpert ExtExpert;
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Init Expert
   if(!ExtExpert.Init(Symbol(),Period(),Expert_EveryTick,Expert_MagicNumber))
      return(-1);

   //================ SIGNAL =================
   CSignalCCI *signal=new CSignalCCI;
   if(signal==NULL)
      return(-2);

   if(!ExtExpert.InitSignal(signal))
      return(-3);

   signal.PeriodCCI(Inp_CCI_Period);
   signal.Applied(Inp_CCI_Price);

   if(!signal.ValidationSettings())
      return(-4);

   //================ TRAILING =================
   CTrailingPSAR *trailing=new CTrailingPSAR;
   if(trailing==NULL)
      return(-5);

   if(!ExtExpert.InitTrailing(trailing))
      return(-6);

   trailing.Step(Inp_PSAR_Step);
   trailing.Maximum(Inp_PSAR_Max);

   if(!trailing.ValidationSettings())
      return(-7);

//================ MONEY =================
CMoneyFixedLot *money=new CMoneyFixedLot;
if(money==NULL)
   return(-8);

if(!ExtExpert.InitMoney(money))
   return(-9);

// set fixed lot
money.Lots(Inp_FixedLot);

if(!money.ValidationSettings())
   return(-10);
   //================ INDICATORS =================
   if(!ExtExpert.InitIndicators())
      return(-11);

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ExtExpert.Deinit();
}
//+------------------------------------------------------------------+
void OnTick()
{
   ExtExpert.OnTick();
}
//+------------------------------------------------------------------+
void OnTrade()
{
   ExtExpert.OnTrade();
}
//+------------------------------------------------------------------+
void OnTimer()
{
   ExtExpert.OnTimer();
}
//+------------------------------------------------------------------+