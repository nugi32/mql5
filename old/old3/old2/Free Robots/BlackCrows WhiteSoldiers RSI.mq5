//+------------------------------------------------------------------+
//|                                             BlackCrows WhiteSoldiers RSI.mq5 |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#define SIGNAL_BUY    1             // Buy signal
#define SIGNAL_NOT    0             // no trading signal
#define SIGNAL_SELL  -1             // Sell signal

#define CLOSE_LONG    2             // signal to close Long
#define CLOSE_SHORT  -2             // signal to close Short

//--- Input parameters
input int  InpAverBodyPeriod=12;    // period for calculating average candlestick size
input int  InpPeriodRSI     =37;    // RSI period
input ENUM_APPLIED_PRICE InpPrice=PRICE_CLOSE;  // price type

//--- trade parameters
input uint InpDuration=10;          // position holding time in bars
input uint InpSL      =200;         // Stop Loss in points
input uint InpTP      =200;         // Take Profit in points
input uint InpSlippage=10;          // slippage in points
//--- money management parameters
input double InpLot   =0.1;         // lot
//--- Expert ID
input long InpMagicNumber=120300;   // Magic Number
input string Trade_Comment = "BCWS RSI"; // Trade comment

//--- global variables
int    ExtAvgBodyPeriod;            // average candlestick calculation period
int    ExtSignalOpen     =0;        // Buy/Sell signal
int    ExtSignalClose    =0;        // signal to close a position
string ExtPatternInfo    ="";       // current pattern information
string ExtDirection      ="";       // position opening direction
bool   ExtPatternDetected=false;    // pattern detected
bool   ExtConfirmed      =false;    // pattern confirmed
bool   ExtCloseByTime    =true;     // requires closing by time 
bool   ExtCheckPassed    =true;     // status checking error
double ema[];                       // EMA array for helper functions

//---  indicator handle
int    ExtIndicatorHandle=INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("InpSL=", InpSL);
   Print("InpTP=", InpTP);
   
   ExtAvgBodyPeriod=InpAverBodyPeriod;
   
//--- indicator initialization
   ExtIndicatorHandle=iRSI(_Symbol, _Period, InpPeriodRSI, InpPrice);
   if(ExtIndicatorHandle==INVALID_HANDLE)
     {
      Print("Error creating RSI indicator");
      return(INIT_FAILED);
     }
     
//--- OK
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- release indicator handle
   IndicatorRelease(ExtIndicatorHandle);
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- save the next bar start time; all checks at bar opening only
   static datetime next_bar_open=0;

//--- Phase 1 - check the emergence of a new bar and update the status
   if(TimeCurrent()>=next_bar_open)
     {
      //--- get the current state of environment on the new bar
      if(CheckState())
        {
         //--- set the new bar opening time
         next_bar_open=TimeCurrent();
         next_bar_open-=next_bar_open%PeriodSeconds(_Period);
         next_bar_open+=PeriodSeconds(_Period);

         //--- report the emergence of a new bar only once within a bar
         if(ExtPatternDetected && ExtConfirmed)
            Print(ExtPatternInfo);
        }
      else
        {
         //--- error getting the status, retry on the next tick
         return;
        }
     }

//--- Phase 2 - if there is a signal and no position in this direction
   if(ExtSignalOpen != SIGNAL_NOT && !PositionExist(ExtSignalOpen))
     {
      Print("\r\nSignal to open position ", ExtDirection);
      PositionOpen();
      if(PositionExist(ExtSignalOpen))
         ExtSignalOpen = SIGNAL_NOT;
     }

//--- Phase 3 - close if there is a signal to close
   if(ExtSignalClose != 0 && PositionExist(ExtSignalClose))
     {
      Print("\r\nSignal to close position ", ExtDirection);
      CloseBySignal(ExtSignalClose);
      if(!PositionExist(ExtSignalClose))
         ExtSignalClose = SIGNAL_NOT;
     }

//--- Phase 4 - close upon expiration
   if(ExtCloseByTime && PositionExpiredByTimeExist())
     {
      CloseByTime();
      ExtCloseByTime = PositionExpiredByTimeExist();
     }
  }
  
