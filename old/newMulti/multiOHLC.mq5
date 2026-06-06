//+------------------------------------------------------------------+
//| ATR Mean Reversion EA — M1 OHLC Virtual Feed v2                 |
//|                                                                  |
//| Corrections vs v1:                                              |
//|  #1  H/L order: Bull=O→L→H→C, Bear=O→H→L→C (docs confirmed)   |
//|  #2  TickVol=1 emits ONLY Close (no Open event)                 |
//|  #12 Spread from rates[0].spread (bar-historical, not live)     |
//|  #13 Prices are Bid-based; Ask = Bid + spread*_Point            |
//|  #20 Position ticket found via immediate scan (no Sleep/poll)   |
//|  #23 NormalizeDouble applied to every price construction         |
//|  #24 Doji detection uses previous bar direction                 |
//+------------------------------------------------------------------+
#property strict
#property description "ATR Mean Reversion — M1 OHLC Virtual Feed v2"

//==================================================================
//  INPUTS
//==================================================================
input group "POSITION SETTINGS"
input double LotSize      = 0.1;
input int    Slippage     = 10;
input double RiskPercent  = 1.0;

input group "INDICATOR SETTINGS"
input int    ATR_Period        = 14;
input double ATR_Multiplier    = 1.5;
input int    Sideways_Period   = 34;
input double Sideways_Buffer   = 155;
input int    meanPeriod        = 50;

input group "STOP LOSS & TAKE PROFIT"
input double SL_Multiplier      = 1.5;
input double TP_Multiplier      = 1.0;
input double TP_Gap_Multiplier  = 1.0;

input group "FEATURE TOGGLES"
input bool useBreakEven = false;

input group "TP SETTINGS"
input bool useATR          = true;
input bool useEma          = false;
input bool useTrailingStop = false;

input group "SAR TRAILING"
input double SAR_Step = 0.02;
input double SAR_Max  = 0.2;

input group "BREAK EVEN"
input double BE_Trigger_ATR = 1.0;
input double BE_Lock_ATR    = 0.2;

//==================================================================
//  VIRTUAL TICK EVENT ENUM
//==================================================================
enum EVirtualTickEvent
{
   VTE_OPEN  = 0,
   VTE_LOW   = 1,   // NOTE: Low comes BEFORE High for bull bars
   VTE_HIGH  = 2,   // NOTE: High comes BEFORE Low  for bear bars
   VTE_CLOSE = 3,
   VTE_NONE  = 4
};

//--- One M1 bar
struct SBarDescriptor
{
   datetime barTime;
   double   O, H, L, C;
   long     tickVol;
   int      spread;    // spread in points at bar time (from rates[].spread)
   bool     bullish;   // C >= O  (after doji resolution)
};

//--- One virtual tick the strategy "sees"
struct SVirtualTick
{
   datetime time;
   double   bid;   // = OHLC price (charts are Bid-based in MT5)
   double   ask;   // = bid + spread * _Point
   double   last;  // = bid (mid-price approximation = bid for forex)
};

//==================================================================
//  MODULE 1 — CVirtualFeed
//  Implements the EXACT MT5 1-Minute OHLC tick generation table:
//
//   TickVol = 1  →  [ Close ]
//   TickVol = 2  →  [ Open, Close ]
//   TickVol = 3  →  [ Open, Low, High, Close ]  (bull)
//                   [ Open, High, Low, Close ]  (bear)
//   TickVol >= 4 →  [ Open, Low, High, Close ]  (bull)
//                   [ Open, High, Low, Close ]  (bear)
//
//  Bull  = C >= O (after doji resolution against previous bar)
//  Bear  = C <  O
//==================================================================
class CVirtualFeed
{
private:
   string   m_symbol;

   SBarDescriptor m_bar;          // current bar being emitted
   SBarDescriptor m_prevBar;      // previous bar (for doji resolution)
   bool           m_hasPrev;

