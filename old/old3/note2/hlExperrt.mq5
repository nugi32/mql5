//+------------------------------------------------------------------+
//|                                              SwingHL_Expert.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double   Risk_Percent     = 1.0;     // Risk Percentage
input double   RR_BE_Level      = 1.0;     // RR Break Even Level
input ulong    Magic_Number     = 123456;  // Magic Number
input int      Depth            = 10;      // Indicator Depth
input string   Trade_Comment    = "SwingHL"; // Trade comment
input int TP_Points = 200;   // Take Profit in points

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
datetime       lastBarTime      = 0;       // Last bar time
bool           signalBuy        = false;   // Buy signal flag
bool           signalSell       = false;   // Sell signal flag
bool           signalCloseBuy   = false;   // Close buy signal
bool           signalCloseSell  = false;   // Close sell signal
double         lastHigh         = 0;       // Last high signal value
double         lastLow          = 0;       // Last low signal value
double         slPrice          = 0;       // Stop Loss price
double         beTriggerLevel   = 0;       // Break even trigger level

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Expert Advisor initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // No indicator handle to release
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   if(!IsNewBar())
      return;
   
   // Get indicator signals
   CheckSignal();
   
   // Manage existing positions
   ManagePositions();
   
   // Open new positions if no active positions
   if(!HasOpenPosition())
      OpenNewPosition();
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(_Symbol, _Period, 0);
   
   if(current == lastBarTime)
      return false;
   
   lastBarTime = current;
   return true;
}

