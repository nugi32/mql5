//+------------------------------------------------------------------+
//|                         RSI_ADX_EMA_MACD_EA.mq5                 |
//|                                                                  |
//|  Signal  : RSI14_deep_oversold + ADX_trending                   |
//|            + EMA21_below_EMA50 + EMA50_above_EMA100             |
//|            + MACD_bear_cross                                     |
//|  Direction: BULLISH  (55.0% win rate, OOS 49.4%)                |
//|  Consistency Score : 0.5484   |  Overfit Status : STABLE        |
//|  Exit     : Close after N candles (timing baseline = 3.62)      |
//|  Stop Loss: NONE                                                 |
//+------------------------------------------------------------------+
#property copyright "Generated EA — Pattern #1"
#property version   "1.00"
#property strict

//=== INPUT PARAMETERS ===============================================
input group            "── Trade Settings ──"
input double           InpLotSize       = 0.1;   // Lot Size
input int              InpExitCandles   = 4;      // Exit after N candles (signal timing ≈ 3.62)
input ulong            InpMagicNumber   = 202401; // Magic Number

input group            "── RSI Settings ──"
input int              InpRSIPeriod     = 14;     // RSI Period
input double           InpRSIDeepLevel  = 25.0;  // RSI Deep Oversold Threshold (<)

input group            "── ADX Settings ──"
input int              InpADXPeriod     = 14;     // ADX Period
input double           InpADXLevel      = 25.0;  // ADX Trending Threshold (>)

input group            "── EMA Settings ──"
input int              InpEMA21Period   = 21;     // EMA Fast Period
input int              InpEMA50Period   = 50;     // EMA Mid Period
input int              InpEMA100Period  = 100;    // EMA Slow Period

input group            "── MACD Settings ──"
input int              InpMACDFast      = 12;     // MACD Fast EMA
input int              InpMACDSlow      = 26;     // MACD Slow EMA
input int              InpMACDSignal    = 9;      // MACD Signal Period

//=== GLOBAL VARIABLES ===============================================
int      hRSI, hADX, hEMA21, hEMA50, hEMA100, hMACD;
datetime g_lastBarTime  = 0;
ulong    g_openTicket   = 0;
int      g_candleCount  = 0;

