//+------------------------------------------------------------------+
//|            EMA Bounce + RSI Momentum EA                         |
//+------------------------------------------------------------------+
#property strict

input double LotSize          = 0.01;
input int    Slippage         = 10;

input int    FastEMA          = 13;    // pullback / bounce MA
input int    SlowEMA          = 55;    // trend bias MA

input int    RsiPeriod        = 7;     // short RSI — momentum direction only
input double RsiMidZone       = 5.0;   // dead-zone around 50 (49–51 = noise, ignored)

input double TouchBuffer      = 0.3;   // ATR fraction: how close wick must come to fast EMA

input int    AtrPeriod        = 14;
input double AtrSlMultiplier  = 1.5;   // virtual SL distance in ATR

input double SarStep          = 0.02;
input double SarMax           = 0.2;

input ulong  MagicNumber      = 123456;

//--- handles
int fastHandle, slowHandle, rsiHandle, atrHandle, sarHandle;

//--- virtual SL
struct VirtualSL { ulong ticket; double sl; };
VirtualSL vsl[];

//+------------------------------------------------------------------+
int OnInit()
{
   fastHandle = iMA (_Symbol, PERIOD_CURRENT, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA (_Symbol, PERIOD_CURRENT, SlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   rsiHandle  = iRSI(_Symbol, PERIOD_CURRENT, RsiPeriod, PRICE_CLOSE);
   atrHandle  = iATR(_Symbol, PERIOD_CURRENT, AtrPeriod);
   sarHandle  = iSAR(_Symbol, PERIOD_CURRENT, SarStep, SarMax);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE ||
      rsiHandle  == INVALID_HANDLE || atrHandle  == INVALID_HANDLE ||
      sarHandle  == INVALID_HANDLE)
      return INIT_FAILED;

   ArrayResize(vsl, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(sarHandle);
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   // 1. virtual SL check
   CheckVirtualStops();

   // 2. copy all buffers (need 4 bars for slope check)
   double fast[], slow[], rsi[], atr[], close[], high[], low[];

   ArraySetAsSeries(fast,  true); ArraySetAsSeries(slow,  true);
   ArraySetAsSeries(rsi,   true); ArraySetAsSeries(atr,   true);
   ArraySetAsSeries(close, true); ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   if(CopyBuffer(fastHandle, 0, 0, 4, fast)           < 4) return;
   if(CopyBuffer(slowHandle, 0, 0, 4, slow)           < 4) return;
   if(CopyBuffer(rsiHandle,  0, 0, 4, rsi)            < 4) return;
   if(CopyBuffer(atrHandle,  0, 0, 4, atr)            < 4) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 4, close) < 4) return;
   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, 4, high)  < 4) return;
   if(CopyLow  (_Symbol, PERIOD_CURRENT, 0, 4, low)   < 4) return;

   double currentPrice = close[0];
   double buf = atr[1] * TouchBuffer;

   // 3. TREND BIAS
   // Slow EMA must be sloping AND price on correct side
   // Use bars [1] vs [3] for slope (avoids single-bar noise)
   bool uptrend   = close[1] > slow[1] && slow[1] > slow[3];
   bool downtrend = close[1] < slow[1] && slow[1] < slow[3];

   // 4. BOUNCE TRIGGER
   // Wick touched (or came within buf of) fast EMA — close recovered on trend side
   // bar[1] is the completed bounce candle
   bool bounceBuy  = low[1]  <= fast[1] + buf && close[1] > fast[1];
   bool bounceSell = high[1] >= fast[1] - buf && close[1] < fast[1];

   // 5. RSI MOMENTUM
   // Must be on correct side of 50 (with dead-zone) AND pointing in trade direction
   double rsiMid = 50.0;
   bool rsiBuy  = rsi[1] > rsiMid + RsiMidZone && rsi[1] > rsi[2];
   bool rsiSell = rsi[1] < rsiMid - RsiMidZone && rsi[1] < rsi[2];

   // 6. FINAL SIGNAL — all three conditions required
   bool buySignal  = uptrend   && bounceBuy  && rsiBuy;
   bool sellSignal = downtrend && bounceSell && rsiSell;

   // 7. trailing SL update
   UpdateTrailingVirtualSL();

   // 8. one position at a time
   if(HasOpenPosition()) return;

   // 9. entry
   if(buySignal)
      OpenBuy (currentPrice - atr[1] * AtrSlMultiplier);

   if(sellSignal)
      OpenSell(currentPrice + atr[1] * AtrSlMultiplier);
}

//+------------------------------------------------------------------+
void CheckVirtualStops()
{
   double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double prevLow  = iLow (_Symbol, PERIOD_CURRENT, 1);

   for(int i = ArraySize(vsl)-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(vsl[i].ticket))
         { ArrayRemove(vsl, i, 1); continue; }

      long type = PositionGetInteger(POSITION_TYPE);
      bool hit  = false;

      if(type == POSITION_TYPE_BUY)  hit = (prevLow  <= vsl[i].sl);
      else                           hit = (prevHigh >= vsl[i].sl);

      if(hit && ClosePosition(vsl[i].ticket))
         ArrayRemove(vsl, i, 1);
   }
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)  == _Symbol &&
            PositionGetInteger(POSITION_MAGIC)  == (long)MagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool OpenBuy(double slPrice)
{
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
   req.type   = ORDER_TYPE_BUY;   req.volume = LotSize;
   req.price  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.sl = 0; req.tp = 0; req.deviation = Slippage; req.magic = MagicNumber;
   if(!OrderSend(req, res)) return false;
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
      { AddVirtualSL(res.order, slPrice); return true; }
   return false;
}

//+------------------------------------------------------------------+
bool OpenSell(double slPrice)
{
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol;
   req.type   = ORDER_TYPE_SELL;  req.volume = LotSize;
   req.price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl = 0; req.tp = 0; req.deviation = Slippage; req.magic = MagicNumber;
   if(!OrderSend(req, res)) return false;
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
      { AddVirtualSL(res.order, slPrice); return true; }
   return false;
}

//+------------------------------------------------------------------+
void AddVirtualSL(ulong ticket, double sl)
{
   int size = ArraySize(vsl);
   ArrayResize(vsl, size + 1);
   vsl[size].ticket = ticket;
   vsl[size].sl     = NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   long type = PositionGetInteger(POSITION_TYPE);
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL; req.position = ticket;
   req.symbol = _Symbol; req.volume = PositionGetDouble(POSITION_VOLUME);
   req.deviation = Slippage; req.magic = MagicNumber;
   if(type == POSITION_TYPE_BUY)
      { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); }
   else
      { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
   if(!OrderSend(req, res)) return false;
   return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL);
}

//+------------------------------------------------------------------+
void UpdateTrailingVirtualSL()
{
   double sar[];
   ArraySetAsSeries(sar, true);
   if(CopyBuffer(sarHandle, 0, 0, 3, sar) < 3) return;
   double sarValue = sar[1];

   for(int i = 0; i < ArraySize(vsl); i++)
   {
      if(!PositionSelectByTicket(vsl[i].ticket)) continue;
      long type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY  && sarValue > vsl[i].sl)
         vsl[i].sl = NormalizeDouble(sarValue, _Digits);
      if(type == POSITION_TYPE_SELL && sarValue < vsl[i].sl)
         vsl[i].sl = NormalizeDouble(sarValue, _Digits);
   }
}