//+------------------------------------------------------------------+
//|  Get the current environment and check for a pattern             |
//+------------------------------------------------------------------+
bool CheckState()
  {
//--- check if there is a pattern
   if(!CheckPattern())
     {
      Print("Error, failed to check pattern");
      return(false);
     }

//--- check for confirmation
   if(!CheckConfirmation())
     {
      Print("Error, failed to check pattern confirmation");
      return(false);
     }
     
//--- if there is no confirmation, cancel the signal
   if(!ExtConfirmed)
      ExtSignalOpen = SIGNAL_NOT;

//--- check if there is a signal to close a position
   if(!CheckCloseSignal())
     {
      Print("Error, failed to check the closing signal");
      return(false);
     }
     
//--- if positions are to be closed after certain holding time in bars
   if(InpDuration > 0)
      ExtCloseByTime = true; // set flag to close upon expiration
           
//--- all checks done
   return(true);
  }
  
//+------------------------------------------------------------------+
//| Open a position in the direction of the signal                   |
//+------------------------------------------------------------------+
bool PositionOpen()
  {
   double price = 0;
   double stoploss = 0.0;
   double takeprofit = 0.0;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;

//--- uptrend
   if(ExtSignalOpen == SIGNAL_BUY)
     {
      price = NormalizeDouble(ask, digits);
      
      //--- if Stop Loss is set
      if(InpSL > 0)
        {
         if(spread >= InpSL * point)
           {
            PrintFormat("StopLoss (%d points) <= current spread = %.0f points. Spread value will be used", InpSL, spread/point);
            stoploss = NormalizeDouble(price - spread, digits);
           }
         else
            stoploss = NormalizeDouble(price - InpSL * point, digits);
        }
        
      //--- if Take Profit is set
      if(InpTP > 0)
        {
         if(spread >= InpTP * point)
           {
            PrintFormat("TakeProfit (%d points) < current spread = %.0f points. Spread value will be used", InpTP, spread/point);
            takeprofit = NormalizeDouble(price + spread, digits);
           }
         else
            takeprofit = NormalizeDouble(price + InpTP * point, digits);
        }

      //--- Validate stop loss
      if(!IsValidStop(price, stoploss))
        {
         Print("Invalid Stop Loss for Buy position");
         return(false);
        }

      double lot = CalculateLot(price, stoploss);
      if(lot <= 0) lot = InpLot;

      SendOrder(ORDER_TYPE_BUY, lot, price, stoploss, takeprofit);
     }

//--- downtrend
   if(ExtSignalOpen == SIGNAL_SELL)
     {
      price = NormalizeDouble(bid, digits);
      
      //--- if Stop Loss is set
      if(InpSL > 0)
        {
         if(spread >= InpSL * point)
           {
            PrintFormat("StopLoss (%d points) <= current spread = %.0f points. Spread value will be used", InpSL, spread/point);
            stoploss = NormalizeDouble(price + spread, digits);
           }
         else
            stoploss = NormalizeDouble(price + InpSL * point, digits);
        }
        
      //--- if Take Profit is set
      if(InpTP > 0)
        {
         if(spread >= InpTP * point)
           {
            PrintFormat("TakeProfit (%d points) < current spread = %.0f points. Spread value will be used", InpTP, spread/point);
            takeprofit = NormalizeDouble(price - spread, digits);
           }
         else
            takeprofit = NormalizeDouble(price - InpTP * point, digits);
        }

      //--- Validate stop loss
      if(!IsValidStop(stoploss, price))
        {
         Print("Invalid Stop Loss for Sell position");
         return(false);
        }

      double lot = CalculateLot(stoploss, price);
      if(lot <= 0) lot = InpLot;

      SendOrder(ORDER_TYPE_SELL, lot, price, stoploss, takeprofit);
     }

   return(true);
  }
  
//+------------------------------------------------------------------+
//|  Close a position based on the specified signal                  |
//+------------------------------------------------------------------+
void CloseBySignal(int type_close)
  {
//--- if there is no signal to close, return successful completion
   if(type_close == SIGNAL_NOT)
      return;
      
//--- if there are no positions opened by our EA
   if(PositionExist(ExtSignalClose) == 0)
      return;

//--- closing direction
   long type;
   switch(type_close)
     {
      case CLOSE_SHORT:
         type = POSITION_TYPE_SELL;
         break;
      case CLOSE_LONG:
         type = POSITION_TYPE_BUY;
         break;
      default:
         Print("Error! Signal to close not detected");
         return;
     }

//--- check all positions and close ours based on the signal
   int positions = PositionsTotal();
   for(int i = positions - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
        {
         //--- get the name of the symbol and the position id (magic)
         string symbol = PositionGetString(POSITION_SYMBOL);
         long   magic = PositionGetInteger(POSITION_MAGIC);
         //--- if they correspond to our values
         if(symbol == _Symbol && magic == InpMagicNumber)
           {
            if(PositionGetInteger(POSITION_TYPE) == type)
              {
               ClosePosition(ticket);
               Print("   ");
              }
           }
        }
     }
  }
  