   int  m_seqIdx;                 // next event index
   int  m_seqLen;                 // total events this bar
   EVirtualTickEvent m_seq[4];    // event list

   datetime m_lastBarTime;        // last COMPLETED bar time we loaded

   //--- Resolve doji direction from previous bar
   bool ResolveBullish(bool defaultBull)
   {
      if (m_bar.O != m_bar.C) return defaultBull;
      // Doji: use previous bar direction (opposite)
      if (!m_hasPrev) return defaultBull;
      bool prevBull = (m_prevBar.C >= m_prevBar.O);
      return !prevBull;  // opposite of previous
   }

   //--- Build the event sequence for the loaded bar
   //    Follows MT5 1-Minute OHLC documentation exactly
   void BuildSequence()
   {
      long tv = m_bar.tickVol;
      m_seqIdx = 0;

      //--- TickVol = 1: only Close
      if (tv <= 1)
      {
         m_seqLen = 1;
         m_seq[0] = VTE_CLOSE;
         return;
      }

      //--- TickVol = 2: Open → Close
      if (tv == 2)
      {
         m_seqLen = 2;
         m_seq[0] = VTE_OPEN;
         m_seq[1] = VTE_CLOSE;
         return;
      }

      //--- TickVol >= 3: four OHLC events in direction-correct order
      //    Bull (C >= O): Open → Low → High → Close
      //       (opening shadow goes DOWN to Low first;
      //        range then goes UP to High;
      //        closing shadow comes DOWN to Close)
      //    Bear (C < O):  Open → High → Low → Close
      //       (opening shadow goes UP to High first;
      //        range goes DOWN to Low;
      //        closing shadow goes UP to Close)
      m_seqLen = 4;
      m_seq[0] = VTE_OPEN;
      m_seq[3] = VTE_CLOSE;

      if (m_bar.bullish)
      {
         m_seq[1] = VTE_LOW;    // opening shadow hits Low first
         m_seq[2] = VTE_HIGH;   // then range moves to High
      }
      else
      {
         m_seq[1] = VTE_HIGH;   // opening shadow hits High first
         m_seq[2] = VTE_LOW;    // then range moves to Low
      }
   }

   //--- Get the price level for a given event
   double PriceForEvent(EVirtualTickEvent ev) const
   {
      switch(ev)
      {
         case VTE_OPEN:  return m_bar.O;
         case VTE_HIGH:  return m_bar.H;
         case VTE_LOW:   return m_bar.L;
         case VTE_CLOSE: return m_bar.C;
         default:        return m_bar.C;
      }
   }

   //--- Assign event timestamps spread across the 60-second bar
   //    Open  → barTime
   //    Close → barTime + 59
   //    Middle events evenly spaced between 0 and 59
   datetime TimeForStep(int step) const
   {
      if (m_seqLen == 1) return m_bar.barTime + 59;   // vol=1: Close at end
      if (step == 0)              return m_bar.barTime;
      if (step == m_seqLen - 1)   return m_bar.barTime + 59;
      return m_bar.barTime + (datetime)(step * 59 / (m_seqLen - 1));
   }

   //--- Build a virtual tick from a price level
   //    MT5: OHLC prices in history are Bid prices.
   //    Ask = Bid + spread * _Point
   //    Fix #13: no mid-price split; prices are Bid-based.
   //    Fix #23: NormalizeDouble on every price.
   SVirtualTick MakeTick(datetime t, double bidPrice) const
   {
      double spreadVal = m_bar.spread * _Point;
      SVirtualTick tk;
      tk.time = t;
      tk.bid  = NormalizeDouble(bidPrice, _Digits);
      tk.ask  = NormalizeDouble(bidPrice + spreadVal, _Digits);
      tk.last = tk.bid;
      return tk;
   }

public:
   void Init(string sym)
   {
      m_symbol      = sym;
      m_lastBarTime = 0;
      m_seqIdx      = 4;
      m_seqLen      = 0;
      m_hasPrev     = false;
      ZeroMemory(m_bar);
      ZeroMemory(m_prevBar);
   }

