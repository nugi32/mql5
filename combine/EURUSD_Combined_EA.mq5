//+------------------------------------------------------------------+
//| EURUSD_Combined_EA.mq5                                           |
//|                                                                  |
//| One EA that merges the 5 walk-forward EAs from "onTest":         |
//|                                                                  |
//|  Model 1 : EURUSD_H1_run2012_w0004          (H1,  SHORT, 11 bars)|
//|  Model 2 : EURUSD_M30_run2010_w0002         (M30, SHORT, 24 bars)|
//|  Model 3 : EURUSD_M30_run2010_w0003         (M30, SHORT, 24 bars)|
//|  Model 4 : EURUSD_M5_run2010_window0003     (M5,  SHORT, 138 bars)|
//|  Model 5 : EURU  SD_M5_run2010_window0005     (M5,  SHORT, 114 bars)|
//|                                                                  |
//| Design:                                                          |
//|  - No external library. Everything is in this single file.       |
//|  - ONE lot input (InpLots) shared by all models, ONE lot         |
//|    calculator (CalcLots).                                        |
//|  - Each model has its own enable/disable bool.                   |
//|  - Each model is its own class with its own indicator handles,   |
//|    its own magic number and its own entry condition.             |
//|  - Entry/exit rules are copied 1:1 from the original EAs.        |
//|  - No broker SL/TP. Exit = close after N bars (per model).       |
//|                                                                  |
//| Every model works on its own hardcoded timeframe (H1/M30/M5), so |
//| the EA can be attached to a chart of ANY timeframe on EURUSD.    |
//|                                                                  |
//| IMPORTANT: all models are SHORT on the same symbol, and each     |
//| model is tracked by its magic number. Use a HEDGING account.     |
//+------------------------------------------------------------------+
#property copyright   "EURUSD Combined"
#property version     "1.00"
#property description "Combined EURUSD walk-forward EA (5 models, 1 lot input, per-model enable)"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Global ==="
input double InpLots = 0.10;                // Lot size (applies to ALL models)

input group "=== Model 1 | H1 | run_2012 / w0004 | SHORT | hold 11 bars ==="
input bool   InpH1W4_Enable    = true;      // Enable this model
input ulong  InpH1W4_Magic     = 9002004;   // Magic number
input int    InpH1W4_Deviation = 30;        // Max slippage (points)

input group "=== Model 2 | M30 | run_2010 / w0002 | SHORT | EURUSD_M30_71 ==="
input bool   InpM30W2_Enable       = true;  // Enable this model
input int    InpM30W2_Magic        = 710002;// Magic number
input int    InpM30W2_Deviation    = 20;    // Max slippage (points)
input int    InpM30W2_HoldBars     = 24;    // Close after N bars
input bool   InpM30W2_AllowOverlap = false; // Allow multiple positions (hedging account only)

input group "=== Model 3 | M30 | run_2010 / w0003 | SHORT | EURUSD_M30_2 ==="
input bool   InpM30W3_Enable       = true;  // Enable this model
input int    InpM30W3_Magic        = 710003;// Magic number
input int    InpM30W3_Deviation    = 20;    // Max slippage (points)
input int    InpM30W3_HoldBars     = 24;    // Close after N bars
input bool   InpM30W3_AllowOverlap = false; // Allow multiple positions (hedging account only)

input group "=== Model 4 | M5 | run_2010 / window_0003 | SHORT | EURUSD_M5_121 ==="
input bool   InpM5W3_Enable       = true;      // Enable this model
input ulong  InpM5W3_Magic        = 520100003; // Magic number
input int    InpM5W3_Slippage     = 20;        // Max deviation (points)
input int    InpM5W3_MaxPositions = 0;         // Max open positions (0 = unlimited, hedging account needed)

input group "=== Model 5 | M5 | run_2010 / window_0005 | SHORT | EURUSD_M5_6 ==="
input bool   InpM5W5_Enable       = true;      // Enable this model
input ulong  InpM5W5_Magic        = 520100005; // Magic number
input int    InpM5W5_Slippage     = 20;        // Max deviation (points)
input int    InpM5W5_MaxPositions = 0;         // Max open positions (0 = unlimited, hedging account needed)

