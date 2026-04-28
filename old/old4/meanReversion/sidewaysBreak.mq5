//+------------------------------------------------------------------+
//|         Mean Reversion EA (Multi Position + SL Only)            |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"

input string Inp_Expert_Title="Expert_Mean_Reversion";
int Expert_MagicNumber=14598;

//================ TRADING =================
input group "=== Trading Settings ==="
input double lotSize = 0.01;
input int StopLossPoints = 300;
input int MaxPositions = 5;
input int MinDistancePoints = 100;

//================ SIDEWAYS DETECTION =================
input group "=== Sideways Detection ==="
input int SidewaysLookback = 10;           // Bars to check for slope
input int SidewaysSlopeThreshold = 50;      // Maximum slope in points

//================ BREAK & RETEST ENTRY =================
input group "=== Break & Retest Entry ==="
input int EntryBuffer = 10;                 // Buffer in points for retest
input bool UseDeMarker = true;               // Enable DeMarker filter
input double DeMarkerBuyLevel = 0.3;         // DeMarker buy threshold
input double DeMarkerSellLevel = 0.7;        // DeMarker sell threshold

//================ GLOBAL =================
MqlRates rates[];
datetime lastBarTime=0;

//================ INDICATORS =================
int env1, env2, env3, env4;
int dem1, dem2, dem3, dem4;

// buffers envelopes
double env1_upper[], env1_lower[];
double env2_upper[], env2_lower[];
double env3_upper[], env3_lower[];
double env4_upper[], env4_lower[];

// buffers demarker
double deM1[], deM2[], deM3[], deM4[];

//+------------------------------------------------------------------+
int OnInit()
{
   ArraySetAsSeries(rates,true);

   // ENVELOPES
   env1 = iEnvelopes(Symbol(), PERIOD_CURRENT, 4, 0, MODE_SMA, PRICE_CLOSE, 0.270);
   env2 = iEnvelopes(Symbol(), PERIOD_CURRENT, 4, 0, MODE_SMA, PRICE_CLOSE, 0.290);
   env3 = iEnvelopes(Symbol(), PERIOD_CURRENT, 6, 0, MODE_SMA, PRICE_CLOSE, 0.370);
   env4 = iEnvelopes(Symbol(), PERIOD_CURRENT, 6, 0, MODE_SMA, PRICE_CLOSE, 0.310);

   // DEMARKER
   dem1 = iDeMarker(Symbol(), PERIOD_CURRENT, 35);
   dem2 = iDeMarker(Symbol(), PERIOD_CURRENT, 20);
   dem3 = iDeMarker(Symbol(), PERIOD_CURRENT, 31);
   dem4 = iDeMarker(Symbol(), PERIOD_CURRENT, 30);

   // array series
   ArraySetAsSeries(env1_upper,true); ArraySetAsSeries(env1_lower,true);
   ArraySetAsSeries(env2_upper,true); ArraySetAsSeries(env2_lower,true);
   ArraySetAsSeries(env3_upper,true); ArraySetAsSeries(env3_lower,true);
   ArraySetAsSeries(env4_upper,true); ArraySetAsSeries(env4_lower,true);

   ArraySetAsSeries(deM1,true);
   ArraySetAsSeries(deM2,true);
   ArraySetAsSeries(deM3,true);
   ArraySetAsSeries(deM4,true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Copy more bars for sideways calculation
   int copy_bars = MathMax(3, SidewaysLookback + 2);
   CopyRates(Symbol(), PERIOD_CURRENT, 0, copy_bars, rates);

   // 1 candle filter
   datetime currentBar = rates[0].time;
   if(currentBar == lastBarTime)
      return;
   lastBarTime = currentBar;

   // COPY ENVELOPES - get enough bars for lookback
   CopyBuffer(env1, 0, 0, copy_bars, env1_upper);
   CopyBuffer(env1, 1, 0, copy_bars, env1_lower);

   CopyBuffer(env2, 0, 0, copy_bars, env2_upper);
   CopyBuffer(env2, 1, 0, copy_bars, env2_lower);

   CopyBuffer(env3, 0, 0, copy_bars, env3_upper);
   CopyBuffer(env3, 1, 0, copy_bars, env3_lower);

   CopyBuffer(env4, 0, 0, copy_bars, env4_upper);
   CopyBuffer(env4, 1, 0, copy_bars, env4_lower);

   // COPY DEMARKER
   CopyBuffer(dem1, 0, 0, 3, deM1);
   CopyBuffer(dem2, 0, 0, 3, deM2);
   CopyBuffer(dem3, 0, 0, 3, deM3);
   CopyBuffer(dem4, 0, 0, 3, deM4);

   CheckForEntry();
   //CheckForExit();  // Moved here to ensure exit is called
}

//+------------------------------------------------------------------+
int CountMyPositions()
{
   int total = 0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      total++;
   }
   return total;
}