   //--- Called from real OnTick().
   //    Returns true + fills 'tick' when a new virtual event is ready.
   //    Returns false when no new event to emit yet.
   bool Next(SVirtualTick &tick)
   {
      //--- If current sequence is exhausted, try to load next completed bar
      if (m_seqIdx >= m_seqLen)
      {
         datetime barTimes[];
         if (CopyTime(m_symbol, PERIOD_M1, 1, 1, barTimes) <= 0)
            return false;

         datetime newBarTime = barTimes[0];
         if (newBarTime == m_lastBarTime)
            return false;  // already processed this completed bar

         MqlRates rates[];
         if (CopyRates(m_symbol, PERIOD_M1, 1, 1, rates) <= 0)
            return false;

         m_lastBarTime = newBarTime;

         // Carry current → previous
         if (m_lastBarTime > 0)
         {
            m_prevBar = m_bar;
            m_hasPrev = true;
         }

         // Load bar
         m_bar.barTime = rates[0].time;
         m_bar.O       = rates[0].open;
         m_bar.H       = rates[0].high;
         m_bar.L       = rates[0].low;
         m_bar.C       = rates[0].close;
         m_bar.tickVol = rates[0].tick_volume;
         // Fix #12: use bar's historical spread (in integer points)
         m_bar.spread  = (int)rates[0].spread;
         if (m_bar.spread <= 0)
            m_bar.spread = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);

         // Resolve direction (including doji → previous bar direction)
         bool rawBull  = (m_bar.C >= m_bar.O);
         m_bar.bullish = ResolveBullish(rawBull);

         BuildSequence();
      }

      if (m_seqIdx >= m_seqLen) return false;

      EVirtualTickEvent ev = m_seq[m_seqIdx];
      double            px = PriceForEvent(ev);
      datetime          t  = TimeForStep(m_seqIdx);

      tick = MakeTick(t, px);
      m_seqIdx++;
      return true;
   }

   SBarDescriptor CurrentBar() const { return m_bar; }
   bool           HasData()    const { return (m_lastBarTime > 0); }
};

//==================================================================
//  MODULE 2 — CVirtualMarketContext
//  Single source of truth for all strategy-facing prices/time.
//==================================================================
class CVirtualMarketContext
{
private:
   SVirtualTick m_tick;
   bool         m_valid;

public:
   void Init()    { m_valid = false; ZeroMemory(m_tick); }

   void Update(const SVirtualTick &tk)
   {
      m_tick  = tk;
      m_valid = true;
   }

   bool     IsValid() const { return m_valid; }
   double   Bid()     const { return m_tick.bid; }
   double   Ask()     const { return m_tick.ask; }
   double   Last()    const { return m_tick.last; }
   datetime Time()    const { return m_tick.time; }
};

//==================================================================
//  MODULE 3 — SVirtualPosition
//==================================================================
struct SVirtualPosition
{
   ulong    ticket;
   int      type;          // ORDER_TYPE_BUY or ORDER_TYPE_SELL
   double   openPrice;
   double   lotSize;
   double   virtualSL;
   double   virtualTP;
   bool     active;
   datetime openTime;
   long     magic;
};

//==================================================================
//  MODULE 4 — CVirtualPositionMgr
//  Manages all exits virtually without broker-side SL/TP.
//==================================================================
class CVirtualPositionMgr
{
private:
   SVirtualPosition m_pos[256];
   int              m_count;
   string           m_symbol;
   int              m_slippage;

   bool ClosePosition(SVirtualPosition &pos, double bid, double ask)
   {
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req); ZeroMemory(res);

      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = m_symbol;
      req.volume    = pos.lotSize;
      req.magic     = pos.magic;
      req.position  = pos.ticket;
      // Fix #11: zero slippage in tester, configured slippage live
      req.deviation = (MQLInfoInteger(MQL_TESTER) != 0) ? 0 : m_slippage;