//+------------------------------------------------------------------+
//|  Close positions upon holding time expiration in bars            |
//+------------------------------------------------------------------+
void CloseByTime()
  {
//--- if there are no positions opened by our EA
   if(PositionExist(ExtSignalOpen) == 0)
      return;

//--- check all positions and close ours based on the holding time in bars
   int positions = PositionsTotal();
   for(int i = positions - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
        {
         //--- get the name of the symbol and the position id (magic)
         string symbol = PositionGetString(POSITION_SYMBOL);
         long   magic = PositionGetInteger(POSITION_MAGIC);
         //--- if they correspond to our values
         if(symbol == _Symbol && magic == InpMagicNumber)
           {
            //--- position opening time
            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            //--- check position holding time in bars
            if(BarsHold(open_time) >= (int)InpDuration)
              {
               Print("\r\nTime to close position #", ticket);
               ClosePosition(ticket);
               Print("   ");
              }
           }
        }
     }
  }
  
//+------------------------------------------------------------------+
//| Returns true if there are open positions                         |
//+------------------------------------------------------------------+
bool PositionExist(int signal_direction)
  {
   bool check_type = (signal_direction != SIGNAL_NOT);

//--- what positions to search
   ENUM_POSITION_TYPE search_type = WRONG_VALUE;
   if(check_type)
      switch(signal_direction)
        {
         case SIGNAL_BUY:
            search_type = POSITION_TYPE_BUY;
            break;
         case SIGNAL_SELL:
            search_type = POSITION_TYPE_SELL;
            break;
         case CLOSE_LONG:
            search_type = POSITION_TYPE_BUY;
            break;
         case CLOSE_SHORT:
            search_type = POSITION_TYPE_SELL;
            break;
         default:
            //--- entry direction is not specified; nothing to search
            return(false);
        }

//--- go through the list of all positions
   int positions = PositionsTotal();
   for(int i = 0; i < positions; i++)
     {
      if(PositionGetTicket(i) != 0)
        {
         //--- if the position type does not match, move on to the next one
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(check_type && (type != search_type))
            continue;
         //--- get the name of the symbol and the expert id (magic number)
         string symbol = PositionGetString(POSITION_SYMBOL);
         long   magic = PositionGetInteger(POSITION_MAGIC);
         //--- if they correspond to our values
         if(symbol == _Symbol && magic == InpMagicNumber)
           {
            //--- yes, this is the right position, stop the search
            return(true);
           }
        }
     }

//--- open position not found
   return(false);
  }
  
//+------------------------------------------------------------------+
//| Returns true if there are open positions with expired time       |
//+------------------------------------------------------------------+
bool PositionExpiredByTimeExist()
  {
//--- go through the list of all positions
   int positions = PositionsTotal();
   for(int i = 0; i < positions; i++)
     {
      if(PositionGetTicket(i) != 0)
        {
         //--- get the name of the symbol and the expert id (magic number)
         string symbol = PositionGetString(POSITION_SYMBOL);
         long   magic = PositionGetInteger(POSITION_MAGIC);
         //--- if they correspond to our values
         if(symbol == _Symbol && magic == InpMagicNumber)
           {
            //--- position opening time
            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            //--- check position holding time in bars
            int check = BarsHold(open_time);
            //--- if the value is -1, the check completed with an error
            if(check == -1 || (BarsHold(open_time) >= (int)InpDuration))
               return(true);
           }
        }
     }

//--- open position not found
   return(false);
  }
  
//+------------------------------------------------------------------+
//| Checks position closing time in bars                             |
//+------------------------------------------------------------------+
int BarsHold(datetime open_time)
  {
//--- first run a basic simple check
   if(TimeCurrent() - open_time < PeriodSeconds(_Period))
     {
      //--- opening time is inside the current bar
      return(0);
     }
//---
   MqlRates bars[];
   if(CopyRates(_Symbol, _Period, open_time, TimeCurrent(), bars) == -1)
     {
      Print("Error. CopyRates() failed, error = ", GetLastError());
      return(-1);
     }
//--- check position holding time in bars
   return(ArraySize(bars));
  }
  
