//+------------------------------------------------------------------+
//|                                                     SignalMA.mqh |
//|                                              Single Function Only |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Single function untuk sinyal trading berdasarkan Moving Average  |
//| Parameters:                                                      |
//|   symbol     - simbol trading                                    |
//|   period     - periode MA                                        |
//|   shift      - shift MA                                          |
//|   method     - metode MA (MODE_SMA, MODE_EMA, dll)               |
//|   applied    - harga yang digunakan (PRICE_CLOSE, dll)           |
//|   &signal    - reference untuk menyimpan sinyal (1=Buy, -1=Sell, 0=Netral) |
//|   &entryPrice - reference untuk menyimpan harga entry            |
//| Returns: true jika ada sinyal, false jika tidak                   |
//+------------------------------------------------------------------+
bool SignalMA(string symbol, 
              int period, 
              int shift, 
              ENUM_MA_METHOD method, 
              ENUM_APPLIED_PRICE applied,
              int &signal,
              double &entryPrice)
{
   //--- Inisialisasi default
   signal = 0;
   entryPrice = 0;
   
   //--- Validasi parameter
   if(period <= 0)
   {
      Print("Error: Period MA must be greater than 0");
      return false;
   }
   
   //--- Buat handle MA
   int maHandle = iMA(symbol, PERIOD_CURRENT, period, shift, method, applied);
   if(maHandle == INVALID_HANDLE)
   {
      Print("Error creating MA handle");
      return false;
   }
   
   //--- Buffer untuk menyimpan nilai MA
   double maBuffer[3]; // Butuh 3 nilai untuk perbandingan
   ArraySetAsSeries(maBuffer, true);
   
   //--- Copy nilai MA (3 nilai terakhir)
   if(CopyBuffer(maHandle, 0, 0, 3, maBuffer) < 3)
   {
      Print("Error copying MA buffer");
      IndicatorRelease(maHandle);
      return false;
   }
   
   //--- Release handle
   IndicatorRelease(maHandle);
   
   //--- Dapatkan harga-harga penting
   double open = iOpen(symbol, PERIOD_CURRENT, 0);   // Open price bar saat ini
   double high = iHigh(symbol, PERIOD_CURRENT, 0);   // High price bar saat ini
   double low = iLow(symbol, PERIOD_CURRENT, 0);      // Low price bar saat ini
   double close = iClose(symbol, PERIOD_CURRENT, 0);  // Close price bar saat ini
   double close1 = iClose(symbol, PERIOD_CURRENT, 1); // Close price bar sebelumnya
   
   //--- Nilai MA
   double ma0 = maBuffer[0]; // MA bar saat ini
   double ma1 = maBuffer[1]; // MA bar sebelumnya
   double ma2 = maBuffer[2]; // MA 2 bar sebelumnya
   
   //--- Hitung perbedaan (diff)
   double diffCloseMA = close - ma0;
   double diffOpenMA = open - ma0;
   double diffHighMA = high - ma0;
   double diffLowMA = low - ma0;
   double diffMA = ma0 - ma1; // Arah MA (positif = naik, negatif = turun)
   
   //--- Normalisasi harga untuk entry
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   //--- Analisis untuk sinyal BUY (Long)
   if(diffCloseMA < 0) // Close di bawah MA
   {
      // Pattern 1: Open di atas MA (intersection) dan MA naik
      if(diffOpenMA > 0 && diffMA > 0)
      {
         signal = 1; // Buy signal
         entryPrice = 0; // Entry di market price
         Print("MA Signal: Pattern 1 BUY - Open above MA with uptrend");
         return true;
      }
   }
   else // Close di atas MA
   {
      // Pattern 0: Close di atas MA (basic buy signal)
      signal = 1;
      entryPrice = 0;
      Print("MA Signal: Pattern 0 BUY - Close above MA");
      return true;
      
      // Pattern 2: Open di bawah MA (intersection) dan MA naik
      if(diffOpenMA < 0 && diffMA > 0)
      {
         signal = 1; // Buy signal
         entryPrice = NormalizeDouble(ma0, digits); // Entry di level MA (pullback)
         Print("MA Signal: Pattern 2 BUY - Pullback to MA");
         return true;
      }
      
      // Pattern 3: Open di atas MA dan low di bawah MA (piercing)
      if(diffOpenMA > 0 && diffLowMA < 0)
      {
         signal = 1; // Buy signal
         entryPrice = 0; // Entry di market price
         Print("MA Signal: Pattern 3 BUY - Piercing");
         return true;
      }
   }
   
   //--- Analisis untuk sinyal SELL (Short)
   if(diffCloseMA > 0) // Close di atas MA
   {
      // Pattern 1: Open di bawah MA (intersection) dan MA turun
      if(diffOpenMA < 0 && diffMA < 0)
      {
         signal = -1; // Sell signal
         entryPrice = 0; // Entry di market price
         Print("MA Signal: Pattern 1 SELL - Open below MA with downtrend");
         return true;
      }
   }
   else // Close di bawah MA
   {
      // Pattern 0: Close di bawah MA (basic sell signal)
      signal = -1;
      entryPrice = 0;
      Print("MA Signal: Pattern 0 SELL - Close below MA");
      return true;
      
      // Pattern 2: Open di atas MA (intersection) dan MA turun
      if(diffOpenMA > 0 && diffMA < 0)
      {
         signal = -1; // Sell signal
         entryPrice = NormalizeDouble(ma0, digits); // Entry di level MA (pullback)
         Print("MA Signal: Pattern 2 SELL - Pullback to MA");
         return true;
      }
      
      // Pattern 3: Open di bawah MA dan high di atas MA (piercing)
      if(diffOpenMA < 0 && diffHighMA > 0)
      {
         signal = -1; // Sell signal
         entryPrice = 0; // Entry di market price
         Print("MA Signal: Pattern 3 SELL - Piercing");
         return true;
      }
   }
   
   //--- Tidak ada sinyal
   return false;
}

//+------------------------------------------------------------------+
//| Simplified version dengan default parameters                     |
//+------------------------------------------------------------------+
bool SignalMA_Simple(string symbol, int &signal, double &entryPrice)
{
   // Menggunakan default: period=12, shift=0, method=MODE_SMA, applied=PRICE_CLOSE
   return SignalMA(symbol, 12, 0, MODE_SMA, PRICE_CLOSE, signal, entryPrice);
}

//+------------------------------------------------------------------+
//| Contoh cara penggunaan dalam EA:                                 |
//+------------------------------------------------------------------+
/*
void OnTick()
{
   int signal;
   double entryPrice;
   
   // Menggunakan parameter lengkap
   if(SignalMA(_Symbol, 20, 0, MODE_EMA, PRICE_CLOSE, signal, entryPrice))
   {
      if(signal > 0)
         Print("BUY signal detected! Entry at: ", entryPrice);
      else if(signal < 0)
         Print("SELL signal detected! Entry at: ", entryPrice);
   }
   
   // Atau menggunakan versi sederhana
   if(SignalMA_Simple(_Symbol, signal, entryPrice))
   {
      // Process signal...
   }
}
*/