      if (pos.type == ORDER_TYPE_BUY)
      {
         req.type  = ORDER_TYPE_SELL;
         req.price = NormalizeDouble(bid, _Digits);
      }
      else
      {
         req.type  = ORDER_TYPE_BUY;
         req.price = NormalizeDouble(ask, _Digits);
      }

      if (OrderSend(req, res))
      {
         if (res.retcode == TRADE_RETCODE_DONE ||
             res.retcode == TRADE_RETCODE_PLACED)
         {
            pos.active = false;
            return true;
         }
      }
      Print("VPosMgr close failed retcode=", res.retcode, " comment=", res.comment);
      return false;
   }

public:
   void Init(string sym, int slip)
   {
      m_symbol   = sym;
      m_slippage = slip;
      m_count    = 0;
      for (int i = 0; i < 256; i++) m_pos[i].active = false;
   }

   void Register(ulong realTicket, int posType, double openPx,
                 double lots, double vSL, double vTP, long magic)
   {
      for (int i = 0; i < 256; i++)
      {
         if (!m_pos[i].active)
         {
            m_pos[i].ticket    = realTicket;
            m_pos[i].type      = posType;
            m_pos[i].openPrice = openPx;
            m_pos[i].lotSize   = lots;
            m_pos[i].virtualSL = NormalizeDouble(vSL, _Digits);  // Fix #24
            m_pos[i].virtualTP = NormalizeDouble(vTP, _Digits);
            m_pos[i].active    = true;
            m_pos[i].openTime  = TimeCurrent();
            m_pos[i].magic     = magic;
            m_count++;
            return;
         }
      }
      Print("VPosMgr: array full");
   }

   //--- Update virtual SL only
   void UpdateVirtualSL(ulong ticket, double newSL)
   {
      for (int i = 0; i < 256; i++)
      {
         if (m_pos[i].active && m_pos[i].ticket == ticket)
         {
            m_pos[i].virtualSL = NormalizeDouble(newSL, _Digits);  // Fix #24
            return;
         }
      }
   }

   //--- Evaluate SL/TP against current virtual tick
   //    Fix #14: BUY exits on Bid; SELL exits on Ask (MT5 standard)
   void Evaluate(const SVirtualTick &tk)
   {
      double bid = tk.bid;
      double ask = tk.ask;

      for (int i = 0; i < 256; i++)
      {
         if (!m_pos[i].active) continue;

         if (m_pos[i].type == ORDER_TYPE_BUY)
         {
            if (m_pos[i].virtualSL > 0.0 && bid <= m_pos[i].virtualSL)
            {
               Print("VPosMgr BUY SL hit bid=", bid, " SL=", m_pos[i].virtualSL);
               ClosePosition(m_pos[i], bid, ask);
               continue;
            }
            if (m_pos[i].virtualTP > 0.0 && bid >= m_pos[i].virtualTP)
            {
               Print("VPosMgr BUY TP hit bid=", bid, " TP=", m_pos[i].virtualTP);
               ClosePosition(m_pos[i], bid, ask);
               continue;
            }
         }
         else
         {
            if (m_pos[i].virtualSL > 0.0 && ask >= m_pos[i].virtualSL)
            {
               Print("VPosMgr SELL SL hit ask=", ask, " SL=", m_pos[i].virtualSL);
               ClosePosition(m_pos[i], bid, ask);
               continue;
            }
            if (m_pos[i].virtualTP > 0.0 && ask <= m_pos[i].virtualTP)
            {
               Print("VPosMgr SELL TP hit ask=", ask, " TP=", m_pos[i].virtualTP);
               ClosePosition(m_pos[i], bid, ask);
               continue;
            }
         }
      }
   }

   int ActiveCount() const
   {
      int n = 0;
      for (int i = 0; i < 256; i++)
         if (m_pos[i].active) n++;
      return n;
   }

   bool GetVirtualLevels(ulong ticket, double &vSL, double &vTP) const
   {
      for (int i = 0; i < 256; i++)
      {
         if (m_pos[i].active && m_pos[i].ticket == ticket)
         {
            vSL = m_pos[i].virtualSL;
            vTP = m_pos[i].virtualTP;
            return true;
         }
      }
      return false;
   }

   //--- Deactivate positions that the broker has already closed
   void Sync()
   {
      for (int i = 0; i < 256; i++)
      {
         if (!m_pos[i].active) continue;
         if (!PositionSelectByTicket(m_pos[i].ticket))
            m_pos[i].active = false;
      }
   }
};

