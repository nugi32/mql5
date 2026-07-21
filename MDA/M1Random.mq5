//+--------------------------------------------------------------------------------+
//| grid-martingale-xauusd-m1.mq5                                                  |
//|                                                                                |
//| STRATEGY SUMMARY                                                              |
//| Base signal : Trend-aligned pullback (mean reversion WITH the higher timeframe|
//|                trend, not against it). Entries require ALL of:                |
//|                  1) Price is above/below a slow EMA (trend filter)            |
//|                  2) RSI crosses back out of an oversold/overbought extreme    |
//|                  3) Price pierced the outer Bollinger Band on the prior bar   |
//|                This is a well documented "buy the dip in an uptrend / sell    |
//|                the rip in a downtrend" pattern - it has statistical support   |
//|                as an edge, but NO signal is a guaranteed edge in live markets.|
//|                Test thoroughly on real tick data before going live.          |
//|                                                                                |
//| Execution   : Once a signal fires, a grid/martingale basket is built in that |
//|                direction. Each level adds a larger position (LotMultiplier)  |
//|                every GridStepPoints against the last entry. The WHOLE basket |
//|                is closed by the EA (not the broker) once floating profit     |
//|                reaches a target - either in money or in average-price points.|
//|                                                                                |
//| RISK WARNING                                                                  |
//| Martingale/grid sizing does not create an edge - it amplifies whatever edge  |
//| (or lack of one) the base signal has, and it converts many small wins into   |
//| an occasional very large loss (risk of ruin / margin call) if price trends   |
//| hard against the grid. MaxGridLevels, LotMultiplier, GridStepPoints and      |
//| MaxBasketDrawdownUSD are your risk controls - size them for your account,    |
//| not the other way around. Backtest with real ticks and forward test on a    |
//| demo before using real money.                                                |
//|                                                                                |
//| DISCLAIMER AND TERMS OF USE OF THIS EXPERT ADVISOR                           |
//| THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR  |
//| IMPLIED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY CLAIM, DAMAGES OR    |
//| OTHER LIABILITY ARISING FROM THE USE OF THIS SOFTWARE. TRADING LEVERAGED     |
//| PRODUCTS CARRIES A HIGH RISK OF LOSS, INCLUDING TOTAL LOSS OF CAPITAL.        |
//+--------------------------------------------------------------------------------+
#property copyright   "Nugi"
#property link        ""
#property description "Grid Martingale EA - XAUUSD M1 - trend-aligned pullback signal"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//+--------------------------------------------------------------------------------+
//| Enums                                                                          |
//+--------------------------------------------------------------------------------+
enum ENUM_GRID_DIRECTION
{
   GRID_NONE = 0,
   GRID_BUY  = 1,
   GRID_SELL = -1
};

//+--------------------------------------------------------------------------------+
//| Input Variables                                                                |
//+--------------------------------------------------------------------------------+
input string               Section_General       = "==== GENERAL ====";       //
input ulong                MagicNumber            = 20260720;                  //Magic Number
input ENUM_TIMEFRAMES      SignalTimeframe         = PERIOD_M1;                 //Signal / Trading Timeframe

input string               Section_Signal        = "==== SIGNAL SETTINGS ====";//
input int                  RSI_Period              = 14;                       //RSI Period
input double                RSI_Oversold            = 30.0;                     //RSI Oversold Level
input double                RSI_Overbought          = 70.0;                     //RSI Overbought Level
input int                  TrendMA_Period          = 200;                      //Trend Filter EMA Period
input ENUM_MA_METHOD        TrendMA_Method          = MODE_EMA;                 //Trend Filter MA Method
input int                  BB_Period               = 20;                       //Bollinger Bands Period
input double                BB_Deviation            = 2.0;                      //Bollinger Bands Deviation

input string               Section_Grid          = "==== GRID / MARTINGALE ====";//
input double                GridStepPoints          = 150;                      //Grid Step (points) Between Levels
input int                  MaxGridLevels           = 8;                        //Max Additional Grid Levels (0 = no averaging, signal-only)
input double                LotMultiplier           = 1.5;                      //Lot Multiplier Per Grid Level
input bool                  UseMoneyTarget          = true;                     //true = Close Basket On $ Target, false = Points Target
input double                BasketTakeProfitUSD     = 5.0;                      //Basket Take Profit (account currency)
input double                BasketTakeProfitPoints  = 100;                      //Basket Take Profit (avg-price points) if not using $ target