//+------------------------------------------------------------------+
//| Returns the open price of the specified bar                      |
//+------------------------------------------------------------------+
double Open(int index)
  {
   double val = iOpen(_Symbol, _Period, index);
//--- if the current check state was successful and an error was received
   if(ExtCheckPassed && val == 0)
      ExtCheckPassed = false;   // switch the status to failed

   return(val);
  }
  
//+------------------------------------------------------------------+
//| Returns the close price of the specified bar                     |
//+------------------------------------------------------------------+
double Close(int index)
  {
   double val = iClose(_Symbol, _Period, index);
//--- if the current check state was successful and an error was received
   if(ExtCheckPassed && val == 0)
      ExtCheckPassed = false;   // switch the status to failed

   return(val);
  }
  
//+------------------------------------------------------------------+
//| Returns the low price of the specified bar                       |
//+------------------------------------------------------------------+
double Low(int index)
  {
   double val = iLow(_Symbol, _Period, index);
//--- if the current check state was successful and an error was received
   if(ExtCheckPassed && val == 0)
      ExtCheckPassed = false;   // switch the status to failed

   return(val);
  }
  
//+------------------------------------------------------------------+
//| Returns the high price of the specified bar                      |
//+------------------------------------------------------------------+
double High(int index)
  {
   double val = iHigh(_Symbol, _Period, index);
//--- if the current check state was successful and an error was received
   if(ExtCheckPassed && val == 0)
      ExtCheckPassed = false;   // switch the status to failed

   return(val);
  }
  
//+------------------------------------------------------------------+
//| Returns the middle body price for the specified bar              |
//+------------------------------------------------------------------+
double MidPoint(int index)
  {
   return (High(index) + Low(index)) / 2.0;
  }
  
//+------------------------------------------------------------------+
//| Returns the middle price of the range for the specified bar      |
//+------------------------------------------------------------------+
double MidOpenClose(int index)
  {
   return (Open(index) + Close(index)) / 2.0;
  }
  
//+------------------------------------------------------------------+
//| Returns the average candlestick body size for the specified bar  |
//+------------------------------------------------------------------+
double AvgBody(int index)
  {
   double sum = 0;
   for(int i = index; i < index + ExtAvgBodyPeriod; i++)
     {
      sum += MathAbs(Open(i) - Close(i));
     }
   return(sum / ExtAvgBodyPeriod);
  }
  
//+------------------------------------------------------------------+
//| Returns true in case of successful pattern check                 |
//+------------------------------------------------------------------+
bool CheckPattern()
  {
   ExtPatternDetected = false;
//--- check if there is a pattern
   ExtSignalOpen = SIGNAL_NOT;
   ExtPatternInfo = "\r\nPattern not detected";
   ExtDirection = "";

//--- check 3 Black Crows
   if((Open(3) - Close(3) > AvgBody(1)) && // long black
      (Open(2) - Close(2) > AvgBody(1)) &&
      (Open(1) - Close(1) > AvgBody(1)) &&
      (MidPoint(2) < MidPoint(3))     && // lower midpoints
      (MidPoint(1) < MidPoint(2)))
     {
      ExtPatternDetected = true;
      ExtSignalOpen = SIGNAL_SELL;
      ExtPatternInfo = "\r\n3 Black Crows detected";
      ExtDirection = "Sell";
      return(true);
     }

//--- check 3 White Soldiers
   if((Close(3) - Open(3) > AvgBody(1)) && // long white
      (Close(2) - Open(2) > AvgBody(1)) &&
      (Close(1) - Open(1) > AvgBody(1)) &&
      (MidPoint(2) > MidPoint(3))     && // higher midpoints
      (MidPoint(1) > MidPoint(2)))
     {
      ExtPatternDetected = true;
      ExtSignalOpen = SIGNAL_BUY;
      ExtPatternInfo = "\r\n3 White Soldiers detected";
      ExtDirection = "Buy";
      return(true);
     }

//--- result of checking
   return(ExtCheckPassed);
  }
  