//+------------------------------------------------------------------+
bool CanOpenNewPosition(double price)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      if(MathAbs(price - openPrice) < MinDistancePoints * _Point)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get outer envelope (max upper, min lower from env3 and env4)    |
//+------------------------------------------------------------------+
void GetOuterEnvelope(double &upper_outer, double &lower_outer, int index)
{
   // Add bounds checking
   if(index < 0 || index >= ArraySize(env3_upper) || index >= ArraySize(env4_upper))
   {
      upper_outer = 0;
      lower_outer = 0;
      return;
   }
   
   upper_outer = MathMax(env3_upper[index], env4_upper[index]);
   lower_outer = MathMin(env3_lower[index], env4_lower[index]);
}
//+------------------------------------------------------------------+
//| Check if market is in sideways condition                         |
//+------------------------------------------------------------------+
bool IsSideways()
{
   // Ensure we have enough data
   if(ArraySize(env3_upper) <= SidewaysLookback || ArraySize(rates) <= 1)
      return true; // If not enough data, don't block trading
   
   double upper_outer, lower_outer;
   double upper_outer_prev, lower_outer_prev;
   
   // Get current and previous outer envelope values
   GetOuterEnvelope(upper_outer, lower_outer, 1);      // Previous candle (rates[1])
   GetOuterEnvelope(upper_outer_prev, lower_outer_prev, SidewaysLookback);
   
   // If envelope values are 0, return true (don't block)
   if(upper_outer == 0 || lower_outer == 0 || upper_outer_prev == 0 || lower_outer_prev == 0)
      return true;
   
   // Condition 1: Price should be WITHIN or NEAR the outer envelope
   // Allow some breathing room (1% buffer)
   double buffer = (upper_outer - lower_outer) * 0.01;
   if(rates[1].high > upper_outer + buffer || rates[1].low < lower_outer - buffer)
      return false;
   
   // Condition 2: Envelope should be relatively flat
   double upper_slope = MathAbs(upper_outer - upper_outer_prev);
   double lower_slope = MathAbs(lower_outer - lower_outer_prev);
   
   double slope_threshold = SidewaysSlopeThreshold * _Point * 10; // Increased threshold
   
   if(upper_slope > slope_threshold && lower_slope > slope_threshold)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| New Entry Logic - MODIFIED SECTION                               |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   // Ensure we have enough data
   if(ArraySize(rates) < 3 || ArraySize(env3_upper) < 3)
      return;
   
   // Check if we can open new positions
   int totalPos = CountMyPositions();
   if(totalPos >= MaxPositions)
      return;
   
   // Get outer envelope values for different candles
   double upper_outer_0, lower_outer_0;   // For current candle
   double upper_outer_1, lower_outer_1;   // For rates[1] (previous candle)
   double upper_outer_2, lower_outer_2;   // For rates[2] (candle before previous)
   
   GetOuterEnvelope(upper_outer_0, lower_outer_0, 0);
   GetOuterEnvelope(upper_outer_1, lower_outer_1, 1);
   GetOuterEnvelope(upper_outer_2, lower_outer_2, 2);
   
   // If envelope values are 0, return (error condition)
   if(upper_outer_0 == 0 || lower_outer_0 == 0 || 
      upper_outer_1 == 0 || lower_outer_1 == 0 || 
      upper_outer_2 == 0 || lower_outer_2 == 0)
      return;
   
   // SIDEWAYS FILTER - Optional, don't block if not sideways
   bool sideways = IsSideways();
   
   // BUY SETUP - More relaxed conditions
   bool buy_signal = false;
   double buy_sl = 0;
   
   // Look for break in last 2 candles
   bool break_occurred = (rates[2].close > upper_outer_2) || (rates[1].close > upper_outer_1);
   
   if(break_occurred)
   {
      // Check if price is near upper envelope (retest)
      double current_price = rates[0].close;
      double distance_to_upper = MathAbs(current_price - upper_outer_0);
      
      if(distance_to_upper <= EntryBuffer * _Point * 5) // Increased buffer
      {
         // Confirmation: price moving up
         if(rates[0].close > rates[1].close)
         {
            // DeMarker confirmation (if enabled)
            bool demarker_ok = true;
            if(UseDeMarker && ArraySize(deM1) > 0)
            {
               // For BUY, DeMarker should be rising or above oversold
               demarker_ok = (deM1[0] > 0.2); // More relaxed condition
            }
            
            if(demarker_ok && (sideways || true)) // Allow non-sideways for testing
            {
               buy_signal = true;
               buy_sl = lower_outer_0;  // SL at lower envelope
               
               // Debug print
               Print("BUY Signal: Price=", current_price, 
                     ", Upper=", upper_outer_0, 
                     ", Distance=", distance_to_upper,
                     ", DeM=", (UseDeMarker ? DoubleToString(deM1[0]) : "disabled"));
            }
         }
      }
   }
   
   // SELL SETUP - More relaxed conditions
   bool sell_signal = false;
   double sell_sl = 0;
   
   // Look for break in last 2 candles
   break_occurred = (rates[2].close < lower_outer_2) || (rates[1].close < lower_outer_1);
   
   if(break_occurred)
   {
      // Check if price is near lower envelope (retest)
      double current_price = rates[0].close;
      double distance_to_lower = MathAbs(current_price - lower_outer_0);
      
      if(distance_to_lower <= EntryBuffer * _Point * 5) // Increased buffer
      {
         // Confirmation: price moving down
         if(rates[0].close < rates[1].close)
         {
            // DeMarker confirmation (if enabled)
            bool demarker_ok = true;
            if(UseDeMarker && ArraySize(deM1) > 0)
            {
               // For SELL, DeMarker should be falling or below overbought
               demarker_ok = (deM1[0] < 0.8); // More relaxed condition
            }
            
            if(demarker_ok && (sideways || true)) // Allow non-sideways for testing
            {
               sell_signal = true;
               sell_sl = upper_outer_0;  // SL at upper envelope
               
               // Debug print
               Print("SELL Signal: Price=", current_price, 
                     ", Lower=", lower_outer_0, 
                     ", Distance=", distance_to_lower,
                     ", DeM=", (UseDeMarker ? DoubleToString(deM1[0]) : "disabled"));
            }
         }
      }
   }
   
   // Execute trades with position filter
   double current_price = rates[0].close;
   
   if(buy_signal && CanOpenNewPosition(current_price))
   {
      Print("Opening BUY at ", current_price, " SL=", buy_sl);
      OpenBuyWithSL(buy_sl);
   }
      
   if(sell_signal && CanOpenNewPosition(current_price))
   {
      Print("Opening SELL at ", current_price, " SL=", sell_sl);
      OpenSellWithSL(sell_sl);
   }
}

