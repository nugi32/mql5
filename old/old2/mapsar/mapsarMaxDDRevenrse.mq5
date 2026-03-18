//+------------------------------------------------------------------+
//|                                                 ExpertMAPSAR.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"
#property strict
//+------------------------------------------------------------------+
//| Include                                                          |
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
input bool useMaxDD = true;


input double MaxRiskPercent = 2.0; // risiko maksimal dalam persen
//+------------------------------------------------------------------+
//| Global                                                           |
//+------------------------------------------------------------------+
CExpert     ExtExpert;
CSignalMA  *ExtSignal=NULL;
CTrade m_trade;
//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit(void)
{
   //--- init expert engine
   if(!ExtExpert.Init(Symbol(),Period(),Expert_EveryTick,Expert_MagicNumber))
   {
      Print("Error initializing expert");
      return(INIT_FAILED);
   }

   //--- create signal
   ExtSignal = new CSignalMA;
   if(ExtSignal==NULL)
   {
      Print("Error creating signal");
      return(INIT_FAILED);
   }

   if(!ExtExpert.InitSignal(ExtSignal))
   {
      Print("Error initializing signal");
      return(INIT_FAILED);
   }

   //--- signal parameters
   ExtSignal.PeriodMA(Inp_Signal_MA_Period);
   ExtSignal.Shift(Inp_Signal_MA_Shift);
   ExtSignal.Method(Inp_Signal_MA_Method);
   ExtSignal.Applied(Inp_Signal_MA_Applied);

   if(!ExtSignal.ValidationSettings())
   {
      Print("Invalid signal settings");
      return(INIT_FAILED);
   }

   //--- trailing
   CTrailingPSAR *trailing=new CTrailingPSAR;
   if(trailing==NULL)
   {
      Print("Error creating trailing");
      return(INIT_FAILED);
   }

   if(!ExtExpert.InitTrailing(trailing))
   {
      Print("Error initializing trailing");
      return(INIT_FAILED);
   }

   trailing.Step(Inp_Trailing_ParabolicSAR_Step);
   trailing.Maximum(Inp_Trailing_ParabolicSAR_Maximum);

   if(!trailing.ValidationSettings())
   {
      Print("Invalid trailing settings");
      return(INIT_FAILED);
   }

   //--- money management
   CMoneyNone *money=new CMoneyNone;
   if(money==NULL)
   {
      Print("Error creating money object");
      return(INIT_FAILED);
   }

   if(!ExtExpert.InitMoney(money))
   {
      Print("Error initializing money");
      return(INIT_FAILED);
   }

   if(!money.ValidationSettings())
   {
      Print("Invalid money settings");
      return(INIT_FAILED);
   }

   //--- indicators
   if(!ExtExpert.InitIndicators())
   {
      Print("Error initializing indicators");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ExtExpert.Deinit();
}
//+------------------------------------------------------------------+
void OnTick(void)
{
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
//| Reverse Close using Framework Signal                            |
//+------------------------------------------------------------------+
void CheckFrameworkReverse()
{
   if(!Inp_CloseOnReverse) return;
   if(!PositionSelect(_Symbol)) return;

   // pastikan ini posisi EA kita
   if(PositionGetInteger(POSITION_MAGIC) != Expert_MagicNumber)
      return;

   long type = PositionGetInteger(POSITION_TYPE);

   bool buySignal  = ExtSignal.LongCondition();
   bool sellSignal = ExtSignal.ShortCondition();

   // Jika BUY tapi framework sekarang sinyal SELL
   if(type==POSITION_TYPE_BUY && sellSignal)
   {
      m_trade.PositionClose(_Symbol);
   }

   // Jika SELL tapi framework sekarang sinyal BUY
   if(type==POSITION_TYPE_SELL && buySignal)
   {
      m_trade.PositionClose(_Symbol);
   }
}

void maxDD()
{
   if(!useMaxDD) return;
   // cek apakah ada posisi terbuka di simbol chart
   if(PositionSelect(Symbol()))
   {
      double profit     = PositionGetDouble(POSITION_PROFIT);
      double volume     = PositionGetDouble(POSITION_VOLUME);
      long type         = PositionGetInteger(POSITION_TYPE); // 0=buy, 1=sell
      ulong ticket      = PositionGetInteger(POSITION_TICKET);

      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double maxLoss    = balance * MaxRiskPercent / 100.0;

      // jika floating loss melebihi batas, tutup posisi
      if(profit < -maxLoss)
      {
         Print("Floating loss melebihi ", MaxRiskPercent, "%. Menutup posisi: ", ticket);

         MqlTradeRequest request;
         MqlTradeResult  result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action   = TRADE_ACTION_DEAL;
         request.symbol   = Symbol();
         request.volume   = volume;
         request.position = ticket;
         request.deviation = 10;

         // close posisi sesuai tipe
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

         if(!OrderSend(request, result))
            Print("Gagal kirim order close! Error: ", GetLastError());
         else
            Print("Order close berhasil. Result: ", result.retcode);
      }
   }
}