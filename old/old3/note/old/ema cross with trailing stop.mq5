//+------------------------------------------------------------------+
//|                                                  EMACrossover.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== EMA Settings ==="
input int      EMA_Fast_Period = 10;      // EMA Fast Period
input int      EMA_Slow_Period = 20;      // EMA Slow Period

input group "=== Trading Settings ==="
input double   Risk_Percent = 1.0;        // Risk Percentage per Trade
input bool     Use_Reverse_TP = false;    // Use Reverse Signal for TP (true) or Fixed TP (false)
input double   Fixed_TP_Ratio = 2.0;      // Fixed TP Ratio (e.g., 2.0 for 1:2)
input double   Auto_BE_Level = 1.0;       // Auto Breakeven Level (RR ratio)

input group "=== Trailing Stop Settings ==="
input bool     Use_Trailing_Stop = true;  // Enable Trailing Stop
input double   Trailing_Stop_Points = 100; // Trailing Stop Distance (points)
input double   Trailing_Step_Points = 50;  // Trailing Step (points)

input group "=== Other Settings ==="
input int      Magic_Number = 12345;      // Magic Number
input string   Trade_Comment = "EMA-Cross"; // Trade Comment

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int ema_fast_handle, ema_slow_handle;
double ema_fast[], ema_slow[];
double point_value;
double min_lot, max_lot, lot_step;
double point_size;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Create EMA handles
    ema_fast_handle = iMA(_Symbol, _Period, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
    ema_slow_handle = iMA(_Symbol, _Period, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
    
    if(ema_fast_handle == INVALID_HANDLE || ema_slow_handle == INVALID_HANDLE)
    {
        Print("Error creating EMA handles");
        return INIT_FAILED;
    }
    
    // Get symbol info
    point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    point_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    
    Print("EA Initialized - Trailing Stop: ", Use_Trailing_Stop ? "Enabled" : "Disabled");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(ema_fast_handle != INVALID_HANDLE) IndicatorRelease(ema_fast_handle);
    if(ema_slow_handle != INVALID_HANDLE) IndicatorRelease(ema_slow_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update EMA values
    if(CopyBuffer(ema_fast_handle, 0, 0, 3, ema_fast) < 3 ||
       CopyBuffer(ema_slow_handle, 0, 0, 3, ema_slow) < 3)
        return;
    
    // Check for new signals
    CheckForEntry();
    
    // Manage existing positions
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntry()
{
    // Check if we have open positions
    if(PositionsTotal() > 0) return;
    
    // Check for crossover
    bool fast_above_slow_now = ema_fast[0] > ema_slow[0];
    bool fast_above_slow_prev = ema_fast[1] > ema_slow[1];
    
    // BUY signal: Fast EMA crosses above Slow EMA
    if(fast_above_slow_now && !fast_above_slow_prev)
    {
        OpenBuyPosition();
    }
    // SELL signal: Fast EMA crosses below Slow EMA  
    else if(!fast_above_slow_now && fast_above_slow_prev)
    {
        OpenSellPosition();
    }
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double sl_price = ema_fast[0]; // SL at fast EMA
    double tp_price = 0;
    double risk_amount = CalculateRiskAmount();
    double lot_size = CalculateLotSize(risk_amount, sl_price, ORDER_TYPE_BUY);
    
    if(lot_size <= 0) return;
    
    if(!Use_Reverse_TP)
    {
        // Fixed TP based on ratio
        double sl_distance = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - sl_price;
        tp_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + (sl_distance * Fixed_TP_Ratio);
    }
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lot_size;
    request.type = ORDER_TYPE_BUY;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.sl = sl_price;
    request.tp = (tp_price > 0) ? tp_price : 0;
    request.magic = Magic_Number;
    request.comment = Trade_Comment;
    request.deviation = 10;
    
    if(OrderSend(request, result))
    {
        Print("Buy order opened. Ticket: ", result.order, " Lot: ", lot_size);
    }
    else
    {
        Print("Buy order failed. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double sl_price = ema_fast[0]; // SL at fast EMA
    double tp_price = 0;
    double risk_amount = CalculateRiskAmount();
    double lot_size = CalculateLotSize(risk_amount, sl_price, ORDER_TYPE_SELL);
    
    if(lot_size <= 0) return;
    
    if(!Use_Reverse_TP)
    {
        // Fixed TP based on ratio
        double sl_distance = sl_price - SymbolInfoDouble(_Symbol, SYMBOL_BID);
        tp_price = SymbolInfoDouble(_Symbol, SYMBOL_BID) - (sl_distance * Fixed_TP_Ratio);
    }
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lot_size;
    request.type = ORDER_TYPE_SELL;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl = sl_price;
    request.tp = (tp_price > 0) ? tp_price : 0;
    request.magic = Magic_Number;
    request.comment = Trade_Comment;
    request.deviation = 10;
    
    if(OrderSend(request, result))
    {
        Print("Sell order opened. Ticket: ", result.order, " Lot: ", lot_size);
    }
    else
    {
        Print("Sell order failed. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == Magic_Number && 
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                ManageBreakeven(ticket);
                
                if(Use_Trailing_Stop)
                {
                    ManageTrailingStop(ticket);
                }
                
                if(Use_Reverse_TP)
                {
                    ManageReverseTP(ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage breakeven functionality                                   |
//+------------------------------------------------------------------+
void ManageBreakeven(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    double current_sl = PositionGetDouble(POSITION_SL);
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
    long type = PositionGetInteger(POSITION_TYPE);
    
    // Calculate risk amount for this position
    double sl_distance = 0;
    if(type == POSITION_TYPE_BUY)
    {
        sl_distance = open_price - current_sl;
        double be_level = open_price + (sl_distance * Auto_BE_Level);
        
        if(current_price >= be_level && current_sl < open_price)
        {
            // Move SL to breakeven
            ModifyPositionSL(ticket, open_price);
            Print("Breakeven activated for BUY position: ", ticket);
        }
    }
    else if(type == POSITION_TYPE_SELL)
    {
        sl_distance = current_sl - open_price;
        double be_level = open_price - (sl_distance * Auto_BE_Level);
        
        if(current_price <= be_level && current_sl > open_price)
        {
            // Move SL to breakeven
            ModifyPositionSL(ticket, open_price);
            Print("Breakeven activated for SELL position: ", ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Manage trailing stop functionality                               |
//+------------------------------------------------------------------+
void ManageTrailingStop(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    long type = PositionGetInteger(POSITION_TYPE);
    
    double trailing_distance = Trailing_Stop_Points * point_size;
    double trailing_step = Trailing_Step_Points * point_size;
    
    if(type == POSITION_TYPE_BUY)
    {
        double new_sl = current_price - trailing_distance;
        
        // Only move SL if new SL is higher than current SL and above open price
        if(new_sl > current_sl && new_sl > open_price)
        {
            // Check if price moved enough to justify moving SL (trailing step)
            if(current_price - current_sl >= trailing_step)
            {
                ModifyPositionSL(ticket, new_sl);
                Print("Trailing Stop updated for BUY: ", ticket, " New SL: ", new_sl);
            }
        }
    }
    else if(type == POSITION_TYPE_SELL)
    {
        double new_sl = current_price + trailing_distance;
        
        // Only move SL if new SL is lower than current SL and below open price
        if((current_sl == 0 || new_sl < current_sl) && new_sl < open_price)
        {
            // Check if price moved enough to justify moving SL (trailing step)
            if(current_sl == 0 || current_sl - current_price >= trailing_step)
            {
                ModifyPositionSL(ticket, new_sl);
                Print("Trailing Stop updated for SELL: ", ticket, " New SL: ", new_sl);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage reverse signal take profit                                |
//+------------------------------------------------------------------+
void ManageReverseTP(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    long type = PositionGetInteger(POSITION_TYPE);
    
    // For BUY positions, close when fast EMA crosses below slow EMA
    if(type == POSITION_TYPE_BUY && ema_fast[0] < ema_slow[0] && ema_fast[1] >= ema_slow[1])
    {
        ClosePosition(ticket);
        Print("Reverse TP triggered - Closed BUY position: ", ticket);
    }
    // For SELL positions, close when fast EMA crosses above slow EMA
    else if(type == POSITION_TYPE_SELL && ema_fast[0] > ema_slow[0] && ema_fast[1] <= ema_slow[1])
    {
        ClosePosition(ticket);
        Print("Reverse TP triggered - Closed SELL position: ", ticket);
    }
}

//+------------------------------------------------------------------+
//| Calculate risk amount based on portfolio percentage              |
//+------------------------------------------------------------------+
double CalculateRiskAmount()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    return equity * (Risk_Percent / 100.0);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double risk_amount, double sl_price, ENUM_ORDER_TYPE order_type)
{
    double entry_price = (order_type == ORDER_TYPE_BUY) ? 
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                        SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double sl_distance = 0;
    if(order_type == ORDER_TYPE_BUY)
        sl_distance = entry_price - sl_price;
    else
        sl_distance = sl_price - entry_price;
    
    if(sl_distance <= 0) return 0;
    
    double sl_points = sl_distance / point_size;
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(tick_value == 0) return 0;
    
    double lot_size = risk_amount / (sl_points * tick_value);
    
    // Normalize lot size
    lot_size = MathRound(lot_size / lot_step) * lot_step;
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Modify position SL                                               |
//+------------------------------------------------------------------+
bool ModifyPositionSL(ulong ticket, double new_sl)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = new_sl;
    request.tp = PositionGetDouble(POSITION_TP); // Keep existing TP
    request.magic = Magic_Number;
    
    bool success = OrderSend(request, result);
    if(!success)
    {
        Print("Modify SL failed. Error: ", GetLastError());
    }
    return success;
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.deviation = 10;
    request.magic = Magic_Number;
    
    long type = PositionGetInteger(POSITION_TYPE);
    if(type == POSITION_TYPE_BUY)
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }
    else if(type == POSITION_TYPE_SELL)
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }
    
    bool success = OrderSend(request, result);
    if(success)
    {
        Print("Position closed. Ticket: ", ticket);
    }
    else
    {
        Print("Close position failed. Error: ", GetLastError());
    }
    return success;
}
//+------------------------------------------------------------------+