input string               Section_MM            = "==== MONEY MANAGEMENT ====";//
input double                EquityPerBaseLot        = 10000.0;                  //Account Equity ($) Per 0.01 Base Lot
input double                MinLot                  = 0.01;                     //Absolute Minimum Lot
input double                MaxLotCap               = 5.0;                      //Hard Safety Cap On Any Single Order
input double                MaxBasketDrawdownUSD     = 0;                        //Emergency Close If Basket Loses This Much ($, 0 = disabled)

//+--------------------------------------------------------------------------------+
//| Global Variables                                                               |
//+--------------------------------------------------------------------------------+
int      TicksReceivedCount    = 0;
int      TicksProcessedCount   = 0;
datetime TimeLastTickProcessed = D'1971.01.01 00:00';

ENUM_GRID_DIRECTION CurrentGridDirection = GRID_NONE;
double   LastGridEntryPrice = 0;
int      GridLevelCount     = 0;

int RSIHandle     = INVALID_HANDLE;
int TrendMAHandle = INVALID_HANDLE;
int BBHandle      = INVALID_HANDLE;

//+--------------------------------------------------------------------------------+
//| Expert initialization                                                          |
//+--------------------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0)
      Print("WARNING: This EA was designed and tuned for XAUUSD. Running on ", _Symbol,
            " - review GridStepPoints / lot settings, tick value differs.");

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   RSIHandle     = iRSI(_Symbol, SignalTimeframe, RSI_Period, PRICE_CLOSE);
   TrendMAHandle = iMA(_Symbol, SignalTimeframe, TrendMA_Period, 0, TrendMA_Method, PRICE_CLOSE);
   BBHandle      = iBands(_Symbol, SignalTimeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);

   if(RSIHandle == INVALID_HANDLE || TrendMAHandle == INVALID_HANDLE || BBHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create one or more indicator handles.");
      return(INIT_FAILED);
   }

   RebuildStateFromExistingPositions();  //In case EA/terminal was restarted with an open basket

   OutputStatusToScreen();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
   if(RSIHandle     != INVALID_HANDLE) IndicatorRelease(RSIHandle);
   if(TrendMAHandle != INVALID_HANDLE) IndicatorRelease(TrendMAHandle);
   if(BBHandle      != INVALID_HANDLE) IndicatorRelease(BBHandle);
}

//+--------------------------------------------------------------------------------+
//| Expert tick function                                                           |
//+--------------------------------------------------------------------------------+
void OnTick()
{
   TicksReceivedCount++;

   //High trade frequency requires reacting to every new M1 bar (not every tick,
   //to keep behaviour identical between Strategy Tester and live trading).
   bool ProcessThisIteration = false;
   if(TimeLastTickProcessed != iTime(_Symbol, PERIOD_M1, 0))
   {
      ProcessThisIteration = true;
      TimeLastTickProcessed = iTime(_Symbol, PERIOD_M1, 0);
   }

   if(ProcessThisIteration)
   {
      TicksProcessedCount++;
      ManageBasket();        //Check TP / emergency exit first
      ManageGridEntries();   //Then look for new / additional entries
   }

   OutputStatusToScreen();
}

//+--------------------------------------------------------------------------------+
//| Signal: trend-aligned pullback (mean reversion WITH the trend)                |
//| Returns 1 = buy, -1 = sell, 0 = no signal                                     |
//+--------------------------------------------------------------------------------+
int GetEntrySignal()
{
   double rsi[], trendMA[], bbUpper[], bbLower[];
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(trendMA, true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);

   if(CopyBuffer(RSIHandle, 0, 0, 3, rsi) < 3)          return 0;
   if(CopyBuffer(TrendMAHandle, 0, 0, 3, trendMA) < 3)  return 0;
   if(CopyBuffer(BBHandle, 1, 0, 3, bbUpper) < 3)       return 0; //Upper band buffer
   if(CopyBuffer(BBHandle, 2, 0, 3, bbLower) < 3)       return 0; //Lower band buffer

   double close1    = iClose(_Symbol, SignalTimeframe, 1); //last completed bar
   double closePrev = iClose(_Symbol, SignalTimeframe, 2); //bar before that

   bool uptrend   = close1 > trendMA[1];
   bool downtrend = close1 < trendMA[1];

   bool rsiCrossUpFromOversold      = (rsi[2] <= RSI_Oversold   && rsi[1] > RSI_Oversold);
   bool rsiCrossDownFromOverbought  = (rsi[2] >= RSI_Overbought && rsi[1] < RSI_Overbought);

   bool touchedLowerBand = (closePrev <= bbLower[2]);
   bool touchedUpperBand = (closePrev >= bbUpper[2]);

   //Buy: uptrend + RSI recovering out of oversold + a recent lower-band pierce
   if(uptrend && rsiCrossUpFromOversold && touchedLowerBand)
      return 1;

   //Sell: downtrend + RSI dropping out of overbought + a recent upper-band pierce
   if(downtrend && rsiCrossDownFromOverbought && touchedUpperBand)
      return -1;

   return 0;
}