//+------------------------------------------------------------------+
//| Returns true in case of successful confirmation check            |
//+------------------------------------------------------------------+
bool CheckConfirmation()
  {
   ExtConfirmed = false;
//--- if there is no pattern, do not search for confirmation
   if(!ExtPatternDetected)
      return(true);

//--- get the value of the RSI indicator to confirm the signal
   double signal = RSI(1);
   if(signal == EMPTY_VALUE)
     {
      //--- failed to get indicator value, check failed
      return(false);
     }

//--- check the Buy signal
   if(ExtSignalOpen == SIGNAL_BUY && (signal < 40))
     {
      ExtConfirmed = true;
      ExtPatternInfo += "\r\n   Confirmed: RSI<40";
     }

//--- check the Sell signal
   if(ExtSignalOpen == SIGNAL_SELL && (signal > 60))
     {
      ExtConfirmed = true;
      ExtPatternInfo += "\r\n   Confirmed: RSI>60";
     }

//--- successful completion of the check
   return(true);
  }
  
//+------------------------------------------------------------------+
//| Check if there is a signal to close                              |
//+------------------------------------------------------------------+
bool CheckCloseSignal()
  {
   ExtSignalClose = 0;
//--- if there is a signal to enter the market, do not check the signal to close
   if(ExtSignalOpen != SIGNAL_NOT)
      return(true);

//--- check if there is a signal to close a long position
   if(((RSI(1) < 70) && (RSI(2) > 70)) || ((RSI(1) < 30) && (RSI(2) > 30)))
     {
      //--- there is a signal to close a long position
      ExtSignalClose = CLOSE_LONG;
      ExtDirection = "Long";
     }

//--- check if there is a signal to close a short position
   if(((RSI(1) > 30) && (RSI(2) < 30)) || ((RSI(1) > 70) && (RSI(2) < 70)))
     {
      //--- there is a signal to close a short position
      ExtSignalClose = CLOSE_SHORT;
      ExtDirection = "Short";
     }

//--- successful completion of the check
   return(true);
  }
  
//+------------------------------------------------------------------+
//| RSI indicator value at the specified bar                         |
//+------------------------------------------------------------------+
double RSI(int index)
  {
   double indicator_values[];
   if(CopyBuffer(ExtIndicatorHandle, 0, index, 1, indicator_values) < 0)
     {
      //--- if the copying fails, report the error code
      PrintFormat("Failed to copy data from the RSI indicator, error code %d", GetLastError());
      return(EMPTY_VALUE);
     }
   return(indicator_values[0]);
  }

//+------------------------------------------------------------------+
//| Helper Functions                                                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Validate Stop Loss                                              |
//+------------------------------------------------------------------+
bool IsValidStop(double entry, double stoploss)
  {
   if(stoploss <= 0) return(false);
   
   double min_stop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(min_stop > 0)
     {
      if(MathAbs(entry - stoploss) < min_stop)
        {
         Print("Stop loss too close to entry price");
         return(false);
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk                                |
//+------------------------------------------------------------------+
double CalculateLot(double entry, double stoploss)
  {
   double risk_percent = 1.0; // 1% risk
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * risk_percent / 100;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double stop_points = MathAbs(entry - stoploss) / point;
   double lot = risk_amount / (stop_points * tick_value);
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathFloor(lot / lot_step) * lot_step;
   
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   
   return(lot);
  }

//+------------------------------------------------------------------+
//| Send Order                                                      |
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp)
  {
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.type     = type;
   req.volume   = lot;
   req.price    = price;
   req.sl       = sl;
   req.tp       = tp;
   req.magic    = InpMagicNumber;
   req.deviation = (int)InpSlippage;

   string comment = Trade_Comment + "|SL=" + DoubleToString(sl, _Digits);

   if(!OrderSend(req, res))
     {
      Print("OrderSend failed: ", GetLastError());
      Print("Retcode: ", res.retcode);
     }
  }

//+------------------------------------------------------------------+
//| Close Position                                                  |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
     {
      Print("Failed to select position: ", GetLastError());
      return;
     }
     
   long type = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.volume   = volume;
   req.magic    = InpMagicNumber;
   req.deviation = (int)InpSlippage;

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

   if(!OrderSend(req, res))
     {
      Print("ClosePosition failed: ", GetLastError());
      Print("Retcode: ", res.retcode);
     }
  }
//+------------------------------------------------------------------+