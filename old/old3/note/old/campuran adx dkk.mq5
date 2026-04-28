//+------------------------------------------------------------------+
//|                                                  ATR Trend System |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+

#property copyright "ATR Trend System"
#property version   "1.00"
#property description "Trend-following system using EMA + ADX + RSI + ATR"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                |
//+------------------------------------------------------------------+

//--- Money Management
input group "=== Money Management ==="
input double RiskPercent = 2.0;          // Risk per trade (% of balance)
input double RiskReward = 1.8;           // Risk Reward Ratio
input int ATR_Period = 14;               // ATR Period
input double ATR_Multiplier = 1.5;       // ATR Multiplier for SL
input double ATR_Min = 0.0008;           // Minimum ATR value
input bool Use_ATR_Filter = true;        // Enable ATR minimum filter

//--- Indicator Filters
input group "=== Indicator Filters ==="
input bool Use_EMA_Filter = true;        // Enable EMA Filter
input int EMA_Fast_Period = 50;          // EMA Fast Period
input int EMA_Slow_Period = 200;         // EMA Slow Period
input bool Use_ADX_Filter = true;        // Enable ADX Filter
input int ADX_Period = 14;               // ADX Period
input int ADX_Min = 25;                  // Minimum ADX value
input bool Use_RSI_Filter = true;        // Enable RSI Filter
input int RSI_Period = 14;               // RSI Period
input int RSI_Buy_Level = 40;            // RSI Buy Level
input int RSI_Sell_Level = 60;           // RSI Sell Level
input bool Use_Bullish_Confirmation = true; // Enable Bullish Confirmation

enum ENUM_CONFIRMATION_TYPE
{
   CONFIRM_CANDLE,    // Candle
   CONFIRM_RSI,       // RSI  
   CONFIRM_MACD       // MACD
};

input ENUM_CONFIRMATION_TYPE Confirmation_Type = CONFIRM_CANDLE; // Confirmation Type

//--- Exit Settings
input group "=== Exit Settings ==="
input bool Use_TrailingStop = true;      // Enable Trailing Stop

enum ENUM_TRAILING_TYPE
{
   TRAIL_ATR,       // ATR-based
   TRAIL_FIXED      // Fixed pips
};

input ENUM_TRAILING_TYPE Trailing_Type = TRAIL_ATR; // Trailing Type
input double Trailing_Multiplier = 0.5;  // Trailing Multiplier (ATR-based)
input int Trailing_Pips = 20;            // Trailing Pips (Fixed)
input double Trailing_ActivateAt = 1.0;  // Activate trailing after profit (R)
input bool Use_Breakeven = true;         // Enable Breakeven
input double Breakeven_At = 1.0;         // Move to BE at profit (R)