//+------------------------------------------------------------------+
//| SECTION 1 - SHARED HELPERS                                       |
//+------------------------------------------------------------------+

//--- Single lot calculator used by every model.
//--- Rounds DOWN to the broker volume step and clamps to min/max volume.
double CalcLots()
  {
   double lots  = InpLots;
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(vstep > 0.0)
      lots = MathFloor(lots / vstep + 1e-8) * vstep;
   lots = MathMax(vmin, MathMin(vmax, lots));

   int digits = 2;
   if(vstep > 0.0)
      digits = (int)MathMax(0.0, MathRound(-MathLog10(vstep)));
   return NormalizeDouble(lots, digits);
  }

//--- Read one indicator buffer value at a given shift.
//--- reject_empty = false reproduces the H1 original (no EMPTY_VALUE check).
bool ReadBuf(const int handle, const int buffer, const int shift,
             double &value, const bool reject_empty = true)
  {
   if(handle == INVALID_HANDLE)
      return false;

   double b[1];
   if(CopyBuffer(handle, buffer, shift, 1, b) != 1)
      return false;
   if(!MathIsValidNumber(b[0]))
      return false;
   if(reject_empty && b[0] == EMPTY_VALUE)
      return false;

   value = b[0];
   return true;
  }

//--- Release an indicator handle safely
void ReleaseHandle(int &handle)
  {
   if(handle != INVALID_HANDLE)
     {
      IndicatorRelease(handle);
      handle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| SECTION 2 - BASE CLASS (shared trade engine, no strategy logic)  |
//|                                                                  |
//| Per new bar of the model's own timeframe:                        |
//|   1) close positions older than m_hold_bars                      |
//|   2) check the position policy (CanOpenNew)                      |
//|   3) check the entry signal (EntrySignal) and open at market     |
//+------------------------------------------------------------------+
class CEdgeModel
  {
protected:
   string           m_name;            // model name (used in logs)
   string           m_comment;         // order comment
   ENUM_TIMEFRAMES  m_tf;              // model timeframe
   ulong            m_magic;           // magic number of this model
   int              m_deviation;       // max slippage (points)
   int              m_hold_bars;       // close after N bars
   bool             m_is_short;        // true = SELL, false = BUY
   bool             m_skip_first_bar;  // true = first tick after attach is NOT a new bar
   datetime         m_last_bar_time;
   CTrade           m_trade;

   //--- Implemented by each model
   virtual bool     CanOpenNew()        = 0;   // position policy
   virtual bool     EntrySignal()       = 0;   // entry condition
   virtual bool     CreateIndicators()  = 0;
   virtual void     ReleaseIndicators() = 0;
   virtual bool     CheckEnvironment()  { return true; }   // optional symbol checks

   //--- True once per new bar of m_tf
   bool IsNewBar()
     {
      datetime t = iTime(_Symbol, m_tf, 0);
      if(t == 0 || t == m_last_bar_time)
         return false;
      m_last_bar_time = t;
      return true;
     }

   //--- Number of open positions of this model (symbol + magic)
   int CountPositions()
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         n++;
        }
      return n;
     }

   //--- Close every position that has lived for >= m_hold_bars bars.
   //--- Age comes from POSITION_TIME, so it survives EA restarts.
   void CloseExpired()
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         int bars_alive  = iBarShift(_Symbol, m_tf, opened, false);
         if(bars_alive < 0)
            continue;

         if(bars_alive >= m_hold_bars)
           {
            if(!m_trade.PositionClose(ticket))
               PrintFormat("[%s] close failed #%I64u, retcode=%u (%s)", m_name, ticket,
                           m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
           }
        }
     }

   //--- Market order, NO SL and NO TP. Lot size comes from CalcLots().
   bool OpenMarket()
     {
      double lots = CalcLots();
      bool   ok;

      if(m_is_short)
         ok = m_trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, m_comment);
      else
         ok = m_trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, m_comment);

      if(!ok)
         PrintFormat("[%s] open failed, retcode=%u (%s)", m_name,
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      return ok;
     }