//+------------------------------------------------------------------+
//| Modified OpenBuy with dynamic SL                                 |
//+------------------------------------------------------------------+
void OpenBuyWithSL(double sl_price)
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   
   // Ensure SL is below entry price
   if(sl_price >= price)
      sl_price = price - StopLossPoints * _Point;
      
   Print("Executing BUY: Price=", price, " SL=", sl_price);
   SendOrder(ORDER_TYPE_BUY, price, sl_price);
}

//+------------------------------------------------------------------+
//| Modified OpenSell with dynamic SL                                |
//+------------------------------------------------------------------+
void OpenSellWithSL(double sl_price)
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   
   // Ensure SL is above entry price
   if(sl_price <= price)
      sl_price = price + StopLossPoints * _Point;
      
   Print("Executing SELL: Price=", price, " SL=", sl_price);
   SendOrder(ORDER_TYPE_SELL, price, sl_price);
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl = price - StopLossPoints * _Point;
   SendOrder(ORDER_TYPE_BUY,price,sl);
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = price + StopLossPoints * _Point;
   SendOrder(ORDER_TYPE_SELL,price,sl);
}

//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price,double sl)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lotSize;
   req.type      = type;
   req.price     = price;
   req.sl        = sl;
   req.tp        = 0;
   req.magic     = Expert_MagicNumber;
   req.deviation = 10;
   req.comment   = Inp_Expert_Title;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+
void CloseBuy()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) continue;

      double volume=PositionGetDouble(POSITION_VOLUME);
      double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

      MqlTradeRequest req={};
      MqlTradeResult res={};

      req.action=TRADE_ACTION_DEAL;
      req.position=ticket;
      req.symbol=_Symbol;
      req.volume=volume;
      req.type=ORDER_TYPE_SELL;
      req.price=price;
      req.magic=Expert_MagicNumber;

      OrderSend(req,res);
   }
}

//+------------------------------------------------------------------+
void CloseSell()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL) continue;

      double volume=PositionGetDouble(POSITION_VOLUME);
      double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      MqlTradeRequest req={};
      MqlTradeResult res={};

      req.action=TRADE_ACTION_DEAL;
      req.position=ticket;
      req.symbol=_Symbol;
      req.volume=volume;
      req.type=ORDER_TYPE_BUY;
      req.price=price;
      req.magic=Expert_MagicNumber;

      OrderSend(req,res);
   }
}

//+------------------------------------------------------------------+

void CheckForExit()
{
   if(ArraySize(rates) == 0 || ArraySize(env1_upper) == 0)
      return;
      
   double price = rates[0].close;
   double mean = (env1_upper[0] + env1_lower[0]) / 2.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      int type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY && price >= mean)
         CloseBuy();

      if(type == POSITION_TYPE_SELL && price <= mean)
         CloseSell();
   }
}


//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(env1);
   IndicatorRelease(env2);
   IndicatorRelease(env3);
   IndicatorRelease(env4);

   IndicatorRelease(dem1);
   IndicatorRelease(dem2);
   IndicatorRelease(dem3);
   IndicatorRelease(dem4);
}
//+------------------------------------------------------------------+