//+--------------------------------------------------------------------------------+
//| Grid entry management                                                         |
//+--------------------------------------------------------------------------------+
void ManageGridEntries()
{
   int positions = CountBasketPositions();

   //No open basket - look for a fresh signal to start one
   if(positions == 0)
   {
      int signal = GetEntrySignal();

      if(signal == 1)
      {
         CurrentGridDirection = GRID_BUY;
         OpenGridPosition(ORDER_TYPE_BUY, 0);
      }
      else if(signal == -1)
      {
         CurrentGridDirection = GRID_SELL;
         OpenGridPosition(ORDER_TYPE_SELL, 0);
      }
      return;
   }

   //Already have a basket - only add if we haven't hit the level cap
   if(positions >= MaxGridLevels + 1)
      return;

   double stepPrice = GridStepPoints * _Point;

   if(CurrentGridDirection == GRID_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid <= LastGridEntryPrice - stepPrice)
         OpenGridPosition(ORDER_TYPE_BUY, positions);
   }
   else if(CurrentGridDirection == GRID_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask >= LastGridEntryPrice + stepPrice)
         OpenGridPosition(ORDER_TYPE_SELL, positions);
   }
}

//+--------------------------------------------------------------------------------+
//| Open a single grid-level position (NO broker SL/TP - managed by the EA)       |
//+--------------------------------------------------------------------------------+
void OpenGridPosition(ENUM_ORDER_TYPE type, int level)
{
   double lot = CalculateLotForLevel(level);

   bool sent;
   if(type == ORDER_TYPE_BUY)
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sent = trade.Buy(lot, _Symbol, price, 0, 0, "Grid Lv" + IntegerToString(level));
      if(sent) LastGridEntryPrice = price;
   }
   else
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sent = trade.Sell(lot, _Symbol, price, 0, 0, "Grid Lv" + IntegerToString(level));
      if(sent) LastGridEntryPrice = price;
   }

   if(sent)
   {
      GridLevelCount = level + 1;
      Print("Opened grid level ", level, " | lot=", DoubleToString(lot,2),
            " | dir=", EnumToString(CurrentGridDirection));
   }
   else
   {
      Print("ERROR: Grid order failed at level ", level, " - retcode: ", trade.ResultRetcode(),
            " (", trade.ResultRetcodeDescription(), ")");
   }
}

//+--------------------------------------------------------------------------------+
//| Dynamic lot sizing based on account equity, then scaled by martingale level   |
//+--------------------------------------------------------------------------------+
double CalculateLotForLevel(int level)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   //Base lot scales with equity: one MinLot "chunk" per EquityPerBaseLot of equity
   double baseLot = NormalizeDouble((equity / EquityPerBaseLot) * MinLot, 2);
   baseLot = MathMax(baseLot, MinLot);

   double lot = baseLot * MathPow(LotMultiplier, level);

   double lotStep      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLotBroker = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLotBroker = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lotStep <= 0) lotStep = 0.01;

   lot = MathRound(lot / lotStep) * lotStep;
   lot = MathMax(lot, MathMax(MinLot, minLotBroker));
   lot = MathMin(lot, MathMin(MaxLotCap, maxLotBroker));

   return NormalizeDouble(lot, 2);
}