//--- Trading Settings
input group "=== Trading Settings ==="
input int MagicNumber = 12345;           // Magic Number
input int Slippage = 3;                  // Slippage in points

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
int adx_handle, ema_fast_handle, ema_slow_handle, rsi_handle, atr_handle, macd_handle;
double last_buy_sl, last_buy_tp, last_sell_sl, last_sell_tp;
datetime last_trade_time;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create indicator handles
   ema_fast_handle = iMA(_Symbol, _Period, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   ema_slow_handle = iMA(_Symbol, _Period, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   adx_handle = iADX(_Symbol, _Period, ADX_Period);
   rsi_handle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   atr_handle = iATR(_Symbol, _Period, ATR_Period);
   
   if(Confirmation_Type == CONFIRM_MACD)
      macd_handle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
   
   if(ema_fast_handle == INVALID_HANDLE || ema_slow_handle == INVALID_HANDLE || 
      adx_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE || 
      atr_handle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(ema_fast_handle != INVALID_HANDLE) IndicatorRelease(ema_fast_handle);
   if(ema_slow_handle != INVALID_HANDLE) IndicatorRelease(ema_slow_handle);
   if(adx_handle != INVALID_HANDLE) IndicatorRelease(adx_handle);
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
   if(macd_handle != INVALID_HANDLE) IndicatorRelease(macd_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time == last_bar_time)
      return;
   last_bar_time = current_bar_time;
   
   // Check if we can trade
   if(!IsNewBarAllowed()) return;
   
   // Get indicator values
   double ema_fast[2], ema_slow[2], adx_values[2], rsi_values[2], atr_values[2];
   double macd_main[2] = {0, 0}, macd_signal[2] = {0, 0};
   
   CopyBuffer(ema_fast_handle, 0, 0, 2, ema_fast);
   CopyBuffer(ema_slow_handle, 0, 0, 2, ema_slow);
   CopyBuffer(adx_handle, 0, 0, 2, adx_values); // ADX main line
   CopyBuffer(rsi_handle, 0, 0, 2, rsi_values);
   CopyBuffer(atr_handle, 0, 0, 2, atr_values);
   
   if(Confirmation_Type == CONFIRM_MACD && macd_handle != INVALID_HANDLE)
   {
      CopyBuffer(macd_handle, 0, 0, 2, macd_main);   // MACD main line
      CopyBuffer(macd_handle, 1, 0, 2, macd_signal); // MACD signal line
   }
   
   double current_atr = atr_values[0];
   double current_adx = adx_values[0];
   double current_rsi = rsi_values[0];
   double prev_rsi = rsi_values[1];
   
   // Check ATR filter
   if(Use_ATR_Filter && current_atr < ATR_Min)
      return;
   
   // Check for BUY conditions
   bool buy_signal = true;
   bool sell_signal = true;
   
   //--- BUY Conditions ---
   if(Use_EMA_Filter && ema_fast[0] <= ema_slow[0])
      buy_signal = false;
   
   if(Use_ADX_Filter && current_adx < ADX_Min)
      buy_signal = false;
   
   if(Use_RSI_Filter && current_rsi >= RSI_Buy_Level)
      buy_signal = false;
   
   if(Use_Bullish_Confirmation && buy_signal)
   {
      switch(Confirmation_Type)
      {
         case CONFIRM_CANDLE:
            if(iClose(_Symbol, _Period, 1) <= iOpen(_Symbol, _Period, 1) || 
               iClose(_Symbol, _Period, 0) <= iOpen(_Symbol, _Period, 0))
               buy_signal = false;
            break;
            
         case CONFIRM_RSI:
            if(!(prev_rsi < 40 && current_rsi > 45))
               buy_signal = false;
            break;
            
         case CONFIRM_MACD:
            if(macd_main[0] <= macd_signal[0] || macd_main[0] <= 0)
               buy_signal = false;
            break;
      }
   }
   
   //--- SELL Conditions ---
   if(Use_EMA_Filter && ema_fast[0] >= ema_slow[0])
      sell_signal = false;
   
   if(Use_ADX_Filter && current_adx < ADX_Min)
      sell_signal = false;
   
   if(Use_RSI_Filter && current_rsi <= RSI_Sell_Level)
      sell_signal = false;
   
   if(Use_Bullish_Confirmation && sell_signal)
   {
      switch(Confirmation_Type)
      {
         case CONFIRM_CANDLE:
            if(iClose(_Symbol, _Period, 1) >= iOpen(_Symbol, _Period, 1) || 
               iClose(_Symbol, _Period, 0) >= iOpen(_Symbol, _Period, 0))
               sell_signal = false;
            break;
            
         case CONFIRM_RSI:
            if(!(prev_rsi > 60 && current_rsi < 55))
               sell_signal = false;
            break;
            
         case CONFIRM_MACD:
            if(macd_main[0] >= macd_signal[0] || macd_main[0] >= 0)
               sell_signal = false;
            break;
      }
   }
   
   // Check existing positions
   bool has_buy = PositionExists(POSITION_TYPE_BUY);
   bool has_sell = PositionExists(POSITION_TYPE_SELL);
   
   // Execute trades
   if(buy_signal && !has_buy)
   {
      if(has_sell)
         CloseAllPositions(POSITION_TYPE_SELL);
      
      double sl, tp;
      CalculateSLTP(POSITION_TYPE_BUY, current_atr, sl, tp);
      OpenPosition(POSITION_TYPE_BUY, sl, tp);
   }
   else if(sell_signal && !has_sell)
   {
      if(has_buy)
         CloseAllPositions(POSITION_TYPE_BUY);
      
      double sl, tp;
      CalculateSLTP(POSITION_TYPE_SELL, current_atr, sl, tp);
      OpenPosition(POSITION_TYPE_SELL, sl, tp);
   }
   
   // Manage exits (trailing stop & breakeven)
   ManageExits(current_atr);
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss and Take Profit                             |
//+------------------------------------------------------------------+
void CalculateSLTP(ENUM_POSITION_TYPE type, double atr, double &sl, double &tp)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double multiplier = (digits == 3 || digits == 5) ? 10 : 1;
   
   double atr_sl = atr * ATR_Multiplier;
   double atr_tp = atr_sl * RiskReward;
   
   double current_price = type == POSITION_TYPE_BUY ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(type == POSITION_TYPE_BUY)
   {
      sl = current_price - atr_sl;
      tp = current_price + atr_tp;
   }
   else
   {
      sl = current_price + atr_sl;
      tp = current_price - atr_tp;
   }
   
   // Store for trailing stop reference
   if(type == POSITION_TYPE_BUY)
   {
      last_buy_sl = sl;
      last_buy_tp = tp;
   }
   else
   {
      last_sell_sl = sl;
      last_sell_tp = tp;
   }
}

//+------------------------------------------------------------------+
//| Open Position                                                   |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_POSITION_TYPE type, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = CalculateLotSize();
   request.sl = sl;
   request.tp = tp;
   request.deviation = (uint)Slippage;
   request.magic = (ulong)MagicNumber;
   request.comment = "ATR Trend System";
   
   if(type == POSITION_TYPE_BUY)
   {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   else
   {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   
   if(!OrderSend(request, result))
   {
      Print("OrderSend error: ", GetLastError());
      return;
   }
   
   last_trade_time = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                              |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * RiskPercent / 100.0;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double multiplier = (digits == 3 || digits == 5) ? 10 : 1;
   
   // Calculate stop loss in points
   double atr_values[1];
   CopyBuffer(atr_handle, 0, 0, 1, atr_values);
   double sl_points = (atr_values[0] * ATR_Multiplier) / (point * multiplier);
   
   if(sl_points == 0) return 0.01; // Prevent division by zero
   
   double lot_size = risk_amount / (sl_points * tick_value);
   
   // Normalize lot size
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
   lot_size = MathRound(lot_size / step_lot) * step_lot;
   
   return lot_size;
}

//+------------------------------------------------------------------+
//| Manage Exits (Trailing Stop & Breakeven)                        |
//+------------------------------------------------------------------+
void ManageExits(double current_atr)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      double current_price = type == POSITION_TYPE_BUY ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = PositionGetDouble(POSITION_PROFIT);
      double initial_sl = type == POSITION_TYPE_BUY ? last_buy_sl : last_sell_sl;
      double sl_distance = MathAbs(open_price - initial_sl);
      
      // Calculate profit in R multiples
      double volume = PositionGetDouble(POSITION_VOLUME);
      double profit_r = MathAbs(profit) / (sl_distance * volume * 
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
      
      // Breakeven logic
      if(Use_Breakeven && profit_r >= Breakeven_At && current_sl == initial_sl)
      {
         double new_sl = open_price;
         ModifyPositionSL(ticket, new_sl);
         continue;
      }
      
      // Trailing stop logic
      if(Use_TrailingStop && profit_r >= Trailing_ActivateAt)
      {
         double new_sl = current_sl;
         double trailing_distance = 0;
         
         if(Trailing_Type == TRAIL_ATR)
            trailing_distance = current_atr * Trailing_Multiplier;
         else
            trailing_distance = Trailing_Pips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 
                              ((SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || 
                                SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5) ? 10 : 1);
         
         if(type == POSITION_TYPE_BUY)
         {
            new_sl = current_price - trailing_distance;
            if(new_sl > current_sl && new_sl > open_price)
               ModifyPositionSL(ticket, new_sl);
         }
         else
         {
            new_sl = current_price + trailing_distance;
            if(new_sl < current_sl && new_sl < open_price)
               ModifyPositionSL(ticket, new_sl);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify Position Stop Loss                                       |
//+------------------------------------------------------------------+
void ModifyPositionSL(ulong ticket, double new_sl)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = new_sl;
   request.magic = (ulong)MagicNumber;
   
   if(!OrderSend(request, result))
      Print("Modify SL error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Check if position exists                                        |
//+------------------------------------------------------------------+
bool PositionExists(ENUM_POSITION_TYPE type)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE) == type)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close All Positions                                             |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE) == type)
      {
         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);
         
         request.action = TRADE_ACTION_DEAL;
         request.symbol = _Symbol;
         request.volume = PositionGetDouble(POSITION_VOLUME);
         request.deviation = (uint)Slippage;
         request.magic = (ulong)MagicNumber;
         
         if(type == POSITION_TYPE_BUY)
         {
            request.type = ORDER_TYPE_SELL;
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         }
         else
         {
            request.type = ORDER_TYPE_BUY;
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         }
         
         if(!OrderSend(request, result))
            Print("Close position error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Check if new bar is allowed                                     |
//+------------------------------------------------------------------+
bool IsNewBarAllowed()
{
   static datetime last_trade = 0;
   datetime current_time = TimeCurrent();
   
   // Allow new trade if enough time has passed or no recent trade
   if(last_trade == 0 || (current_time - last_trade) >= PeriodSeconds(_Period))
   {
      last_trade = current_time;
      return true;
   }
   return false;
}