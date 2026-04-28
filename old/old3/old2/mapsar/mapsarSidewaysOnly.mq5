//+------------------------------------------------------------------+
//|                                                 ExpertMAPSAR.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.20"
#property strict

#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "ADXDot"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrOrange
#property indicator_width1  2
//+------------------------------------------------------------------+
#include <Expert\Expert.mqh>
#include <Expert\Signal\SignalMA.mqh>
#include <Expert\Trailing\TrailingParabolicSAR.mqh>
#include <Expert\Money\MoneyNone.mqh>
#include <Trade\Trade.mqh>
//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string             Inp_Expert_Title                 ="ExpertMAPSAR";
input int                Expert_MagicNumber               =14598;
input bool               Expert_EveryTick                 =false;

input int                Inp_Signal_MA_Period             =12;
input int                Inp_Signal_MA_Shift              =6;
input ENUM_MA_METHOD     Inp_Signal_MA_Method             =MODE_SMA;
input ENUM_APPLIED_PRICE Inp_Signal_MA_Applied            =PRICE_CLOSE;

input double             Inp_Trailing_ParabolicSAR_Step   =0.02;
input double             Inp_Trailing_ParabolicSAR_Maximum=0.2;

input bool               Inp_CloseOnReverse               =true;
input bool               useMaxDD                         =true;

input double             MaxRiskPercent                   =20.0;

input int                adxPeriod                        =14;
input int                adxThreshold                     =20;
//+------------------------------------------------------------------+
//| Global                                                           |
//+------------------------------------------------------------------+
CExpert     ExtExpert;
CSignalMA  *ExtSignal=NULL;
CTrade      m_trade;

double DotBuffer[];
double adxBuffer[];
int    adxHandle;
//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit(void)
{
   SetIndexBuffer(0, DotBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 159);

   ArraySetAsSeries(DotBuffer, true);
   ArraySetAsSeries(adxBuffer, true);

   adxHandle = iADX(_Symbol, _Period, adxPeriod);
   if(adxHandle == INVALID_HANDLE)
   {
      Print("ADX handle failed");
      return INIT_FAILED;
   }

   //--- init expert engine
   if(!ExtExpert.Init(Symbol(),Period(),Expert_EveryTick,Expert_MagicNumber))
      return INIT_FAILED;

   //--- create signal
   ExtSignal = new CSignalMA;
   if(ExtSignal==NULL)
      return INIT_FAILED;

   if(!ExtExpert.InitSignal(ExtSignal))
      return INIT_FAILED;

   ExtSignal.PeriodMA(Inp_Signal_MA_Period);
   ExtSignal.Shift(Inp_Signal_MA_Shift);
   ExtSignal.Method(Inp_Signal_MA_Method);
   ExtSignal.Applied(Inp_Signal_MA_Applied);

   if(!ExtSignal.ValidationSettings())
      return INIT_FAILED;

   //--- trailing PSAR
   CTrailingPSAR *trailing=new CTrailingPSAR;
   if(trailing==NULL)
      return INIT_FAILED;

   if(!ExtExpert.InitTrailing(trailing))
      return INIT_FAILED;

   trailing.Step(Inp_Trailing_ParabolicSAR_Step);
   trailing.Maximum(Inp_Trailing_ParabolicSAR_Maximum);

   if(!trailing.ValidationSettings())
      return INIT_FAILED;

   //--- money management
   CMoneyNone *money=new CMoneyNone;
   if(money==NULL)
      return INIT_FAILED;

   if(!ExtExpert.InitMoney(money))
      return INIT_FAILED;

   if(!money.ValidationSettings())
      return INIT_FAILED;

   if(!ExtExpert.InitIndicators())
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ExtExpert.Deinit();

   if(adxHandle != INVALID_HANDLE)
      IndicatorRelease(adxHandle);
}
//+------------------------------------------------------------------+
//| ADX TREND FILTER                                                 |
//+------------------------------------------------------------------+
bool IsSideways()
{
   if(adxHandle == INVALID_HANDLE)
      return false;

   double adxValue[2];
   ArraySetAsSeries(adxValue,true);

   if(CopyBuffer(adxHandle,0,0,2,adxValue) <= 0)
      return false;

   // pakai bar sebelumnya (lebih stabil)
   return (adxValue[1] < adxThreshold);
}
//+------------------------------------------------------------------+
void OnTick(void)
{
   // Hanya izinkan framework open posisi saat trending
   if(IsSideways())
      ExtExpert.OnTick();

   CheckFrameworkReverse();
   maxDD();
}
//+------------------------------------------------------------------+
void OnTrade(void)
{
   ExtExpert.OnTrade();
}
//+------------------------------------------------------------------+
void OnTimer(void)
{
   ExtExpert.OnTimer();
}
//+------------------------------------------------------------------+
//| Reverse Close                                                    |
//+------------------------------------------------------------------+
void CheckFrameworkReverse()
{
   if(!Inp_CloseOnReverse) return;
   if(!PositionSelect(_Symbol)) return;

   if(PositionGetInteger(POSITION_MAGIC) != Expert_MagicNumber)
      return;

   long type = PositionGetInteger(POSITION_TYPE);

   bool buySignal  = ExtSignal.LongCondition();
   bool sellSignal = ExtSignal.ShortCondition();

   if(type==POSITION_TYPE_BUY && sellSignal)
      m_trade.PositionClose(_Symbol);

   if(type==POSITION_TYPE_SELL && buySignal)
      m_trade.PositionClose(_Symbol);
}
//+------------------------------------------------------------------+
//| Max Drawdown Protection                                          |
//+------------------------------------------------------------------+
void maxDD()
{
   if(!useMaxDD) return;
   if(!PositionSelect(Symbol())) return;

   double profit  = PositionGetDouble(POSITION_PROFIT);
   double volume  = PositionGetDouble(POSITION_VOLUME);
   long   type    = PositionGetInteger(POSITION_TYPE);
   ulong  ticket  = PositionGetInteger(POSITION_TICKET);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxLoss = balance * MaxRiskPercent / 100.0;

   if(profit < -maxLoss)
   {
      Print("Max DD reached. Closing position: ", ticket);

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = Symbol();
      request.volume   = volume;
      request.position = ticket;
      request.deviation = 10;

      if(type == POSITION_TYPE_BUY)
      {
         request.type  = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      }
      else
      {
         request.type  = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      }

      OrderSend(request,result);
   }
}
//+------------------------------------------------------------------+
//| Indicator Calculation                                            |
//+------------------------------------------------------------------+
int Calculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
)
{
   if(rates_total < 50)
      return 0;

   ArrayResize(adxBuffer, rates_total);

   if(CopyBuffer(adxHandle,0,0,rates_total,adxBuffer) <= 0)
      return 0;

   for(int i=rates_total-2; i>=1; i--)
   {
      DotBuffer[i] = EMPTY_VALUE;

      if(adxBuffer[i] > adxThreshold)
         DotBuffer[i] = high[i] + 30*_Point;
   }

   return rates_total;
}
//+------------------------------------------------------------------+