//+--------------------------------------------------------------------------------+
//| Basket management - EA-managed exit since no broker SL/TP is used             |
//+--------------------------------------------------------------------------------+
void ManageBasket()
{
   int count = CountBasketPositions();
   if(count == 0)
   {
      CurrentGridDirection = GRID_NONE;
      return;
   }

   double totalProfit    = 0;
   double totalLots      = 0;
   double weightedPrice  = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double lots = PositionGetDouble(POSITION_VOLUME);
      totalLots += lots;
      weightedPrice += PositionGetDouble(POSITION_PRICE_OPEN) * lots;
   }

   bool closeBasket = false;

   if(UseMoneyTarget)
   {
      if(totalProfit >= BasketTakeProfitUSD)
         closeBasket = true;
   }
   else if(totalLots > 0)
   {
      double avgPrice = weightedPrice / totalLots;
      double currentPrice = (CurrentGridDirection == GRID_BUY)
                              ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double pointsProfit = (CurrentGridDirection == GRID_BUY)
                              ? (currentPrice - avgPrice) / _Point
                              : (avgPrice - currentPrice) / _Point;
      if(pointsProfit >= BasketTakeProfitPoints)
         closeBasket = true;
   }

   //Optional emergency net - NOT a broker SL, just an EA-managed cutoff
   if(MaxBasketDrawdownUSD > 0 && totalProfit <= -MathAbs(MaxBasketDrawdownUSD))
   {
      Print("EMERGENCY CLOSE: basket drawdown reached $", DoubleToString(totalProfit,2));
      closeBasket = true;
   }

   if(closeBasket)
      CloseAllBasketPositions();
}

//+--------------------------------------------------------------------------------+
//| Close every position belonging to this EA/symbol                              |
//+--------------------------------------------------------------------------------+
void CloseAllBasketPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      trade.PositionClose(ticket);
   }

   CurrentGridDirection = GRID_NONE;
   LastGridEntryPrice   = 0;
   GridLevelCount        = 0;

   Print("Basket closed.");
}

//+--------------------------------------------------------------------------------+
//| Count open positions belonging to this EA on this symbol                      |
//+--------------------------------------------------------------------------------+
int CountBasketPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      count++;
   }
   return count;
}

//+--------------------------------------------------------------------------------+
//| Rebuild internal grid state if the EA/terminal restarts mid-basket            |
//+--------------------------------------------------------------------------------+
void RebuildStateFromExistingPositions()
{
   int count = 0;
   double lastPrice = 0;
   datetime lastTime = 0;
   ENUM_GRID_DIRECTION dir = GRID_NONE;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      count++;
      dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? GRID_BUY : GRID_SELL;

      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t > lastTime)
      {
         lastTime  = t;
         lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }

   if(count > 0)
   {
      CurrentGridDirection = dir;
      LastGridEntryPrice   = lastPrice;
      GridLevelCount        = count;
      Print("Recovered existing basket: ", count, " positions, direction=", EnumToString(dir));
   }
}

//+--------------------------------------------------------------------------------+
//| On-screen status / diagnostics                                                |
//+--------------------------------------------------------------------------------+
void OutputStatusToScreen()
{
   double offsetInHours = (TimeCurrent() - TimeGMT()) / 3600.0;

   double totalProfit = 0;
   int    count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      count++;
   }

   string OutputText = "\n\r";
   OutputText += "MT5 SERVER TIME: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
                 " (UTC/GMT" + StringFormat("%+.1f", offsetInHours) + ")\n\r\n\r";

   OutputText += Symbol() + " TICKS RECEIVED / PROCESSED: " + IntegerToString(TicksReceivedCount) +
                 " / " + IntegerToString(TicksProcessedCount) + "\n\r";
   OutputText += "GRID DIRECTION: " + EnumToString(CurrentGridDirection) + "\n\r";
   OutputText += "GRID LEVELS OPEN: " + IntegerToString(count) + " / " + IntegerToString(MaxGridLevels+1) + "\n\r";
   OutputText += "LAST GRID ENTRY PRICE: " + DoubleToString(LastGridEntryPrice, _Digits) + "\n\r";
   OutputText += "BASKET FLOATING P/L: " + DoubleToString(totalProfit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n\r";
   OutputText += "ACCOUNT EQUITY: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n\r";
   OutputText += "NEXT LEVEL LOT (est): " + DoubleToString(CalculateLotForLevel(count), 2) + "\n\r";

   Comment(OutputText);
}