//==================================================================
//  MODULE 5 — CVirtualExecution
//  Places broker orders without SL/TP; registers virtual levels.
//  Fix #20: resolves position ticket by immediate scan (no Sleep).
//==================================================================
class CVirtualExecution
{
private:
   CVirtualPositionMgr *m_mgr;
   string               m_symbol;
   int                  m_slippage;

   //--- Find the position ticket that was just opened
   //    Scans all positions for matching magic+symbol+recent open time
   //    Fix #20: replaces the fragile Sleep+poll loop
   ulong FindNewPositionTicket(long magic, datetime openedAfter)
   {
      for (int i = 0; i < PositionsTotal(); i++)
      {
         ulong t = PositionGetTicket(i);
         if (!PositionSelectByTicket(t)) continue;
         if (PositionGetInteger(POSITION_MAGIC)  != magic)      continue;
         if (PositionGetString (POSITION_SYMBOL) != m_symbol)   continue;
         datetime pt = (datetime)PositionGetInteger(POSITION_TIME);
         if (pt >= openedAfter)
            return t;
      }
      return 0;
   }

public:
   void Init(CVirtualPositionMgr *mgr, string sym, int slip)
   {
      m_mgr      = mgr;
      m_symbol   = sym;
      m_slippage = slip;
   }

   bool MarketOrder(int orderType, double lots, double virtualSL, double virtualTP,
                    long magic, double &filledPrice)
   {
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req); ZeroMemory(res);

      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = m_symbol;
      req.volume    = lots;
      req.type      = (ENUM_ORDER_TYPE)orderType;
      req.deviation = (MQLInfoInteger(MQL_TESTER) != 0) ? 0 : m_slippage;
      req.magic     = magic;
      req.sl        = 0.0;   // virtual SL — never on broker
      req.tp        = 0.0;   // virtual TP — never on broker
      req.price     = (orderType == ORDER_TYPE_BUY)
                      ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                      : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      datetime sendTime = TimeCurrent();

      if (!OrderSend(req, res))
      {
         Print("VExec OrderSend error=", GetLastError(), " retcode=", res.retcode);
         return false;
      }
      if (res.retcode != TRADE_RETCODE_DONE &&
          res.retcode != TRADE_RETCODE_PLACED)
      {
         Print("VExec rejected retcode=", res.retcode, " comment=", res.comment);
         return false;
      }

      filledPrice = NormalizeDouble(res.price, _Digits);

      // Fix #20: immediate position scan, no Sleep()
      ulong posTicket = FindNewPositionTicket(magic, sendTime);
      if (posTicket == 0)
      {
         // Fallback: use deal number (sub-optimal but better than 0)
         posTicket = res.deal;
         Print("VExec: fallback to deal ticket ", posTicket);
      }

      m_mgr.Register(posTicket, orderType, filledPrice, lots,
                     virtualSL, virtualTP, magic);
      return true;
   }
};

//==================================================================
//  GLOBAL INSTANCES
//==================================================================
CVirtualFeed         gFeed;
CVirtualMarketContext gCtx;
CVirtualPositionMgr  gPosMgr;
CVirtualExecution    gExec;

int atrHandle, maHandle, sidewayHandle, sarHandle;

//==================================================================
//  FORWARD DECLARATIONS
//==================================================================
void   strategyOnTick();
bool   isSideways();
void   managePosition();
void   tradeBuy (double sl, double tp, double currentPrice);
void   tradeSell(double sl, double tp, double currentPrice);
void   modifyVirtualSL(ulong ticket, double newSL, double tp);
double calculateLot(double slDist);