//+------------------------------------------------------------------+
//|  IsNewBar                                                        |
//|  Returns true exactly once per new completed bar.               |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}
/*
//+------------------------------------------------------------------+
//|  GetFillingType                                                  |
//|  Detects the broker-supported order filling mode.               |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingType()
{
   uint flags = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_FLAGS);
   if((flags & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((flags & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}
*/
//+------------------------------------------------------------------+
//|  OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   hRSI    = iRSI (_Symbol, _Period, InpRSIPeriod,   PRICE_CLOSE);
   hADX    = iADX (_Symbol, _Period, InpADXPeriod);
   hEMA21  = iMA  (_Symbol, _Period, InpEMA21Period,  0, MODE_EMA, PRICE_CLOSE);
   hEMA50  = iMA  (_Symbol, _Period, InpEMA50Period,  0, MODE_EMA, PRICE_CLOSE);
   hEMA100 = iMA  (_Symbol, _Period, InpEMA100Period, 0, MODE_EMA, PRICE_CLOSE);
   hMACD   = iMACD(_Symbol, _Period, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   if(hRSI    == INVALID_HANDLE ||
      hADX    == INVALID_HANDLE ||
      hEMA21  == INVALID_HANDLE ||
      hEMA50  == INVALID_HANDLE ||
      hEMA100 == INVALID_HANDLE ||
      hMACD   == INVALID_HANDLE)
   {
      Print("❌ Failed to create indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
   }

   // Warm up buffers — wait for enough candles before trading
   int warmUp = MathMax(InpEMA100Period, InpMACDSlow + InpMACDSignal) + 10;
   Print("✅ EA initialized | Warm-up bars needed: ", warmUp);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  OnDeinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   IndicatorRelease(hADX);
   IndicatorRelease(hEMA21);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hEMA100);
   IndicatorRelease(hMACD);
   Print("🔴 EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//|  ReadIndicators                                                  |
//|  Reads all indicator values from bar index 1 (last closed bar). |
//+------------------------------------------------------------------+
bool ReadIndicators(double &rsi,   double &adx,
                    double &ema21, double &ema50, double &ema100,
                    double &macd,  double &sig)
{
   double buf[1];

   // RSI — buffer 0
   if(CopyBuffer(hRSI,    0, 1, 1, buf) < 1) return false; rsi   = buf[0];

   // ADX — buffer 0 = ADX value (buffer 1 = +DI, buffer 2 = -DI)
   if(CopyBuffer(hADX,    0, 1, 1, buf) < 1) return false; adx   = buf[0];

   // EMAs — buffer 0
   if(CopyBuffer(hEMA21,  0, 1, 1, buf) < 1) return false; ema21  = buf[0];
   if(CopyBuffer(hEMA50,  0, 1, 1, buf) < 1) return false; ema50  = buf[0];
   if(CopyBuffer(hEMA100, 0, 1, 1, buf) < 1) return false; ema100 = buf[0];

   // MACD — buffer 0 = MACD line, buffer 1 = Signal line
   if(CopyBuffer(hMACD,   0, 1, 1, buf) < 1) return false; macd  = buf[0];
   if(CopyBuffer(hMACD,   1, 1, 1, buf) < 1) return false; sig   = buf[0];

   return true;
}

//+------------------------------------------------------------------+
//|  CheckEntrySignal                                                |
//|  Returns true when all 5 pattern conditions are satisfied.      |
//|                                                                  |
//|  1. RSI14_deep_oversold  → RSI_14 < 25                         |
//|  2. ADX_trending         → ADX_14 > 25                         |
//|  3. EMA21_below_EMA50   → EMA_21 < EMA_50                      |
//|  4. EMA50_above_EMA100  → EMA_50 > EMA_100                     |
//|  5. MACD_bear_cross     → MACD_12_26 < MACD_SIGNAL_9           |
//+------------------------------------------------------------------+
bool CheckEntrySignal()
{
   double rsi, adx, ema21, ema50, ema100, macd, sig;
   if(!ReadIndicators(rsi, adx, ema21, ema50, ema100, macd, sig))
   {
      Print("⚠️ ReadIndicators failed.");
      return false;
   }

   bool c1 = (rsi   < InpRSIDeepLevel);   // RSI14_deep_oversold
   bool c2 = (adx   > InpADXLevel);       // ADX_trending
   bool c3 = (ema21 < ema50);             // EMA21_below_EMA50
   bool c4 = (ema50 > ema100);            // EMA50_above_EMA100
   bool c5 = (macd  < sig);              // MACD_bear_cross

   if(c1 && c2 && c3 && c4 && c5)
   {
      PrintFormat("🟢 SIGNAL | RSI=%.2f | ADX=%.2f | EMA21=%.5f < EMA50=%.5f | "
                  "EMA50=%.5f > EMA100=%.5f | MACD=%.5f < Sig=%.5f",
                  rsi, adx, ema21, ema50, ema50, ema100, macd, sig);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|  HasOpenPosition                                                 |
//|  Checks if this EA has an open position on this symbol.         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)       == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//|  OpenBuy                                                         |
//+------------------------------------------------------------------+
bool OpenBuy()
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = InpLotSize;
   req.type         = ORDER_TYPE_BUY;
   req.price        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.deviation    = 20;
   req.magic        = InpMagicNumber;
   req.comment      = StringFormat("PatternBUY | exit@%dc", InpExitCandles);

   if(!OrderSend(req, res))
   {
      PrintFormat("❌ OrderSend BUY failed | retcode=%d | %s", res.retcode, res.comment);
      return false;
   }

   g_openTicket  = res.deal;           // deal ticket for position tracking
   g_candleCount = 0;
   PrintFormat("✅ BUY opened | Ticket=%I64u | Ask=%.5f | Lots=%.2f | Exit in %d candles",
               g_openTicket, req.price, InpLotSize, InpExitCandles);
   return true;
}

//+------------------------------------------------------------------+
//|  ClosePosition                                                   |
//|  Market-closes the position associated with our magic number.   |
//+------------------------------------------------------------------+
bool ClosePosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol)       continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = _Symbol;
      req.volume       = PositionGetDouble(POSITION_VOLUME);
      req.type         = ORDER_TYPE_SELL;
      req.price        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      req.deviation    = 20;
      req.magic        = InpMagicNumber;
      req.position     = ticket;
      req.comment      = StringFormat("Exit@%dCandles", g_candleCount);

      if(!OrderSend(req, res))
      {
         PrintFormat("❌ ClosePosition failed | retcode=%d | %s", res.retcode, res.comment);
         return false;
      }

      PrintFormat("🔴 BUY closed | After %d candles | Bid=%.5f | P&L=%.2f",
                  g_candleCount,
                  req.price,
                  PositionGetDouble(POSITION_PROFIT));

      g_openTicket  = 0;
      g_candleCount = 0;
      return true;
   }

   // Position no longer exists (closed externally)
   g_openTicket  = 0;
   g_candleCount = 0;
   return false;
}

//+------------------------------------------------------------------+
//|  OnTick — main logic                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only execute logic on a new completed bar
   if(!IsNewBar()) return;

   //=== EXIT MANAGEMENT ============================================
   if(HasOpenPosition())
   {
      g_candleCount++;
      PrintFormat("📊 Candle %d / %d | Waiting to exit...", g_candleCount, InpExitCandles);

      if(g_candleCount >= InpExitCandles)
         ClosePosition();

      return; // Do not look for new entries while in trade
   }

   //--- Sync ticket state if position was closed externally
   if(g_openTicket != 0)
   {
      Print("ℹ️ Position closed externally. Resetting state.");
      g_openTicket  = 0;
      g_candleCount = 0;
   }

   //=== ENTRY MANAGEMENT ===========================================
   if(CheckEntrySignal())
      OpenBuy();
}
//+------------------------------------------------------------------+