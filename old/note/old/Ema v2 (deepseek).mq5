//+------------------------------------------------------------------+
//| Expert Advisor Double EMA dengan SL di bawah/atas EMA Lambat     |
//| Risiko 1%, Filter RSI, Maksimum 1 Posisi                         |
//| Dibuat untuk MetaTrader 5                                        |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "https://www.example.com"
#property version   "1.00"

// Input parameter
input int      emaFastPeriod   = 12;       // Periode EMA Cepat
input int      emaSlowPeriod   = 26;       // Periode EMA Lambat
input double   riskPercent     = 1.0;      // Risiko per trade (%)
input double   slPoints        = 50;       // Jarak SL tambahan dari EMA Lambat (poin)
input double   tpMultiplier    = 2.0;      // Multiplier TP terhadap SL
input int      rsiPeriod       = 14;       // Periode RSI
input double   rsiOverbought   = 70;       // Level RSI Overbought
input double   rsiOversold     = 30;       // Level RSI Oversold
input int      magicNumber     = 123456;   // Magic Number

// Global variables
int handleEmaFast, handleEmaSlow, handleRsi;
double emaFast[], emaSlow[], rsi[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Inisialisasi indikator
   handleEmaFast = iMA(_Symbol, PERIOD_CURRENT, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaSlow = iMA(_Symbol, PERIOD_CURRENT, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleRsi = iRSI(_Symbol, PERIOD_CURRENT, rsiPeriod, PRICE_CLOSE);

   if(handleEmaFast == INVALID_HANDLE || handleEmaSlow == INVALID_HANDLE || handleRsi == INVALID_HANDLE)
   {
      Print("Gagal membuat handle indikator!");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEmaFast);
   IndicatorRelease(handleEmaSlow);
   IndicatorRelease(handleRsi);
}

//+------------------------------------------------------------------+
//| Fungsi untuk memeriksa jumlah posisi terbuka                     |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Fungsi untuk menghitung lot size berdasarkan risiko               |
//+------------------------------------------------------------------+
double CalculateLotSize(double balance, double riskPercent, double slDistance, double tickValue)
{
   if(slDistance <= 0 || tickValue <= 0)
   {
      Print("Invalid lot size calculation: slDistance=", slDistance, ", tickValue=", tickValue);
      return 0.0;
   }
   
   double riskAmount = balance * (riskPercent / 100.0);
   double lotSize = riskAmount / (slDistance * tickValue);
   lotSize = NormalizeDouble(lotSize, 2); // Bulatkan ke 2 desimal
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return MathMax(minLot, MathMin(maxLot, lotSize));
}

//+------------------------------------------------------------------+
//| Fungsi untuk membuka posisi                                      |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_POSITION_TYPE posType, double price, double sl, double tp, double lotSize)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = NormalizeDouble(price, _Digits);
   request.sl = (sl > 0) ? NormalizeDouble(sl, _Digits) : 0;
   request.tp = (tp > 0) ? NormalizeDouble(tp, _Digits) : 0;
   request.deviation = 10;
   request.magic = magicNumber;
   request.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
   {
      Print("Gagal membuka posisi, error: ", GetLastError(), ", retcode: ", result.retcode);
   }
   else
   {
      Print("Posisi dibuka, ticket: ", result.deal, ", lot: ", lotSize);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Cek apakah sudah ada posisi terbuka
   if(HasOpenPosition()) return;

   // Ambil data indikator
   if(CopyBuffer(handleEmaFast, 0, 0, 3, emaFast) <= 0 || 
      CopyBuffer(handleEmaSlow, 0, 0, 3, emaSlow) <= 0 || 
      CopyBuffer(handleRsi, 0, 0, 3, rsi) <= 0)
   {
      Print("Gagal mengambil data indikator!");
      return;
   }

   // Cek sinyal crossover
   bool buySignal = (emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2] && rsi[1] < rsiOverbought);
   bool sellSignal = (emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2] && rsi[1] > rsiOversold);

   // Harga saat ini
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Hitung lot size berdasarkan risiko 1%
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   // Open posisi Buy
   if(buySignal)
   {
      double sl = emaSlow[1] - slPoints * point; // SL di bawah EMA lambat
      double slDistance = (ask - sl) / point;    // Jarak SL dalam poin
      double tp = ask + (slDistance * tpMultiplier * point); // TP sebagai perkalian SL
      
      double lotSize = CalculateLotSize(accountBalance, riskPercent, slDistance, tickValue);
      if(lotSize > 0 && sl > 0 && tp > ask)
         OpenPosition(POSITION_TYPE_BUY, ask, sl, tp, lotSize);
      else
         Print("Invalid Buy parameters: lotSize=", lotSize, ", sl=", sl, ", tp=", tp);
   }
   // Open posisi Sell
   else if(sellSignal)
   {
      double sl = emaSlow[1] + slPoints * point; // SL di atas EMA lambat
      double slDistance = (sl - bid) / point;    // Jarak SL dalam poin
      double tp = bid - (slDistance * tpMultiplier * point); // TP sebagai perkalian SL
      
      double lotSize = CalculateLotSize(accountBalance, riskPercent, slDistance, tickValue);
      if(lotSize > 0 && sl > bid && tp < bid)
         OpenPosition(POSITION_TYPE_SELL, bid, sl, tp, lotSize);
      else
         Print("Invalid Sell parameters: lotSize=", lotSize, ", sl=", sl, ", tp=", tp);
   }
}