//==================================================================
//  OnInit
//==================================================================
int OnInit()
{
   // All handles pinned to M1 — matches the virtual feed's data source
   atrHandle     = iATR (_Symbol, PERIOD_M1, ATR_Period);
   maHandle      = iMA  (_Symbol, PERIOD_M1, meanPeriod,      0, MODE_SMA, PRICE_CLOSE);
   sidewayHandle = iMA  (_Symbol, PERIOD_M1, Sideways_Period, 0, MODE_SMA, PRICE_CLOSE);
   sarHandle     = iSAR (_Symbol, PERIOD_M1, SAR_Step, SAR_Max);

   if (atrHandle     == INVALID_HANDLE || maHandle      == INVALID_HANDLE ||
       sidewayHandle == INVALID_HANDLE || sarHandle     == INVALID_HANDLE)
   {
      Print("OnInit: indicator handle error ", GetLastError());
      return INIT_FAILED;
   }

   gFeed.Init  (_Symbol);
   gCtx .Init  ();
   gPosMgr.Init(_Symbol, Slippage);
   gExec.Init  (&gPosMgr, _Symbol, Slippage);

   Print("M1 OHLC Virtual Feed v2 initialized.");
   return INIT_SUCCEEDED;
}

//==================================================================
//  OnDeinit
//==================================================================
void OnDeinit(const int reason)
{
   IndicatorRelease(atrHandle);
   IndicatorRelease(maHandle);
   IndicatorRelease(sidewayHandle);
   IndicatorRelease(sarHandle);
}

//==================================================================
//  OnTick — real broker tick pumps the virtual feed
//==================================================================
void OnTick()
{
   // Sync virtual records with actual broker positions
   gPosMgr.Sync();

   // Drain all pending virtual ticks produced from completed M1 bars
   SVirtualTick vTick;
   while (gFeed.Next(vTick))
   {
      gCtx.Update(vTick);

      // Fix #18: Evaluate exits BEFORE strategy logic (same as MT5 tester order)
      gPosMgr.Evaluate(vTick);

      strategyOnTick();
   }
}