public:
   CEdgeModel()
     {
      m_name           = "";
      m_comment        = "";
      m_tf             = PERIOD_CURRENT;
      m_magic          = 0;
      m_deviation      = 20;
      m_hold_bars      = 1;
      m_is_short       = true;
      m_skip_first_bar = false;
      m_last_bar_time  = 0;
     }
   virtual ~CEdgeModel() {}

   string Name() const { return m_name; }

   bool Init()
     {
      if(!CheckEnvironment())
         return false;

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_deviation);
      m_trade.SetTypeFillingBySymbol(_Symbol);

      // M5 originals do not treat the very first tick after attach as a new bar;
      // H1 and M30 originals do. This flag keeps each model identical to its original.
      m_last_bar_time = m_skip_first_bar ? iTime(_Symbol, m_tf, 0) : 0;

      if(!CreateIndicators())
        {
         PrintFormat("[%s] ERROR: failed to create indicator handle(s)", m_name);
         return false;
        }

      PrintFormat("[%s] ready | %s %s | hold=%d bars | magic=%I64u | no SL/TP",
                  m_name, _Symbol, EnumToString(m_tf), m_hold_bars, m_magic);
      return true;
     }

   void Deinit() { ReleaseIndicators(); }

   //--- Called from OnTick()
   void Run()
     {
      if(!IsNewBar())
         return;

      CloseExpired();            // 1) exit by time
      if(!CanOpenNew())          // 2) position policy
         return;
      if(EntrySignal())          // 3) entry on closed-bar signal
         OpenMarket();
     }
  };