//+------------------------------------------------------------------+
//| Check indicator signals                                          |
//+------------------------------------------------------------------+
void CheckSignal()
{
   // Reset signals
   signalBuy = false;
   signalSell = false;
   signalCloseBuy = false;
   signalCloseSell = false;
   lastHigh = 0;
   lastLow = 0;
   
   // Get data for indicator calculation
   int rates_total = Bars(_Symbol, _Period);
   if(rates_total < Depth * 3) return;
   
   // Arrays for data
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   // Copy data (enough for calculation)
   int to_copy = Depth * 2 + 2;
   if(CopyHigh(_Symbol, _Period, 0, to_copy, high) < to_copy) return;
   if(CopyLow(_Symbol, _Period, 0, to_copy, low) < to_copy) return;
   
   // Check for Swing High at bar index 1 (previous closed bar)
   bool isSwingHigh = true;
   int checkIndex = 1; // Bar index 1 is the closed bar
   
   // Check left side
   for(int i = 1; i <= Depth; i++)
   {
      if(high[checkIndex] < high[checkIndex + i])
      {
         isSwingHigh = false;
         break;
      }
   }
   
   // Check right side
   if(isSwingHigh)
   {
      for(int i = 1; i <= Depth; i++)
      {
         if(checkIndex - i >= 0 && high[checkIndex] <= high[checkIndex - i])
         {
            isSwingHigh = false;
            break;
         }
      }
   }
   
   // Check for Swing Low at bar index 1
   bool isSwingLow = true;
   
   // Check left side
   for(int i = 1; i <= Depth; i++)
   {
      if(low[checkIndex] > low[checkIndex + i])
      {
         isSwingLow = false;
         break;
      }
   }
   
   // Check right side
   if(isSwingLow)
   {
      for(int i = 1; i <= Depth; i++)
      {
         if(checkIndex - i >= 0 && low[checkIndex] >= low[checkIndex - i])
         {
            isSwingLow = false;
            break;
         }
      }
   }
   
   // Set signals
   if(isSwingHigh)
   {
      signalSell = true;
      lastHigh = high[checkIndex];
      
      // Check if this is opposite signal for existing positions
      if(HasOpenPosition())
      {
         long posType = GetPositionType();
         if(posType == POSITION_TYPE_BUY)
            signalCloseBuy = true;
      }
   }
   
   if(isSwingLow)
   {
      signalBuy = true;
      lastLow = low[checkIndex];
      
      // Check if this is opposite signal for existing positions
      if(HasOpenPosition())
      {
         long posType = GetPositionType();
         if(posType == POSITION_TYPE_SELL)
            signalCloseSell = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if has open position                                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get position type                                                |
//+------------------------------------------------------------------+
long GetPositionType()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            return PositionGetInteger(POSITION_TYPE);
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Open new position                                                |
//+------------------------------------------------------------------+
void OpenNewPosition()
{
   if(signalBuy && !signalSell)
      OpenBuy();
   else if(signalSell && !signalBuy)
      OpenSell();
}

//+------------------------------------------------------------------+
//| Open BUY position                                                |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(lastLow == 0)
      return;

   slPrice = lastLow;

   double lot = CalculateLot(price, slPrice);
   if(lot <= 0)
      return;

   beTriggerLevel = price + (RR_BE_Level * (price - slPrice));

   double tpPrice = price + TP_Points * _Point;

   SendOrder(ORDER_TYPE_BUY, lot, price, slPrice, tpPrice);
}


//+------------------------------------------------------------------+
//| Open SELL position                                               |
//+------------------------------------------------------------------+
void OpenSell()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(lastHigh == 0)
      return;

   slPrice = lastHigh;

   double lot = CalculateLot(price, slPrice);
   if(lot <= 0)
      return;

   beTriggerLevel = price - (RR_BE_Level * (slPrice - price));

   double tpPrice = price - TP_Points * _Point;

   SendOrder(ORDER_TYPE_SELL, lot, price, slPrice, tpPrice);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLot(double entry, double sl)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * Risk_Percent / 100.0;
   double points = MathAbs(entry - sl) / _Point;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(points <= 0 || tickValue <= 0)
      return 0;
   
   double rawLot = riskMoney / (points * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(rawLot < minLot)
      return 0;
   
   double lot = MathFloor(rawLot / stepLot) * stepLot;
   lot = MathMin(lot, maxLot);
   
   return lot;
}

//+------------------------------------------------------------------+
//| Send order function                                              |
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.type = type;
   req.volume = lot;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.magic = Magic_Number;
   req.comment = Trade_Comment;
   req.deviation = 10;
   
   OrderSend(req, res);
   
   if(res.retcode == TRADE_RETCODE_DONE)
   {
      if(type == ORDER_TYPE_BUY)
         Print("Buy order opened: Ticket ", res.order);
      else
         Print("Sell order opened: Ticket ", res.order);
   }
   else
   {
      Print("Order failed: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Manage positions                                                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number)
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      
      ManageBreakeven(ticket);
      //ManageReverseSignal(ticket);
   }
}

//+------------------------------------------------------------------+
//| Manage break even                                                |
//+------------------------------------------------------------------+
void ManageBreakeven(ulong ticket)
{
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   long type = PositionGetInteger(POSITION_TYPE);
   
   double risk = MathAbs(open - sl);
   if(risk <= 0)
      return;
   
   if(type == POSITION_TYPE_BUY && price >= beTriggerLevel && beTriggerLevel > 0 && sl < open)
      ModifySL(ticket, open);
   
   if(type == POSITION_TYPE_SELL && price <= beTriggerLevel && beTriggerLevel > 0 && sl > open)
      ModifySL(ticket, open);
}

//+------------------------------------------------------------------+
//| Manage reverse signal                                            |
//+------------------------------------------------------------------+
/*
void ManageReverseSignal(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);
   
   if(type == POSITION_TYPE_BUY && signalCloseBuy)
      ClosePosition(ticket);
   
   if(type == POSITION_TYPE_SELL && signalCloseSell)
      ClosePosition(ticket);
}*/

//+------------------------------------------------------------------+
//| Modify stop loss                                                 |
//+------------------------------------------------------------------+
void ModifySL(ulong ticket, double newSL)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol = _Symbol;
   req.sl = newSL;
   req.tp = PositionGetDouble(POSITION_TP);
   req.magic = Magic_Number;
   
   if(OrderSend(req, res))
      Print("Break Even activated for position: Ticket ", ticket);
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   long type = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   
   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = _Symbol;
   req.volume = volume;
   req.magic = Magic_Number;
   req.deviation = 10;
   req.comment = "Close on reverse signal";
   
   if(type == POSITION_TYPE_BUY)
   {
      req.type = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      req.type = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   
   if(OrderSend(req, res))
      Print("Position closed: Ticket ", ticket, " Profit: ", PositionGetDouble(POSITION_PROFIT));
}

//+------------------------------------------------------------------+  