//==================================================================
//  strategyOnTick — original logic, reads only from gCtx/gPosMgr
//==================================================================
void strategyOnTick()
{
   if (!gCtx.IsValid()) return;

   managePosition();

   if (!isSideways())                return;
   if (gPosMgr.ActiveCount() > 0)    return;

   double atr[], ma[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(ma,  true);

   if (CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0) return;
   if (CopyBuffer(maHandle,  0, 0, 3, ma)  <= 0) return;

   // Fix #6/#7: index 1 = last fully CLOSED bar's indicator value.
   // In OHLC tester, when a bar's events fire, that bar is completed.
   // atr[1] / ma[1] are from the completed bar we're generating events for.
   double currentATR   = atr[1];
   double currentMA    = ma[1];
   // Fix #7: virtual price from gCtx, not CopyClose
   double currentPrice = gCtx.Last();

   double deviation = MathAbs(currentPrice - currentMA);
   double threshold = currentATR * ATR_Multiplier;

   double sl, tp;

   if (useATR)
   {
      if (currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + (currentATR * SL_Multiplier);
         tp = currentPrice - (currentATR * TP_Multiplier);
         tradeSell(sl, tp, currentPrice);
      }
      if (currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - (currentATR * SL_Multiplier);
         tp = currentPrice + (currentATR * TP_Multiplier);
         tradeBuy(sl, tp, currentPrice);
      }
   }
   else if (useEma)
   {
      if (currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + (currentATR * SL_Multiplier);
         tp = currentMA    + (currentATR * TP_Gap_Multiplier);
         tradeSell(sl, tp, currentPrice);
      }
      if (currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - (currentATR * SL_Multiplier);
         tp = currentMA    - (currentATR * TP_Gap_Multiplier);
         tradeBuy(sl, tp, currentPrice);
      }
   }
   else if (useTrailingStop)
   {
      if (currentPrice > currentMA && deviation > threshold)
      {
         sl = currentPrice + (currentATR * SL_Multiplier);
         tp = currentMA    + (currentATR * TP_Gap_Multiplier);
         tradeSell(sl, tp, currentPrice);
      }
      if (currentPrice < currentMA && deviation > threshold)
      {
         sl = currentPrice - (currentATR * SL_Multiplier);
         tp = currentMA    - (currentATR * TP_Gap_Multiplier);
         tradeBuy(sl, tp, currentPrice);
      }
   }
}

//==================================================================
//  isSideways — unchanged logic; uses indicator series on M1
//==================================================================
bool isSideways()
{
   double sideway[], atr[];
   ArraySetAsSeries(sideway, true);
   ArraySetAsSeries(atr,     true);

   if (CopyBuffer(sidewayHandle, 0, 0, 3, sideway) <= 0) return false;
   if (CopyBuffer(atrHandle,     0, 0, 3, atr)     <= 0) return false;

   // Fix #6: use closed bar values (index 1 and 2)
   double sideway_diff = MathAbs(sideway[1] - sideway[2]);
   double buffer_fixed = Sideways_Buffer * _Point;
   double buffer_atr   = atr[1] * 0.2;

   return (sideway_diff <= buffer_fixed + buffer_atr);
}

//==================================================================
//  managePosition — reads virtual Bid/Ask from gCtx
//==================================================================
void managePosition()
{
   if (gPosMgr.ActiveCount() <= 0) return;

   double atr[], sar[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(sar, true);

   if (CopyBuffer(atrHandle, 0, 0, 3, atr) <= 0) return;
   if (CopyBuffer(sarHandle,  0, 0, 3, sar) <= 0) return;

   double currentATR = atr[1];  // Fix #6: closed bar
   double currentSAR = sar[1];

   double vBid = gCtx.Bid();
   double vAsk = gCtx.Ask();

   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int    type      = (int)PositionGetInteger(POSITION_TYPE);

      double vSL = 0, vTP = 0;
      if (!gPosMgr.GetVirtualLevels(ticket, vSL, vTP)) continue;

      double price = (type == POSITION_TYPE_BUY) ? vBid : vAsk;

      //--- BREAK EVEN — Fix #15: uses virtual price
      if (useBreakEven)
      {
         double trigger = currentATR * BE_Trigger_ATR;
         double lock    = currentATR * BE_Lock_ATR;

         if (type == POSITION_TYPE_BUY)
         {
            if (price - openPrice >= trigger)
            {
               double newSL = NormalizeDouble(openPrice + lock, _Digits);
               if (newSL > vSL)
                  modifyVirtualSL(ticket, newSL, vTP);
            }
         }
         else
         {
            if (openPrice - price >= trigger)
            {
               double newSL = NormalizeDouble(openPrice - lock, _Digits);
               if (newSL < vSL || vSL == 0)
                  modifyVirtualSL(ticket, newSL, vTP);
            }
         }
      }

      //--- TRAILING SAR — Fix #16: uses virtual price for comparison
      if (useTrailingStop)
      {
         if (type == POSITION_TYPE_BUY)
         {
            if (currentSAR > vSL && currentSAR < price)
               modifyVirtualSL(ticket, NormalizeDouble(currentSAR, _Digits), vTP);
         }
         else
         {
            if (currentSAR < vSL && currentSAR > price)
               modifyVirtualSL(ticket, NormalizeDouble(currentSAR, _Digits), vTP);
         }
      }
   }
}

//==================================================================
//  modifyVirtualSL — updates gPosMgr only; NO broker SLTP call
//==================================================================
void modifyVirtualSL(ulong ticket, double newSL, double tp)
{
   gPosMgr.UpdateVirtualSL(ticket, newSL);
   // Broker order is NOT modified — SL/TP live only in gPosMgr
}

//==================================================================
//  tradeBuy / tradeSell — route through CVirtualExecution
//==================================================================
void tradeBuy(double sl, double tp, double currentPrice)
{
   double slDist  = MathAbs(currentPrice - sl);
   double lot     = calculateLot(slDist);
   double filled  = 0;
   // Fix #24: normalize SL/TP before passing to execution layer
   gExec.MarketOrder(ORDER_TYPE_BUY, lot,
                     NormalizeDouble(sl, _Digits),
                     NormalizeDouble(tp, _Digits),
                     123456, filled);
}

void tradeSell(double sl, double tp, double currentPrice)
{
   double slDist  = MathAbs(currentPrice - sl);
   double lot     = calculateLot(slDist);
   double filled  = 0;
   gExec.MarketOrder(ORDER_TYPE_SELL, lot,
                     NormalizeDouble(sl, _Digits),
                     NormalizeDouble(tp, _Digits),
                     123456, filled);
}

//==================================================================
//  calculateLot — unchanged
//==================================================================
double calculateLot(double slPriceDistance)
{
   double balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney     = balance * (RiskPercent / 100.0);
   double tickValue     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double valuePerPoint = tickValue / tickSize;
   double slPoints      = slPriceDistance / _Point;

   if (slPoints <= 0) return LotSize;

   double lot     = riskMoney / (slPoints * valuePerPoint);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lotStep) * lotStep;
   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

//==================================================================
//  OnTester — unchanged
//==================================================================
double OnTester()
{
   double profit   = TesterStatistics(STAT_PROFIT);
   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades   = TesterStatistics(STAT_TRADES);
   double sharpe   = TesterStatistics(STAT_SHARPE_RATIO);

   if (trades   < 50) return -1000;
   if (drawdown <= 0) return -1000;

   return (profit * (1.0 / drawdown)) * sharpe * MathLog(trades);
}

//+------------------------------------------------------------------+
//  VALIDATION REPORT (revision 2)
//
//  SEQUENCE CORRECTIONS (from official docs):
//  ------------------------------------------
//  TickVol=1:     [Close]               — NOT [Open] as before
//  TickVol=2:     [Open, Close]
//  TickVol=3 Bull:[Open, Low, High, Close]  — Low precedes High
//  TickVol=3 Bear:[Open, High, Low, Close]  — High precedes Low
//  TickVol>=4 Bull:[Open, Low, High, Close] — same direction rule
//  TickVol>=4 Bear:[Open, High, Low, Close]
//  Doji (C==O):   direction = opposite of previous bar
//
//  Rationale for Bull order O→L→H→C:
//    The "opening shadow" on a bull candle is the lower wick.
//    Price descends from Open toward Low (the opening shadow),
//    then the body range ascends from Low to High,
//    then the closing shadow descends from High to Close.
//    This matches the ideal 3-5-3 distribution documented by MT.
//
//  SPREAD FIX:
//  -----------
//    rates[0].spread is the integer spread stored in M1 history.
//    This matches what the MT5 tester uses per bar ("spread fixed
//    in the appropriate bar"). Previously live SYMBOL_SPREAD was
//    used — wrong for historical testing and live replay.
//
//  BID/ASK FIX:
//  ------------
//    OHLC prices in MT5 history are Bid prices (charts are Bid).
//    Ask = Bid + spread * _Point.
//    Previous implementation used Mid ± spread/2 which is incorrect.
//
//  POSITION TICKET FIX:
//  --------------------
//    After OrderSend succeeds, an immediate scan of PositionsTotal()
//    finds the new position by magic+symbol+openTime >= sendTime.
//    This is deterministic and avoids the brittle Sleep()+poll.
//
//  INDICATOR SHIFT FIX:
//  --------------------
//    Strategy now reads index [1] (last CLOSED bar) for all
//    indicator values and indicator-derived sideways comparisons.
//    Index [0] is the currently-forming live bar which may not
//    correspond to the bar whose OHLC events we are processing.
//+------------------------------------------------------------------+