//+------------------------------------------------------------------+
//| SECTION 3 - MODEL 1 : EURUSD H1 | run_2012 / window_0004         |
//| Source : EURUSD_H1_run2012_w0004.mq5                             |
//| Rule   : SHORT when                                              |
//|   stoch_14_3_3_k > 80 AND cci_14 > 50 AND                        |
//|   ma_5_lwma < close AND mom_10 > 0                               |
//| Exit   : close after 11 bars | one position at a time            |
//+------------------------------------------------------------------+
class CModelH1W4 : public CEdgeModel
  {
private:
   int m_h_stoch_14_3_3_k;
   int m_h_cci_14;
   int m_h_ma_5_lwma;
   int m_h_mom_10;

protected:
   //--- One position at a time
   virtual bool CanOpenNew()
     {
      return (CountPositions() == 0);
     }

   //--- Evaluated on the last CLOSED bar (shift 1)
   virtual bool EntrySignal()
     {
      double stoch_14_3_3_k, cci_14, ma_5_lwma, mom_10;
      if(!ReadBuf(m_h_stoch_14_3_3_k, 0, 1, stoch_14_3_3_k, false)) return false;
      if(!ReadBuf(m_h_cci_14,         0, 1, cci_14,         false)) return false;
      if(!ReadBuf(m_h_ma_5_lwma,      0, 1, ma_5_lwma,      false)) return false;
      if(!ReadBuf(m_h_mom_10,         0, 1, mom_10,         false)) return false;

      double close_1 = iClose(_Symbol, PERIOD_H1, 1);
      if(close_1 <= 0.0) return false;

      return (stoch_14_3_3_k > 80.0 && cci_14 > 50.0 && ma_5_lwma < close_1 && mom_10 > 0.0);
     }

   virtual bool CreateIndicators()
     {
      m_h_stoch_14_3_3_k = iStochastic(_Symbol, PERIOD_H1, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
      m_h_cci_14         = iCCI(_Symbol, PERIOD_H1, 14, PRICE_TYPICAL);
      m_h_ma_5_lwma      = iMA(_Symbol, PERIOD_H1, 5, 0, MODE_LWMA, PRICE_CLOSE);
      m_h_mom_10         = iMomentum(_Symbol, PERIOD_H1, 10, PRICE_CLOSE);

      return (m_h_stoch_14_3_3_k != INVALID_HANDLE &&
              m_h_cci_14         != INVALID_HANDLE &&
              m_h_ma_5_lwma      != INVALID_HANDLE &&
              m_h_mom_10         != INVALID_HANDLE);
     }

   virtual void ReleaseIndicators()
     {
      ReleaseHandle(m_h_stoch_14_3_3_k);
      ReleaseHandle(m_h_cci_14);
      ReleaseHandle(m_h_ma_5_lwma);
      ReleaseHandle(m_h_mom_10);
     }

public:
   CModelH1W4()
     {
      m_h_stoch_14_3_3_k = INVALID_HANDLE;
      m_h_cci_14         = INVALID_HANDLE;
      m_h_ma_5_lwma      = INVALID_HANDLE;
      m_h_mom_10         = INVALID_HANDLE;

      m_name           = "H1_run2012_w0004";
      m_comment        = "run2012_w0004";
      m_tf             = PERIOD_H1;
      m_magic          = InpH1W4_Magic;
      m_deviation      = InpH1W4_Deviation;
      m_hold_bars      = 11;
      m_is_short       = true;
      m_skip_first_bar = false;
     }
  };

//+------------------------------------------------------------------+
//| SECTION 4 - M30 MODELS (shared snapshot, separate conditions)    |
//| Source : eurusdM30 EdgeCore.mqh                                  |
//| The original M30 engine builds one snapshot of all indicators on |
//| the last closed bar and only trades if ALL of them are readable. |
//| That behaviour is kept here. Each M30 model only supplies its    |
//| own EdgeCondition().                                             |
//+------------------------------------------------------------------+

//--- Indicator values at the last closed bar (names match report/CSV columns)
struct EdgeSnapshot
  {
   double close;
   double rsi_7, rsi_14, rsi_21;
   double stoch_5_3_3_k;
   double cci_14;
   double mom_10;
   double ma_5_sma, ma_5_ema, ma_5_lwma;
  };

class CEdgeModelM30 : public CEdgeModel
  {
protected:
   bool m_allow_overlap;

   int  m_h_rsi_7, m_h_rsi_14, m_h_rsi_21;
   int  m_h_stoch_5_3_3;
   int  m_h_cci_14;
   int  m_h_mom_10;
   int  m_h_ma_5_sma, m_h_ma_5_ema, m_h_ma_5_lwma;

   //--- Implemented by each M30 model (condition exactly as in the report)
   virtual bool EdgeCondition(const EdgeSnapshot &s) = 0;

   virtual bool CheckEnvironment()
     {
      if(StringFind(_Symbol, "EURUSD") < 0)
         Print("WARNING: edges were researched on EURUSD, current symbol is ", _Symbol);

      // Overlap is only possible on a hedging account
      if(m_allow_overlap &&
         (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
        {
         PrintFormat("[%s] WARNING: not a hedging account, AllowOverlap forced to false.", m_name);
         m_allow_overlap = false;
        }
      return true;
     }

   //--- No overlap = one position at a time
   virtual bool CanOpenNew()
     {
      if(!m_allow_overlap && CountPositions() > 0)
         return false;
      return true;
     }

   bool BuildSnapshot(EdgeSnapshot &s)
     {
      double c[1];
      if(CopyClose(_Symbol, m_tf, 1, 1, c) != 1) return false;
      s.close = c[0];

      if(!ReadBuf(m_h_rsi_7,       0, 1, s.rsi_7))         return false;
      if(!ReadBuf(m_h_rsi_14,      0, 1, s.rsi_14))        return false;
      if(!ReadBuf(m_h_rsi_21,      0, 1, s.rsi_21))        return false;
      if(!ReadBuf(m_h_stoch_5_3_3, 0, 1, s.stoch_5_3_3_k)) return false; // buffer 0 = %K
      if(!ReadBuf(m_h_cci_14,      0, 1, s.cci_14))        return false;
      if(!ReadBuf(m_h_mom_10,      0, 1, s.mom_10))        return false;
      if(!ReadBuf(m_h_ma_5_sma,    0, 1, s.ma_5_sma))      return false;
      if(!ReadBuf(m_h_ma_5_ema,    0, 1, s.ma_5_ema))      return false;
      if(!ReadBuf(m_h_ma_5_lwma,   0, 1, s.ma_5_lwma))     return false;
      return true;
     }

   virtual bool EntrySignal()
     {
      EdgeSnapshot s;
      if(!BuildSnapshot(s))
         return false;
      return EdgeCondition(s);
     }

   virtual bool CreateIndicators()
     {
      m_h_rsi_7       = iRSI(_Symbol, PERIOD_M30, 7,  PRICE_CLOSE);
      m_h_rsi_14      = iRSI(_Symbol, PERIOD_M30, 14, PRICE_CLOSE);
      m_h_rsi_21      = iRSI(_Symbol, PERIOD_M30, 21, PRICE_CLOSE);
      m_h_stoch_5_3_3 = iStochastic(_Symbol, PERIOD_M30, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
      m_h_cci_14      = iCCI(_Symbol, PERIOD_M30, 14, PRICE_TYPICAL);
      m_h_mom_10      = iMomentum(_Symbol, PERIOD_M30, 10, PRICE_CLOSE);
      m_h_ma_5_sma    = iMA(_Symbol, PERIOD_M30, 5, 0, MODE_SMA,  PRICE_CLOSE);
      m_h_ma_5_ema    = iMA(_Symbol, PERIOD_M30, 5, 0, MODE_EMA,  PRICE_CLOSE);
      m_h_ma_5_lwma   = iMA(_Symbol, PERIOD_M30, 5, 0, MODE_LWMA, PRICE_CLOSE);

      return (m_h_rsi_7 != INVALID_HANDLE && m_h_rsi_14 != INVALID_HANDLE && m_h_rsi_21 != INVALID_HANDLE &&
              m_h_stoch_5_3_3 != INVALID_HANDLE && m_h_cci_14 != INVALID_HANDLE && m_h_mom_10 != INVALID_HANDLE &&
              m_h_ma_5_sma != INVALID_HANDLE && m_h_ma_5_ema != INVALID_HANDLE && m_h_ma_5_lwma != INVALID_HANDLE);
     }

   virtual void ReleaseIndicators()
     {
      ReleaseHandle(m_h_rsi_7);
      ReleaseHandle(m_h_rsi_14);
      ReleaseHandle(m_h_rsi_21);
      ReleaseHandle(m_h_stoch_5_3_3);
      ReleaseHandle(m_h_cci_14);
      ReleaseHandle(m_h_mom_10);
      ReleaseHandle(m_h_ma_5_sma);
      ReleaseHandle(m_h_ma_5_ema);
      ReleaseHandle(m_h_ma_5_lwma);
     }

public:
   CEdgeModelM30()
     {
      m_h_rsi_7 = m_h_rsi_14 = m_h_rsi_21 = INVALID_HANDLE;
      m_h_stoch_5_3_3 = m_h_cci_14 = m_h_mom_10 = INVALID_HANDLE;
      m_h_ma_5_sma = m_h_ma_5_ema = m_h_ma_5_lwma = INVALID_HANDLE;

      m_tf             = PERIOD_M30;
      m_is_short       = true;
      m_skip_first_bar = false;
      m_allow_overlap  = false;
     }
  };

//+------------------------------------------------------------------+
//| MODEL 2 : EURUSD M30 | run_2010 / window_0002 | EURUSD_M30_71    |
//| Source : EURUSD_M30_run2010_w0002.mq5                            |
//| Rule   : SHORT when rsi_7 > 80 AND stoch_5_3_3_k > 80 AND        |
//|          mom_10 > 0                                              |
//| Exit   : close after InpM30W2_HoldBars bars (default 24)         |
//+------------------------------------------------------------------+
class CModelM30W2 : public CEdgeModelM30
  {
protected:
   virtual bool EdgeCondition(const EdgeSnapshot &s)
     {
      return (s.rsi_7 > 80.0
              && s.stoch_5_3_3_k > 80.0
              && s.mom_10 > 0.0);
     }

public:
   CModelM30W2()
     {
      m_name          = "EURUSD_M30_71";
      m_comment       = "EURUSD_M30_71";
      m_magic         = (ulong)InpM30W2_Magic;
      m_deviation     = InpM30W2_Deviation;
      m_hold_bars     = InpM30W2_HoldBars;
      m_allow_overlap = InpM30W2_AllowOverlap;
     }
  };

//+------------------------------------------------------------------+
//| MODEL 3 : EURUSD M30 | run_2010 / window_0003 | EURUSD_M30_2     |
//| Source : EURUSD_M30_run2010_w0003.mq5                            |
//| Rule   : SHORT when rsi_7 > 75                                   |
//| Exit   : close after InpM30W3_HoldBars bars (default 24)         |
//+------------------------------------------------------------------+
class CModelM30W3 : public CEdgeModelM30
  {
protected:
   virtual bool EdgeCondition(const EdgeSnapshot &s)
     {
      return (s.rsi_7 > 75.0);
     }

public:
   CModelM30W3()
     {
      m_name          = "EURUSD_M30_2";
      m_comment       = "EURUSD_M30_2";
      m_magic         = (ulong)InpM30W3_Magic;
      m_deviation     = InpM30W3_Deviation;
      m_hold_bars     = InpM30W3_HoldBars;
      m_allow_overlap = InpM30W3_AllowOverlap;
     }
  };

//+------------------------------------------------------------------+
//| SECTION 5 - M5 MODELS (shared policy, separate indicators/rules) |
//| Source : eurusdM5 EdgeCore.mqh                                   |
//| Original M5 EAs require EURUSD (init fails otherwise), skip the  |
//| first tick after attach, and limit positions via MaxPositions.   |
//+------------------------------------------------------------------+
class CEdgeModelM5 : public CEdgeModel
  {
protected:
   int m_max_positions;   // 0 = unlimited

   virtual bool CheckEnvironment()
     {
      if(StringFind(_Symbol, "EURUSD") < 0)
        {
         PrintFormat("[%s] ERROR: this model is designed for EURUSD. Current symbol: %s", m_name, _Symbol);
         return false;
        }
      return true;
     }

   //--- Unlimited when m_max_positions == 0, otherwise capped
   virtual bool CanOpenNew()
     {
      if(m_max_positions > 0 && CountPositions() >= m_max_positions)
         return false;
      return true;
     }

public:
   CEdgeModelM5()
     {
      m_tf             = PERIOD_M5;
      m_is_short       = true;
      m_skip_first_bar = true;
      m_max_positions  = 0;
     }
  };

//+------------------------------------------------------------------+
//| MODEL 4 : EURUSD M5 | run_2010 / window_0003 | EURUSD_M5_121     |
//| Source : EURUSD_M5_run2010_window0003.mq5                        |
//| Rule   : SHORT when rsi_14 > 75 AND stoch_14_3_3_k > 80 AND      |
//|          mom_10 > -5                                             |
//| Exit   : close after 138 bars                                    |
//+------------------------------------------------------------------+
class CModelM5W3 : public CEdgeModelM5
  {
private:
   int m_h_rsi14;
   int m_h_stoch14;
   int m_h_mom10;

protected:
   //--- Evaluated on the last CLOSED bar (shift 1)
   virtual bool EntrySignal()
     {
      double rsi, k, mom;
      if(!ReadBuf(m_h_rsi14,   0, 1, rsi)) return false;   // rsi_14
      if(!ReadBuf(m_h_stoch14, 0, 1, k))   return false;   // stoch_14_3_3_k (main)
      if(!ReadBuf(m_h_mom10,   0, 1, mom)) return false;   // mom_10

      return (rsi > 75.0 && k > 80.0 && mom > -5.0);
     }

   virtual bool CreateIndicators()
     {
      m_h_rsi14   = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
      m_h_stoch14 = iStochastic(_Symbol, PERIOD_M5, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
      m_h_mom10   = iMomentum(_Symbol, PERIOD_M5, 10, PRICE_CLOSE);

      return (m_h_rsi14   != INVALID_HANDLE &&
              m_h_stoch14 != INVALID_HANDLE &&
              m_h_mom10   != INVALID_HANDLE);
     }

   virtual void ReleaseIndicators()
     {
      ReleaseHandle(m_h_rsi14);
      ReleaseHandle(m_h_stoch14);
      ReleaseHandle(m_h_mom10);
     }

public:
   CModelM5W3()
     {
      m_h_rsi14   = INVALID_HANDLE;
      m_h_stoch14 = INVALID_HANDLE;
      m_h_mom10   = INVALID_HANDLE;

      m_name          = "r2010w0003_M5_121";
      m_comment       = "r2010w0003_M5_121";
      m_magic         = InpM5W3_Magic;
      m_deviation     = InpM5W3_Slippage;
      m_max_positions = InpM5W3_MaxPositions;
      m_hold_bars     = 138;
     }
  };

//+------------------------------------------------------------------+
//| MODEL 5 : EURUSD M5 | run_2010 / window_0005 | EURUSD_M5_6       |
//| Source : EURUSD_M5_run2010_window0005.mq5                        |
//| Rule   : SHORT when rsi_14 > 75 AND stoch_5_3_3_k > 80           |
//| Exit   : close after 114 bars                                    |
//+------------------------------------------------------------------+
class CModelM5W5 : public CEdgeModelM5
  {
private:
   int m_h_rsi14;
   int m_h_stoch5;

protected:
   //--- Evaluated on the last CLOSED bar (shift 1)
   virtual bool EntrySignal()
     {
      double rsi, k;
      if(!ReadBuf(m_h_rsi14,  0, 1, rsi)) return false;    // rsi_14
      if(!ReadBuf(m_h_stoch5, 0, 1, k))   return false;    // stoch_5_3_3_k (main)

      return (rsi > 75.0 && k > 80.0);
     }

   virtual bool CreateIndicators()
     {
      m_h_rsi14  = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
      m_h_stoch5 = iStochastic(_Symbol, PERIOD_M5, 5, 3, 3, MODE_SMA, STO_LOWHIGH);

      return (m_h_rsi14  != INVALID_HANDLE &&
              m_h_stoch5 != INVALID_HANDLE);
     }

   virtual void ReleaseIndicators()
     {
      ReleaseHandle(m_h_rsi14);
      ReleaseHandle(m_h_stoch5);
     }

public:
   CModelM5W5()
     {
      m_h_rsi14  = INVALID_HANDLE;
      m_h_stoch5 = INVALID_HANDLE;

      m_name          = "r2010w0005_M5_6";
      m_comment       = "r2010w0005_M5_6";
      m_magic         = InpM5W5_Magic;
      m_deviation     = InpM5W5_Slippage;
      m_max_positions = InpM5W5_MaxPositions;
      m_hold_bars     = 114;
     }
  };

//+------------------------------------------------------------------+
//| SECTION 6 - EA ENTRY POINTS                                      |
//+------------------------------------------------------------------+
CEdgeModel *g_models[];   // only the ENABLED models are created

//--- Append a model to the active list
void AddModel(CEdgeModel *model)
  {
   int n = ArraySize(g_models);
   ArrayResize(g_models, n + 1);
   g_models[n] = model;
  }

//--- Release every model and empty the list
void DeleteModels()
  {
   for(int i = 0; i < ArraySize(g_models); i++)
     {
      if(CheckPointer(g_models[i]) == POINTER_DYNAMIC)
        {
         g_models[i].Deinit();
         delete g_models[i];
        }
      g_models[i] = NULL;
     }
   ArrayResize(g_models, 0);
  }

int OnInit()
  {
   ArrayResize(g_models, 0);

   //--- Create only the models that are enabled in the inputs
   if(InpH1W4_Enable)  AddModel(new CModelH1W4());
   if(InpM30W2_Enable) AddModel(new CModelM30W2());
   if(InpM30W3_Enable) AddModel(new CModelM30W3());
   if(InpM5W3_Enable)  AddModel(new CModelM5W3());
   if(InpM5W5_Enable)  AddModel(new CModelM5W5());

   if(ArraySize(g_models) == 0)
     {
      Print("ERROR: all models are disabled. Enable at least one model.");
      return INIT_FAILED;
     }

   //--- All models trade the same symbol in the same direction and are tracked by magic number
   if(ArraySize(g_models) > 1 &&
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: not a hedging account. Models on the same symbol will be netted into one position "
            "and per-model magic tracking / time exits will not work correctly.");

   //--- Initialise every enabled model
   for(int i = 0; i < ArraySize(g_models); i++)
     {
      if(!g_models[i].Init())
        {
         PrintFormat("ERROR: model [%s] failed to initialise", g_models[i].Name());
         DeleteModels();
         return INIT_FAILED;
        }
     }

   PrintFormat("Combined EA started with %d model(s), lot=%.2f", ArraySize(g_models), InpLots);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   DeleteModels();
  }

void OnTick()
  {
   for(int i = 0; i < ArraySize(g_models); i++)
      g_models[i].Run();
  }
//+------------------------------------------------------------------+
